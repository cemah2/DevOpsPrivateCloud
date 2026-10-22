# Module 21 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Les solutions complètes sont dans [`fichiers/`](fichiers/), un dossier par exercice, sous la forme d'un **extrait des projets** : `…/observabilite/…` = `plateforme/observabilite`, `…/ansible/…` = `plateforme/ansible`, `…/k8s/…` = `plateforme/k8s`, `…/infra/…` = `plateforme/infra`, `…/gitops/…` = `plateforme/gitops`, `…/deploiement…/…` = `mediagenda/deploiement` (ou `medidoc/deploiement`), `…/ceph/…` = `plateforme/ceph`, `…/medisphere/…` = la documentation, `…/git01/` et `…/pve01/` = fichiers posés sur ces hôtes, `…/essais/` = `~/m21/eXX/`. On **superpose** les dossiers dans l'ordre des exercices, par-dessus ceux du palier 1 (E07 pour `plateforme/observabilite` et les composants `supervision`) ; un fichier d'un exercice plus récent remplace le précédent. Les `*.extrait` sont des morceaux à intégrer dans un fichier existant (l'emplacement est dit en tête).

**Ce qui a été vérifié, ce qui ne l'a pas été.**
- *Règles et alertes* : toutes les PrometheusRule du palier extraites (`outils/extraire-regles.sh`) et passées à `promtool check rules` **et** `promtool test rules` (Prometheus 3.15.1) : tests d'E14, E15, E21 (branche `revue-lucas`) et E23 au vert ; les règles des ressources de Lucas passent `promtool check rules` (c'est le piège : la syntaxe ne dit rien du sens). Règles chargées dans un vrai Prometheus 3.15.1 (page *Rules* : santé `ok`), et les filtres `jq` des checks E14 et E15 rejoués contre cette API.
- *Alertmanager* : configuration d'E16 rendue par le chart (`helm template` de kube-prometheus-stack 92.11.0 avec les valeurs du palier 1 et les extraits), contrôlée par `amtool check-config` 0.34.1, routage rejoué par `outils/tester-routes.sh` d'E07 (13 essais au vert), configuration chargée dans un vrai Alertmanager 0.34.1 avec un silence `CHG-2216` : le check E16 y passe au vert. Supprimer une route d'équipe le fait passer au rouge.
- *Objets Kubernetes* : `kubeconform -strict` avec les schémas tirés des CRD de prometheus-operator 0.94 (chart 92.11.0) et d'Argo Rollouts 1.10.1 (ScrapeConfig, ServiceMonitor, PrometheusRule, ClusterAnalysisTemplate, Prometheus rendu avec `scrapeClasses`) ; `kustomize build` (5.8.3) de tout `plateforme/observabilite` superposé (22 objets valides) ; `helm template` du chart Cilium 1.20.2 avec les valeurs du M15 et l'extrait d'E20 (quatre ServiceMonitor étiquetés).
- *Réécritures* : la règle conditionnelle de la classe de collecte (`regex: "^$"`) et le `drop` des seaux de sonde rejoués dans un Prometheus local sur des métriques au format de MédiAgenda.
- *Supervision témoin* : rôle `supervision_temoin` passé à `ansible-lint` (profil `production`, 0 défaut) et `ansible-playbook --syntax-check` ; gabarits rendus par Ansible et validés par `promtool check config`, `amtool check-config` et `blackbox_exporter --config.check` ; Prometheus 3.13.5 et blackbox_exporter 0.29.1 lancés avec la configuration rendue : sonde ICMP réussie, trois règles chargées, alerte `CibleTemoinInjoignable` en attente sur une cible arrêtée. Empreintes SHA-256 relevées dans les `sha256sums.txt` officiels.
- *Tableaux* : 6 tableaux générés au modèle classique, validés par `outils/valider-tableaux.py` (et 3 erreurs détectées sur un tableau volontairement abîmé) ; 65 expressions PromQL des tableaux analysées par un Prometheus 3.15.1.
- *OpenTofu* : `tofu validate` et `tofu fmt -check` (OpenTofu 1.13.2, fournisseur `grafana/grafana` 4.50.0).
- *Scripts* : `shellcheck -x` et `bash -n` sur tous les scripts (checks, `reconfigurer-plan-controle.sh`, scripts de `pve01`, `trafic-empoisonne.sh`, `extraire-regles.sh`) ; `python3 -m py_compile` sur `valider-tableaux.py` ; frontend HAProxy de métriques validé (`haproxy -c`) et interrogé (200 sur `/metrics`, 404 ailleurs). Requête empoisonnée d'E18 : `psycopg` refuse bien un caractère nul côté client (`DataError`).
- **Non rejoués sur le lab réel** (signalés « ⚠️ À vérifier sur ton lab ») : collecte effective des exportateurs (Ceph derrière firewalld, GitLab et sa liste blanche, Harbor), adresse source vue par HAProxy sur les nœuds de contrôle, comportement de `ceph-par1` avec `standby_behaviour`, réutilisation par le provisionnement de Grafana d'un dossier créé par OpenTofu, canary réel et `AnalysisRun`, régénération des manifestes du plan de contrôle et d'etcd, sondes SMTP et ICMP contre Mailpit et la bordure, noms des métriques d'Envoy de la passerelle, chiffres de la saturation d'E23.

**Où lancer les commandes.** `admin@adm01:~$` avec ton kubeconfig personnel ; `admin@adm01:~/src/observabilite$`, `~/src/ansible$`, `~/src/k8s$`, `~/src/infra$` dans les copies des projets ; `admin@mon01:~$`, `root@pve01:~#`, `[admin@ceph01 ~]$` sur les hôtes. Toute modification passe par une MR relue puis la synchronisation d'Argo CD (`argocd app get observabilite --refresh` pour ne pas attendre).

---

### M21-E10 — Exportateurs natifs : Ceph, HAProxy, PowerDNS, Kea, GitLab, Harbor

**Solution**

Fichiers : `ScrapeConfig` [`ceph.yaml`](fichiers/M21-E10/observabilite/scrape/ceph.yaml), [`haproxy.yaml`](fichiers/M21-E10/observabilite/scrape/haproxy.yaml), [`powerdns.yaml`](fichiers/M21-E10/observabilite/scrape/powerdns.yaml), [`gitlab.yaml`](fichiers/M21-E10/observabilite/scrape/gitlab.yaml), [`harbor.yaml`](fichiers/M21-E10/observabilite/scrape/harbor.yaml), [`kustomization.yaml`](fichiers/M21-E10/observabilite/scrape/kustomization.yaml) ; HAProxy : [`role_lb`](fichiers/M21-E10/ansible/inventories/lab/group_vars/role_lb/haproxy.yml.extrait), [`k8s_plan_controle`](fichiers/M21-E10/ansible/inventories/lab/group_vars/k8s_plan_controle/haproxy_metriques.yml) et le rôle [`k8s_plan_controle`](fichiers/M21-E10/ansible/roles/k8s_plan_controle/) ; PowerDNS : extraits des rôles [`powerdns_auth`](fichiers/M21-E10/ansible/roles/powerdns_auth/) et [`powerdns_recursor`](fichiers/M21-E10/ansible/roles/powerdns_recursor/), variables [`role_dns`](fichiers/M21-E10/ansible/inventories/lab/group_vars/role_dns/supervision.yml), [`dns01`](fichiers/M21-E10/ansible/inventories/lab/host_vars/dns01/supervision.yml), [`dns02`](fichiers/M21-E10/ansible/inventories/lab/host_vars/dns02/supervision.yml) ; [`gitlab.rb.extrait`](fichiers/M21-E10/git01/gitlab.rb.extrait) ; [Ceph](fichiers/M21-E10/ceph/prometheus-mgr.md) ; [flux](fichiers/M21-E10/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) et [matrice](fichiers/M21-E10/medisphere/docs/socle/matrice-flux.md.extrait) ; [inventaire](fichiers/M21-E10/essais/inventaire.md).

1. **Inventaire** ([modèle](fichiers/M21-E10/essais/inventaire.md)). Le point clé est **Kea 3.0** : il n'a **aucun** point d'accès Prometheus natif. Ses statistiques (`pkt4-received`, baux par sous-réseau…) se lisent par les commandes `statistic-get-all` du canal de contrôle, celui que M06-E25 a mis en HTTPS sur le port 8004 avec le compte `supervision`. Trois voies : `kea-exporter` (petit service Python qui interroge ce canal), l'agent de **Stork** d'ISC (exportateur intégré, plus complet, plus lourd), ou un script pour le collecteur `textfile` de node_exporter (fragile). Choix : `kea-exporter` en « pour aller plus loin », Stork si Kea se généralise.
2. **Ceph.**
   ```
   [admin@ceph01 ~]$ sudo cephadm shell -- ceph mgr module enable prometheus
   [admin@ceph01 ~]$ sudo cephadm shell -- ceph mgr services
   admin@adm01:~$ for n in 51 52 53; do curl -s -o /dev/null -w "10.10.30.$n : %{http_code} %{size_download}\n" http://10.10.30.$n:9283/metrics; done
   10.10.30.51 : 200 412873
   10.10.30.52 : 200 0
   10.10.30.53 : 200 0
   ```
   Avec `standby_behaviour` à `default`, seul le mgr **actif** sert les métriques ; les mgr en attente répondent `200` avec un corps vide. Les trois cibles restent `up`, `ceph_*` n'existe qu'une fois, et une bascule du mgr ne déclenche aucune alerte « cible injoignable ». Le mode `error` ne change que la réponse des mgr en attente sur la **racine** `/` (500 par défaut, `standby_error_status_code`) : il sert au contrôle de santé d'un répartiteur placé devant les mgr, pour qu'il n'envoie qu'à l'actif ; `/metrics` d'un mgr en attente répond toujours `200` avec un corps vide (code du module `prometheus` de Tentacle, classe `StandbyModule`). Sans répartiteur, il n'apporte donc rien ici. **`honorLabels: true`** : la documentation le demande, parce que les séries par démon portent leur propre `instance` (nom de l'hôte du démon) ; sans lui, Prometheus la renommerait `exported_instance`, et ces séries changeraient d'`instance` à chaque bascule du mgr. Les réglages sont consignés dans [`plateforme/ceph`](fichiers/M21-E10/ceph/prometheus-mgr.md), avec le pare-feu `firewalld` des nœuds Rocky (cephadm ouvre parfois lui-même les ports des modules : regarde avant d'ajouter).
