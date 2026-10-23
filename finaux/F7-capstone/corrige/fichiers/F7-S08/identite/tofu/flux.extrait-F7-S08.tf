# tofu/flux.tf — EXTRAIT (F7-S08, PLAT-3708) : le flux navigateur-medisphere du M24-E21 REFUSE les
# utilisateurs « client-externe » (agents fédérés du GHSV) sur tous les clients qui l'utilisent
# (GitLab, Argo CD, Grafana, Harbor, Kubernetes, Proxmox, NetBox, OAuth2 Proxy interne, portail…).
#
# Pourquoi c'est nécessaire : un agent qui s'est connecté pour MédiAgenda a une session SSO dans le
# royaume medisphere. Sans ce refus, l'exécution « Cookie » de navigateur-medisphere l'authentifierait
# en silence sur n'importe quel client interne ; seuls les contrôles propres à chaque service (groupes
# exigés) le retiendraient… ou pas (création de compte à la volée, rôle par défaut).
#
# Règle de Keycloak : dans un même niveau, des exécutions REQUIRED ou CONDITIONAL font IGNORER les
# ALTERNATIVE voisines. On ne peut donc pas ajouter le refus à côté de « Cookie » et des formulaires :
# on les range dans un sous-flux « authentification » (REQUIRED), suivi du sous-flux de refus
# (CONDITIONAL). Nouvelle structure :
#
#   navigateur-medisphere
#   ├── navigateur-medisphere-authentification                      REQUIRED
#   │   ├── Cookie (auth-cookie)                                     ALTERNATIVE
#   │   └── navigateur-medisphere-formulaires                        ALTERNATIVE  (inchangé, M24-E21)
#   └── navigateur-medisphere-refus-externes                         CONDITIONAL
#       ├── Condition - user role (client-externe)                   REQUIRED
#       └── Deny access (deny-access-authenticator)                  REQUIRED
#
# ⚠️ Changement du flux de TOUT le royaume : appliqué par MR, plan relu, essai sur une copie du
# royaume (export/import dans idp02 du M24 ou un royaume d'essai) ; retour arrière immédiat : RB du
# M24-E21 (browser_flow = "browser", ou console d'administration master → Bind flow).
#
# Modifications de flux.tf :
#   1. keycloak_authentication_execution.cookie : parent_flow_alias =
#        keycloak_authentication_subflow.authentification.alias
#   2. keycloak_authentication_subflow.formulaires : parent_flow_alias =
#        keycloak_authentication_subflow.authentification.alias
#   3. ajouter les ressources ci-dessous ;
#   4. keycloak_authentication_bindings.medisphere : ajouter à depends_on
#        keycloak_authentication_execution.refus et keycloak_authentication_execution_config.refus_condition.
# Note : changer le parent d'une exécution la RECRÉE (plan : destroy + create). Le flux reste lié au
# royaume pendant l'apply ; fais-le dans une fenêtre, comme au M24-E21.

resource "keycloak_authentication_subflow" "authentification" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_flow.navigateur.alias
  alias             = "navigateur-medisphere-authentification"
  description       = "Session existante ou formulaires (structure du M24-E21)"
  provider_id       = "basic-flow"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_subflow" "refus_externes" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_flow.navigateur.alias
  alias             = "navigateur-medisphere-refus-externes"
  description       = "Refuse les utilisateurs fédérés d'un client (rôle client-externe) sur les clients internes (F7-S08)"
  provider_id       = "basic-flow"
  requirement       = "CONDITIONAL"
  priority          = 20
}

resource "keycloak_authentication_execution" "refus_condition" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_subflow.refus_externes.alias
  authenticator     = "conditional-user-role"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_execution_config" "refus_condition" {
  realm_id     = keycloak_realm.medisphere.id
  execution_id = keycloak_authentication_execution.refus_condition.id
  alias        = "porte-client-externe"
  config = {
    condUserRole = keycloak_role.client_externe.name
    negate       = "false"
  }
}

resource "keycloak_authentication_execution" "refus" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_subflow.refus_externes.alias
  authenticator     = "deny-access-authenticator"
  requirement       = "REQUIRED"
  priority          = 20
}
