# Contribuer aux projets de la plateforme MédiSphère

Ce guide s'applique à tous les projets du groupe `plateforme` sur
<https://git01.par1.medisphere.internal>. Il est court exprès : chaque règle a une raison,
donnée entre parenthèses. Une règle qui gêne se discute dans une MR sur ce fichier, pas en la
contournant.

Responsable du document : équipe Plateforme (Karim Benali). Dernière revue : voir l'historique Git.

## 1. Avant le premier commit

Sur ton poste (en général `adm01`) :

```
git config --global user.name "Prénom Nom"
git config --global user.email "prenom.nom@medisphere.internal"
git config --global init.defaultBranch main
git config --global pull.rebase true
git config --global rerere.enabled true
```

- Ta clé SSH est déclarée dans ton profil GitLab, **avec une date d'expiration** ; on clone en SSH
  (`git@git01.par1.medisphere.internal:plateforme/<projet>.git`).
- Outils : Node.js 24 LTS, `pre-commit` 4.x, `gitleaks` 8.30.x (voir `docs/socle/forge.md`).
- Dans chaque clone : `pre-commit install` (installe les contrôles `pre-commit` **et** `commit-msg`).
  Un clone sans hooks n'est pas un clone de travail.

## 2. Branches

- `main` est protégée : personne n'y pousse directement, tout passe par une merge request (MR).
- Une branche par sujet, créée depuis `main` à jour, nommée `type/description-courte` avec les
  types de commit ci-dessous : `feat/sauvegarde-git01`, `fix/seuil-alerte-pbs`, `docs/runbook-gitlab`.
  Ajoute le ticket s'il existe : `fix/PLAT-228-seuil-alerte`.
- Branches de maintenance : `N.x` (ex. `1.x`), uniquement des correctifs rétroportés avec
  `git cherry-pick -x` (la trace `cherry picked from commit` relie les deux branches).
- Une branche vit quelques jours, pas quelques semaines (plus elle vit, plus les conflits coûtent).

## 3. Messages de commit

Format [Conventional Commits 1.0.0](https://www.conventionalcommits.org/fr/v1.0.0/), vérifié par
commitlint à chaque commit et dans la CI :

```
type(portée facultative): sujet en minuscules, sans point final

Corps : POURQUOI ce changement (le quoi est dans le diff). Lignes de 100 caractères au plus.

Refs: PLAT-228
```

| Type | Quand | Effet sur la version (semantic-release) |
|---|---|---|
| `feat` | nouvelle fonctionnalité | mineure (1.2.0 → 1.3.0) |
| `fix` | correction d'un défaut | correctif (1.2.0 → 1.2.1) |
| `perf` | performance, sans changement de comportement | correctif |
| `docs`, `style`, `refactor`, `test`, `build`, `ci`, `chore`, `revert` | le reste | aucune (sauf rupture) |
| `!` après le type, ou pied `BREAKING CHANGE: …` | rupture de compatibilité | majeure (1.2.0 → 2.0.0) |

- Le sujet décrit le changement à l'infinitif ou au nom : `fix(pbs): corriger le seuil d'alerte`,
  `docs(socle): ajout de runner01 à l'inventaire`. Il commence par une minuscule
  (« sauvegarde de GitLab », pas « GitLab sauvegardé »).
- Un commit = un changement cohérent, qui laisse le dépôt dans un état valide (on doit pouvoir
  faire `git bisect` sur `main`).
- Pas de `wip`, `fix typo`, `oups` dans une MR prête à relire : utilise `git commit --fixup` puis
  `git rebase -i --autosquash` avant de demander la revue.

## 4. Merge requests

- Ouvre la MR tôt en **Draft** si tu veux un avis ; retire le Draft quand elle est prête.
- Titre au format Conventional Commits (il devient le message du commit si la MR est fusionnée
  en squash).
- Remplis le modèle (`.gitlab/merge_request_templates/Default.md`) : contexte et ticket, ce qui
  change, **comment tu as vérifié** (commandes et résultats), impact sécurité/réseau/sauvegarde,
  retour arrière.
- Petite MR : moins de 400 lignes modifiées hors fichiers générés, un seul sujet.
- Mets ta branche à jour par **rebase** sur `main` (`git pull --rebase` ou `git rebase origin/main`),
  jamais en fusionnant `main` dans ta branche. Pousse ensuite avec
  `git push --force-with-lease` (jamais `--force` seul).

## 5. Revue

- Au moins **une approbation** d'un autre membre de l'équipe avant fusion ; une MR qui touche
  la sécurité (secrets, flux réseau, droits) demande l'avis de Sophie Laurent.
  > GitLab CE ne rend pas l'approbation obligatoire (fonction Premium) : c'est une règle d'équipe,
  > tracée par le message de fusion (`Approved-by:`), que la revue de Karim vérifie.
- Le relecteur répond sous un jour ouvré. Il préfixe ses commentaires :
  **bloquant**, **à corriger**, **suggestion**, **question**, **détail** (ce dernier n'empêche pas la fusion).
- On commente le code, pas la personne. On explique pourquoi, on propose quand on peut
  (bouton *Insert suggestion*).
- L'auteur répond à chaque fil ; **celui qui a ouvert le fil le résout** (GitLab refuse la fusion
  tant qu'un fil est ouvert).

## 6. Fusion

- Méthode du projet : commit de fusion avec historique semi-linéaire (la branche doit être à jour
  de `main` ; les commits de la branche sont conservés tels quels). Squash autorisé, pas imposé.
- Le pipeline doit réussir (pre-commit, commitlint, gitleaks, tests du projet).
- Qui fusionne : un Maintainer, en général l'auteur après approbation.
- La branche source est supprimée à la fusion.

## 7. Secrets

**Aucun secret dans un dépôt, jamais** : ni mot de passe, ni jeton, ni clé privée, ni fichier
`.env` réel, même « pour tester », même sur une branche.

- Les secrets vivent hors des dépôts : `~/.config/workbook/` (700/600) sur les postes, variables
  CI protégées et masquées, Ansible Vault (M04), puis Vault/OpenBao (M25).
- gitleaks (hook pre-commit + CI) arrête la plupart des fuites ; une exception
  (`.gitleaks.toml`, `gitleaks:allow`) se justifie dans la MR et passe en revue.
- **Un secret a été poussé ?** Même sur une branche, même supprimé depuis : préviens
  immédiatement Sophie Laurent et l'astreinte, **révoque/fais tourner le secret d'abord**, puis
  applique la procédure de purge (`docs/socle/runbooks/`). Supprimer le fichier dans un nouveau
  commit ne suffit pas.

## 8. Ce qui est interdit

- Pousser sur `main`, réécrire `main` ou une étiquette `v*`.
- `git commit --no-verify` ou `SKIP=…` pour faire passer un commit refusé, sauf panne avérée d'un
  outil, signalée dans la MR (la CI rejouera les contrôles de toute façon).
- Créer une étiquette `v*` à la main : les versions sont publiées par semantic-release.
- Commiter des fichiers de plus de 500 Ko (images, archives, binaires) sans en parler avant.

## 9. Contacts

| Sujet | Qui |
|---|---|
| Règles de ce guide, revues | Karim Benali |
| Sécurité, secrets, fuite | Sophie Laurent |
| Incident forge (GitLab, runner) | astreinte — Nadia Roussel |
| Priorités | Claire Morel |
