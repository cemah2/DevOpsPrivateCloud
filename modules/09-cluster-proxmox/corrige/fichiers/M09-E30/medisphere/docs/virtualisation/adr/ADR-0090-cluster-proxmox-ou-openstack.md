# ADR-0090 — Cluster Proxmox VE ou OpenStack : quelles charges, où

- Statut : accepté (2026-10-XX)
- Décideurs : Claire Morel ; consultés : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit
- Contexte technique : `hv-par1` (Proxmox VE 9.2, 3 nœuds, Ceph hyperconvergé, HA) ; OpenStack 2026.1 prévu au module 10 sur `ceph-par1` ; Kubernetes au module 14.

## Contexte et problème

MédiSphère disposera de deux plateformes de VMs. La direction demande pourquoi ; les équipes demandent où va chaque charge. Sans règle, chaque demande se tranche au cas par cas, et l'équipe Plateforme opère deux plateformes à moitié.

## Facteurs de décision

1. **Qui demande, et à quelle fréquence** (équipe Plateforme quelques fois par mois / équipes de développement plusieurs fois par jour).
2. **Modèle de disponibilité** : VM unique qui doit survivre (« pet ») ou instance remplaçable dans une application redondante (« cattle »).
3. Libre-service, multi-locataire, quotas, API stable pour l'IaC des équipes.
4. Charge d'astreinte et compétences (un cluster Proxmox s'opère à deux personnes ; OpenStack demande des compétences rares).
5. Coût du plan de contrôle (mémoire, CPU, complexité des mises à jour).
6. Conformité HDS : cloisonnement entre locataires, traçabilité, localisation des données de santé.
7. Réversibilité : sortie possible sans réécrire les charges.

## Options envisagées

| | A. Tout sur Proxmox | B. Tout sur OpenStack | C. Partage par usage | D. OpenStack **sur** des VMs Proxmox |
|---|---|---|---|---|
| Libre-service, quotas | faible : pools, droits, pas de quotas par projet | fort : projets, quotas, réseaux par locataire | fort là où il sert | fort |
| VM unique hautement disponible | natif (HA, fencing, ~3 min) | absent par défaut (évacuation manuelle ou outils additionnels) | Proxmox pour ces VMs | comme B |
| Plan de contrôle | léger (intégré aux nœuds) | lourd (≈ 16 Go pour le contrôle dans le lab, nombreux services) | les deux | les deux, imbriqués |
| Astreinte | maîtrisée | lourde, compétences rares | deux plateformes, mais chacune dans son domaine | pire des deux |
| Stockage | Ceph hyperconvergé | `ceph-par1` | les deux | `ceph-par1` |
| HDS (cloisonnement locataires) | par pools et droits, faible entre équipes | par projets, réseaux isolés | adapté à chaque usage | adapté |
| Réversibilité | bonne (VMs standard, sauvegarde PBS) | bonne (images, API) | bonne | moyenne |

## Décision

**Option C : partage par usage.**

| Charge | Plateforme | Raison |
|---|---|---|
| Services socle et d'infrastructure (DNS, PKI, forge, NetBox, sauvegardes, bastion) | `pve01` aujourd'hui, `hv-par1` à terme | VMs uniques, peu nombreuses, gérées par la Plateforme ; HA de VM nécessaire ; ne doivent pas dépendre d'OpenStack (OpenStack dépend d'elles) |
| Bases de données de production de MédiAgenda | `hv-par1` (pool `prod`) | VM unique à état ; HA de VM + réplication applicative ; règles d'anti-affinité |
| VMs héritées d'InfoGér (Legacy-RDV) | `hv-par1` | « pets » importés (E23), à migrer plus tard ; pas de libre-service utile |
| Environnements de recette éphémères des équipes de Julien | **OpenStack** (projets `mediagenda-dev`, …) | demandes fréquentes, libre-service, quotas, réseaux isolés par projet, destruction automatique |
| Nœuds Kubernetes (M14) | `hv-par1` d'abord (VMs créées par OpenTofu) ; réévalué en F1 | peu de nœuds, cycle de vie maîtrisé par la Plateforme ; OpenStack possible (provider Cluster API) quand il sera éprouvé |
| Postes de rebond, outillage de la Plateforme | `hv-par1` | idem socle |
| Charges de test du workbook | là où l'exercice le dit | — |

Règle générale : **une charge va sur OpenStack si elle est demandée par une équipe hors Plateforme, plus d'une fois par semaine, et si elle est remplaçable** ; sinon sur le cluster Proxmox.

## Conditions de remise en cause

- Plus de 3 équipes hors Plateforme ou plus de 10 demandes de VMs par semaine sur `hv-par1` : le libre-service manque, élargir OpenStack.
- OpenStack sans incident majeur pendant 6 mois et deux personnes formées à son astreinte : y déplacer les nœuds Kubernetes.
- Moins de 2 demandes par mois sur OpenStack après 6 mois : coût du plan de contrôle injustifié, envisager de le retirer (option A).
- Un incident de cloisonnement entre équipes sur `hv-par1` : revoir le placement des charges multi-équipes.

## Conséquences

Positives : chaque plateforme fait ce pour quoi elle est conçue ; le socle ne dépend pas d'OpenStack ; les équipes de développement ont du libre-service.

Négatives (et actions) :
- Deux plateformes à opérer, à mettre à jour, à superviser → supervision commune (M21), runbooks par plateforme (RB-09x, RB-10x), astreinte formée sur les deux (F3).
- Deux modèles de droits → identité centralisée (Keycloak, M24) pour les deux.
- Deux Ceph (hyperconvergé et `ceph-par1`) → politique de stockage commune (ADR-0080, `docs/stockage/politique-stockage.md`).
- Risque de « dérive » (une recette créée sur Proxmox « parce que c'est plus simple ») → contrôle dans la revue mensuelle de capacité (`ms-capacite-cluster`, E31) : toute VM du pool `recette` de plus de 30 jours est signalée.
- Catalogue de services pour orienter les demandes → module 28.
