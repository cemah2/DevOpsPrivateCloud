# État livré `ci-v1` — la chaîne de CI de MédiSphère v1

> Livré par M19-E46 (PLAT-2046). Ce que le module 20 (GitOps) et les suivants trouvent en entrant.
> Rien de ce tableau ne doit manquer ; rien ne doit porter un autre nom.

| Élément | État |
|---|---|
| GitLab | CE 19.5.x sur `git01` ; courriels vers Mailpit (`smtp.par1.medisphere.internal:25`) ; KAS activé |
| Runners | `k8s-par1` (exécuteur `kubernetes`, étiquettes `k8s`, `kubernetes`, gestionnaire dans `gitlab-runner` en 2 réplicas, PDB, jobs dans `ci-jobs`, PriorityClass `medisphere-ci`) ; `k8s-par1-protege` (`ref_protected`, étiquette `protege`, jobs dans `ci-jobs-protege`, seul à recevoir la clé Cosign et `DEPLOIEMENT_TOKEN`) ; `runner02` (exécuteur `docker`, étiquette `docker`) ; chart `gitlab/gitlab-runner` 0.94.x sous Helmfile (`plateforme/k8s`) |
| Constructions | `buildkitd` rootless partagé (espace `buildkit`, TLS mutuel par `buildkit-ca`, CiliumNetworkPolicy), cache `plateforme/cache-buildkit` ; aucun conteneur privilégié |
| Cache | `s3-01`, compartiment `ci-cache`, identité `ci-cache` |
| Composants | `plateforme/ci-templates` v2.x (étiquettes `vX.Y.Z`, v2.8.0 en fin de module, consommées en `@vX.Y.Z`) : `construction-image`, `qualite`, `securite`, `deploiement`, `promotion` ; catalogue de l'instance ; anciens gabarits v1.x gelés |
| Projets applicatifs | `mediagenda/api`, `mediagenda/chart`, `mediagenda/deploiement`, `medidoc/medidoc`, `mediagenda/annuaire` : uniquement des composants `@vX.Y.Z` ≥ v2.0.0 ; `medidoc/deploiement` créé (M19-E33) |
| Promotion | MR ouverte par `ci-promotion` dans `mediagenda/deploiement` (overlay `dev` par digest) ; recette et prod par MR fusionnée par Julien Petit ou Karim Benali ; porte de vérification Cosign dans les MR ; clé de signature dans le seul Secret `ci-jobs-protege/cosign-medisphere` (plus aucune variable `COSIGN_*` : exception de M19-E24 close) |
| Déploiement en dev | agent `k8s-par1` (espace `gitlab-agent`, 19.5), `ci_access` vers le groupe `mediagenda` et `formation/ci-labo`, droits limités à `mediagenda-dev` et `wb-essais` — **retiré au M20** (Argo CD) |
| Retirés | Jenkins (espace `jenkins`, release, `jenkins.apps…`), SonarQube (espace `sonarqube`, release, base CNPG `sonarqube-db`, `sonarqube.apps…`), variables `SONAR_*` et `JENKINS_*` ; voir ADR-0190 |
| Documentation | ADR-0190 ; RB-190 à RB-198 (`docs/livraison/ci/runbooks/`) ; `cloisonnement.md`, `capacite-runners.md`, `chaine-approvisionnement.md`, `conformite.md`, `anatomie-job.md`, `normes-pipeline.md`, `mesures-pipeline.md`, `secrets-ci.md`, `indicateurs-dora.md`, `comparatif-jenkins.md`, `sous-le-capot.md` |
| Témoin | `formation/ci-pannes` (canari) : conservé ou supprimé (décision écrite ici) |

## Ce que le module 20 doit traiter

- Retirer les accès CI de l'agent aux espaces applicatifs (Argo CD applique, la CI ne fait plus que promouvoir par MR).
- Synchroniser `dev` et `recette` depuis `mediagenda/deploiement` et `medidoc/deploiement`.
- Notifications d'Argo CD vers Mailpit.

## Ce qui n'est pas redondant

`git01` (GitLab entier), `reg01` (Harbor), `s3-01` (cache), `buildkitd` (une réplique), `mon01` (Mailpit). Risques et modules qui les traitent : voir ADR-0190, section « Limites ».
