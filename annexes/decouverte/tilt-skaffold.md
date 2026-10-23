# Tilt et Skaffold — fiche découverte

> Fiche courte du module 28 (plateforme développeurs). Ni Tilt ni Skaffold ne sont installés (décision : ADR-0280, M28-E17). Versions relevées le 23/10/2026 : **Tilt 0.37.x** (0.37.8), **Skaffold 2.25.x** (2.25.0). Tous deux sous licence Apache 2.0.

## Le problème : la boucle de développement interne

La **boucle interne** (*inner loop*), c'est ce que fait un développeur cent fois par jour : modifier le code, construire, lancer, voir le résultat. La **boucle externe**, c'est la livraison : MR, CI, image signée, Argo CD (M19-M20). Quand une application ne se lance plus seule sur un poste (elle a besoin d'autres services, d'opérateurs, de CRD), la boucle interne passe par un cluster de développement — et devient lente si chaque essai demande `docker build`, `docker push`, `kubectl apply`.

## Ce que font Tilt et Skaffold

Les deux surveillent les fichiers, reconstruisent l'image, la chargent dans un cluster local (kind, k3d, minikube) ou distant, appliquent les manifestes (Kustomize, Helm), suivent les journaux, transfèrent les ports — et savent **synchroniser des fichiers dans un conteneur en marche** sans reconstruire (Python, Go recompilé dans le conteneur…).

| | Tilt 0.37 | Skaffold 2.25 |
|---|---|---|
| Configuration | `Tiltfile` (Starlark, un dialecte de Python) : programmable | `skaffold.yaml` (déclaratif) : profils, étapes `build`, `test`, `deploy`, `verify` |
| Interface | tableau de bord web (état des ressources, journaux, boutons d'action) | ligne de commande (`skaffold dev`, `run`, `debug`) |
| Usage hors poste | essentiellement le poste | aussi en CI (`skaffold build`, `skaffold render` pour produire les manifestes) |
| Écosystème | extensions (`load('ext://…')`) | intégré à Cloud Code (IDE), maintenu par Google |

## Et `docker compose` (M12) ?

`docker compose` lance déjà MédiAgenda avec PostgreSQL et Valkey sur un poste, en quelques secondes, avec rechargement du code par un volume : pour trois applications simples, c'est **suffisant** et sans cluster. Tilt ou Skaffold apporteraient un environnement de développement plus proche de la recette (mêmes manifestes Kustomize, mêmes politiques), au prix d'un cluster local par développeur et d'un outil de plus.

## Place dans le chemin balisé

Si le besoin apparaît, l'outil se placerait dans le **modèle `nouveau-service`** du portail (M28-E08) : un `Tiltfile` ou un `skaffold.yaml` généré avec le squelette, pointant sur l'overlay `dev` du dépôt de déploiement et sur un cluster kind local — **jamais** sur `k8s-par1`, qui n'est pas un poste de développement.

**Signal de révision** (ADR-0280) : une application qui ne se lance plus en local sans le cluster, ou plus de dix minutes entre une modification et son essai.

## Pour aller plus loin

- Tilt : <https://docs.tilt.dev/>
- Skaffold : <https://skaffold.dev/docs/>
- kind (cluster local, M18) : <https://kind.sigs.k8s.io/>
