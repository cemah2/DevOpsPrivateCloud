# shellcheck shell=bash
# _m06-operationnel.sh — fonctions partagées par les checks M06-E10 à M06-E21 (lecture seule).
# Sourcé par les check-EXX.sh concernés (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m06o_ : pas de collision avec les fonctions des autres paliers.
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
# Les jetons et clés sont lus dans leurs fichiers et passés à curl par l'entrée standard
# (-H @-) : ils n'apparaissent ni dans ps, ni dans la sortie.

_M06O_CFG="$HOME/.config/workbook"
_M06O_NB="${WB_NETBOX_URL:-https://nbx01.par1.medisphere.internal}"
_M06O_ANSIBLE="${WB_SRC:-$HOME/src}/ansible"
_M06O_ZONE="par1.medisphere.internal"
_M06O_PROJET_OUTILS="projects/plateforme%2Foutils"
_M06O_PROJET_ANSIBLE="projects/plateforme%2Fansible"
_M06O_PROJET_MODULES="projects/plateforme%2Ftofu-modules"
_M06O_PROJET_INFRA="projects/plateforme%2Finfra"

# Dossier temporaire du check (effacé à la sortie) : fichiers known_hosts de test, en-têtes.
_M06O_TMP="$(mktemp -d)"
trap 'rm -rf "$_M06O_TMP"' EXIT

# Hôtes du socle à la fin du palier 2 (PLAN.md §4.5) : nom → adresse de connexion.
declare -A _M06O_IP=([gw01]=10.10.10.1 [adm01]=10.10.10.10 [dns01]=10.10.20.10 [ca01]=10.10.20.11
  [git01]=10.10.20.12 [nbx01]=10.10.20.13 [s3-01]=10.10.20.14 [runner01]=10.10.20.15)
_M06O_SOCLE="gw01 adm01 dns01 ca01 git01 nbx01 s3-01 runner01"
# Hôtes joints en SSH depuis adm01 (adm01 lui-même : exécution locale, voir remote()).
_M06O_DISTANTS="gw01 dns01 ca01 git01 nbx01 s3-01 runner01"

# _m06o_mode600 FICHIER — le fichier existe, n'est pas vide, et est en mode 600.
_m06o_mode600() {
  [[ -s "$1" && "$(stat -c %a "$1" 2>/dev/null)" == 600 ]]
}

# _m06o_nb FICHIER_JETON CHEMIN — GET sur l'API REST NetBox avec le jeton du fichier (v2).
_m06o_nb() {
  [[ -r "$1" ]] || return 1
  printf 'Authorization: Bearer %s\n' "$(tr -d '\n' <"$1")" \
    | curl -sf --max-time "$WB_TIMEOUT" -H @- -H 'Accept: application/json' "$_M06O_NB/api/$2"
}

# _m06o_nb_code FICHIER_JETON CHEMIN — code HTTP d'un GET (pour prouver un refus, 403).
_m06o_nb_code() {
  [[ -r "$1" ]] || { echo 000; return 0; }
  printf 'Authorization: Bearer %s\n' "$(tr -d '\n' <"$1")" \
    | curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" -H @- "$_M06O_NB/api/$2" || true
}

# _m06o_jeton_lecture_seule FICHIER_JETON — CE jeton (retrouvé par sa clé, partie entre « nbt_ » et
# le point) existe et n'a pas le droit d'écrire. Le filtre par clé est indispensable : un compte voit
# au moins ses propres jetons (dont, pour svc-automatisation, le jeton d'écriture), et wb-checks,
# qui a « view » sur tous les types d'objets, voit ceux de tout le monde.
_m06o_jeton_lecture_seule() {
  local cle
  cle="$(sed -n 's/^nbt_\([A-Za-z0-9]*\)\..*/\1/p' "$1" 2>/dev/null | head -n 1)"
  [[ -n "$cle" ]] || return 1
  _m06o_nb "$1" "users/tokens/?key=$cle" \
    | jq -e '.results | length == 1 and (.[0].write_enabled == false)' >/dev/null
}

# _m06o_graphql REQUÊTE — requête GraphQL (lecture) avec le jeton des checks ; JSON de réponse.
_m06o_graphql() {
  local f="${WB_NETBOX_TOKEN_FILE:-$_M06O_CFG/netbox-checks.token}"
  [[ -r "$f" ]] || return 1
  # En-tête dans un fichier du dossier temporaire (700) : l'entrée standard porte la requête.
  printf 'Authorization: Bearer %s\n' "$(tr -d '\n' <"$f")" >"$_M06O_TMP/entete"
  jq -n --arg q "$1" '{query: $q}' \
    | curl -sf --max-time "$WB_TIMEOUT" -H @"$_M06O_TMP/entete" -H 'Content-Type: application/json' \
      --data @- "$_M06O_NB/graphql/"
}

