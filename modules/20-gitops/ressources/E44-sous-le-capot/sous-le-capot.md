# Sous le capot : du commit à l'objet (M20-E44, PLAT-2144)

> Squelette du livrable. À copier dans `docs/livraison/gitops/sous-le-capot.md` de
> `plateforme/medisphere`, puis à remplir avec TES mesures et TES sorties (raccourcies, sans jeton).
> Chaque affirmation s'appuie sur une commande que tu as lancée ; cite-la.

## Chronologie mesurée d'une livraison en dev

| Étape | Horodatage (hh:mm:ss) | Source de la mesure | Écart avec l'étape précédente |
|---|---|---|---|
| Commit de la MR | | API GitLab (`committed_date`) | — |
| Fusion de la MR | | API GitLab (`merged_at`) | |
| Webhook reçu par Argo CD | | journal d'`argocd-server` | |
| Rafraîchissement de l'Application | | journal du contrôleur | |
| Manifestes générés (repo-server) | | journal du repo-server (debug) | |
| Début de l'opération de synchronisation | | `.status.operationState.startedAt` | |
| Fin de l'opération | | `.status.operationState.finishedAt` | |
| Pod neuf créé | | `kubectl get pods` | |
| Pod neuf prêt | | condition `Ready` | |

Même mesure **sans webhook** (interrogation périodique) : …

## Le repo-server et son cache

- Où sont les copies des dépôts dans le pod, et comment s'appellent-elles :
- Ce que le repo-server met en cache, la clé, la durée (`reposerver.repo.cache.expiration`) :
- Ce qu'un `--hard-refresh` change :

## Redis

- Rôle de Redis pour Argo CD (et ce qui se passe s'il disparaît) :
- Clés relevées (familles, pas de valeur) :

## Le contrôleur d'applications

- Réconciliation : déclencheurs, période (`timeout.reconciliation`), niveaux de comparaison :
- Cache d'état du cluster : ce qu'il surveille (watch) et pourquoi Argo CD n'interroge pas l'API à
  chaque comparaison :
- Lignes de journal en `debug` qui montrent une réconciliation et ses durées :

## Comparaison (diff)

- Stratégie de comparaison en usage sur `mediagenda-dev`, et d'où tu le sais (objet, champ, valeur) :
- Rendu servi par Argo CD comparé au rendu local (`kubectl kustomize`) : identiques ? différences et
  pourquoi :

## Annotation de suivi

- Valeur réelle de `argocd.argoproj.io/tracking-id` sur le Deployment de dev :
- Ce qui se passe si on la retire, si on la copie sur un autre objet :

## Ce que j'en retiens pour l'exploitation

- Trois métriques à surveiller au M21 :
- Deux réglages à revoir :
