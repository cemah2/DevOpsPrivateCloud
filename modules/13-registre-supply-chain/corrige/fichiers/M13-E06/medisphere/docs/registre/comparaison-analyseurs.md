# Comparaison des analyseurs et des SBOM

> SEC-1406 (M13-E06). Images analysées : dernière version de `medisphere/mediagenda-api`, `medidoc`, `medinotif`, `legacy-rdv`, **par empreinte**, le <DATE>. Outils : Trivy 0.75.0 (base du <DATE>), Syft 1.54.1, Grype 0.120.1 (base v6 du <DATE>), SBOM de Harbor (Trivy 0.74 embarqué).

## Méthode

1. Empreinte résolue une fois (`skopeo inspect`), toutes les analyses portent sur `…@sha256:…`.
2. Syft : une analyse, deux sorties (SPDX 2.3 JSON, CycloneDX 1.6 JSON) — `outils/sbom-images.sh`.
3. Grype sur la **SBOM SPDX** (`grype sbom:…`), Trivy sur l'**image** (`trivy image`) et sur la SBOM (`trivy sbom`).
4. Comparaison sur les CVE critiques et élevées **corrigeables**, et sur le nombre de composants.

## Résultats (à remplir avec tes chiffres)

| Image | Composants Syft | Composants Trivy (SPDX) | Crit./élevées corrigeables Trivy | Crit./élevées corrigeables Grype | Communes |
|---|---|---|---|---|---|
| mediagenda-api | <N> | <N> | <N> | <N> | <N> |
| medidoc | <N> | <N> | <N> | <N> | <N> |
| medinotif | <N> | <N> | <N> | <N> | <N> |
| legacy-rdv | <N> | <N> | <N> | <N> | <N> |

## Écarts expliqués

1. **Ce qui est vu.** Syft catalogue aussi des fichiers et des binaires isolés (binaire `uv` copié dans l'image MédiAgenda, informations de construction Go de MédiDoc) que Trivy rattache autrement ou ignore ; Trivy rattache les paquets Python à l'environnement virtuel `/app/.venv`. Les totaux de composants diffèrent donc sans qu'aucun ne « rate » quelque chose d'essentiel.
2. **Les bases.** Trivy utilise les avis de la distribution (Debian Security Tracker) en priorité pour les paquets Debian et GitHub Advisories pour l'écosystème Python et Go ; Grype croise NVD, GitHub et les avis de distribution avec ses propres règles. Une CVE marquée « *no-dsa* » ou « *not affected* » par Debian disparaît chez l'un, reste chez l'autre.
3. **La notion de « corrigé ».** « Corrigé dans Debian » (nouvelle révision du paquet dans trixie) n'est pas « corrigé en amont » : `--ignore-unfixed` (Trivy) et `--only-fixed` (Grype) ne retiennent pas les mêmes lignes.
4. **La correspondance.** Grype peut faire correspondre par CPE quand le `purl` ne suffit pas (faux positifs possibles sur des noms génériques) ; Trivy correspond par écosystème et nom de paquet.
5. **La sévérité.** Sévérité de la distribution contre score CVSS de la NVD : la même CVE peut être « élevée » chez l'un et « moyenne » chez l'autre.

## Décision

- **Analyseur bloquant** : Trivy (chaîne de livraison, seuil « critique corrigeable », `docs/registre/analyse.md`) ; c'est aussi celui de Harbor, donc une seule vérité à la poussée.
- **Second avis** : Grype sur la SBOM conservée, lors de la revue hebdomadaire et en réponse à une alerte (M13-E18) ; un écart « critique » entre les deux se traite à la main.
- **SBOM de référence** : **SPDX 2.3 JSON produite par Syft dans la CI**, attestée et signée (M13-E08, M13-E09), conservée **avec l'image** dans Harbor (référent) et comme artefact du pipeline. CycloneDX produite en même temps pour les outils qui la préfèrent (Dependency-Track, plus tard), non attestée.
- **SBOM de Harbor** : générée à la poussée (`medisphere`, `plateforme`, `bibliotheque`), sert de contrôle croisé. On n'en fait pas la référence : elle n'est pas signée par la chaîne et son générateur change avec la version de Harbor.
