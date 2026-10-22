# tofu/imports.tf — reprise dans le code de ce qui a été créé À LA MAIN en M24-E05 et M24-E06
# (M24-E08). Blocs « import » (OpenTofu ≥ 1.5) : relus en MR comme le reste, appliqués par le
# pipeline, sans « tofu import » lancé depuis un poste.
# Identifiants : URL de la console (…/clients/<ID>/settings, …/user-federation/ldap/<ID>…) ou
# outils/identifiants-keycloak.sh. Le royaume s'importe par son NOM, le reste par « medisphere/<ID> ».
# Une fois l'import appliqué (plan suivant vide), ce fichier peut être supprimé par une MR : il ne
# sert plus à rien, l'état connaît les objets (le garder ne fait rien de plus).

import {
  to = keycloak_realm.medisphere
  id = "medisphere"
}

import {
  to = keycloak_ldap_user_federation.ipa01
  id = "medisphere/<ID-FEDERATION-IPA01>"
}

import {
  to = keycloak_ldap_group_mapper.groupes_ipa
  id = "medisphere/<ID-FEDERATION-IPA01>/<ID-MAPPEUR-GROUPES>"
}

import {
  to = keycloak_openid_client_scope.groupes
  id = "medisphere/<ID-PORTEE-GROUPES>"
}

import {
  to = keycloak_openid_group_membership_protocol_mapper.groups
  id = "medisphere/client-scope/<ID-PORTEE-GROUPES>/<ID-MAPPEUR-GROUPS>"
}

# Les portées par défaut du royaume s'importent par le nom du royaume.
import {
  to = keycloak_realm_default_client_scopes.defaut
  id = "medisphere"
}

import {
  to = keycloak_openid_client.wb_checks
  id = "medisphere/<ID-CLIENT-WB-CHECKS>"
}

# Rôles du compte de service : medisphere/<ID-UTILISATEUR-DU-COMPTE-DE-SERVICE>/<ID-CLIENT-REALM-MANAGEMENT>/<ID-RÔLE>
import {
  for_each = {
    "view-realm"   = "<ID-ROLE-VIEW-REALM>"
    "view-users"   = "<ID-ROLE-VIEW-USERS>"
    "view-clients" = "<ID-ROLE-VIEW-CLIENTS>"
  }
  to = keycloak_openid_client_service_account_role.wb_checks[each.key]
  id = "medisphere/<ID-COMPTE-DE-SERVICE-WB-CHECKS>/<ID-CLIENT-REALM-MANAGEMENT>/${each.value}"
}

# essai-oidc : importé dans la PREMIÈRE MR (plan vide), puis supprimé par la seconde MR (le bloc
# resource de clients-essai.tf et cet import disparaissent : le plan annonce « 1 to destroy »).
# import {
#   to = keycloak_openid_client.essai_oidc
#   id = "medisphere/<ID-CLIENT-ESSAI-OIDC>"
# }
