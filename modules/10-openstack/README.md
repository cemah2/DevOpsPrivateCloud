# Module 10 — OpenStack

| | |
|---|---|
| **Bloc** | B — Infrastructure cloud privé |
| **Niveau** | Cœur |
| **Profil de lab** | openstack : socle + `osctl01` (2101, 16 Go), `oscmp01-02` (2102-2103, 8 Go) + `ceph01-03` (stockage) |
| **Prérequis** | Module 08 (Ceph `ceph-par1`) ; module 05 (OpenTofu) ; module 07 (VLAN, MTU, répartiteurs) |
| **Durée indicative** | 45 à 55 heures |

## Contexte MédiSphère

Les équipes de développement veulent des machines **en libre-service** : Julien Petit attend des jours chaque fois que MédiAgenda a besoin d'un environnement de recette. La DSI veut un vrai **IaaS** interne, multi-projets, avec quotas, réseaux isolés, IP flottantes, volumes et répartiteurs de charge à la demande, piloté par API et par OpenTofu — l'équivalent d'un cloud public, mais hébergé chez MédiSphère pour la souveraineté des données de santé. Claire Morel a retenu **OpenStack**, déployé en conteneurs par **Kolla-Ansible**, stocké sur le Ceph de PAR1. Sophie Laurent veut un cloisonnement strict entre projets ; Nadia Roussel veut pouvoir dépanner une instance « bloquée en ERROR » sans appeler un expert.

## Objectifs

