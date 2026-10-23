# Plan de reprise d'activité (PRA) de MédiSphère — `pra-v1`

> Point d'entrée. Si PAR1 vient de disparaître : **[RB-350](runbooks/RB-350-bascule-par2.md)** et **[cellule de crise](cellule-de-crise.md)**. Ce dossier est aussi lisible à PAR2, dans le miroir de `plateforme/medisphere` sur `adm02`.

## Comprendre

| Document | Contenu | Révision |
|---|---|---|
| [`bia.md`](bia.md) | analyse d'impact : ce que coûte l'arrêt de chaque service, DMIA et PDMA | annuelle |
| [`objectifs.md`](objectifs.md) | RTO, RPO, mode dégradé et périmètre du PRA v1, justifiés par la BIA | après chaque exercice |
| [`dependances.md`](dependances.md) | ce dont la reprise dépend, dans quel ordre (vagues), et la mesure de chaque flux | à chaque changement de PAR2 |
| [`adr/ADR-0350-site-de-repli-par2.md`](adr/ADR-0350-site-de-repli-par2.md) | pourquoi un site tiède sur `hp01`, et ce qu'il ne permet pas | révision 2027-03-31 |

## Agir

| Document | Quand |
|---|---|
| [`cellule-de-crise.md`](cellule-de-crise.md) | rôles, canaux qui ne dépendent pas de PAR1, messages, main courante |
| [`runbooks/RB-350-bascule-par2.md`](runbooks/RB-350-bascule-par2.md) | déclenchement et bascule vers PAR2 |
| [`runbooks/RB-351-retour-par1.md`](runbooks/RB-351-retour-par1.md) | retour à PAR1 sans perte |
| [`runbooks/RB-353-hyperviseur-par2.md`](runbooks/RB-353-hyperviseur-par2.md) | hyperviseur et réseau de PAR2 sur `hp01` (go/no-go, retour arrière, amorçage de l'état) |
| [`runbooks/RB-354-replication-par2.md`](runbooks/RB-354-replication-par2.md) | réplications vers PAR2 (objets, documents, code, images) ; copie ≠ sauvegarde |
| [`runbooks/RB-355-coffre-de-secours.md`](runbooks/RB-355-coffre-de-secours.md) | restauration de `kms01` à PAR2 et coffre de secours `bao-par2` |
| [`runbooks/RB-356-cluster-de-secours.md`](runbooks/RB-356-cluster-de-secours.md) | cluster `k8s-par2`, base de secours, secrets, témoin |
| [`enveloppe.md`](enveloppe.md) | ce qu'il faut avoir en main (sans aucun secret ici) |

## Prouver

| Document | Contenu |
|---|---|
| [`calendrier-tests.md`](calendrier-tests.md) | ce qui est testé, quand, par qui ; historique des tests |
| [`exercices/2026-exercice-1/`](exercices/2026-exercice-1/) | répétition (`repetition.md`), mode dégradé, fiche de retour CHG-3512, **rapport** |
| [`mesures/`](mesures/) | retards de réplication, mesures de la sonde, témoins, documents, divergence |
| [`journal/`](journal/) | mains courantes des exercices et des incidents PRA |

## Outillage (hors de ce dépôt)

- `plateforme/k8s` : `outils/pra/controle-preparation.sh`, `mesures-pra.sh`, `rejouer-notifications.sh`, `essai-reprise.sh` ; fichiers de site de PAR2 ; job `pra:essai-reprise` et son pipeline planifié.
- `adm02` : sonde `ms-sonde-pra`, Prometheus, Alertmanager, blackbox_exporter, Mailpit de secours (`regles-pra.yml`).
- Mesures en continu : `cnpg_pra_temoin_age_secondes`, `cnpg_pg_replication_lag`, `pra_par2_pret` (Prometheus de PAR2).

Étiquette `pra-v1` posée après l'exercice 2026-1, le rapport approuvé et le premier essai trimestriel réussi.
