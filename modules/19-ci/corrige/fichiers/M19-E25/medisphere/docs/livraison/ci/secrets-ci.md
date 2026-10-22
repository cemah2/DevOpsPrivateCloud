# Secrets de la CI

| | |
|---|---|
| Ticket | SEC-2025 (M19-E25) |
| Propriétaire | Équipe Plateforme ; relecture : Sophie Laurent (RSSI) |
| Inventaire | `plateforme/outils` : `bin/ci-inventaire-variables.sh` (TSV, sans valeurs), relancé chaque mois |
| Rotation | RB-191 |

## 1. Où vivent les secrets de la CI

| Secret | Où | Qui le reçoit | Attributs | Expiration / rotation |
|---|---|---|---|---|
| Clé Cosign + mot de passe | Vault `critique` (`plateforme/k8s/secrets/cosign-ci.yml`) → Secret `ci-jobs-protege/cosign-medisphere` | jobs du runner `k8s-par1-protege` seulement (volume) | — (hors GitLab) | pas d'expiration ; rotation = nouvelle paire + re-signature (procédure de M13, RB-13x) |
| `COSIGN_PRIVATE_KEY`, `COSIGN_PASSWORD` (groupe `mediagenda`… — **exception E24**) | variables de groupe | jobs des références protégées des projets v1 | protégées ; `COSIGN_PASSWORD` masquée ; `COSIGN_PRIVATE_KEY` de type fichier, **non masquable** (PEM multiligne, M13-E07) : seule variable à clé de secret non masquée admise | supprimées au mini-projet (M19-E46) |
| `DEPLOIEMENT_TOKEN` (`mediagenda/api`) | variable de projet ; jeton de projet `ci-promotion` de `mediagenda/deploiement` | jobs `promouvoir-*` (environnement `promotion/*`) sur `protege` | protégée, masquée **et cachée**, portée `promotion/*` | 90 jours, rotation tous les 60 jours (RB-191 §2) |
| `DEPLOIEMENT_TOKEN` (`medidoc/medidoc`, E33) | idem pour `medidoc/deploiement` | idem | idem | idem |
| `HARBOR_ROBOT_USER` / `HARBOR_ROBOT_TOKEN` | variables de groupe ; robot `robot$medisphere+ci` (état OpenTofu `registre`) | jobs de publication | jeton : protégée, masquée, cachée | 90 jours, rotation tous les 60 jours (RB-191 §3) |
| `GITLAB_TOKEN` (semantic-release, M01) | variable de projet ; jeton de projet | job `release` | protégée, masquée, cachée | 1 an maximum, rotation annuelle |
| `SONAR_TOKEN` (E16) | variable de projet | job d'analyse | protégée, masquée | **supprimé** avec SonarQube (M19-E46) |
| `MEDISPHERE_ROOT_CA` | variable d'instance, type fichier | tous les jobs | non secrète, visible | renouvelée avec la racine (2035) |
| Jetons `glrt-` des runners | Vault `critique` → Secrets `gitlab-runner/*-jeton` | gestionnaires | — | rotation par `POST /runners/:id/reset_authentication_token` (RB-191 §4) |
| Jeton de l'agent `k8s-par1` | Vault `critique` → Secret `gitlab-agent` | `agentk` | — | rotation par l'interface (deux jetons actifs au plus) |
| Identité S3 `ci-cache` | Vault `critique` → Secret `gitlab-runner/ci-cache-s3` | gestionnaire (URL présignées) | — | annuelle |

## 2. Règles retenues

