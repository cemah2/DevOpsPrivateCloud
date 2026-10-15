# Image `plateforme/outils-supply-chain`

Construite depuis ce dossier par le pipeline de `plateforme/ci-templates`. Avant de construire,
le job copie dans le contexte : `docs/registre/cosign.pub` et `docs/registre/signing-config.json`
(dépôt `plateforme/medisphere`, à l'étiquette publiée) et la racine MédiSphère
(`/usr/local/share/ca-certificates/medisphere-root-ca.crt`, variable de CI `MEDISPHERE_ROOT_CA`).
Monter un outil : changer `*_VERSION` et `*_SHA256` (après `cosign verify-blob` manuel), publier une
nouvelle version de l'image, puis mettre à jour `SC_OUTILS_IMAGE` (étiquette + empreinte) dans
`templates/supply-chain.yml` (et `MS_IMAGE_OUTILS` dans `templates/verification.yml`) — Renovate le propose (M13-E11).
