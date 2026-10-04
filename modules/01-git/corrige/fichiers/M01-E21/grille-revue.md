# M01-E21 — Défauts de la MR de Lucas et revue modèle

## Grille des défauts (18 points)

| # | Où | Défaut | Gravité | Pourquoi c'est grave |
|---|---|---|---|---|
| 1 | `scripts/verifier-certificats.sh`, ligne `TOKEN=` | Jeton GitLab `glpat-…` en clair | **bloquant** | Un secret poussé sur le serveur est compromis, même sur une branche non fusionnée : révocation immédiate (ici factice, mais la procédure de M01-E17 s'applique) |
| 2 | `curl -k` | Vérification TLS désactivée | **bloquant** | Le jeton part vers un serveur non authentifié : interception triviale. La CA provisoire est installée sur `adm01` : `-k` est inutile |
| 3 | `https://10.10.20.12/…`, `HOSTS=` | Adresses IP en dur au lieu des noms | à corriger | Le certificat de `git01` couvre aussi son IP (SAN) : ce n'est donc pas une raison pour `-k`. Mais une IP en dur casse au premier changement d'adressage ; l'URL vient de `WB_GITLAB_URL`, les hôtes d'une liste de noms |
| 4 | `projects/1/issues` | Identifiant de projet en dur | à corriger | `1` n'est pas forcément `plateforme/medisphere` ; utiliser le chemin encodé |
| 5 | `?title=Certificat $h expire…` | Paramètres non encodés (espaces) | à corriger | Requête invalide ou titre tronqué ; `--data-urlencode` |
| 6 | `openssl s_client -connect $h:443` | Pas de `-servername`, pas de délai maximal | à corriger | Sans SNI, mauvais certificat possible derrière un proxy ; sans `timeout`, le script peut bloquer indéfiniment |
| 7 | `pve01:443`, `10.10.20.10:443` | Mauvaises cibles | à corriger | L'interface de Proxmox écoute sur 8006 ; `dns01` n'a aucun service HTTPS : ces deux contrôles échouent à chaque passage |
| 8 | `date -d "$date_fin"` sans contrôle | Échec silencieux | **bloquant** | Hôte injoignable → `date_fin` vide → `date -d ""` donne minuit du jour : faux « 0 jour », création d'issues en rafale |
| 9 | Pas de `set -euo pipefail`, variables non protégées par des guillemets | Robustesse | à corriger | `shellcheck` signale SC2086 ; erreurs ignorées |
| 10 | `echo "OK"` et code de sortie toujours 0 | Supervision impossible | à corriger | Un script de contrôle doit sortir en erreur quand il trouve un problème |
| 11 | Mode du fichier `100644` | Script non exécutable | détail | `git update-index --chmod=+x` |
| 12 | Shebang `#!/bin/bash`, commentaires sans accents, pas d'usage | Conventions de l'équipe | détail | `#!/usr/bin/env bash`, en-tête d'usage comme les autres scripts |
| 13 | `docs/socle/certificats.md` | Fins de ligne CRLF | à corriger | Diffs illisibles, hooks `end-of-file-fixer`/`trailing-whitespace` en échec ; `.gitattributes` |
| 14 | `docs/socle/capture-certificats.png` (700 Ko) | Fichier lourd et inutile | à corriger | Alourdit définitivement le dépôt ; une sortie texte suffit |
| 15 | `docs/socle/matrice-flux.md` | Flux « adm01 → tout le lab, tous ports » | **bloquant** | Contraire au principe de la matrice (flux ciblés) ; le vrai besoin : 443 (git01), 8006 (pve01)… et `adm01` (MGMT) joint déjà le lab |
| 16 | Commits `ajout script`, `wip`, `fix`, `update matrice` | Hors Conventional Commits | à corriger | Refusés par commitlint et la CI ; historique inexploitable par semantic-release |
| 17 | Auteur `lucas.martin.perso@example.org` | Adresse personnelle | à corriger | Commits non rattachés au compte GitLab, traçabilité perdue ; `git config user.email` |
| 18 | Titre « Ajout script certifs », description vide, aucun ticket | MR inexploitable | à corriger | Le relecteur ne sait ni pourquoi, ni comment vérifier ; modèle de MR (M01-E22) |

Bonus (rarement vu, très bon signe) : Lucas a contourné pre-commit (création par l'API, ou
`--no-verify`) : les contrôles locaux ne suffisent pas, d'où la CI (M01-E24) et les hooks côté
serveur (M01-E26). Et la question de fond : un tel script a-t-il sa place dans `medisphere`
(documentation) plutôt que dans `plateforme/outils` (M02) ?

## Commentaire de synthèse modèle (fil général)

> Merci Lucas, l'idée est bonne : surveiller l'expiration des certificats nous manque vraiment, et
> la PKI provisoire expire dans un peu plus d'un an.
>
> **Décision : changements demandés, pas de fusion en l'état.** Trois points bloquants :
> 1. **Jeton en clair** (ligne 3 du script). Un secret poussé sur `git01` est considéré comme
>    compromis, même sur une branche : révoque-le maintenant dans ton profil, préviens Sophie,
>    et lis `CONTRIBUTING.md` §7. Le script doit lire le jeton depuis l'environnement
>    (`GITLAB_TOKEN`, chargé depuis `~/.config/workbook/`).
> 2. **`curl -k`** : avec le nom `git01.par1.medisphere.internal`, le certificat est valide sur
>    `adm01` ; retire `-k` et utilise le nom.
> 3. **Matrice des flux** : pas de flux « tout vers tout ». Retire ce commit ; si un flux manque,
>    on en parle dans une MR dédiée.
>
> Ensuite, à corriger : gestion des hôtes injoignables (aujourd'hui, une erreur produit une fausse
> alerte), `set -euo pipefail` et guillemets (lance `shellcheck`), code de sortie, encodage des
> paramètres de l'API, port 8006 pour `pve01`. Côté dépôt : supprime la capture PNG, convertis
> `certificats.md` en fins de ligne Unix, réécris l'historique en 2 ou 3 commits conventionnels
> (`git rebase -i`), corrige ton adresse e-mail Git, et remplis le modèle de MR.
>
> Installe aussi les hooks (`pre-commit install`) : ils auraient arrêté les points 1, 13, 14 et 16
> avant même le push. Je suis disponible demain matin pour en parler si tu veux.
