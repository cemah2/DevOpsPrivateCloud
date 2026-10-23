# plateforme/politiques — rego/revue-lucas/garde-fous.rego (M29-E11, version corrigée de la MR !214)
# Corrigée ligne à ligne pour la revue ; la cible reste rego/tofu/ (M29-E03), qui couvre déjà ces
# intentions avec les plages par état : cette version sert à MONTRER chaque correction à Lucas.
# Défauts corrigés (numéros de REVUE.md) : 1 syntaxe v0, 2 paquet hors de --namespace tofu, 3 chemin
# rc.after, 4 plage unique 2000-2999, 5 règle au nom ignoré par conftest, 6 seule la première action lue, 7 pool en warn et champ
# absent, 8 itération qui refuse toute VM ayant une autre étiquette.
package tofu

lucas_vms contains rc if {
	some rc in input.resource_changes
	rc.type == "proxmox_virtual_environment_vm"
	rc.mode == "managed"
	some action in rc.change.actions
	action in {"create", "update"}
}

# (3, 4) Chemin change.after ; plage selon l'état (contexte du job), pas une seule plage pour tous.
lucas_plage := [1000, 1099] if {
	data.contexte.etat == "socle"
} else := [2000, 2999]

deny contains msg if {
	some rc in lucas_vms
	vmid := object.get(rc.change.after, "vm_id", null)
	not lucas_dans_plage(vmid)
	msg := sprintf("%s : VMID %v hors de %v", [rc.address, vmid, lucas_plage])
}

lucas_dans_plage(vmid) if {
	is_number(vmid)
	vmid >= lucas_plage[0]
	vmid <= lucas_plage[1]
}

# (5, 6) Une règle « deny » (seuls deny/warn/violation sont lus) ; un remplacement, quel que soit
# l'ordre (["delete","create"] ou ["create","delete"]), est une destruction.
deny contains msg if {
	some rc in input.resource_changes
	rc.type == "proxmox_virtual_environment_vm"
	"delete" in rc.change.actions
	"socle" in object.get(rc.change.before, "tags", [])
	not "destruction-autorisee" in object.get(data.contexte, "etiquettes_mr", [])
	msg := sprintf("%s : destruction ou remplacement d'une VM du socle sans l'étiquette de MR destruction-autorisee", [rc.address])
}

# (7) Le pool est une exigence (deny), et un champ ABSENT est un écart (object.get), pas un silence.
deny contains msg if {
	some rc in lucas_vms
	object.get(rc.change.after, "pool_id", null) != "lab"
	msg := sprintf("%s : pool %v au lieu de « lab »", [rc.address, object.get(rc.change.after, "pool_id", null)])
}

# (8) « Toute VM étiquetée socle » était faux (VMs d'environnement) ET mal écrit (refusait toute VM
# ayant une étiquette autre que socle). Exigence corrigée : socle OU env-…, testée sur l'ensemble.
deny contains msg if {
	some rc in lucas_vms
	etiquettes := object.get(rc.change.after, "tags", [])
	not "socle" in etiquettes
	count([e | some e in etiquettes; startswith(e, "env-")]) == 0
	msg := sprintf("%s : ni « socle » ni « env-… » (étiquettes : %v)", [rc.address, etiquettes])
}
