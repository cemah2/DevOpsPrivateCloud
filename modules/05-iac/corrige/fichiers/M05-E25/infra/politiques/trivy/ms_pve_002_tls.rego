# METADATA
# title: Le provider Proxmox doit vérifier le certificat TLS de l'API
# description: >-
#   insecure = true désactive la vérification du certificat de pve01 : le jeton wb-tofu
#   partirait vers quiconque se place entre adm01 (ou runner01) et l'API.
# custom:
#   id: MS-PVE-002
#   avd_id: MS-PVE-002
#   severity: CRITICAL
#   short_code: tls-verifie
#   recommended_action: Retirer insecure = true ; installer l'autorité de pve01 dans le magasin du système (M02-E08, M03-E02).
#   input:
#     selector:
#     - type: terraform-raw
package user.medisphere.pve002

import rego.v1

deny contains res if {
	some m in input.modules
	some b in m.blocks
	b.kind == "provider"
	b.name == "proxmox"
	b.attributes.insecure.value == true
	res := result.new("Le provider proxmox désactive la vérification TLS (insecure = true)", b.attributes.insecure)
}
