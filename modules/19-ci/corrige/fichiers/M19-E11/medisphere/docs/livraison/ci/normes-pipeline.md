# Normes des pipelines MédiSphère

> Version 1 — M19-E11 (DEV-2011), complétée en M19-E15 (exceptions de sécurité) et M19-E16 (jobs
> propres à un projet). Propriétaire : équipe Plateforme. Relue par Sophie Laurent (RSSI) et Julien
> Petit (équipes de développement). Toute exception passe par une MR sur ce fichier.

## 1. Obligatoire

| # | Règle | Pourquoi | Comment le vérifier |
|---|---|---|---|
| O1 | Le `.gitlab-ci.yml` n'inclut que des **composants** de `plateforme/ci-templates`, à une version **complète épinglée** (`@vX.Y.Z`) | Pipeline reproductible, montée par MR (Renovate) | `lab/bin/check 19 11`, contrôle planifié (E32) |
| O2 | Le projet définit son `workflow:` : pipelines de MR, de la branche par défaut et des étiquettes `vX.Y.Z` ; **jamais** de doublon branche + MR | Coût, résultats contradictoires | Liste des pipelines d'une MR |
| O3 | Jobs sur les runners du cluster (`k8s`, `protege` à partir de E24) ; `docker` (`runner02`) seulement par exception | Capacité, cloisonnement | `GET /projects/:id/jobs` (champ `runner`) |
| O4 | Images : Harbor uniquement, **étiquette et empreinte** ; jamais `latest` | Chaîne d'approvisionnement, reproductibilité | Revue de MR, Renovate |
| O5 | Aucun conteneur privilégié, aucun Docker-in-Docker ; les images se construisent par le composant `construction-image` (buildkitd) | ADR-0120, ADR-0190 | Pod Security de `ci-jobs` (E24) |
| O6 | Les images publiées passent **avant publication** par `securite:trivy` (critique avec correctif = échec) et sont **signées** ; on travaille ensuite sur l'**empreinte** (`IMAGE_REF`), jamais sur l'étiquette | Ce qui est déployé est ce qui a été analysé | `cosign verify`, Harbor |
| O7 | Les pipelines de MR ne publient rien, ne signent rien et ne reçoivent **aucune variable protégée** | Une branche non relue ne touche pas aux secrets | Variables protégées, règles des composants |
| O8 | Analyses du code et des secrets (`securite:semgrep`, `securite:gitleaks`) bloquantes (E15) | HDS, ISO 27001 | Rapport SAST du pipeline |
| O9 | Tests avec rapport JUnit ; couverture publiée (E13) ; « Pipelines must succeed » activé | Une MR rouge ne se fusionne pas | Réglages du projet |
| O10 | Artefacts avec `expire_in` ; aucun secret dans un artefact ni dans un journal (`set -x` interdit dans un job qui manipule un secret) | Fuites, stockage | Revue de MR |

## 2. Recommandé

- Pipeline de MR **sous 10 minutes** (E23 : mesures et leviers) ; `interruptible: true` et
  `workflow:auto_cancel:on_new_commit: interruptible`.
- Un job écrit à la main dans un projet (hors composants) n'est accepté que s'il est **propre au
  projet**, porte un commentaire qui dit pourquoi, et n'a pas d'équivalent dans un composant
  (exemple : le job `sonarqube` de `mediagenda/api` pendant l'essai de E16). S'il se répète dans deux
  projets, il devient un composant.
- Clés de cache calculées sur le fichier de verrou (`uv.lock`, `go.sum`) ; politique `pull` hors de
  la branche par défaut.

## 3. Pipeline standard d'un projet Python

```yaml
include:
  - component: $CI_SERVER_FQDN/plateforme/ci-templates/qualite@v2.0.0
  - component: $CI_SERVER_FQDN/plateforme/ci-templates/construction-image@v2.0.0
    inputs:
      image_nom: <projet-harbor>/<dépôt>
  - component: $CI_SERVER_FQDN/plateforme/ci-templates/securite@v2.0.0
  - component: $CI_SERVER_FQDN/plateforme/ci-templates/release@v2.0.0
```

Avec le `workflow:` et les `stages:` de `mediagenda/api` (modèle : son `.gitlab-ci.yml`). Un projet
Go ajoute `inputs: { langage: go }` au composant `qualite`.

## 4. Exceptions

Une exception est **écrite, justifiée, datée et revue** :

| Type | Où | Qui valide | Durée |
|---|---|---|---|
| Écart à une règle de ce document | ligne dans le tableau ci-dessous (MR) | Karim Benali (Plateforme) | 3 mois max., renouvelable |
| Résultat Semgrep accepté | commentaire `# nosemgrep: <id-de-règle> — <raison> (<ticket>)` sur la ligne | relecteur de la MR + Sophie Laurent si règle `ERROR` | jusqu'à correction |
| Vulnérabilité acceptée | `.trivyignore` : identifiant + commentaire (raison, ticket, date d'échéance) | Sophie Laurent | 30 jours, renouvelable |
| Faux positif Gitleaks | `.gitleaksignore` (empreinte du résultat) + commentaire dans la MR | Sophie Laurent | définitive |

Revue mensuelle des exceptions par l'équipe Plateforme : `git grep -n "nosemgrep"` sur les projets
des groupes applicatifs, contenu des `.trivyignore` et `.gitleaksignore`, tableau ci-dessous.

| Projet | Règle | Raison | Validé par | Échéance |
|---|---|---|---|---|
| tous les projets encore en v1 | O1, O3 | migration vers les composants en cours (E33, E34, mini-projet) | K. Benali | fin du module 19 |
