---
chg: CHG-3512
titre: "Retour de la production de PAR2 à PAR1 (fin de l'exercice PRA 2026-1)"
categorie: normal
statut: termine
decision: go
demandeur: Claire Morel
executant: équipe Plateforme
approbateurs: Claire Morel, Julien Petit, Sophie Laurent
fenetre-debut: "2026-12-16T10:30:00+01:00"
fenetre-fin: "2026-12-16T12:00:00+01:00"
coupure-objectif-s: 900
coupure-mesuree-s: 550
procedure: RB-351
incident-lie: INC-6109
---

# CHG-3512 — Retour à PAR1

> Exemple de référence : heures et chiffres d'un lab imaginé.

| Champ | Valeur |
|---|---|
| Catégorie | normal ; préparation (phases A et B) le 2026-12-16 de 08:00 à 10:30 sans coupure ; **coupure** dans la fenêtre 10:30-12:00, objectif ≤ 15 min |
| Risque | élevé : bascule d'une base de santé, deux sites, données écrites des deux côtés |
| Impact | MédiAgenda, MédiDoc, Legacy-RDV indisponibles pendant la coupure (cabinets prévenus la veille, message de maintenance) ; MédiNotif : notifications retardées de la durée de la coupure |
| Procédure | RB-351 |
| Retour arrière | jusqu'à C3 : rester à PAR2 sans perte (remettre les réplicas) ; de C3 à C4 : repromouvoir PAR2 (`replica.primary: mediagenda-db-par2`, sa ligne temporelle est intacte) ; après C4 : pas de retour simple — rester à PAR1 et corriger en avant |
| Préalables | RB-351 §0, tous verts le 2026-12-16 à 07:55 (Nadia Roussel) |

## Exécution

| Heure | Étape | Observé | Écart |
|---|---|---|---|
| 08:02 | A1-A2 | auto-synchronisation de l'Application de prod de PAR1 suspendue ; API de PAR1 à 0 ; témoin de PAR1 suspendu | — |
| 08:06 | A3-A4 | export de la divergence (voir ci-dessous) | — |
| 08:12 | A5 | deux `VolumeSnapshot` (instances de `mediagenda-db`) prêts | — |
| 08:14 | A6 | `mediagenda-db` clôturé (toutes instances) | — |
| 08:20 | A7 | 10 *push mirrors* désactivés | — |
| 08:24 | A8 | `filer.sync` et minuterie `rclone` arrêtés sur `s3-02` | — |
| 08:31 | A9-A10 | constat de Sophie ; isolement levé depuis `pve01` | — |
| 08:40 | B1 | 4 projets avec commits de PRA (`plateforme/medisphere`, `mediagenda/deploiement`, `medidoc/deploiement`, `legacy/deploiement`) : MR en avance rapide, fusionnées | — |
| 08:52 | B2 | `filer.sync` relancé, rattrapage de 22 h d'événements en 6 min | — |
| 09:05 | B3 | flux PAR1 → `s3-02` ouvert ; nouvelle `mediagenda-db` en réplique de PAR2 ; rattrapage terminé à 09:41 | **écart** : 12 min perdues — l'identité de lecture de `s3-02` n'avait pas le droit `List` (corrigé, ajouté au contrôle 0.6) |
| 09:48 | B4 | nouvelle autorité de la base copiée pour OpenBao de PAR1 | — |
| 09:55 | B5 | 41 documents copiés de `s3-02` vers le RGW, `rclone check` sans différence | — |
| 10:10 | B6 | répétition du transfert de Legacy-RDV sur la recette : 3 min 40 | — |
| 10:30 | C1 | **début de coupure** : écritures de PAR2 gelées, file `notifications` vide | — |
| 10:32 | C2 | derniers deltas : 2 documents ; base de Legacy-RDV transférée | — |
| 10:34 | C3 | PAR2 rétrogradé ; jeton disponible à 10:35 | — |
| 10:36 | C4 | PAR1 promu (jeton) à 10:37 ; auto-synchronisation réactivée | — |
| 10:38 | C5 | API de PAR1 prête ; création d'un rendez-vous par Julien : 201 | — |
| 10:39 | C6 | série de dns01 portée à 2026121604 (dns03 : 2026121502) ; dns03 secondaire, transfert à 10:39:40 | — |
| 10:40 | C7 | **fin de coupure** : la sonde voit `par1` sur les trois noms | coupure mesurée 9 min 10 s (objectif 15) |
| 11:30 | D1-D9 | veille de PAR2, miroirs, `rclone`, coffre, sauvegardes, clôture d'INC-6109 | — |

## La divergence de PAR1 (export A4)

| Mesure | Valeur |
|---|---|
| Dernier témoin vu à PAR2 (D) | 2026-12-15 08:58:02 UTC |
| Dernier témoin écrit à PAR1 avant T0 (09:07:00 UTC) | 2026-12-15 09:06:03 UTC |
| **RPO exact de MédiAgenda** | **8 min 01 s** (borne de RB-350 : 8 min 58 s) |
| Témoins de PAR1 entre D et T0 | 8 (ce qu'un vrai sinistre aurait perdu, côté témoin) |
| Témoins de PAR1 après T0 (PAR1 isolé, jusqu'à A2) | 1 315 (écritures « fantômes » d'un site qui se croyait vivant) |
| Rendez-vous réels de PAR1 entre D et T0 | 3 — remis chiffrés à Julien ; décision : recontact des 3 patients par le support, aucune réinjection automatique (créneaux repris entre-temps à PAR2 pour 1 d'entre eux) |
| Rendez-vous réels de PAR1 après T0 | 0 (aucun accès possible des cabinets à PAR1 pendant l'isolement) |
| Annulations de PAR1 après D | non mesurables par `cree_le` (limite écrite) ; journaux de l'API de PAR1 : 0 `DELETE` entre 08:58 et 09:07 UTC |

## Preuves

- `docs/pra/mesures/2026-exercice-1/temoins-par2.csv` (témoins écrits à PAR2 pendant le PRA, tous servis par PAR1 après le retour : `lab/bin/check F5 12`) ;
- `docs/pra/mesures/2026-exercice-1/medidoc-par2.csv` (documents déposés à PAR2, tous servis par PAR1) ;
- `docs/pra/mesures/2026-exercice-1/temoins-par1-divergence.csv` (témoins seulement) ;
- relevés de Sophie, journal de la sonde.

## Revue après mise en œuvre

Objectif de coupure tenu (9 min 10 s pour 15). L'écart de B3 (droit `List` manquant) montre que le flux de retour n'avait jamais été essayé : le test trimestriel (S14) lit désormais l'archive de PAR2 **depuis PAR1** une fois par trimestre. Les instantanés A5 et les exports de divergence sont conservés jusqu'à l'approbation du rapport (PLAT-3535).
