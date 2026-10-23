# Post-mortem INC-5523 — Le locataire MédiDoc a saturé un travailleur

> Modèle de corrigé (M28-E23) : chronologie et chiffres à remplacer par les tiens. Sans reproche : on décrit des systèmes et des décisions, pas des fautes.

| | |
|---|---|
| Date | <AAAA-MM-JJ> |
| Durée | <HH:MM> → <HH:MM> |
| Gravité | P2 (recette dégradée, production intacte) |
| Rédaction | <MOI>, relu par Karim Benali et Nadia Roussel |

## Résumé
Un traitement par lots de MédiDoc, lancé dans `medidoc-dev` sans `requests` et avec des garde-fous retirés la veille (LimitRange supprimé, quota de l'espace relevé), a consommé le CPU d'un travailleur ; ses pods ont été tués par manque de mémoire en boucle et la recette des autres équipes a ralenti.

## Chronologie
| Heure | Événement |
|---|---|
| <J-1 17:40> | commit dans le dépôt du locataire : LimitRange de `medidoc-dev` retiré, quota relevé (« pour l'indexation ») |
| <09:05> | déploiement du lot `medidoc-indexation` |
| <09:20> | alerte de capacité ; plaintes de lenteur en recette |
| <09:32> | charge identifiée (tableau de capacité, `kubectl top`) |
| <09:38> | endiguement : `scale --replicas=0` après accord de l'équipe |
| <10:30> | garde-fous rétablis par MR ; lot relancé avec requests, limites et `medisphere-lot` |

## Impact
Recette de MédiAgenda et MédiNotif ralentie ~30 min ; aucune donnée perdue ; production intacte.

## Détection
Par les plaintes avant l'alerte : l'alerte de capacité a un seuil trop tardif.

## Causes
1. Garde-fous de l'espace (LimitRange, quota) modifiables sans revue de la Plateforme.
2. Rien n'exige des `requests` dans les espaces des locataires.
3. Pas d'alerte « pods sans requests » ni « CPU d'un nœud volé par un seul locataire ».

## Ce qui a bien marché
Tableau de capacité, journal d'incident tenu, endiguement réversible.

## Actions
| Action | Propriétaire | Échéance |
|---|---|---|
| `CODEOWNERS` : `espaces/` et `locataires/` relus par la Plateforme | Karim Benali | <date> |
| ValidatingPolicy Kyverno : `requests` obligatoires dans les espaces des locataires | <MOI> | <date> |
| Alerte « pods sans requests » et « part CPU d'un locataire sur un nœud > 60 % » | <MOI> | <date> |
| Guide d'accueil : traitements par lots en `medisphere-lot` | Julien Petit | <date> |
