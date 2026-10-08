#!/usr/bin/env bash
# creer-identite-tofu.sh — M10-E15 (PLAT-1125) : compte de service svc-tofu et application
# credential « tofu-openstack-projets », pour envs/openstack-projets de plateforme/infra.
# À lancer depuis adm01, INTERACTIVEMENT, avec le cloud d'administration. Le mot de passe de
# svc-tofu est tapé (jamais passé en argument) et ne sert qu'à créer l'application credential ;
# le secret de celle-ci va directement dans ~/.config/workbook/openstack-tofu.env (600), jamais
# à l'écran. Idempotent pour le compte et le rôle ; refuse de recréer une application credential
# existante (rotation : la supprimer d'abord, après avoir mis à jour la CI).
#
# Pourquoi admin sur le projet admin (domaine Default) : poser des quotas et créer des ressources
# Neutron pour d'autres projets sont des opérations d'administrateur. Le risque (admin est global)
# est accepté et inscrit au registre des secrets : expiration à 90 jours, secret seulement en CI
# protégée et sur adm01, pas d'option --unrestricted.
set -euo pipefail

ADMIN_CLOUD="${ADMIN_CLOUD:-medisphere-admin}"
ENV_FICHIER="$HOME/.config/workbook/openstack-tofu.env"
NOM_AC=tofu-openstack-projets
os() { openstack --os-cloud "$ADMIN_CLOUD" "$@"; }

if ! os user show --domain Default svc-tofu >/dev/null 2>&1; then
  echo "Création de svc-tofu. Mot de passe : génère-le dans un autre terminal (openssl rand -base64 24)."
  os user create --domain Default --password-prompt \
    --description "OpenTofu : plateforme/infra envs/openstack-projets (M10-E15)" svc-tofu >/dev/null
fi
os role add --user svc-tofu --user-domain Default --project admin --project-domain Default admin

if [[ -s "$ENV_FICHIER" ]]; then
  echo "$ENV_FICHIER existe déjà : application credential non recréée." >&2
  exit 0
fi

# L'application credential se crée EN TANT QUE svc-tofu (Keystone l'impose).
export OS_AUTH_URL="https://openstack.par1.medisphere.internal:5000/v3" OS_IDENTITY_API_VERSION=3 \
       OS_USERNAME=svc-tofu OS_USER_DOMAIN_NAME=Default OS_PROJECT_NAME=admin \
       OS_PROJECT_DOMAIN_NAME=Default OS_CACERT=/usr/local/share/ca-certificates/medisphere-root-ca.crt
read -rsp "Mot de passe de svc-tofu : " OS_PASSWORD
echo
export OS_PASSWORD
expiration="$(date -u -d '+90 days' +%Y-%m-%dT%H:%M:%S)"
rep="$(openstack application credential create --expiration "$expiration" \
         --description "plateforme/infra envs/openstack-projets (PLAT-1125)" -f json "$NOM_AC")"
unset OS_PASSWORD

umask 077
mkdir -p "$(dirname "$ENV_FICHIER")"
{
  echo "# Accès d'OpenTofu à OpenStack (M10-E15). Application credential $NOM_AC, expire le $expiration."
  echo "OS_AUTH_URL=https://openstack.par1.medisphere.internal:5000/v3"
  echo "OS_AUTH_TYPE=v3applicationcredential"
  echo "OS_APPLICATION_CREDENTIAL_ID=$(jq -r .id <<<"$rep")"
  echo "OS_APPLICATION_CREDENTIAL_SECRET=$(jq -r .secret <<<"$rep")"
  echo "OS_REGION_NAME=RegionOne"
  echo "OS_INTERFACE=public"
  echo "OS_CACERT=/usr/local/share/ca-certificates/medisphere-root-ca.crt"
} >"$ENV_FICHIER"
chmod 600 "$ENV_FICHIER"
echo "Écrit : $ENV_FICHIER (600). Identifiant : $(jq -r .id <<<"$rep"), expiration $expiration."
echo "À faire : variables protégées et masquées de plateforme/infra, registre des secrets (alerte J-15)."
echo "Conseil : change maintenant le mot de passe de svc-tofu pour une valeur aléatoire oubliée."
