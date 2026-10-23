#!/usr/bin/env bash
# =============================================================================
# /usr/local/sbin/conformite-analyse — rôle durcissement (M26-E24, SEC-2724).
# Analyse de conformité HEBDOMADAIRE de l'hôte, en LECTURE SEULE :
#   1. pour chaque référentiel de CONFORMITE_REFERENTIELS : oscap xccdf eval du profil adapté d'E10
#      (<id>_medisphere de tailoring-<nom>.xml : exceptions désélectionnées), ARF + HTML compressés ;
#   2. Lynis (indice de durcissement) ;
#   3. envoi des résultats vers s3-01, compartiment « conformite », clé AAAA-MM-JJ/<hôte>/… ;
#   4. métriques pour le collecteur textfile de node_exporter (écriture atomique).
# Jamais de remédiation (aucune option --remediate) : ce script ne modifie que ses propres sorties.
# Code de sortie : 0 si toutes les analyses ont tourné et ont été envoyées (même si des règles
# échouent : c'est le résultat normal d'une mesure), 1 sinon (le service passe en échec, journald).
# Paramètres : /etc/medisphere/conformite/conformite.env ; identifiants S3 : …/s3.env (600).
# =============================================================================
set -Eeuo pipefail
umask 077

PARAMS=/etc/medisphere/conformite/conformite.env
SECRETS=/etc/medisphere/conformite/s3.env
[[ -r "$PARAMS" ]] || { echo "paramètres illisibles : $PARAMS" >&2; exit 1; }
[[ -r "$SECRETS" ]] || { echo "identifiants S3 illisibles : $SECRETS" >&2; exit 1; }
# shellcheck source=/dev/null
. "$PARAMS"
: "${CONFORMITE_DATASTREAM:?}" "${CONFORMITE_REFERENTIELS:?}" "${CONFORMITE_S3_URL:?}"
: "${CONFORMITE_COMPARTIMENT:?}" "${CONFORMITE_TEXTFILE:?}"
CONFORMITE_LYNIS="${CONFORMITE_LYNIS:-oui}"

S3_CLE_ACCES="" S3_CLE_SECRETE=""
# shellcheck source=/dev/null
. "$SECRETS"
[[ -n "$S3_CLE_ACCES" && -n "$S3_CLE_SECRETE" ]] || { echo "identifiants S3 incomplets" >&2; exit 1; }

for outil in oscap xmllint gzip curl; do
  command -v "$outil" >/dev/null || { echo "outil manquant : $outil" >&2; exit 1; }
done
[[ -r "$CONFORMITE_DATASTREAM" ]] || { echo "datastream introuvable : $CONFORMITE_DATASTREAM" >&2; exit 1; }

hote="$(hostname -s)"
jour="$(date -u +%F)"
# Dossier de travail hors de /tmp (monté noexec, et parfois privé) ; supprimé à la sortie.
travail="$(mktemp -d /var/tmp/conformite.XXXXXX)"
trap 'rm -rf "$travail"' EXIT
metriques="$travail/conformite.prom"
echec=0

# envoyer FICHIER CLE — PUT signé SigV4 vers s3-01. Les identifiants passent par un fichier de
# configuration de curl (descripteur hérité), jamais par la ligne de commande (visible par ps).
envoyer() {
  curl -sS --fail --retry 3 --retry-delay 5 --max-time 300 \
    -K <(printf 'user = "%s:%s"\naws-sigv4 = "aws:amz:us-east-1:s3"\n' "$S3_CLE_ACCES" "$S3_CLE_SECRETE") \
    --upload-file "$1" "$CONFORMITE_S3_URL/$CONFORMITE_COMPARTIMENT/$2" >/dev/null
}

# compter FICHIER_ARF RESULTAT — nombre de règles dans cet état (local-name() : sans dépendre des
# préfixes d'espaces de noms XML de l'ARF).
compter() {
  xmllint --xpath "count(//*[local-name()='rule-result'][*[local-name()='result']='$2'])" "$1" 2>/dev/null || echo 0
}

{
  echo "# HELP medisphere_conformite_score Score XCCDF (0-100) de la dernière analyse, exceptions appliquées."
  echo "# TYPE medisphere_conformite_score gauge"
} >"$metriques"
lignes_regles=""
lignes_date=""

