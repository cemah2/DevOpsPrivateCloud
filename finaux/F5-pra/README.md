# Final F5 — PRA multi-site

| | |
|---|---|
| **Type** | Workbook final (scénarios longs) |
| **Profil de lab** | PAR1 : profil de travail des blocs F et G (≈ 111 Go sur `pve01`), inchangé. PAR2 : `hp01` devient aussi hyperviseur (Proxmox VE à côté de PBS) ; ≈ 8 Go de VMs en veille, ≈ 10 Go pendant un PRA (voir [`PLAN.md`](../../PLAN.md) §4.15) |
| **Prérequis** | F2 (`day1-v1`) ; M00 (PBS, tunnel `wg0`), M06 (DNS, PKI), M14 (kubeadm), M15 (Cilium), M16 et M27 (CloudNativePG, Velero, réplica de secours), M20 (Argo CD), M25 (OpenBao, `kms01`), M29 (journées de jeu, mesures de bascule). F3 et F4 conseillés |
| **Durée indicative** | 60 à 80 heures |

## Contexte MédiSphère

L'audit HDS a relevé la même phrase dans trois rapports : « Plan de reprise d'activité non testé ». Tout MédiSphère tient dans une salle, PAR1 ; PAR2 n'est qu'un serveur de sauvegardes. Claire Morel a obtenu de la direction un budget modeste et une date : dans deux mois, un exercice de PRA réel, avec un huissier interne — Sophie Laurent — et un rapport chiffré. « Si PAR1 brûle un mardi à 10 h, je veux savoir à quelle heure les patients reprennent rendez-vous, et combien de rendez-vous on a perdus. Pas une estimation : une mesure. » Nadia Roussel organisera la cellule de crise ; Julien Petit veut savoir ce que son équipe devra faire « le jour J » ; Karim Benali prévient : `hp01` n'a que 16 Go de mémoire et deux cœurs.

## Objectifs

À la fin de ce final, tu sais :
- conduire une analyse d'impact et fixer des objectifs de reprise (RTO, RPO, mode dégradé) défendables ;
- cartographier les dépendances d'une reprise et en tirer un ordre de redémarrage ;
- construire un site de repli minimal, alimenté en continu (données, code, images, secrets, confiance) ;
- déclarer un sinistre, basculer, mesurer le RTO et le RPO réels, tenir en mode dégradé ;
- revenir sur le site principal sans perdre ce qui a été écrit pendant le PRA ;
- rendre compte d'un exercice de PRA et faire de la reprise une capacité testée régulièrement.

## Carte des scénarios

| ID | Titre | Type | Diff. | Phase |
|---|---|---|---|---|
| F5-S01 | Analyse d'impact et objectifs de reprise | RED | ★★ | 1. Analyser |
| F5-S02 | Les dépendances de la reprise et l'architecture de PAR2 | RED | ★★★ | 1. Analyser |
| F5-S03 | L'hyperviseur et le réseau de PAR2 | LIBRE | ★★★ | 2. Construire PAR2 |
| F5-S04 | Les données partent à PAR2 | LIBRE | ★★★ | 2. Construire PAR2 |
| F5-S05 | La confiance et les secrets hors de PAR1 | LIBRE | ★★★★ | 2. Construire PAR2 |
| F5-S06 | Le cluster de secours `k8s-par2` | LIBRE | ★★★★ | 2. Construire PAR2 |
| F5-S07 | Le runbook de bascule et la cellule de crise | RED | ★★ | 2. Construire PAR2 |
| F5-S08 | Panne : la reprise qui ne reprend pas | BF | ★★★ | 3. L'exercice |
| F5-S09 | Le sinistre : perte de PAR1 | CHRONO | ★★★★ | 3. L'exercice |
| F5-S10 | Panne : les surprises de la crise | BF | ★★★★ | 3. L'exercice |
| F5-S11 | Tenir en mode dégradé | LIBRE | ★★★ | 3. L'exercice |
| F5-S12 | Le retour à PAR1 | LIBRE | ★★★★ | 4. Retour et bilan |
| F5-S13 | Le rapport d'exercice PRA | RED | ★★ | 4. Retour et bilan |
| F5-S14 | Recette `pra-v1` : une reprise qui se teste | LIBRE | ★★★ | 4. Retour et bilan |

**Répartition** : 14 scénarios · 2 break & fix · 1 chronométré · 4 rédactions.

## Hôtes et objets

| Élément | VMID / nom | Adresse | Scénario |
|---|---|---|---|
| Hyperviseur de PAR2 | `hp01` (nœud Proxmox `pbs01`, PBS conservé) | 10.20.10.10 ; passerelle PAR2 INFRA 10.20.20.1 (`vmbr2`) | S03 |
| `adm02` | 1050 | 10.20.20.10 | S03, S04 |
| `dns03` | 1051 | 10.20.20.11 | S03, S09 |
| `s3-02` | 1052 | 10.20.20.14 | S04 |
| `reg02` | 1053 | 10.20.20.18 | S04 |
| `k8s-par2-n01` (cluster `k8s-par2`) | 1054 | 10.20.20.50 ; LB IPAM 10.20.20.200-239, Gateway `gw-par2` 10.20.20.200 | S06 |
| `bao-par2` | 1055 | 10.20.20.21 | S05, S09 |
| `kms01` restauré à PAR2 (pendant un PRA) | 3501 | 10.20.20.24 | S05, S09 |
| VPN d'administration de secours | `wg1` de `hp01`, UDP 51823 | 10.255.3.0/24 | S03 |
| Noms de service globaux | `mediagenda.medisphere.internal`, `medidoc.medisphere.internal`, `rdv.medisphere.internal` (CNAME, TTL 60 s) | vers PAR1 ou PAR2 | S03, S09, S12 |

Le sinistre est **simulé par isolement** (`lab/bin/break F5 09`) : la bordure de PAR1 coupe la liaison vers PAR2 et le VPN d'administration de PAR1 ; aucune VM n'est arrêtée. Versions : [`annexes/versions-finaux-F5-F7.md`](../../annexes/versions-finaux-F5-F7.md). Détails figés : [`PLAN.md`](../../PLAN.md) §4.15.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check F5 <XX>`, depuis `adm01` (depuis `adm02` pendant le PRA, de S09 à S11).
- Pannes : `lab/bin/break F5 <XX>`, depuis `adm01` ; annulation du sinistre depuis `pve01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
