# Ansible et le coffre

| | |
|---|---|
| Ticket | PLAT-2611 (M25-E11) |
| Propriétaire | Équipe Plateforme ; relecture : Karim Benali |
| Configuration | `plateforme/secrets` : `politiques/ansible-lab.hcl`, `politiques/ansible-critique.hcl`, `tofu/ci-ansible.tf` ; `plateforme/ansible` : `outils/vault-pass-client.sh`, `outils/openbao-ci.sh`, `ansible.cfg` |

## 1. Où sont les mots de passe

| Identité | Chemin | Qui le lit |
|---|---|---|
| `lab` | `kv/plateforme/ansible-vault/lab` (clé `mot-de-passe`) | groupe OIDC `plateforme` (Lucas compris), `plateforme-admins`, jobs protégés de `plateforme/ansible` (`ci-plateforme-ansible`) |
| `critique` | `kv/plateforme/ansible-vault/critique` | `plateforme-admins`, jobs `appliquer`/`derive` de `main` en `lab/socle` (`ci-plateforme-ansible-critique`) |

Deux chemins et non deux clés d'un même secret : une politique OpenBao accorde un **chemin**, toutes ses clés avec. `kv/plateforme/ansible-vault` avec `lab` et `critique` aurait donné `critique` à quiconque lit `lab`.

Plus aucune copie dans `~/.config/workbook/` ni dans les variables de CI.

## 2. Utilisation

```
admin@adm01:~$ bao login -method=oidc            # navigateur, OTP ; jeton dans ~/.vault-token
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --check --diff
```

Sans session : `vault-pass-client : pas de jeton OpenBao valide… Connecte-toi : bao login -method=oidc`. Toute lecture est dans l'audit (E21) avec l'identité de la personne ou du job.

## 3. Bris de glace : coffre fermé ou injoignable

Quand : OpenBao scellé, grappe sans leader, `vault01-03` injoignables, et un playbook est **nécessaire** pour réparer (le rôle `openbao` lui-même, la bordure, `step-ca`).

1. **Décider** : astreinte (Nadia) + un administrateur plateforme ; ouvrir un ticket `INC-`.
2. **Sortir les mots de passe** : copie hors ligne chiffrée par `age` (même support et même procédure que les parts de descellement, M25-E03), déchiffrée **sur `adm01`** par un dépositaire, dans un fichier `600` d'un répertoire temporaire en mémoire :
   ```
   admin@adm01:~$ install -d -m 700 /dev/shm/ansible-secours
   admin@adm01:~$ age -d -i <CLÉ-DU-DÉPOSITAIRE> <SUPPORT>/ansible-vault-critique.age > /dev/shm/ansible-secours/critique.pass
   ```
3. **Lancer** en mode secours explicite :
   ```
   admin@adm01:~/src/ansible$ VAULT_PASS_SECOURS=1 VAULT_PASS_CRITIQUE=/dev/shm/ansible-secours/critique.pass \
       uv run ansible-playbook playbooks/<PLAYBOOK>.yml --limit <HÔTE>
   ```
4. **Refermer** : `shred -u /dev/shm/ansible-secours/*.pass`, `rmdir`, ligne au journal de l'incident ; si la copie a été exposée (écran partagé, fichier oublié), rotation des mots de passe Ansible Vault (`ansible-vault rekey`) dès que le coffre est revenu.

Les lookups (`community.hashi_vault`) ne fonctionnent pas en mode secours : un playbook qui en dépend (Mailpit sur `mon01`) attend le retour du coffre. C'est pourquoi les secrets d'**amorçage** (ce qu'il faut pour rouvrir le coffre) restent dans des fichiers Ansible Vault.

## 4. Essai de la procédure

| Date | Qui | Simulation | Résultat |
|---|---|---|---|
| Essai du AAAA-MM-JJ | `<MOI>` (témoin : `<MOI>`) | `BAO_ADDR=https://127.0.0.1:1` (coffre injoignable), `--check` sur `adm01` | refus clair sans secours ; secours avec `VAULT_PASS_SECOURS=1` : `--check` réussi ; fichiers effacés |

## 5. Secrets servis directement aux playbooks

| Secret | Chemin | Consommateur | Depuis |
|---|---|---|---|
| Comptes de Mailpit | `kv/plateforme/mailpit/comptes` (`moi`, `wb-checks`) | `host_vars/mon01/mailpit.yml` (`vault_kv2_get`) | M25-E11 |

Règle : tout **nouveau** secret d'un playbook va dans le coffre et se lit par lookup ; les fichiers chiffrés restent pour l'amorçage et sont réduits petit à petit.
