# tofu/autopilot.tf — réglages d'autopilot de la grappe Raft (M25-E24, PLAT-2624).
# vault_raft_autopilot (fournisseur hashicorp/vault 5.13) écrit sys/storage/raft/autopilot/configuration :
# essayé contre OpenBao 2.6.4 et 2.7.1 (apply, puis plan vide).
#
# ⚠️ Les durées s'écrivent comme OpenBao les RELIT (« 24h0m0s », « 10s ») : écrire « 24h » donne
# un plan qui veut changer « 24h0m0s » → « 24h » à chaque passage (différence perpétuelle).
#
# Choix :
# - cleanup_dead_servers = true et min_quorum = 3 : autopilot ne retire JAMAIS un pair si la grappe
#   tomberait sous trois serveurs. Dans une grappe de trois, il ne retire donc rien tout seul : c'est
#   voulu (un nœud arrêté pour maintenance ou une VM restaurée depuis PBS doit retrouver sa place) ;
#   le nettoyage ne servira que si la grappe grandit (cinq nœuds : un mort sera retiré, la grappe
#   restera à quatre électeurs). Retirer un pair à la main : « bao operator raft remove-peer » (RB-251).
# - dead_server_last_contact_threshold = 24 h (valeur par défaut, explicite) : une nuit de panne ne
#   suffit pas à déclarer un nœud mort.
# - server_stabilization_time = 10 s : un nouveau nœud reste non électeur tant qu'il n'a pas été sain
#   10 s (rattrapage des journaux) ; c'est ce qu'on voit dans list-peers juste après un join.
resource "vault_raft_autopilot" "grappe" {
  cleanup_dead_servers               = true
  min_quorum                         = 3
  dead_server_last_contact_threshold = "24h0m0s"
  last_contact_threshold             = "10s"
  max_trailing_logs                  = 1000
  server_stabilization_time          = "10s"
}
