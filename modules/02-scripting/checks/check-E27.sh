# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur pve01
#
# check-E27.sh — M02-E27 : Idempotence et --dry-run
# À lancer depuis adm01. Lecture seule : état final de la VM de démonstration 2027 sur pve01
# (instantanés, verrou) et rapport de tests du dernier pipeline réussi de main (API GitLab).
# Le check ne lance jamais ms-snapshot, même en --dry-run.

title "M02-E27 — Idempotence et --dry-run"
require_cmd jq curl ssh

_m02_p="projects/plateforme%2Foutils"
_m02_val() { jq -r "$2" <<<"$1" 2>/dev/null || true; }

# --- VM de démonstration 2027 (m02-idem) ----------------------------------------------
_m02_snaps="$(remote "$WB_PVE_HOST" 'pvesh get /nodes/$(hostname)/qemu/2027/snapshot --output-format json' 2>/dev/null)" \
  || _m02_snaps=""
if [[ -n "$_m02_snaps" ]]; then
  check_output "VM 2027 : exactement 2 instantanés au format avant-AAAAMMJJ-HHMMSS (--keep 2)" '^2$' \
    _m02_val "$_m02_snaps" '[.[].name | select(test("^avant-[0-9]{8}-[0-9]{6}$"))] | length'
  check_output "VM 2027 : l'instantané manuel « avant-manuel » a survécu aux rotations" '^true$' \
    _m02_val "$_m02_snaps" 'any(.[]; .name == "avant-manuel")'
  check_output "VM 2027 : l'instantané manuel « avant-maj-demo » a survécu aux rotations" '^true$' \
    _m02_val "$_m02_snaps" 'any(.[]; .name == "avant-maj-demo")'
  check_ssh "VM 2027 : aucun verrou (pas de tâche interrompue laissée en plan)" "$WB_PVE_HOST" \
    '! qm config 2027 | grep -q "^lock:"'
  _m02_res="$(remote "$WB_PVE_HOST" 'pvesh get /cluster/resources --type vm --output-format json' 2>/dev/null)" \
    || _m02_res="[]"
  check_output "VM 2027 : membre du pool lab, étiquette env-m02" '^true$' _m02_val "$_m02_res" \
    'any(.[]; .vmid == 2027 and .pool == "lab" and ((.tags // "") | split(";") | index("env-m02")))'
else
  skip "VM de démonstration 2027" "absente : démonstration non faite, ou VM déjà détruite après validation"
fi

# --- Tests automatisés dans la CI --------------------------------------------------------
_m02_pl="$(gitlab_api "$_m02_p/pipelines?ref=main&status=success&per_page=1" 2>/dev/null)" || _m02_pl="[]"
_m02_pid="$(_m02_val "$_m02_pl" '.[0].id // empty')"
_m02_tr=""
[[ -n "$_m02_pid" ]] && { _m02_tr="$(gitlab_api "$_m02_p/pipelines/$_m02_pid/test_report" 2>/dev/null)" || _m02_tr=""; }
check_output "CI (main) : au moins un test bats réussi sur --dry-run" '^true$' \
  _m02_val "$_m02_tr" '[.test_suites[] | select(.name == "bats") | .test_cases[]
    | select(.status == "success" and (.name | test("dry-run"; "i")))] | length >= 1'
check_output "CI (main) : au moins trois tests bats réussis sur l'idempotence" '^true$' \
  _m02_val "$_m02_tr" '[.test_suites[] | select(.name == "bats") | .test_cases[]
    | select(.status == "success" and (.name | test("idempot"; "i")))] | length >= 3'
check_output "CI (main) : aucun test en échec" '^0$' \
  _m02_val "$_m02_tr" '(.failed_count // 0) + (.error_count // 0)'
