# Module 19 — Intégration continue : palier 5 — Mini-projet

Le module a monté une chaîne de livraison complète, l'a cassée et réparée : runners dans `k8s-par1`, constructions sans privilège, composants CI/CD, analyses de sécurité, signature et provenance, promotion par MR, déploiement en dev par l'agent. Jenkins et SonarQube ont été essayés, comparés, et la décision est écrite. Il reste à **livrer** la chaîne comme une brique de la plateforme : chaque équipe applicative sur le pipeline standard, plus rien de provisoire, la documentation qui dit au module 20 ce qu'il trouve. C'est ce que Claire Morel présentera au comité de direction comme « la chaîne de CI de MédiSphère v1 ».

---

### M19-E46 — Mini-projet : la chaîne de CI de MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-2046** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel*
> Recette de la chaîne de CI dans deux semaines. Je veux que **tous** les projets applicatifs passent par le pipeline standard, que plus rien de provisoire ne traîne (Jenkins, SonarQube, pannes ouvertes, variables orphelines), et que le module GitOps puisse démarrer sur une base saine.
> Pendant la revue : Julien poussera une correction sur `mediagenda/api` et suivra sa version jusqu'en dev, chronomètre en main ; Sophie vérifiera qu'aucun secret ne peut sortir d'un pipeline de branche et qu'une image non signée est refusée ; Karim fera la revue de `plateforme/ci-templates` et de `plateforme/k8s` ; Nadia mettra en pause le runner `k8s-par1` pendant ta présentation et regardera ce que tu vois. Format habituel : 10 minutes de présentation, les démonstrations, nos questions.

**Objectifs pédagogiques**
- Consolider la chaîne du module en une brique cohérente, pilotée par le code, sans dette provisoire.
- Prouver ce qui a été construit : délai de bout en bout d'un changement, cloisonnement des secrets, refus d'une image non signée, détection d'une panne de runner.
- Livrer l'état `ci-v1` : documentation, décisions, runbooks, étiquette de version, et ce que le module 20 devra traiter.

**Prérequis** : M19-E01 à M19-E45 (au minimum tous les `LAB`, `LIBRE`, `BF` et le `CHRONO`).
**Durée indicative** : 8 à 12 h, plus 30 min de revue.

**Contexte technique**
- Projets applicatifs concernés : `mediagenda/api`, `mediagenda/chart`, `mediagenda/deploiement`, `medidoc/medidoc` (et `medidoc/deploiement`, M19-E33), `mediagenda/annuaire` (M19-E34).
- Composants de `plateforme/ci-templates` en version 2 ou plus ; les anciens gabarits v1.x restent publiés mais ne sont plus consommés par les projets applicatifs.
- Runners : `k8s-par1`, `k8s-par1-protege`, et `runner02` gardé pour l'étiquette `docker` (ses usages restants sont listés et justifiés).
- Le projet témoin `formation/ci-pannes` du palier 4 peut rester ou être supprimé : la décision est écrite dans l'état livré.
- Le contrôle global `lab/bin/check 19 46` rejoue les contrôles clés des paliers précédents (`19 04`, `19 08`, `19 10`, `19 17`, `19 18`, `19 24`, `19 29`), puis vérifie l'adoption des composants, les runners, le retrait de Jenkins et de SonarQube, la documentation et l'étiquette. Il prend quelques minutes.

**État livré `ci-v1`** — ce que le module 20 et les suivants trouveront en entrant.

