# Journal de diagnostic — INC-5240 « permission denied » (Julien Petit)

> Modèle de journal (M25-E40). Une ligne par geste : heure, hypothèse, commande (sans secret), résultat,
> conclusion. Aucun jeton, aucun accesseur complet (les 6 premiers caractères suffisent).

| Heure | Hypothèse | Commande | Résultat | Conclusion |
|---|---|---|---|---|
| 09:12 | — | `bao token lookup -accessor 4kQ2xV…` | `display_name oidc-julien.petit`, `identity_policies [mediagenda-dev]` | Julien a bien le groupe |
| 09:14 | la politique ne couvre plus le chemin | `bao write sys/capabilities-accessor accessor=4kQ2xV… paths=kv/data/mediagenda/dev/valkey` | `[deny]` | refus confirmé sans usurper |
| 09:16 | — | audit Loki : `… erreur="permission denied"` | `update kv/data/mediagenda/dev/valkey` | le chemin demandé est le bon |
| 09:18 | — | `bao policy read mediagenda-dev` | `path "kv/data/mediagenda/+"` | `+` = un seul segment : `dev/valkey` en a deux |
| 09:20 | dérive | `tofu plan` (plateforme/secrets) | `vault_policy.acl["mediagenda-dev.hcl"]` à mettre à jour | le dépôt a raison |
| 09:31 | — | pipeline de `main` (tester-politiques ajouté, apply) | 20 cas, 0 écart ; apply OK | — |
| 09:33 | — | `sys/capabilities-accessor` (même accesseur) | `create, delete, read, update` | réparé sans reconnexion |

**Cause** : motif `kv/data/mediagenda/+` (un segment) à la place de `kv/data/mediagenda/dev/*`, posé
à la main. **Correctif** : `tofu apply` de `main`. **Prévention** : `tests/politiques/capacites.tsv`,
alerte `OpenBaoPolitiqueModifiee` (M25-E21) relue par l'astreinte.
