# RB-328 — Rapport mensuel de refacturation interne (showback) par locataire

*Propriétaire : équipe Plateforme. Destinataires : Claire Morel, responsables d'équipe (Inès Garnier, Hugo Bernard, Julien Petit). Version F2-S08 (PLAT-3208). Rythme : le 2 de chaque mois.*

## Principe

- **Showback**, pas chargeback : chaque équipe voit ce qu'elle mobilise et ce que cela coûterait ; aucune écriture comptable. Passer au chargeback est une décision de la direction (budget par équipe), pas de la plateforme.
- **Ce qui est compté** : par locataire Capsule (étiquette `capsule.clastix.io/tenant` des espaces), la moyenne du mois de `locataire:cpu_facture:max` et `locataire:memoire_facturee:max` (le plus grand de *réservé* et *utilisé* : on paie ce qu'on bloque, et ce qu'on prend en rafale au-delà), et de `locataire:stockage_demande:somme` (PVC). Règles : `plateforme/observabilite`, `regles/enregistrement-locataires.yaml`.
- **Ce qui n'est pas compté** (dit dans le rapport) : les espaces hors locataire (plateforme, supervision, CI), le stockage objet (RGW, s3-01 : ajouté à la main depuis `radosgw-admin bucket stats` tant qu'il n'y a pas de métrique par compartiment), le réseau, les VMs du socle. Le coût de la plateforme est réparti dans les tarifs unitaires.
- **Tarifs** : `plateforme/outils`, `showback/tarifs.yaml`, validés par Claire une fois par an.

## Produire le rapport

1. Le tableau Grafana « Consommation par locataire » (`plateforme-consommation-locataires`), période « mois précédent » : vérifier qu'aucun locataire n'a de trou (Prometheus arrêté, règle absente) et noter les faits marquants (pic, quota atteint).
2. Depuis `adm01`, dans le clone de `plateforme/outils` :
   ```
   admin@adm01:~/src/outils$ bin/ms-showback --mois <AAAA-MM> > ~/medisphere/docs/accueil/mesures/refacturation-<AAAA-MM>.md
   ```
   (`--partiel` pour le mois en cours, `--json` pour comparer deux mois.)
3. Compléter le fichier : stockage objet par compartiment, commentaires (requests surdimensionnées : rapport *réservé/utilisé* du tableau, recommandations du VPA), actions proposées à chaque équipe.
4. MR sur `plateforme/medisphere`, relue par Claire ; un message aux responsables d'équipe avec le lien.

## Lire et agir

| Constat | Ce qu'on propose à l'équipe |
|---|---|
| réservé ≫ utilisé (efficacité < 30 %) | baisser les requests (recommandations VPA, M28) : l'équipe paie moins et libère de la place |
| utilisé > réservé régulièrement | relever les requests : le pod vit sur la place des autres et sera évincé le premier |
| quota à plus de 80 % | revoir le quota avec la plateforme (bilan de capacité des travailleurs, S02) |
| stockage demandé ≫ utilisé | réduire à la prochaine recréation (un PVC ne rétrécit pas) |

## Contrôle

`lab/bin/check F2 8` ; le rapport du mois existe et cite chaque locataire accueilli.
