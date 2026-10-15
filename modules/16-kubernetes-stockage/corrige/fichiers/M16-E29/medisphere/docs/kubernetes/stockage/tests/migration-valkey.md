# Migration du Valkey de la recette vers `ceph-rbd-chiffre` — compte rendu M16-E29 (SEC-1729)

| | |
|---|---|
| Date | <AAAA-MM-JJ> |
| Volume | `mediagenda-recette/donnees-valkey-0` (<TAILLE>), `ceph-rbd` → `ceph-rbd-chiffre` |
| Témoins | clés `e29:*` (<N> clés, empreinte <SHA256>) ; `outils/temoin-api.sh` (API publiée) |
| Mesure prise pour l'API | sonde de disponibilité de l'API : `failureThreshold` 3 → 30 pendant la fenêtre (MR <!N>), rétablie (MR <!N>) ; DEV-1729 ouvert |

## Répétition

| Essai | Coupure de Valkey | Effet sur l'API (témoin) |
|---|---|---|
| Sans adaptation de la sonde | 2 min | <N> s d'échecs : pods de l'API retirés du Service après ~30 s |
| Avec `failureThreshold: 30` | 2 min | 0 échec ; créneaux calculés depuis la base (mode dégradé) |

## Chronologie

| Heure | Étape | Durée |
|---|---|---|
| | PV source en `Retain`, PVC cible créé | |
| | Copie à chaud (<N> Mio) | |
| | **Début de coupure** : `valkey` à 0 | |
| | Copie à froid (<N> fichiers, <N> Kio transférés) | |
| | PV cible rattaché, StatefulSet recréé (MR) | |
| | **Fin de coupure** : `valkey-0` prêt | |

**Coupure de Valkey** : <DURÉE> (objectif ≤ 2 min). **Échecs du témoin de l'API** pendant la coupure : <N> (objectif 0).

## Contrôles

| Contrôle | Résultat |
|---|---|
| Clés témoins (nombre, empreinte) | identiques |
| PVC `donnees-valkey-0` lié à un PV de `ceph-rbd-chiffre` | oui (`<PV>`) |
| `lsblk` sur `<NŒUD>` : `rbdN` → `crypt` | oui |
| `rbd image-meta list k8s-rbd/<IMAGE>` : `rbd.csi.ceph.com/encrypted` | `encrypted` |
| Sonde `ms-verif-k8s-stockage` | verte |
| Ancien PV et son image RBD | supprimés le <AAAA-MM-JJ> |