3. **HAProxy.** Sur `lb01`/`lb02`, aucune modification du rôle : le frontend est une section de plus dans `haproxy_sections` ([lb](fichiers/M21-E10/ansible/inventories/lab/group_vars/role_lb/haproxy.yml.extrait)). Sur les nœuds de contrôle, **piège** : `haproxy_sections` y est passée au rôle `haproxy` par l'`include_role … vars:` du rôle `k8s_plan_controle` (M14-E03), qui l'emporte sur toute variable d'inventaire : une section posée dans `group_vars/k8s_plan_controle` serait ignorée **sans erreur**. On ouvre donc le rôle à des sections supplémentaires ([tâche](fichiers/M21-E10/ansible/roles/k8s_plan_controle/tasks/point_acces.yml.extrait), [défaut](fichiers/M21-E10/ansible/roles/k8s_plan_controle/defaults/main.yml.extrait)) et on déclare le frontend dans [`group_vars/k8s_plan_controle/haproxy_metriques.yml`](fichiers/M21-E10/ansible/inventories/lab/group_vars/k8s_plan_controle/haproxy_metriques.yml) ; application avec `--tags point_acces`, un nœud de contrôle à la fois (`haproxy -c` puis rechargement sans coupure de l'API). L'ordre compte : la règle `http-request deny … unless supervision` passe **avant** `use-service prometheus-exporter`, sinon le service répond avant que l'ACL ne soit évaluée ; une dernière règle `deny 404` refuse tout autre chemin. Le rôle rend la configuration, la valide (`haproxy -c`) et recharge sans coupure.
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/repartiteurs.yml --limit lb02 --check --diff
   admin@adm01:~$ curl -s http://lb01.par1.medisphere.internal:8405/metrics | grep -m3 '^haproxy_'
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' http://lb01.par1.medisphere.internal:8405/   # 404
   ```
   (Le nom des playbooks est celui de ton dépôt : M07 pour les répartiteurs, M14 pour les nœuds de contrôle ; applique un hôte à la fois. Contrôle que la section est bien là : `ssh k8s-cp01 'grep -n fe_metriques /etc/haproxy/haproxy.cfg'`.) Sur les nœuds de contrôle, Prometheus est sur le même VLAN : selon le chemin choisi par Cilium, HAProxy voit l'adresse du travailleur ou celle du pod ; l'ACL accepte les deux (⚠️ à vérifier sur ton lab, en retirant `no log` le temps d'un essai).
4. **PowerDNS.** `/metrics` est servi par le **serveur web** de chaque logiciel, pas par une option à part : sur l'autoritaire, c'est le serveur web de l'API (8081, `webserver-allow-from`) ; sur le récurseur, le **webservice** (section `webservice` de `recursor.yml` : `webserver`, `address`, `port` 8082, `allow_from`). Les rôles du M06 sont étendus ([défauts et gabarits](fichiers/M21-E10/ansible/roles/)) : le secondaire `dns02`, qui n'a pas d'API (M06-E24), reçoit un serveur web **sans API** (`api=no`, `webserver=yes`) ; le récurseur n'a pas de clé d'API, son API REST reste inutilisable. Sur `dns01`, ajouter les travailleurs à `webserver-allow-from` leur ouvre le **réseau** de l'API, pas l'API : la clé `X-API-Key` reste exigée (401 sans elle). Aucun `webserver-password` n'est posé au M06 ; si tu en poses un, il protège aussi `/metrics`, et le `ScrapeConfig` doit présenter `basicAuth` (Secret hors Git).
5. **GitLab** ([`gitlab.rb.extrait`](fichiers/M21-E10/git01/gitlab.rb.extrait)). Instantané, `free -m`, puis :
   ```
   admin@adm01:~$ ms-snapshot --prefix avant-m21e10 1004
   admin@git01:~$ sudo gitlab-ctl reconfigure && sudo gitlab-ctl status && free -m
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://git01.par1.medisphere.internal/-/metrics   # 200 depuis adm01 (liste blanche)
   ```
   On rallume `gitlab-exporter` (9168), les métriques de Sidekiq (8082), Workhorse (9229) et Gitaly (9236), sur l'adresse INFRA ; `/-/metrics` (Rails) passe par le HTTPS d'omnibus et sa **liste blanche**, où l'on ajoute les travailleurs (Prometheus sort du cluster avec l'adresse du nœud : le journal `gitlab_access.log` le montre). On laisse éteints le Prometheus et l'Alertmanager embarqués (le cluster fait ce travail), `postgres_exporter` et `redis_exporter` (20 à 40 Mo chacun, et `gitlab-exporter` donne déjà l'état des files et de la base vu de l'application). Mesure type : +130 Mo, l'essentiel pour `gitlab-exporter` (⚠️ à vérifier chez toi).
6. **Harbor.** `metric.enabled: true` depuis le M13 ; le même point d'accès sert l'exportateur de Harbor (projets, artefacts, quotas, tâches) et, avec `?comp=core|registry|jobservice`, chaque composant. Un `ScrapeConfig` ne porte qu'un jeu de `params` : on déclare quatre groupes de cibles (même adresse) avec une étiquette `composant` et on la réécrit en `__param_comp` ; sans ce paramètre distinct, Prometheus fusionnerait les quatre cibles identiques.
7. **Flux** ([extrait](fichiers/M21-E10/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait)) : `K8S_TRAV` → `lb01`/`lb02` 8405, `dns01`/`dns02` 8081-8082, `git01` 8082/9168/9229/9236, `reg01` 9090. Rien vers `ceph-par1` (carte `eth1`, sans la bordure) ni vers les nœuds de contrôle (même VLAN). Une passerelle à la fois, puis la [matrice](fichiers/M21-E10/medisphere/docs/socle/matrice-flux.md.extrait).
8. **Collecte et requêtes de sens.**
   ```
   ceph_health_status                                         # 0 OK, 1 WARN, 2 ERR
   sum by (instance, proxy) (haproxy_server_status{state="DOWN"})
   rate(pdns_recursor_servfail_answers[5m]) / rate(pdns_recursor_questions[5m])
   sum by (name) (sidekiq_queue_size)                         # gitlab-exporter
   harbor_artifact_pulled                                     # tirages par projet (exportateur)
   ```
   (Les noms exacts des séries viennent de chaque logiciel : relis-les dans la réponse de `/metrics` avant d'écrire une alerte.)

**Explications**

Un exportateur **intégré** connaît son logiciel de l'intérieur et suit ses versions ; un exportateur tiers interroge une API de l'extérieur, peut prendre du retard et ajoute un processus à maintenir. Le `ScrapeConfig` (`v1alpha1`) est l'objet de prometheus-operator pour les cibles hors du cluster : l'opérateur le traduit en `scrape_config`, pose `job` par réécriture (`jobName`), et copie dans ses propres secrets les ConfigMaps et Secrets référencés (ici, la racine MédiSphère). Chaque cible est un **flux** : la bordure, le pare-feu local, et la liste d'autorisation propre au service (ACL HAProxy, `allow-from` de PowerDNS, `monitoring_whitelist` de GitLab) ; les trois doivent dire la même chose.

**Alternatives**
- *Stork* pour Kea, *ceph-exporter* pour les compteurs de performance de chaque démon Ceph (déployé par cephadm avec sa pile de supervision, désactivée au M08).
- *Collecte par `mon01`* plutôt que par le cluster : utile pour ce qui doit rester visible quand le cluster tombe (palier 3) ; ici, les métriques de service vont au Prometheus principal.
- *Un `ScrapeConfig` par composant ou un seul* : un objet par job est plus lisible et se désactive seul ; un objet unique avec réécriture du `job` fonctionne mais cache le nom du job.

**Pièges classiques**
- Croire que le mode `error` du module Ceph fait tomber les mgr en attente : il ne touche que la page `/` (contrôle de santé d'un répartiteur) ; et à l'inverse, compter les cibles `up` pour savoir si les métriques de Ceph arrivent : les trois sont `up` même quand aucun mgr n'est actif depuis un moment. Surveille `absent(ceph_health_status)`.
- `use-service` placé avant le `deny` : l'ACL ne protège rien.
- `/-/metrics` de GitLab qui répond **404** : ce n'est pas une absence, c'est la liste blanche (GitLab cache l'existence de la page).
- Un seul `params` pour quatre cibles identiques de Harbor : une seule cible au lieu de quatre.
- Oublier `gitlab_rails['monitoring_whitelist']` des répartiteurs (M07-E13) en réécrivant la ligne : leurs contrôles de santé tombent, GitLab disparaît de la VIP.

**En production chez MédiSphère**
Chaque nouveau logiciel du socle arrive avec ses métriques (critère d'acceptation d'un rôle Ansible), son `ScrapeConfig`, ses flux et sa ligne de matrice ; les exportateurs écoutent sur une interface d'administration, jamais publique ; `kea-exporter` ou Stork pour le DHCP avant le PRA (F5).

---

### M21-E11 — Sondes blackbox et supervision hors cluster sur `mon01`

**Solution**

Fichiers : rôle [`supervision_temoin`](fichiers/M21-E11/ansible/roles/supervision_temoin/) (défauts, `argument_specs`, tâches, gabarits, unités), [playbook](fichiers/M21-E11/ansible/playbooks/supervision-temoin.yml), [variables de `mon01`](fichiers/M21-E11/ansible/inventories/lab/host_vars/mon01/supervision_temoin.yml), [flux](fichiers/M21-E11/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait).

1. **Lecture.** Dans le *multi-target exporter pattern*, Prometheus n'interroge pas la cible : il interroge l'exportateur en lui passant la cible (`/probe?target=…&module=…`). La réécriture met l'adresse découverte dans `__param_target`, la recopie dans `instance` (sinon toutes les séries auraient l'adresse de blackbox), puis remplace `__address__` par l'adresse de l'exportateur. `up` vaut 1 dès que **blackbox** a répondu, même si le site sondé est en panne : c'est **`probe_success`** qui dit si la sonde a réussi (et `probe_http_status_code`, `probe_duration_seconds`, `probe_ssl_earliest_cert_expiry` qui disent pourquoi).
2. **Le rôle.** Points de conception, lisibles dans les fichiers :
   - binaires dans `/opt/supervision-temoin/<composant>-<version>.linux-amd64/`, liens dans `/usr/local/bin` ; changer de version = changer version **et** empreinte (le rôle refuse une empreinte absente) ; l'ancienne arborescence reste pour le retour arrière ;
   - Prometheus **3.13.5** (LTS) : `sha256 0388822a…a0699`, relevée dans le `sha256sums.txt` de la version ; Alertmanager 0.34.1 et blackbox_exporter 0.29.1 de même ;
   - chaque configuration est rendue par `ansible.builtin.template` avec **`validate:`** (`promtool check config %s`, `amtool check-config %s`, `blackbox_exporter --config.check --config.file=%s`) : le fichier temporaire est validé avant d'être posé ; d'où des chemins **absolus** dans `rule_files` ;
   - unités durcies (`ProtectSystem=strict`, `NoNewPrivileges`, `MemoryMax`), `CapabilityBoundingSet=` vide sauf pour blackbox (`CAP_NET_RAW` ambiante, la seule obtenable) ; `ExecReload=kill -HUP` : une nouvelle configuration est rechargée, une nouvelle version redémarre le service ;
   - Alertmanager témoin **sans grappe** (`--cluster.listen-address=` vide) : sinon il ouvre 9094 et cherche des pairs.
   ```
   admin@adm01:~/src/ansible$ uv run ansible-lint --profile production roles/supervision_temoin
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/supervision-temoin.yml --check --diff
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/supervision-temoin.yml
   admin@mon01:~$ systemctl status prometheus alertmanager blackbox_exporter --no-pager | grep -E 'Active|Memory'
   admin@mon01:~$ free -m
   ```
3. **Sondes et cibles** ([variables](fichiers/M21-E11/ansible/inventories/lab/host_vars/mon01/supervision_temoin.yml), [modules](fichiers/M21-E11/ansible/roles/supervision_temoin/templates/blackbox.yml.j2)). Une URL qui prouve le **service** : `/users/sign_in` de GitLab (rendu par Rails, base et Redis compris ; `/-/readiness` est réservé à la liste blanche), `/login/` de NetBox (Django), `/api/v2.0/ping` de Harbor (service *core*), `/api/health` de Grafana, `/healthz` d'Argo CD, `/pret` de MédiAgenda (PostgreSQL et Valkey ; autorisé par la politique L7 du chart). Module `https_2xx` : TLS obligatoire, racine MédiSphère, redirections suivies. `icmp` : VIP `.1` des VLAN 10, 20, 30, 40 et 70. `dns_soa` : SOA de `par1.medisphere.internal` demandé aux récurseurs, avec une expression sur la réponse. `smtp_starttls` : bannière, `EHLO`, `STARTTLS`, bascule TLS, second `EHLO` (l'exemple officiel attend `250-AUTH`, que Mailpit n'annonce pas forcément : on attend `^250 `).
4. **Règles et Alertmanager témoin** ([règles](fichiers/M21-E11/ansible/roles/supervision_temoin/templates/regles-temoin.yml.j2), [Alertmanager](fichiers/M21-E11/ansible/roles/supervision_temoin/templates/alertmanager.yml.j2)) : `SondeEnEchec` (critique, 5 min), `CertificatEcheanceProche` (14 jours), `CibleTemoinInjoignable` ; un seul récepteur, `astreinte@`, STARTTLS exigé et vérifié par le magasin système de `mon01`. Les modèles `{{ $labels… }}` de Prometheus sont protégés de Jinja par `{% raw %}`.
5. **Flux et vérification.**
   ```
   admin@adm01:~$ curl -s 'http://mon01.par1.medisphere.internal:9090/api/v1/query?query=probe_success' \
       | jq -r '.data.result[] | "\(.metric.module)\t\(.metric.instance)\t\(.value[1])"'
   https_2xx    https://git01.par1.medisphere.internal/users/sign_in   1
   icmp         10.10.10.1                                             1
   smtp_starttls smtp.par1.medisphere.internal:25                      1
   …
   ```
   Les cibles du VLAN 20 (`git01`, `nbx01`, `reg01`, DNS) ne traversent pas la bordure ; il faut ouvrir `mon01` → `gw-par1` 443 et l'ICMP vers les VIP (règle d'**entrée** : ce sont des adresses de la passerelle elle-même).
6. **Panne contrôlée.** Ajoute un groupe `essai` (module `https_2xx`, cible `https://nbx01.par1.medisphere.internal:9999/`) dans les variables, joue le playbook : après 5 minutes, `SondeEnEchec` passe `firing`, un courriel `[témoin mon01] FIRING SondeEnEchec` arrive dans la boîte `astreinte@` de Mailpit. Retire le groupe : le rôle **supprime** le fichier de cibles qui n'est plus déclaré, la série disparaît, l'alerte se résout (courriel `RESOLVED`).

**Explications**

Le témoin regarde le lab **comme un utilisateur** et depuis **l'extérieur du cluster** : il sait dire « Grafana ne répond plus » quand Prometheus, Alertmanager et Grafana sont tombés ensemble. C'est pourquoi il a son propre Alertmanager et n'emprunte rien au cluster (palier 3 : il surveillera aussi la supervision du cluster). `file_sd_configs` relit les fichiers de cibles sans rechargement : ajouter une sonde ne redémarre rien.

