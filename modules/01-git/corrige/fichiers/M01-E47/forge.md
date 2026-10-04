# Fiche de service — La forge MédiSphère

> Exemple de corrigé (M01-E47). Emplacement : `docs/socle/forge.md` de `plateforme/medisphere`.
> Les valeurs entre `<…>` sont à remplacer par tes mesures ; aucune valeur secrète, seulement des emplacements.

| | |
|---|---|
| Version du document | forge-v1 (étiquette Git du même nom) |
| Responsable du service | équipe Plateforme (Karim Benali en suppléance) |
| État | en production pour l'équipe Plateforme et l'équipe MédiAgenda |

## 1. Ce que rend le service

Hébergement des dépôts Git de la plateforme, revue de code (MR), CI de qualité obligatoire, publication automatique des versions. Utilisateurs : équipe Plateforme, équipes de développement (à partir du module 12), automatisations (runner, scripts).

Engagement interne (heures ouvrées) : disponibilité visée 99 % ; rétablissement en moins de 4 h ; perte de données maximale 24 h (sauvegarde applicative quotidienne).

## 2. Composants

| Composant | Hôte | Version | Rôle |
|---|---|---|---|
| GitLab CE (omnibus) | `git01`, VMID 1004, 10.10.20.12 | 19.4.x | web, API, Git (HTTPS et SSH), CI |
| GitLab Runner (`shell`) | `runner01`, VMID 1007, 10.10.20.15 | 19.4.x | exécution des jobs (étiquettes `shell`, `socle`) |
| Outils de CI | `runner01` `/opt/release-tools` | figés par `package-lock.json` | commitlint, semantic-release |
| Hooks globaux | `git01` `/var/opt/gitlab/gitaly/custom_hooks/pre-receive.d/` | dépôt `plateforme/medisphere`, `forge/hooks/` | Conventional Commits, fichiers ≤ 5 Mio |
| PKI provisoire | `adm01` `~/pki-provisoire/` | — | certificat HTTPS de `git01` (jusqu'au M06) |

Dépendances : `dns01` (résolution), `gw01` (routage, NTP, tunnel vers PAR2), `pbs01` (sauvegardes), `pve01` (hyperviseur).

## 3. Accès

| Accès | Chemin | Remarque |
|---|---|---|
| Utilisateurs | `https://git01.par1.medisphere.internal`, `git@git01.par1.medisphere.internal` | comptes nominatifs, inscriptions fermées |
| Administration | `ssh git01`, `ssh runner01` (alias IP, compte `admin`) | indépendant de GitLab et du DNS |
| Secours | console `qm terminal 1004` / `1007` sur `pve01` | |
| Bris de glace | compte GitLab `root` | mot de passe dans le gestionnaire de l'équipe |

## 4. Projets et règles

Groupe `plateforme` : `main` protégée (aucune poussée directe, fusion par MR), pipeline et discussions résolues obligatoires, méthode de fusion de M01-E11, pre-commit, gabarits `plateforme/ci-templates@v1` (`qualite.yml`, `release.yml`), étiquettes `v*` protégées. Groupe `formation` : bac à sable des exercices.

## 5. Sauvegarde et restauration

- Sauvegarde de VM : tâche `lab-nuit` (pool `lab`) vers `pbs-par2`.
- Sauvegarde applicative : `gitlab-backup create` + `gitlab-ctl backup-etc`, copiées vers PBS (`ds-lab`, espace de noms `par1/git01`), minuteur `wb-backup-gitlab.timer` (M01-E28).
- Restauration : runbook RB-010 ; dernier test le <AAAA-MM-JJ> sur la VM jetable 2010, RTO mesuré <NN> min (voir `tests/restauration.md`).

## 6. Exploitation

| Sujet | Où |
|---|---|
| Mise à jour de GitLab | runbook RB-011 (M01-E29) : chemin officiel de montée de version (arrêts obligatoires), sauvegarde vérifiée et instantané avant, contrôles après |
| Supervision | sonde de M01-E30 (`forge/supervision/sonde-forge.sh`, planifiée toutes les 5 min) ; en incident, `forge/outils/triage-forge.sh` (M01-E43) |
| Supervision et incidents | sonde `sonde-forge.sh` et RB-012 « Diagnostiquer la forge » (M01-E30) ; RB-013 « La forge est en panne » par symptôme (M01-E47) ; post-mortems dans `post-mortems/` (INC-2788) |
| Jetons d'automatisation | `bot-release` par projet (expiration suivie, rotation outillée) ; jeton d'administration personnel ≤ 90 jours |

## 7. Risques connus

| Risque | Effet | Traitement |
|---|---|---|
| `git01` seule instance (pas de HA) | arrêt de toute la livraison | RTO de RB-010, sauvegardes testées ; HA hors périmètre (coût mémoire) |
| 8 Go de RAM au strict minimum | lenteurs, Puma tué par manque de mémoire | profil mémoire contrainte, supervision de la mémoire (E30) |
| CA provisoire sur `adm01` | perte ou fuite de la clé | remplacement par step-ca au M06 |
| Fonctions Premium absentes (approbations, push rules) | revue non obligatoire au sens strict | discussions résolues + pipeline obligatoires + hooks côté serveur (ADR-0010 et E11) |
| Modifications manuelles sur `git01` | dérive, pannes (INC-2782) | Ansible au M04, contrôle de dérive, tickets CHG |
