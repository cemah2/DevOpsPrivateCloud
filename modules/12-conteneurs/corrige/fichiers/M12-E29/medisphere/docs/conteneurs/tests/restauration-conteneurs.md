# Test de restauration — base de MédiAgenda (recette, ctr01)

| | |
|---|---|
| **Date** | <AAAA-MM-JJ> (M12-E29, PLAT-1355) |
| **Opérateur** | <MOI> ; validation : Julien Petit |
| **Sauvegarde** | PBS `par1/conteneurs`, `host/ctr01/<HORODATAGE>` (passage de 01:40) |
| **RPO** | 24 h (un export par nuit) ; perte réelle constatée : rendez-vous créés après 01:40 |
| **RTO mesuré** | **9 min** (de la décision à la base restaurée et vérifiée, hors bascule) |

## Déroulé chronométré (modèle : remplace par tes mesures)

| Étape | Commande (RB-121) | Durée |
|---|---|---|
| Liste des instantanés, choix | `proxmox-backup-client snapshot list` | 1 min |
| Téléchargement et déchiffrement | `proxmox-backup-client restore … bases.pxar` | 1 min |
| Conteneur et volume `restau-*` | `docker run … postgres:18-trixie` + `pg_isready` | 1 min |
| `pg_restore` | flux dans `docker exec -i` | 2 min |
| Vérification | requête de comptage et d'empreinte, des deux côtés | 2 min |
| Nettoyage | `docker rm`, `volume rm`, `shred` | 2 min |

## Résultat

| | Base d'origine (à 01:40) | Base restaurée |
|---|---|---|
| `count(*)` de `rendez_vous` | <N> | <N> |
| empreinte `md5(string_agg(…))` | <EMPREINTE> | <EMPREINTE> |

## Essai de copie de volume « à chaud » (étape 2 de E29)

Copie `tar` du volume pendant une boucle d'écritures : PostgreSQL redémarre dessus après une « récupération automatique » et semble sain, ce qui **ne prouve rien** (pages copiées à des instants différents, journal rejoué sur des fichiers qui ne lui correspondent pas). Copie après `docker compose stop db` : cohérente. Décision : export logique quotidien ; copie à froid réservée aux migrations planifiées (arrêt annoncé).

## Écarts et actions

- RTO dominé par la vérification humaine : script de comparaison à ajouter à RB-121 (ticket).
- Pas de restauration à un instant précis (RPO 24 h) : archivage continu des WAL avec CloudNativePG au module 16.
