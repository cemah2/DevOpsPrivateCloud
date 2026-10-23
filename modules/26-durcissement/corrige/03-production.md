# Module 26 — Palier 3 : Production — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Validé hors lab pour ce corrigé** : sources des versions de référence lues à l'étiquette exacte — documentation de Cilium **1.20.3** (*Host Firewall*, *Host Policies* et leurs *known issues*, *Firewall Rules*, *WireGuard Transparent Encryption*), `values.yaml` et gabarit de ConfigMap du chart Cilium 1.20.3 (clés `hostFirewall`, `extraConfig`, `encryption.nodeEncryption`, `encryption.strictMode.egress.cidr`/`.ingress.enabled`), option d'agent `enable-extended-ip-protocols` dans `pkg/option/config.go` ; documentation et exemples de **Tetragon 1.7.1** (*Enforcement*, *Selectors*, *Kubernetes filtering*, *Hooks*, `file_monitoring_enforce.yaml`) ; README et `values.yaml` de **kubelet-csr-approver 1.2.15**, empreinte de l'archive du chart recalculée ; `values.yaml` de **kube-prometheus-stack 92.11.0** (`kubelet.serviceMonitor.tlsConfig`) et de `prometheus-node-exporter` (`extraArgs`, `extraHostVolumeMounts`) ; profils `cis_level1_server`, `anssi_bp28_intermediary` (Debian 13) et `cis_server_l1` (RHEL 10) présents à l'étiquette **ComplianceAsCode v0.1.82** (pas de produit Rocky : `rl10` absent). Validation **par schéma** des trois `CiliumClusterwideNetworkPolicy` d'hôte et de la politique `quarantaine` contre la CRD de Cilium 1.20.3 (protocole `VRRP` accepté), et des trois `TracingPolicyNamespaced` contre la CRD de Tetragon 1.7.1 ; rendu du chart kubelet-csr-approver 1.2.15 avec les valeurs de ce corrigé (`helm template`, ServiceMonitor rendu quand l'API `monitoring.coreos.com/v1` est déclarée) ; `promtool` 3.5 : `check rules` et **tous** les `test rules` de ce palier (conformité, correctifs) ; `ansible-lint` (profil *production*) sur les tâches de conformité continue, le rôle `correctifs` et le playbook de redémarrages ; script `conformite-analyse` exécuté sur un banc (oscap, curl et lynis simulés, xmllint réel : métriques et envois conformes) ; `shellcheck -x` et `bash -n` de tous les scripts.

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- **pare-feu d'hôte (E27)** : comportement réel du VRRP de keepalived avec `enable-extended-ip-protocols` (lu dans la documentation et le code, jamais observé) ; périphériques détectés automatiquement sur nos nœuds (`eth1` des travailleurs) ; identités vues pour les flux pod → nœud, Envoy de la Gateway → hôte, et pour les Services `LoadBalancer` à `externalTrafficPolicy: Local` (les *known issues* disent qu'ils sont filtrés au niveau des pods ; l'audit doit le confirmer) ; non-application des politiques au trafic reçu par `cilium_wg0` (limite documentée) ; champ `status.policy.realized.policy-enabled` lu par `outils/pare-feu-hote.sh` (forme exacte de la sortie JSON de `cilium-dbg` 1.20 non vérifiée) ; `hubble observe` dans le conteneur de l'agent et taille de son tampon ;
- **chiffrement nœud à nœud (E26)** : chiffres de débit et de processeur (indicatifs) ; chemin MTU des flux de l'hôte vers `cilium_wg0` (trou noir de MTU possible, à mesurer) ;
- **Tetragon (E29)** : `matchArgs` `Prefix` sur un argument `linux_binprm` résolu en `file` (`resolve: file`) dans un **kprobe** ; présence de `CONFIG_BPF_KPROBE_OVERRIDE` dans le noyau Debian 13 des nœuds ; chemin vu par Tetragon pour un fichier d'un `emptyDir` monté sur `/tmp` ; forme exacte du champ `action` dans les événements exportés vers Loki ;
- **conformité (E24)** : le playbook (`playbooks/durcissement.yml`), le *datastream* Rocky (`ssg-rl10-ds.xml`) et les profils adaptés (`/etc/medisphere/conformite/tailoring-{cis,anssi}.xml`, profils `…_<id>_medisphere`) sont ceux du rôle d'E10, éprouvé hors lab ; restent à vérifier : durée et mémoire d'une analyse (valeurs de l'unité à ajuster) ; acceptation de `curl --aws-sigv4` par SeaweedFS pour un `PUT` (les sondes du M08 et du M19 le font en lecture) ; Lynis dans EPEL 10 ;
- **kubelets (E25)** : résolution du nom court `k8s-w0N` depuis le pod de l'approbateur (domaines de recherche du nœud) ; raison et message posés par kubelet-csr-approver sur une demande refusée, et texte de ses journaux lors d'un refus (le check d'E25 y cherche « deni|denied|refus ») ; comportement de `seccompDefault` avec les composants du cluster qui ne déclarent pas de profil ;
- **audit (E28)** : verbe enregistré pour un `kubectl exec` en WebSocket (`get` attendu) ; syntaxe LogQL des règles (non chargées dans un Loki réel) ;
- **réponse à incident (E33)** : `ContainerCheckpoint` est bêta et activée par défaut en 1.36 (documentation « Kubelet Checkpoint API » de la 1.36), mais sa prise en charge par containerd et la présence de CRIU sur nos nœuds restent à constater ; effet exact de `allow-localhost` sur les sondes d'un pod en quarantaine ; verrouillage d'objet S3 dans la version de SeaweedFS du lab.

**Faits que ce palier fixe pour la suite** (palier 4, mini-projet, bloc G, F6) : minuterie `conformite-analyse.timer`, script `/usr/local/sbin/conformite-analyse`, `/etc/medisphere/conformite/{conformite.env,s3.env}` (à côté des profils adaptés et d'`exceptions.json` d'E10), variables `durcissement_conformite_*` du rôle ; compartiments `conformite` (identités `conformite`, `conformite-lecture`) et `preuves` (identités `preuves-depot`, `preuves-lecture`) de `s3-01` ; `~/.config/workbook/s3-conformite.env` ; métriques `medisphere_conformite_*`, `medisphere_lynis_indice`, `medisphere_redemarrage_requis`, `medisphere_correctifs_*` (fichiers `conformite.prom`, `correctifs.prom` de `/var/lib/prometheus/node-exporter/`) ; PrometheusRules `conformite` (`ConformiteDegradee`, `ConformiteSousObjectif`, `ConformiteAnalyseAbsente`, `LynisIndiceBas`, enregistrement `medisphere:conformite_objectif`) et `correctifs` (`RedemarrageEnAttente`, `CorrectifsSecuriteEnAttente`, `CorrectifsVerificationAbsente`) ; tableau `securite-conformite` ; Application et espace `kubelet-csr-approver` ; `seccompDefault: true` ; `encryption.nodeEncryption: true` ; `hostFirewall.enabled: true` + `extraConfig.enable-extended-ip-protocols` ; politiques d'hôte `hote-commun`, `hote-plan-controle`, `hote-travailleurs` (`composants/cilium/hote/`), étiquette `medisphere.internal/pare-feu-hote: "oui"`, outil `outils/pare-feu-hote.sh` ; politique d'audit v2 ; règles Loki `audit-securite` (`AuditExecProduction`, `AuditLectureSecretParPersonne`, `AuditLiaisonRoleCluster`, `AuditBrisDeGlace`) et `tetragon-application` (`TetragonProcessusTue`) ; `TracingPolicyNamespaced` `bloquer-exec-tmp` et `proteger-fichiers-systeme` (`tetragon/application/<espace>/`) ; rôle `correctifs`, playbook `redemarrages-vague.yml`, outil `outils/cve-en-service.sh` ; politique de cluster `quarantaine` (`composants/reseau/politiques/`) ; RB-262, RB-264, ADR-0260, `conformite-continue.md`.

**Promesses des modules précédents tenues ici** : M14-E26/M21-E29 (vérification TLS des kubelets par Prometheus, approbation contrôlée des CSR) ; M15-E24 (réévaluation de `nodeEncryption`) ; M23 (chiffrement des flux internes : flux pod → nœud désormais chiffrés entre travailleurs) ; M15-E28/M15 E4 (modèle d'isolement par étiquette `medisphere.internal/quarantaine`, posé par une procédure) ; M03 (contrôle de conformité outillé chaque semaine, écarts remontés comme alertes). **Ce qui reste promis** : la source `k8saudit` de Falco (M14) est seulement discutée en E28 (le ruler de Loki la remplace) ; le filtrage des **sorties** de l'espace `traces` (M23) n'est pas traité par le pare-feu d'hôte (il filtre les nœuds, pas les pods) : il relève des CiliumNetworkPolicy de l'espace (mini-projet) ; la réévaluation d'OBI (M23) est laissée au mini-projet.

Fichiers de solution : `corrige/fichiers/M26-E24/` à `M26-E33/`. Les fichiers `*.extrait` ne montrent que ce qui change dans un fichier existant d'un autre exercice ou module.

---

### M26-E24 — Conformité continue : analyses hebdomadaires, rapports, alertes

**Solution**

Fichiers : rôle `durcissement` — [`tasks/conformite_continue.yml`](fichiers/M26-E24/ansible/roles/durcissement/tasks/conformite_continue.yml), [`tasks/main.yml.extrait`](fichiers/M26-E24/ansible/roles/durcissement/tasks/main.yml.extrait), [`defaults/main.yml.extrait`](fichiers/M26-E24/ansible/roles/durcissement/defaults/main.yml.extrait), [`files/conformite-analyse.sh`](fichiers/M26-E24/ansible/roles/durcissement/files/conformite-analyse.sh), [`templates/`](fichiers/M26-E24/ansible/roles/durcissement/templates/) (unité, minuterie, paramètres, identifiants) ; [`host_vars/s3-01/seaweedfs.yml.extrait`](fichiers/M26-E24/ansible/inventories/lab/host_vars/s3-01/seaweedfs.yml.extrait) ; [`s3-conformite.env.exemple`](fichiers/M26-E24/adm01/s3-conformite.env.exemple) ; dans `plateforme/observabilite` : [`regles/conformite.yaml`](fichiers/M26-E24/observabilite/regles/conformite.yaml), [`tests/conformite.test.yaml`](fichiers/M26-E24/observabilite/tests/conformite.test.yaml), [`kps/values.yaml.extrait`](fichiers/M26-E24/observabilite/kps/values.yaml.extrait), [tableau](fichiers/M26-E24/observabilite/tableaux/securite/securite-conformite.json) et son [extrait de kustomization](fichiers/M26-E24/observabilite/tableaux/kustomization.yaml.extrait) ; documentation : [`conformite-continue.md`](fichiers/M26-E24/medisphere/docs/securite/durcissement/conformite-continue.md).

*1. Conception* : `conformite-continue.md`. Les deux réponses demandées : un score **stable** peut cacher une dérive (une règle réparée, une autre cassée la même semaine) ; c'est le compte `fail` et la comparaison des ARF qui la montrent. L'**ARF** est la preuve (résultat et éléments observés de chaque règle, versions du contenu et du profil adapté) ; le score n'en est qu'un résumé, pondéré, comparable seulement entre deux analyses du même profil.

*2. Stockage* : deux identités dans `host_vars/s3-01/seaweedfs.yml` (rôle `seaweedfs`, M05), compartiment versionné. `conformite` (VMs) : `Write:conformite`, `List:conformite` ; `conformite-lecture` : `Read:conformite`, `List:conformite`. Secrets générés hors écran et rangés en Vault `critique` :

```
admin@adm01:~/src/ansible$ uv run ansible-vault edit --vault-id critique@outils/vault-pass-client.sh group_vars/all/vault-critique-s3.yml
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/socle.yml -l s3-01 --tags seaweedfs --check --diff
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/socle.yml -l s3-01 --tags seaweedfs
admin@adm01:~$ install -m 600 /dev/null ~/.config/workbook/s3-conformite.env && "${EDITOR:-vi}" ~/.config/workbook/s3-conformite.env
admin@adm01:~$ (set -a; . ~/.config/workbook/s3-conformite.env; set +a; aws s3 ls s3://conformite/)          # liste : OK
admin@adm01:~$ (set -a; . ~/.config/workbook/s3-conformite.env; set +a; echo x | aws s3 cp - s3://conformite/essai)   # AccessDenied : attendu
```

*3. Analyse* : le script fait, par référentiel, `oscap xccdf eval --tailoring-file /etc/medisphere/conformite/tailoring-<cis|anssi>.xml --profile xccdf_org.ssgproject.content_profile_<id>_medisphere --results-arf … --report … <datastream>` (le profil `…_medisphere` n'existe que dans le profil adapté d'E10 : le script refuse d'analyser sans lui), accepte les codes 0 et 2 (2 = au moins une règle échoue, c'est un résultat), lit le score (`TestResult/score`) et les comptes par résultat avec `xmllint` et `local-name()`, compresse, envoie par `curl --aws-sigv4` (identifiants passés par un fichier de configuration de curl hérité, `-K <(…)`, jamais dans `ps`), puis Lynis (`hardening_index` de `/var/log/lynis-report.dat`). Les métriques sont écrites dans un fichier temporaire **du même dossier** puis renommées (le renommage est atomique sur un même système de fichiers : node_exporter ne lit jamais un fichier à moitié écrit). Les tâches du rôle n'activent que la **minuterie** : le service ne démarre jamais pendant un jeu du rôle (une vague entière lancerait oscap en même temps). Variables : `durcissement_conformite_*` (préfixe du rôle, exigé par `ansible-lint`).

L'unité n'utilise **aucun** réglage de bac à sable qui change la vue du système (`PrivateTmp`, `ProtectSystem`, `ProtectHome`) : CIS vérifie les options de montage de `/tmp`, `/home`, `/var/tmp` ; un `/tmp` privé fausserait ces règles. La charge est bornée autrement : `Nice=19`, `IOSchedulingClass=idle`, `CPUWeight`, `CPUQuota=50%`, `MemoryMax=1G`. La minuterie : `OnCalendar=Sun *-*-* 03:30:00`, `RandomizedDelaySec=30min`, **`FixedRandomDelay=yes`** (même créneau chaque semaine pour un hôte : les comparaisons restent propres), `Persistent=true`.

*4. Essai sur `mon01`* :

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/durcissement.yml -l mon01 --tags conformite_continue --check --diff
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/durcissement.yml -l mon01 --tags conformite_continue
admin@mon01:~$ systemctl list-timers conformite-analyse.timer
admin@mon01:~$ sudo systemctl start conformite-analyse.service ; systemctl status conformite-analyse.service --no-pager
admin@mon01:~$ journalctl -u conformite-analyse.service -n 20 --no-pager
… [cis_l1_serveur] score 87.31, durée 371 s
… [anssi_intermediaire] score 79.12, durée 402 s
admin@mon01:~$ systemctl show conformite-analyse.service -p MemoryPeak -p CPUUsageNSec
admin@mon01:~$ curl -s --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt https://mon01.par1.medisphere.internal:9100/metrics | grep ^medisphere_conformite_score
admin@adm01:~$ (set -a; . ~/.config/workbook/s3-conformite.env; set +a; aws s3 ls --recursive s3://conformite/ | tail -5)
```

Note la durée et la mémoire réelles (`MemoryPeak`) dans `conformite-continue.md` et ajuste `durcissement_conformite_memoire_max` si besoin.

*5. Déploiement* : les vagues d'E14 (`playbooks/durcissement.yml -l durcissement_vague_N --tags conformite_continue`), puis les nœuds (`-l k8s_par1`). Pour les nœuds, la MR de `plateforme/observabilite` ([extrait](fichiers/M26-E24/observabilite/kps/values.yaml.extrait)) recopie les deux options par défaut d'`extraArgs` (sinon le DaemonSet collecterait aussi les montages de conteneurs) et monte le dossier en lecture seule. Contrôle d'exhaustivité :

```
count(up{job=~"vms|node-exporter"} == 1)                                         # hôtes supervisés
count(count by (instance) (medisphere_conformite_derniere_analyse_secondes))      # hôtes analysés
(up{job=~"vms|node-exporter"} == 1) unless on (instance) medisphere_conformite_derniere_analyse_secondes   # les oubliés
```

Les oubliés habituels : `adm01` (pas dans une vague « normale »), `gw01`/`gw02` (le rôle passe, mais l'alerte `ConformiteAnalyseAbsente` sonne jusqu'au premier dimanche), les VMs Rocky (paquet `scap-security-guide` absent → la tâche `assert` arrête le jeu, ce qui est voulu).

*6. Alertes* : [`regles/conformite.yaml`](fichiers/M26-E24/observabilite/regles/conformite.yaml). Points de conception :
- `ConformiteDegradee` : le score est une jauge **constante** toute la semaine ; `offset 7d` lit donc l'analyse précédente. `for: 1h` évite un faux positif pendant les minutes où une analyse vient de remplacer le fichier.
- `ConformiteSousObjectif` : un objectif **par référentiel** (CIS 85, ANSSI 75) en séries d'enregistrement constantes (`medisphere:conformite_objectif`), puis `score < on (referentiel) group_left () objectif`. Un seul seuil pour les deux référentiels serait faux (l'ANSSI intermédiaire est plus exigeant).
- `ConformiteAnalyseAbsente` : trois cas réunis par `or on (instance)` — analyse trop vieille, hôte supervisé **sans** série (`up == 1 unless on (instance) …` : une série absente ne vaut pas « vieux », elle n'existe pas), hôte avec un seul des deux référentiels.
- aucune alerte critique : une dérive de conformité se traite en heures ouvrées.

```
admin@adm01:~/src/observabilite$ outils/extraire-regles.sh && promtool test rules tests/conformite.test.yaml
  SUCCESS
```

Dans les tests, les séries ont un pas d'une minute : avec un pas d'une heure, les évaluations faites entre deux échantillons ne voient plus la série au-delà de 5 minutes (*lookback*) et le `for` repart de zéro.

*7. Tableau* : [`securite-conformite.json`](fichiers/M26-E24/observabilite/tableaux/securite/securite-conformite.json), dossier « Sécurité » (annotation `grafana_folder` du sidecar, comme au M21). Les métriques de conformité ne sont pas sensibles ; les journaux d'audit, eux, restent dans l'organisation « Sécurité » (M22).

**Explications**

OpenSCAP évalue un *datastream* SCAP (XCCDF pour les règles et leur sélection, OVAL pour les tests) contre un profil ; le fichier de *tailoring* modifie un profil sans toucher au contenu amont (règles désélectionnées, valeurs changées). C'est là que vit le registre des exceptions sous forme exécutable : une règle exceptée devient `notselected` dans l'ARF, ce qui prouve à la fois **qu'elle** est écartée et **que** le reste a été évalué. Le collecteur *textfile* transforme n'importe quel processus planifié en métriques sans démon supplémentaire : la minuterie produit, node_exporter expose, Prometheus collecte comme d'habitude, avec les mêmes étiquettes `instance` que les autres séries de l'hôte.

**Alternatives**
- **Pushgateway** au lieu du *textfile* : une dépendance centrale de plus, et des séries qui survivent à la disparition d'un hôte (piège classique).
- **Remédiation automatique** (`oscap … --remediate` ou playbooks générés) : rejetée (M03, ADR-0260) ; le durcissement passe par le rôle, relu.
- **Opérateur Compliance** (OpenShift) ou **kube-bench planifié** pour la partie Kubernetes : complémentaire (E05 en CronJob, mini-projet).
- **Wazuh SCA** : même mesure avec un agent et un gestionnaire, trop lourd pour le lab (ADR-0260).

**Pièges classiques**
- Code de sortie 2 d'oscap traité comme une erreur : le service échoue chaque semaine pour de mauvaises raisons et on cesse de regarder.
- `PrivateTmp=yes` « pour durcir » l'unité : les règles de partition de `/tmp` mentent.
- Le *datastream* RHEL 10 amont sur Rocky : la CPE de RHEL n'est pas reconnue, des centaines de règles passent en `notapplicable`, le score est absurde (regarde le compte `notapplicable`).
- Lancer l'analyse dans les tâches du rôle : la vague entière analyse en même temps.
- Identifiants sur la ligne de commande de curl (`--user cle:secret`) : visibles dans `ps` de tous les utilisateurs pendant l'envoi.
- Une alerte d'absence fondée sur `time() - …` seulement : un hôte jamais analysé ne sonne jamais.
- Remplacer `extraArgs` du node-exporter de `kps` sans recopier les options par défaut.

**En production chez MédiSphère**
Lot hebdomadaire signé (empreinte du dossier de la semaine signée par la clé `transit` d'OpenBao) ; rapport mensuel généré automatiquement pour la RSSI (tendance, nouvelles règles en échec, exceptions qui expirent) ; mise à jour trimestrielle de ComplianceAsCode annoncée (baisse de score attendue) ; même chaîne pour les hôtes physiques (`pve01`, `pbs01`) par un agent minimal ou une analyse à distance (`oscap-ssh`).

---

### M26-E25 — Kubelets : certificats de service et approbation des CSR

**Solution**

Fichiers : [`charts.yaml.extrait`](fichiers/M26-E25/charts-miroir/charts.yaml.extrait), [espace](fichiers/M26-E25/k8s/espaces/kubelet-csr-approver/00-namespace.yaml), [Application](fichiers/M26-E25/gitops/plateforme/kubelet-csr-approver.yaml) et [valeurs](fichiers/M26-E25/gitops/valeurs/kubelet-csr-approver/values.yaml), [`KubeletConfiguration`](fichiers/M26-E25/k8s/cluster/kubeadm-config.yaml.extrait), [values de `kps`](fichiers/M26-E25/observabilite/kps/values.yaml.extrait), [`csr-forgee.sh`](fichiers/M26-E25/adm01/csr-forgee.sh), [RB-143 §5](fichiers/M26-E25/medisphere/docs/kubernetes/runbooks/RB-143-renouveler-les-certificats.extrait-M26.md), [`securite.md`](fichiers/M26-E25/medisphere/docs/observabilite/metriques/securite.extrait-M26.md).

*1. Lecture* (réponses attendues) :
- Contrôles de l'approbateur (README 1.2.15) : demandeur préfixé `system:node:` ; au plus `allowedDnsNames` noms DNS (1) ; au moins un nom ou une adresse ; nom DNS conforme à `providerRegex` **et** préfixé par le nom du nœud demandeur ; adresses IP dans `providerIpPrefixes` ; nom DNS résolu vers des adresses qui incluent celles demandées ; durée ≤ `maxExpirationSeconds`. Sinon : refus (condition `Denied`).
- Sans ces contrôles, un kubelet compromis (son certificat client suffit) obtiendrait un certificat **serveur** signé par la CA du cluster pour n'importe quel nom : `sso.par1…`, `k8s-api…`, l'adresse d'un autre nœud. Tout client qui fait confiance à la CA du cluster (le serveur d'API vers les kubelets, Prometheus, metrics-server) accepterait alors un imposteur.
- Contrôle DNS : il ne vaut que ce que vaut la zone ; quelqu'un qui écrit dans `par1.medisphere.internal` (jeton de l'API de PowerDNS, clé TSIG) peut faire résoudre un nom vers son adresse. C'est pourquoi la plage d'adresses (VLAN 40) et l'expression stricte restent nécessaires : défense en couches.
- Les demandes **client** (`kubernetes.io/kube-apiserver-client-kubelet`) sont approuvées par le gestionnaire de contrôleurs (M14-E26) : elles ne prouvent qu'une identité de nœud déjà amorcée, pas un droit sur un nom réseau.

*2. Approbateur* : entrée `charts.yaml` (empreinte du champ `digest` de l'index amont, recontrôlée : `a8697589…e32f`), pipeline de `charts-miroir`, espace par `plateforme/k8s` (`task appliquer`), Application dans `plateforme/gitops`. Les valeurs : `providerRegex: '^k8s-(cp|w)0[1-9]$'`, `providerIpPrefixes: [10.10.40.0/24]`, `maxExpirationSeconds: "31536000"` (un an : la durée de kubeadm), `bypassDnsResolution: false` (le pod hérite des domaines de recherche du nœud ; si la résolution échoue, les journaux le disent et tu choisis entre un enregistrement manquant à corriger ou le contournement **justifié**), 2 réplicas avec élection de chef et anti-affinité, ServiceMonitor étiqueté pour `kps`. Le conteneur du chart est déjà conforme à `restricted`.

```
admin@adm01:~$ kubectl -n kubelet-csr-approver get deploy,pods -o wide
admin@adm01:~$ kubectl -n kubelet-csr-approver logs -l app.kubernetes.io/name=kubelet-csr-approver --tail=20 --prefix
```

*3. Preuve* : sur `k8s-w03`, forcer une nouvelle demande de service (RB-143 : supprimer le lien `kubelet-server-current.pem`, redémarrer le kubelet) :

```
admin@k8s-w03:~$ sudo rm /var/lib/kubelet/pki/kubelet-server-current.pem && sudo systemctl restart kubelet
admin@adm01:~$ kubectl get csr --field-selector spec.signerName=kubernetes.io/kubelet-serving --sort-by=.metadata.creationTimestamp | tail -2
NAME        AGE   SIGNERNAME                      REQUESTOR             REQUESTEDDURATION   CONDITION
csr-8q2lx   6s    kubernetes.io/kubelet-serving   system:node:k8s-w03   <none>              Approved,Issued
admin@adm01:~$ kubectl get csr csr-8q2lx -o jsonpath='{.status.conditions[0].reason}{" "}{.status.conditions[0].message}{"\n"}'
```

Demande forgée ([`csr-forgee.sh`](fichiers/M26-E25/adm01/csr-forgee.sh)) : clé ECDSA et demande dans `$XDG_RUNTIME_DIR`, objet créé **en se faisant passer pour le kubelet de `k8s-w01`** (`kubectl create --as=system:node:k8s-w01 --as-group=system:nodes`) — le scénario du modèle de menace —, nom `sso.par1.medisphere.internal`, adresse 10.10.20.30. Résultat attendu : condition `Denied` en quelques secondes, message de l'approbateur sur le nom (expression, préfixe du nœud) ou l'adresse (hors préfixe). L'usurpation est elle-même tracée par l'audit (`impersonatedUser`).

*4. Vérification TLS* : metrics-server n'a plus `--kubelet-insecure-tls` depuis M14-E26 (le check le vérifie). Values de `kps` : `kubelet.serviceMonitor.tlsConfig: {insecureSkipVerify: false, ca: {configMap: {name: kube-root-ca.crt, key: ca.crt}}}`. Après synchronisation :

```
admin@adm01:~$ kubectl -n supervision get servicemonitor kps-kubelet -o jsonpath='{.spec.endpoints[0].tlsConfig}' | jq
admin@adm01:~$ curl -s http://prometheus.apps.par1.medisphere.internal:9090/api/v1/query --data-urlencode 'query=up{job="kubelet"}' | jq -r '.data.result[] | .metric.instance + " " + .value[1]'
```

Le certificat de service porte l'adresse du nœud en nom alternatif (IP SAN) : la vérification du nom réussit alors que Prometheus contacte une adresse. Restent en `insecureSkipVerify` : `kubeControllerManager` et `kubeScheduler` (certificats de service auto-signés générés au démarrage par ces composants dans un cluster kubeadm), dette inscrite dans `securite.md`.

*5. seccomp par défaut* : `seccompDefault: true` dans le document `KubeletConfiguration` du dépôt et dans le ConfigMap (même MR), puis un nœud à la fois :

```
admin@adm01:~$ kubectl drain k8s-w03 --ignore-daemonsets --delete-emptydir-data
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-kubelet-config.yml -l k8s-w03
admin@adm01:~$ kubectl uncordon k8s-w03 && kubectl get pods -A --field-selector spec.nodeName=k8s-w03 | grep -v -E 'Running|Completed'
admin@adm01:~$ kubectl -n wb-essais exec <POD-SANS-PROFIL> -- grep Seccomp /proc/1/status
Seccomp:        2
Seccomp_filters:        1
```

`Seccomp: 2` = mode filtre (profil actif) ; 0 = aucun. Les pods privilégiés (Cilium, Falco, Tetragon, node-exporter) ne reçoivent rien ; les pods déjà conformes à `restricted` déclaraient `RuntimeDefault` : le changement touche surtout les espaces `baseline`/`privileged` sans profil explicite.

*6. RB-143 §5* : [extrait](fichiers/M26-E25/medisphere/docs/kubernetes/runbooks/RB-143-renouveler-les-certificats.extrait-M26.md) (approbation automatique, surveillance, approbateur arrêté, approbateur qui approuverait à tort).

**Explications**

Un certificat de service du kubelet est la seule chose qui permette au serveur d'API, à metrics-server et à Prometheus de savoir qu'ils parlent au **vrai** kubelet de `k8s-w01` et pas à un pod qui aurait pris son adresse. La CA du cluster ne peut pas vérifier seule qu'un demandeur a droit à un nom réseau ; l'approbateur ajoute cette connaissance de la topologie (noms, plage, DNS). L'approbation devient continue (un nœud reconstruit retrouve un certificat en secondes) et **traçable** (chaque décision est une condition dans l'objet CSR et un événement d'audit).

**Alternatives**
- **Approbation manuelle** (M14) : sûre si on lit vraiment, mais elle s'oublie, et le jour où elle manque, `logs`/`exec` tombent.
- **Contrôleur maison** (CronJob qui approuve selon des règles) : à écrire et maintenir, sans valeur ajoutée face à un projet maintenu.
- **CA externe** (mode *external CA* de kubeadm, step-ca) : centralisation, mais kubeadm ne renouvelle plus rien seul.

**Pièges classiques**
- Expression trop large (`^k8s-.*`) ou plage `10.10.0.0/16` : l'approbateur devient un tampon encreur.
- `bypassDnsResolution: true` par confort sans l'écrire dans les exceptions.
- Supprimer `kubelet-server-current.pem` sur plusieurs nœuds à la fois pour « tester ».
- Croire que `seccompDefault` touche les pods privilégiés, ou l'activer sur tout le cluster en une fois.
- Oublier que la mise à jour du ConfigMap ne change rien sur un nœud tant que `kubeadm upgrade node phase kubelet-config` n'a pas réécrit `/var/lib/kubelet/config.yaml`.

**En production chez MédiSphère**
Alerte sur toute CSR `Denied` (métrique de l'approbateur ou règle sur l'audit) et sur toute CSR sans décision depuis 15 minutes ; durée des certificats de service ramenée à 90 jours ; certificats de service signés aussi pour le contrôleur et l'ordonnanceur ; profil seccomp local plus strict que `RuntimeDefault` pour les applications exposées.

---

### M26-E26 — Chiffrement transparent entre nœuds avec WireGuard

**Solution**

Fichiers : [extrait des values de Cilium](fichiers/M26-E26/k8s/composants/cilium/values.yaml.extrait), [`chiffrement.md` révisé](fichiers/M26-E26/medisphere/docs/kubernetes/reseau/chiffrement.md).

*1. État des lieux* :

```
admin@adm01:~$ kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.enable-wireguard} {.data.encrypt-node}{"\n"}'
true
admin@adm01:~$ for p in $(kubectl -n kube-system get pods -l k8s-app=cilium -o name); do kubectl -n kube-system exec $p -c cilium-agent -- cilium-dbg status | grep Encryption; done
admin@adm01:~$ kubectl get pods -A -o json | jq -r '.items[] | select(.spec.hostNetwork) | "\(.metadata.namespace)/\(.metadata.name) \(.spec.nodeName)"'
admin@k8s-cp01:~$ sudo ss -lntup | sort -k5
```

`encrypt-node` est vide : la clé n'est posée dans la ConfigMap que si `nodeEncryption` est vrai (gabarit du chart). Le tableau des flux est dans [`chiffrement.md`](fichiers/M26-E26/medisphere/docs/kubernetes/reseau/chiffrement.md) : avant M26-E26, tout ce qui va d'un **pod** vers le **réseau d'un nœud** (Prometheus vers les agents Cilium 9962/9964/9965, vers node-exporter 9100, vers Tetragon 2112, vers etcd 2381) circule en clair entre nœuds, ainsi que tout trafic d'hôte à hôte.

*2. Preuve avant* :

```
admin@adm01:~$ kubectl apply -f ~/DevOpsPrivateCloud/modules/15-kubernetes-reseau/ressources/E24-mesure-iperf3.yaml
admin@adm01:~$ kubectl -n supervision get pods -o wide | grep prometheus-kps                  # sur quel nœud ?
admin@k8s-w01:~$ sudo timeout 60 tcpdump -ni eth0 -A -c 30 'tcp port 9962 and host 10.10.40.62' | grep -m3 cilium_
admin@adm01:~$ kubectl label namespace wb-perf pod-security.kubernetes.io/enforce=privileged --overwrite
admin@adm01:~$ kubectl debug node/k8s-w02 -n wb-perf --profile=sysadmin --image=registry.par1.medisphere.internal/dockerhub/nicolaka/netshoot:v0.16 -- iperf3 -s
admin@adm01:~$ kubectl debug node/k8s-w01 -n wb-perf --profile=sysadmin -it --image=registry.par1.medisphere.internal/dockerhub/nicolaka/netshoot:v0.16 -- iperf3 -c 10.10.40.62 -t 30   # hôte → hôte
admin@adm01:~$ kubectl -n wb-perf exec mesure-a -- iperf3 -c 10.10.40.62 -t 30                 # pod → hôte
admin@adm01:~$ kubectl -n wb-perf exec mesure-a -- iperf3 -c $(kubectl -n wb-perf get pod mesure-b -o jsonpath='{.status.podIP}') -t 30   # pod → pod
```

(Si Prometheus tourne sur `k8s-w02`, inverse les nœuds de la capture : il faut deux travailleurs **différents**.)

*3. Activation* : `nodeEncryption: true`, MR, puis :

```
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=cilium diff        # une seule ligne : encrypt-node: "true"
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=cilium apply
admin@adm01:~$ kubectl -n kube-system rollout restart ds/cilium && kubectl -n kube-system rollout status ds/cilium
admin@adm01:~$ cilium status --wait
```

*4. Preuve après* : la même capture ne montre plus de TCP 9962 entre `k8s-w01` et `k8s-w02` (seulement de l'UDP 51871) ; vers `k8s-cp01`, toujours en clair : les nœuds de contrôle sont **exclus** (`node-encryption-opt-out-labels`, défaut `node-role.kubernetes.io/control-plane`), pour qu'un travailleur qui régénère sa clé puisse la publier par l'API sans passer par WireGuard. Mesures : le pod → pod ne bouge pas ; le pod → hôte et l'hôte → hôte s'alignent sur le coût du chiffrement (ordre de grandeur ×3 de processeur). Chemin MTU : `cilium_wg0` à 1405, `ping -M do -s 1377` passe d'hôte à hôte, au-delà le noyau répond « message too long » (si rien ne revient et que les paquets disparaissent, c'est un trou noir de MTU : reviens en arrière et documente).

*5-6.* Décision et coût dans `chiffrement.md` ; matrice inchangée (même port 51871) ; `kubectl delete namespace wb-perf` ; `ls /tmp/*.pcap` vide sur les nœuds.

**Explications**

Avec `nodeEncryption`, l'agent ajoute aux pairs WireGuard les adresses des **nœuds** (en plus des adresses de pods) et redirige vers `cilium_wg0` le trafic de l'hôte vers les autres nœuds (sauf nœuds exclus). Le tableau *Which traffic is encrypted* de la documentation est la référence : « Node » y inclut les pods en réseau de l'hôte. Le mode strict, lui, ferait **refuser** le trafic non chiffré au lieu de simplement chiffrer ce qui peut l'être : utile contre une erreur de configuration, dangereux pendant la propagation d'une clé.

**Alternatives**
- **TLS applicatif** sur chaque flux de métriques (Cilium sait servir ses métriques en TLS, etcd aussi) : chiffre aussi vers les nœuds de contrôle, mais flux par flux.
- **IPsec** de Cilium : incompatible avec le pare-feu d'hôte selon les *known issues* de la 1.20, clés à gérer.
- **ztunnel** (`encryption.type: ztunnel`, nouveau en 1.20) : identité par charge, à suivre.

**Pièges classiques**
- Oublier le redémarrage des agents (`rollOutCiliumPods: false`).
- Faire la capture entre un travailleur et un nœud de contrôle et conclure que « ça ne marche pas ».
- Retirer l'exclusion des nœuds de contrôle pour « tout chiffrer ».
- Laisser `wb-perf` en `privileged` après l'exercice.

**En production chez MédiSphère**
Alerte si `Peers` ≠ nombre de nœuds − 1 sur un agent ; métriques des agents en TLS ; décision révisée quand le chiffrement nœud à nœud passe en stable ; TLS de bout en bout vers PostgreSQL (M27) pour les données de santé.

---

### M26-E27 — Pare-feu d'hôte de Cilium

**Solution**

Fichiers : [values](fichiers/M26-E27/k8s/composants/cilium/values.yaml.extrait), [`hote-commun.yaml`](fichiers/M26-E27/k8s/composants/cilium/hote/hote-commun.yaml), [`hote-plan-controle.yaml`](fichiers/M26-E27/k8s/composants/cilium/hote/hote-plan-controle.yaml), [`hote-travailleurs.yaml`](fichiers/M26-E27/k8s/composants/cilium/hote/hote-travailleurs.yaml), [`cluster/noeuds.yaml.extrait`](fichiers/M26-E27/k8s/cluster/noeuds.yaml.extrait), [`outils/pare-feu-hote.sh`](fichiers/M26-E27/k8s/outils/pare-feu-hote.sh), [`Taskfile.yml.extrait`](fichiers/M26-E27/k8s/Taskfile.yml.extrait), [RB-264](fichiers/M26-E27/medisphere/docs/securite/durcissement/runbooks/RB-264-pare-feu-hote-cilium.md), [matrice des flux du cluster](fichiers/M26-E27/medisphere/docs/kubernetes/reseau/matrice-flux-cluster.extrait-M26.md).

*1. Lecture* (réponses attendues) :
- Le pare-feu d'hôte s'accroche aux **périphériques natifs** gérés par Cilium (option `devices`, sinon détection automatique : `cilium-dbg status | grep 'Host firewall'` donne `[eth0]` sur les nœuds de contrôle et `[eth0, eth1]` sur les travailleurs, à vérifier chez toi). Il filtre l'entrée et la sortie du point de terminaison `reserved:host` (identité 1), pods en `hostNetwork` compris.
- Identités vues sur `k8s-cp01` : un autre nœud = `remote-node` ; un nœud qui porte le serveur d'API = `kube-apiserver` (en plus de `remote-node`) ; les sondes de cilium-health = `health` ; un pod = **son** identité (espace, étiquettes) ; tout le reste = `world`, distingué par `fromCIDR`.
- `fromCIDR` ne sélectionne pas les nœuds du cluster : leurs adresses ont l'identité `remote-node`, pas une identité CIDR (mode de correspondance par défaut). Une règle « 10.10.40.0/24 » n'autoriserait donc **aucun** nœud — mais bien la bordure (`gw01`/`gw02`, hors cluster).
- Les réponses aux connexions sortantes (DNS, NTP, Harbor, `s3-01`, Ceph par `eth1`) sont reconnues par le suivi de connexions ; et nos politiques n'ont **que** des règles d'entrée, la sortie n'est pas filtrée du tout.
- *Known issues* : les politiques d'hôte ne s'appliquent pas aux interfaces WireGuard de l'hôte ; avec le chiffrement nœud à nœud d'E26, ce qui arrive sur un **travailleur** depuis un autre travailleur — trafic d'hôte, mais aussi trafic d'un **pod** d'un autre travailleur vers ce nœud (Prometheus vers 9100… et un pod compromis vers le kubelet 10250) — passe par `cilium_wg0` et échappe au pare-feu d'hôte. Les nœuds de contrôle, exclus du chiffrement nœud à nœud, sont bien filtrés, comme tout ce qui arrive de l'extérieur du cluster par `eth0`. C'est une limite réelle du couple « chiffrement nœud à nœud + pare-feu d'hôte » : à écrire dans RB-264, dans la matrice et dans `exceptions.md` (compensations : authentification et autorisation du kubelet, politiques des pods en sortie, Falco/Tetragon), et à vérifier en audit (`hubble observe --to-identity 1` sur un travailleur).

*2. Inventaire* :

```
admin@k8s-cp01:~$ sudo ss -lntup | awk 'NR>1 {print $1, $5, $7}' | sort -u
admin@k8s-w01:~$ sudo ss -lntup | awk 'NR>1 {print $1, $5, $7}' | sort -u
```

Le résultat attendu (à confronter au tien) est la table de l'[extrait de la matrice](fichiers/M26-E27/medisphere/docs/kubernetes/reseau/matrice-flux-cluster.extrait-M26.md). Les ports qui n'écoutent que sur 127.0.0.1 (9878, 9879, 9890, 9891, 6060-6062, 10248, 10256, 54321 de Tetragon…) ne sont pas concernés : le pare-feu d'hôte ne voit pas le trafic local.

*3. Activation* : la MR contient **deux** choses : `hostFirewall.enabled: true` et `extraConfig: {enable-extended-ip-protocols: "true"}`. La seconde est la clé de l'exercice : la documentation *Host Policies* dit que, pare-feu d'hôte actif, les protocoles sans port inconnus de l'agent (dont **VRRP**) sont jetés (`DROP_CT_UNKNOWN_PROTO`) même sans aucune politique. Sans elle, au redémarrage des agents des nœuds de contrôle, keepalived n'entend plus ses pairs : chaque nœud se croit seul et prend la VIP 10.10.40.200 (ARP qui oscille, API intermittente). Le chart 1.20 n'a pas de clé dédiée : `extraConfig` ajoute l'option à la ConfigMap.

```
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=cilium diff         # enable-host-firewall, enable-extended-ip-protocols
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=cilium apply
admin@adm01:~$ kubectl -n kube-system rollout restart ds/cilium && kubectl -n kube-system rollout status ds/cilium
admin@adm01:~$ for n in k8s-cp01 k8s-cp02 k8s-cp03; do echo -n "$n : "; ssh $n ip -br addr | grep -c 10.10.40.200; done   # 1, 0, 0 (une seule)
admin@adm01:~$ kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status | grep 'Host firewall'
admin@adm01:~$ cilium bgp peers ; kubectl get nodes
```

*4. Politiques* : trois fichiers, règles d'entrée seulement, chaque règle commentée. Choix notables :
- **entre nœuds** (`hote-commun`) : 4240, 8472/UDP, 51871/UDP et ICMP depuis `remote-node`/`health` seulement ;
- **kubelet 10250** : `kube-apiserver` (logs, exec), Prometheus (`fromEndpoints` sur l'espace `supervision`), metrics-server (`kube-system`, étiquette du chart) — pas `remote-node` en entier : un travailleur n'a aucune raison de parler au kubelet d'un autre ;
- **plan de contrôle** : etcd 2379-2380 et **VRRP** depuis `remote-node` — et surtout **pas** depuis `kube-apiserver`, tentant mais dangereux : cette identité vient des Endpoints du Service `kubernetes` et un nœud la **perd** dès que son serveur d'API redémarre (E28, montée de version) ; ses pairs etcd seraient alors refusés par les deux autres (son serveur d'API, qui lit l'etcd local, ne reviendrait plus) et, s'il porte la VIP, ses annonces VRRP aussi (deux VIP). L'exposition aux travailleurs est acceptée et écrite (etcd exige un certificat client ; émettre du VRRP suppose d'être déjà root sur un nœud) ; 6443 et 8443 depuis `cluster` (les pods joignent l'API par le Service `kubernetes`, traduit vers 10.10.40.51-53:6443 : le paquet arrive avec l'identité du pod ; les travailleurs passent par la VIP:8443) ; 8443 depuis MGMT, `vault01-03` (OpenBao valide les jetons par TokenReview) et `mon01` ; métriques 2381, 10257, 10259 et l'exportateur HAProxy **8405** (M21-E10) depuis `supervision` ;
- **travailleurs** : BGP 179 depuis 10.10.40.2/.3 (la bordure est passive, mais on ne veut pas d'un refus silencieux le jour où elle initie) ;
- **administration** : SSH depuis MGMT et `runner01` ; ping depuis MGMT et `mon01` ; ICMP 3 (découverte du MTU du chemin) depuis le lab.

L'outil [`pare-feu-hote.sh`](fichiers/M26-E27/k8s/outils/pare-feu-hote.sh) trouve le point de terminaison d'hôte (identité 1) dans l'agent du nœud et règle `PolicyAuditMode` ; `applique` refuse si le nœud n'est pas étiqueté ou si le tampon de Hubble de l'agent contient des verdicts `AUDIT` vers l'identité 1 sur la dernière heure.

*5. Audit sur `k8s-w03`* :

```
admin@adm01:~/src/k8s$ outils/pare-feu-hote.sh audit k8s-w03
admin@adm01:~/src/k8s$ git switch -c pare-feu-k8s-w03 && "${EDITOR:-vi}" cluster/noeuds.yaml    # étiquette + etiquettes_gerees, MR
admin@adm01:~/src/k8s$ git switch main && git pull && outils/etiqueter-noeuds.sh
admin@adm01:~/src/k8s$ outils/pare-feu-hote.sh etat k8s-w03
admin@adm01:~$ kubectl -n kube-system exec $(kubectl -n kube-system get pods -l k8s-app=cilium --field-selector spec.nodeName=k8s-w03 -o name) \
    -c cilium-agent -- cilium-dbg monitor -t policy-verdict --related-to <ID-HOTE> | grep -v 'action allow'
```

Verdicts `audit` typiques à la première lecture : la sonde ICMP de `mon01` (si tu l'avais oubliée), le port d'un composant ajouté depuis (Tetragon 2112), parfois 80/443 vers une adresse 10.10.41.x si l'Envoy de la Gateway est vu comme l'hôte (à observer ; si c'est le cas, une règle depuis `world` vers les ports d'écoute réels d'Envoy, documentée). Chaque verdict : flux légitime → MR sur la politique ; illégitime → noté.

*6. Retour arrière répété* : chronomètre l'étape 1 (une commande), l'étape 2 (étiquette retirée : quelques secondes avant que l'agent ne régénère sa politique d'hôte), l'étape 3 par la console Proxmox (`crictl exec` dans `cilium-agent`, procédure *Emergency Recovery*). Les durées vont dans RB-264.

*7. Application* :

```
admin@adm01:~/src/k8s$ outils/pare-feu-hote.sh applique k8s-w03
admin@adm01:~$ kubectl get nodes ; kubectl -n wb-essais logs <POD-SUR-W03> --tail=1
admin@adm01:~$ ssh k8s-w03 true && echo ssh-ok
admin@adm01:~$ nc -vz -w 3 10.10.40.63 10255 ; nc -vz -w 3 10.10.40.63 9100     # refusés depuis MGMT (9100 n'est ouvert qu'à supervision)
```

Puis `k8s-w02`, `k8s-w01`, une nuit, et les nœuds de contrôle (celui qui porte la VIP en dernier). Sur chaque nœud de contrôle, après application : une seule VIP, `etcdctl endpoint health` sur les trois membres, `kubectl get --raw /readyz`.

*8.* Matrice et RB-264 sur `main`.

**Explications**

Le pare-feu d'hôte réutilise le chemin de données de Cilium : les programmes eBPF attachés aux périphériques natifs (`bpf_host`) évaluent la politique du point de terminaison `reserved:host` avec les mêmes identités que pour les pods. D'où sa force (une politique écrite comme les autres, des verdicts visibles dans Hubble, un mode audit) et ses limites (ce qui passe par `cilium_wg0`, les protocoles sans port, les Services traduits avant). Le mode audit est une propriété du point de terminaison **dans l'agent**, pas un objet de l'API : il disparaît au redémarrage de l'agent. D'où l'étiquette comme vrai interrupteur : sans étiquette, aucune politique ne sélectionne le nœud, quel que soit l'état de l'agent.

**Alternatives**
- **nftables local** (rôle `pare_feu` sur les nœuds) : connu de l'équipe, mais en concurrence avec les règles posées par Cilium (et kube-proxy jusqu'au M15) ; invisible de Hubble ; une règle `drop` mal placée casse le VXLAN.
- **Règles de sortie** en plus de l'entrée : la cible à terme (un nœud n'a pas à joindre Internet), mais l'inventaire des sorties est plus long (Harbor, `git01`, `s3-01`, Ceph, NTP, DNS, OpenBao, Loki, `ca01`) : mini-projet ou F6.
- **Pare-feu Proxmox** sur les cartes des VMs nœuds : filtre aussi, mais hors du dépôt du cluster, sans les identités des pods.

**Pièges classiques**
- `policyAuditMode: true` dans les values « pour être prudent » : toutes les politiques de **pods** passent en audit, l'isolement des équipes (M15-E28) disparaît.
- Activer le pare-feu sans `enable-extended-ip-protocols` : trois VIP.
- `fromCIDR: [10.10.40.0/24]` pour « autoriser les nœuds » : n'autorise que la bordure.
- etcd et VRRP limités à `kube-apiserver` : le premier redémarrage d'un serveur d'API isole son membre etcd (et peut dédoubler la VIP).
- Oublier l'opérateur Cilium (9963, `hostNetwork`) : sa cible tombe dans Prometheus sur le seul nœud qui le porte.
- 6443 limité à `remote-node` : les pods (Argo CD, opérateurs, ESO) ne joignent plus l'API.
- Étiqueter avant de passer en audit : le nœud applique tout de suite.
- Oublier `vault01-03` sur 8443 : les pods ne s'authentifient plus auprès d'OpenBao (`k8s-par1`), ESO cesse de rafraîchir les secrets, sans alerte immédiate.
- Redémarrer les agents (montée de Cilium) pendant la période d'audit d'un nœud.

**En production chez MédiSphère**
Alerte sur les refus vers l'hôte (`hubble_drop_total{reason="POLICY_DENIED"}` filtrés par identité de destination), revue trimestrielle de la matrice, règles de sortie, pare-feu d'hôte inclus dans la recette de reconstruction du cluster (F1) avec l'audit comme première étape.

---

### M26-E28 — Audit Kubernetes revisité : politique, détection, rétention

**Solution**

Fichiers : [politique v2](fichiers/M26-E28/ansible/roles/k8s_audit/files/politique.yaml), [règles du ruler](fichiers/M26-E28/observabilite/loki/regles/audit/securite.yaml), section « Traces » de [`conformite-continue.md`](fichiers/M26-E24/medisphere/docs/securite/durcissement/conformite-continue.md).

*1. Revue* :

```
sum by (resource) (count_over_time({job="kubernetes-audit"}[1h]))                         # volume par ressource
topk(10, sum by (user) (count_over_time({job="kubernetes-audit"}[1h])))                   # qui écrit le plus
{job="kubernetes-audit"} |= `"subresource":"exec"` | json | line_format "{{.verb}} {{.requestURI}}"
```

Constats attendus : les objets de sécurité ajoutés depuis le M14 (`policies.kyverno.io`, politiques `cilium.io`, `TracingPolicy`, `external-secrets.io`) tombent dans la dernière règle `Metadata` : on sait **qui** a modifié une politique d'admission, pas **ce qu'il** a demandé. Les plus bavards : les rapports de Kyverno (`reports.kyverno.io`, `wgpolicyk8s.io`) réécrits par ses contrôleurs, et les objets d'état de Cilium (`ciliumendpoints`, `ciliumidentities`). Un événement `pods/exec` au niveau `Metadata` contient `requestURI` avec `command=` et `container=` : la commande lancée **est** dans le journal ; le contenu du shell ne l'est jamais, à aucun niveau. Monter `exec` en `RequestResponse` n'apporterait rien (une requête de connexion n'a pas de corps) : c'est pourquoi la politique v2 le garde en `Metadata`, contrairement à une idée répandue.

*2. Politique v2* : [`politique.yaml`](fichiers/M26-E28/ansible/roles/k8s_audit/files/politique.yaml) : section « 1 bis » (bruit des rapports de Kyverno et des objets d'état de Cilium, **limitée** aux comptes de service des espaces `kyverno` et `kube-system` : une personne qui modifie ces objets reste tracée) ; CSR `…/approval` explicite en `Metadata` (approbations d'E25) ; `Request` pour `policies.kyverno.io`, les politiques et `TracingPolicy` de `cilium.io`, `external-secrets.io`. Application :

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-api-fichiers.yml --tags k8s_audit --check --diff
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-api-fichiers.yml --tags k8s_audit
admin@k8s-cp03:~$ sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/ && sleep 20 && sudo mv /etc/kubernetes/kube-apiserver.yaml /etc/kubernetes/manifests/
admin@adm01:~$ kubectl get --raw /readyz?verbose | tail -1 ; kubectl -n kube-system get pod kube-apiserver-k8s-cp03
```

(Le fichier de manifeste ne change pas : il faut le retirer puis le remettre pour que le kubelet recrée le pod statique et que le serveur d'API relise la politique.) Puis `k8s-cp02`, `k8s-cp01`. Contrôle par nœud : modifier une `PolicyException` de test et retrouver l'événement avec `requestObject` dans Loki, champ `node` (étiquette posée par Alloy) égal au nœud.

*3. Règles* : [`securite.yaml`](fichiers/M26-E28/observabilite/loki/regles/audit/securite.yaml). La sous-ressource et les groupes ne sont pas des métadonnées structurées : filtre de ligne d'abord (`|~`), puis filtres sur métadonnées (`| object_ns=~…`, `| user=~"oidc:.*"`). `AuditExecProduction` ne filtre **pas** le verbe (WebSocket : `get` ; SPDY : `create`). `AuditBrisDeGlace` est la seule critique : en dehors d'un incident déclaré, `admin.conf` ne doit jamais servir.

*4. Essais* :

```
admin@adm01:~$ kubectl -n mediagenda-prod exec deploy/mediagenda -- true                      # ticket CHG ouvert avant
admin@adm01:~$ kubectl -n wb-essais create secret generic essai-audit --from-literal=x=y && kubectl -n wb-essais get secret essai-audit -o name
admin@adm01:~$ kubectl create clusterrolebinding wb-test-liaison --clusterrole=view --user=lucas.martin && kubectl delete clusterrolebinding wb-test-liaison
admin@adm01:~$ kubectl --kubeconfig "$XDG_RUNTIME_DIR/admin.conf" get nodes                  # bris de glace, fichier temporaire 600
admin@adm01:~$ shred -u "$XDG_RUNTIME_DIR/admin.conf" ; kubectl -n wb-essais delete secret essai-audit
```

Délai mesuré entre l'action et le courriel : intervalle du ruler (1 min) + fenêtre de la requête + `group_wait` d'Alertmanager (30 s) : 1 à 3 minutes.

*5. Rétention* : locataire `audit` 1 an (M22), fichiers locaux 30 jours (options `audit-log-*` du M14). Section « Traces » de `conformite-continue.md`.

**Explications**

L'audit de l'API répond à « qui a fait quoi, quand, avec quel résultat » pour **toutes** les requêtes, y compris celles qui contournent GitOps. Sa politique est un compromis volume/valeur réglé par l'ordre des règles : le bruit d'abord (`None`), les données sensibles ensuite (jamais au-delà de `Metadata`), les écritures importantes avec leur corps (`Request`), le reste en `Metadata`. Les détections vivent dans le ruler de Loki, au plus près des données, avec les mêmes routes d'Alertmanager que le reste.

**Alternatives**
- **Falco, source `k8saudit`** (promise au M14) : le serveur d'API envoie ses événements en temps réel à Falco par un *webhook backend* (`--audit-webhook-config-file`) ; règles prêtes à l'emploi. Écartée ici : un composant de plus dans le chemin d'audit, un second flux à configurer sur trois nœuds de contrôle, des règles en double avec le ruler. À reconsidérer si Loki ne suffit plus (latence).
- **SIEM** externe : la cible d'une entreprise plus grande ; ici Loki `audit` + Grafana « Sécurité » en tiennent lieu.

**Pièges classiques**
- Mettre la règle `None` des rapports de Kyverno **après** une règle `Request` qui les vise : elle ne sert jamais.
- `level: Request` sur `""/secrets` « pour savoir ce qui a changé » : les valeurs en clair dans Loki pour un an.
- Filtrer `verb="create"` pour `exec` : aucune alerte avec un kubectl récent.
- Redémarrer les trois serveurs d'API en même temps.
- Oublier les personnes `oidc:` dans les filtres (`user!~"system:.*"` est plus sûr que `user=~"oidc:.*"` pour une liaison de rôle).

**En production chez MédiSphère**
Signature et archivage hebdomadaire des journaux d'audit (intégrité) ; tableau « qui a utilisé quoi » pour la revue trimestrielle des droits ; tests des règles du ruler (outil `logcli` sur un jeu d'événements) dans la CI de `plateforme/observabilite`.

---

### M26-E29 — Tetragon en application : bloquer

**Solution**

Fichiers : [`bloquer-exec-tmp`](fichiers/M26-E29/politiques/tetragon/application/wb-essais/bloquer-exec-tmp.yaml), [`proteger-fichiers-systeme` (essai)](fichiers/M26-E29/politiques/tetragon/application/wb-essais/proteger-fichiers-systeme.yaml), [`proteger-fichiers-systeme` (recette)](fichiers/M26-E29/politiques/tetragon/application/mediagenda-recette/proteger-fichiers-systeme.yaml), [pod d'essai](fichiers/M26-E29/essais/pod-essai-tetragon.yaml), [règle Loki](fichiers/M26-E29/observabilite/loki/regles/audit/tetragon.yaml), [AppProject](fichiers/M26-E29/gitops/projets/plateforme.extrait-M26-E29.yaml), [RB-260](fichiers/M26-E29/medisphere/docs/securite/durcissement/runbooks/RB-260-alerte-falco.extrait-M26-E29.md).

*1. Lecture* : `Sigkill` envoie un signal **synchrone** au processus qui a déclenché le crochet : il meurt avant de revenir de l'appel, mais l'opération en cours (une écriture) peut avoir eu lieu. `Override` remplace la valeur de retour de la fonction (ici `-1`, soit `-EPERM`) : l'opération n'a **pas** lieu, le processus continue et voit une erreur. L'exemple amont combine les deux sur les écritures pour garantir les deux effets. `TracingPolicyNamespaced` ne peut **par construction** viser que les pods de son espace (un `hostSelector` est refusé), et un objet d'un espace d'équipe se gouverne par le RBAC de cet espace ; une `TracingPolicy` avec `podSelector` resterait un objet de cluster qu'une erreur de sélecteur étend à tout le nœud. La politique est chargée par **chaque** agent Tetragon : un redémarrage de Tetragon la recharge (quelques secondes sans application), un pod qui change de nœud reste couvert.

*2. Prérequis noyau* :

```
admin@k8s-w01:~$ grep -E 'CONFIG_BPF_KPROBE_OVERRIDE|CONFIG_FUNCTION_ERROR_INJECTION' /boot/config-$(uname -r)
admin@k8s-w01:~$ sudo grep -E '^security_(bprm_check|file_permission)' /sys/kernel/debug/error_injection/list
```

Les fonctions `security_*` sont injectables depuis le noyau 5.7 (documentation *Override action*). Si `CONFIG_BPF_KPROBE_OVERRIDE` manque, remplace `Override` par `Sigkill` dans `bloquer-exec-tmp` et garde `Sigkill` seul dans l'autre (écris-le dans le journal : l'écriture peut alors avoir lieu avant la mort du processus).

*3. Dans `wb-essais`* :

```
admin@adm01:~$ kubectl -n wb-essais apply -f pod-essai-tetragon.yaml && kubectl -n wb-essais wait --for=condition=Ready pod/essai-tetragon
admin@adm01:~$ N=$(kubectl -n wb-essais get pod essai-tetragon -o jsonpath='{.spec.nodeName}')
admin@adm01:~$ T=$(kubectl -n tetragon get pods -l app.kubernetes.io/name=tetragon --field-selector spec.nodeName=$N -o name)
admin@adm01:~$ kubectl -n tetragon exec $T -c tetragon -- tetra tracingpolicy list
admin@adm01:~$ kubectl -n tetragon exec $T -c tetragon -- tetra getevents -o compact --namespace wb-essais &
admin@adm01:~$ kubectl -n wb-essais exec essai-tetragon -- sh -c 'cp /bin/true /tmp/t && /tmp/t; echo code=$?'
sh: /tmp/t: Operation not permitted
code=126
admin@adm01:~$ kubectl -n wb-essais exec essai-tetragon -- sh -c 'echo x > /etc/essai/f; echo code=$?'
command terminated with exit code 137
admin@adm01:~$ kubectl -n wb-essais exec essai-tetragon -- sh -c 'cat /etc/hosts >/dev/null && cat /etc/os-release >/dev/null && echo x > /tmp/y && /bin/true && echo positifs-ok'
positifs-ok
admin@adm01:~$ kubectl -n wb-essais exec essai-tetragon -- cat /etc/shadow ; echo code=$?
cat: can't open '/etc/shadow': Permission denied
code=1
```

Codes : 126 (exécution refusée par `Override`), 137 (128 + 9 : `SIGKILL` pendant l'écriture ; l'`Override` a d'abord refusé l'écriture). Dans les événements : `KPROBE_ACTION_OVERRIDE` sur `security_bprm_check`, `KPROBE_ACTION_SIGKILL` sur `security_file_permission`. `cat /etc/shadow` ne déclenche **rien** : le pod tourne en utilisateur 10001 (PSA `restricted`), l'**ouverture** du fichier échoue par les droits Unix avant toute lecture, et `security_file_permission` n'est appelé qu'à la lecture d'un fichier ouvert. La règle de lecture ne protège donc que des conteneurs qui tournent en root (espaces `baseline`/`privileged`, image mal construite) : défense en profondeur, faible valeur dans un espace `restricted` — écris-le dans le journal plutôt que d'élargir la règle. Même raisonnement pour l'écriture dans la recette : avec une racine en lecture seule, l'ouverture en écriture échoue d'abord ; d'où le volume `/etc/essai` du pod d'essai pour **voir** la règle agir.

*4. En recette* : seule `proteger-fichiers-systeme` va en recette. `bloquer-exec-tmp` attendra : une application Python qui compile des extensions ou un outil qui décompresse et exécute dans `/tmp` (scripts d'initialisation, *wheels*) serait cassée, et `/tmp` est justement le seul endroit inscriptible de l'image (E21). Une semaine d'observation :

```
{service="tetragon"} |= "KPROBE_ACTION" | json | process_kprobe_process_pod_namespace="mediagenda-recette"
admin@adm01:~$ kubectl -n mediagenda-recette get pods -l app.kubernetes.io/component=api -o jsonpath='{range .items[*]}{.metadata.name} {.status.containerStatuses[0].restartCount}{"\n"}{end}'
```

*5. Alerte et arrêt d'urgence* : [`tetragon.yaml`](fichiers/M26-E29/observabilite/loki/regles/audit/tetragon.yaml) ; RB-260 complété : suspendre l'auto-synchronisation de l'Application `politiques`, supprimer l'objet, corriger par MR, réactiver. Chronométré en recette : une à deux minutes.

**Explications**

Tetragon attache un programme eBPF au crochet du noyau et évalue les sélecteurs **dans le noyau** : la décision ne passe pas par l'espace utilisateur, donc pas de fenêtre entre détection et action (contrairement à Falco qui détecte puis alerte). C'est aussi pourquoi une erreur de sélecteur est immédiate et massive : d'où l'espace d'essai, les cas positifs et la portée par espace. Sur un système de fichiers racine en lecture seule, la règle d'écriture ne se déclenche presque jamais (l'ouverture en écriture échoue avant) : elle protège surtout les images qui ne respectent pas E21 et les volumes montés sur ces chemins ; la règle de lecture de `/etc/shadow`, elle, reste utile.

**Alternatives**
- **Seccomp/AppArmor** (profils locaux) : prévention par appel système ou par chemin, sans dépendance à Tetragon, mais plus difficile à cibler finement et à faire évoluer par GitOps.
- **Falco + réponse automatique** (falcosidekick qui supprime le pod) : réaction après coup, et supprimer un pod détruit les preuves (RB-262).
- **KubeArmor** : politiques d'application LSM par pod ; un outil de plus.

**Pièges classiques**
- `Prefix "/etc"` en lecture : tout processus meurt en lisant `/etc/hosts`.
- `matchBinaries` pour bloquer « l'exécution depuis /tmp » : il filtre le processus **appelant**.
- Écrire une `TracingPolicy` (de cluster) pour un essai.
- Croire que la politique est active parce que l'objet existe : `tetra tracingpolicy list` sur le **bon** nœud dit l'état réel (erreur de chargement, crochet absent).
- Oublier de réactiver l'auto-synchronisation après un arrêt d'urgence.

**En production chez MédiSphère**
Passage en production après un mois de recette sans faux positif ; politiques versionnées avec des tests (pods d'essai joués en CI sur un cluster jetable) ; alerte `TetragonProcessusTue` routée vers la sécurité **et** l'équipe de l'application.

---

### M26-E30 — Correctifs de sécurité : le parc, le cluster et les images en service

**Solution**

Fichiers : rôle [`correctifs`](fichiers/M26-E30/ansible/roles/correctifs/), [`playbooks/correctifs.yml`](fichiers/M26-E30/ansible/playbooks/correctifs.yml), [`playbooks/redemarrages-vague.yml`](fichiers/M26-E30/ansible/playbooks/redemarrages-vague.yml), [`regles/correctifs.yaml`](fichiers/M26-E30/observabilite/regles/correctifs.yaml) et ses [tests](fichiers/M26-E30/observabilite/tests/correctifs.test.yaml), [`outils/cve-en-service.sh`](fichiers/M26-E30/k8s/outils/cve-en-service.sh).

*1. Rôle* : Debian — `52medisphere-unattended-upgrades` (lu après le `50unattended-upgrades` du paquet) : origine `Debian-Security` seulement, liste noire (paquets du cluster, de la bordure, HAProxy, OpenBao, GitLab), `Automatic-Reboot "false"` ; `20auto-upgrades` ; `needrestart` en mode `l` (liste). Rocky — `dnf-automatic` : `upgrade_type = security`, `apply_updates = yes`, `reboot = never`, exclusions Ceph et FreeIPA. Partout : `correctifs-etat` (quotidien, après la mise à niveau) écrit `correctifs.prom`.

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/correctifs.yml -l durcissement_vague_1 --check --diff
admin@mon01:~$ sudo unattended-upgrade --dry-run --debug 2>&1 | grep -E 'Allowed origins|Checking|blacklist' | head
admin@ipa01:~$ sudo dnf -q updateinfo list --security --available | head
```

Pourquoi pas de dépôt tiers dans l'automatique : PowerDNS, Kea, FRR, HAProxy, Docker, GitLab… publient des versions qui changent le comportement (et certains redémarrent leur service) ; elles passent par une MR et une fenêtre de changement. Exception justifiable : un dépôt tiers qui publie un canal « sécurité » séparé.

*2. Alertes* : `min_over_time(…[7d]) == 1` pour un redémarrage attendu **sans interruption** depuis 7 jours (un hôte redémarré entre-temps ne sonne pas) ; `min_over_time(…[3d]) > 0` pour des correctifs disponibles et non installés (paquet exclu ou automatique bloqué) ; absence de vérification sur le modèle d'E24. Tests : `promtool test rules` vert (pas de 4 minutes pour une fenêtre de 7 jours : au pas d'une minute, promtool dépasse sa limite d'échantillons).

*3. Redémarrages* : le playbook calcule le besoin sur l'hôte, `serial: 1` dès la vague 4, et selon le groupe : pair VRRP actif (passerelles, répartiteurs), `drain`/`uncordon` (nœuds K8s, depuis `adm01`), `HEALTH_OK` puis `noout` (Ceph, commandes lancées depuis un **autre** nœud de la grappe), santé des deux autres nœuds d'OpenBao. `adm01` n'est jamais redémarré par lui-même. Sans `-e vague=N`, le groupe visé n'existe pas : rien n'est redémarré par oubli.

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/redemarrages-vague.yml -e vague=1 --check
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/redemarrages-vague.yml -e vague=1
```

*4. Cluster* : `kubectl version` et `kubeadm upgrade plan` (lecture) donnent la version de correctif en place et la dernière publiée ; le *changelog* de la 1.36.x liste ses correctifs de sécurité (section « Changes by Kind », CVE) ; la montée suit RB-142 (M14-E25) dans une fenêtre planifiée.

*5. Images en service* :

```
admin@adm01:~$ install -m 600 /dev/null ~/.config/workbook/harbor-vulns.env && "${EDITOR:-vi}" ~/.config/workbook/harbor-vulns.env
admin@adm01:~/src/k8s$ outils/cve-en-service.sh | head -20
== Images en service analysées par Harbor (critiques, hautes, date de l'analyse) ==
2  14  2026-10-19T03:12:40Z  dockerhub/library/postgres@…   wb-essais
0  3   2026-10-21T02:01:11Z  medisphere/mediagenda-api@…   mediagenda-prod,mediagenda-recette
…
== Images en service SANS analyse retrouvée dans Harbor (origine hors cache, ou non analysée) ==
```

L'`imageID` donne le digest réellement tiré même si le manifeste citait une étiquette ; l'API de Harbor exige le nom du dépôt **doublement** encodé (`/` → `%252F`). Le robot : droits de lecture d'artefacts seulement, dans les projets `medisphere`, `plateforme`, `bibliotheque` et les caches.

**Explications**

Trois horloges différentes : le correctif publié (jour J), installé (J+1 par l'automatique), **actif** (au redémarrage pour le noyau et les bibliothèques chargées, au redémarrage du service pour le reste : `needrestart` le dit). Les métriques rendent visible l'écart entre « installé » et « actif », qui est le vrai risque. Pour les conteneurs, l'image ne se corrige pas en place : il faut la reconstruire et la redéployer, d'où la liste par digest **en service**, pas par dépôt.

**Alternatives**
- **Reconstruire les VMs** depuis une image dorée récente au lieu de corriger en place (M03, F1) : la cible pour les nœuds K8s (immuables) ; plus difficile pour les VMs à état (GitLab, OpenBao, FreeIPA).
- **Trivy Operator** : rapports de vulnérabilités en CRD pour chaque charge, continus ; un opérateur de plus, des analyses en double avec Harbor.
- **kubescape** (`kubescape scan image`) : ponctuel, utile pour une image hors Harbor.

**Pièges classiques**
- `Automatic-Reboot "true"` : deux passerelles qui redémarrent la même nuit.
- Laisser `kubelet` ou `containerd.io` dans l'automatique : une montée de version mineure du cluster sans plan.
- Mesurer « à jour » par `apt list --upgradable` vide alors qu'un redémarrage est attendu.
- Chercher les vulnérabilités par étiquette d'image : l'étiquette a pu être réécrite, le digest non.

**En production chez MédiSphère**
Fenêtre de redémarrage mensuelle par vague, annoncée ; délai maximal par gravité (critique : 72 h ; haute : 14 jours) suivi par des alertes ; rapport mensuel « images en service » transmis aux équipes avec un ticket par image critique ; montée de correctif du cluster tous les mois.

---

### M26-E31 — ADR : la stratégie de durcissement et de détection

**Solution** : exemple complet : [`ADR-0260-durcissement-et-detection.md`](fichiers/M26-E31/medisphere/docs/securite/durcissement/adr/ADR-0260-durcissement-et-detection.md).

Ce qu'un relecteur vérifie :
- chaque couche a de **vraies** options (pas une option « retenue » contre deux épouvantails), comparées sur des critères explicites et pondérés par le contexte (mémoire du lab, taille de l'équipe, souveraineté) ;
- les faits récents sont exacts et sourcés : `ClusterPolicy` dépréciée en Kyverno 1.19 et supprimée en 1.20 ; IPsec incompatible avec le pare-feu d'hôte (*known issues* de Cilium 1.20) ; chiffrement nœud à nœud en *beta* ; Wazuh trop lourd (OpenSearch) pour la marge mémoire ;
- chaque conséquence négative a une action datée ou une acceptation signée ;
- les conditions de révision sont observables (un score, un nombre d'alertes, une version publiée).

**Explications** : un ADR de stratégie couvre plusieurs couches ; le risque est le catalogue. Une table par couche et une seule section de conséquences gardent le document lisible ; le détail technique reste dans les fiches (`chiffrement.md`, `conformite-continue.md`, RB-264).

**Pièges classiques** : comparer des versions ou des licences de mémoire ; oublier le coût d'exploitation (le vrai coût de la sécurité est humain) ; ne pas écrire ce qu'on **n'a pas** fait (sorties des nœuds, *k8saudit*, mode strict).

**En production chez MédiSphère** : ADR relu à chaque revue de sécurité annuelle et après chaque incident ; annexe « matrice de couverture » (menaces d'E02 × contrôles) tenue à jour.

---

### M26-E32 — Questions de production : sécurité

**1. 300 alertes par jour dont 290 faux positifs.** Problème de sécurité : la vraie alerte se noie, l'astreinte apprend à ignorer (et finit par couper la règle) — c'est le mécanisme de la plupart des intrusions « détectées mais pas vues ». Dans l'ordre : classer les 290 par règle et par source (trois règles font souvent 90 %) ; pour chaque règle, corriger la cause (une charge légitime mal écrite), sinon une **exception ciblée** (macro Falco sur l'image et le processus, datée, RB-261), jamais la suppression de la règle ; baisser la priorité de ce qui n'appelle pas d'action (journal, pas courriel) ; mesurer le bruit chaque semaine. Augmenter le seuil global (`minimum_priority`) est la mauvaise réponse : on perd aussi les vraies alertes de cette priorité.

**2. Règle passée en `Deny` qui bloque la production un vendredi soir.** Options : (a) corriger la charge pour qu'elle respecte la règle ; (b) une `PolicyException` étroite (cette ressource, cet espace, expiration courte) ; (c) repasser la règle en `Audit` par MR (ou suspendre son application). Choix selon la règle : une règle de **sécurité dure** (signature d'image, privilégié) → jamais (c) ; (b) seulement si la RSSI l'accepte, sinon le déploiement attend lundi. Une règle d'**hygiène** (limites, étiquettes) → (b) ou (c) tout de suite, (a) lundi. Dans tous les cas : écrit, daté, et la question « pourquoi la règle est-elle passée en `Deny` sans période d'audit propre ? ».

**3. « 92 % CIS ».** (1) Le score ne porte que sur ce que le référentiel mesure (configuration de l'hôte), pas sur les applications, les identités, le réseau, la chaîne d'approvisionnement ; (2) les exceptions sont sorties du calcul : un 92 % avec vingt exceptions larges vaut moins qu'un 85 % sans ; (3) c'est une photo hebdomadaire d'un état, pas une preuve de détection ni de réponse (un attaquant sur un hôte conforme reste un attaquant). Aussi : le score pondère les règles, toutes les règles ne se valent pas.

**4. CVE noyau : correctif + redémarrage vs reconstruction.** Correctif en place : rapide, outillé (E30), mais chaque nœud dérive de son image d'origine. Reconstruction depuis une image dorée corrigée : nœuds immuables et identiques, retour arrière simple (ancienne image), preuve d'état facile — c'est la cible. Ce qui manque aujourd'hui : un pipeline d'images dorées pour les nœuds qui produit et teste une image en quelques heures (M03 pour les VMs, M18 pour image-builder), le remplacement de nœud automatisé (Cluster API, M18, n'est pas le mode de `k8s-par1`) et du temps de recette.

**5. Conteneur ≠ VM.** Un conteneur partage le noyau de l'hôte : une faille du noyau (ou un réglage permissif : capacité, montage, socket du runtime) suffit à en sortir ; une VM passe par l'hyperviseur, une surface bien plus petite. Rapprochements : **gVisor** (noyau en espace utilisateur qui intercepte les appels système : isolation forte, coût en performance et en compatibilité d'appels système) ; **Kata Containers** (une micro-VM par pod : isolation d'une VM, coût mémoire et temps de démarrage, virtualisation imbriquée dans notre lab).

**6. Pod compromis vers etcd.** Dans l'ordre du paquet : (1) politique réseau de sortie du pod (refus par défaut de l'espace, `isolement-*` de cluster, M15-E28) ; (2) pare-feu d'hôte du nœud de contrôle : 2379 n'est autorisé que depuis `kube-apiserver` ; (3) etcd exige un certificat client signé par `etcd-ca`, que le pod n'a pas ; (4) Falco/Tetragon voient la tentative de connexion (`connexions-sortantes`). Avant même le réseau : PSA `restricted` et Kyverno empêchent que le pod ait les privilèges qui faciliteraient l'évasion.

**7. Preuve de durcissement continu sur six mois.** Les ARF et rapports hebdomadaires du compartiment `conformite` (versionné, trois ans) ; la série du score dans Thanos (2 ans, résolution 1 h) ; le registre des exceptions et son historique Git (qui a signé quoi, quand) ; les MR du rôle `durcissement` ; les alertes `ConformiteDegradee` et leur traitement (tickets). Confiance : forte pour la mesure (outil standard, contenu public, preuves règle par règle), à nuancer par ce que le référentiel ne mesure pas et par l'identité partagée d'écriture (versionnage, comparaison des séries).

**8. Tetragon tue un processus en recette.** Ne pas toucher la politique d'abord : lire l'événement complet (binaire, parent, argument, image, conteneur), reproduire le geste, demander à Julien ce que le processus devait faire. Si c'est l'application qui écrit dans `/etc` ou exécute depuis `/tmp` : défaut de l'image (E21) → corriger l'image. Si la politique est trop large : MR qui la resserre (chemin exact plutôt que préfixe), tests positifs dans `wb-essais`. Si c'est une tentative réelle : RB-262. En attendant : arrêt d'urgence si la recette est bloquée (RB-260), jamais suppression silencieuse.

**9. Exception documentée vs codée.** Documentée (registre, justification, risque, compensation, valideur, date de revue) : c'est la décision et sa responsabilité. Codée (`durcissement_exceptions`, `PolicyException`, macro Falco) : c'est ce qui fait que l'outil cesse de signaler l'écart. Sans la première, une exception codée est une porte dérobée ; sans la seconde, l'écart accepté reste une alerte permanente que tout le monde apprend à ignorer. Les deux viennent de la même MR, et le check du mini-projet les compare.

**10. Image malveillante malgré la signature.** (1) Clé de signature volée (variable de CI, poste) → signature valide : clé dans `transit` d'OpenBao (M25), signature seulement par le runner protégé ; (2) dépendance malveillante **dans** l'image construite et signée par nous (typosquattage) → SBOM, analyse Trivy, Renovate relu, pas de couverture par la signature ; (3) image de **base** compromise en amont (cache Harbor) → épinglage par digest, reconstruction des bases (`bibliotheque`) ; (4) espace non couvert par la politique (un espace sans l'étiquette visée, `wb-*`) ou exception trop large → périmètre de la politique revu, PSA ; (5) pipeline compromis (job qui signe autre chose) → runner protégé, provenance (attestations) en cible.

**11. `failurePolicy` du webhook de signature.** `Ignore` : si Kyverno est indisponible (mise à jour, panne, attaque par saturation), **toute** image passe sans vérification : la règle de sécurité devient optionnelle. `Fail` : si Kyverno est indisponible, plus rien ne se déploie dans les espaces visés (recette, prod) ; c'est pourquoi l'exclusion de `kube-system`, `kyverno`, `argocd`, `cilium` et trois réplicas du contrôleur d'admission sont indispensables. MédiSphère : `Fail` pour la signature en recette/prod, `Ignore` pour l'hygiène.

**12. SSH durci casse un outil de supervision.** Les deux : le durcissement avait raison sur le fond (accès par groupe, algorithmes modernes), l'outil avait un accès réel et légitime non inventorié. Prévention : inventaire des accès SSH automatisés avant la vague (journaux `sshd` : qui se connecte avec quoi), compte de service dans un groupe autorisé et clé moderne, vague 1 sur des VMs où ces outils passent, et l'outil passé en métriques (node_exporter) plutôt qu'en SSH.

**13. Audit et Falco sur `exec`.** L'audit voit la **demande** à l'API (qui, quand, quel pod, quelle commande initiale) et rien de ce qui se passe ensuite dans le shell ; Falco voit les **processus** dans le conteneur (shell lancé, commandes, fichiers lus), mais pas qui l'a demandé. Un shell obtenu sans `kubectl exec` (évasion, processus lancé par l'application compromise) n'apparaît que dans Falco ; un `exec` qui n'a lancé qu'une commande anodine n'est que dans l'audit. La corrélation des deux (horodatage, pod) donne l'histoire complète.

**14. Rythme hebdomadaire.** Une analyse dure plusieurs minutes et charge l'hyperviseur : quotidienne, elle coûte sept fois plus pour un changement de configuration qui, chez nous, passe par une MR et des vagues (la dérive est rare et lente) ; mensuelle, une dérive resterait un mois sans être vue et l'auditeur n'aurait que douze points par an. Changeraient le rythme : des changements manuels fréquents (passer en quotidien sur les hôtes concernés), une exigence contractuelle, ou une détection de dérive en temps réel par un autre moyen (AIDE, auditd, E12) qui rendrait l'analyse complète moins urgente.

---

### M26-E33 — Préparer la réponse à incident

Exercice `LIBRE` : la solution ci-dessous est **une** solution acceptable, pas la seule.

**Solution**

Fichiers : [politique `quarantaine`](fichiers/M26-E33/k8s/composants/reseau/politiques/quarantaine.yaml), [compartiment `preuves`](fichiers/M26-E33/ansible/inventories/lab/host_vars/s3-01/seaweedfs.yml.extrait), [RB-262](fichiers/M26-E33/medisphere/docs/securite/durcissement/runbooks/RB-262-reponse-incident-conteneur.md), [compte rendu d'exercice sur table](fichiers/M26-E33/medisphere/docs/securite/durcissement/rapports/AAAA-MM-JJ-exercice-sur-table-RB-262.md), [pod de test](fichiers/M26-E33/essais/pod-suspect.yaml).

- **Isolement** : une `CiliumClusterwideNetworkPolicy` de **refus** (`ingressDeny`, `egressDeny`) — un refus l'emporte sur toute autorisation, y compris les politiques des équipes ; une politique « vide » ne suffirait pas (les autorisations s'additionnent). Toute entrée est refusée **sauf** l'hôte local (les sondes du kubelet : une sonde de vivacité qui échoue relancerait le conteneur et détruirait les preuves en mémoire) ; toute sortie est refusée. Le pod est ensuite **sorti de son contrôleur** (une étiquette du sélecteur retirée) : le ReplicaSet recrée un pod sain, le suspect reste en vie, isolé, hors du Service. `exec`, `debug` et `logs` passent par le kubelet et l'API, pas par le réseau du pod : la collecte reste possible.
- **Collecte** : du plus volatil au plus durable (processus et connexions par un conteneur éphémère `--target`, fichiers déposés lus par `/proc/1/root`, journaux, événements Falco/Tetragon/audit exportés de Loki, flux Hubble — tampon limité : tôt —, *checkpoint* si disponible, instantané PBS du nœud), empreintes SHA-256, dépôt dans `preuves/INC-NNNN/<horodatage>/` par l'identité `preuves-depot` (écrire, lister, jamais supprimer), compartiment versionné. Verrouillage d'objet S3 : à vérifier dans la documentation de la version de SeaweedFS du lab ; à défaut, compensation écrite (versionnage, empreintes dans le ticket et le journal Git, copie PBS).
- **Rôles et obligations** : RB-262 §1 et §7 (RGPD art. 33 : 72 heures pour la CNIL ; art. 34 : information des personnes si risque élevé ; contrat HDS ; signalement des incidents graves de sécurité des systèmes d'information de santé, art. L.1111-8-2 du code de la santé publique) — délais à faire confirmer par le DPO.
- **Essai** sur `wb-essais/suspect` (annexe de RB-262) : quarantaine, refus constatés dans les deux sens, `restartCount` inchangé après une minute, sortie du ReplicaSet, nettoyage.
- **Exercice sur table** : scénario écrit à l'avance avec des injections (lecture d'un Secret, signal métier qui fait basculer vers la violation de données), chronologie, écarts au runbook, actions datées.

**Explications**

La réponse à incident se prépare comme une sauvegarde : un outil posé à l'avance et testé (la politique de quarantaine), une procédure écrite à partir de gestes réellement exécutés, une répétition. Le conflit central est entre **préserver** (preuves, compréhension, obligations légales) et **rétablir** (service) : sortir le pod suspect de son contrôleur résout ce conflit pour un Deployment, puisque le service est rétabli par un pod neuf pendant que le suspect est conservé.

**Alternatives**
- Isoler par une `NetworkPolicy` d'espace : levable par l'équipe (ses propres politiques d'autorisation s'additionnent) ; ne vaut pas une politique de refus de cluster.
- Isoler le **nœud** (`cordon`, pare-feu d'hôte) : nécessaire si l'évasion du conteneur est probable ; beaucoup plus coûteux (toutes les charges du nœud).
- Supprimer le pod tout de suite : rétablit vite, détruit tout ; acceptable seulement si la menace est active et non contenue.

**Pièges classiques**
- Quarantaine qui bloque les sondes de vivacité : le conteneur redémarre, les preuves volatiles disparaissent.
- Oublier que le contrôleur garde le pod suspect dans le Service (trafic des utilisateurs vers un pod compromis isolé = erreurs).
- Installer des outils dans le conteneur suspect (`apt install tcpdump`) : on modifie la scène.
- Collecter sans empreinte ni horodatage : la pièce ne vaut plus rien devant un tiers.
- Argo CD qui élague le pod orphelin pendant la collecte.

**En production chez MédiSphère**
Exercice sur table deux fois par an, exercice réel une fois (M26-E42, F6) ; contrat avec un prestataire de réponse à incident (PRIS qualifié par l'ANSSI) pour les cas graves ; procédure de gel GitOps pendant un incident ; journal d'incident modèle prêt.

---

### M26-E34 — Audit de conformité en temps limité

Exercice `CHRONO` : **pas de corrigé**, par construction. Le check vérifie la présence, la date, la structure du rapport et la cohérence des scores cités avec les métriques. Le retour d'expérience compte autant que le rapport : il doit déboucher sur un ajout concret (une requête enregistrée, un panneau du tableau « Conformité », un script de synthèse des `PolicyReport`).
