# Runbook — MédiVisio consultation

> Service : `medivisio-consultation` (catalogue). Propriétaire : équipe MédiVisio, `medivisio@medisphere.internal` (Inès Garnier, responsable ; Léo Fabre). Astreinte de la plateforme : `astreinte@medisphere.internal` (Nadia Roussel), pour ce qui relève de la plateforme seulement. Version 1 (F2-S05, DEV-3205).

## En un coup d'œil

| | |
|---|---|
| Ce que fait le service | créneaux de téléconsultation et ouverture de salles (liens signés) |
| Dépendances | aucune base ; secret `kv/medivisio/<env>/consultation` (clé des liens de salle) ; Gateway `gw-par1` |
| Production | espace `medivisio-prod`, 2 réplicas, `medisphere-critique`, `https://consultation.apps.par1.medisphere.internal` |
| SLO | 99,5 % de requêtes sans 5xx sur 28 jours (Pyrra : `medivisio-consultation-disponibilite`) |
| Tableau de bord | Grafana, dossier **MédiVisio**, « MédiVisio — consultation » |
| Livraison | Argo CD `medivisio-consultation-prod`, synchronisation manuelle, jamais du vendredi 16 h au lundi 8 h |

## Alerte `ErrorBudgetBurn` (slo=medivisio-consultation-disponibilite)

1. Tableau de bord : taux de 5xx par route, réplicas prêts, dernière synchronisation.
2. Une livraison récente ? Argo CD → historique de `medivisio-consultation-prod`. Si oui : **retour arrière** (ci-dessous) d'abord, diagnostic ensuite.
3. Pods prêts ? `kubectl -n medivisio-prod get pods -l app.kubernetes.io/instance=consultation` (lecture : rôle `view` de l'équipe). `/pret` répond 503 si la clé des salles manque : vérifier `kubectl -n medivisio-prod get externalsecret consultation` (`Ready`).
4. Journaux : Grafana → Explore → Loki, `{namespace="medivisio-prod", app_kubernetes_io_name="consultation"}`.
5. Toujours pas de cause, ou suspicion d'un problème plateforme (Gateway, nœuds, coffre) : appeler l'astreinte avec l'heure de début et ce qui a été vérifié.

## Alerte `SLOMetricAbsent`

Plus aucune requête comptée : service arrêté, ServiceMonitor perdu, ou plus de trafic. Vérifier les pods, puis la cible dans Prometheus (`up{namespace="medivisio-prod", service="consultation"}`). La nuit sans trafic de lab, l'alerte peut être attendue : la noter, ne pas la taire sans décision.

## Retour arrière

1. MR dans `medivisio/consultation-deploiement` qui remet dans `overlays/prod/kustomization.yaml` l'empreinte précédente (historique Git du fichier).
2. Fusion (relecture par un second membre, ou par l'astreinte si personne n'est joignable), puis **Sync** de `medivisio-consultation-prod` dans Argo CD. Pendant la fenêtre interdite : passer par l'astreinte (dérogation, RB-320).
3. Jamais de `kubectl edit`/`rollout undo` à la main : Argo CD le défait, et rien n'est tracé.

## Clé des liens de salle

Rotation : `bao kv put kv/medivisio/prod/consultation cle_salles=<NOUVELLE-CLÉ>` (connexion OIDC), puis attendre le rafraîchissement de l'`ExternalSecret` (15 min) et redémarrer les pods par une MR (annotation de gabarit) : les liens émis avec l'ancienne clé deviennent invalides.

## Contacts et escalade

Équipe d'abord (`medivisio@`), plateforme si la cause est la plateforme (`astreinte@`), sécurité si fuite ou compromission (`securite@`).
