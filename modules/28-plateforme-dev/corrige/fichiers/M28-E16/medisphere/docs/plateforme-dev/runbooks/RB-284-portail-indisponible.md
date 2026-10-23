# RB-284 — Le portail développeurs est indisponible

> Alerte `PortailIndisponible` (critique, équipe plateforme) ou signalement d'une équipe. Rédigé en M28-E16. Propriétaire : équipe Plateforme.

## Impact

- **Touché** : `https://portail.apps.par1.medisphere.internal` (catalogue, création de service par modèle, documentation TechDocs, vue Kubernetes des équipes).
- **Pas touché** : les applications (MédiAgenda, MédiNotif, MédiDoc) tournent ; les déploiements continuent (MR + Argo CD) ; GitLab, Argo CD et Grafana restent les voies de secours. Une création de service peut attendre ou se faire à la main en suivant le guide du chemin balisé (M28-E12).
- Priorité : **P3** en journée (gêne), jamais réveil la nuit. Communiquer sur le canal des équipes.

## Diagnostic, par étage

| Étage | Commande | Normal |
|---|---|---|
| 1. Nom et Gateway | `curl -sk -o /dev/null -w '%{http_code}\n' https://portail.apps.par1.medisphere.internal/.backstage/health/v1/readiness` ; `kubectl -n portail get httproute` | `200` ; route `Accepted` |
| 2. Pods | `kubectl -n portail get pods -o wide` ; `kubectl -n portail describe pod <pod>` ; `kubectl -n portail logs <pod> --previous` | 2 pods `Running`, `READY 1/1`, sur deux nœuds |
| 3. Base | `kubectl -n portail get cluster portail-db` ; `kubectl -n portail logs <pod> \| grep -i -E 'knex\|postgres\|ECONNREFUSED'` | `Cluster in healthy state` |
| 4. OIDC | journaux : `auth` / `oidc` ; `curl -s https://sso.par1.medisphere.internal/realms/medisphere/.well-known/openid-configuration` | page de découverte servie |
| 5. GitLab | journaux : `gitlab`, `401`, `403` ; `kubectl -n portail get externalsecrets` | ExternalSecret `Ready`, pas de 401 |
| 6. Version | `argocd app history portail` ; `kubectl -n portail get deploy -o jsonpath='{..image}'` | image = dernière version promue |

Journaux dans Grafana (source « Loki — plateforme ») : `{namespace="portail"}`.

## Actions

- **Pods en échec après une montée de version** : retour arrière par MR (`git revert` de la MR de promotion dans `plateforme/gitops/valeurs/portail/`), synchronisation de l'Application `portail`. Si la nouvelle version a migré les schémas des plugins, vérifier dans les notes de version que l'ancienne accepte le schéma migré ; sinon restaurer la base (ci-dessous) **avant** de redémarrer l'ancienne version.
- **Base indisponible** : traiter comme une base CNPG (RB-16x) ; restauration :
  1. vérifier la dernière sauvegarde : `kubectl -n portail get backups --sort-by=.metadata.creationTimestamp` ;
  2. créer un cluster `portail-db-restauree` en `bootstrap.recovery` depuis `cnpg-s3` (modèle : `essais/portail-db-restauration.yaml` du M28-E16), vérifier, puis repointer le portail (valeurs : hôte de la base) par MR ; garder l'ancien cluster jusqu'à validation.
- **401 de GitLab** : jeton de `svc-portail` expiré ou changé → RB-288.
- **OIDC** : Keycloak indisponible → RB-24x ; le portail reprend seul.

## Vérification et clôture

`lab/bin/check 28 16` vert ; sonde `probe_success{job="blackbox-portail"}` à 1 ; une création d'essai par le modèle (sur un nom fictif, retirée ensuite) si l'incident touchait le *scaffolder*. Post-mortem si l'indisponibilité dépasse une demi-journée.
