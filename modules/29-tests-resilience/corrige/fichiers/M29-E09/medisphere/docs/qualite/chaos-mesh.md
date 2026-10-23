# Chaos Mesh — fiche du service

> `plateforme/medisphere` — `docs/qualite/chaos-mesh.md` (M29-E09, PLAT-3009). Propriétaire : Karim Benali.

| Élément | Valeur |
|---|---|
| Version | Chaos Mesh 2.8.6 (chart `chaos-mesh` 2.8.6, miroir Harbor `charts/`) |
| Déploiement | Application Argo CD `chaos-mesh` (projet `plateforme`), valeurs `plateforme/gitops/valeurs/chaos-mesh/values.yaml` |
| Espaces | `chaos-mesh` (contrôleur, démons ; PSA `privileged`, EXC-K-005), `chaos-experiences` (les expériences ; `restricted`, quota d'objets) |
| Runtime | containerd, `/run/containerd/containerd.sock` |
| Espaces visables | **`mediagenda-recette`, `medinotif-recette`, `wb-essais`** (annotation `chaos-mesh.org/inject=enabled`) — jamais `*-prod`, `messagerie` ni un espace de plateforme |
| Garde-fous | (1) `controllerManager.enableFilterNamespace: true` ; (2) pas de tableau de bord, webhook `validate-auth` actif (`dashboard.securityMode: true`) ; (3) VAP `medisphere-chaos-espaces` (liste fermée d'espaces annotables, objets seulement dans `chaos-experiences`, cibles dans la liste) ; (4) RBAC : création par `oidc:plateforme-admins` seulement ; (5) toute expérience a une `duration` (règle `rego/kubernetes/chaos.rego`) ; (6) quota d'objets dans `chaos-experiences` |
| Qui | crée : `oidc:plateforme-admins` ; lit : `oidc:plateforme`, `oidc:mediagenda` |
| Arrêt d'urgence | RB-292 |
| Exceptions | EXC-K-005 (PSA), EXC-K-006 (hostPath), EXC-D-002 (Falco) au registre `docs/securite/durcissement/exceptions.md` |
| Expériences | versionnées dans `plateforme/resilience/chaos/`, appliquées depuis `adm01` sous l'identité OIDC (exception à « rien à la main hors Argo CD », ADR-0290) |
