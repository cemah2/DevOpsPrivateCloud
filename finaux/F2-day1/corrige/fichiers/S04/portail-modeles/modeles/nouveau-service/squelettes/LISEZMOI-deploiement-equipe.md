# Squelette « deploiement-equipe » (modèle nouveau-service v2, F2-S04) — à construire dans squelettes/deploiement-equipe/

Le dossier `squelettes/deploiement-equipe/` du modèle contient la **même arborescence** que `medivisio/consultation-deploiement`
(corrigé F2-S04, `corrige/fichiers/S04/medivisio-consultation-deploiement/`), avec ces remplacements :

| Dans le dépôt de référence | Dans le squelette |
|---|---|
| `consultation` (noms d'objets, `app.kubernetes.io/name`, `instance`) | `${{ values.nom }}` |
| `medivisio-consultation` (`backstage.io/kubernetes-id`, image `medisphere/…`) | `${{ values.composant }}` |
| `medivisio` (`part-of`, `equipe`, espaces `medivisio-<env>`, chemins `kv/medivisio/<env>/…`) | `${{ values.equipe }}` |
| `consultation-dev.apps…`, `consultation-recette.apps…`, `consultation.apps…` | `${{ values.nom }}-dev.apps…`, `${{ values.nom }}-recette.apps…`, `${{ values.nom }}.apps…` |
| empreintes `sha256:<…>` | `sha256:<POSÉ-PAR-LA-PROMOTION>` (dev), `<À-COPIER-DE-DEV>` (recette), `<À-COPIER-DE-RECETTE>` (prod) |

Les squelettes `python` et `go` du M28-E08 changent de même : `metadata.name` et
`backstage.io/kubernetes-id` de `catalog-info.yaml`, et `image_nom`/`nom_image` de `.gitlab-ci.yml`,
prennent `${{ values.composant }}` ; `gitlab.com/project-slug` devient `${{ values.locataire }}/${{ values.nom }}` ;
`projet_deploiement` devient `${{ values.locataire }}/${{ values.nom }}-deploiement`.
