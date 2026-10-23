# CHG-3104 — Filet de sécurité et go/no-go de la fenêtre CHG-3107

| | |
|---|---|
| Demandeur | Claire Morel |
| Exécutant | <MOI> |
| Relecteurs | Karim Benali (technique), Sophie Laurent (sécurité) |
| Fenêtre décidée | CHG-3107 : <date>, 18 h 00 → 06 h 00 (production gelée, MédiAgenda en maintenance annoncée) |
| Communication | Nadia (support) : annonce J-3 et J-1 ; Julien : gel des déploiements à partir de J-1 12 h |

## 1. Critères de go (tous verts, vérifiés à J-1 18 h, preuves de moins de 24 h)

| # | Critère | Comment on le vérifie | Résultat |
|---|---|---|---|
| G1 | Contrôles d'entrée du final verts | `lab/bin/check 29 25`, `28 25`, `27 25` | ✅ / ❌ |
| G2 | Dérive nulle sur toutes les couches | `lab/bin/check F1 2` ; dernier pipeline planifié de chaque couche | |
| G3 | Filet prouvé | `lab/bin/check F1 4` vert | |
| G4 | Lisibilité PBS | VM 5311 restaurée depuis `k8s-cp01` et démarrée (durée : <N> min) | |
| G5 | Instantané etcd lisible | téléchargé, déchiffré, `etcdutl snapshot status` | |
| G6 | WAL de `mediagenda-db` (prod) à jour | `lastArchivedWALTime` de moins de 10 min | |
| G7 | Usine prête | `lab/bin/check F1 6` vert, `pxe01` démarrée | |
| G8 | Socle redondant | `lab/bin/check F1 5` vert (`lb01`, `dns01` et leurs jumelles) | |
| G9 | Secrets d'amorçage accessibles | `admin.conf` (Vault `critique`), mots de passe Vault Ansible, clés `age` : ouverts par un témoin (pas d'affichage) | |
| G10 | Retour arrière relu | `retour-arriere.md` relu par Nadia, questions closes | |
| G11 | Mémoire | `free -g` sur `pve01` : ≥ 12 Go libres ; aucune VM temporaire | |

Un seul ❌ = **no-go**, la fenêtre est reportée et S04 se rejoue.

## 2. Messages en file

`notifications.rebut` (prod) : 3 messages, examinés avec Julien, perte acceptée (DEV-3104). `notifications` vide à 18 h (consommateurs à jour) ; MédiAgenda en maintenance : plus de publication pendant la fenêtre.

## 3. Décision

| Date et heure | Décision | Par | Remarques |
|---|---|---|---|
| <AAAA-MM-JJ HH:MM> | **GO** / NO-GO | Claire Morel | <critère en défaut s'il y a lieu> |
