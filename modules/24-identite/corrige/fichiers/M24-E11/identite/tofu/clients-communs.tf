# tofu/clients-communs.tf — ce qui est commun à tous les clients OIDC des services (M24-E11, PLAT-2511).
#
# Portées par DÉFAUT de chaque client, écrites explicitement plutôt qu'héritées du royaume :
#   - le royaume ne les donne qu'aux clients créés APRÈS lui avoir ajouté « groupes » (M24-E06) ; un
#     client recréé dans le même apply que la portée, ou importé, pourrait ne pas l'avoir ;
#   - si quelqu'un retire « groupes » d'un client dans la console, le plan suivant le montre et l'apply
#     le remet (sans elle : plus de revendication groups, plus de droits, M24-E35).
# Les portées SAML de la liste du royaume (role_list, saml_organization, AuthnContextClassRef) ne
# concernent pas un client OpenID Connect.
locals {
  portees_clients_oidc = [
    "acr",
    "basic",
    "email",
    "profile",
    "roles",
    "web-origins",
    keycloak_openid_client_scope.groupes.name,
  ]
}
