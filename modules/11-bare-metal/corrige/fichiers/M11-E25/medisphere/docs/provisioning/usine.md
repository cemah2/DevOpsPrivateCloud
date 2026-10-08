# L'usine de provisioning (PLAT-1290, `provisioning-v1`)

> Modèle de structure (M11-E25). Chaque section renvoie aux documents détaillés plutôt que de les recopier.

## 1. Ce que fait l'usine
Un serveur déclaré `planned` dans NetBox (rôle `serveur-bm`, interface `eno1` avec sa MAC) devient, par le job manuel `provisionner` de `plateforme/provisioning`, un serveur `active` : installé (Debian 13 ou Rocky 10 ; Proxmox VE 9.2 par `pve-answer/`), dans le DNS, dans l'inventaire Ansible, avec la racine de la PKI et sa clé d'hôte signée. Temps mesurés : BIOS/Debian <…> min, UEFI/Rocky <…> min.

## 2. Architecture
Schéma du VLAN 60 (`pxe01`, Kea `dns01`/`dns02` relayé par `gw01`/`gw02`, `bm*`), flux (lien vers `docs/socle/matrice-flux.md`), projets (`plateforme/provisioning`, rôles `pxe`, `pve_reponses`, `kea_dhcp4`, `relais_dhcp`).

## 3. Chaîne de confiance
Résumé de `securite-chaine.md` et de l'ADR-0111 ; ce qui reste usurpable (DHCP, TFTP).

## 4. Cycle de vie d'un serveur
Diagramme d'états de `orchestration.md` ; reprise ; retrait (statut `decommissioning`, effacement : voir 7).

## 5. Dépendances : que se passe-t-il quand… ?
| Composant indisponible | Effet | Tenue | Procédure |
|---|---|---|---|
| `pxe01` | plus aucun démarrage réseau ; serveurs en service non touchés | — | reconstruction par le code (OpenTofu, `pxe01.yml`, pipeline `deployer`), RB-111 |
| Kea (les deux) | plus d'adresse sur le VLAN 60 | baux en cours | M06 |
| NetBox | plus de rendu ni d'orchestration ; fichiers servis restent en place | — | M06 |
| `ca01` | plus d'émission ; certificat de `pxe01` valide jusqu'à 30 jours | 10 jours avant alerte | M06 |
| forge / runner | plus de job `provisionner` ; dépannage depuis `adm01` | — | RB-110 |

## 6. Procédures
RB-110 (provisionner un serveur), RB-111 (diagnostiquer un démarrage réseau), `pve-pxe.md`, `firmware.md`, ADR-0110, ADR-0111.

## 7. Ce qui n'est pas couvert
Effacement sécurisé avant retrait (F6) ; mise à jour des firmwares (fiche CHG, pas d'automatisation) ; *commissioning* et tests matériels (MAAS les faisait : ADR-0110) ; Secure Boot (serveurs physiques, module 26) ; installation des nœuds Kubernetes (module 14).

## 8. État après la recette
Serveurs de démonstration : <recréés vides et `planned`, ou détruits>. `maas01`, compte `wb-maas`, template 9050 : <sort et justification>.
