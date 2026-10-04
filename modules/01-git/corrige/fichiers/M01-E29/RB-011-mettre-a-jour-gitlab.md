# RB-011 — Mettre à jour GitLab CE (version mineure ou corrective)

| | |
|---|---|
| Service | Forge GitLab `git01` (VMID 1004) et runner `runner01` (VMID 1007) |
| Rédigé | M01-E29 (CHG-256), passage 19.3.x → 19.4.x le AAAA-MM-JJ |
| Fenêtre | 1 h annoncée ; interruption réelle 10 à 20 min (migrations comprises) |
| Retour arrière | instantané de la VM (perte des écritures faites après) ou réinstallation de l'ancienne version + RB-010 |

## Cadence et choix de la version

- GitLab publie une **version mineure par mois** (troisième jeudi) et des **correctifs** (patchs) entre deux, dont des correctifs de sécurité : on vise toujours le **dernier patch** de la mineure cible (`19.4.Z`, jamais `19.4.0` par principe).
- Les **arrêts obligatoires** (*required stops*) tombent sur `x.2`, `x.5`, `x.8`, `x.11` (19.2, 19.5, 19.8, 19.11). On ne saute jamais un arrêt : outil officiel *Upgrade Path* (`gitlab-com.gitlab.io/support/toolbox/upgrade-path/`).
- Rythme MédiSphère : correctifs de sécurité sous 7 jours, mineure une fois par mois ou par trimestre (sans jamais laisser passer un arrêt obligatoire), majeure (mai) après lecture des ruptures annoncées.

## J-7 à J-1 : préparation (sans rien changer)

1. Version actuelle et cible :
   ```
   admin@git01:~$ sudo gitlab-rake gitlab:env:info | sed -n '/GitLab information/,/^$/p'
   admin@git01:~$ apt-cache madison gitlab-ce | head
   ```
2. Lire l'article de version, les notes de mise à jour de la série 19 (*GitLab 19 upgrade notes*) et les dépréciations qui concernent nos réglages (`gitlab.rb` : clés renommées, ex. `nginx[...]` → `gitlab_rails['nginx'][...]` depuis 19.2).
3. Migrations d'arrière-plan **toutes terminées** (sinon : on attend, on ne force pas) :
   ```
   admin@git01:~$ sudo gitlab-rake gitlab:background_migrations:list      # 18.9 et suivantes ; avant : :status
   admin@git01:~$ sudo gitlab-psql -c "SELECT job_class_name, table_name FROM batched_background_migrations WHERE status NOT IN (3, 6);"
   ```
4. Santé de départ : `sudo gitlab-rake gitlab:check SANITIZE=true`, `sudo gitlab-rake gitlab:doctor:secrets`, `gitlab-ctl status`, espace disque (`df -h /var/opt/gitlab` : au moins 2 × la base + 5 Go).
5. Annonce aux équipes (date, durée, impact : pas de push ni de pipeline pendant la fenêtre).

## Jour J

1. **Sauvegardes** : `sudo systemctl start wb-backup-gitlab.service` puis vérifier l'instantané dans PBS (RB-010 §1) ; instantané de VM **sans la RAM** :
   ```
   root@pve01:~# qm snapshot 1004 avant-maj-19-4 --description "CHG-256 avant 19.4.Z"
   ```
2. **Gel** : mettre en pause le runner (*Admin → CI/CD → Runners → Pause*) pour ne pas couper des jobs au milieu.
3. **Mise à jour** :
   ```
   admin@git01:~$ sudo apt-mark unhold gitlab-ce
   admin@git01:~$ sudo apt-get update && sudo apt-get install gitlab-ce=19.4.Z-ce.0
   admin@git01:~$ sudo apt-mark hold gitlab-ce
   ```
   Lire la sortie : sauvegarde automatique de la base, `reconfigure`, migrations, redémarrage. Une erreur de migration = **stop**, on ne relance pas à l'aveugle : diagnostic, puis décision de retour arrière.
4. **Contrôles** (liste à cocher, dans cet ordre) :
   - [ ] `gitlab-ctl status` : tous les services `run:` depuis plus de 60 s
   - [ ] sur `git01` (127.0.0.1 est toujours autorisé à lire les sondes) : `curl -s --resolve git01.par1.medisphere.internal:443:127.0.0.1 "https://git01.par1.medisphere.internal/-/readiness?all=1"` → `"status":"ok"` partout (depuis `adm01` après M01-E30)
   - [ ] version : `curl -s -H "PRIVATE-TOKEN: …" https://git01.par1.medisphere.internal/api/v4/version`
   - [ ] `gitlab-rake gitlab:check SANITIZE=true` et `gitlab:doctor:secrets` sans erreur
   - [ ] connexion web (avec 2FA), `git clone` en SSH et en HTTPS, push sur une branche, MR
   - [ ] hooks globaux actifs (`lab/bin/check 01 26`) : `reconfigure` régénère la configuration de Gitaly
   - [ ] runner réactivé, un pipeline complet passe (qualité + release)
   - [ ] migrations d'arrière-plan de la nouvelle version : en cours ou terminées, aucune en échec
5. **Runner** : version alignée sur `major.minor` de GitLab (`gitlab-runner --version` sur `runner01`) ; sinon, même procédure (`apt-mark unhold`, version exacte des deux paquets, `hold`).

## Retour arrière

| Situation | Décision |
|---|---|
| Échec avant la fin des migrations, aucune écriture utilisateur | `qm rollback 1004 avant-maj-19-4` (VM arrêtée), redémarrage, contrôles |
| Problème découvert après réouverture aux utilisateurs | pas de rollback de VM (perte des pushes/MR faits depuis) : correctif ou patch suivant ; en dernier recours, réinstallation de la version d'origine et restauration (RB-010) avec communication de la perte |
| Downgrade du paquet (`apt install gitlab-ce=19.3.Z`) | **interdit** : la base a migré, GitLab ne gère pas le retour de schéma |

## Clôture

- Supprimer l'instantané après 24 à 48 h sans incident : `qm delsnapshot 1004 avant-maj-19-4` (un instantané conservé alourdit le stockage et n'a plus de valeur dès que des données ont été écrites).
- Mettre à jour l'inventaire (`docs/socle/inventaire.md` : version), fermer le ticket CHG avec la preuve (sorties des contrôles).

## Historique

| Date | Auteur | Changement |
|---|---|---|
| AAAA-MM-JJ | <apprenant> | Création, 19.3.x → 19.4.x (M01-E29) |
