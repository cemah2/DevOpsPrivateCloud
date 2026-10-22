# tofu/quotas.tf — quotas de débit (M25-E28, SEC-2628). vault_quota_rate_limit essayé contre OpenBao
# 2.6.4 et 2.7.1 (apply, plan vide, quota qui mord).
#
# Un quota est compté PAR ADRESSE CLIENTE. Il vise un chemin qui commence par un montage existant :
# s'il vise le montage entier (« auth/approle/ »), il frappe aussi la gestion des rôles par OpenTofu
# (essayé : 429 au plan). On vise donc la seule connexion.

# Filet global, large : 200 requêtes par seconde et par client. Les rafales normales (plan OpenTofu,
# démarrage d'ESO, pipeline) restent loin dessous ; une boucle folle est freinée.
resource "vault_quota_rate_limit" "global" {
  name = "global"
  path = ""
  rate = 200
}

# Connexion AppRole : 10 essais par minute et par adresse, puis 5 minutes de blocage. Un secret_id
# volé ou deviné ne s'essaie pas en masse ; aucune machine légitime ne se connecte plus d'une fois
# par minute (checks : un jeton par vérification ; instantanés : un par heure).
resource "vault_quota_rate_limit" "approle_connexion" {
  name           = "approle-connexion"
  path           = "${vault_auth_backend.approle.path}/login"
  rate           = 10
  interval       = 60
  block_interval = 300
}
