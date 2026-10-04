# RB-013 — La forge est en panne : diagnostic par symptôme

| | |
|---|---|
| Service | Forge GitLab `git01` (VMID 1004, 10.10.20.12) et runner `runner01` (VMID 1007, 10.10.20.15) |
| Rédigé | M01-E47 (PLAT-290), à partir des incidents INC-2781 à INC-2788 |
| Durée attendue | 15 à 45 min selon le symptôme |
| Escalade | Karim Benali (plateforme), puis Claire Morel ; Sophie Laurent si une clé d'hôte ou un jeton est en cause |

## Déclencheur

Alerte de supervision ou remontée d'un utilisateur : interface web en erreur, `git push`/`git clone` refusés, pipelines bloqués, release automatique en échec.

## Prérequis

- Accès `ssh git01` et `ssh runner01` (alias en adresse IP, compte `admin`) ; en dernier recours, console de la VM (`qm terminal <VMID>` sur `pve01`).
- Jeton en lecture `~/.config/workbook/gitlab-checks.token` ; jeton d'administration (`api`) pour les corrections par l'API.
- Script de triage `triage-forge.sh` (dépôt `plateforme/medisphere`, `forge/outils/`).

## 0. Triage (5 min)

```
admin@adm01:~$ forge/outils/triage-forge.sh
```

Note l'heure, les portes KO, et envoie la première communication (#astreinte). Rejoue la sonde **après chaque correction**.

## 1. Interface web en 502

| Étape | Commande | Résultat attendu |
|---|---|---|
| Services | `sudo gitlab-ctl status` deux fois à 10 s d'intervalle | tous `run:`, PID et durée de Puma stables |
| NGINX | `sudo gitlab-ctl tail nginx` pendant un `curl` | pas de `connect() to unix:… failed` |
| Workhorse | `sudo gitlab-ctl tail gitlab-workhorse` | pas de `badgateway … dial unix` |
| Puma | `sudo gitlab-ctl tail puma` | `Listening on unix:///var/opt/gitlab/gitlab-rails/sockets/gitlab.socket`, pas d'`EACCES` |
| Sockets | `sudo ss -xlp \| grep -E 'gitlab\|workhorse'` ; `sudo stat -c '%U:%G %a' /var/opt/gitlab/gitlab-rails/sockets` | `gitlab.socket` et `sockets/socket` à l'écoute ; `git:… 750` |

Correctif d'un fichier ou d'un droit géré par omnibus modifié à la main : vérifier que `/etc/gitlab/gitlab.rb` est conforme à la dernière sauvegarde de configuration, le copier, puis `sudo gitlab-ctl reconfigure` (garder sa sortie : elle prouve la dérive). Compter 1 à 3 min de démarrage de Puma. Vérification : `/-/readiness` depuis `git01`.

Retour arrière : restaurer `gitlab.rb` copié, `reconfigure`.

## 2. `git push` refusé

1. `git remote -v` (URL de **push**), `git config --show-origin --get-all remote.origin.pushurl`, `git config --global --get-regexp 'url\..*insteadof'`.
2. Même push depuis un clone neuf dans `/tmp`, et vers `formation/git-labo` : une personne, un projet ou toute la forge ?
3. Message `GitLab: …` : réglages du projet (archivé, **Protected branches** : chercher les règles à joker). Message `GL-HOOK-ERR:` : `ls -l <custom_hooks_dir>/pre-receive.d/` sur `git01` ; tout hook absent de `forge/hooks/` est suspect : redéployer avec `forge/hooks/deployer-hooks.sh`.

## 3. Clone/push en SSH impossibles

1. `ssh -vT git@git01.par1.medisphere.internal` : noter la dernière étape réussie.
2. Avant l'authentification : `ssh -G git01.par1.medisphere.internal` (rebond, port, identité). Alerte de clé d'hôte : **comparer** avec `ssh git01 ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` avant tout `ssh-keygen -R` ; empreinte présentée différente de la vraie → arrêt, escalade sécurité.
3. Authentification refusée : `sudo journalctl -u ssh` sur `git01`, `getent shadow git | cut -d: -f8` (expiration).
4. Authentifié puis erreur : `/var/log/gitlab/gitlab-shell/gitlab-shell.log`, `gitlab_url` de `/var/opt/gitlab/gitlab-shell/config.yml` (fichier généré → `reconfigure`).

## 4. Jobs bloqués en attente

1. Message du job bloqué ; pipeline de `main` comparé à celui d'une MR.
2. `GET /runners/:id` : `tag_list` (doit contenir `shell`, `socle`), `access_level` (`not_protected`), `paused`, `contacted_at`.
3. Sur `runner01` : `journalctl -u gitlab-runner --since -10min` (`forbidden` = jeton ; `dial tcp`/`no route` = résolution ou réseau ; `x509` = CA), `getent hosts git01.par1.medisphere.internal`, `sudo gitlab-runner verify`.
4. **Ne jamais réenregistrer** le runner : corriger le réglage, ou réinitialiser son jeton d'authentification dans GitLab et le reporter dans `config.toml` (root, 600).

## 5. Release automatique en échec

1. Premier message d'erreur du job `release` (code `E…` de semantic-release, ou message du script du gabarit).
2. Jeton `bot-release` (actif, dernière utilisation), variable `GITLAB_TOKEN` (protégée, masquée, portée `*`), étiquettes protégées `v*` (création : Maintainers), `npm ls --prefix /opt/release-tools --depth=0` sur `runner01`.
3. Rotation du jeton : renouveler et écrire la valeur directement dans la variable, sans l'afficher. Outils : `installer-release-tools.sh` de `plateforme/ci-templates`. Jamais d'étiquette posée à la main.

## Vérification finale

`triage-forge.sh` entièrement OK ; `lab/bin/check 01 36` à `01 40` verts ; une MR de test passe de bout en bout (pipeline, fusion, release si applicable).

## Après l'incident

Communication de fin, journal de diagnostic publié par MR, post-mortem si P1/P2 (`docs/socle/post-mortems/`).
