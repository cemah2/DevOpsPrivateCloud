#!/usr/bin/env bash
# recap-ansible.sh — résume le « PLAY RECAP » d'un journal d'ansible-playbook (M04-E27, E29)
#
# Usage : outils/recap-ansible.sh JOURNAL [--json FICHIER]
# Affiche une ligne de totaux et la liste des hôtes qui ont changé ou échoué ; avec --json,
# écrit aussi le résumé dans FICHIER (pour un rapport ou une alerte).
# Codes retour (stables, utilisés par la CI et par outils/derive.sh) :
#   0  aucun changement, aucun échec
#   1  au moins un changement (changed > 0), aucun échec
#   2  au moins un hôte en échec ou injoignable
#   3  pas de PLAY RECAP dans le journal (exécution interrompue avant la fin)
#   4  erreur d'usage
set -euo pipefail

usage() { echo "Usage : $0 JOURNAL [--json FICHIER]" >&2; exit 4; }
(($# == 1 || $# == 3)) || usage
journal="$1"
json=""
if (($# == 3)); then
  [[ "$2" == "--json" ]] || usage
  json="$3"
fi
[[ -r "$journal" ]] || { echo "Journal illisible : $journal" >&2; exit 4; }

# Lignes du récapitulatif, codes couleur retirés :
#   gw01   : ok=12   changed=0    unreachable=0    failed=0    skipped=3    rescued=0    ignored=0
recap="$(sed -e 's/\x1b\[[0-9;]*m//g' "$journal" \
  | awk '/^PLAY RECAP/ { dans = 1; next } dans && /^[^ ]+ +: ok=/ { print }')"
if [[ -z "$recap" ]]; then
  echo "Aucun PLAY RECAP : exécution interrompue ou journal incomplet." >&2
  exit 3
fi

resume="$(awk '
  {
    hote = $1
    for (i = 3; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] + 0 }
    n++; ok += v["ok"]; ch += v["changed"]; un += v["unreachable"]; fa += v["failed"]
    if (v["changed"] > 0) lch = lch (lch ? "," : "") hote
    if (v["failed"] > 0 || v["unreachable"] > 0) lfa = lfa (lfa ? "," : "") hote
  }
  END {
    printf "hotes=%d ok=%d changed=%d unreachable=%d failed=%d hotes_changes=%s hotes_en_echec=%s\n",
      n, ok, ch, un, fa, (lch ? lch : "-"), (lfa ? lfa : "-")
  }' <<<"$recap")"
echo "$resume"

# Valeurs pour le code retour et le JSON
declare -A r=()
for paire in $resume; do r["${paire%%=*}"]="${paire#*=}"; done

if [[ -n "$json" ]]; then
  jq -n \
    --argjson hotes "${r[hotes]}" --argjson ok "${r[ok]}" --argjson changed "${r[changed]}" \
    --argjson unreachable "${r[unreachable]}" --argjson failed "${r[failed]}" \
    --arg hotes_changes "${r[hotes_changes]}" --arg hotes_en_echec "${r[hotes_en_echec]}" \
    '{hotes: $hotes, ok: $ok, changed: $changed, unreachable: $unreachable, failed: $failed,
      hotes_changes: ($hotes_changes | if . == "-" then [] else split(",") end),
      hotes_en_echec: ($hotes_en_echec | if . == "-" then [] else split(",") end)}' >"$json"
fi

if ((r[failed] > 0 || r[unreachable] > 0)); then exit 2; fi
if ((r[changed] > 0)); then exit 1; fi
exit 0
