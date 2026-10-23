# Réponse à DEV-3209 — « Accès en lecture à la base de prod » (Hugo Bernard, équipe Data)

*Rédigée par : équipe Plateforme, avec Sophie Laurent (RSSI). Relue par : Julien Petit (responsable de la donnée MédiAgenda), Claire Morel. Date : <DATE>. Décision : **refus de l'accès demandé, alternative fournie**.*

## 1. Ce que tu demandes, et ce dont tu as besoin

Tu demandes un compte en lecture sur `mediagenda-db` en production pour produire les statistiques d'activité demandées par la direction (volumes, délais de réservation, répartition par praticien et par canal de rappel). Ce dont tu as besoin, c'est **des données de rendez-vous à jour chaque matin, dans une base où tu peux écrire tes propres tables et requêtes**. Ce n'est pas la même chose, et c'est ce second besoin que nous couvrons.

## 2. Pourquoi nous refusons l'accès direct

1. **HDS.** La table `rendez_vous` contient des données de santé à caractère personnel (nom du patient, motif en texte libre, contact de rappel). Notre certification HDS et ISO 27001 nous engage à n'en donner l'accès qu'aux personnes dont la mission l'exige, nominativement, et à le tracer. Une analyse statistique n'exige pas de savoir *qui* a pris rendez-vous ni *pourquoi*.
2. **RGPD, minimisation (art. 5.1.c) et finalité (art. 5.1.b).** Les données ont été collectées pour gérer des rendez-vous. Les réutiliser à des fins statistiques est compatible (art. 89) **à condition** de mettre en place des garanties, au premier rang desquelles la pseudonymisation et la minimisation : ne traiter que les colonnes nécessaires, sous une forme qui ne désigne plus directement la personne.
3. **Sécurité et disponibilité de la production.** Une requête d'analyse sur la base qui sert les patients prend de la mémoire, des E/S et peut tenir des verrous ou provoquer des annulations ; un compte de plus sur la prod, c'est une surface d'attaque de plus et un accès à révoquer le jour où tu changes de poste.
4. **Principe de la plateforme.** Aucune équipe n'accède à la base d'une autre équipe : les données passent par une interface décidée par leur responsable (ici Julien).

## 3. Ce que nous te proposons (disponible dès maintenant)

- Une **base PostgreSQL à toi**, `statistiques-db`, dans l'espace `data-traitements` (libre-service, sauvegardée chaque nuit).
- Chaque nuit, une **extraction pseudonymisée** des rendez-vous des 13 derniers mois, chargée dans `stats.rendez_vous` : identifiants du rendez-vous, du patient et du praticien remplacés par des pseudonymes stables (HMAC), jour, heure, jour de la semaine, durée, canal de rappel, délai de réservation. Ni nom, ni motif, ni coordonnées, ni horodatage exact. (ADR-0327, RB-327.)
- Des **identifiants personnels et temporaires** pour tes analyses : `bao read db-data/creds/data-analyste` après connexion OIDC (8 h), puis `kubectl port-forward` vers `statistiques-db-ro`.
- Des **traitements par lots** à toi (CronJobs en classe `medisphere-lot`) et un compartiment `data-resultats` pour publier tes résultats agrégés.

Ce qui ne sort pas et pourquoi : le motif (texte libre : on y trouve des pathologies et parfois des noms) ; le contact de rappel ; l'heure à la minute. Si une statistique future en a besoin (par exemple une classification des motifs), la demande passe par Julien et Sophie : une nouvelle colonne **dérivée** (catégorie, jamais le texte) sera ajoutée à la vue par une migration de MédiAgenda.

**Règles d'usage** que tu acceptes en utilisant ces données : pas de tentative de ré-identification ; aucun résultat publié hors MédiSphère portant sur moins de 10 rendez-vous ; pas de copie hors de `data-traitements` et `data-resultats` ; conservation 13 mois.

## 4. Conditions d'un accès exceptionnel à la production

Un accès direct en lecture peut être accordé **exceptionnellement**, si et seulement si :

| Condition | Détail |
|---|---|
| Motif | un besoin que l'extraction ne peut pas couvrir (enquête sur une anomalie de données, demande d'une autorité), écrit dans un ticket `SEC-` |
| Validation | Sophie Laurent (RSSI) **et** Julien Petit (responsable de la donnée), par écrit dans le ticket |
| Périmètre | lecture seule, sur le **réplica de secours** ou une restauration ponctuelle (jamais le primaire), limité aux colonnes et lignes nécessaires (vue dédiée) |
| Durée | compte nominatif à **expiration automatique** (`VALID UNTIL`, rôle géré par CloudNativePG, comme l'accès de Lucas au M27), 5 jours ouvrés au plus |
| Authentification | depuis `adm01`, après SSO et OTP ; aucune copie des données hors de la session |
| Traçabilité | journalisation des requêtes du compte (`log_statement = 'all'` pour ce rôle), journal envoyé au locataire `audit` de Loki ; compte rendu dans le ticket à la clôture |
| Clôture | rôle passé à `ensure: absent`, revue d'accès du mois suivant |

## 5. Prochaines étapes

- Aujourd'hui : accès à `statistiques-db` ouvert pour toi et Sarah (groupe `data`) ; premier chargement disponible demain matin.
- Sous une semaine : point avec toi pour vérifier que les colonnes couvrent les indicateurs demandés par la direction ; s'il en manque, nous ouvrons la demande de colonne dérivée avec Julien.

Merci d'avoir posé la question plutôt que de chercher un contournement : c'est exactement ce que la plateforme attend.

— Équipe Plateforme, pour Sophie Laurent (RSSI)
