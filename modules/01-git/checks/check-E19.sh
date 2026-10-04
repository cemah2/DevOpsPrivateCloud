# shellcheck shell=bash
# shellcheck disable=SC2016  # variables jq entre apostrophes
#
# check-E19.sh — M01-E19 : rétroportage de deux correctifs de main vers la branche de maintenance e19/1.x
# Lancé depuis adm01. Lecture seule (API GitLab avec le jeton des checks).

title "M01-E19 — Cherry-pick et rétroportage vers une branche de maintenance"
require_cmd curl jq bash

_m01_p="projects/formation%2Fgit-labo"
_m01_f="cherry%2Fsauvegarde-vm.sh"

# _m01_sha_main "début du titre" — empreinte du commit de main portant ce titre
_m01_sha_main() {
  gitlab_api "$_m01_p/repository/commits?ref_name=main&path=$_m01_f&per_page=100" 2>/dev/null \
    | jq -r --arg t "$1" '[.[] | select(.title | startswith($t))][0].id // empty' 2>/dev/null || true
}
_m01_c="$(_m01_sha_main "fix(cherry): refuser un VMID")"
_m01_e="$(_m01_sha_main "fix(cherry): message clair")"
check_cmd "les deux correctifs de main sont identifiables (atelier préparé)" test -n "$_m01_c" -a -n "$_m01_e"

_m01_maint="$(gitlab_api "$_m01_p/repository/commits?ref_name=e19%2F1.x&per_page=100" 2>/dev/null)" || _m01_maint="[]"
check_cmd "e19/1.x contient le correctif « VMID hors plages », rétroporté avec cherry-pick -x" \
  jq -e --arg s "$_m01_c" '$s != "" and any(.[]; .message | contains("(cherry picked from commit " + $s + ")"))' <<<"$_m01_maint"
check_cmd "e19/1.x contient le correctif « message clair quand vzdump échoue », rétroporté avec cherry-pick -x" \
  jq -e --arg s "$_m01_e" '$s != "" and any(.[]; .message | contains("(cherry picked from commit " + $s + ")"))' <<<"$_m01_maint"
check_cmd "les correctifs sont arrivés sur e19/1.x par une merge request fusionnée" \
  test "$(gitlab_api "$_m01_p/merge_requests?state=merged&target_branch=e19%2F1.x" 2>/dev/null | jq 'length' 2>/dev/null || echo 0)" -ge 1

_m01_v="$(gitlab_api "$_m01_p/repository/files/$_m01_f/raw?ref=e19%2F1.x" 2>/dev/null)" || _m01_v=""
check_cmd "e19/1.x : sauvegarde-vm.sh est syntaxiquement valide" bash -n <<<"$_m01_v"
check_cmd "e19/1.x : le contrôle des plages de VMID est présent" grep -q 'VMID hors des plages du workbook' <<<"$_m01_v"
check_cmd "e19/1.x : le message d'échec de vzdump est présent" grep -q 'échec de vzdump' <<<"$_m01_v"
check_cmd "e19/1.x : le nom de fonction de la 1.x (verifier_vmid) est conservé" \
  bash -c 'grep -q "^verifier_vmid()" <<<"$1" && ! grep -q "controler_vmid" <<<"$1"' _ "$_m01_v"
check_cmd "e19/1.x : aucune nouvelle fonctionnalité de main (--pool, syslog) n'a été rétroportée" \
  bash -c '! grep -Eq -- "--pool|logger " <<<"$1"' _ "$_m01_v"