À la fin de ce module, tu sais :
- expliquer l'architecture d'OpenStack (Keystone, Glance, Nova, Neutron/OVN, Cinder, Placement, Heat, Horizon, Octavia) et le chemin d'une requête ;
- déployer et maintenir OpenStack avec Kolla-Ansible (configuration en code, reconfiguration, mise à jour, ajout de nœud) ;
- brancher OpenStack sur Ceph (images, volumes, disques éphémères, sauvegardes) ;
- organiser le multi-projets : domaines, projets, rôles, quotas, politiques ;
- fournir réseaux, routeurs, IP flottantes, groupes de sécurité et répartiteurs de charge ;
- piloter OpenStack par la CLI, Heat et OpenTofu, et donner le libre-service aux équipes ;
- sauvegarder, superviser, sécuriser et dépanner la plateforme.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M10-E01 | Test de positionnement : IaaS et OpenStack | Q | ★★ | 1 |
| M10-E02 | Préparer les nœuds OpenStack | LAB | ★★ | 1 |
| M10-E03 | Préparer Kolla-Ansible | LAB | ★★ | 1 |
| M10-E04 | Déployer OpenStack | LAB | ★★ | 1 |
| M10-E05 | Keystone : domaines, projets, rôles | LAB | ★★ | 1 |
| M10-E06 | Glance : les images | LAB | ★ | 1 |
| M10-E07 | Nova : gabarits, clés et première instance | LAB | ★★ | 1 |
| M10-E08 | Neutron et OVN : réseaux, routeurs, IP flottantes | LAB | ★★ | 1 |
| M10-E09 | Questions : architecture d'OpenStack | Q | ★★ | 1 |
| M10-E10 | Brancher OpenStack sur Ceph | LAB | ★★★ | 2 |
| M10-E11 | Cinder : volumes, types, snapshots, sauvegardes | LAB | ★★ | 2 |
| M10-E12 | Le réseau externe intégré au lab | LAB | ★★ | 2 |
| M10-E13 | Projets et quotas pour les équipes | LAB | ★★ | 2 |
| M10-E14 | Heat : des piles d'infrastructure | LAB | ★★ | 2 |
| M10-E15 | OpenTofu et le provider OpenStack | LAB | ★★★ | 2 |
| M10-E16 | Octavia : répartiteurs de charge à la demande | LAB | ★★★ | 2 |
| M10-E17 | Horizon et l'accès des équipes | LAB | ★★ | 2 |
| M10-E18 | Métadonnées et cloud-init dans OpenStack | LAB | ★★ | 2 |
| M10-E19 | Exploiter le calcul : migrer, évacuer, désactiver | LAB | ★★ | 2 |
| M10-E20 | Kolla au quotidien : surcharges, reconfiguration, journaux | LAB | ★★ | 2 |
| M10-E21 | Revue : la configuration Kolla du prestataire | REV | ★★ | 2 |
| M10-E22 | Runbook : accueillir une équipe sur OpenStack | RED | ★★ | 2 |
| M10-E23 | Politiques d'accès et rôles de lecture | LAB | ★★★ | 2 |
| M10-E24 | La haute disponibilité du plan de contrôle | LAB | ★★★ | 3 |
| M10-E25 | Sauvegarder et restaurer OpenStack | LAB | ★★★ | 3 |
| M10-E26 | Superviser OpenStack | LAB | ★★ | 3 |
| M10-E27 | Sécuriser OpenStack | LAB | ★★★ | 3 |
| M10-E28 | Mettre à jour OpenStack | LAB | ★★★ | 3 |
| M10-E29 | Ajouter et retirer un nœud de calcul | LAB | ★★★ | 3 |
| M10-E30 | ADR : choix réseau et répartiteurs | RED | ★★ | 3 |
| M10-E31 | Le libre-service pour MédiAgenda | LIBRE | ★★★ | 3 |
| M10-E32 | Questions de production : OpenStack | Q | ★★★ | 3 |
| M10-E33 | Rapport de capacité et de consommation | RED | ★★ | 3 |
| M10-E34 | Un environnement complet en temps limité | CHRONO | ★★★ | 3 |
| M10-E35 | Panne : « No valid host was found » | BF | ★★★ | 4 |
| M10-E36 | Panne : l'IP flottante ne répond pas | BF | ★★★ | 4 |
| M10-E37 | Panne : l'instance ignore sa configuration | BF | ★★ | 4 |
| M10-E38 | Panne : le volume ne s'attache pas | BF | ★★★ | 4 |
| M10-E39 | Panne : plus personne ne s'authentifie | BF | ★★★ | 4 |
| M10-E40 | Panne : les calculs sont « down » | BF | ★★★ | 4 |
| M10-E41 | Panne : l'envoi d'image échoue | BF | ★★ | 4 |
| M10-E42 | Panne : le tableau de bord est inaccessible | BF | ★★ | 4 |
| M10-E43 | Astreinte : le cloud en détresse | BF | ★★★★ | 4 |
| M10-E44 | Sous le capot : la vie d'un `server create` | LAB | ★★★ | 4 |
| M10-E45 | Questions expert : OpenStack | Q | ★★★ | 4 |
| M10-E46 | Mini-projet : cloud MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 45 exercices + mini-projet · 9 break & fix · 4 questionnaires · 1 revue · 3 rédactions · 1 chronométré.

## Hôtes créés dans ce module

| Hôte | VMID | Adresses | Rôle | Exercice |
|---|---|---|---|---|
| `osctl01` | 2101 | OS-API 10.10.50.51, OS-TUN 10.10.51.51, STOR-PUB 10.10.30.61, OS-EXT (sans adresse) | Contrôle + réseau (passerelle OVN) | E02 |
| `oscmp01`, `oscmp02` | 2102, 2103 | OS-API 10.10.50.52-53, OS-TUN 10.10.51.52-53, STOR-PUB 10.10.30.62-63 | Calcul (KVM imbriqué) | E02 |
| VIP | — | 10.10.50.200 (interne), 10.10.50.201 (`openstack.par1.medisphere.internal`) | Points d'accès des API | E04 |

OpenStack 2026.1 « Gazpacho », Kolla-Ansible 22, OVN, stockage sur `ceph-par1`, réseau externe `ext-net` 10.10.52.0/24 (IP flottantes .200-.249) : voir [`PLAN.md`](../../PLAN.md) §4.9.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 10 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 10 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
