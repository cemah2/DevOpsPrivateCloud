# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# _m24-production.sh — fonctions partagées par les checks M24-E24 à M24-E34 (lecture seule).
# Sourcé par les check-EXX.sh du palier 3 (lab/bin/check ne lance que les check-EXX.sh).
# Préfixe _m24p_ : pas de collision avec les autres paliers. Réutilise les fonctions _m24d_* du
# palier 1 (_m24-decouverte.sh : GitLab, annuaire, Keycloak, SSH, découverte OIDC).
# Rappel : les checks tournent sous « set -euo pipefail » (lab/bin/check) : toute commande qui
# peut échouer hors des fonctions check_* est protégée (|| true, ou dans une fonction).
#
# Accès (tous en lecture) :
#   - Keycloak : keycloak_api (client wb-checks, royaume medisphere) ; royaume master par SELECT
#     dans la base sur idp01 (sudo -n -u postgres psql), comme check-E04 ;
#   - VMs : SSH en admin, commandes de consultation (sudo -n en lecture) ;
#   - Proxmox : SSH sur WB_PVE_HOST (root), qm status / pvesh get / pvesm list ;
#   - Prometheus (prom_requete, prom_api), Loki (loki_requete ; ruler par /prometheus/api/v1/rules),
#     témoin de mon01 (WB_M21_TEMOIN_URL), Kubernetes (kube), GitLab (gitlab_api), Mailpit (mailpit_api).
#
# Variables de lab/lab.env (valeurs par défaut) : WB_M24_IPA (ipa01), WB_M24_IDP (idp01),
# WB_PVE_HOST (pve01), WB_M21_TEMOIN_URL (http://mon01.par1.medisphere.internal:9090),
# WB_LOKI_URL, WB_PROM_URL.

# shellcheck source=_m24-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m24-decouverte.sh"

_M24P_PVE="${WB_PVE_HOST:-pve01}"
_M24P_TEMOIN="${WB_M21_TEMOIN_URL:-http://mon01.par1.medisphere.internal:9090}"
_M24P_LOKI="${WB_LOKI_URL:-http://loki.apps.par1.medisphere.internal:3100}"
_M24P_DOC="docs/securite/identite"

# --- Outils génériques -------------------------------------------------------------------------------

# _m24p_compare VALEUR OP SEUIL — comparaison numérique (awk), faux si VALEUR vide ou NaN.
_m24p_compare() {
  [[ -n "$1" && "$1" != NaN ]] && awk -v v="$1" -v s="$3" "BEGIN { exit !(v $2 s) }"
}

# _m24p_aucun REGEX TEXTE — le texte est NON VIDE et aucune de ses lignes ne correspond.
_m24p_aucun() { [[ -n "${2//[[:space:]]/}" ]] && ! grep -Eq -- "$1" <<<"$2"; }

# _m24p_tous TEXTE REGEX… — le texte est non vide et contient chaque REGEX (grep -Ei).
_m24p_tous() {
  local texte="$1" r
  shift
  [[ -n "${texte//[[:space:]]/}" ]] || return 1
  for r in "$@"; do grep -Eqi -- "$r" <<<"$texte" || return 1; done
}

# _m24p_nb_durees TEXTE — nombre de durées en secondes écrites dans le texte (« 12 s », « 3,5 s »).
_m24p_nb_durees() { grep -Eo '[0-9]+([,.][0-9]+)? ?s\b' <<<"$1" | wc -l; }

# _m24p_nb_lignes TEXTE REGEX — nombre de lignes du texte qui correspondent (grep -Eci).
_m24p_nb_lignes() { grep -Eci -- "$2" <<<"$1" || true; }

# _m24p_vide TEXTE — le texte est vide (aucune ligne non blanche).
_m24p_vide() { [[ -z "${1//[[:space:]]/}" ]]; }

# _m24p_sql REQUÊTE — SELECT en lecture dans la base keycloak d'idp01 (sortie brute, vide si erreur).
_m24p_sql() {
  _m24d_ssh "$_M24D_IDP" "cd /tmp && sudo -n -u postgres psql -d keycloak -XtAc \"$1\""
}

# --- GitLab -----------------------------------------------------------------------------------------

# _m24p_arbre PROJET DOSSIER — chemins des fichiers du dossier (récursif) sur main (5 pages au plus).
_m24p_arbre() {
  local p d page
  p="$(_m24d_uri "$1")"
  d="$(_m24d_uri "$2")"
  for page in 1 2 3 4 5; do
    gitlab_api "projects/$p/repository/tree?ref=main&recursive=true&per_page=100&page=$page&path=$d" 2>/dev/null \
      | jq -r '.[] | select(.type == "blob") | .path' 2>/dev/null || true
  done | sort -u
}

