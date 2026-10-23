#!/usr/bin/env bash
# outils/preuves-depart.sh — tableau de preuves d'un départ (RB-242), en LECTURE SEULE (M24-E46, PLAT-2546).
#
# Usage : outils/preuves-depart.sh <IDENTIFIANT>
#   Interroge chaque source avec les identités de lecture de la revue des accès (M24-E30, variables
#   REVUE_* de l'environnement GitLab lab/revue-acces, ou exportées à la main depuis le Vault, jamais
#   écrites sur la ligne de commande) et écrit un tableau Markdown horodaté sur la sortie standard :
#   annuaire (compte verrouillé, groupes), Keycloak (sessions), GitLab (compte, jetons personnels actifs),
#   Grafana (présence dans l'organisation), Kubernetes (liaisons nominatives), Proxmox VE (compte du royaume).
#   Ne modifie RIEN : il prouve ce que RB-242 a coupé, et dit ce qui reste ouvert.
# Variables : REVUE_LDAP_DN, REVUE_LDAP_MOT_DE_PASSE, REVUE_KEYCLOAK_CLIENT_SECRET, REVUE_GITLAB_TOKEN,
#   REVUE_GRAFANA_TOKEN, REVUE_K8S_TOKEN, REVUE_K8S_CA (chemin), REVUE_K8S_API, REVUE_PVE_TOKEN (« utilisateur!jeton=secret »),
#   REVUE_RACINE (défaut : racine MédiSphère). Une source sans variable est notée « non vérifiée ».
set -euo pipefail

ID="${1:?usage : $0 <IDENTIFIANT>}"
[[ "$ID" =~ ^[a-z0-9._-]+$ ]] || { echo "identifiant invalide : $ID" >&2; exit 2; }
RACINE="${REVUE_RACINE:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
LDAP_URL="${REVUE_LDAP_URL:-ldaps://ipa01.par1.medisphere.internal}"
BASE="dc=par1,dc=medisphere,dc=internal"
SSO="${REVUE_KEYCLOAK_URL:-https://sso.par1.medisphere.internal}"
GITLAB="${REVUE_GITLAB_URL:-https://git01.par1.medisphere.internal}"
GRAFANA="${REVUE_GRAFANA_URL:-https://grafana.apps.par1.medisphere.internal}"
K8S="${REVUE_K8S_API:-https://10.10.40.200:8443}"   # même défaut que revue_acces.py (E30)
PVE="${REVUE_PVE_URL:-https://pve01.par1.medisphere.internal:8006}"

ligne() { printf '| %s | %s | %s |\n' "$1" "$2" "$3"; }
# req CHEMIN_OU_URL [options curl] — GET avec la racine MédiSphère ; en-têtes secrets passés par -K <(…).
req() { curl -sS --fail --max-time 15 --cacert "$RACINE" "$@"; }

echo "## Preuves de départ — $ID — $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo
echo "| Source | Constat | Verdict |"
echo "|---|---|---|"

# --- Annuaire --------------------------------------------------------------------------------------------
if [[ -n "${REVUE_LDAP_DN:-}" && -n "${REVUE_LDAP_MOT_DE_PASSE:-}" ]]; then
  r="$(ldapsearch -LLL -o ldif-wrap=no -H "$LDAP_URL" -D "$REVUE_LDAP_DN" -y <(printf '%s' "$REVUE_LDAP_MOT_DE_PASSE") \
    -b "cn=users,cn=accounts,$BASE" "(uid=$ID)" nsAccountLock memberOf 2>/dev/null || true)"
  if [[ -z "$r" ]]; then
    ligne "Annuaire" "personne introuvable" "**à vérifier** (supprimée ? RB-242 : désactiver, jamais supprimer)"
  else
    verrou="$(sed -n 's/^nsAccountLock: //Ip' <<<"$r" | head -n 1)"
    groupes="$(sed -n 's/^memberOf: cn=\([^,]*\),cn=groups,.*/\1/p' <<<"$r" | grep -vx 'ipausers' | paste -sd, - || true)"
    ligne "Annuaire" "verrouillé : ${verrou:-non} ; groupes : ${groupes:-aucun}" \
      "$([[ "${verrou,,}" == true && -z "$groupes" ]] && echo coupé || echo '**ouvert**')"
  fi
else
  ligne "Annuaire" "REVUE_LDAP_* absentes" "non vérifiée"
fi

