# shellcheck shell=bash
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées par bash -c
#
# check-E03.sh — M01-E03 : configuration Git de admin@adm01 (niveau global) et signature SSH.
# Lecture seule : lit la configuration, les fichiers de clés (sans phrase de passe) et vérifie
# une signature existante (git verify-commit n'a pas besoin de la clé privée).

title "M01-E03 — Configurer Git sur adm01"
require_cmd git ssh-keygen

_m01_cfg() { git config --global --get "$1" 2>/dev/null; }
_m01_chemin() { local p="$1"; printf '%s' "${p/#\~/$HOME}"; }

# --- Identité ---------------------------------------------------------------------------
check_output "user.name renseigné (prénom et nom)" '^[^[:space:]].*[[:space:]].+$' _m01_cfg user.name
check_output "user.email en @medisphere.internal" '^[a-z0-9._-]+@medisphere\.internal$' _m01_cfg user.email
if [[ -n "${WB_MOI:-}" ]]; then
  check_output "user.email = WB_MOI@medisphere.internal (lab/lab.env)" \
    "^${WB_MOI//./\\.}@medisphere\\.internal\$" _m01_cfg user.email
else
  check_cmd "WB_MOI renseigné dans lab/lab.env" test -n "${WB_MOI:-}"
fi

# --- Réglages --------------------------------------------------------------------------
check_output "init.defaultBranch = main" '^main$' _m01_cfg init.defaultBranch
check_cmd "comportement de git pull explicite (pull.ff=only ou pull.rebase)" \
  bash -c '[ "$(git config --global --get pull.ff)" = only ] || git config --global --get pull.rebase | grep -Eqx "true|merges|interactive"'
check_output "fetch.prune activé" '^true$' _m01_cfg fetch.prune
check_output "push.autoSetupRemote activé" '^true$' _m01_cfg push.autoSetupRemote
check_output "merge.conflictStyle affiche l'ancêtre commun" '^(zdiff3|diff3)$' _m01_cfg merge.conflictStyle
check_output "diff.algorithm = histogram" '^histogram$' _m01_cfg diff.algorithm
check_output "alias lg : graphe des branches" '--graph' _m01_cfg alias.lg
_m01_ign="$(_m01_cfg core.excludesFile)"
_m01_ign="$(_m01_chemin "${_m01_ign:-${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore}")"
check_cmd "fichier d'ignorés global avec .env ($_m01_ign)" grep -Eq '^/?\.env$' "$_m01_ign"

# --- Signature SSH -----------------------------------------------------------------------
check_output "gpg.format = ssh" '^ssh$' _m01_cfg gpg.format
check_output "commits signés par défaut (commit.gpgSign)" '^true$' _m01_cfg commit.gpgSign
check_output "étiquettes annotées signées par défaut (tag.gpgSign)" '^true$' _m01_cfg tag.gpgSign

_m01_sk="$(_m01_cfg user.signingKey)"
if [[ -z "$_m01_sk" || "$_m01_sk" == key::* ]]; then
  check_cmd "user.signingKey désigne un fichier de clé" false
else
  _m01_sk="$(_m01_chemin "$_m01_sk")"
  _m01_pub="${_m01_sk%.pub}.pub"
  _m01_priv="${_m01_sk%.pub}"
  check_cmd "clé publique de signature présente ($_m01_pub)" test -s "$_m01_pub"
  check_output "clé de signature de type ed25519" '^ssh-ed25519 ' cat "$_m01_pub"
  check_output "clé privée de signature en mode 600" '^600$' stat -c %a "$_m01_priv"
  check_cmd "clé privée de signature protégée par une phrase de passe" \
    bash -c '[ -f "$1" ] && ! ssh-keygen -y -P "" -f "$1" >/dev/null 2>&1' _ "$_m01_priv"
  check_cmd "clé de signature distincte de la clé de connexion ~/.ssh/id_ed25519" \
    bash -c '[ -s "$1" ] && [ "$(cut -d" " -f2 "$1")" != "$(cut -d" " -f2 "$2" 2>/dev/null)" ]' \
    _ "$_m01_pub" "$HOME/.ssh/id_ed25519.pub"
  _m01_as="$(_m01_chemin "$(_m01_cfg gpg.ssh.allowedSignersFile)")"
  check_cmd "allowed_signers associe ton adresse à ta clé de signature" \
    bash -c 'f="$1"; [ -s "$f" ] || exit 1; k=$(cut -d" " -f2 "$2"); m=$(git config --global --get user.email); grep -v "^#" "$f" | grep -F "$k" | grep -qF "$m"' \
    _ "$_m01_as" "$_m01_pub"
  check_output "allowed_signers limite la clé à l'espace de noms git" 'namespaces="git"' cat "$_m01_as"
fi

_m01_lo="${WB_SRC:-$HOME/src}/labo-objets"
check_cmd "le dernier commit de ~/src/labo-objets porte une signature valide" \
  git -C "$_m01_lo" verify-commit HEAD