# _m06o_pdns CHEMIN — GET sur l'API PowerDNS (…/servers/localhost/CHEMIN) avec la clé de
# ~/.config/workbook/powerdns-api.env (lu sans être exécuté).
_m06o_pdns() {
  local f="$_M06O_CFG/powerdns-api.env" url cle
  [[ -r "$f" ]] || return 1
  url="$(sed -nE 's/^(export[[:space:]]+)?PDNS_SERVER_URL="?([^"]*)"?.*/\2/p' "$f" | head -n 1)"
  cle="$(sed -nE 's/^(export[[:space:]]+)?PDNS_API_KEY="?([^"]*)"?.*/\2/p' "$f" | head -n 1)"
  [[ -n "$url" && -n "$cle" ]] || return 1
  printf 'X-API-Key: %s\n' "$cle" \
    | curl -sf --max-time "$WB_TIMEOUT" -H @- "${url%/}/api/v1/servers/localhost/$1"
}

# _m06o_dig NOM [TYPE] — réponse courte du résolveur du lab (10.10.20.10).
_m06o_dig() {
  dig +short +time=3 +tries=1 @10.10.20.10 "$1" "${2:-A}" 2>/dev/null || true
}

# _m06o_pve_vms — /cluster/resources (VMs) de pve01, en JSON (lu en root sur pve01).
_m06o_pve_vms() {
  remote "${WB_PVE_HOST:-pve01}" 'pvesh get /cluster/resources --type vm --output-format json' 2>/dev/null || true
}

# _m06o_fichier_main PROJET CHEMIN [REF] — le fichier existe sur la référence (main par défaut).
_m06o_fichier_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin?ref=${3:-main}" >/dev/null 2>&1
}

# _m06o_contenu_main PROJET CHEMIN [REF] — contenu brut d'un fichier du dépôt (vide si absent).
_m06o_contenu_main() {
  local chemin
  chemin="$(jq -rn --arg v "$2" '$v | @uri')"
  gitlab_api "$1/repository/files/$chemin/raw?ref=${3:-main}" 2>/dev/null || true
}

# _m06o_etiquette PROJET REGEX — une étiquette Git du projet correspond à la regex.
_m06o_etiquette() {
  gitlab_api "$1/repository/tags?per_page=100" 2>/dev/null \
    | jq -e --arg r "$2" 'map(select(.name | test($r))) | length > 0' >/dev/null 2>&1
}

# _m06o_ans COMMANDE [ARGS…] — outil de l'environnement du projet Ansible, depuis sa racine,
# avec les accès de l'inventaire (Proxmox et NetBox) chargés comme le ferait l'apprenant.
_m06o_ans() {
  (
    cd "$_M06O_ANSIBLE" 2>/dev/null || exit 1
    set -a
    # shellcheck source=/dev/null
    [[ -r "$_M06O_CFG/pve-ansible.env" ]] && . "$_M06O_CFG/pve-ansible.env"
    # shellcheck source=/dev/null
    [[ -r "$_M06O_CFG/netbox-ansible.env" ]] && . "$_M06O_CFG/netbox-ansible.env"
    set +a
    env -u ANSIBLE_CONFIG PATH="$_M06O_ANSIBLE/.venv/bin:$PATH" ANSIBLE_NOCOLOR=1 "$@"
  )
}

# _m06o_inventaire FICHIER — inventaire (--list) normalisé : groupes socle/role_* triés et
# ansible_host de chaque hôte du socle ({"groupes":…, "adresses":…}) ; vide si erreur.
_m06o_inventaire() {
  _m06o_ans ansible-inventory -i "$1" --list 2>/dev/null </dev/null | jq -S -c '
    def brut: if type == "object" and has("__ansible_unsafe") then .__ansible_unsafe else . end;
    . as $inv
    | { groupes: (with_entries(select(.key == "socle" or (.key | startswith("role_"))))
                  | map_values((.hosts // []) | sort)),
        adresses: ([($inv.socle.hosts // [])[] as $h
                    | {($h): ($inv._meta.hostvars[$h].ansible_host | brut)}] | add // {}) }' 2>/dev/null || true
}

# _m06o_cert_tls HÔTE PORT [OPTIONS s_client…] — certificat présenté (texte d'openssl x509),
# vide si échec. Ex. NTS-KE : _m06o_cert_tls 10.10.20.1 4460 -alpn ntske/1
_m06o_cert_tls() {
  local hote="$1" port="$2"
  shift 2
  timeout "$WB_TIMEOUT" openssl s_client -connect "$hote:$port" -servername "$hote" "$@" </dev/null 2>/dev/null \
    | openssl x509 -noout -issuer -subject -dates -ext subjectAltName 2>/dev/null || true
}

# _m06o_duree_jours TEXTE_X509 — durée de validité (notAfter - notBefore) en jours, arrondie.
_m06o_duree_jours() {
  local debut fin
  debut="$(sed -n 's/^notBefore=//p' <<<"$1")"
  fin="$(sed -n 's/^notAfter=//p' <<<"$1")"
  [[ -n "$debut" && -n "$fin" ]] || { echo 9999; return 0; }
  echo $(( ($(date -d "$fin" +%s) - $(date -d "$debut" +%s) + 43200) / 86400 ))
}

