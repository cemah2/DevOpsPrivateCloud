# Registre des secrets et accès à la forge

> Ce registre décrit **où sont** les secrets et **comment les remplacer**. Il ne contient
> **aucune valeur**. Toute création, rotation ou révocation se fait par MR sur ce fichier.
> Revue complète : tous les trimestres, et à chaque départ d'un membre de l'équipe.

Dernière revue : <AAAA-MM-JJ> par <MOI>.

## Jetons et clés de la forge `git01`

| Identifiant | Type | Propriétaire | Portée / rôle | Stockage | Expiration | Rotation |
|---|---|---|---|---|---|---|
| `gitlab-checks` | jeton d'accès personnel | `<MOI>` | `read_api` | `adm01:~/.config/workbook/gitlab-checks.token` (600) | ≤ 1 an | interface (Profil > Jetons d'accès > Faire tourner), réécrire le fichier |
| `gitlab-admin` | jeton d'accès personnel | `<MOI>` (administrateur) | `api` (+ `admin_mode` si le mode admin est actif) | `adm01:~/.config/workbook/gitlab-admin.token` (600) | ≤ 90 jours | `gitlab-rotation-jeton.sh ~/.config/workbook/gitlab-admin.token 90` |
| jetons d'emprunt d'identité `workbook-M01-…` | jeton d'emprunt (admin) | comptes des personnages | `api` | jamais stockés (mémoire du script) | 1 jour | révoqués à la fin de chaque script de `ressources/` |
| `labo-lecture` | clé de déploiement SSH | projet `formation/git-labo` | lecture seule | `adm01:~/.ssh/id_ed25519_deploy_gitlabo` (600) | sans (clé SSH) : revue trimestrielle | nouvelle clé, ajout, test, retrait de l'ancienne |
| `bot-release` | jeton d'accès de projet | projets `plateforme/*` (M01-E25) | Maintainer, `api`, `write_repository` | variable CI `GITLAB_TOKEN` protégée et masquée | ≤ 1 an | rotation dans le projet, mise à jour de la variable |
| `glrt-…` runner `runner01` | jeton d'authentification de runner (M01-E23) | instance | exécution des jobs étiquetés `shell`, `socle` | `runner01:/etc/gitlab-runner/config.toml` (600, root) | selon réglage de l'instance | réinitialiser le jeton dans l'interface, `gitlab-runner register` |
| clé SSH de `<MOI>` | clé SSH (authentification) | `<MOI>` | accès Git à ses projets | `adm01:~/.ssh/id_ed25519` (phrase de passe) | date fixée dans GitLab | nouvelle clé, ajout dans GitLab, retrait de l'ancienne |

## Procédure de rotation (cas général)

1. Créer le nouveau secret **avant** de retirer l'ancien (sauf fuite : révoquer d'abord).
2. Le déposer à son emplacement (fichier 600 écrit de façon atomique, variable CI protégée et masquée).
3. Tester l'usage réel (check, pipeline, clone).
4. Révoquer l'ancien ; vérifier qu'il est refusé (`401`).
5. Mettre à jour ce registre (date, expiration) par MR.

## En cas de fuite

Révoquer immédiatement, prévenir Sophie Laurent, puis suivre la procédure de M01-E17
(évaluation de l'exposition, purge, communication). Ne jamais « tester » un secret exposé
depuis un poste extérieur.