| Élément | État attendu à la livraison |
|---|---|
| GitLab | CE 19.5.x, courriels vers Mailpit, KAS activé, aucune migration d'arrière-plan en attente |
| Runners | `k8s-par1` (étiquettes `k8s`, `kubernetes`, jobs dans `ci-jobs`, gestionnaire en deux réplicas avec PDB) et `k8s-par1-protege` (références protégées, étiquette `protege`, jobs dans `ci-jobs-protege`) en ligne, chart 0.94.x sous Helmfile ; `runner02` en ligne (étiquette `docker`) |
| Constructions et cache | `buildkitd` rootless partagé (TLS mutuel, politique réseau, cache dans `plateforme/cache-buildkit`) ; cache S3 `ci-cache` sur `s3-01` ; aucun conteneur privilégié dans `ci-jobs`, `ci-jobs-protege`, `buildkit` |
| Composants | `plateforme/ci-templates` publié en v2.x au catalogue : `construction-image`, `qualite`, `securite`, `deploiement`, `promotion` |
| Projets applicatifs | les cinq projets n'incluent **que** des composants ≥ 2.0 ; derniers pipelines de `main` verts |
| Chaîne d'approvisionnement | images `vX.Y.Z` signées par le runner protégé, SBOM et provenance attachés ; porte de vérification dans les MR de `mediagenda/deploiement` |
| Promotion et dev | MR de promotion par `ci-promotion` (overlay `dev` par digest) ; `deployer-dev` par l'agent `k8s-par1` (accès limités à `mediagenda-dev` et `wb-essais`, retirés au M20) |
| Retraits | Jenkins et SonarQube : releases, espaces, base CNPG `sonarqube-db`, enregistrements DNS, Secrets de Vault, variables de CI `SONAR_*` et `JENKINS_*`, jetons ; aucune panne `M19` active |
| Documentation | ADR-0190 ; RB-190 et RB-194 à RB-198 ; état livré `docs/livraison/ci/etat-ci-v1.md` (ce que trouve le M20, ce qui n'est pas redondant) ; journal et post-mortem INC-4643 ; matrice des flux à jour |
| Livraison | étiquette **`ci-v1`** sur `plateforme/medisphere` |

**Travail demandé**
1. **Rien de provisoire.** Aucune panne du palier 4 ouverte ; Jenkins et SonarQube retirés **par le code** (et tout ce qui leur était attaché, jusqu'aux enregistrements DNS et aux secrets) ; variables, jetons et branches d'essai des paliers supprimés ou justifiés ; décision écrite sur le témoin `formation/ci-pannes` et sur les usages restants de `runner02`.
2. **Le pipeline standard partout.** Les cinq projets applicatifs n'incluent que des composants ≥ 2.0 (plus aucun `include` de fichiers de gabarits v1.x) ; leurs pipelines de `main` et de MR sont verts ; une équipe nouvelle peut adopter le pipeline standard en suivant `normes-pipeline.md` sans aide.
3. **Runners et capacité.** Les deux runners Kubernetes et `runner02` sont en ligne, leur configuration est entièrement dans le code (values, Vault, script de création des runners), `helmfile diff` est vide ; les limites et priorités des jobs sont celles du M19-E27.
4. **Sécurité de la chaîne.** Aucun secret sensible accessible à un pipeline de branche non protégée ; jetons longue durée inventoriés avec expiration et procédure de rotation ; signature et provenance par le runner protégé ; une image non signée est refusée par la porte de vérification.
5. **Bout en bout.** Un changement de `mediagenda/api` va de la MR jusqu'à `mediagenda-dev` sans intervention manuelle autre que les fusions prévues ; le délai est mesuré.
6. **Documentation.** ADR-0190 relue ; runbooks RB-190 et RB-194 à RB-198 ; `etat-ci-v1.md` (ce que trouve le M20, ce qui n'est pas redondant, ce qui reste à faire) ; matrice des flux à jour (flux ajoutés par le module, flux de Jenkins et de SonarQube retirés).
7. **Livraison.** Tout est fusionné, les pipelines de `main` sont verts, l'étiquette `ci-v1` est posée sur `plateforme/medisphere`.
8. **La revue.** Présentation de 10 minutes (architecture, choix, limites), puis les démonstrations de Julien, Sophie et Nadia.

**Contraintes**
- Tout ce qui est créé ou retiré l'est par le code (OpenTofu, Ansible, Helmfile de `plateforme/k8s`, composants) ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.
- Aucun secret dans un dépôt, un journal de CI ou la documentation : des **emplacements**, jamais des valeurs.
- Jamais de conteneur privilégié ; jamais d'image hors de Harbor.
- Les composants publiés ne sont jamais modifiés en place : toute correction est une nouvelle version.

**Critères de réussite**
- [ ] `lab/bin/check 19 46` est entièrement vert.
- [ ] Démonstration de Julien : le délai entre la fusion de sa MR sur `mediagenda/api` (étiquette `vX.Y.Z` posée par semantic-release) et la nouvelle version en `mediagenda-dev` est mesuré et expliqué étape par étape.
- [ ] Démonstration de Sophie : un pipeline de branche non protégée ne voit ni la clé Cosign, ni `DEPLOIEMENT_TOKEN`, ni les identifiants de poussée ; une MR de promotion vers une image non signée est bloquée.
- [ ] Démonstration de Nadia : pendant la pause du runner, tu identifies la cause en moins de 5 minutes par la méthode de RB-190, et le canari ou une alerte le montre.
- [ ] La revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 19 46`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 19 46` dès le début : la liste des points rouges est ton plan de travail. Les contrôles détaillés (`lab/bin/check 19 XX`) donnent le détail par brique ; `lab/bin/check 19 43` rejoue d'un coup toutes les vérifications du palier 4.
</details>

<details><summary>Indice 2</summary>

Fais le retrait de Jenkins et de SonarQube **après** avoir figé les preuves dont l'ADR-0190 a besoin (mesures, captures, comparatif) : une fois l'outil retiré, tu ne pourras plus les refaire. Cherche toutes les références avant de retirer : variables de projet **et** de groupe, composants, documentation, matrice des flux, DNS.
</details>

<details><summary>Indice 3</summary>

Pour la démonstration de Julien, découpe le délai : pipeline de l'étiquette (construction, analyses, signature), ouverture de la MR de promotion, porte de vérification, fusion, déploiement en dev. Le chiffre qui compte est le délai « fusion de la promotion → en dev » : c'est lui que le M20 remplacera par une synchronisation d'Argo CD.
</details>

**Pour aller plus loin** (facultatif) : un tableau de bord texte, depuis `adm01`, qui résume l'état de la chaîne (runners, âge du plus vieux job en attente, dernier canari, dernière promotion, expiration des jetons de CI) : il servira de cahier des charges aux tableaux de bord du module 21.
