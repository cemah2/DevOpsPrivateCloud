# La CI et le coffre

| | |
|---|---|
| Ticket | SEC-2610 (M25-E10) |
| Propriétaire | Équipe Plateforme ; relecture : Sophie Laurent (RSSI) |
| Configuration | `plateforme/secrets` : `tofu/auth-gitlab.tf`, `politiques/ci-*.hcl`, `politiques/tofu-secrets.hcl` |
| Composants | `plateforme/ci-templates` : `securite` ≥ v2.9.0 (`.openbao-connexion`), `promotion` ≥ v2.8.0, `release` ≥ v2.1.0 |

## 1. Le chemin d'un job vers un secret

```
job GitLab (pod du runner k8s-par1 / k8s-par1-protege, ou runner01)
  │ 1. id_tokens : GitLab signe un JWT (RS256) — iss git01, aud openbao.medisphere.internal,
  │    project_id, project_path, ref, ref_type, ref_protected, environment, runner_id… ; 5 min
  ▼
OpenBao  auth/gitlab/login  (rôle ci-<groupe>-<projet>[-promotion])
  │ 2. signature vérifiée contre les clés publiées par git01 (découverte OIDC, racine MédiSphère)
  │ 3. iss = bound_issuer, aud ∈ bound_audiences, exp/nbf, revendications liées (glob)
  │ 4. jeton de SERVICE de 10 min, politique du rôle, métadonnées (projet, ref, pipeline, job)
  ▼
kv/data/…  lecture seule, chemins exacts ; jeton révoqué en after_script
```

Aucun secret n'est stocké dans GitLab pour ces jobs : la preuve est le jeton d'identité, émis pour un job, valable quelques minutes, et inutilisable par un autre service (audience).

## 2. Rôles et revendications

| Rôle | Projet | Références | Environnement | Politique | Lit |
|---|---|---|---|---|---|
| `ci-mediagenda-api` | `mediagenda/api` | `main`, `v*` protégées | — | `ci-mediagenda-api` | `kv/plateforme/harbor/robot-ci`, `kv/mediagenda/ci/release` |
| `ci-mediagenda-api-promotion` | `mediagenda/api` | `main`, `v*` protégées | `promotion/*` | `ci-mediagenda-api-promotion` | `kv/mediagenda/ci/promotion` |
| `ci-medidoc-medidoc` (+ `-promotion`) | `medidoc/medidoc` | idem | idem | idem | `kv/medidoc/ci/*` correspondants |
| `ci-plateforme-secrets` | `plateforme/secrets` | `main`, `conf/*` protégées | — | `tofu-secrets` | configuration du coffre, `kv/plateforme/tofu/etat-secrets` |
| `ci-plateforme-ansible` (+ `-critique`) | `plateforme/ansible` | M25-E11 | `lab/socle` pour critique | `ansible-lab` / `ansible-critique` | mots de passe Ansible Vault |

Revendications : `project_id` (et non le chemin, réattribuable), `ref_protected` (**chaîne** `"true"`), `ref` et `ref_type` ; `sub` seul ne suffit pas (ni protection, ni environnement). Durée : 10 minutes (`token_explicit_max_ttl`), jeton de service (révocable par accesseur, RB-250).

## 3. Ce qui reste en variables de CI, et pourquoi

| Variable | Où | Pourquoi elle reste | Revue |
|---|---|---|---|
| `*_RO_USER` / `*_RO_TOKEN` (robots Harbor en lecture) | groupes | les pipelines de MR tournent sur des branches non protégées, que le coffre refuse ; exposition acceptée (lecture d'images que le cluster tire déjà) | M25-E46 : rôle de lecture sans contrainte de protection |
| `MEDISPHERE_ROOT_CA` | instance | publique | — |
| Clé Cosign (fichier monté par le runner protégé) | Secret `ci-jobs-protege/cosign-medisphere` | migrée vers transit en E20 | E20 |
| Accès de `plateforme/ansible` | projet | migrés en E11 | E11 |

## 4. Exploitation

- Un nouveau projet qui a besoin d'un secret : une MR sur `plateforme/secrets` (rôle dans `roles_ci`, politique `politiques/ci-<groupe>-<projet>.hcl`, identifiant du projet), relue par la plateforme ; le secret écrit dans `kv/<groupe>/ci/…` par l'entrée standard.
- Refus à la connexion : le message de la méthode dit quelle revendication ne correspond pas (`claim "ref_protected" does not match…`) ; le journal d'audit (E21) garde la trace.
- GitLab change sa clé de signature : rien à faire (découverte OIDC). Si la découverte est injoignable depuis `vault01`, plus aucun job ne se connecte (alerte E27).
- Bris de glace : un pipeline ne peut pas obtenir de secret quand le coffre est fermé ; la publication attend (RB-251, RB-255).
