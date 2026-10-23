# plateforme/politiques — rego/tofu/pool.rego (M29-E03, PLAT-3003)
# Toute VM du workbook est dans le pool Proxmox « lab » (PLAN §3.1, §4.3 bis) : c'est ce qui
# l'isole des VMs personnelles de pve01, et c'est le périmètre des jetons d'automatisation.
package tofu

deny contains msg if {
	some rc in vms_creees_ou_modifiees
	pool := object.get(rc.change.after, "pool_id", null)
	pool != "lab"
	msg := sprintf("%s : pool Proxmox %v au lieu de « lab »", [rc.address, pool])
}
