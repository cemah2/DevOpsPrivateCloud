# Recette Day 0 — `k8s-par1` reconstruit (PLAT-3114)

> Modèle du corrigé de F1-S14. Signée par Claire Morel par l'approbation de la MR qui publie ce
> document ; l'étiquette `day0-v1` est posée **après** la fusion, sur un `main` au pipeline vert.

| | |
|---|---|
| Date | <AAAA-MM-JJ> (J+<N> après la réouverture : les contrôles datés ont eu une nuit) |
| Cluster | né le <AAAA-MM-JJ HH:MM> (espace `kube-system`) |
| Lancement | `lab/bin/check F1 14` (et chaque contrôle seul pour le détail) |

## Contrôles

| Commande | Résultat | Date | Remarque |
|---|---|---|---|
| `lab/bin/check 29 25` | vert | <AAAA-MM-JJ> | |
| `lab/bin/check 28 25` | vert | | |
| `lab/bin/check 27 25` | vert | | |
| `lab/bin/check 26 46` | vert | | |
| `lab/bin/check 25 46` | vert | | |
| `lab/bin/check 24 46` | vert | | |
| `lab/bin/check F1 2` | vert | | aucune dérive après la reconstruction |
| `lab/bin/check F1 5`, `F1 6` | vert | | |
| `lab/bin/check F1 7` à `F1 13` | vert | | |
| `ms-verif-services`, `ms-verif-sauvegardes` | vert | | |

## Écarts légitimes et leur traitement

| Contrôle | Écart | Pourquoi il est légitime | Traitement |
|---|---|---|---|
| <ex. `27 25`> | <ex. lit l'archive sous `serverName: mediagenda-db-prod`> | la production archive désormais sous `mediagenda-db-prod-day0` (F1-S11) | <variable `WB_…` posée dans `lab/lab.env`, ou contrôle corrigé par MR du workbook> |

## Variables `WB_*` adaptées

| Variable | Valeur | Raison |
|---|---|---|
| <…> | <…> | <…> |

## Réserves

| Réserve | Échéance | Responsable |
|---|---|---|
| <ex. gestes manuels inscrits en dette au rapport (S15)> | <AAAA-MM-JJ> | |

## Décision

Recette prononcée le <AAAA-MM-JJ> ; étiquette `day0-v1` posée sur `plateforme/medisphere` (commit <SHA>).
