# DevOps Private Cloud — Workbook

Workbook pratique et progressif pour passer d'**administrateur système et réseau** à **DevOps / ingénieur plateforme orienté cloud privé**.

Tu rejoins l'équipe Plateforme de **MédiSphère**, éditeur de logiciels de santé qui construit son propre cloud privé sur deux sites. Chaque module est un chantier de l'entreprise, chaque exercice un ticket. À la fin, tu as construit une plateforme complète : hyperviseurs, réseau, stockage Ceph, OpenStack, Kubernetes, CI/CD, GitOps, observabilité, sécurité.

## Commencer

1. Lis [`PLAN.md`](PLAN.md) (fil rouge, matériel, plan réseau, liste des modules).
2. Ouvre le [module 00](modules/00-lab/README.md) et commence par son [introduction](modules/00-lab/enonce/00-introduction.md).

## Organisation

| Dossier | Contenu |
|---|---|
| `modules/NN-…/enonce/` | Les exercices, par palier (découverte → opérationnel → production → expert → mini-projet) |
| `modules/NN-…/checks/` | Scripts de vérification : `lab/bin/check <module> <exercice>` |
| `modules/NN-…/corrige/` | ⚠️ Corrigés détaillés et scripts de panne — à ouvrir après avoir cherché |
| `finaux/` | Workbooks finaux multi-technologies (à venir) |
| `lab/` | Outillage commun du lab |
| `annexes/` | Prérequis entre modules, correspondance avec les certifications, glossaire, versions et changements de comportement |

Types d'exercices : labs guidés et libres, break & fix (pannes injectées par `lab/bin/break`), questionnaires, revues de configuration, rédaction (runbooks, ADR, post-mortems), exercices chronométrés.

## État

Voir [`AVANCEMENT.md`](AVANCEMENT.md). Les **blocs A** (fondations automatisées, modules 00 à 06), **B** (infrastructure cloud privé, modules 07 à 11), **C** (conteneurs et Kubernetes, modules 12 à 18), **D** (livraison, modules 19 et 20), **E** (observabilité, modules 21 à 23) et **F** (sécurité, modules 24 à 26) sont disponibles.

| # | Module | Exercices |
|---|---|---|
| 00 | [Positionnement et montage du lab](modules/00-lab/README.md) | 49 + mini-projet |
| 01 | [Git et workflow professionnel](modules/01-git/README.md) | 46 + mini-projet |
| 02 | [Scripting d'automatisation](modules/02-scripting/README.md) | 45 + mini-projet |
| 03 | [Images dorées](modules/03-images/README.md) | 24 + mini-projet |
| 04 | [Gestion de configuration (Ansible)](modules/04-ansible/README.md) | 45 + mini-projet |
| 05 | [Infrastructure as Code (OpenTofu)](modules/05-iac/README.md) | 45 + mini-projet |
| 06 | [Services socle](modules/06-services-socle/README.md) | 45 + mini-projet |
| 07 | [Réseau datacenter et haute disponibilité](modules/07-reseau-ha/README.md) | 45 + mini-projet |
| 08 | [Stockage distribué (Ceph)](modules/08-ceph/README.md) | 45 + mini-projet |
| 09 | [Cluster de virtualisation](modules/09-cluster-proxmox/README.md) | 45 + mini-projet |
| 10 | [OpenStack](modules/10-openstack/README.md) | 45 + mini-projet |
| 11 | [Provisioning bare-metal](modules/11-bare-metal/README.md) | 24 + mini-projet |
| 12 | [Conteneurs](modules/12-conteneurs/README.md) | 45 + mini-projet |
| 13 | [Registre et chaîne d'approvisionnement](modules/13-registre-supply-chain/README.md) | 24 + mini-projet |
| 14 | [Administration Kubernetes](modules/14-kubernetes-admin/README.md) | 45 + mini-projet |
| 15 | [Réseau Kubernetes](modules/15-kubernetes-reseau/README.md) | 45 + mini-projet |
| 16 | [Stockage et données dans Kubernetes](modules/16-kubernetes-stockage/README.md) | 45 + mini-projet |
| 17 | [Packaging (Helm, Kustomize, Helmfile)](modules/17-packaging/README.md) | 24 + mini-projet |
| 18 | [Distributions et cycle de vie des clusters](modules/18-distributions/README.md) | 24 + mini-projet |
| 19 | [Intégration continue](modules/19-ci/README.md) | 45 + mini-projet |
| 20 | [GitOps et déploiement continu](modules/20-gitops/README.md) | 45 + mini-projet |
| 21 | [Métriques et alerting](modules/21-metriques/README.md) | 45 + mini-projet |
| 22 | [Journaux](modules/22-logs/README.md) | 24 + mini-projet |
| 23 | [Traces et profilage](modules/23-traces/README.md) | 24 + mini-projet |
| 24 | [Identité et accès](modules/24-identite/README.md) | 45 + mini-projet |
| 25 | [Secrets](modules/25-secrets/README.md) | 45 + mini-projet |
| 26 | [Durcissement et sécurité à l'exécution](modules/26-durcissement/README.md) | 45 + mini-projet |

Les applications métier de MédiSphère (MédiAgenda, MédiDoc, MédiNotif, Legacy-RDV) sont dans [`apps/`](apps/README.md) à partir du module 12. Les blocs suivants (G, puis les finaux) sont produits bloc par bloc.

Annexes :
- [`annexes/prerequis.md`](annexes/prerequis.md) — graphe des dépendances entre modules, ce que chaque module suppose et laisse en place ;
- [`annexes/certifications.md`](annexes/certifications.md) — exercices utiles pour préparer LFCS/RHCSA, RHCE, Terraform Associate, GitLab, CKA, CKAD, CKS, KCSA, PCA, OTCA, CAPA, CGOA, Vault Associate (équivalence OpenBao)… ;
- [`annexes/glossaire.md`](annexes/glossaire.md) — termes du workbook, avec l'exercice qui les introduit ;
- [`annexes/versions-bloc-A.md`](annexes/versions-bloc-A.md) [`annexes/versions-bloc-B.md`](annexes/versions-bloc-B.md), [`annexes/versions-bloc-C.md`](annexes/versions-bloc-C.md), [`annexes/versions-bloc-DE.md`](annexes/versions-bloc-DE.md) et [`annexes/versions-bloc-F.md`](annexes/versions-bloc-F.md) — versions de référence des blocs A à F et changements de comportement à connaître.

Tu rencontres une erreur dans un exercice ? Note l'exercice, ce que tu as fait et le message d'erreur, et utilise le message « Corriger après tes tests » de [`REPRISE.md`](REPRISE.md).
