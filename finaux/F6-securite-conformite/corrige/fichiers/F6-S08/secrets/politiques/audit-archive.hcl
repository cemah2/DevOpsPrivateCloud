# politiques/audit-archive.hcl — signature des manifestes de l'archive d'audit (F6-S08, SEC-3608).
# Donnée par le rôle kubernetes « audit-archive » (k8s-par1) au CronJob journaux/audit-archive.
path "transit/sign/audit-archive" {
  capabilities = ["update"]
}
path "auth/token/revoke-self" {
  capabilities = ["update"]
}
# Jamais : lire, régler, exporter ou sauvegarder la clé ; lire un secret.
path "transit/keys/audit-archive*" {
  capabilities = ["deny"]
}
path "transit/export/*" {
  capabilities = ["deny"]
}
