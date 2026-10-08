# Tests de restauration de ceph-par1

> Les tests les plus récents en tête. Chaque test : date, opérateur, ce qui est restauré, à partir de quoi, durée de chaque étape, résultat, écarts.

## 2026-10-XX — Restauration de `rbd-test/disque01` à J-1 et de la configuration (M08-E25)

**Préparation** : 1 Gio de données témoins écrites dans `disque01` (fichier `temoin.bin`, somme `sha256` notée), complet le dimanche `sauv-AAAAMMJJ`, incrémentaux J-2 et J-1 (passages forcés avec `WB_DATE`).

| Étape | Début | Durée | Commentaire |
|---|---|---|---|
| Recherche des sauvegardes (`snapshot list`, `catalog dump`) | | 3 min | trois sauvegardes `host/ceph-par1-rbd` nécessaires |
| Téléchargement depuis PBS (3 × `restore`) | | 4 min | via `wg0`, 1,1 Gio au total |
| Vérification de `MANIFESTE.tsv` | | 1 min | sommes identiques |
| `rbd create` + 3 × `import-diff` | | 3 min | |
| Comparaison des sommes | | 2 min | `rbd export rbd-test/disque01@sauv-J-1 - \| sha256sum` = `rbd export rbd-test/restau-disque01@sauv-J-1 - \| sha256sum` |
| Restauration de l'archive de configuration et `diff` avec `plateforme/ceph` | | 5 min | écarts : aucun (ou : liste) |

**RTO mesuré** : 18 min pour un volume de 1 Gio (dominé par le transfert depuis PAR2 ; extrapolation : ~ 3 min par Gio supplémentaire à ce débit).
**RPO** : 24 h (sauvegarde quotidienne à 01:30).
**Nettoyage** : `rbd-test/restau-disque01` supprimée, dossier de travail supprimé.
**Écarts et actions** : …
