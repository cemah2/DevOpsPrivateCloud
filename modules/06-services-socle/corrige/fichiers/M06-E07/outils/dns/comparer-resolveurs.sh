#!/usr/bin/env bash
# comparer-resolveurs.sh — même question, deux résolveurs : les réponses sont-elles identiques ?
# (M06-E07 : preuve avant la bascule dnsmasq -> PowerDNS Recursor, M06-E08.)
#
#   comparer-resolveurs.sh [-a SERVEUR[:PORT]] [-b SERVEUR[:PORT]] [FICHIER_QUESTIONS]
#     -a  résolveur de référence      (défaut 10.10.20.10:53, dnsmasq)
#     -b  résolveur candidat          (défaut 10.10.20.10:5301, PowerDNS Recursor en essai)
#     FICHIER_QUESTIONS  une question par ligne : « nom type » ou « -x adresse » ; # = commentaire
#                        (défaut : questions-socle.txt à côté du script)
#
# Compare le statut (NOERROR, NXDOMAIN…) et l'ensemble des données de la section réponse
# (ordre et TTL ignorés : ils varient légitimement). Code retour : 0 identiques, 1 écarts, 2 usage.
set -euo pipefail

ref="10.10.20.10:53"
cand="10.10.20.10:5301"
while getopts "a:b:" opt; do
  case "$opt" in
    a) ref="$OPTARG" ;;
    b) cand="$OPTARG" ;;
    *) echo "Usage : $0 [-a SERVEUR[:PORT]] [-b SERVEUR[:PORT]] [FICHIER]" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
questions="${1:-$(dirname "$0")/questions-socle.txt}"
[[ -r "$questions" ]] || { echo "comparer-resolveurs : $questions illisible" >&2; exit 2; }
command -v dig >/dev/null || { echo "comparer-resolveurs : dig introuvable (bind9-dnsutils)" >&2; exit 2; }

# interroger SERVEUR:PORT ARGS… -> « STATUT|donnée1 donnée2… » (données triées, sans TTL)
interroger() {
  local cible="$1"; shift
  local hote="${cible%:*}" port="${cible##*:}" sortie statut donnees
  sortie="$(dig +time=3 +tries=2 +noall +comments +answer -p "$port" "@$hote" "$@" 2>&1)" || true
  statut="$(sed -n 's/.*status: \([A-Z]*\).*/\1/p' <<<"$sortie" | head -n 1)"
  # Section réponse : nom, TTL, classe, type, données -> on garde nom, type, données.
  donnees="$(awk '!/^;/ && NF >= 5 { $2 = ""; $3 = ""; print }' <<<"$sortie" | tr -s ' ' | sort | paste -sd ' ' -)"
  printf '%s|%s\n' "${statut:-SANS-REPONSE}" "$donnees"
}

ecarts=0
total=0
while IFS= read -r ligne || [[ -n "$ligne" ]]; do
  ligne="${ligne%%#*}"
  [[ -n "${ligne// /}" ]] || continue
  total=$((total + 1))
  # shellcheck disable=SC2086  # la ligne est découpée volontairement en arguments de dig
  a="$(interroger "$ref" $ligne)"
  # shellcheck disable=SC2086
  b="$(interroger "$cand" $ligne)"
  if [[ "$a" == "$b" ]]; then
    printf '  =  %-45s %s\n' "$ligne" "${a%%|*}"
  else
    ecarts=$((ecarts + 1))
    printf '  ≠  %-45s\n       %s : %s\n       %s : %s\n' "$ligne" "$ref" "$a" "$cand" "$b"
  fi
done <"$questions"

echo
echo "$total question(s), $ecarts écart(s) entre $ref et $cand."
((ecarts == 0))
