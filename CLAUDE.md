# CLAUDE.md — Consignes de production du workbook

Ce dépôt est un workbook de formation DevOps / cloud privé, en français, produit par Claude en plusieurs conversations. L'apprenant (propriétaire du dépôt) ne doit avoir qu'une phrase à fournir pour lancer une conversation (voir `REPRISE.md`).

## Avant toute chose
1. Lire `PLAN.md`, `CONVENTIONS.md`, `AVANCEMENT.md`.
2. Le module 00 (`modules/00-lab/`) est le **gabarit** : en lire au moins le README, un fichier d'énoncé, le corrigé correspondant, deux checks et un script de panne avant de produire un autre module.

## Produire un bloc
1. Au démarrage, vérifier (recherche web) les versions stables actuelles des outils du bloc et les consigner dans `PLAN.md` §6.
2. Pour chaque module : écrire d'abord le `README.md` du module (carte des exercices avec ID, titre, type, difficulté, palier, conforme aux cibles de volume de CONVENTIONS §3), puis déléguer la rédaction à des agents (un agent par palier ou groupe de paliers pour les modules cœur), avec un brief commun listant les faits partagés (noms, IP, VMID, fichiers) pour que les parties restent cohérentes.
3. Harmoniser les parties (un agent dédié), puis faire relire par un **agent indépendant** selon CONVENTIONS §11 (exactitude technique vérifiée sur la doc officielle, sécurité de l'apprenant, faisabilité, pédagogie).
4. `shellcheck -x` et `bash -n` sur tous les scripts.
5. Toute nouvelle décision structurante (hôte permanent, IP, VMID, convention) va dans `PLAN.md` (et son journal des décisions).
6. Mettre à jour `AVANCEMENT.md`, committer et pousser **après chaque module** (pas seulement en fin de bloc), pour ne rien perdre en cas d'interruption.

## Enchaînement automatique des blocs
Ordre : bloc A (01-06) → B (07-11) → C (12-18) → D+E (19-23) → F (24-26) → G (27-29) → finaux F1-F4 → finaux F5-F7.
La session tourne sans l'apprenant : ne pas poser de questions, prendre la lecture la plus raisonnable et la consigner dans `AVANCEMENT.md`.
Quand le bloc est terminé (relu, poussé, `AVANCEMENT.md` à jour), créer une **tâche planifiée ponctuelle** (quelques minutes plus tard) qui lance une nouvelle session avec ce message, en remplaçant le bloc par le suivant :
> Dépôt GitHub `cemah2/DevOpsPrivateCloud` (attache-le avec accès en écriture et clone-le). Lis `CLAUDE.md`, `PLAN.md`, `CONVENTIONS.md` et `AVANCEMENT.md`, puis produis le bloc <X> en suivant `CLAUDE.md`, y compris l'enchaînement automatique.
Ne jamais lancer le bloc suivant si le bloc courant n'est pas entièrement poussé. Après le dernier bloc, ne rien planifier. Si la session s'arrête avant la fin (limite d'utilisation), l'apprenant relance avec `REPRISE.md` et la production reprend d'après `AVANCEMENT.md`.

## Corriger après retour de l'apprenant
Reproduire le raisonnement, corriger énoncé + corrigé + check concernés, vérifier l'impact sur les exercices et modules suivants, consigner dans `AVANCEMENT.md`.

## Git
Branche `main`. Messages de commit en français, préfixés (`feat(m05): …`, `fix(m00): …`, `docs: …`).
