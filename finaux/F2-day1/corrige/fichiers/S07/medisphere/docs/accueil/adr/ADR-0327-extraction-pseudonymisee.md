# ADR-0327 — Données de MédiAgenda pour l'équipe Data : extraction pseudonymisée poussée par MédiAgenda

*Statut : acceptée. Date : <DATE>. Décideurs : Claire Morel, Sophie Laurent (RSSI), Julien Petit (responsable de la donnée MédiAgenda). Consultés : Hugo Bernard (Data), Karim Benali. Ticket : DEV-3207.*

## Contexte

L'équipe Data doit produire chaque mois les statistiques d'activité (volumes de rendez-vous par jour, par praticien, délais de réservation, canaux de rappel). La seule source est la table `rendez_vous` de MédiAgenda : des **données de santé** (HDS), avec le nom du patient, un motif en texte libre et un contact de rappel. Hugo demande « un accès en lecture à la base de prod » (DEV-3209). La plateforme offre des bases PostgreSQL en libre-service (CloudNativePG) dans le locataire `data`.

Contraintes : aucune charge ni verrou sur la base qui sert les patients ; minimisation (RGPD art. 5.1.c) ; pseudonymisation (art. 4.5, 32) ; traçabilité ; l'équipe Data ne doit jamais détenir un moyen d'atteindre les données identifiantes.

## Options étudiées

| Option | Pour | Contre |
|---|---|---|
| A. Accès en lecture de Data à `mediagenda-db` (prod) | immédiat | contraire à HDS et à la minimisation ; charge sur la prod ; tout le schéma visible ; refusé (DEV-3209) |
| B. CronJob **de Data** qui lit des vues pseudonymisées sur le réplica `mediagenda-db-secours` | pas de charge sur la prod ; vues contrôlées par MédiAgenda | Data détient un mot de passe vers une base de santé et un flux réseau vers `mediagenda-secours` (cloison de locataire percée) ; une erreur de droits suffit à exposer la table ; le réplica de secours devient un service de production |
| C. **Job côté MédiAgenda** qui lit les vues sur le réplica et **dépose** un fichier dans un sas S3 que Data lit | aucune liaison Data → MédiAgenda (ni réseau, ni rôle, ni secret) ; le responsable de la donnée décide de ce qui sort ; fichier signé par son empreinte, rejouable, auditable | une pièce de plus (le sas) ; latence d'une nuit ; deux identités S3 à gérer |
| D. Réplication logique d'une publication pseudonymisée vers la base Data | quasi temps réel | une publication ne transforme pas les données (les colonnes publiées sont brutes) ; réplication depuis la prod (pas depuis un réplica physique) ; Data devient abonnée de la prod |

## Décision

**Option C.** La migration Flyway **V5** de `mediagenda/api` crée le schéma `extraction` : une clé de pseudonymisation de 32 octets **générée dans la base** (jamais dans Git ni dans un Secret), lisible par `mediagenda` seul, et la vue `extraction.rendez_vous_pseudo` (identifiants remplacés par HMAC-SHA-256, motif et contact exclus, horodatages tronqués au jour et à la demi-journée, fenêtre de 13 mois). Le rôle `extraction_data` (géré par CloudNativePG en prod, répliqué vers le secours) n'a que `SELECT` sur cette vue. Le CronJob `extraction-data` de `mediagenda-secours` la lit chaque nuit sur le **réplica de secours** et dépose `rendez-vous/AAAA-MM-JJ.csv.gz` et son manifeste (lignes, SHA-256) dans `s3://data-extractions` (s3-01) avec une identité qui ne sait qu'écrire. L'équipe Data charge le fichier dans sa base `statistiques-db` avec une identité qui ne sait que lire.

## Conséquences

- Les pseudonymes restent des **données personnelles** : la base Data a des accès nominatifs (comptes dynamiques d'OpenBao), une durée de conservation (13 mois glissants) et figure au registre des traitements (finalité : statistiques d'activité). Les pseudonymes sont stables d'une nuit à l'autre ; changer la clé les change tous (décision conjointe, RB-327).
- Risque résiduel de **ré-identification** par recoupement : quelqu'un qui connaît son rendez-vous (praticien, jour) retrouve sa ligne, donc son pseudonyme et ses autres rendez-vous. On le réduit par la granularité : l'heure ne sort pas (avec l'index unique praticien + début de V2, praticien + jour + heure désignerait un ou deux rendez-vous), seulement la demi-journée (une dizaine de rendez-vous par praticien : *k* ≈ 10 en moyenne, moins pour un praticien peu actif). Diffusion : pas de publication hors MédiSphère de résultats portant sur moins de 10 rendez-vous (règle de l'équipe Data, rappelée dans son README) ; mesure du *k*-anonymat de l'extraction (plus petit groupe praticien × jour × demi-journée) à faire avant toute nouvelle colonne.
- Le réplica de secours sert une lecture de quelques secondes par nuit : si son rejeu est en retard ou s'il est promu (RB-275), l'extraction s'arrête ou se repointe (RB-327 §5) ; l'extraction ne retarde jamais une reprise.
- Toute nouvelle colonne demandée par Data passe par une **migration de MédiAgenda** relue par Julien et Sophie : c'est voulu.
- Base Data à **une instance** : données reconstructibles depuis le sas (7 jours) et les sauvegardes (`cnpg-data`, 14 jours). À revoir si l'équipe y stocke des résultats non reconstructibles.
- Bases en libre-service : la politique `cnpg-sauvegarde-obligatoire` impose l'archivage, une classe et des limites dans tous les espaces de locataires sauf `dev` et les réplicas.
