# RB-288 — Le portail ne crée plus de services

> Rédigé en M28-E22. Propriétaire : équipe Plateforme.

## Diagnostic
1. Relancer le modèle sur un nom fictif ; lire le journal de la tâche (étape en échec, message), puis Loki : `{namespace="portail"} |= "<taskId>"`.
2. Selon le message :

| Message | Cause probable | Vérifier |
|---|---|---|
| `Template action with ID '…' is not registered` | modèle cassé (action inconnue) | `git log -p` de `plateforme/portail-modeles` ; entité `Template` au catalogue |
| `No matching integration configuration for host …` | `repoUrl` vers un hôte sans intégration | `integrations.gitlab` de `app-config.production.yaml` ; le modèle |
| `401 Unauthorized` (GitLab) | jeton de `svc-portail` expiré ou révoqué | `kubectl -n portail get externalsecret portail` ; date d'expiration du jeton dans GitLab |
| `403 Forbidden` (GitLab) | droits de `svc-portail` insuffisants dans le groupe | `GET /groups/<groupe>/members/all` : rôle de `svc-portail` |

## Rotation du jeton de `svc-portail`
1. Nouveau jeton (API ou interface GitLab, compte de service), expiration ≤ 90 jours, portées du M28-E06.
2. `bao kv patch -mount=kv plateforme/portail gitlab_token=<NOUVEAU>` (jamais dans un ticket).
3. `kubectl -n portail annotate externalsecret portail force-sync=$(date +%s) --overwrite`, puis `kubectl -n portail rollout restart deploy/portail` (le backend lit la variable au démarrage).
4. Essai du modèle sur un nom fictif ; révocation de l'ancien jeton.

## Après
Supprimer projets et MR d'essai ; vérifier qu'aucune entité d'essai ne reste au catalogue.
