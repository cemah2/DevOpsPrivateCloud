# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c
# check-E21.sh — M11-E21 « Panne : l'installation reste bloquée » : preseed et kickstart servis par
# pxe01 complets pour une installation sans question (partitionnement confirmé, disque existant,
# source joignable), validés quand les validateurs sont installés sur adm01 ; panne close. Lecture seule.

# shellcheck source=_m11-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-expert.sh"

title "M11-E21 — Fichiers de réponse servis"
require_cmd curl ssh

_m11_e21_r="$(_m11p_racine_nginx)" || true
mapfile -t _m11_e21_pre < <(remote pxe01 "ls '${_m11_e21_r:-/srv/http}'/preseed/ 2>/dev/null" 2>/dev/null | grep -E '\.cfg$')
mapfile -t _m11_e21_ks < <(remote pxe01 "ls '${_m11_e21_r:-/srv/http}'/kickstart/ 2>/dev/null" 2>/dev/null | grep -E '\.ks$')
check_cmd "pxe01 : au moins un preseed et un kickstart servis" test "${#_m11_e21_pre[@]}" -ge 1 -a "${#_m11_e21_ks[@]}" -ge 1

for _m11_e21_f in "${_m11_e21_pre[@]}"; do
  _m11_e21_c="$(_m11p_https_contenu "/preseed/$_m11_e21_f")" || true
  check_cmd "preseed/$_m11_e21_f : lisible en HTTPS depuis adm01" test -n "$_m11_e21_c"
  check_cmd "preseed/$_m11_e21_f : partman/confirm et partman/confirm_nooverwrite préremplis" \
    bash -c 'grep -Eq "^d-i[[:space:]]+partman/confirm[[:space:]]+boolean[[:space:]]+true" <<<"$1" && grep -Eq "^d-i[[:space:]]+partman/confirm_nooverwrite[[:space:]]+boolean[[:space:]]+true" <<<"$1"' _ "$_m11_e21_c"
  if command -v debconf-set-selections >/dev/null 2>&1; then
    check_cmd "preseed/$_m11_e21_f : accepté par debconf-set-selections -c" \
      bash -c 't="$(mktemp)"; printf "%s\n" "$1" >"$t"; debconf-set-selections -c "$t" >/dev/null 2>&1; r=$?; rm -f "$t"; exit $r' _ "$_m11_e21_c"
  else
    skip "preseed/$_m11_e21_f : debconf-set-selections -c" "debconf absent sur ce poste"
  fi
done

for _m11_e21_f in "${_m11_e21_ks[@]}"; do
  _m11_e21_c="$(_m11p_https_contenu "/kickstart/$_m11_e21_f")" || true
  check_cmd "kickstart/$_m11_e21_f : lisible en HTTPS depuis adm01" test -n "$_m11_e21_c"
  # Les VMs bm* n'ont qu'un disque (scsi0) : sda (ou vda selon le contrôleur).
  check_cmd "kickstart/$_m11_e21_f : ignoredisk limité au seul disque existant (sda/vda)" \
    bash -c 'd="$(sed -nE "s/^ignoredisk[[:space:]]+--only-use=([a-z0-9]+).*/\1/p" <<<"$1" | head -n 1)"; [ -z "$d" ] || [ "$d" = sda ] || [ "$d" = vda ]' _ "$_m11_e21_c"
  _m11_e21_url="$(sed -nE 's/^url[[:space:]].*--url=?[[:space:]]*([^[:space:]]+).*/\1/p' <<<"$_m11_e21_c" | head -n 1)" || true
  if [[ -n "$_m11_e21_url" ]]; then
    check_http "kickstart/$_m11_e21_f : source d'installation joignable (${_m11_e21_url%/}/repodata/repomd.xml)" \
      "${_m11_e21_url%/}/repodata/repomd.xml" 200 --max-time 20
  else
    skip "kickstart/$_m11_e21_f : source d'installation" "pas de commande url (source donnée par inst.repo)"
  fi
  if command -v ksvalidator >/dev/null 2>&1; then
    check_cmd "kickstart/$_m11_e21_f : accepté par ksvalidator -v RHEL10" \
      bash -c 't="$(mktemp)"; printf "%s\n" "$1" >"$t"; ksvalidator -v RHEL10 "$t" >/dev/null 2>&1; r=$?; rm -f "$t"; exit $r' _ "$_m11_e21_c"
  else
    skip "kickstart/$_m11_e21_f : ksvalidator" "pykickstart absent sur ce poste (uv tool install pykickstart)"
  fi
done

# inst.repo des scripts iPXE (source d'Anaconda quand le kickstart n'a pas de url)
for _m11_e21_s in $(_m11x_scripts_mac); do
  _m11_e21_repo="$(_m11p_https_contenu "$_m11_e21_s" | grep -oE 'inst\.repo=[^[:space:]]+' | head -n 1 | cut -d= -f2-)" || true
  [[ -n "$_m11_e21_repo" ]] || continue
  check_http "$_m11_e21_s : inst.repo joignable (${_m11_e21_repo%/}/.treeinfo)" "${_m11_e21_repo%/}/.treeinfo" 200 --max-time 20
done
check_cmd "panne M11-E21 close (lab/bin/break 11 21 --annuler après réparation)" _m11p_aucune_panne_active E21
