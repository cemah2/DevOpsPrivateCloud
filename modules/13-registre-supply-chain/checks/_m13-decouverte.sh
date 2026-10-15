# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et commandes distantes entre apostrophes
# _m13-decouverte.sh — fonctions partagées par les checks M13-E02 à M13-E12 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m13d_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès : configuration Proxmox lue sur pve01 (qm config) ; reg01 et runner02 en SSH (sudo -n pour
# LIRE) ; API de Harbor par harbor_api (robot wb-checks, lecture seule, à partir de M13-E03) ;
# skopeo et cosign avec le même robot, dans un dossier d'authentification TEMPORAIRE (effacé à la
# sortie) ; GitLab par gitlab_api (jeton en lecture).

_M13D_REG="reg01"
_M13D_NOM="registry.par1.medisphere.internal"
_M13D_DNS="10.10.20.10"
_M13D_CFG="$HOME/.config/workbook"
_M13D_TRAVAIL="$HOME/m13"
_M13D_DOC="projects/plateforme%2Fmedisphere"
_M13D_ANSIBLE="projects/plateforme%2Fansible"
_M13D_INFRA="projects/plateforme%2Finfra"
_M13D_CITPL="projects/plateforme%2Fci-templates"
_M13D_TMP=""

# _m13d_tmp — dossier temporaire du check (créé une fois, effacé à la sortie).
_m13d_tmp() {
  if [[ -z "$_M13D_TMP" ]]; then
    _M13D_TMP="$(mktemp -d "${TMPDIR:-/tmp}/wb-m13.XXXXXX")"
    chmod 700 "$_M13D_TMP"
    trap 'rm -rf "$_M13D_TMP"' EXIT
  fi
  printf '%s' "$_M13D_TMP"
}

# _m13d_qm VMID — configuration Proxmox de la VM (vide si erreur).
_m13d_qm() { remote "$WB_PVE_HOST" "qm config $1" 2>/dev/null || true; }

# _m13d_api CHEMIN — GET sur l'API de Harbor avec wb-checks ; sortie vide si erreur.
_m13d_api() { harbor_api "$1" 2>/dev/null || true; }

# _m13d_projet NOM — objet JSON du projet (GET /projects/{nom}), vide si absent.
_m13d_projet() { _m13d_api "projects/$1"; }

# _m13d_artefacts PROJET DÉPÔT — artefacts du dépôt avec étiquettes, analyse, accessoires, SBOM.
#   Un « / » dans le nom du dépôt est encodé deux fois (%252F), comme l'exige l'API de Harbor.
_m13d_artefacts() {
  local depot="${2//\//%252F}"
  _m13d_api "projects/$1/repositories/$depot/artifacts?page_size=100&with_tag=true&with_scan_overview=true&with_accessory=true&with_sbom_overview=true"
}

# _m13d_derniere_version PROJET DÉPÔT — plus grande étiquette au format version (v)X.Y.Z.
_m13d_derniere_version() {
  _m13d_artefacts "$1" "$2" | jq -r '.[]?.tags[]?.name' 2>/dev/null \
    | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 || true
}

# _m13d_empreinte PROJET DÉPÔT ÉTIQUETTE — empreinte de l'artefact qui porte l'étiquette.
_m13d_empreinte() {
  _m13d_artefacts "$1" "$2" | jq -r --arg t "$3" '[.[]? | select([.tags[]?.name] | index($t)) | .digest][0] // empty' 2>/dev/null || true
}

# _m13d_auth — chemin d'un DOCKER_CONFIG temporaire avec les identifiants de wb-checks.
_m13d_auth() {
  local d f="${WB_HARBOR_CHECKS_FILE:-$_M13D_CFG/harbor-checks.env}" HARBOR_USER="" HARBOR_PASSWORD=""
  d="$(_m13d_tmp)/docker"
  if [[ ! -s "$d/config.json" && -r "$f" ]]; then
    mkdir -p "$d"
    # shellcheck disable=SC1090
    source "$f"
    jq -n --arg r "$_M13D_NOM" --arg a "$(printf '%s:%s' "$HARBOR_USER" "$HARBOR_PASSWORD" | base64 -w0)" \
      '{auths: {($r): {auth: $a}}}' > "$d/config.json"
    chmod 600 "$d/config.json"
  fi
  printf '%s' "$d"
}

