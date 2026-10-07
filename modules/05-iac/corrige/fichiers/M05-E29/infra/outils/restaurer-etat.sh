#!/usr/bin/env bash
# restaurer-etat.sh — restaurer un objet d'état OpenTofu dans tofu-state (M05-E29).
#
# Usage :
#   outils/restaurer-etat.sh --lister CLÉ
#   outils/restaurer-etat.sh --version CLÉ VERSION_ID [--oui]
#   outils/restaurer-etat.sh --fichier CLÉ FICHIER   [--oui]
#
#   --lister   versions et marqueurs de suppression de CLÉ (le plus récent d'abord)
#   --version  remet en place une version précédente de CLÉ (copie côté serveur : une NOUVELLE
#              version est créée, l'historique n'est jamais réécrit)
#   --fichier  remet en place une copie externe (sauvegarder-etats.sh, artefact de CI)
#
# Garde-fous (refus = code 3) :
#   - aucun verrou CLÉ.tflock ne doit exister (une opération est peut-être en cours) ;
#   - si CLÉ existe, le lineage de ce qu'on restaure doit être le MÊME : un autre lineage est un
#     autre état (autre configuration, ou état recréé) ; on l'examine sous _restauration/ ;
#   - la version courante est d'abord copiée dans ~/.local/state/infra-restaurations/<date>/
#     avec son VersionId : c'est le retour arrière de la restauration elle-même ;
#   - confirmation demandée (sauf --oui).
# Après une restauration : « tofu plan » dans la configuration concernée (attendu : vide, ou
# exactement l'écart qu'on attendait), jamais d'apply dans la foulée.
#
# Accès S3 : identité tofu-etat (s3-tofu.env, profil s3-socle) ; en CI : S3_ENDPOINT.
# Codes retour : 0 fait · 1 erreur · 2 utilisation · 3 refus d'un garde-fou.
set -euo pipefail

COMPARTIMENT="${COMPARTIMENT:-tofu-state}"
s3() {
  if [[ -n "${S3_ENDPOINT:-}" ]]; then
    aws --endpoint-url "$S3_ENDPOINT" --output json "$@"
  else
    aws --output json "$@"
  fi
}
die() { printf 'restaurer-etat : %s\n' "$2" >&2; exit "$1"; }

usage() { sed -n '4,7p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
for c in aws jq; do command -v "$c" >/dev/null || die 2 "outil manquant : $c"; done

mode="${1:-}"
cle="${2:-}"
[[ -n "$mode" && -n "$cle" ]] || usage
[[ "$cle" == *.tfstate ]] || die 2 "la clé doit désigner un état (*.tfstate) : $cle"
oui=0
for a in "$@"; do
  if [[ "$a" == "--oui" ]]; then oui=1; fi
done

# --- Lister -----------------------------------------------------------------------------------
if [[ "$mode" == "--lister" ]]; then
  s3 s3api list-object-versions --bucket "$COMPARTIMENT" --prefix "$cle" | jq -r --arg k "$cle" '
    ([(.Versions // [])[] | select(.Key == $k) | {d: .LastModified, t: "version ", id: .VersionId, c: .IsLatest, s: .Size}]
     + [(.DeleteMarkers // [])[] | select(.Key == $k) | {d: .LastModified, t: "SUPPRIMÉ", id: .VersionId, c: .IsLatest, s: 0}])
    | sort_by(.d) | reverse | .[]
    | "\(.d)  \(.t)  \(.id)  \(if .c then "(courante)" else "" end) \(.s) o"'
  exit 0
fi

# --- Préparer la restauration ---------------------------------------------------------------------
umask 077
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

case "$mode" in
  --version)
    version="${3:?VERSION_ID manquant}"
    s3 s3api get-object --bucket "$COMPARTIMENT" --key "$cle" --version-id "$version" "$tmp/candidat" >/dev/null \
      || die 1 "version $version introuvable pour $cle"
    ;;
  --fichier)
    source_fichier="${3:?FICHIER manquant}"
    [[ -r "$source_fichier" ]] || die 1 "fichier illisible : $source_fichier"
    cp "$source_fichier" "$tmp/candidat"
    ;;
  *) usage ;;
esac

jq -e 'has("lineage") and has("serial")' "$tmp/candidat" >/dev/null 2>&1 \
  || die 3 "ce que tu veux restaurer n'est pas un état OpenTofu (lineage/serial absents)"
lineage_candidat="$(jq -r .lineage "$tmp/candidat")"
serial_candidat="$(jq -r .serial "$tmp/candidat")"
if ! jq -e 'has("encrypted_data")' "$tmp/candidat" >/dev/null; then
  echo "⚠️  Cet état est EN CLAIR : après E27, la configuration le refusera (enforced) ou le réécrira chiffré." >&2
fi

# Verrou : une opération en cours sur cet état ?
if s3 s3api head-object --bucket "$COMPARTIMENT" --key "$cle.tflock" >/dev/null 2>&1; then
  die 3 "un verrou $cle.tflock existe : une opération est peut-être en cours (RB-050). Rien n'est fait."
fi

# État courant : copie de sûreté, comparaison du lineage.
journal="${XDG_STATE_HOME:-$HOME/.local/state}/infra-restaurations/$(date +%Y%m%d-%H%M%S)"
version_courante="(aucune)"
if reponse="$(s3 s3api get-object --bucket "$COMPARTIMENT" --key "$cle" "$tmp/courant" 2>/dev/null)"; then
  version_courante="$(jq -r '.VersionId // "null"' <<<"$reponse")"
  lineage_courant="$(jq -r '.lineage // empty' "$tmp/courant" 2>/dev/null || true)"
  if [[ -n "$lineage_courant" && "$lineage_courant" != "$lineage_candidat" ]]; then
    die 3 "lineage différent (courant $lineage_courant, candidat $lineage_candidat) : ce n'est pas le même état. Restaure-le sous _restauration/ pour l'examiner."
  fi
  mkdir -p "$journal"
  cp "$tmp/courant" "$journal/$(basename "$cle").avant"
fi

echo "État       : s3://$COMPARTIMENT/$cle"
echo "Courant    : version $version_courante, serial $(jq -r '.serial // "-"' "$tmp/courant" 2>/dev/null || echo -)"
echo "Restauré   : serial $serial_candidat, lineage $lineage_candidat ($mode)"
if [[ $oui -eq 0 ]]; then
  read -r -p "Confirmer la restauration (oui/non) ? " reponse_humaine
  [[ "$reponse_humaine" == "oui" ]] || die 3 "abandon, rien n'est fait"
fi

# --- Restaurer ---------------------------------------------------------------------------------
if [[ "$mode" == "--version" ]]; then
  nouvelle="$(s3 s3api copy-object --bucket "$COMPARTIMENT" --key "$cle" \
    --copy-source "$COMPARTIMENT/$cle?versionId=$version" | jq -r '.VersionId // "?"')"
else
  nouvelle="$(s3 s3api put-object --bucket "$COMPARTIMENT" --key "$cle" --body "$tmp/candidat" \
    | jq -r '.VersionId // "?"')"
fi

if [[ -d "$journal" ]]; then
  printf '%s %s remplacée par %s (%s %s), nouvelle version %s\n' "$(date -Iseconds)" "$version_courante" \
    "$mode" "${version:-${source_fichier:-}}" "$cle" "$nouvelle" >> "$journal/journal.txt"
  echo "Copie de l'ancienne version et journal : $journal"
fi
echo "Restauré : nouvelle version $nouvelle. Lance maintenant « tofu plan » dans la configuration concernée."
