# Versions des finaux F1 à F4 et changements de comportement

> Relevé fait le 23 octobre 2026 au démarrage des finaux F1 à F4, à partir des sources officielles (pages de publication des projets, `kubernetes.io/releases`, documentation de Cilium, notes de version de Ceph, PyPI, GitHub). Les finaux F1 à F3 **n'introduisent aucun nouvel outil** : ils réutilisent les versions figées des blocs A à G ([`PLAN.md`](../PLAN.md) §6). Seul F4 (changements majeurs) vise des versions **cibles**, qui seront souvent plus récentes au moment où tu feras l'exercice : la règle est alors de viser la dernière version que **toute la chaîne** déclare compatible, et de l'écrire dans la fiche de changement.

## État au relevé

| Composant | Installé dans le lab | Dernière publiée au relevé | Cible de F4 | Remarque |
|---|---|---|---|---|
| Kubernetes | 1.36.5 (M14) | 1.37.1 (15/09/2026) ; 1.36.5 et 1.35.9 le même jour | **1.37.x**, à la condition que Cilium, cert-manager, ceph-csi, CloudNativePG, Kyverno, Capsule, KEDA et Argo CD la déclarent | Fin de maintenance : 1.35 le 28/02/2027, 1.36 le 28/06/2027, 1.37 le 28/10/2027. Montée d'une mineure à la fois, plan de contrôle d'abord (`kubeadm upgrade plan/apply`), décalage kubelet autorisé jusqu'à N−3 |
| Cilium | 1.20.3 (M26) | 1.20.3 (15/10/2026) ; 1.21.0 en pré-version (documentation `latest` = 1.21.0-dev) | 1.20.x dernière corrective, puis **1.21.x** dès sa publication | **Cilium 1.20 teste Kubernetes 1.33 à 1.36 seulement** ; la 1.21 (en développement) teste 1.34 à 1.37. Au relevé, la montée en 1.37 est donc **bloquée** par Cilium : c'est le cas d'étude du scénario F4-S03 (go/no-go) |
| Ceph | Tentacle 20.2.4 (M08) | 20.2.4 (19/08/2026) ; aucune annonce d'Umbrella (21) | dernière corrective Tentacle disponible (≥ 20.2.5) ; à défaut, mise à jour du système Rocky Linux 10 des hôtes en roulement | `ceph orch upgrade` déjà pratiqué au M08 ; F4 le refait **sous charge mesurée** (RBD du cluster, RGW de l'observabilité, Cinder) |
| OpenStack / Kolla-Ansible | 2026.1 / 22.2.0 (M10) | 2026.2 « Hibiscus » sortie le 30/09/2026 ; Kolla-Ansible **23.0.0.0rc1** (07/10/2026), 22.2.0 dernière stable | **2026.2 avec Kolla-Ansible 23.x stable** | Au relevé, Kolla 23 n'est qu'en RC : si c'est encore le cas quand tu fais F4, la montée se répète sur RC dans une fenêtre d'essai et la production attend la stable (décision écrite) |
| Proxmox VE | 9.x sur `pve01` | 9.2 (21/05/2026) ; Ceph Tentacle 20.2.1 en option, import ESXi corrigé en 9.1 | inchangé (`pve01` n'est jamais mis à niveau par le workbook) | Import OVA/OVF (`qm importovf`, assistant d'import) et `qm disk import` pour les VMDK ; l'assistant d'import ESXi exige un ESXi joignable (absent du lab) |
| Argo CD | 3.5.x (M20) | 3.5.x ; 3.6 GA annoncée le 03/11/2026 | 3.6.x quand elle est publiée | Composant de plateforme monté par GitOps (F4-S05) |
| Kyverno | 1.19.x (M26) | 1.19.x ; 1.20 annoncée vers novembre 2026 | 1.20.x quand elle est publiée | 1.20 supprime `ClusterPolicy` : sans effet chez MédiSphère (politiques CEL seulement depuis le M26), à vérifier par un inventaire |
| CloudNativePG | 1.30.1 (M16, M27) | 1.30.x ; 1.31 non publiée | 1.31.x quand elle est publiée | 1.31 supprime `barmanObjectStore` : MédiSphère n'archive que par le plugin Barman Cloud depuis le M16 (à vérifier sur chaque `Cluster`) |

## Migration de Legacy-RDV et des VMs d'InfoGér (F4)

| Outil | Version | Ce qui compte |
|---|---|---|
| mariadb-operator | **26.6.x** (26.6.0 du 06/06/2026 ; charts OCI `oci://ghcr.io/mariadb-operator/charts/mariadb-operator-crds`, `mariadb-operator`, `mariadb-cluster`) | Licence MIT (projet communautaire, distinct du *MariaDB Enterprise Operator*). 26.6 : prise en charge de Kubernetes 1.36, ancien dépôt Helm et anciens registres d'images **dépréciés** au profit des charts OCI ; 26.3 : restauration à un instant donné. Les charts passent par `plateforme/charts-miroir` (recopiés et signés dans Harbor), comme tout chart tiers depuis le M20 |
| MariaDB | 11.8 LTS (paquet Debian 13 et image `mariadb:11.8`) | Version de la VM d'InfoGér (Debian 12, MariaDB 10.11) plus ancienne : la migration change aussi de version majeure (dump logique, vérification des collations `utf8mb4`) |
| PHP | 8.4 (Debian 13, image officielle `php:8.4-apache`) | `apps/legacy-rdv` est écrit pour 8.4 |
| qemu-img / `qm` | ceux de Proxmox VE 9 | VMDK `streamOptimized` des exports VMware : `qemu-img info`, `qm importovf`, `qm disk import` |

## Changements de comportement qui touchent les finaux

- **Cilium et Kubernetes 1.37** : ne pas monter le plan de contrôle en 1.37 tant que la version de Cilium installée ne la déclare pas ; l'ordre est Cilium d'abord (la nouvelle mineure de Cilium accepte encore 1.36), Kubernetes ensuite.
- **Kolla-Ansible 23** : vérifier la plage `ansible-core` exigée par la 23 (elle change à chaque série) avant de créer l'environnement virtuel de déploiement ; la montée se fait avec `kolla-ansible upgrade` après `pull`, service par service possible avec `--tags`.
- **Composants de plateforme** : les montées de mineure (Argo CD 3.6, Kyverno 1.20, CloudNativePG 1.31) passent par une MR dans `plateforme/charts-miroir` puis `plateforme/gitops` ; chaque note de version est lue pour les suppressions d'API (*breaking changes*) avant la MR.
- **mariadb-operator 26.6** : l'ancien dépôt Helm (non OCI) est déprécié ; installer les CRD **avant** l'opérateur (chart séparé).
