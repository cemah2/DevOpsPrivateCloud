# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres
#
# check-E11.sh — M02-E11 : ms-snapshot, instantanés du lab avant intervention
# À lancer depuis adm01, AVANT de détruire la VM 2020 (M02-E16). Lecture seule :
# ms-snapshot n'est lancé qu'en simulation (--dry-run) ou sur des cas refusés ;
# l'état de pve01 est lu par pvesh et qm (lecture).

title "M02-E11 — ms-snapshot : instantanés du lab avant intervention"
require_cmd jq shellcheck git

_m02_r="${WB_SRC:-$HOME/src}/outils"
_m02_snap="$_m02_r/bin/ms-snapshot"

# _m02_code ATTENDU COMMANDE... — vrai si la commande sort avec le code ATTENDU
_m02_code() {
  local attendu="$1" rc=0
  shift
  "$@" </dev/null >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq "$attendu" ]]
}

# --- Le script ---------------------------------------------------------------------
check_cmd "bin/ms-snapshot présent et exécutable" test -x "$_m02_snap"
check_cmd "ms-snapshot passe ShellCheck" bash -c 'cd "$1" && shellcheck -x bin/ms-snapshot' _ "$_m02_r"
check_cmd "ms-snapshot charge lib/ms-commun.sh" grep -Eq '^[^#]*source .*lib/ms-commun\.sh' "$_m02_snap"
check_cmd "ms-snapshot est fusionné dans main (GitLab)" \
  gitlab_api "projects/plateforme%2Foutils/repository/files/bin%2Fms-snapshot?ref=main"

# --- Interface et garde-fous (aucune écriture possible : refus ou simulation) ---------
check_cmd "--help : code 0" _m02_code 0 "$_m02_snap" --help
check_cmd "option inconnue : code 2 (usage)" _m02_code 2 "$_m02_snap" --option-inconnue 2020
check_cmd "aucune cible : code 2 (usage)" _m02_code 2 "$_m02_snap"
check_cmd "--keep 0 refusé : code 2" _m02_code 2 "$_m02_snap" --dry-run --keep 0 2020
check_cmd "pool autre que lab : refus, code 3" _m02_code 3 "$_m02_snap" --dry-run --pool production
check_cmd "template 9000 : refus, code 3" _m02_code 3 "$_m02_snap" --dry-run 9000
check_cmd "VMID inexistant ou invisible (999999) : refus, code 3" _m02_code 3 "$_m02_snap" --dry-run 999999

# --- Traces dans le journal des tâches de pve01 (preuves durables) -----------------------
_m02_taches() { # _m02_taches TYPE — tâches TYPE sur la VM 2020 exécutées par le jeton, terminées OK
  remote "$WB_PVE_HOST" "pvesh get /nodes/\$(hostname)/tasks --vmid 2020 --typefilter $1 --userfilter wb-automation --limit 500 --output-format json" 2>/dev/null |
    jq -r '[.[] | select((.user | test("^wb-automation@pve!lab")) and .status == "OK")] | length'
}
check_output "pve01 : au moins un instantané de 2020 créé par le jeton (qmsnapshot OK)" '^[1-9][0-9]*$' \
  _m02_taches qmsnapshot
check_output "pve01 : au moins une purge d'instantané de 2020 par le jeton (qmdelsnapshot OK)" '^[1-9][0-9]*$' \
  _m02_taches qmdelsnapshot

# --- État des instantanés de la VM 2020 (si elle existe encore) ---------------------------
_m02_liste="$(remote "$WB_PVE_HOST" 'pvesh get /nodes/$(hostname)/qemu/2020/snapshot --output-format json' 2>/dev/null || true)"
if [[ -n "$_m02_liste" ]] && jq -e 'type == "array"' >/dev/null 2>&1 <<<"$_m02_liste"; then
  check_cmd "VM 2020 : entre 1 et 3 instantanés « avant-AAAAMMJJ-HHMMSS » (rotation --keep 3)" \
    bash -c 'n=$(jq "[.[] | select(.name | test(\"^avant-[0-9]{8}-[0-9]{6}$\"))] | length" <<<"$1"); ((n >= 1 && n <= 3))' _ "$_m02_liste"
  check_cmd "VM 2020 : l'instantané manuel « manuel-karim » a survécu aux purges" \
    jq -e 'any(.[]; .name == "manuel-karim")' <<<"$_m02_liste"
  check_cmd "--dry-run ne crée ni ne supprime aucun instantané" bash -c '
    avant="$1"
    "$2" --dry-run 2020 </dev/null >/dev/null 2>&1 || exit 1
    apres="$(ssh -o BatchMode=yes "$3" "pvesh get /nodes/\$(hostname)/qemu/2020/snapshot --output-format json")"
    [[ "$(jq -c "[.[].name] | sort" <<<"$avant")" == "$(jq -c "[.[].name] | sort" <<<"$apres")" ]]' \
    _ "$_m02_liste" "$_m02_snap" "$WB_PVE_HOST"
else
  skip "état des instantanés de la VM 2020" "VM 2020 absente (détruite en M02-E16 ?) : seules les traces du journal comptent"
fi