**Alternatives**
- Paquets Debian (`prometheus`, `prometheus-alertmanager`) : plus simples, mais versions de Debian 13 (Prometheus 2.x) ; on veut la même ligne LTS partout et maîtriser la date de mise à jour.
- Conteneurs Podman/Quadlet sur `mon01` : isolement, mais une dépendance de plus sur l'hôte qui doit rester le plus simple.
- `net.ipv4.ping_group_range` au lieu de `CAP_NET_RAW` : ouvre les sockets ICMP non privilégiées à un groupe, pour tout le système.

**Pièges classiques**
- Chemins relatifs dans `rule_files` avec `validate:` : la validation porte sur un fichier temporaire, ailleurs.
- Sonde ICMP sans capacité : `socket: operation not permitted`, `probe_success` à 0 pour toutes les passerelles.
- Lire `up` au lieu de `probe_success` : « tout est vert » pendant que NetBox est en panne.
- Oublier de recopier `__param_target` dans `instance` : toutes les sondes ont la même instance, les séries se mélangent.
- Alertmanager témoin avec la grappe active : il annonce 9094 et cherche des pairs à chaque démarrage.

**En production chez MédiSphère**
Le témoin vit sur un hôte **hors** de la plateforme supervisée (ici `mon01`, demain un autre site) ; il sonde les points d'entrée **publiés** (vus des centres de santé) ; il est lui-même sauvegardé (rôle, pas données) et ses alertes vont à un canal qui ne dépend pas du cluster.

---

### M21-E12 — Proxmox VE et PBS : pve-exporter

**Solution**

Fichiers : [identité Proxmox](fichiers/M21-E12/pve01/identite-supervision.sh), [IPSet et règle](fichiers/M21-E12/pve01/pare-feu-supervision.sh), [variables de `mon01`](fichiers/M21-E12/ansible/inventories/lab/host_vars/mon01/supervision_temoin_pve.yml) et [modèle de Vault](fichiers/M21-E12/ansible/inventories/lab/host_vars/mon01/vault-critique-supervision.yml.exemple), tâches [`pve_exporter.yml`](fichiers/M21-E11/ansible/roles/supervision_temoin/tasks/pve_exporter.yml) et [unité](fichiers/M21-E11/ansible/roles/supervision_temoin/templates/pve-exporter.service.j2) (déjà dans le rôle d'E11, inactives tant que `supervision_temoin_pve_active` est faux), [`federation-mon01.yaml`](fichiers/M21-E12/observabilite/scrape/federation-mon01.yaml), [flux](fichiers/M21-E12/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [matrice](fichiers/M21-E12/medisphere/docs/socle/matrice-flux.md.extrait).

1. **Identité** ([script](fichiers/M21-E12/pve01/identite-supervision.sh)) :
   ```
   root@pve01:~# pveum user add wb-supervision@pve --comment "Supervision témoin mon01 (M21-E12), lecture seule"
   root@pve01:~# pveum user token add wb-supervision@pve prometheus --privsep 1 --comment "pve-exporter de mon01"
   root@pve01:~# pveum acl modify / --tokens 'wb-supervision@pve!prometheus' --roles PVEAuditor
   root@pve01:~# pveum user token permissions wb-supervision@pve prometheus | head
   ```
   Le secret n'est affiché qu'à la création : Vault `critique` et `~/.config/workbook/pve-supervision.env`. Preuve : `GET /api2/json/nodes` avec l'en-tête `Authorization: PVEAPIToken=wb-supervision@pve!prometheus=<SECRET>` répond 200 ; `POST /api2/json/nodes/<nœud>/qemu/<vmid>/status/start` répond 403 (`Permission check failed`). Avec `--privsep 1`, le jeton n'hérite **rien** de l'utilisateur : on pose l'ACL sur le jeton.
2. **Pare-feu Proxmox** ([script](fichiers/M21-E12/pve01/pare-feu-supervision.sh)), sur le modèle de l'IPSet `automation` du M03-E15 : copie de `cluster.fw`, IPSet `supervision` (10.10.20.19), règle d'entrée 8006 **et** 9100 (node_exporter de `pve01`), `pve-firewall compile` relu avant tout. Bordure : `mon01` → `pve01` par la sortie WAN, `mon01` → `pbs01` par `wg0`, `K8S_TRAV` → `mon01` 9090.
3. **pve-exporter** : environnement `uv` dans `/opt/pve-exporter` (uv 0.13.5 épinglé par empreinte), `prometheus-pve-exporter==3.10.1`, unité durcie qui écoute sur `127.0.0.1:9221`. La vérification TLS reste active : `requests` n'utilise pas le magasin du système mais `certifi` ; la racine de `pve01` est ajoutée au magasin du système, et l'unité pose `REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt`. `pve.yml` (0600, utilisateur `pve-exporter`) : `user`, `token_name`, `token_value`, `verify_ssl: true`. Jobs du témoin : `pve` (`/pve?target=<pve01>&module=default&cluster=1&node=1`, réécriture comme pour blackbox) et `hyperviseurs` (HTTPS, racine MédiSphère).
4. **node_exporter de `pve01` et `pbs01`** : le rôle d'E08, appliqué hors de `socle` (`--limit pve01,pbs01`, inventaire des hôtes physiques s'il n'existe pas : `ansible_user: root`). Le certificat doit couvrir le nom par lequel `mon01` les joint : on cible `pve01.par1.medisphere.internal` et `pbs01.par2.medisphere.internal` (enregistrements DNS à ajouter s'ils manquent). ⚠️ À vérifier sur ton lab : le mode d'émission du certificat (ACME HTTP-01 depuis `ca01` vers `pve01` ne passe pas par la bordure ; le provisionneur JWK `admin` de step-ca est l'alternative).
5. **Témoin** :
   ```
   admin@adm01:~$ curl -s 'http://mon01.par1.medisphere.internal:9090/api/v1/query' --data-urlencode 'query=pve_up{id=~"node/.*"}' | jq -c '.data.result[] | [.metric.id, .value[1]]'
   ["node/pve01","1"]
   ```
   Mémoire et disque : `pve_memory_usage_bytes{id="node/pve01"} / pve_memory_size_bytes{id="node/pve01"}`, `pve_disk_usage_bytes{id=~"storage/pve01/.*"}`.
6. **Fédération** ([`federation-mon01.yaml`](fichiers/M21-E12/observabilite/scrape/federation-mon01.yaml)) : `metricsPath: /federate`, `params: {"match[]": ['{job=~"pve|hyperviseurs|blackbox"}']}`, **`honorLabels: true`**. Dans le cluster, `pve_up` garde `job="pve"` et `instance="pve01"` ; sans `honorLabels`, elles deviendraient `exported_job`/`exported_instance` et `job` vaudrait `federation-mon01` : aucune requête écrite pour le témoin ne marcherait plus.
7. **Journal.** Fédérer **tout** le témoin dupliquerait ses séries de fonctionnement (`prometheus_*` de `mon01`) dans le cluster et ferait du cluster un second témoin ; on ne tire que ce qui ne peut venir que de là. `/federate` renvoie la **dernière valeur** de chaque série : l'intervalle de collecte de la fédération (30 s) doit valoir celui de la source, sinon des échantillons sautent et un `rate()` calculé dans le cluster sur une fenêtre courte devient faux (règle : calculer les `rate()` sur la source, ou des fenêtres d'au moins quatre intervalles).

**Explications**

C'est `mon01`, et pas le cluster, qui parle à l'hyperviseur : le jour où le cluster est compromis, il ne détient aucun accès à Proxmox, et le jour où il tombe, l'état de `pve01` reste visible. Le rôle `PVEAuditor` est en lecture seule (`Sys.Audit`, `VM.Audit`, `Datastore.Audit`…), sur `/`, pour le seul jeton.

**Alternatives**
- *Serveur de métriques* de Proxmox (InfluxDB, Graphite) : PVE **pousse** ses mesures ; pas de jeton à gérer, mais une base de plus.
- pve-exporter sur `pve01` lui-même : pas de flux 8006, mais un logiciel de plus sur l'hyperviseur (règle MédiSphère : rien sur `pve01` que Proxmox ne fournisse).
- `pbs-exporter` (communautaire) pour les sauvegardes de PBS : en « pour aller plus loin ».

**Pièges classiques**
- `verify_ssl: false` « pour que ça marche » : la racine de `pve01` est connue depuis le M02.
- ACL posée sur l'utilisateur au lieu du jeton (avec `--privsep 1`) : 403 partout.
- Fédération sans `honorLabels`, ou `match[]` trop large (`{job=~".+"}`) : doublons et explosion des séries.
- Règle Proxmox ajoutée au mauvais niveau, ou pare-feu activé où il ne l'était pas : coupure de l'accès à l'interface.

**En production chez MédiSphère**
Un jeton par usage, révisé chaque semestre (registre des secrets du M25) ; alertes sur `pve_up`, la mémoire de `pve01`, les invités sans sauvegarde (`pve_not_backed_up_total`) ; PBS supervisé par ses tâches de vérification (palier 3).

---

### M21-E13 — Relabeling : maîtriser les étiquettes

**Solution**

