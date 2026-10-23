# RB-346 — Bascule et retour arrière de Legacy-RDV

> CHG-3413 (F4-S13). Outils : `bascule-legacy-rdv.sh`, `retour-arriere-legacy-rdv.sh`,
> `copier-donnees-legacy.sh` (plateforme/outils, dossier `legacy-rdv/`). Nom des cabinets :
> `rdv.par1.medisphere.internal` (répartiteurs, variable `legacy_rdv_cible` de `group_vars/role_lb/legacy-rdv.yml`).

## J-7 à J-1
1. Annonce aux cabinets (Nadia) : date, heure, durée (15 min), numéro du support.
2. Répétition complète vers la recette (`--repetition`), chronométrée : durée reportée dans la fiche.
3. Trois MR **préparées et approuvées** (non fusionnées) : `legacy_rdv_cible: maintenance`, `k8s`, `vm`.
4. J-1 : `bascule-legacy-rdv.sh --pre-copie` (pièces jointes, horodatage gardé).

## Jour J (fenêtre ≤ 15 min mesurée par la sonde)
| Minute | Étape | Contrôle |
|---|---|---|
| -30 | go/no-go : sonde verte, sauvegarde PBS de 3401 du matin vérifiée, base de prod prête, astreinte | fiche |
| 0 | MR `maintenance` (lb02 puis lb01) : page 503 « maintenance » | sonde : début de l'interruption |
| 1 | gel : `REVOKE INSERT, UPDATE, DELETE` du compte applicatif sur la VM | `SHOW GRANTS` |
| 2 | **référence** relevée (nombre, identifiant max.) → fiche | |
| 3-6 | vidage logique → prod ; rattrapage des pièces jointes | nombres égaux |
| 7-9 | contrôles : témoins, empreinte des dates, échantillon de pièces | aucun écart |
| 10 | **point de non-retour** : MR `k8s` (lb02, contrôle, lb01) | `https://rdv…/` 200 |
| 11-15 | contrôles fonctionnels par l'URL des cabinets ; fin d'annonce | sonde : fin de l'interruption |

## Retour arrière
- **Avant le point de non-retour** : MR `vm`, `GRANT` rendu ; rien d'autre (la VM n'a rien perdu). 3 min.
- **Pendant les 48 h** : `retour-arriere-legacy-rdv.sh` : maintenance, rapatriement des rendez-vous `id > identifiant max. au gel` et des pièces jointes déposées depuis la bascule, `GRANT` rendu, MR `vm`. ≈ 10 min.
- **Après 48 h** : plus de retour vers la VM (décommissionnement, F4-S14) ; on répare en avant (restauration de la sauvegarde de l'opérateur).

## Après
`stats01` : tâche nocturne désactivée (aucun lecteur depuis 2020, décision de Claire) ; sauvegarde de production vérifiée le lendemain (objet dans `mariadb-legacy-rdv/prod/`) ; alertes de Legacy-RDV en production (sonde blackbox de `mon01` sur `rdv`, disponibilité des pods) ; fiche complétée.
