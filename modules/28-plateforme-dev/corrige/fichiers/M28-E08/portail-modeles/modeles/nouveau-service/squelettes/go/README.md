# ${{ values.nom }}

${{ values.description }}

Créé par le modèle « nouveau service » du portail (équipe `${{ values.equipe }}`, locataire `${{ values.locataire }}`).

- Code : ce projet ; image `registry.par1.medisphere.internal/medisphere/${{ values.nom }}`, construite, analysée et signée par la CI.
- Déploiement : projet `${{ values.locataire }}/${{ values.nom }}-deploiement` (Kustomize, overlay `dev`), livré par Argo CD dans l'espace `${{ values.nom }}-dev` ; chaque pipeline de `main` ouvre la MR de promotion vers `dev`.
- Points d'accès : `GET /sante` (vivacité), `GET /pret` (disponibilité), port 8080.
- Guide : `docs/plateforme-dev/guide-accueil-equipe.md` de `plateforme/medisphere`.
