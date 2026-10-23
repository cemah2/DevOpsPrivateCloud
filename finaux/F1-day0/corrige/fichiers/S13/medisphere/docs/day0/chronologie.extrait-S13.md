## Phase 4 — S13 : première livraison (DEV-3113)

> Extrait du corrigé à ajouter à `chronologie.md`. Heures et durées : les tiennes.

| Heure | Étape | Durée | Remarque |
|---|---|---|---|
| <HH:MM> | Branche `feat/dev-3113` de `mediagenda/api`, correctif de `ressources/S13/` appliqué, tests locaux | | `uv run pytest`, `ruff` |
| <HH:MM> | Pipeline de la MR | | <ex. bloqué : runner `k8s-par1` sans jeton → corrigé en S09 ? sinon cause et MR> |
| <HH:MM> | MR approuvée (Julien), fusion ; semantic-release publie `v<X.Y.Z>` | | version **mineure** (`feat`) |
| <HH:MM> | Pipeline de l'étiquette : construction BuildKit, analyse, SBOM, signature par `transit/cosign-medisphere` (runner protégé), poussée Harbor | | condensé `sha256:<…>` |
| <HH:MM> | MR de promotion `dev` ouverte par `ci-promotion`, fusionnée ; dev et recette synchronisées | | |
| <HH:MM> | MR de promotion `prod` (condensé), approuvée par Julien ; synchronisation manuelle de `mediagenda-prod` | | |
| <HH:MM> | Canary : <ex. 20 % → analyse → 50 % → analyse → 100 %> | | AnalysisRun `<nom>` Successful |
| <HH:MM> | SLO observé une heure : latence p95 <N> ms (< 250), disponibilité <N> % | | |
| | **Délai de bout en bout** (fusion → 100 %) | <durée> | comparé à avant le Day 0 : <durée> |
