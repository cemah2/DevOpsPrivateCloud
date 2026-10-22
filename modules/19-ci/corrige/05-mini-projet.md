# Module 19 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

---

### M19-E46 — Mini-projet : la chaîne de CI de MédiSphère v1

Il n'y a pas de solution unique : ce corrigé donne un **plan de travail** éprouvé, les points de contrôle de chaque étape, la préparation des démonstrations et la **grille de revue** avec laquelle Claire, Karim, Sophie, Julien et Nadia évaluent la livraison. Les fichiers de référence sont ceux des exercices du module ; les nouveaux sont le modèle de l'état livré [`etat-ci-v1.md`](fichiers/M19-E46/medisphere/docs/livraison/ci/etat-ci-v1.md) et la procédure de [retrait de Jenkins et de SonarQube](fichiers/M19-E46/medisphere/docs/livraison/ci/retrait-jenkins-sonarqube.md).

**Solution**

*Plan de travail recommandé* (on fige les preuves, on adopte, on retire, on documente)

1. **État des lieux** (1 h) : `lab/bin/check 19 46`, puis `lab/bin/check 19 43` (tout le palier 4) et les contrôles détaillés rouges. Inventaire des restes : `ls ~/.local/state/workbook/pannes-actives/`, projets et branches d'essai (`gl "projects?search=…"`), variables de projet et de groupe contenant `SONAR`, `JENKINS`, `DEBUG`, runners (`gl runners/all`), espaces du cluster (`kubectl get ns`).
2. **Figer les preuves de l'ADR-0190** (30 min) : mesures du comparatif Jenkins (M19-E20), constat des limites de SonarQube Community Build (M19-E16), captures ; tout est dans `plateforme/medisphere` **avant** le retrait.
3. **Adoption des composants** (3 à 4 h) : pour chaque projet applicatif, une MR qui remplace les `include` restants par les composants (épinglés à une version complète `@vX.Y.Z`, la dernière publiée, pas `~latest` ni `@2`), pipeline de MR vert, fusion. Ordre conseillé : `mediagenda/chart` (le plus simple), `mediagenda/annuaire`, `medidoc/medidoc`, `mediagenda/deploiement` (porte de vérification), `mediagenda/api` en dernier (le plus long, il sert à la démonstration de Julien). Vérifie avec `POST /projects/:id/ci/lint` (`dry_run`) avant chaque MR.
4. **Retrait de Jenkins et de SonarQube** (2 h) : procédure du fichier fourni, **par le code** (`plateforme/k8s`, Vault, variables de CI), puis vérifications (`kubectl get ns`, `helm list -A`, `dig`, recherche de variables).
5. **Runners et dérive** (1 h) : `helmfile -e par1 diff` vide ; attributs des runners (étiquettes, protection, `maximum_timeout`) identiques au script de création ; `runner02` : liste de ses usages restants (projets avec l'étiquette `docker`), justifiés dans `etat-ci-v1.md` ou migrés.
6. **Sécurité** (1 à 2 h) : fin de l'exception Cosign de M19-E24 : `mediagenda/chart` signe désormais son chart par le composant `securite` sur le runner protégé (ou par un job local étiqueté `protege` qui lit la clé montée), pipeline d'étiquette du chart vert ; `medinotif/worker` aussi : le plus simple est de le passer sur les composants `construction-image` et `securite` @v2.8.0 comme `mediagenda/annuaire` en E34 (sinon, surcharge de son job `sc:signature` : `tags: [protege]`, `COSIGN_PRIVATE_KEY: /run/secrets/medisphere/cosign/cosign.key` en variable du job et `COSIGN_PASSWORD` lu dans `cosign.password` en début de script), pipeline d'étiquette du worker vert ; **puis** suppression des variables de groupe `COSIGN_PRIVATE_KEY` et `COSIGN_PASSWORD` de `mediagenda`, `medidoc`, `medinotif` (et `legacy`, si ce n'est pas déjà fait en E24) (`DELETE /groups/:id/variables/:key`, avec un pipeline témoin de chaque projet signé après), exception close dans `cloisonnement.md` et `secrets-ci.md` ; inventaire des jetons longue durée (robots Harbor de CI, `DEPLOIEMENT_TOKEN`, jeton de l'agent, jetons de semantic-release) avec expiration et procédure (M19-E25) ; variables sensibles masquées, cachées si possible, protégées ; aucune variable sensible sans protection (`gl "projects/<id>/variables" | jq '.[] | select(.protected | not) | .key'`) ; règle Semgrep contre `set -x` et `CI_DEBUG_TRACE` dans le composant `securite`.
7. **Bout en bout et démonstrations** (1 à 2 h) : répétition des trois démonstrations (tableau ci-dessous), chronométrées.
8. **Documentation et livraison** (2 h) : ADR-0190 relue (statut « acceptée », limites), RB-190 à RB-198 (`docs/livraison/ci/runbooks/`), `etat-ci-v1.md`, matrice des flux (ajouts du module, retraits de Jenkins et SonarQube), journal et post-mortem INC-4643 ; MR, pipelines verts, étiquette `ci-v1` sur `plateforme/medisphere`.

*Démonstration de Julien — de la MR à `mediagenda-dev`* (à répéter avant la revue)

| Étape | Ce qu'on montre | Durée de référence sur le lab (indicative) |
|---|---|---|
| 1 | MR de correction sur `mediagenda/api` : pipeline de MR (lint, tests, analyses, construction sans poussée) | 4 à 7 min |
| 2 | Fusion ; semantic-release pose `vX.Y.Z` ; pipeline de l'étiquette : construction, Trivy, SBOM, signature et provenance par le runner protégé, poussée | 6 à 10 min |
| 3 | Job `promouvoir-dev` (runner protégé) : MR ouverte dans `mediagenda/deploiement`, image par digest | < 1 min |
| 4 | Pipeline de MR de `mediagenda/deploiement` : `kustomize build`, `kubeconform`, `cosign verify` + `verify-attestation` | 1 à 2 min |
| 5 | Fusion par Julien (Maintainer) ; `deployer-dev` par l'agent | 1 à 2 min |
| 6 | `kubectl -n mediagenda-dev get deploy mediagenda -o jsonpath='{..image}'` : le digest promu | — |

Le délai « fusion de la promotion → en dev » est celui que le M20 remplacera par Argo CD : note-le dans `etat-ci-v1.md`.

*Démonstration de Sophie — secrets et signature*

| Essai | Attendu |
|---|---|
| Pipeline d'une branche non protégée qui affiche la **présence** (jamais la valeur) de `COSIGN_PRIVATE_KEY`, `DEPLOIEMENT_TOKEN`, `HARBOR_ROBOT_TOKEN` (`test -n "${VAR:-}" && echo présente \|\| echo absente`) et cherche `/run/secrets/medisphere/cosign` | `absente` pour les trois (la première n'existe plus, les deux autres sont protégées) ; pas de clé montée (runner `k8s-par1`) |
| Job étiqueté `protege` sur cette branche | reste en attente (runner `ref_protected`) |
| MR dans `mediagenda/deploiement` qui pointe vers une image non signée (par exemple une étiquette `mr-…` jamais poussée, ou une image de `dockerhub/…`) | la porte de vérification échoue, la fusion est bloquée (« pipelines must succeed ») |
| `kubectl get pods -A -o json \| jq '[.items[] \| select(any(.spec.containers[]; .securityContext.privileged == true))] \| map(.metadata.namespace) \| unique'` | aucun espace de CI dans la liste |

