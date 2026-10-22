# Module 21 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les questionnaires (E01, E09) sont argumentés et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice ; chaque dossier reproduit l'arborescence du projet concerné : `observabilite/` pour `plateforme/observabilite`, `gitops/` pour `plateforme/gitops`, `charts-miroir/` pour `plateforme/charts-miroir`, `k8s/` pour `plateforme/k8s`, `ansible/` pour `plateforme/ansible`, `mediagenda-deploiement/` et `medidoc-deploiement/` pour les dépôts de déploiement, `medisphere/` pour la documentation. Un fichier n'apparaît que dans l'exercice qui le crée ou le modifie : `M21-E02/` (values **état E02**, Application, espaces, ClusterRole), `M21-E03/` et `M21-E04/` (requêtes), `M21-E05/` (tableau de bord, script du compte de service), `M21-E06/` (values **état E06**, avec Alertmanager), `M21-E07/` (components, politique de collecte, structure et CI de `plateforme/observabilite`, Application `observabilite`), `M21-E08/` (rôle `node_exporter` v2, playbooks, flux, `scrape/`).

**Ce qui a été vérifié à la rédaction** :
- le chart **kube-prometheus-stack 92.11.0** réel (index du dépôt amont, empreinte `c357a259…a2c` recalculée sur l'archive) rendu par **Helm 4.3.1** avec les values d'E02 puis d'E06 : 103 puis 104 objets, tous valides pour `kubeconform -strict` (Kubernetes 1.36, schémas des CRD du catalogue communautaire) ; noms obtenus (`Prometheus`/`Alertmanager` `kps`, `kps-operator`, `kps-grafana`, `kps-kube-state-metrics`, DaemonSet `kps-prometheus-node-exporter` dans `supervision-noeuds`) ; étiquette de sélection présente sur **les 8 ServiceMonitor et les 30 PrometheusRule** du rendu ; images (Prometheus `v3.15.0-distroless`, Alertmanager `v0.34.1`, opérateur et rechargeur `v0.94.1`, kube-state-metrics `v2.20.0`, node-exporter `v1.12.1-distroless`, Grafana `13.2.4-distroless`, sidecar `k8s-sidecar 2.14.1`, Thanos par défaut `v0.42.4`) ; contrôle de Pod Security « restricted » sur les gabarits rendus (Grafana, opérateur, kube-state-metrics conformes ; node-exporter non conforme, d'où son espace) ;
- la configuration d'Alertmanager **extraite du Secret rendu** par le chart : `amtool check-config` (0.34.1) réussit, avec le gabarit ; `amtool config routes test` sur les quatre jeux d'essai ; une instance réelle d'Alertmanager 0.34.1 lancée avec cette configuration : `/api/v2/status` relu par le check d'E06 (tous les contrôles de configuration verts), `amtool alert add` accepté ; `smtp_tls_config` global confirmé (un champ mal orthographé fait échouer `check-config`) ;
- les requêtes d'E03, d'E04 et du tableau d'E05 évaluées par un **Prometheus 3.15.1** local sur des données synthétiques de MédiAgenda (compteurs, histogramme, cache, `kube_pod_info`, mémoire des conteneurs) rétro-chargées par `promtool tsdb create-blocks-from openmetrics` : toutes valides, toutes non vides ; le check d'E03/E04 (découpage des fichiers `.promql`, évaluation) exécuté contre ce Prometheus : 23 contrôles verts ; `outils/verifier-promql.sh` (`promtool --experimental promql format`) détecte une parenthèse non fermée ;
- node_exporter **1.12.1** (empreinte `b51d8a76…e63` de `sha256sums.txt` de la publication) lancé avec la configuration web du rôle et un certificat de test : `promtool check web-config` réussit, `/metrics` en HTTPS répond, une requête HTTP en clair reçoit **400** ; options de ligne de commande relues dans `node_exporter --help` ;
- le rôle `node_exporter` v2 et les deux playbooks : `ansible-lint` 26.10 (profil `production`) et `--syntax-check` (ansible-core 2.21, rôle `certificats_acme` du M06 et collection `netbox.netbox` installés) ; la génération de `scrape/vms.yaml` exécutée avec une liste de VMs simulée (la recherche NetBox remplacée) sur un vrai dépôt Git : fichier conforme au schéma `ScrapeConfig` (`v1alpha1`), branche créée ;
- components kustomize, Application `observabilite`, politique `collecte-prometheus` : `kubectl kustomize` (kustomize 5.8.1) et `kubeconform` ; `.gitlab-ci.yml` analysé comme YAML ; `outils/tester-routes.sh` exécuté ;
- tous les scripts (checks, ressources, scripts du corrigé) : `shellcheck -x` (et `-s sh` pour les scripts POSIX) et `bash -n` ; checks exécutés sans lab (tous les contrôles KO, aucune erreur d'exécution sous `set -euo pipefail`), et les filtres `jq` d'E02, E06, E07, E08 testés sur les objets rendus.

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- le déploiement complet par Argo CD 3.5 : en particulier l'ordre de la première synchronisation avec le webhook en `failurePolicy: Fail` (le `retry` doit suffire), la prise en compte de `ignoreDifferences` sur le `caBundle` injecté par cert-manager, et la santé des CR `Prometheus`/`Alertmanager` vue par Argo CD ;
- la conformité « restricted » des pods **créés par l'opérateur** (Prometheus, Alertmanager, conteneurs de rechargement) : l'opérateur 0.94 pose `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem`, `capabilities.drop: [ALL]` sur ses conteneurs et le chart le `seccompProfile` du pod ; non rendu hors cluster ;
- le comportement de Cilium 1.20 avec `externalTrafficPolicy: Local` et `fromCIDR` sur un Service `LoadBalancer` (adresse source conservée jusqu'au pod) : conforme à la documentation, non mesuré ici ;
- les droits du rôle Viewer de Grafana 13.2 sur `/api/datasources/uid/<uid>/health` et `/api/datasources` (le check d'E05 passe en « ignoré » ou en KO selon la réponse) ; la lecture d'un tableau enregistré au **schéma v2** par `/api/dashboards/uid/` ;
- l'émission ACME du certificat de node_exporter sur les hôtes qui n'avaient pas de certificat ACME (`adm01`, `runner01`, `runner02`) : flux `ca01` → port 80 à ouvrir si besoin ;
- le relais du rechargement de certificat par node_exporter (exporter-toolkit relit le fichier web à chaque connexion : documenté, non observé sur un renouvellement réel) ;
- `charts.yaml` du miroir et `secrets-k8s.sh` suivent les formats écrits au M20-E13 (liste `charts:`) et au M19-E04 / M20-E06 (table `secrets-k8s.conf`, modules `secrets-k8s.d/`) : si ton dépôt s'en écarte, reprends **ses** noms de champs.

---

### M21-E01 — Test de positionnement : supervision

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 36. En dessous de 18, relis les « Concepts clés » de l'introduction avant E04 ; les questions 4 à 8 sont reprises en E04 et E14, 9-10 en E13 et E14, 11-14 en E06, E15 et E16, 15-16 en E26-E27, 17-18 en E24-E28.

**Réponses argumentées — collecte**

**1. Pull et push.** Avantages du *pull* : (a) Prometheus **sait** quand une cible ne répond plus (`up == 0`) au lieu de confondre « silence » et « tout va bien » ; (b) la liste de ce qui est supervisé est **décidée côté supervision** (découverte, relabeling) et non par chaque émetteur ; (c) on peut ouvrir `/metrics` à la main pour voir exactement ce que voit Prometheus ; (d) la cadence est maîtrisée (pas d'émetteur qui inonde). Le *push* est préférable pour ce qui ne vit pas assez longtemps pour être collecté (traitement par lots, fonction éphémère), pour des émetteurs derrière un NAT ou un pare-feu qui interdit d'entrer, et pour les très grands volumes déjà agrégés côté émetteur. OpenTelemetry (M23) pousse en OTLP ; Prometheus 3 sait d'ailleurs recevoir OTLP.

**2. Réponse B.** À chaque collecte, Prometheus écrit `up` (1 ou 0) pour la cible. Quand la collecte échoue, `up` vaut 0 et les séries que la cible exposait reçoivent un **marqueur de péremption** (*staleness marker*) : elles disparaissent des requêtes instantanées au lieu d'être prolongées 5 minutes. A est faux (la série `up` reste, à 0) ; C est faux (rien n'est recopié : c'est l'ancien comportement de Prometheus 1.x pendant 5 minutes, sans marqueur) ; D est faux : aucune alerte n'existe sans règle (le chart en livre une, `TargetDown`).

**3. Traitement court.** Une collecte toutes les 30 s peut tomber entièrement à côté d'un processus de 40 s, et de toute façon il disparaît avant d'avoir été lu deux fois : ses compteurs ne donnent aucun taux. Deux façons : le **Pushgateway** (le traitement pousse à la fin ses métriques, dont l'heure de dernier succès, et Prometheus collecte le Pushgateway), ou le **collecteur textfile** de node_exporter (le traitement écrit un fichier `.prom` atomiquement : c'est ce que font `ms-verif-*` depuis le M07). Dans les deux cas, on supervise surtout `…_last_success_timestamp_seconds` : « le traitement a-t-il réussi depuis moins de 26 heures ? ».

**Réponses argumentées — types et calculs**

**4. Types.** Compteur : `mediagenda_http_requests_total` → `rate`, `increase`. Jauge : `node_memory_MemAvailable_bytes`, `kube_deployment_status_replicas_available` → valeur brute, `avg_over_time`, `deriv`, `predict_linear`. Histogramme : `mediagenda_http_request_duration_seconds` → `histogram_quantile` sur `rate(…_bucket)`, et `rate(…_sum)/rate(…_count)` pour la moyenne. Résumé : `go_gc_duration_seconds{quantile="0.75"}` (exposé par le client Go) → on lit le quantile tel quel, sans pouvoir l'agréger.

**5. Réponse B.** `rate` interprète toute baisse comme une remise à zéro (redémarrage du processus) et ajoute la valeur d'après la baisse : sur une jauge qui monte et descend, le résultat n'a aucun sens. A est donc faux ; C est faux (`deriv` fait une régression linéaire et accepte une baisse : c'est **lui** qu'il faut pour une jauge) ; D est faux (le résultat est quelconque, rarement 0).

**6. `rate` et `irate`.** `rate` calcule la pente moyenne entre le premier et le dernier échantillon de la fenêtre (extrapolée aux bords) : lissé, stable. `irate` ne prend que les **deux derniers** échantillons : très réactif, très bruité, et il ignore tout ce qui s'est passé avant dans la fenêtre. Alerte : `rate` (on veut une tendance sur quelques minutes, pas un pic d'un intervalle) ; graphique de diagnostic à fort zoom : `irate` peut montrer une rafale que `rate` aplatit.

**7. Moyenne de quantiles.** Un quantile ne se moyenne pas : le p95 du service est le temps sous lequel passent 95 % de **toutes** les requêtes ; un pod qui sert 90 % du trafic pèse plus qu'un pod qui en sert 5 %, et la moyenne des p95 ne correspond à aucune population. Avec un histogramme, on **additionne d'abord les compartiments** de tous les pods (`sum by (le) (rate(…_bucket[5m]))`), puis on calcule le quantile sur la distribution agrégée. C'est la raison d'être des histogrammes face aux résumés (M21-E04, question 5).

**8. `increase` non entier.** `increase` est `rate` multiplié par la durée de la fenêtre, et `rate` **extrapole** aux bords de la fenêtre (les échantillons ne tombent pas pile sur ses bornes). Le résultat est une estimation, pas un comptage : 41,7 veut dire « environ 42 ».

**Réponses argumentées — étiquettes**

**9. Cardinalité.** Le nombre de séries distinctes d'une métrique : le produit des nombres de valeurs de ses étiquettes (au plus). Chaque série coûte de la mémoire (environ quelques kio dans la tête de la TSDB), un index, et du temps de requête. À ne jamais mettre sur MédiAgenda : l'identifiant d'un rendez-vous, d'un patient, le chemin **réel** (`/api/v1/rendez-vous/12345`) au lieu du modèle de route, l'adresse IP du client, un identifiant de requête. Chaque nouvelle valeur crée une série qui ne resservira jamais : la mémoire de Prometheus explose, il est tué (OOM) ou ralentit pour tout le monde. Le code de MédiAgenda le dit d'ailleurs en commentaire (« le libellé route est le modèle de chemin »). M21-E38 en fait une panne.

**10. Réponse C.** 5 × 12 × 8 × 6 = 2 880 séries **au plus** (toutes les combinaisons ne sont pas réalisées : une route ne reçoit pas toutes les méthodes). A additionne au lieu de multiplier ; B oublie les pods (l'étiquette `pod` ajoutée par la collecte multiplie tout) ; D confond séries et cibles.

**Réponses argumentées — alerter**

**11. Symptôme et cause.** Symptôme : ce que l'utilisateur subit (« 5 % des requêtes de MédiAgenda échouent depuis 10 minutes », « le p95 dépasse 2 s »). Cause : une raison possible (« un pod redémarre en boucle », « le CPU d'un nœud est à 90 % », « la base a 95 connexions »). Seuls les symptômes réveillent quelqu'un : une cause peut n'avoir aucun effet (le CPU à 90 % d'un service qui répond bien), et toutes les causes ne sont pas prévisibles (un symptôme attrape aussi la panne qu'on n'a pas imaginée). Les causes vont dans les tableaux de bord et les alertes de jour (tickets).

**12. `for`.** La condition doit rester vraie pendant cette durée avant que l'alerte passe de *pending* à *firing* : elle absorbe les pics d'un intervalle et les redémarrages normaux. Sans `for`, chaque pic d'une collecte déclenche (et résout) une notification : du bruit, et une équipe qui finit par ignorer les courriels. Avec 2 heures, une vraie panne n'est signalée qu'au bout de 2 heures : trop tard pour un service patient. On choisit selon le coût d'un retard (souvent 5 à 15 min) ; `keep_firing_for` (E15) évite à l'inverse qu'une alerte oscille.

**13. Réponse B.** Le **regroupement** réunit les alertes qui partagent les étiquettes de `group_by` en une seule notification ; une **inhibition** (« nœud injoignable » fait taire « pod injoignable » sur ce nœud, E16) va plus loin. Les silences (A) sont posés à la main, avant ou pendant une intervention ; `repeat_interval` (C) espace les rappels d'un même groupe, il ne réunit rien ; D est faux : Prometheus envoie une alerte par série, c'est le rôle d'Alertmanager de les regrouper.

**14. Une notification utile.** Quoi (résumé lisible, pas une expression PromQL), où (environnement, service, espace), depuis quand, gravité, **impact** utilisateur, un lien vers le **runbook** (que faire maintenant), un lien vers le graphique (la source dans Prometheus, ou un tableau de bord), et qui est concerné (équipe). Et rien de plus : une notification illisible sur un téléphone ne sert à rien. C'est l'objet des annotations `resume`, `description`, `runbook_url` (E15) et des gabarits d'Alertmanager (E06).

**Réponses argumentées — niveaux de service**

**15. SLI, SLO, SLA.** **SLI** : un indicateur mesuré (part des requêtes réussies, part servie en moins de 300 ms). **SLO** : l'objectif interne sur cet indicateur et une période (99,5 % sur 28 jours). **SLA** : l'engagement contractuel envers un client, avec des pénalités ; il est moins exigeant que le SLO, qui sert de marge. L'équipe Plateforme se fixe des SLO ; la direction signe des SLA (le contrat HDS de Claire).

**16. Budget.** 28 jours = 40 320 minutes ; 0,5 % = **201,6 minutes** (≈ 3 h 22) d'indisponibilité autorisées. Le **budget d'erreur** est cette marge : tant qu'il en reste, l'équipe peut prendre des risques (livrer, tester) ; quand il est consommé, on gèle les changements risqués et on travaille la fiabilité (M21-E27, `politique-budget-erreur.md`).

**Réponses argumentées — architecture**

**17. Superviser la supervision.** Si la pile tombe avec le cluster (nœuds arrêtés, réseau coupé, stockage plein), **aucune** alerte ne part : le silence ressemble à « tout va bien ». D'où un composant indépendant qui attend un signal permanent (`Watchdog`, alerte toujours active) et alerte sur son **absence** (*dead man's switch*) : c'est la supervision témoin de `mon01` (M21-E11, E28), hors du cluster, avec son propre chemin de courriel.

**18. Conservation longue.** (a) Augmenter la rétention locale : simple, mais un seul disque, une seule instance, des requêtes longues lentes et une TSDB énorme à sauvegarder ; (b) envoyer les blocs vers un **stockage objet** et les requêter par une couche globale (Thanos, Mimir) : durable, avec sous-échantillonnage, mais plus de composants à exploiter ; (c) *remote write* vers une base externe (Mimir, VictoriaMetrics) : découple, mais ajoute une dépendance réseau au chemin d'écriture. Le module retient Thanos sur le RGW (E24-E25, ADR-0210).

---

### M21-E02 — Déployer kube-prometheus-stack par Argo CD

**Solution**

*A. Le chart recopié.* Entrée de [`charts.extrait.yaml`](fichiers/M21-E02/charts-miroir/charts.extrait.yaml) dans `plateforme/charts-miroir` (version 92.11.0, empreinte `sha256:c357a259965187edcbed86591461bfbd56997591afba09be3a49a09b2bec8a2c`, celle de l'index amont, recalculée sur l'archive). Le pipeline du miroir tire, vérifie, pousse en OCI et signe. L'archive contient ses sous-charts (`crds`, `kube-state-metrics` 8.6.0, `prometheus-node-exporter` 4.60.0, `grafana` 14.0.1, `prometheus-windows-exporter`) : Argo CD n'a rien à tirer de `ghcr.io`.

```
admin@adm01:~/m21/e02$ helm show values oci://registry.par1.medisphere.internal/charts/kube-prometheus-stack --version 92.11.0 > defauts.yaml
admin@adm01:~/m21/e02$ wc -l defauts.yaml
6248 defauts.yaml
admin@adm01:~/m21/e02$ helm template kps oci://registry.par1.medisphere.internal/charts/kube-prometheus-stack --version 92.11.0 -n supervision \
>   | yq -r 'select(.kind) | .kind' | sort | uniq -c | sort -rn | head
```

Objets sans espace : `ClusterRole`, `ClusterRoleBinding`, `MutatingWebhookConfiguration`, `ValidatingWebhookConfiguration` et, à l'installation, les `CustomResourceDefinition` (dans `charts/crds/crds/`, qu'Argo CD applique : il rend les charts avec leurs CRD). D'où l'extrait d'AppProject [`plateforme.extrait.yaml`](fichiers/M21-E02/gitops/projets/plateforme.extrait.yaml) : sources (OCI de Harbor, `plateforme/observabilite`), destinations `supervision` et `supervision-noeuds`, et cette liste **fermée** de types sans espace.

*B. Espaces et droits.* Le DaemonSet de node-exporter rendu demande `hostNetwork: true`, `hostPID: true`, trois volumes `hostPath` (`/proc`, `/sys`, `/`), et son conteneur ne retire pas toutes les capacités : quatre motifs de refus par `restricted` (et trois par `baseline`). Plutôt que d'abaisser `supervision` (où tournent Grafana, Prometheus, Alertmanager), node-exporter va dans un espace dédié **`supervision-noeuds`** en `privileged`, avec `audit`/`warn` en `restricted` et l'exception en annotation : [`espaces/supervision-noeuds.yaml`](fichiers/M21-E02/k8s/espaces/supervision-noeuds.yaml). L'espace `supervision` migre dans [`espaces/supervision.yaml`](fichiers/M21-E02/k8s/espaces/supervision.yaml) avec `medisphere.internal/exposition: oui` (sinon `gw-par1` refuse la route de Grafana : `NotAllowedByListeners`) ; on retire le document `Namespace` de `rbac/supervision/supervision.yaml` dans la même MR. ClusterRole [`wb-checks-observabilite`](fichiers/M21-E02/k8s/rbac/wb-checks-observabilite.yaml) : lecture des CRD de l'opérateur (et de leur `status`), de `pyrra.dev`, `opentelemetry.io`, des `Certificate`/`Issuer` de cert-manager, aucune ressource `secrets`.

```
admin@adm01:~/src/k8s$ task espaces
admin@adm01:~/src/k8s$ task diff && task appliquer
admin@adm01:~/src/k8s$ uv run --project ~/src/ansible ansible-vault create --vault-id critique@$HOME/src/ansible/outils/vault-pass-client.sh secrets/grafana.yml
admin@adm01:~/src/k8s$ outils/secrets-k8s.sh appliquer grafana && outils/secrets-k8s.sh verifier grafana   # → supervision/grafana-admin
```

Le Secret est une simple liste de clés : une ligne de la table `outils/secrets-k8s.conf` (format de M19-E04) suffit, sans module `secrets-k8s.d/` ([`secrets-k8s.conf.extrait`](fichiers/M21-E02/k8s/outils/secrets-k8s.conf.extrait), modèle du Vault [`secrets/grafana.yml.exemple`](fichiers/M21-E02/k8s/secrets/grafana.yml.exemple)) : Secret `supervision/grafana-admin`, clés `admin-user` (`admin`) et `admin-password`.

*C. Les values.* Fichier complet commenté : [`kps/values.yaml`](fichiers/M21-E02/observabilite/kps/values.yaml). L'essentiel :

| Besoin | Réglage |
|---|---|
| Noms courts | `fullnameOverride: kps` + `cleanPrometheusOperatorObjectNames: true` → CR `kps`, StatefulSets `prometheus-kps`, `alertmanager-kps` |
| Sélection | `prometheusSpec.<type>Selector.matchLabels: {medisphere.internal/supervision: "oui"}` et `<type>NamespaceSelector: {}` pour `serviceMonitor`, `podMonitor`, `rule`, `probe`, `scrapeConfig` ; `…SelectorNilUsesHelmValues: false` |
| Étiquette sur les objets du chart | `commonLabels` (objets du chart parent : 5 ServiceMonitor, 30 PrometheusRule) ; `kube-state-metrics.prometheus.monitor.additionalLabels`, `prometheus-node-exporter.prometheus.monitor.additionalLabels`, `grafana.serviceMonitor.labels` (sous-charts) |
| Stockage, rétention | `storageSpec.volumeClaimTemplate` (`ceph-rbd`, 40 Gi), `retention: 15d`, `retentionSize: 32GB` ; Alertmanager `storage` 1 Gi |
| Plan de contrôle | `kubeControllerManager`, `kubeScheduler`, `kubeEtcd`, `kubeProxy`, `coreDns` : `enabled: false` |
| Webhooks | `prometheusOperator.admissionWebhooks.certManager.enabled: true`, `failurePolicy: Fail` |
| Grafana | `admin.existingSecret`, `persistence` + `deploymentStrategy: Recreate`, `initChownData.enabled: false`, `route.main` sur `gw-par1`, `grafana.ini` (URL, pas d'appel à grafana.com, inscription et anonyme désactivés) |
| Accès | `extraManifests` : Services `prometheus-externe` et `alertmanager-externe` (`lbipam.cilium.io/ips`, `external-dns.kubernetes.io/hostname`, `externalTrafficPolicy: Local`), CNP `prometheus-entree` et `alertmanager-entree` |

Validation hors ligne :

```
admin@adm01:~/src/observabilite$ helm template kps oci://registry.par1.medisphere.internal/charts/kube-prometheus-stack \
>   --version 92.11.0 -n supervision -f kps/values.yaml > ~/m21/e02/rendu.yaml
admin@adm01:~/src/observabilite$ kubeconform -strict -summary -kubernetes-version 1.36.0 \
>   -schema-location default -schema-location "$HOME/src/k8s/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" ~/m21/e02/rendu.yaml
Summary: 103 resources found in 1 file - Valid: 103, Invalid: 0, Errors: 0, Skipped: 0
admin@adm01:~/src/observabilite$ yq -r 'select(.kind == "Deployment" or .kind == "DaemonSet")
>   | [.metadata.namespace, .metadata.name, (.spec.template.spec.hostNetwork // false),
>      ([.spec.template.spec.containers[].securityContext.capabilities.drop // [] | join(",")] | join(";"))] | @tsv' ~/m21/e02/rendu.yaml
supervision-noeuds	kps-prometheus-node-exporter	true
supervision	kps-grafana	false	ALL;ALL;ALL
supervision	kps-kube-state-metrics	false	ALL
supervision	kps-operator	false	ALL
```

(Le dossier des schémas de CRD est celui de `outils/schemas-crd.sh` du M16 ; sans lui, ajoute `-ignore-missing-schemas`.)

*D. L'Application.* [`plateforme/kube-prometheus-stack.yaml`](fichiers/M21-E02/gitops/plateforme/kube-prometheus-stack.yaml) : deux sources (chart OCI `registry.par1.medisphere.internal/charts`, version **exacte** 92.11.0, `releaseName: kps`, `valueFiles: [$values/kps/values.yaml]` ; `plateforme/observabilite` en `ref: values`), synchronisation automatique, `ServerSideApply=true`, `CreateNamespace=false`, `RespectIgnoreDifferences=true`, `retry`, `ignoreDifferences` sur `.webhooks[]?.clientConfig.caBundle` des deux configurations de webhooks `kps-admission`, et **pas** de finaliseur de suppression.

```
admin@adm01:~$ argocd app get kube-prometheus-stack --refresh
Name:               argocd/kube-prometheus-stack
Project:            plateforme
Sync Policy:        Automated (Prune)
Sync Status:        Synced to 92.11.0
Health Status:      Healthy
admin@adm01:~$ kubectl --context k8s-par1 -n supervision get pods
NAME                                      READY   STATUS    RESTARTS   AGE
alertmanager-kps-0                        2/2     Running   0          6m
kps-grafana-6c9f8d7b5-x2k9q               3/3     Running   0          6m
kps-kube-state-metrics-7d8b9c6f4-p7m2r    1/1     Running   0          6m
kps-operator-5b7c9d8f6-q4w8z              1/1     Running   0          6m
prometheus-kps-0                          2/2     Running   0          6m
admin@adm01:~$ kubectl --context k8s-par1 -n supervision-noeuds get ds
NAME                           DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
kps-prometheus-node-exporter   6         6         6       6            6           kubernetes.io/os=linux   6m
```

Pendant la première synchronisation, il est normal de lire des erreurs `failed calling webhook "prometheusrulemutate.monitoring.coreos.com"` : les `PrometheusRule` arrivent avant que l'opérateur (qui sert le webhook) soit prêt et que cert-manager ait émis son certificat. Le `retry` relance la synchronisation ; à la deuxième ou troisième tentative tout passe.

*E. Constater.*

```
admin@adm01:~$ dig +short prometheus.apps.par1.medisphere.internal alertmanager.apps.par1.medisphere.internal
10.10.41.60
10.10.41.61
admin@adm01:~$ curl -s http://prometheus.apps.par1.medisphere.internal:9090/api/v1/status/buildinfo | jq -r .data.version
3.15.0
admin@adm01:~$ curl -s 'http://prometheus.apps.par1.medisphere.internal:9090/api/v1/targets?state=active' \
>   | jq -r '.data.activeTargets[] | [.labels.job, .health] | @tsv' | sort | uniq -c
      1 apiserver   up
      …
      6 kubelet     up        (×3 : /metrics, /metrics/cadvisor, /metrics/probes)
      6 node-exporter up
```

Depuis `wb-essais`, `curl --max-time 5 http://10.10.41.60:9090/-/ready` reste sans réponse : Cilium traduit l'adresse du Service vers le pod Prometheus, et la politique `prometheus-entree` refuse l'identité de `wb-essais` (`hubble observe --to-pod supervision/prometheus-kps-0 --verdict DROPPED` le montre).

**Explications**

- **Comment l'opérateur sélectionne.** Le CR `Prometheus` porte des sélecteurs d'étiquettes et d'espaces ; l'opérateur liste les objets qui y répondent, les traduit en jobs et en fichiers de règles, écrit la configuration (compressée) dans le Secret `prometheus-kps`, et le conteneur `config-reloader` du pod demande à Prometheus de la recharger. Dans le chart, `…SelectorNilUsesHelmValues: true` (défaut) remplace un sélecteur **vide** par `release: <nom de release>` : historiquement, « prends ce que ce chart a installé ». Mettre `false` laisse un sélecteur vide **tout** sélectionner ; nous allons plus loin avec un sélecteur explicite, qui oblige à étiqueter, y compris les moniteurs du chart (sinon Prometheus ne collecterait plus son propre kubelet).
- **Pourquoi des Services dédiés plutôt que le Service du chart en `LoadBalancer`.** Le Service `kps-prometheus` est l'adresse **interne** utilisée par Grafana et, plus tard, par Argo Rollouts : la changer de type aurait mélangé deux usages. Avec un Service d'accès séparé, M21-E24 peut le repointer vers Thanos Query sans toucher aux clients internes.
- **`externalTrafficPolicy: Local`.** Avec `Cluster`, un nœud qui reçoit le trafic peut le renvoyer vers un pod d'un autre nœud en remplaçant l'adresse source par la sienne : la politique verrait une adresse de nœud, impossible à filtrer. Avec `Local`, seuls les nœuds qui hébergent un pod annoncent l'adresse en BGP (M15-E25) et l'adresse du client est conservée jusqu'au pod, où `fromCIDR` la reconnaît.
- **Une politique qui sélectionne un pod en entrée le ferme à tout le reste.** C'est pourquoi les politiques autorisent aussi l'espace `supervision` (Grafana → Prometheus, Prometheus → Alertmanager, auto-collecte sur 9090 et le rechargeur sur 8080). Les sondes du kubelet viennent de l'hôte et restent permises par Cilium.
- **cert-manager pour les webhooks.** Les Jobs `certgen` du chart sont des hooks Helm : sous Argo CD, ils deviennent des hooks `PreSync` et réécrivent le `caBundle` des webhooks après coup — une source permanente de différences et de surprises. Avec cert-manager, un `Issuer` auto-signé et deux `Certificate` vivent dans `supervision`, et le *cainjector* tient le `caBundle` à jour ; on dit à Argo CD d'ignorer ce seul champ.
- **`failurePolicy: Fail`.** Un webhook en `Ignore` laisse passer une `PrometheusRule` invalide sans qu'on le sache (la règle n'est simplement pas chargée) ; en `Fail`, la synchronisation d'Argo CD échoue avec le message de validation : l'erreur est visible au bon endroit (M21-E41).

**Alternatives**

- **Manifestes `kube-prometheus` (jsonnet).** La source amont du chart ; plus de contrôle, mais un langage et une chaîne de génération de plus : réservé à qui personnalise beaucoup.
- **Installer les CRD à part** (Application dédiée, ou `crds.enabled: false` et le chart `prometheus-operator-crds`) : découple leur cycle de vie (une montée de CRD avant celle de l'opérateur) et protège encore mieux contre une suppression en cascade ; c'est ce qu'on ferait avec plusieurs Prometheus sur le cluster.
- **Prometheus Agent + stockage central** (Mimir, VictoriaMetrics) : écarté par l'ADR-0210 (palier 3) pour la taille du lab.
- **Grafana sur base CloudNativePG** plutôt que SQLite : utile pour plusieurs réplicas de Grafana ; SQLite sur un volume suffit pour un réplica, et la configuration utile (tableaux, sources) sera *as code* (E17).
- **Gateway pour Prometheus**, avec authentification par un mandataire OAuth2 : la bonne cible après le SSO du M24 ; d'ici là, un filtrage réseau strict.

**Pièges classiques**

- Oublier l'étiquette sur les moniteurs des **sous-charts** : node-exporter, kube-state-metrics et Grafana disparaissent des cibles alors que les pods tournent ; aucune erreur nulle part.
- Mettre `serviceMonitorSelector: {}` en croyant « tout prendre » avec `…NilUsesHelmValues: true` : le chart le remplace par `release: kps` et les ServiceMonitor des équipes sont ignorés.
- Laisser les cibles du plan de contrôle activées : elles écoutent sur 127.0.0.1 (défaut kubeadm), donc `TargetDown` sonne dès la première heure pour des composants en bonne santé.
- Synchroniser sans `ServerSideApply` : `CustomResourceDefinition.apiextensions.k8s.io "prometheuses.monitoring.coreos.com" is invalid: metadata.annotations: Too long`.
- Garder la stratégie `RollingUpdate` de Grafana avec un volume RWO : à la première modification, le nouveau pod attend le volume encore attaché à l'ancien (`Multi-Attach error`) et la mise à jour reste bloquée.
- Garder `initChownData` : le pod de Grafana est refusé par la Pod Security de l'espace (`violates PodSecurity "restricted"`), et le Deployment reste à 0 réplica sans autre symptôme que l'événement du ReplicaSet.
- Un Service `LoadBalancer` **sans** adresse demandée : LB IPAM prend la première adresse libre du pool (10.10.41.11…), réservée aux Gateways (convention du M15).
- `externalTrafficPolicy: Cluster` avec une politique `fromCIDR` : tout est refusé (adresse source remplacée), ou tout est accepté si l'on a autorisé les nœuds par facilité.
- Mettre un finaliseur `resources-finalizer` « comme sur les autres Applications » : une suppression dans l'interface d'Argo CD supprime les CRD, donc tous les `ServiceMonitor` et `PrometheusRule` des équipes.
- Collecte des kubelets : le chart utilise `insecureSkipVerify: true` (certificats de service des kubelets auto-signés par kubeadm). C'est la seule exception tolérée à la règle 3 du module (E20 l'étend au plan de contrôle, pour la même raison) ; M21-E29 l'inscrit aux limites acceptées de `securite.md`, avec sa correction (certificats des kubelets signés par la CA du cluster, `serverTLSBootstrap`), qui touche tous les nœuds et sort du périmètre du module.

**En production chez MédiSphère**

- Deux réplicas de Prometheus et trois d'Alertmanager (E24), PodDisruptionBudgets, anti-affinité par nœud et par baie (`par1-baie-a/b/c`).
- Authentification devant Prometheus et Alertmanager (mandataire OAuth2 après M24), journal d'accès.
- Alerte sur la configuration non rechargée (`PrometheusBadConfig`, `AlertmanagerFailedReload`) et sur les objets rejetés par l'opérateur (`PrometheusOperatorRejectedResources`), livrées par le chart.
- Montées du chart : lecture de `UPGRADE.md`, rendu et différence (`argocd app diff`) relus en MR, une majeure à la fois, jamais un vendredi (fenêtres de synchronisation du M20).

---

### M21-E03 — Explorer Prometheus : cibles, séries et étiquettes

**Solution**

1. *Runtime & build information* : Prometheus 3.15.0 ; *Command-line flags* : `--storage.tsdb.retention.time=15d`, `--storage.tsdb.retention.size=32GB`, `--storage.tsdb.path=/prometheus`, `--web.enable-lifecycle`, `--config.file=/etc/prometheus/config_out/prometheus.env.yaml`. C'est l'**opérateur** qui compose ces options à partir du CR `kps`.
2. *Target health* : une quinzaine de jobs (`apiserver`, `kubelet` en trois points de collecte par nœud, `node-exporter`, `kube-state-metrics`, `kps-operator`, `kps-prometheus`, `kps-alertmanager`, `kps-grafana`…), une trentaine de cibles, aucune en échec. Cible kubelet : `https://10.10.40.61:10250/metrics/cadvisor`, collecte de 0,1 à 0,4 s, étiquettes `endpoint="https-metrics"`, `instance="10.10.40.61:10250"`, `job="kubelet"`, `metrics_path="/metrics/cadvisor"`, `namespace="kube-system"`, `node="k8s-w01"`, `service="kps-kubelet"`.
3. *Service discovery* : la même cible avant relabeling porte des dizaines d'étiquettes `__meta_kubernetes_endpointslice_*`, `__meta_kubernetes_service_*`, `__meta_kubernetes_node_name`… et `__address__="10.10.40.61:10250"`, `__scheme__="https"`, `__metrics_path__="/metrics/cadvisor"`. Les étiquettes en `__` disparaissent après le relabeling. Cibles écartées : le Service `kps-kubelet` (géré par l'opérateur dans `kube-system`) déclare trois ports (`https-metrics` 10250, `http-metrics` 10255, `cadvisor` 4194) ; le ServiceMonitor ne collecte que `https-metrics` : les deux autres ports de chaque nœud sont découverts puis écartés par la règle `keep` sur `__meta_kubernetes_endpointslice_port_name`.
4. La configuration générée est dans le Secret **`prometheus-kps`**, clé `prometheus.yaml.gz` (gzip) :
   ```
   admin@adm01:~$ kubectl --context k8s-par1 -n supervision get secret prometheus-kps \
   >   -o jsonpath='{.data.prometheus\.yaml\.gz}' | base64 -d | gunzip | less
   ```
   Job `serviceMonitor/supervision/kps-kubelet/0` : `kubernetes_sd_configs` en rôle `endpointslice`, espace `kube-system` ; relabeling : `keep` sur les étiquettes du Service sélectionné (`__meta_kubernetes_service_label_app_kubernetes_io_name=kubelet`), `keep` sur le nom de port, `replace` de `__meta_kubernetes_namespace` vers `namespace`, de `__meta_kubernetes_service_name` vers `service`, `job` tiré de l'étiquette `k8s-app` du Service (`jobLabel`), `endpoint` = nom du port. Lire le Secret à l'écran ne l'écrit nulle part ; `kubectl get secret … -o yaml > fichier` le ferait.
