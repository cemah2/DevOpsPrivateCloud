# Journée de jeu — répétition de la démonstration au GHSV (<AAAA-MM-JJ>)

> F7-S11 (PLAT-3711). Modèle de compte rendu (convention du M29 : `docs/qualite/journees-de-jeu/`). Meneur : Karim Benali ; équipe : `<MOI>` ; observatrice : Nadia Roussel. Sans recherche de coupable : les causes sont des mécanismes.

## 1. Cadre

| | |
|---|---|
| Cible | `ghsv-prod` (production de démonstration, données fictives) |
| Charge | `TestRun` `demo-ghsv`, `testid=demo-ghsv-<AAAAMMJJ>`, `<TAUX>` itérations/s (≈ `<5 × TAUX>` req/s), parcours du DPI |
| Instruments | SLO `ghsv-*` (Pyrra), sondes `client-ghsv*` de `mon01`, tableau `f4-changement-en-cours`, événements Keycloak, Mailpit (`support@`) |
| Injection | `lab/bin/break F7 11` (variante `<N>`, tirée au hasard) |
| Fenêtre | `<HH:MM>` → `<HH:MM>` (heure de Paris) |

## 2. Chronologie

| Heure | Événement | Source | Qui |
|---|---|---|---|
| `<HH:MM:SS>` | début de la charge | k6 | |
| `<HH:MM:SS>` | incident 1 injecté | meneur | |
| `<HH:MM:SS>` | **détection** : `<alerte, sonde, courriel, tableau>` | | |
| `<HH:MM:SS>` | annonce au GHSV : « `<texte>` » | | |
| `<HH:MM:SS>` | cause identifiée : `<mécanisme>` | | |
| `<HH:MM:SS>` | réparation (`<MR, sync Argo CD, apply>`) | | |
| `<HH:MM:SS>` | retour à la normale constaté (sonde verte, charge sans erreur) | | |
| … | incidents 2 et 3 | | |

## 3. Ce qu'a vu chaque utilisateur

| Incident | Patient / DPI | Agents | Détecté par | Délai de détection | Durée |
|---|---|---|---|---|---|
| 1 `<nom>` | | | | | |
| 2 | | | | | |
| 3 | | | | | |

## 4. Indisponibilité mesurée

Secondes d'erreur de la sonde vue du client sur la fenêtre (même calcul que le rapport mensuel) :

```promql
avg_over_time(max(1 - probe_success{job="blackbox", groupe=~"client-ghsv.*"})[<D>s:15s]) * <D>
```

| Mesure | Valeur |
|---|---|
| Indisponibilité vue par les sondes | `<S>` s |
| Requêtes de la charge en erreur / envoyées | `<E>` / `<N>` |
| Budget d'erreur consommé (`ghsv-disponibilite-sonde`, 30 j ≈ 43 min) | `<P>` % |
| Effet sur le rapport du mois s'il s'agissait de la vraie production | `<99,9xx>` % au lieu de `<…>` |

Ce que la sonde ne voit pas : l'incident d'identité (403 des agents) ne touche ni `/pret` ni l'opération sondée ; il ne compte pas dans la disponibilité de la « prise de rendez-vous » au sens d'ENF-03, mais il compte pour les secrétariats. Décision : ajouter une sonde synthétique de connexion d'agent (compte de test du GHSV) — action A-2.

## 5. Ce qui a bien marché, ce qui a coûté

- `<…>`

## 6. Actions

| ID | Action | Responsable | Échéance |
|---|---|---|---|
| A-1 | Politique Kyverno : refuser toute CiliumNetworkPolicy avec `egressDeny` hors du dépôt (modification en direct) | Karim | |
| A-2 | Sonde de connexion d'un agent de test (MFA par TOTP de test) | `<MOI>` | |
| A-3 | `/pret` ne doit pas dépendre du cache (Valkey est un cache : sa perte dégrade, ne casse pas — M27) : correctif de `mediagenda/api` | Julien | |
| A-4 | Alerte « Application de production OutOfSync depuis 15 min » pour les espaces des clients | Nadia | |
