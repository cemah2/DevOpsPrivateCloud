# ADR-0020 — Écrire les outils de la plateforme en Bash pour les gestes système et en Python au-delà

- Statut : accepté
- Date : 2026-10-04
- Décideurs : Karim Benali (ingénieur plateforme senior), Claire Morel (responsable infrastructure)
- Consultés : Nadia Roussel (astreinte), Sophie Laurent (RSSI), Julien Petit (lead dev MédiAgenda)

## Contexte et problème

L'équipe Plateforme a hérité d'InfoGér une trentaine de scripts shell non testés, et produit depuis
le module 02 deux familles d'outils dans `plateforme/outils` : des scripts Bash (`ms-snapshot`,
`ms-verif-sauvegardes`, `ms-diag`…) et une CLI Python (`medictl`). Sans règle, chaque nouvel outil
relance le débat, et l'astreinte doit maîtriser autant de langages que d'auteurs. Il faut décider
quel langage utiliser pour quel outil, et à quelles conditions.

## Facteurs de décision

- Fiabilité en astreinte : échouer bruyamment, codes retour cohérents, pas d'état à moitié appliqué.
- Testabilité en CI sans toucher au vrai Proxmox (bats, pytest).
- Compétences : équipe d'administrateurs système (Bash courant, Python inégal) ; recrutement.
- Dépendances sur les hôtes : Bash et coreutils partout ; Python 3.13 sur les VMs Debian 13.
- Sécurité : traitement des secrets, validation des entrées, scripts lancés en root (sudo, systemd).
- Distribution et versions : publication par la CI, retour arrière possible.
- Pérennité : Ansible (M04) et OpenTofu (M05) prendront une partie de ces besoins.

## Options envisagées

1. Tout en Bash.
2. Tout en Python.
3. Bash pour les gestes système courts, Python pour le reste, avec des critères de bascule écrits.
4. Go (binaires statiques) pour tous les outils.

## Décision

Option retenue : « Bash pour les gestes système courts, Python au-delà », parce qu'elle garde
Bash là où il est le plus simple et le plus lisible (enchaîner des commandes système), et impose
Python dès que la logique, les données ou les API deviennent le cœur de l'outil.

Un outil est écrit en **Bash** si toutes ces conditions sont vraies :
- il enchaîne principalement des commandes système (systemctl, journalctl, ssh, tar, curl) ;
- il tient en moins de ~200 lignes hors commentaires, avec au plus une API simple appelée par
  `lib/ms-commun.sh` ;
- ses données sont des lignes de texte ou du JSON traité par `jq` en quelques filtres.

Sinon, il est écrit en **Python** (sous-commande de `medictl` ou module du projet) ; en
particulier : structures de données imbriquées, appels d'API multiples avec reprises, parallélisme,
interface utilisateur riche, logique métier à tester finement.

Pour les deux langages : mode strict (`set -euo pipefail` / exceptions non avalées), ShellCheck ou
ruff sans avertissement, tests (bats / pytest) en CI, contrat de codes retour commun (0/1/2/3),
`--help` complet, publication par semantic-release. Un outil qui configure durablement des hôtes
n'est **pas** un script : il relève d'Ansible (M04) ou d'OpenTofu (M05).

### Conséquences

- Positives : choix rapide et prévisible ; Bash reste court et relisible par toute l'équipe ;
  la logique complexe bénéficie des tests unitaires, du typage et des bibliothèques Python
  (proxmoxer, requests).
- Négatives : deux chaînes d'outillage à maintenir (ShellCheck/shfmt/bats et uv/ruff/pytest) ;
  certains scripts franchiront la limite et devront être réécrits (coût de migration) ; Python
  impose un environnement géré (uv, paquet publié) là où un script Bash se copie.
- Actions induites : revue annuelle de `bin/` contre les critères (première revue avec le
  mini-projet M02-E46) ; formation Python de l'astreinte (binômes) ; réécriture de
  `ms-verif-sauvegardes` en sous-commande `medictl` si elle doit un jour vérifier PBS en
  profondeur (contenu, chiffrement) ; reprise des gestes de configuration par Ansible au M04.

## Analyse des options

### Tout en Bash
- Pour : disponible partout, aucune installation ; idéal pour enchaîner des commandes ; connu de tous.
- Contre : gestion d'erreurs piégeuse (`set -e` et ses exceptions, sous-shells, pipelines) ;
  données structurées pénibles ; tests possibles (bats) mais plus fragiles ; parallélisme et
  signaux délicats (M02-E28, E30).

### Tout en Python
- Pour : erreurs explicites (exceptions), bibliothèques, tests unitaires riches, parallélisme maîtrisé.
- Contre : verbeux pour trois commandes système ; dépendances à gérer sur chaque hôte ; un script
  root en Python avec des dépendances tierces élargit la surface d'attaque ; démarrage plus lent.

### Bash pour le système, Python au-delà (retenue)
- Pour : chaque langage dans son domaine ; critères écrits ; mêmes exigences de qualité pour les deux.
- Contre : deux écosystèmes ; zone grise à trancher en revue de MR.

### Go
- Pour : binaire statique sans dépendance, typage, performances, concurrence native.
- Contre : compétence absente dans l'équipe ; cycle compilation/publication plus lourd pour de petits
  outils ; peu d'intérêt tant que les outils restent des clients d'API simples. À réexaminer si
  l'équipe écrit un jour un opérateur Kubernetes (bloc C).

## Liens

- Tickets PLAT-362 (cet ADR), PLAT-354 (CI), DEV-355 (distribution de `medictl`).
- `plateforme/outils` : `README.md`, `docs/astreinte.md`, `CONTRIBUTING.md`.
- ADR-0010 (workflow Git, M01) ; à venir : ADR du M04 (Ansible) sur la frontière scripts / configuration.
