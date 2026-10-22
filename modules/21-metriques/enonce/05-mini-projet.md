# Module 21 — Palier 5 : Mini-projet

Le module a construit la supervision de MédiSphère, l'a éprouvée, cassée et réparée. Il reste à la **livrer** comme une brique de la plateforme : tout le lab collecté (cluster, socle, Proxmox, Ceph, réseau, applications), des alertes fondées sur les symptômes, testées, routées vers les bonnes personnes et reliées à leurs runbooks, des SLO chiffrés pour les contrats HDS, un historique de deux ans sur le stockage objet, des tableaux de bord versionnés, et un témoin hors cluster qui sait dire quand la supervision elle-même se tait. Les pannes du palier 4 ont laissé des runbooks et des alertes « méta » ; la documentation dit aux modules 22 et 23 ce qu'ils trouvent. C'est ce que Claire Morel présentera à la DSI et à l'auditeur HDS comme « Supervision MédiSphère v1 ».

---

### M21-E46 — Mini-projet : la supervision de MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-2246** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Recette de la supervision v1 dans deux semaines. Je veux un contrôle global sans un seul rouge, **sans rien de provisoire** (aucune panne ouverte, aucun silence oublié, aucun essai en cours, aucune VM d'essai), et une supervision qu'on peut croire : qui prévient quand il le faut, qui ne réveille pas pour rien, et qui dit quand elle ne voit plus.
> Pendant la revue : Karim relira `plateforme/observabilite`, `plateforme/ansible` (rôles `node_exporter`, `supervision_temoin`) et les dépôts `…/deploiement`, puis ajoutera devant nous une cible à superviser ; Sophie relira la sécurité de la pile et l'absence de données personnelles dans les métriques ; Nadia arrêtera l'Alertmanager du cluster pendant ta présentation et attendra le courriel du témoin ; Julien lancera une version de MédiAgenda volontairement défaillante en recette et attendra l'interruption du canary par l'analyse Prometheus ; je vous demanderai la disponibilité de MédiAgenda sur les 28 derniers jours et le budget d'erreur restant. Format habituel : 10 minutes de présentation, les démonstrations, nos questions.

**Objectifs pédagogiques**
- Consolider la supervision du module en une brique cohérente, pilotée par le code (Argo CD, Ansible, OpenTofu), sans dette provisoire.
- Prouver ce qui a été construit : chaîne d'alerte de bout en bout, supervision de la supervision, SLO, analyses de déploiement, conservation longue.
- Livrer l'état `metriques-v1` : documentation, runbooks, flux, étiquette de version, et ce que les modules 22 et 23 devront traiter.

**Prérequis** : M21-E01 à M21-E45 (au minimum tous les `LAB`, `LIBRE`, `BF` et le `CHRONO`).
**Durée indicative** : 8 à 12 h, plus 30 min de revue.

**Contexte technique**
- Pile et adresses figées (PLAN §4.11) : kube-prometheus-stack sous Argo CD dans `supervision` (objet Prometheus `kps`, 2 réplicas, 15 jours sur `ceph-rbd`) ; vue globale Thanos Query **10.10.41.60** (`prometheus.apps.par1.medisphere.internal:9090`) et Alertmanager **10.10.41.61**, joints depuis MGMT et `mon01` seulement ; Grafana 13.2 sur `grafana.apps.par1.medisphere.internal` ; Thanos 0.42 vers `thanos-k8s-par1` ; Pyrra 0.10 ; témoin `mon01` (10.10.20.19).
- Dépôts : `plateforme/observabilite` (règles, ScrapeConfig, routes, tableaux, SLO, Thanos, tests), `plateforme/gitops` (Applications), `plateforme/charts-miroir`, `plateforme/ansible` (`node_exporter`, `supervision_temoin`, pare-feu), `plateforme/infra` (OpenTofu : dossiers et équipes Grafana), `plateforme/k8s` (Secrets hors Git, espaces), `mediagenda/deploiement` et `medidoc/deploiement` (composant `components/supervision`), `plateforme/medisphere` (documentation `docs/observabilite/metriques/`).
- Les témoins `wb-pannes` du palier 4 peuvent rester (au repos, ils ne sonnent pas) ou être retirés après la recette.
- Le contrôle global `lab/bin/check 21 46` rejoue les contrôles clés des paliers 1 à 3 (déploiement de la pile, collecte des applications et des VMs, témoin, alertes testées, Thanos, SLO, supervision de la supervision), puis vérifie la couverture de la collecte, la pile, l'absence de provisoire, la documentation et l'étiquette. Il prend quelques minutes.

