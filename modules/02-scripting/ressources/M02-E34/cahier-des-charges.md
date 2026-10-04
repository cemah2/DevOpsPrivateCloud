# M02-E34 — Cahier des charges : `ms-verif-socle`

> N'ouvre ce fichier qu'au moment de lancer le chronomètre. Durée : **90 minutes**.

## Demande (Nadia Roussel, astreinte)

« Avant chaque nuit d'astreinte, je veux une commande qui me dise en une fois si le socle est
sain : chaque hôte joignable, à l'heure, avec de la place, son nom DNS cohérent, et le certificat
de GitLab encore valide. Une ligne par contrôle, un code retour fiable, et une sortie JSON pour
qu'on la branche plus tard sur la supervision. »

## Interface (imposée : elle est vérifiée)

```
ms-verif-socle [-j|--json] [HOTE...]
```

- Emplacement : `bin/ms-verif-socle` du clone `~/src/outils`, exécutable, chargeant
  `lib/ms-commun.sh` comme les autres outils.
- `HOTE` : alias SSH de `adm01`. Sans argument : `gw01 dns01 git01 runner01 pbs01`.
- Un nom d'hôte qui n'est pas de la forme `^[a-z][a-z0-9-]{0,30}$` est refusé (code 2).
- Option inconnue : code 2.

## Contrôles, pour chaque hôte

| Contrôle | OK si… |
|---|---|
| `dns` | `<HOTE>.par1.medisphere.internal` résout, **via 10.10.20.10**, vers l'adresse que vise l'alias SSH (`ssh -G`), et le PTR de cette adresse commence par `<HOTE>.` |
| `ssh` | connexion par clé, sans interaction (`BatchMode`), établie en moins de 5 s |
| `temps` | chrony de l'hôte synchronisé (`Leap status : Normal`) et écart absolu < 0,5 s |
| `disque` | système de fichiers `/` de l'hôte occupé à moins de 85 % |
| `tls` | si le port 443 de l'hôte répond : chaîne de certificats valide pour le magasin de `adm01`, nom conforme, validité restante ≥ 30 jours. Port fermé : état `NA` |

Si SSH échoue, `temps` et `disque` sont `KO` (on ne peut pas affirmer qu'ils vont bien).

## Sorties

- Texte (défaut) : une ligne par contrôle sur la sortie standard, champs séparés par une
  **tabulation** : `HOTE  CONTROLE  ETAT  DETAIL`, `ETAT` ∈ `OK`, `KO`, `NA`. Dans l'ordre des
  hôtes demandés, contrôles dans l'ordre du tableau.
- `--json` : un **tableau JSON** d'objets `{"hote", "controle", "etat", "detail"}` sur la sortie
  standard, et rien d'autre sur la sortie standard.
- Journaux et bilan : sur la sortie d'erreur.

## Codes retour

`0` aucun `KO` ; `1` au moins un `KO` ; `2` usage. Un hôte injoignable ne doit pas empêcher de
contrôler les suivants.

## Exigences de qualité

- `shellcheck -x` sans aucun message ; format `shfmt` du projet.
- Au moins **trois** tests dans `tests/bats/ms-verif-socle.bats`, sans accès réseau.
- Durée totale < 60 s pour les cinq hôtes du socle.
- Aucune écriture sur les hôtes contrôlés (lecture seule).
- Commit sur une branche `feat/ms-verif-socle`, message Conventional Commits.

## Fin de l'épreuve

À la fin des 90 minutes, arrête-toi, commite l'état atteint (même incomplet) et lance
`lab/bin/check 02 34`. Note dans ton journal : l'heure de fin, les critères atteints, ce qui t'a
fait perdre du temps.
