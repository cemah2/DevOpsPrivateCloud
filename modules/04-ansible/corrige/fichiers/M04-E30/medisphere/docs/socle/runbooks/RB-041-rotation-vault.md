# RB-041 — Rotation des secrets Ansible Vault

| | |
|---|---|
| **Quand** | Rotation planifiée (`lab` : tous les 6 mois ; `critique` : tous les 3 mois), départ d'une personne qui détenait un mot de passe, soupçon de fuite (journal, poste perdu, dépôt exposé) |
| **Qui** | Un Maintainer de `plateforme/ansible` qui détient l'identité concernée, avec un second Maintainer pour la vérification |
| **Durée** | 30 à 45 min par identité ; prévoir une fenêtre sans application en cours |
| **Impact** | Aucun sur les services ; les applications (CI, Semaphore) sont suspendues pendant la bascule |
| **Prérequis** | Accès à `adm01`, droits Maintainer sur `plateforme/ansible`, compte administrateur Semaphore, registre des secrets ouvert |

## Deux rotations différentes

1. **Changer le mot de passe Vault d'une identité** (`ansible-vault rekey`) : protège l'avenir. Les anciens
   commits restent déchiffrables avec l'ancien mot de passe : quiconque l'a eu et a eu accès au dépôt
   **connaît toujours les secrets** qui y étaient.
2. **Changer les secrets eux-mêmes** (mot de passe PostgreSQL, jeton du runner, clés de Semaphore…) :
   la seule rotation qui invalide ce qui a fui. Après une fuite du mot de passe Vault, on fait **les deux**.

## Procédure A — nouveau mot de passe pour une identité (exemple : `critique`)

1. **Geler** : vérifier qu'aucun job `appliquer`/`derive` ne tourne (pipelines de `main`) ni aucune tâche
   Semaphore ; prévenir l'équipe dans le canal (« rotation Vault critique en cours, pas d'application »).
2. **Branche** : `git switch -c conf/rotation-vault-critique` dans `~/src/ansible`, à jour de `main`.
3. **Générer** le nouveau mot de passe, sans l'afficher :
   `( umask 077; openssl rand -base64 32 > ~/.config/workbook/ansible-vault-critique.pass.nouveau )`
4. **Lister** les fichiers de l'identité : `grep -rl '^\$ANSIBLE_VAULT;1.2;AES256;critique' inventories/ roles/`.
   Une valeur chiffrée **en ligne** (`!vault |`) n'est pas un fichier : la déchiffrer et la rechiffrer à part.
5. **Rechiffrer** :
   `uv run ansible-vault rekey --vault-id critique@outils/vault-pass-client.sh --new-vault-id critique@$HOME/.config/workbook/ansible-vault-critique.pass.nouveau <fichiers>`
6. **Basculer le poste** : `mv ~/.config/workbook/ansible-vault-critique.pass.nouveau ~/.config/workbook/ansible-vault-critique.pass` (mode 600 conservé).
7. **Vérifier en local** : `uv run ansible-vault view <un fichier>` (ne pas afficher à l'écran : `> /dev/null`, code 0),
   puis `uv run ansible-playbook playbooks/sem01.yml --check` sans erreur de déchiffrement.
8. **Basculer la CI** : Settings > CI/CD > Variables, `VAULT_PASS_CRITIQUE` (fichier, protégée, portée `lab/socle`) :
   nouvelle valeur. Une variable « cachée » ne se modifie pas : la supprimer et la recréer.
9. **Basculer Semaphore** : groupe de variables du projet, secret `VAULT_MDP_CRITIQUE` : nouvelle valeur.
10. **MR** depuis `conf/rotation-vault-critique` (« chore(vault): rotation de l'identité critique »), pipeline vert,
    fusion, puis job `appliquer` : le contrôle de convergence doit être à zéro.
11. **Vérifier Semaphore** : lancer le modèle « Socle — vérifier » : succès.
12. **Tracer** : registre des secrets (date de rotation, auteur, prochaine échéance) ; détruire toute copie
    de l'ancien mot de passe (gestionnaire de mots de passe : archiver l'entrée avec la date).

## Procédure B — changer un secret (exemple : mot de passe PostgreSQL de Semaphore)

1. Geler comme en A.1.
2. `uv run ansible-vault edit inventories/lab/host_vars/sem01/vault.yml` : nouvelle valeur (`openssl rand -hex 24`).
3. MR, puis `uv run ansible-playbook playbooks/sem01.yml --diff` depuis `adm01` (sem01 n'est pas dans `site.yml`) :
   le rôle détecte que l'ancien mot de passe ne passe plus, exécute `ALTER ROLE`, réécrit `config.json`
   et redémarre Semaphore.
4. Vérifier : `https://sem01.par1.medisphere.internal/api/ping` → `pong`, une tâche « Socle — vérifier » réussie.

## Retour arrière

- Avant l'étape A.10, tout est local ou dans la branche : `git restore` des fichiers rechiffrés et remise de
  l'ancien fichier de mot de passe (garde-le jusqu'à l'étape A.12, hors du dépôt, en 600).
- Après fusion : refaire la procédure A dans l'autre sens est inutile ; corriger la valeur fausse (CI ou
  Semaphore) suffit, puisque le dépôt et le poste sont cohérents.
- Procédure B : remettre l'ancienne valeur dans `vault.yml` et réappliquer `sem01.yml`.

## Vérifications de fin

- [ ] Chaque fichier de l'identité se déchiffre avec le nouveau mot de passe et **plus** avec l'ancien
      (`ANSIBLE_VAULT_IDENTITY_LIST=critique@<ANCIEN-FICHIER> uv run ansible-vault view <fichier> > /dev/null`
      échoue : la variable remplace la liste de `ansible.cfg`, seul l'ancien mot de passe est essayé).
- [ ] Pipeline de `main` vert, `appliquer` réussi, convergence à zéro.
- [ ] Modèle Semaphore « Socle — vérifier » réussi.
- [ ] Registre des secrets à jour ; ancienne valeur détruite.
