# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres
#
# check-E29.sh — M02-E29 : Durcir un script lancé avec sudo
# À lancer depuis adm01 (admin, sudo sans mot de passe). Lecture seule : droits des fichiers,
# règles sudo, puis quelques appels de ms-diag par le compte de test astreinte01 (l'outil ne
# fait que lire ; il écrit une ligne d'audit dans le journal, et l'archive va dans un dossier
# temporaire supprimé à la fin).

title "M02-E29 — Durcir un script lancé avec sudo"
require_cmd sudo tar stat

_m02_s=/usr/local/sbin/ms-diag
_m02_r=/etc/sudoers.d/ms-diag

# --- Fichiers installés -----------------------------------------------------------------
check_cmd "$_m02_s est un fichier ordinaire (pas un lien vers un clone)" bash -c '[[ -f "$1" && ! -L "$1" ]]' _ "$_m02_s"
# _m02_sur CHEMIN — vrai si CHEMIN appartient à root, n'est pas modifiable par « les autres »,
# et, s'il est modifiable par son groupe, si ce groupe n'a aucun membre (cas root:staff de Debian).
_m02_sur() {
  local f="$1" g membres
  [[ "$(stat -c %U "$f")" == root ]] || return 1
  ! find "$f" -maxdepth 0 -perm -002 | grep -q . || return 1
  if find "$f" -maxdepth 0 -perm -020 | grep -q .; then
    g="$(stat -c %G "$f")"
    membres="$(getent group "$g" | cut -d: -f4)"
    [[ "$g" == root || -z "$membres" ]] || return 1
  fi
}
check_cmd "$_m02_s appartient à root et n'est modifiable par personne d'autre" _m02_sur "$_m02_s"
_m02_parents_surs() {
  local d
  d="$(dirname "$1")"
  while :; do
    _m02_sur "$d" || return 1
    [[ "$d" == / ]] && return 0
    d="$(dirname "$d")"
  done
}
check_cmd "aucun dossier parent de $_m02_s n'est modifiable par un non-root" _m02_parents_surs "$_m02_s"
check_cmd "$_m02_s ne fait référence à aucun fichier sous /home (clone de travail, lib)" \
  bash -c '! grep -Eq "/home/|~/|\\\$HOME|src/outils" "$1"' _ "$_m02_s"
if [[ -e /usr/local/lib/ms-commun.sh ]]; then
  check_cmd "la bibliothèque /usr/local/lib/ms-commun.sh appartient à root (non modifiable)" \
    _m02_sur /usr/local/lib/ms-commun.sh
fi

# --- Règles sudo ---------------------------------------------------------------------------
check_output "$_m02_r : root, mode 0440" '^root 440$' sudo -n stat -c '%U %a' "$_m02_r"
check_cmd "$_m02_r : syntaxe valide (visudo -c)" sudo -n visudo -cf "$_m02_r"
check_cmd "le compte de test astreinte01 existe et appartient au groupe astreinte" \
  bash -c 'id -nG astreinte01 | tr " " "\n" | grep -qx astreinte'
check_cmd "astreinte01 n'est pas dans le groupe sudo" bash -c '! id -nG astreinte01 | tr " " "\n" | grep -qx sudo'
_m02_l="$(sudo -n sudo -l -U astreinte01 2>/dev/null)" || _m02_l=""
check_output "astreinte01 peut lancer $_m02_s en root sans mot de passe" \
  '\(root\) NOPASSWD: /usr/local/sbin/ms-diag' printf '%s\n' "$_m02_l"
check_cmd "astreinte01 n'a aucun autre droit sudo (ni ALL, ni autre utilisateur cible)" \
  bash -c '! grep -Eq "\(ALL|NOPASSWD: ALL|: ALL$| ALL$" <<<"$1"' _ "$_m02_l"

# --- Comportement, en tant que astreinte01 -------------------------------------------------
_m02_t="$(mktemp -d)"
_m02_diag() { sudo -n -u astreinte01 -- sudo -n "$_m02_s" "$@"; }
_m02_diag ssh.service >"$_m02_t/diag.tar.gz" 2>"$_m02_t/err"
check_output "ms-diag ssh.service produit une archive tar.gz (au moins 3 fichiers) sur la sortie standard" \
  '^([3-9]|[1-9][0-9]+)$' bash -c 'tar -tzf "$1" | grep -vc "/$"' _ "$_m02_t/diag.tar.gz"
check_cmd "l'archive ne contient ni clé privée, ni shadow, ni fichier .env" \
  bash -c 's="$(tar -tzf "$1")" && [[ -n "$s" ]] && ! grep -Eq "ssh_host_[a-z0-9]+_key$|shadow|\.env$|id_(rsa|ed25519)$" <<<"$s"' _ "$_m02_t/diag.tar.gz"
check_cmd "le journal (identifiant ms-diag) trace l'utilisation et l'identité de l'appelant" \
  bash -c 'sudo -n journalctl -q --no-pager -t ms-diag --since -10min | grep -q astreinte01'
for _m02_a in "../../etc/shadow" "ssh.service;id" "--output=/etc/passwd" "/etc/shadow" "nexistepas.service"; do
  check_output "argument refusé : « $_m02_a » (code ≠ 0, aucune archive)" '^refus$' \
    bash -c 'out="$( "$@" 2>/dev/null)"; rc=$?; (( rc != 0 )) && [[ -z "$out" ]] && echo refus' _ \
    sudo -n -u astreinte01 -- sudo -n "$_m02_s" "$_m02_a"
done
check_output "sortie vers un terminal refusée (archive binaire, et pas de pager)" '^refus$' \
  bash -c 'script -qec "sudo -n -u astreinte01 -- sudo -n $1 ssh.service" /dev/null >/dev/null 2>&1; (( $? != 0 )) && echo refus' _ "$_m02_s"
rm -rf -- "${_m02_t:?}"
