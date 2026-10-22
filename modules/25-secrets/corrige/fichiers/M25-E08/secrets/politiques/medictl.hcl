# politiques/medictl.hcl — AppRole « medictl » (outil d'exploitation de plateforme/outils, sur adm01)
# (M25-E07, en code en E08). Lire ses propres secrets d'accès, rien d'autre ; le palier 2 ajoute le
# chiffrement par transit (clé medictl-donnees, M25-E17).
path "kv/data/plateforme/medictl/*" {
  capabilities = ["read"]
}
