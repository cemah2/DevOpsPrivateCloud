# Module 21 — Palier 2 : Opérationnel

Le palier 1 a posé la pile : kube-prometheus-stack sous Argo CD dans `supervision`, Prometheus et Alertmanager joignables depuis MGMT, Grafana, le projet `plateforme/observabilite`, les ServiceMonitor de MédiAgenda et MédiDoc, node_exporter sur les VMs. Ce palier traite les **tickets du quotidien** d'une équipe qui exploite une supervision : faire entrer dans Prometheus tout ce qui parle déjà le format Prometheus (Ceph, HAProxy, PowerDNS, GitLab, Harbor), monter sur `mon01` une supervision **hors du cluster** (sondes blackbox, Proxmox VE), maîtriser les **étiquettes** (relabeling, cardinalité, règles d'enregistrement), écrire des **alertes** qui réveillent pour de bonnes raisons et les **router**, versionner les **tableaux de bord**, brancher Prometheus sur les **canaries** d'Argo Rollouts, superviser le plan de contrôle de Kubernetes. Tu termines en relisant les règles de Lucas, en écrivant les premiers runbooks d'alerte et en diagnostiquant une saturation par les seules métriques.

> **Rappels du module** (introduction) : tout objet de supervision vit dans **`plateforme/observabilite`** (clone `~/src/observabilite` sur `adm01`), passe par une MR relue et arrive dans le cluster par l'Application Argo CD **`observabilite`** (règles, `ScrapeConfig`, tableaux) ou **`kube-prometheus-stack`** (valeurs du chart, `kps/values.yaml`) ; les ServiceMonitor et PodMonitor des applications vivent dans leurs dépôts `…/deploiement` (composant `components/supervision`). Aucun `kubectl apply` sur les espaces applicatifs. Toute VM se configure par Ansible (`plateforme/ansible`, clone `~/src/ansible`), tout flux réseau passe par le rôle `pare_feu` (`group_vars/role_routeur/pare_feu.yml`) et `docs/socle/matrice-flux.md`. Les vérifications (`lab/bin/check 21 XX`) lisent Prometheus et Alertmanager par 10.10.41.60 et .61, Grafana avec le compte de service `wb-checks`, le cluster avec le compte `wb-checks`, GitLab avec le jeton des checks.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Pile du cluster (palier 1) | Application `kube-prometheus-stack` (release `kps`, `fullnameOverride: kps`, `cleanPrometheusOperatorObjectNames: true`) : CR Prometheus **`kps`** (pods `prometheus-kps-N`), CR Alertmanager **`kps`** (pods `alertmanager-kps-N`), Services internes `kps-prometheus:9090` et `kps-alertmanager:9093`, Services externes `prometheus-externe` (10.10.41.60) et `alertmanager-externe` (10.10.41.61), Grafana `kps-grafana` ; source de données Grafana `prometheus` (UID) |
| Sélecteur commun | Prometheus ne prend que les objets (`ServiceMonitor`, `PodMonitor`, `PrometheusRule`, `ScrapeConfig`, `Probe`) étiquetés **`medisphere.internal/supervision: "oui"`**, dans tous les espaces |
| Étiquettes externes | `cluster: k8s-par1`, `site: par1` (`prometheusSpec.externalLabels`) |
| Dépôt `plateforme/observabilite` | `kps/values.yaml`, `regles/` (PrometheusRule), `scrape/` (ScrapeConfig), `alertmanager/routes-tests.txt` (essais de routage, E07), `tableaux/<equipe>/` (JSON), `tests/` (`promtool test rules`), `requetes/`, `outils/`, `.gitlab-ci.yml` (étape `valider`, jobs `promql`, `alertmanager:extraire`, `alertmanager:verifier`, E07) ; un `kustomization.yaml` par dossier, référencé par celui de la racine (espace `supervision`, étiquette de sélection posée sur tout ce qui en sort) |
| Collecte de MédiAgenda (E07) | Service de collecte sans adresse `mediagenda-metriques` (tous les pods de l'API, stables et canary, une fois), ServiceMonitor `mediagenda` (`job="mediagenda"`, étiquette `rollouts_pod_template_hash`), PodMonitor `mediagenda-db` (instances CloudNativePG, port `metrics`) ; même schéma pour MédiDoc (`medidoc-metriques`, `medidoc`) |
| Racine MédiSphère dans `supervision` | ConfigMap `racine-medisphere`, clé `ca.crt` (déclarée dans `kps/values.yaml` en E06, utilisée par Prometheus pour les cibles en HTTPS depuis E08) |
| Étiquettes d'alerte | `gravite` (`critique`, `avertissement`, `info`), `equipe` (`plateforme`, `mediagenda`, `medidoc`) ; annotations `resume`, `description`, `runbook_url` |
| Récepteurs d'Alertmanager (E06) | `"null"` (jamais notifié), `plateforme-mail` (`plateforme@medisphere.internal`), `astreinte-mail` (`astreinte@`), `mediagenda-mail` (`mediagenda@`), `medidoc-mail` (`medidoc@`) ; configuration sous la clé `alertmanager.config` de `kps/values.yaml`, gabarit de sujet `medisphere.tmpl` |
| `mon01` (10.10.20.19) | Mailpit (M19) ; à partir d'E11 : Prometheus **témoin** 3.13 LTS (9090), Alertmanager témoin 0.34 (9093), blackbox_exporter 0.29 (9115, local) ; E12 : prometheus-pve-exporter 3.10 (9221, local) ; rôle Ansible `supervision_temoin` |
| Jobs fédérés depuis `mon01` (E12) | `blackbox`, `pve`, `hyperviseurs` |
| Runbooks | `docs/observabilite/metriques/runbooks/RB-210-modele-runbook-alerte.md` (modèle), `RB-211-mediagenda-erreurs.md`, `RB-212-mediagenda-latence.md`, `RB-213-disque-plein.md` (E22) ; liens `runbook_url` vers `https://git01.par1.medisphere.internal/plateforme/medisphere/-/blob/main/docs/observabilite/metriques/runbooks/…` |
| Travail personnel | `~/m21/eXX/` sur `adm01` (essais, sorties, journaux de travail) |

> 💡 **Où vivent les fichiers.** `plateforme/observabilite` décrit **ce que Prometheus collecte, calcule et dit** (cibles hors cluster, règles, routes, tableaux). Ce qui se configure **sur les hôtes** (exportateur d'un service, `gitlab.rb`, mgr Ceph, `mon01`) relève d'Ansible ou, pour `gitlab.rb` et `ceph-par1`, de leurs dépôts habituels (`gitlab.rb` reste géré à la main depuis le M01 ; la configuration de Ceph se fait par `ceph config`, consignée dans `plateforme/ceph`). Ce qui concerne **une application** (ServiceMonitor, Rollout) va dans son dépôt `…/deploiement`.

> ⚠️ **Mémoire.** Ce palier ajoute des exportateurs sur des VMs déjà serrées (`git01` en profil « mémoire contrainte », 8 Go) et une charge volontaire sur la recette (E23). Mesure avant et après (`free -m`, `ps -o rss`), et n'enchaîne jamais E23 avec une autre activité lourde du lab.

Durée indicative du palier : 28 à 34 heures. Ordre conseillé :

```
E10 ─ E13 ─ E14 ─ E15 ─ E16 ─ E21 ─ E22
E11 ─ E12 (fédération : après E10, pour les flux vers le cluster)
E17 ─ E19 (après E14 : les tableaux s'appuient sur les règles d'enregistrement)
E18 (après E13 et E15)
E20 (à tout moment ; un nœud de contrôle à la fois)
E23 en dernier (il mobilise tout le reste)
```

---

### M21-E10 — Exportateurs natifs : Ceph, HAProxy, PowerDNS, Kea, GitLab, Harbor  `LAB` `★★★`

> **Ticket PLAT-2210** — *De : Karim Benali*
> On a node_exporter partout, très bien : on sait qu'une VM a du CPU. Mais personne ne sait si Ceph est en `HEALTH_WARN`, combien de serveurs HAProxy sont `DOWN`, si le récurseur DNS rate des requêtes, si Sidekiq empile des jobs ou si Harbor sature. La plupart de ces logiciels exposent **déjà** des métriques Prometheus : il suffit de les allumer proprement et d'aller les chercher. Pas d'exportateur maison tant qu'un natif existe. Et je veux la liste des flux ouverts, un par un.

**Objectifs pédagogiques**
- Activer l'exportateur intégré d'un logiciel plutôt que d'ajouter un exportateur tiers, et savoir quand ce n'est pas possible.
- Collecter des cibles hors du cluster par des `ScrapeConfig` (prometheus-operator, `v1alpha1`) : cibles statiques, schéma, chemin, paramètres, authentification.
- Comprendre les particularités de collecte de chaque source (mgr Ceph actif/en attente, `honor_labels`, liste blanche de GitLab, composants de Harbor).
- Ouvrir chaque flux au plus juste (bordure, pare-feu local, liste d'adresses autorisées du service) et le documenter.

**Prérequis** : M21-E07 (projet `plateforme/observabilite`, Application `observabilite`), M21-E08 (ScrapeConfig `vms`, racine MédiSphère dans `supervision`).
**Durée indicative** : 4 h.

**Contexte technique**
- Prometheus tourne sur les **travailleurs** : vu des cibles, il arrive avec l'adresse du nœud (10.10.40.61-63 ; groupe `K8S_TRAV` de la matrice des flux). Vers `ceph-par1`, il sort par la carte `eth1` des travailleurs (VLAN 30, 10.10.30.81-83), sans traverser la bordure.
- Sources et ports de référence :

| Source | Où | Exportateur | Port |
|---|---|---|---|
| Ceph Tentacle 20.2 | mgr de `ceph01-03` (10.10.30.51-53) | module `prometheus` du mgr | 9283 |
| HAProxy 3.2 | `lb01`, `lb02` (DMZ) ; `k8s-cp01-03` (API du cluster) | exportateur intégré (service `prometheus-exporter`) | 8405 (à créer) |
| PowerDNS Authoritative 5.0 | `dns01` (webserver déjà actif en 8081, API filtrée), `dns02` | `/metrics` du webserver | 8081 |
| PowerDNS Recursor 5.4 | `dns01`, `dns02` | `/metrics` du webservice (configuration YAML) | 8082 |
| Kea 3.0 | `dns01`, `dns02` | à déterminer (voir travail demandé) | — |
| GitLab 19.5 (omnibus) | `git01` | `/-/metrics` (Rails), gitlab-exporter, Sidekiq, Workhorse, Gitaly | 443, 9168, 8082, 9229, 9236 |
| Harbor 2.15 | `reg01` (activé au M13, ouvert depuis MGMT) | `metric` de `harbor.yml` | 9090 |

- Un `ScrapeConfig` par source dans `scrape/` (`ceph.yaml`, `haproxy.yaml`, `powerdns.yaml`, `gitlab.yaml`, `harbor.yaml`), étiquetés `medisphere.internal/supervision: "oui"`, avec un `jobName` explicite (`ceph`, `haproxy`, `powerdns-autoritaire`, `powerdns-recurseur`, `gitlab-rails`, `gitlab-exporter`, `gitlab-sidekiq`, `gitlab-workhorse`, `gitlab-gitaly`, `harbor`) et les étiquettes de cible `equipe: plateforme` et `role` (`ceph`, `lb`, `k8s-api`, `dns`, `gitlab`, `registre`).
- `gitlab.rb` est géré à la main sur `git01` (M01) : instantané de la VM avant modification (`ms-snapshot`, M00). Le profil « mémoire contrainte » de M01-E30 a coupé la plupart des exportateurs de GitLab : tu en rallumes certains, pas tous.
- Les sections HAProxy se déclarent dans la variable `haproxy_sections` du rôle `haproxy` (M07) ; le rôle valide la configuration (`haproxy -c`) avant de recharger. Sur `lb01`/`lb02`, elle vient de l'inventaire (`group_vars/role_lb/haproxy.yml`) ; sur les nœuds de contrôle, c'est le rôle `k8s_plan_controle` (M14-E03) qui la construit et la passe au rôle `haproxy` : relis `tasks/point_acces.yml` avant de décider où déclarer ta section.

> ⚠️ **Attention** : `gitlab-ctl reconfigure` redémarre des composants de GitLab, la modification du pare-feu de la bordure touche tout le lab, et le HAProxy des nœuds de contrôle porte la VIP de l'API du cluster (applique-le un nœud de contrôle à la fois, `kubectl get nodes` entre deux ; retour arrière : `git revert` et même playbook). Fais l'instantané de `git01` avant, et applique la matrice des flux une passerelle à la fois (`--limit gw01`, vérification, puis `gw02`). Retour arrière : restauration de l'instantané pour `git01` ; `git revert` de la MR et même playbook pour la bordure.

**Travail demandé**
1. **Inventaire.** Pour chaque source, lis la documentation officielle de son exportateur intégré (liens en « Pour aller plus loin ») et note dans `~/m21/e10/inventaire.md` : port, chemin, authentification, ce qui est exposé par défaut, coût éventuel (mémoire, requêtes vers la base). Pour **Kea 3.0**, réponds précisément : existe-t-il un point d'accès Prometheus natif ? Sinon, quelles sont les solutions et laquelle retiendrais-tu ?
2. **Ceph.** Active le module `prometheus` du mgr (`ceph mgr module enable …`, depuis un nœud ou `cephcli01` avec la clé d'administration) et vérifie depuis `adm01` les trois mgr :
   ```
   admin@adm01:~$ for n in 51 52 53; do curl -s -o /dev/null -w "10.10.30.$n : %{http_code} %{size_download}\n" http://10.10.30.$n:9283/metrics; done
   ```
   Explique ce que renvoient le mgr actif et les mgr en attente, puis lis la section *honor_labels* de la documentation : faut-il l'activer ici, et pourquoi ? Consigne les commandes `ceph config …` dans `plateforme/ceph` (MR).
3. **HAProxy.** Ajoute un frontend `fe_metriques` sur le port 8405 de `lb01`, `lb02` et des trois nœuds de contrôle, qui ne sert **que** `/metrics` et **seulement** aux adresses autorisées (travailleurs, `adm01`). Vérifie avec `haproxy -c` (le rôle le fait) et `curl` depuis `adm01`.
4. **PowerDNS.** Rends `/metrics` joignable depuis les travailleurs sur l'autoritaire (8081) et le récurseur (8082) de `dns01` et `dns02`, sans ouvrir l'API d'écriture à qui que ce soit d'autre qu'avant. Quels réglages bornent l'accès (`webserver-allow-from`, `webservice.allow_from`, mot de passe) ? Applique par les rôles `powerdns_auth` et `powerdns_recursor` (M06).
5. **GitLab.** Dans `gitlab.rb`, rallume `gitlab-exporter`, les métriques de Sidekiq, Workhorse et Gitaly sur l'adresse INFRA de `git01`, et ajoute les travailleurs à `monitoring_whitelist`. Mesure la mémoire avant et après (`free -m`, `gitlab-ctl status`). Laisse éteints le serveur Prometheus embarqué, Alertmanager, `postgres_exporter` et `redis_exporter`, et explique pourquoi.
6. **Harbor.** Vérifie que `metric` est actif dans `harbor.yml` (M13) et liste les composants qu'on peut interroger par le paramètre `comp`.
7. **Flux.** Ajoute à `group_vars/role_routeur/pare_feu.yml` les règles `K8S_TRAV` → `lb01`/`lb02` 8405, → `dns01`/`dns02` 8081-8082, → `git01` 9168, 8082, 9229, 9236 (443 est déjà ouvert), → `reg01` 9090 ; vérifie les pare-feu locaux des hôtes (`nft list ruleset`, `firewall-cmd --list-all` sur les nœuds Ceph). Reporte tout dans `docs/socle/matrice-flux.md`.
8. **Collecte.** Écris les `ScrapeConfig`, MR, synchronisation par Argo CD. Contrôle dans l'interface de Prometheus (*Status → Targets*) que chaque job a toutes ses cibles `UP`, puis lance quelques requêtes de sens : état de santé de Ceph, nombre de serveurs HAProxy `DOWN` par backend, taux de réponses `SERVFAIL` du récurseur, taille des files de Sidekiq, nombre d'artefacts par projet Harbor.

**Critères de réussite**
- [ ] Les jobs `ceph`, `haproxy`, `powerdns-autoritaire`, `powerdns-recurseur`, `gitlab-rails`, `gitlab-exporter`, `gitlab-sidekiq`, `gitlab-workhorse`, `gitlab-gitaly` et `harbor` existent et toutes leurs cibles sont `up == 1`.
- [ ] `ceph_health_status` est présent **une seule fois** (le mgr actif) et `haproxy_server_status` couvre les deux répartiteurs et les trois nœuds de contrôle.
- [ ] Le port 8405 ne répond pas à une adresse non autorisée (essai depuis une VM de `vsandbox` ou de l'INFRA) ; l'API d'écriture de PowerDNS reste refusée depuis les travailleurs.
- [ ] Les `ScrapeConfig` sont sur `main` de `plateforme/observabilite` ; les flux sont dans la matrice des flux ; `~/m21/e10/inventaire.md` répond pour Kea.

**Vérification** : `lab/bin/check 21 10`

<details><summary>Indice 1</summary>

Un mgr Ceph en attente répond lui aussi sur 9283 : regarde le code HTTP **et** la taille de la réponse. La documentation du module (`standby_behaviour`) explique les deux comportements possibles ; réfléchis à ce que chacun donne pour la métrique `up` et pour une alerte « cible injoignable ».
</details>

<details><summary>Indice 2</summary>

Dans HAProxy, l'exportateur est un *service* qu'un frontend HTTP appelle par une règle `http-request use-service …` ; une ACL sur l'adresse source et une règle `deny` placées **avant** suffisent à le restreindre. Dans un `ScrapeConfig`, les paramètres d'URL (`params`) valent pour toutes les cibles : pour interroger plusieurs composants de Harbor, une réécriture d'étiquette vers `__param_comp` par cible est plus souple.
</details>

<details><summary>Indice 3</summary>

GitLab répond `404` (et non `403`) sur `/-/metrics` à une adresse absente de `monitoring_whitelist`. Et vu de `git01`, la requête de Prometheus vient-elle de l'adresse du pod, du travailleur, ou des répartiteurs ? Regarde le journal nginx d'omnibus pour le savoir.
</details>

**Pour aller plus loin** (facultatif) : documentation des exportateurs ([Ceph](https://docs.ceph.com/en/tentacle/mgr/prometheus/), [HAProxy](https://www.haproxy.com/documentation/haproxy-configuration-tutorials/alerts-and-monitoring/prometheus/), [PowerDNS Authoritative](https://doc.powerdns.com/authoritative/http-api/index.html), [PowerDNS Recursor](https://doc.powerdns.com/recursor/http-api/prometheus.html), [GitLab](https://docs.gitlab.com/administration/monitoring/prometheus/), [Harbor](https://goharbor.io/docs/2.15.0/administration/metrics/)). Pour Kea, essaie [`kea-exporter`](https://pypi.org/project/kea-exporter/) dans un environnement `uv` sur `dns01` contre le socket de contrôle HTTPS (compte `supervision` du M06-E25) ; mesure son coût et compare avec Stork d'ISC.

---

### M21-E11 — Sondes blackbox et supervision hors cluster sur `mon01`  `LAB` `★★★`

> **Ticket PLAT-2211** — *De : Nadia Roussel*
> Si le cluster tombe, qui nous prévient ? Pas Prometheus, il tombe avec. Je veux une petite supervision **à côté**, sur `mon01`, qui regarde le lab comme un utilisateur : est-ce que GitLab, NetBox, le registre, Grafana, Argo CD et MédiAgenda répondent en HTTPS, est-ce que les passerelles répondent, est-ce que le DNS résout, est-ce que le SMTP accepte nos mails. Et qui m'envoie elle-même un courriel sur `astreinte@` quand ça casse.

**Objectifs pédagogiques**
- Installer un Prometheus et un Alertmanager par binaires amont épinglés par empreinte, avec un rôle Ansible propre (utilisateurs dédiés, unités systemd durcies, validation des configurations avant rechargement).
- Comprendre le modèle de blackbox_exporter : la cible et le module passent en paramètres d'URL, Prometheus interroge l'exportateur, pas la cible (*multi-target exporter pattern*).
- Écrire des modules de sonde HTTPS (racine MédiSphère, échéance du certificat), ICMP (capacité `CAP_NET_RAW`), DNS et SMTP avec STARTTLS.
- Déclarer les cibles dans des fichiers (`file_sd_configs`) relus à chaud.

**Prérequis** : M19 (`mon01`, Mailpit), M04 (rôles Ansible, pipeline protégé), M21-E06 (Alertmanager, Mailpit).
**Durée indicative** : 4 h.

**Contexte technique**
- Versions : Prometheus **3.13 LTS** (la LTS, pas la 3.15 du cluster : un témoin bouge le moins possible), Alertmanager 0.34, blackbox_exporter 0.29 ; archives `linux-amd64` des versions publiées sur GitHub, empreintes relevées dans le fichier `sha256sums.txt` de chaque version et inscrites dans les variables du rôle.
- Rôle `supervision_temoin` dans `plateforme/ansible`, playbook `playbooks/supervision-temoin.yml` (hôte `mon01`), variables dans `inventories/lab/host_vars/mon01/supervision_temoin.yml`.
- Écoutes : Prometheus `0.0.0.0:9090`, Alertmanager `0.0.0.0:9093` (MGMT seulement par le pare-feu ; pas de grappe : un seul Alertmanager témoin), blackbox `127.0.0.1:9115`.
- Rétention du témoin : 30 jours ; données dans `/var/lib/prometheus`.
- Un seul job de sondes, nommé **`blackbox`** (E12 le fédère) ; cibles dans `/etc/prometheus/cibles/blackbox-*.yml`, chaque groupe portant une étiquette `module`.
- Sondes attendues :

| Module | Cibles |
|---|---|
| `https_2xx` | `https://git01.par1.medisphere.internal/-/liveness`… (à toi de choisir l'URL qui prouve le service : GitLab, NetBox `nbx01`, registre, `grafana.apps…`, `argocd.apps…`, `mediagenda.apps…`) |
| `icmp` | VIP des passerelles des VLAN 10, 20, 30, 40, 70 |
| `dns_soa` | `dns01` et `dns02` (SOA de `par1.medisphere.internal` par le récurseur) |
| `smtp_starttls` | `smtp.par1.medisphere.internal:25` |

- Alertmanager témoin : courriels via `smtp.par1.medisphere.internal:25` (STARTTLS vérifié par la racine MédiSphère du magasin système), expéditeur `supervision-temoin@medisphere.internal`, récepteur unique `astreinte-mail`.
- Flux : `mon01` → les cibles (HTTPS, ICMP, DNS ; la plupart traversent la bordure). MGMT → `mon01` 9090 et 9093 existe depuis le M19.

> ⚠️ **Attention** : `mon01` porte Mailpit, dont dépendent les courriels de GitLab, d'Argo CD et d'Alertmanager. 3 Go de mémoire : vérifie `free -m` après installation (le témoin doit rester sous 500 Mio). Avant la première exécution du playbook, `--check --diff`.

**Travail demandé**
1. Lis *Multi-target exporter pattern* (documentation de Prometheus) et le fichier d'exemple de blackbox_exporter. Dans `~/m21/e11/journal.md` : pourquoi la cible apparaît-elle en `__param_target` ? Que vaut `up` d'une cible blackbox dont le site est en panne, et quelle métrique dit vraiment si la sonde a réussi ?
2. Écris le rôle `supervision_temoin` : utilisateurs système sans shell, téléchargement vérifié par empreinte, répertoires, configurations rendues par gabarits **validées avant d'être posées** (`promtool check config`, `amtool check-config`, `blackbox_exporter --config.check`), unités systemd durcies (`ProtectSystem`, `NoNewPrivileges`, capacité `CAP_NET_RAW` pour blackbox seulement), rechargement par signal plutôt que redémarrage. Variables documentées dans `meta/argument_specs.yml`. `ansible-lint` (profil `production`) propre.
3. Écris les quatre modules de sonde et les fichiers de cibles. Pour chaque URL HTTPS, explique ton choix de chemin (une page qui prouve que le service **fonctionne**, pas seulement que nginx répond).
4. Écris trois règles d'alerte du témoin (`/etc/prometheus/regles/temoin.yml`) : sonde en échec, certificat à moins de 14 jours de son échéance, cible du témoin injoignable ; et la configuration d'Alertmanager témoin.
5. Ouvre les flux `mon01` → cibles dans la matrice (une MR), applique, puis le playbook. Vérifie depuis `adm01` : `http://mon01.par1.medisphere.internal:9090/targets`, et la requête `probe_success`.
6. Provoque une panne contrôlée : arrête le service HTTP d'une cible **de test** (par exemple, une sonde vers un port fermé ajoutée temporairement), constate l'alerte, le courriel dans Mailpit (`astreinte@`), puis la résolution. Retire la cible de test.

**Critères de réussite**
- [ ] `prometheus`, `alertmanager` et `blackbox_exporter` sont actifs sur `mon01`, aux versions demandées, sous des utilisateurs dédiés ; blackbox n'écoute que sur 127.0.0.1.
- [ ] Le job `blackbox` du témoin sonde au moins 6 URL HTTPS, 5 passerelles, 2 serveurs DNS et le SMTP ; toutes les sondes réussissent (`probe_success == 1`).
- [ ] Les règles du témoin sont chargées sans erreur ; Alertmanager témoin route vers `astreinte@medisphere.internal`.
- [ ] Un courriel d'alerte du témoin (cible de test) est arrivé dans Mailpit ; la cible de test est retirée.
- [ ] Le rôle et le playbook sont sur `main` de `plateforme/ansible`.

**Vérification** : `lab/bin/check 21 11`

<details><summary>Indice 1</summary>

La réécriture classique tient en quatre règles : l'adresse découverte devient `__param_target`, `__param_target` devient `instance`, `__address__` devient l'adresse de l'exportateur, et l'étiquette `module` du groupe de cibles devient `__param_module`. Une seule `job_name` suffit pour tous les modules.
</details>

<details><summary>Indice 2</summary>

Un module ICMP sans privilège échoue avec `socket: operation not permitted`. Deux voies : la capacité `CAP_NET_RAW` donnée au seul processus (`AmbientCapabilities` et `CapabilityBoundingSet` dans l'unité), ou `net.ipv4.ping_group_range`. Pour la validation avant pose, la directive `validate` d'`ansible.builtin.template` passe un fichier **temporaire** : les chemins relatifs (`rule_files`) ne fonctionneront plus.
</details>

<details><summary>Indice 3</summary>

Pour SMTP, le prober `tcp` sait enchaîner `expect`/`send` puis basculer en TLS (`starttls: true`) au milieu de l'échange : l'exemple officiel de blackbox_exporter en contient un. Lis la bannière de Mailpit (`nc smtp.par1.medisphere.internal 25`) avant d'écrire tes expressions.
</details>

**Pour aller plus loin** (facultatif) : [blackbox_exporter](https://github.com/prometheus/blackbox_exporter/blob/master/CONFIGURATION.md) ; ajoute une sonde `http` avec `fail_if_body_not_matches_regexp` sur le contenu JSON de `/sante` de MédiAgenda (la version déployée), et une sonde TCP sur le port 22 de `git01` (clones SSH).

---

### M21-E12 — Proxmox VE et PBS : pve-exporter  `LAB` `★★`

> **Ticket PLAT-2212** — *De : Claire Morel*
> Le jour où `pve01` manquera de mémoire ou de disque, tout le lab tombera d'un coup, cluster compris. Je veux ses chiffres (et ceux de `pbs01`) dans la supervision, mais **pas** un Prometheus du cluster qui parle directement à l'hyperviseur : c'est `mon01` qui le fait, avec un jeton en lecture seule. Le cluster récupère ce dont il a besoin chez `mon01`.

**Objectifs pédagogiques**
- Créer une identité Proxmox en lecture seule (jeton d'API, rôle `PVEAuditor`) et la restreindre au pare-feu (IPSet).
- Installer un exportateur Python dans un environnement `uv` et le lancer en service durci.
- Superviser l'hyperviseur et le serveur de sauvegarde par node_exporter, depuis `mon01` seulement.
- Fédérer une partie des séries du témoin dans le Prometheus du cluster (`/federate`, `match[]`, `honor_labels`).

**Prérequis** : M21-E11, M21-E08 (rôle `node_exporter`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Identité : utilisateur `wb-supervision@pve` (le créer s'il n'existe pas sur `pve01`), jeton `prometheus` avec séparation des privilèges, rôle `PVEAuditor` sur `/` pour le jeton. Secret du jeton dans Ansible Vault `critique` (`inventories/lab/host_vars/mon01/vault-critique-supervision.yml`) et, pour toi, dans `~/.config/workbook/pve-supervision.env` (600).
- prometheus-pve-exporter **3.10** (PyPI `prometheus-pve-exporter`) dans un environnement `uv` sous `/opt/pve-exporter`, écoute **127.0.0.1:9221**, configuration `/etc/prometheus/pve.yml` (600, propriétaire l'utilisateur du service). Le certificat de l'API de `pve01` est signé par la racine Proxmox de `pve01` (`~/.config/workbook/pve-root-ca.pem`, M02-E08) : pas de `verify_ssl: false`.
- Jobs du témoin : **`pve`** (pve-exporter, `cluster=1`, `node=1`) et **`hyperviseurs`** (node_exporter de `pve01` et `pbs01`, en HTTPS, rôle `node_exporter` d'E08).
- Flux : `mon01` → `pve01` 8006 (bordure **et** pare-feu Proxmox : IPSet `supervision`), `mon01` → `pve01` 9100, `mon01` → `pbs01` 9100 (par `wg0`), `K8S_TRAV` → `mon01` 9090 (fédération).
- Fédération par le Prometheus du cluster : `ScrapeConfig` **`federation-mon01`** (`scrape/federation-mon01.yaml`), `match[]` sur `{job=~"pve|hyperviseurs|blackbox"}`.

> ⚠️ **Attention** : tu modifies le **pare-feu datacenter de `pve01`** (IPSet et règle). Une règle mal posée peut te couper l'accès à l'interface ou à l'API de l'hyperviseur, y compris depuis ton poste. Avant : `cp /etc/pve/firewall/cluster.fw /root/cluster.fw.avant-m21e12` ; garde une session SSH ouverte sur `pve01` pendant l'opération ; retour arrière : recopie du fichier, `pve-firewall compile` puis `pve-firewall restart`. N'active jamais le pare-feu d'un niveau où il était désactivé.

**Travail demandé**
1. Sur `pve01`, crée (ou vérifie) l'utilisateur, le jeton avec séparation des privilèges, la permission `PVEAuditor` sur `/` **du jeton**. Prouve ce qu'il peut et ne peut pas faire (`pveum user token permissions …`, un `GET` qui marche, un `POST` refusé).
2. Crée l'IPSet `supervision` (entrée 10.10.20.19) et la règle d'entrée 8006 correspondante, à la manière de l'IPSet `automation` du M03. Ouvre le flux sur la bordure.
3. Étends le rôle `supervision_temoin` : installation de pve-exporter par `uv` (version épinglée), fichier `pve.yml` depuis le Vault, unité systemd durcie qui fait confiance à la racine de `pve01` **sans** désactiver la vérification TLS, jobs `pve` et `hyperviseurs` dans la configuration du témoin.
4. Applique le rôle `node_exporter` d'E08 à `pve01` et `pbs01` (certificat dont le nom couvre l'adresse par laquelle `mon01` les joint). Ouvre les flux.
5. Vérifie sur le témoin : `pve_up`, `pve_node_info`, la mémoire et le disque de `pve01`, `up{job="hyperviseurs"}`.
6. Écris le `ScrapeConfig` `federation-mon01` dans `plateforme/observabilite`, ouvre le flux `K8S_TRAV` → `mon01` 9090, synchronise. Dans le Prometheus du cluster : retrouve `pve_up` et `probe_success` ; d'où vient leur étiquette `instance` ? Que se passe-t-il sans `honorLabels: true` ?
7. Dans `~/m21/e12/journal.md` : pourquoi la fédération ne doit-elle tirer **qu'une partie** des séries ? Quel intervalle de collecte choisir, et quel effet a-t-il sur les `rate()` calculés dans le cluster ?

**Critères de réussite**
- [ ] Le jeton `wb-supervision@pve!prometheus` n'a que `PVEAuditor` ; l'IPSet `supervision` existe.
- [ ] Sur `mon01`, le service pve-exporter est actif, n'écoute que sur 127.0.0.1, et `pve_up{id="node/<nœud>"}` vaut 1 ; `up{job="hyperviseurs"}` vaut 1 pour `pve01` et `pbs01`.
- [ ] Dans le Prometheus du cluster, la cible `federation-mon01` est `up` et les séries des jobs `pve`, `hyperviseurs` et `blackbox` sont visibles avec leurs étiquettes d'origine.
- [ ] Aucune configuration ne contient `verify_ssl: false` ni le secret du jeton en clair.

**Vérification** : `lab/bin/check 21 12`

<details><summary>Indice 1</summary>

Un jeton créé avec séparation des privilèges (`--privsep 1`) n'a **aucun** droit tant qu'on ne lui en donne pas ; la permission se pose sur le jeton (`--tokens 'wb-supervision@pve!prometheus'`), pas seulement sur l'utilisateur. Le secret n'est affiché qu'une fois, à la création.
</details>

<details><summary>Indice 2</summary>

pve-exporter s'appuie sur `requests`, qui n'utilise pas le magasin de certificats du système mais son propre paquet de racines : regarde la variable d'environnement qui lui désigne un fichier de racines, et pose-la dans l'unité systemd.
</details>

**Pour aller plus loin** (facultatif) : PBS expose ses propres métriques par son serveur de métriques (InfluxDB) ; un exportateur communautaire existe (`pbs-exporter`). Lis le README de [prometheus-pve-exporter](https://github.com/prometheus-pve/prometheus-pve-exporter) et la page *Metric Server* de Proxmox VE, et compare les deux approches (tirer ou pousser).

---

### M21-E13 — Relabeling : maîtriser les étiquettes  `LAB` `★★★`

> **Ticket PLAT-2213** — *De : Karim Benali*
> J'ai voulu faire un tableau « erreurs par équipe et par environnement » : impossible, chaque source a ses étiquettes, ou n'en a pas. Et Prometheus stocke pour rien les histogrammes de `/sante` et `/metrics` de MédiAgenda, interrogés toutes les dix secondes par les sondes. Je veux trois étiquettes partout où ça a un sens — `equipe`, `environnement`, `site` — et qu'on arrête de stocker ce qui ne sert à rien.

**Objectifs pédagogiques**
- Distinguer `relabelings` (avant la collecte, sur la cible) et `metricRelabelings` (après, sur chaque série), et savoir ce que chacun coûte.
- Utiliser les actions `replace`, `keep`, `drop`, `labelmap`, `labeldrop`, `hashmod`.
- Poser des étiquettes communes par une **classe de collecte** (`scrapeClasses`) plutôt que dans chaque moniteur.
- Lire les étiquettes avant et après réécriture dans l'interface de Prometheus.

**Prérequis** : M21-E07 (ServiceMonitor `mediagenda`, `medidoc`), M21-E10.
**Durée indicative** : 3 h.

**Contexte technique**
- Les espaces portent déjà `medisphere.internal/equipe` et `medisphere.internal/environnement` (M14) ; `site` est déjà une **étiquette externe** du Prometheus du cluster (`externalLabels`, E02) et une étiquette des cibles `vms` (E08).
- Moniteurs à compléter : ceux d'E07 (`mediagenda` et `medidoc`, dans les composants `supervision`).
- Les deux applications étiquettent leurs requêtes par `route` : MédiAgenda `/sante`, `/pret`, `/metrics`, `/api/v1/…` ; MédiDoc `GET /healthz`, `GET /readyz`, `GET /metrics`, `POST /documents`…
- La classe de collecte se déclare dans `prometheus.prometheusSpec.scrapeClasses` de `kps/values.yaml` ; une classe `default: true` s'applique à tous les moniteurs et `ScrapeConfig` qui n'en désignent pas d'autre.

**Travail demandé**
1. Dans l'interface de Prometheus, page *Service Discovery*, ouvre une cible `mediagenda` et compare *Discovered Labels* et *Target Labels*. Liste dans `~/m21/e13/journal.md` les méta-étiquettes `__meta_kubernetes_*` disponibles pour un ServiceMonitor (rôle `endpoints` ou `endpointslice`) et celles qui **n'existent pas** (étiquettes de l'espace de noms ?).
2. Mesure avant : `count by (route) (mediagenda_http_request_duration_seconds_bucket)`, puis le nombre total de séries de MédiAgenda et de MédiDoc (`count({job=~"mediagenda|medidoc"})`, adapte au nom de tes jobs).
3. Dans le composant `components/supervision` de `mediagenda/deploiement` et de `medidoc/deploiement` (MR chez chaque équipe) :
   - `relabelings` : poser `equipe` et `environnement` sur la cible ; copier en étiquettes les étiquettes `app.kubernetes.io/version` et `app.kubernetes.io/component` du pod par un `labelmap` restreint ;
   - `metricRelabelings` : supprimer les seaux (`_bucket`) des routes de sonde, et uniquement eux.
4. Dans `kps/values.yaml`, déclare une classe de collecte par défaut qui pose `equipe="plateforme"` et `site="par1"` quand la cible n'a pas déjà ces étiquettes (indice 2), MR, synchronisation. Vérifie sur les cibles du chart (`kubelet`, `node-exporter`), sur un `ScrapeConfig` d'E10 et sur les séries de MédiAgenda.
5. `site` existe aussi en étiquette **externe** : explique dans le journal la différence entre les deux (où chacune apparaît : requêtes directes à Prometheus, alertes, fédération, Thanos au palier 3) et pourquoi elles ne se contredisent pas.
6. Essai de `hashmod` sur le Prometheus **témoin** de `mon01` (un job de test, copie du job `blackbox` restreint à `__tmp_hash == 0` avec un modulo 2) : quelles sondes reste-t-il ? À quoi ce mécanisme sert-il en production ? Retire l'essai.
7. Mesure après (même requêtes qu'à l'étape 2) et note le gain.

**Critères de réussite**
- [ ] Les séries `mediagenda_http_requests_total` de chacun des trois environnements portent `equipe="mediagenda"`, l'`environnement` correct et `site="par1"` ; celles de MédiDoc portent `equipe="medidoc"`.
- [ ] Il ne reste aucun seau d'histogramme pour les routes de sonde de MédiAgenda et de MédiDoc ; les seaux des routes de l'API sont toujours là.
- [ ] Les séries `up` du kubelet et des `ScrapeConfig` d'E10 portent une étiquette `equipe`.
- [ ] Le Prometheus du cluster a toujours l'étiquette externe `site="par1"`.

**Vérification** : `lab/bin/check 21 13`

<details><summary>Indice 1</summary>

Une action `replace` sans `sourceLabels` (ou dont la source est vide) et avec une `replacement` fixe pose une valeur constante. Pour dériver `environnement` du nom de l'espace, une expression régulière avec un groupe de capture sur `__meta_kubernetes_namespace` suffit.
</details>

<details><summary>Indice 2</summary>

« Seulement si l'étiquette est absente » : la règle `replace` utilise par défaut l'expression `(.*)` ; avec `sourceLabels: [equipe]` et `regex: ""`, elle ne s'applique que quand la valeur source est vide. Attention à l'ordre : les réécritures de la classe passent-elles avant ou après celles du moniteur ? Lis la documentation de `ScrapeClass` dans l'API de prometheus-operator.
</details>

<details><summary>Indice 3</summary>

`metricRelabelings` voit `__name__` comme une étiquette : une règle `drop` sur `sourceLabels: [__name__, route]` avec un séparateur et une expression qui couvre les deux suffit. Vérifie ton expression avec `promtool` ou sur la page *Relabeling* de l'interface de Prometheus 3 avant de pousser.
</details>

**Pour aller plus loin** (facultatif) : [`<relabel_config>`](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#relabel_config) ; lis les actions `keepequal`/`dropequal` et l'option `attachMetadata` : que permettrait `attachMetadata.node` pour un DaemonSet ?

---

### M21-E14 — Recording rules et cardinalité  `LAB` `★★★`

> **Ticket PLAT-2214** — *De : Julien Petit*
> Le tableau « MédiAgenda — aperçu » met huit secondes à s'afficher sur 7 jours, et j'ai peur qu'on demande la même chose aux alertes. Et quelqu'un m'a dit que si un développeur ajoute un identifiant de patient en étiquette, on peut tuer Prometheus : c'est vrai ? Comment on s'en protège ?

**Objectifs pédagogiques**
- Écrire des règles d'enregistrement selon la convention `niveau:métrique:opérations`, et choisir ce qui mérite d'être enregistré.
- Mesurer la cardinalité : page *TSDB Status*, `count by (__name__)`, `promtool tsdb analyze`.
- Poser des limites par moniteur (`sampleLimit`, `labelLimit`, `labelValueLengthLimit`) et comprendre ce qui se passe quand elles sont dépassées.
- Tester une règle d'enregistrement avec `promtool test rules`.

**Prérequis** : M21-E13.
**Durée indicative** : 3 h.

**Contexte technique**
- Convention MédiSphère : `niveau` = étiquettes conservées après agrégation (ex. `environnement`, `environnement_route`) ; `métrique` = nom d'origine sans `_total` (ex. `mediagenda_requetes`) ; `opérations` = du plus récent au plus ancien (ex. `taux5m`, `ratio_taux5m`, `p95_5m`). Exemple de la doc interne : `job:mediagenda_requetes:taux5m`.
- Règles attendues dans **`regles/enregistrement-mediagenda.yaml`** (PrometheusRule `enregistrement-mediagenda`, espace `supervision`, groupe `mediagenda.enregistrement`, intervalle 30 s), en excluant les routes de sonde :

| Série enregistrée | Sens |
|---|---|
| `environnement:mediagenda_requetes:taux5m` | requêtes par seconde |
| `environnement:mediagenda_requetes_5xx:taux5m` | réponses 5xx par seconde |
| `environnement:mediagenda_requetes_5xx:ratio_taux5m` | part des 5xx |
| `environnement_le:mediagenda_duree_requetes_seaux:taux5m` | seaux de l'histogramme, agrégés |
| `environnement:mediagenda_duree_requetes:p95_5m` | latence au 95e centile |

- Même famille pour MédiDoc dans `regles/enregistrement-medidoc.yaml` (préfixe `medidoc_`).
- `promtool tsdb analyze` se lance sur le Prometheus **témoin** de `mon01` (données dans `/var/lib/prometheus/data`), jamais dans le cluster.

**Travail demandé**
1. Page *Status → TSDB Status* du Prometheus du cluster : note les 5 métriques qui ont le plus de séries, les 5 étiquettes aux valeurs les plus nombreuses. Écris dans `~/m21/e14/cardinalite.promql` les requêtes qui retrouvent ces chiffres (`topk`, `count by (__name__)`, `count(count by (étiquette) (…))`).
2. Sur `mon01` : `promtool tsdb analyze` sur le répertoire du témoin. Que signifient *Label pairs most involved in churning* et *Highest cardinality metric names* ?
3. Écris les deux PrometheusRule d'enregistrement. Pourquoi enregistrer les **seaux** agrégés plutôt que seulement le centile ? Pourquoi `rate` **avant** `sum` ?
4. Écris `tests/enregistrement-mediagenda.test.yaml` : des séries d'entrée qui montent régulièrement, et la valeur attendue du taux et du ratio. Fais-le passer avec `promtool test rules` sur `adm01` (le fichier de règles se tire de la PrometheusRule : seule sa `spec` est un fichier de règles Prometheus).
5. MR, synchronisation, puis : page *Rules* (dernière évaluation, durée, erreur éventuelle), requête des séries enregistrées.
6. Pose sur le ServiceMonitor de MédiAgenda une `sampleLimit` raisonnable (mesure le nombre d'échantillons par collecte avec `scrape_samples_scraped` et garde une marge) et une `labelValueLengthLimit`. Dans `~/m21/e14/journal.md` : que devient la cible quand la limite est dépassée ? Quelle alerte du chart le signale ? Pourquoi est-ce une protection, et pas une solution, contre l'identifiant de patient en étiquette ?
7. Remplace dans le tableau « MédiAgenda — aperçu » (E05) les expressions longues par les séries enregistrées, et compare le temps de chargement sur 7 jours.

**Critères de réussite**
- [ ] Les PrometheusRule `enregistrement-mediagenda` et `enregistrement-medidoc` sont chargées : leurs groupes sont sains (aucune erreur de la dernière évaluation).
- [ ] `environnement:mediagenda_requetes:taux5m` et `environnement:mediagenda_duree_requetes:p95_5m` renvoient des valeurs pour au moins deux environnements.
- [ ] Le ServiceMonitor `mediagenda` a une `sampleLimit` non nulle, supérieure au nombre d'échantillons actuel.
- [ ] Le test `promtool` est dans `tests/` sur `main`.

**Vérification** : `lab/bin/check 21 14`

<details><summary>Indice 1</summary>

`histogram_quantile` attend des seaux **déjà** passés par `rate` et agrégés en gardant `le`. Enregistrer les seaux agrégés permet de calculer n'importe quel centile plus tard, et d'agréger encore (sur tous les environnements) sans retourner aux séries brutes ; un centile, lui, ne s'agrège pas.
</details>

<details><summary>Indice 2</summary>

Dans un test `promtool`, `input_series` s'écrit en notation d'expansion (`0+60x20` : part de 0, ajoute 60 à chaque intervalle, 20 fois) ; `promql_expr_test` compare le résultat **exact** d'une expression à un instant `eval_time`, étiquettes comprises. Un `rate` sur 5 minutes de `0+60x20` avec un intervalle d'une minute donne 1 par seconde.
</details>

**Pour aller plus loin** (facultatif) : [Recording rules — best practices](https://prometheus.io/docs/practices/rules/) ; lis la page *Native histograms* : quelle différence pour la cardinalité d'un histogramme de latence ?

---

### M21-E15 — Écrire de bonnes alertes  `LAB` `★★★`

> **Ticket PLAT-2215** — *De : Nadia Roussel*
> Les règles du chart sont utiles, mais elles parlent de pods et de kubelets. Moi, je veux être réveillée quand **les centres de santé** ont un problème avec MédiAgenda, ou quand un disque du socle va être plein **avant demain matin**. Pas quand un pod redémarre une fois. Chaque alerte doit dire qui est concerné, à quel point c'est grave, et pointer vers la marche à suivre. Et je veux une preuve qu'elles marchent avant qu'elles partent en production.

**Objectifs pédagogiques**
- Écrire des alertes sur les **symptômes** vus par l'utilisateur (erreurs, latence, indisponibilité), et sur les causes seulement quand elles sont prévisibles (saturation à venir).
- Régler `for` et `keep_firing_for`, choisir les fenêtres (au moins quatre intervalles de collecte).
- Normaliser les étiquettes (`gravite`, `equipe`) et les annotations (`resume`, `description`, `runbook_url`).
- Tester les alertes par `promtool test rules` dans la CI de `plateforme/observabilite`.

**Prérequis** : M21-E14, M21-E06.
**Durée indicative** : 3 h 30.

**Contexte technique**
- Fichiers : `regles/alertes-mediagenda.yaml` (PrometheusRule `alertes-mediagenda`), `regles/alertes-socle.yaml` (`alertes-socle`), tests dans `tests/alertes-mediagenda.test.yaml` et `tests/alertes-socle.test.yaml`.
- Alertes attendues (noms figés, utilisés par E16, E21, E22 et les pannes du palier 4) :

| Alerte | Symptôme | Gravité | Équipe |
|---|---|---|---|
| `MediagendaTauxErreurEleve` | plus de 5 % de 5xx en prod pendant 10 min (2 % en avertissement) | `critique` en prod, `avertissement` ailleurs | `mediagenda` |
| `MediagendaLatenceElevee` | p95 au-dessus de 300 ms en prod pendant 15 min | `avertissement` | `mediagenda` |
| `MediagendaIndisponible` | aucune cible MédiAgenda `up` en prod pendant 5 min, ou plus aucune série | `critique` | `mediagenda` |
| `MediagendaPodsNonPrets` | des pods MédiAgenda non prêts depuis 15 min (étiquette `node`) | `avertissement` | `mediagenda` |
| `CibleInjoignable` | une VM du socle (job `vms`) ne répond plus depuis 5 min | `avertissement` | `plateforme` |
| `DisqueBientotPlein` | un système de fichiers d'une VM sera plein dans moins de 24 h au rythme actuel | `avertissement` | `plateforme` |
| `CertificatBientotExpire` | un certificat sondé par le témoin expire dans moins de 7 jours | `avertissement` | `plateforme` |

- `runbook_url` : RB-211 (erreurs), RB-212 (latence), RB-213 (disque plein), RB-210 (modèle) pour les autres en attendant leur runbook (E22).
- CI de `plateforme/observabilite` (E07) : étape `valider`, runner `k8s-par1` (étiquette `k8s`) ; images par les caches Harbor, variables `IMAGE_PROMETHEUS` (`quay/prometheus/prometheus:v3.15.1`, contient `promtool`) et `IMAGE_YQ` (`dockerhub/mikefarah/yq:4.54.1`). Le job de tests s'appelle **`tests-regles`**.

**Travail demandé**
1. Lis *My Philosophy on Alerting* (Rob Ewaschuk) et la page *Alerting* des bonnes pratiques de Prometheus. Dans `~/m21/e15/journal.md` : pour chaque alerte du tableau, est-ce un symptôme ou une cause ? Qui doit être réveillé ?
2. Écris les alertes de MédiAgenda en t'appuyant sur les séries enregistrées d'E14. Pour le taux d'erreurs, comment éviter qu'une seule erreur sur trois requêtes à 4 h du matin réveille quelqu'un ? Pour `MediagendaIndisponible`, couvre aussi le cas où **la cible elle-même a disparu** (`absent`).
3. Écris les alertes du socle. `DisqueBientotPlein` utilise `predict_linear` : sur quelle fenêtre, et pourquoi exclure certains types de systèmes de fichiers ? `CertificatBientotExpire` s'appuie sur les séries fédérées depuis `mon01` (E12).
4. Ajoute `keep_firing_for` là où une alerte risque de clignoter (taux d'erreurs) et explique la différence avec `for`.
5. Écris les tests `promtool` : pour chaque alerte, au moins un cas qui déclenche (avec les étiquettes et annotations attendues) et un cas qui ne déclenche pas (sous le seuil, ou pas assez longtemps).
6. Ajoute à `.gitlab-ci.yml` les jobs qui extraient les `spec` des PrometheusRule (`outils/extraire-regles.sh`, écrit en E14), lancent `promtool check rules`, puis **`tests-regles`** (`promtool test rules tests/*.test.yaml`). Fais échouer volontairement un test dans une MR pour voir le pipeline rouge, puis corrige.
7. Après fusion et synchronisation : page *Alerts* de Prometheus, toutes les règles chargées et `inactive`.

**Critères de réussite**
- [ ] Les sept alertes sont chargées dans le Prometheus du cluster, chacune avec `gravite`, `equipe`, `resume`, `description` et `runbook_url`, et un `for` d'au moins 5 minutes.
- [ ] Aucune alerte n'utilise `irate` ; `MediagendaIndisponible` couvre la disparition de la cible.
- [ ] Le dernier pipeline de `main` de `plateforme/observabilite` a réussi et contient le job `tests-regles` réussi.

**Vérification** : `lab/bin/check 21 15`

<details><summary>Indice 1</summary>

Un ratio seul ment à faible trafic. Combine-le avec un minimum de trafic (`and` sur le taux de requêtes) ; une alerte qui ne peut pas avoir de sens la nuit ne doit pas pouvoir partir la nuit.
</details>

<details><summary>Indice 2</summary>

Dans un test d'alerte, `exp_alerts` liste **toutes** les instances attendues à `eval_time`, avec toutes leurs étiquettes (celles de l'expression **et** celles de la règle) et les annotations **rendues** (modèles évalués). Une alerte encore en attente (`pending`, `for` non écoulé) n'apparaît pas.
</details>

<details><summary>Indice 3</summary>

`absent()` ne garde que les étiquettes d'égalité de son sélecteur : `absent(up{job="mediagenda",namespace="mediagenda-prod"})` produit une série avec `job` et `namespace`, ce qui suffit pour router.
</details>

**Pour aller plus loin** (facultatif) : [Alerting — best practices](https://prometheus.io/docs/practices/alerting/) ; les règles du projet [kubernetes-mixin](https://github.com/kubernetes-monitoring/kubernetes-mixin) dont viennent celles du chart : lesquelles désactiverais-tu (`defaultRules.disabled`) et pourquoi ?

---

### M21-E16 — Silences, inhibitions et routage par équipe  `LAB` `★★`

> **Ticket PLAT-2216** — *De : Nadia Roussel*
> Hier soir, `k8s-w02` a été redémarré pour une maintenance annoncée : j'ai reçu quarante courriels, dont trente pour des pods « non prêts » sur ce nœud. Et l'équipe de Julien reçoit nos alertes de disque. Je veux : chaque équipe reçoit ses alertes, les critiques arrivent aussi à l'astreinte, les avertissements ne partent qu'aux heures ouvrées, un nœud tombé n'entraîne pas une avalanche, et une maintenance se déclare **avant** de commencer.
>
> *Commentaire de Karim Benali* : et je veux des tests de routage dans la CI, comme pour les règles.

**Objectifs pédagogiques**
- Construire un arbre de routage d'Alertmanager (correspondances, `continue`, regroupement, héritage des réglages).
- Écrire des inhibitions justes (`equal`) et connaître le piège des étiquettes absentes des deux côtés.
- Limiter des routes dans le temps (`time_intervals`, `active_time_intervals`, `mute_time_intervals`).
- Poser, lire, prolonger et expirer un silence avec `amtool` (auteur, commentaire, durée).
- Tester le routage hors ligne (`amtool config routes test`) dans la CI.

**Prérequis** : M21-E15, M21-E06.
**Durée indicative** : 2 h 30.

**Contexte technique**
- La configuration d'Alertmanager est la clé `alertmanager.config` de `kps/values.yaml` (E06) ; le chart la rend dans le Secret de configuration d'Alertmanager.
- Routage attendu (racine : `plateforme-mail`) :
  - `alertname="Watchdog"` → récepteur sans notification (il existe déjà ; le palier 3 s'en sert) ;
  - `equipe="mediagenda"` → `mediagenda-mail` ; `equipe="medidoc"` → `medidoc-mail` ; `equipe="plateforme"` → `plateforme-mail` ;
  - toute alerte `gravite="critique"` va **aussi** à `astreinte-mail`, à toute heure ;
  - `gravite="avertissement"` : seulement du lundi au vendredi, 08:00-19:00 (Europe/Paris), intervalle nommé `heures-ouvrees` ;
  - `gravite="info"` : jamais notifiée.
- Inhibitions : `CibleInjoignable` éteint les autres alertes de la **même** `instance` ; `KubeNodeNotReady` et `KubeNodeUnreachable` (règles du chart, étiquette `node`) éteignent `MediagendaPodsNonPrets` du **même** `node`.
- `amtool` sur `adm01` (même version que l'Alertmanager du cluster, 0.34), `--alertmanager.url=http://alertmanager.apps.par1.medisphere.internal:9093` ; essais de routage dans `alertmanager/routes-tests.txt`, rejoués par `outils/tester-routes.sh` et le job `alertmanager:verifier` de la CI (E07).
- Changement de référence pour la maintenance : **CHG-2216**.

**Travail demandé**
1. Lis la page *Configuration* d'Alertmanager (sections `route`, `inhibit_rule`, `time_interval`). Dans `~/m21/e16/journal.md`, dessine l'arbre de routage voulu, en indiquant pour chaque nœud `group_by`, `continue` et les réglages hérités.
2. Écris la configuration (MR) : routes, `time_intervals`, inhibitions. Vérifie localement avec `amtool check-config` sur la clé extraite de `kps/values.yaml`.
3. Complète `alertmanager/routes-tests.txt` (format d'E07 : récepteurs attendus, séparés par des virgules, puis les étiquettes) : une dizaine de cas au moins, dont critique MédiAgenda en prod, avertissement MédiDoc, disque plein plateforme, `Watchdog`, `info`, une alerte critique du chart (`severity`). Rejoue-les en local avec `outils/tester-routes.sh` avant la MR : certains essais d'E07 changent de résultat, et c'est normal (pourquoi ?).
4. Après synchronisation, vérifie la configuration chargée (`amtool config show`, page *Status* d'Alertmanager).
5. Inhibition : envoie à l'Alertmanager du cluster deux alertes de test (`amtool alert add`) — `CibleInjoignable{instance="essai-e16:9100"}` et `DisqueBientotPlein{instance="essai-e16:9100"}` — puis constate laquelle est `suppressed` (`amtool alert query --inhibited`). Que se passerait-il avec `equal: [instance]` si aucune des deux alertes n'avait d'étiquette `instance` ?
6. Silence : déclare la maintenance d'un travailleur (CHG-2216) par un silence de 2 h sur `node="k8s-w02"`, auteur et commentaire renseignés ; lis-le, prolonge-le, expire-le. Dans le journal : pourquoi un silence vaut mieux qu'une désactivation de règle, et pourquoi il doit être **court** ?

**Critères de réussite**
- [ ] La configuration chargée par l'Alertmanager du cluster route par `equipe`, envoie les `critique` à `astreinte-mail`, limite les `avertissement` à l'intervalle `heures-ouvrees` et contient les deux inhibitions demandées, avec `equal`.
- [ ] Un silence portant `CHG-2216` dans son commentaire a été posé (actif ou expiré), avec un auteur.
- [ ] `alertmanager/routes-tests.txt` couvre les routes d'équipe sur `main`, et le job `alertmanager:verifier` du dernier pipeline de `main` a réussi.

**Vérification** : `lab/bin/check 21 16`

<details><summary>Indice 1</summary>

Une alerte ne suit **qu'une** branche de l'arbre, la première qui correspond, sauf `continue: true`. Pour envoyer une alerte critique à la fois à l'équipe et à l'astreinte, la route « astreinte » se place **avant** les routes d'équipe, avec `continue: true`.
</details>

<details><summary>Indice 2</summary>

`time_intervals` est une section de premier niveau (nommée) ; une route s'y réfère par `active_time_intervals` (notifie seulement pendant) ou `mute_time_intervals` (se tait pendant). Le fuseau horaire se donne par `location` dans l'intervalle. Une alerte d'une route inactive n'est pas perdue : elle est notifiée quand l'intervalle s'ouvre, si elle est toujours active.
</details>

<details><summary>Indice 3</summary>

`amtool config routes test` ne lit pas Alertmanager : il lit un **fichier**, et il ignore les intervalles de temps (il ne teste que l'arbre). La CI d'E07 extrait déjà `.alertmanager.config` de `kps/values.yaml` : reproduis ses trois commandes `yq` en local.
</details>

**Pour aller plus loin** (facultatif) : [Alertmanager — configuration](https://prometheus.io/docs/alerting/latest/configuration/) ; l'outil de visualisation de l'arbre de routage (*routing tree editor*) et les `AlertmanagerConfig` (`v1alpha1`) qui permettraient à chaque équipe de gérer ses routes dans son espace : avantages et risques.

---

### M21-E17 — Tableaux de bord *as code*  `LAB` `★★★`

> **Ticket PLAT-2217** — *De : Claire Morel*
> Le tableau de Julien a été modifié par quelqu'un, puis cassé, puis personne ne savait qui ni quand. Je veux que nos tableaux soient du code : relus en MR, validés en CI, rangés par équipe, avec les bons droits, et qu'on ne puisse plus les abîmer à la souris. Les équipes et leurs droits aussi, décrits dans un dépôt.

**Objectifs pédagogiques**
- Provisionner des tableaux de bord par le *sidecar* de Grafana à partir de ConfigMaps générées par Kustomize.
- Écrire des tableaux portables : UID stables, source de données par variable (`${datasource}`), pas d'identifiant interne.
- Valider les tableaux en CI (JSON, UID uniques, aucune source de données codée en dur).
- Décrire dossiers, équipes et permissions par OpenTofu (fournisseur `grafana/grafana`), et savoir ce que le provisionnement par fichiers accepte en Grafana 13.

**Prérequis** : M21-E05 (tableau « MédiAgenda — aperçu », compte `wb-checks`), M21-E14, M05 (OpenTofu, état S3).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Arborescence : `tableaux/plateforme/`, `tableaux/mediagenda/`, `tableaux/medidoc/` ; un `kustomization.yaml` dans `tableaux/` génère une ConfigMap par fichier (`configMapGenerator`, étiquette `grafana_dashboard: "1"` — déjà attendue par le sidecar du chart —, annotation de dossier `grafana_folder`, sans suffixe de hachage).
- Sidecar (valeurs `grafana.sidecar.dashboards` de `kps/values.yaml`) : `folderAnnotation: grafana_folder`, `provider.foldersFromFilesStructure: true`, `provider.allowUiUpdates: false`.
- Dossiers Grafana (titre → UID) : `Plateforme` → `plateforme`, `MédiAgenda` → `mediagenda`, `MédiDoc` → `medidoc`. UID des tableaux : `<dossier>-<nom>` en minuscules (ex. `mediagenda-apercu`).
- OpenTofu : état **`observabilite-grafana`** dans `plateforme/infra` (dossier `observabilite-grafana/`, même dorsale S3 que les autres états), fournisseur `grafana/grafana` épinglé en **`~> 4.50`** (dernière version publiée au 22/10/2026) ; compte de service Grafana `tofu` (rôle Admin), jeton dans `~/.config/workbook/grafana-tofu.token` (600), passé par `TF_VAR_grafana_jeton` ; équipes `plateforme`, `mediagenda`, `medidoc` (membres : des comptes locaux de Grafana, en attendant le SSO du M24).
- Droits voulus : chaque équipe **voit** (View) son dossier ; l'équipe `plateforme` voit tous les dossiers ; le rôle Viewer de base ne voit que `Plateforme` ; le compte de service `wb-checks` (E05, vérifications) voit tout ; personne n'édite (provisionnement).

**Travail demandé**
1. Exporte le tableau « MédiAgenda — aperçu » d'E05 (*Export → Export as JSON*, sans l'option de partage externe). Repère ce qui le rend non portable : `id`, UID de source de données, `__inputs`, `version`. Nettoie-le, donne-lui l'UID `mediagenda-apercu`, une variable `datasource` de type source de données Prometheus, et range-le dans `tableaux/mediagenda/`. Note le format de schéma du fichier exporté (classique ou v2) et ce qu'en dit la documentation du provisionnement par fichiers de Grafana 13.
2. Écris le `kustomization.yaml` de `tableaux/` et ajoute-le à l'Application `observabilite`. Modifie les valeurs du sidecar dans `kps/values.yaml`.
3. Écris `outils/valider-tableaux.py` (bibliothèque standard de Python seulement) : JSON valide, `uid` présent, unique, conforme au motif, `id` nul ou absent, aucun `datasource` dont l'`uid` n'est pas `${datasource}` (ou une variable), titre présent. Ajoute le job `valider-tableaux` à la CI.
4. Crée d'abord dans Grafana (avec ton compte `<MOI>`, *Administration > Users and access > Users*) les comptes locaux de Karim Benali, Nadia Roussel, Claire Morel et Julien Petit (`prenom.nom@medisphere.internal`, rôle Viewer, mots de passe aléatoires rangés dans ton gestionnaire) : le fournisseur rattache des comptes **existants** aux équipes, il ne les crée pas. Puis écris l'état OpenTofu `observabilite-grafana` : fournisseur épinglé, dorsale S3, dossiers (UID fixes), équipes (Karim et Nadia dans `plateforme`, toi aussi ; Julien dans `mediagenda`), permissions des dossiers. `tofu plan`, MR, `tofu apply`.
5. Synchronise. Dans Grafana : le tableau est dans le dossier `MédiAgenda`, marqué provisionné ; essaie de l'enregistrer après modification : que se passe-t-il ? Connecte-toi avec le compte de Julien : que vois-tu ?
6. Le tableau d'E05, créé à la main, porte déjà l'UID `mediagenda-apercu` : le provisionnement ne prend pas la main sur un tableau existant de même UID. Supprime-le dans Grafana juste avant la synchronisation (il est dans Git, tu ne perds rien), puis vérifie qu'il n'en reste qu'**une** version, provisionnée.

**Critères de réussite**
- [ ] Le tableau d'UID `mediagenda-apercu` existe, dans le dossier d'UID `mediagenda`, provisionné, et ne référence aucune source de données autrement que par variable.
- [ ] Les dossiers `plateforme`, `mediagenda` et `medidoc` existent avec ces UID ; chaque fichier de `tableaux/` correspond à un tableau provisionné.
- [ ] `outils/valider-tableaux.py` est sur `main` et le dernier pipeline de `main` a réussi avec le job `valider-tableaux` ; l'état OpenTofu `observabilite-grafana` est sur `main` de `plateforme/infra`.

**Vérification** : `lab/bin/check 21 17`

<details><summary>Indice 1</summary>

Le sidecar écrit chaque ConfigMap dans un sous-dossier qui porte la valeur de l'annotation ; avec `foldersFromFilesStructure`, Grafana fait de chaque sous-dossier un dossier **de même titre**. Si OpenTofu a créé le dossier avant, avec ce titre exact, le provisionnement le réutilise : l'UID du dossier reste celui d'OpenTofu. Vérifie-le chez toi.
</details>

<details><summary>Indice 2</summary>

Une ConfigMap est limitée à 1 Mio, et Argo CD en *client-side apply* stocke une copie complète dans une annotation limitée à 256 Kio : un gros tableau passe par `ServerSideApply=true`. Côté Kustomize, `generatorOptions` (ou `options` par générateur) porte étiquettes, annotations et `disableNameSuffixHash`.
</details>

<details><summary>Indice 3</summary>

Dans le fournisseur Grafana, `grafana_folder_permission` **remplace** toutes les permissions du dossier par celles déclarées : un dossier sans bloc pour le rôle `Viewer` n'est plus visible des Viewers. C'est ce que tu veux pour `mediagenda` et `medidoc`, pas pour `plateforme`.
</details>

**Pour aller plus loin** (facultatif) : [Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/#dashboards), [Git Sync](https://grafana.com/docs/grafana/latest/observability-as-code/provision-resources/) et les [ressources du fournisseur](https://registry.terraform.io/providers/grafana/grafana/latest/docs) ; compare avec l'opérateur Grafana (`GrafanaDashboard`) et avec Grizzly.

---

### M21-E18 — Analyses Prometheus pour Argo Rollouts  `LAB` `★★★`

> **Ticket DEV-2218** — *De : Julien Petit*
> Nos canaries vérifient que `/pret` répond et que les tests de fumée passent. Mais la semaine dernière, une version qui renvoyait 8 % d'erreurs sur la prise de rendez-vous est passée jusqu'à 50 % du trafic avant qu'on s'en aperçoive. Je veux que le canary regarde les **vrais** chiffres de la version canary : taux d'erreurs et latence, et qu'il s'arrête tout seul si ça dérape.

**Objectifs pédagogiques**
- Écrire une `ClusterAnalysisTemplate` avec le fournisseur Prometheus : requête, conditions de succès et d'échec, intervalle, nombre de mesures, limites d'échec et d'erreur.
- Isoler la révision canary dans les métriques (étiquette `rollouts-pod-template-hash`, argument `podTemplateHashValue`).
- Brancher l'analyse en arrière-plan d'un canary par le plugin Gateway API.
- Provoquer un échec et lire l'`AnalysisRun`.

**Prérequis** : M20-E16 et E18 (canary de `mediagenda-recette`, analyses Job et `web`), M21-E13, M21-E15.
**Durée indicative** : 3 h.

**Contexte technique**
- `ClusterAnalysisTemplate` **`taux-erreur-mediagenda`**, rangée avec `fumee-mediagenda` et `pret-mediagenda` (M20) dans le dépôt et l'Application qui les portent.
- Adresse de Prometheus **interne** au cluster : `http://kps-prometheus.supervision.svc.cluster.local:9090`. Elle reste celle des analyses au palier 3 : avec deux réplicas (M21-E24), ce Service répartit les requêtes entre deux Prometheus qui collectent les mêmes cibles, et une analyse de quelques minutes n'a pas besoin de l'historique de Thanos. La politique d'entrée `prometheus-entree` (palier 1) n'autorise que MGMT, `mon01` et l'espace `supervision` : le contrôleur d'Argo Rollouts (espace `argo-rollouts`) doit y être ajouté.
- Arguments : `namespace` (espace de la Rollout), `hash-canary` (`valueFrom.podTemplateHashValue: Latest`) ; seuils : 5xx < 5 % et p95 < 500 ms sur 2 minutes, mesure toutes les minutes, 3 échecs tolérés au plus.
- Rollouts concernées : `mediagenda` dans `mediagenda-recette` et `mediagenda-prod` (`mediagenda/deploiement`, overlays `recette` et `prod`).
- Les séries de MédiAgenda portent l'étiquette `rollouts_pod_template_hash` (réécriture du ServiceMonitor d'E07), et chaque pod n'est collecté **qu'une fois** (Service de collecte `mediagenda-metriques`).
- Requête d'erreur volontaire pour l'essai : un appel à `GET /api/v1/creneaux` avec un paramètre `praticien` contenant un caractère nul encodé (`%00`) provoque une erreur 500 sur **tous** les pods, stables comme canary.

**Travail demandé**
1. Lis la page *Analysis* d'Argo Rollouts (fournisseur Prometheus, arguments, `valueFrom`, analyses en arrière-plan, traitement de `NaN`). Dans `~/m21/e18/journal.md` : que devient une mesure quand la requête renvoie un vecteur vide ? Comment ton expression l'évite-t-elle ?
2. Vérifie comment le moniteur de MédiAgenda (E07) collecte les pods en recette, avant puis **pendant** un canary : quels Services sélectionnent quels pods (`mediagenda`, `mediagenda-canary`, `mediagenda-metriques`) ? Chaque pod est-il collecté une fois, et une seule (`count by (pod) (up{job="mediagenda", namespace="mediagenda-recette"})`) ? Ses séries portent-elles le hachage de révision ? Note dans le journal ce qui se passerait si le ServiceMonitor suivait les Services du chart.
3. Écris la `ClusterAnalysisTemplate` : deux métriques (`taux-erreur`, `latence-p95`), conditions qui tolèrent l'absence de trafic sans masquer une vraie panne, `failureLimit`, `consecutiveErrorLimit`. Teste chaque requête dans l'interface de Prometheus avec un hachage réel avant de l'écrire.
4. Ajoute la politique d'entrée pour `argo-rollouts` → Prometheus (9090) dans `kps/values.yaml`. Vérifie depuis le contrôleur (journaux) que la première mesure aboutit.
5. Branche l'analyse en arrière-plan sur les Rollouts de recette et de prod (à partir de la première étape, en plus des analyses du M20). MR dans `mediagenda/deploiement`.
6. Lance un canary en recette (nouvelle version par le processus de promotion du M20) et suis-le (`kubectl argo rollouts get rollout mediagenda -n mediagenda-recette --watch`). La recette ne reçoit pas de trafic d'utilisateurs : pendant tout le canary, fais tourner le trafic d'essai d'E04 (`ressources/E04-trafic/trafic-mediagenda.sh`, recette seulement). L'`AnalysisRun` doit réussir. Que se serait-il passé sans ce trafic ?
7. **Canary échoué volontairement** : relance un canary et, pendant l'étape à 10 %, envoie depuis `adm01` un trafic où une requête sur cinq est la requête empoisonnée. Constate l'avortement, lis l'`AnalysisRun` (valeurs mesurées, phase), et explique dans le journal pourquoi la version canary a été rejetée **alors qu'elle n'y est pour rien**. Quelle analyse aurait évité ce faux positif ? Remets la Rollout dans un état sain (nouvelle tentative sans trafic empoisonné).

**Critères de réussite**
- [ ] La `ClusterAnalysisTemplate` `taux-erreur-mediagenda` existe, avec le fournisseur Prometheus à l'adresse interne du cluster et l'argument `hash-canary`.
- [ ] Les Rollouts `mediagenda` de recette et de prod y font référence (`clusterScope: true`).
- [ ] En recette, au moins un `AnalysisRun` issu de ce modèle est `Successful` et au moins un est `Failed` ; la Rollout est saine à la fin.

**Vérification** : `lab/bin/check 21 18`

<details><summary>Indice 1</summary>

`(sum(rate(x{code=~"5.."}[2m])) or vector(0)) / (sum(rate(x[2m])) > 0)` renvoie un vecteur vide sans trafic, et une valeur sinon ; à l'inverse, un centile calculé sans trafic vaut `NaN`. Les conditions d'Argo Rollouts disposent de `isNaN()` et de `default()` ; `result` est un tableau de valeurs.
</details>

<details><summary>Indice 2</summary>

Pendant un canary, Argo Rollouts ajoute le hachage du ReplicaSet au sélecteur des Services `mediagenda` et `mediagenda-canary` ; une fois la promotion finie, les deux sélectionnent les mêmes pods. Un moniteur qui suivrait ces deux Services collecterait alors chaque pod deux fois (étiquette `service` différente) ; un moniteur qui ne suivrait que le stable perdrait les pods canary. C'est pour cela qu'E07 a créé un Service **de collecte** à part.
</details>

<details><summary>Indice 3</summary>

Le contrôleur d'Argo Rollouts interroge Prometheus depuis son pod : la politique Cilium de l'espace `supervision` doit l'autoriser par son espace (`io.kubernetes.pod.namespace`). Une requête refusée apparaît comme une mesure en **erreur** (pas en échec) dans l'`AnalysisRun`.
</details>

**Pour aller plus loin** (facultatif) : [Analysis](https://argo-rollouts.readthedocs.io/en/stable/features/analysis/) ; une analyse **comparative** (canary contre stable, rapport des taux d'erreurs) et les `Experiment` (référence et canary lancés en parallèle) : réécris ta requête pour comparer les deux révisions.

---

### M21-E19 — Méthodes USE et RED : les tableaux de bord de référence  `LIBRE` `★★★`

> **Ticket PLAT-2219** — *De : Nadia Roussel*
> Pendant une astreinte, je n'ai pas le temps d'inventer des requêtes. Je veux un petit nombre de tableaux **toujours les mêmes**, construits de la même façon : pour les ressources (nœuds, Ceph), *Utilisation, Saturation, Erreurs* ; pour les services (MédiAgenda, MédiDoc, la passerelle d'entrée), *Débit, Erreurs, Durée*. Avec, sur chaque tableau, les liens vers les runbooks.

**Objectifs pédagogiques**
- Appliquer les méthodes USE (Brendan Gregg) et RED (Tom Wilkie) pour choisir les panneaux d'un tableau.
- Construire des tableaux homogènes, paramétrés (variables), rapides (séries enregistrées) et reliés aux runbooks.

**Prérequis** : M21-E14, M21-E17, M21-E10 (Ceph), M21-E20 (métriques de Cilium) ou à défaut les métriques de la passerelle disponibles.
**Durée indicative** : 4 h.

**Contexte technique**
- Tableaux attendus (UID figés) : `plateforme-use-noeuds` (nœuds du cluster et VMs), `plateforme-use-ceph`, `mediagenda-red`, `medidoc-red`, `plateforme-red-passerelle` (Gateway `gw-par1`).
- Ils suivent les règles d'E17 (dossiers, `${datasource}`, CI) ; les panneaux du RED de MédiAgenda s'appuient sur les séries enregistrées d'E14.
- Métriques HTTP de la passerelle : celles de l'Envoy de Cilium ou de Hubble, si elles existent dans ton cluster ; sinon, le tableau le dit et mesure ce qui est mesurable (connexions, octets, flux refusés).

**Travail demandé**
Conçois et livre les cinq tableaux. Contraintes :
- chaque tableau commence par une ligne de synthèse (trois ou quatre statistiques lisibles en deux secondes), puis une section par lettre de la méthode, dont le titre commence par **Utilisation**, **Saturation**, **Erreurs** (USE) ou **Débit**, **Erreurs**, **Durée** (RED) ;
- variables : source de données, et selon le cas `environnement`, `instance` ou `node` ; aucune valeur codée en dur qui empêche de réutiliser le tableau ;
- chaque tableau porte au moins un lien (liens du tableau) vers le runbook concerné (RB-21x) et vers le tableau de référence voisin ;
- un tableau s'ouvre en moins de 3 secondes sur 24 heures ;
- `docs/observabilite/metriques/tableaux.md` (dans `plateforme/medisphere`) explique, tableau par tableau, ce que mesure chaque section et ce qu'il **ne** montre **pas**.

**Critères de réussite**
- [ ] Les cinq tableaux existent avec ces UID, provisionnés dans le bon dossier.
- [ ] Chaque tableau USE a des panneaux ou rangées dont les titres commencent par Utilisation, Saturation et Erreurs ; chaque RED par Débit, Erreurs et Durée.
- [ ] Chaque tableau a au moins un lien vers un runbook `RB-21` ; `tableaux.md` est publié.

**Vérification** : `lab/bin/check 21 19`

<details><summary>Indice 1</summary>

Pour un nœud, la saturation CPU n'est pas l'utilisation à 100 % : c'est la file d'attente (charge rapportée au nombre de cœurs, *pressure stall information* `node_pressure_*` si le noyau l'expose). Pour Ceph, l'utilisation est la capacité et les IOPS, la saturation les opérations lentes et les PG non actifs, les erreurs l'état de santé et les OSD `down`.
</details>

<details><summary>Indice 2</summary>

Les séries de l'Envoy de Cilium suivent le schéma de nommage d'Envoy (`envoy_http_downstream_rq_xx`, `envoy_cluster_upstream_rq_time_bucket`…) : explore-les dans Prometheus avant de construire les panneaux, leurs étiquettes disent quel écouteur et quel cluster amont elles décrivent.
</details>

**Pour aller plus loin** (facultatif) : [The USE Method](https://www.brendangregg.com/usemethod.html), [The RED Method](https://grafana.com/blog/2018/08/02/the-red-method-how-to-instrument-your-services/), les tableaux de [node-exporter-mixin](https://github.com/prometheus/node_exporter/tree/master/docs/node-mixin) et le projet [Grafana Foundation SDK](https://github.com/grafana/grafana-foundation-sdk) pour générer des tableaux par du code.

---

### M21-E20 — Superviser Kubernetes : plan de contrôle, etcd, kubelet, Cilium  `LAB` `★★`

> **Ticket PLAT-2220** — *De : Karim Benali*
> Prometheus nous montre les pods et les kubelets, mais `kube-controller-manager`, `kube-scheduler` et etcd sont des boîtes noires : leurs métriques n'écoutent que sur `127.0.0.1`. Pareil pour CoreDNS, Cilium et Hubble, qui ont des métriques actives depuis le M15 que personne ne collecte. Je veux tout ça, par le code, un nœud de contrôle à la fois.

**Objectifs pédagogiques**
- Exposer les métriques du plan de contrôle d'un cluster kubeadm (adresses d'écoute de `kube-controller-manager`, `kube-scheduler`, `--listen-metrics-urls` d'etcd) et mesurer ce que cela expose.
- Reconfigurer un composant statique par `kubeadm init phase …` sur un cluster existant, nœud par nœud, avec retour arrière.
- Activer les cibles correspondantes du chart et les ServiceMonitor de Cilium, d'Hubble et de l'opérateur.
- Comprendre comment Prometheus s'authentifie auprès des composants qui exigent un jeton.

**Prérequis** : M14-E23, E27 (configuration kubeadm dans `plateforme/k8s`, `outils/reconfigurer-apiserver.sh`), M15-E26 (métriques de Cilium), M17-E10 (release Helmfile `cilium`).
**Durée indicative** : 3 h.

**Contexte technique**
- `kube-controller-manager` (10257) et `kube-scheduler` (10259) servent leurs métriques en HTTPS avec authentification et autorisation déléguées : seule leur adresse d'écoute (`bind-address`) est à changer. etcd sert `/metrics` en HTTP **sans authentification** sur l'URL de `--listen-metrics-urls` (kubeadm : `http://127.0.0.1:2381`).
- Configuration : `cluster/kubeadm-config.yaml` de `plateforme/k8s` (API `v1beta4`, `extraArgs` en liste `name`/`value`) ; application nœud par nœud : `kubeadm init phase control-plane controller-manager|scheduler` et `kubeadm init phase etcd local`, puis `kubeadm init phase upload-config kubeadm` une fois les trois nœuds passés (méthode de M14-E27).
- Chart : `kubeControllerManager`, `kubeScheduler`, `kubeEtcd`, `coreDns` (désactivés en E02) ; `kubeProxy` reste désactivé.
- Cilium : valeurs `composants/cilium/values.yaml` de `plateforme/k8s`, release Helmfile `cilium` ; les métriques de l'agent (9962), de l'opérateur (9963), de l'Envoy (9964) et d'Hubble (9965) sont déjà actives (M15-E26).

> ⚠️ **Attention** : régénérer un manifeste statique redémarre le composant ; régénérer celui d'**etcd** redémarre un membre de la base du cluster. Un nœud de contrôle à la fois, quorum vérifié avant et après (`etcdctl endpoint health --cluster`), instantané etcd vérifié avant de commencer (RB-141). Retour arrière : le script garde le manifeste d'origine hors de `/etc/kubernetes/manifests/` et le remet si le composant ne redevient pas sain.

**Travail demandé**
1. Mesure la surface : sur `k8s-cp01`, `ss -tlnp` pour les ports 10257, 10259, 2381. Dans `~/m21/e20/journal.md` : que pourrait faire un tiers qui joint `:2381` ? et `:10257` sans jeton ? Quel compromis retiens-tu pour l'adresse d'écoute (`0.0.0.0`, adresse du nœud par *patch* kubeadm) ?
2. Modifie `cluster/kubeadm-config.yaml` (MR) et écris `outils/reconfigurer-plan-controle.sh` (généralisation de `reconfigurer-apiserver.sh` : composant en argument, contrôle de santé propre à chaque composant, retour arrière). Applique sur `k8s-cp01`, vérifie, puis `k8s-cp02`, `k8s-cp03`, puis téléverse la configuration.
3. Active les cibles du plan de contrôle et de CoreDNS dans `kps/values.yaml` (MR, synchronisation). Contrôle les cibles `kube-controller-manager`, `kube-scheduler`, `kube-etcd`, `coredns` : avec quelle identité Prometheus s'authentifie-t-il auprès des deux premiers ? Où le voit-on ?
4. Cilium : active les ServiceMonitor de l'agent, de l'opérateur, de l'Envoy et d'Hubble dans les valeurs de la release, avec l'étiquette de sélection commune. `helmfile -e par1 -l composant=cilium diff`, puis `apply`. Lis le diff : un redémarrage des agents est-il déclenché ?
5. Vérifie quelques séries utiles : `etcd_server_has_leader`, `etcd_disk_wal_fsync_duration_seconds_bucket`, `workqueue_depth`, `scheduler_pending_pods`, `coredns_dns_requests_total`, `cilium_drop_count_total`, `hubble_drop_total`, et les alertes du chart qui s'appuient sur elles (page *Alerts*).

**Critères de réussite**
- [ ] Les jobs `kube-controller-manager`, `kube-scheduler` et `kube-etcd` ont chacun trois cibles `up == 1`, `coredns` au moins deux.
- [ ] Les cibles de l'agent Cilium (une par nœud), de l'opérateur Cilium et d'Hubble sont `up`.
- [ ] `cluster/kubeadm-config.yaml` sur `main` contient les nouvelles adresses d'écoute, et le ConfigMap `kube-system/kubeadm-config` les contient aussi.
- [ ] Les trois membres etcd sont sains et le cluster n'a pas changé de version.

**Vérification** : `lab/bin/check 21 20`

<details><summary>Indice 1</summary>

Dans `v1beta4`, `controllerManager.extraArgs`, `scheduler.extraArgs` et `etcd.local.extraArgs` sont des **listes** d'objets `{name, value}`. Le contrôle de santé du contrôleur se fait en HTTPS local (`https://127.0.0.1:10257/healthz`, certificat auto-signé), celui d'etcd en HTTP sur le port des métriques (`/health`).
</details>

<details><summary>Indice 2</summary>

Le chart crée lui-même, dans `kube-system`, des Services sans adresse (*headless*) qui sélectionnent les pods statiques par leur étiquette `component` : tu n'as aucun Service à écrire. Les ServiceMonitor du chart s'authentifient par un jeton de compte de service dans un Secret (depuis la version 90 du chart) : regarde leur section `authorization`.
</details>

**Pour aller plus loin** (facultatif) : [Reconfiguring a kubeadm cluster](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-reconfigure/) et les *patches* de kubeadm (`--patches`) pour une adresse d'écoute par nœud ; les tableaux de bord du chart pour etcd et le plan de contrôle.

---

### M21-E21 — Revue : les règles d'alerte du stagiaire  `REV` `★★`

> **Ticket PLAT-2221** — *De : Karim Benali*
> Lucas a écrit des alertes pour « couvrir tout ce qui manque ». Il a ouvert une MR. Fais la revue avant que quelqu'un la fusionne : je pense qu'il y a de quoi réveiller Nadia toutes les nuits. Pousse ta version corrigée dans une branche à côté, avec des tests.

**Objectifs pédagogiques**
- Relire des règles Prometheus avec une grille : symptôme ou cause, fenêtre, `for`, fonction adaptée au type de métrique, agrégation, étiquettes, annotations, cardinalité.
- Argumenter chaque remarque, proposer la correction et la prouver par un test.

**Prérequis** : M21-E14, M21-E15.
**Durée indicative** : 2 h.

**Contexte technique**
- Fichiers fournis : [`ressources/E21-regles-lucas/`](../ressources/E21-regles-lucas/) (`alertes-lucas.yaml`, `enregistrement-lucas.yaml`, et la description de MR `MR-lucas.md`).
- Version corrigée : branche **`revue-lucas`** de `plateforme/observabilite`, fichiers `regles/alertes-lucas.yaml` et `regles/enregistrement-lucas.yaml`, tests `tests/alertes-lucas.test.yaml` ; elle n'est **pas** fusionnée (c'est une proposition à Lucas).
- Intervalle de collecte du cluster : 30 s (défaut du chart).

**Travail demandé**
1. Lis la MR et les deux fichiers. Relève **au moins dix** défauts dans `~/m21/e21/revue.md`, chacun avec : la ligne, le problème, la conséquence concrète (fausse alerte, alerte muette, coût), la correction.
2. Distingue ce qui est une **erreur** (la règle ne fait pas ce qu'elle annonce) de ce qui est un **choix** discutable (à argumenter avec Lucas).
3. Écris la version corrigée dans la branche `revue-lucas` : supprime ce qui ne doit pas exister, corrige le reste, et écris un test `promtool` pour chaque alerte conservée. Le pipeline de la branche doit être vert.
4. Rédige le commentaire de revue à Lucas (dans la MR) : ton bienveillant, trois points prioritaires, renvoi vers ta branche.

**Critères de réussite**
- [ ] `revue.md` relève au moins dix défauts argumentés.
- [ ] La branche `revue-lucas` existe ; aucune alerte n'y utilise `irate`, chacune a un `for`, `gravite`, `equipe` et un `runbook_url` vers un runbook existant ; le dernier pipeline de la branche a réussi.

**Vérification** : `lab/bin/check 21 21`

<details><summary>Indice 1</summary>

Pour chaque règle, pose cinq questions : quelle est la métrique (compteur, jauge, histogramme) ? la fonction convient-elle à ce type ? la fenêtre couvre-t-elle au moins quatre collectes ? qui est réveillé et pourquoi ? que voit-on dans le courriel (étiquettes, annotations) ?
</details>

<details><summary>Indice 2</summary>

Une étiquette d'alerte qui change à chaque évaluation (une valeur mesurée, un identifiant de requête) crée une **nouvelle** alerte à chaque fois : l'ancienne se résout, la nouvelle part. Une valeur se met dans une annotation, jamais dans une étiquette.
</details>

---

### M21-E22 — Runbook : répondre à une alerte  `RED` `★★`

> **Ticket PLAT-2222** — *De : Nadia Roussel*
> Une alerte sans runbook, c'est une alerte qui me réveille pour rien : je ne sais pas quoi faire. Il me faut un modèle commun, puis les runbooks de nos trois alertes principales : erreurs de MédiAgenda, latence de MédiAgenda, disque plein. Écrits pour quelqu'un qui est réveillé à 3 h et qui ne connaît pas le détail de l'application.

**Objectifs pédagogiques**
- Structurer un runbook d'alerte : ce que signifie l'alerte, impact, premières vérifications, causes connues et actions, escalade, retour à la normale, après l'incident.
- Écrire des commandes et requêtes directement utilisables, sans supposer de contexte.

**Prérequis** : M21-E15, M21-E19.
**Durée indicative** : 2 h 30.

**Livrables** (dans `plateforme/medisphere`, `docs/observabilite/metriques/runbooks/`) :
- `RB-210-modele-runbook-alerte.md` : le modèle (sections, règles d'écriture, ce qu'un runbook ne contient pas) ;
- `RB-211-mediagenda-erreurs.md` (`MediagendaTauxErreurEleve`), `RB-212-mediagenda-latence.md` (`MediagendaLatenceElevee`), `RB-213-disque-plein.md` (`DisqueBientotPlein`).

**Contraintes**
- Chaque runbook tient sur un écran et demi ; il commence par « Que signifie cette alerte » et « Impact pour les utilisateurs ».
- Les premières vérifications sont des requêtes PromQL et des liens vers les tableaux d'E19 (avec la variable déjà positionnée) ; les commandes indiquent l'hôte et le compte.
- Aucun secret, aucune commande destructive sans avertissement et retour arrière.
- Escalade : qui appeler, quand (Julien Petit pour l'application, Karim Benali pour la plateforme), et quand ouvrir un incident `INC-48xx`.
- Les `runbook_url` des alertes d'E15 pointent vers ces fichiers.

Exercice auto-évalué : relis tes runbooks avec la grille du corrigé.

---

### M21-E23 — Diagnostiquer une saturation par les métriques  `LAB` `★★★`

> **Incident INC-4823** — *De : Nadia Roussel*
> Hier entre 14 h et 15 h, la recette de MédiAgenda a répondu en plusieurs secondes pendant la campagne de tests de charge des partenaires. Personne n'a su dire si c'était l'API, la base ou le cache. Reproduis le phénomène, trouve **par les métriques** ce qui sature, écris-le, et fais en sorte que la prochaine fois, une alerte le dise avant les partenaires.

**Objectifs pédagogiques**
- Générer une charge contrôlée et bornée depuis le cluster.
- Mener un diagnostic de saturation par les métriques : débit, latence, erreurs, puis CPU bridé (*throttling*), mémoire, connexions PostgreSQL, cache Valkey.
- Écrire un journal de diagnostic daté et chiffré.
- Ajouter une règle ou une alerte de saturation qui aurait prévenu.

**Prérequis** : M21-E14, M21-E15, M21-E19.
**Durée indicative** : 3 h.

**Contexte technique**
- Générateur : `oha` 1.16, image `registry.par1.medisphere.internal/ghcr/hatoo/oha:1.16.0` (cache `ghcr`), en **Job** dans `wb-essais`, vers `https://mediagenda-recette.apps.par1.medisphere.internal` (racine MédiSphère par une ConfigMap, option `--cacert`). Squelette : [`ressources/E23-charge/charge-oha.yaml`](../ressources/E23-charge/charge-oha.yaml).
- Métriques de PostgreSQL : l'exportateur intégré aux instances CloudNativePG (port nommé `metrics`, 9187), collecté par le `PodMonitor` `mediagenda-db` du composant `supervision` (E07, `job="mediagenda-db"`).
- Bridage du CPU : kube-prometheus-stack ne garde de cAdvisor que les **périodes** (`container_cpu_cfs_periods_total`, `container_cpu_cfs_throttled_periods_total`) ; `container_cpu_cfs_throttled_seconds_total` est jetée par une réécriture des valeurs par défaut du chart (`helm show values`, clé `kubelet.serviceMonitor.cAdvisorMetricRelabelings`).
- Journal : `docs/kubernetes/journal/AAAA-MM-JJ-INC-4823-saturation-recette.md` dans `plateforme/medisphere`.
- Règle et alerte de saturation dans `regles/alertes-mediagenda.yaml` (et leur test).

> ⚠️ **Attention** : la charge vise **la recette seulement**, jamais la prod ; elle est **bornée** (durée et débit maximum dans le Job, `activeDeadlineSeconds`), et tu préviens Julien avant (canal de l'équipe). Les travailleurs sont partagés : surveille `kubectl top nodes` pendant l'essai ; arrêt immédiat par `kubectl delete job -n wb-essais charge-oha`.

**Travail demandé**
1. Vérifie que le `PodMonitor` `mediagenda-db` (E07) collecte la base de recette, et repère les métriques de connexions (actives, maximum autorisé).
2. Mesure de référence (10 minutes au calme) : débit, p95, ratio 5xx, CPU par pod de l'API et ses limites, mémoire, connexions à la base, taux de succès du cache (`mediagenda_cache_total`). Consigne-les.
3. Complète le Job à partir du squelette : charge par paliers (par exemple 20, 50, 100 requêtes par seconde, trois minutes chacun) sur `GET /api/v1/creneaux` avec des dates variées et `GET /api/v1/rendez-vous`. Lance-le.
4. Pendant la charge, suis tes tableaux RED et USE. Pour chaque palier, relève : débit servi, p95, 5xx, part de CPU bridé (`container_cpu_cfs_throttled_periods_total` rapporté à `container_cpu_cfs_periods_total`), connexions PostgreSQL, succès du cache. Qu'est-ce qui sature en premier ?
5. Formule une hypothèse et **vérifie-la** par une seconde mesure qui change un seul paramètre (par exemple, une requête qui ne touche pas la base, ou une limite de CPU différente dans un essai en dehors de la recette).
6. Rédige le journal : chronologie, mesures (tableau), hypothèses testées, cause, recommandations (chiffrées).
7. Ajoute la règle et l'alerte de saturation qui t'auraient prévenu (par exemple : CPU bridé au-delà d'un seuil pendant 15 minutes alors que la latence monte), avec son test `promtool`. MR, synchronisation.

**Critères de réussite**
- [ ] Le journal `…INC-4823…` est sur `main` de `plateforme/medisphere` et contient des mesures chiffrées pour chaque palier et la cause identifiée.
- [ ] Une alerte de saturation de MédiAgenda est chargée dans le Prometheus du cluster, testée en CI.
- [ ] Le `PodMonitor` `mediagenda-db` collecte la base de recette (`cnpg_*` présentes) ; le Job de charge n'existe plus dans `wb-essais`.

**Vérification** : `lab/bin/check 21 23`

<details><summary>Indice 1</summary>

Un pod bridé n'a pas forcément un CPU « à 100 % » : il consomme son quota en début de période de 100 ms, puis attend. Regarde la **part de périodes bridées**, pas seulement l'utilisation moyenne. Et compare la latence au nombre de connexions : chaque processus de l'API a un réservoir de connexions borné.
</details>

<details><summary>Indice 2</summary>

`oha` affiche son propre histogramme de latences en fin d'exécution (`--no-tui`, sortie dans les journaux du pod) : compare-le au p95 mesuré par l'application. Un écart important dit que l'attente se passe **avant** l'application (file d'attente de la passerelle, connexions TCP).
</details>

**Pour aller plus loin** (facultatif) : la page *Throttling* de la documentation de Kubernetes sur les limites de CPU, et les métriques de pression (`node_pressure_cpu_waiting_seconds_total`, PSI) ; refais l'essai **sans** limite de CPU (requête seule) sur une copie de MédiAgenda dans `wb-essais` et compare.
