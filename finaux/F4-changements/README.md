# Final F4 — Changements majeurs

| | |
|---|---|
| **Type** | Workbook final (scénarios longs) |
| **Profil de lab** | Profil de travail des blocs F et G (≈ 111 Go) ; VMs migrées d'InfoGér `legacy-rdv01`, `ftp-part01`, `stats01` (3401-3403, ≤ 4 Go en tout) ; montée d'OpenStack (S08) **`k8s-par1` arrêté** : socle + `ceph-par1` + profil openstack (≈ 101 Go) |
| **Prérequis** | F2 (`day1-v1`) ; M08 (Ceph), M10 (OpenStack), M09-E23 (import OVA), M12-E19 (image de Legacy-RDV), M14 (montée de Kubernetes), M16 (CephFS), M20 (GitOps), M29 (k6) |
| **Durée indicative** | 65 à 80 heures |

## Contexte MédiSphère

Le trimestre des gros changements. Le contrat d'InfoGér s'arrête dans six semaines : leurs dernières VMs tournent encore sur leur VMware, et Legacy-RDV, l'ancienne prise de rendez-vous qu'utilisent toujours quarante cabinets, est dedans. Dans le même temps, Kubernetes, Ceph, OpenStack et plusieurs composants de plateforme ont de nouvelles versions, et l'audit HDS demande des systèmes maintenus. Claire Morel fixe une règle : « Aucun changement sans fiche, sans mesure et sans retour arrière. Et les cabinets ne doivent rien voir. » Karim Benali met en place la sonde qui jugera chaque opération ; Julien Petit et Nadia Roussel négocient les fenêtres ; Sophie Laurent veut que Legacy-RDV sorte du VMware… sans sortir ses mots de passe en dur.

## Objectifs

À la fin de ce final, tu sais :
- conduire un changement : fiche, analyse de risque, go/no-go, fenêtre, retour arrière, revue après mise en œuvre ;
- mesurer objectivement l'interruption subie par les utilisateurs pendant un changement ;
- décider d'une montée de version à partir d'une matrice de compatibilité, et la refuser quand elle n'est pas prête ;
- monter Kubernetes, les composants de plateforme, Ceph et OpenStack sans interruption visible ;
- migrer des VMs d'un hyperviseur VMware vers Proxmox VE (conversion, pilotes, réseau, inscription dans le code) ;
- replatformer une application monolithique vers Kubernetes et basculer ses données avec une coupure courte et réversible.

## Carte des scénarios

| ID | Titre | Type | Diff. | Phase |
|---|---|---|---|---|
| F4-S01 | Le processus de changement de MédiSphère | RED | ★★ | 1. Gouverner |
| F4-S02 | La sonde de continuité | LIBRE | ★★★ | 1. Gouverner |
| F4-S03 | Go ou no-go : la mineure suivante de Kubernetes | RED | ★★★ | 2. Montées |
| F4-S04 | Monter Kubernetes sans interruption | LIBRE | ★★★★ | 2. Montées |
| F4-S05 | Monter les composants de plateforme par GitOps | LIBRE | ★★★ | 2. Montées |
| F4-S06 | Panne : la montée qui bloque | BF | ★★★★ | 2. Montées |
| F4-S07 | Monter Ceph sous charge | LIBRE | ★★★ | 2. Montées |
| F4-S08 | Monter OpenStack de 2026.1 à 2026.2 | LIBRE | ★★★★ | 2. Montées |
| F4-S09 | Plan de migration du VMware d'InfoGér | RED | ★★★ | 3. Migrations |
| F4-S10 | Migrer les VMs d'InfoGér vers Proxmox VE | LIBRE | ★★★ | 3. Migrations |
| F4-S11 | Panne : la VM migrée ne démarre pas comme avant | BF | ★★★ | 3. Migrations |
| F4-S12 | Legacy-RDV sur Kubernetes | LIBRE | ★★★★ | 3. Migrations |
| F4-S13 | La bascule de Legacy-RDV | LIBRE | ★★★★ | 3. Migrations |
| F4-S14 | Revue des changements et décommissionnement | RED | ★★ | 4. Bilan |

**Répartition** : 14 scénarios · 2 break & fix · 4 rédactions.

## Hôtes et objets

| Élément | VMID / nom | Adresse | Scénario |
|---|---|---|---|
| `legacy-rdv01` | 3401 | 10.10.20.44 (`192.168.50.21` chez InfoGér) | S10, décommissionnée en S14 |
| `ftp-part01` | 3402 | 10.10.20.45 (`192.168.50.30`) | S10 |
| `stats01` | 3403 | 10.10.20.46 (`192.168.50.40`) | S10 |
| Legacy-RDV publié aux cabinets | `rdv.par1.medisphere.internal` (VIP de `lb01`/`lb02`) : vers `legacy-rdv01` (S10), puis vers Kubernetes (S13) | 10.10.70.200 | S10, S13 |
| Legacy-RDV sur Kubernetes | locataire `legacy`, espaces `legacy-rdv-recette`, `legacy-rdv-prod` | routes de la Gateway `legacy-rdv-recette.apps.par1.medisphere.internal`, `legacy-rdv.apps.par1.medisphere.internal` | S12, S13 |
| mariadb-operator 26.6 | espace `mariadb-system` | — | S12 |

L'export VMware est **simulé** : `ressources/S09/` fabrique, sur `pve01`, les disques VMDK et les descripteurs OVF tels qu'InfoGér les aurait livrés (matériel VMware, `vmxnet3`, `pvscsi`, `open-vm-tools`, adresses d'InfoGér). Versions cibles : [`annexes/versions-finaux-F1-F4.md`](../../annexes/versions-finaux-F1-F4.md). Détails figés : [`PLAN.md`](../../PLAN.md) §4.14.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check F4 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break F4 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