5. `headStats` : `numSeries` de l'ordre de 150 000 à 250 000 sur ce cluster avec les seuls composants du chart ; les cinq métriques les plus coûteuses sont des histogrammes du kube-apiserver (`apiserver_request_duration_seconds_bucket`, `apiserver_request_sli_duration_seconds_bucket`, `etcd_request_duration_seconds_bucket`) et de cAdvisor (`container_…`) : beaucoup de compartiments × beaucoup de ressources et de verbes. Les séries de **tête** sont celles qui ont reçu un échantillon dans les 2 dernières heures environ (bloc en mémoire, pas encore écrit).
6. Requêtes : [`requetes/E03.promql`](fichiers/M21-E03/observabilite/requetes/E03.promql).
7. Compte rendu : modèle de [`ressources/E03-exploration/`](../ressources/E03-exploration/exploration-modele.md) rempli ; un exemple de forme attendue est dans [`fichiers/M21-E03/medisphere/`](fichiers/M21-E03/medisphere/docs/observabilite/metriques/exploration.md).

**Explications**

Prometheus ne collecte pas « des pods » : il découvre des **objets** (points de terminaison, pods, nœuds), en fait des cibles candidates étiquetées `__meta_*`, puis le relabeling garde, écarte, renomme. L'opérateur écrit ce relabeling à partir du ServiceMonitor : c'est pourquoi une erreur de sélecteur ne produit **aucune** erreur, seulement des cibles écartées. La page *TSDB status* est le premier outil de capacité : séries de tête, métriques et étiquettes les plus coûteuses.

