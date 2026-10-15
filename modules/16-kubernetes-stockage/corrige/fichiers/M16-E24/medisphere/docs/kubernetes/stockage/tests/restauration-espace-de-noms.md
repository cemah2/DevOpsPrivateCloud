# Essai de restauration d'un espace de noms — modèle de compte rendu (M16-E24)

| | |
|---|---|
| Date | <AAAA-MM-JJ> |
| Opérateur | <MOI> |
| Source | `mediagenda-recette`, sauvegarde Velero `e24-recette` (<HORODATAGE>, <N> objets, <N> volumes déplacés par le *data mover*) |
| Cible | `wb-restauration` |
| Versions | Velero 1.18.x, plugin AWS 1.14.x, CloudNativePG 1.30.x, plugin Barman Cloud 0.15.x |

## État de référence (avant sauvegarde, écritures de test suspendues)

| Mesure | Source |
|---|---|
| Rendez-vous | <N> |
| Empreinte de `rendez_vous` | <MD5> |
| Clés Valkey | <N> |

## Chronologie

| Heure | Étape | Durée | Observations |
|---|---|---|---|
| | Décision, cible vérifiée | | |
| | `Restore` appliqué | | |
| | `Restore` `Completed` (dont téléchargement des volumes) | | |
| | `Cluster` de récupération appliqué | | |
| | `Cluster` sain | | |
| | Tous les pods prêts | | |
| | Contrôles terminés | | |

**RTO mesuré** : <DURÉE> (dont <DURÉE> pour la base, <DURÉE> pour les volumes).

## Contrôles

| Contrôle | Attendu | Obtenu |
|---|---|---|
| Rendez-vous / empreinte / clés Valkey | identiques à la référence | |
| Hôte de la base vue par l'API de la copie | `mediagenda-db-rw.wb-restauration` | |
| HTTPRoute de la copie | non acceptée, aucun DNS | |
| CronJobs de la copie | suspendus | |
| WAL ou sauvegarde partis de la copie | aucun | |
| Recette | intacte (base saine, API prête, archivage actif) | |

## Écarts et décisions

- <écart> → <cause> → <action, ticket>.

## Nettoyage

Copie supprimée le <AAAA-MM-JJ HH:MM> ; images RBD de la copie absentes de `k8s-rbd` (<N> images avant, <N> après).
