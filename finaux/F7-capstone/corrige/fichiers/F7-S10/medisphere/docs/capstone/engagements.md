# Engagements de service du GHSV : définitions et mesures

> F7-S10 (PLAT-3710). Répond à EXP-07 (« le candidat décrit comment il mesure ») et à R-09 (la mesure du titulaire fait foi si sa méthode a été validée en comité de suivi). Code : `plateforme/observabilite/slo/ghsv-*.yaml`, sondes `client-ghsv*` du témoin de `mon01` (`plateforme/ansible`), `plateforme/outils/bin/ms-rapport-client` et `clients/ghsv.yaml`. Procédure : RB-374.

## 1. Tableau des engagements

| Engagement (CCTP) | Indicateur exact | Source | Fréquence | Où le lire | Ce qu'il ne voit pas |
|---|---|---|---|---|---|
| ENF-03 : disponibilité mensuelle ≥ 99,9 % de la prise de rendez-vous | part des sondes réussies, mois calendaire de Paris, hors maintenances conformes : `sum(sum_over_time(probe_success{job="blackbox",groupe=~"client-ghsv.*"}[I]))` / `sum(count_over_time(…[I]))`, I = intervalles du mois hors maintenances | sondes HTTPS de `mon01` (hors cluster) : `/pret` (chaîne complète) **et** une opération du contrat authentifiée (`GET /api/v1/creneaux`, client `ghsv-sonde`), toutes les 30 s | 30 s | rapport mensuel ; SLO Pyrra `ghsv-disponibilite-sonde` (30 j glissants) | une panne entre deux sondes (< 30 s) ; une panne qui ne touche qu'une opération non sondée (création) ; le réseau du GHSV jusqu'à nous |
| (complément) | part des requêtes de l'API sans 5xx | compteur `mediagenda_http_requests_total` de l'application | 30 s | SLO `ghsv-disponibilite` ; rapport §1 | tout ce qui n'arrive pas à l'API (Gateway, DNS, mandataires, réseau) |
| ENF-05 : 95 % des requêtes de l'API < 300 ms | `increase(…_bucket{le="0.3"})` / `increase(…_count)` sur le mois | histogramme de l'application (seau 0,3 ajouté en F7-S10) | 30 s | SLO `ghsv-latence` ; rapport §3 | le temps passé dans la Gateway et les mandataires : mesuré par la charge k6 de recette (écart p95 serveur/client noté dans le rapport de charge) ; si > 20 ms, la mesure passe à la Gateway |
| ENF-05 : aucune requête > 1 s | proposition R-10 : 99,9 % < 1 s, seau `le="1.0"` | idem | 30 s | rapport §3 | un maximum absolu n'est pas mesurable par un histogramme (ni promettable) : réserve écrite dans l'offre |
| ENF-04 : maintenances annoncées 5 jours ouvrés avant, 22 h-6 h, ≤ 4 h/mois | liste `maintenances` de `clients/ghsv.yaml`, contrôlée par l'outil (annonce, horaires, cumul) | MR relue (Nadia Roussel), horodatage de l'annonce = message du ticket commun | à chaque maintenance | rapport §2 | les jours fériés (comptés comme ouvrés par l'outil : une annonce peut être jugée conforme à tort ; calendrier à ajouter avant la production, risque écrit) |
| ENF-06 : RTO 4 h, RPO 15 min | RPO : dernier témoin `PRA-TEMOIN` écrit à PAR1 − dernier retrouvé à PAR2 ; RTO : déclaration du sinistre → première sonde verte sur le nom global | témoin `temoin-rpo` (1/min), sondes, main courante | à chaque essai (annuel, ENF-08) | `pra-ghsv.md`, rapport d'exercice | les rendez-vous confirmés dans les 15 min perdues (ENF-07, R-11) : traités par la réconciliation avec le DPI (§3) |
| EXP-03 : rapport avant le 10 | rapport généré le 1er à 06:15 (Paris), MR sur `plateforme/medisphere` | `ms-rapport-client` (pipeline planifié de `plateforme/outils`) | mensuel | `docs/capstone/rapports/` | les sections 6 (sécurité, changements, actions) : relues et complétées à la main **à partir de sources citées** |

## 2. Glissant ou calendaire : deux usages, deux chiffres

- Le SLO de Pyrra est **glissant** (30 jours) : il sert à piloter (alertes de consommation du budget, décision de reporter un changement). Il n'exclut pas les maintenances.
- Le chiffre du contrat est **calendaire** (mois de Paris) et **exclut** les maintenances conformes : il est calculé une fois, après la fin du mois, par `ms-rapport-client`, sur les données brutes de Thanos (30 jours de données brutes, comptés depuis le moment du calcul : le rapport est produit **le 1er à 06:15**, et toute heure du mois de plus de 30 jours n'existe plus qu'en données sous-échantillonnées à 5 min. Un mois de 31 jours dépasse déjà la rétention de près de 31 h au moment du rapport : rétention brute de Thanos portée à **35 jours** (MR `plateforme/observabilite`) ; un rapport refait plus tard est marqué « recalculé sur données sous-échantillonnées »).
- Les deux peuvent diverger : un mois avec une maintenance conforme de 2 h a un SLO glissant à 99,7 % et une disponibilité contractuelle à 100 %.

## 3. Ce que la mesure ne règle pas

- **ENF-07 et le RPO** (R-11) : un rendez-vous confirmé pendant les 15 dernières minutes avant un sinistre peut manquer à PAR2. Il n'est pas perdu pour autant : le DPI le connaît (rapprochement toutes les 5 min, R-01) et le patient a reçu une confirmation. Procédure de reprise : rejouer depuis le DPI les rendez-vous de la fenêtre perdue (liste exportée par le DPI), avant de rouvrir la prise en ligne. À valider avec le GHSV (question au comité de suivi).
- **La sonde du GHSV** (R-09) : quand elle existe, ses mesures sont ajoutées au rapport en regard des nôtres ; un écart > 0,05 point déclenche une analyse commune.
- **Les jours fériés** (ENF-04) ne sont pas retirés des jours ouvrés par l'outil (calendrier à ajouter) : tant que ce n'est pas fait, une annonce faite juste avant un pont est jugée conforme alors qu'elle ne l'est pas. Risque connu.

## 4. Alertes

| SLO | Consommation rapide | Destinataires |
|---|---|---|
| `ghsv-disponibilite-sonde` | critique (astreinte) | astreinte, `ghsv@medisphere.internal` |
| `ghsv-disponibilite` | critique | idem |
| `ghsv-latence` | critique pour la consommation la plus rapide, sinon avertissement | équipe MédiAgenda, `ghsv@` |

Routage : AlertmanagerConfig du locataire (étiquette `equipe="ghsv"`, rendu de `plateforme/equipes`) + route d'astreinte globale pour `gravite="critique"`.