**Alternatives** : `promtool tsdb analyze` sur une copie de la TSDB (palier 4, hors cluster) donne la même analyse plus finement ; l'API `/api/v1/status/tsdb?limit=20` la donne en JSON pour un script.

**Pièges classiques**

- Confondre cibles **actives** et **écartées** : `/api/v1/targets` sans `state=active` renvoie les deux ; les écartées n'ont pas de `health`.
- Croire que `count by (__name__) ({__name__=~".+"})` est anodin : sur un Prometheus de production, c'est une requête qui touche **toutes** les séries ; elle a sa place dans un exercice, pas dans un tableau de bord.
- Écrire la configuration déchiffrée sur disque « pour la lire tranquillement » : elle contient des références à des Secrets, et un fichier oublié dans `~/` finit dans une sauvegarde.

**En production chez MédiSphère** : un tableau de bord de capacité de Prometheus lui-même (séries de tête, échantillons par seconde, durée des collectes et des évaluations de règles), alimenté par l'auto-collecte ; c'est l'objet de M21-E30.

---

### M21-E04 — PromQL : sélecteurs, taux et agrégations

**Solution**

Fichier complet et commenté : [`requetes/E04.promql`](fichiers/M21-E04/observabilite/requetes/E04.promql). Les requêtes clés :

