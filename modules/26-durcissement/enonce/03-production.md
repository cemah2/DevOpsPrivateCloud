# Module 26 — Palier 3 : Production

Les paliers 1 et 2 ont posé les briques : un rôle `durcissement` appliqué au socle par vagues, des exceptions écrites, une admission Kyverno qui refuse ce qui n'est pas conforme, Falco et Tetragon qui regardent les processus. Rien de tout cela n'est encore **de production**. La mesure de conformité a été faite une fois, à la main, et personne ne saura si une VM dérive dans trois mois. Les kubelets ont des certificats signés, mais quelqu'un doit approuver chaque demande, chaque année, à la main. Les pods se parlent chiffrés depuis le M15, les nœuds non. Les nœuds eux-mêmes acceptent toute connexion que le pare-feu de la bordure laisse passer, et tout le VLAN 40 se voit. Le journal d'audit de l'API est conservé, mais rien n'y cherche ce qui compte. Tetragon voit, mais n'empêche rien. Les correctifs de sécurité dépendent de la mémoire de chacun. Ce palier fait passer la sécurité en production : **conformité mesurée chaque semaine**, **kubelets** à certificats approuvés par une règle, **chiffrement** étendu aux nœuds, **pare-feu d'hôte** de Cilium, **audit** revisité, **Tetragon en application**, **correctifs** suivis, puis l'ADR, les questions de production, la préparation de la réponse à incident et un audit de conformité chronométré.

> ⚠️ **Rappel** : trois exercices de ce palier peuvent **couper le cluster** ou une partie du socle : le chiffrement entre nœuds (E26), le pare-feu d'hôte (E27) et l'application de Tetragon (E29) ; deux autres redémarrent des composants du plan de contrôle (E25, E28). Avant chacun : (1) une sauvegarde PBS récente des nœuds de `k8s-par1` (`par1/k8s`) et un instantané etcd vérifié (RB-141) ; (2) la console Proxmox de **chaque** nœud ouverte et testée (identifiant `admin` local, mot de passe du bris de glace : la console ne dépend ni du réseau ni de SSSD) ; (3) `admin.conf` déchiffré dans un fichier temporaire 600 (bris de glace, M24), au cas où l'OIDC ne répondrait plus ; (4) un seul nœud à la fois, et l'état du cluster vérifié entre deux nœuds (`kubectl get nodes`, `cilium status`, le Watchdog de M21, le témoin de `mon01`). Nadia Roussel l'a écrit au début du module : le durcissement ne doit pas casser l'astreinte.

