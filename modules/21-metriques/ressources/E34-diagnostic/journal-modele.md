# Journal de diagnostic — INC-4834 (M21-E34)

> Modèle à recopier dans `plateforme/medisphere`, `docs/kubernetes/journal/<AAAA-MM-JJ>-M21-E34-inc-4834.md`.
> Règle du jour : **les métriques seulement** (Grafana, Thanos Query sur 10.10.41.60, Alertmanager, Pyrra).
> Chaque affirmation est prouvée par une requête PromQL **copiée telle quelle** et par sa valeur.

| | |
|---|---|
| Début du chronomètre (T0) | `hh:mm` |
| Fin (T1) | `hh:mm` |
| Environnement | `mediagenda-recette` |

## 1. Symptôme, chiffré

Ce que vivent les testeurs, en nombres : latence (p50, p95), taux d'erreurs (par code), débit, depuis quand.

| Mesure | Requête | Avant | Pendant |
|---|---|---|---|
| | | | |

## 2. Chronologie

| Heure | Ce que j'ai regardé (requête, tableau) | Ce que j'ai vu | Ce que j'en conclus (hypothèse retenue ou écartée) |
|---|---|---|---|
| | | | |

## 3. Hypothèses écartées

Une ligne par hypothèse, avec la requête qui l'écarte.

## 4. Cause racine

Une phrase. Puis la ou les requêtes qui la prouvent, et pourquoi elles suffisent.

## 5. Action

Ce que tu fais (ou proposes) pour rétablir le service, et la mesure qui montre le retour à la normale.

## 6. Prévention

Ce qui aurait dû alerter plus tôt ou empêcher l'incident (alerte, limite, quota, tableau de bord, règle d'exploitation), avec le ticket à ouvrir.

## 7. Retour sur l'exercice

Durée réelle, ce qui t'a fait perdre du temps, la requête que tu aurais aimé avoir déjà enregistrée.
