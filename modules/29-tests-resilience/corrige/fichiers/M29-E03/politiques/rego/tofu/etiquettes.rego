# plateforme/politiques — rego/tofu/etiquettes.rego (M29-E03, PLAT-3003)
# Étiquettes Proxmox obligatoires (PLAN §4.8) : elles alimentent l'inventaire Ansible (NetBox,
# Proxmox) et les sources de données OpenTofu. Une VM sans étiquette n'est ni configurée, ni
# supervisée, ni nettoyée.
#   - état « socle » : « socle » ET au moins un « role-<rôle> » ;
#   - état « envs/mNN » : « env-mNN » du même module ;
#   - autre environnement (envs/k8s…) : au moins un « env-… » ;
#   - jamais « socle » hors de l'état socle (la VM entrerait dans l'inventaire et les protections
#     du socle sans en être).
package tofu

deny contains msg if {
	data.contexte.etat == "socle"
	some rc in vms_creees_ou_modifiees
	not "socle" in etiquettes_apres(rc)
	msg := sprintf("%s : VM de l'état socle sans l'étiquette « socle » (étiquettes : %v)", [rc.address, etiquettes_apres(rc)])
}

deny contains msg if {
	data.contexte.etat == "socle"
	some rc in vms_creees_ou_modifiees
	count([e | some e in etiquettes_apres(rc); startswith(e, "role-")]) == 0
	msg := sprintf("%s : VM du socle sans étiquette « role-<rôle> » (étiquettes : %v)", [rc.address, etiquettes_apres(rc)])
}

deny contains msg if {
	regex.match(`^envs/m[0-9]{2}$`, data.contexte.etat)
	attendue := concat("", ["env-", substring(data.contexte.etat, 5, 3)])
	some rc in vms_creees_ou_modifiees
	not attendue in etiquettes_apres(rc)
	msg := sprintf("%s : étiquette « %s » absente (étiquettes : %v)", [rc.address, attendue, etiquettes_apres(rc)])
}

deny contains msg if {
	data.contexte.etat != "socle"
	not regex.match(`^envs/m[0-9]{2}$`, data.contexte.etat)
	some rc in vms_creees_ou_modifiees
	count([e | some e in etiquettes_apres(rc); startswith(e, "env-")]) == 0
	msg := sprintf("%s : VM d'environnement sans étiquette « env-… » (étiquettes : %v)", [rc.address, etiquettes_apres(rc)])
}

deny contains msg if {
	data.contexte.etat != "socle"
	some rc in vms_creees_ou_modifiees
	"socle" in etiquettes_apres(rc)
	msg := sprintf("%s : étiquette « socle » sur une VM de l'état %q", [rc.address, data.contexte.etat])
}