```
# Q3 — part des 5xx, 0 quand il n'y a pas d'erreur
(
  sum by (namespace) (rate(mediagenda_http_requests_total{code=~"5.."}[5m]))
  or
  sum by (namespace) (rate(mediagenda_http_requests_total[5m])) * 0
)
/
sum by (namespace) (rate(mediagenda_http_requests_total[5m]))

# Q5 — p95 par route
histogram_quantile(0.95, sum by (le, route) (rate(mediagenda_http_request_duration_seconds_bucket{namespace="mediagenda-recette"}[5m])))

# Q14 — mémoire par pod, avec son nœud
sum by (namespace, pod) (container_memory_working_set_bytes{namespace=~"mediagenda-.*", container="api"})
* on (namespace, pod) group_left (node)
kube_pod_info{namespace=~"mediagenda-.*"}
```

Exemple de sortie (Q5, trafic du script, 4 requêtes/s) :

```
admin@adm01:~$ promtool query instant http://prometheus.apps.par1.medisphere.internal:9090 \
>   'histogram_quantile(0.95, sum by (le, route) (rate(mediagenda_http_request_duration_seconds_bucket{namespace="mediagenda-recette"}[5m])))'
{route="/api/v1/creneaux"} => 0.0912 @[…]
{route="/api/v1/rendez-vous"} => 0.0471 @[…]
{route="/api/v1/rendez-vous/{rdv_id}"} => 0.0238 @[…]
{route="non-routee"} => 0.0048 @[…]
{route="/sante"} => 0.0047 @[…]
```

Question 3 du travail (trois calculs) : agréger **sans** `le` (`sum by (route) (rate(…_bucket[5m]))`) supprime l'étiquette dont `histogram_quantile` a besoin : résultat vide (et, selon la forme, un avertissement « bucket label le is missing »). Calculer le p95 par pod puis faire la moyenne donne une valeur fausse dès que les pods ne reçoivent pas le même trafic : un pod peu chargé, au p95 bas, tire la moyenne vers le bas (écart de 10 à 30 % observé avec deux pods et une répartition 70/30). Question 4 (sans `group_left`) : `Error executing query: found duplicate series for the match group {namespace="…", pod="…"} on the right hand-side of the operation` ou `many-to-many matching not allowed` selon le sens : sans `on`, aucune série ne s'apparie (étiquettes différentes) ; avec `on` sans `group_left`, Prometheus exige une correspondance un-à-un et refuse.

**Explications**

