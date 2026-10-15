# Qualité des images : Hadolint et Dive

> M12-E16 (SEC-1316). S'applique à tout Dockerfile des projets applicatifs et de la plateforme.

## Hadolint 2.15

- Fichier `.hadolint.yaml` de MédiSphère à la racine de chaque projet (modèle : `plateforme/ci-templates`, `exemples/.hadolint.yaml`) : seuil d'échec `warning`, registres autorisés, étiquettes OCI obligatoires, règles relevées en erreur (`DL3002` dernier `USER` root, `DL3007` `latest`, `DL3020` `ADD`, `DL3025` forme exec, `DL4006` `pipefail`…).
- Une dérogation se fait **dans le Dockerfile**, sur la ligne concernée, avec sa raison : `# hadolint ignore=DL3008  (raison : …)`. Jamais dans `ignored:` du fichier de configuration.
- En CI : job `hadolint` (gabarit `templates/image.yml`, M12-E21), rapport Code Quality dans la MR.
- Ce que Hadolint ne voit pas (revue humaine obligatoire) : secrets qui ne ressemblent pas à des secrets, `COPY . .` sans `.dockerignore`, permissions (`chmod 777`), image de construction livrée en production, port déclaré faux, image de base d'un registre non maîtrisé déguisée par une variable.

## Dive 0.13

`CI=true dive <image>` (ou `dive --ci --ci-config .dive-ci <image>`) avec le fichier `.dive-ci` du projet :

| Règle | Seuil MédiSphère | Pourquoi |
|---|---|---|
| `lowestEfficiency` | 0,95 | moins de 5 % d'octets écrasés ou supprimés par des couches suivantes |
| `highestWastedBytes` | 20 Mo | un cache APT ou un fichier temporaire oublié se voit tout de suite |
| `highestUserWastedPercent` | 0,20 | rapporté à ce que NOUS ajoutons ; la base Python gaspille déjà ≈ 6 Mo (fichiers dpkg réécrits) |

Mesures de référence (2026-10, `ctr01`) : à relever et reporter ici par l'équipe à chaque nouvelle version d'image.

| Image | Taille (contenu) | Efficacité | Octets perdus | Verdict |
|---|---|---|---|---|
| `mediagenda-api:0.1.0` (E05) | <À-RELEVER> | <À-RELEVER> | <À-RELEVER> | <À-RELEVER> |
| `mediagenda-api:0.2.0` (E11) | <À-RELEVER> | <À-RELEVER> | <À-RELEVER> | <À-RELEVER> |
| `medidoc:1.0.0` (E10) | <À-RELEVER> | <À-RELEVER> | <À-RELEVER> | <À-RELEVER> |
