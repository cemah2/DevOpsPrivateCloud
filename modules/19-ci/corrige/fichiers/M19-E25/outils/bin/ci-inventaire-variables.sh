#!/usr/bin/env bash
# plateforme/outils — bin/ci-inventaire-variables.sh (M19-E25, SEC-2025).
# Inventaire des variables de CI/CD de l'instance, des groupes du périmètre et de leurs projets.
# Une ligne TSV par variable : niveau, propriétaire, clé, type, protégée, masquée, cachée, raw,
# portée d'environnement, et un classement « secret probable » d'après la clé.
# La VALEUR n'est jamais affichée ni écrite : elle est retirée par jq dans le même tuyau que la
# réponse de l'API (aucun fichier intermédiaire).
#
# Usage : ci-inventaire-variables.sh [GROUPE…]     (défaut : le périmètre de SEC-2025)
# Jeton : lecture seule, d'un administrateur (les variables d'instance et de tous les projets ne
# sont lisibles qu'ainsi) : GITLAB_TOKEN_FILE (défaut ~/.config/workbook/gitlab-checks.token,
# portées read_api + admin_mode). En CI : variable de type fichier, protégée, masquée.
# Sortie : TSV sur la sortie standard ; résumé et anomalies sur la sortie d'erreur ; code 1 si une
# variable à clé de secret n'est pas protégée ou pas masquée.
set -euo pipefail

GITLAB_URL="${GITLAB_URL:-${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}}"
JETON="${GITLAB_TOKEN_FILE:-$HOME/.config/workbook/gitlab-checks.token}"
GROUPES=("$@")
(( ${#GROUPES[@]} )) || GROUPES=(plateforme mediagenda medidoc medinotif legacy formation)
MOTIF_SECRET='(TOKEN|PASSWORD|PASSWD|SECRET|KEY|CLE|JETON|CREDENTIAL|AUTH)'

[[ -r "$JETON" ]] || { echo "jeton illisible : $JETON" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq manquant" >&2; exit 2; }

# get CHEMIN — toutes les pages d'un GET de l'API (en-tête x-next-page), concaténées en un tableau.
get() {
  local chemin="$1" page=1 sep corps entetes
  entetes="$(mktemp)"
  trap 'rm -f "$entetes"' RETURN
  while [[ -n "$page" ]]; do
    [[ "$chemin" == *\?* ]] && sep='&' || sep='?'
    corps="$(curl -sSf --max-time 30 -D "$entetes" \
      -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(<"$JETON")") \
      "$GITLAB_URL/api/v4/${chemin}${sep}per_page=100&page=$page")" || return 1
    # Retrait des valeurs AVANT toute autre chose.
    jq -c 'if type == "array" then map(del(.value)) else del(.value) end' <<<"$corps"
    page="$(awk -F': ' 'tolower($1) == "x-next-page" {gsub(/\r/, "", $2); print $2}' "$entetes")"
  done | jq -s 'add // []'
}

# lignes NIVEAU PROPRIÉTAIRE — lit un tableau de variables (sans valeurs) sur l'entrée standard.
lignes() {
  jq -r --arg niv "$1" --arg prop "$2" --arg motif "$MOTIF_SECRET" '
    .[] | [ $niv, $prop, .key, .variable_type,
            (.protected | tostring), (.masked | tostring), ((.hidden // false) | tostring),
            ((.raw // false) | tostring), (.environment_scope // "*"),
            (if (.key | ascii_upcase | test($motif)) then "secret" else "-" end) ] | @tsv'
}

inventaire="$(
  get "admin/ci/variables" | lignes instance "-"
  for g in "${GROUPES[@]}"; do
    get "groups/${g//\//%2F}/variables" | lignes groupe "$g"
    while IFS=$'\t' read -r id chemin; do
      get "projects/$id/variables" | lignes projet "$chemin"
    done < <(get "groups/${g//\//%2F}/projects?include_subgroups=true&archived=false&simple=true" \
               | jq -r '.[] | [.id, .path_with_namespace] | @tsv')
  done
)"

printf 'niveau\tproprietaire\tcle\ttype\tprotegee\tmasquee\tcachee\traw\tportee\tclasse\n'
printf '%s\n' "$inventaire"
awk -F'\t' '
  NF == 0 { next }
  $10 == "secret" && ($5 != "true" || $6 != "true") { print "ANOMALIE : " $1 " " $2 " " $3 " (protégée=" $5 ", masquée=" $6 ")" > "/dev/stderr"; ko = 1 }
  { n++ }
  END { print n " variables inventoriées" > "/dev/stderr"; exit ko }' <<<"$inventaire"
