#!/usr/bin/env bash
# creer-identite-supervision.sh — M10-E26 : identité OpenStack de la sonde ms-verif-openstack.
# À lancer depuis adm01, INTERACTIVEMENT (le mot de passe de svc-supervision est tapé, jamais passé
# en argument), avec le nuage d'administration. Idempotent pour l'utilisateur et les rôles ;
# l'identifiant d'application n'est créé que si secure.yaml ne contient pas encore le nuage
# medisphere-supervision (son secret n'est affiché qu'une fois par Keystone : il va directement
# dans ~/.config/openstack/secure.yaml, jamais à l'écran).
#
# Pourquoi le rôle admin sur le projet admin : en 2026.1, les politiques par défaut de Nova
# réservent la liste des services de calcul (os-services) à l'administrateur ; « reader » ne
# suffit pas. Le risque est borné par les RÈGLES D'ACCÈS de l'identifiant d'application : GET
# seulement, sur les services listés ; un identifiant restreint (non « unrestricted ») ne peut pas
# non plus créer d'autres identifiants d'application.
set -euo pipefail

ADMIN_CLOUD="${ADMIN_CLOUD:-medisphere-admin}"
REGLES="$(dirname "$(readlink -f "$0")")/regles-acces-supervision.json"
SECURE="$HOME/.config/openstack/secure.yaml"
os() { openstack --os-cloud "$ADMIN_CLOUD" "$@"; }

if ! os user show svc-supervision --domain Default >/dev/null 2>&1; then
  echo "Création de svc-supervision. Mot de passe : génère-le dans un autre terminal"
  echo "(openssl rand -base64 24) ; il ne sert qu'à créer l'identifiant d'application."
  os user create svc-supervision --domain Default --password-prompt \
    --description "Sonde ms-verif-openstack (M10-E26)" >/dev/null
fi
os role add --user svc-supervision --user-domain Default --project admin --project-domain Default admin
# La sonde ne doit jamais être verrouillée par la politique de E27 (5 échecs).
os user set --ignore-lockout-failure-attempts --domain Default svc-supervision

if grep -qs 'medisphere-supervision' "$SECURE"; then
  echo "secure.yaml contient déjà medisphere-supervision : identifiant d'application non recréé."
else
  # L'identifiant d'application se crée EN TANT QUE svc-supervision (Keystone l'impose).
  export OS_AUTH_URL="https://openstack.par1.medisphere.internal:5000/v3" OS_IDENTITY_API_VERSION=3 \
         OS_USERNAME=svc-supervision OS_USER_DOMAIN_NAME=Default OS_PROJECT_NAME=admin \
         OS_PROJECT_DOMAIN_NAME=Default OS_CACERT=/usr/local/share/ca-certificates/medisphere-root-ca.crt
  read -rsp "Mot de passe de svc-supervision : " OS_PASSWORD
  echo
  export OS_PASSWORD
  rep="$(openstack application credential create supervision-adm01 --role admin \
           --access-rules "$(<"$REGLES")" --description "Sonde ms-verif-openstack (M10-E26)" -f json)"
  unset OS_PASSWORD
  umask 077
  mkdir -p "$(dirname "$SECURE")"
  entete=""
  [[ -s "$SECURE" ]] || entete="clouds:"$'\n'
  # Ajout en fin de fichier : si secure.yaml a déjà d'autres nuages sous « clouds: », la nouvelle
  # entrée (indentée de deux espaces) s'y range ; relis le fichier après.
  printf '%s  medisphere-supervision:\n    auth:\n      application_credential_secret: "%s"\n' \
    "$entete" "$(jq -r .secret <<<"$rep")" >>"$SECURE"
  chmod 600 "$SECURE"
  echo "identifiant d'application : $(jq -r .id <<<"$rep") — reporte-le dans clouds.yaml (application_credential_id)"
  echo "Conseil : change maintenant le mot de passe de svc-supervision pour une valeur aléatoire oubliée."
fi
echo "Règles d'accès en place :"
os access rule list --user svc-supervision --user-domain Default