- **Protégée** pour tout secret : seules les références protégées le reçoivent. Ne protège **pas** contre un job de `main` qui n'en a pas besoin : d'où la portée d'environnement (projet, Free) et, mieux, le secret monté par le runner protégé.
- **Masquée** : le journal remplace la valeur exacte par `[MASKED]`. Ne protège pas d'une valeur transformée (`base64`, découpée, encodée en URL), écrite dans un fichier d'artefact, envoyée sur le réseau, ou affichée caractère par caractère. `set -x` affiche la commande **après** substitution : le masquage la rattrape si la valeur apparaît telle quelle, pas si elle est transformée.
- **Cachée** (*Masked and hidden*) : la valeur n'est plus visible dans l'interface ni par l'API, même par un Maintainer ; elle ne se modifie qu'en la recréant. Pour tous les jetons.
- **Type fichier** pour clés, certificats et configurations : la valeur n'est pas dans l'environnement du processus (`/proc/<pid>/environ`), seulement son chemin.
- **`raw`** pour toute valeur qui contient `$` (sinon GitLab tente de la développer).
- **Portée d'environnement** : `DEPLOIEMENT_TOKEN` en `promotion/*` ; les jobs de promotion déclarent `environment: {name: promotion/<cible>, action: prepare}`. Constaté : un job de `main` sans environnement ne reçoit plus la variable (`echo ${DEPLOIEMENT_TOKEN:+présente}` n'affiche rien).
- **Identités de lecture** (`*_RO_USER`/`*_RO_TOKEN` : robots Harbor en tirage seul, `HARBOR_CHARTS_RO_*` du M17, `HARBOR_ROBOT_RO_*` de la porte E29) : masquées mais **non protégées**, car les pipelines de MR tournent sur des branches non protégées ; exposition acceptée (lecture d'images que le cluster tire déjà).
- **Groupe vs projet** : en Free, la portée d'environnement n'existe pas au niveau du groupe ; un secret de groupe est donc remis à toute référence protégée de tout projet du groupe.

## 3. `CI_JOB_TOKEN`

- Liste d'autorisation entrante **active** sur chaque projet des groupes `plateforme`, `mediagenda`, `medidoc`, `medinotif`, `legacy`, `formation` ; réglage d'instance *Enforce job token allowlist* activé (plus de désactivation projet par projet).
- Autorisations accordées (justifiées) :

| Projet cible | Autorise | Pourquoi |
|---|---|---|
| `mediagenda/deploiement` | `mediagenda/chart` | job de validation déclenché par l'étiquette du chart (E12) qui lit le dépôt de déploiement avec `CI_JOB_TOKEN` |
| `plateforme/outils` | groupes `mediagenda`, `medidoc` | paquet `medictl` du registre de paquets (M02) installé dans des jobs |

- Non nécessaire : `include: component` (résolu par le serveur avec les droits de l'auteur du pipeline), `trigger:project` (droits de l'utilisateur), la promotion (jeton `ci-promotion`).
- Essai inverse : depuis `formation/ci-labo`, `git clone https://gitlab-ci-token:${CI_JOB_TOKEN}@git01.par1.medisphere.internal/mediagenda/deploiement.git` → `remote: … not allowed` / 403.

## 4. Jetons d'identité (préparation du M25)

Relevé du job `jeton-identite` de `formation/ci-labo` (AAAA-MM-JJ) :

| Revendication | Branche `essai-oidc` | `main` |
|---|---|---|
| `iss` | `https://git01.par1.medisphere.internal` | idem |
| `aud` | `openbao.medisphere.internal` | idem |
| `sub` | `project_path:formation/ci-labo:ref_type:branch:ref:essai-oidc` | `project_path:formation/ci-labo:ref_type:branch:ref:main` |
| `ref_protected` | `"false"` | `"true"` |
| `namespace_path` / `project_path` | `formation` / `formation/ci-labo` | idem |
| `runner_id` | id de `k8s-par1` | id de `k8s-par1` (ou de `k8s-par1-protege` pour un job `protege`) |
| `environment` | absente | absente (présente pour un job qui déclare un environnement) |
| `exp - iat` | 300 s (durée du job bornée) | idem |

Signature RS256 vérifiée contre `https://git01.par1.medisphere.internal/oauth/discovery/keys`.

**Ce que la politique d'OpenBao devra exiger (M25)** : `aud` = `openbao.medisphere.internal` ; `project_path` (ou mieux `project_id`, stable au renommage) dans une liste ; `ref_protected` = `true` et `ref` = `main` ou une étiquette `v*` pour tout secret de production ; `runner_id` du runner protégé pour la clé de signature ; `environment` = `promotion/*` pour le jeton de promotion. **`sub` seul ne suffit pas** : il décrit le projet et la référence, mais pas si la référence est protégée (sauf personnalisation, `ci_id_token_sub_claim_components`), ni le runner, ni l'environnement ; une branche nommée `main` dans un projet renommé ou recréé au même chemin hériterait des droits (GitLab bloque d'ailleurs l'émission dans ce cas).

## 5. Calendrier de rotation

| Secret | Dernière rotation | Prochaine | Rappel |
|---|---|---|---|
| `ci-promotion` (`mediagenda/deploiement`) | AAAA-MM-JJ (E25) | +60 j | courriel `plateforme@` (Mailpit) par le contrôle mensuel |
| `robot$medisphere+ci` | AAAA-MM-JJ (E25) | +60 j | idem |
| `GITLAB_TOKEN` (semantic-release) | AAAA-MM-JJ | +1 an | idem |
| jetons `glrt-` | E04 / E24 | annuelle | idem |
