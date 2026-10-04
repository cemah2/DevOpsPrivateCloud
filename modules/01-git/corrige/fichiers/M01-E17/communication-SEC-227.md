# SEC-227 — Jeton GitLab exposé dans formation/labo-fuite : compte rendu

**À** : Sophie Laurent (RSSI) — **Cc** : Claire Morel, Julien Petit, astreinte
**Statut** : clos — secret révoqué, historique purgé, aucun usage frauduleux constaté

## Résumé (à lire en premier)

Le <AAAA-MM-JJ> à <HH:MM>, un jeton d'accès GitLab (`collecte-medisphere`, jeton de projet,
lecture du dépôt `formation/labo-fuite` uniquement) et un mot de passe de base de données de test
ont été poussés dans `config/collecte.env`. Le jeton a été **révoqué à <HH:MM>**, soit
<N> minutes après la détection. L'historique du dépôt a été réécrit et purgé côté GitLab.
Aucun accès avec ce jeton n'apparaît dans les journaux en dehors de la création par l'équipe.

## Chronologie (heure de Paris)

| Heure | Événement |
|---|---|
| J-2 <HH:MM> | Commit `feat: configuration de la collecte` : le fichier contient le jeton et `DB_PASSWORD` |
| J-2 <HH:MM> | Push vers `formation/labo-fuite` ; étiquette `v0.1.0` et branche `feat/export-csv` en dépendent |
| J-1 <HH:MM> | Commit `chore: retrait du fichier de configuration` : le fichier disparaît de `main`, **pas de l'historique** |
| J <HH:MM> | Détection (ticket SEC-227) |
| J <HH:MM> | Jeton révoqué (Paramètres > Jetons d'accès) ; vérification : `401` à l'usage |
| J <HH:MM> | Mot de passe `DB_PASSWORD` signalé à l'équipe MédiAgenda (compte de test, changé) |
| J <HH:MM> | Purge : `git filter-repo --sensitive-data-removal`, push forcé, *Remove blobs*, ménage et élagage |
| J <HH:MM> | Contrôle : aucune révision accessible ne contient les secrets (clone miroir) |

## Exposition

- **Portée du jeton** : rôle Reporter, `read_repository`, sur ce seul projet (bac à sable sans
  donnée de santé). Expiration prévue sous 7 jours de toute façon.
- **Qui pouvait le lire** : les membres du projet (moi, Julien Petit) et les administrateurs de
  l'instance. Projet privé, instance non exposée à Internet.
- **Usage constaté** : `last_used_at` du jeton = <vide / date> ; journaux de `git01`
  (`/var/log/gitlab/gitlab-rails/production_json.log`, `api_json.log`, `gitlab-shell/gitlab-shell.log`)
  sans accès au projet par le compte du jeton.
- **Copies hors de GitLab** : clones de Julien et de moi (supprimés et refaits), aucune
  copie de sauvegarde ne quitte le lab en clair (PBS chiffré). Les sauvegardes de `git01` antérieures
  à la purge contiennent encore le secret : il est révoqué, c'est acceptable ; elles expirent selon
  la rétention.

## Actions

| Action | Qui | État |
|---|---|---|
| Révoquer le jeton | moi | fait |
| Changer le mot de passe de test | Julien | fait |
| Purger l'historique (branches, étiquette, références de MR) | moi | fait |
| Refaire les clones existants | Julien, moi | fait |
| `config/*.env` dans `.gitignore`, exemple `config/collecte.env.example` sans valeur | Julien | fait |
| pre-commit + gitleaks sur le projet, CI gitleaks (M01-E24) | moi | prévu |

## Cause et prévention

Cause : fichier de configuration réel ajouté au dépôt « pour aller vite », sans hook local ni
contrôle côté serveur. Le retrait dans un commit suivant a donné une fausse impression de correction.
Prévention : hook gitleaks obligatoire (CONTRIBUTING), contrôle gitleaks en CI sur chaque MR,
fichier d'exemple versionné et vrai fichier ignoré, secrets chargés depuis l'environnement.
