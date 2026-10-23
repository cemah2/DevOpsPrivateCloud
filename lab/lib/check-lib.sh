#!/usr/bin/env bash
# check-lib.sh — Bibliothèque commune des scripts de vérification du workbook.
#
# Usage : sourcée par lab/bin/check, jamais exécutée directement.
# Toutes les fonctions sont en LECTURE SEULE : elles observent le lab, ne le modifient pas.
#
# Variables d'environnement (définies dans lab/lab.env, voir lab/lab.env.example) :
#   WB_PVE_HOST   hôte SSH de l'hyperviseur principal (défaut : pve01)
#   WB_PBS_HOST   hôte SSH du Proxmox Backup Server  (défaut : pbs01)
#   WB_SSH_OPTS   options SSH supplémentaires
#   WB_TIMEOUT    délai max (s) pour les tests réseau (défaut : 5)
#   WB_GITLAB_URL, WB_GITLAB_TOKEN_FILE, WB_NETBOX_URL, WB_NETBOX_TOKEN_FILE  (bloc A, voir lab.env.example)

# shellcheck disable=SC2034  # variables utilisées par les scripts qui sourcent la lib
WB_PVE_HOST="${WB_PVE_HOST:-pve01}"
WB_PBS_HOST="${WB_PBS_HOST:-pbs01}"
WB_SSH_OPTS="${WB_SSH_OPTS:-}"
WB_TIMEOUT="${WB_TIMEOUT:-5}"

_WB_OK=0
_WB_KO=0
_WB_SKIP=0

if [[ -t 1 ]]; then
  _C_OK=$'\e[32m'; _C_KO=$'\e[31m'; _C_SKIP=$'\e[33m'; _C_TITLE=$'\e[1m'; _C_RST=$'\e[0m'
else
  _C_OK=""; _C_KO=""; _C_SKIP=""; _C_TITLE=""; _C_RST=""
fi

# title "texte" — affiche le titre de l'exercice vérifié
title() {
  printf '%s== %s ==%s\n' "$_C_TITLE" "$1" "$_C_RST"
}

_ok()   { _WB_OK=$((_WB_OK + 1));     printf '  %s[OK]%s   %s\n' "$_C_OK" "$_C_RST" "$1"; }
_ko()   { _WB_KO=$((_WB_KO + 1));     printf '  %s[KO]%s   %s\n' "$_C_KO" "$_C_RST" "$1"; }

# skip "description" "raison" — contrôle non applicable (ex. option non choisie)
skip() {
  _WB_SKIP=$((_WB_SKIP + 1))
  printf '  %s[--]%s   %s (%s)\n' "$_C_SKIP" "$_C_RST" "$1" "${2:-ignoré}"
}

# check_cmd "description" commande [args...]
#   OK si la commande renvoie 0 (exécutée localement sur adm01).
check_cmd() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then _ok "$desc"; else _ko "$desc"; fi
}

# check_output "description" "regex étendue" commande [args...]
#   OK si la sortie (stdout+stderr) de la commande correspond à la regex.
check_output() {
  local desc="$1" regex="$2"; shift 2
  local out
  out="$("$@" 2>&1)" || true
  if grep -Eq -- "$regex" <<<"$out"; then _ok "$desc"; else _ko "$desc"; fi
}

# remote hôte commande — exécute une commande en SSH (sans interaction), renvoie son code.
#   Si hôte vaut « localhost » ou le nom court de la machine courante, la commande est
#   exécutée localement (utile avant que adm01 n'existe : les checks tournent alors sur pve01).
remote() {
  local host="$1"; shift
  if [[ "$host" == "localhost" || "$host" == "$(hostname -s)" ]]; then
    bash -c "$*"
    return
  fi
  # shellcheck disable=SC2086  # WB_SSH_OPTS doit être découpé en mots
  ssh -o BatchMode=yes -o ConnectTimeout="$WB_TIMEOUT" $WB_SSH_OPTS "$host" -- "$@"
}

# check_ssh "description" hôte "commande distante"
#   OK si la commande distante renvoie 0.
check_ssh() {
  local desc="$1" host="$2" cmd="$3"
  if remote "$host" "$cmd" >/dev/null 2>&1; then _ok "$desc"; else _ko "$desc"; fi
}

