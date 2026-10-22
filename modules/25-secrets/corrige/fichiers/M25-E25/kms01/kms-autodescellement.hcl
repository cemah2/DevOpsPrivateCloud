# kms01 — politique « kms-autodescellement » (M25-E25). Écrite à la main sur kms01 avec son jeton
# racine initial, consignée ici et dans ~/m25/e25/kms01.md (kms01 n'est pas géré par
# plateforme/secrets : voir le corrigé). Rien d'autre que chiffrer et déchiffrer avec LA clé :
# pas de lecture de la clé (keys/), pas de rotate, pas de rewrap, pas de sys/.
path "transit/encrypt/autodescellement-par1" {
  capabilities = ["update"]
}

path "transit/decrypt/autodescellement-par1" {
  capabilities = ["update"]
}
