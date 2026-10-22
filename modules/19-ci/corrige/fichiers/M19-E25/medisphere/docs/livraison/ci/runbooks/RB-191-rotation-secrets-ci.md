# RB-191 — Faire tourner les secrets de la CI

| | |
|---|---|
| Rédigé | M19-E25 (SEC-2025) |
| Inventaire | `docs/livraison/ci/secrets-ci.md` |
| Fréquence | jetons de promotion et robot Harbor : 60 jours ; autres : voir le calendrier |
| Durée | 10 min par secret, pipeline témoin compris |

## 0. Règles

- Jamais pendant un pipeline d'étiquette ou de `main` du projet consommateur (vérifie la liste des pipelines en cours).
- Une rotation invalide l'ancienne valeur **immédiatement** : prépare la commande de mise à jour de la variable avant de lancer la rotation.
- Aucune valeur dans le terminal ni dans un fichier : tuyaux `jq` vers l'API ou vers `ansible-vault`.
- Après chaque secret : pipeline témoin, et mise à jour de la date dans `secrets-ci.md`.

## 1. Préalables

```
admin@adm01:~$ export GL=https://git01.par1.medisphere.internal/api/v4
admin@adm01:~$ ADM=~/.config/workbook/gitlab-admin.token       # api + admin_mode, durée courte
```

## 2. Jeton de projet `ci-promotion` (`DEPLOIEMENT_TOKEN`)

1. Identifier le jeton :
   ```
   admin@adm01:~$ curl -sSf -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(<$ADM)") \
       "$GL/projects/mediagenda%2Fdeploiement/access_tokens" | jq '.[] | {id, name, active, expires_at, scopes}'
   ```
2. Tourner et remplacer la variable dans la même commande (la variable est **cachée** : on la supprime puis on la recrée avec ses attributs ; la valeur passe par l'entrée standard de `curl`, `value@-`, jamais par ses arguments visibles dans `ps`) :
   ```
   admin@adm01:~$ ID=<ID-DU-JETON>; EXP=$(date -d '+90 days' +%F)
   admin@adm01:~$ curl -sSf -X POST -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(<$ADM)") \
       "$GL/projects/mediagenda%2Fdeploiement/access_tokens/$ID/rotate?expires_at=$EXP" \
     | jq -r .token \
     | { read -r t
         curl -sSf -X DELETE -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(<$ADM)") \
           "$GL/projects/mediagenda%2Fapi/variables/DEPLOIEMENT_TOKEN?filter%5Benvironment_scope%5D=promotion/*"
         printf '%s' "$t" | curl -sSf -X POST -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(<$ADM)") \
           "$GL/projects/mediagenda%2Fapi/variables" \
           --data-urlencode key=DEPLOIEMENT_TOKEN --data-urlencode "value@-" \
           --data-urlencode protected=true --data-urlencode masked_and_hidden=true \
           --data-urlencode "environment_scope=promotion/*" --data-urlencode raw=true > /dev/null; }
   ```
3. Vérifier : le nouveau jeton est `active`, l'ancien `revoked` (la rotation révoque l'ancien) ; pipeline témoin : relancer le job `promouvoir-recette` (manuel) d'une étiquette récente, ou poser une étiquette corrective.
4. Retour arrière : il n'y en a pas pour l'ancien jeton (révoqué). Si la nouvelle valeur est mal recopiée : nouvelle rotation.

## 3. Robot Harbor `robot$medisphere+ci`

1. Le robot est dans l'état OpenTofu `registre` (`plateforme/infra`) : sa durée est fixée par le code (`duration`). Régénérer le secret par l'interface de Harbor (*Robot Accounts → Refresh secret*) ou par l'API (opération de rafraîchissement du secret du robot), en recevant la nouvelle valeur dans un tuyau.
2. Recréer la variable de groupe `HARBOR_ROBOT_TOKEN` (masquée et cachée, protégée) comme au §2.
3. Pipeline témoin : publication d'une version de correctif de `mediagenda/api` ; puis `lab/bin/check 13 05`.
4. Si l'état OpenTofu suit le secret : `tofu plan` du dossier `registre` ne doit montrer aucune dérive non expliquée.

## 4. Jetons des runners (`glrt-`)

1. `POST /runners/:id/reset_authentication_token` (jeton d'administration) → nouvelle valeur dans un tuyau vers `ansible-vault encrypt` du fichier `secrets/<runner>.yml`.
2. `outils/secrets-k8s.sh appliquer <composant>` (`gitlab-runner` ou `gitlab-runner-protege`, table `outils/secrets-k8s.conf`) puis redémarrage du gestionnaire (`kubectl -n gitlab-runner rollout restart deployment/<runner>`).
3. Vérifier : `GET /runners/:id/managers` montre un gestionnaire en ligne contacté il y a moins d'une minute ; un job passe.

## 5. Clé Cosign

Hors de ce runbook : une rotation de la clé de signature change la clé publique que vérifient la porte (E29), Harbor et les consommateurs ; elle suit la procédure du M13 (nouvelle paire, période de double vérification, re-signature des versions en service).

## 6. Après

- Date mise à jour dans `secrets-ci.md` §5.
- `bin/ci-inventaire-variables.sh` : aucune anomalie.