**État livré `metriques-v1`** — ce que les modules suivants trouveront, tel que les exercices du module l'ont construit. Rien de ce tableau ne doit manquer, rien ne doit porter un autre nom.

| Élément | État attendu à la livraison |
|---|---|
| Pile | Application `kube-prometheus-stack` (chart 92.x recopié et signé par `charts-miroir`) Synced/Healthy ; Prometheus `kps` 2 réplicas, sidecar Thanos, rétention locale 15 j, `ceph-rbd`, limites globales par cible, **ni** API d'administration **ni** récepteur *remote write* (le M23 l'active) ; Alertmanager `kps` ; Grafana 13.2 (inscription et anonymes fermés, mot de passe `admin` hors Git, compte de service `wb-checks`) |
| Accès | Services `LoadBalancer` .60 (Thanos Query) et .61 (Alertmanager), `externalTrafficPolicy: Local`, CiliumNetworkPolicy : MGMT et `mon01` seulement ; Grafana derrière `gw-par1` |
| Collecte | plan de contrôle, etcd, kubelet/cAdvisor, Cilium/Hubble, CoreDNS, kube-state-metrics, node-exporter des nœuds ; node_exporter TLS sur toutes les VMs (job `vms`, NetBox) ; Ceph, HAProxy, PowerDNS, GitLab, Harbor ; Proxmox et PBS par `mon01` (fédération) ; MédiAgenda (trois environnements) et MédiDoc par leurs dépôts ; étiquettes `equipe`, `site`, `environnement` ; aucune cible en échec |
| Règles | enregistrement (`niveau:métrique:opérations`) et alertes dans `plateforme/observabilite` et dans les dépôts d'équipe, toutes chargées ; `gravite`, `equipe`, `runbook_url` partout ; tests `promtool test rules` en CI ; alertes méta : cible disparue, règle non évaluée, transport des alertes, Thanos (envoi, Store, Compactor), cardinalité |
| Alertmanager | récepteurs `plateforme-mail`, `astreinte-mail`, `mediagenda-mail`, `medidoc-mail` ; routage par `equipe` et `gravite`, `time_intervals` ; inhibitions testées ; essais de routage en CI ; aucun silence de plus de 7 jours |
| Tableaux | JSON de `tableaux/` (UID stables, sources par variable), dossiers et équipes par OpenTofu (état `observabilite-grafana`), tableaux USE et RED de référence, contrôles de CI (JSON, UID, sources, règles et étiquettes citées) |
| Historique long | Thanos Query, Store, Compactor (un seul) ; compartiment `thanos-k8s-par1` (utilisateur RGW `thanos`, quota) ; rétentions 30 j / 180 j / 2 ans ; Grafana sur Thanos Query |
| SLO | Pyrra : `mediagenda-disponibilite` (99,5 % sur 28 j), `mediagenda-latence` (95 % < 300 ms), `medidoc-disponibilite` ; alertes multi-fenêtres ; `slo.apps.par1.medisphere.internal` |
| Livraison continue | ClusterAnalysisTemplate `taux-erreur-mediagenda` branchée sur les canaries de recette et de prod |
| Témoin `mon01` | Prometheus 3.13 LTS, Alertmanager, blackbox, pve-exporter par le rôle `supervision_temoin` ; *dead man's switch* sur le Watchdog du cluster ; sondes des points d'entrée ; relais des alertes de transport du cluster ; alertes sur lui-même ; API d'administration fermée |
| Documentation | `docs/observabilite/metriques/` : ADR-0210, `politique-alerte.md`, `politique-budget-erreur.md`, runbooks RB-210 à RB-219, `supervision-v1.md` (fiche de livraison) ; journaux et post-mortem INC-4843 dans `docs/kubernetes/` ; matrice des flux à jour (9100, exportateurs, `mon01`) ; étiquette **`metriques-v1`** sur `plateforme/medisphere` |