# check_ssh_output "description" hôte "regex" "commande distante"
check_ssh_output() {
  local desc="$1" host="$2" regex="$3" cmd="$4"
  local out
  out="$(remote "$host" "$cmd" 2>&1)" || true
  if grep -Eq -- "$regex" <<<"$out"; then _ok "$desc"; else _ko "$desc"; fi
}

# check_ping "description" ip
check_ping() {
  local desc="$1" ip="$2"
  if ping -c 2 -W "$WB_TIMEOUT" "$ip" >/dev/null 2>&1; then _ok "$desc"; else _ko "$desc"; fi
}

# check_port "description" hôte port
#   OK si une connexion TCP aboutit.
check_port() {
  local desc="$1" host="$2" port="$3"
  if timeout "$WB_TIMEOUT" bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null; then
    _ok "$desc"
  else
    _ko "$desc"
  fi
}

# check_http "description" url [code_attendu=200] [options curl supplémentaires...]
check_http() {
  local desc="$1" url="$2" expected="${3:-200}"
  shift $(( $# < 3 ? $# : 3 ))
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time "$WB_TIMEOUT" "$@" "$url" 2>/dev/null)" || true
  if [[ "$code" == "$expected" ]]; then _ok "$desc"; else _ko "$desc (HTTP ${code:-aucune réponse})"; fi
}

# check_dns "description" nom type "regex attendue" [serveur]
check_dns() {
  local desc="$1" name="$2" type="$3" regex="$4" server="${5:-}"
  local out
  if [[ -n "$server" ]]; then
    out="$(dig +short +time="$WB_TIMEOUT" "@$server" "$name" "$type" 2>&1)" || true
  else
    out="$(dig +short +time="$WB_TIMEOUT" "$name" "$type" 2>&1)" || true
  fi
  if grep -Eq -- "$regex" <<<"$out"; then _ok "$desc"; else _ko "$desc"; fi
}

# require_cmd outil... — vérifie la présence d'outils sur adm01 avant les contrôles
require_cmd() {
  local c missing=0
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      printf '  %s[!!]%s   outil manquant sur ce poste : %s\n' "$_C_KO" "$_C_RST" "$c"
      missing=1
    fi
  done
  if (( missing )); then
    echo "Installe les outils manquants puis relance la vérification."
    exit 2
  fi
}

# gitlab_api "chemin" — GET sur l'API GitLab v4 avec le jeton en lecture des checks (bloc A).
#   Exemple : gitlab_api "projects/plateforme%2Foutils" | jq -r .default_branch
gitlab_api() {
  local f="${WB_GITLAB_TOKEN_FILE:-$HOME/.config/workbook/gitlab-checks.token}"
  [[ -r "$f" ]] || { echo "jeton GitLab des checks illisible : $f" >&2; return 1; }
  curl -sf --max-time "$WB_TIMEOUT" -H "PRIVATE-TOKEN: $(<"$f")" \
    "${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}/api/v4/$1"
}

# netbox_api "chemin" — GET sur l'API REST NetBox avec le jeton v2 en lecture des checks (M06).
#   Exemple : netbox_api "ipam/prefixes/?prefix=10.10.20.0/24" | jq .count
netbox_api() {
  local f="${WB_NETBOX_TOKEN_FILE:-$HOME/.config/workbook/netbox-checks.token}"
  [[ -r "$f" ]] || { echo "jeton NetBox des checks illisible : $f" >&2; return 1; }
  curl -sf --max-time "$WB_TIMEOUT" -H "Authorization: Bearer $(<"$f")" -H "Accept: application/json" \
    "${WB_NETBOX_URL:-https://nbx01.par1.medisphere.internal}/api/$1"
}

# kube ARGS... — kubectl en LECTURE avec le compte de service des checks (bloc C, M14-E06).
#   Exemple : kube get nodes -o json | jq '.items | length'
kube() {
  local f="${WB_K8S_KUBECONFIG:-$HOME/.config/workbook/k8s-checks.kubeconfig}"
  [[ -r "$f" ]] || { echo "kubeconfig des checks illisible : $f" >&2; return 1; }
  kubectl --kubeconfig "$f" --request-timeout="${WB_TIMEOUT}s" "$@"
}

# harbor_api "chemin" — GET sur l'API Harbor v2.0 avec le robot en lecture des checks (M13-E03).
#   Le fichier WB_HARBOR_CHECKS_FILE contient HARBOR_USER=... et HARBOR_PASSWORD=...
#   Exemple : harbor_api "projects?name=medisphere" | jq -r '.[0].name'
harbor_api() {
  local f="${WB_HARBOR_CHECKS_FILE:-$HOME/.config/workbook/harbor-checks.env}" HARBOR_USER="" HARBOR_PASSWORD=""
  [[ -r "$f" ]] || { echo "identifiants Harbor des checks illisibles : $f" >&2; return 1; }
  # shellcheck disable=SC1090
  source "$f"
  # identifiants passés par un fichier de configuration curl (jamais sur la ligne de commande : visibles par ps)
  curl -sf --max-time "$WB_TIMEOUT" -K <(printf 'user = "%s:%s"\n' "$HARBOR_USER" "$HARBOR_PASSWORD") -H "Accept: application/json" \
    "${WB_HARBOR_URL:-https://registry.par1.medisphere.internal}/api/v2.0/$1"
}

# --- Blocs D et E (PLAN §4.11) : toutes ces fonctions sont des GET en lecture seule ---

# mailpit_api "chemin" — API de Mailpit sur mon01 (M19), compte en lecture des checks.
#   Le fichier WB_MAILPIT_CHECKS_FILE contient MAILPIT_USER=... et MAILPIT_PASSWORD=...
#   Exemple : mailpit_api "search?query=subject:Watchdog" | jq .messages_count
mailpit_api() {
  local f="${WB_MAILPIT_CHECKS_FILE:-$HOME/.config/workbook/mailpit-checks.env}" MAILPIT_USER="" MAILPIT_PASSWORD=""
  [[ -r "$f" ]] || { echo "identifiants Mailpit des checks illisibles : $f" >&2; return 1; }
  # shellcheck disable=SC1090
  source "$f"
  curl -sf --max-time "$WB_TIMEOUT" -K <(printf 'user = "%s:%s"\n' "$MAILPIT_USER" "$MAILPIT_PASSWORD") -H "Accept: application/json" \
    "${WB_MAILPIT_URL:-https://mon01.par1.medisphere.internal:8025}/api/v1/$1"
}

# prom_api "chemin" — API HTTP de Prometheus (Thanos Query, vue globale) du cluster (M21).
#   Exemple : prom_api "query?query=up%7Bjob%3D%22node%22%7D" | jq '.data.result | length'
#   Pour une requête PromQL quelconque, préférer : prom_requete 'expression PromQL'
prom_api() {
  curl -sf --max-time "$WB_TIMEOUT" -H "Accept: application/json" \
    "${WB_PROM_URL:-http://prometheus.apps.par1.medisphere.internal:9090}/api/v1/$1"
}

# prom_requete 'PromQL' — requête instantanée (encodage géré), renvoie le JSON de l'API.
#   Exemple : prom_requete 'sum(up{job="node"} == 0)' | jq -r '.data.result[0].value[1] // "0"'
prom_requete() {
  curl -sf --max-time "$WB_TIMEOUT" -H "Accept: application/json" --data-urlencode "query=$1" \
    "${WB_PROM_URL:-http://prometheus.apps.par1.medisphere.internal:9090}/api/v1/query"
}

# am_api "chemin" — API v2 d'Alertmanager du cluster (M21). Exemple : am_api "alerts?active=true"
am_api() {
  curl -sf --max-time "$WB_TIMEOUT" -H "Accept: application/json" \
    "${WB_AM_URL:-http://alertmanager.apps.par1.medisphere.internal:9093}/api/v2/$1"
}

# grafana_api "chemin" — API HTTP de Grafana avec le jeton du compte de service Viewer des checks (M21).
#   Exemple : grafana_api "search?query=MédiAgenda" | jq length
grafana_api() {
  local f="${WB_GRAFANA_TOKEN_FILE:-$HOME/.config/workbook/grafana-checks.token}"
  [[ -r "$f" ]] || { echo "jeton Grafana des checks illisible : $f" >&2; return 1; }
  curl -sf --max-time "$WB_TIMEOUT" -K <(printf 'header = "Authorization: Bearer %s"\n' "$(<"$f")") \
    -H "Accept: application/json" "${WB_GRAFANA_URL:-https://grafana.apps.par1.medisphere.internal}/api/$1"
}

# loki_api "chemin" [locataire=plateforme] — API de requête de Loki (M22).
#   Exemple : loki_api 'labels' mediagenda | jq '.data'
#   Pour une requête LogQL, préférer : loki_requete '{namespace="mediagenda-prod"}' [locataire] [depuis=1h]
loki_api() {
  curl -sf --max-time "$WB_TIMEOUT" -H "X-Scope-OrgID: ${2:-plateforme}" -H "Accept: application/json" \
    "${WB_LOKI_URL:-http://loki.apps.par1.medisphere.internal:3100}/loki/api/v1/$1"
}

# loki_requete 'LogQL' [locataire=plateforme] [depuis=1h] — requête sur une plage récente.
loki_requete() {
  curl -sf --max-time "$WB_TIMEOUT" -G -H "X-Scope-OrgID: ${2:-plateforme}" -H "Accept: application/json" \
    --data-urlencode "query=$1" --data-urlencode "since=${3:-1h}" --data-urlencode "limit=100" \
    "${WB_LOKI_URL:-http://loki.apps.par1.medisphere.internal:3100}/loki/api/v1/query_range"
}

# --- Bloc F (PLAN §4.12) : lecture seule ---

# keycloak_api "chemin" — API d'administration de Keycloak (royaume medisphere par défaut) avec le
#   compte de service des checks (client « wb-checks » du royaume medisphere, rôles view-realm,
#   view-users, view-clients de realm-management ; flux client_credentials, M24-E05).
#   Le fichier WB_KEYCLOAK_CHECKS_FILE contient KEYCLOAK_CLIENT_ID=... et KEYCLOAK_CLIENT_SECRET=...
#   Exemple : keycloak_api "clients?clientId=grafana" | jq -r '.[0].enabled'
#   Chemin absolu (commençant par /realms/…) : envoyé tel quel (ex. /realms/medisphere/.well-known/openid-configuration).
keycloak_api() {
  local f="${WB_KEYCLOAK_CHECKS_FILE:-$HOME/.config/workbook/keycloak-checks.env}" KEYCLOAK_CLIENT_ID="" KEYCLOAK_CLIENT_SECRET=""
  local base="${WB_KEYCLOAK_URL:-https://sso.par1.medisphere.internal}" royaume="${WB_KEYCLOAK_ROYAUME:-medisphere}" jeton
  if [[ "$1" == /* ]]; then
    curl -sf --max-time "$WB_TIMEOUT" -H "Accept: application/json" "$base$1"
    return
  fi
  [[ -r "$f" ]] || { echo "identifiants Keycloak des checks illisibles : $f" >&2; return 1; }
  # shellcheck disable=SC1090
  source "$f"
  jeton="$(curl -sf --max-time "$WB_TIMEOUT" -K <(printf 'user = "%s:%s"\n' "$KEYCLOAK_CLIENT_ID" "$KEYCLOAK_CLIENT_SECRET") \
    -d grant_type=client_credentials "$base/realms/$royaume/protocol/openid-connect/token" | jq -r '.access_token // empty')" || return 1
  [[ -n "$jeton" ]] || return 1
  curl -sf --max-time "$WB_TIMEOUT" -K <(printf 'header = "Authorization: Bearer %s"\n' "$jeton") -H "Accept: application/json" \
    "$base/admin/realms/$royaume/$1"
}

# ipa_ldap 'filtre' [attributs...] — recherche LDAPS en lecture dans l'annuaire FreeIPA (ipa01, M24)
#   avec le compte système des checks (uid=wb-checks,cn=sysaccounts,cn=etc,<base>).
#   Le fichier WB_IPA_CHECKS_FILE contient IPA_BIND_DN=... et IPA_BIND_PASSWORD=... ; sortie LDIF sans retour à la ligne.
#   Exemple : ipa_ldap '(&(objectClass=posixgroup)(cn=plateforme-admins))' member
ipa_ldap() {
  local f="${WB_IPA_CHECKS_FILE:-$HOME/.config/workbook/ipa-checks.env}" IPA_BIND_DN="" IPA_BIND_PASSWORD="" filtre="$1"
  shift
  [[ -r "$f" ]] || { echo "identifiants LDAP des checks illisibles : $f" >&2; return 1; }
  # shellcheck disable=SC1090
  source "$f"
  # mot de passe par un fichier (-y), jamais sur la ligne de commande
  ldapsearch -LLL -o ldif-wrap=no -o nettimeout="$WB_TIMEOUT" -H "${WB_IPA_URL:-ldaps://ipa01.par1.medisphere.internal}" \
    -D "$IPA_BIND_DN" -y <(printf '%s' "$IPA_BIND_PASSWORD") \
    -b "${WB_IPA_BASE:-dc=par1,dc=medisphere,dc=internal}" "$filtre" "$@"
}

# bao_api "chemin" — API HTTP d'OpenBao (M25) avec l'identité AppRole en lecture des checks (politique
#   « wb-checks » : métadonnées, jamais de valeur de secret). Le jeton obtenu est gardé le temps du check.
#   Le fichier WB_OPENBAO_CHECKS_FILE contient BAO_ROLE_ID=... et BAO_SECRET_ID=...
#   Exemple : bao_api "sys/auth" | jq -r '.data | keys[]'
#   Les chemins sys/health, sys/seal-status et sys/leader sont lus sans jeton.
_WB_BAO_JETON=""
bao_api() {
  local f="${WB_OPENBAO_CHECKS_FILE:-$HOME/.config/workbook/openbao-checks.env}" BAO_ROLE_ID="" BAO_SECRET_ID=""
  local base="${WB_OPENBAO_URL:-https://openbao.par1.medisphere.internal:8200}"
  case "$1" in
    sys/health* | sys/seal-status | sys/leader)
      # sys/health répond 429/472/473/501/503 selon l'état : on renvoie le corps quel que soit le code
      curl -s --max-time "$WB_TIMEOUT" -H "Accept: application/json" "$base/v1/$1"
      return
      ;;
  esac
  if [[ -z "$_WB_BAO_JETON" ]]; then
    [[ -r "$f" ]] || { echo "identifiants OpenBao des checks illisibles : $f" >&2; return 1; }
    # shellcheck disable=SC1090
    source "$f"
    # identifiants passés par l'environnement de jq, jamais en argument (visibles par ps)
    _WB_BAO_JETON="$(BAO_ROLE_ID="$BAO_ROLE_ID" BAO_SECRET_ID="$BAO_SECRET_ID" jq -nc '{role_id: env.BAO_ROLE_ID, secret_id: env.BAO_SECRET_ID}' |
      curl -sf --max-time "$WB_TIMEOUT" --data @- "$base/v1/auth/approle/login" | jq -r '.auth.client_token // empty')" || return 1
    [[ -n "$_WB_BAO_JETON" ]] || return 1
  fi
  curl -sf --max-time "$WB_TIMEOUT" -K <(printf 'header = "X-Vault-Token: %s"\n' "$_WB_BAO_JETON") -H "Accept: application/json" \
    "$base/v1/$1"
}

# summary — affiche le bilan et renvoie 0 si aucun KO
summary() {
  echo
  printf 'Bilan : %s%d OK%s, %s%d KO%s, %d ignoré(s)\n' \
    "$_C_OK" "$_WB_OK" "$_C_RST" "$_C_KO" "$_WB_KO" "$_C_RST" "$_WB_SKIP"
  if (( _WB_KO == 0 )); then
    echo "Exercice validé."
    return 0
  fi
  echo "Exercice non validé : corrige les points en KO puis relance."
  return 1
}
