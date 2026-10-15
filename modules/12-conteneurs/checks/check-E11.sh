# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016,SC2088  # « ~ » développé sur l'hôte distant ou simple libellé ; gabarits Go et scripts entre apostrophes : évalués à distance ou par bash -c
#
# check-E11.sh — M12-E11 : BuildKit : cache, secrets de construction, montages
# À lancer depuis adm01. Lecture seule : API GitLab en GET ; sur ctr01 (SSH) : docker image inspect,
# docker save lu en flux (aucun fichier écrit), lecture des archives de ~/m12/e11 ; HTTP vers l'API.

# shellcheck source=_m12-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-operationnel.sh"

title "M12-E11 — BuildKit : cache, secrets de construction, montages"
require_cmd jq curl

# --- 1. Le Dockerfile de main -----------------------------------------------------------------------------
_m12o_e11_df="$(_m12o_fichier mediagenda/api Dockerfile)"
check_cmd "mediagenda/api (main) : Dockerfile à deux étapes au moins" \
  bash -c '[ "$(grep -Eic "^FROM " <<<"$1")" -ge 2 ]' _ "$_m12o_e11_df"
check_cmd "Dockerfile : montage de cache (--mount=type=cache)" _m12o_correspond "$_m12o_e11_df" '--mount=type=cache'
check_cmd "Dockerfile : secret de construction (--mount=type=secret)" _m12o_correspond "$_m12o_e11_df" '--mount=type=secret'
check_cmd "Dockerfile : ni ARG ni ENV porteur d'un jeton ou d'un mot de passe" \
  _m12o_absent "$_m12o_e11_df" '^(ARG|ENV) +[^#]*(TOKEN|JETON|PASSWORD|MOT_DE_PASSE|PASS|SECRET)[A-Z_]*='
_m12o_e11_epingle() { _m12o_from_epingles "$1" && grep -Eq 'uv:0\.12\.23@sha256:' <<<"$1"; }
check_cmd "Dockerfile : images de base épinglées par empreinte, uv 0.12.23 aussi" _m12o_e11_epingle "$_m12o_e11_df"

# --- 2. L'image 0.2.0 et la pile ---------------------------------------------------------------------------
_m12o_e11_img="$(_m12o_docker "image inspect --format '{{.Config.User}}|{{json .Config.Env}}' mediagenda-api:0.2.0")"
check_cmd "ctr01 : image mediagenda-api:0.2.0 présente" test -n "$_m12o_e11_img"
check_cmd "Image : utilisateur 10001, MEDIAGENDA_VERSION=0.2.0" \
  bash -c 'grep -Eq "^10001(:10001)?\|" <<<"$1" && grep -q "MEDIAGENDA_VERSION=0.2.0" <<<"$1"' _ "$_m12o_e11_img"
# Lecture des couches en flux (docker save | python) : uv absent de l'image finale.
_m12o_e11_uv="$(remote "$_M12O_CTR01" "docker save mediagenda-api:0.2.0 2>/dev/null | python3 -c '
import io, sys, tarfile
t = tarfile.open(fileobj=sys.stdin.buffer, mode=\"r|\")
trouve = \"non\"
for m in t:
    if not m.isfile() or not m.name.startswith(\"blobs/\"):
        continue
    data = t.extractfile(m).read()
    try:
        c = tarfile.open(fileobj=io.BytesIO(data), mode=\"r:*\")
        for n in c.getnames():
            if n.rstrip(\"/\").endswith(\"bin/uv\"):
                trouve = \"oui\"
    except tarfile.TarError:
        pass
print(trouve)
'" 2>/dev/null || true)"
check_output "Image : uv absent des couches de l'image finale" '^non$' echo "${_m12o_e11_uv:-?}"
check_output "Pile mediagenda de ctr01 : l'API tourne avec l'image 0.2.0" 'mediagenda-api:0\.2\.0' \
  _m12o_docker "ps --filter label=com.docker.compose.project=mediagenda --filter label=com.docker.compose.service=api --format '{{.Image}}'"
check_output "Depuis adm01 : /sante (port 8000) annonce la version 0.2.0" '"version": *"0\.2\.0"' \
  curl -s --max-time "${WB_TIMEOUT:-5}" "http://$_M12O_NOM01:8000/sante"

# --- 3. Cache exporté et reproductibilité ---------------------------------------------------------------------
check_ssh "ctr01 : ~/m12/e11/cache/ est une disposition OCI (index.json, oci-layout)" "$_M12O_CTR01" \
  'test -s ~/m12/e11/cache/index.json && test -s ~/m12/e11/cache/oci-layout'
_m12o_e11_a="$(_m12o_oci_empreinte "$_M12O_CTR01" '~/m12/e11/repro-a.oci.tar')"
_m12o_e11_b="$(_m12o_oci_empreinte "$_M12O_CTR01" '~/m12/e11/repro-b.oci.tar')"
check_cmd "ctr01 : repro-a.oci.tar et repro-b.oci.tar ont la même empreinte (${_m12o_e11_a:-absente})" \
  bash -c '[[ "$1" =~ ^sha256:[0-9a-f]{64}$ ]] && [ "$1" = "$2" ]' _ "$_m12o_e11_a" "$_m12o_e11_b"
