# Revue de la MR « MédiNotif dans Argo CD » (Lucas Martin) — M20-E21

> Exemple de revue. Verdict : **refusée en l'état** ; 18 défauts, dont 6 bloquants (★). Version corrigée
> dans `corrige/`. Pour chaque défaut : le risque concret, puis la correction.

| # | Fichier | Défaut | Risque | Correction |
|---|---|---|---|---|
| 1 ★ | `secret-rabbitmq.yaml` | Secret dans Git, en base64 (un encodage, pas un chiffrement), mot de passe en commentaire | identifiants lisibles par tout lecteur du dépôt, **pour toujours** (historique Git, clones, caches) | supprimer le fichier, **changer le mot de passe** (il est compromis), Secret créé par `secrets-k8s.sh` (composant `medinotif-*`) depuis le Vault `critique` ; External Secrets au M25 |
| 2 ★ | `applicationset-medinotif.yaml` | `goTemplate: true` avec la syntaxe *fasttemplate* `{{path.basename}}`, `{{path}}` | rendu en échec (`function "path" not defined`) : aucune Application générée, l'ApplicationSet en erreur | `{{.path.basename}}`, `{{.path.path}}` |
| 3 ★ | AppSet + `medinotif-prod.yaml` | `medinotif-prod` décrite **deux fois** : par le générateur de répertoires (dossier `overlays/prod`) et par le fichier à part | l'ApplicationSet adopte l'Application du fichier et la réécrit ; l'application racine la remet : bataille permanente, réglages de prod imprévisibles | une seule source : un générateur **liste** explicite (dev, prod) avec `templatePatch` pour la prod, plus de fichier à part |
| 4 ★ | AppSet, prod | synchronisation automatique avec `prune` et `selfHeal` en prod | une erreur fusionnée sur `main` part en prod sans geste humain, et `prune` y supprime des objets | prod en synchronisation manuelle (PLAN §4.11), `prune` décidé à la synchronisation |
| 5 ★ | AppSet, prod | `allowEmpty: true` | un rendu vide (dossier vidé par erreur, chemin renommé) supprime **toute** l'application | retiré (défaut : refus de synchroniser un rendu vide) |
| 6 ★ | AppSet, prod, RabbitMQ | finaliseur `resources-finalizer.argocd.argoproj.io`, sans `preserveResourcesOnDeletion` ni politique `applicationsSync` | supprimer l'ApplicationSet (ou retirer un dossier d'`overlays/`) supprime les Applications **et** leurs charges, prod comprise | `syncPolicy.preserveResourcesOnDeletion: true`, `applicationsSync: create-update`, pas de finaliseur en prod |
| 7 | les trois | `project: default` | aucun cloisonnement : n'importe quel dépôt, n'importe quel espace, objets de cluster | AppProject `medinotif` (sources `medinotif/*`, destinations `medinotif-*`, aucun objet de cluster) ; RabbitMQ dans `plateforme` |
| 8 | AppSet, prod | `targetRevision: HEAD` / `revision: HEAD` | la prod suit la branche par défaut, quelle qu'elle soit (changement de branche par défaut, branche poussée en force) | `main`, protégée, fusion par MR (Maintainers) |
| 9 | AppSet, prod, RabbitMQ | `CreateNamespace=true` | espaces créés sans étiquettes PSA, sans quota, sans politique réseau, hors de `plateforme/k8s` | `CreateNamespace=false` ; espaces `medinotif-dev`, `medinotif-prod` créés par la plateforme (`espaces/`) |
| 10 | AppSet | `ignoreDifferences` : `/spec` de **tous** les Deployments | plus aucune dérive visible sur les Deployments : image changée à la main, réplicas, sondes… | rien à ignorer pour MédiNotif ; sinon un champ précis d'un objet nommé (`/spec/replicas` du Deployment sous HPA) |
| 11 | AppSet | `retry.limit: -1` | réessais sans fin d'une synchronisation vouée à l'échec, charge inutile, alerte noyée | limite finie (3) et recul exponentiel |
| 12 | prod | `Replace=true` | `kubectl replace` : les champs posés par d'autres (HPA, contrôleurs) sont écrasés, objets recréés, coupure | retiré ; `ServerSideApply=true` |
| 13 | les trois | `ServerSideApply=true` absent | les CRD de l'opérateur RabbitMQ dépassent la limite de l'annotation `last-applied-configuration` (« Too long ») : synchronisation en échec ; pas de gestion des champs partagés | `ServerSideApply=true` partout |
| 14 | RabbitMQ | chart tiré d'Internet (`charts.bitnami.com`) | Argo CD ne sort pas vers Internet (M20-E25) ; dépendance à un tiers sans contrôle ; catalogue gratuit de Bitnami retiré (images non maintenues, PLAN §4.11) | manifestes officiels de l'opérateur (`cluster-operator.yml`, version figée) recopiés dans `plateforme/gitops` ; un chart tiers, s'il y en avait un, passerait par `plateforme/charts-miroir` |
| 15 | RabbitMQ | `targetRevision: "*"` | chaque nouvelle version du chart part en prod sans relecture | version exacte, dans le chemin du dossier (`tiers/rabbitmq-operateur/v2.23.1`) |
| 16 | RabbitMQ | `$valeurs/…` alors que la source Git porte `ref: values` | la référence `$valeurs` ne désigne aucune source : rendu en échec | même nom des deux côtés (`ref: values` et `$values/…`) ; ici, plus de multi-sources (une source Git suffit) |
| 17 | RabbitMQ | image `tag: latest` | version inconnue, non reproductible, refusée par la VAP `medisphere-images` (M14-E18) | version figée (et digest) par le cache Harbor |
| 18 | RabbitMQ | `destination.namespace: "*"` ; `automated.prune` sans `selfHeal` | un espace « * » n'existe pas (destination invalide) ; demi-mesure : supprime, mais ne corrige pas la dérive | espace `rabbitmq-system` (opérateur) déclaré par la plateforme ; `prune` + `selfHeal` pour un service de plateforme |

## Ce qui est bien

- l'idée d'un ApplicationSet (un seul gabarit pour les environnements) ;
- la séparation entre l'application (`medinotif/deploiement`) et son intergiciel (RabbitMQ, côté plateforme).

## Pour Lucas

Avant d'ouvrir une MR GitOps, trois commandes : `argocd appset generate <fichier>` (ce que génère
l'ApplicationSet), `argocd app diff --local` (ce qui changerait), et un `grep -r "kind: Secret"`.
