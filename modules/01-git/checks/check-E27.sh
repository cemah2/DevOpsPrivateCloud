# shellcheck shell=bash
# shellcheck disable=SC2016  # scripts de bash -c et filtres jq : développés par le sous-shell, pas ici
#
# check-E27.sh — M01-E27 « Signer commits et étiquettes, vérifier dans GitLab »
# Lancé depuis adm01 (ton compte, ta configuration Git). Lecture seule : l'étiquette
# est vérifiée dans un clone nu temporaire, supprimé à la fin.

title "M01-E27 — Signer commits et étiquettes"
require_cmd git jq curl ssh-keygen

_m01_get() { gitlab_api "$1" 2>/dev/null || true; }
_m01_HOTE="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}"
_m01_HOTE="${_m01_HOTE#https://}"
_m01_TAG=essai-signature-e27

# --- 1. Configuration locale ---------------------------------------------------------------
check_output "Git : format de signature SSH" '^ssh$' git config --global --get gpg.format
check_output "Git : commits signés par défaut" '^true$' git config --global --get commit.gpgsign
check_output "Git : étiquettes signées par défaut" '^true$' git config --global --get tag.gpgsign
_m01_cle_pub="$(git config --global --get user.signingkey 2>/dev/null || true)"
_m01_cle_pub="${_m01_cle_pub/#\~/$HOME}"
[[ -f "$_m01_cle_pub" ]] || _m01_cle_pub=""
check_cmd "Git : clé de signature (user.signingkey) lisible" test -n "$_m01_cle_pub"
_m01_signers="$(git config --global --get gpg.ssh.allowedSignersFile 2>/dev/null || true)"
_m01_signers="${_m01_signers/#\~/$HOME}"
_m01_cle_txt="$( [[ -n "$_m01_cle_pub" ]] && awk '{print $2}' "$_m01_cle_pub" 2>/dev/null || true)"
check_cmd "Git : fichier allowedSignersFile présent et contenant ta clé de signature" \
  bash -c '[[ -n "$2" && -f "$1" ]] && grep -qF -- "$2" "$1"' _ "$_m01_signers" "$_m01_cle_txt"

# --- 2. Côté GitLab -------------------------------------------------------------------------
_m01_user="$(_m01_get user)"
check_cmd "GitLab : une clé de ton compte a l'usage « Signing », avec une date d'expiration" \
  jq -e 'any(.[]?; (.usage_type == "signing" or .usage_type == "auth_and_signing") and .expires_at != null)' \
  <<<"$(_m01_get user/keys)"
check_cmd "GitLab : cette clé est bien ta clé de signature locale" \
  bash -c '[[ -n "$2" ]] && jq -e --arg k "$2" '"'"'any(.[]?; (.key | split(" ")[1]) == $k)'"'"' <<<"$1" >/dev/null' _ "$(_m01_get user/keys)" "$_m01_cle_txt"
_m01_courriels="$(jq -r '[.email, .commit_email, .public_email] | map(select(. != null and . != "")) | unique | .[]' <<<"$_m01_user" 2>/dev/null || true)"
_m01_sha=""
if [[ -n "$_m01_courriels" ]]; then
  _m01_sha="$(_m01_get "projects/plateforme%2Fmedisphere/repository/commits?ref_name=main&per_page=100" \
    | jq -r --arg m "$_m01_courriels" '($m | split("\n")) as $mails | [.[]? | select((.parent_ids | length) == 1 and (.author_email as $a | $mails | index($a)))][0].id // empty' 2>/dev/null || true)"
fi
check_cmd "plateforme/medisphere : un de tes commits est arrivé sur main" test -n "$_m01_sha"
check_cmd "ton dernier commit sur main est signé SSH et « Verified » dans GitLab" \
  jq -e '.signature_type == "SSH" and .verification_status == "verified"' \
  <<<"$(_m01_get "projects/plateforme%2Fmedisphere/repository/commits/${_m01_sha:-0}/signature")"
check_cmd "plateforme/medisphere : liste des signataires versionnée (docs/socle/securite/allowed_signers)" \
  test -n "$(_m01_get "projects/plateforme%2Fmedisphere/repository/files/docs%2Fsocle%2Fsecurite%2Fallowed_signers/raw?ref=main")"

# --- 3. Étiquette signée -----------------------------------------------------------------------
check_cmd "formation/git-labo : étiquette annotée $_m01_TAG présente" \
  jq -e '.name and (.message | length > 0)' <<<"$(_m01_get "projects/formation%2Fgit-labo/repository/tags/$_m01_TAG")"
_m01_tmp="$(mktemp -d)"
check_cmd "l'étiquette $_m01_TAG est signée et vérifiée par git tag -v (clone temporaire)" \
  bash -c 'git init -q --bare "$1/d.git" \
    && git -C "$1/d.git" fetch -q "git@$2:formation/git-labo.git" "refs/tags/$3:refs/tags/$3" \
    && git -C "$1/d.git" tag -v "$3"' _ "$_m01_tmp" "$_m01_HOTE" "$_m01_TAG"
rm -rf "$_m01_tmp"
