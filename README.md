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

Voir [`AVANCEMENT.md`](AVANCEMENT.md). Les **blocs A** (fondations automatisées, modules 00 à 06) et **B** (infrastructure cloud privé, modules 07 à 11) sont disponibles.

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

Les blocs suivants (C à G, puis les finaux) sont produits bloc par bloc.

Annexes :
- [`annexes/prerequis.md`](annexes/prerequis.md) — graphe des dépendances entre modules, ce que chaque module suppose et laisse en place ;
- [`annexes/certifications.md`](annexes/certifications.md) — exercices utiles pour préparer LFCS/RHCSA, RHCE, Terraform Associate, GitLab, CKA… ;
- [`annexes/glossaire.md`](annexes/glossaire.md) — termes du workbook, avec l'exercice qui les introduit ;
- [`annexes/versions-bloc-A.md`](annexes/versions-bloc-A.md) et [`annexes/versions-bloc-B.md`](annexes/versions-bloc-B.md) — versions de référence des blocs A et B et changements de comportement à connaître.

Tu rencontres une erreur dans un exercice ? Note l'exercice, ce que tu as fait et le message d'erreur, et utilise le message « Corriger après tes tests » de [`REPRISE.md`](REPRISE.md).
