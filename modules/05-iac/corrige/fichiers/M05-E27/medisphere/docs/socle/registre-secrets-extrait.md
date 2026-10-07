<!-- EXTRAIT (M05-E26, M05-E27, M05-E28) — lignes à ajouter au tableau de
     docs/socle/registre-secrets.md dans plateforme/medisphere (par MR). Aucune valeur. -->

| Identifiant | Type | Propriétaire | Portée / rôle | Stockage | Expiration | Rotation |
|---|---|---|---|---|---|---|
| `tofu-chiffrement` | phrase de chiffrement des états et plans OpenTofu (fournisseur `pbkdf2 "etat"`, 64 caractères hexadécimaux, `openssl rand -hex 32`) | équipe Plateforme | tous les états de `plateforme/infra` (`socle/`, `envs/*`, unités Terragrunt) et les plans enregistrés | `adm01:~/.config/workbook/tofu-chiffrement.pass` (600) ; variable CI `TOFU_PHRASE_CHIFFREMENT` protégée, masquée et cachée ; **coffre de l'équipe** (deux détenteurs, relecture vérifiée à chaque rotation) | aucune (rotation annuelle, ou immédiate si exposée) | voir « Rotation de la phrase » ci-dessous |
| `TOFU_PHRASE_CHIFFREMENT` | variable CI | `plateforme/infra` | jobs `plan:`, `apply:`, `derive:` | GitLab (masquée et cachée : non relisible dans l'interface) | — | avec `tofu-chiffrement` |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (CI) | identité S3 `tofu-etat` | `plateforme/infra` | compartiment `tofu-state` (Read, Write, List) | variables CI protégées ; la clé secrète masquée et cachée | — | avec `s3-tofu` (M05-E11) : nouvelle clé dans `s3.json`, variable, fichier de `adm01`, puis retrait de l'ancienne |
| `DERIVE_TOKEN` | jeton d'accès de **projet** GitLab, rôle Reporter, portée `api` | `plateforme/infra` | créer et commenter les tickets `derive` | variable CI protégée, masquée et cachée | 1 an | nouveau jeton, variable mise à jour, ancien révoqué |

### Rotation de la phrase de chiffrement (non exécutée en E27 ; chaque étape se vérifie)

1. Générer la nouvelle phrase (`openssl rand -hex 32`), la ranger dans le coffre **avant** tout
   usage ; vérifier qu'on la relit depuis le coffre.
2. MR : dans `socle/chiffrement.tf` (copié par Terragrunt), un **nouveau** couple fournisseur /
   méthode sous un **autre nom** (ex. `pbkdf2 "etat_2027"` et `aes_gcm "etat_2027"`) devient la
   méthode principale ; l'ancien couple `etat` reste, avec l'**ancienne** phrase, en `fallback` de
   `state`, `plan` et `remote_state_data_sources`. Le nom compte : chaque état chiffré garde dans
   ses métadonnées le sel PBKDF2 **sous le nom de son fournisseur** ; donner la nouvelle phrase au
   fournisseur `etat` rendrait les états existants illisibles. `TF_ENCRYPTION` contient alors
   **deux** fournisseurs (`outils/charger-acces.sh` et `ci-preparer.sh` lisent un second fichier /
   une seconde variable).
3. Apply de chaque état (plans vides : réécriture avec la nouvelle clé). Vérifier : chaque objet
   de `tofu-state` a une nouvelle version ; `tofu plan` réussit avec la **seule** nouvelle phrase
   (retirer temporairement l'ancienne de `TF_ENCRYPTION` sur `adm01`).
4. MR qui retire le `fallback` et l'ancien couple `etat` ; retrait de l'ancienne phrase des
   variables CI, de `~/.config/workbook/` et du coffre **après** une copie externe des états
   (E29) chiffrée avec la nouvelle.
5. Les copies externes antérieures restent chiffrées avec l'ancienne phrase : la garder dans le
   coffre, étiquetée « lecture des sauvegardes antérieures au AAAA-MM-JJ », 90 jours (durée de
   conservation des artefacts), puis la détruire.
