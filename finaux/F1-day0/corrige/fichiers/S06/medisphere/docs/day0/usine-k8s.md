# L'usine installe un nœud Kubernetes : profil `k8s-noeud` (F1-S06, PLAT-3106)

> Version de référence (corrigé F1-S06). Durées : EXEMPLES de forme, à remplacer par tes mesures.

## 1. Le profil

| | Nœud cloné (M14) | Nœud de l'usine (`k8s-noeud`) |
|---|---|---|
| Origine | clone complet de l'image dorée `gold/debian13/current` | Debian 13 installé par debian-installer (preseed `gabarits/k8s-noeud.cfg.j2`) |
| NetBox | VM créée par le module `vm-noeud` | VM de plate-forme **`k8s-noeud`** créée par `envs/k8s/usine.tf` (ou `envs/f1/essai.tf`) |
| Réseau dans l'invité | `eth0` (cloud-init), netplan / systemd-networkd | `eth0` (netplan, carte reconnue par sa MAC et renommée), systemd-networkd, adresse **statique** de service |
| Swap | aucun (image dorée) | aucun (recette de partitionnement sans swap) |
| Compte `admin`, clé d'`adm01`, sudo | cloud-init | `late_command` du preseed |
| Racine de la PKI | image dorée | remise par iPXE, empreinte vérifiée, `update-ca-certificates` |
| Agent QEMU | image dorée | paquet installé |
| `cloud-init` | présent | **absent** ; `/etc/cloud/cloud.cfg.d/` créé vide (le rôle `k8s_reseau_stockage` y écrit) |
| Ce qui reste aux rôles Ansible | `containerd`, `k8s_noeud` (modules, sysctl, dépôt, paquets), `k8s_travailleur`… | identique : l'usine ne duplique rien |

## 2. Deux adresses pour un nœud

Décision : l'interface `ens18` de la VM NetBox porte **deux** adresses, et la MAC est la même dans les deux phases.

| Adresse | Exemple (`k8s-w03`) | Statut NetBox | Sert à |
|---|---|---|---|
| service | 10.10.40.63/24 (IP primaire, `dns_name`) | `active` | écrite statique dans le système installé ; DNS ; inventaire Ansible |
| provisioning | 10.10.60.163/24 (règle : 100 + suffixe) | `reserved` | réservation Kea du VLAN 60, démarrage réseau et installation |

