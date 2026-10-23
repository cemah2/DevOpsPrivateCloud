# plateforme/politiques — rego/tofu/tofu_test.rego (M29-E03, PLAT-3003)
# Tests unitaires des règles du paquet « tofu » : chaque règle a au moins un cas qui passe et un
# cas qui échoue (une règle qui ne peut pas échouer ne vérifie rien).
#   opa test rego/tofu rego/donnees -v
#   conftest verify -p rego/tofu --data rego/donnees
# Les plans sont réduits au strict nécessaire (resource_changes) : la forme vient d'un vrai
# « tofu show -json » (OpenTofu 1.13, bpg/proxmox 0.116), voir rego/exemples/.
package tofu_test

import data.tofu

# --- Fabriques de plans --------------------------------------------------------------------
vm(adresse, actions, avant, apres) := {
	"address": adresse,
	"mode": "managed",
	"type": "proxmox_virtual_environment_vm",
	"name": "vm",
	"change": {"actions": actions, "before": avant, "after": apres},
}

attributs(nom, vmid, pool, etiquettes) := {"name": nom, "vm_id": vmid, "pool_id": pool, "tags": etiquettes}

plan(changements) := {"format_version": "1.2", "resource_changes": changements}

cree(nom, vmid, pool, etiquettes) := vm(sprintf("module.%s.proxmox_virtual_environment_vm.vm", [nom]), ["create"], null, attributs(nom, vmid, pool, etiquettes))

ctx_m29 := {"etat": "envs/m29"}

ctx_socle := {"etat": "socle", "etiquettes_mr": []}

# --- Contexte -------------------------------------------------------------------------------
test_contexte_absent_refuse if {
	some msg in tofu.deny with input as plan([cree("m29-a", 2291, "lab", ["env-m29"])])
		with data.contexte as {}
	contains(msg, "contexte absent")
}

# --- VMID -----------------------------------------------------------------------------------
test_vmid_dans_la_plage_generale if {
	count(tofu.deny) == 0 with input as plan([cree("m29-a", 2291, "lab", ["env-m29"])])
		with data.contexte as ctx_m29
}

test_vmid_bornes_incluses if {
	count(tofu.deny) == 0 with input as plan([cree("m29-a", 2290, "lab", ["env-m29"]), cree("m29-b", 2299, "lab", ["env-m29"])])
		with data.contexte as ctx_m29
}

test_vmid_hors_plage_refuse if {
	some msg in tofu.deny with input as plan([cree("m29-a", 2300, "lab", ["env-m29"])])
		with data.contexte as ctx_m29
	contains(msg, "VMID 2300 hors des plages")
}

test_vmid_non_fixe_refuse if {
	some msg in tofu.deny with input as plan([cree("m29-a", null, "lab", ["env-m29"])])
		with data.contexte as ctx_m29
	contains(msg, "VMID non fixé")
}

test_plage_explicite_l_emporte if {
	count(tofu.deny) == 0 with input as plan([cree("k8s-w01", 2144, "lab", ["env-k8s", "role-k8s-worker"])])
		with data.contexte as {"etat": "envs/k8s"}
		with data.plages_vmid as {"envs/k8s": [[2140, 2149]]}
}

test_socle_hors_plage_refuse if {
	some msg in tofu.deny with input as plan([cree("dns03", 2063, "lab", ["socle", "role-dns"])])
		with data.contexte as ctx_socle
		with data.plages_vmid as {"socle": [[1000, 1099]]}
	contains(msg, "VMID 2063 hors des plages")
}

test_etat_inconnu_refuse if {
	some msg in tofu.deny with input as plan([cree("x", 2291, "lab", ["env-x"])])
		with data.contexte as {"etat": "envs/nouveau"}
		with data.plages_vmid as {}
	contains(msg, "sans plage de VMID déclarée")
}

# --- Pool -----------------------------------------------------------------------------------
test_pool_absent_refuse if {
	some msg in tofu.deny with input as plan([cree("m29-a", 2291, null, ["env-m29"])])
		with data.contexte as ctx_m29
	contains(msg, "au lieu de « lab »")
}

