# providers.tf — API du cluster hv-par1 par sa VIP (M09-E18).
#
# Aucun secret ici. Le provider lit dans l'environnement :
#   PROXMOX_VE_ENDPOINT   https://hv.par1.medisphere.internal:8006/
#   PROXMOX_VE_API_TOKEN  wb-tofu-hv@pve!tofu=<SECRET>
# (~/.config/workbook/pve-tofu-hv.env sur adm01 ; variables CI protégées et masquées
#  HV_PROXMOX_VE_ENDPOINT / HV_PROXMOX_VE_API_TOKEN, recopiées par le job de l'environnement.)
#
# TLS vérifié : le certificat présenté par la VIP est signé par l'autorité du cluster hv-par1,
# installée dans le magasin système d'adm01 et de runner01 (hv-par1-root-ca.crt, rôle pve_cluster).
# Il contient le nom hv.par1.medisphere.internal quel que soit le nœud qui porte la VIP.
provider "proxmox" {
  insecure = false
}