**Chemin imposé** (introduction du module) : le rôle `durcissement` et les rôles de VMs dans `plateforme/ansible` (pipeline protégé de la forge ou `adm01`, toujours `--check --diff` d'abord) ; la configuration du cluster (`cluster/kubeadm-config.yaml`, `composants/cilium/values.yaml` sous Helmfile, `composants/`, `espaces/`, `cluster/noeuds.yaml`) dans `plateforme/k8s` ; les politiques Kyverno, règles Falco et `TracingPolicy` dans `plateforme/politiques` (Application Argo CD `politiques`) ; les composants tiers par Argo CD depuis Harbor (`plateforme/charts-miroir`) ; les règles d'alerte dans `plateforme/observabilite` (`regles/` pour Prometheus, `loki/regles/<locataire>/` pour Loki) ; la documentation dans `docs/securite/durcissement/` de `plateforme/medisphere` (`adr/`, `runbooks/`, `rapports/`) ; les flux de la bordure dans `group_vars/role_routeur/pare_feu.yml` et `docs/socle/matrice-flux.md`, ceux du cluster dans `docs/kubernetes/reseau/matrice-flux-cluster.md`. Tout passe par une MR relue.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Conformité continue (E24) | Minuterie `conformite-analyse.timer` (dimanche 03:30, décalage aléatoire de 30 min), service `conformite-analyse.service`, script `/usr/local/sbin/conformite-analyse` posés par le rôle `durcissement` ; paramètres dans `/etc/conformite/conformite.env` (644), identifiants S3 dans `/etc/conformite/s3.env` (600, `root`) ; compartiment **`conformite`** de `s3-01` (`https://s3-01.par1.medisphere.internal:8333`), identité d'écriture **`conformite`** (VMs), identité de lecture **`conformite-lecture`** (`~/.config/workbook/s3-conformite.env` sur `adm01`) ; objets `AAAA-MM-JJ/<hôte>/…` |
| Métriques de conformité | Fichier `conformite.prom` du collecteur *textfile* : `/var/lib/prometheus/node-exporter/` (rôle `node_exporter` du M21 sur les VMs ; même chemin monté dans le DaemonSet node-exporter de `kps` pour les nœuds de `k8s-par1`) ; séries `medisphere_conformite_score{referentiel}`, `medisphere_conformite_regles{referentiel,resultat}`, `medisphere_conformite_derniere_analyse_secondes{referentiel}`, `medisphere_lynis_indice` ; `referentiel` = `cis_l1_serveur` ou `anssi_intermediaire` ; règles `plateforme/observabilite/regles/conformite.yaml` (PrometheusRule `conformite`) |
| Kubelets (E25) | `serverTLSBootstrap: true` depuis M14-E26 ; ajout de `seccompDefault: true` (`KubeletConfiguration` de `cluster/kubeadm-config.yaml`, ConfigMap `kube-system/kubelet-config`, playbook `playbooks/k8s-kubelet-config.yml`) ; **kubelet-csr-approver 1.2.15** (chart `kubelet-csr-approver` 1.2.15 recopié dans Harbor `charts/`, image `registry.par1.medisphere.internal/ghcr/postfinance/kubelet-csr-approver:v1.2.15`), Application Argo CD `kubelet-csr-approver`, espace `kubelet-csr-approver` |
| Cilium (E26, E27) | 1.20, release Helmfile **`cilium`** (`releases/10-reseau.yaml.gotmpl`, values `composants/cilium/values.yaml`, `helmfile -e par1 -l composant=cilium diff/apply`) ; routage **tunnel VXLAN** (UDP 8472) ; WireGuard **entre pods** depuis M15-E24 (UDP 51871, interface `cilium_wg0`) ; `kubeProxyReplacement: true` ; mise à jour des agents un nœud à la fois (`updateStrategy.rollingUpdate.maxUnavailable: 1`) ; `rollOutCiliumPods: false` (redémarrage volontaire : `kubectl -n kube-system rollout restart ds/cilium`) |
| Pare-feu d'hôte (E27) | Politiques `CiliumClusterwideNetworkPolicy` à `nodeSelector` dans **`plateforme/k8s/composants/cilium/hote/`** : `hote-commun`, `hote-plan-controle`, `hote-travailleurs` ; elles ne sélectionnent que les nœuds étiquetés **`medisphere.internal/pare-feu-hote: "oui"`** (étiquette gérée par `cluster/noeuds.yaml`) ; outil `outils/pare-feu-hote.sh` ; runbook **RB-264** |
| Nœuds et adresses | `k8s-cp01-03` 10.10.40.51-53 (keepalived **VRRP v3 unicast**, VRID 140, VIP 10.10.40.200, HAProxy 8443 → kube-apiserver 6443) ; `k8s-w01-03` 10.10.40.61-63 (+ `eth1` VLAN 30, 10.10.30.81-83, MTU 9000) ; bordure `gw01` 10.10.40.2, `gw02` 10.10.40.3 (BGP 179, AS 65000 ↔ 65040) ; MGMT 10.10.10.0/24 ; `mon01` 10.10.20.19 ; `vault01-03` 10.10.20.21-23 (authentification `k8s-par1` d'OpenBao : API par la VIP:8443) |
| Audit (E28) | Politique `/etc/kubernetes/audit/politique.yaml` (rôle `k8s_audit`, M14-E27), lue **au démarrage** du serveur d'API ; journal collecté par Alloy (`{job="kubernetes-audit"}`, locataire Loki **`audit`**, métadonnées structurées `verb`, `user`, `code`, `resource`, `object_ns`, `object_name`) ; règles du ruler dans `plateforme/observabilite/loki/regles/audit/` |
| Tetragon (E29) | 1.7, espace `tetragon` ; politiques dans `plateforme/politiques/tetragon/` (observation : `observer-exec`, `fichiers-sensibles`, `connexions-sortantes`, E20) ; application dans **`tetragon/application/`** ; événements vers Loki `audit` (`service="tetragon"`) |
| Correctifs (E30) | Rôle **`correctifs`** de `plateforme/ansible` ; métriques `medisphere_redemarrage_requis`, `medisphere_correctifs_securite_en_attente`, `medisphere_correctifs_derniere_verification_secondes` (fichier `correctifs.prom`) ; règles `regles/correctifs.yaml` ; outil `plateforme/k8s/outils/cve-en-service.sh` |
| Réponse à incident (E33) | Étiquette **`medisphere.internal/quarantaine: "oui"`**, politique de cluster **`quarantaine`** posée à l'avance ; compartiment **`preuves`** de `s3-01` ; runbook **RB-262** |
| Documentation | `docs/securite/durcissement/` : `conformite-continue.md` (E24), `adr/ADR-0260-durcissement-et-detection.md` (E31), `runbooks/RB-262-reponse-incident-conteneur.md` (E33), `runbooks/RB-264-pare-feu-hote-cilium.md` (E27), `rapports/` (E24, E34) ; `docs/kubernetes/reseau/chiffrement.md` (M15, mis à jour en E26) |

> ⚠️ **Mémoire** : le profil du bloc F occupe déjà ≈ 111 Go sur 128 Go. Les VMs d'essai `durci-deb`/`durci-rocky` doivent être détruites (fin d'E14). Ce palier n'ajoute aucune VM ; les analyses OpenSCAP d'E24 consomment de la mémoire et du processeur **sur chaque VM en même temps** si tu les lances toutes à la main : passe par la minuterie (décalage aléatoire) ou par lots de trois. Arrête ce qui ne sert pas (OpenSearch, Jaeger et autres essais des modules précédents doivent déjà être retirés).

**Ordre conseillé** : E24 → E25 → E26 → E27 → E28 → E29 → E30 → E31 → E32 → E33 → E34. La conformité continue (E24) vient d'abord : elle mesure tout ce qui suit et l'audit chronométré (E34) s'en sert. Les kubelets (E25) précèdent le chiffrement et le pare-feu : un nœud qui redémarre doit retrouver seul son certificat de service. Le chiffrement entre nœuds (E26) précède le pare-feu (E27) : tu lis les refus du pare-feu avec le trafic définitif. **Durée totale indicative** : 25 à 28 h.

Les vérifications se lancent **depuis `adm01`** (`lab/bin/check 26 XX`). Variables facultatives de `lab/lab.env` : `WB_M26_S3_URL` (défaut `https://s3-01.par1.medisphere.internal:8333`), `WB_M26_S3_CONFORMITE_FILE` (défaut `~/.config/workbook/s3-conformite.env`), `WB_M26_VMS_ECHANTILLON` (VMs dont le check lit l'état par SSH, défaut `mon01 nbx01 dns02 ipa01`).

---

### M26-E24 — Conformité continue : analyses hebdomadaires, rapports, alertes  `LAB` `★★★`

> **Ticket SEC-2724** — *De : Sophie Laurent* — *Copie : Claire Morel*
> L'auditeur HDS ne me demandera pas « êtes-vous conformes ? », il me demandera « montrez-moi votre mesure de la semaine dernière, et celle d'il y a trois mois ». Aujourd'hui j'ai un rapport HTML fait à la main en E14.
> Je veux une analyse OpenSCAP **chaque semaine sur chaque machine**, avec nos exceptions appliquées, des rapports conservés hors des machines, un score que je vois dans Grafana, et une alerte quand une machine dérive ou ne s'est pas analysée.

**Objectifs pédagogiques**
- Industrialiser une mesure de conformité : planification, profil adapté (*tailoring*) qui reflète les exceptions, résultats normalisés (ARF), conservation hors de l'hôte.
- Transformer un résultat d'outil en métriques exploitables (collecteur *textfile*) et écrire des alertes de dérive et d'absence de mesure, testées.
- Mesurer sans gêner : coût d'une analyse, étalement dans le temps, identité de dépôt aux droits minimaux.

**Prérequis** : M26-E04 (OpenSCAP, ComplianceAsCode 0.1.82), M26-E10 et E14 (rôle `durcissement`, *tailoring*, vagues), M26-E23 (registre des exceptions), M26-E03 (Lynis), M21-E08 (rôle `node_exporter`), M21-E15 (règles d'alerte et tests `promtool`), M05-E10 (identités SeaweedFS).
**Durée indicative** : 3 h 30.

**Contexte technique**
- **Lecture** : `oscap xccdf eval --help` (options `--profile`, `--tailoring-file`, `--results-arf`, `--report`) et le [manuel d'OpenSCAP](https://static.open-scap.org/openscap-1.3/oscap_user_manual.html) (codes de sortie : 0 tout passe, 2 au moins une règle échoue, 1 erreur) ; [collecteur textfile de node_exporter](https://github.com/prometheus/node_exporter#textfile-collector) (écriture **atomique** : fichier temporaire puis renommage) ; `man systemd.timer` (`RandomizedDelaySec`, `Persistent`).
- Le contenu ComplianceAsCode est déjà déplié par le rôle (`/usr/local/share/scap/ssg-0.1.82/`) avec le profil adapté généré à partir de `durcissement_exceptions` (E10). Les identifiants de profils et le nom du *datastream* Rocky sont ceux que tu as relevés en E04 et consignés dans `referentiels.md`.
- Une analyse CIS dure plusieurs minutes et occupe un cœur ; le rapport HTML pèse plusieurs mégaoctets (compresse-le). Vingt-cinq VMs et six nœuds sur un seul hyperviseur : un dimanche à 03:30 pile, tout le monde en même temps, c'est une crête de charge sur `pve01`.
- Envoi vers `s3-01` **sans** AWS CLI sur les VMs : `curl --aws-sigv4 "aws:amz:us-east-1:s3"` (curl 8 de Debian 13 et Rocky 10), identifiants lus dans un fichier de configuration de curl (`-K`), jamais sur la ligne de commande. Les identités SeaweedFS se déclarent dans `host_vars/s3-01/seaweedfs.yml` (rôle `seaweedfs`, M05) : actions limitées à un compartiment (`Write:conformite`, `List:conformite`…).
- Nœuds de `k8s-par1` : node_exporter y est le DaemonSet de `kps` (espace `supervision-noeuds`), pas le rôle du M21. Lis les clés `extraArgs` et `extraHostVolumeMounts` du sous-chart `prometheus-node-exporter` : remplacer `extraArgs` **remplace** la liste par défaut du chart.
- Rocky 10 (`ipa01`, `ceph01-03`) : SELinux *enforcing* ; si node_exporter ne lit pas le fichier, lis les refus (`ausearch -m AVC -ts recent`) avant de toucher quoi que ce soit (E13).

> ⚠️ **Attention** : (1) le service d'analyse lit tout le système en `root` : il ne doit **rien** modifier (aucune remédiation, jamais `--remediate`) ; teste-le d'abord sur une VM de la vague 1 (`mon01`) en le lançant à la main, mesure sa durée et sa mémoire ; (2) une identité S3 partagée par toutes les VMs est un secret présent partout : droits d'écriture et de listage sur le seul compartiment `conformite`, rien d'autre ; (3) retour arrière : `durcissement_conformite_continue_actif: false` dans les variables et rejouer le rôle (minuterie désactivée, rien d'autre ne change).

**Travail demandé**
1. **Conception.** Dans `docs/securite/durcissement/conformite-continue.md` : ce qui est mesuré (référentiels, profil adapté, Lynis), quand, où vont les résultats, combien de temps on les garde, qui peut les lire, quelles métriques, quelles alertes et leurs seuils. Réponds aussi : pourquoi un score qui ne bouge pas peut cacher une dérive ? Pourquoi garder l'ARF et pas seulement le score ?
2. **Stockage.** Compartiment `conformite` (versionné) et identités `conformite` (écriture et listage) et `conformite-lecture` (lecture et listage) sur `s3-01`, secrets en Vault `critique` ; identifiants de lecture dans `~/.config/workbook/s3-conformite.env` (600).
3. **Analyse.** Dans le rôle `durcissement` (fichier de tâches dédié, inclus par `main.yml`, activé par une variable) : paquets nécessaires, `/etc/conformite/` (paramètres et identifiants), le script `/usr/local/sbin/conformite-analyse` et ses unités systemd. Le script, pour chaque référentiel : `oscap xccdf eval` avec le profil adapté, ARF et rapport HTML compressés, envoi vers `conformite/<date>/<hôte>/`, métriques écrites atomiquement ; puis Lynis (indice) ; un code de sortie non nul si l'analyse elle-même a échoué (pas si des règles échouent). L'unité : priorité basse (processeur et disque), limites de ressources, journal dans journald.
4. **Essai.** Sur `mon01` : `--check --diff`, application, lancement à la main (`systemctl start conformite-analyse.service`), durée, objets dans le compartiment, `curl` local sur node_exporter : les séries `medisphere_conformite_*` apparaissent.
5. **Déploiement.** Par les vagues d'E14 (même inventaire), puis les nœuds de `k8s-par1` : le DaemonSet node-exporter de `kps` lit le même dossier (values dans `plateforme/observabilite`, MR). Vérifie dans Thanos Query qu'**aucune** VM du socle ni aucun nœud ne manque.
6. **Alertes.** `regles/conformite.yaml` : au moins **`ConformiteDegradee`** (le score d'un hôte baisse de plus de 5 points en une semaine), **`ConformiteSousObjectif`** (score sous l'objectif fixé en E23, 85 % par défaut), **`ConformiteAnalyseAbsente`** (un hôte supervisé sans analyse depuis plus de 8 jours, y compris un hôte qui n'a **jamais** produit la métrique). Étiquettes `gravite`, `equipe` ; annotations avec `runbook_url`. Tests `promtool` (dont le cas « hôte jamais analysé »). Pipeline vert.
7. **Tableau.** Un tableau Grafana « Conformité » (dossier « Sécurité », provisionné depuis `plateforme/observabilite/tableaux/` comme ceux du M21) : score par hôte et par référentiel, évolution sur 90 jours, règles en échec, âge de la dernière analyse.

**Critères de réussite**
- [ ] `conformite-analyse.timer` est actif sur chaque VM du socle et chaque nœud de `k8s-par1`, avec un décalage aléatoire ; aucun hôte n'a d'analyse de plus de 8 jours.
- [ ] Thanos Query renvoie `medisphere_conformite_score` pour les deux référentiels sur tous les hôtes supervisés (VMs du socle et nœuds) ; `medisphere_lynis_indice` aussi.
- [ ] Le compartiment `conformite` contient, pour chaque hôte, un ARF et un rapport HTML de moins de 8 jours ; l'identité de lecture ne peut pas écrire ; `/etc/conformite/s3.env` est en 600 sur les VMs.
- [ ] Les trois alertes imposées sont chargées par Prometheus ; leurs tests sont dans `tests/` ; `conformite-continue.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 26 24`

<details><summary>Indice 1</summary>

Le score et les comptes se lisent dans l'ARF (XML) : l'élément `score` du `TestResult` et les `rule-result/result`. `xmllint --xpath` sait compter (`count(…)`) sans dépendre des espaces de noms XML si tu passes par `local-name()`. Une règle « notselected » n'est pas une règle « notapplicable ».
</details>

<details><summary>Indice 2</summary>

Une alerte d'absence ne peut pas se fonder sur la seule métrique d'âge : un hôte qui n'a jamais été analysé n'a **pas** de série. Pars de ce qui prouve qu'un hôte existe et est supervisé (`up` de ses node_exporter) et retire ceux qui ont la série (`unless on (instance)`). Vérifie que les deux côtés portent la même étiquette `instance`.
</details>

<details><summary>Indice 3</summary>

« 403 » de `s3-01` : l'action déclarée n'est pas la bonne (l'envoi d'un objet demande `Write:conformite`), ou l'horloge de la VM est fausse (la signature SigV4 porte l'heure). « 0 octet » dans le compartiment : `curl --upload-file` avec un fichier vide parce que la compression a écrit ailleurs.
</details>

**Pour aller plus loin** (facultatif) : signer les rapports (empreinte du lot de la semaine signée avec la clé `transit` d'OpenBao) pour les rendre opposables ; remonter les règles en échec dans NetBox (champ personnalisé par VM) ; comparer avec l'opérateur Compliance d'OpenShift (`compliance-operator`), qui fait la même chose dans le cluster.

---

### M26-E25 — Kubelets : certificats de service et approbation des CSR  `LAB` `★★★`

> **Ticket PLAT-2725** — *De : Karim Benali* — *Copie : Sophie Laurent*
> Depuis le M14, les kubelets ont des certificats de service signés, très bien. Sauf que quelqu'un doit lire et approuver six demandes par an, plus une à chaque nœud reconstruit, et le jour où personne ne le fait, `kubectl logs` tombe en panne. Et Prometheus collecte toujours les kubelets sans vérifier leur certificat : c'est écrit noir sur blanc dans `securite.md` du M21.
> Je veux une approbation **automatique mais contrôlée**, la vérification TLS partout où c'est possible, et le profil seccomp par défaut sur tous les pods.

**Objectifs pédagogiques**
- Comprendre ce que l'approbation d'une demande `kubernetes.io/kubelet-serving` affirme, et ce qu'un approbateur automatique doit vérifier pour ne pas devenir une faille.
- Déployer kubelet-csr-approver par GitOps et le régler à la topologie réelle (noms, réseaux, DNS).
- Rendre la vérification TLS des kubelets effective chez leurs clients (metrics-server, Prometheus).
- Activer `seccompDefault` sans casser les charges, un nœud à la fois.

**Prérequis** : M14-E26 (certificats des kubelets, RB-143, `playbooks/k8s-kubelet-config.yml`), M21-E02 et E29 (`kps`, `securite.md`), M20-E13 (`charts-miroir`), M26-E06 (PSA).
**Durée indicative** : 2 h 30.

**Contexte technique**
- **Lecture** : le [README de kubelet-csr-approver](https://github.com/postfinance/kubelet-csr-approver/blob/v1.2.15/README.md) (section des contrôles et du modèle de menace) et son `values.yaml` 1.2.15 ; [Certificate Signing Requests](https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/) ; [seccomp, `seccompDefault`](https://kubernetes.io/docs/tutorials/security/seccomp/#enable-the-use-of-runtimedefault-as-the-default-seccomp-profile-for-all-workloads).
- Les demandes de service des kubelets contiennent un nom DNS (le nom **court** du nœud) et une adresse IP (VLAN 40). Lis-en une (M14-E26) avant d'écrire la configuration de l'approbateur.
- Contraintes de Sophie : noms acceptés **seulement** `k8s-cp0N` et `k8s-w0N` ; adresses **seulement** du VLAN 40 ; durée maximale ≤ celle de kubeadm ; la résolution DNS reste un contrôle tant qu'elle fonctionne (si tu la contournes, justifie-le).
- Collecte des kubelets par `kps` : section `kubelet.serviceMonitor.tlsConfig` des values (le chart pose `insecureSkipVerify: true` par défaut ; il connaît déjà la ConfigMap `kube-root-ca.crt`). Prometheus contacte les kubelets **par adresse IP**.
- `seccompDefault: true` applique `RuntimeDefault` aux conteneurs qui ne déclarent pas de profil ; les conteneurs **privilégiés** n'en reçoivent pas.

> ⚠️ **Attention** : (1) avant de retirer l'approbation à la main, vérifie que l'approbateur approuve **réellement** (fais-lui traiter une vraie demande) ; un approbateur qui refuse tout laisse les nœuds sans certificat de service à leur prochain renouvellement : `kubectl logs`/`exec` et la collecte tombent ; (2) `seccompDefault` se change **un nœud à la fois** (`cordon`/`drain`, playbook, `uncordon`) : un pod qui fait un appel système refusé meurt au démarrage ; (3) retour arrière : `seccompDefault: false` et rejouer le playbook ; l'approbateur se met à 0 réplica par Git, l'approbation manuelle (RB-143 §5) reste possible.

**Travail demandé**
1. **Lecture.** Dans ton journal : quels contrôles l'approbateur fait-il sur une demande ? Que pourrait obtenir un kubelet compromis si l'approbateur ne vérifiait que le préfixe `system:node:` ? Que vaut le contrôle DNS si quelqu'un peut écrire dans la zone `par1.medisphere.internal` ? Pourquoi l'approbateur ne touche-t-il **pas** aux demandes de certificat **client** des kubelets ?
2. **Approbateur.** Recopie du chart dans Harbor (`charts.yaml` de `charts-miroir`), espace `kubelet-csr-approver` (PSA `restricted`, `plateforme/k8s/espaces/`), Application Argo CD : expression des noms, préfixe d'adresses, durée maximale, deux réplicas avec élection de chef, ServiceMonitor, ressources, image par le cache `ghcr`. Synchronise.
3. **Preuve.** Provoque une demande réelle sur un travailleur (renouvellement du certificat de service : RB-143 te dit lequel supprimer et quoi redémarrer) et vérifie qu'elle est approuvée en quelques secondes, par qui (`kubectl get csr`, journaux de l'approbateur). Puis montre qu'une demande **forgée** est refusée : depuis `adm01`, une CSR `kubernetes.io/kubelet-serving` pour un nom hors de l'expression (fichier de demande et clé créés dans `$XDG_RUNTIME_DIR`, supprimés ensuite). Note la condition posée sur la demande refusée.
4. **Vérification TLS.** metrics-server ne désactive plus rien depuis le M14 : vérifie-le. Dans les values de `kps`, active la vérification du certificat des kubelets par la CA du cluster, MR, synchronisation ; les cibles `kubelet` restent `up` dans Prometheus. Lis ce qui reste en `insecureSkipVerify` dans les values (contrôleur, ordonnanceur) et explique pourquoi ; mets à jour `docs/observabilite/metriques/securite.md` (limites connues).
5. **seccomp par défaut.** `seccompDefault: true` dans la `KubeletConfiguration` du dépôt et dans le ConfigMap `kubelet-config` ; un nœud à la fois avec le playbook ; après chaque nœud : pods en échec ? Contrôle sur un pod de `wb-essais` sans profil déclaré : `grep Seccomp /proc/1/status` dans le conteneur.
6. **Runbook.** Mets à jour RB-143 §5 : approbation automatique, ce qu'on surveille, ce qu'on fait si l'approbateur est arrêté ou refuse.

**Critères de réussite**
- [ ] `kubelet-csr-approver` est prêt (2 réplicas, image par Harbor), sa configuration n'accepte que `k8s-(cp|w)0N` et 10.10.40.0/24 ; aucune demande `kubelet-serving` n'attend.
- [ ] La dernière demande de service d'un kubelet a été approuvée en moins de 5 minutes ; une demande forgée a été **refusée** (condition `Denied`).
- [ ] Le ServiceMonitor `kubelet` de `kps` vérifie le certificat (pas d'`insecureSkipVerify`, CA du cluster) et ses cibles sont `up`.
- [ ] `seccompDefault: true` dans le ConfigMap `kubelet-config` et sur les six nœuds ; aucun pod en `CrashLoopBackOff` causé par le changement ; RB-143 à jour sur `main`.

**Vérification** : `lab/bin/check 26 25`

<details><summary>Indice 1</summary>

`kubectl certificate approve` n'est qu'une mise à jour de la sous-ressource `approval` d'une CSR : l'approbateur fait la même chose avec un compte de service. Les droits qu'il lui faut (`approve` sur le signataire `kubernetes.io/kubelet-serving`) sont dans le chart : lis-les.
</details>

<details><summary>Indice 2</summary>

Une demande forgée se fabrique avec `openssl req -new -subj "/O=system:nodes/CN=system:node:<NOM>" -addext "subjectAltName=…"` puis un objet `CertificateSigningRequest` (`spec.signerName`, `spec.usages` : `digital signature`, `server auth`, et `key encipherment` pour une clé RSA). Elle n'aura pas l'identité d'un nœud (c'est toi qui la crées) : regarde ce que l'approbateur en fait.
</details>

<details><summary>Indice 3</summary>

« x509: cannot validate certificate for 10.10.40.61 because it doesn't contain any IP SANs » dans les cibles de Prometheus : un kubelet sert encore un vieux certificat auto-signé (le nœud n'a jamais renouvelé depuis M14-E26 ?). Regarde `openssl s_client -connect 10.10.40.61:10250` avant d'accuser la configuration.
</details>

**Pour aller plus loin** (facultatif) : un profil seccomp **local** plus strict que `RuntimeDefault` pour MédiAgenda (`Localhost`, opérateur Security Profiles Operator cité) ; l'admission `NodeRestriction` et ce qu'elle empêche un kubelet compromis de faire ; durcir les certificats de service du contrôleur et de l'ordonnanceur (`--tls-cert-file`) pour supprimer les derniers `insecureSkipVerify`.

---

### M26-E26 — Chiffrement transparent entre nœuds avec WireGuard  `LAB` `★★★`

> **Ticket SEC-2726** — *De : Sophie Laurent* — *Copie : Karim Benali*
> L'auditeur m'a posé la question telle quelle : « tout ce qui circule entre deux machines du cluster est-il chiffré ? ». J'ai répondu « les pods, oui, depuis le M15 ». Il a demandé : « et le reste ? ».
> Je veux la carte exacte de ce qui circule en clair entre les nœuds aujourd'hui, ce que `nodeEncryption` y change, son coût mesuré, et une décision écrite. Pas de mode strict pour l'instant : je ne veux pas d'un nœud isolé parce qu'il a changé de clé un dimanche.

**Objectifs pédagogiques**
- Distinguer les flux couverts par le chiffrement **entre pods** de ceux qui ne le sont pas (réseau de l'hôte, pods en `hostNetwork`, nœuds de contrôle), et le prouver par capture.
- Activer le chiffrement **nœud à nœud** de Cilium, en comprendre l'exclusion des nœuds de contrôle et le coût.
- Mesurer avant et après (débit, latence, processeur), vérifier le MTU effectif des flux de l'hôte.

**Prérequis** : M15-E24 (WireGuard entre pods, fiche `chiffrement.md`, mesure iperf3), M15-E29 (mesures), M17-E10 (release Helmfile `cilium`), M21-E02 (Prometheus collecte les nœuds), M26-E06 (PSA).
**Durée indicative** : 2 h 30.

**Contexte technique**
- **Lecture** : [WireGuard Transparent Encryption](https://docs.cilium.io/en/stable/security/network/encryption-wireguard/) de Cilium 1.20, en entier : *Node-to-Node Encryption (beta)*, *Which traffic is encrypted*, *Known Issues* ; la clé `encryption` du `values.yaml` du chart 1.20.
- Ta fiche `docs/kubernetes/reseau/chiffrement.md` (M15) liste ce qui n'est pas chiffré : relis-la, puis complète-la avec ce qui a été ajouté depuis (Prometheus qui collecte les agents Cilium, node-exporter, etcd ; Tetragon en réseau de l'hôte ; Hubble ; Alloy…).
- Instrument de mesure : les pods de [`modules/15-kubernetes-reseau/ressources/E24-mesure-iperf3.yaml`](../../15-kubernetes-reseau/ressources/E24-mesure-iperf3.yaml) (espace **`wb-perf`**, recréé pour l'exercice, PSA `baseline`) et, pour le réseau de l'hôte, un pod de débogage de nœud (`kubectl debug node/<nœud> -n wb-perf --profile=sysadmin --image=<image netshoot du M15> -- iperf3 -s`), qui exige que `wb-perf` soit **temporairement** en `privileged`. N'utilise pas `wb-essais` (qui reste `restricted`).
- Le chart applique les agents un nœud à la fois (`maxUnavailable: 1`), mais **ne redémarre pas** les agents quand seule la ConfigMap change (`rollOutCiliumPods: false`).

> ⚠️ **Attention** : (1) pendant le redémarrage d'un agent, son nœud perd quelques secondes de réseau des pods ; la bordure perd un chemin BGP : fais-le hors d'un autre essai, Watchdog et témoin vérifiés avant ; (2) n'active **pas** `encryption.strictMode` (ni `egress`, ni `ingress`) : une clé publique périmée isolerait un nœud ; (3) ne retire **pas** l'exclusion des nœuds de contrôle (`node-encryption-opt-out-labels`) : la documentation explique pourquoi un travailleur qui change de clé ne pourrait plus la publier ; (4) supprime `wb-perf` à la fin (pods privilégiés) ; (5) retour arrière : `nodeEncryption: false` dans les values, MR, `helmfile apply`, redémarrage des agents.

**Travail demandé**
1. **État des lieux.** Vérifie que le chiffrement du M15 est toujours actif après la reprise par Helmfile (ConfigMap `cilium-config`, `cilium-dbg status`, nombre de pairs sur chaque agent). Complète dans `chiffrement.md` le tableau « ce qui circule entre nœuds en clair », flux par flux (source, destination, port, protocole applicatif, chiffré par qui), en distinguant pod → pod, pod → nœud, nœud → nœud, et les flux des nœuds de contrôle.
2. **Preuve avant.** Recrée `wb-perf`. Capture sur `eth0` d'un travailleur une collecte de Prometheus vers l'agent Cilium d'un **autre** nœud (port 9962, HTTP) : le texte des métriques est-il lisible ? Mesure : iperf3 pod → pod (rappel du M15), pod → réseau de l'hôte d'un autre nœud, hôte → hôte ; latence (`ping`) ; processeur des deux nœuds pendant la mesure ; MTU des routes des pods et de `cilium_wg0`.
3. **Activation.** `encryption.nodeEncryption: true` dans `composants/cilium/values.yaml`, MR (le rendu `helmfile -e par1 -l composant=cilium diff` ne doit montrer **que** cette clé), `apply`, puis redémarrage contrôlé des agents. Vérifie l'option effective dans la ConfigMap et sur chaque agent.
4. **Preuve après.** Même capture : plus de 9962 en clair entre deux travailleurs. Et vers un nœud de contrôle (etcd 2381, agent Cilium d'un nœud de contrôle) ? Explique ce que tu vois. Mêmes mesures qu'en 2 ; vérifie le chemin MTU des flux de l'hôte entre deux travailleurs (`ping -M do` à taille croissante, `tracepath`) et note où se fait la fragmentation, s'il y en a.
5. **Décision.** Dans `chiffrement.md` : tableau avant/après, ce qui reste en clair et pourquoi c'est accepté ou ce qu'on y fera (TLS applicatif, mode strict plus tard), coût mesuré, conditions de révision. Mets à jour la matrice des flux du cluster si un flux change de port.
6. **Nettoyage.** `wb-perf` supprimé ; aucune capture `.pcap` laissée sur un nœud.

**Critères de réussite**
- [ ] `cilium-config` porte `enable-wireguard: "true"` et `encrypt-node: "true"` ; chaque agent annonce WireGuard avec 5 pairs ; les six `CiliumNode` publient une clé.
- [ ] La release Helmfile `cilium` est sans écart (`helmfile diff` vide) et les agents ont redémarré après le changement.
- [ ] `chiffrement.md` (sur `main`) contient le tableau des flux avant/après, les mesures (débit, latence, processeur, MTU) et la décision ; l'espace `wb-perf` n'existe plus.

**Vérification** : `lab/bin/check 26 26`

<details><summary>Indice 1</summary>

Le tableau *Which traffic is encrypted* répond presque à tout : « Node » y désigne aussi un pod en réseau de l'hôte. Ensuite, regarde quels pods de ton cluster sont en `hostNetwork` (`kubectl get pods -A -o json | jq …`) et quels ports ils servent.
</details>

<details><summary>Indice 2</summary>

Pour la capture, filtre sur le port et l'adresse du nœud collecté, avec `-A` pour voir le contenu : en mode tunnel, le trafic d'un pod vers un **nœud** n'est pas encapsulé en VXLAN (le nœud n'est pas un pod). Après l'activation, le même échange n'apparaît plus que comme de l'UDP 51871.
</details>

<details><summary>Indice 3</summary>

Si `ping -M do -s 1472` d'hôte à hôte échoue après l'activation alors que 1352 passe, ce n'est pas une panne : regarde le MTU de `cilium_wg0` et les routes de l'hôte. La question est de savoir si TCP s'en accommode (découverte du MTU du chemin) ou si des paquets disparaissent sans message.
</details>

**Pour aller plus loin** (facultatif) : lis la section `encryption.strictMode` du chart 1.20 (les anciennes clés `strictMode.enabled`/`strictMode.cidrs` ont été remplacées par `strictMode.egress.*` et `strictMode.ingress.enabled`) et écris ce qu'il faudrait pour l'activer sans risque (procédure de remplacement d'un nœud, supervision des clés) ; compare avec IPsec (accélération matérielle, gestion des clés) et avec le chiffrement par ztunnel annoncé en 1.20.

---

### M26-E27 — Pare-feu d'hôte de Cilium  `LAB` `★★★★`

> **Ticket SEC-2727** — *De : Sophie Laurent* — *Copie : Claire Morel, Nadia Roussel, Karim Benali*
> Les nœuds de `k8s-par1` acceptent toute connexion qui arrive du VLAN 40 : un pod compromis, ou une VM du VLAN 40 sous le contrôle de quelqu'un, peut parler au kubelet, à etcd, à n'importe quel port en écoute. Le CIS et l'ANSSI demandent un filtrage local des hôtes ; nos VMs l'ont (nftables, rôle `pare_feu`), pas les nœuds.
> Je veux un filtrage en entrée de chaque nœud, **écrit comme une politique**, observé avant d'être appliqué, appliqué un nœud à la fois, avec un retour arrière que Nadia sait faire à 3 heures du matin sans moi.
> — *Nadia* : et je veux le tester, ce retour arrière, avant que vous l'appliquiez au dernier nœud de contrôle.

**Objectifs pédagogiques**
- Comprendre le pare-feu d'hôte de Cilium : point d'accrochage (périphériques natifs), politiques à `nodeSelector`, identités (`remote-node`, `kube-apiserver`, `health`, `world`), sens d'application, état des connexions.
- Établir la liste **exhaustive** des flux entrants d'un nœud de contrôle et d'un travailleur, et la vérifier par observation (mode audit) plutôt que par mémoire.
- Déployer un changement à fort risque : audit, application nœud par nœud, critère de passage, retour arrière testé, accès hors bande.

**Prérequis** : M26-E26, M14-E03 (point d'accès : keepalived et HAProxy des nœuds de contrôle), M15-E11 (BGP), M15-E28 et E32 (politiques de cluster, matrice des flux du cluster), M21-E07/E20 (ce que Prometheus collecte sur les nœuds), M25 (OpenBao valide les jetons par la VIP de l'API).
**Durée indicative** : 5 h.

**Contexte technique**
- **Lecture obligatoire** : [Host Firewall](https://docs.cilium.io/en/stable/security/host-firewall/) (dont *Emergency Recovery*), [Host Policies](https://docs.cilium.io/en/stable/security/policy/host/) (dont *Host Policies known issues*, en entier), [Firewall Rules](https://docs.cilium.io/en/stable/operations/system_requirements/#firewall-rules), la clé `hostFirewall` et la clé `extraConfig` du `values.yaml` 1.20.
- Le pare-feu d'hôte s'active dans les values de la release `cilium` ; il ne filtre rien tant qu'aucune politique ne sélectionne un nœud. Une politique d'hôte n'a d'effet que dans le **sens** où elle déclare des règles : n'écris que des règles d'**entrée** (`ingress`).
- Le **mode audit** se règle **par nœud** sur le point de terminaison de l'hôte (`cilium-dbg endpoint config <ID> PolicyAuditMode=Enabled`) et **ne survit pas** au redémarrage de l'agent ; l'option globale `policyAuditMode` du chart, elle, désactiverait aussi **toutes** les politiques des pods (M15, M21) : ne t'en sers pas.
- Les nœuds de contrôle tiennent la VIP de l'API par **keepalived** (VRRP, protocole IP 112, sans port). Lis attentivement ce que la documentation dit du VRRP quand le pare-feu d'hôte est actif.
- Quelques sources qu'on oublie : la bordure (BGP), `vault01-03` (validation des jetons de comptes de service par la VIP:8443), MGMT (`kubectl`, SSH), `mon01` (sondes ICMP du témoin), Prometheus (collecte des agents, de node-exporter, des kubelets, d'etcd, du contrôleur et de l'ordonnanceur), metrics-server, Hubble Relay, le serveur d'API vers les kubelets, les sondes de santé de Cilium, l'encapsulation VXLAN et WireGuard. La liste des ports en écoute (`ss -lntup` sur un nœud) est ta référence, pas ta mémoire.
- Les Services `LoadBalancer` (10.10.41.x) sont traduits par le remplacement de kube-proxy **avant** le pare-feu d'hôte : lis l'entrée correspondante des *known issues* pour savoir où leur trafic est filtré.
- Ordre des nœuds imposé : `k8s-w03`, `k8s-w02`, `k8s-w01`, puis `k8s-cp03`, `k8s-cp02`, `k8s-cp01` (le dernier porte en général la VIP : vérifie qui la porte et fais-le en dernier).

> ⚠️ **Attention** : ce changement peut **couper l'accès** à un nœud (SSH, API, kubelet) ou au cluster entier.
> - **Avant** : console Proxmox de chaque nœud testée (connexion `admin` locale) ; sauvegarde PBS de `par1/k8s` de moins de 24 h ; instantané etcd vérifié ; `admin.conf` disponible ; un collègue prévenu (Nadia).
> - **VRRP** : si le pare-feu d'hôte est activé sans que le protocole VRRP soit autorisé **dans le chemin de données**, les trois nœuds de contrôle peuvent se croire seuls et porter **tous** la VIP 10.10.40.200 (ARP qui oscille, API intermittente). Vérifie après l'activation, avant toute politique : `ip -br addr | grep 10.10.40.200` sur les trois nœuds de contrôle (un seul doit la porter).
> - **Audit avant application** : un nœud n'est étiqueté qu'**après** que son point de terminaison d'hôte est passé en audit ; il ne sort de l'audit qu'après **24 h sans** verdict `audit` inexpliqué. Si l'agent redémarre pendant l'observation, le nœud **applique** immédiatement : surveille-le.
> - **Retour arrière** (RB-264), du plus doux au plus fort : (1) repasser le point de terminaison de l'hôte en audit (`outils/pare-feu-hote.sh audit <nœud>`) ; (2) retirer l'étiquette du nœud (`kubectl label node <nœud> medisphere.internal/pare-feu-hote-`, puis le retirer de `cluster/noeuds.yaml`) : plus aucune politique ne le sélectionne ; (3) sans API : console Proxmox du nœud, `crictl exec` dans le conteneur `cilium-agent`, audit sur le point de terminaison `reserved:host` (procédure *Emergency Recovery*) ; (4) `hostFirewall.enabled: false` (Helmfile) et redémarrage des agents.
> - Le pare-feu d'hôte ne remplace pas la bordure : les règles de `gw01`/`gw02` restent, et le pare-feu local nftables des VMs n'est pas concerné.

**Travail demandé**
1. **Lecture.** Dans ton journal : où le pare-feu d'hôte s'accroche-t-il (quels périphériques sur **tes** nœuds, `eth1` compris ?) ; qu'est-ce que l'identité `remote-node`, `kube-apiserver`, `health`, `world` pour un paquet qui arrive sur `k8s-cp01` ; pourquoi une règle `fromCIDR` ne sélectionne-t-elle pas les autres nœuds du cluster ; que deviennent les réponses aux connexions **sortantes** du nœud (DNS, NTP, Harbor, Ceph) ; que dit la documentation des interfaces WireGuard de l'hôte, et quelle conséquence avec le chiffrement nœud à nœud d'E26 ?
2. **Inventaire.** Pour un nœud de contrôle et un travailleur : `ss -lntup` (processus, adresse, port), puis la table des flux **entrants** attendus : source (entité ou réseau), port, protocole, raison, exercice qui l'a créé. Ajoute-la à `docs/kubernetes/reseau/matrice-flux-cluster.md` (section « entrées des nœuds »).
3. **Activation.** Dans les values de `cilium` : pare-feu d'hôte, et ce qu'il faut pour que le VRRP de keepalived continue de passer. MR, `helmfile apply`, redémarrage des agents un par un. Vérifie : `cilium-dbg status | grep 'Host firewall'` (périphériques), une seule VIP, BGP établi (`cilium bgp peers`), `kubectl get nodes`.
4. **Politiques.** Dans `composants/cilium/hote/` : `hote-commun` (tous les nœuds étiquetés), `hote-plan-controle` (nœuds de contrôle étiquetés), `hote-travailleurs` (travailleurs étiquetés), règles d'entrée seulement, chaque règle commentée avec sa raison. Le dossier est appliqué par `task appliquer`. Écris l'outil `outils/pare-feu-hote.sh` : `etat <nœud>` (identifiant du point de terminaison, mode audit, application), `audit <nœud>`, `applique <nœud>` (refuse si le nœud n'est pas étiqueté, ou si des verdicts `audit` sont apparus dans la dernière heure).
5. **Audit, un nœud.** `k8s-w03` : audit sur son point de terminaison d'hôte, **puis** étiquette (`cluster/noeuds.yaml`, `outils/etiqueter-noeuds.sh`). Lis les verdicts (`cilium-dbg monitor -t policy-verdict --related-to <ID>` ou `hubble observe --verdict AUDIT --to-identity 1`) pendant une journée d'usage normal (dont une collecte complète, une sauvegarde, une synchronisation d'Argo CD, un `kubectl logs`, un `ssh`). Chaque verdict `audit` : flux légitime oublié (corrige la politique) ou flux illégitime (note-le). Recommence jusqu'à zéro verdict inexpliqué.
6. **Retour arrière répété.** Avec Nadia (joue-la), sur `k8s-w03` en audit : chronomètre les étapes (1) et (2) du retour arrière, puis l'étape (3) par la console Proxmox. Écris **RB-264** à partir de ce que tu as réellement tapé.
7. **Application, nœud par nœud.** `k8s-w03` en application (`outils/pare-feu-hote.sh applique`) ; contrôles : `kubectl get nodes`, `kubectl logs` d'un pod du nœud, cibles Prometheus du nœud `up`, BGP, SSH depuis `adm01`, un port non autorisé refusé depuis `adm01` (`nc -vz -w 3 10.10.40.63 <port>`). Puis les autres nœuds dans l'ordre imposé, avec audit préalable pour chacun et une nuit entre les travailleurs et les nœuds de contrôle.
8. **Documentation.** Mets à jour la matrice des flux du cluster et `exceptions.md` (E23) si un flux ne peut pas être fermé.

**Critères de réussite**
- [ ] `cilium-config` porte `enable-host-firewall: "true"` et active les protocoles IP étendus ; un seul nœud de contrôle porte 10.10.40.200 ; les deux sessions BGP de chaque travailleur sont établies.
- [ ] Les trois politiques existent, ne contiennent que des règles d'entrée, et ne sélectionnent que les nœuds étiquetés `medisphere.internal/pare-feu-hote: "oui"` ; les six nœuds portent l'étiquette, et elle est dans `cluster/noeuds.yaml`.
- [ ] Les six points de terminaison d'hôte appliquent la politique en entrée (plus aucun en audit) ; depuis `adm01`, SSH vers les nœuds fonctionne et un port non autorisé est refusé.
- [ ] Le cluster est sain : six nœuds `Ready`, `cilium status` sans erreur, aucune cible `up == 0` sur les nœuds dans Prometheus.
- [ ] RB-264 et la section « entrées des nœuds » de la matrice des flux du cluster sont sur `main`.

**Vérification** : `lab/bin/check 26 27`

<details><summary>Indice 1</summary>

Le premier exemple de la documentation (`lock-down-ingress`) autorise **tout** depuis `remote-node` et `health` : c'est un point de départ, pas une fin. Pour un nœud de contrôle, distingue ce qui ne doit venir que des autres nœuds de contrôle (etcd, VRRP), ce qui vient de tout le cluster (pods compris : l'API par le Service `kubernetes`), et ce qui vient de l'extérieur (MGMT, `vault01-03`, `mon01`, la bordure).
</details>

<details><summary>Indice 2</summary>

Un pod qui joint un port du **nœud** (Prometheus vers 9962, metrics-server vers 10250, Hubble Relay vers 4244) arrive avec l'identité **du pod**, pas `remote-node` : une règle `fromEndpoints` avec l'espace de noms du pod (`k8s:io.kubernetes.pod.namespace`) les autorise sans ouvrir à tout le cluster.
</details>

<details><summary>Indice 3</summary>

`DROP_CT_UNKNOWN_PROTO` dans `cilium-dbg monitor` sur un nœud de contrôle juste après l'activation : c'est le VRRP. La documentation des *Host Policies* nomme l'option de l'agent qui l'autorise ; le chart n'a pas de clé dédiée pour elle, mais il sait ajouter une option quelconque à la ConfigMap. Ensuite, la politique doit encore l'autoriser (protocole `VRRP` dans `toPorts`).
</details>

**Pour aller plus loin** (facultatif) : des règles de **sortie** pour les travailleurs (seulement DNS, NTP, Harbor, `s3-01`, Ceph, `git01`…) et leur coût d'exploitation ; une alerte sur les refus du pare-feu d'hôte (`hubble_drop_total` avec la raison `POLICY_DENIED` vers l'identité `host`) ; la comparaison avec un nftables local sur les nœuds (pourquoi Cilium et kube-proxy rendent cette voie fragile).

---

### M26-E28 — Audit Kubernetes revisité : politique, détection, rétention  `LAB` `★★`

> **Ticket SEC-2728** — *De : Sophie Laurent*
> Le journal d'audit de l'API existe depuis le M14 et part dans Loki depuis le M22. Mais il ne sait rien de Kyverno, de Tetragon, d'External Secrets ; il enregistre peut-être des choses qu'il ne devrait pas ; et il ne dit rien à personne quand quelqu'un ouvre un shell en production, lit un Secret à la main ou se donne `cluster-admin`.
> Je veux une politique d'audit revue pour ce que nous avons aujourd'hui, et quatre détections : exec en production, lecture de Secret par une personne, liaison de rôle de cluster, usage du bris de glace.

**Objectifs pédagogiques**
- Relire une politique d'audit à la lumière des composants ajoutés (CRD de sécurité, rapports, contrôleurs bavards) : niveau, ordre des règles, volume, données sensibles.
- Écrire des détections LogQL sur le locataire `audit` et les tester sur de vrais événements.
- Vérifier la chaîne complète (API → fichier → Alloy → Loki → ruler → Alertmanager) et sa rétention.

**Prérequis** : M14-E27 (politique, rôle `k8s_audit`, `outils/reconfigurer-apiserver.sh`), M22-E07 et E08 (collecte, locataire `audit`, règles du ruler), M24 (identités `oidc:` et bris de glace `admin.conf`), M26-E07 et E20 (CRD de Kyverno et de Tetragon), M25 (CRD d'ESO).
**Durée indicative** : 2 h.

**Contexte technique**
- **Lecture** : [Auditing](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/) (niveaux, étapes, ordre des règles) et la référence de l'API [`audit.k8s.io/v1`](https://kubernetes.io/docs/reference/config-api/apiserver-audit.v1/).
- Le serveur d'API lit la politique **au démarrage** : un fichier invalide l'empêche de redémarrer. La politique est déposée par le rôle `k8s_audit` sur les trois nœuds ; le redémarrage se fait un nœud à la fois.
- Après le M24, les personnes apparaissent comme `oidc:<identifiant>` ; `admin.conf` (bris de glace) s'authentifie comme `kubernetes-admin` (groupe `kubeadm:cluster-admins`), `super-admin.conf` dans le groupe `system:masters`. Les jobs de CI, Argo CD et les contrôleurs sont des comptes `system:serviceaccount:…`.
- Les métadonnées structurées posées par Alloy ne contiennent **pas** la sous-ressource (`exec`, `log`…) : elle est dans la ligne JSON (`objectRef.subresource`).
- Une commande `kubectl exec` passe par WebSocket depuis kubectl 1.31 : vérifie sur un **vrai** événement quel `verb` est enregistré avant d'écrire ta règle.

> ⚠️ **Attention** : (1) une règle `Request` ou `RequestResponse` sur les Secrets écrit leur contenu en clair dans les journaux (et dans Loki pour un an) : ne le fais jamais ; (2) relis le fichier deux fois et redémarre d'abord **un** serveur d'API ; si le pod statique ne revient pas, remets l'ancien fichier (`.orig` laissé par le rôle ou copie manuelle) avant de toucher aux autres ; (3) retour arrière : `git revert` de la politique, rôle rejoué, redémarrage nœud par nœud.

**Travail demandé**
1. **Revue.** Lis la politique en place et le volume actuel (`sum by (resource) (count_over_time({job="kubernetes-audit"}[1h]))` dans Grafana, source « Loki — audit »). Dans ton journal : quels objets ajoutés depuis le M14 tombent dans la règle finale `Metadata` alors qu'une écriture mériterait `Request` ; quels contrôleurs produisent le plus d'événements inutiles ; ce que contient un événement `pods/exec` au niveau `Metadata` (la commande y est-elle ?).
2. **Politique v2.** Modifie `politique.yaml` (rôle `k8s_audit`) : écritures des CRD de sécurité (`policies.kyverno.io`, `cilium.io`, `external-secrets.io`) au niveau `Request` ; bruit des rapports de politiques réduit ; Secrets toujours en `Metadata` ; commentaire de chaque règle nouvelle. MR, rôle rejoué, serveurs d'API redémarrés un par un ; contrôle sur chaque nœud que le nouveau fichier est lu (un événement de la nouvelle règle apparaît).
3. **Détections.** `loki/regles/audit/securite.yaml` dans `plateforme/observabilite` : **`AuditExecProduction`** (exec ou attach dans `mediagenda-prod` ou `medidoc-prod` par une personne), **`AuditLectureSecretParPersonne`** (lecture d'un Secret par un compte `oidc:`), **`AuditLiaisonRoleCluster`** (création ou modification d'un `ClusterRoleBinding` hors comptes système), **`AuditBrisDeGlace`** (toute requête de `kubernetes-admin` ou du groupe `system:masters`). Étiquettes `gravite` (laquelle est critique ?), `equipe: securite` ou `plateforme`, `runbook_url`.
4. **Essais.** Déclenche chaque détection une fois, de façon inoffensive (un `kubectl exec … -- true` dans un pod de `mediagenda-prod` avec un ticket CHG ouvert, la lecture d'un Secret de `wb-essais`, une liaison de test `wb-test-liaison` vers une ClusterRole en lecture seule, puis supprimée, une requête `get nodes` avec `admin.conf`) ; vérifie chaque alerte dans Alertmanager, puis note le délai entre l'action et la notification.
5. **Rétention.** Vérifie la rétention réelle du locataire `audit` (configuration de Loki) et des fichiers locaux (options du serveur d'API) ; écris dans `docs/securite/durcissement/conformite-continue.md` (section « traces ») combien de temps chaque trace est gardée et où.

**Critères de réussite**
- [ ] La politique d'audit des trois nœuds de contrôle est identique (même empreinte), contient une règle `Request` pour les CRD de sécurité et garde les Secrets en `Metadata` ; aucune règle `Request`/`RequestResponse` ne vise les Secrets.
- [ ] Les quatre règles du ruler sont chargées dans le locataire `audit` ; chacune a déclenché au moins une alerte pendant l'essai.
- [ ] La liaison de test `wb-test-liaison` n'existe plus ; la section « traces » de `conformite-continue.md` est sur `main`.

**Vérification** : `lab/bin/check 26 28`

<details><summary>Indice 1</summary>

L'ordre compte : la **première** règle qui correspond s'applique. Une règle `Request` pour `cilium.io` placée après une règle générale `Metadata` ne servira jamais ; une règle `None` pour les rapports placée après une règle `Request` qui vise `wgpolicyk8s.io` non plus.
</details>

<details><summary>Indice 2</summary>

`{job="kubernetes-audit"} |= "\"subresource\":\"exec\"" | json` puis un filtre sur `objectRef_namespace` et `user_username` : le filtre de ligne d'abord (il évite d'analyser chaque ligne), l'analyse JSON ensuite. Pour une alerte, compte avec `count_over_time(…[5m])` et groupe par utilisateur.
</details>

**Pour aller plus loin** (facultatif) : la source `k8saudit` de Falco (promise au M14) : ce qu'elle exigerait (*webhook backend* d'audit vers Falco, `--audit-webhook-config-file`) et pourquoi le lab s'en tient au ruler de Loki ; une politique d'audit différente pour l'espace `ci-jobs` ; la signature des journaux d'audit (intégrité) avant archivage.

---

### M26-E29 — Tetragon en application : bloquer  `LAB` `★★★`

> **Ticket SEC-2729** — *De : Sophie Laurent* — *Copie : Julien Petit*
> Tetragon nous dit depuis E20 qui exécute quoi et qui lit quoi. Je veux maintenant qu'il **empêche** ce qui n'a aucune raison d'arriver dans un conteneur de MédiAgenda : exécuter un binaire déposé dans `/tmp`, lire `/etc/shadow`, écrire dans `/etc` ou `/usr`.
> — *Julien* : d'accord, mais d'abord dans `wb-essais`, puis en recette pendant une semaine, et je veux pouvoir le couper moi-même si ça casse une démo.

**Objectifs pédagogiques**
- Comprendre les deux mécanismes d'application de Tetragon (signal `Sigkill`, remplacement de la valeur de retour `Override`), leurs prérequis noyau et leurs limites.
- Passer d'une politique d'observation à une politique d'application **limitée à un espace** (`TracingPolicyNamespaced`) et la valider sur des cas positifs et négatifs.
- Déployer une règle bloquante sur une application réelle avec une procédure d'arrêt d'urgence.

**Prérequis** : M26-E20 (Tetragon, `tetra`, événements dans Loki), M26-E21 (charges sûres : MédiAgenda en système de fichiers racine en lecture seule), M26-E19 (Falco : même règle « binaire depuis /tmp » en détection).
**Durée indicative** : 2 h 30.

**Contexte technique**
- **Lecture** : documentation de Tetragon 1.7 : [Enforcement](https://tetragon.io/docs/concepts/enforcement/), [Selectors](https://tetragon.io/docs/concepts/tracing-policy/selectors/) (actions `Sigkill`, `Override`, `NoPost` ; `matchBinaries`), [Kubernetes filtering](https://tetragon.io/docs/concepts/tracing-policy/k8s-filtering/) (`TracingPolicyNamespaced`, `podSelector`), et les exemples `file_monitoring_enforce.yaml` de l'étiquette `v1.7.1`.
- `Override` sur une fonction `security_*` exige un noyau ≥ 5.7 compilé avec `CONFIG_BPF_KPROBE_OVERRIDE` : vérifie sur un travailleur (`/boot/config-$(uname -r)`). Sans lui, `Sigkill` seul tue le processus mais ne garantit pas que l'opération n'ait pas eu lieu.
- Les politiques vivent dans `plateforme/politiques/tetragon/` ; l'Application `politiques` d'Argo CD les applique (auto-synchronisée). L'AppProject doit autoriser le type `TracingPolicyNamespaced` dans les espaces visés.
- MédiAgenda tourne avec un système de fichiers racine en lecture seule (E21) : une écriture dans `/etc` y échoue **déjà**. Que t'apporte alors la règle ?

> ⚠️ **Attention** : (1) une politique d'application **non namespacée** (`TracingPolicy`) s'applique à tout le nœud, processus de l'hôte compris : n'en écris aucune dans cet exercice ; jamais rien sur `kube-system` ; (2) teste chaque règle sur un cas qui **doit passer** autant que sur un cas qui doit échouer : une règle `Prefix "/etc"` en lecture tuerait tout processus qui lit `/etc/hosts` ; (3) arrêt d'urgence (pour Julien) : suspendre l'auto-synchronisation de l'Application `politiques` puis supprimer l'objet, ou `git revert` ; l'écrire dans RB-260 (E19).

**Travail demandé**
1. **Lecture.** Dans ton journal : différence entre `Sigkill` et `Override` (que se passe-t-il pour l'appel système, pour le processus) ; pourquoi l'exemple amont combine parfois les deux ; ce qu'apporte `TracingPolicyNamespaced` par rapport à une `TracingPolicy` avec `podSelector` ; ce que devient la règle si Tetragon redémarre ou si le pod change de nœud.
2. **Prérequis noyau.** Vérifie `CONFIG_BPF_KPROBE_OVERRIDE` et la présence de la fonction visée dans `/sys/kernel/debug/error_injection/list` (ou explique pourquoi elle n'y est pas nécessaire pour un crochet `security_`).
3. **Dans `wb-essais`.** Deux politiques `TracingPolicyNamespaced` dans `tetragon/application/wb-essais/` : `bloquer-exec-tmp` (exécution d'un fichier sous `/tmp` ou `/dev/shm`) et `proteger-fichiers-systeme` (lecture de `/etc/shadow`, écriture sous `/etc`, `/usr`, `/bin`, `/sbin`, `/lib`). Un pod d'essai (image du cache, contexte `restricted`, `/tmp` en `emptyDir`, et un second `emptyDir` monté sur `/etc/essai` pour pouvoir **tenter** une écriture sous `/etc`) : cas négatifs (copier `/bin/true` dans `/tmp` et l'exécuter ; écrire dans `/etc/essai/`) et positifs (`cat /etc/hosts`, `cat /etc/os-release`, écrire dans `/tmp`, exécuter `/bin/true`). Note les événements (`tetra getevents -o compact --namespace wb-essais`) et les codes de sortie. Essaie aussi `cat /etc/shadow` : pourquoi ce cas ne déclenche-t-il **pas** la politique dans ce pod, et que protège alors cette règle ?
4. **En recette.** La politique `proteger-fichiers-systeme` (pas l'autre : pourquoi ?) dans `tetragon/application/mediagenda-recette/`, limitée aux pods de l'API (`podSelector`). MR relue par Julien. Une semaine d'observation : aucun redémarrage de pod de la recette causé par Tetragon (journaux Loki `service="tetragon"`, action `SIGKILL`) ; tests de bout en bout de la recette verts.
5. **Alerte et arrêt d'urgence.** Une alerte du ruler Loki (locataire `audit`) **`TetragonProcessusTue`** sur tout `SIGKILL` décidé par une politique d'application ; complète RB-260 avec l'arrêt d'urgence (qui, comment, en combien de temps) et teste-le une fois en recette (chronomètre).

**Critères de réussite**
- [ ] Les politiques `bloquer-exec-tmp` et `proteger-fichiers-systeme` existent dans `wb-essais`, `proteger-fichiers-systeme` dans `mediagenda-recette` (limitée à l'API) ; aucune `TracingPolicy` (non namespacée) ne porte d'action `Sigkill` ou `Override`.
- [ ] Les cas négatifs de `wb-essais` ont été bloqués (événements `SIGKILL` ou `OVERRIDE` dans Loki `audit`, `service="tetragon"`) ; les cas positifs passent.
- [ ] La recette est saine (déploiement de l'API prêt, aucun redémarrage récent de ses conteneurs) ; l'alerte `TetragonProcessusTue` est chargée ; RB-260 contient l'arrêt d'urgence.

**Vérification** : `lab/bin/check 26 29`

<details><summary>Indice 1</summary>

`security_file_permission` reçoit un `struct file *` (type `file`) et un masque (`MAY_READ` = 4, `MAY_WRITE` = 2) : `matchArgs` sur les deux, opérateurs `Prefix`/`Equal`. Pour l'exécution, un crochet appelé au moment de l'`execve` avec le chemin du **nouveau** binaire est plus sûr qu'un filtre `matchBinaries`, qui regarde le processus **appelant**.
</details>

<details><summary>Indice 2</summary>

« La politique est chargée mais rien n'est tué » : `kubectl get tracingpoliciesnamespaced -n wb-essais -o yaml` (état), `tetra tracingpolicy list` dans le pod Tetragon du **nœud du pod d'essai** (mode, erreurs de chargement), et le filtre de politiques de Tetragon (`enable-policy-filter`) : sans lui, une politique namespacée ne peut pas se limiter à un espace.
</details>

**Pour aller plus loin** (facultatif) : bloquer les connexions sortantes de l'API de recette hors de la liste attendue (exemple `network_egress_cluster_enforce.yaml`) et comparer avec une CiliumNetworkPolicy (qui fait quoi, à quelle couche) ; le mode de politique (`monitor`/`enforce`) de `tetra tracingpolicy` pour basculer sans modifier l'objet.

---

### M26-E30 — Correctifs de sécurité : le parc, le cluster et les images en service  `LAB` `★★`

> **Ticket CHG-2730** — *De : Claire Morel* — *Copie : Nadia Roussel, Sophie Laurent*
> Une faille critique d'OpenSSH est sortie mardi. Mercredi, personne ne savait dire combien de nos machines étaient corrigées, lesquelles attendaient un redémarrage, ni si nos images de conteneurs en production embarquaient une bibliothèque vulnérable.
> Je veux : les correctifs de sécurité appliqués automatiquement sur les VMs, les redémarrages **programmés par vague** (jamais deux passerelles ni deux nœuds d'une grappe en même temps), une métrique « redémarrage en attente » et une alerte, et la liste des CVE critiques des images qui **tournent** aujourd'hui.

**Objectifs pédagogiques**
- Automatiser les correctifs de sécurité sur Debian (`unattended-upgrades`, `needrestart`) et Rocky (`dnf-automatic`) sans redémarrage sauvage.
- Rendre visible l'état des correctifs (métriques, alertes) et organiser les redémarrages par vague.
- Relier les images **en service** (digests réels) aux analyses de vulnérabilités de Harbor.

**Prérequis** : M26-E14 (vagues), M26-E24 (collecteur *textfile*, alertes), M13 (Harbor, Trivy), M14-E25 (montée de version du cluster, RB-142), M04 (rôles Ansible).
**Durée indicative** : 2 h 30.

**Contexte technique**
- **Lecture** : `/usr/share/doc/unattended-upgrades/README.md.gz` (Debian 13), `man needrestart` (option `restart` de `/etc/needrestart/needrestart.conf` : mode liste), `/etc/dnf/automatic.conf` commenté de Rocky 10 (`upgrade_type`, `apply_updates`, `reboot`), l'API REST v2.0 de Harbor (documentation interactive de ton instance : `https://registry.par1.medisphere.internal/devcenter-api-2.0`) pour les résultats d'analyse d'un artefact (paramètre `with_scan_overview`).
- Debian : un redémarrage est attendu quand `/run/reboot-required` existe ; Rocky : `dnf needs-restarting -r` (code de sortie 1).
- Les nœuds de `k8s-par1` : paquets du système oui, mais **jamais** `kubelet`, `kubeadm`, `kubectl`, `containerd.io` par les mises à jour automatiques (montée de version contrôlée, RB-142 : ils sont déjà épinglés) ; un redémarrage de nœud passe par `cordon`/`drain`.
- `ceph01-03` : un nœud à la fois, `ceph osd set noout` avant, retiré après, `HEALTH_OK` entre deux.

> ⚠️ **Attention** : (1) `Unattended-Upgrade::Automatic-Reboot` reste à `false` partout : les redémarrages passent par le playbook de vague ; (2) sur les passerelles, une mise à jour de `keepalived`, `frr` ou `nftables` redémarre le service : laisse ces paquets hors de l'automatique (liste noire) et traite-les par changement planifié ; (3) retour arrière : rôle rejoué avec `correctifs_auto: false` (les minuteries s'arrêtent, les paquets installés restent).

**Travail demandé**
1. **Rôle `correctifs`.** Debian : `unattended-upgrades` limité à l'origine de sécurité de Debian (et aux dépôts tiers que tu juges sûrs : justifie), liste noire (paquets du cluster, de la bordure), journal ; `needrestart` en mode liste (aucun redémarrage de service automatique). Rocky : `dnf-automatic` en `security`, `reboot = never`. Les deux : un script `correctifs-etat` (minuterie quotidienne) qui écrit `correctifs.prom` (redémarrage requis, nombre de mises à jour de sécurité en attente, date de vérification). `--check --diff`, vague 1, puis tout le parc.
2. **Alertes.** `regles/correctifs.yaml` : `RedemarrageEnAttente` (plus de 7 jours), `CorrectifsSecuriteEnAttente` (des mises à jour de sécurité non installées depuis plus de 3 jours), `CorrectifsVerificationAbsente`. Tests `promtool`.
3. **Redémarrages par vague.** Un playbook `playbooks/redemarrages-vague.yml` : ne redémarre que les hôtes qui en ont besoin, `serial: 1` à partir de la vague 4, vérifications avant/après adaptées (VRRP des passerelles et des répartiteurs, `noout` de Ceph, `drain` des nœuds K8s, santé de la grappe OpenBao). Essai sur la vague 1.
4. **Cluster.** Dans ton journal : la version de correctif 1.36 en place, la dernière publiée, ce que dit son *changelog* en sécurité, et la date prévue de la montée (RB-142, pas dans cet exercice).
5. **Images en service.** `plateforme/k8s/outils/cve-en-service.sh` : liste les images **réellement** en service (digests `imageID` des conteneurs de tous les espaces), retrouve dans Harbor leur analyse et sort, par image, le nombre de vulnérabilités critiques et hautes, l'âge de l'analyse et les espaces concernés ; les images hors Harbor (caches compris) sont listées à part. Identifiants Harbor d'un robot en **lecture** seule, fichier 600. Lance-le, joins la sortie à ton journal, ouvre un ticket DEV pour la pire image applicative.

**Critères de réussite**
- [ ] Sur les VMs Debian, `unattended-upgrades` est configuré (sécurité seulement, sans redémarrage automatique) ; sur les VMs Rocky, `dnf-automatic` en `security` ; la minuterie `correctifs-etat.timer` est active partout.
- [ ] Thanos Query renvoie `medisphere_redemarrage_requis` pour toutes les VMs du socle ; les trois alertes sont chargées.
- [ ] `outils/cve-en-service.sh` est sur `main` de `plateforme/k8s` ; `playbooks/redemarrages-vague.yml` est sur `main` de `plateforme/ansible`.

**Vérification** : `lab/bin/check 26 30`

<details><summary>Indice 1</summary>

L'origine de sécurité de Debian 13 se reconnaît par `origin=Debian,codename=${distro_codename}-security,label=Debian-Security` dans `Unattended-Upgrade::Origins-Pattern`. `unattended-upgrade --dry-run --debug` montre ce qu'il prendrait, sans rien installer.
</details>

<details><summary>Indice 2</summary>

L'`imageID` d'un conteneur (`status.containerStatuses[].imageID`) donne le digest **réellement** tiré, même si le manifeste citait une étiquette. Dans Harbor, un artefact se lit par digest (`…/artifacts/sha256:…?with_scan_overview=true`) ; une image tirée par un cache (`dockerhub/…`) est aussi un artefact de Harbor.
</details>

**Pour aller plus loin** (facultatif) : Trivy Operator (rapports de vulnérabilités en CRD dans le cluster) et pourquoi il n'est pas retenu ici ; `kubescape scan image` ; remplacer les correctifs en place des nœuds par la **reconstruction** des nœuds depuis une image dorée récente (M03, F1).

---

### M26-E31 — ADR : la stratégie de durcissement et de détection  `RED` `★★`

> **Ticket PLAT-2731** — *De : Claire Morel*
> Le comité d'architecture veut une décision écrite avant l'audit : pourquoi CIS **et** ANSSI, pourquoi OpenSCAP plutôt qu'un produit, pourquoi Kyverno et pas Gatekeeper, pourquoi Falco **et** Tetragon, pourquoi le pare-feu d'hôte de Cilium, et ce que tout cela nous coûte en exploitation.

**Objectifs pédagogiques**
- Rédiger un ADR qui couvre une stratégie (plusieurs couches) sans devenir un catalogue : options réelles, critères pondérés par le contexte, conséquences négatives et actions.
- Relier chaque choix à une exigence (HDS, ISO 27001, référentiels, astreinte) et à une mesure.

**Prérequis** : M26-E01 à E30 ; ADR-0250 (modèle, M25).
**Durée indicative** : 1 h 30.

**Travail demandé**
Rédige `docs/securite/durcissement/adr/ADR-0260-durcissement-et-detection.md` (format des ADR du dépôt) :
1. **Contexte** : l'audit HDS, le modèle de menace (E02), ce qui existait avant le module, les contraintes (équipe, lab, astreinte, logiciels libres, souveraineté).
2. **Décisions et options**, par couche : référentiels (CIS seul, ANSSI seul, les deux, STIG) ; mesure des hôtes (OpenSCAP + ComplianceAsCode, Lynis seul, produit commercial, agent de type Wazuh) ; durcissement (rôle maison, collection communautaire, images dorées seules) ; admission (PSA seule, Kyverno, Gatekeeper, VAP/MAP natives) ; détection à l'exécution (Falco, Tetragon, les deux, kubescape node-agent) ; réseau (WireGuard nœud à nœud, IPsec, maillage de services ; pare-feu d'hôte Cilium, nftables local, rien). Pour chaque couche : au moins deux options comparées sur des critères explicites (couverture, maturité et licence, coût mémoire et processeur dans le lab, compétences, risque pour la disponibilité, preuves fournies à l'auditeur).
3. **Conséquences** positives, et **négatives avec leur action** : faux positifs et fatigue d'alerte, double détection Falco/Tetragon, dépendance à eBPF et au noyau, `ClusterPolicy` disparue en Kyverno 1.20, pare-feu d'hôte et retour arrière, chiffrement nœud à nœud en *beta* et nœuds de contrôle exclus, analyses hebdomadaires et charge, exceptions à revoir.
4. **Conditions de révision** observables (ex. score moyen sous l'objectif deux semaines de suite, plus de N alertes Falco ignorées par semaine, Cilium qui fait passer le chiffrement nœud à nœud en stable, Kyverno 1.20 publié).

**Critères de réussite**
- [ ] L'ADR est sur `main` de `plateforme/medisphere` (MR relue par Sophie et Karim), avec au moins six couches, deux options par couche et des critères explicites.
- [ ] Chaque conséquence négative a une action ou une acceptation signée ; les conditions de révision sont mesurables.

**Pour aller plus loin** (facultatif) : une annexe « matrice de couverture » (menaces d'E02 × contrôles du module : préventif, détectif, correctif) ; la place de gVisor ou Kata Containers pour les charges les plus exposées.

---

### M26-E32 — Questions de production : sécurité  `Q` `★★★`

> *De : Karim Benali* — Avant l'audit, je te pose les questions que l'auditeur ou un candidat senior devrait savoir traiter. Réponds sans relire le module, puis vérifie.

1. Falco produit 300 alertes par jour, dont 290 sont des faux positifs connus. Pourquoi est-ce un problème de **sécurité** et pas seulement de confort, et que fais-tu dans l'ordre ?
2. Une règle Kyverno passée de `Audit` à `Deny` bloque un déploiement de production un vendredi soir. Quelles sont tes trois options, et laquelle choisis-tu selon la nature de la règle ?
3. « Nos nœuds sont durcis à 92 % CIS. » Donne trois raisons pour lesquelles ce chiffre ne prouve pas que le cluster est sûr.
4. Une CVE critique touche le noyau des nœuds. Compare « appliquer le correctif et redémarrer les nœuds un par un » et « reconstruire les nœuds depuis une image dorée corrigée ». Lequel préfères-tu à terme, et qu'est-ce qui te manque aujourd'hui pour le faire ?
5. Pourquoi un conteneur n'est-il pas une frontière de sécurité au même titre qu'une VM ? Cite deux technologies qui rapprochent le conteneur de la VM et leur coût.
6. Le pare-feu d'hôte est appliqué sur les six nœuds. Un pod compromis dans `mediagenda-recette` cherche à joindre etcd. Quelles couches l'en empêchent, dans l'ordre où le paquet les rencontre ?
7. Un auditeur HDS demande « la preuve que le durcissement est appliqué en continu sur toutes les machines depuis six mois ». Que lui fournis-tu, d'où vient chaque pièce, et quelle confiance lui accorder ?
8. Tetragon tue un processus de MédiAgenda en recette. Julien dit que c'est un faux positif. Quelle est ta démarche avant de modifier la politique ?
9. Explique la différence entre une exception **documentée** et une exception **codée**, et pourquoi il faut les deux.
10. La chaîne d'approvisionnement : cite quatre points où une image malveillante pourrait entrer dans `mediagenda-prod` malgré la signature exigée par Kyverno, et le contrôle qui couvre (ou non) chacun.
11. Que perds-tu en sécurité si tu actives `failurePolicy: Ignore` sur le webhook de vérification des signatures ? Et en disponibilité si tu mets `Fail` ?
12. Durcir le SSH des nœuds (`AllowGroups`, algorithmes) a cassé la collecte d'un outil de supervision qui se connectait en SSH. Qui avait raison ? Comment éviter que ça se reproduise ?
13. Pourquoi la détection d'un `kubectl exec` en production par le journal d'audit et par Falco n'est-elle pas redondante ?
14. Quel est l'intérêt d'une analyse de conformité **hebdomadaire** plutôt que quotidienne ou mensuelle ? Qu'est-ce qui pourrait te faire changer de rythme ?

**Durée indicative** : 1 h.

---

### M26-E33 — Préparer la réponse à incident  `LIBRE` `★★★`

> **Ticket SEC-2733** — *De : Sophie Laurent* — *Copie : Nadia Roussel, Claire Morel*
> La dernière question de l'auditeur sera : « un conteneur de production est compromis cette nuit ; que se passe-t-il ? ». Je ne veux pas qu'on invente la procédure ce soir-là.
> Je veux, **préparés à l'avance** : de quoi isoler un pod en une commande sans le tuer, de quoi collecter les preuves sans les abîmer, un endroit où les ranger que personne ne peut effacer, qui fait quoi, et un exercice sur table joué avec Nadia avant l'audit.

**Objectifs pédagogiques**
- Concevoir une capacité de réponse à incident pour des conteneurs : isolement, collecte, conservation des preuves, éradication, rétablissement, communication.
- Préparer les outils **avant** l'incident et les éprouver sans incident réel (exercice sur table, essai sur une charge de test).
- Arbitrer entre conservation des preuves et rétablissement du service.

**Prérequis** : M26-E19 et E20 (Falco, Tetragon), M26-E27 (politiques de cluster), M26-E28 (audit), M15-E28 (politiques de cluster), M16 (sauvegardes, Velero), M00 (PBS), M22 (journaux).
**Durée indicative** : 3 h.

**Contraintes**
- L'isolement repose sur l'étiquette **`medisphere.internal/quarantaine: "oui"`** et une politique de cluster **`quarantaine`** posée **à l'avance** (versionnée, appliquée, testée), qu'aucune politique d'équipe ne peut lever ; un pod isolé ne doit plus rien pouvoir émettre ni recevoir du réseau, et ne doit **pas** être redémarré ou remplacé à cause de l'isolement lui-même (pense aux sondes et au contrôleur qui le possède).
- La collecte ne doit pas modifier ce qu'elle collecte quand on peut l'éviter (pas d'outil installé dans le conteneur suspect), doit être horodatée et accompagnée d'empreintes, et garder la trace de qui a collecté quoi.
- Les preuves vont dans un compartiment **`preuves`** de `s3-01`, avec une identité qui ne peut pas supprimer ; s'il existe un mécanisme de rétention immuable dans ta version de SeaweedFS, utilise-le, sinon documente la compensation.
- Sources à prévoir : alertes Falco, événements Tetragon, journal d'audit de l'API, journaux du pod, Hubble, état du pod et de son nœud ; envisage le *checkpoint* de conteneur par l'API du kubelet (vérifie son statut dans Kubernetes 1.36 avant de t'y fier) et l'instantané du disque du nœud par PBS.
- Rôles : qui décide l'isolement, qui collecte, qui parle aux équipes et à la direction, quand prévenir la RSSI, quand l'incident devient une **violation de données** (RGPD, HDS : délais de notification à vérifier et à citer avec leur source).
- Aucune vraie charge malveillante : l'essai se fait sur un pod de test de `wb-essais`.

**Livrables**
1. La politique `quarantaine` dans le dépôt de la plateforme, appliquée, et la preuve qu'elle isole un pod de test sans qu'il redémarre.
2. Le compartiment `preuves` et son identité, conformes aux contraintes.
3. `docs/securite/durcissement/runbooks/RB-262-reponse-incident-conteneur.md` : détection et qualification, isolement, collecte (ordre, commandes, empreintes, dépôt), analyse, éradication, rétablissement, retour d'expérience ; rôles et contacts ; critères de bascule vers une violation de données.
4. Un compte rendu d'**exercice sur table** (scénario écrit par toi, joué avec Nadia et Sophie, chronologie, décisions, écarts au runbook, actions) dans `docs/securite/durcissement/rapports/`.

**Critères de réussite**
- [ ] La politique de cluster `quarantaine` existe, sélectionne les pods étiquetés `medisphere.internal/quarantaine: "oui"` et refuse tout trafic d'entrée et de sortie, y compris face aux politiques d'autorisation des équipes.
- [ ] RB-262 et le compte rendu d'exercice sur table sont sur `main` de `plateforme/medisphere` ; le runbook cite les commandes réellement éprouvées sur le pod de test.
- [ ] Aucun pod du cluster n'est resté en quarantaine après l'essai.

**Vérification** : `lab/bin/check 26 33`

---

### M26-E34 — Audit de conformité en temps limité  `CHRONO` `★★★`

> **Ticket SEC-2734** — *De : Sophie Laurent*
> L'auditeur avance sa visite : il arrive demain matin. Il me faut ce soir le **rapport de conformité** du parc et du cluster : où on en est, ce qu'on accepte, ce qu'on corrige et quand. Tu as une heure.

**Objectifs pédagogiques**
- Produire sous contrainte de temps un rapport de conformité exploitable par un auditeur, à partir des seuls outils en place.
- Hiérarchiser des écarts (gravité, exposition, coût) et proposer un plan de remédiation daté.

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé (cet exercice n'en a pas). Tes runbooks, tes tableaux de bord, tes requêtes enregistrées, la documentation officielle sont permis.
- Sources permises : les métriques et le tableau « Conformité » (E24), le compartiment `conformite` (lecture), les rapports Kyverno (`PolicyReport`), kube-bench et kubescape (E05, relancés si tu veux), le registre des exceptions (E23), les alertes en cours, `cve-en-service.sh` (E30). Aucune modification du parc ou du cluster pendant l'heure.
- Durée : **60 minutes** entre le début (note l'heure dans le rapport) et le rapport poussé sur `main`.

**Prérequis** : paliers 1 à 3 du module, en particulier E05, E18, E23, E24, E30.
**Durée** : 1 h chronométrée + 30 minutes de retour d'expérience.

**Livrable** : `docs/securite/durcissement/rapports/<AAAA-MM-JJ>-audit-conformite.md` dans `plateforme/medisphere`, avec au moins :
1. **Périmètre et méthode** : hôtes et cluster couverts, référentiels et versions des outils, date des mesures utilisées, limites ;
2. **Synthèse** : score par référentiel (moyenne, minimum, hôte le plus faible), évolution sur 30 jours, admission (politiques en refus, violations en cours), détection (Falco/Tetragon actifs, alertes des 7 derniers jours), chiffrement et pare-feu d'hôte (état) ;
3. **Écarts** : tableau (identifiant de règle ou de contrôle, périmètre, gravité, exposition, statut : à corriger / exception signée / faux positif) ;
4. **Exceptions** en vigueur, avec leur date de revue (et celles qui ont expiré) ;
5. **Plan de remédiation priorisé** : au moins cinq actions datées, avec un responsable ;
6. **Retour d'expérience** (après l'heure) : ce qui t'a manqué, la requête ou le tableau que tu aurais voulu avoir.

**Critères de réussite**
- [ ] Le rapport est sur `main` de `plateforme/medisphere`, daté de moins de 7 jours, et contient les six sections ; les scores cités correspondent aux métriques du moment (à 5 points près).
- [ ] Le plan de remédiation compte au moins cinq actions datées avec un responsable.
- [ ] Le retour d'expérience propose une amélioration concrète, ajoutée ensuite à `plateforme/observabilite` ou à la documentation.

**Vérification** : `lab/bin/check 26 34` (à lancer à la fin)

**Pour aller plus loin** (facultatif) : refais l'exercice dans un mois en visant 40 minutes, et compare les deux rapports : qu'est-ce qui a bougé, et le rapport précédent l'avait-il prévu ?
