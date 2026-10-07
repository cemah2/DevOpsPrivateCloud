# RB-040 — Appliquer un changement de configuration sur le socle

| | |
|---|---|
| Service | Configuration du socle par Ansible (projet `plateforme/ansible`) : `gw01`, `adm01`, `dns01`, `git01`, `runner01` |
| Rédigé | M04-E22 (CHG-532) — dernière exécution complète : AAAA-MM-JJ, changement CHG-… |
| Qui peut l'exécuter | Équipe Plateforme (Maintainer de `plateforme/ansible`) ; l'astreinte en mode « secours » (§ 7) |
| Durée attendue | 15 à 30 min pour un changement simple ; prévoir 1 h sur `gw01` |
| Retour arrière | Rejouer le dernier état fusionné (§ 6) ; instantané Proxmox en dernier recours |

## Quand utiliser ce runbook

- Toute modification d'un rôle, d'une variable d'inventaire ou d'un playbook du projet, **une fois la MR fusionnée** dans `main`.
- Un écart constaté entre un hôte et le code (dérive) : on réapplique le code, on ne corrige pas l'hôte à la main.

**Ne pas utiliser** pour une intervention d'urgence sur un hôte qui ne répond plus en SSH (console série, RB-002) ni pour une mise à jour de paquets en série (M04-E25).

## Règles

1. **Rien sans MR fusionnée** : on applique `main`, jamais une branche locale ni un fichier modifié à la main. `git status` doit être propre.
2. **Toujours `--check --diff` d'abord**, et le diff est **lu**. Ce qui n'est pas compris n'est pas appliqué.
3. **Un hôte, puis les autres.** Le premier est le moins critique concerné (ordre : `runner01`, `dns01`, `git01`, `adm01`, `gw01` en dernier et seul).
4. **`gw01` à part** : jamais dans le même passage qu'un autre hôte ; session de secours ouverte (§ 2).
5. **Tout changement a un numéro** (CHG-… ou INC-…), repris par l'enveloppe `changement-socle.yml` dans l'instantané et le journal.

## Ce qu'il faut avoir sous la main

- Le numéro du changement et le lien de la MR fusionnée.
- Sur `adm01` : clé SSH chargée (`ssh-add -l`), mot de passe Vault (`~/.config/workbook/ansible-vault.pass`), accès Proxmox de l'inventaire (`~/.config/workbook/pve-ansible.env`), `ms-snapshot` (M02).
- Une console série ouverte sur l'hôte le plus sensible du changement : `ssh pve01 qm terminal <VMID>` (sortie : `Ctrl+O`), compte `secours` (mot de passe dans le coffre de l'équipe).

## Étapes

### 1. Préparer (adm01)

```
admin@adm01:~$ cd ~/src/ansible && git switch main && git pull --ff-only && git status --short
admin@adm01:~$ uv sync --locked
admin@adm01:~$ uv run ansible-galaxy collection install -r collections/requirements.yml -p collections
admin@adm01:~$ set -a; . ~/.config/workbook/pve-ansible.env; set +a
admin@adm01:~$ uv run ansible-inventory --graph socle          # les 5 hôtes, inventaire dynamique
```

Attendu : aucun fichier modifié ; l'inventaire liste `gw01`, `adm01`, `dns01`, `git01`, `runner01`. Si l'inventaire dynamique échoue (API Proxmox indisponible) : `-i inventories/lab/hosts.yml` sur toutes les commandes suivantes, et le noter dans le ticket.

### 2. Ouvrir l'accès de secours

- Changement sur `gw01` : console `ssh pve01 qm terminal 1000` connectée **et** session SSH ouverte sur `gw01` (elle survit au rechargement du pare-feu).
- Changement qui touche `ssh_durci` ou les clés (`base_utilisateurs`) : session SSH ouverte sur chaque hôte concerné, et console prête.

### 3. Simuler

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --check --diff --limit <HÔTE> [--tags <ÉTIQUETTE>]
```

Attendu : `failed=0`, `unreachable=0` ; les `changed` correspondent exactement à la MR (un fichier, une ligne…). Tout autre changement est une **dérive** : on s'arrête et on l'explique avant d'aller plus loin (qui a modifié l'hôte, ou que contient `main` qu'on n'attendait pas).

Limites de `--check` à avoir en tête : les commandes (`command`, `shell`) ne s'exécutent pas, les handlers non plus, `no_log` masque le diff des comptes et des jetons, et le pare-feu ne montre que son diff.

### 4. Appliquer sur le premier hôte

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/changement-socle.yml -e changement=<CHG-NNN> --limit <HÔTE> [--tags <ÉTIQUETTE>]
```

