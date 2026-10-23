# Répétition de restauration du coffre à PAR2 — 2026-11-12

> Compte rendu d'exemple (lab de référence imaginé) : **remplace les valeurs par les tiennes**.

| | |
|---|---|
| Runbook | RB-355 |
| Participants | <MOI> (clavier), Karim Benali, Sophie Laurent (observatrice) ; gardiens de parts : Claire Morel, Sophie Laurent, Karim Benali |
| Sauvegarde restaurée | `vm/1024/2026-11-12T01:10:04Z` (âge au début : 8 h 52 min) |
| Instantané du coffre | `horaire/2026-11-12/vault02-20261112T094507Z.snap.age` (sur `s3-02`) |

## Chronologie et durées

| Étape | Début | Fin | Durée |
|---|---|---|---|
| Préalables (RB-355 §1), secret `wb-essais/rpo-par2` écrit à PAR1 | 10:02 | 10:08 | 6 min |
| Restauration de 3501, adresse vérifiée carte coupée | 10:08 | 10:14 | 6 min |
| Neutralisation des minuteries, isolement vérifié, carte rebranchée | 10:14 | 10:19 | 5 min |
| Descellement (3 gardiens) | 10:19 | 10:23 | 4 min |
| `bao-par2` : démarrage, initialisation, instantané, restauration, redémarrage | 10:23 | 10:32 | 9 min |
| Contrôles (secret ancien, RPO, jeton de seal, méthode `k8s-par2`) | 10:32 | 10:38 | 6 min |
| **Total de la reprise du coffre** | | | **36 min** |
| Retour en veille (RB-355 §6) | 10:38 | 10:45 | 7 min |

## Mesures

- **RPO du coffre** : secret écrit à PAR1 à 09:58:41 ; instantané restauré de 09:45:07 → secret absent ; RPO mesuré : **13 min 34 s** (borne : 1 h + copie).
- Certificat TLS de la copie de `kms01` : expire le 2026-12-02 (20 jours restants).
- Jeton de seal : `expire_time` = 2026-11-18T23:00 (≈ 6 jours après la sauvegarde) : conforme à l'hypothèse de RB-355 §5.
- Isolement : 14 paquets bloqués par les règles `isoles` pendant les 4 min où les minuteries tournaient encore (tentatives vers `s3-01` et Loki) : **la seconde ceinture a servi**.

## Écarts et actions

- PLAT-3505-a : une part saisie avec une faute de frappe (refus, nouvelle saisie) : prévoir un quatrième gardien présent.
- PLAT-3505-b : la minuterie d'instantané de `kms01` ne portait pas le nom attendu : runbook corrigé (lecture de `systemctl list-timers` d'abord).