test_pool_autre_refuse if {
	some msg in tofu.deny with input as plan([cree("m29-a", 2291, "perso", ["env-m29"])])
		with data.contexte as ctx_m29
	contains(msg, "pool Proxmox perso au lieu")
}

# --- Étiquettes -----------------------------------------------------------------------------
test_etiquette_env_absente_refusee if {
	some msg in tofu.deny with input as plan([cree("m29-a", 2291, "lab", ["env-m28"])])
		with data.contexte as ctx_m29
	contains(msg, "« env-m29 » absente")
}

test_socle_sans_role_refuse if {
	some msg in tofu.deny with input as plan([cree("dns03", 1050, "lab", ["socle"])])
		with data.contexte as ctx_socle
		with data.plages_vmid as {"socle": [[1000, 1099]]}
	contains(msg, "sans étiquette « role-<rôle> »")
}

test_socle_conforme if {
	count(tofu.deny) == 0 with input as plan([cree("dns03", 1050, "lab", ["role-dns", "socle"])])
		with data.contexte as ctx_socle
		with data.plages_vmid as {"socle": [[1000, 1099]]}
}

test_etiquette_socle_hors_socle_refusee if {
	some msg in tofu.deny with input as plan([cree("m29-a", 2291, "lab", ["env-m29", "socle"])])
		with data.contexte as ctx_m29
	contains(msg, "étiquette « socle » sur une VM")
}

test_autre_environnement_sans_env_refuse if {
	some msg in tofu.deny with input as plan([cree("k8s-w01", 2144, "lab", ["role-k8s-worker"])])
		with data.contexte as {"etat": "envs/k8s"}
		with data.plages_vmid as {"envs/k8s": [[2140, 2149]]}
	contains(msg, "sans étiquette « env-… »")
}

# --- Destructions ---------------------------------------------------------------------------
remplacement_socle := vm(
	"module.dns02.proxmox_virtual_environment_vm.vm",
	["delete", "create"],
	attributs("dns02", 1008, "lab", ["role-dns", "socle"]),
	attributs("dns02", 1018, "lab", ["role-dns", "socle"]),
)

destruction_essai := vm(
	"module.essai.proxmox_virtual_environment_vm.vm",
	["delete"],
	attributs("m29-a", 2291, "lab", ["env-m29"]),
	null,
)

test_remplacement_socle_refuse_sans_etiquette if {
	some msg in tofu.deny with input as plan([remplacement_socle])
		with data.contexte as ctx_socle
		with data.plages_vmid as {"socle": [[1000, 1099]]}
	contains(msg, "le plan remplace une VM du socle (dns02)")
}

test_remplacement_socle_autorise_par_etiquette if {
	count(tofu.deny) == 0 with input as plan([remplacement_socle])
		with data.contexte as {"etat": "socle", "etiquettes_mr": ["destruction-autorisee"]}
		with data.plages_vmid as {"socle": [[1000, 1099]]}
	some msg in tofu.warn with input as plan([remplacement_socle])
		with data.contexte as {"etat": "socle", "etiquettes_mr": ["destruction-autorisee"]}
		with data.plages_vmid as {"socle": [[1000, 1099]]}
	contains(msg, "AUTORISÉE")
}

test_destruction_hors_socle_signalee_pas_refusee if {
	count(tofu.deny) == 0 with input as plan([destruction_essai])
		with data.contexte as ctx_m29
	some msg in tofu.warn with input as plan([destruction_essai])
		with data.contexte as ctx_m29
	contains(msg, "détruit la VM m29-a")
}

# Une source de données (mode « data ») ou une ressource inchangée ne déclenche rien.
test_lecture_et_inchange_ignores if {
	lecture := object.union(cree("image", 9012, null, []), {"mode": "data", "change": {"actions": ["read"], "before": null, "after": {}}})
	inchange := vm("module.b.proxmox_virtual_environment_vm.vm", ["no-op"], attributs("b", 9999, null, []), attributs("b", 9999, null, []))
	count(tofu.deny) == 0 with input as plan([lecture, inchange])
		with data.contexte as ctx_m29
}