- `rate` sur 5 minutes avec une collecte de 30 s : dix échantillons par fenêtre, assez pour un résultat stable, et l'extrapolation aux bords explique les non-entiers d'`increase`.
- Un vecteur vide n'est pas zéro : `a / b` sans aucune série à gauche est vide. `or vector(0)` ne convient pas ici (il n'a pas d'étiquette `namespace`) ; `… * 0` fournit un zéro **avec les bonnes étiquettes**.
- La route `non-routee` vient des 404 du script : FastAPI ne trouve pas de modèle de route pour un chemin inconnu… sauf `/api/v1/rendez-vous/999999999`, qui correspond au modèle `{rdv_id}` et répond 404 **depuis** le gestionnaire. Lire les étiquettes, c'est lire le code.
- `absent()` renvoie `{job="medinotif"} 1` quand rien ne correspond, **rien** sinon : c'est la base d'une alerte « cible disparue » (E15).
- La sous-requête `[1h:1m]` évalue l'expression intérieure toutes les minutes sur une heure ; `max_over_time` en prend le maximum. Coûteuse : à réserver aux tableaux de bord et aux règles d'enregistrement.

**Alternatives** : les règles d'enregistrement (E14) précalculent les agrégats coûteux (`job:mediagenda_requetes:taux5m`) ; les histogrammes **natifs** de Prometheus 3 (un seul échantillon par série, compartiments exponentiels) simplifient `histogram_quantile` (plus d'étiquette `le`) mais exigent un client qui les expose : le client Python les expose sur option, pas MédiAgenda aujourd'hui.

**Pièges classiques**

- `rate(sum(...))` au lieu de `sum(rate(...))` : on somme des compteurs de pods qui redémarrent à des moments différents, puis `rate` voit des « remises à zéro » fantômes. Toujours `rate` d'abord, `sum` ensuite. (PromQL refuse d'ailleurs `rate` sur un vecteur instantané : il faut une sous-requête pour faire l'erreur.)
- Comparer `code="5xx"` au lieu de `code=~"5.."` : MédiAgenda expose des codes exacts.
- Oublier d'exclure les sondes (`/sante`, `/pret`, `/metrics`) du débit « utilisateurs » : en dev, sans trafic, elles sont tout le trafic.
- Lire `histogram_quantile` comme une mesure exacte : c'est une **interpolation linéaire** dans un compartiment ; avec les bornes par défaut (0,25 puis 0,5 s), « p95 = 0,4 s » veut dire « entre 0,25 et 0,5 s ».

**En production chez MédiSphère** : ces requêtes deviennent des règles d'enregistrement (E14), puis les SLI des SLO de MédiAgenda (E26). Julien reçoit le fichier comme documentation vivante, testé par la CI (syntaxe) et par le check du module (données).

---

### M21-E05 — Grafana : sources de données, exploration, premier tableau de bord

**Solution**