# --- Keycloak ----------------------------------------------------------------------------------------------
if [[ -n "${REVUE_KEYCLOAK_CLIENT_SECRET:-}" ]]; then
  jeton="$(req -K <(printf 'user = "revue-acces:%s"\n' "$REVUE_KEYCLOAK_CLIENT_SECRET") -d grant_type=client_credentials \
    "$SSO/realms/medisphere/protocol/openid-connect/token" | jq -r '.access_token // empty')" || jeton=""
  if [[ -n "$jeton" ]]; then
    u="$(req -K <(printf 'header = "Authorization: Bearer %s"\n' "$jeton") \
      "$SSO/admin/realms/medisphere/users?username=$ID&exact=true" | jq -r '.[0].id // empty')" || u=""
    if [[ -z "$u" ]]; then
      ligne "Keycloak" "aucune personne importée" "coupé"
    else
      n="$(req -K <(printf 'header = "Authorization: Bearer %s"\n' "$jeton") \
        "$SSO/admin/realms/medisphere/users/$u/sessions" | jq 'length')" || n="?"
      ligne "Keycloak" "sessions SSO ouvertes : $n" "$([[ "$n" == 0 ]] && echo coupé || echo '**ouvert**')"
    fi
  else
    ligne "Keycloak" "jeton du client revue-acces refusé" "non vérifiée"
  fi
else
  ligne "Keycloak" "REVUE_KEYCLOAK_CLIENT_SECRET absente" "non vérifiée"
fi

# --- GitLab ------------------------------------------------------------------------------------------------
if [[ -n "${REVUE_GITLAB_TOKEN:-}" ]]; then
  g() { req -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$REVUE_GITLAB_TOKEN") "$GITLAB/api/v4/$1"; }
  gu="$(g "users?username=$ID" | jq -c '.[0] // empty')" || gu=""
  if [[ -z "$gu" ]]; then
    ligne "GitLab" "aucun compte" "coupé"
  else
    gid="$(jq -r .id <<<"$gu")"
    etat="$(jq -r .state <<<"$gu")"
    nj="$(g "personal_access_tokens?user_id=$gid&state=active&per_page=100" | jq 'length')" || nj="?"
    ligne "GitLab" "compte : $etat ; jetons personnels actifs : $nj" \
      "$([[ "$nj" == 0 ]] && echo 'coupé (connexion par l'"'"'annuaire)' || echo '**ouvert**')"
  fi
else
  ligne "GitLab" "REVUE_GITLAB_TOKEN absente" "non vérifiée"
fi

# --- Grafana -----------------------------------------------------------------------------------------------
if [[ -n "${REVUE_GRAFANA_TOKEN:-}" ]]; then
  n="$(req -K <(printf 'header = "Authorization: Bearer %s"\n' "$REVUE_GRAFANA_TOKEN") \
    "$GRAFANA/api/org/users/lookup?query=$ID&limit=10" | jq --arg l "$ID" '[.[] | select(.login == $l)] | length')" || n="?"
  ligne "Grafana" "membre de l'organisation principale : $n" \
    "$([[ "$n" == 0 ]] && echo coupé || echo '**à fermer** (sessions et utilisateur, RB-242 étape 4)')"
else
  ligne "Grafana" "REVUE_GRAFANA_TOKEN absente" "non vérifiée"
fi

# --- Kubernetes --------------------------------------------------------------------------------------------
if [[ -n "${REVUE_K8S_TOKEN:-}" && -n "${REVUE_K8S_CA:-}" ]]; then
  # REVUE_K8S_CA : CHEMIN du fichier de l'autorité du cluster (comme pour revue_acces.py).
  n="$(curl -sS --fail --max-time 15 --cacert "$REVUE_K8S_CA" -K <(printf 'header = "Authorization: Bearer %s"\n' "$REVUE_K8S_TOKEN") \
    "$K8S/apis/rbac.authorization.k8s.io/v1/clusterrolebindings" |
    jq --arg u "oidc:$ID" '[.items[] | .subjects[]? | select(.kind == "User" and .name == $u)] | length')" || n="?"
  ligne "Kubernetes" "liaisons nominatives (oidc:$ID) : $n ; accès par groupe : suit l'annuaire au prochain jeton (≤ 5 min)" \
    "$([[ "$n" == 0 ]] && echo coupé || echo '**ouvert**')"
else
  ligne "Kubernetes" "REVUE_K8S_* absentes" "non vérifiée"
fi

# --- Proxmox VE --------------------------------------------------------------------------------------------
if [[ -n "${REVUE_PVE_TOKEN:-}" ]]; then
  e="$(req -K <(printf 'header = "Authorization: PVEAPIToken=%s"\n' "$REVUE_PVE_TOKEN") \
    "$PVE/api2/json/access/users/$ID@medisphere" | jq -r '.data.enable // empty')" || e=""
  ligne "Proxmox VE" "compte $ID@medisphere : ${e:-absent} (1 = actif)" "$([[ "$e" != 1 ]] && echo coupé || echo '**ouvert**')"
else
  ligne "Proxmox VE" "REVUE_PVE_TOKEN absente" "non vérifiée"
fi

echo
echo "Reste ouvert par construction (à écrire au ticket) : certificats SSH déjà émis (≤ 16 h, refusés à l'étape"
echo "account par SSSD), jetons d'accès déjà émis (≤ 5 min), sessions propres des services non fermées par leur API."
