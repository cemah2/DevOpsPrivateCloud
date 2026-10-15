# Revue de la MR !14 de `medinotif/worker` (Lucas Martin)

> Relecture du <DATE>, M13-E12. Merci Lucas : la chaîne tourne de bout en bout, l'image a bien une SBOM et une signature, et tu as pensé à Renovate. Elle ne peut pas être fusionnée en l'état : plusieurs points exposent des secrets ou rendent la signature sans valeur. Classés du plus grave au moins grave.

## Action immédiate (avant tout le reste)

Le mot de passe d'`admin` de Harbor et la clé Cosign ont été **poussés** sur `git01` dans la branche `lucas/chaine-livraison` : ils sont dans l'historique Git, visibles de tous les membres du projet, et la clé a déjà servi à signer. On change le mot de passe d'`admin` (puis le Vault et la variable de `plateforme/infra`), on considère la clé `cosign.key` comme compromise (jamais reconnue par nos vérificateurs : elle n'est pas `docs/registre/cosign.pub`), on supprime la branche et on purge l'historique, on cherche dans le journal d'audit de Harbor ce qui a été fait avec `admin` depuis la poussée. L'image signée par cette clé est **retirée**.

## Bloquants

1. `.gitlab-ci.yml`, `variables:` : `HARBOR_PASSWORD` du compte **`admin`** en clair. Risque : quiconque lit le dépôt administre le registre. Correctif : robot du projet, `HARBOR_ROBOT_USER` / `HARBOR_ROBOT_TOKEN` en variables protégées (le jeton masqué).
2. `cosign.key` (et `COSIGN_PASSWORD: ""`) dans le dépôt : clé privée en clair, sans phrase de passe. Risque : n'importe qui signe « au nom de MédiSphère ». Correctif : `COSIGN_PRIVATE_KEY` (fichier, protégée) et `COSIGN_PASSWORD` (masquée) des variables du groupe ; la clé MédiSphère, pas une clé de projet.
3. Job `trivy` : image **`aquasec/trivy:0.69.5`**, une des images piégées de mars 2026 (vol des secrets de la CI). Avec le point 1, le mot de passe d'`admin` a pu partir. Correctif : image outillée MédiSphère, épinglée par empreinte.
4. Job `trivy` : `allow_failure: true` et `--exit-code 0`. Risque : une image critique passe. Correctif : contrôle bloquant `--severity CRITICAL --ignore-unfixed --exit-code 1`.
5. Ordre : l'image est **poussée avant** d'être analysée (`build` pousse `latest`). Risque : une image vulnérable est tirable avant même le résultat. Correctif : construction en archive, analyse, puis publication.
6. `cosign sign … $IMAGE:latest` : signature d'une **étiquette**, pas d'une empreinte ; `cosign verify … || true` ne vérifie rien. Risque : on signe ce que `latest` désigne à cet instant (peut-être l'image d'un autre pipeline). Correctif : signer `…@sha256:…` issu de la construction, vérification bloquante.
7. `cosign sign --yes` sans `--signing-config` : la signature et l'attestation partent dans le **journal public** Rekor (nom et empreinte de nos images publiés, définitivement). Correctif : `--signing-config docs/registre/signing-config.json`.
8. `.trivyignore` : six CVE ignorées sans justification ni date, dont **CVE-2024-3094** (porte dérobée de xz). Risque : exceptions éternelles et invérifiables. Correctif : une justification, un auteur, une date de revue par ligne ; retirer celles qui ont un correctif.

## Importants

9. Étiquettes : `latest` et `$CI_COMMIT_SHORT_SHA` réécrits à chaque pipeline, `$CI_COMMIT_TAG` repoussé si le pipeline est rejoué ; aucune règle `rules:` (toute branche publie). Correctif : `vX.Y.Z` sur étiquette protégée seulement, refus si elle existe, immuabilité Harbor.
10. `docker:dind` : exige le mode privilégié (interdit sur `runner02`) et `DOCKER_TLS_CERTDIR: ""` désactive TLS vers le démon. Correctif : BuildKit rootless.
11. `curl … install.sh | sh` de Syft depuis la branche `main` : code non épinglé, non vérifié, exécuté dans le job qui voit les secrets. Correctif : Syft de l'image outillée (paquet vérifié).
12. Images `docker:latest`, `alpine:latest`, `bitnami/cosign:latest` tirées de Docker Hub en direct : interdites par `allowed_images` de `runner02`, non épinglées. Correctif : images de Harbor, `étiquette@sha256`.
13. `GIT_SSL_NO_VERIFY`, `trivy --insecure`, `NODE_TLS_REJECT_UNAUTHORIZED: "0"` : vérification TLS désactivée (attaque de l'intermédiaire possible). Correctif : racine MédiSphère (`MEDISPHERE_ROOT_CA`).
14. `docker login -p` et `cosign login -p` : mot de passe en argument (visible dans `ps`, parfois dans le journal). Correctif : `--password-stdin`.
15. `renovate.json` : fusion automatique de **tout** (majeures comprises), `ignoreTests: true` (fusion même si la CI échoue), `minimumReleaseAge: null`, `pinDigests: false`. Correctif : étendre `local>plateforme/renovate-config` (correctifs seulement, 3 jours, empreintes).
16. `config.js` : jeton GitLab en clair (`glpat-…`), `autodiscover` sans filtre (le bot traiterait tout ce qu'on lui ouvre), `onboarding: true`, `admin` de Harbor en clair. Correctif : `RENOVATE_TOKEN` en variable, `autodiscoverFilter`, robot `renovate` en lecture.

## Mineurs

17. `plateforme/renovate/.gitlab-ci.yml` : pas de `rules:` (Renovate tournerait à chaque poussée), image `latest`, pas d'inclusion du gabarit importé.
18. Le job `sbom` produit la SBOM de `latest`, pas de l'image construite par ce pipeline.

Ce qui est bien : SBOM en SPDX et attestation, idée de vérifier la signature, Renovate branché tôt. La version corrigée tient en vingt lignes : l'inclusion du gabarit `supply-chain.yml` (voir `chaine-livraison.md`).