Écartés : un champ personnalisé (une adresse hors d'IPAM échappe aux contrôles de doublons de NetBox) ; une règle de calcul seule (NetBox ne dirait plus rien de ce qui se passe).

## 3. Changements de la chaîne

| Dépôt | Fichier | Changement |
|---|---|---|
| `plateforme/provisioning` | `outils/netbox-provision.py` | lit aussi les VMs de plate-forme `k8s-noeud` ; adresse de provisioning = l'adresse de `ens18` dans 10.10.60.0/24 ; MAC par l'objet MAC de NetBox ≥ 4.2 |
| | `gabarits/k8s-noeud.cfg.j2`, `gabarits/ipxe-hote.ipxe.j2` | nouveau preseed ; branche Debian pour `k8s-noeud` |
| | `outils/provisionner.py` | accepte les VMs `k8s-noeud` ; s'arrête après l'installation si l'adresse de service est hors du VLAN 60 ; `--apres-bascule` ; vérification du profil en SSH au lieu de l'accueil des serveurs bm |
| | `tests/test_profil_k8s.py`, `tests/donnees/netbox-k8s.json`, `.gitlab-ci.yml` | tests et rendu simulé du profil (les tests du M11 sont inchangés) |
| `plateforme/infra` | `envs/f1/` (nouvel état), `envs/k8s/usine.tf`, `variables.tf`, `noeuds.tf` | essai ; nœuds de l'usine, variable `noeuds_usine` (vide par défaut) |
| `plateforme/politiques` | `rego/donnees/plages-vmid.yaml` | plage de `envs/f1` (3100-3199) |
| NetBox (compte `<MOI>`) | — | plate-forme `k8s-noeud` ; champ `pxe_action` étendu aux machines virtuelles |
| Proxmox (`root@pam`) | ACL | `WBProvision` sur `/vms/3101` (retirée après l'essai) et `/vms/2146` |

## 4. Essai (`f1-usine-essai`, VM 3101)

| Étape | Durée |
|---|---|
| MR `envs/f1` (`avec_essai = true`), apply | 6 min |
| Rendu et publication (job `deployer` déclenché par la MR de `plateforme/provisioning`) | 3 min |
| Job `provisionner`, `EQUIPEMENT=f1-usine-essai` : PXE, installation, extinction | 22 min |
| Premier démarrage, clé d'hôte par l'agent, vérification du profil, `active` | 4 min |
| Vérifications à la main (§5) | 10 min |
| `avec_essai = false`, apply ; ACL `/vms/3101` retirée ; réservation Kea retirée par le rendu suivant | 8 min |

Trace sur `pxe01` : `/var/log/nginx/pxe-acces.log` (`GET /ipxe/mac-02-4d-53-60-31-01.ipxe`, `GET /preseed/f1-usine-essai.cfg`).

## 5. Vérifié sur la machine d'essai

`swapon --show` vide ; `ip -br a` : `eth0` 10.10.60.191/24 ; `networkctl` : `eth0` géré ; `/etc/resolv.conf` : 10.10.20.10, .16 ; `chronyc sources` : la passerelle ; racine MédiSphère dans le magasin ; `systemctl is-active qemu-guest-agent` ; `hostname` = `f1-usine-essai` ; rôle `k8s_noeud` joué en `--check` sur la machine (groupe ad hoc) : il ne trouve que ce qu'il doit installer (dépôt, paquets), aucune précondition en échec.

## 6. Procédure prévue pour `k8s-w03` (phase 3, F1-S07)

1. Cluster détruit (CHG-3107) : les cinq autres nœuds ont été remplacés (`-replace`), et `k8s-w03` a été **retiré** de `module.noeud` par un apply à part (`tofu apply -destroy -target='module.noeud["k8s-w03"]'`, plan relu : seuls la VM 2146 et les objets NetBox/DNS de `k8s-w03` disparaissent ; `outils/day0/20-noeuds.sh` de F1-S07 le fait). VM 2146 n'existe plus. Jamais les deux changements (retrait du clone, création par l'usine) dans le même apply.
2. MR `plateforme/infra` : `noeuds_usine = { "k8s-w03" = "installation" }` ; plan relu (VM 2146 vide sur `vprov`, VM NetBox `planned`, deux adresses, DNS) ; apply.
3. Pipeline de `plateforme/provisioning` : *Run pipeline*, `EQUIPEMENT=k8s-w03`, job `provisionner` : installation, extinction, NetBox `staged`, `pxe_action=local`, journal « bascule réseau attendue ».
4. MR `plateforme/infra` : `noeuds_usine = { "k8s-w03" = "service" }` ; plan : modification **en place** (carte sur `vk8s`, carte de stockage ajoutée, démarrage sur disque, VM démarrée) ; apply.
5. Depuis `adm01` (copie de travail de `plateforme/provisioning`, jeton `netbox-auto.token`, `pve-provision.env`) : `uv run outils/provisionner.py k8s-w03 --apres-bascule` : SSH, DNS, clé d'hôte lue par l'agent (fichier `~/.cache/provisionner/known_hosts-k8s-w03`, à donner au premier passage d'Ansible), vérification, NetBox `active` : `k8s-w03` entre dans `netbox-k8s.yml`.
6. Playbooks Kubernetes (S07) comme pour les autres nœuds.

Temps attendu : 35 à 45 min de l'apply « installation » au statut `active`.

## 7. Droits accordés (registre des secrets)

`wb-provision@pve!provision` (rôle `WBProvision` : `VM.Audit`, `VM.PowerMgmt`, `VM.GuestAgent.FileRead`) : `/vms/2112` à `/vms/2115` (M11), **`/vms/2146`** (F1-S06, k8s-w03, permanent tant qu'il est installé par l'usine), `/vms/3101` le temps de l'essai (retiré le <date>). Risque accepté : le jeton peut éteindre `k8s-w03` (travailleur de production) ; atténuation : `VMID_AUTORISES` de `provisionner.py`, job manuel sur `main`, `resource_group`.
