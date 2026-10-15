# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
#
# check-E24.sh — M12-E24 « Durcir l'exécution : utilisateur, capacités, seccomp, lecture seule »
# Lecture seule : docker inspect et lecture de /proc dans les conteneurs de la pile Compose
# « mediagenda » de ctr01, un essai ptrace(PTRACE_TRACEME) dans un processus fils de l'API (refusé
# attendu, rien n'est modifié), /pret sur ctr01, fichiers sur main (API GitLab).

# shellcheck source=_m12-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-production.sh"

title "M12-E24 — Durcir l'exécution"
require_cmd jq curl

_m12_e24_api="$(_m12p_ctr_service ctr01 mediagenda api)"
_m12_e24_db="$(_m12p_ctr_service ctr01 mediagenda db)"
_m12_e24_vk="$(_m12p_ctr_service ctr01 mediagenda valkey)"
check_cmd "ctr01 : l'API de la pile mediagenda tourne" test -n "$_m12_e24_api"

title "Options d'exécution (docker inspect)"
for _m12_e24_c in "$_m12_e24_api" "$_m12_e24_db" "$_m12_e24_vk"; do
  _m12_e24_j="$(_m12p_inspect ctr01 "$_m12_e24_c")"
  check_cmd "${_m12_e24_c:-service absent} : UID non nul, cap_drop ALL sans ajout, no-new-privileges, non privilégié, racine en lecture seule" \
    _m12p_durci "$_m12_e24_j"
done
_m12_e24_j="$(_m12p_inspect ctr01 "$_m12_e24_api")"
check_cmd "API : profil seccomp personnalisé (JSON transmis au démon)" \
  _m12p_jq "$_m12_e24_j" '(.HostConfig.SecurityOpt // []) | any(startswith("seccomp={"))'
check_cmd "API : le profil personnalisé n'autorise plus ptrace sans capacité" \
  _m12p_jq "$_m12_e24_j" '
    (.HostConfig.SecurityOpt // []) | map(select(startswith("seccomp="))) | .[0] | ltrimstr("seccomp=") | fromjson
    | [.syscalls[] | select(((.includes.caps // []) | length) == 0 and (.action == "SCMP_ACT_ALLOW") and (.names | index("ptrace")))] | length == 0'
check_cmd "API : /tmp est un tmpfs borné et sans exécution" \
  _m12p_jq "$_m12_e24_j" '(.HostConfig.Tmpfs // {})["/tmp"] // "" | test("size=") and test("noexec")'

title "Dans le conteneur de l'API"
_m12_e24_st="$(_m12p_docker ctr01 "exec $_m12_e24_api cat /proc/1/status")"
check_output "API : aucune capacité, même dans le jeu limite (CapBnd à 0)" '^CapBnd:[[:space:]]+0+$' echo "$_m12_e24_st"
check_output "API : NoNewPrivs à 1" '^NoNewPrivs:[[:space:]]+1$' echo "$_m12_e24_st"
check_output "API : ptrace refusé (EPERM)" '^ptrace-refuse$' _m12p_docker ctr01 \
  "exec $_m12_e24_api python -c \"import ctypes,os,sys
l=ctypes.CDLL(None,use_errno=True)
p=os.fork()
if p==0: os._exit(0 if l.ptrace(0,0,0,0)==0 else 1)
print('ptrace-refuse' if os.waitstatus_to_exitcode(os.waitpid(p,0)[1]) else 'ptrace-accepte')\""
check_ssh_output "ctr01 : /pret répond (PostgreSQL et Valkey joints)" ctr01 '"statut": ?"pret"' \
  "curl -s --max-time 5 http://127.0.0.1:8000/pret || sudo -n docker exec $_m12_e24_api python -c \"import urllib.request as u; print(u.urlopen('http://127.0.0.1:8000/pret').read().decode())\""

title "Dans le code"
check_cmd "mediagenda/api : securite/seccomp-mediagenda.json sur main" \
  _m12p_doc_main mediagenda/api securite/seccomp-mediagenda.json 'SCMP_ACT_ERRNO'
check_cmd "mediagenda/api : un script de securite/ régénère le profil" \
  _m12p_arbre_contient mediagenda/api '^securite/.+\.(sh|py)$'
check_cmd "mediagenda/api : compose.yaml retire toutes les capacités et passe en lecture seule" \
  _m12p_doc_main mediagenda/api compose.yaml 'cap_drop' 'read_only: *true' 'no-new-privileges'
check_cmd "plateforme/medisphere : docs/conteneurs/durcissement-execution.md sur main" \
  _m12p_doc_main plateforme/medisphere docs/conteneurs/durcissement-execution.md 'seccomp' 'no-new-privileges|no_new_priv'
