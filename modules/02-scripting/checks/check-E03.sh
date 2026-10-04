# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes entre apostrophes reçoivent leurs valeurs en paramètres ($1)
#
# check-E03.sh — M02-E03 : Un script Bash robuste (bin/ms-collecte-config)
# À lancer depuis adm01. Exécute le script de l'apprenant dans des dossiers
# temporaires (supprimés à la fin) ; côté dns01, le script ne fait que lire.

title "M02-E03 — Un script Bash robuste : mode strict, trap, codes retour, usage"
require_cmd git tar shellcheck

_m02_s="${WB_SRC:-$HOME/src}/outils/bin/ms-collecte-config"
_m02_t="$(mktemp -d)"

# _m02_lance CMD... — exécute, puis affiche « rc=<code> » suivi des sorties mêlées.
_m02_lance() {
  local out rc=0
  out="$("$@" 2>&1 </dev/null)" || rc=$?
  printf 'rc=%s\n%s\n' "$rc" "$out"
}

# --- Le fichier -------------------------------------------------------------------
check_cmd "bin/ms-collecte-config présent et exécutable" test -x "$_m02_s"
check_output "interpréteur : #!/usr/bin/env bash" '^#!/usr/bin/env bash$' head -n 1 "$_m02_s"
check_cmd "versionné dans plateforme/outils" \
  git -C "$(dirname "$_m02_s")" ls-files --error-unmatch "$_m02_s"
check_cmd "ShellCheck ne signale rien" shellcheck "$_m02_s"

# --- Interface ------------------------------------------------------------------------
check_output "--help : aide affichée, code 0" '^rc=0$' _m02_lance "$_m02_s" --help
check_output "--help : l'aide commence par « Usage »" '^Usage' _m02_lance "$_m02_s" --help
check_output "sans argument : code 2 (usage)" '^rc=2$' _m02_lance "$_m02_s"
check_output "option inconnue : code 2 (usage)" '^rc=2$' _m02_lance "$_m02_s" --option-inexistante
check_output "nom d'hôte commençant par « - » refusé : code 2" '^rc=2$' \
  _m02_lance "$_m02_s" -- -oProxyCommand=false

# --- Garde-fou : jamais dans un dépôt Git ----------------------------------------------
git init -q "$_m02_t/depot"
check_output "destination dans un dépôt Git : refus, code 3" '^rc=3$' \
  _m02_lance "$_m02_s" -o "$_m02_t/depot/collectes" dns01
check_cmd "après un refus, rien n'a été créé dans le dépôt" test ! -e "$_m02_t/depot/collectes"

# --- Collecte réelle (lecture seule sur dns01) -------------------------------------------
_m02_out="$("$_m02_s" -o "$_m02_t/ok" dns01 2>/dev/null </dev/null)" && _m02_rc=0 || _m02_rc=$?
check_output "collecte de dns01 : code 0" '^0$' printf '%s\n' "$_m02_rc"
check_output "sortie standard : uniquement le chemin de l'archive dns01-AAAAMMJJ-HHMMSS.tar.gz" \
  "^${_m02_t}/ok/dns01-[0-9]{8}-[0-9]{6}\.tar\.gz$" printf '%s\n' "$_m02_out"
check_output "sortie standard : une seule ligne (les messages vont sur la sortie d'erreur)" '^1$' \
  bash -c 'printf "%s\n" "$1" | grep -c .' _ "$_m02_out"
_m02_arch="$(find "$_m02_t/ok" -maxdepth 1 -name 'dns01-*.tar.gz' -print -quit 2>/dev/null)" || _m02_arch=""
check_output "archive lisible par son seul propriétaire (600)" '^600$' stat -c %a "${_m02_arch:-/nonexistent}"
check_output "archive : contient la configuration dnsmasq de dns01" '^etc/dnsmasq\.d/' \
  tar -tzf "${_m02_arch:-/nonexistent}"
check_output "aucun fichier temporaire laissé dans la destination" '^1$' \
  bash -c 'find "$1" -mindepth 1 | wc -l' _ "$_m02_t/ok"

# --- Un hôte en échec n'arrête pas les autres, mais se voit ------------------------------
check_output "un hôte injoignable parmi d'autres : code 1" '^rc=1$' \
  _m02_lance "$_m02_s" -o "$_m02_t/mixte" hote-inexistant.invalid dns01
check_output "… et l'hôte joignable a tout de même son archive (et rien d'autre)" '^1$' \
  bash -c 'find "$1" -mindepth 1 | wc -l' _ "$_m02_t/mixte"

rm -rf -- "$_m02_t"
