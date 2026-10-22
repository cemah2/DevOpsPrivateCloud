# tofu/imports.tf — reprise dans le code de ce qui a été créé À LA MAIN en M25-E04 à E07 (M25-E08).
# Blocs « import » : relus en MR, appliqués comme le reste ; aucun « tofu import » depuis un poste.
# Identifiants : outils/identifiants-openbao.sh (lecture seule). Une fois le plan suivant vide,
# ce fichier peut être supprimé par une MR : l'état connaît les objets.

import {
  to = vault_mount.kv
  id = "kv"
}

import {
  to = vault_kv_secret_backend_v2.kv
  id = "kv/config"
}

import {
  to = vault_jwt_auth_backend.oidc
  id = "oidc"
}

import {
  to = vault_auth_backend.approle
  id = "approle"
}

import {
  to = vault_jwt_auth_backend_role.personne
  id = "auth/oidc/role/personne"
}

import {
  to = vault_approle_auth_backend_role.wb_checks
  id = "auth/approle/role/wb-checks"
}

import {
  to = vault_approle_auth_backend_role.medictl
  id = "auth/approle/role/medictl"
}

# Politiques : identifiant = nom.
import {
  for_each = fileset("${path.module}/../politiques", "*.hcl")
  to       = vault_policy.acl[each.value]
  id       = trimsuffix(each.value, ".hcl")
}

# Groupes externes et alias : identifiants internes (UUID), donnés par outils/identifiants-openbao.sh.
import {
  for_each = {
    "plateforme-admins" = "<ID-GROUPE-PLATEFORME-ADMINS>"
    "plateforme"        = "<ID-GROUPE-PLATEFORME>"
    "support"           = "<ID-GROUPE-SUPPORT>"
    "securite"          = "<ID-GROUPE-SECURITE>"
    "mediagenda"        = "<ID-GROUPE-MEDIAGENDA>"
  }
  to = vault_identity_group.keycloak[each.key]
  id = each.value
}

import {
  for_each = {
    "plateforme-admins" = "<ID-ALIAS-PLATEFORME-ADMINS>"
    "plateforme"        = "<ID-ALIAS-PLATEFORME>"
    "support"           = "<ID-ALIAS-SUPPORT>"
    "securite"          = "<ID-ALIAS-SECURITE>"
    "mediagenda"        = "<ID-ALIAS-MEDIAGENDA>"
  }
  to = vault_identity_group_alias.keycloak[each.key]
  id = each.value
}
