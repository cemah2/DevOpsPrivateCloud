# ${{ values.nom }}-deploiement

Déploiement Kustomize de `${{ values.locataire }}/${{ values.nom }}` (modèle « nouveau service » du portail). `base/` : objets communs ; `overlays/dev/` : environnement `dev`, espace `${{ values.nom }}-dev`, livré par l'Application Argo CD `${{ values.nom }}-dev`. L'image est posée par la MR de promotion de la CI du code (par empreinte).
