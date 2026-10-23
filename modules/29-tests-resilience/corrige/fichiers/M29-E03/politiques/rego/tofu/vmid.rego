# plateforme/politiques — rego/tofu/vmid.rego (M29-E03, PLAT-3003)
# Les VMID respectent les plages de PLAN §4.6 selon l'état (dossier) du plan :
#   - plages explicites : data.plages_vmid[<état>] (socle, envs/k8s…) ;
#   - à défaut, pour un dossier envs/mNN : 2000 + NN*10 à 2000 + NN*10 + 9 (règle du plan) ;
#   - un état inconnu est REFUSÉ (on ne devine pas une plage : on la déclare par MR).
package tofu

plages_etat := data.plages_vmid[data.contexte.etat] if {
	data.plages_vmid[data.contexte.etat]
} else := [[debut, debut + 9]] if {
	regex.match(`^envs/m[0-9]{2}$`, data.contexte.etat)
	debut := 2000 + (10 * to_number(substring(data.contexte.etat, 6, 2)))
}

vmid_autorise(vmid) if {
	some plage in plages_etat
	vmid >= plage[0]
	vmid <= plage[1]
}

deny contains msg if {
	data.contexte.etat
	not plages_etat
	msg := sprintf("état %q sans plage de VMID déclarée : ajoute-la dans rego/donnees/plages-vmid.yaml (PLAN §4.6)", [data.contexte.etat])
}

# Un VMID absent ou calculé : Proxmox prendrait le premier libre, n'importe où (5000, 9000…).
deny contains msg if {
	some rc in vms_creees_ou_modifiees
	not is_number(object.get(rc.change.after, "vm_id", null))
	msg := sprintf("%s : VMID non fixé dans le code (Proxmox choisirait le premier libre)", [rc.address])
}

deny contains msg if {
	some rc in vms_creees_ou_modifiees
	vmid := rc.change.after.vm_id
	is_number(vmid)
	plages_etat
	not vmid_autorise(vmid)
	msg := sprintf("%s : VMID %d hors des plages de l'état %q %v (PLAN §4.6)", [rc.address, vmid, data.contexte.etat, plages_etat])
}