1. Compte `<MOI>` : *Administration > Users and access > Users > New user*, puis rôle **Admin** dans l'organisation (*Organization users*). `admin` est un compte partagé, sans trace de qui a fait quoi : il devient un bris de glace (mot de passe dans le Vault, usage noté au journal).
2. La source `Prometheus` est **provisionnée** : déclarée dans la ConfigMap `kps-grafana-datasource` (étiquette `grafana_datasource: "1"`), lue par le conteneur *sidecar* `grafana-sc-datasources` qui écrit le fichier de provisionnement et demande un rechargement. Une source provisionnée n'est pas modifiable dans l'interface. URL : `http://kps-prometheus.supervision:9090/` ; *Test* : « Successfully queried the Prometheus API ».
3. `$__rate_interval` vaut au moins quatre fois l'intervalle de collecte déclaré de la source (30 s ici, réglé par le chart dans `timeInterval`), et s'adapte au zoom : un `[5m]` codé en dur est trop court sur un graphique de 30 jours (Grafana demande un point toutes les quelques heures) ou trop long pour voir un pic.
4. Tableau : JSON de référence [`mediagenda-apercu.json`](fichiers/M21-E05/grafana/mediagenda-apercu.json) (importable par *Dashboards > New > Import*). Variables `datasource` (type *Data source*, `prometheus`) et `environnement` (`label_values(up{job="mediagenda"}, namespace)`) ; statistiques en tête (pods qui répondent, part des 5xx avec `or vector(0)` sous l'agrégat global, p95, cache) ; séries temporelles (débit par code hors sondes, p50/p95 par route, CPU et mémoire par pod) ; unités `reqps`, `s`, `percentunit`, `bytes`.
5. Sans trafic : la part des 5xx affiche « No data » ou `NaN` (0/0) ; la latence aussi. « Pas de données » est la réponse honnête pour la latence (aucune requête mesurée) ; pour la part des 5xx, une option de valeur *No value* = « aucune requête » vaut mieux qu'un 0 % trompeur. Les sondes de Kubernetes, elles, continuent : c'est pourquoi le débit les exclut.
6. L'export « classique » est au schéma `schemaVersion` 41 environ (modèle v1) ; selon l'option d'export, Grafana 13 peut aussi produire le modèle **v2** (`apiVersion: dashboard.grafana.app/v2…`, `spec.elements`). Les requêtes référencent `${datasource}` si la variable a été utilisée, sinon l'UID `prometheus` en dur : E17 interdira l'UID en dur.
7. Compte de service : interface, ou script [`grafana-jeton-checks.sh`](fichiers/M21-E05/outils/grafana-jeton-checks.sh) (idempotent pour le compte, rotation du jeton, identifiants d'administration lus dans `grafana-admin.env` 600 et passés à `curl` par `-K`, jeton écrit avec `umask 077`, jamais affiché) :
   ```
   admin@adm01:~$ ./grafana-jeton-checks.sh 90
   Compte de service wb-checks créé (id 2, rôle Viewer).
   Jeton écrit dans /home/admin/.config/workbook/grafana-checks.token (expire dans 90 jours).
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' -K <(printf 'header = "Authorization: Bearer %s"\n' "$(<~/.config/workbook/grafana-checks.token)") \
   >   https://grafana.apps.par1.medisphere.internal/api/datasources
   403
   ```
8. `acces.md` : tableau des trois adresses, réseau autorisé, authentification (aucune pour Prometheus et Alertmanager : filtrage réseau ; comptes nominatifs pour Grafana), bris de glace, rotation du jeton tous les 90 jours (date au registre des secrets).

**Explications**

Grafana ne garde aucune métrique : il stocke tableaux, dossiers, comptes, préférences (SQLite sur le volume `ceph-rbd`). Perdre ce volume, c'est perdre les tableaux faits à la main : c'est la raison des tableaux *as code* (E17). Les variables sont substituées **avant** l'envoi de la requête ; `$__rate_interval` est calculé par Grafana à partir de l'intervalle de la source et de la résolution du panneau.

**Alternatives** : provisionner le tableau tout de suite par une ConfigMap (étiquette `grafana_dashboard: "1"`, sidecar) — c'est E17, avec validation en CI ; Grafana Git Sync (GA en 13) synchronise des tableaux avec un dépôt Git depuis l'interface : séduisant, mais l'écriture se fait depuis Grafana vers Git, à l'envers de notre chemin MR → Argo CD.

**Pièges classiques**

- Garder l'UID de la source en dur dans le JSON : le tableau casse le jour où la source change (Thanos, E24).
- Faire une moyenne de pourcentages entre environnements dans une statistique : additionner les taux, puis diviser.
- Jeton de compte de service sans expiration, ou rôle Editor « pour être tranquille » : le check d'E05 refuse un jeton qui liste les sources de données.
- Passer le mot de passe d'admin en argument de `curl -u` : visible dans `ps` et dans l'historique du shell.

**En production chez MédiSphère** : comptes par SSO (M24, Keycloak), équipes et dossiers par OpenTofu (E17), tableaux par MR ; le compte `admin` désactivé ou réservé au bris de glace, son usage alerté (journal d'audit de Grafana, M22).

---

### M21-E06 — Alertmanager : routes, regroupement et courriels

**Solution**

Values complètes à l'état E06 : [`kps/values.yaml`](fichiers/M21-E06/observabilite/kps/values.yaml) (clés `alertmanager.config`, `alertmanager.templateFiles`, `alertmanager.alertmanagerSpec.configMaps`, ConfigMap `racine-medisphere` dans `extraManifests`). Extrait :

```yaml
alertmanager:
  config:
    global:
      smtp_smarthost: smtp.par1.medisphere.internal:25
      smtp_from: alertmanager-k8s@medisphere.internal
      smtp_hello: alertmanager.apps.par1.medisphere.internal
      smtp_require_tls: true
      smtp_tls_config:
        ca_file: /etc/alertmanager/configmaps/racine-medisphere/ca.crt
        min_version: TLS12
    route:
      receiver: plateforme-mail
      group_by: [alertname, namespace]
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      routes:
        - receiver: "null"
          matchers: ['alertname = "Watchdog"']
        - receiver: astreinte-mail
          matchers: ['gravite = "critique"']
        - receiver: astreinte-mail
          matchers: ['severity = "critical"']
```

Gabarit du sujet : `[FIRING:1] EssaiPLAT2206 — avertissement (wb-essais)`, `[RESOLVED] …`.

Vérifications hors ligne (étape 4) :

```
admin@adm01:~/m21/e06$ amtool check-config am.yml
Checking 'am.yml'  SUCCESS
Found:
 - global config
 - route
 - 3 inhibit rules
 - 5 receivers
 - 1 templates
  SUCCESS
admin@adm01:~/m21/e06$ amtool config routes test --config.file=am.yml alertname=Watchdog severity=none
null
admin@adm01:~/m21/e06$ amtool config routes test --config.file=am.yml alertname=X gravite=critique
astreinte-mail
admin@adm01:~/m21/e06$ amtool config routes test --config.file=am.yml alertname=EssaiPLAT2206 gravite=avertissement equipe=plateforme
plateforme-mail
```

Après la synchronisation : `amtool config show` montre la nouvelle configuration ; `alertmanager_config_last_reload_successful` vaut 1. Une configuration refusée laisse l'ancienne en place : l'erreur est dans les journaux du conteneur `config-reloader` et d'`alertmanager` du pod `alertmanager-kps-0`, et l'alerte `AlertmanagerFailedReload` du chart sonne.

Essai (étape 6) : groupe visible tout de suite dans l'interface ; courriel de déclenchement **≈ 30 s** après (`group_wait`) ; l'alerte se termine à `--end` ; courriel de résolution au plus `group_interval` (5 min) après la fin. Étape 7 : `EssaiCritiquePLAT2206` arrive à `astreinte@` ; trois `EssaiPLAT2206` qui ne diffèrent que par `pod`, envoyées pendant `group_wait` : **un** courriel qui les liste (même groupe, `pod` n'étant pas dans `group_by`) ; envoyées après le premier envoi : un second courriel au `group_interval` suivant, avec les trois.

**Explications**

- **Arbre de routage.** Une alerte descend depuis la racine ; la première sous-route qui correspond la prend (sauf `continue: true`) ; sans correspondance, la racine (`plateforme-mail`). Les paramètres de groupe sont hérités.
- **Les trois délais.** `group_wait` : attente avant le **premier** envoi d'un groupe nouveau (réunir les alertes sœurs) ; `group_interval` : attente avant de renvoyer un groupe **qui a changé** ; `repeat_interval` : rappel d'un groupe **inchangé** toujours actif. Avec 4 h, une alerte non résolue rappelle trois fois par nuit, pas toutes les 5 minutes.
- **Watchdog** est une alerte toujours active livrée par le chart : sa présence prouve que Prometheus collecte et évalue ses règles. On ne la notifie pas par courriel ; en M21-E28, la supervision témoin de `mon01` vérifie chaque minute qu'elle est toujours là (elle interroge l'API de requête de la vue globale) et alerte sur son **absence** ; Alertmanager, lui, est surveillé par des sondes à part.
- **La racine dans une ConfigMap**, pas un Secret : c'est un certificat public. L'image d'Alertmanager ne connaît que les autorités publiques, et un `insecure_skip_verify` ouvrirait la porte à n'importe quel serveur qui se ferait passer pour `smtp.par1`.

**Alternatives**

- **`AlertmanagerConfig`** (CRD `v1alpha1` de l'opérateur) : chaque équipe déclare ses routes dans son espace, fusionnées dans la configuration globale (avec un `matcher` forcé sur l'espace). Utile à l'échelle ; ici, une configuration centrale relue par la plateforme suffit (E16 en discute).
- **Configuration dans un Secret géré hors du chart** (`alertmanagerSpec.useExistingSecret` ou `configSecret`) : nécessaire dès qu'un récepteur porte un secret (webhook avec jeton, SMTP authentifié), alimenté par `secrets-k8s.sh` puis External Secrets (M25).
- **Webhook vers un outil d'astreinte** (Grafana OnCall, PagerDuty) : hors du lab ; le courriel vers Mailpit en tient lieu.

**Pièges classiques**

- `group_by: ['...']` (tout regrouper par toutes les étiquettes) : chaque série devient un groupe, un courriel par pod.
- Un récepteur déclaré mais oublié dans les routes : aucune erreur, aucun courriel. `amtool config routes` le montre (il n'apparaît pas dans l'arbre).
- Tester avec `amtool alert add` **sans** `--end` : l'alerte reste active 5 minutes par défaut (`resolve_timeout`) puis se résout ; avec un `--end` dans le passé, elle est aussitôt résolue et rien ne part.
- Écrire le gabarit dans `extraManifests` au lieu de `templateFiles` : Helm interprète les `{{ }}` et casse le rendu.
- Oublier d'adapter le chemin `templates:` dans la copie locale : `amtool check-config` ne trouve pas le gabarit, ou trouve celui d'un autre dossier.
- Configuration invalide fusionnée : Alertmanager garde l'**ancienne** sans le dire ailleurs que dans ses journaux et dans `alertmanager_config_last_reload_successful`. D'où la CI d'E07 qui vérifie avant la fusion.

**En production chez MédiSphère** : trois réplicas d'Alertmanager en cluster (E24), webhook vers la supervision témoin (E28), routage par équipe et heures ouvrées (E16), politique d'alerte écrite (E32) ; chaque alerte qui réveille a un runbook (E22).

---

### M21-E07 — Les métriques de MédiAgenda : ServiceMonitor et PodMonitor

**Solution**

*A. Le piège du canary.* Hors canary, Argo Rollouts pose sur **les deux** Services (`mediagenda` et `mediagenda-canary`) le sélecteur `rollouts-pod-template-hash=<révision stable>` : ils désignent les mêmes pods. Pendant un canary, `mediagenda` garde la révision stable et `mediagenda-canary` passe à la nouvelle. Un ServiceMonitor sur `mediagenda` ne voit donc jamais les pods canary ; sur les deux Services, il collecte deux fois chaque pod hors canary (séries en double, débits doublés). Solution : un Service **sans adresse** dédié à la collecte, qui sélectionne les pods par les seules étiquettes du chart.

*B. Les components.* [`mediagenda-deploiement/components/supervision/`](fichiers/M21-E07/mediagenda-deploiement/components/supervision/) :
- `service-metriques.yaml` : Service `mediagenda-metriques`, `clusterIP: None`, sélecteur `name`/`instance`/`component` du chart, port `http` → `targetPort: http`, étiquettes `app.kubernetes.io/name: mediagenda` et `medisphere.internal/collecte: prometheus` ;
- `servicemonitor.yaml` : ServiceMonitor `mediagenda` (étiquette de sélection), `jobLabel: app.kubernetes.io/name` (job `mediagenda`), port `http`, `/metrics`, 30 s, et un relabeling qui copie `__meta_kubernetes_pod_label_rollouts_pod_template_hash` vers `rollouts_pod_template_hash` (la révision, pour M21-E18) ;
- `podmonitor-db.yaml` : PodMonitor `mediagenda-db`, sélecteur `cnpg.io/cluster: mediagenda-db` et `cnpg.io/podRole: instance`, port `metrics`, `jobLabel: cnpg.io/cluster`.

Inclusion dans les trois overlays, **avant** `../../components/livraison` qui reste le dernier (M17-E09) : [`kustomization.extrait.yaml`](fichiers/M21-E07/mediagenda-deploiement/overlays/kustomization.extrait.yaml). MédiDoc : [`medidoc-deploiement/components/supervision/`](fichiers/M21-E07/medidoc-deploiement/components/supervision/) (Service `medidoc-metriques`, ServiceMonitor `medidoc`, job `medidoc`).

```
admin@adm01:~/src/mediagenda-deploiement$ for e in dev recette prod; do kustomize build overlays/$e | yq 'select(.kind == "ServiceMonitor" or .kind == "PodMonitor") | .kind + " " + .metadata.namespace + "/" + .metadata.name'; done
ServiceMonitor mediagenda-dev/mediagenda
PodMonitor mediagenda-dev/mediagenda-db
…
```

*C. Le flux.* [`collecte-prometheus.yaml`](fichiers/M21-E07/k8s/composants/reseau/politiques/collecte-prometheus.yaml) : une `CiliumClusterwideNetworkPolicy` qui sélectionne les pods des espaces portant `medisphere.internal/equipe`, autorise l'entrée depuis les pods `app.kubernetes.io/name: prometheus` de `supervision` sur 8000, 8080 et 9187, avec `enableDefaultDeny: {ingress: false, egress: false}`. La plateforme l'écrit parce que l'AppProject des équipes leur interdit les politiques réseau (M20-E07) et parce qu'un flux de collecte doit être le même partout.

*D. `plateforme/observabilite`.* Structure : [`kustomization.yaml`](fichiers/M21-E07/observabilite/kustomization.yaml) racine (espace `supervision`, `labels` qui pose l'étiquette de sélection sur tout ce qu'elle produit, sans toucher aux sélecteurs), [`regles/`](fichiers/M21-E07/observabilite/regles/kustomization.yaml) et [`scrape/`](fichiers/M21-E07/observabilite/scrape/kustomization.yaml) vides, [`README.md`](fichiers/M21-E07/observabilite/README.md). CI : [`.gitlab-ci.yml`](fichiers/M21-E07/observabilite/.gitlab-ci.yml) — composant `qualite`, job `promql` ([`outils/verifier-promql.sh`](fichiers/M21-E07/observabilite/outils/verifier-promql.sh) dans l'image `prometheus`), jobs `alertmanager:extraire` (image `yq`) et `alertmanager:verifier` (image `alertmanager` : `amtool check-config` puis [`outils/tester-routes.sh`](fichiers/M21-E07/observabilite/outils/tester-routes.sh) sur [`alertmanager/routes-tests.txt`](fichiers/M21-E07/observabilite/alertmanager/routes-tests.txt)). Application [`plateforme/observabilite.yaml`](fichiers/M21-E07/gitops/plateforme/observabilite.yaml) (kustomize, `path: .`, avec finaliseur : elle ne porte ni CRD ni volume).

Essai de l'étape 9 (récepteur `plateforme-mal` dans une route) :

```
$ amtool check-config alertmanager.yaml
Checking 'alertmanager.yaml'  FAILED: undefined receiver "plateforme-mal" used in route
```

Résultat dans Prometheus :

```
admin@adm01:~$ promtool query instant http://prometheus.apps.par1.medisphere.internal:9090 'count by (namespace, job) (up{job=~"mediagenda|mediagenda-db|medidoc"} == 1)'
{job="mediagenda", namespace="mediagenda-dev"} => 1
{job="mediagenda", namespace="mediagenda-prod"} => 3
{job="mediagenda", namespace="mediagenda-recette"} => 2
{job="mediagenda-db", namespace="mediagenda-dev"} => 1
{job="mediagenda-db", namespace="mediagenda-prod"} => 3
{job="mediagenda-db", namespace="mediagenda-recette"} => 1
{job="medidoc", namespace="medidoc-dev"} => 1
```

**Explications**

- Un ServiceMonitor produit un job `serviceMonitor/<espace>/<nom>/<index du point>` dont la découverte (`role: endpointslice`) est limitée à l'espace du ServiceMonitor (sans `namespaceSelector`) ; le relabeling garde les points de terminaison des Services qui ont les bonnes étiquettes et le bon **nom** de port, puis ajoute `namespace`, `service`, `pod`, `container`, `endpoint`, et `job` (nom du Service, ou valeur de l'étiquette désignée par `jobLabel`).
- Un PodMonitor découvre directement les **pods** (`role: pod`) et garde le conteneur dont un port porte le nom indiqué. C'est le bon outil quand aucun Service ne désigne chaque instance : les Services de CNPG désignent des **rôles** (`-rw` le primaire, `-ro` les réplicas), et un primaire qui bascule changerait de Service.
- Le Service sans adresse ne crée aucune règle de traduction (pas d'adresse virtuelle) : il ne sert qu'à publier des points de terminaison. Les pods canary y figurent parce que le sélecteur n'a pas l'empreinte de révision ; `rollouts_pod_template_hash` permet ensuite de séparer les deux révisions dans une requête.
- `labels` (et non `commonLabels`) dans la kustomization : `commonLabels` modifierait aussi les **sélecteurs**, qui ne doivent pas changer.

**Alternatives**

- **PodMonitor pour MédiAgenda aussi** : simple et naturellement compatible avec le canary ; on garde le ServiceMonitor parce que c'est la forme que les équipes rencontrent partout (charts publics) et que le Service de collecte documente ce qui est exposé.
- **Annotations `prometheus.io/scrape`** : non lues par l'opérateur (convention d'une configuration de découverte écrite à la main) ; à éviter, elles donnent l'illusion d'une collecte.
- **`AlertmanagerConfig` et `PrometheusRule` dans les dépôts des équipes** : prévu en E29 (`ruleNamespaceSelector`, RBAC) ; au palier 1, les règles restent à la plateforme.

**Pièges classiques**

- Port **numéroté** dans le ServiceMonitor (`targetPort: 8000`) : déprécié, et cassé au premier changement de port ; toujours le **nom**.
- `jobLabel` qui désigne une étiquette absente du Service : le job prend le nom du Service (`mediagenda-metriques`) et les requêtes sur `job="mediagenda"` ne renvoient rien.
- Inclure `components/supervision` **après** `livraison` : sans effet ici, mais la règle du M17 (livraison en dernier) existe pour les remplacements d'images ; la garder évite une surprise.
- Oublier la politique réseau : cibles `down` avec `context deadline exceeded` (le paquet est jeté en silence par le refus par défaut) ; Hubble montre `DROPPED (Policy denied)`.
- Écrire la politique de collecte **sans** `enableDefaultDeny` à `false` : dans un espace d'équipe qui n'aurait pas encore son refus par défaut, elle fermerait tout le reste (la Gateway ne joindrait plus l'application).
- Le Service `mediagenda-metriques` doit vivre dans le dépôt de l'équipe : s'il était dans `plateforme/observabilite`, l'Application `observabilite` déploierait dans les espaces des équipes, ce que son projet ne permet pas.

**En production chez MédiSphère** : un modèle de `components/supervision` publié dans la documentation de la plateforme (« publier ses métriques »), une alerte « cible absente » par job (E15), une limite d'échantillons par collecte (`sampleLimit`, E14) imposée aux moniteurs des équipes.

---

### M21-E08 — Superviser les VMs : node_exporter partout

**Solution**

*A. Préparer.* Sur une VM du socle (v1) : `prometheus-node-exporter` 1.9 du paquet Debian, écoute en HTTP sur l'adresse principale, `/var/lib/prometheus/node-exporter/medisphere.prom` (rôle v1) et, sur `adm01`, les `.prom` des outils `ms-verif-*` (M07, M15, M16). L'empreinte publiée dans `sha256sums.txt` protège contre une archive modifiée **à la source** ou en cache, ce que HTTPS ne couvre pas (il ne protège que le transport) ; et elle épingle **cette** archive : une republication sous le même nom serait refusée.

*B. Le rôle v2.* [`roles/node_exporter/`](fichiers/M21-E08/ansible/roles/node_exporter/) :
- [`defaults/main.yml`](fichiers/M21-E08/ansible/roles/node_exporter/defaults/main.yml) : version 1.12.1, empreinte `b51d8a76aa2a9156a55d501aca6276fae09e262259a5e4e831d2c2222f084e63`, cache sur le contrôleur, TLS, crochets ACME repris du premier certificat de l'hôte ;
- [`tasks/installer.yml`](fichiers/M21-E08/ansible/roles/node_exporter/tasks/installer.yml) : `get_url` (`checksum: sha256:…`, `delegate_to: localhost`, `run_once`), utilisateur système, `unarchive` dans `/opt/node_exporter/<version>/`, lien `/usr/local/bin/node_exporter` ;
- [`tasks/tls.yml`](fichiers/M21-E08/ansible/roles/node_exporter/tasks/tls.yml) : `set_fact` de l'entrée de certificat (id `node-exporter`, groupe `node_exporter`), puis `include_role: certificats_acme` avec `vars: certificats_acme_certificats: [<entrée>]` ;
- [`tasks/main.yml`](fichiers/M21-E08/ansible/roles/node_exporter/tasks/main.yml) : contrôles, `web.yml`, retrait du paquet Debian **puis** démarrage du nouveau service, dossier textfile et `medisphere.prom` conservés, `flush_handlers`, vérification ;
- [`templates/node_exporter.service.j2`](fichiers/M21-E08/ansible/roles/node_exporter/templates/node_exporter.service.j2) : `User=node_exporter`, `CapabilityBoundingSet=` vide, `ProtectSystem=strict`, `ProtectHome=read-only`, `PrivateDevices`, `ProtectKernel*`, `RestrictNamespaces`, `SystemCallFilter=@system-service`, `RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK`, `MemoryDenyWriteExecute` ;
- [`tasks/verifier.yml`](fichiers/M21-E08/ansible/roles/node_exporter/tasks/verifier.yml) : depuis le contrôleur, HTTPS vérifié + version, puis HTTP → 400.

Passerelles : [`group_vars/role_routeur/node_exporter.yml`](fichiers/M21-E08/ansible/inventories/lab/group_vars/role_routeur/node_exporter.yml) — écoute sur `0.0.0.0` (leur route par défaut est le WAN : l'adresse par défaut serait celle du LAN maison) ; la chaîne `input` ne laisse entrer 9100 que depuis `K8S_TRAV` et MGMT. Playbook [`node-exporter.yml`](fichiers/M21-E08/ansible/playbooks/node-exporter.yml) : `hosts: socle:!k8s_par1`, `serial: 1`, `any_errors_fatal` — un hôte à la fois parce que l'émission ACME **arrête** le service qui tient le port 80 (nginx de NetBox, Harbor, GitLab) le temps du défi : deux services du socle arrêtés en même temps, c'est un incident.

*C. Les flux.* Extraits : [`pare_feu.extrait.yml`](fichiers/M21-E08/ansible/inventories/lab/group_vars/role_routeur/pare_feu.extrait.yml) (transit `$K8S_TRAV` → `[$V_MGMT, $V_INFRA, $V_DMZ]` en 9100 ; entrée des passerelles depuis `$K8S_TRAV` et MGMT), [`pare_feu_local.extrait.yml`](fichiers/M21-E08/ansible/inventories/lab/group_vars/socle/pare_feu_local.extrait.yml) (9100 depuis les trois travailleurs et MGMT, dans `pare_feu_local_communes`).

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/routeurs.yml --limit gw01 --check --diff
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/routeurs.yml --limit gw01 && uv run ansible-playbook playbooks/routeurs.yml --limit gw02
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/pare-feu-local.yml
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/node-exporter.yml --limit mon01
…
TASK [node_exporter : /metrics répond en HTTPS avec un certificat vérifié pour le nom de l'hôte] ***
ok: [mon01 -> localhost]
TASK [node_exporter : Le HTTP en clair est refusé] *****************************
ok: [mon01 -> localhost]
admin@adm01:~$ curl -s https://mon01.par1.medisphere.internal:9100/metrics | grep ^node_exporter_build_info
node_exporter_build_info{branch="HEAD",goarch="amd64",goos="linux",goversion="go1.26.5",revision="6044da7…",tags="unknown",version="1.12.1"} 1
admin@adm01:~$ ssh mon01 'systemd-analyze security node_exporter.service | tail -1'
→ Overall exposure level for node_exporter.service: 1.9 OK :-)
```

(Le score exact dépend de ta version de systemd ; au-delà de 3, relis les directives.)

*D. Les cibles.* [`supervision-cibles.yml`](fichiers/M21-E08/ansible/playbooks/supervision-cibles.yml) : `nb_lookup` sur `virtual-machines` (`tag=socle status=active`), une cible par VM (`role` tiré de la première étiquette `role-*`, `site` du site NetBox), garde-fou (au moins 10 cibles), `git switch --force-create maj/cibles-vms origin/main`, gabarit [`scrapeconfig-vms.yaml.j2`](fichiers/M21-E08/ansible/playbooks/templates/scrapeconfig-vms.yaml.j2), puis, si le fichier a changé, validation et `git push -o merge_request.create -o merge_request.target=main …`. `scrape/kustomization.yaml` liste `vms.yaml` : [`scrape/kustomization.yaml`](fichiers/M21-E08/observabilite/scrape/kustomization.yaml).

ScrapeConfig produite (extrait) :

```yaml
apiVersion: monitoring.coreos.com/v1alpha1
kind: ScrapeConfig
metadata:
  name: vms
  namespace: supervision
  labels:
    medisphere.internal/supervision: "oui"
spec:
  jobName: vms
  scheme: https
  tlsConfig:
    ca:
      configMap: {name: racine-medisphere, key: ca.crt}
  relabelings:
    - sourceLabels: [__address__]
      regex: '([^.:]+)[.:].*'
      targetLabel: instance
      replacement: '${1}'
  staticConfigs:
    - targets: ["adm01.par1.medisphere.internal:9100"]
      labels: {hote: adm01, role: bastion, site: par1, equipe: plateforme}
    …
```

Dans Prometheus : `count(up{job="vms"} == 1)` → 15 ; `count by (version) (node_exporter_build_info{job="vms"})` → `{version="1.12.1"} 15`. Node_exporter arrêté sur une VM : à la collecte suivante, `up{job="vms", instance="dns02"}` passe à 0 et ses séries disparaissent des requêtes instantanées (marqueurs de péremption) ; la cible apparaît en rouge (*connection refused*) ; l'alerte `TargetDown` du chart passerait en *pending* au bout d'une minute… si elle visait ce job (ses règles visent tous les jobs : elle sonnerait après 10 minutes).

Pour une VM d'environnement de module : une étiquette NetBox `supervision` (ou `env-mNN`) et un second fichier généré (`scrape/vms-environnements.yaml`), pour que la disparition d'une VM jetable ne touche pas la liste du socle ; ou un `file_sd`/`http_sd` alimenté par NetBox si les environnements changent trop souvent pour des MR.

**Explications**

- **Pourquoi TLS sans authentification ?** Le TLS donne la confidentialité et l'**authenticité du serveur** (Prometheus est sûr de parler au vrai `dns01`) ; le contrôle d'accès vient du filtrage (bordure + pare-feu local). L'authentification par certificat client (`client_auth_type: RequireAndVerifyClientCert` dans `web.yml`) est discutée en E29 : elle exigerait un certificat client pour Prometheus, à renouveler dans le cluster.
- **Le rechargement du certificat** : node_exporter relit `web.yml` et ses fichiers à chaque connexion ; `cert-renewer@node-exporter` remplace les fichiers et remet leurs droits (groupe `node_exporter`, clé en 0640). Rien à redémarrer.
- **Pourquoi la liste passe par une MR** : NetBox est la vérité de **ce qui existe** ; la MR est la vérité de **ce qu'on supervise**. Une VM retirée de NetBox par erreur ne disparaît pas silencieusement de la supervision : la MR montre la ligne supprimée, quelqu'un la relit.
- **`instance` raccourci** : par défaut `instance` vaut l'adresse de la cible (`adm01.par1.medisphere.internal:9100`) ; le nom court est plus lisible dans les tableaux et les alertes, et l'étiquette `hote` garde l'information explicitement.

**Alternatives**

- **Paquet Debian** : plus simple à mettre à jour, mais en 1.9 et au rythme de Debian ; les collecteurs et options de la 1.12 (TLS par exporter-toolkit récent) justifient l'amont épinglé.
- **Exportateur par Alloy** (M22) : Grafana Alloy embarque un équivalent de node_exporter (`prometheus.exporter.unix`) et peut **pousser** (*remote write*) : utile pour des VMs injoignables depuis le cluster ; au prix d'un agent plus gros.
- **Certificats par le provisioner JWK** dédié (`exporteurs`, avec une politique de noms) émis depuis le contrôleur : évite le port 80 sur les VMs ; demande un provisioner de plus et un secret sur le contrôleur.
- **Découverte `http_sd` depuis NetBox** (greffon `netbox-plugin-prometheus-sd`) : liste toujours fraîche, sans relecture.

**Pièges classiques**

- Démarrer le nouveau service **avant** de retirer le paquet : `bind: address already in use`, le service redémarre en boucle, et la tâche de vérification échoue sur un ancien node_exporter en HTTP.
- `ProtectHome=yes` : le collecteur filesystem perd `/home` (statfs refusé) et l'alerte de disque plein ne verra jamais ce volume.
- `RestrictAddressFamilies` sans `AF_UNIX` : le collecteur systemd échoue (`couldn't get dbus connection`) et `node_systemd_unit_state` disparaît.
- `include_role` avec `certificats_acme_certificats: "{{ … certificats_acme_certificats … }}"` : récursion de gabarit (`recursive loop detected in template string`). Le `set_fact` préalable fige la valeur.
- Émission ACME sur un hôte qui n'a jamais fait d'ACME : `ca01` ne joint pas le port 80 (`error validating challenge … connection refused` ou délai) ; ouvre le flux, ou émets pendant une fenêtre où tu ouvres temporairement le port.
- Nom de la cible ≠ nom du certificat (cible par adresse IP) : `x509: cannot validate certificate for 10.10.20.10 because it doesn't contain any IP SANs`. La cible est le **nom**.
- Oublier le trafic sortant des pods : les paquets de Prometheus vers une VM sortent avec l'adresse du **travailleur** (masquage) ; une règle de pare-feu qui autoriserait 10.240.0.0/16 (les pods) ne correspondrait jamais.
- Passerelles en `node_exporter_adresse` par défaut : écoute sur l'adresse WAN, injoignable depuis le cluster, et exposée vers le LAN maison si la chaîne `input` l'autorisait par erreur.

**En production chez MédiSphère** : alertes de saturation et de santé des VMs (disque, mémoire, horloge, unités systemd en échec) en E15 et E19 ; tableau USE des VMs (E19) ; le playbook `supervision-cibles.yml` planifié chaque nuit dans le pipeline de `plateforme/ansible`, qui n'ouvre une MR que si NetBox a changé.

---

### M21-E09 — Questions : modèle de données et architecture de Prometheus

**Barème** : 2 points par question, total sur 28. En dessous de 20, reprends E03 et E07 avant le palier 2 ; les questions 4 à 7 préparent E14, E30 et E44 ; 9 à 11 préparent E35 et E41 ; 12 et 13 préparent E24.

**1. Format d'exposition.**
```
# HELP mediagenda_http_requests_total Requêtes HTTP traitées
# TYPE mediagenda_http_requests_total counter
mediagenda_http_requests_total{methode="GET",route="/api/v1/creneaux",code="200"} 1843.0
mediagenda_http_requests_total{methode="GET",route="/sante",code="200"} 2311.0
```
Une série est identifiée par son nom **et** l'ensemble exact de ses étiquettes (après ajout des étiquettes de cible). L'horodatage n'est normalement pas exposé : Prometheus attribue l'heure de la collecte (un exportateur **peut** fournir un horodatage, rarement une bonne idée). Le client Python expose aussi `mediagenda_http_requests_created` (horodatage de création de chaque série), utile au traitement des remises à zéro.

**2. Étiquettes de cible et de métrique.** Les étiquettes de **cible** viennent de la découverte et du relabeling (Prometheus, opérateur) ; les étiquettes de **métrique** viennent de l'application. En cas de conflit de nom, par défaut Prometheus garde celle de la cible et renomme celle de l'application en `exported_<nom>` ; avec `honorLabels: true`, il garde celle de l'application. C'est nécessaire pour un exportateur qui parle **au nom d'autres** (kube-state-metrics : son `namespace` est celui du pod décrit, pas le sien ; fédération, Pushgateway) ; dangereux pour une application quelconque, qui pourrait se faire passer pour un autre job.

**3. Réponse B.** `__name__` est une étiquette : `{__name__=~"mediagenda_.*"}` sélectionne toutes les métriques de MédiAgenda. A est faux (on vient de le faire) ; C est faux (la TSDB range des **chunks** par série dans des blocs, pas un fichier par métrique) ; D est faux (une série sans nom est refusée à l'ingestion ; les résultats de calculs, eux, perdent leur nom).

**4. Chemin d'un échantillon.** Collecté, il est ajouté au **bloc de tête** (*head block*) en mémoire, et écrit d'abord dans le **WAL** (*write-ahead log*, `wal/`, segments de 128 Mo) ; toutes les 2 heures, la tête est compactée en un **bloc** immuable sur disque (index + chunks), puis les blocs sont fusionnés en blocs plus longs (compaction, jusqu'à 10 % de la rétention ou 31 jours). Le WAL permet de reconstruire la tête après un arrêt brutal : on ne perd au plus que les dernières secondes non encore écrites (et les écritures du WAL sont groupées). Au redémarrage, la relecture du WAL prend du temps (minutes sur un gros Prometheus) : la sonde de démarrage doit le tolérer.

**5. NFS.** La TSDB suppose un système de fichiers POSIX local (verrous, `mmap`, renommages atomiques, `fsync`) ; NFS en donne une sémantique approximative, et la documentation de Prometheus le déconseille explicitement (corruptions). Choix d'E02 : volume bloc RBD (`ceph-rbd`), vu comme un disque local ext4 par le pod.

**6. Péremption.** Quand la cible disparaît, Prometheus écrit un marqueur de péremption dans ses séries à la collecte suivante : dès lors, une requête instantanée ne les renvoie plus. Sans marqueur (cible jamais revenue, Prometheus redémarré entre-temps), une requête instantanée cherche le dernier échantillon dans les **5 minutes** précédentes (`lookback delta`) : la série « traîne » 5 minutes. Une requête sur la dernière heure montre la série jusqu'à sa disparition : l'historique reste.

**7. Quatre intervalles.** `rate` a besoin d'au moins **deux** échantillons dans la fenêtre ; avec une collecte de 30 s et une fenêtre de 30 s, il n'y en a souvent qu'un (décalage de phase, collecte ratée) : résultat vide ou haché. Quatre intervalles (2 min ici ; 5 min par confort) laissent au moins deux échantillons même si une collecte échoue. `$__rate_interval` de Grafana applique cette règle.

**8. Règle d'enregistrement.** Une expression évaluée périodiquement dont le résultat est enregistré comme une **nouvelle série** : le tableau de bord lit le résultat au lieu de recalculer. Exemple pour E05 : `namespace_route:mediagenda_http_requests:rate5m = sum by (namespace, route) (rate(mediagenda_http_requests_total[5m]))`. Convention `niveau:métrique:opérations` (niveau d'agrégation, nom de la métrique sans `_total`, opérations appliquées) ; MédiSphère la francise en E14 (`job:mediagenda_requetes:taux5m`).

**9. De l'objet à la configuration.** L'opérateur surveille les CR `Prometheus` et les objets sélectionnés (`ServiceMonitor`…) ; à chaque changement, il régénère la configuration et l'écrit (gzip) dans le Secret `prometheus-kps` ; les règles vont dans des ConfigMaps `prometheus-kps-rulefiles-N`. Le conteneur `config-reloader` du pod surveille ces fichiers montés et appelle `/-/reload` de Prometheus. Où regarder : l'étiquette de sélection et l'espace de l'objet ; les journaux de `kps-operator` (objets rejetés, `PrometheusOperatorRejectedResources`) ; le Secret de configuration (le job y est-il ?) ; les journaux de `config-reloader` ; la page *Configuration* et `prometheus_config_last_reload_successful`.

**10. Réponse B.** Dans notre lab, un objet sans l'étiquette de sélection est ignoré **sans aucune erreur** : c'est la cause la plus probable du symptôme décrit. A provoquerait des erreurs `forbidden` dans les journaux de Prometheus ; C donnerait une configuration sans cible mais visible dans *Service discovery* (cibles écartées) ; D donnerait des cibles **présentes** et en échec (`context deadline exceeded`), pas absentes.

**11. Droits RBAC.** La découverte Kubernetes interroge l'API : `endpointslices` (et `services`) pour les ServiceMonitor, `pods` pour les PodMonitor et pour enrichir les cibles (`__meta_kubernetes_pod_*`), `nodes` pour le rôle `node`. `nodes/metrics` donne le droit de lire `/metrics` et `/metrics/cadvisor` des kubelets (et le jeton présenté au kubelet est autorisé par délégation à l'API) ; sans lui, les cibles kubelet sont en `401/403`. Jamais `nodes/proxy`, qui ouvrirait tout le kubelet.

**12. Prometheus par cluster et fédération.** Collecter **près** des cibles évite de faire dépendre la supervision du réseau inter-sites (une coupure ferait croire à une panne de tout un site), réduit la latence et le trafic, et limite l'effet d'une panne de Prometheus à un cluster. La **fédération** : un Prometheus collecte `/federate` d'un autre, avec un filtre `match[]` (ex. les séries de `mon01` au palier 2, E12). Limite : elle ne transporte que le **dernier** échantillon de chaque série à chaque collecte (pas d'historique, pas de rattrapage après une coupure), et elle ne passe pas à l'échelle pour « tout » fédérer : on fédère des agrégats ou des séries choisies ; pour une vue globale complète, on passe à Thanos (E24).

**13. Haute disponibilité.** Deux Prometheus identiques collectent les mêmes cibles indépendamment : ils ont des données **presque** identiques (horodatages différents), aucune réplication entre eux ; on lit l'un ou l'autre, ou on déduplique au moment de la requête (Thanos Query, étiquette externe de réplica, E24). Les deux envoient les mêmes alertes à Alertmanager ; Alertmanager **déduplique** les alertes identiques (mêmes étiquettes) et, en cluster (protocole de bavardage entre réplicas), se coordonne pour qu'un seul réplica notifie.

**14. Limites du pull en E08.** Il faut que Prometheus **joigne** chaque cible : flux à ouvrir à la bordure et sur chaque VM (et le trafic part des nœuds, pas des pods) ; il faut **connaître** les cibles : découverte par NetBox, liste générée et relue ; il faut **authentifier** le serveur collecté : TLS avec un certificat de la PKI et la racine distribuée à Prometheus. Pour des cibles derrière un pare-feu qu'on ne contrôle pas, on inverserait le sens (agent qui pousse, M22-M23).
