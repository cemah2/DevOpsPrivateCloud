# Démonstration de bout en bout en production (M27-E25)

| | |
|---|---|
| Date | 2026-11-24, fenêtre CHG-2825 (10:00-10:30), annoncée à Julien Petit et Nadia Roussel |
| Filet | sauvegarde CNPG `mediagenda-db-20261124095512` (`Completed`), export des définitions de 09:56 |
| Rendez-vous de test | praticien fictif `dr-plateforme` (réservé à la plateforme, aucun agenda réel), patient « Test Plateforme », destinataire factice (MédiNotif simule l'envoi : rien ne part réellement) |

> Exemple du lab de référence : remplace les identifiants et les heures par les tiens.

## Parcours

| Heure (CET) | Étape | Preuve |
|---|---|---|
| 10:04:12.380 | `POST /api/v1/rendez-vous` sur `https://mediagenda.apps.par1.medisphere.internal` → **201**, `id` 18 422 | réponse ; journal `mediagenda.acces` (Loki, locataire `mediagenda`) |
| 10:04:12.391 | transaction validée par le primaire `mediagenda-db-2`, confirmée par `mediagenda-db-3` (`sync_state = quorum`) | `pg_stat_replication` au moment du test |
| 10:04:12.402 | publication confirmée sur l'échange `notifications` (vhost `medinotif-prod`) par `mediagenda-prod` ; `mediagenda_notifications_total{resultat="publiee"}` +1 | journal de MédiAgenda (`notification publiée`, `rendez_vous_id` 18422) |
| 10:04:12.415 | message dans la file quorum `notifications` (leader `rabbitmq-server-1`) | statistiques de la file |
| 10:04:12.471 | consommé et acquitté par `medinotif-7d9c…-x2kq` ; `notification envoyée (simulation)`, `modele` `confirmation`, `rendez_vous_id` 18422, destinataire masqué `**********00` | journal de MédiNotif ; `medinotif_messages_total{resultat="envoye"}` +1 |
| 10:05:03 | `DELETE /api/v1/rendez-vous/18422` → **204** (annulation) ; notification d'annulation suivie de la même façon | journaux |

Délai de bout en bout (création → envoi simulé) : **91 ms**.

## Ce qui reste du test

Une ligne supprimée par l'annulation (aucune donnée de patient réel), deux lignes de journal par application, deux messages acquittés. Rien au rebut. Le praticien `dr-plateforme` est exclu des statistiques de Julien (filtre documenté).
