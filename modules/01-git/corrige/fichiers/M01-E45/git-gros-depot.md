# Analyse — import de l'historique Git de Legacy-RDV (PLAT-281)

| | |
|---|---|
| Auteur | équipe Plateforme |
| Date des mesures | AAAA-MM-JJ (adm01, Git 2.47, git-lfs 3.x ; GitLab 19.4) |
| Dépôt source | historique livré par InfoGér, 4 000 commits (`~/src/legacy-rdv`) |
| Projet cible | `formation/legacy-rdv` (privé) |

> Exemple de rapport (M01-E45). Les chiffres « adm01 » proviennent d'une exécution réelle des
> commandes indiquées ; les durées de clone ont été mesurées sur un serveur local `file://` :
> remplace-les par tes mesures depuis `git01`.

## 1. État initial

| Mesure | Commande | Valeur |
|---|---|---|
| Commits | `git rev-list --count --all` | 4 000 |
| Objets | `git count-objects -vH` (`in-pack`) | 16 035, tous empaquetés (1 paquet) |
| Taille des paquets | `git count-objects -vH` (`size-pack`) | 49,5 Mio |
| Chaînes de deltas | `git verify-pack -v` | jusqu'à 50 (profondeur par défaut) |

## 2. Ce qui pèse

`gros-objets.sh` (rev-list `--objects --all` + `cat-file --batch-check`) :

| Taille | Sur disque | Chemin | Remarque |
|---|---|---|---|
| 18,0 Mio | 18,1 Mio | `assets/video/presentation.mp4` (v2) | supprimé de l'arbre au commit 3 000, toujours dans l'historique |
| 18,0 Mio | 18,1 Mio | `assets/video/presentation.mp4` (v1) | idem |
| 9,0 Mio | 9,1 Mio | `vendor/sdk-legacy-1.2.tar.gz` | présent dans `HEAD` |
| 2,5 Mio | 155 Kio | `db/dump-demo.sql` (12 versions) | texte répétitif : se compresse très bien |

Les trois binaires représentent 46 Mio sur 49,5. Incompressibles (vidéo, archive déjà compressée), sans delta possible entre versions : chaque version est stockée en entier et téléchargée par chaque clone complet, même après leur suppression de l'arbre.

## 3. Compression

| Opération | Durée | Taille des paquets |
|---|---|---|
| `git gc` | < 1 s | 49,5 Mio (deltas existants réutilisés) |
| `git repack -a -d -f --depth=50 --window=250` | 12 s | 48,7 Mio |

Conclusion : la compression ne règle rien, il faut sortir les binaires de Git.

## 4. Stratégies de clone (avant migration)

| Stratégie | Durée | `.git` | Usage |
|---|---|---|---|
| clone complet | 3,8 s | 49 Mio | archivage, miroir |
| `--depth 1` | 0,8 s | 9,4 Mio | job de CI sans historique (pas semantic-release) |
| `--filter=blob:none` | 1,2 s | 11 Mio | développeur : historique complet, contenus à la demande |
| `--filter=blob:limit=1m` | 1,6 s | 12 Mio | historique et petits fichiers complets |
| `--filter=blob:none --sparse` + `src` | 0,5 s | 1,8 Mio | revue d'une partie du code |

## 5. Migration vers Git LFS

Commandes : `git lfs migrate info --everything --above=5mb`, puis `git lfs migrate import --everything --above=5mb` sur une copie ; purge des reflogs et `gc` ; poussée vers un projet neuf.

| | Avant | Après |
|---|---|---|
| Paquets Git (adm01) | 49,5 Mio | 3,7 Mio |
| Objets LFS | — | 46 Mio (2 vidéos, 1 archive) |
| Dépôt Git côté GitLab (`repository_size`) | ≈ 50 Mio (`legacy-rdv-brut`) | quelques Mio (`legacy-rdv`) |
| Empreintes des commits | — | **toutes changées** (réécriture) |

Conséquences : tout clone de l'ancien historique est obsolète ; l'ancien projet de mesure (`legacy-rdv-brut`) a été supprimé ; une machine qui clone doit avoir `git-lfs` installé (`git lfs install`), sinon elle n'obtient que des pointeurs.

## 6. Maintenance

- Graphe de commits (`git commit-graph write --reachable --changed-paths`) : `git log -- src/Module7.php` passe de 0,25 s à 0,06 s (×4 dès 4 000 commits ; davantage sur de longs historiques).
- `git maintenance start` : minuteurs systemd utilisateur (horaire, quotidien, hebdomadaire) pour `prefetch`, `commit-graph`, `loose-objects`, `incremental-repack`. Gardé pour `~/medisphere` et les gros clones de travail, retiré (`unregister`) pour les dépôts d'exercice.
- GitLab : *housekeeping* automatique (après N poussées et optimisation planifiée heuristique) ; « Prune unreachable objects » seulement hors activité (délai de grâce de 30 min, risque de corruption avec une opération concurrente).

## 7. Recommandations

1. **Règle des gros fichiers** : aucun fichier de plus de 5 Mio dans Git ; hook global de M01-E26 étendu aux groupes applicatifs ; LFS pour les binaires indispensables, registre d'artefacts (M13) pour tout ce qui est produit par une construction.
2. **CI** : `GIT_DEPTH` court par défaut ; historique complet (`GIT_DEPTH: "0"`) seulement pour les jobs qui en ont besoin (release) ; `GIT_LFS_SKIP_SMUDGE=1` pour les jobs qui n'utilisent pas les binaires.
3. **Postes** : clone partiel (`--filter=blob:none`) pour les gros dépôts ; `git maintenance` activé sur les clones durables.
4. **Imports futurs** : toujours mesurer (`gros-objets.sh`) avant d'importer, migrer sur une copie, pousser dans un projet neuf, communiquer la réécriture.