**Travail demandé**
1. **Rien de provisoire.** Aucune panne `M21` ouverte, aucun silence oublié, aucun essai en cours sur les témoins, aucune VM d'environnement du module (2210-2219), aucune API d'administration ouverte, aucun objet posé à la main dans un espace géré par Argo CD.
2. **Tout le lab collecté.** Chaque élément du tableau « Collecte » est présent et `up`, avec ses étiquettes ; une alerte de disparition couvre chaque job attendu.
3. **Alertes qu'on peut croire.** Chaque alerte a une gravité, une équipe, un runbook qui existe et un test ; chaque route est couverte par un essai de routage ; chaque inhibition par un essai d'inhibition ; le bruit d'une semaine est mesuré (alertes les plus notifiées) et justifié ou corrigé.
4. **La supervision de la supervision.** Le témoin prévient quand le cluster ne prévient plus (Watchdog, Alertmanager arrêté, courriel cassé), et le cluster prévient quand le témoin ne voit plus juste ; démonstration de Nadia répétée **avant** la revue et chronométrée.
5. **SLO et déploiements.** Les trois SLO ont leurs alertes de budget ; le rapport de Claire (disponibilité sur 28 jours, budget restant) se lit dans Pyrra et dans Grafana, chiffres concordants ; le canary défaillant de Julien est interrompu par l'analyse Prometheus en recette (démonstration répétée).
6. **Historique.** Une requête sur toute la période depuis l'installation de Thanos répond sans trou ni avertissement ; l'inventaire du compartiment est consigné ; le Compactor est seul et sain.
7. **Sécurité et données.** Revue de Sophie préparée : accès aux points d'entrée, Grafana, Secrets hors Git, API d'administration, et la preuve qu'aucune métrique ne contient de donnée personnelle (étiquettes interdites contrôlées, recherche faite et consignée).
8. **Documentation.** `supervision-v1.md` (architecture, couverture, **limites assumées**, ce que trouvent les modules 22 et 23), ADR-0210, politiques, runbooks RB-210 à RB-219, matrice des flux.
9. **Livraison.** Tout est fusionné, les pipelines de `main` sont verts, l'étiquette **`metriques-v1`** est posée sur `plateforme/medisphere`.
10. **La revue.** 10 minutes de présentation (architecture, choix et compromis, limites), les démonstrations de Nadia et de Julien, l'ajout d'une cible par Karim, le rapport SLO pour Claire, les questions de Sophie.

**Contraintes**
- Tout passe par le code (Argo CD, Ansible, OpenTofu) ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.
- Aucun secret dans un dépôt, un tableau, une annotation d'alerte ou la documentation : des **emplacements**, jamais des valeurs.
- Aucune donnée supprimée du compartiment Thanos ; aucune API d'administration ouverte dans le cluster.
- Les choix qui s'écartent d'un exercice du module sont justifiés (ADR ou description de MR).

**Critères de réussite**
- [ ] `lab/bin/check 21 46` est entièrement vert.
- [ ] Démonstration de Nadia : Alertmanager du cluster arrêté, courriel du témoin reçu par `astreinte@` dans le délai annoncé par la politique d'alerte ; retour à la normale sans intervention manuelle autre que le redémarrage.
- [ ] Démonstration de Julien : le canary défaillant est interrompu par `taux-erreur-mediagenda`, la version stable reste servie, l'événement est visible dans Argo CD et dans Grafana.
- [ ] Le rapport SLO de Claire est cohérent entre Pyrra, Grafana et une requête PromQL écrite à la main.
- [ ] `supervision-v1.md` dit ce qui n'est **pas** couvert et ce que les modules 22 et 23 devront traiter ; la revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 21 46`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 21 46` dès le début : la liste des points rouges est ton plan de travail. `lab/bin/check 21 43` rejoue d'un coup les contrôles du palier 4, qui sont aussi des contrôles de santé de la supervision.
</details>

<details><summary>Indice 2</summary>

Répète les démonstrations **avant** de nettoyer : la coupure de l'Alertmanager du cluster doit être faite d'une façon qu'Argo CD ne défait pas aussitôt (que fait `selfHeal` d'un StatefulSet mis à zéro réplica ? et l'opérateur ?) ; le canary défaillant exige une image qui renvoie des erreurs 5xx sur une partie des requêtes, et du trafic pendant l'analyse.
</details>

<details><summary>Indice 3</summary>

« Ce qui n'est pas couvert » : un seul hyperviseur et une seule salle, le témoin qui partage `mon01` avec Mailpit, des alertes par courriel seulement, pas de journaux ni de traces, des comptes locaux sans SSO. Écris pour chacun le risque, ce qui le détecte (ou rien), et le module ou le final qui le traite.
</details>

**Pour aller plus loin** (facultatif) : un essai hebdomadaire automatisé de toute la chaîne (job planifié qui déclenche l'essai des témoins, attend le courriel dans Mailpit et alerte par le témoin s'il n'arrive pas) ; une revue mensuelle du bruit des alertes produite par un script, publiée dans `docs/observabilite/metriques/revues/`.