Fichiers : ServiceMonitor [`mediagenda`](fichiers/M21-E13/deploiement-mediagenda/components/supervision/servicemonitor.yaml) et [`medidoc`](fichiers/M21-E13/deploiement-medidoc/components/supervision/servicemonitor.yaml) (complètent ceux d'E07), [classe de collecte](fichiers/M21-E13/observabilite/kps/values.yaml.extrait), [essai de `hashmod`](fichiers/M21-E13/essais/hashmod-temoin.yml).

1. **Méta-étiquettes.** Pour un ServiceMonitor (découverte `endpoints` par défaut, `endpointslice` si `serviceDiscoveryRole: EndpointSlice`) : `__meta_kubernetes_namespace`, `…_service_name`, `…_service_label_*`, `…_pod_name`, `…_pod_label_*`, `…_pod_container_name`, `…_pod_node_name`, `…_endpoint_port_name` (`…_endpointslice_port_name` avec le rôle `endpointslice`). Notre CR `kps` ne fixe pas `serviceDiscoveryRole` : c'est donc le rôle `endpoints`. **Pas** d'étiquettes de l'espace de noms : on dérive `environnement` du **nom** de l'espace. La page *Service Discovery* montre les deux colonnes : à gauche ce que la découverte a trouvé, à droite ce qui reste après réécriture (les `__*` disparaissent).
2. **Avant** (valeurs types) : `count by (route) (mediagenda_http_request_duration_seconds_bucket)` compte 15 seaux × méthodes par route, dont `/sante`, `/pret`, `/metrics` (≈ 45 séries par pod, sans intérêt).
3. **Moniteurs.** `relabelings` (sur la cible, une fois) : `equipe` constante, `environnement` par expression sur l'espace, `labelmap` **restreint** à `version` et `component` (un `labelmap` sur toutes les étiquettes du pod importerait `pod-template-hash` & co.). `metricRelabelings` (sur chaque série, à chaque collecte) : `drop` sur `[__name__, route]` avec le séparateur `;` et l'expression `mediagenda_http_request_duration_seconds_bucket;/(sante|pret|metrics)`. Les seaux des routes de l'API, `_sum` et `_count` restent.
4. **Classe de collecte** (`scrapeClasses`, `default: true`) : `equipe="plateforme"` et `site="par1"` **seulement si absentes** (`sourceLabels: [equipe]`, `regex: "^$"`). L'ordre est celui de l'API de prometheus-operator : réécritures de l'opérateur, puis **celles de la classe**, puis celles du moniteur. Une équipe qui pose `equipe` dans son moniteur l'emporte donc toujours ; un `ScrapeConfig` qui la pose dans ses groupes de cibles (`vms` d'E08) est respecté par la condition.
   ```
   admin@adm01:~$ kubectl get prometheus kps -n supervision -o jsonpath='{.spec.scrapeClasses}' | jq
   ```
5. **`site`.** Les **étiquettes externes** (`externalLabels`) ne sont ajoutées qu'aux échanges avec l'extérieur : alertes envoyées à Alertmanager, `/federate`, écriture distante, Thanos (palier 3). Une requête directe à ce Prometheus ne les montre pas. Les poser **aussi** sur les séries (classe de collecte) rend les requêtes locales homogènes avec celles des VMs (E08) ; une étiquette externe ne remplace jamais celle d'une série, et les deux valent `par1` : aucun conflit.
6. **`hashmod`** ([essai](fichiers/M21-E13/essais/hashmod-temoin.yml)) : l'empreinte de `__address__` modulo 2 donne 0 ou 1, stable pour une cible ; `keep` sur `0` garde environ la moitié des sondes. C'est le partage de la collecte (*sharding*) : plusieurs Prometheus, chacun sa part ; prometheus-operator le fait avec `spec.shards`. Retire le job d'essai (le playbook le fait de toute façon).
7. **Après** : plus aucun seau de sonde (`mediagenda_http_request_duration_seconds_bucket{route=~"/sante|/pret|/metrics"}` vide), ≈ 45 séries de moins par pod de MédiAgenda, autant pour MédiDoc (seaux par défaut de Go).

**Explications**

`relabelings` décide **quelles cibles** existent et **comment elles s'appellent** ; `metricRelabelings` décide **quelles séries** sont gardées, au prix d'un passage par série et par collecte. Supprimer à la source (l'application n'expose pas l'histogramme des sondes) est toujours mieux ; ici, on ne touche pas au code de l'équipe. Les étiquettes communes servent tout ce qui suit : alertes routées par `equipe` (E16), tableaux par `environnement` (E17, E19), SLO (palier 3).

**Alternatives**
- Poser les étiquettes dans **chaque** moniteur (sans classe) : lisible, mais un oubli = une série sans `equipe`, routée par défaut à la plateforme.
- `attachMetadata.node` (étiquettes du nœud) pour les DaemonSets ; `keepequal`/`dropequal` pour comparer deux étiquettes.
- Corriger l'application (pas de seaux sur les routes de sonde) : la bonne solution à terme, à proposer à Julien.

**Pièges classiques**
- `regex: ""` dans la classe : expression vide **omise** à la génération, remplacée par le défaut `(.*)` : la règle écrase alors toutes les `equipe`.
- `labelmap` trop large : des dizaines d'étiquettes, et une série nouvelle à chaque déploiement (`pod-template-hash`).
- `drop` sur `__name__` seul : toutes les séries de l'histogramme disparaissent, y compris celles de l'API.
- Croire qu'une étiquette externe apparaît dans les requêtes locales.

**En production chez MédiSphère**
Une convention d'étiquettes écrite (`equipe`, `environnement`, `site`, `version`) vérifiée par une politique d'admission sur les moniteurs (M26) ; revue trimestrielle des métriques les plus coûteuses (E14).

---

### M21-E14 — Recording rules et cardinalité

**Solution**

Fichiers : [`enregistrement-mediagenda.yaml`](fichiers/M21-E14/observabilite/regles/enregistrement-mediagenda.yaml), [`enregistrement-medidoc.yaml`](fichiers/M21-E14/observabilite/regles/enregistrement-medidoc.yaml), [`regles/kustomization.yaml`](fichiers/M21-E14/observabilite/regles/kustomization.yaml), [test](fichiers/M21-E14/observabilite/tests/enregistrement-mediagenda.test.yaml), [`outils/extraire-regles.sh`](fichiers/M21-E14/observabilite/outils/extraire-regles.sh), [limites du moniteur](fichiers/M21-E14/deploiement-mediagenda/components/supervision/servicemonitor.yaml.extrait), [requêtes de cardinalité](fichiers/M21-E14/essais/cardinalite.promql).

1. **TSDB Status** et [requêtes](fichiers/M21-E14/essais/cardinalite.promql) : `topk(10, count by (__name__) ({__name__=~".+"}))`, `count(count by (pod) ({__name__=~".+"}))`, `sort_desc(scrape_samples_post_metric_relabeling)`. Dans un `k8s-par1` type, les plus gros sont `apiserver_request_duration_seconds_bucket`, `etcd_request_duration_seconds_bucket` (après E20), `container_*` de cAdvisor, et les étiquettes aux valeurs les plus nombreuses `id`, `pod`, `le`, `uid`.
2. **`promtool tsdb analyze`** sur le témoin :
   ```
   admin@mon01:~$ sudo -u prometheus /usr/local/bin/promtool tsdb analyze /var/lib/prometheus/data
   ```
   *Highest cardinality metric names* : les métriques qui ont le plus de séries ; *Label pairs most involved in churning* : les couples étiquette=valeur qui créent et abandonnent le plus de séries (un `pod` qui change à chaque déploiement, une `instance` de sonde ajoutée puis retirée). `analyze` ouvre la base en lecture ; on ne le lance jamais sur le cluster (la commande lit tous les blocs, mémoire et disque).
3. **Règles** : le niveau `environnement` (étiquettes gardées : `equipe`, `environnement`), routes de sonde exclues ; `rate` **avant** `sum` (un `rate` sur une somme de compteurs ne voit pas la remise à zéro d'un pod) ; le ratio des 5xx vaut **0** et non « absent » quand il n'y a aucune erreur (`or … * 0`), `NaN` sans trafic ; on enregistre les **seaux** agrégés (`environnement_le:…_seaux:taux5m`) et on en tire le p95 : un centile ne s'agrège pas, des seaux si (tous environnements, autre centile, plus tard). L'exemple de la documentation interne `job:mediagenda_requetes:taux5m` agrégerait les trois environnements ensemble : inutile pour nos alertes.
4. **Test** ([fichier](fichiers/M21-E14/observabilite/tests/enregistrement-mediagenda.test.yaml)) : `promtool` lit des fichiers de règles (`groups:`), pas des PrometheusRule ; [`outils/extraire-regles.sh`](fichiers/M21-E14/observabilite/outils/extraire-regles.sh) en tire la `spec` (yq, POSIX `sh` pour tourner dans l'image de yq).
   ```
   admin@adm01:~/src/observabilite$ sh outils/extraire-regles.sh && promtool test rules tests/enregistrement-mediagenda.test.yaml
     SUCCESS
   ```
   Le p95 est testé arrondi au millième : le calcul en virgule flottante donne 0,39999…, que `promtool` ne confond pas avec 0,4.
5. **Après synchronisation** : page *Rules*, groupes `mediagenda.enregistrement` et `medidoc.enregistrement`, dernière évaluation en quelques millisecondes, aucune erreur ; `environnement:mediagenda_requetes:taux5m` renvoie une série par environnement.
6. **Limites** ([extrait](fichiers/M21-E14/deploiement-mediagenda/components/supervision/servicemonitor.yaml.extrait)) : `scrape_samples_post_metric_relabeling{job="mediagenda"}` ≈ 350 à 450 par pod ; `sampleLimit: 2000`, `labelValueLengthLimit: 128`, `labelLimit: 30`. Au-delà, la **collecte entière** de la cible échoue : `up == 0`, erreur `sample limit exceeded` sur la page *Targets*, `prometheus_target_scrapes_exceeded_sample_limit_total` qui augmente, alertes du chart `PrometheusScrapeSampleLimitHit` et `TargetDown`. C'est une **protection** (Prometheus ne meurt pas), pas une **solution** : l'application reste aveugle tant que l'équipe n'a pas retiré l'identifiant de patient de ses étiquettes — qui est d'ailleurs une donnée de santé à ne jamais mettre dans une métrique (RGPD).
7. **Tableau d'E05** : les panneaux lisent les séries enregistrées ; sur 7 jours, le chargement passe de plusieurs secondes à moins d'une (la requête lit une série par environnement au lieu de toutes les séries de tous les pods). La version provisionnée arrive en E17.

**Explications**

Une règle d'enregistrement calcule **une fois, à chaque intervalle**, ce que dix tableaux et trois alertes calculeraient chacun de leur côté ; elle produit une série neuve, peu cardinale, que l'on garde et que Thanos sous-échantillonne bien (palier 3). La convention de nommage dit, dans le nom, ce que la série contient : quelles étiquettes restent, quelle métrique, quelles opérations.

**Alternatives**
- *Histogrammes natifs* (stables depuis Prometheus 3.9) : un seul échantillon par histogramme au lieu d'une série par seau ; exige la prise en charge du client Python (`prometheus_client`) et `scrapeNativeHistograms`.
- Enregistrer par `pod` ou par `route` aussi : utile au diagnostic, à mesurer (cardinalité multipliée).
- `enforcedSampleLimit` au niveau du Prometheus : plafond global imposé à tous les moniteurs (palier 3, E30).

**Pièges classiques**
- `sum` avant `rate`, `histogram_quantile` sans `le` dans le `by` : résultats faux ou vides, sans erreur.
- Nommer une règle comme la métrique brute : deux familles de séries homonymes (piège de Lucas, E21).
- Ratio « absent » quand il n'y a pas d'erreur : un tableau vide et une alerte qui ne peut pas se résoudre proprement.
- `promtool test rules` qui échoue sur 0,39999… : comparer à un arrondi.

**En production chez MédiSphère**
Chaque tableau partagé et chaque alerte s'appuient sur des séries enregistrées ; les limites par moniteur font partie du gabarit de supervision de toute nouvelle application ; `promtool tsdb analyze` sur un instantané (palier 4, E44) à chaque revue de capacité.

---

### M21-E15 — Écrire de bonnes alertes

**Solution**

Fichiers : [`alertes-mediagenda.yaml`](fichiers/M21-E15/observabilite/regles/alertes-mediagenda.yaml), [`alertes-socle.yaml`](fichiers/M21-E15/observabilite/regles/alertes-socle.yaml), [`regles/kustomization.yaml`](fichiers/M21-E15/observabilite/regles/kustomization.yaml), tests [MédiAgenda](fichiers/M21-E15/observabilite/tests/alertes-mediagenda.test.yaml) et [socle](fichiers/M21-E15/observabilite/tests/alertes-socle.test.yaml), [`.gitlab-ci.yml`](fichiers/M21-E15/observabilite/.gitlab-ci.yml) (celui d'E07 complété).

1. **Symptômes et causes.** Symptômes (ce que vivent les utilisateurs) : `MediagendaTauxErreurEleve`, `MediagendaLatenceElevee`, `MediagendaIndisponible`. Causes **prévisibles**, qui annoncent un symptôme à venir : `DisqueBientotPlein` (plein avant demain), `CertificatBientotExpire` (renouvellement en échec). Causes « de contexte », en avertissement : `CibleInjoignable` (sur le socle, c'est le premier signal ; source d'inhibition en E16), `MediagendaPodsNonPrets` (n'a de sens que pour expliquer, et pour être inhibée). Seules les **critiques** réveillent (`MediagendaTauxErreurEleve` en prod, `MediagendaIndisponible`).
2. **MédiAgenda** : séries enregistrées d'E14 ; un ratio seul ment à faible trafic, d'où `and on (equipe, environnement) environnement:mediagenda_requetes:taux5m > 0.1` (au moins 6 requêtes par minute). Deux règles du même nom pour le taux d'erreurs : critique en prod au-delà de 5 %, avertissement de 2 à 5 % en prod (`> 0.02 <= 0.05`, filtres enchaînés) et au-delà de 5 % ailleurs : jamais deux alertes pour la même situation. `MediagendaIndisponible` : `sum by (equipe, environnement) (up{…}) == 0 or absent(up{…})`. `absent()` garde les étiquettes d'**égalité** de son sélecteur (`equipe`, `environnement`) : l'alerte se route. `MediagendaPodsNonPrets` porte `node` (jointure `group_left (node)` avec `kube_pod_info`, phase `Running` pour écarter les Jobs terminés).
3. **Socle.** `DisqueBientotPlein` : `predict_linear(...[6h], 24 * 3600) < 0` **et** moins de 25 % libre **et** pas en lecture seule ; systèmes de fichiers virtuels exclus (`tmpfs`, `overlay`, `squashfs`, `nsfs`, `fuse.*`) : sans le seuil de remplissage, une grosse écriture ponctuelle sur un disque vide déclencherait. `CertificatBientotExpire` lit `probe_ssl_earliest_cert_expiry{job="blackbox"}` fédérée depuis le témoin (E12) : 7 jours, alors que step-ca renouvelle à 15 jours — à 7 jours, le renouvellement a échoué depuis une semaine.
4. **`for` et `keep_firing_for`.** `for` retarde le **déclenchement** (la condition doit tenir N minutes) ; `keep_firing_for` retarde la **résolution** (l'alerte reste active N minutes après que la condition est devenue fausse). Un taux d'erreurs qui oscille autour du seuil, sans `keep_firing_for`, ferait « résolu / déclenché » à chaque oscillation, un courriel à chaque fois.
5. **Tests** : pour chaque alerte, un cas qui déclenche (étiquettes et annotations **rendues** attendues) et un qui ne déclenche pas : trafic nocturne avec 33 % d'erreurs mais 0,01 req/s, alerte encore `pending` à 8 minutes, disque presque plein mais stable, cibles qui disparaissent (`absent`). Les séries d'entrée doivent avoir un pas plus court que la fenêtre de recherche (5 minutes) : avec un échantillon toutes les 10 minutes, la série est « absente » une évaluation sur deux et le `for` repart de zéro.
   ```
   admin@adm01:~/src/observabilite$ sh outils/extraire-regles.sh && promtool test rules tests/*.test.yaml
     SUCCESS
   ```
6. **CI** ([`.gitlab-ci.yml`](fichiers/M21-E15/observabilite/.gitlab-ci.yml)) : trois jobs dans l'étape `valider` d'E07 : `regles:extraire` (yq → `build/regles/`, artefact), `regles:verifier` (`promtool check rules`), **`tests-regles`** (`promtool test rules tests/*.test.yaml`). Un test volontairement faux (valeur attendue 0,3 au lieu de 0,4) rend le pipeline de la MR rouge : `FAILED: exp … got …`.
7. **Page *Alerts*** : sept règles `inactive` (vertes), sauf ce qui est vraiment en cours.

**Explications**

Une bonne alerte répond à trois questions dans son courriel : **qui** est touché (étiquettes `equipe`, `environnement`), **à quel point** (`gravite`, valeur dans l'annotation), **que faire** (`runbook_url`). Les valeurs mesurées vont dans les **annotations** : une étiquette qui change à chaque évaluation crée une nouvelle alerte à chaque fois. Les tests `promtool` rejouent des séries synthétiques à travers les vraies règles (enregistrement compris) : ils attrapent un seuil inversé, une agrégation qui perd une étiquette, un modèle d'annotation cassé.

**Alternatives**
- Alertes fondées sur le **budget d'erreur** (palier 3, Pyrra, E26-E27) : plus justes que des seuils fixes pour les symptômes ; les seuils restent pour les causes prévisibles.
- `absent_over_time` au lieu de `absent` pour une série qui ne disparaît que par intermittence.
- Désactiver des règles du chart (`defaultRules.disabled`) qui doublonnent les nôtres : à faire après une semaine d'observation.

**Pièges classiques**
- `irate` dans une alerte : deux derniers points seulement, une valeur qui saute ; l'alerte clignote.
- Fenêtre `[1m]` avec une collecte à 30 s : deux points, parfois un seul ; `rate` vide.
- `absent()` oublié : une application **disparue** ne sonne jamais.
- Annotation `{{ $value }}` dans les étiquettes (voir E21).
- Oublier que `exp_alerts` exige **toutes** les étiquettes, y compris celles de la règle.

**En production chez MédiSphère**
Revue mensuelle des alertes (combien ont sonné, combien ont servi, combien ont été ignorées) dans la politique d'alerte (palier 3, E32) ; toute alerte critique a un runbook relu en exercice ; pas d'alerte sans test en CI.

---

### M21-E16 — Silences, inhibitions et routage par équipe

**Solution**

Fichiers : [configuration d'Alertmanager](fichiers/M21-E16/observabilite/kps/values.yaml.extrait) (clé `alertmanager.config` complète), [`alertmanager/routes-tests.txt`](fichiers/M21-E16/observabilite/alertmanager/routes-tests.txt) (complété).

1. **Arbre** (hérités de la racine : `receiver: plateforme-mail`, `group_by: [alertname, namespace, environnement]`, `group_wait` 30 s, `group_interval` 5 min, `repeat_interval` 4 h) :
   ```
   racine → plateforme-mail
   ├── alertname=Watchdog | InfoInhibitor          → "null"
   ├── gravite=info | severity=info                → "null"
   ├── gravite=critique     → astreinte-mail (repeat 1 h, continue: true)
   ├── severity=critical    → astreinte-mail (repeat 1 h, continue: true)
   ├── equipe=mediagenda    → mediagenda-mail
   │   └── gravite=avertissement  (active_time_intervals: heures-ouvrees)
   ├── equipe=medidoc       → medidoc-mail       (même sous-route)
   ├── equipe=plateforme    → plateforme-mail    (même sous-route)
   ├── severity=warning     → plateforme-mail (active_time_intervals: heures-ouvrees)
   └── severity=critical    → plateforme-mail
   ```
   Une alerte suit la **première** branche qui correspond, sauf `continue: true` : la route d'astreinte, placée avant les routes d'équipe, laisse l'alerte continuer. La dernière route est nécessaire : une alerte critique du chart (sans `equipe`) a trouvé une correspondance (astreinte), donc la racine ne sert plus de repli ; sans elle, la plateforme ne la recevrait pas.
2. **Configuration** ([extrait](fichiers/M21-E16/observabilite/kps/values.yaml.extrait)) : `time_intervals` (section de premier niveau) `heures-ouvrees` = lundi-vendredi, 08:00-19:00, `location: Europe/Paris` (le binaire d'Alertmanager n'embarque pas les fuseaux ; l'image `quay.io/prometheus/alertmanager:v0.34.1` du chart contient `/usr/share/zoneinfo`, vérifié à la relecture) ; inhibitions d'E06 conservées, deux ajoutées. Vérification locale, comme la CI d'E07 :
   ```
   admin@adm01:~/src/observabilite$ mkdir -p /tmp/am && yq '.alertmanager.config' kps/values.yaml > /tmp/am/alertmanager.yaml
   admin@adm01:~/src/observabilite$ yq '.alertmanager.templateFiles["medisphere.tmpl"]' kps/values.yaml > /tmp/am/medisphere.tmpl
   admin@adm01:~/src/observabilite$ yq -i '.templates = ["medisphere.tmpl"]' /tmp/am/alertmanager.yaml
   admin@adm01:~/src/observabilite$ (cd /tmp/am && amtool check-config alertmanager.yaml)
   admin@adm01:~/src/observabilite$ sh outils/tester-routes.sh /tmp/am/alertmanager.yaml alertmanager/routes-tests.txt
   OK  alertname=MediagendaTauxErreurEleve gravite=critique equipe=mediagenda environnement=prod -> astreinte-mail,mediagenda-mail
   …
   ```
   (`amtool check-config` 0.34 ne lit pas le fichier de CA désigné par `smtp_tls_config.ca_file` : le chemin du pod, absent d'`adm01` et de l'image de la CI, ne gêne pas la vérification ; Alertmanager, lui, le lit au premier envoi.)
3. **Essais** ([`routes-tests.txt`](fichiers/M21-E16/observabilite/alertmanager/routes-tests.txt)) : 13 cas. Deux essais d'E07 changent de résultat, et c'est le but : `KubePodCrashLooping severity=critical` va maintenant à `astreinte-mail,plateforme-mail`, `MediagendaIndisponible` à `astreinte-mail,mediagenda-mail` (l'équipe reçoit enfin ses critiques). `amtool config routes test` ne teste que l'arbre, pas les intervalles de temps.
4. **Configuration chargée** : `amtool config show --alertmanager.url=http://alertmanager.apps.par1.medisphere.internal:9093` ou page *Status*.
5. **Inhibition** :
   ```
   admin@adm01:~$ export AM=--alertmanager.url=http://alertmanager.apps.par1.medisphere.internal:9093
   admin@adm01:~$ amtool $AM alert add CibleInjoignable instance=essai-e16:9100 gravite=avertissement equipe=plateforme --end=$(date -d '+15 min' -Iseconds)
   admin@adm01:~$ amtool $AM alert add DisqueBientotPlein instance=essai-e16:9100 gravite=avertissement equipe=plateforme --end=$(date -d '+15 min' -Iseconds)
   admin@adm01:~$ amtool $AM alert query --inhibited instance=essai-e16:9100
   Alertname           Starts At                Summary  State
   DisqueBientotPlein  …                                 suppressed
   ```
   Le piège d'`equal` : si **ni** la source **ni** la cible n'ont l'étiquette `instance`, leurs valeurs (vides) sont « égales » et l'inhibition s'applique à **toutes** les alertes. Ici, la source vient toujours de `up{job="vms"}`, qui a une `instance` : le piège ne peut pas se produire. Pour les pods, les règles du chart n'ont pas d'étiquette `node` : une inhibition `KubeNodeNotReady → KubePod*` avec `equal: [node]` ne s'appliquerait jamais ; d'où `MediagendaPodsNonPrets` qui calcule `node` (E15).
6. **Silence** (CHG-2216) :
   ```
   admin@adm01:~$ amtool $AM silence add node=k8s-w02 --duration=2h --author="<MOI>" --comment="CHG-2216 redémarrage de k8s-w02 (maintenance annoncée)"
   admin@adm01:~$ amtool $AM silence query node=k8s-w02
   admin@adm01:~$ amtool $AM silence update <ID> --duration=3h       # prolonger
   admin@adm01:~$ amtool $AM silence expire <ID>
   ```
   Un silence est **daté, signé, commenté** et expire tout seul ; désactiver une règle ne laisse aucune trace et s'oublie. Il doit être court et précis (un nœud, une durée), sinon il masque aussi la panne **imprévue** qui survient pendant la maintenance. Les silences expirés restent visibles (rétention de 5 jours par défaut) : c'est l'historique des maintenances.

**Explications**

Le routage décide **qui** reçoit ; le regroupement, **combien** de courriels (une notification par groupe, `group_by`) ; l'inhibition, **ce qui est redondant** (une alerte qui en explique d'autres) ; le silence, **ce qui est attendu** (maintenance). Les intervalles de temps rendent une route active ou muette selon l'heure, sans perdre l'alerte : elle est notifiée à l'ouverture de l'intervalle si elle est toujours active.

**Alternatives**
- `mute_time_intervals` (se taire **pendant**) au lieu d'`active_time_intervals` (notifier **seulement pendant**) : équivalent ici, moins lisible.
- `AlertmanagerConfig` (`v1alpha1`) par équipe, dans son espace : autonomie des équipes, mais l'opérateur ajoute un filtre `namespace` à leurs routes (une équipe ne voit que les alertes de son espace) ; à étudier au palier 3 (E29).
- Un récepteur webhook vers un outil d'astreinte (PagerDuty, Grafana OnCall) : hors du lab.

**Pièges classiques**
- Route d'astreinte sans `continue` : l'équipe ne reçoit jamais ses critiques (configuration d'E06).
- Inhibition avec `equal` sur une étiquette absente des deux côtés : tout s'éteint.
- Silence de 30 jours « pour être tranquille » : la prochaine vraie panne passe inaperçue (panne du palier 4).
- Fuseau oublié : `times` sont en UTC par défaut ; 08:00 devient 09:00 ou 10:00 à Paris.

**En production chez MédiSphère**
Les silences se posent depuis le ticket de changement (lien CHG dans le commentaire) ; la politique d'alerte (E32) fixe les horaires et l'escalade ; les essais de routage sont mis à jour à chaque nouvelle équipe ou nouvelle gravité.

---

### M21-E17 — Tableaux de bord *as code*

**Solution**

Fichiers : [`tableaux/mediagenda/mediagenda-apercu.json`](fichiers/M21-E17/observabilite/tableaux/mediagenda/mediagenda-apercu.json), [`tableaux/kustomization.yaml`](fichiers/M21-E17/observabilite/tableaux/kustomization.yaml), [racine](fichiers/M21-E17/observabilite/kustomization.yaml), [valeurs du sidecar](fichiers/M21-E17/observabilite/kps/values.yaml.extrait), [`outils/valider-tableaux.py`](fichiers/M21-E17/observabilite/outils/valider-tableaux.py), [`.gitlab-ci.yml`](fichiers/M21-E17/observabilite/.gitlab-ci.yml), état OpenTofu [`observabilite-grafana/`](fichiers/M21-E17/infra/observabilite-grafana/).

1. **Export et nettoyage.** L'export « pour partage externe » ajoute `__inputs` et remplace les sources par `${DS_PROMETHEUS}` ; l'export simple garde l'`id` interne, la `version`, et l'UID de la source (`prometheus`) dans chaque panneau. On retire `id` (ou `null`), `version`, `__inputs`, on remplace chaque `datasource` par `{"type": "prometheus", "uid": "${datasource}"}` et on ajoute une variable `datasource` (type `datasource`, requête `prometheus`). Grafana 13 active par défaut le **schéma v2** (ressource `dashboard.grafana.app/v2…`) et migre à l'ouverture ; le provisionnement par fichiers et le sidecar travaillent avec le **modèle classique** (`schemaVersion`), que l'on garde dans le dépôt. ⚠️ À vérifier sur ton lab : la forme du fichier exporté par ta version (si l'export propose le v2, choisis le modèle classique).
2. **Kustomize et sidecar** : une ConfigMap par tableau (`configMapGenerator`, `disableNameSuffixHash: true`, étiquette `grafana_dashboard: "1"` déjà attendue par le sidecar du chart, annotation `grafana_folder: MédiAgenda`) ; dans `kps/values.yaml`, `folderAnnotation: grafana_folder`, `provider.foldersFromFilesStructure: true`, `allowUiUpdates: false`. `tableaux` s'ajoute aux ressources de la racine.
3. **Validation** ([script](fichiers/M21-E17/observabilite/outils/valider-tableaux.py)) : JSON valide, titre, `uid` unique de la forme `<dossier>-<nom>` (40 caractères au plus), `id` nul ou absent, pas de `__inputs`, au moins une variable de type `datasource`, et toute référence de source par variable. Sur un tableau volontairement abîmé (UID en double, `id`, source codée en dur), trois erreurs et le code 1. Job `valider-tableaux` dans la CI.
4. **OpenTofu** ([état](fichiers/M21-E17/infra/observabilite-grafana/)). Préalable : les comptes locaux des personnages (`karim.benali@…`, `nadia.roussel@…`, `claire.morel@…`, `julien.petit@…`) créés à la main dans Grafana (rôle Viewer) ; `grafana_team` rattache des comptes existants et l'`apply` échoue sur une adresse qui ne correspond à aucun compte. Ensuite : dossiers à UID fixe (`plateforme`, `mediagenda`, `medidoc`), équipes et membres (comptes du palier 1), `grafana_folder_permission` qui **remplace** les permissions de chaque dossier : l'équipe voit son dossier, `plateforme` voit tout, le rôle Viewer ne voit que `Plateforme`, le compte de service `wb-checks` voit tout (vérifications). État chiffré comme les autres (M05-E27). Fournisseur : `~> 4.50` — le registre d'OpenTofu reflète les versions avec retard (4.50.0 au 22/10/2026) ; la version retenue s'écrit dans `.terraform.lock.hcl`, à committer.
   ```
   admin@adm01:~/src/infra/observabilite-grafana$ export TF_VAR_grafana_jeton="$(cat ~/.config/workbook/grafana-tofu.token)"
   admin@adm01:~/src/infra/observabilite-grafana$ tofu init && tofu plan -out plan.tfplan && tofu apply plan.tfplan
   ```
   Le compte de service `tofu` (rôle Admin) se crée une fois dans Grafana ; son jeton va dans `~/.config/workbook/grafana-tofu.token` (600). Appliqué depuis `adm01` : `runner01` (pipeline de `plateforme/infra`) ne joint pas la Gateway.
5. **Dans Grafana** : le tableau est dans le dossier `MédiAgenda`, avec la mention *Provisioned* ; enregistrer une modification affiche « Cannot save provisioned dashboard » (on peut l'exporter, puis proposer le JSON en MR). Avec le compte de Julien : le dossier `MédiAgenda` seulement (et `Plateforme`, par le rôle Viewer).
6. **Ancien tableau.** Celui d'E05 porte le même UID ; le provisionnement ne prend pas la main sur un tableau existant créé à la main (⚠️ à vérifier sur ton lab : selon la version, il le remplace ou journalise un conflit). On le supprime juste avant la synchronisation (il est dans Git), puis on vérifie qu'il n'en reste qu'un, provisionné.

**Explications**

Trois couches, trois outils : Argo CD déploie Grafana (chart) et les **contenus** (ConfigMaps de tableaux) ; OpenTofu règle **l'organisation** (dossiers, équipes, droits) par l'API de Grafana ; la CI empêche un tableau non portable d'arriver. Le dossier fait le lien : même **titre** côté sidecar (annotation) et côté OpenTofu (UID fixe). ⚠️ À vérifier sur ton lab : que le provisionnement réutilise bien le dossier existant de même titre (c'est le comportement attendu de `foldersFromFilesStructure`), sinon un doublon de dossier apparaît.

**Alternatives**
- **Git Sync** de Grafana 13 (GA) : Grafana lit et écrit un dépôt Git ; modifications à la souris possibles, puis PR. Exige un accès de Grafana à GitLab (flux, jeton) ; à évaluer.
- Opérateur Grafana (`GrafanaDashboard`, `GrafanaFolder`) : tout en objets Kubernetes ; un composant de plus.
- Tableaux générés par du code (Grafana Foundation SDK, Jsonnet/Grafonnet) : homogénéité, au prix d'un outillage.

**Pièges classiques**
- Suffixe de hachage de Kustomize : nom de ConfigMap différent à chaque changement, tableau supprimé puis recréé.
- Gros tableau en *client-side apply* : annotation de 256 Kio dépassée ; `ServerSideApply=true`.
- `grafana_folder_permission` sans le rôle Viewer sur un dossier : les Viewers (et le compte des checks) ne le voient plus.
- UID de source codé en dur : le tableau casse le jour où la source change (Thanos, palier 3).

**En production chez MédiSphère**
Les équipes proposent leurs tableaux par MR dans `tableaux/<equipe>/` ; la plateforme relit la portabilité et le coût des requêtes ; les dossiers et droits suivent les équipes du SSO (M24) au lieu de comptes locaux.

---

### M21-E18 — Analyses Prometheus pour Argo Rollouts

**Solution**

Fichiers : [`ClusterAnalysisTemplate`](fichiers/M21-E18/gitops/analyses/taux-erreur-mediagenda.yaml), correctifs des Rollouts de [recette](fichiers/M21-E18/deploiement/overlays/recette/rollout-analyse.yaml) et de [prod](fichiers/M21-E18/deploiement/overlays/prod/rollout-analyse.yaml), [politique d'entrée de Prometheus](fichiers/M21-E18/observabilite/kps/values.yaml.extrait), [trafic empoisonné](fichiers/M21-E18/essais/trafic-empoisonne.sh).

1. **Lecture.** Une requête qui renvoie un vecteur **vide** fait échouer l'évaluation de `result[0]` : la mesure est en **erreur** (pas en échec) ; `consecutiveErrorLimit` borne ces erreurs. Un centile sans trafic vaut `NaN` : `isNaN(result[0]) || …`. Pour le taux d'erreurs, `(… or vector(0)) / (… > 0)` renvoie 0 sans erreur, mais **vide** sans trafic : un canary qui ne reçoit rien n'est pas déclaré sain par défaut.
2. **Collecte.** E07 a déjà la bonne forme : un Service de collecte `mediagenda-metriques` qui sélectionne tous les pods de l'API par les étiquettes du chart (stables **et** canary, une fois chacun) et la réécriture qui pose `rollouts_pod_template_hash`. Pendant un canary, Argo Rollouts ajoute le hachage au sélecteur de `mediagenda` (stable) et de `mediagenda-canary` ; hors canary, les deux désignent les mêmes pods : un moniteur sur ces Services aurait soit doublé les séries, soit perdu le canary.
   ```
   admin@adm01:~$ kubectl get endpointslices -n mediagenda-recette -l kubernetes.io/service-name=mediagenda-metriques -o wide
   count by (pod, rollouts_pod_template_hash) (up{job="mediagenda", namespace="mediagenda-recette"})   # 1 par pod
   ```
3. **Modèle** ([fichier](fichiers/M21-E18/gitops/analyses/taux-erreur-mediagenda.yaml)) : arguments `namespace`, `hash-canary`, `seuil-erreurs` (0.05), `seuil-p95` (0.5) ; deux métriques (`taux-erreur`, `latence-p95`), `interval: 1m`, `initialDelay: 2m` (le temps que la fenêtre de 2 minutes contienne du trafic canary), `failureLimit: 3`, `consecutiveErrorLimit: 4` ; adresse `http://kps-prometheus.supervision.svc.cluster.local:9090` (Service interne du chart). Requêtes testées dans l'interface de Prometheus avec un hachage réel (`kubectl get rs -n mediagenda-recette -L rollouts-pod-template-hash`).
4. **Politique d'entrée** ([extrait](fichiers/M21-E18/observabilite/kps/values.yaml.extrait)) : `prometheus-entree` (palier 1) gagne une règle `fromEndpoints` sur l'espace `argo-rollouts` et `app.kubernetes.io/name: argo-rollouts`. C'est le **contrôleur** qui interroge Prometheus. Sans elle, les mesures sont en erreur (`context deadline exceeded` dans l'`AnalysisRun` et les journaux du contrôleur).
5. **Rollouts** : analyse en **arrière-plan** (`strategy.canary.analysis`, `startingStep: 1`), `templates: [{templateName: taux-erreur-mediagenda, clusterScope: true}]`, `hash-canary` par `valueFrom.podTemplateHashValue: Latest`, `namespace` écrit en clair dans chaque overlay (prod : `seuil-erreurs: "0.02"`). Les analyses du M20 (fumée, `/pret`) restent. Une analyse d'arrière-plan en échec fait **avorter** la Rollout (poids canary à 0, Rollout `Degraded` jusqu'à la prochaine révision).
6. **Canary réussi**, avec du trafic : sans requête vers le canary, la requête du taux d'erreurs est **vide** à chaque mesure, quatre erreurs consécutives (`consecutiveErrorLimit: 4`) mettent l'`AnalysisRun` en `Error` et la Rollout **avorte** (c'est voulu : « aucune mesure » n'est pas « sain »). D'où le trafic d'essai d'E04 pendant tout le canary (4 req/s, dont ≈ 0,4 vers un canary à 10 %, assez pour une fenêtre de 2 minutes ; ses 404 et 422 ne comptent pas parmi les 5xx).
   ```
   admin@adm01:~$ ressources/E04-trafic/trafic-mediagenda.sh https://mediagenda-recette.apps.par1.medisphere.internal 40 4 &
   admin@adm01:~$ kubectl argo rollouts get rollout mediagenda -n mediagenda-recette --watch
   admin@adm01:~$ kubectl get analysisrun -n mediagenda-recette
   NAME                                   STATUS       AGE
   mediagenda-7c9f6b5d8-12-1              Successful   9m
   ```
7. **Canary échoué volontairement** ([script](fichiers/M21-E18/essais/trafic-empoisonne.sh)) : pendant l'étape à 10 %, une requête sur cinq est `GET /api/v1/creneaux?date=…&praticien=%00`. PostgreSQL refuse les octets nuls dans un texte ; `psycopg` lève `DataError` avant même d'envoyer la requête, l'API ne la traite pas et répond **500** (⚠️ à vérifier sur ton lab : que la Gateway laisse passer `%00` dans la chaîne de requête). Le canary voit ≈ 20 % d'erreurs, trois mesures au-dessus de 5 % : `AnalysisRun` `Failed`, Rollout avortée.
   ```
   admin@adm01:~$ kubectl get analysisrun -n mediagenda-recette <NOM> -o jsonpath='{range .status.metricResults[*]}{.name}{"\t"}{.phase}{"\t"}{.measurements[-1].value}{"\n"}{end}'
   taux-erreur   Failed      [0.19]
   latence-p95   Successful  [0.041]
   ```
   **Le canary n'y est pour rien** : la requête empoisonnée fait échouer **tous** les pods, stables compris. Une analyse qui ne regarde que le canary, contre un seuil absolu, le punit pour une panne commune. Une analyse **comparative** (rapport du taux d'erreurs du canary à celui de la révision stable, `podTemplateHashValue: Stable`) ou une `Experiment` (référence et canary lancés ensemble) n'aurait pas rejeté la version. Remise en état : `kubectl argo rollouts retry rollout mediagenda -n mediagenda-recette` sans trafic empoisonné (ou nouvelle révision par le processus de promotion).

**Explications**

L'analyse transforme une question (« la nouvelle version est-elle au moins aussi bonne ? ») en mesures répétées ; Argo Rollouts compte les succès, échecs, erreurs et résultats non concluants, et arrête le déploiement au-delà des limites. Le hachage de révision est la clé : sans lui, la requête mesure tout le service et un canary à 10 % est noyé dans 90 % de trafic sain.

**Alternatives**
- Comparaison canary/stable (`result[0] <= 1.5 * stable`) : robuste aux pannes communes, plus difficile à régler à faible trafic.
- Analyse en **étape** (`steps: - analysis`) plutôt qu'en arrière-plan : bloque le palier jusqu'au verdict.
- Thanos Query (palier 3) comme adresse : vue des deux réplicas, déduplication ; à faire évoluer avec E24.

**Pièges classiques**
- Politique réseau de `supervision` oubliée : mesures en erreur, puis canary arrêté pour « trop d'erreurs » de mesure.
- Requête sans hachage : le canary est noyé dans le stable.
- `successCondition: result[0] < 0.05` sans traitement du vide : erreur à chaque mesure sans trafic.
- Seuil de latence plus bas que le p95 normal de la recette : chaque canary échoue.

**En production chez MédiSphère**
Analyse comparative en prod, seuils dérivés des SLO (palier 3), une notification d'Argo CD sur chaque avortement (M20-E19), et un trafic synthétique minimal pendant les canaries de nuit pour que l'analyse ait de quoi mesurer.

---

### M21-E19 — Méthodes USE et RED : les tableaux de bord de référence

**Solution (une solution possible)**

Fichiers : [`plateforme-use-noeuds.json`](fichiers/M21-E19/observabilite/tableaux/plateforme/plateforme-use-noeuds.json), [`plateforme-use-ceph.json`](fichiers/M21-E19/observabilite/tableaux/plateforme/plateforme-use-ceph.json), [`mediagenda-red.json`](fichiers/M21-E19/observabilite/tableaux/mediagenda/mediagenda-red.json), [`medidoc-red.json`](fichiers/M21-E19/observabilite/tableaux/medidoc/medidoc-red.json), [`plateforme-red-passerelle.json`](fichiers/M21-E19/observabilite/tableaux/plateforme/plateforme-red-passerelle.json), [`tableaux/kustomization.yaml`](fichiers/M21-E19/observabilite/tableaux/kustomization.yaml), [`tableaux.md`](fichiers/M21-E19/medisphere/docs/observabilite/metriques/tableaux.md).

- **USE des nœuds** : variables `job` (`node-exporter` du chart ou `vms`) et `instance` ; *Utilisation* : CPU non inactif, mémoire non disponible, remplissage ; *Saturation* : charge sur 5 min par cœur, PSI CPU (`node_pressure_cpu_waiting_seconds_total`), PSI mémoire et pages échangées ; *Erreurs* : erreurs réseau, systèmes de fichiers en lecture seule, cibles injoignables. Ligne de synthèse : CPU moyen, mémoire disponible minimale, disque libre minimal, instances injoignables.
- **USE de Ceph** : capacité (grappe et pools), opérations (`ceph_pool_rd`, `ceph_pool_wr`) ; latences des OSD, PG non actifs ou non propres ; `ceph_health_status`, `ceph_health_detail`, OSD `down`/`out`.
- **RED de MédiAgenda et MédiDoc** : séries enregistrées d'E14 (débit, part des 5xx, p95) en synthèse et en courbes, par route pour le débit et la durée, codes par classe ; variable `environnement`.
- **RED de la passerelle** : statistiques de l'Envoy de Cilium (`envoy_http_downstream_rq_total`, `…_rq_xx`, `envoy_cluster_upstream_rq_time_bucket`, `…_downstream_rq_time_bucket`) et paquets refusés d'Hubble. ⚠️ À vérifier sur ton lab : les noms et étiquettes exacts (`envoy_http_conn_manager_prefix`, `envoy_cluster_name`, `envoy_response_code_class`) dans la réponse de `cilium-envoy` (port 9964), après E20. Les métriques HTTP de Hubble (`hubble_http_*`) n'existent que pour les flux à visibilité L7 (politiques L7) : celles de MédiAgenda le sont (M17), pas toutes.
- Chaque tableau : liens vers RB-211/RB-212/RB-213 (RB-210 pour MédiDoc, qui n'a pas encore ses runbooks) et vers le tableau voisin ; les 65 expressions passent l'analyse de Prometheus 3.15 ; ouverture rapide grâce aux séries enregistrées.

**Explications**

USE (Brendan Gregg) s'applique aux **ressources** : pour chacune, combien elle sert (utilisation), combien attend (saturation), combien échoue (erreurs). RED (Tom Wilkie) s'applique aux **services** : combien de requêtes, combien en erreur, combien de temps. En astreinte, on part du RED du service touché, puis on descend vers l'USE des ressources qu'il consomme : deux grilles fixes évitent d'inventer des requêtes sous pression.

**Alternatives**
- Les tableaux fournis par le chart (Kubernetes, nœuds) et par les projets (*mixins*) : complets, mais pas à nos noms ni à nos étiquettes ; on les garde à côté.
- Générer les tableaux par du code (le corrigé les a produits par un petit générateur Python) : une modification de style se fait une fois pour tous.
- *Golden signals* de Google (latence, trafic, erreurs, saturation) : RED + la saturation de l'USE.

**Pièges classiques**
- Confondre utilisation et saturation (un CPU à 100 % qui ne fait attendre personne n'est pas saturé).
- Calculer des centiles à la volée sur 30 jours dans un tableau : lent ; séries enregistrées, puis Thanos.
- Un tableau par personne : il en faut un petit nombre, toujours les mêmes, connus de toute l'astreinte.

**En production chez MédiSphère**
Les tableaux de référence sont la page d'accueil de l'astreinte ; tout nouveau service livre son RED avant la mise en production ; revue des tableaux après chaque post-mortem (ce qui a manqué pour voir).

---

### M21-E20 — Superviser Kubernetes : plan de contrôle, etcd, kubelet, Cilium

**Solution**

Fichiers : [`kubeadm-config.yaml.extrait`](fichiers/M21-E20/k8s/cluster/kubeadm-config.yaml.extrait), [`outils/reconfigurer-plan-controle.sh`](fichiers/M21-E20/k8s/outils/reconfigurer-plan-controle.sh), [valeurs du chart](fichiers/M21-E20/observabilite/kps/values.yaml.extrait), [valeurs de Cilium](fichiers/M21-E20/k8s/composants/cilium/values.yaml.extrait).

1. **Surface** :
   ```
   admin@k8s-cp01:~$ sudo ss -tlnp | grep -E ':(10257|10259|2381) '
   LISTEN 0 4096 127.0.0.1:10257 … kube-controller
   LISTEN 0 4096 127.0.0.1:10259 … kube-scheduler
   LISTEN 0 4096 127.0.0.1:2381  … etcd
   ```
   `:2381` d'etcd est en HTTP **sans authentification** : un tiers qui le joint lit l'état de la base (leader, latences, taille, nombre de clés), pas les données (le client 2379 et les pairs 2380 restent en TLS mutuel). `:10257` et `:10259` délèguent authentification et autorisation à l'API : sans jeton, `/metrics` répond 403 ; seuls `/healthz`, `/readyz`, `/livez` répondent à tous. Compromis retenu : `0.0.0.0` (une seule configuration de cluster), réseau du VLAN 40 seul joignable ; plus fermé : l'adresse du nœud par un *patch* kubeadm propre à chaque nœud.
2. **Configuration et application** : `controllerManager.extraArgs`, `scheduler.extraArgs` (`bind-address: 0.0.0.0`), `etcd.local.extraArgs` (`listen-metrics-urls: http://0.0.0.0:2381`), en **ajoutant** aux listes existantes. Le [script](fichiers/M21-E20/k8s/outils/reconfigurer-plan-controle.sh) généralise celui de M14-E27 : fichier propre au nœud (ClusterConfiguration du dépôt + InitConfiguration avec son adresse), `kubeadm init phase control-plane controller-manager|scheduler` ou `kubeadm init phase etcd local`, copie de retour arrière **hors** de `/etc/kubernetes/manifests/`, attente d'un **nouveau** conteneur puis de son point de santé (`https://127.0.0.1:10257/healthz`, `…:10259/healthz`, `http://127.0.0.1:2381/health`), retour arrière sinon ; quorum etcd vérifié avant et après (`etcdctl endpoint health --cluster` dans le conteneur etcd).
   ```
   admin@adm01:~/src/k8s$ for n in k8s-cp01 k8s-cp02 k8s-cp03; do outils/reconfigurer-plan-controle.sh controller-manager $n && outils/reconfigurer-plan-controle.sh scheduler $n; done
   admin@adm01:~/src/k8s$ outils/reconfigurer-plan-controle.sh etcd k8s-cp01     # vérifie, puis cp02, puis cp03
   admin@adm01:~/src/k8s$ outils/reconfigurer-plan-controle.sh --televerser k8s-cp01
   ```
   Sans `--televerser`, la prochaine montée de version (RB-142) régénérerait les manifestes **sans** ces options.
3. **Chart** : `kubeControllerManager`, `kubeScheduler`, `kubeEtcd` (port 2381, HTTP), `coreDns` activés ; `kubeProxy` reste désactivé. Le chart crée dans `kube-system` des Services sans adresse qui sélectionnent les pods statiques (`component: kube-controller-manager`…) et leurs ServiceMonitor, étiquetés par `commonLabels`. Prometheus s'authentifie par le **jeton d'un compte de service** que le chart range dans un Secret (section `authorization` des ServiceMonitor depuis la version 90), autorisé par la ClusterRole du chart (`nonResourceURLs: /metrics`) ; TLS non vérifié (`insecureSkipVerify`) : certificats de service auto-signés de kubeadm. On le voit dans `kubectl get servicemonitor kps-kube-controller-manager -n supervision -o yaml`.
4. **Cilium** : `serviceMonitor.enabled` et l'étiquette de sélection pour l'agent, l'opérateur, l'Envoy et Hubble ; `trustCRDsExist: true` pour l'agent (le chart vérifie la présence des CRD au rendu, ce que `helm diff` ne sait pas faire). Le diff ne montre que quatre ServiceMonitor : la ConfigMap `cilium-config` ne change pas, aucun redémarrage des agents.
   ```
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=cilium diff
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=cilium apply
   ```
   Jobs : `cilium-agent` (un par nœud), `cilium-operator`, `cilium-envoy`, `hubble-metrics` (nom des Services, faute de `jobLabel`).
5. **Séries** : `etcd_server_has_leader` (3 × 1), `histogram_quantile(0.99, sum by (le, instance) (rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m])))` (sous 10 ms sur NVMe), `workqueue_depth{job="kube-controller-manager"}`, `scheduler_pending_pods`, `rate(coredns_dns_requests_total[5m])`, `rate(cilium_drop_count_total[5m])`, `rate(hubble_drop_total[5m])` ; les alertes du chart `etcdMembersDown`, `KubeSchedulerDown`, `KubeControllerManagerDown` quittent l'état « sans données ».

**Explications**

kubeadm fait écouter ces composants sur la boucle locale par prudence ; la supervision exige de les ouvrir au réseau des nœuds, en connaissant ce qu'on expose. La reconfiguration d'un cluster kubeadm existant passe par les phases de `kubeadm init` sur chaque nœud **et** par le ConfigMap `kubeadm-config` (source des prochaines montées de version) : l'oubli de l'un ou de l'autre est une panne différée.

**Alternatives**
- Laisser `127.0.0.1` et collecter par un agent sur chaque nœud de contrôle (Alloy, M22) qui pousse vers Prometheus : rien d'ouvert, un composant de plus.
- etcd en `https` sur l'URL de métriques avec certificats clients : plus fermé, à gérer (rotation).
- Grappe de supervision séparée pour le plan de contrôle : hors de portée du lab.

**Pièges classiques**
- `extraArgs` au format `v1beta3` (dictionnaire) dans un fichier `v1beta4` (liste) : `kubeadm config validate` refuse.
- Régénérer etcd sur deux nœuds à la fois : perte de quorum.
- Oublier le téléversement : options perdues à la prochaine montée de version.
- `kubeEtcd` en `https` alors qu'etcd sert ses métriques en HTTP sur 2381 : cible en erreur TLS.

**En production chez MédiSphère**
Alertes du chart sur etcd (latence d'écriture du journal, changements de leader) relues et routées à la plateforme ; adresse d'écoute par nœud (*patches*) au palier production ; supervision du plan de contrôle incluse dans le gabarit de tout nouveau cluster (F1).

---

### M21-E21 — Revue : les règles d'alerte du stagiaire

**Réponses**

Fichiers : version corrigée [`alertes-lucas.yaml`](fichiers/M21-E21/observabilite/regles/alertes-lucas.yaml), [`enregistrement-lucas.yaml`](fichiers/M21-E21/observabilite/regles/enregistrement-lucas.yaml), [tests](fichiers/M21-E21/observabilite/tests/alertes-lucas.test.yaml) (branche `revue-lucas`).

| # | Où | Défaut | Conséquence | Correction |
|---|---|---|---|---|
| 1 | `ApiErreurs` | `irate` dans une alerte | deux derniers points : valeur qui saute, alerte qui clignote | `rate` sur 5 min, ou mieux, la série enregistrée d'E14 |
| 2 | `ApiErreurs` | fenêtre `[1m]` avec une collecte à 30 s | deux points, parfois un : résultat vide par moments | au moins quatre intervalles (2 min), 5 min ici |
| 3 | `ApiErreurs` | pas de `for` | une seule évaluation au-dessus du seuil réveille quelqu'un | `for: 10m` (et `keep_firing_for`) |
| 4 | `ApiErreurs` | seuil `> 5` sur un **ratio** (0 à 1) | l'alerte ne peut **jamais** sonner | `> 0.05` |
| 5 | `ApiErreurs` | `sum` sans `by` | dev, recette et prod mélangés ; plus d'étiquette `environnement`, routage par défaut | `sum by (equipe, environnement)` |
| 6 | `ApiErreurs` | `valeur: "{{ $value }}"` en **étiquette** | nouvelle alerte à chaque évaluation : un courriel par évaluation, des séries `ALERTS` sans fin | la valeur dans une annotation |
| 7 | `ApiLente` | `histogram_quantile` sans `le` dans le `by` | résultat vide : l'alerte ne sonne jamais | `sum by (le, …)` |
| 8 | toutes | `severity: page`, pas de `gravite` ni d'`equipe` | routage par défaut à la plateforme, jamais à l'astreinte ni à l'équipe (E16) | `gravite`, `equipe` |
| 9 | `PodRedemarre` | compteur comparé à 0 | sonne **pour toujours** dès le premier redémarrage ; cause, pas symptôme, réveille la nuit | `increase(...[1h]) > 3`, avertissement |
| 10 | `MediagendaDown` | pas d'`absent()` | si les cibles disparaissent, rien ne sonne ; doublon de `MediagendaIndisponible` | supprimée (E15 couvre) |
| 11 | `MemoireQuiBaisse` | `rate()` sur une **jauge** | chaque baisse vue comme une remise à zéro de compteur : valeurs absurdes | `MemAvailable / MemTotal < 0.10` |
| 12 | `DisquePresquePlein` | seuil absolu 1 Go, aucun filtre de `fstype` ni de `job` | `tmpfs` et `overlay` sonnent en permanence, un disque de 2 To à 1 Go libre aussi | supprimée (`DisqueBientotPlein`, prédiction) |
| 13 | `CpuEleve` | une alerte **par cœur** (`by (instance, cpu)`), CPU occupé ≠ saturé, réveille | 8 courriels pour un nœud, la nuit, pour rien | file d'attente par cœur (`node_load15` / cœurs), avertissement |
| 14 | annotations | `runbook_url` vers le wiki d'InfoGér (mort), absentes ailleurs ; `summary` au lieu de `resume`/`description` | personne ne sait quoi faire | runbooks RB-21x |
| 15 | enregistrement | règle nommée comme la métrique brute, somme de **compteurs** avant `rate` | deux familles homonymes, remises à zéro masquées | supprimée |
| 16 | enregistrement | `rate(...[30s])`, nom hors convention, groupe à 5 s | une seule collecte dans la fenêtre : vide ; calcul six fois par collecte | `namespace_pod:mediagenda_requetes_5xx:taux5m`, groupe à 30 s |
| 17 | MR | « `promtool check rules` passe » | la syntaxe ne dit rien du sens : défauts 4, 7, 9 passent | tests `promtool test rules` |

**Erreurs** (la règle ne fait pas ce qu'elle annonce) : 4, 6, 7, 9, 11, 15, 16. **Choix à discuter** : 1, 2, 3, 5 (fenêtres et seuils), 12, 13 (alertes de causes), 8, 14 (conventions).

**Version corrigée.** Supprimé ce qui doublonne E15 (`ApiErreurs`, `ApiLente`, `MediagendaDown`, `DisquePresquePlein`) ; gardé, corrigé et en **avertissement** ce qui manquait (`MediagendaRedemarragesFrequents`, `MemoireBientotEpuisee`, `CpuSature`) et une règle d'enregistrement par pod ; un test par alerte, dont celui qui prouve qu'un **ancien** redémarrage ne sonne plus. Pipeline de la branche vert (`tests-regles`).
```
admin@adm01:~/src/observabilite$ git switch -c revue-lucas && git add regles/alertes-lucas.yaml regles/enregistrement-lucas.yaml tests/alertes-lucas.test.yaml regles/kustomization.yaml
admin@adm01:~/src/observabilite$ git commit -m "fix(regles): revue de la MR !14 (PLAT-2221)" && git push -u origin revue-lucas
```

**Commentaire à Lucas** (extrait) : « Merci, il y a de vraies bonnes idées (les redémarrages, la mémoire). Trois points d'abord : (1) `ApiErreurs` ne peut jamais sonner (seuil 5 sur un ratio) et sonnerait à chaque évaluation si on le corrigeait (valeur en étiquette) ; (2) `PodRedemarre` sonnerait pour toujours après le premier redémarrage ; (3) sans `gravite` ni `equipe`, aucune ne partirait au bon endroit. J'ai poussé une proposition avec des tests dans `revue-lucas` : regardons-la ensemble demain. »

**Pièges classiques** : s'arrêter à « ça passe `promtool check rules` » ; corriger les fautes sans supprimer les doublons ; une revue qui ne propose rien de testable.

---

### M21-E22 — Runbook : répondre à une alerte

**Proposition** : [RB-210](fichiers/M21-E22/medisphere/docs/observabilite/metriques/runbooks/RB-210-modele-runbook-alerte.md) (modèle), [RB-211](fichiers/M21-E22/medisphere/docs/observabilite/metriques/runbooks/RB-211-mediagenda-erreurs.md), [RB-212](fichiers/M21-E22/medisphere/docs/observabilite/metriques/runbooks/RB-212-mediagenda-latence.md), [RB-213](fichiers/M21-E22/medisphere/docs/observabilite/metriques/runbooks/RB-213-disque-plein.md).

**Grille d'auto-évaluation**
- [ ] Le modèle fixe les sections dans l'ordre, les règles d'écriture (public, longueur, invites, aucun secret, avertissements) et ce qu'un runbook **ne** contient **pas**.
- [ ] Chaque runbook commence par la signification et l'impact, en mots simples ; seuil et durée sont cités.
- [ ] Les premières vérifications répondent dans l'ordre à : est-ce réel (vu de l'extérieur) ? depuis quand ? quelle étendue ? qu'est-ce qui a changé ?
- [ ] Chaque requête est copiable, chaque commande dit où la lancer ; les liens de tableaux portent leurs variables.
- [ ] Un tableau « ce que tu observes → cause probable → action », issu des cas réels (E18, E23), pas d'une liste théorique.
- [ ] Les actions restent dans le code (MR, Argo CD) sauf bris de glace explicite ; rien de destructif sans avertissement (RB-213 : jamais de suppression d'un fichier non identifié ; agrandir est réversible).
- [ ] L'escalade nomme les personnes (Julien Petit, Karim Benali, astreinte) et le seuil d'un incident `INC-48xx`.
- [ ] Le retour à la normale se constate par une requête précise, et le runbook dit quoi améliorer après.
- [ ] Les `runbook_url` des alertes d'E15 pointent vers ces fichiers (le check d'E21 le vérifie pour la branche de Lucas).

**Pièges classiques** : un runbook qui raconte l'architecture au lieu de dire quoi faire ; des commandes qui supposent un contexte (`kubectl` sans `-n`) ; des « il faudrait » ; un runbook jamais rejoué (le palier 4 le mettra à l'épreuve).

---

### M21-E23 — Diagnostiquer une saturation par les métriques

**Solution**

Fichiers : [Job de charge](fichiers/M21-E23/essais/charge-oha.yaml) (à partir du [squelette](../ressources/E23-charge/charge-oha.yaml)), [journal type](fichiers/M21-E23/medisphere/docs/kubernetes/journal/2026-10-23-INC-4823-saturation-recette.md), [`alertes-mediagenda.yaml`](fichiers/M21-E23/observabilite/regles/alertes-mediagenda.yaml) (groupe `mediagenda.saturation` ajouté) et son [test](fichiers/M21-E23/observabilite/tests/saturation-mediagenda.test.yaml).

1. **Base** : `PodMonitor` `mediagenda-db` d'E07 (`job="mediagenda-db"`) ; connexions : `cnpg_backends_total` (par base, utilisateur, état), maximum : `cnpg_pg_settings_setting{name="max_connections"}` (⚠️ à vérifier sur ton lab : noms exposés par ta version de CloudNativePG, `curl` sur le port `metrics` d'une instance).
2. **Référence** au calme (10 min) : débit, p95, 5xx (séries d'E14), CPU par pod et **sa limite** :
   ```
   admin@adm01:~$ kubectl get pod -n mediagenda-recette -l app.kubernetes.io/component=api -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[?(@.name=="api")].resources}{"\n"}{end}'
   ```
   Le chart ne pose pas de limite de CPU ; le **LimitRange** `limites-defaut` de l'espace (M14-E10) en injecte une (500m) : c'est elle qui bridera.
3. **Charge** ([Job](fichiers/M21-E23/essais/charge-oha.yaml)) : l'image `oha` n'a pas de shell (point d'entrée `/bin/oha`, utilisateur 65535) ; trois paliers enchaînés par des **conteneurs d'initialisation** (chacun attend la fin du précédent), bornés par `-z` (durée), `-q` (débit) et `activeDeadlineSeconds: 900` ; `--cacert` sur la racine MédiSphère montée depuis une ConfigMap. Le dernier palier lit `/api/v1/rendez-vous` (base, sans cache).
   ```
   admin@adm01:~$ kubectl create configmap racine-medisphere -n wb-essais --from-file=ca.crt=/usr/local/share/ca-certificates/medisphere-root-ca.crt
   admin@adm01:~$ kubectl apply -f ~/m21/e23/charge-oha.yaml && kubectl logs -n wb-essais job/charge-oha -c palier-20 -f
   ```
4. **Mesures** (voir le [journal type](fichiers/M21-E23/medisphere/docs/kubernetes/journal/2026-10-23-INC-4823-saturation-recette.md)) :
   ```
   sum by (pod) (rate(container_cpu_cfs_throttled_periods_total{namespace="mediagenda-recette", container="api"}[2m]))
     / sum by (pod) (rate(container_cpu_cfs_periods_total{namespace="mediagenda-recette", container="api"}[2m]))
   sum by (pod) (cnpg_backends_total{namespace="mediagenda-recette"})
   sum by (resultat) (rate(mediagenda_cache_total{environnement="recette"}[2m]))
   ```
   On raisonne en **périodes** : `container_cpu_cfs_throttled_seconds_total` n'existe pas dans Prometheus, le chart la jette par défaut (`kubelet.serviceMonitor.cAdvisorMetricRelabelings`, avec `container_cpu_load_average_10s` et les temps système et utilisateur) ; la retirer de cette liste coûterait une série par conteneur pour une information que le rapport des périodes donne déjà.

   Ce qui sature d'abord, dans l'essai type : le **CPU bridé** de l'API (plus de la moitié des périodes de 100 ms dès 50 req/s), alors que l'utilisation « moyenne » plafonne à la limite ; puis, au palier sur la base, le réservoir de **10 connexions** par processus (`ConnectionPool(max_size=10)` dans le code) : conséquence, pas cause.
5. **Vérification de l'hypothèse** : même palier contre une copie de MédiAgenda dans `wb-essais` avec une limite plus haute (un seul paramètre changé) : p95 revenu à la normale, plus de bridage. L'écart entre le p95 d'`oha` et celui de l'application dit que l'attente se passe **avant** le traitement (file d'attente du processus, passerelle).
6. **Journal** : chronologie, tableau des mesures par palier, hypothèses testées, cause, recommandations chiffrées (ressources explicites de l'API dans `mediagenda/deploiement`, réplicas × 10 connexions sous `max_connections`, HPA au M28).
7. **Règle et alerte** : `namespace_pod:mediagenda_cpu_bride:ratio5m`, et `MediagendaCpuBride` = plus de 25 % de périodes bridées **et** p95 au-dessus de 300 ms dans le même environnement (jointure `label_replace` de `environnement` vers `namespace`), 15 minutes, avertissement. Seul, le bridage n'est pas grave (pointe brève) ; avec la latence, il explique et dit quoi faire. Le chart a déjà `CPUThrottlingHigh` (sans lien avec la latence, routé à la plateforme) : la nôtre est pour l'équipe.
8. **Nettoyage** : `kubectl delete job -n wb-essais charge-oha` (ou `ttlSecondsAfterFinished`), copie d'essai supprimée.

**Explications**

Une limite de CPU est un **quota** par période (100 ms) : un processus qui l'a consommé en 30 ms attend 70 ms, quelle que soit la charge du nœud. L'utilisation moyenne ne le montre pas ; la part de périodes bridées, si. Diagnostiquer, c'est **mesurer, supposer, vérifier en changeant une seule chose**, et écrire assez pour que la personne suivante n'ait pas à recommencer.

**Alternatives**
- Pas de limite de CPU, requête seule (les pods prennent le CPU libre du nœud) : débattu dans ADR-0140 ; à mesurer au M28 (VPA).
- `k6` ou `vegeta` pour générer la charge (scénarios, seuils) ; `oha` suffit pour des paliers simples.
- Profilage de l'API (Pyroscope, M23) pour savoir **où** le CPU part.

**Pièges classiques**
- Charger la **prod** « pour voir » ; une charge sans borne de durée ni de débit.
- Lire `container_cpu_usage_seconds_total` seul : « l'API n'utilise que 0,5 cœur », donc tout va bien.
- Conclure sur un seul essai, sans faire varier un paramètre.
- Multiplier les réplicas sans regarder `max_connections` : la base sature à son tour.

**En production chez MédiSphère**
Tests de charge planifiés avant chaque version majeure (M29), en recette, avec les partenaires prévenus ; ressources explicites dans tous les overlays ; `MediagendaCpuBride` et les séries de la base au tableau RED de l'équipe.
