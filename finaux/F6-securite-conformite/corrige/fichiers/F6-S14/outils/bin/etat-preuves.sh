#!/usr/bin/env bash
# etat-preuves.sh — état des preuves de conformité (F6-S14).
#
# plateforme/outils — bin/etat-preuves.sh. Génère docs/conformite/etat-preuves.md et échoue (sortie 1)
# si une preuve manque, a vieilli, n'est pas inaltérable, ou si sa date est postérieure à la clôture de
# l'écart. LECTURE SEULE (registre des écarts local + compartiment preuves-conformite en lecture).
#
# Pour chaque écart clos du registre (docs/conformite/ecarts/ECA-*.md), il lit le champ « preuve » et le
# champ « clos-le », liste le préfixe correspondant dans preuves-conformite, et vérifie :
#   - la preuve existe (préfixe non vide) ;
#   - l'objet le plus récent n'a pas vieilli au-delà de WB_F6_AGE_MAX_JOURS ;
#   - la date de la preuve est <= clos-le + WB_F6_TOLERANCE_JOURS (pas fabriquée après coup) ;
#   - le compartiment a le verrouillage d'objets (inaltérabilité).
#
# Variables (défauts) :
#   WB_F6_ECARTS_DIR     docs/conformite/ecarts
#   WB_F6_SORTIE         docs/conformite/etat-preuves.md
#   WB_F6_RGW_URL        https://rgw.par1.medisphere.internal
#   WB_F6_PREUVES_BUCKET preuves-conformite
#   WB_F6_PREUVES_ENV    ~/.config/workbook/s3-preuves-conformite-lecture.env
#   WB_F6_AGE_MAX_JOURS  35     (une preuve mensuelle qui a plus d'un mois a vieilli)
#   WB_F6_TOLERANCE_JOURS 2
set -euo pipefail

ECARTS="${WB_F6_ECARTS_DIR:-docs/conformite/ecarts}"
SORTIE="${WB_F6_SORTIE:-docs/conformite/etat-preuves.md}"
RGW="${WB_F6_RGW_URL:-https://rgw.par1.medisphere.internal}"
BUCKET="${WB_F6_PREUVES_BUCKET:-preuves-conformite}"
ENV_FILE="${WB_F6_PREUVES_ENV:-$HOME/.config/workbook/s3-preuves-conformite-lecture.env}"
AGE_MAX="${WB_F6_AGE_MAX_JOURS:-35}"
TOLERANCE="${WB_F6_TOLERANCE_JOURS:-2}"

for c in aws jq date; do
  command -v "$c" >/dev/null 2>&1 || { echo "outil manquant : $c" >&2; exit 2; }
done
[[ -d "$ECARTS" ]] || { echo "registre des écarts introuvable : $ECARTS" >&2; exit 2; }
[[ -r "$ENV_FILE" ]] || { echo "identité de lecture des preuves illisible : $ENV_FILE" >&2; exit 2; }

s3() {
  (
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
    aws --endpoint-url "$RGW" "$@"
  )
}

# Champ d'en-tête YAML simple : « cle: valeur ».
champ() { sed -n "s/^$2:[[:space:]]*//p" "$1" | head -n1; }

aujourdhui="$(date -u +%s)"
# Verrouillage d'objets du compartiment (inaltérabilité commune).
verrou="non"
if s3 s3api get-object-lock-configuration --bucket "$BUCKET" 2>/dev/null \
   | jq -e '.ObjectLockConfiguration.ObjectLockEnabled == "Enabled"' >/dev/null 2>&1; then
  verrou="oui"
fi

echec=0
{
  echo "# État des preuves de conformité"
  echo
  echo "> Généré par \`etat-preuves.sh\` le $(date -u +%FT%TZ). Compartiment \`$BUCKET\`, verrouillage : **$verrou**."
  echo
  echo "| Écart | Statut | Preuve (préfixe) | Objets | Dernière preuve | Antérieure à la clôture | Verrou | État |"
  echo "|---|---|---|---|---|---|---|---|"
} >"$SORTIE.tmp"

for f in "$ECARTS"/ECA-*.md; do
  [[ -e "$f" ]] || continue
  id="$(champ "$f" id)"
  statut="$(champ "$f" statut)"
  preuve="$(champ "$f" preuve)"
  clos="$(champ "$f" clos-le)"
  [[ "$statut" == "clos" ]] || continue
  # Préfixe dans le compartiment (après « preuves-conformite/ »).
  prefixe="${preuve#*"$BUCKET"/}"
  prefixe="${prefixe%/}/"
  liste="$(s3 s3 ls --recursive "s3://$BUCKET/$prefixe" 2>/dev/null || true)"
  nb="$(grep -c . <<<"$liste" 2>/dev/null || echo 0)"
  etat="OK"
  if (( nb == 0 )); then
    etat="KO : aucune preuve"; echec=1; derniere="—"; anterieure="—"
  else
    # Date du dernier objet (colonne 1 de « aws s3 ls », AAAA-MM-JJ).
    derniere="$(awk '{print $1}' <<<"$liste" | sort | tail -n1)"
    dep="$(date -u -d "$derniere" +%s 2>/dev/null || echo 0)"
    if (( dep > 0 && (aujourdhui - dep) > AGE_MAX * 86400 )); then
      etat="KO : preuve vieillie"; echec=1
    fi
    # Antériorité : la preuve ne doit pas être postérieure à la clôture + tolérance.
    anterieure="oui"
    if [[ -n "$clos" ]]; then
      clos_s="$(date -u -d "$clos" +%s 2>/dev/null || echo 0)"
      if (( dep > 0 && clos_s > 0 && dep > clos_s + TOLERANCE * 86400 )); then
        anterieure="NON (fabriquée après coup ?)"; etat="KO : preuve postérieure à la clôture"; echec=1
      fi
    fi
  fi
  [[ "$verrou" == "oui" ]] || { etat="KO : compartiment non verrouillé"; echec=1; }
  printf '| %s | %s | %s | %s | %s | %s | %s | %s |\n' \
    "$id" "$statut" "$prefixe" "$nb" "${derniere:-—}" "${anterieure:-—}" "$verrou" "$etat" >>"$SORTIE.tmp"
done

mv "$SORTIE.tmp" "$SORTIE"
echo "État écrit dans $SORTIE"
if (( echec )); then
  echo "== Des preuves manquent, ont vieilli ou ne sont pas recevables (voir $SORTIE) =="
  exit 1
fi
echo "== Toutes les preuves des écarts clos sont présentes, inaltérables et recevables =="