*Démonstration de Nadia — runner en pause* : Nadia suspend `k8s-par1` (`PUT /runners/:id paused=true`) ; tu lances un pipeline ; méthode de RB-190 : job `pending` → `gl runners/all` → `paused: true` ; temps jusqu'au diagnostic juste noté ; le canari planifié (ou l'alerte du M21 quand elle existera) aurait montré l'arrêt au plus tard le lendemain matin : c'est la limite à écrire dans `etat-ci-v1.md`.

*Grille de revue* (ce que chaque relecteur regarde)

| Relecteur | Points | Attendu |
|---|---|---|
| Karim | `plateforme/ci-templates` | composants avec `spec:inputs` typés et documentés (README par composant), versions publiées par release, tests du composant dans son propre pipeline, aucune étiquette déplacée, anciens gabarits gelés |
| Karim | `plateforme/k8s` | runners, `buildkitd`, agent sous Helmfile ; `helmfile diff` vide ; Jenkins et SonarQube retirés du code (pas seulement du cluster) ; politiques d'admission et réseau dans le code |
| Sophie | secrets | plus aucune variable `COSIGN_*` (exception de M19-E24 close) ; aucune variable sensible non protégée ; jetons inventoriés avec expiration ; rotation documentée (RB-198) ; « masquée et cachée » pour ce qui n'a jamais besoin d'être relu |
| Sophie | chaîne d'approvisionnement | signature par le seul runner protégé, provenance et SBOM présents, porte de vérification bloquante, aucune image hors de Harbor, aucun conteneur privilégié |
| Julien | expérience des équipes | adoption en une MR, documentation `normes-pipeline.md` suffisante, délai de bout en bout mesuré, erreurs de pipeline compréhensibles |
| Nadia | exploitation | runbooks RB-190 à RB-198 (RB-194 à RB-198 testés pendant le palier 4), post-mortem INC-4643, canari et ce qui manque encore en supervision (M21) |
| Claire | décisions et limites | ADR-0190 (Jenkins et SonarQube non retenus, Kaniko archivé, BuildKit partagé, runner protégé), ce qui n'est pas redondant, ce que le M20 doit faire |

**Explications** : la livraison `ci-v1` ne se mesure pas au nombre de fonctions ajoutées mais à trois propriétés : **adoptée** (toutes les équipes sur le même socle, versionné), **sûre** (les secrets de production ne sortent que vers les références protégées, chaque image en production est prouvablement issue de la CI), **exploitable** (pannes connues, runbooks, canari, dérive détectée). Le contrôle global vérifie la première et une partie de la deuxième ; les démonstrations vérifient le reste.

**Alternatives** : garder SonarQube Community Build pour la seule branche principale (analyse « de tendance ») est défendable si l'équipe accepte d'exploiter une base et une instance de plus pour une valeur limitée ; l'ADR-0190 doit alors le dire et le mini-projet garder l'espace. Garder Jenkins n'a de sens que pour un usage que GitLab CI ne couvre pas (aucun dans le lab).

**Pièges classiques**
- Retirer Jenkins ou SonarQube du cluster sans retirer le code : le prochain `helmfile apply` les réinstalle.
- Oublier les variables de **groupe** et les enregistrements DNS.
- Épingler les composants à `~latest` « pour ne plus avoir à monter de version » (M19-E45, question 5).
- Poser l'étiquette `ci-v1` avant que les pipelines de `main` soient verts.
- Supprimer le témoin avant d'avoir fermé toutes les pannes (l'annulation en a besoin).

**En production chez MédiSphère** : tableau de bord de la chaîne et alertes (M21 : âge des jobs en attente, échecs système des jobs, expiration des jetons, dernier canari) ; revue trimestrielle des versions de composants consommées ; procédure d'arrivée d'une nouvelle équipe (une MR, un projet témoin, une heure).