# _m13d_cle_publique — cosign.pub de main de plateforme/medisphere, copiée dans le dossier temporaire.
_m13d_cle_publique() {
  local f
  f="$(_m13d_tmp)/cosign.pub"
  [[ -s "$f" ]] || _m13d_contenu_main "$_M13D_DOC" docs/registre/cosign.pub > "$f"
  printf '%s' "$f"
}

# _m13d_cosign_verifie RÉF — la signature de RÉF (…@sha256:…) se vérifie avec la clé publiée.
_m13d_cosign_verifie() {
  local pub
  pub="$(_m13d_cle_publique)"
  grep -q 'BEGIN PUBLIC KEY' "$pub" 2>/dev/null || return 1
  DOCKER_CONFIG="$(_m13d_auth)" timeout 60 cosign verify --key "$pub" --insecure-ignore-tlog=true "$1" >/dev/null 2>&1
}

# _m13d_attestation_verifiee RÉF TYPE — attestation TYPE (spdxjson, cyclonedx) vérifiable.
_m13d_attestation_verifiee() {
  local pub
  pub="$(_m13d_cle_publique)"
  grep -q 'BEGIN PUBLIC KEY' "$pub" 2>/dev/null || return 1
  DOCKER_CONFIG="$(_m13d_auth)" timeout 60 cosign verify-attestation --key "$pub" --insecure-ignore-tlog=true \
    --type "$2" "$1" >/dev/null 2>&1
}

# _m13d_fichier_main PROJET CHEMIN [REF] / _m13d_contenu_main — comme aux modules 06 et 08.
_m13d_fichier_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin?ref=${3:-main}" >/dev/null 2>&1
}
_m13d_contenu_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin/raw?ref=${3:-main}" 2>/dev/null || true
}

# _m13d_cert_tls HÔTE PORT — certificat présenté (texte d'openssl x509), vide si échec.
_m13d_cert_tls() {
  timeout "$WB_TIMEOUT" openssl s_client -connect "$1:$2" -servername "$1" </dev/null 2>/dev/null \
    | openssl x509 -noout -issuer -subject -dates -ext subjectAltName 2>/dev/null || true
}

# _m13d_duree_jours TEXTE_X509 — durée de validité en jours (arrondie).
_m13d_duree_jours() {
  local debut fin
  debut="$(sed -n 's/^notBefore=//p' <<<"$1")"
  fin="$(sed -n 's/^notAfter=//p' <<<"$1")"
  [[ -n "$debut" && -n "$fin" ]] || { echo 9999; return 0; }
  echo $(( ($(date -d "$fin" +%s) - $(date -d "$debut" +%s) + 43200) / 86400 ))
}

# _m13d_local600 FICHIER — fichier local (adm01) non vide en mode 600.
_m13d_local600() { [[ -s "$1" && "$(stat -c %a "$1" 2>/dev/null)" == 600 ]]; }

# _m13d_robot NOM_COMPLET — objet JSON du robot (liste des robots lue par wb-checks), vide si absent.
_m13d_robot() {
  _m13d_api "robots?page_size=100" | jq -c --arg n "$1" '[.[]? | select(.name == $n)][0] // empty' 2>/dev/null || true
}

# _m13d_robot_expire_bien JSON — le robot expire (pas -1) dans 181 jours au plus.
_m13d_robot_expire_bien() {
  local exp
  exp="$(jq -r '.expires_at // -1' <<<"$1" 2>/dev/null)"
  [[ "$exp" =~ ^[0-9]+$ ]] && (( exp > $(date +%s) && exp <= $(date +%s) + 181 * 86400 ))
}

# _m13d_robot_sans_ecriture JSON — aucune action d'écriture dans les permissions du robot.
_m13d_robot_sans_ecriture() {
  jq -e '[.permissions[]?.access[]?.action] | length > 0 and all(. as $a | ["create","update","delete","push","stop","operate","*"] | index($a) | not)' <<<"$1" >/dev/null 2>&1
}
