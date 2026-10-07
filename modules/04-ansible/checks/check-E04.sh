# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E04.sh — M04-E04 : Commandes ad hoc, modules et facts
# À lancer depuis adm01. Lecture seule : fichiers produits dans ~/m04/e04/, et une collecte
# de faits restreinte (module setup, sans élévation) pour comparer avec ton relevé.

# shellcheck source=_m04-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m04-decouverte.sh"

title "M04-E04 — Commandes ad hoc, modules et facts"
require_cmd jq

_m04_e04="$HOME/m04/e04"
check_cmd "journal ~/m04/e04/notes.md présent et rempli" test -s "$_m04_e04/notes.md"

# --- Faits enregistrés par --tree ------------------------------------------------------------
for _m04_h in $_M04_SOCLE; do
  check_output "faits de $_m04_h enregistrés dans ~/m04/e04/facts/ (Debian 13)" '^Debian 13$' \
    jq -r '.ansible_facts | "\(.ansible_distribution) \(.ansible_distribution_major_version)"' \
    "$_m04_e04/facts/$_m04_h"
done
check_output "les faits enregistrés contiennent le matériel (mémoire, montages)" '^true$' \
  jq -r '.ansible_facts | has("ansible_memtotal_mb") and has("ansible_mounts")' "$_m04_e04/facts/dns01"

# --- Relevé de capacité ------------------------------------------------------------------------
_m04_csv="$_m04_e04/capacite.csv"
check_cmd "relevé ~/m04/e04/capacite.csv présent" test -s "$_m04_csv"
for _m04_h in $_M04_SOCLE; do
  check_output "capacite.csv : une ligne pour $_m04_h" "^\"?$_m04_h\"?," cat "$_m04_csv"
done
# La mémoire relevée pour dns01 doit être celle que rapportent les faits aujourd'hui (±5 %).
_m04_mem_reelle="$(_m04_resultat "$(_m04_json ansible dns01 -m ansible.builtin.setup -a 'filter=ansible_memtotal_mb')" \
  dns01 '.ansible_facts.ansible_memtotal_mb // empty')"
# _m04_mem_coherente — une valeur numérique de la ligne dns01 est à ±5 % de la mémoire réelle
_m04_mem_coherente() {
  [[ -n "$_m04_mem_reelle" ]] || return 1
  grep -E '^"?dns01"?,' "$_m04_csv" | tr -d '"' | tr ',' '\n' | grep -E '^[0-9]+$' \
    | awk -v r="$_m04_mem_reelle" '{ if ($1 >= r * 0.95 && $1 <= r * 1.05) ok = 1 } END { exit !ok }'
}
check_cmd "capacite.csv : la mémoire de dns01 correspond aux faits actuels" _m04_mem_coherente
