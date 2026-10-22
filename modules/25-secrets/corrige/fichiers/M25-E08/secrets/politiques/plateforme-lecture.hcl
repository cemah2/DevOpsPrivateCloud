# politiques/plateforme-lecture.hcl — groupes « plateforme » et « support » (M25-E05, en code en E08).
# Voir comment le coffre est configuré et quels secrets existent, sans en lire aucune VALEUR :
# assez pour diagnostiquer (« le secret existe-t-il ? quelle version ? qui peut le lire ? »).
path "sys/mounts" {
  capabilities = ["read"]
}

path "sys/auth" {
  capabilities = ["read"]
}

path "sys/policies/acl" {
  capabilities = ["list"]
}

path "sys/policies/acl/*" {
  capabilities = ["read"]
}

# Métadonnées KV v2 : versions, dates, suppressions ; jamais kv/data/*.
path "kv/metadata/*" {
  capabilities = ["read", "list"]
}

# ATTENTION aux motifs : les membres de plateforme-admins sont AUSSI dans « plateforme ». Entre deux
# politiques, OpenBao ne cumule pas des motifs différents : c'est le motif le PLUS PRÉCIS qui
# s'applique, seul. Un « auth/+/role/+ » en lecture ici masquerait le « auth/+/role/* » en écriture
# de plateforme-admin. On reprend donc EXACTEMENT les motifs de plateforme-admin (même chaîne :
# capacités cumulées), avec des capacités de lecture seulement.
path "auth/+/role/*" {
  capabilities = ["read", "list"]
}

path "identity/*" {
  capabilities = ["read", "list"]
}

# « Qu'est-ce que je peux faire ici ? » (bao token capabilities <chemin>)
path "sys/capabilities-self" {
  capabilities = ["update"]
}
