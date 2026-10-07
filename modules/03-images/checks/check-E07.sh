# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant ou dans la VM
#
# check-E07.sh — M03-E07 « Provisioners et préparation au clonage »
# Clones de contrôle 2030 et 2031 (de 9001) démarrés. Lecture seule.

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E07 — Provisioners et préparation au clonage"
require_cmd jq git shellcheck
_m03_charger
_m03_e07_s="$_M03_SRC/scripts/preparer-clonage.sh"

title "Script de préparation"
check_cmd "scripts/preparer-clonage.sh exécutable" test -x "$_m03_e07_s"
check_cmd "sans remarque ShellCheck" shellcheck -x "$_m03_e07_s"
check_cmd "publié sur main" _m03_fichier_main scripts/preparer-clonage.sh
check_cmd "le script vérifie son résultat (machine-id, clés d'hôte)" \
  bash -c 'grep -q "machine-id" "$1" && grep -q "ssh_host_" "$1"' _ "$_m03_e07_s"

# La préparation est le DERNIER provisioner : aucun « provisioner » après la ligne qui
# appelle preparer-clonage.sh.
_m03_e07_dernier() {
  local f="$_M03_SRC/$1/build.pkr.hcl" p d
  p="$(grep -n 'preparer-clonage\.sh' "$f" 2>/dev/null | tail -n 1 | cut -d: -f1)"
  d="$(grep -n '^ *provisioner "' "$f" 2>/dev/null | tail -n 1 | cut -d: -f1)"
  [[ -n "$p" && -n "$d" && "$p" -gt "$d" ]]
}
for _m03_e07_i in debian13-base rocky10-base; do
  check_cmd "$_m03_e07_i : la préparation est le dernier provisioner" _m03_e07_dernier "$_m03_e07_i"
done

# Les templates ont été (re)créés APRÈS l'arrivée du script dans le dépôt.
_m03_e07_ajout="$(git -C "$_M03_SRC" log --diff-filter=A --format=%ct -- scripts/preparer-clonage.sh 2>/dev/null | tail -n 1)" \
  || _m03_e07_ajout=""
_m03_e07_recent() { # VMID
  local c
  c="$(_m03_conf "$1" | sed -nE 's/^meta: .*ctime=([0-9]+).*/\1/p')"
  [[ -n "$c" && -n "$_m03_e07_ajout" && "$c" -gt "$_m03_e07_ajout" ]]
}
check_cmd "template 9001 reconstruit après l'ajout du script" _m03_e07_recent 9001
check_cmd "template 9002 reconstruit après l'ajout du script" _m03_e07_recent 9002

title "Clones de contrôle 2030 et 2031"
check_cmd "VM 2030 démarrée" _m03_en_marche 2030
check_cmd "VM 2031 démarrée" _m03_en_marche 2031
_m03_e07_val() { _m03_gexec "$1" "$2" 2>/dev/null | head -n 1 || true; }
_m03_e07_mid_a="$(_m03_e07_val 2030 'cat /etc/machine-id')"
_m03_e07_mid_b="$(_m03_e07_val 2031 'cat /etc/machine-id')"
_m03_e07_cle_a="$(_m03_e07_val 2030 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub')"
_m03_e07_cle_b="$(_m03_e07_val 2031 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub')"
_m03_e07_ip_a="$(_m03_e07_val 2030 'hostname -I')"
_m03_e07_ip_b="$(_m03_e07_val 2031 'hostname -I')"
_m03_e07_diff() { [[ -n "$1" && -n "$2" && "$1" != "$2" ]]; }
check_cmd "machine-id différents et initialisés" \
  bash -c '[[ "$1" =~ ^[0-9a-f]{32}$ && "$2" =~ ^[0-9a-f]{32}$ && "$1" != "$2" ]]' _ "$_m03_e07_mid_a" "$_m03_e07_mid_b"
check_cmd "clés d'hôte SSH différentes" _m03_e07_diff "${_m03_e07_cle_a%% root@*}" "${_m03_e07_cle_b%% root@*}"
check_cmd "adresses IP différentes" _m03_e07_diff "$_m03_e07_ip_a" "$_m03_e07_ip_b"
for _m03_e07_v in 2030 2031; do
  check_cmd "$_m03_e07_v : ni compte packer ni sudoers de build" \
    _m03_gexec "$_m03_e07_v" '! id packer >/dev/null 2>&1 && ! test -e /etc/sudoers.d/90-build-packer'
done
