# Module 21 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. En supervision, « j'ai redémarré Prometheus et ça remarche » est presque toujours faux : la configuration fautive est dans Git, Argo CD la remet, et le redémarrage efface la tête (donc la preuve) ou masque une panne intermittente.

Les scripts d'injection sont dans `corrige/pannes/` : `_m21-commun.sh` contient les fonctions partagées (requêtes vers la vue globale et Alertmanager, lecture des sélecteurs de l'objet Prometheus, MR de Lucas par l'API de GitLab avec fusion automatique et transformation inverse à l'annulation, attente des synchronisations d'Argo CD, exécution sur `mon01` et les VMs, témoins de `wb-pannes`). Les fichiers modifiés sur une VM sont journalisés dans `/var/lib/workbook/pannes.log` de la VM ; les objets Kubernetes d'origine et l'état des pannes sont gardés sur `adm01` dans `~/.local/state/workbook/M21-EXX/`.

> **Remarque sur l'historique Git** : les MR de panne sont ouvertes au nom de `lucas.martin` (jeton d'emprunt d'identité créé par ton jeton d'administration, puis révoqué) et **fusionnées avec ton jeton** : dans GitLab, c'est toi qui apparais comme celui qui a fusionné. En production, ce serait Karim ou Julien, et c'est précisément la question du post-mortem : pourquoi la relecture n'a-t-elle rien vu, et qu'est-ce que la CI aurait pu voir ?

