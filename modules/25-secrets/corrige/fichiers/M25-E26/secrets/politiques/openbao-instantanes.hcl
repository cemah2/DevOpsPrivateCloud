# politiques/openbao-instantanes.hcl — AppRole des instantanés horaires (M25-E26, SEC-2626).
# bao operator raft snapshot save = GET sys/storage/raft/snapshot : rien d'autre. Pas de restore
# (sys/storage/raft/snapshot en update, ou snapshot-force) : restaurer est un geste humain (RB-252).
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}
