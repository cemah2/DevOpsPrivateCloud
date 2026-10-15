# shellcheck shell=bash
# _m12-production.sh — fonctions partagées par les checks M12-E24 à M12-E34 (lecture seule).
# Sourcé par les check-EXX.sh du palier 3 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m12p_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction testée).
#
# Hôtes (SSH en admin, noms courts) : ctr01 (Docker), ctr02 et ctr03 (Podman, compte « app »).
# Aucune fonction ne crée, ne modifie ni ne supprime de conteneur : inspect, ps, exec de lecture.
# Registre de travail : ~/.config/workbook/registre-travail.env (REGISTRE_UTILISATEUR,
# REGISTRE_MOT_DE_PASSE : compte « plateforme » du registre, M12-E15), variable WB_REGISTRE_ENV.

# shellcheck disable=SC2034  # constantes utilisées par les check-EXX.sh qui sourcent ce fichier
_M12P_DOMAINE=par1.medisphere.internal
_M12P_REGISTRE="ctr01.par1.medisphere.internal:5000"
_M12P_RACINE=/usr/local/share/ca-certificates/medisphere-root-ca.crt
_M12P_APP=app
_M12P_APP_UID=1001

# --- Moteurs -----------------------------------------------------------------------------------

# _m12p_docker HÔTE "ARGUMENTS" — docker en lecture sur l'hôte (sudo -n), sortie standard seule.
_m12p_docker() { remote "$1" "sudo -n docker $2" 2>/dev/null || true; }

# _m12p_podman HÔTE "ARGUMENTS" — podman du compte app (sa session : XDG_RUNTIME_DIR, bus).
_m12p_podman() {
  remote "$1" "cd /tmp && sudo -n -u $_M12P_APP env XDG_RUNTIME_DIR=/run/user/$_M12P_APP_UID DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$_M12P_APP_UID/bus podman $2" 2>/dev/null || true
}

# _m12p_systemctl_app HÔTE "ARGUMENTS" — systemctl --user du compte app.
_m12p_systemctl_app() {
  remote "$1" "cd /tmp && sudo -n -u $_M12P_APP env XDG_RUNTIME_DIR=/run/user/$_M12P_APP_UID DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$_M12P_APP_UID/bus systemctl --user $2" 2>/dev/null || true
}

# _m12p_ctr_service HÔTE PROJET SERVICE — nom du conteneur EN MARCHE d'un service Compose.
_m12p_ctr_service() {
  _m12p_docker "$1" "ps --filter label=com.docker.compose.project=$2 --filter label=com.docker.compose.service=$3 --format '{{.Names}}'" | head -n 1
}

# _m12p_inspect HÔTE CONTENEUR — JSON de « docker inspect » (objet unique), ou « null ».
_m12p_inspect() {
  local s
  [[ -n "$2" ]] || { echo null; return; }
  s="$(_m12p_docker "$1" "inspect $2")"
  jq -ce '.[0]' <<<"$s" 2>/dev/null || echo null
}

# _m12p_jq JSON FILTRE [ARGS jq…] — vrai si le filtre jq (-e) est vrai sur le JSON.
_m12p_jq() {
  local d="$1" f="$2"
  shift 2
  [[ -n "$d" && "$d" != null ]] && jq -e "$@" "$f" <<<"$d" >/dev/null 2>&1
}