for triplet in $CONFORMITE_REFERENTIELS; do
  ref="${triplet%%:*}"
  reste="${triplet#*:}"
  profil="${reste%%:*}"
  tailoring="${reste#*:}"
  arf="$travail/$ref-arf.xml"
  html="$travail/$ref-rapport.html"
  # Le profil <id>_medisphere n'existe que dans le tailoring : sans lui, pas de mesure honnête.
  if [[ ! -r "$tailoring" ]]; then
    echo "[$ref] profil adapté illisible : $tailoring" >&2
    echec=1
    continue
  fi
  args=(xccdf eval --tailoring-file "$tailoring" --profile "$profil" --results-arf "$arf" --report "$html")
  debut="$(date +%s)"
  rc=0
  oscap "${args[@]}" "$CONFORMITE_DATASTREAM" >"$travail/$ref.log" 2>&1 || rc=$?
  # 0 : tout passe ; 2 : au moins une règle échoue (résultat normal) ; autre : l'analyse a échoué.
  if (( rc != 0 && rc != 2 )) || [[ ! -s "$arf" ]]; then
    echo "[$ref] échec de l'analyse (code $rc) :" >&2
    tail -n 20 "$travail/$ref.log" >&2 || true
    echec=1
    continue
  fi
  score="$(xmllint --xpath "string((//*[local-name()='TestResult']/*[local-name()='score'])[1])" "$arf" 2>/dev/null || true)"
  [[ "$score" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "[$ref] score illisible dans l'ARF" >&2; echec=1; continue; }

  # Comptes par résultat, lus sur l'ARF avant compression.
  for r in pass fail notapplicable notselected error unknown notchecked; do
    lignes_regles+="$(printf 'medisphere_conformite_regles{referentiel="%s",resultat="%s"} %s' "$ref" "$r" "$(compter "$arf" "$r")")"$'\n'
  done

  gzip -9 "$arf" "$html"
  if ! envoyer "$arf.gz" "$jour/$hote/$ref-arf.xml.gz" || ! envoyer "$html.gz" "$jour/$hote/$ref-rapport.html.gz"; then
    # La mesure a eu lieu, mais elle n'est pas conservée hors de l'hôte : échec du service,
    # métriques publiées quand même (l'alerte d'échec de l'unité dira pourquoi).
    echo "[$ref] envoi vers $CONFORMITE_S3_URL impossible" >&2
    echec=1
  fi

  printf 'medisphere_conformite_score{referentiel="%s"} %s\n' "$ref" "$score" >>"$metriques"
  fin="$(date +%s)"
  lignes_date+="$(printf 'medisphere_conformite_derniere_analyse_secondes{referentiel="%s"} %s' "$ref" "$fin")"$'\n'
  lignes_date+="$(printf 'medisphere_conformite_duree_secondes{referentiel="%s"} %s' "$ref" "$(( fin - debut ))")"$'\n'
  echo "[$ref] score $score, durée $(( fin - debut )) s"
done

# Lynis : indice de durcissement (0-100), complément lisible des analyses OpenSCAP.
if [[ "$CONFORMITE_LYNIS" == oui ]] && command -v lynis >/dev/null; then
  if lynis audit system --cronjob --quiet >"$travail/lynis.log" 2>&1; then
    indice="$(sed -n 's/^hardening_index=//p' /var/log/lynis-report.dat | tail -n 1)"
    if [[ "$indice" =~ ^[0-9]+$ ]]; then
      {
        echo "# HELP medisphere_lynis_indice Indice de durcissement de Lynis (0-100)."
        echo "# TYPE medisphere_lynis_indice gauge"
        echo "medisphere_lynis_indice $indice"
      } >>"$travail/lynis.prom"
      gzip -9c /var/log/lynis-report.dat >"$travail/lynis-report.dat.gz"
      envoyer "$travail/lynis-report.dat.gz" "$jour/$hote/lynis-report.dat.gz" || { echo "[lynis] envoi impossible" >&2; echec=1; }
    else
      echo "[lynis] indice illisible" >&2; echec=1
    fi
  else
    echo "[lynis] échec de l'audit" >&2; echec=1
  fi
fi

# Assemblage, puis écriture ATOMIQUE (fichier temporaire du même dossier, puis renommage) :
# node_exporter ne lit jamais un fichier à moitié écrit.
{
  cat "$metriques"
  echo "# HELP medisphere_conformite_regles Nombre de règles par résultat (pass, fail…)."
  echo "# TYPE medisphere_conformite_regles gauge"
  printf '%s' "$lignes_regles"
  echo "# HELP medisphere_conformite_derniere_analyse_secondes Horodatage de la dernière analyse réussie."
  echo "# TYPE medisphere_conformite_derniere_analyse_secondes gauge"
  printf '%s' "$lignes_date" | grep '^medisphere_conformite_derniere' || true
  echo "# HELP medisphere_conformite_duree_secondes Durée de la dernière analyse."
  echo "# TYPE medisphere_conformite_duree_secondes gauge"
  printf '%s' "$lignes_date" | grep '^medisphere_conformite_duree' || true
  cat "$travail/lynis.prom" 2>/dev/null || true
} >"$travail/final.prom"
tmp="$(mktemp "$CONFORMITE_TEXTFILE/.conformite.prom.XXXXXX")"
cat "$travail/final.prom" >"$tmp"
chmod 0644 "$tmp"
mv -f "$tmp" "$CONFORMITE_TEXTFILE/conformite.prom"

exit "$echec"
