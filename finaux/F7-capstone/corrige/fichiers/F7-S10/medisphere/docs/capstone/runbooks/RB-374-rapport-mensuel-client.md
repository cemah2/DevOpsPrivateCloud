# RB-374 — Rapport mensuel d'un client

| | |
|---|---|
| Portée | client hébergé avec engagements de service (GHSV : EXP-03, ENF-03 à ENF-05) |
| Échéance | rapport généré le 1er à 06:15 (Paris) ; relu et remis **avant le 10** (pénalité de 200 € par jour ouvré de retard) |
| Rôles | Nadia Roussel (relecture, sections 6, remise), Julien Petit (temps de réponse, changements), responsable du compte (comité de suivi) |
| Outils | `ms-rapport-client`, `clients/<client>.yaml` (`plateforme/outils`), pipeline planifié `rapport:clients` |
| Créé | F7-S10 (PLAT-3710) |

## 1. Déclarer une maintenance programmée (au fil du mois)

1. Annoncer au client par le ticket commun **au moins 5 jours ouvrés avant**, fenêtre entre 22 h et 6 h (Paris), durée prévue.
2. MR sur `clients/<client>.yaml` (liste `maintenances`) : début, fin **prévue**, horodatage de l'annonce, CHG, motif. Après la maintenance, corriger la fin **réelle** (une maintenance qui déborde : la partie hors fenêtre est une indisponibilité, l'outil la compte).
3. Cumul du mois > 4 h : l'outil compte l'excédent comme indisponibilité.

## 2. Production du rapport (automatique)

Le pipeline planifié de `plateforme/outils` (`RAPPORT_CLIENTS=oui`) génère `docs/capstone/rapports/<client>-<AAAA-MM>.md` et ouvre une MR sur `plateforme/medisphere`. À la main, si le pipeline a échoué :
```
admin@adm01:~/src/outils$ bin/ms-rapport-client -m <AAAA-MM> ghsv > ~/medisphere/docs/capstone/rapports/ghsv-<AAAA-MM>.md
```
⚠️ Le plus tôt possible après la fin du mois (pipeline du 1er à 06:15) : chaque jour de retard fait sortir un jour de plus du mois de la rétention brute de Thanos (35 jours depuis F7-S10 ; 30 jours auparavant, ce qui ne couvrait déjà pas un mois de 31 jours).

## 3. Relecture (avant le 10)

1. Chiffres : comparer au SLO glissant de Pyrra et au tableau ; un écart inexpliqué = enquête avant remise.
2. Section 4 (incidents) : relier chaque alerte critique à sa fiche d'incident, sa cause et ses actions.
3. Section 6 : accès du personnel aux données du client (revue des accès du F6, journaux d'audit), vulnérabilités (tableau `f6-vulnerabilites`, espace du client), changements réalisés et prévus (MR des overlays du client, maintenances à venir), actions en cours. Chaque ligne cite sa source.
4. Fusion de la MR (le rapport devient une preuve : collecté par `ms-preuves`), puis remise au client (PDF depuis le Markdown, ticket commun).

## 4. Un engagement n'est pas tenu

1. Écrire la cause (fiches d'incident) et le plan d'action dans la section 6.
2. Informer le responsable du compte et Claire Morel **avant** la remise : la pénalité (CCTP §10) est calculée par le client à partir du rapport.
3. Si la mesure est contestée (sonde du client, R-09) : analyse commune en comité de suivi, les deux mesures côte à côte.

## Vérifications

- `lab/bin/check F7 10` vert.
