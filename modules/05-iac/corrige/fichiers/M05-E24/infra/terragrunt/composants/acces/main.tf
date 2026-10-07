# main.tf — composant « acces » : une paire de clés SSH par environnement (M05-E24).
#
# Julien reçoit la clé privée de SON environnement, jamais celle de admin@adm01 : on peut la
# lui donner, et elle disparaît avec l'environnement.
#
# ⚠️ La clé privée est écrite EN CLAIR dans l'état (envs/<env>/acces/terraform.tfstate) :
# c'est le cas de tout secret produit par un provider. « sensitive » la masque à l'écran,
# pas dans l'état. Sophie Laurent le relève en M05-E27 : l'état sera chiffré.
resource "tls_private_key" "env" {
  algorithm = "ED25519"
}
