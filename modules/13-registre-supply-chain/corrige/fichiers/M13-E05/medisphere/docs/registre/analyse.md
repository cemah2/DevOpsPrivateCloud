# Analyse de vulnérabilités des images

> Outils : Trivy 0.75 (CLI, `adm01` et CI), Trivy 0.74 intégré à Harbor ; Grype 0.120 en second avis (M13-E06). Mis en place : M13-E05 (SEC-1405).

## Seuil de blocage

| Situation | Décision |
|---|---|
| Vulnérabilité **critique** avec version corrigée disponible | **bloquant** : la chaîne de livraison (M13-E09) s'arrête avant publication |
| Critique sans correctif, élevée avec ou sans correctif | non bloquant ; visible dans Harbor et dans le rapport du pipeline ; revue hebdomadaire |
| Présente au catalogue KEV de la CISA | traitée comme critique corrigeable, même si le score CVSS est plus bas (décision RSSI) |

Commande de référence (code retour 1 = bloquer) :

```
trivy image --severity CRITICAL --ignore-unfixed --exit-code 1 <image>@<empreinte>
```

## Exceptions

- Fichier `.trivyignore` à la racine du projet, relu en MR par un membre de l'équipe Plateforme.
- Chaque exception : identifiant précédé d'un commentaire `# <date de revue> | <auteur> | <justification> | <ticket>`.
- Revue mensuelle des exceptions ; une date dépassée = exception retirée.
- Jamais d'exception sur un paquet **utilisé** par l'application tant qu'un correctif existe.

## Où lire les résultats

- Harbor : onglet « Vulnerabilities » de chaque artefact ; analyse à la poussée sur `medisphere`, `plateforme`, `bibliotheque`, `charts` ; analyse de tout le registre chaque nuit (2 h 15).
- CI : artefact `trivy.json` de chaque pipeline de la chaîne de livraison.
- `adm01` : `trivy image` avec `~/.config/workbook/harbor-moi.env` (variables `TRIVY_USERNAME`, `TRIVY_PASSWORD`).

## Base de vulnérabilités

Trivy télécharge sa base (`mirror.gcr.io/aquasec/trivy-db:2`, repli `ghcr.io/aquasecurity/trivy-db:2`) au plus une fois toutes les 12 h dans `~/.cache/trivy`. Sans Internet : `--db-repository` vers une copie interne (cache `ghcr` de Harbor) ou `--skip-db-update` avec une base récente copiée.