# _m12p_durci JSON — conteneur durci au sens de E24 : UID non nul, cap_drop ALL sans ajout,
# no-new-privileges, non privilégié, racine en lecture seule, ni seccomp ni AppArmor désactivés.
_m12p_durci() {
  _m12p_jq "$1" '
    ((.Config.User // "") | test("^(0|root)?(:.*)?$") | not)
    and ((.HostConfig.CapDrop // []) | map(ascii_upcase) | (index("ALL") != null or index("CAP_ALL") != null))
    and (((.HostConfig.CapAdd // []) | length) == 0)
    and ((.HostConfig.SecurityOpt // []) | any(test("^no-new-privileges(:true|=true)?$")))
    and ((.HostConfig.SecurityOpt // []) | any(test("unconfined")) | not)
    and (.HostConfig.Privileged == false)
    and (.HostConfig.ReadonlyRootfs == true)'
}

# --- GitLab (jeton des checks, lecture) -----------------------------------------------------------

# _m12p_fichier_main PROJET CHEMIN — contenu d'un fichier de la branche main.
_m12p_fichier_main() {
  local p="${1//\//%2F}" f="${2//\//%2F}"
  gitlab_api "projects/$p/repository/files/$f/raw?ref=main"
}

# _m12p_doc_main PROJET CHEMIN REGEX... — le fichier existe sur main et contient chaque motif
# (grep -E, insensible à la casse).
_m12p_doc_main() {
  local c m p="$1" chemin="$2"
  shift 2
  c="$(_m12p_fichier_main "$p" "$chemin" 2>/dev/null)" || return 1
  [[ -n "$c" ]] || return 1
  for m in "$@"; do grep -Eqi -- "$m" <<<"$c" || return 1; done
}

# _m12p_arbre_contient PROJET REGEX — un fichier de main a un chemin qui correspond (récursif).
_m12p_arbre_contient() {
  local p="${1//\//%2F}"
  gitlab_api "projects/$p/repository/tree?ref=main&recursive=true&per_page=100" 2>/dev/null \
    | jq -e --arg r "$2" 'any(.[]?; .type == "blob" and (.path | test($r)))' >/dev/null
}

# _m12p_pipeline_ok PROJET — dernier pipeline de main réussi (« manual » : jobs manuels non lancés).
_m12p_pipeline_ok() {
  local p="${1//\//%2F}"
  gitlab_api "projects/$p/pipelines?ref=main&per_page=1" 2>/dev/null \
    | jq -e '.[0].status == "success" or .[0].status == "manual"' >/dev/null
}

# --- Registre de travail ---------------------------------------------------------------------------

# _m12p_registre CHEMIN — GET authentifié sur l'API du registre (/v2/…), en-têtes d'acceptation OCI.
_m12p_registre() {
  local f="${WB_REGISTRE_ENV:-$HOME/.config/workbook/registre-travail.env}" REGISTRE_UTILISATEUR="" REGISTRE_MOT_DE_PASSE=""
  [[ -r "$f" ]] || { echo "identifiants du registre illisibles : $f" >&2; return 1; }
  # shellcheck disable=SC1090
  source "$f"
  curl -sf --max-time "$WB_TIMEOUT" --cacert "$_M12P_RACINE" -u "$REGISTRE_UTILISATEUR:$REGISTRE_MOT_DE_PASSE" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json' \
    "https://$_M12P_REGISTRE/v2/$1"
}

# _m12p_etiquettes DÉPÔT — étiquettes d'un dépôt du registre, une par ligne.
_m12p_etiquettes() { _m12p_registre "$1/tags/list" 2>/dev/null | jq -r '.tags[]?' 2>/dev/null; }

# _m12p_config DÉPÔT ÉTIQUETTE — configuration de l'image (plateforme linux/amd64 si index), JSON.
_m12p_config() {
  local m d
  m="$(_m12p_registre "$1/manifests/$2" 2>/dev/null)" || return 1
  if jq -e '.manifests' >/dev/null 2>&1 <<<"$m"; then
    d="$(jq -r '[.manifests[] | select(.platform.os == "linux" and .platform.architecture == "amd64")][0].digest // empty' <<<"$m")"
    [[ -n "$d" ]] || return 1
    m="$(_m12p_registre "$1/manifests/$d" 2>/dev/null)" || return 1
  fi
  d="$(jq -r '.config.digest // empty' <<<"$m")"
  [[ -n "$d" ]] || return 1
  _m12p_registre "$1/blobs/$d" 2>/dev/null
}

# --- PBS ---------------------------------------------------------------------------------------------

# _m12p_pbs_recent HÔTE MOTIF HEURES — dans l'espace par1/conteneurs du datastore ds-lab, un
# instantané de l'hôte de moins de HEURES heures contient une archive dont le nom correspond.
_m12p_pbs_recent() {
  remote "${WB_PBS_HOST:-pbs01}" "
    p=\$(proxmox-backup-manager datastore show ds-lab --output-format json | sed -nE 's/.*\"path\" *: *\"([^\"]+)\".*/\1/p')
    [ -n \"\$p\" ] || exit 1
    find \"\$p/ns/par1/ns/conteneurs/host/$1\" -mindepth 2 -maxdepth 2 -type f -name '$2' -mmin -$(($3 * 60)) 2>/dev/null | grep -q ." \
    >/dev/null 2>&1
}

# --- Divers --------------------------------------------------------------------------------------------

# _m12p_aucune_panne_active — aucune panne M12 marquée par lab/bin/break.
_m12p_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives"
  [[ -z "$(find "$d" -maxdepth 1 -name 'M12-E*' 2>/dev/null)" ]]
}
