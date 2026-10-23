# Schémas des CRD pour kubeconform (paquet `schemas-crd`)

> `plateforme/medisphere` — `docs/qualite/schemas-crd.md` (M29-E02, PLAT-3002). Propriétaire : équipe Plateforme.

| Élément | Valeur |
|---|---|
| Outil | `plateforme/k8s/outils/schemas-crd.sh` (`generer`, `publier`, `verifier`) |
| Source | les CRD **servies par `k8s-par1`** (`kubectl get crd`), donc les versions réellement installées |
| Conversion | `outils/openapi2jsonschema.py` de kubeconform v0.8.0 (empreinte vérifiée par le script) : ajoute `additionalProperties: false` (racine comprise, `DENY_ROOT_ADDITIONAL_PROPERTIES=1`), sans quoi `-strict` laisse passer un champ inconnu dans une ressource personnalisée |
| Contenu | `<groupe>/<kind>_<version>.json`, `api-versions.txt` (pour `helm template --api-versions`), `LISEZMOI` |
| Publication | paquet générique GitLab **`schemas-crd`** du projet `plateforme/k8s`, version `AAAA.MM.JJ[-N]`, archive `schemas-crd.tar.gz` + `schemas-crd.tar.gz.sha256` |
| Consommateurs | composant CI/CD `validation` (input `schemas_crd_version`), postes (`adm01`) |
| Quand régénérer | après toute installation ou montée de version d'un composant qui apporte des CRD (Argo CD, CNPG, RabbitMQ, KEDA, Capsule, Chaos Mesh, k6-operator…), puis relever la version dans les dépôts consommateurs (MR) |

Lecture côté poste :

```
admin@adm01:~$ kubeconform -strict -summary -kubernetes-version 1.36.5 \
    -schema-location default -schema-location "$HOME/schemas-crd/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" rendu.yaml
```

Jamais `-ignore-missing-schemas` : un type sans schéma est **sauté** (« Skipped »), le code de sortie reste 0, et la CI dit vert sur un objet qu'elle n'a pas lu.
