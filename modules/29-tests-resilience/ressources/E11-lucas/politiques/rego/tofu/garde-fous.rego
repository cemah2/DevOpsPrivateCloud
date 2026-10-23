# Garde-fous sur les plans OpenTofu de plateforme/infra
# Lucas Martin — MR !214 « politiques : garde-fous des plans (PLAT-3011) »
# Repris d'un exemple trouvé sur un blog (il marchait chez eux), adapté à nos plans.
# Lancement : conftest test --namespace tofu -p rego/tofu plan.json
package main.infra

# Les VMs doivent être dans la plage des environnements (2000-2999).
deny[msg] {
	rc := input.resource_changes[_]
	rc.type == "proxmox_virtual_environment_vm"
	vmid := rc.after.vm_id
	vmid < 2000
	msg := "VMID hors plage"
}

deny[msg] {
	rc := input.resource_changes[_]
	rc.type == "proxmox_virtual_environment_vm"
	vmid := rc.after.vm_id
	vmid > 2999
	msg := "VMID hors plage"
}

# Pas de destruction d'une VM du socle.
refuser_destruction[msg] {
	rc := input.resource_changes[_]
	rc.change.actions[0] == "delete"
	rc.change.before.tags[_] == "socle"
	msg := sprintf("destruction de %s interdite", [rc.address])
}

# Le pool doit être « lab ».
warn[msg] {
	rc := input.resource_changes[_]
	rc.type == "proxmox_virtual_environment_vm"
	rc.change.after.pool_id != "lab"
	msg := "mauvais pool"
}

# Toute VM doit être étiquetée « socle ».
deny[msg] {
	rc := input.resource_changes[_]
	rc.type == "proxmox_virtual_environment_vm"
	etiquette := rc.change.after.tags[_]
	etiquette != "socle"
	msg := "étiquette socle manquante"
}
