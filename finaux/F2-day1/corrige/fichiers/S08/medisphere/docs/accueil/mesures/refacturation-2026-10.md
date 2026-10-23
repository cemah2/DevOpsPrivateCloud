# Refacturation interne (showback) — 2026-10 (partiel, au 2026-10-31)

Moyennes du mois, tirées des règles `locataire:*` de Prometheus (RB-328). CPU et mémoire : max(réservé, utilisé) ; stockage : PVC demandés. Tarifs : `showback/tarifs.yaml`. Montants indicatifs, pas une facture.

| Locataire | CPU facturé (cœurs) | Mémoire facturée (Gio) | Stockage demandé (Gio) | Coût indicatif (EUR) |
|---|---:|---:|---:|---:|
| mediagenda | <VALEUR> | <VALEUR> | <VALEUR> | <VALEUR> |
| medinotif | <VALEUR> | <VALEUR> | <VALEUR> | <VALEUR> |
| medivisio | <VALEUR> | <VALEUR> | <VALEUR> | <VALEUR> |
| medidoc | <VALEUR> | <VALEUR> | <VALEUR> | <VALEUR> |
| data | <VALEUR> | <VALEUR> | <VALEUR> | <VALEUR> |
| **Total** | | | | **<VALEUR>** |

*Exemple de forme : les valeurs sont celles de TON lab (`bin/ms-showback --partiel --mois 2026-10`).*

## Hors du tableau

| Élément | Locataire | Volume | Coût indicatif |
|---|---|---|---|
| compartiment RGW `data-resultats` | data | <TAILLE> Gio (`radosgw-admin bucket stats --bucket=data-resultats`) | <VALEUR> EUR |
| sas `data-extractions` (s3-01) | data / plateforme | < 1 Gio, purgé à 7 jours | négligeable |
| base `statistiques-db` : sauvegardes `cnpg-data` (s3-01) | data | <TAILLE> Gio | <VALEUR> EUR |

Non comptés : espaces de plateforme, CI (`ci-jobs`), supervision, VMs du socle, réseau.

## Commentaires

- **medivisio** : arrivée le <DATE> ; mois partiel. CPU — mémoire — stockage : lire l'efficacité *réservé/utilisé* du tableau avant la prochaine revue des requests.
- **data** : la base `statistiques-db` réserve plus qu'elle n'utilise hors de la fenêtre 03:30-05:00 ; les lots (`medisphere-lot`) restent sous leur quota propre.
- Actions proposées : <ACTIONS>.
