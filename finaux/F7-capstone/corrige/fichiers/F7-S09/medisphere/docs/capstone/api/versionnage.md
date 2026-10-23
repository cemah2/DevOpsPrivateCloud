# Versionnage et dépréciation des API exposées aux clients

> F7-S09 (DEV-3709). S'applique à toute API de MédiSphère consommée par un client sous contrat (aujourd'hui : l'API de rendez-vous du GHSV). Procédure : RB-373. Engagement contractuel de référence : EF-05 du GHSV (rétrocompatibilité pendant le marché ; une v2 coexiste au moins 12 mois avec la v1).

## 1. Ce qui est compatible

Un changement est **compatible** s'il ne casse aucun client qui respecte le contrat en vigueur :
- ajouter une opération, un paramètre **facultatif**, un champ de réponse **facultatif** (le contrat du GHSV dit que le DPI ignore les champs inconnus) ;
- accepter plus (élargir une borne d'entrée, un format) ;
- corriger un défaut pour revenir à ce que dit le contrat (le contrat est la référence, pas l'implémentation).

Est **incompatible** : retirer ou renommer une opération, un paramètre ou un champ ; rendre obligatoire ce qui était facultatif ; resserrer une borne d'entrée ; changer un type, un format, le sens d'un code de réponse ; changer l'authentification ou les portées exigées ; ajouter une valeur à une énumération **de réponse** (un client strict peut la refuser : traitée comme incompatible par défaut, sauf accord écrit du client).

Le job `contrat:compatibilite` (oasdiff) classe automatiquement la plupart de ces cas ; la revue humaine (Julien Petit, Karim Benali) tranche le reste.

## 2. Numérotation

- **Majeure dans le chemin** : `/api/v1`, `/api/v2`. Deux majeures sont servies **en même temps** par la même application (routes distinctes, une couche d'adaptation par version), jamais par deux déploiements.
- **Mineure et corrective dans le document** : `info.version` 1.1.0 (ajouts, par exemple les pièces jointes de la réponse R-06), 1.0.1 (précision sans effet). Une mineure ne change pas le chemin.
- Chaque version servie a **son** fichier de contrat dans `mediagenda/api/contrats/<client>/` et **ses** tests de contrat : tant qu'une version est servie, ses tests tournent sur chaque MR.

## 3. Coexistence et dépréciation d'une majeure

| Étape | Délai | Ce qui se passe |
|---|---|---|
| Annonce de la v2 | J − 3 mois au moins | comité de suivi (EXP-04) : motif, différences, calendrier ; contrat v2 transmis au client pour ses propres tests |
| v2 en recette | J − 10 jours ouvrés au moins (EXP-06) | le client teste ; la v1 reste identique |
| v2 en production | J | v1 et v2 servies ; la v1 reçoit les en-têtes `Deprecation` et `Sunset` (RFC 9745 et RFC 8594) avec la date de fin, et un lien vers la note de migration |
| Mesure de l'usage | J → fin | trafic par version (`mediagenda_http_requests_total{route=~"/api/v1/.*"}`) dans le rapport mensuel du client |
| Fin de la v1 | J + 12 mois **au moins** (EF-05) et pas avant que le trafic du client sur la v1 soit nul depuis 30 jours, ou un accord écrit | retrait par MR ; tests de contrat v1 retirés dans la même MR |

Un changement incompatible **sans** nouvelle majeure n'est permis que pour corriger une faille de sécurité, avec accord écrit du client et communication immédiate (incident de sécurité, ESC-10).

## 4. Communication au client

- Toute évolution de l'API (même compatible) figure dans le rapport mensuel (« changements réalisés et à venir », EXP-03) et dans la note de version de la recette.
- Une rupture involontaire découverte en production est un **incident** (P2 au moins) : retour arrière de la version, post-mortem, et un test de contrat de plus.

## 5. Ce que vérifie la CI

| Contrôle | Où | Bloquant |
|---|---|---|
| Tests de contrat de chaque version servie (`pytest -m contrat`) | `mediagenda/api`, chaque MR | oui |
| Comparaison des descriptions (`oasdiff breaking`, contrat en référence) | `mediagenda/api`, chaque MR | oui |
| Empreinte des fichiers de contrat (contrat reçu jamais modifié) | `test_contrat_intact` | oui |
| Recette du client : parcours du DPI rejoué (k6, `testid=contrat-ghsv`) après chaque livraison en recette | `plateforme/resilience` | non (alerte) |
