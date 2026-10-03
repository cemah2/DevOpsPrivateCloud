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

Types d'exercices : labs guidés et libres, break & fix (pannes injectées par `lab/bin/break`), questionnaires, revues de configuration, rédaction (runbooks, ADR, post-mortems), exercices chronométrés.

## État

Voir [`AVANCEMENT.md`](AVANCEMENT.md). Le module 00 est disponible ; les suivants sont produits bloc par bloc.

Tu rencontres une erreur dans un exercice ? Note l'exercice, ce que tu as fait et le message d'erreur, et utilise le message « Corriger après tes tests » de [`REPRISE.md`](REPRISE.md).
