# Modèle d'accès au coffre OpenBao

> M25-E05 (SEC-2605). Qui peut faire quoi dans OpenBao, et pourquoi. Les politiques elles-mêmes sont
> les fichiers `politiques/*.hcl` de `plateforme/secrets` (en code depuis M25-E08) ; ce document en
> donne l'intention. Revue : Sophie Laurent, à chaque MR qui touche une politique.

## Principes

1. **Personne n'a de jeton racine au quotidien.** Le jeton initial est révoqué (M25-E08) ; un jeton racine se régénère avec trois parts de la clé, pour une opération précise, puis se révoque.
2. **Les droits viennent des groupes** de l'annuaire (revendication `groups` de Keycloak) par des **groupes externes** d'OpenBao ; aucune politique n'est attachée à une personne.
3. **Lire la configuration n'est pas lire les secrets.** Les politiques de lecture voient `kv/metadata/*` (existence, versions, propriétaire), jamais `kv/data/*`.
4. **Les machines ont leur identité** (AppRole, puis JWT de GitLab et comptes de service Kubernetes au palier 2), liée à une adresse ou à des revendications vérifiées, avec des jetons courts.
5. **Ce qui n'est pas permis est refusé** : une politique liste des chemins et des capacités ; tout le reste est interdit.

## Groupes et politiques

| Groupe Keycloak | Politique | Peut | Ne peut pas |
|---|---|---|---|
| `plateforme-admins` (`<MOI>`, Karim) | `plateforme-admin` | monter des moteurs, régler les méthodes, écrire les politiques, gérer les identités, lire et écrire `kv/plateforme/*`, sceller en urgence, régénérer un jeton racine avec les parts | lire `kv/<application>/*`, `sys/raw`, tourner les clés de la barrière |
| `plateforme` (+ Lucas), `support` (Nadia) | `plateforme-lecture` | voir la configuration, les politiques, les rôles, l'existence et les versions des secrets | lire une valeur, écrire quoi que ce soit |
| `securite` (Sophie) | `securite-audit` | tout voir de la configuration, lister les dispositifs d'audit, les jetons vivants (métadonnées), calculer un HMAC d'audit | lire une valeur, modifier |
| `mediagenda` (Julien) | `mediagenda-dev` | gérer `kv/mediagenda/dev/*` (écrire, lire, supprimer, restaurer) | recette, production, détruire une version, rien d'autre |
| `direction`, `medidoc` | — (`default`) | se connecter | rien |

Machines du palier 1 : `wb-checks` (vérifications du workbook, métadonnées), `medictl` (ses secrets Proxmox).

## Règles d'écriture des politiques

- **Priorité entre motifs.** Quand plusieurs politiques s'appliquent, OpenBao ne cumule les capacités que pour une **même chaîne** de chemin. Pour des motifs différents, c'est le **plus précis** qui l'emporte, seul : `auth/+/role/+` (lecture, dans une politique) masque `auth/+/role/*` (écriture, dans une autre). Les membres de `plateforme-admins` sont aussi dans `plateforme` : les politiques de lecture reprennent donc **exactement** les motifs de `plateforme-admin`.
- `*` ne s'emploie qu'en fin de chemin (« tout ce qui commence par ») ; `+` remplace **un** segment.
- Une **liste** porte en général sur le chemin **avec la barre finale** (`auth/oidc/role/`, `kv/metadata/mediagenda/`) : une règle sans barre (`auth/+/role`) ne l'autorise pas. `*` couvre aussi la chaîne vide : `kv/metadata/mediagenda/dev/*` permet de lister `kv/metadata/mediagenda/dev/`. En cas de doute, `bao token capabilities` sur le chemin exact, ou un essai.
- `deny` l'emporte sur tout, dans toute politique : à réserver aux interdits explicites.
- Certaines opérations exigent `sudo` en plus de la capacité : activer ou régler une méthode (`sys/auth/*`), lister les dispositifs d'audit (`sys/audit`), sceller (`sys/seal`), créer un jeton orphelin.
- Vérifier avant de fusionner : `bao token capabilities <jeton> <chemin>` pour chaque chemin sensible, avec un jeton de chaque politique.

## Jetons

| Usage | Type | Durée |
|---|---|---|
| Personne (OIDC) | service, renouvelable | 1 h, 8 h au plus |
| Vérifications, medictl (AppRole) | *batch* | 10 et 5 minutes |
| OpenTofu | enfant du jeton de la personne | 20 minutes, révoqué en fin d'exécution |
| Jeton racine | — | aucun ; régénéré pour une opération, révoqué aussitôt |