L'enveloppe prend un instantané Proxmox (`<chg-nnn>-AAAAMMJJ-HHMMSS`), applique `site.yml`, vérifie le nom DNS et le SSH de l'hôte, puis écrit une ligne dans `docs/socle/journal/changements-ansible.md` (à pousser avec la documentation).

Contrôles, puis **second passage** :

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --check --limit <HÔTE>   # attendu : changed=0
admin@adm01:~$ ssh -o ControlPath=none <HÔTE> true                                              # nouvelle connexion SSH
```

Plus le contrôle propre au changement (service redémarré, `sshd -T`, `chronyc sources`, `nft list ruleset`…).

### 5. Étendre

Même commande, sur les hôtes restants (`--limit 'socle:!gw01'`, puis `gw01` seul). Second passage à `changed=0` sur tout le périmètre.

`gw01` : le rôle `pare_feu` arme un retour automatique ; s'il échoue avec « La nouvelle configuration nftables n'a pas été confirmée », **ne relance pas** : `gw01` est revenu à l'ancienne configuration ; lis `sudo journalctl -t pare-feu-retour` et corrige la matrice des flux par une nouvelle MR.

### 6. Revenir en arrière

Ordre de préférence :

1. **Revert de la MR** dans GitLab (nouvelle MR), puis ce runbook depuis l'étape 1 : la configuration redevient celle d'avant, de la même façon qu'elle a été appliquée.
2. Urgence, sans attendre la MR : appliquer le commit précédent depuis un clone de travail détaché (`git switch --detach <COMMIT-PRÉCÉDENT>`), avec `--limit` sur les hôtes touchés ; régulariser par la MR de revert ensuite.
3. Hôte inutilisable : retour à l'instantané (`ssh pve01 qm rollback <VMID> <chg-nnn-…>`), **en sachant** que tout ce qui a changé sur l'hôte depuis (données, journaux) est perdu ; puis rejouer `main` dès que possible pour retrouver un état connu.

Une fois le changement validé (24 h sans anomalie) : supprimer les instantanés `chg-…` (`ms-snapshot` ne garde que les 2 derniers de chaque préfixe ; les autres se suppriment par `qm delsnapshot`).

### 7. Mode secours (astreinte, hors heures ouvrées)

L'astreinte peut **réappliquer** `main` (étapes 1 à 5) pour corriger une dérive ou après une restauration. Elle ne fusionne pas de MR et ne modifie pas le code ; un correctif de code attend l'équipe Plateforme, sauf incident majeur (validation de Claire Morel par téléphone, tracée dans le ticket).

## Que faire si…

| Symptôme | Cause probable | Action |
|---|---|---|
| `UNREACHABLE` sur un hôte | agent SSH vide, hôte arrêté, clé d'hôte changée, pare-feu | `ssh-add -l` ; `ssh -o ControlPath=none <HÔTE>` ; ne jamais désactiver la vérification des clés d'hôte |
| `Decryption failed` / `no vault secrets` | fichier de mot de passe absent ou mauvais identifiant | `ls -l ~/.config/workbook/ansible-vault.pass` ; `ansible-config dump --only-changed \| grep VAULT` |
| Inventaire vide ou en erreur | accès Proxmox non chargé, jeton expiré | `env \| grep ^PROXMOX_` ; `ansible-inventory --graph` ; repli sur `hosts.yml` |
| Le second passage n'est pas à `changed=0` | tâche non idempotente, ou quelqu'un modifie l'hôte en parallèle | relire la tâche signalée ; ne pas « corriger » par une boucle de passages |
| Échec dans un `rescue` (chrony, pare-feu) | le rôle est revenu en arrière tout seul | lire son message : l'hôte est dans l'état précédent, rien à défaire |

## Après

- Ticket mis à jour : commandes lancées, récapitulatifs (`PLAY RECAP`), écarts constatés.
- `docs/socle/journal/changements-ansible.md` poussé par MR dans `plateforme/medisphere`.
- Si une étape de ce runbook était fausse ou incomplète : MR sur ce runbook le jour même.
