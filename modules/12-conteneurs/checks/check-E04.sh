# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E04.sh — M12-E04 : Images, couches, manifestes et empreintes
# À lancer depuis adm01. Lecture seule : fichier local, skopeo inspect (lecture du registre) et
# lecture de fichiers sur ctr02, docker image inspect sur ctr01.

# shellcheck source=_m12-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-decouverte.sh"

title "M12-E04 — Images, couches, manifestes et empreintes"
require_cmd jq

_m12d_e04_liste="$HOME/m12/e04/images-de-base.txt"
check_cmd "adm01 : ~/m12/e04/images-de-base.txt existe" test -s "$_m12d_e04_liste"

# _m12d_e04_ligne NOM ETIQUETTE — empreinte notée pour cette image (vide si ligne absente ou mal formée).
_m12d_e04_ligne() {
  [[ -r "$_m12d_e04_liste" ]] || return 0
  grep -E "^${1//./\\.}:${2//./\\.}@sha256:[0-9a-f]{64}[[:space:]]*$" "$_m12d_e04_liste" 2>/dev/null \
    | sed -n 1p | sed -E 's/.*@(sha256:[0-9a-f]{64}).*/\1/' || true
}

# _m12d_e04_est_index NOM EMPREINTE — dans le registre, ce document est un index multi-plateformes.
_m12d_e04_est_index() {
  local brut
  [[ -n "$2" ]] || return 1
  # Sortie capturée d'abord : un « … | grep -q » sous pipefail échoue quand grep s'arrête tôt.
  brut="$(_m12d_ssh ctr02 "skopeo inspect --raw docker://$1@$2")"
  # Analyse JSON (jq) : le registre peut échapper les « / » (application\/vnd…).
  jq -e '(.mediaType // "") as $t
         | ($t == "application/vnd.oci.image.index.v1+json"
            or $t == "application/vnd.docker.distribution.manifest.list.v2+json"
            or ($t == "" and has("manifests")))' <<<"$brut" >/dev/null 2>&1
}

_m12d_e04_debian=""
for _m12d_e04_def in "docker.io/library/debian trixie-slim" "docker.io/library/python 3.13-slim-trixie" \
  "docker.io/library/golang 1.26-trixie" "docker.io/library/postgres 18-trixie" "docker.io/valkey/valkey 8-trixie"; do
  read -r _m12d_e04_nom _m12d_e04_etiq <<<"$_m12d_e04_def"
  _m12d_e04_emp="$(_m12d_e04_ligne "$_m12d_e04_nom" "$_m12d_e04_etiq")"
  [[ "$_m12d_e04_nom" == docker.io/library/debian ]] && _m12d_e04_debian="$_m12d_e04_emp"
  check_cmd "Liste : $_m12d_e04_nom:$_m12d_e04_etiq@sha256:… (nom complet, étiquette, empreinte)" test -n "$_m12d_e04_emp"
  check_cmd "Registre : l'empreinte notée pour $_m12d_e04_nom désigne un index multi-plateformes" \
    _m12d_e04_est_index "$_m12d_e04_nom" "$_m12d_e04_emp"
done

# --- Le dossier OCI de ctr02 ------------------------------------------------------------------------
check_ssh "ctr02 : ~/m12/e04/debian-oci est un OCI layout (oci-layout, index.json, blobs)" ctr02 \
  'd=$HOME/m12/e04/debian-oci; grep -q "imageLayoutVersion" "$d/oci-layout" && test -s "$d/index.json" && test -d "$d/blobs/sha256"'
check_ssh "ctr02 : le manifeste du dossier OCI est l'entrée linux/amd64 de l'index épinglé de debian" ctr02 \
  "[ -n '$_m12d_e04_debian' ] && skopeo inspect --raw docker://docker.io/library/debian@$_m12d_e04_debian | python3 -c '
import json, os, sys
idx = json.load(sys.stdin)
amd = {m[\"digest\"] for m in idx.get(\"manifests\", []) if m.get(\"platform\", {}).get(\"architecture\") == \"amd64\" and m.get(\"platform\", {}).get(\"os\") == \"linux\"}
loc = {m[\"digest\"] for m in json.load(open(os.path.expanduser(\"~/m12/e04/debian-oci/index.json\"))).get(\"manifests\", [])}
sys.exit(0 if amd & loc else 1)'"

# --- L'image épinglée sur ctr01 -------------------------------------------------------------------
# _m12d_e04_presente EMPREINTE — l'image debian épinglée par cette empreinte est dans le stockage de ctr01.
_m12d_e04_presente() {
  [[ -n "$1" ]] && [[ -n "$(_m12d_docker "image inspect --format {{.Id}} docker.io/library/debian@$1")" ]]
}
check_cmd "ctr01 : debian:trixie-slim présente sous l'empreinte de ta liste" _m12d_e04_presente "$_m12d_e04_debian"