# _m24p_doc CHEMIN — contenu d'un fichier de plateforme/medisphere sur main (vide si absent).
_m24p_doc() { _m24d_contenu_main plateforme/medisphere "$1"; }

# _m24p_sans_gabarit TEXTE — le document a été rempli : non vide, sans valeur <N> ni <AAAA-MM-JJ>
# laissée telle quelle (les modèles du corrigé en contiennent).
_m24p_sans_gabarit() {
  [[ -n "${1//[[:space:]]/}" ]] && ! grep -Eq '<N>|<AAAA-MM-JJ>|<HH:MM>|<À REMPLACER' <<<"$1"
}

# _m24p_tofu_tout — concaténation de tous les .tf de plateforme/identite/tofu sur main.
_m24p_tofu_tout() {
  local f
  while IFS= read -r f; do
    [[ "$f" == *.tf ]] && _m24d_contenu_main plateforme/identite "$f"
  done < <(_m24p_arbre plateforme/identite tofu)
}

# --- Proxmox ---------------------------------------------------------------------------------------------

# _m24p_vm_absente VMID — la VM n'existe pas sur l'hyperviseur (qm status échoue avec « does not exist »).
_m24p_vm_absente() {
  local s
  s="$(remote "$_M24P_PVE" "qm status $1" 2>&1)" || true
  grep -qi 'does not exist\|not exist' <<<"$s"
}

# --- Prometheus, Loki, témoin -------------------------------------------------------------------------

# _m24p_valeur 'PromQL' — valeur du premier résultat, ou vide.
_m24p_valeur() {
  prom_requete "$1" 2>/dev/null | jq -r '.data.result[0].value[1] // empty' 2>/dev/null || true
}

# _m24p_alerte_chargee NOM — une règle d'alerte NOM est chargée par Prometheus.
_m24p_alerte_chargee() {
  prom_api "rules?type=alert" 2>/dev/null \
    | jq -e --arg n "$1" 'any(.data.groups[].rules[]; .name == $n)' >/dev/null 2>&1
}

# _m24p_ruler LOCATAIRE — noms des règles d'alerte chargées par le ruler de Loki pour ce locataire.
_m24p_ruler() {
  curl -sf --max-time "$WB_TIMEOUT" -H "X-Scope-OrgID: $1" -H "Accept: application/json" \
    "$_M24P_LOKI/prometheus/api/v1/rules" 2>/dev/null \
    | jq -r '.data.groups[]?.rules[]? | select(.type == "alerting") | .name' 2>/dev/null || true
}

# _m24p_loki_lignes 'LogQL' LOCATAIRE DEPUIS — nombre de lignes renvoyées (plafonné à 100) ; VIDE si
# Loki ne répond pas ou refuse la requête (un « 0 » ne doit jamais venir d'une erreur : faux positif).
_m24p_loki_lignes() {
  local r
  r="$(loki_requete "$1" "$2" "$3" 2>/dev/null)" || r=""
  jq -r 'select(.status == "success") | [.data.result[]?.values[]?] | length' <<<"$r" 2>/dev/null || true
}

# _m24p_temoin_valeur 'PromQL' — valeur du premier résultat sur le Prometheus témoin de mon01.
_m24p_temoin_valeur() {
  curl -sf --max-time "$WB_TIMEOUT" -H "Accept: application/json" --data-urlencode "query=$1" \
    "$_M24P_TEMOIN/api/v1/query" 2>/dev/null | jq -r '.data.result[0].value[1] // empty' 2>/dev/null || true
}

# --- Keycloak --------------------------------------------------------------------------------------------

# _m24p_royaume — représentation du royaume medisphere (wb-checks, view-realm), ou vide.
_m24p_royaume() { _m24d_kc ""; }

# _m24p_clients_metier — clients du royaume SAUF ceux que Keycloak crée lui-même (account,
# account-console, admin-cli, broker, realm-management, security-admin-console) : leurs redirections
# à suffixe (/realms/medisphere/account/*) et le flux direct d'admin-cli sont ceux de Keycloak.
# Les secrets des clients (livrés à view-clients, voir _m24d_kc_client) sont retirés dès la lecture.
_m24p_clients_metier() {
  _m24d_kc "clients?max=500" | jq -c '[.[] | del(.secret) | select(.clientId as $c
    | ["account", "account-console", "admin-cli", "broker", "realm-management", "security-admin-console"]
    | index($c) | not)]' 2>/dev/null || true
}
