# Synthèse pour la direction du GHSV

**Objet** : réponse de MédiSphère à la consultation GHSV-DSI-2026-014 (prise de rendez-vous en ligne). Deux pages.

## Ce que le GHSV obtient

Une prise de rendez-vous en ligne aux couleurs et sous le nom du groupement, pour les patients et pour les secrétariats, raccordée au dossier patient (DPI) et à l'annuaire du groupement. Les secrétaires se connectent avec **leur** compte du groupement : aucun mot de passe de plus, et une personne qui quitte le groupement perd l'accès en moins de 15 minutes. Les patients reçoivent un rappel deux jours avant leur rendez-vous s'ils l'ont demandé.

Le service est hébergé par MédiSphère, en France, dans deux salles distinctes, par l'équipe qui développe l'application. Les données de santé du groupement restent dans l'Espace économique européen, chiffrées avec des clés qui lui sont réservées.

## Nos engagements, et ce qui les garantit

| Engagement | Ce que cela veut dire pour le groupement | Ce qui le garantit |
|---|---|---|
| Disponibilité de **99,9 %** par mois | au plus 40 à 45 minutes d'interruption non programmée par mois (selon la longueur du mois) | sondes indépendantes toutes les 30 secondes, calcul publié chaque mois, méthode validée en comité de suivi |
| Temps de réponse : 95 % des demandes en moins de 0,3 seconde | l'attente ne se voit pas | mesure permanente, publiée dans le rapport mensuel |
| Reprise en **4 heures** (RTO) si une salle est détruite | le service revient sur la seconde salle dans la matinée | exercice réel réalisé en 2026, test annuel en présence du groupement |
| Perte de données de **15 minutes** au plus (RPO) | les rendez-vous des 15 dernières minutes avant un sinistre sont repris depuis le DPI | réplication continue mesurée minute par minute |
| Rapport mensuel avant le 10 | une page de chiffres vérifiables : disponibilité, incidents, capacité | rapport produit automatiquement, aucun chiffre saisi à la main |
| Réversibilité | en fin de contrat, toutes vos données en format ouvert sous 30 jours, puis leur destruction prouvée | export déjà testé sur la maquette, essai chaque année |

Ces engagements ont été **mesurés** sur une maquette de la plateforme pendant la préparation de l'offre ; deux restent à confirmer avant la mise en service (capacité réelle de la pointe du lundi matin, identité pendant une reprise sur la seconde salle) et sont inscrits au planning.

## Le coût sur cinq ans

Coût complet estimé : **≈ 1,9 million d'euros HT sur cinq ans** (≈ 0,53 M€ la première année, mise en service comprise, puis ≈ 0,33 M€ par an). Ordres de grandeur d'octobre 2026, hypothèses détaillées dans le chiffrage, **à confirmer par devis** : ce ne sont pas des prix contractuels. La moitié environ est du travail humain (exploitation 24 h/24, astreinte, sécurité, évolutions), un septième les SMS de rappel ; le matériel ne pèse que quelques pour cent.

## Les trois risques principaux

1. **Délai de démarrage** : si le marché est notifié tard, le 1er mars 2027 est serré. Nous engageons dès janvier, à nos risques, les travaux communs à tous les scénarios, et nous demandons au groupement une solution de secours avec son prestataire actuel.
2. **Pointe du lundi matin** : notre maquette ne peut pas reproduire 150 demandes par seconde. Une campagne de charge en préproduction (avril 2027) la vérifiera avant le premier établissement ; nos serveurs sont dimensionnés avec une marge écrite.
3. **Reprise sur la seconde salle** : l'authentification des secrétaires et du DPI n'y est pas encore reproduite. Elle le sera avant la mise en service (chiffrée dans l'offre) ; d'ici là, la reprise des données est prouvée, celle des connexions ne l'est pas.

## Calendrier jusqu'au 1er mars 2027

| Date | Étape |
|---|---|
| fin janvier 2027 | notification ; lancement ; demande des éléments du groupement |
| février 2027 | raccordement à l'annuaire et au DPI en recette ; reprise des données à blanc |
| 1er mars 2027 | cinq établissements en service (GHSV-01 à 05) |
| mars à juin 2027 | sept établissements par vagues, jusqu'au 30 juin |

## Ce que le groupement doit fournir

- Un accès à son annuaire (client OIDC, groupes des secrétariats, compte de test) avant le **1er février 2027**.
- Le nom de domaine du service et sa délégation, l'environnement de recette du DPI.
- L'export de l'outil actuel (extrait anonymisé dès la notification, export complet à J−15).
- Un représentant aux comités de suivi mensuels et au test annuel de reprise.
