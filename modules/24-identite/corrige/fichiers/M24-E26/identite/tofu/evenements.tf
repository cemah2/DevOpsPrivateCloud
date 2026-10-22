# tofu/evenements.tf — événements du royaume medisphere (M24-E26, PLAT-2526).
#
# Deux usages distincts :
#   - le JOURNAL (écouteur jboss-logging) : chaque événement part dans journald puis dans Loki
#     (locataire audit), où il est cherché et alerté (FederationLdapEnEchec, bris de glace E28) ;
#   - le STOCKAGE en base (events_enabled) : consultable dans la console (Events) et par l'API,
#     utile pour l'enquête ponctuelle ; borné à 30 jours (la base n'est pas un puits de journaux).
# Les événements d'ADMINISTRATION (qui a changé quoi dans le royaume : OpenTofu, toi) sont stockés
# avec leur contenu (details) : c'est la trace que Sophie demandera.
resource "keycloak_realm_events" "medisphere" {
  realm_id = keycloak_realm.medisphere.id

  events_enabled    = true
  events_expiration = 2592000 # 30 jours, en secondes
  # Liste VIDE = tous les types d'événements utilisateurs (connexions, erreurs, déconnexions…).
  enabled_event_types = []

  admin_events_enabled         = true
  admin_events_details_enabled = true

  # jboss-logging est l'écouteur par défaut ; l'écrire évite qu'un apply le retire.
  events_listeners = ["jboss-logging"]
}
