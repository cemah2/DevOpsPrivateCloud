# Post-mortem — INC-2788 — Forge indisponible puis pipelines de MR bloqués

> Exemple de corrigé (M01-E43), pour la paire E37 variante 2 + E38 variante 4. Rédigé avec le
> modèle de l'équipe (`modules/00-lab/ressources/M00-E46/modele-post-mortem.md`). À ranger dans
> `docs/socle/post-mortems/AAAA-MM-JJ-INC-2788.md` de `plateforme/medisphere`, fusionné par MR.

| | |
|---|---|
| **Statut** | Relu |
| **Date de l'incident** | AAAA-MM-JJ |
| **Rédacteur** | <MOI> (astreinte plateforme) |
| **Relecteurs** | Nadia Roussel, Karim Benali |
| **Sévérité** | P2 : toute l'équipe ne peut plus relire ni fusionner, aucune perte de données, pas d'impact patient |
| **Durée d'impact** | 06:58 → 08:12 (1 h 14) |
| **Services touchés** | forge GitLab (`git01`) : interface web, API, Git en SSH ; CI (`runner01`) pour les MR |

## 1. Résumé

À 06:58, l'interface web de la forge a commencé à répondre « 502 » et Git en SSH a cessé de fonctionner : Puma, l'application de GitLab, redémarrait en boucle car il ne pouvait plus créer sa socket (droits du dossier modifiés). Le service web est revenu à 07:41 après réapplication de la configuration. Une seconde panne, masquée par la première, bloquait ensuite les pipelines de MR : le runner du socle avait été restreint aux branches protégées. Elle a été corrigée à 08:12. Aucune donnée n'a été perdue.

## 2. Impact

- Équipe Plateforme et équipe MédiAgenda (Julien) : impossible de consulter, relire, fusionner, ou pousser en SSH entre 06:58 et 07:41 ; impossible de fusionner (pipeline obligatoire bloqué) jusqu'à 08:12. Trois MR en attente ont été retardées.
- Données : aucune perte ni corruption (dépôts servis par Gitaly, non concernés ; vérifié par `gitlab-rake gitlab:check`).
- Conformité : la traçabilité des changements est intacte ; aucune modification n'a contourné la revue pendant l'incident.

## 3. Chronologie

