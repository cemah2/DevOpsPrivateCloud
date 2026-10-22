# RB-192 — Monter GitLab, les runners et l'agent

| | |
|---|---|
| Rédigé | M19-E26 (CHG-2026), 19.4.z → 19.5.z |
| Généralise | RB-011 (forge seule, M01) au périmètre de la CI |
| Fréquence | correctifs de sécurité : sous 7 jours ; mineure : chaque mois ou trimestre, **jamais** au-delà d'un arrêt obligatoire (`x.2`, `x.5`, `x.8`, `x.11`) |
| Durée | 1 h de fenêtre |

## 1. Règle d'alignement

GitLab, les runners (gestionnaires) et l'agent restent sur la **même mineure** ; un runner ou un agent d'une mineure **plus ancienne** que GitLab est toléré le temps de la fenêtre, jamais l'inverse. Les charts : `gitlab/gitlab-runner` (appVersion = version du runner) et `gitlab/gitlab-agent` (appVersion = version de l'agent) ; lire `appVersion` dans l'index (`helm search repo gitlab/gitlab-runner --versions`).

## 2. J-7 : préparation

1. Notes de version de chaque mineure **traversée** et notes de montée ; recherche des ruptures pour CI, runner, agent, omnibus.
2. Chemin de montée (outil *Upgrade Path*).
3. Inventaire des versions **par l'API** :
   ```
   admin@adm01:~$ GL=https://git01.par1.medisphere.internal/api/v4; T=~/.config/workbook/gitlab-checks.token
   admin@adm01:~$ curl -sSf -H "PRIVATE-TOKEN: $(<$T)" $GL/version | jq .version
   admin@adm01:~$ for id in $(curl -sSf -H "PRIVATE-TOKEN: $(<$T)" "$GL/runners/all?per_page=100" | jq '.[].id'); do
   >   curl -sSf -H "PRIVATE-TOKEN: $(<$T)" "$GL/runners/$id/managers" | jq -r --arg id "$id" '.[] | "\($id) \(.system_id) \(.version) \(.status)"'; done
   admin@adm01:~$ kubectl -n gitlab-agent get deploy -o jsonpath='{..image}{"\n"}'
   ```
4. Recherche des usages de variables dont le format change (ex. 19.5 : `CI_RUNNER_TAGS`, `CI_JOB_TAGS`).
5. Plan de changement `docs/livraison/ci/changements/CHG-<n>.md` ; annonce.

## 3. J0 : sauvegardes et gel

1. Migrations d'arrière-plan : `sudo gitlab-rake gitlab:background_migrations:list` → rien en cours ; sinon **report**.
2. Sauvegarde PBS de la VM 1004 (tâche manuelle) et vérification ; `sudo gitlab-backup create STRATEGY=copy` ; copie chiffrée de `/etc/gitlab/gitlab-secrets.json` et `gitlab.rb` (Vault `critique`, RB-010) ; `qm snapshot 1004 avant-<version>` (sans mémoire).
3. Pause des runners (API, ou *Admin → CI/CD → Runners*), attente de la fin des jobs en cours.

## 4. GitLab

```
admin@git01:~$ sudo apt-mark unhold gitlab-ce && sudo apt-get update && sudo apt-get install gitlab-ce=<19.5.Z>-ce.0 && sudo apt-mark hold gitlab-ce
```
Contrôles (dans l'ordre) : `gitlab-ctl status` ; `readiness?all=1` ; `/api/v4/version` ; `gitlab-rake gitlab:check SANITIZE=true` ; `gitlab-rake gitlab:doctor:secrets` ; `gitlab:background_migrations:list` (celles de la nouvelle version : en cours ou terminées, **aucune en échec**) ; connexion web, clone SSH et HTTPS. Puis réouverture (point de non-retour).

## 5. Runners

1. `plateforme/k8s` : version du chart des **deux** releases dans `releases/50-ci.yaml.gotmpl`, clés renommées des values (0.94 : `image.repository`) ; `helmfile -e par1 -l composant=gitlab-runner diff`, relecture, `apply` ; idem `gitlab-runner-protege`.
2. Réactiver le runner, contrôler **chaque gestionnaire** (`/runners/:id/managers` : version, `contacted_at` récent) ; supprimer les gestionnaires périmés s'il en reste (`stale`).
3. Job témoin sur `k8s` et sur `protege` (référence protégée) ; l'image *helper* d'un pod de job doit porter la nouvelle version (`kubectl -n ci-jobs get pod -l … -o jsonpath='{..image}'`).
4. `runner01`, `runner02` : variable `gitlab_runner_version` (Ansible), un hôte à la fois, réactivation, job témoin `shell` / `docker`.

## 6. Agent

1. Chart de la même mineure (`appVersion`), `helmfile … -l composant=gitlab-agent apply`.
2. Adresse : `grpcs://git01.par1.medisphere.internal` (depuis 19.5) ; `kasCaCert` = racine MédiSphère.
3. Contrôles : journaux d'`agentk` (connexion établie, pas d'erreur TLS ni `HTTP/1.1`), *Opérer → Clusters Kubernetes* : « Connecté » ; job `deployer-dev` de `mediagenda/deploiement` relancé.
4. Retour arrière immédiat : adresse `wss://git01.par1.medisphere.internal/-/kubernetes-agent/`.

## 7. Après

- Pipelines témoins (MR et étiquette de `mediagenda/api`, `main` de `mediagenda/deploiement`) ; `lab/bin/check 19 26`.
- Instantané de VM supprimé après 24 à 48 h ; versions dans l'inventaire ; plan de changement complété (durées réelles) ; prochaine fenêtre inscrite au calendrier (prochain arrêt obligatoire).

## 8. Retour arrière

| Situation | Geste |
|---|---|
| Échec du paquet ou des migrations, GitLab pas rouvert | `qm rollback 1004 avant-<version>` (VM arrêtée), démarrage, contrôles, runners réactivés |
| Problème après réouverture | pas de rollback de VM (perte des écritures) : correctif suivant, ou restauration RB-010 annoncée |
| Runner 19.5 défaillant | release précédente (commit d'avant, `helmfile apply`) : un runner d'une mineure plus ancienne fonctionne avec GitLab 19.5 |
| Agent non connecté en `grpcs://` | remettre `wss://`, analyser ensuite (HTTP/2 de NGINX, certificat) |
| Rétrogradation du paquet GitLab | **interdite** (schéma de base migré) |
