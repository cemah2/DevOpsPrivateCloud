# Post-mortem INC-5523 — Le locataire MédiDoc a saturé un travailleur

> Modèle de corrigé (M28-E23) : chronologie et chiffres à remplacer par les tiens. Sans reproche : on décrit des systèmes et des décisions, pas des fautes.

| | |
|---|---|
| Date | <AAAA-MM-JJ> |
| Durée | <HH:MM> → <HH:MM> |
| Gravité | P2 (recette dégradée, production intacte) |
| Rédaction | <MOI>, relu par Karim Benali et Nadia Roussel |

## Résumé
Un traitement par lots de MédiDoc (`medidoc-indexation`), lancé à la main dans `medidoc-dev` avec des `requests` **à zéro**, juste après que les garde-fous de l'espace eurent été desserrés (LimitRange supprimée, quota relevé), a occupé le CPU d'un travailleur que l'ordonnanceur croyait libre ; ses conteneurs ont été tués par manque de mémoire en boucle et la recette des autres équipes a ralenti.

## Chronologie
| Heure | Événement |
|---|---|
| <09:03> | commit de Lucas dans `plateforme/k8s` (`espaces/medidoc-dev/`) : LimitRange de `medidoc-dev` retirée, quota relevé (« pour le lot d'indexation »), appliqué au cluster |
| <09:05> | lot `medidoc-indexation` créé à la main (`kubectl apply`), requests `0`, classe `medisphere-lot` |
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
2. Les `requests` sont exigées (Kyverno `exiger-limites`, M26) mais seulement **présentes** : une valeur nulle passe ; la LimitRange d'origine n'avait pas de minimum (ses valeurs par défaut ne s'appliquent qu'aux requests absentes).
3. Pas d'alerte « pods aux requests absentes ou nulles » ni « CPU d'un nœud volé par un seul locataire ».

## Ce qui a bien marché
Tableau de capacité, journal d'incident tenu, endiguement réversible.

## Actions
| Action | Propriétaire | Échéance |
|---|---|---|
| `CODEOWNERS` : `espaces/` et `locataires/` relus par la Plateforme | Karim Benali | <date> |
| `exiger-limites` : requests strictement positives ; `min` dans les LimitRange des espaces des locataires | <MOI> | <date> |
| Alerte « pods aux requests absentes ou nulles » et « part CPU d'un locataire sur un nœud > 60 % » | <MOI> | <date> |
| Guide d'accueil : traitements par lots en `medisphere-lot` | Julien Petit | <date> |