| Heure | Événement | Source |
|---|---|---|
| ~06:55 | Modification des droits de `/var/opt/gitlab/gitlab-rails/sockets` (root:root 0700) et redémarrage de Puma | `stat` du dossier, journal de Puma |
| 06:58 | Premières 502 | journal NGINX `gitlab_access.log` |
| 07:00 | Remontée de Julien (canal #plateforme) | message |
| 07:04 | Prise en charge par l'astreinte, triage avec `triage-forge.sh` : web KO, API KO, SSH KO, runner « en ligne » | journal de diagnostic |
| 07:08 | 1re communication | #astreinte |
| 07:15 | `gitlab-ctl status` relancé trois fois : PID de Puma différent, durée < 5 s | journal |
| 07:22 | Journal de Puma : `Permission denied` sur la socket ; dossier en root:root 0700 | `gitlab-ctl tail puma` |
| 07:30 | Vérification : `gitlab.rb` inchangé depuis le dernier `reconfigure` (sauvegarde de config du jour) | `ls -l`, `diff` |
| 07:33 | `gitlab-ctl reconfigure` : la sortie montre la remise du propriétaire `git` et du mode 0750 | journal de reconfigure |
| 07:41 | Puma stable, web et API revenus, SSH revenu | `triage-forge.sh` |
| 07:45 | 2e communication (partiellement rétabli) ; sonde : les jobs de MR restent en attente | #astreinte |
| 07:50 | Hypothèse « le runner n'a pas rattrapé la 502 » écartée : le pipeline de `main` passe, celui de la MR non | journal |
| 08:02 | API : `access_level: ref_protected` sur le runner du socle | `GET /runners/:id` |
| 08:05 | Réglage remis à `not_protected` | API |
| 08:12 | Pipeline de la MR de test vert ; fin d'impact | GitLab |
| 08:20 | Communication de fin d'incident | #astreinte |

## 4. Causes

### 4.1 Causes racines

1. **Droits du dossier des sockets de Puma modifiés** (`root:root 0700` au lieu de `git` et `0750`) : Puma, qui tourne sous `git`, ne pouvait plus créer `gitlab.socket` et redémarrait en boucle ; Workhorse ne joignait plus Puma (502), `gitlab-shell` ne joignait plus l'API interne (SSH). Preuves : `stat` du dossier, erreur `EACCES` dans le journal de Puma, différences affichées par `reconfigure`.
2. **Runner du socle restreint aux branches protégées** (`access_level: ref_protected`) : il ne prenait plus que les jobs de `main`. Preuves : réponse de l'API, message « no runners for the protected branch » sur le job, pipeline de `main` qui passe.

### 4.2 Facteurs contributifs

- Modifications à la main, sans ticket ni trace, sur un serveur et dans un réglage gérés « à la main » (pas encore de gestion de configuration : Ansible au M04, réglages GitLab en code au M05).
- `gitlab-ctl status` présente un service en boucle de redémarrage comme « run » : une seule lecture trompe.
- Le statut « en ligne » du runner ne dit rien de sa capacité à prendre les jobs de MR.

## 5. Détection et diagnostic

- Détection par un utilisateur (Julien), 2 minutes après le début : aucune alerte. Une sonde HTTP sur `/users/sign_in` toutes les minutes l'aurait détectée avant lui ; une alerte sur l'uptime de Puma aurait donné la cause.
- La seconde panne était **masquée** par la première : le triage initial l'attribuait à la 502. Elle a été trouvée parce que toutes les sondes ont été rejouées après la première correction, et que le pipeline de `main` (vert) a été comparé à celui de la MR (bloqué).
- Temps de diagnostic : 37 min pour la première (lecture unique de `gitlab-ctl status` au début), 20 min pour la seconde.

## 6. Ce qui a bien fonctionné

- Accès d'administration à `git01` par l'alias IP, indépendant de GitLab.
- Sauvegarde quotidienne de la configuration (M01-E28) : elle a permis de vérifier `gitlab.rb` avant `reconfigure`.
- Journal de diagnostic tenu en local pendant l'incident, publié ensuite.

## 7. Actions

| # | Action | Type | Responsable | Échéance |
|---|---|---|---|---|
| 1 | Sonde HTTP `/users/sign_in` + sonde SSH `ssh -T git@…` toutes les minutes, alerte après 3 échecs | détecter | <MOI> | M21 (provisoire : cron + notification, J+7) |
| 2 | Alerte « Puma redémarré plus de 3 fois en 5 min » | détecter | <MOI> | J+14 |
| 3 | Sonde « job en attente depuis plus de 5 min » sur `plateforme/*` | détecter | <MOI> | J+14 |
| 4 | Contrôle de dérive nocturne : sommes de contrôle des fichiers et droits gérés par omnibus | détecter | Karim Benali | J+30 |
| 5 | Réglages des runners et des projets décrits en code et comparés chaque nuit | prévenir | Karim Benali | M05 |
| 6 | Règle d'équipe : toute intervention sur `git01`/`runner01` passe par un ticket CHG, même « rapide » | prévenir | Claire Morel | J+7 |
| 7 | Runbook RB-013 « forge en panne » mis à jour avec ces deux cas | atténuer | <MOI> | J+3 |

## 8. Enseignements

- Rejouer **toutes** les sondes après chaque correction : la seconde panne n'aurait pas été vue sinon.
- Un service « en marche » peut être en boucle : toujours deux lectures espacées.
- Nos sondes doivent tester chaque porte de la forge (web, API, SSH, runner, release), pas seulement « le serveur répond ».

## Annexes

- Journal de diagnostic : `docs/socle/journal/AAAA-MM-JJ-INC-2788.md`.
- Sortie de `gitlab-ctl reconfigure` (extrait des différences appliquées).
