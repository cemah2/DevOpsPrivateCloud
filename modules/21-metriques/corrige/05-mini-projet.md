# Module 21 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

### M21-E46 — Mini-projet : la supervision de MédiSphère v1

Il n'y a pas de solution unique : ce corrigé donne un **plan de travail** éprouvé, les points de contrôle de chaque étape, la préparation des démonstrations et la **grille de revue** avec laquelle Claire, Karim, Sophie, Nadia et Julien évaluent la livraison. Les fichiers de référence sont ceux des exercices du module ; le nouveau est le modèle de fiche de livraison [`supervision-v1.md`](fichiers/M21-E46/medisphere/docs/observabilite/metriques/supervision-v1.md).

**Solution**

*Plan de travail recommandé* (on prouve d'abord, on nettoie ensuite, on documente à la fin)

1. **État des lieux** (1 h) : `lab/bin/check 21 46`, puis `lab/bin/check 21 43` (tout le palier 4) et les contrôles détaillés rouges. Inventaire des restes : `ls ~/.local/state/workbook/pannes-actives/` ; `amtool silence query` ; `kubectl -n wb-pannes get configmap temoin-etat -o jsonpath='{.data.etat\.json}'` ; objets non suivis dans les espaces gérés (`kubectl get cnp -A`, Applications avec ressources orphelines dans Argo CD) ; VMs 2210-2219 (`pvesh get /cluster/resources --type vm`).
2. **Démonstrations, répétition** (2 h) : voir plus bas. Faites **avant** le nettoyage : si quelque chose ne revient pas, tu as le temps.
3. **Couverture** (2 h) : `count by (job) (up)` contre le tableau « Collecte » de l'énoncé ; pour chaque manque, l'exercice qui le traite (E08, E10, E12, E20…). Une expression `CibleDisparue` par job attendu (M21-E35). Étiquettes `equipe`, `site`, `environnement` (M21-E13).
4. **Alertes** (2 h) : script de revue (toutes les alertes chargées : gravité, équipe, `runbook_url` qui répond en 200 dans GitLab) ; essais de routage et d'inhibition couvrant chaque route et chaque inhibition ; bruit d'une semaine : `topk(10, sum by (alertname) (changes(ALERTS{alertstate="firing"}[7d])))` et les courriels de Mailpit ; chaque alerte bruyante corrigée ou justifiée dans la politique d'alerte.
5. **Données personnelles** (30 min) : recherche d'étiquettes suspectes sur la vue globale (`/api/v1/labels`, puis valeurs de celles qui ressemblent à `*mail*`, `*user*`, `*utilisateur*`, `*patient*`, `*_id`), consignée dans la fiche ; liste d'étiquettes interdites dans la politique et contrôle de CI (M21-E38).
6. **Historique** (30 min) : requête sur toute la période (`count_over_time(up{job="vms"}[1d])` en graphe sur 60 jours, résolution 1 h) sans trou ni avertissement ; `thanos tools bucket inspect` (lecture) consigné ; Compactor unique et non arrêté.
7. **Nettoyage** (1 h) : pannes closes (`--annuler`), silences expirés, essais témoins à zéro, API d'administration fermées, objets manuels retirés et reportés dans le code.
8. **Documentation et livraison** (2 à 3 h) : `supervision-v1.md`, ADR-0210, politiques, RB-210 à RB-219, matrice des flux ; MR, pipelines verts, étiquette `metriques-v1`.

*Démonstration de Nadia — l'Alertmanager du cluster s'arrête* (à répéter **avant** la revue, en heures ouvrées, Nadia prévenue)

| Étape | Action | Attendu |
|---|---|---|
| 1 | Ticket `CHG-` ; MR qui met `alertmanager.alertmanagerSpec.replicas: 0` (procédure d'essai de M21-E28 : pas de `kubectl scale`, l'opérateur et Argo CD remettraient l'état de Git) | MR relue, fusionnée, Argo CD synchronisé ; pods `alertmanager-kps-*` arrêtés |
| 2 | Chronomètre ; sur `mon01`, suivre les sondes du témoin (`curl localhost:9090/api/v1/alerts`) | `SupervisionClusterComposantKO` (sonde de 10.10.41.61) puis courriel du **témoin** dans `astreinte@` |
| 3 | Bilan du délai : `for` de la règle du témoin + `group_wait` de son Alertmanager + collecte | dans le délai écrit dans la politique d'alerte (ordre de grandeur : 6 à 8 minutes) |
| 4 | `git revert` de la MR (nouvelle MR), synchronisation | Alertmanager revenu ; les alertes du cluster restées actives sont notifiées à la reprise ; courriel de résolution du témoin |
| 5 | Questions à préparer | Que se passe-t-il pour les alertes nées pendant la coupure ? (Prometheus les renvoie à chaque évaluation : elles partent à la reprise.) Qui aurait prévenu si `mon01` était tombé en même temps ? (Personne : limite assumée, écrite dans la fiche.) |

*Démonstration de Julien — un canary défaillant interrompu* : une image de MédiAgenda (étiquette d'essai `vX.Y.Z-defaut`, signée comme les autres, poussée par la CI) qui renvoie des 5xx sur une partie des requêtes (variable d'environnement de l'application ou version volontairement cassée, selon ce que ton code de MédiAgenda permet) ; MR de promotion en recette (M20) ; trafic généré pendant l'analyse (Job `oha` de M21-E23) ; `kubectl argo rollouts get rollout mediagenda -n mediagenda-recette --watch` : l'AnalysisRun `taux-erreur-mediagenda` échoue, le Rollout passe en `Degraded` et revient à la version stable ; puis `git revert` de la promotion. À montrer dans Grafana : le taux d'erreurs de la révision canary (étiquette `rollouts_pod_template_hash`, M21-E07) et le retour à zéro.

*Rapport de Claire* : la disponibilité de MédiAgenda sur 28 jours lue dans Pyrra (`slo.apps.par1.medisphere.internal`), dans le tableau SLO de Grafana, et recalculée à la main :

```
1 - (
  sum(increase(http_requests_total{job="mediagenda", namespace="mediagenda-prod", code=~"5.."}[28d]))
  / sum(increase(http_requests_total{job="mediagenda", namespace="mediagenda-prod"}[28d]))
)
```

(adapte le nom de la métrique et le sélecteur à la définition de ton SLO, M21-E26). Les trois chiffres doivent concorder à l'arrondi près ; un écart s'explique (fenêtre glissante contre calendaire, requêtes de sondes exclues ou non, recording rules de Pyrra contre requête brute sur des données sous-échantillonnées : sur 28 jours, Thanos peut servir du 5 min si la requête le permet).

*Ajout d'une cible par Karim* : il choisit une VM ou un service (par exemple le récurseur de `dns02`) ; tu montres le chemin complet par le code : inventaire NetBox ou ScrapeConfig, flux (matrice et rôle `pare_feu`), MR, synchronisation, cible `up`, alerte de disparition, ligne dans `supervision-v1.md`. Temps attendu : moins de 30 minutes.

*Grille de revue* (ce que chaque relecteur regarde)

| Relecteur | Points | Attendu |
|---|---|---|
| Karim | `plateforme/observabilite`, `plateforme/ansible`, `…/deploiement`, `plateforme/gitops` | MR lisibles ; aucune configuration hors code ; versions épinglées (charts recopiés et signés) ; tests de règles, essais de routage et d'inhibition, contrôles de tableaux en CI ; ajout d'une cible en moins de 30 min |
| Sophie | sécurité de la pile, données | points d'entrée filtrés (MGMT et `mon01`), Grafana durci, Secrets hors Git et recréés depuis Vault, API d'administration fermées, **aucune donnée personnelle dans les métriques** (recherche consignée), étiquettes interdites contrôlées |
| Nadia | alertes, astreinte, témoin | démonstration réussie dans le délai écrit ; chaque alerte critique a un runbook utilisable à 4 h du matin ; bruit d'une semaine mesuré ; le témoin dit quand il ne voit plus (alertes sur lui-même) |
| Julien | équipes, livraison | ServiceMonitor et règles d'équipe validés par la CI de son dépôt ; canary interrompu par l'analyse ; tableaux RED de son équipe dans son dossier |
| Claire | ensemble | rapport SLO concordant ; limites assumées et écrites (un hyperviseur, `mon01` partagé, courriel seulement, pas de journaux ni de traces, pas de SSO) ; feuille de route vers M22 (Loki), M23 (traces, *remote write*), M24 (SSO de Grafana), M25 (secrets) |

**Explications**

Le contrôle global ne remplace pas les contrôles détaillés : il vérifie l'**état de livraison** (couverture, absence de provisoire, documentation, étiquette) et rejoue les contrôles qui cassent le plus souvent en silence. Les démonstrations portent sur ce qu'aucun contrôle automatique ne prouve : qu'un humain est réellement prévenu, à temps, par un chemin qui ne dépend pas de ce qui est en panne.

**Alternatives**

Démonstration de Nadia par une coupure plus brutale (politique réseau qui isole Alertmanager) : plus réaliste pour une panne réseau, mais l'essai du M21-E28 par le code a l'avantage d'être tracé, relu et défait par `git revert`. Rapport SLO produit par un tableau Grafana exporté en PDF plutôt que lu à l'écran : l'Image Renderer est supprimé de Grafana 13 (annexe des versions) ; un export par l'API de Pyrra ou une requête PromQL consignée est plus simple.

**Pièges classiques**
- Faire les démonstrations après le nettoyage, puis découvrir que le canary ou le témoin ne marchent plus.
- Arrêter l'Alertmanager par `kubectl scale` : l'opérateur le relance en quelques secondes, la démonstration ne prouve rien.
- Oublier de défaire l'essai (Alertmanager à 0 réplica en production pendant la nuit).
- Laisser un silence « de démonstration » de 30 jours.
- Poser l'étiquette `metriques-v1` avant que les pipelines de `main` soient verts.

**En production chez MédiSphère**

La livraison `metriques-v1` devient la référence des changements suivants (fiches `CHG-22xx`) ; l'essai de bout en bout de la chaîne d'alerte devient hebdomadaire et automatique ; la revue mensuelle du bruit entre dans le rituel de l'équipe ; chaque nouvelle brique de la plateforme (M22 et suivants) arrive avec son ServiceMonitor, son alerte de disparition et son runbook, sinon elle n'est pas en production.
