# plateforme/politiques — rego/tofu/pool.rego (M29-E03, PLAT-3003)
# Toute VM du workbook est dans le pool Proxmox « lab » (PLAN §3.1, §4.3 bis) : c'est ce qui
# l'isole des VMs personnelles de pve01, et c'est le périmètre des jetons d'automatisation.
# Seule exception : un état déclaré dans data.conventions_etat (rego/donnees/plages-vmid.yaml)
# avec son propre pool (envs/hv-invites, cluster imbriqué hv-par1 du M09 : pool « recette »).
package tofu

pool_attendu := data.conventions_etat[data.contexte.etat].pool if {
	data.conventions_etat[data.contexte.etat].pool
} else := "lab"

deny contains msg if {
	some rc in vms_creees_ou_modifiees
	pool := object.get(rc.change.after, "pool_id", null)
	pool != pool_attendu
	msg := sprintf("%s : pool Proxmox %v au lieu de « %s »", [rc.address, pool, pool_attendu])
}
