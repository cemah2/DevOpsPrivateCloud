#!/usr/bin/env bash
# =============================================================================
# outils/ranger-secret-client.sh — plateforme/identite (M24-E11, PLAT-2511 ; resservi par chaque
# client OIDC du palier 2 et par la rotation des secrets, M24-E29).
#
# Range le secret d'un client confidentiel du royaume medisphere dans l'Ansible Vault « critique »
# secrets/identite.yml de plateforme/ansible, clé keycloak_secrets_clients.<client> (tiret → « _ »),
# SANS jamais l'afficher, l'écrire en clair sur disque ni le passer en argument d'une commande.
#
#   outils/ranger-secret-client.sh <client>              lit le secret dans Keycloak et le range
#   outils/ranger-secret-client.sh --verifier <client>   compare Keycloak et le Vault (empreintes)
#
# Accès : client svc-tofu-keycloak du royaume master (~/.config/workbook/keycloak-tofu.env, 600 :
#   KEYCLOAK_CLIENT_ID, KEYCLOAK_CLIENT_SECRET). Il a manage-clients sur medisphere : c'est le
#   droit qu'exige la lecture d'un secret de client depuis Keycloak 26.8 (view-clients ne suffit plus).
# Variables : KEYCLOAK_URL (https://sso.par1.medisphere.internal), MS_ANSIBLE_DIR (~/src/ansible),
#   MS_VAULT_ID (critique@$MS_ANSIBLE_DIR/outils/vault-pass-client.sh), CA (racine du lab).
# Prérequis : curl, jq, yq (mikefarah), uv et l'environnement de plateforme/ansible (ansible-vault).
# Après usage : MR dans plateforme/ansible pour secrets/identite.yml (fichier chiffré).
# Ne jamais lancer avec « bash -x ». Codes : 0 rangé ou identique ; 1 écart ou échec ; 2 usage.
# =============================================================================
set -Eeuo pipefail
umask 077
# shellcheck disable=SC2016  # « $ANSIBLE_VAULT » est le texte littéral de l'en-tête Ansible Vault
ENTETE_VAULT='^\$ANSIBLE_VAULT;1\.2;AES256;critique$'

usage() { sed -n '3,21p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
die() { echo "ranger-secret-client : $*" >&2; exit 1; }

verifier=0
if [[ "${1:-}" == --verifier ]]; then verifier=1; shift; fi
client="${1:-}"
[[ "$client" =~ ^[a-z][a-z0-9-]{1,40}$ ]] || usage
cle="${client//-/_}"

url="${KEYCLOAK_URL:-https://sso.par1.medisphere.internal}"
ca="${CA:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
acces="$HOME/.config/workbook/keycloak-tofu.env"
ansible_dir="${MS_ANSIBLE_DIR:-$HOME/src/ansible}"
vault_id="${MS_VAULT_ID:-critique@$ansible_dir/outils/vault-pass-client.sh}"
fichier="$ansible_dir/secrets/identite.yml"

for outil in curl jq yq uv sha256sum; do
  command -v "$outil" >/dev/null || die "$outil absent"
done
yq --version 2>/dev/null | grep -q mikefarah || die "yq de mikefarah attendu (le paquet Debian « yq » est un autre outil)"
[[ -r "$acces" && "$(stat -c %a "$acces")" == 600 ]] || die "$acces absent ou pas en 600"
[[ -d "$ansible_dir/.git" ]] || die "$ansible_dir n'est pas un clone de plateforme/ansible"

KEYCLOAK_CLIENT_ID="" KEYCLOAK_CLIENT_SECRET=""
# shellcheck source=/dev/null
. "$acces"
[[ -n "$KEYCLOAK_CLIENT_ID" && -n "$KEYCLOAK_CLIENT_SECRET" ]] || die "identifiants incomplets dans $acces"

# Jeton du compte d'OpenTofu (royaume master) : identifiants par un fichier anonyme (-K), jamais en argument.
jeton="$(curl -sf --cacert "$ca" -K <(printf 'user = "%s:%s"\n' "$KEYCLOAK_CLIENT_ID" "$KEYCLOAK_CLIENT_SECRET") \
  -d grant_type=client_credentials "$url/realms/master/protocol/openid-connect/token" | jq -r '.access_token // empty')" \
  || die "jeton refusé (secret de svc-tofu-keycloak, ou /realms/master filtré par HAProxy hors MGMT)"
[[ -n "$jeton" ]] || die "jeton vide"

api() {
  curl -sf --cacert "$ca" -K <(printf 'header = "Authorization: Bearer %s"\n' "$jeton") \
    "$url/admin/realms/medisphere/$1"
}

representation="$(api "clients?clientId=$client" | jq -c '.[0] // empty')" || die "API d'administration illisible"
[[ -n "$representation" ]] || die "client $client absent du royaume medisphere (apply d'OpenTofu fait ?)"
[[ "$(jq -r '.publicClient' <<<"$representation")" == false ]] || die "$client est un client public : il n'a pas de secret"
id="$(jq -r '.id' <<<"$representation")"

# Le secret ne quitte jamais une variable du script.
SECRET_CLIENT="$(api "clients/$id/client-secret" | jq -r '.value // empty')" || die "lecture du secret refusée (manage-clients ?)"
[[ ${#SECRET_CLIENT} -ge 32 ]] || die "secret de $client vide ou trop court"
export SECRET_CLIENT

# Contenu actuel du Vault (vide si le fichier n'existe pas encore), en mémoire seulement.
contenu=""
if [[ -f "$fichier" ]]; then
  head -n 1 "$fichier" | grep -q "$ENTETE_VAULT" \
    || die "$fichier n'est pas chiffré sous l'identité « critique » : arrêt"
  contenu="$(cd "$ansible_dir" && uv run ansible-vault view --vault-id "$vault_id" "$fichier")" \
    || die "déchiffrement impossible ($vault_id)"
fi

empreinte() { sha256sum | cut -c1-16; }

if ((verifier)); then
  e_kc="$(printf '%s' "$SECRET_CLIENT" | empreinte)"
  e_vault="$(yq -r ".keycloak_secrets_clients.$cle // \"\"" <<<"$contenu" | tr -d '\n' | empreinte)"
  if [[ "$e_kc" == "$e_vault" ]]; then
    echo "[OK] $client : le secret du Vault est celui de Keycloak ($e_kc…)"
    exit 0
  fi
  echo "[KO] $client : le Vault ($e_vault…) diffère de Keycloak ($e_kc…)"
  exit 1
fi

# Nouveau contenu : la valeur vient de l'environnement (strenv), jamais de la ligne de commande.
[[ -n "$contenu" ]] || contenu='{}'
nouveau="$(yq ".keycloak_secrets_clients.$cle = strenv(SECRET_CLIENT)" <<<"$contenu")" \
  || die "yq n'a pas pu poser la clé"
mkdir -p "$(dirname "$fichier")"
tmp="$(mktemp "$fichier.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
if ! printf '%s\n' "$nouveau" | (cd "$ansible_dir" && uv run ansible-vault encrypt --vault-id "$vault_id" \
  --encrypt-vault-id critique --output "$tmp" - 2>/dev/null); then
  die "chiffrement impossible"
fi
head -n 1 "$tmp" | grep -q "$ENTETE_VAULT" || die "fichier chiffré inattendu : rien n'est remplacé"
mv -f "$tmp" "$fichier"
trap - EXIT
unset SECRET_CLIENT
echo "[OK] secret de $client rangé dans $fichier (clé keycloak_secrets_clients.$cle). MR dans plateforme/ansible."
