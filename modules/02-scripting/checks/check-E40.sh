# shellcheck shell=bash
# shellcheck disable=SC2016  # la commande entre apostrophes est évaluée sur pve01
# check-E40.sh — M02-E40 « Panne : l'inventaire met dix minutes » : état sain.
# Si la panne n'a jamais été injectée (zone /opt/workbook/m02/e40 absente), rien à contrôler.
# Sinon : l'inventaire se termine en moins de 30 s et liste toutes les VMs du pool lab
# (référence : /cluster/resources lu sur pve01). Le script est lancé avec « -o - » : il
# n'écrit rien dans la zone. Lecture seule côté Proxmox.

title "M02-E40 — Inventaire du lab en moins de 30 secondes"
require_cmd jq ssh

_m02_e40_zone=/opt/workbook/m02/e40
_m02_e40_sortie=""
_m02_e40_duree=""

# Une seule exécution, mesurée ; la sortie sert aux contrôles suivants.
_m02_e40_lancer() {
  local debut rc=0
  debut="$(date +%s)"
  _m02_e40_sortie="$(cd "$_m02_e40_zone" && timeout 30 bin/ms-inventaire-lab -o - 2>/dev/null)" || rc=$?
  _m02_e40_duree=$(($(date +%s) - debut))
  ((rc == 0))
}

_m02_e40_toutes_les_vms() {
  local ids id
  ids="$(remote "$WB_PVE_HOST" 'pvesh get /cluster/resources --type vm --output-format json' \
    | jq -r '.[] | select(.pool == "lab") | .vmid')" || return 1
  [[ -n "$ids" && -n "$_m02_e40_sortie" ]] || return 1
  for id in $ids; do
    grep -Eq "^\|[[:space:]]*${id}[[:space:]]*\|" <<<"$_m02_e40_sortie" || return 1
  done
}

if [[ ! -d "$_m02_e40_zone" ]]; then
  skip "zone de test $_m02_e40_zone" "panne jamais injectée : rien à contrôler"
else
  check_cmd "script d'inventaire présent et exécutable" test -x "$_m02_e40_zone/bin/ms-inventaire-lab"
  if command -v shellcheck >/dev/null 2>&1; then
    check_cmd "script d'inventaire : ShellCheck sans remarque" shellcheck -x "$_m02_e40_zone/bin/ms-inventaire-lab"
  else
    skip "script d'inventaire : ShellCheck" "shellcheck absent de ce poste"
  fi
  check_cmd "l'inventaire se termine sans erreur en moins de 30 s" _m02_e40_lancer
  printf '         (durée mesurée : %s s)\n' "${_m02_e40_duree:-?}"
  check_cmd "l'inventaire liste toutes les VMs du pool lab (une ligne par VMID)" _m02_e40_toutes_les_vms
fi
