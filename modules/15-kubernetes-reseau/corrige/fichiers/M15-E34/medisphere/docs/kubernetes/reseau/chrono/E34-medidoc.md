# Chrono M15-E34 — Publication de MédiDoc dans `medidoc-dev` (DEV-1634)

## Feuille de temps (exemple d'un passage réussi : remplace par la tienne)

| Jalon | Heure | Écart | Gestes manuels (commande, raison) |
|---|---|---|---|
| T0 — dossier ouvert | 14:00 | — | — |
| T1 — application prête | 14:17 | 17 min | aucun (Secret et ConfigMap par `task medidoc:secrets`, créée pendant le chrono : 6 min) |
| T2 — route acceptée, nom publié | 14:26 | 9 min | `kubectl get httproute -n medidoc-dev medidoc -o yaml` (constat : `NotAllowedByListeners`, label d'exposition oublié) |
| T3 — HTTPS, politiques, document relu | 14:44 | 18 min | `hubble observe -n medidoc-dev --verdict DROPPED` (constat : sortie vers `s3-01` refusée avant la règle FQDN) |
| T4 — check vert, documentation | 14:53 | 9 min | — |

Total : 53 minutes.

## Retour d'expérience

- Ce qui a coûté : écrire la tâche de création des Secrets (n'existait pas) ; oublier le label d'exposition de l'espace
  (la route était `Accepted: False`, raison `NotAllowedByListeners`) ; la règle de sortie vers `s3-01` (adresse en dur
  d'abord, puis par nom).
- À outiller : un **modèle** d'application dans `plateforme/k8s` (`applications/_modele/` : Service, HTTPRoute avec les
  en-têtes de E33, politiques de base), une tâche `task application:secrets APP=…` qui lit Vault, et la case « label
  d'exposition » dans le modèle d'espace.
- Pour que l'équipe le fasse seule : droits limités sur `HTTPRoute` dans son espace, contrôle d'admission du nom d'hôte
  (`<espace>.apps…` seulement, module 26), GitOps (module 20) pour que la MR suffise.
