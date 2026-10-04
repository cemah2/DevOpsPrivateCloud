# shellcheck shell=bash
# shellcheck disable=SC2016  # les commandes bash -c reçoivent leurs valeurs en paramètres
#
# check-E25.sh — M02-E25 : Empaqueter, versionner et distribuer medictl
# À lancer depuis adm01. Lecture seule : API GitLab (jeton des checks) et outil installé
# par uv sur adm01.

title "M02-E25 — Empaqueter, versionner et distribuer medictl"
require_cmd jq curl uv

_m02_p="projects/plateforme%2Foutils"
_m02_val() { jq -r "$2" <<<"$1" 2>/dev/null || true; }

# --- Dernière version publiée : étiquette, release, paquet -----------------------------
_m02_tags="$(gitlab_api "$_m02_p/repository/tags?order_by=version&sort=desc&per_page=20" 2>/dev/null)" || _m02_tags="[]"
_m02_tag="$(_m02_val "$_m02_tags" '[.[].name | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))][0] // empty')"
_m02_ver="${_m02_tag#v}"
check_cmd "une étiquette de version vX.Y.Z existe sur plateforme/outils" test -n "$_m02_tag"
check_output "la release GitLab ${_m02_tag:-?} existe (posée par semantic-release)" '"tag_name"' \
  gitlab_api "$_m02_p/releases/${_m02_tag:-absente}"
_m02_pk="$(gitlab_api "$_m02_p/packages?package_type=pypi&package_name=medictl&per_page=100" 2>/dev/null)" || _m02_pk="[]"
check_output "le registre PyPI du projet contient medictl ${_m02_ver:-?}" '^true$' \
  _m02_val "$_m02_pk" "any(.[]; .name == \"medictl\" and .version == \"${_m02_ver:-absente}\")"
_m02_pkid="$(_m02_val "$_m02_pk" "[.[] | select(.version == \"${_m02_ver:-absente}\")][0].id // empty")"
if [[ -n "$_m02_pkid" ]]; then
  _m02_pf="$(gitlab_api "$_m02_p/packages/$_m02_pkid/package_files" 2>/dev/null)" || _m02_pf="[]"
  check_output "le paquet ${_m02_ver} contient une roue (wheel) et une archive source" '^true$' \
    _m02_val "$_m02_pf" 'any(.[]; .file_name | endswith(".whl")) and any(.[]; .file_name | endswith(".tar.gz"))'
  _m02_pl="$(gitlab_api "$_m02_p/packages/$_m02_pkid/pipelines" 2>/dev/null)" || _m02_pl="[]"
  check_output "le paquet a été publié par un pipeline de main (et non à la main)" '^true$' \
    _m02_val "$_m02_pl" 'any(.[]; .ref == "main")'
else
  skip "contenu et origine du paquet" "paquet medictl ${_m02_ver:-?} absent du registre"
fi

# --- Installation sur adm01 ---------------------------------------------------------------
check_output "medictl est installé comme outil uv" '^medictl v' uv tool list
check_output "medictl --version affiche la dernière version publiée (${_m02_ver:-?})" \
  "medictl ${_m02_ver//./\\.}\$" medictl --version
_m02_dir="$(uv tool dir 2>/dev/null)/medictl"
check_output "l'outil a été installé depuis le registre PyPI de git01 (reçu d'installation uv)" \
  'git01\.par1\.medisphere\.internal/api/v4/projects/[^/]+/packages/pypi/simple' cat "$_m02_dir/uv-receipt.toml"
check_cmd "l'outil n'est pas une copie installée depuis un répertoire local" \
  bash -c '! compgen -G "$1/lib/python3*/site-packages/medictl-*.dist-info/direct_url.json" >/dev/null' _ "$_m02_dir"
check_cmd "le reçu d'installation ne contient aucun identifiant" \
  bash -c '! grep -Eq "://[^/@\"]+:[^/@\"]+@" "$1/uv-receipt.toml"' _ "$_m02_dir"
_m02_cred="$(uv auth dir 2>/dev/null)/credentials.toml"
if [[ -f "$_m02_cred" ]]; then
  check_output "le magasin d'identifiants de uv n'est lisible que par toi" '^[4-7]00$' stat -c '%a' "$_m02_cred"
else
  skip "droits du magasin d'identifiants de uv" "pas de credentials.toml (identifiants fournis autrement)"
fi
