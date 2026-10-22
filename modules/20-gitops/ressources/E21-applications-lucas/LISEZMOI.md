# Les Applications de Lucas (M20-E21)

Lucas a préparé l'arrivée de **MédiNotif** dans Argo CD. Sa MR sur `plateforme/gitops` ajoute trois
fichiers et un quatrième dans `medinotif/deploiement`. Il a « tout testé sur son poste avec
`argocd app create` » et demande une fusion rapide : l'équipe de MédiNotif veut sa prod lundi.

| Fichier | Dépôt cible | Contenu |
|---|---|---|
| `applicationset-medinotif.yaml` | `plateforme/gitops`, `applications/` | les environnements de MédiNotif, un par dossier de `overlays/` |
| `medinotif-prod.yaml` | `plateforme/gitops`, `applications/` | « la prod à part, pour être sûr qu'elle se synchronise » |
| `rabbitmq.yaml` | `plateforme/gitops`, `plateforme/` | le RabbitMQ de MédiNotif (opérateur et cluster), chart et valeurs |
| `secret-rabbitmq.yaml` | `medinotif/deploiement`, `base/` | « les identifiants, pour que tout soit dans Git comme le dit le GitOps » |

Contexte : MédiNotif est un *worker* Python qui consomme RabbitMQ (`apps/medinotif`). Dépôt de
déploiement `medinotif/deploiement` (base + overlays `dev` et `prod`, sur le modèle de MédiAgenda),
espaces `medinotif-dev` et `medinotif-prod` à créer.
