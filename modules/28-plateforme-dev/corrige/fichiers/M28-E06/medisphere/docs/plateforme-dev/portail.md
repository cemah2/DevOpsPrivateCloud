# Portail développeurs (Backstage)

> Plateforme développeurs — M28-E06 (PLAT-2906), complété en M28-E10. Responsable : équipe Plateforme. Adresse : <https://portail.apps.par1.medisphere.internal>.

## Architecture

| Élément | Valeur |
|---|---|
| Application | Backstage **1.56.2**, créée par `@backstage/create-app` 0.9.3 (Node.js 24, Yarn 4), nouveau backend et nouveau système de frontend ; projet GitLab `plateforme/portail` |
| Image | `registry.par1.medisphere.internal/plateforme/portail:vX.Y.Z`, Dockerfile multi-étapes de la documentation, construite par BuildKit (composant `construction-image`), signée (`securite`) |
| Déploiement | chart `backstage` 2.10.2 (recopié dans Harbor), Application Argo CD `portail`, espace `portail` (PSA `restricted`), valeurs `plateforme/gitops/valeurs/portail/values.yaml` |
| Base | CloudNativePG `portail-db` (1 instance, PostgreSQL 18), base `portail`, **un schéma par plugin** (`pluginDivisionMode: schema`), TLS vérifié (`portail-db-ca`) |
| Connexion | OIDC Keycloak (client confidentiel `backstage`), résolution `preferred_username` → entité `User` du catalogue (module local `authOidcMedisphere`) ; pas de fournisseur invité |
| Accès machine | `backend.auth.externalAccess` statique, sujet `wb-checks`, plugin `catalog`, lecture seule |

## Configuration en couches

1. `app-config.yaml` (dépôt) : valeurs de développement local (SQLite en mémoire, `localhost`).
2. `app-config.production.yaml` (dépôt, dans l'image) : adresses publiques, PostgreSQL, OIDC, accès externe, catalogue. **Aucun secret** : des `${VARIABLES}`.
3. Variables d'environnement du pod : Secret `portail` (ExternalSecret, `kv/plateforme/portail`) et Secret `portail-db-app` (CNPG).

Le chart remplace la commande de l'image : les `--config` sont redonnés par `backstage.args` (sinon seule la couche 1 serait lue). Contrôle de la configuration en CI : `backstage-cli config:check --lax`.

## Secrets

| Clé de `kv/plateforme/portail` | Variable | Usage |
|---|---|---|
| `oidc_client_secret` | `AUTH_OIDC_CLIENT_SECRET` | client `backstage` (même valeur imposée à Keycloak par OpenTofu) |
| `session_secret` | `AUTH_SESSION_SECRET` | session OIDC (identique entre réplicas) |
| `checks_token` | `BACKSTAGE_CHECKS_TOKEN` | accès externe des vérifications ; copie sur `adm01` : `~/.config/workbook/backstage-checks.token` (600) |
| `gitlab_token` | `GITLAB_TOKEN` | compte de service `svc-portail` (E07) |
| `ldap_mot_de_passe` | `LDAP_SECRET` | compte système `svc-portail` (E07) |
| `techdocs_cle`, `techdocs_secret` | `TECHDOCS_S3_…` | lecture de `portail-techdocs` (E10) |

Rotation : nouvelle valeur dans le coffre ; ESO met le Secret à jour dans l'heure ; redémarrer le Deployment (Backstage ne relit pas sa configuration d'authentification à chaud).

## Contrôles

```
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://portail.apps.par1.medisphere.internal/.backstage/health/v1/readiness
200
admin@adm01:~$ curl -s -H "Authorization: Bearer $(<~/.config/workbook/backstage-checks.token)" \
    https://portail.apps.par1.medisphere.internal/api/catalog/entities?limit=1 | jq length
1
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $(<~/.config/workbook/backstage-checks.token)" \
    https://portail.apps.par1.medisphere.internal/api/scaffolder/v2/tasks
403
```

## Mise à jour et retour arrière

- **Montée de Backstage** : `yarn backstage-cli versions:bump` dans `plateforme/portail` (MR, CI), nouvelle étiquette, puis MR sur `valeurs/portail/values.yaml` (étiquette et empreinte). Les migrations des schémas des plugins tournent au démarrage du nouveau pod.
- **Retour arrière** : revenir à l'étiquette précédente dans les valeurs **seulement si** les notes de version ne signalent aucune migration de schéma irréversible ; sinon, restauration de `portail-db` (palier 3, M28-E16) avec l'image précédente.
- **Montée du chart** : nouvelle entrée de `charts-miroir`, lecture du `values.yaml` de la nouvelle version, MR sur l'Application.