Les sorties reproduites sont **représentatives** : noms de pods, adresses, horodatages et formulations exactes varient selon ton lab et les versions (Prometheus 3.15 dans le cluster et 3.13 LTS sur `mon01`, Alertmanager 0.34, prometheus-operator 0.94, Thanos 0.42, Grafana 13.2, Cilium 1.20).

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) :
- L'ensemble des scripts de panne a été vérifié par `shellcheck` et `bash -n`, leurs transformations `yq`/`jq` sur des fichiers d'exemple conformes aux corrigés de M21-E02 à E17, l'application témoin exécutée localement (sortie validée par `promtool check metrics`) et ses manifestes validés par `kubeconform` avec les schémas des CRD ; **aucune injection n'a été jouée sur un lab réel**. Les points les plus sensibles : l'emprunt d'identité de `lucas.martin` (ses droits sur les deux dépôts : à défaut, la branche est créée avec ton jeton et seul le commit porte Lucas comme auteur), la fusion automatique (`auto_merge` / `merge_when_pipeline_succeeds` de l'API de GitLab 19), le déclenchement d'une synchronisation par le champ `operation` d'une Application sans synchronisation automatique.
- E35 v3 : comportement d'une CiliumNetworkPolicy qui ne contient que `ingressDeny` avec `enableDefaultDeny: {ingress: false}` (attendu : seul le trafic venant de `supervision` est refusé, le reste passe).
- E35 v4 : node_exporter (exporter-toolkit) relit certificat et clé à chaque connexion (documenté) ; la minuterie de renouvellement step-ca de ta VM peut, selon ton rôle, tenter de renouveler le certificat autosigné et échouer bruyamment : c'est un indice de plus.
- E36 : un changement de configuration d'Alertmanager passe par la régénération du Secret par l'opérateur puis par le rechargement par le *config-reloader* (une à deux minutes).
- E37 v3 : Grafana met à jour l'UID d'une source provisionnée retrouvée par son nom (code de provisionnement de Grafana) ; si ta version crée une seconde source à la place, le symptôme est le même côté tableaux.
- E39 v1 : comportement du Store Gateway 0.42 quand la synchronisation initiale échoue (attendu : pod non prêt, en redémarrage, ou présent mais en erreur dans `/api/v1/stores`).
- E39 v2 : l'opérateur retire le paramètre `--objstore.config` du sidecar quand `objectStorageConfig` disparaît de l'objet Prometheus (les sidecars ne servent plus que l'API Store), et `disableCompaction: true` (posé par la même MR) garde des blocs de 2 h pendant la panne (lu dans le code de l'opérateur 0.94.1, `compactionModeFor`).
- E42 v1 : le contenu exact de la page `/config` de blackbox_exporter 0.29.
- E44 : `promtool tsdb dump` 3.15 réclame un dossier `wal/` dans le répertoire analysé (vérifié sur un instantané local) ; la 3.13 du témoin, à vérifier.

---

### M21-E35 — Panne : une cible a disparu

**Démarche de diagnostic**

*Symptômes* : un tableau vide pour un environnement ou une machine ; aucune alerte.

*Hypothèses* : la cible n'est plus **découverte** (ServiceMonitor non retenu, port nommé qui ne correspond plus, Service ou points de terminaison changés, fichier de cibles) ; la cible est découverte mais la collecte **échoue** (réseau, TLS, authentification, délai) ; la collecte réussit mais les séries sont **jetées** (relabeling) ; l'affichage est faux (M21-E37).

**Étape 1 — Disparue ou en échec ?**

```
admin@adm01:~$ P=http://prometheus.apps.par1.medisphere.internal:9090
admin@adm01:~$ curl -s $P/api/v1/query --data-urlencode 'query=count by (namespace) (up{job="mediagenda"})' | jq -c '.data.result[] | [.metric.namespace, .value[1]]'
["mediagenda-prod","2"]
admin@adm01:~$ curl -s $P/api/v1/query --data-urlencode 'query=count by (namespace) (up{job="mediagenda"} offset 1h)' | jq -c '.data.result[] | [.metric.namespace, .value[1]]'
["mediagenda-dev","1"]
["mediagenda-prod","2"]
["mediagenda-recette","2"]
```

Dev et recette ont **disparu** (plus de série `up`), prod est intacte : la cause est commune aux environnements synchronisés automatiquement (prod est synchronisée à la main, M20). Si les séries existent avec `up == 0`, c'est une cible **en échec** :

```
admin@adm01:~$ curl -s $P/api/v1/targets | jq -r '.data.activeTargets[] | select(.health != "up") | "\(.labels.job) \(.scrapeUrl) \(.lastError)"'
mediagenda http://10.240.1.37:8000/metrics Get "http://10.240.1.37:8000/metrics": context deadline exceeded
```

**Variante 1 — port du ServiceMonitor renommé.**

```
admin@adm01:~$ kubectl -n supervision port-forward pod/prometheus-kps-0 9091:9090 &
admin@adm01:~$ curl -s localhost:9091/api/v1/targets?state=dropped | jq '[.data.droppedTargets[] | select(.discoveredLabels.__meta_kubernetes_namespace == "mediagenda-recette")] | length'
4
admin@adm01:~$ kubectl -n mediagenda-recette get servicemonitor mediagenda -o jsonpath='{.spec.endpoints[*].port}{"\n"}'
metriques
admin@adm01:~$ kubectl -n mediagenda-recette get service mediagenda-metriques -o jsonpath='{.spec.ports[*].name}{"\n"}'
http
```

La page *Service Discovery* montre les cibles du ServiceMonitor **découvertes puis écartées** : l'opérateur génère un `relabel_configs` qui ne garde que le port nommé `metriques`, que le Service n'a pas. `git log -p components/supervision/servicemonitor.yaml` dans `mediagenda/deploiement` montre le commit de Lucas (« port aligné sur le chart », marqueur `M21-E35`) : il a confondu le nom du port du conteneur dans le chart et celui du Service de collecte. Correctif : MR qui remet `port: http` (ou qui renomme les deux de façon cohérente) ; Argo CD synchronise dev et recette ; prod n'a jamais été touchée.

**Variante 2 — étiquette de sélection « normalisée ».**

```
admin@adm01:~$ kubectl -n supervision get prometheus kps -o jsonpath='{.spec.serviceMonitorSelector}{"\n"}'
{"matchLabels":{"medisphere.internal/supervision":"oui"}}
admin@adm01:~$ kubectl -n mediagenda-recette get servicemonitor mediagenda --show-labels
NAME         AGE   LABELS
mediagenda   41d   app.kubernetes.io/instance=mediagenda-recette,medisphere.internal/supervision=true
```

`true` n'est pas `oui` : l'opérateur ignore le ServiceMonitor, qui n'apparaît **nulle part** dans Prometheus (ni découvert, ni écarté). C'est la panne la plus silencieuse : aucun message, aucune erreur. Correctif : MR qui remet `"oui"`. Prévention : une règle de CI (ou une ValidatingAdmissionPolicy sur les espaces `mediagenda-*`) qui exige la valeur exacte ; et l'alerte de disparition ci-dessous.

**Variante 3 — politique réseau qui refuse la collecte.**

```
admin@adm01:~$ hubble observe --namespace mediagenda-recette --verdict DROPPED --last 20
Oct 27 09:12:04.511: supervision/prometheus-kps-1:51234 (ID:48211) <> mediagenda-recette/mediagenda-6c9…:8000 (ID:30117) policy-verdict:L3-Only INGRESS DENIED (TCP Flags: SYN)
admin@adm01:~$ kubectl get ciliumnetworkpolicies -A | grep mediagenda-recette
mediagenda-recette   durcissement-recette   …
admin@adm01:~$ kubectl -n mediagenda-recette get cnp durcissement-recette -o yaml | yq '.metadata.annotations, .spec'
```

Une politique posée à la main (annotation `medisphere.internal/auteur: lucas.martin`, ticket `SEC-2235`), hors de tout dépôt : Argo CD ne la gère pas et ne la signale pas (elle n'appartient à aucune Application). `ingressDeny` l'emporte sur toute autorisation, y compris celle de M21-E07 (`collecte-prometheus`). Correctif : retirer la politique (`kubectl delete cnp`), puis traiter l'intention de Sophie **par le code** : les politiques réseau des espaces applicatifs sont celles de la plateforme (`plateforme/k8s`, matrice `docs/kubernetes/reseau/matrice-flux-cluster.md`), relues, et elles autorisent explicitement `supervision` sur le port de collecte. Prévention : une alerte `up == 0` aurait sonné en 5 minutes ; l'AppProject des applications interdit déjà les NetworkPolicy aux équipes (M20-E07) mais pas aux humains munis de `cluster-admin`.

**Variante 4 — certificat de node_exporter remplacé.**

```
admin@adm01:~$ curl -s $P/api/v1/targets | jq -r '.data.activeTargets[] | select(.labels.job == "vms" and .health != "up") | "\(.labels.instance) \(.lastError)"'
nbx01 Get "https://nbx01.par1.medisphere.internal:9100/metrics": tls: failed to verify certificate: x509: certificate signed by unknown authority
admin@adm01:~$ openssl s_client -connect nbx01.par1.medisphere.internal:9100 -CAfile /usr/local/share/ca-certificates/medisphere-root-ca.crt </dev/null 2>/dev/null | openssl x509 -noout -issuer -subject -dates
issuer=CN=nbx01.par1.medisphere.internal
subject=CN=nbx01.par1.medisphere.internal
notBefore=Oct 27 08:51:12 2026 GMT
```

Certificat **autosigné** (émetteur = sujet), créé aujourd'hui. Sur la VM : `sudo journalctl -u 'cert-renewer*' --since today` montre le renouvellement en échec, `ls -l /etc/node_exporter/tls/` la date de modification ; `/var/lib/workbook/pannes.log` contient l'aveu (à lire **après** avoir trouvé). Correctif : rejouer le rôle `node_exporter` (`--check --diff` d'abord : il signale le certificat) qui redemande un certificat à step-ca ; node_exporter le relit à la connexion suivante. Prévention : alerte sur l'expiration et sur l'émetteur des certificats d'exportateurs (`probe_ssl_earliest_cert_expiry` depuis `mon01`, ou le collecteur `textfile` du rôle).

**Variante 5 — pare-feu local de la VM.**

```
admin@adm01:~$ ssh nbx01 'sudo nft list ruleset | grep -B3 -A1 9100'
table inet durcissement_exportateurs {
	chain entree {
		type filter hook input priority filter - 10; policy accept;
		ip saddr { 10.10.40.0/24, 10.240.0.0/16 } tcp dport 9100 counter packets 412 bytes 24720 drop comment "PLAT-2235 exportateurs : MGMT seulement (Lucas)"
```

Le compteur grimpe à chaque collecte : c'est la preuve. Depuis `adm01` (MGMT) le port répond, depuis un nœud non : un test depuis le **même endroit que Prometheus** est indispensable. Correctif : retirer la table (`sudo nft delete table inet durcissement_exportateurs`) et vérifier que le rôle du pare-feu local (M21-E08) décrit bien le flux `K8S_TRAV → 9100` ; le prochain passage d'Ansible ne retire pas une table qu'il ne connaît pas si le rôle n'écrase pas tout le jeu de règles (`flush ruleset`) : c'est une question à se poser pour le rôle.

**Clôture commune** : cibles revenues, trou visible dans les courbes (il ne se comble pas : les échantillons non collectés n'existent pas), `lab/bin/check 21 35`, puis `lab/bin/break 21 35 --annuler`.

**Ce qui a sonné, ce qui manquait.** Pour les variantes 4 et 5, `CibleInjoignable` (M21-E15, `up{job="vms"} == 0` pendant 5 min) **a sonné** : en `avertissement`, donc vers `plateforme@` (et pas la nuit si M21-E16 met les avertissements en sourdine hors heures ouvrées). Vérifie-le dans Mailpit : l'alerte existait, elle n'allait pas à la personne qui a ouvert le ticket ; c'est une question de politique (M21-E32), pas de règle. Pour les variantes 1 à 3, rien ne pouvait sonner : aucune alerte `up == 0` sur les applications, et **aucune** alerte de disparition. Ajouts : [`regles/collecte.yaml`](fichiers/M21-E35/observabilite/regles/collecte.yaml) et ses tests [`tests/collecte.test.yaml`](fichiers/M21-E35/observabilite/tests/collecte.test.yaml) : `ApplicationCibleEnEchec` (`up == 0` pendant 5 min sur les jobs des applications) et `CibleDisparue` (`absent_over_time(up{job="…"}[10m])`, une expression par job attendu : MédiAgenda, MédiDoc, VMs, node-exporter, fédération de `mon01`). Le runbook : [`RB-217-collecte-et-regles.md`](fichiers/M21-E35/medisphere/docs/observabilite/metriques/runbooks/RB-217-collecte-et-regles.md) (sections des pannes E35, E37 et E41).

**Explications**

Une cible n'existe pour Prometheus que si la **découverte** la produit puis que le **relabeling** la garde : l'opérateur traduit chaque ServiceMonitor retenu en un `scrape_config` qui découvre les points de terminaison de l'espace et ne garde que ceux du bon Service et du bon port nommé. Tout ce qui ne correspond pas devient une cible « écartée », visible seulement sur *Service Discovery* d'un Prometheus (Thanos Query n'expose que les cibles actives). Une fois découverte, la cible a une série `up` à chaque collecte (1 ou 0) et un `lastError`. Quand elle disparaît, Prometheus écrit un **marqueur de péremption** : la série `up` cesse d'exister pour les requêtes, et `up == 0` ne peut plus rien détecter. D'où la paire d'alertes : `up == 0` pour l'échec, `absent_over_time` (ou une comparaison du nombre de cibles) pour la disparition.

**Alternatives**

`absent()` sur une liste de jobs codée en dur contre `count(up{job=…}) < N` : le premier ne détecte que la disparition totale, le second une perte partielle mais exige de tenir N à jour ; kube-prometheus-stack propose `TargetDown` (pourcentage de cibles en échec par job), utile mais aveugle à la disparition. Pour les VMs, comparer la liste de NetBox (source de la ScrapeConfig) et les cibles présentes, dans le playbook `supervision-cibles.yml` (M21-E08).

**Pièges classiques**
- Chercher une cible disparue dans la page *Targets* de la vue globale : elle n'y est pas, et Thanos Query ne montre pas les cibles écartées.
- Tester la cible depuis `adm01` : le chemin réseau (MGMT) n'est pas celui de Prometheus (pods, VLAN 40) ; une politique ou un pare-feu qui ne vise que ce dernier passe inaperçu.
- Corriger le ServiceMonitor avec `kubectl edit` : Argo CD remet la version de Git en quelques secondes (et la MR fautive reste).
- Supprimer la politique réseau sans traiter la demande de sécurité qui l'a motivée.

**En production chez MédiSphère**

Les deux alertes de collecte vont à l'astreinte (`gravite: critique` pour MédiAgenda en prod et pour la disparition de la fédération du témoin, `avertissement` ailleurs) ; une politique d'admission refuse un ServiceMonitor ou une PodMonitor d'équipe sans l'étiquette de sélection exacte ; les politiques réseau des espaces applicatifs sont générées par la plateforme avec une règle d'entrée `supervision` toujours présente.

---

### M21-E36 — Panne : l'alerte ne part plus

**Démarche de diagnostic**

*Symptômes* : une alerte `firing` dans Prometheus, aucun courriel dans `astreinte@`.

*Hypothèses* : l'alerte n'arrive pas à Alertmanager (configuration `alerting` de Prometheus, réseau) ; elle arrive mais est **éteinte** (silence, inhibition, intervalle de mise en sourdine) ; elle part vers un **autre** récepteur (route) ; l'envoi **échoue** (SMTP, TLS, authentification) ; le courriel part mais ailleurs (adresse).

**Étape 1 — Prometheus, puis Alertmanager.**

```
admin@adm01:~$ curl -s $P/api/v1/alerts | jq -r '.data.alerts[] | select(.labels.alertname | startswith("EssaiChaine")) | "\(.labels.alertname) \(.state)"'
EssaiChaineAlerteCritique firing
EssaiChaineAlerteAvertissement firing
admin@adm01:~$ A=http://alertmanager.apps.par1.medisphere.internal:9093
admin@adm01:~$ curl -s "$A/api/v2/alerts" -G --data-urlencode 'filter=alertname="EssaiChaineAlerteCritique"' | jq '.[] | {receivers: [.receivers[].name], state: .status.state, inhibitedBy: .status.inhibitedBy, silencedBy: .status.silencedBy}'
```

La réponse classe tout de suite la panne : `state: "suppressed"` avec `silencedBy` (variante 4) ou `inhibitedBy` (variante 3) ; `state: "active"` mais un récepteur inattendu (variante 1) ; `state: "active"`, bon récepteur, rien reçu (variante 2 : regarder l'envoi).

**Variante 1 — faute de frappe dans les matchers de la route d'astreinte.**

```
{ "receivers": ["plateforme-mail"], "state": "active", "inhibitedBy": [], "silencedBy": [] }
admin@adm01:~$ curl -s $A/api/v2/status | jq -r .config.original > /tmp/am.yml
admin@adm01:~$ amtool config routes test --config.file=/tmp/am.yml gravite=critique equipe=plateforme alertname=EssaiChaineAlerteCritique
plateforme-mail
admin@adm01:~$ yq '.route.routes[] | select(.receiver == "astreinte-mail")' /tmp/am.yml
receiver: astreinte-mail
matchers:
  - gravite = "critque"
```

L'alerte tombe dans la route par défaut (`plateforme-mail`) : `plateforme@` l'a reçue, pas l'astreinte. Le commit de Lucas (« matchers simplifiés ») a introduit la faute. **Si ta CI rejoue les essais de routage de M21-E07** (`astreinte-mail | … gravite=critique …`), cette variante est refusée par le pipeline et le script en a choisi une autre : c'est le meilleur résultat possible, et la raison d'être de ces essais. Correctif : MR qui remet `gravite = "critique"` et ajoute à `routes-tests.txt` l'essai qui couvre une critique **de la plateforme** ([`routes-tests.extrait.txt`](fichiers/M21-E36/observabilite/alertmanager/routes-tests.extrait.txt)).

**Variante 2 — smarthost sur un port fermé.**

```
admin@adm01:~$ kubectl -n supervision logs alertmanager-kps-0 -c alertmanager --since=15m | grep -m2 -i notify
time=… level=WARN source=notify.go:… msg="Notify attempt failed, will retry later" component=dispatcher receiver=astreinte-mail integration=email[0] attempts=3 err="establish connection to server: dial tcp 10.10.20.19:587: connect: connection refused"
admin@adm01:~$ curl -s $P/api/v1/query --data-urlencode 'query=sum by (integration, reason) (increase(alertmanager_notifications_failed_total[15m]))' | jq -c '.data.result[] | [.metric, .value[1]]'
[{"integration":"email","reason":"other"},"12"]
```

Toutes les notifications par courriel échouent (pas seulement l'essai) : `plateforme@` et les équipes ne reçoivent rien non plus. Mailpit n'écoute que le 25 (avec STARTTLS) ; « passer au port de soumission » n'a de sens que si le serveur l'offre. Correctif : MR qui remet `smtp.par1.medisphere.internal:25`. Prévention : kube-prometheus-stack fournit `AlertmanagerFailedToSendAlerts` (`severity: warning`) : elle a sonné, et elle est partie deux fois. Par la route du cluster, vers le courriel cassé : perdue. Par le **chemin de secours de M21-E28** (`additionalAlertManagerConfigs`, filtre `Alertmanager.+`) : l'Alertmanager du témoin l'a reçue et l'a écrite à `astreinte@` par son propre envoi — cherche dans Mailpit un courriel de `supervision-temoin@` quelques minutes après l'injection : c'était le premier signal, et il ne disait pas « critique ». Si ton E28 n'est pas en place, rien n'est arrivé du tout. Complément : [`regles/alertmanager.yaml`](fichiers/M21-E36/observabilite/regles/alertmanager.yaml) crée `AlertmanagerCourrielEnEchec` (gravité **critique**, propre au courriel) ; son nom commence par `Alertmanager` : elle emprunte le chemin de secours sans rien y changer. Ce chemin est **poussé** par le Prometheus du cluster (flux `K8S_TRAV` → `mon01`:9093) ; pour qu'une coupure de ce flux ne le rende pas muet en même temps, un second chemin, **tiré** par le témoin, est facultatif mais peu coûteux : une sonde de la vue globale qui échoue quand une alerte marquée `relais="temoin"` est active, comme pour le Watchdog ([`prometheus-jobs-relais.extrait.yml`](fichiers/M21-E36/ansible/roles/supervision_temoin/templates/prometheus-jobs-relais.extrait.yml), [`blackbox-module-relais.extrait.yml`](fichiers/M21-E36/ansible/roles/supervision_temoin/templates/blackbox-module-relais.extrait.yml), règle du témoin [`relais-cluster.yml`](fichiers/M21-E36/ansible/roles/supervision_temoin/files/regles/relais-cluster.yml)).

**Variante 3 — inhibition à l'envers.**

```
{ "receivers": ["astreinte-mail"], "state": "suppressed", "inhibitedBy": ["3f2c…"], "silencedBy": [] }
admin@adm01:~$ yq '.inhibit_rules[] | select(.target_matchers[] | test("critique"))' /tmp/am.yml
# PLAT-2236 (Lucas) : pas de doublon avertissement + critique pour la même équipe
source_matchers:
  - gravite="avertissement"
target_matchers:
  - gravite="critique"
equal:
  - equipe
```

L'essai avertissement (même équipe) est actif : il éteint la critique. L'intention de Lucas était l'inverse (une critique éteint l'avertissement du même problème), et elle existait déjà, **avec** `equal: [namespace, alertname]`, qui limite l'inhibition au même problème. Correctif : retirer la règle ajoutée. Prévention : un essai de routage ne voit pas les inhibitions ; un test d'inhibition demande un Alertmanager de test (en CI, dans l'image `alertmanager` : configuration extraite, récepteurs vidés, couples d'alertes envoyés par `amtool alert add`, puis `amtool alert query --inhibited`) : [`tester-inhibitions.sh`](fichiers/M21-E36/observabilite/outils/tester-inhibitions.sh) et ses essais [`inhibitions-tests.txt`](fichiers/M21-E36/observabilite/alertmanager/inhibitions-tests.txt). Vérifié hors lab avec Alertmanager 0.34.1 : il passe sur la configuration de M21-E06 et **refuse** celle de Lucas.

**Variante 4 — silence de 30 jours sur toute l'équipe.**

```
admin@adm01:~$ amtool --alertmanager.url=$A silence query
ID                                    Matchers              Ends At                  Created By    Comment
1d7e…                                 equipe="plateforme"   2026-11-26 09:10:02 UTC  lucas.martin  CHG-2236 maintenance de gw02 : on coupe le bruit pendant l intervention (Lucas)
```

Un silence large et long, posé pour une maintenance de 2 heures. Correctif : `amtool silence expire 1d7e…` (le silence est un objet d'exploitation, pas de Git : il se corrige sur place) ; puis vérifier qu'aucune autre alerte n'a été tue pendant ce temps (`amtool alert query --silenced`). Prévention : règle de l'équipe dans RB-218 (silence = matchers précis — `alertname` + `instance` —, durée de la fenêtre de changement + 1 h, commentaire avec le ticket CHG), contrôle quotidien des silences de plus de 24 h (une requête sur `alertmanager_silences{state="active"}` ne suffit pas : elle ne dit pas la durée ; le contrôle de M21-E36 lit l'API), et `time_intervals` (M21-E16) pour les maintenances récurrentes plutôt que des silences.

**Clôture** : le courriel `[FIRING:1] EssaiChaineAlerteCritique` arrive dans `astreinte@` (Mailpit) ; `lab/bin/check 21 36` ; `--annuler` (qui termine l'essai : un courriel `[RESOLVED]` suit si `send_resolved` est actif).

**Explications**

Le chemin d'une alerte : Prometheus évalue la règle (`pending` pendant `for`, puis `firing`) et l'envoie à **chaque** Alertmanager de sa liste toutes les `evaluation_interval` (avec une date de fin qu'il repousse) ; Alertmanager la range dans un **groupe** selon la route qui la prend, puis, à chaque échéance du groupe, retire les alertes inhibées ou en silence, et envoie le reste au récepteur. L'API v2 expose chaque étape : `receivers` (route), `status.inhibitedBy` et `status.silencedBy` (mise en sourdine), et les métriques `alertmanager_notifications_total` / `_failed_total` par intégration (envoi). C'est pourquoi la démarche commence par une seule requête à l'API d'Alertmanager.

**Alternatives**

Pour prouver la chaîne en continu plutôt qu'une fois par mois : une alerte « Watchdog » qui passe par la **vraie** route de l'astreinte vers un récepteur de contrôle (webhook vers un service qui alerte s'il ne reçoit rien), ou un service externe de type *dead man's switch* ; MédiSphère utilise le témoin de `mon01` (M21-E28).

**Pièges classiques**
- Vérifier la configuration du dépôt au lieu de la configuration **chargée** (`/api/v2/status`) : un rechargement raté ou une MR non synchronisée les fait diverger.
- Expirer le silence sans regarder ce qu'il a tu pendant sa durée de vie.
- Corriger l'inhibition en la supprimant toute entière : on perd aussi la bonne (critique → avertissement).
- Tester le SMTP avec `swaks` depuis `adm01` : ce n'est pas le chemin d'Alertmanager (pods, VLAN 40 → `mon01` 25).

**En production chez MédiSphère**

Essais de routage et d'inhibition en CI ; essai mensuel de la chaîne, par l'astreinte, avec accusé de réception consigné ; alerte d'échec d'envoi routée vers le témoin ; silences limités par politique (durée, matchers, ticket) et revus chaque semaine.

---

### M21-E37 — Panne : les tableaux de bord sont vides

**Démarche de diagnostic**

*Symptômes* : « No data », erreur de source, ou courbes qui s'arrêtent à une date.

*Hypothèses* : variable vide (requête de variable, étiquette inexistante) ; source de données introuvable (UID) ou mal pointée (URL) ; métrique ou règle d'enregistrement absente ; données absentes sur la période (rétention, Store).

**Étape 1 — L'inspecteur de requête.** Panneau → menu → **Inspect → Query** : la requête interpolée et la réponse brute. Exemples de ce qu'on y lit :

```
expr: sum by (code) (rate(http_requests_total{namespace=~"", job="mediagenda"}[5m]))     ← variable vide
"Datasource prometheus was not found"                                                       ← UID inconnu
expr: job:mediagenda_requetes:taux5m{namespace="mediagenda-prod"}  →  result: []           ← règle absente
```

**Variante 1 — variable réécrite sur une étiquette inexistante.** La variable `namespace` du tableau RED a pour requête `label_values(up{job="mediagenda"}, kubernetes_namespace)` : l'étiquette `kubernetes_namespace` n'existe pas ici (c'est le nom que posaient les anciens exemples de configuration de Prometheus et l'ancien chart `prometheus`, par `labelmap` de `__meta_kubernetes_namespace` ; l'opérateur pose `namespace`). La vérification : `curl -s "$P/api/v1/label/kubernetes_namespace/values"` renvoie une liste vide. Le commit de Lucas est dans `tableaux/`. Correctif : MR qui remet `namespace`. **Contrôle de CI** : pour chaque variable `label_values(sélecteur, étiquette)` des tableaux, vérifier que l'étiquette existe dans la vue globale (job qui interroge `/api/v1/label/<étiquette>/values?match[]=<sélecteur>` : la CI joint-elle la vue globale ? les runners sont dans le cluster, mais une CI qui dépend de l'état de la production est fragile : préférer une liste d'étiquettes autorisées tenue dans le dépôt), voir [`verifier-tableaux.sh`](fichiers/M21-E37/observabilite/outils/verifier-tableaux.sh).

**Variante 2 — règle d'enregistrement renommée.** *Status → Rules* montre `job:mediagenda_requetes:rate5m` à la place de `job:mediagenda_requetes:taux5m` ; les tableaux citent l'ancien nom. Le renommage d'une règle d'enregistrement est un **changement d'API** : tout consommateur (tableaux, alertes, SLO, analyses Argo Rollouts de M21-E18) casse. **Si les tests `promtool test rules` de M21-E15 couvrent cette règle, la MR a été refusée** et le script a choisi une autre variante. Correctif : remettre l'ancien nom ; si le renommage est voulu, enregistrer les **deux** noms pendant une période de transition, migrer les consommateurs, puis retirer l'ancien. Contrôle de CI : chaque nom de la forme `niveau:métrique:opération` cité dans `tableaux/` doit être défini dans `regles/` (même script, job [`.gitlab-ci.extrait.yml`](fichiers/M21-E37/observabilite/.gitlab-ci.extrait.yml), liste des étiquettes garanties [`tableaux-etiquettes.txt`](fichiers/M21-E37/observabilite/tableaux-etiquettes.txt) ; vérifié hors lab sur les tableaux de M21-E17 et les règles de M21-E14 : il passe, puis refuse le renommage de Lucas).

**Variante 3 — UID de la source de données changé.**

```
admin@adm01:~$ curl -s https://grafana.apps.par1.medisphere.internal/api/frontend/settings -H "Authorization: Bearer $(cat ~/.config/workbook/grafana-checks.token)" | jq -r '.datasources[] | "\(.uid) \(.name) \(.isDefault)"'
thanos-query Prometheus true
Alertmanager-kps alertmanager false
```

Le tableau cassé cite la source par son UID en dur (`"uid": "prometheus"`), ce que la CI de M21-E17 interdit pour les tableaux du dépôt : le tableau fautif est donc un tableau **hors dépôt** (celui de M21-E05 fait à la main, ou un tableau par défaut copié). Deux corrections, les deux nécessaires : remettre l'UID d'origine (un UID de source est un identifiant **stable**, comme celui d'un tableau : on ne le renomme pas), et versionner ou supprimer les tableaux qui citent un UID en dur.

**Variante 4 — source repointée vers un Prometheus sans Thanos.** Les courbes s'arrêtent à 15 jours (rétention locale) et la vue « 6 mois » est vide (le sous-échantillonnage n'existe que dans le compartiment). La source par défaut pointe vers `http://prometheus-operated.supervision.svc:9090/` (Service sans tête de l'opérateur : selon la résolution DNS, l'un **ou** l'autre réplica, sans déduplication). La ConfigMap générée le prouve : `kubectl -n supervision get cm -l grafana_datasource=1 -o yaml | grep url`. Correctif : MR qui remet l'URL de Thanos Query ; la justification de Lucas (« au plus près de Prometheus, c'est plus rapide ») est fausse pour la plupart des requêtes et cache deux défauts (historique, et un réplica qui redémarre fait un trou).

**Clôture** : `lab/bin/check 21 37` (il parcourt **tous** les tableaux du dépôt : sources, variables, règles citées), `--annuler`.

**Explications**

Grafana n'a pas de données : il envoie des requêtes, avec les variables substituées, à une source identifiée par son UID. Chaque maillon peut rendre une réponse vide **valide** (pas d'erreur) : c'est ce qui rend ces pannes trompeuses. L'inspecteur de requête est le seul endroit qui montre la requête réellement envoyée ; *Explore* permet de la rejouer en isolant la variable.

**Alternatives**

Tests de tableaux plus poussés : `grafana-dashboard-linter` (règles sur les sources et les variables), ou un test qui charge chaque tableau dans un Grafana éphémère de CI et exécute ses requêtes contre un Prometheus de test alimenté par `promtool tsdb create-blocks-from` : complet, coûteux, à réserver aux tableaux critiques (RED de MédiAgenda, SLO).

**Pièges classiques**
- Corriger le tableau dans l'interface : il est provisionné (non modifiable) ou, s'il l'est, la modification sera écrasée au prochain chargement.
- Conclure « Prometheus ne collecte plus » sans regarder la requête envoyée.
- Renommer une règle d'enregistrement « pour la convention » sans période de double écriture.

**En production chez MédiSphère**

Contrôles de CI des tableaux (variables, règles citées, sources), propriété claire des tableaux (dossier par équipe, M21-E17), et une alerte sur les règles d'enregistrement qui ne produisent plus rien (`absent()` sur les règles consommées par les SLO).

---

### M21-E38 — Panne : Prometheus déborde

**Démarche de diagnostic**

*Symptômes* : séries en tête et mémoire qui montent vite ; requêtes lentes.

*Hypothèses* : nouvelle cible très riche ; étiquette à valeurs non bornées (identifiants, chemins, utilisateurs) ; *churn* (séries qui naissent et meurent sans cesse : redéploiements en boucle, étiquette qui change à chaque collecte) ; règle d'enregistrement mal agrégée.

**Étape 1 — Combien, depuis quand, d'où ?**

```
admin@adm01:~$ q() { curl -s $P/api/v1/query --data-urlencode "query=$1" | jq -c '.data.result[] | [.metric, .value[1]]'; }
admin@adm01:~$ q 'max by (pod) (prometheus_tsdb_head_series{namespace="supervision"})'
[{"pod":"prometheus-kps-0"},"182442"]
[{"pod":"prometheus-kps-1"},"181903"]
admin@adm01:~$ q 'max(prometheus_tsdb_head_series{namespace="supervision"} offset 1h)'
[{},"121876"]
admin@adm01:~$ q 'sum(rate(prometheus_tsdb_head_series_created_total{namespace="supervision"}[5m])) by (pod)'
[{"pod":"prometheus-kps-0"},"333.6"]
admin@adm01:~$ q 'topk(3, scrape_series_added)'
[{"namespace":"wb-pannes","pod":"temoin-metriques-7d9…","job":"temoin-metriques",…},"2500"]
[{"namespace":"wb-pannes","pod":"temoin-metriques-7d9…",…},"2500"]
[{"namespace":"mediagenda-prod",…},"0"]
```

Deux cibles créent 2 500 séries **à chaque collecte** (la tête a pris 60 000 séries en quelques minutes) : ce n'est pas une cible riche (elle le serait une fois), c'est du *churn*. Sur un des Prometheus (*Status → TSDB Status*, par `port-forward`) : `mediagenda_rapports_requetes_total` en tête des métriques, et l'étiquette coupable (`requete_id`, `chemin` ou `utilisateur`) avec des dizaines de milliers de valeurs.

**Étape 2 — Gravité.** 333 séries/s ≈ 1,2 million par heure si l'application ne plafonnait pas (ici bornée à 60 000 pour ne pas mettre le lab en OOM) ; à quelques kilo-octets par série en tête (M21-E30 et ta mesure de M21-E44), c'est la mémoire de chaque réplica qui y passe, puis l'index des blocs, puis le compartiment Thanos. Lis les valeurs :

```
admin@adm01:~$ curl -s "$P/api/v1/series" -G --data-urlencode 'match[]=mediagenda_rapports_requetes_total' --data-urlencode "start=$(date -d '-2 min' +%s)" | jq -r '.data[0:3][] | to_entries | map("\(.key)=\(.value)") | join(" ")'
```

**Variantes 1 à 3 — l'étiquette** : `requete_id` (identifiant de requête), `chemin` (URL brute avec l'identifiant du rendez-vous), `utilisateur` (adresse de courriel du patient). La troisième est aussi un **incident de données personnelles** : des adresses de patients sont dans la supervision, donc dans les blocs, dans le compartiment (rétention 2 ans) et dans les sauvegardes. Ce n'est pas à toi de décider de la suite : Sophie Laurent (RSSI) est prévenue dans l'heure, avec l'inventaire de ce qui est stocké où (question 20 de M21-E45).

**Étape 3 — Contenir, à la collecte.** Le ServiceMonitor du témoin (en vrai, celui du dépôt de l'équipe) reçoit ([`servicemonitor-temoin.yaml`](fichiers/M21-E38/wb-pannes/servicemonitor-temoin.yaml)) :

```yaml
  endpoints:
    - port: metriques
      interval: 15s
      metricRelabelings:
        # INC-4838 : métrique à étiquette non bornée, jetée tant que l'équipe ne l'a pas corrigée.
        - action: drop
          sourceLabels: [__name__]
          regex: mediagenda_rapports_requetes_total
  sampleLimit: 500          # le témoin expose ~15 échantillons ; marge x30
  labelLimit: 20
  labelValueLengthLimit: 200
```

Vérification immédiate : `scrape_samples_scraped` reste élevé (l'application envoie toujours ses 2 500 lignes), `scrape_samples_post_metric_relabeling` retombe à une quinzaine, `scrape_series_added` à zéro. Pourquoi pas `labeldrop` : sans l'étiquette, les 2 500 lignes deviennent 2 500 échantillons **de la même série** au même instant ; Prometheus en garde un, rejette les autres (`prometheus_target_scrapes_sample_duplicate_timestamp_total`, avertissement « Error on ingesting samples with different value but same timestamp ») ; la collecte reste `up` (Prometheus 3.x : les doublons sont comptés et jetés, ils ne font pas échouer la collecte), mais la valeur gardée est arbitraire : on aurait remplacé une panne visible par une donnée fausse et silencieuse.

**Étape 4 — La tête ne redescend pas tout de suite.** Les séries créées restent en tête jusqu'à la compaction suivante (bloc de 2 h, puis retrait des séries sans échantillon récent) : la mémoire baisse en une à trois heures. Elles restent ensuite dans les blocs puis dans `thanos-k8s-par1`. **On ne supprime rien** (gestes interdits) ; pour la variante 3, la suppression est une décision de la RSSI, avec la procédure de la question 20.

**Réponse à l'équipe (modèle)** : [`reponse-equipe-mediagenda.md`](fichiers/M21-E38/medisphere/docs/kubernetes/journal/2026-10-27-INC-4838-reponse-equipe.md) — ce qui s'est passé, le coût chiffré, ce qu'il faut exposer (compteur `mediagenda_rapports_requetes_total{type, code}` aux valeurs bornées ; histogramme de durée sans identifiant ; l'identifiant de requête dans les **journaux** (M22) et les **traces** (M23), où il est à sa place), et la règle : *une étiquette, c'est un ensemble de valeurs fini et petit, connu à l'avance*.

**Prévention** : limite globale par cible (`enforcedSampleLimit`, `enforcedLabelLimit`, M21-E30) ; `PrometheusSeriesProchesDuBudget` (M21-E30, plus de 80 % du budget pendant 30 min) finit par sonner, mais une demi-heure **après** avoir franchi le seuil, soit près d'une heure après le début : il manque une alerte sur le **rythme de création** ([`regles/capacite-cardinalite.yaml`](fichiers/M21-E38/observabilite/regles/capacite-cardinalite.yaml) : `PrometheusCreationSeriesRapide`, `rate(prometheus_tsdb_head_series_created_total[10m])` au-delà d'un seuil étalonné sur ton lab, et `CibleTropDeSeriesNouvelles` sur `scrape_series_added`, qui désigne la cible) ; revue des métriques dans la MR de l'équipe (une métrique nouvelle = son nombre de séries prévu). RB-219 : [`RB-219-cardinalite-et-historique.md`](fichiers/M21-E39/medisphere/docs/observabilite/metriques/runbooks/RB-219-cardinalite-et-historique.md).

**Explications**

Le coût de Prometheus est proportionnel au nombre de séries **actives** (tête : index inversé, chunks ouverts, une structure par série) et, pour le stockage, au nombre total de séries vues par bloc (index). Une étiquette à valeurs non bornées multiplie les séries ; si chaque valeur ne vit qu'une collecte, le *churn* fait grossir la tête bien au-delà du nombre de séries « vivantes » à un instant donné. `sampleLimit` protège Prometheus d'une cible (la collecte est refusée en bloc), `metricRelabelings` filtre avant l'ingestion, mais après le transfert : le coût réseau et l'analyse du texte restent.

**Alternatives**

Agréger côté application (la seule vraie correction) ; une règle d'enregistrement qui agrège puis un `drop` de la brute (inutile ici : la brute n'a aucune valeur agrégée) ; un Prometheus séparé pour les équipes (isolation, au prix d'une instance de plus). Les limites globales de l'opérateur (`enforcedSampleLimit`, `enforcedLabelLimit`, `enforcedBodySizeLimit`…) bornent une **collecte** : aucune n'aurait arrêté cette panne, où chaque collecte restait petite (2 500 échantillons) et où c'est l'accumulation (*churn*) qui coûte ; d'où l'alerte sur le rythme de création des séries. Prometheus 3.15 n'a pas de limite du nombre de séries de la tête (vérifié dans `prometheus --help-long`).

**Pièges classiques**
- `labeldrop` de l'étiquette coupable (voir plus haut).
- Une `sampleLimit` plus basse que ce que la cible expose **légitimement** : `up == 0`, plus de données utiles.
- Redémarrer Prometheus pour « vider la mémoire » : la tête est reconstruite depuis le WAL, avec les mêmes séries, plus lentement.
- Ne pas traiter la variante 3 comme un incident de données personnelles.

**En production chez MédiSphère**

Limites globales et par équipe, alerte sur la création de séries, contrôle de la cardinalité dans les MR des équipes (une étape de CI qui collecte l'application de test et compte ses séries), et une liste d'étiquettes interdites (`*_id`, `email`, `utilisateur`, `chemin` brut) dans la politique de supervision.

---

### M21-E39 — Panne : les données anciennes ont disparu

**Démarche de diagnostic**

*Symptômes* : vues longues vides ou tronquées, avertissement de réponse partielle, ou absence d'envoi des sidecars.

*Hypothèses* : Store Gateway hors service ou sans accès au compartiment ; Store qui ne sert qu'une partie du temps (`--min-time`, `--max-time`, partage) ; sidecars qui n'envoient plus ; Compactor arrêté (`halt`) ; données réellement supprimées (rétention, opération manuelle).

**Étape 1 — Qui sert quoi.**

```
admin@adm01:~$ curl -s $P/api/v1/stores | jq '.data | map_values(map({name, lastError, minTime: (.minTime/1000|floor|todate), maxTime: (.maxTime/1000|floor|todate)}))'
{
  "sidecar": [
    {"name": "10.240.3.21:10901", "lastError": null, "minTime": "2026-10-12T08:00:00Z", "maxTime": "+275760-09-13T00:00:00Z"},
    {"name": "10.240.1.18:10901", "lastError": null, "minTime": "2026-10-12T08:00:00Z", "maxTime": "+275760-09-13T00:00:00Z"}
  ],
  "store": [
    {"name": "10.240.2.44:10901", "lastError": null, "minTime": "2026-10-25T08:00:00Z", "maxTime": "2026-10-27T06:00:00Z"}
  ]
}
```

Lecture : les sidecars servent les 15 derniers jours (rétention locale) ; le Store devrait commencer au premier bloc du compartiment (date de M21-E24). Ici il ne commence qu'il y a deux jours : **variante 3**. Pour la variante 1, le Store est absent de la liste, ou présent avec un `lastError` ; pour la variante 2, tout semble sain ici, l'indice est ailleurs (étape 3).

**Étape 2 — L'inventaire du compartiment, en lecture.**

```
admin@adm01:~$ cfg="$(~/src/observabilite/outils/objstore-local.sh)"      # M21-E25 : fichier 600 en mémoire
admin@adm01:~$ thanos tools bucket inspect --objstore.config-file="$cfg" --sort-by=FROM --output=tsv 2>/dev/null | tail -n 3
admin@adm01:~$ rm -f "$cfg"
```

(Même configuration qu'en M21-E25 : style par chemin, racine MédiSphère. `inspect` ne fait que lire.) Les blocs sont là, du premier jour à hier : **rien n'est perdu** dans les variantes 1 et 3. Pour la variante 2, le dernier bloc de niveau 1 (`Resolution 0`, source `sidecar`) date du redémarrage des Prometheus : les sidecars n'envoient plus.

**Variante 1 — Secret du stockage objet faux, Store redémarré.** (`ThanosQueryStoreManquant` de M21-E25 sonne au bout de 10 min : vérifie-le dans `plateforme@`.)

```
admin@adm01:~$ kubectl -n supervision logs <pod du Store> | grep -m2 -iE 'error|denied'
… level=error … msg="… initial synchronization" err="… SignatureDoesNotMatch: The request signature we calculated does not match the signature you provided …"
admin@adm01:~$ kubectl -n supervision get secret thanos-objstore -o jsonpath='{.metadata.annotations}'
{"medisphere.internal/restaure-depuis":"coffre-2026-06"}
```

Le Secret (créé hors Git) a été remplacé par une ancienne version (clé secrète périmée) ; le Store a redémarré et ne peut plus lister le compartiment. Le sidecar et le Compactor utilisent le même Secret mais ne l'ont pas relu : **ils tomberont au prochain redémarrage**, la panne est une bombe à retardement. Correctif : recréer le Secret **depuis la source** (`plateforme/k8s/outils/secrets-k8s.sh appliquer thanos`, qui lit Vault `critique`), puis redémarrer le Store (`kubectl -n supervision rollout restart` de son objet, ou suppression du pod si c'est un StatefulSet géré par Argo CD) ; vérifier que les trois composants voient le même contenu. Prévention : `thanos_objstore_bucket_operation_failures_total` en alerte, et la règle « un Secret se recrée depuis Vault, jamais depuis une copie » dans RB-219.

**Variante 2 — sidecar sans stockage objet.**

```
admin@adm01:~$ kubectl -n supervision get sts prometheus-kps -o json | jq -r '.spec.template.spec.containers[] | select(.name == "thanos-sidecar") | .args[]' | grep -c objstore
0
admin@adm01:~$ q 'count(thanos_shipper_uploads_total)'
(aucun résultat)
```

Lucas a retiré `objectStorageConfig` de `prometheus.prometheusSpec.thanos` (« le sidecar n'a besoin que du gRPC ») et, dans la même MR, posé `disableCompaction: true` : l'opérateur a reconfiguré les sidecars sans expéditeur et Prometheus en blocs de 2 h (`min-block-duration` = `max-block-duration`). Rien n'est perdu **tant que** la rétention locale (15 jours) couvre la durée de la panne : les blocs non envoyés sont encore sur les volumes des Prometheus, et le sidecar les enverra quand il retrouvera sa configuration (il envoie les blocs locaux **de niveau 1** absents du compartiment). C'est le `disableCompaction` qui sauve la mise — et c'est pour cela que le script de panne le pose : sans lui, l'opérateur, ne voyant plus de stockage objet, aurait rendu à Prometheus sa compaction normale ; les blocs de 2 h non envoyés auraient été fusionnés en blocs de 6 h puis 18 h, que le sidecar n'envoie jamais (sauf `--shipper.upload-compacted`, prévu pour les migrations et seulement sans compaction) : un trou définitif dans le compartiment, invisible pendant 15 jours. Leçon : retirer le stockage objet d'un sidecar n'est jamais anodin, même « pour un moment ». Après correction, tu peux retirer `disableCompaction` (retour à la compaction retardée d'E24 : Prometheus ne compacte que ce que le sidecar a déjà envoyé) ou le garder : les deux sont sûrs. Au-delà de 15 jours, les blocs les plus anciens seraient supprimés localement sans avoir été envoyés : perte définitive de l'historique de cette période. Correctif : MR qui remet la clé, synchronisation, vérification que `thanos_shipper_uploads_total` repart et que les blocs manquants apparaissent dans le compartiment. Pourquoi `ThanosSidecarEnvoisArretes` (M21-E25) n'a rien dit : son expression `increase(thanos_shipper_uploads_total[5h]) == 0` suppose que la métrique **existe** ; un sidecar sans stockage objet ne crée pas d'expéditeur, donc pas de métrique (`cmd/thanos/sidecar.go` : « uploads will be disabled ») : la règle n'a aucune série à évaluer. Complément ([`regles/thanos-complements.yaml`](fichiers/M21-E39/observabilite/regles/thanos-complements.yaml)) : `ThanosSidecarSansExpediteur` = sidecar `up` **sans** métrique d'expéditeur (`up{job="kps-thanos-discovery"} == 1 unless on (pod) thanos_shipper_uploads_total`).

**Variante 3 — `--min-time` du Store.**

```
admin@adm01:~$ kubectl -n supervision get pods -o json | jq -r '.items[].spec.containers[] | select((.args // []) | index("store")) | .args[]' | grep min-time
--min-time=-2d
```

Le Store ne sert que les blocs des deux derniers jours ; les sidecars couvrent 15 jours ; tout ce qui est plus ancien n'est servi par personne (et le sous-échantillonnage, qui n'existe que dans le compartiment, est invisible). Correctif : MR qui retire l'argument. Aucune alerte de M21-E25 ne le voit (le Store est sain, connecté, sans erreur). Complément : `ThanosStoreBlocsExclus` sur `thanos_blocks_meta_synced{state="time-excluded"}` (blocs écartés par la fenêtre de temps du Store, même fichier), et une revue des arguments du Store dans la CI (`kustomize build thanos/ | yq`).

**Réponse à Claire (modèle)** : « Aucune donnée n'a été supprimée : le compartiment contient tous les blocs depuis le 12 octobre (inventaire joint). Pendant N heures, la partie ancienne de l'historique n'était plus **servie** à Grafana, à cause de (cause). Si la panne avait été celle de l'envoi et avait duré plus de 15 jours, la période non envoyée aurait été perdue ; l'alerte ajoutée aujourd'hui sonne au bout de 15 minutes. »

**Clôture** : `lab/bin/check 21 39`, `--annuler`.

**Explications**

Thanos Query ne stocke rien : il interroge les composants qui exposent l'API *Store* (sidecars, Store Gateway, éventuellement Ruler et Receive), chacun annonçant ses **étiquettes externes** et sa **fenêtre de temps** ; il ne questionne que ceux dont la fenêtre recoupe la requête, et déduplique sur l'étiquette de réplica. Une fenêtre réduite (`--min-time`) ou un composant absent ne produisent pas d'erreur : seulement moins de données. Le Store Gateway ne fait que lire le compartiment (il garde un cache d'index local) ; le Compactor est le seul à le réécrire ; les sidecars y déposent les blocs de 2 h de leur Prometheus.

**Alternatives**

Thanos Receive (*remote write* vers un composant qui écrit dans le compartiment) à la place du sidecar : les données quittent Prometheus en continu (pas de fenêtre de 2 h à risque), au prix d'un composant à état de plus. Mimir 3 (écarté par ADR-0210 : ingestion par Kafka, trop lourd pour le lab).

**Pièges classiques**
- Lancer une sous-commande d'écriture de `thanos tools bucket` « pour vérifier » (`cleanup`, `mark`, `rewrite`) : interdit, et dangereux en concurrence avec le Compactor.
- Recréer le Secret avec la clé « qui marchait l'an dernier ».
- Conclure à une perte de données parce qu'une courbe est vide, sans inventorier le compartiment.
- Oublier que la panne de la variante 1 frappe les autres composants **à leur prochain redémarrage**.

**En production chez MédiSphère**

Alertes sur l'envoi des sidecars, sur les erreurs de stockage objet, sur le Compactor arrêté (`thanos_compact_halted`) ; contrôle hebdomadaire de l'inventaire du compartiment (dernier bloc, trous) par un job planifié en lecture ; rotation des clés RGW par Vault (M25) avec redémarrage contrôlé des trois composants.

---

### M21-E40 — Panne : l'alerte sonne sans arrêt

**Démarche de diagnostic**

*Symptômes* : beaucoup de courriels pour un même problème.

*Hypothèses* : la condition **bat** autour du seuil et la règle n'attend pas (`for` absent ou trop court, pas de `keep_firing_for`) ; le groupe est **relancé** trop souvent (`repeat_interval`) ; le regroupement est **trop fin** (`group_by` qui contient une étiquette par instance, ou `...`).

**Étape 1 — Mesurer et classer.**

```
admin@adm01:~$ q 'changes(ALERTS{alertname="TemoinFileAttenteHaute", alertstate="firing"}[1h])'
admin@adm01:~$ q 'count(ALERTS{alertname="TemoinFileAttenteHaute", alertstate="firing"})'
admin@adm01:~$ q 'max_over_time(temoin_file_attente[1h])' ; q 'min_over_time(temoin_file_attente[1h])'
admin@adm01:~$ curl -s -u "$MAILPIT_USER:$MAILPIT_PASSWORD" "https://mon01.par1.medisphere.internal:8025/api/v1/search?query=TemoinFileAttenteHaute&limit=50" | jq -r '.messages[] | "\(.Created) \(.Subject)"' | head
```

(Charge `MAILPIT_USER` et `MAILPIT_PASSWORD` depuis `~/.config/workbook/mailpit-checks.env` sans les afficher.) Trois profils :

| Profil | `ALERTS` | Courriels | Variante |
|---|---|---|---|
| battement | créneaux courts qui s'allument et s'éteignent toutes les 3 min | `[FIRING:2]` puis `[RESOLVED]` en alternance | 1 |
| répétition | ligne continue | même `[FIRING:2]` toutes les 5 min | 2 |
| éclatement | dix lignes parallèles par épisode | dix `[FIRING:1]` à la fois, puis dix `[RESOLVED]` | 3 |

**Variante 1 — `for` retiré.** `kubectl -n wb-pannes get prometheusrule temoin-metriques -o yaml` : plus de `for` sur `TemoinFileAttenteHaute` (annotation `medisphere.internal/modifie-par: lucas.martin`). La file a des pics de 45 s : sans `for`, chaque pic est une alerte. Correctif : remettre `for: 5m` (une file qui déborde moins de 5 minutes n'est pas un incident) ; si l'on veut aussi éviter qu'une alerte réelle se coupe sur un creux, `keep_firing_for: 10m`. Prévention : un test `promtool test rules` qui injecte une série en pics et vérifie qu'**aucune** alerte ne sort ([`temoin-regle.test.yaml`](fichiers/M21-E40/wb-pannes/temoin-regle.test.yaml), avec la règle corrigée [`temoin-regle.yml`](fichiers/M21-E40/wb-pannes/temoin-regle.yml)).

**Variante 2 — `repeat_interval: 1m`.** La configuration chargée (`/api/v2/status`) montre `repeat_interval: 1m` sur la route de l'astreinte (commit de Lucas). Une relance ne peut partir qu'à une échéance du groupe (`group_interval`, 5 min) : d'où un courriel toutes les 5 minutes, pour un incident **connu**. Correctif : remettre `4h` (politique d'alerte : une critique non acquittée est relancée par l'escalade humaine de M21-E32, pas par le flot de courriels). Prévention : contrôle de CI sur les valeurs minimales ([`verifier-routes.sh`](fichiers/M21-E40/observabilite/outils/verifier-routes.sh) : `repeat_interval ≥ 1h`, `group_interval ≥ 1m`, aucun `group_by` contenant `pod`, `instance` ou `...` sans justification).

**Variante 3 — regroupement par pod et par file.** `group_by: [alertname, pod, file]` sur la route de l'astreinte : chaque série est un groupe, donc un courriel ; dix courriels par épisode et dix résolutions. Correctif : revenir à `[alertname, namespace]` (le courriel du groupe liste les dix séries et leurs étiquettes : on sait quels pods sans recevoir dix messages).

**Clôture** : `lab/bin/check 21 40` (attends que la fenêtre de 30 minutes ne contienne plus la rafale), `--annuler` (qui remet la file témoin au calme).

**Explications**

Le nombre de notifications est le produit de trois choses : combien de fois l'état change (règle : seuil, `for`, `keep_firing_for`), combien de groupes il y a (route : `group_by`) et combien de fois un groupe inchangé est renvoyé (`repeat_interval`, borné par `group_interval`). `send_resolved` double la mise. Le bon réglage dépend de **qui** reçoit : une astreinte la nuit veut un message par incident, avec de quoi agir (runbook, résumé).

**Alternatives**

Pour les seuils qui battent, une hystérésis dans l'expression (seuil d'entrée haut, seuil de sortie bas : `x > 50 or (x > 30 and ALERTS{alertname="…"})`), ou une moyenne sur une fenêtre (`avg_over_time(x[5m]) > 50`) ; pour les incidents connus, un silence **court et précis** posé par l'astreinte avec le ticket.

**Pièges classiques**
- Monter `repeat_interval` à 24 h pour tout : une critique non traitée n'est plus rappelée du tout avant le lendemain.
- Supprimer `send_resolved` pour réduire le bruit : on perd l'information « c'est fini ».
- Grouper par `alertname` seul : deux équipes reçoivent le même courriel mêlant leurs incidents.

**En production chez MédiSphère**

Valeurs de référence dans la politique d'alerte (M21-E32), contrôlées en CI ; revue mensuelle du bruit (alertes les plus notifiées, alertes jamais acquittées) ; toute nouvelle alerte critique passe une semaine en `avertissement` avant d'être promue.

---

### M21-E41 — Panne : une règle ne se charge pas

**Démarche de diagnostic**

*Symptômes* : une règle commitée n'apparaît pas dans *Status → Rules* ; parfois Argo CD en échec.

*Hypothèses* : la règle n'est pas dans le cluster (synchronisation refusée : admission, AppProject, quota) ; elle y est mais l'opérateur ne la retient pas (étiquette de l'objet, étiquette de l'espace) ; elle est retenue mais Prometheus refuse le fichier généré (rare : l'admission valide) ; elle est chargée mais n'est pas évaluée (groupe en erreur).

**Étape 1 — Étage par étage.**

```
admin@adm01:~$ kubectl -n mediagenda-dev get prometheusrules --show-labels
admin@adm01:~$ kubectl -n argocd get applications.argoproj.io mediagenda-dev -o jsonpath='{.status.operationState.phase}{" "}{.status.operationState.message}{"\n"}'
admin@adm01:~$ kubectl -n supervision get prometheus kps -o jsonpath='{.spec.ruleSelector}{"\n"}{.spec.ruleNamespaceSelector}{"\n"}'
admin@adm01:~$ kubectl get ns mediagenda-dev --show-labels
admin@adm01:~$ kubectl -n supervision get cm -l prometheus-name=kps -o name | grep rulefiles
admin@adm01:~$ curl -s $P/api/v1/rules | jq -r '.data.groups[] | select(.name == "mediagenda-valkey") | .file'
```

**Variante 1 — étiquette de sélection oubliée.** L'objet existe dans `mediagenda-dev` et `mediagenda-recette`, Argo CD est vert, mais l'objet n'a pas `medisphere.internal/supervision: "oui"` : l'opérateur l'ignore, sans message. Correctif : MR dans `mediagenda/deploiement` qui ajoute l'étiquette (ou, mieux, la pose sur tout le composant par `labels:` dans sa `kustomization.yaml`, comme le fait `plateforme/observabilite` à sa racine). Prévention : contrôle de CI (toute PrometheusRule rendue porte l'étiquette) et politique d'admission (« Pour aller plus loin »).

**Variante 2 — l'espace a perdu son étiquette.** L'objet a la bonne étiquette, mais `ruleNamespaceSelector` (posé en M21-E29) ne retient plus `mediagenda-dev` : l'étiquette d'espace a été retirée à la main (annotation `medisphere.internal/nettoyage-etiquettes`). Toutes les règles d'équipe de l'espace ont disparu, pas seulement la nouvelle ; si le même sélecteur sert aux ServiceMonitors, les cibles aussi. Correctif : remettre l'étiquette **par le code de la plateforme** (`plateforme/k8s`, `espaces/`), puis vérifier. Cette variante n'existe que si ton sélecteur d'espaces est fondé sur une étiquette (le script la saute sinon).

**Variante 3 — PromQL illisible, refus du webhook.**

```
admin@adm01:~$ argocd app get mediagenda-dev | grep -i -A2 PrometheusRule
monitoring.coreos.com  PrometheusRule  mediagenda-dev  mediagenda-valkey  OutOfSync  …  admission webhook "prometheusrulevalidate.monitoring.coreos.com" denied the request: Rules are not valid … 1:25: parse error: unexpected identifier "container_memory_working_set_bytes" in aggregation
```

`max by (namespace, pod) container_memory…` : il manque les parenthèses de l'agrégation. Le webhook de prometheus-operator valide chaque PrometheusRule avec le même analyseur que Prometheus ; la synchronisation échoue (et Argo CD envoie ses notifications `on-sync-failed`, M20-E19) ; **le reste de la synchronisation a pu s'appliquer**, seule la règle manque. Correctif : MR avec l'expression corrigée ([`regle-valkey.yaml`](fichiers/M21-E41/mediagenda-deploiement/components/supervision/regle-valkey.yaml)). Reproduction hors Argo CD : `kustomize build overlays/dev | kubectl apply --dry-run=server -f -`.

**Prévention commune** : le pipeline de `mediagenda/deploiement` valide les règles comme celui de la plateforme ([`.gitlab-ci.extrait.yml`](fichiers/M21-E41/mediagenda-deploiement/.gitlab-ci.extrait.yml) et [`outils/extraire-regles-rendues.sh`](fichiers/M21-E41/mediagenda-deploiement/outils/extraire-regles-rendues.sh) : `kustomize build` de chaque overlay, extraction des `spec` de PrometheusRule, `promtool check rules`, et contrôle de l'étiquette de sélection). Les tests unitaires de règles (`promtool test rules`) restent l'affaire de la plateforme pour ses règles ; pour celles des équipes, ils sont recommandés et documentés.

**Clôture** : la règle est dans *Status → Rules* avec une dernière évaluation récente ; `lab/bin/check 21 41` (il vérifie que **toutes** les PrometheusRule du cluster sont chargées) ; `--annuler` (qui ne retire la règle de Lucas que si tu ne l'as pas modifiée). Pour rejouer l'exercice avec une autre variante, retire d'abord `regle-valkey.yaml` du composant (par MR) : le script refuse d'écraser un fichier existant ; et si ton composant pose désormais l'étiquette de sélection pour tous ses objets (`labels:` de la `kustomization.yaml`, ci-dessous), la variante 1 n'a plus d'effet : c'était le but.

**Explications**

Le chemin d'une règle : Git → Argo CD (synchronisation, avec admission par l'API : webhook de validation de l'opérateur) → l'objet PrometheusRule existe → l'opérateur sélectionne les objets par `ruleSelector` dans les espaces retenus par `ruleNamespaceSelector` → il écrit les règles dans des ConfigMaps `prometheus-kps-rulefiles-N` montées dans les pods → le *config-reloader* demande à Prometheus de recharger → Prometheus charge et évalue le groupe. Seules deux étapes produisent une erreur visible (admission et rechargement) ; la sélection, elle, est muette.

**Alternatives**

Laisser les équipes écrire leurs règles dans `plateforme/observabilite` (une seule CI, mais la plateforme devient un goulot) ; ou des PrometheusRule d'équipe validées par une ValidatingAdmissionPolicy (refus à l'API, visible dans Argo CD) en plus de la CI.

**Pièges classiques**
- Croire qu'un Argo CD vert prouve que la règle est chargée.
- Ajouter l'étiquette à la main sur l'objet : Argo CD la retire (ou la laisse si elle n'est pas dans Git… jusqu'à la prochaine recréation).
- Corriger l'étiquette de l'espace à la main sans la reporter dans le code qui crée les espaces.

**En production chez MédiSphère**

Une alerte méta : `count(prometheus_rule_group_rules) by (rule_group)` comparé à la liste des groupes attendus, ou plus simplement une alerte sur `prometheus_rule_evaluation_failures_total` et sur les groupes non évalués depuis 5 minutes (`time() - prometheus_rule_group_last_evaluation_timestamp_seconds > 300`).

---

### M21-E42 — Panne : la supervision hors cluster est aveugle

**Démarche de diagnostic**

*Symptômes* : le témoin crie au loup, ou se tait alors qu'il devrait parler.

*Hypothèses* : sonde mal configurée (module) ; réseau de `mon01` (pare-feu local, bordure) ; cibles disparues (fichiers de cibles) ; envoi des alertes du témoin (SMTP) ; service arrêté ; rechargement refusé.

**Étape 1 — Sur `mon01`, en lecture.**

```
admin@adm01:~$ ssh mon01
admin@mon01:~$ systemctl --no-pager status prometheus alertmanager blackbox_exporter | grep -E '●|Active'
admin@mon01:~$ curl -s localhost:9090/api/v1/targets | python3 -c 'import json,sys; [print(t["labels"]["job"], t["labels"].get("instance"), t["health"], t["lastError"][:80]) for t in json.load(sys.stdin)["data"]["activeTargets"]]'
admin@mon01:~$ curl -s localhost:9090/api/v1/query --data-urlencode 'query=count by (job) (up)'
admin@mon01:~$ sudo journalctl -u prometheus -u alertmanager -u blackbox_exporter --since -2h --no-pager | grep -iE 'error|reload' | tail
```

**Variante 1 — modules blackbox en IPv6 seulement.**

```
admin@mon01:~$ curl -s 'http://127.0.0.1:9115/probe?target=https://grafana.apps.par1.medisphere.internal/api/health&module=https_2xx&debug=true' | head -n 8
Logs for the probe:
… level=INFO msg="Beginning probe" probe=http timeout_seconds=…
… level=INFO msg="Resolving target address" target=grafana.apps.par1.medisphere.internal ip_protocol=ip6
… level=ERROR msg="Resolution with IP protocol failed" target=grafana.apps.par1.medisphere.internal ip_protocol=ip6 err="address grafana.apps.par1.medisphere.internal: no suitable address found"
admin@mon01:~$ curl -s http://127.0.0.1:9115/config | grep -B2 -A2 ip_protocol
```

Le lab est en IPv4 ; `preferred_ip_protocol: ip6` avec `ip_protocol_fallback: false` rend toutes les sondes HTTP impossibles, et le témoin alerte sur tout. Correctif : rejouer le rôle (`--check --diff` montre l'écart de `blackbox.yml`), qui remet le fichier et recharge blackbox.

**Variante 2 — sortie de `mon01` coupée vers la supervision du cluster.**

```
admin@mon01:~$ curl -m 5 -sv http://10.10.41.60:9090/-/healthy 2>&1 | tail -n 2
* Connection timed out after 5001 milliseconds
admin@mon01:~$ sudo nft list ruleset | grep -B4 10.10.41.6
table inet durcissement_sortie {
	chain sortie {
		type filter hook output priority filter - 10; policy accept;
		ip daddr { 10.10.41.60, 10.10.41.61 } counter packets 1882 bytes 112920 drop comment "PLAT-2242 sorties de mon01 limitées (Lucas)"
```

Depuis `adm01`, la vue globale répond : la coupure est **locale** à `mon01` (un `traceroute -T -p 9090 10.10.41.60` depuis `mon01` le confirme : rien ne sort). Correctif : retirer la table, puis vérifier que le rôle du pare-feu local de `mon01` décrit les sorties attendues. Leçon : le témoin a fait son travail (il a dit « je ne vois plus le cluster »), mais il ne sait pas distinguer « le cluster est mort » de « je suis aveugle » : la sonde canari (« Pour aller plus loin ») et une deuxième vue (le cluster sonde `mon01`, M21-E28) permettent de trancher.

**Variante 3 — fichier de cibles vidé.**

```
admin@mon01:~$ sudo head -n 3 /etc/prometheus/cibles/blackbox-https.yml
# PLAT-2242 (Lucas) : sondes désactivées le temps de la migration, à remettre après
# - targets:
#     - https://git01.par1.medisphere.internal/users/sign_in
```

Un fichier **valide** (une liste vide) : aucune erreur, aucune alerte, cinq sondes en moins. C'est la panne la plus dangereuse des quatre : le témoin est aveugle sans le savoir. Correctif : rejouer le rôle. Prévention : une alerte du témoin sur le nombre de cibles par job (`count by (job) (up) < N`, avec N tiré des variables du rôle dans le gabarit des règles), et le contrôle croisé depuis le cluster (`up` des jobs du témoin, à ajouter au `match[]` de `federation-mon01`).

**Variante 4 — SMTP de l'Alertmanager témoin.**

```
admin@mon01:~$ curl -s localhost:9093/metrics | grep 'alertmanager_notifications_failed_total{integration="email"'
alertmanager_notifications_failed_total{integration="email",reason="other"} 6
admin@mon01:~$ sudo journalctl -u alertmanager --since -30min | grep -m1 -i 'notify'
… msg="Notify attempt failed …" err="establish connection to server: dial tcp 10.10.20.19:587: connect: connection refused"
```

Même faute que M21-E36 v2, sur le témoin. Correctif : rejouer le rôle ; vérifier que l'alerte d'essai `EssaiTemoinAstreinte` arrive dans `astreinte@` à l'échéance suivante du groupe. Prévention : le cluster surveille l'envoi du témoin. Ni la fédération d'E12 (`match[]` limité à `pve|hyperviseurs|blackbox`) ni la ScrapeConfig `temoin-mon01` d'E28 (métriques du **Prometheus** témoin) ne voient cette métrique : ajoute `alertmanager-temoin` au `match[]` de `federation-mon01` (ou collecte `mon01:9093/metrics`, flux ouvert en E28), et une alerte du cluster sur `increase(alertmanager_notifications_failed_total{job="alertmanager-temoin"}[15m]) > 0`. Chacun surveille alors le transport de l'autre.

**Clôture** : rejeu du rôle sans écart (`--check --diff` vide), `lab/bin/check 21 42`, `--annuler`. Alertes ajoutées au témoin : [`temoin-lui-meme.yml`](fichiers/M21-E42/ansible/roles/supervision_temoin/files/regles/temoin-lui-meme.yml) (rechargement refusé, toutes les sondes HTTPS en échec à la fois, envois en échec) et [`temoin-lui-meme-cibles.yml.j2`](fichiers/M21-E42/ansible/roles/supervision_temoin/templates/temoin-lui-meme-cibles.yml.j2) (une règle par groupe de sondes : nombre de cibles sous celui que décrit le code), déposées par les tâches de [`regles-temoin.extrait.yml.j2`](fichiers/M21-E42/ansible/roles/supervision_temoin/templates/regles-temoin.extrait.yml.j2). La sonde « canari » (une cible volontairement en échec qui doit **toujours** être rouge) reste en « Pour aller plus loin ». RB-218 : [`RB-218-alertes-muettes-ou-bavardes.md`](fichiers/M21-E36/medisphere/docs/observabilite/metriques/runbooks/RB-218-alertes-muettes-ou-bavardes.md).

**Explications**

Le témoin est un petit Prometheus classique : pas d'opérateur, des fichiers rechargés par `SIGHUP` (ou `/-/reload` si `--web.enable-lifecycle`), des cibles relues automatiquement (`file_sd_configs`), un blackbox qui ne fait que ce que dit son module. Il hérite des mêmes modes de panne que le cluster, avec un outil de moins (pas d'Argo CD pour remettre la configuration : c'est Ansible, à la demande). D'où l'importance du `--check --diff` comme instrument de diagnostic.

**Alternatives**

Un service externe de sondes (hors du lab) ; un second témoin sur `pbs01` (site PAR2) qui surveille `mon01` — plus robuste, mais `pbs01` est une machine de sauvegarde qu'on ne charge pas (PLAN §4.9).

**Pièges classiques**
- Redémarrer les services au lieu de comparer avec le code : on ne sait plus ce qui avait changé.
- Tester les sondes depuis `adm01` : le chemin réseau n'est pas celui de `mon01`.
- Prendre les alertes du témoin pour argent comptant pendant l'incident (variante 2 : « tout le cluster est mort »).

**En production chez MédiSphère**

Rejeu planifié du rôle en `--check` (dérive détectée chaque nuit, rapport à `plateforme@`) ; surveillance croisée cluster ↔ témoin ; sonde canari permanente ; accès à `mon01` limité au compte d'automatisation et aux administrateurs nominatifs.

---

### M21-E43 — Astreinte : une nuit agitée

**Démarche** (il n'y a pas de solution unique : trois pannes parmi huit, chacune avec ses variantes)

1. **Triage (15 min).** Instruments d'abord : la vue globale répond-elle (`curl $P/-/ready`) ? Un Prometheus en direct (`port-forward`) dit-il la même chose ? L'Alertmanager du cluster envoie-t-il ? (`amtool alert add EssaiAstreinte gravite=avertissement equipe=plateforme --annotation=resume="essai astreinte" --alertmanager.url=$A`, puis Mailpit ; cette commande **écrit** dans Alertmanager : c'est voulu, c'est un essai, et l'alerte expire d'elle-même.) Le témoin voit-il juste (`ssh mon01`, cibles et sondes) ? Puis `lab/bin/check 21 35` à `21 42` pour cartographier.
2. **Ordre** : (a) le chemin des alertes (E36, E40, E42 v4) — tant qu'il est cassé, tout le reste, y compris une vraie panne du lab, passe inaperçu ; (b) le témoin (E42) — c'est lui qui préviendrait d'une chute du cluster pendant que tu travailles ; (c) la protection de Prometheus (E38) — elle menace tout le reste ; (d) la collecte et les règles (E35, E41) ; (e) l'affichage et l'historique (E37, E39) — gênants, rarement urgents la nuit, **sauf** E39 v2 (l'envoi : le compteur de 15 jours tourne).
3. **Communications** : modèle de message toutes les 30 minutes (ce qui est cassé, l'impact, ce qui est fait, prochaine étape, prochain point) ; journal horodaté.
4. **Clôture** : `lab/bin/break 21 43 --annuler` après réparation, `lab/bin/check 21 43`, post-mortem.

**Post-mortem d'exemple** : [`2026-10-27-INC-4843.md`](fichiers/M21-E43/medisphere/docs/kubernetes/post-mortems/2026-10-27-INC-4843.md) (trio E36 v3 + E35 v2 + E39 v1). Ce qu'on attend de la section **Détection** : pour chaque cause, l'alerte qui aurait dû exister, pourquoi elle n'existait pas, et l'action ; et une réflexion transverse : *la supervision n'était pas supervisée sur ce point* (inhibitions jamais testées, ServiceMonitor non retenu silencieux, Secret hors Git sans contrôle).

**Pièges classiques**
- Commencer par le tableau vide (E37) parce que c'est le symptôme le plus visible.
- Réparer trois pannes et n'en annuler qu'une (`--annuler` clôt les trois).
- Recopier dans le post-mortem un extrait du Secret `thanos-objstore` ou de `s3-thanos.env` (le contrôle le refuse).

---

### M21-E44 — Sous le capot : WAL, blocs et chunks

**Solution**

1. **API d'administration par le code** : [`defaults.extrait.yml`](fichiers/M21-E44/ansible/roles/supervision_temoin/defaults/main.extrait.yml) et [`prometheus.service.extrait.j2`](fichiers/M21-E44/ansible/roles/supervision_temoin/templates/prometheus.service.extrait.j2) :

   ```
   --web.listen-address={{ supervision_temoin_prometheus_ecoute }} \
   {% if supervision_temoin_api_admin | bool %}
     --web.enable-admin-api \
   {% endif %}
     --web.external-url={{ supervision_temoin_prometheus_url_externe }}
   ```

   (Attention à la continuation de ligne : le `\` doit terminer chaque ligne de `ExecStart` sauf la dernière, que la condition soit vraie ou non.) MR, pipeline protégé, `supervision_temoin_api_admin: true` dans `host_vars/mon01/`, rejeu ; un changement d'`ExecStart` impose un redémarrage (le gestionnaire du rôle le fait), pas un rechargement.

   ```
   admin@adm01:~$ curl -s http://mon01.par1.medisphere.internal:9090/api/v1/status/flags | jq -r '.data["web.enable-admin-api"]'
   true
   ```

2. **La base vivante** (sortie représentative) :

   ```
   admin@mon01:~$ sudo ls -la /var/lib/prometheus/data
   drwxr-xr-x  3 prometheus prometheus 4096 Oct 26 21:00 01M5X06Q1RPGW7P223TRZVHHNB
   drwxr-xr-x  3 prometheus prometheus 4096 Oct 27 03:00 01M5XMSTV8C3F88KKZEFW9H512
   drwxr-xr-x  3 prometheus prometheus 4096 Oct 27 07:00 01M5Y2H8RW60SFDSFHMSZH9F2A
   drwxr-xr-x  2 prometheus prometheus 4096 Oct 27 08:12 chunks_head
   -rw-r--r--  1 prometheus prometheus    0 Oct 20 10:02 lock
   -rw-r--r--  1 prometheus prometheus 20001 Oct 27 08:40 queries.active
   drwxr-xr-x  3 prometheus prometheus 4096 Oct 27 07:00 wal
   admin@mon01:~$ sudo ls -la /var/lib/prometheus/data/wal
   drwxr-xr-x 2 prometheus prometheus     4096 Oct 27 07:00 checkpoint.00000412
   -rw-r--r-- 1 prometheus prometheus 18120704 Oct 27 08:40 00000413
   -rw-r--r-- 1 prometheus prometheus  3276800 Oct 27 08:40 00000414
   ```

   Les segments du WAL font au plus 128 Mio ; à chaque troncature (après la création d'un bloc), les anciens segments sont remplacés par un *checkpoint* qui ne garde que les séries encore vivantes. `chunks_head/` contient les chunks complets de la tête, projetés en mémoire (*mmap*).

3. **Instantané** :

   ```
   admin@adm01:~$ curl -s -XPOST http://mon01.par1.medisphere.internal:9090/api/v1/admin/tsdb/snapshot
   {"status":"success","data":{"name":"20261027T084512Z-6d2a1f0c9b3e4a17"}}
   admin@mon01:~$ sudo du -sh /var/lib/prometheus/data/snapshots/20261027T084512Z-6d2a1f0c9b3e4a17 /var/lib/prometheus/data
   admin@mon01:~$ sudo stat -c '%h %n' /var/lib/prometheus/data/snapshots/*/01M5X06Q1RPGW7P223TRZVHHNB/index
   2 /var/lib/prometheus/data/snapshots/20261027T084512Z-6d2a1f0c9b3e4a17/01M5X06Q1RPGW7P223TRZVHHNB/index
   admin@adm01:~$ install -d -m 700 ~/m21/e44/instantane
   admin@adm01:~$ ssh mon01 'sudo tar -C /var/lib/prometheus/data/snapshots/20261027T084512Z-6d2a1f0c9b3e4a17 -cf - .' | tar -C ~/m21/e44/instantane -xf -
   admin@mon01:~$ sudo rm -rf --one-file-system /var/lib/prometheus/data/snapshots/20261027T084512Z-6d2a1f0c9b3e4a17
   ```

   `du` du dossier seul montre la taille des blocs, mais `du` de l'ensemble ne double pas : ce sont des liens physiques (2 liens par fichier). L'instantané contient aussi la tête, écrite en bloc pour l'occasion (`skip_head=false` par défaut). Le script [`instantane-temoin.sh`](fichiers/M21-E44/adm01/instantane-temoin.sh) fait les étapes 3 et la suppression avec garde-fous (nom vérifié, suppression limitée à `snapshots/<nom>`).

4. **Les blocs** (Prometheus 3.13.x téléchargé dans `~/m21/e44/outils/`, empreinte vérifiée contre `sha256sums.txt`) :

   ```
   admin@adm01:~$ ~/m21/e44/outils/promtool tsdb list -r ~/m21/e44/instantane
   BLOCK ULID                  MIN TIME                       MAX TIME                       DURATION     NUM SAMPLES  NUM CHUNKS   NUM SERIES   SIZE
   01M5K…                      2026-10-20 10:02:11 +0000 UTC  2026-10-22 06:00:00 +0000 UTC  43h57m48.4s  9204518      84216        1913         13MiB…
   01M5RG…                      2026-10-22 06:00:00 +0000 UTC  2026-10-24 06:00:00 +0000 UTC  48h0m0s      10051200     86688        1906         14MiB…
   …
   01M5Y2H8RW60SFDSFHMSZH9F2A  2026-10-27 05:00:00 +0000 UTC  2026-10-27 07:00:00 +0000 UTC  2h0m0s       418800       3816         1908         1.1MiB…
   01M5Y8…                     2026-10-27 07:00:00 +0000 UTC  2026-10-27 08:45:12 +0000 UTC  1h45m12s     366450       3622         1932         1.0MiB…
   admin@adm01:~$ jq '{minTime: (.minTime/1000|todate), maxTime: (.maxTime/1000|todate), stats, compaction}' ~/m21/e44/instantane/01M5K…/meta.json
   ```

   Lecture : blocs de 2 h (niveau 1) pour les dernières heures, blocs compactés de 6 h puis 18 h puis 54 h (niveaux 2, 3, 4, `compaction.sources` listant les blocs d'origine) pour les jours précédents ; le témoin garde 30 jours, donc ses blocs ne dépassent pas 10 % de 30 j = 72 h (la progression ×3 s'arrête à 54 h). Le dernier bloc, plus court, est la tête écrite par l'instantané.

5. **L'analyse** (sorties représentatives, format vérifié avec `promtool` 3.15 sur un instantané de test) :

   ```
   admin@adm01:~$ ~/m21/e44/outils/promtool tsdb analyze --limit=5 ~/m21/e44/instantane 01M5RG…
   Block ID: 01M5RG…
   Duration: 48h0m0s
   Total Series: 1906
   Label names: 61
   Postings (unique label pairs): 1874
   Postings entries (total label pairs): 15123

   Label pairs most involved in churning:
   …
   Highest cardinality labels:
   312 __name__
   91 le
   …
   Highest cardinality metric names:
   88 prometheus_http_request_duration_seconds_bucket
   …
   admin@adm01:~$ ~/m21/e44/outils/promtool tsdb analyze --extended --limit=3 ~/m21/e44/instantane 01M5RG… | sed -n '/Compaction analysis/,$p'
   Compaction analysis:
   samples per float chunk (min/avg/max): 1/116/120
   …
   admin@adm01:~$ install -d ~/m21/e44/instantane/wal     # promtool tsdb dump l'exige
   admin@adm01:~$ ~/m21/e44/outils/promtool tsdb dump --match='probe_success{instance="https://grafana.apps.par1.medisphere.internal/api/health"}' \
       --min-time=$(date -d '2026-10-26 10:00' +%s000) --max-time=$(date -d '2026-10-26 11:00' +%s000) ~/m21/e44/instantane | wc -l
   240
   ```

   240 échantillons en une heure = un toutes les 15 s (`scrape_interval` du témoin). « Échantillons par chunk » autour de 120 : un chunk XOR se ferme à 120 échantillons pour une série régulière (soit 30 min à 15 s).

6. **Refermer** : `supervision_temoin_api_admin: false`, rejeu, `web.enable-admin-api` à `false`.

7. **Compte rendu d'exemple** : [`tsdb-sous-le-capot.md`](fichiers/M21-E44/medisphere/docs/observabilite/metriques/analyses/tsdb-sous-le-capot.md), avec les réponses aux questions. Squelette fourni : [`ressources/E44-tsdb/compte-rendu-squelette.md`](../ressources/E44-tsdb/compte-rendu-squelette.md).

**Réponses aux questions d'analyse**

1. Le WAL rend durable ce qui n'est encore qu'en mémoire (la tête) : chaque lot d'échantillons y est écrit (séries nouvelles, échantillons, *tombstones*) avant d'être acquitté. Au redémarrage, Prometheus rejoue le WAL (depuis le dernier *checkpoint*) pour reconstruire la tête ; plus la tête est grosse (séries, durée depuis le dernier bloc), plus le rejeu est long. Le *checkpoint* compacte les segments anciens en ne gardant que les séries encore vivantes et les échantillons postérieurs au dernier bloc, pour borner le rejeu.
2. `chunks_head/` : depuis Prometheus 2.19, les chunks **complets** de la tête sont écrits sur disque et projetés en mémoire (*mmap*) au lieu de rester dans le tas : la mémoire résidente baisse, et au redémarrage ces chunks n'ont pas à être reconstruits depuis le WAL (rejeu plus rapide).
3. Un bloc est écrit une fois puis jamais modifié : c'est ce qui permet la lecture sans verrou, le partage par liens physiques (instantanés), l'envoi tel quel au stockage objet (Thanos). Une suppression de séries pose des *tombstones* (intervalles masqués) dans le bloc ; l'espace n'est libéré qu'à la réécriture du bloc (compaction suivante, ou `clean_tombstones`).
4. La rétention supprime des **blocs entiers** : par durée, ceux dont tout le contenu est plus vieux que la limite ; par taille, les plus anciens jusqu'à repasser sous `retention.size` (WAL et `chunks_head` compris dans le décompte). On ne peut pas supprimer « la moitié » d'un bloc : la granularité est la durée du bloc.
5. Le sidecar envoie les blocs **tels que Prometheus les écrit** ; si Prometheus compactait localement, il réécrirait des blocs déjà envoyés et le compartiment contiendrait des chevauchements. L'ancienne réponse de l'opérateur : `min-block-duration` = `max-block-duration` = 2 h quand le stockage objet est configuré (pas de compaction locale du tout). Celle de l'opérateur 0.94 avec Prometheus ≥ 3.9 et Thanos ≥ 0.42 (le cas du lab, M21-E24) : compaction locale **retardée** — Prometheus lit le fichier `thanos.shipper.json` du sidecar (`--storage.tsdb.delay-compact-file.path`) et ne compacte un bloc de niveau 1 qu'une fois envoyé ; le sidecar (`--shipper.ignore-unequal-block-size`) n'envoie que les blocs de niveau 1. Vérifie sur ton objet (arguments des conteneurs `prometheus` et `thanos-sidecar`) ; `disableCompaction: true` ramène l'ancien mode. Dans les deux cas, le compartiment ne reçoit que des blocs de 2 h et la compaction **du compartiment** se fait une fois, par le Compactor (M21-E25) ; la compaction locale retardée ne sert qu'à garder la base locale compacte (moins de blocs à ouvrir pour les requêtes des 15 derniers jours).
6. Le nombre moyen d'échantillons par chunk compressé : plus il est élevé, meilleure est la compression (XOR des valeurs, delta-de-delta des horodatages). Prometheus ferme un chunk à 120 échantillons (ou à la frontière d'un bloc) : à 15 s, un chunk couvre 30 min ; des séries courtes (*churn*) laissent des chunks presque vides, coûteux.
7. Ordre de grandeur sur le témoin : `prometheus_tsdb_head_series` ≈ 1 900, mémoire résidente du processus ≈ 150 à 250 Mo dont une part fixe (≈ 100 Mo) ; sur disque, 14 Mio pour 1 906 séries sur 48 h ≈ 7 Kio par série et par 48 h (≈ 1,3 octet par échantillon). Les chiffres du cluster (M21-E30) sont plus fiables pour la mémoire par série (quelques Kio) ; les 60 000 séries de M21-E38 ≈ deux à six cents Mo **par réplica** ; sans borne, la tête aurait dépassé le budget de 300 000 séries en un quart d'heure.
8. Le répertoire d'un Prometheus en marche change sans cesse (WAL, compaction, rétention) et est verrouillé (`lock`) : `promtool` ouvrirait une base en cours d'écriture, au mieux incohérente, au pire en la modifiant (rejeu du WAL dans un « bac à sable » qui peut créer des chunks). L'instantané est un état figé et cohérent.

**Pièges classiques**
- Oublier la continuation de ligne dans le gabarit de l'unité : `ExecStart` invalide, Prometheus témoin arrêté (le pipeline Molecule du rôle le voit, si le rôle en a un).
- Supprimer `snapshots/` entier, ou pire `data/`, au lieu du seul instantané créé.
- Analyser avec un `promtool` plus ancien que le Prometheus qui a écrit les blocs.
- Laisser l'API d'administration ouverte.

**En production chez MédiSphère**

L'API d'administration reste fermée partout ; une analyse de TSDB se fait sur un instantané pris à la demande (variable du rôle le temps de l'intervention, consigné), ou sur des blocs du compartiment Thanos téléchargés en lecture.

---

### M21-E45 — Questions expert : PromQL et Prometheus

1. `rate()` prend les échantillons du compteur dans la fenêtre, corrige les remises à zéro (une baisse est traitée comme un redémarrage : la valeur après la baisse s'ajoute), calcule l'augmentation entre le premier et le dernier échantillon, puis **extrapole** jusqu'aux bords de la fenêtre (sans dépasser la moitié d'un intervalle moyen au-delà des échantillons, ni aller sous zéro pour un compteur), et divise par la durée de la fenêtre. `increase()` est le même calcul sans la division : l'extrapolation donne des valeurs non entières même pour un compteur entier.
2. **c**. Il faut au moins deux échantillons dans la fenêtre, et de la marge pour une collecte manquée : quatre intervalles est la règle d'usage (`$__rate_interval` de Grafana applique la même idée). **a** et **b** donnent une ou deux valeurs, souvent aucune ; **d** est faux, `rate` n'interpole rien entre deux collectes.
3. `rate` : pente moyenne sur la fenêtre ; `irate` : pente entre les **deux derniers** échantillons. `irate` sert aux graphes très réactifs à grande résolution ; dans une alerte ou une règle d'enregistrement, elle ne voit qu'un instant (bruit, pics manqués entre deux évaluations) et dépend de l'alignement des collectes.
4. **b**. On agrège les **buckets** par `le` (en gardant les étiquettes voulues), puis on calcule le centile. **a** fait la moyenne de centiles par pod : statistiquement faux ; **c** perd l'étiquette `le` (`histogram_quantile` n'a plus de buckets) ; **d** applique `quantile` à des sommes : sans rapport.
5. `rate` doit voir chaque compteur séparément pour détecter **ses** remises à zéro ; `sum` d'abord mélange des compteurs dont l'un redémarre : la somme baisse, `rate` y voit une remise à zéro et ajoute une valeur fausse. PromQL interdit d'ailleurs `rate()` sur une expression (il faut une sous-requête), ce qui protège en partie.
6. Quand une cible disparaît (ou qu'une série manque à une collecte), Prometheus écrit un **marqueur de péremption** : la série cesse immédiatement d'exister pour les requêtes. Sans marqueur (données importées, fédération), une requête instantanée remonte jusqu'à 5 min en arrière (*lookback delta*) : 3 min après, elle verrait encore la dernière valeur ; 6 min après, rien. Avec marqueur : rien dans les deux cas.
7. `absent(up{job="vms"})` : vrai seulement si **aucune** série ne correspond **à l'instant** (disparition totale) ; `absent_over_time(…[10m])` : aucune série pendant 10 min (évite les faux positifs d'un redéploiement) ; `count(…) < 12` : détecte une perte **partielle**, mais pas la disparition totale (`count` d'un ensemble vide ne renvoie rien, la comparaison non plus) et exige de tenir 12 à jour. Il faut souvent les deux.
8. **b**. La correspondance se fait sur toutes les étiquettes, `code` compris. Forme correcte : `sum by (pod) (rate(http_requests_total{code=~"5.."}[5m])) / sum by (pod) (rate(http_requests_total[5m]))` (avec `or` sur un vecteur nul si on veut 0 plutôt qu'aucun résultat pour les pods sans erreur). **a** et **c** sont faux ; **d** : `bool` sert aux comparaisons.
9. `for` : l'alerte reste `pending` tant que la condition n'a pas été vraie à **chaque** évaluation pendant la durée ; `keep_firing_for` : une fois `firing`, elle le reste pendant la durée après que la condition est redevenue fausse (anti-battement). Au redémarrage, Prometheus restaure l'état `for` depuis la série `ALERTS_FOR_STATE` si l'interruption est plus courte que `--rules.alert.for-outage-tolerance` (1 h par défaut), avec un délai minimal `--rules.alert.for-grace-period` (10 min) avant de pouvoir passer `firing`.
10. `niveau:métrique:opérations` (ex. `job:http_requests:rate5m`) : niveau d'agrégation (étiquettes gardées), métrique d'origine, opérations dans l'ordre. On enregistre les buckets agrégés (`sum by (le, job) (rate(…_bucket[5m]))`) parce qu'on peut en tirer **n'importe quel** centile plus tard, et ré-agréger ; un centile enregistré ne s'agrège plus (pas de moyenne de centiles).
11. 5 × 40 × 8 × 6 = 9 600 séries au plus (en pratique beaucoup moins : toutes les combinaisons n'existent pas) ; × 2 réplicas × ~3 Ko ≈ 60 Mo : acceptable. Avec des chemins bruts, la dimension `chemin` devient le nombre de rendez-vous : des centaines de milliers ou plus, et elle croît sans fin ; × 2 réplicas, des gigaoctets : inacceptable (M21-E38).
12. Fédération : un Prometheus **collecte** une sélection de séries d'un autre (`/federate`), à son intervalle : valeur instantanée seulement, pas d'historique, trous si la collecte échoue. *Remote write* : copie **en continu** des échantillons vers un récepteur, avec file d'attente et reprise (perte possible au-delà de la file). Sidecar Thanos : envoi des **blocs** de 2 h une fois écrits ; les 2 dernières heures n'existent que localement. MédiSphère fédère entre `mon01` et le cluster (petit volume, sélection précise, aucun composant de plus) et utilise le sidecar vers le RGW (historique complet, pas de composant d'écriture supplémentaire, compatible avec la déduplication).
13. Chaque réplica a une étiquette externe de réplica (`prometheus_replica`, M21-E24) ; Thanos Query (`--query.replica-label`) regroupe les séries identiques **à cette étiquette près** et fusionne leurs échantillons (pénalisation des écarts). Si les autres étiquettes externes diffèrent, les séries ne sont pas considérées comme identiques : doublons (deux courbes, sommes doublées).
14. **b**. Le Compactor suppose être seul : deux instances choisissent les mêmes blocs, produisent des blocs qui se chevauchent, et les marquages de suppression se croisent ; le Compactor détecte ensuite les chevauchements et s'arrête (`halt`), et la vue globale peut doubler des données. **a**, **c**, **d** : il n'y a ni partage de travail ni verrou par défaut (le partage existe par *sharding* explicite des étiquettes externes, pas par défaut), et le RGW n'y est pour rien.
15. Un bloc sous-échantillonné garde, pour chaque fenêtre (5 min ou 1 h), cinq agrégats (`count`, `sum`, `min`, `max`, `counter`) : pour une série collectée toutes les 30 s, le gain est modeste à 5 min, et les trois résolutions coexistent tant que leurs rétentions se recouvrent. Le sous-échantillonnage sert d'abord à **interroger** vite de longues périodes ; on garde le brut 30 jours parce qu'on en a besoin pour les diagnostics récents (pics, centiles exacts) qu'aucun agrégat ne restitue.
16. 3 h 00 : première alerte → nouveau groupe, `group_wait` → courriel à **3 h 00 min 30 s** (`[FIRING:1]`). 3 h 02 : deuxième alerte dans le groupe → envoyée à l'échéance suivante du groupe, **3 h 05 min 30 s** (`[FIRING:2]`). 3 h 20 : résolution des deux → envoyée à l'échéance **3 h 20 min 30 s** (`[RESOLVED]`, si `send_resolved`). Trois courriels. Sans changement et sans résolution, le suivant aurait été la relance à 7 h 05 min 30 s (`repeat_interval` 4 h, à une échéance du groupe).
17. Les Alertmanager d'une grappe échangent silences et journal des notifications par *gossip* ; chaque instance attend avant d'envoyer un délai proportionnel à sa position dans la grappe (`peer_timeout`, 15 s par défaut, × position), puis vérifie dans le journal qu'un autre n'a pas déjà envoyé. Prometheus doit envoyer aux **deux** : si une instance est perdue, l'autre a déjà les alertes (la déduplication n'est pas une réplication des alertes).
18. Noms UTF-8 : une métrique peut contenir des points, à citer entre guillemets dans les accolades (`{"http.server.duration", code="200"}`) ; sélecteurs de plage : le bord gauche est **exclu**, une fenêtre `[1m]` sur des collectes à 1 min peut ne plus contenir qu'un échantillon (et `rate` plus rien) ; regex : `.` inclut désormais les fins de ligne ; collecte : `scrape_protocols` et un type de contenu absent ou invalide fait échouer la collecte sauf `fallback_scrape_protocol`. Celui qui fausse une alerte **sans erreur** : les fenêtres à bord gauche exclu (une règle `rate(x[1m])` avec un intervalle de 30 s n'a plus que un ou deux échantillons, elle renvoie moins souvent un résultat).
19. 0,5 % de 28 jours = 0,005 × 40 320 min ≈ **201,6 minutes** d'indisponibilité. Le taux d'erreur instantané sonne pour des pics sans conséquence et rate les fuites lentes ; le *burn rate* mesure la vitesse de consommation du budget : 14,4 sur 1 h consomme 2 % du budget en une heure (épuisé en ~2 jours) ; la fenêtre courte (5 min) confirme que le problème est **en cours** et fait cesser l'alerte vite après la correction (SRE Workbook, chapitre 5).
20. (1) Contenir : relabeling `drop` immédiat (M21-E38), vérifier qu'aucune nouvelle série n'entre. (2) Décider : la RSSI (Sophie) qualifie l'incident (données de santé indirectes : adresse de patient), décide de la suppression et de la notification éventuelle. (3) Prometheus du cluster : les séries sont dans la tête et les blocs locaux (15 j) ; suppression par l'API d'administration (`delete_series` puis `clean_tombstones`), **ouverte temporairement par le code** et refermée — ou attendre l'expiration locale si la RSSI l'accepte. (4) Compartiment : `thanos tools bucket rewrite` avec une configuration de suppression (`--rewrite.to-delete-config`), en marquant les anciens blocs pour suppression, **Compactor arrêté** pendant l'opération, sur une copie testée d'abord, avec l'accord écrit ; vérifier l'absence par requête. (5) Sauvegardes et copies (PBS des volumes, instantanés, copies d'analyse comme celle de M21-E44) : inventorier, appliquer la politique de rétention ou purger selon la décision. (6) Documenter : chronologie, périmètre, preuves de suppression, cause, prévention (étiquettes interdites, contrôle en CI).
