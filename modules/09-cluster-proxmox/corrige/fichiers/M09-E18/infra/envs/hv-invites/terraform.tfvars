# terraform.tfvars — environnement hv-invites (M09-E18). Versionné : rien de secret.

cles_ssh_admin = [
  "ssh-ed25519 AAAA…REMPLACE-PAR-TA-CLE-PUBLIQUE… <MOI>@adm01",
]

# rec01 et rec02 sur deux nœuds différents ; le placement fin reste à la HA si on les y inscrit.
vms = {
  rec01 = { vmid = 130, noeud = "hv02" }
  rec02 = { vmid = 131, noeud = "hv03" }
}
