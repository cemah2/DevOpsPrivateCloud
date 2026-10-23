# vm-debian/test/fixtures/vm — configuration racine de Terratest (M29-E08, PLAT-3008).
#
# Une VM jetable, créée par le module à tester (le dossier vm-debian lui-même, par chemin
# relatif : on teste le code de la MR, pas une étiquette publiée), puis détruite par le test.
# État LOCAL (pas de backend) : il vit dans le dossier temporaire du test et disparaît avec lui.
# Le test copie tout vm-debian/ dans un dossier temporaire avant d'exécuter tofu : le chemin
# « ../../.. » reste valide, et deux tests ne partagent jamais leur état.

module "vm" {
  source = "../../.."

  nom   = var.nom
  vmid  = var.vmid
  noeud = var.noeud
  # Sous-pool de lab réservé aux tests : c'est là, et là seulement, que l'identité
  # wb-terratest a des droits d'écriture (outils/proxmox/pve-terratest-compte.sh de plateforme/infra).
  pool           = "lab/terratest"
  vnet           = "vsandbox"
  etiquettes     = ["env-m29", "terratest"]
  reseau_prefixe = "10.10.99.0/24"
  # Plage « statique » de SANDBOX dans NetBox (10.10.99.10-49, M06-E13) : vm-debian v2 ne connaît
  # pas le DHCP, l'adresse est ALLOUÉE par NetBox et RENDUE à la destruction (le test le vérifie).
  plage_adresses = "10.10.99.10"
  coeurs         = 1
  memoire_mo     = 1024
  disque_go      = 10
  demarrage_auto = false
  cle_ssh_admin  = var.cle_ssh_admin
  description    = "Terratest M29-E08 (${var.lancement}) : VM jetable, détruite par le test. Orpheline ? RB-293."
}
