# kms01 — politique « kms-autodescellement » (M25-E25 ; référence pour la rétablir en M25-E42, INC-5242).
# Écrite à la main sur kms01 avec son jeton
# racine initial (puis, pour toute réécriture, avec un jeton racine régénéré : M25-E28), consignée ici
# et dans ~/m25/e25/kms01.md (kms01 n'est pas géré par plateforme/secrets : voir le corrigé). Chiffrer et déchiffrer avec LA clé, et garder SON jeton vivant :
#  - encrypt : le seal fait un chiffrement d'essai en se configurant, au démarrage du processus ;
#  - decrypt : déchiffrer la clé racine stockée (core/hsm/barrier-unseal-keys), à chaque descellement ;
#  - renew-self : le jeton est créé « -no-default-policy » ; sans ce droit, le serveur ne peut pas le
#    renouveler (son essai de renouvellement échoue en silence) et le jeton périodique MEURT au bout de
#    sa période (168 h) : la grappe tourne, mais plus aucun nœud ne redémarre. Constaté sur OpenBao
#    2.7.1 : last_renewal_time reste vide sans ce bloc, il suit chaque démarrage avec lui.
# Rien d'autre : pas de lecture de la clé (keys/), pas de rotate, pas de rewrap, pas de sys/.
path "transit/encrypt/autodescellement-par1" {
  capabilities = ["update"]
}

path "transit/decrypt/autodescellement-par1" {
  capabilities = ["update"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
