# Composant `deploiement`

Validation d'un dépôt de déploiement Kustomize (base + `overlays/<environnement>/`).

```yaml
include:
  - component: $CI_SERVER_FQDN/plateforme/ci-templates/deploiement@v2.0.0
    inputs:
      overlays: [dev, recette, prod]
```

Un job `deploiement:valider: [<overlay>]` par overlay : `kustomize build`, puis `kubeconform
-strict` (schémas Kubernetes 1.36 et schémas des CRD du catalogue datreeio : Cilium, Gateway API,
CloudNativePG). Les rendus sont gardés une semaine en artefact : on les relit dans la MR.
