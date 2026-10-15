# Renovate : mises à jour automatiques des dépendances

> PLAT-1411 (M13-E11). Renovate 44 auto-hébergé, projet `plateforme/renovate`, chaque nuit à 4 h sur `runner02`.

## Ce que fait Renovate

Chaque nuit, pour chaque projet traité (`mediagenda/api`, `medidoc/medidoc`, `medinotif/worker`, `legacy/legacy-rdv`, `plateforme/ci-templates`) qui contient un `renovate.json` étendant `local>plateforme/renovate-config` :

- images des `Dockerfile`, `compose.yaml` et `.gitlab-ci.yml` : nouvelle étiquette ou nouvelle empreinte (les images restent épinglées `étiquette@sha256:…`) ; pour les caches de Harbor, Renovate consulte l'amont (`registryAliases`) ;
- dépendances Python (`pyproject.toml` + `uv.lock`) et Go (`go.mod` + `go.sum`, `go mod tidy`) ;
- gabarits inclus (`include: ref:`) quand ils sont épinglés sur une étiquette.

Chaque mise à jour = une MR de `renovate-bot`, qui lance la chaîne de livraison en mode MR (construction, analyse Trivy, SBOM).

## Ce qui fusionne seul

| Mise à jour | Fusion |
|---|---|
| correctif (*patch*), publié depuis **3 jours** au moins, pipeline vert | automatique (« fusionner quand le pipeline réussit ») |
| mineure, empreinte, épinglage | MR relue par l'équipe du projet |
| majeure | MR relue, étiquette `majeure` |
| outils de sécurité (Trivy, Cosign, Syft, Grype, image outillée) | relecture de Sophie Laurent, jamais automatique |

Le délai de 3 jours (`minimumReleaseAge`) laisse le temps à une version piégée d'être découverte et retirée (Trivy 0.69.4, mars 2026 : retirée en quelques heures).

## Exclure une dépendance

Dans le `renovate.json` du projet, une règle commentée (ticket, date de revue) :

```json
{ "packageRules": [ { "matchPackageNames": ["<nom>"], "enabled": false, "description": "<ticket> — revue le <date>" } ] }
```

## Jeton

`renovate-bot` (Developer sur les projets traités, non administrateur), jeton personnel portée `api`, **180 jours** ; variable `RENOVATE_TOKEN` (protégée, masquée) de `plateforme/renovate`. Renouvellement : `outils/creer-renovate-bot.sh` à J-15 (date au registre des secrets). Harbor : robot `robot$renovate` (tirage de `bibliotheque` et `plateforme`), variables `HARBOR_RENOVATE_USER` / `HARBOR_RENOVATE_TOKEN`.
