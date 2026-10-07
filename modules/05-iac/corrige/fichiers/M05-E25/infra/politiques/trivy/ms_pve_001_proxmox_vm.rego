# METADATA
# title: Ressource expérimentale proxmox_vm interdite
# description: >-
#   Dans bpg/proxmox 0.x, proxmox_vm est une ressource expérimentale dont le schéma peut changer
#   sans préavis. Les VMs se déclarent avec proxmox_virtual_environment_vm (ou le module vm-debian).
# custom:
#   id: MS-PVE-001
#   avd_id: MS-PVE-001
#   severity: HIGH
#   short_code: pas-de-proxmox-vm
#   recommended_action: Utiliser proxmox_virtual_environment_vm ou le module vm-debian.
#   input:
#     selector:
#     - type: terraform-raw
package user.medisphere.pve001

import rego.v1

deny contains res if {
	some m in input.modules
	some b in m.blocks
	b.kind == "resource"
	b.type == "proxmox_vm"
	res := result.new(sprintf("%s utilise la ressource expérimentale proxmox_vm", [b.__defsec_metadata.resource]), b)
}
