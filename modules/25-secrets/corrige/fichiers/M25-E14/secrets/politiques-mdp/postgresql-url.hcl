# politiques-mdp/postgresql-url.hcl — politique de MOT DE PASSE (pas une ACL) — M25-E14, DEV-2614.
# Les identifiants dynamiques finissent dans une URL postgresql://utilisateur:motdepasse@… (clé « uri »
# du Secret lu par MédiAgenda) : aucun caractère qui demanderait un encodage (« @ », « : », « / »,
# « % », « # »…). 32 caractères alphanumériques ≈ 190 bits d'entropie.
length = 32

rule "charset" {
  charset   = "abcdefghijklmnopqrstuvwxyz"
  min-chars = 1
}

rule "charset" {
  charset   = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  min-chars = 1
}

rule "charset" {
  charset   = "0123456789"
  min-chars = 1
}
