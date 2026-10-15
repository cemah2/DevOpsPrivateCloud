## Pourquoi

<!-- Ticket, besoin. Une MR = un changement. -->

## Ce qui change

- [ ] Type de version attendu (Conventional Commits) : `fix:` (correctif) / `feat:` (mineure) / `feat!:` ou `BREAKING CHANGE:` (majeure : valeur renommée ou supprimée, objet renommé)
- [ ] `values.yaml`, `values.schema.json` et les tests helm-unittest sont cohérents

## Diff du rendu (obligatoire, M17-E14)

Release du dev, avec l'état réel du cluster :

```
helm diff upgrade mediagenda charts/mediagenda -n mediagenda-dev --reuse-values \
  --three-way-merge --normalize-manifests --context 3
```

<details><summary>Diff</summary>

```diff
(colle ici)
```
</details>

## Retour arrière

<!-- Version précédente du chart à réutiliser ; migrations de schéma éventuelles et leur réversibilité. -->
