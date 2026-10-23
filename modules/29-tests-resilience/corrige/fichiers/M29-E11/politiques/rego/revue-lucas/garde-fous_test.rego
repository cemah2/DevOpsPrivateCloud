# plateforme/politiques — rego/revue-lucas/garde-fous_test.rego (M29-E11, version corrigée)
# (9) Chaque règle a un cas ACCEPTÉ et un cas REFUSÉ : un test qui ne vérifie que le plan correct
# reste vert quand la règle ne se déclenche jamais (c'était le cas de la MR !214).
#   opa test rego/revue-lucas -v
package tofu_lucas_test

import data.tofu

vm(actions, avant, apres) := {"resource_changes": [{
	"address": "module.a.proxmox_virtual_environment_vm.vm",
	"mode": "managed",
	"type": "proxmox_virtual_environment_vm",
	"change": {"actions": actions, "before": avant, "after": apres},
}]}

ok := {"vm_id": 2291, "pool_id": "lab", "tags": ["env-m29"]}

test_plan_correct_accepte if {
	count(tofu.deny) == 0 with input as vm(["create"], null, ok) with data.contexte as {"etat": "envs/m29"}
}

test_vmid_hors_plage_refuse if {
	some msg in tofu.deny with input as vm(["create"], null, object.union(ok, {"vm_id": 5001}))
		with data.contexte as {"etat": "envs/m29"}
	contains(msg, "VMID 5001")
}

test_vmid_environnement_refuse_dans_le_socle if {
	some msg in tofu.deny with input as vm(["create"], null, {"vm_id": 2291, "pool_id": "lab", "tags": ["socle"]})
		with data.contexte as {"etat": "socle"}
	contains(msg, "VMID 2291")
}

test_pool_absent_refuse if {
	some msg in tofu.deny with input as vm(["create"], null, object.remove(ok, ["pool_id"]))
		with data.contexte as {"etat": "envs/m29"}
	contains(msg, "pool null")
}

test_sans_etiquette_refuse if {
	some msg in tofu.deny with input as vm(["create"], null, object.union(ok, {"tags": ["role-dns"]}))
		with data.contexte as {"etat": "envs/m29"}
	contains(msg, "ni « socle »")
}

test_remplacement_socle_refuse_dans_les_deux_ordres if {
	socle := {"vm_id": 1008, "pool_id": "lab", "tags": ["role-dns", "socle"]}
	some m1 in tofu.deny with input as vm(["delete", "create"], socle, socle) with data.contexte as {"etat": "socle"}
	contains(m1, "remplacement")
	some m2 in tofu.deny with input as vm(["create", "delete"], socle, socle) with data.contexte as {"etat": "socle"}
	contains(m2, "remplacement")
}

test_remplacement_socle_autorise_par_etiquette if {
	socle := {"vm_id": 1008, "pool_id": "lab", "tags": ["role-dns", "socle"]}
	count(tofu.deny) == 0 with input as vm(["delete", "create"], socle, socle)
		with data.contexte as {"etat": "socle", "etiquettes_mr": ["destruction-autorisee"]}
}
