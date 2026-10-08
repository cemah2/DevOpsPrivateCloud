# Module 14 — Administration Kubernetes

| | |
|---|---|
| **Bloc** | C — Conteneurs et Kubernetes |
| **Niveau** | Cœur |
| **Profil de lab** | k8s : socle + `k8s-cp01-03` (2141-2143, 4 Go chacun) + `k8s-w01-03` (2144-2146, 8 Go chacun) ; `k8s-w04` (2147) ponctuellement |
| **Prérequis** | Modules 12 et 13 (images, Harbor) ; module 07 (keepalived, HAProxy, bordure) ; modules 04-06 (Ansible, OpenTofu, PKI, DNS) |
| **Durée indicative** | 50 à 60 heures |

## Contexte MédiSphère

Les images sont prêtes et signées ; il faut maintenant un endroit pour les faire tourner, à plusieurs instances, avec des mises à jour sans coupure et des équipes qui ne se marchent pas dessus. Le comité d'architecture a retenu **Kubernetes** installé avec **kubeadm**, sur des VMs de PAR1 : pas de distribution packagée, pour que l'équipe Plateforme comprenne et maîtrise chaque composant. Claire Morel veut un plan de contrôle **redondant** ; Sophie Laurent veut des identités, des rôles et un audit ; Nadia Roussel veut savoir quoi faire quand un nœud tombe, quand etcd souffre, quand les certificats expirent.

## Objectifs

À la fin de ce module, tu sais :
- construire un cluster kubeadm hautement disponible (etcd empilé, VIP d'API) depuis le code ;
- déployer et exploiter des charges de travail (Deployments, StatefulSets, DaemonSets, Jobs) ;
- cloisonner les équipes : espaces de noms, quotas, RBAC, comptes de service, admission ;
- maîtriser l'ordonnancement (affinités, taints, répartition topologique, PDB) ;
- sauvegarder et restaurer etcd, monter le cluster de version, gérer ses certificats, l'auditer, chiffrer les Secrets ;
- diagnostiquer méthodiquement nœuds, pods, plan de contrôle et DNS du cluster.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M14-E01 | Test de positionnement : Kubernetes | Q | ★★ | 1 |
| M14-E02 | Préparer les nœuds | LAB | ★★ | 1 |
| M14-E03 | Le point d'accès de l'API : keepalived et HAProxy | LAB | ★★ | 1 |
| M14-E04 | Amorcer le cluster avec kubeadm | LAB | ★★ | 1 |
| M14-E05 | Joindre les nœuds et installer Cilium | LAB | ★★ | 1 |
| M14-E06 | kubectl, kubeconfig et k9s | LAB | ★ | 1 |
| M14-E07 | Pods, Deployments et Services : MédiAgenda sur le cluster | LAB | ★★ | 1 |
| M14-E08 | ConfigMaps, Secrets, sondes et ressources | LAB | ★★ | 1 |
| M14-E09 | Questions : architecture de Kubernetes | Q | ★★ | 1 |
| M14-E10 | Espaces de noms, quotas et LimitRanges | LAB | ★★ | 2 |
| M14-E11 | RBAC : des rôles pour les équipes | LAB | ★★★ | 2 |
| M14-E12 | Identités humaines : certificats clients et CSR | LAB | ★★ | 2 |
| M14-E13 | Comptes de service et jetons liés | LAB | ★★ | 2 |
| M14-E14 | Ordonnancement : affinités, taints et répartition | LAB | ★★★ | 2 |
| M14-E15 | StatefulSets, DaemonSets, Jobs et CronJobs | LAB | ★★ | 2 |
| M14-E16 | Mises à jour progressives, retour arrière et PDB | LAB | ★★ | 2 |
| M14-E17 | Drainer, ajouter et retirer un nœud | LAB | ★★ | 2 |
| M14-E18 | Admission : Pod Security et ValidatingAdmissionPolicy | LAB | ★★★ | 2 |
| M14-E19 | Tirer les images depuis Harbor | LAB | ★★ | 2 |
| M14-E20 | Diagnostiquer un pod | LAB | ★★ | 2 |
| M14-E21 | Revue : les manifestes du stagiaire | REV | ★★ | 2 |
| M14-E22 | Runbook : un nœud est NotReady | RED | ★★ | 2 |
| M14-E23 | Le cluster décrit par le code | LIBRE | ★★★ | 2 |
| M14-E24 | Sauvegarder et restaurer etcd | LAB | ★★★ | 3 |
| M14-E25 | Monter le cluster de version : 1.35 → 1.36 | LAB | ★★★ | 3 |
| M14-E26 | Les certificats du cluster | LAB | ★★★ | 3 |
| M14-E27 | Auditer l'API | LAB | ★★★ | 3 |
| M14-E28 | Chiffrer les Secrets dans etcd | LAB | ★★★ | 3 |
| M14-E29 | Perdre un nœud de contrôle | LAB | ★★★ | 3 |
| M14-E30 | Politique de cycle de vie des versions Kubernetes | RED | ★★ | 3 |
| M14-E31 | ADR : distribution et topologie de `k8s-par1` | RED | ★★ | 3 |
| M14-E32 | Questions de production : Kubernetes | Q | ★★★ | 3 |
| M14-E33 | Accueillir une équipe sur le cluster | LIBRE | ★★★ | 3 |
| M14-E34 | Examen blanc d'administration | CHRONO | ★★★ | 3 |
| M14-E35 | Panne : un nœud est NotReady | BF | ★★ | 4 |
| M14-E36 | Panne : des pods restent Pending | BF | ★★ | 4 |
| M14-E37 | Panne : ImagePullBackOff | BF | ★★ | 4 |
| M14-E38 | Panne : CrashLoopBackOff | BF | ★★ | 4 |
| M14-E39 | Panne : l'API ne répond plus | BF | ★★★ | 4 |
| M14-E40 | Panne : un membre etcd est en détresse | BF | ★★★ | 4 |
| M14-E41 | Panne : accès refusé | BF | ★★★ | 4 |
| M14-E42 | Panne : le DNS du cluster ne répond plus | BF | ★★★ | 4 |
| M14-E43 | Astreinte : le cluster en détresse | BF | ★★★★ | 4 |
| M14-E44 | Sous le capot : du `kubectl apply` au conteneur | LAB | ★★★★ | 4 |
| M14-E45 | Questions expert : Kubernetes | Q | ★★★ | 4 |
| M14-E46 | Mini-projet : Kubernetes MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 45 exercices + mini-projet · 9 break & fix · 4 questionnaires · 1 revue · 3 rédactions · 1 chronométré.

## Hôtes créés dans ce module

| Hôte | VMID | Adresse (VLAN 40) | Rôle | Exercice |
|---|---|---|---|---|
| `k8s-cp01-03` | 2141-2143 | 10.10.40.51-53 | Plan de contrôle (etcd empilé), keepalived + HAProxy de la VIP d'API | E02-E05 |
| `k8s-w01-03` | 2144-2146 | 10.10.40.61-63 | Travailleurs | E02-E05 |
| `k8s-w04` | 2147 | 10.10.40.64 | Ajout et remplacement de nœud (détruit en fin de module) | E17 |

Cluster **`k8s-par1`**, kubeadm 1.35 puis **1.36** (E25), API `https://k8s-api.par1.medisphere.internal:8443` (VIP 10.10.40.200), containerd 2.3, Cilium 1.20 : voir [`PLAN.md`](../../PLAN.md) §4.10. Le cluster est **conservé** (arrêtable) : il porte les modules 15 à 29 et les finaux.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 14 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 14 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
