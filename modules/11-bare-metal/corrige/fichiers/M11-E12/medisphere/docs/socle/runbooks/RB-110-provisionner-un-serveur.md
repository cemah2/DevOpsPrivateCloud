# RB-110 — Provisionner un serveur

| | |
|---|---|
| Version | 1.0 (M11-E12, PLAT-1217) — à mettre à jour en M11-E15 (passage à `active` automatisé) et M11-E13 (HTTPS) |
| Propriétaire | Équipe Plateforme |
| Durée | 30 à 45 min par serveur, dont 10 à 20 min d'installation sans surveillance |
| Quand | Arrivée d'un serveur ; réinstallation d'un serveur existant (section 7) |
| Risque | Une installation **efface les disques** du serveur. Vérifier deux fois le nom et la MAC. |

## 1. Prérequis et accès

- Poste : `adm01` (VPN d'administration ou bastion), copies de travail `~/src/provisioning` et `~/src/ansible` à jour (`git pull`).
- Accès : NetBox avec ton jeton personnel (`~/.config/workbook/netbox-moi.token`, 7 jours — le renouveler si besoin) ; droit de fusion sur `plateforme/ansible` (ou un relecteur disponible) ; jeton d'alimentation (`~/.config/workbook/pve-maas.env` pour le lab ; BMC du serveur en production).
- Contrôle d'état de la chaîne avant de commencer :

  | Commande | Résultat attendu |
  |---|---|
  | `curl -s http://pxe01.par1.medisphere.internal/boot.ipxe \| head -n 1` | `#!ipxe` |
  | `ssh pxe01 'systemctl is-active tftpd-hpa nginx'` | `active` deux fois |
  | `ssh dns01 'sudo -n systemctl is-active isc-kea-dhcp4-server'` | `active` |
  | `lab/bin/check 11 06` | vert (hors serveurs en cours d'installation) |

## 2. Réception : saisir le serveur dans NetBox

Données obligatoires, relevées sur l'étiquette du serveur, le bon de livraison ou le BMC (Redfish `Systems/1` : `SerialNumber` ; les MAC dans `EthernetInterfaces` quand le firmware les expose) :

| Champ NetBox | Valeur | Contrôle |
|---|---|---|
| Nom | `bmNN` (prochain numéro libre) | unique dans le site |
| Site / rôle / type | `par1` / `serveur-bm` / type du modèle livré | |
| Plate-forme | `debian-13` ou `rocky-10` (décision d'affectation) | aucune autre n'est acceptée par la chaîne |
| Numéro de série | celui de l'étiquette | |
| Statut | **`planned`** | `planned` = « à installer » |
| Interface `eno1` + adresse MAC primaire | MAC de la carte de démarrage | format `aa:bb:cc:dd:ee:ff` |
| IP primaire | prochaine libre de 10.10.60.100-199, `dns_name` = `bmNN.par1.medisphere.internal` | |

Lab : `cd ~/src/provisioning && uv run outils/declarer-bm.py --simulation`, relire, puis sans `--simulation`.

## 3. Générer et appliquer

| # | Commande | Résultat attendu |
|---|---|---|
| 3.1 | `cd ~/src/provisioning && uv run outils/netbox-provision.py rendre --kea-ansible ~/src/ansible/inventories/lab/group_vars/role_dns/kea_reservations_prov.yml` | une ligne `[rendu] bmNN planned … → installation` ; **aucun** `[refus]` pour un serveur `planned` ; code de sortie 0 |
| 3.2 | Si `[refus]` : corriger NetBox (le motif est affiché), reprendre 3.1 | |
| 3.3 | `cd ~/src/ansible && git switch -c prov-bmNN && git add inventories/lab/group_vars/role_dns/kea_reservations_prov.yml && git commit -m "feat(dhcp): réservation de bmNN" && git push -u origin prov-bmNN` puis MR | diff = une ligne ajoutée (ou la ligne du serveur) |
| 3.4 | Fusion après relecture ; pipeline | vert |
| 3.5 | `ssh dns01 'printf "{\"command\":\"config-get\"}" \| sudo -n socat - UNIX-CONNECT:/run/kea/kea4-ctrl-socket' \| jq '.arguments.Dhcp4.subnet4[] \| select(.id==60) .reservations[] \| select(.hostname=="bmNN")'` | la réservation (même chose sur `dns02`) |
| 3.6 | `cd ~/src/provisioning && outils/publier.sh --simulation && outils/publier.sh` | `ipxe/mac-….ipxe` (et `kickstart/bmNN.ks` pour Rocky) publiés |
| 3.7 | `curl -s http://pxe01.par1.medisphere.internal/ipxe/mac-<MAC-AVEC-TIRETS>.ipxe` | `kernel …` avec `hostname=bmNN` (Debian) ou `inst.ks=…/bmNN.ks` (Rocky) |
| 3.8 | `medictl dns sync` (simulation, puis réelle) | `bmNN.par1.medisphere.internal` créé |

## 4. Démarrer et suivre l'installation

| # | Commande | Résultat attendu |
|---|---|---|
| 4.1 | Lab : `outils/alim.sh bmNN allumer`. Production : BMC du serveur (démarrage unique sur le réseau si l'ordre n'est pas « réseau d'abord ») | « allumée » |
| 4.2 | Console : `qm terminal <VMID>` / noVNC (lab), console du BMC (production) | iPXE affiche `bmNN : installation de …` |
| 4.3 | Suivi côté réseau : `ssh pxe01 'sudo tail -f /var/log/nginx/pxe-acces.log'` | téléchargement du noyau, de l'initrd, du preseed ou kickstart, en 200 |
| 4.4 | Attendre l'extinction (10-20 min) : `outils/alim.sh bmNN etat` | `stopped` |

## 5. Contrôles d'acceptation (serveur éteint puis rallumé)

| # | Commande | Résultat attendu |
|---|---|---|
| 5.1 | Passer le serveur en **`active`** dans NetBox, puis 3.1 et 3.6 (régénérer, publier) | script par MAC = « disque local » |
| 5.2 | `outils/alim.sh bmNN allumer` | démarre sur son disque (pas de nouvelle installation) |
| 5.3 | `ssh admin@bmNN.par1.medisphere.internal 'hostname -f; sudo -n true && echo sudo-ok'` | `bmNN.par1.medisphere.internal`, `sudo-ok` (première connexion : comparer l'empreinte avec la console) |
| 5.4 | Debian : `findmnt -no SOURCE /` ; Rocky : idem + `getenforce` | `/dev/mapper/…` ; `Enforcing` |
| 5.5 | `ls /usr/local/share/ca-certificates/medisphere-root-ca.crt` (Debian) / `trust list \| grep "MédiSphère Root CA"` (Rocky) | présent |
| 5.6 | Premier passage d'Ansible (pipeline) | clé d'hôte signée par la CA SSH (M06-E19) |

Consigner : nom, numéro de série, date, durée, opérateur, dans le ticket de réception.

## 6. Retour arrière

- Le serveur n'est pas encore en service : rien à restaurer. Repasser en `planned` et reprendre en 3, ou passer en `offline` et laisser le serveur éteint.
- Une mauvaise réservation a été fusionnée : révoquer la MR (pipeline), contrôle 3.5.
- Une publication erronée : `git revert` dans `plateforme/provisioning`, puis 3.6.

## 7. Réinstaller un serveur existant

⚠️ Efface le serveur. Uniquement sur ticket, après accord du responsable du service hébergé.
1. Vérifier qu'il n'héberge plus rien (drainage, sauvegardes à jour).
2. NetBox : statut `planned` (commentaire : numéro du ticket).
3. Sections 3 (3.1 et 3.6 suffisent : la réservation existe déjà) et 4 (`outils/alim.sh bmNN cycle`).
4. Section 5.

## 8. Dépannage

| Symptôme | Première vérification | Suite |
|---|---|---|
| Le serveur n'obtient pas d'adresse (« No DHCP offers », « PXE-E51 ») | `ssh pxe01 'sudo nmap --script broadcast-dhcp-discover -e ens18'` : une offre ? | Pas d'offre : relais (`gw01`/`gw02`, `ens19.60`) et Kea (sous-réseau 60). Offre mais pas pour ce serveur : MAC de NetBox ≠ MAC réelle |
| L'adresse obtenue n'est pas la réservée | `config-get` (3.5) sur les deux pairs | Réservation absente : MR non fusionnée ou pipeline en échec |
| « PXE-E32 TFTP open timeout » / « File not found » | `ssh pxe01 'sudo journalctl -t in.tftpd -n 20'` | Fichier absent de `/srv/tftp`, `tftpd-hpa` arrêté, classe Kea qui donne un mauvais nom |
| iPXE : « Connection timed out » ou « No such file » sur une URL | `curl -sI <URL affichée>` depuis `adm01` | 404 : publication (3.6) ; refus 403 : réseaux autorisés de nginx ; DNS : `dig pxe01.par1.medisphere.internal` |
| iPXE affiche le menu au lieu d'installer | `curl -s …/ipxe/mac-<MAC>.ipxe` | Absent : serveur refusé en 3.1, ou MAC saisie différente de celle qui démarre (autre carte ?) |
| L'installateur pose une question | Lire la question à la console | Valeur manquante dans le preseed/kickstart : ticket au propriétaire de la chaîne, ne pas répondre à la main (le serveur ne serait plus reproductible) |
| L'installation s'arrête sur « late_command » / « %post » en erreur | Console : le message ; `/root/ks-post.log` (Rocky) | Racine de la PKI différente de l'empreinte attendue : **ne pas contourner** ; prévenir la sécurité |
| Le serveur se réinstalle en boucle | Statut NetBox | Encore `planned` : faire 5.1 avant de rallumer |
| Rocky : l'installateur s'arrête au chargement de l'image (stage 2) | Version de l'initrd servi vs `inst.repo` | Versions mineures différentes : MR de montée de version (rôle `pxe`, `parametres.yml`, kickstart) |

## Références

PLAT-1210 (chaîne générée depuis NetBox), CHG-1215 (essai MAAS), ADR-0110 (choix de l'outil, M11-E16), RB-060 (ajouter un hôte au socle). Projets : `plateforme/provisioning`, `plateforme/ansible` (rôles `pxe`, `kea_dhcp4`, `relais_dhcp`).

## Exécutions

| Date | Serveur | Opérateur | Durée | Corrections apportées au runbook |
|---|---|---|---|---|
| JJ/MM/AAAA | bm03 | <MOI> | 38 min | 3.3 : nom de branche ; 4.3 : préciser le nom du journal nginx |
