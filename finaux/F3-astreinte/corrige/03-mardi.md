# Final F3 — Corrigé de la phase 3 : mardi

> ⚠️ Corrigé. À n'ouvrir qu'après avoir cherché (et **jamais** pendant S07).

**Points non testés en conditions réelles** : délai de prise en compte de la métadonnée `TSIG-ALLOW-DNSUPDATE` par l'autoritaire (cache des métadonnées de PowerDNS, `zone-metadata-cache-ttl`, 60 s par défaut) ; comportement exact de containerd 2.3 au redémarrage avec un `config.toml` invalide (les conteneurs déjà lancés survivent grâce à `KillMode=process`, à vérifier sur ton nœud : `systemctl show containerd -p KillMode`) ; libellés exacts des messages de kubelet 1.36 pour une option inconnue.

---

### F3-S05 — Mardi : les certificats ne se renouvellent plus

**Démarche de diagnostic**

*Symptômes* : `wb-pannes/repetition-joker` reste `Ready=False` ; le vrai joker est encore valide.

1. **Urgence** : `kubectl get certificates -A` (colonnes `notAfter`, `renewalTime`). `apps-joker` est valide encore une vingtaine de jours et sera renouvelé 10 jours avant : **SEV3** (« la plateforme ne pourra plus renouveler ; échéance dans N jours »), qui deviendrait SEV2 sous 72 h.
2. **Suivre la chaîne** (RB-332 §2) : `cmctl status certificate repetition-joker -n wb-pannes`, puis `describe` de la `CertificateRequest`, de l'`Order`, du `Challenge`, et de la `ClusterIssuer`.
3. Selon l'étage :

**Variante 1 — la zone refuse les mises à jour de cert-manager**

- `Challenge` : `presented: false`, raison du type `DNS update failed: … REFUSED` (ou `NOTAUTH`). L'émetteur est prêt, l'ACME répond : le problème est côté DNS.
- Sur `dns01` :
  ```
  admin@dns01:~$ sudo -u pdns pdnsutil metadata get apps.par1.medisphere.internal TSIG-ALLOW-DNSUPDATE
  TSIG-ALLOW-DNSUPDATE = externaldns-k8s
  admin@dns01:~$ sudo journalctl -u pdns --since -30min | grep -i update
  ```
  La clé `certmanager-k8s` existe toujours (`pdnsutil tsigkey list`), mais elle n'est plus **autorisée** sur la zone. ExternalDNS, lui, fonctionne : la panne est sélective.
- Origine : la métadonnée est déclarée dans `group_vars/role_dns/dnsupdate-k8s.yml` (`cles: [certmanager-k8s, externaldns-k8s]`, M15-E14) ; elle a été changée à la main sur `dns01` (« nettoyage » de Lucas : `journalctl _COMM=sudo` sur `dns01`).
- Correction par le code : rejouer le rôle `powerdns_auth` sur `dns01` (d'abord `--check --diff`, qui montre la métadonnée à rétablir), puis `cmctl renew repetition-joker -n wb-pannes`.

**Variante 2 — l'émetteur interroge un mauvais répertoire**

- `ClusterIssuer step-ca-acme` : `Ready=False`, `Failed to register ACME account: … 404` ; `spec.acme.server` vaut `…/acme/acme-v2/directory`. Le provisioner ACME de `ca01` s'appelle `acme` (M06) : `/acme/acme/directory`.
  ```
  admin@adm01:~$ curl -s --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt https://ca01.par1.medisphere.internal/acme/acme/directory | jq .
  admin@adm01:~$ kubectl get clusterissuer step-ca-acme -o yaml | yq '.metadata.managedFields[] | {manager, time}'
  ```
  `managedFields` montre un `kubectl-patch` récent : dérive à la main par rapport à `plateforme/k8s/composants/cert-manager/clusterissuer-step-ca-acme.yaml`.
- Correction par le code : réappliquer le fichier du dépôt par le chemin du M15 (même méthode que l'installation : `kubectl apply --server-side` du composant ou la tâche du `Taskfile`), vérifier `Ready=True`, renouveler la répétition. Ticket : faire suivre la `ClusterIssuer` par Argo CD (Application de plateforme) pour que la dérive soit vue et corrigée.

**Variante 3 — la bordure jette l'ACME des travailleurs**

- `Order` / `Challenge` : erreurs de délai vers `ca01` (`context deadline exceeded`, `i/o timeout`) ; l'émetteur peut rester `Ready` (compte déjà enregistré). Depuis `adm01`, `ca01` répond : la panne ne touche que certains chemins.
- Essai depuis un travailleur (pod jetable de `wb-essais`, ou `ssh k8s-w01 curl -sv https://ca01.par1.medisphere.internal/health`) : délai dépassé. Sur la passerelle **maîtresse** (`ip -br a | grep 10.10.20.1` pour la savoir) :
  ```
  admin@gw01:~$ sudo nft -a list chain inet filter forward | head -5
      ip saddr { 10.10.40.0/24, 10.240.0.0/16 } ip daddr 10.10.20.11 tcp dport 443 counter packets 42 bytes 2520 drop comment "PLAT-3305 durcissement provisoire" # handle 87
  admin@gw01:~$ sudo nft -c -f /etc/nftables.conf && grep -c PLAT-3305 /etc/nftables.conf
  0
  ```
  La règle a été ajoutée **à chaud** (sur les deux passerelles) ; elle n'est pas dans `/etc/nftables.conf` ni dans la matrice des flux (`group_vars/role_routeur/pare_feu.yml`) : `ansible-playbook … --check --diff` ne la voit pas (le fichier n'a pas changé).
- Correction par le code : remettre ce que décrit le code, une passerelle à la fois, la **secondaire** d'abord : `sudo systemctl reload nftables` (le fichier commence par `flush ruleset` et recharge la matrice écrite), puis la maîtresse ; vérifier la règle `VLAN 40 → ca01 443` de la matrice (M15) et ses compteurs. Si un durcissement était voulu (PLAT-3305 existe-t-il ?), il passe par une MR de la matrice des flux, revue.
- Prévention : un contrôle planifié qui compare `nft list ruleset` à la configuration écrite (empreinte) sur les passerelles, alerte en cas d'écart (ticket PLAT-3305-a) ; la répétition hebdomadaire devient une alerte (Pour aller plus loin).

**Messages d'état types** (SEV3) : début « la plateforme ne peut plus délivrer de certificats ; aucun service touché aujourd'hui ; le certificat commun des services publiés échoit dans N jours ; prochain point HH:MM » ; fin « cause : <métadonnée DNS | adresse de l'émetteur | règle de pare-feu> modifiée à la main le <date> ; rétabli par la configuration du dépôt ; répétition délivrée à HH:MM ; prévention : <…> ».

**Main courante attendue** : `[ouverture]` avec l'échéance du joker, `[action]` étage par étage (message exact de l'objet qui bloque), `[action]` origine (qui, quand : `managedFields`, journal `sudo`, compteurs nft), `[décision]` si le geste touche la bordure (rechargement nftables, une passerelle à la fois, retour arrière : `nft -f` de la sauvegarde), `[clôture]`.

Runbook : [`RB-332-certificats-acme.md`](fichiers/S05/medisphere/docs/exploitation/runbooks/RB-332-certificats-acme.md).

**Explications**

cert-manager découpe une émission en objets successifs, chacun avec sa condition et ses événements : l'objet le plus en aval qui n'avance pas dit l'étage. Les trois variantes sont trois dialogues différents (le cluster vers l'ACME, le cluster vers l'autoritaire DNS, la configuration de l'émetteur) et trois **dérives à la main** de choses qui sont décrites dans le code. Le point commun pédagogique : `--check --diff` ne voit que ce que le code gère ; une règle nftables ajoutée à chaud ou une métadonnée changée par `pdnsutil` sont invisibles tant qu'on ne compare pas l'état **réel** à l'état **écrit**.

**Alternatives**

- Variante 1 : `pdnsutil metadata add` pour remettre la seule valeur manquante (rapide), puis rôle Ansible pour vérifier : acceptable si consigné.
- Variante 3 : `nft delete rule inet filter forward handle <N>` sur chaque passerelle : rapide, mais ne prouve pas que le reste du jeu de règles est conforme ; le rechargement de la configuration écrite le prouve.
- Délivrer un certificat par HTTP-01 pour débloquer : impossible pour un joker.

**Pièges classiques**

- Recharger nftables sur la passerelle maîtresse d'abord, ou sur les deux en même temps : une erreur de syntaxe coupe tout le lab (le fichier est validé par `nft -c` avant).
- Corriger la variante 3 sur la seule maîtresse : à la prochaine bascule VRRP, la panne revient.
- Supprimer et recréer la `ClusterIssuer` : nouveau compte ACME, et tous les certificats repassent par une émission.
- Désactiver la vérification TLS de l'émetteur (`skipTLSVerify`) « pour voir » : interdit, et inutile (le problème n'est pas TLS).

**En production chez MédiSphère**

Tout ce qui est décrit dans le code est **comparé** régulièrement à l'état réel (Argo CD pour le cluster, `--check` planifié pour Ansible, `tofu plan` planifié pour l'infrastructure, empreinte du jeu de règles des passerelles) ; les certificats ont une alerte d'échéance à 14 jours et une alerte de non-renouvellement (`certmanager_certificate_ready_status`), et la répétition de renouvellement est hebdomadaire.

---

### F3-S06 — Mardi : un nœud tombe malade

**Démarche de diagnostic**

*Symptômes* : alertes sur un travailleur, pods de recette replanifiés.

1. **Impact** : `kubectl get nodes` ; pods du nœud (`--field-selector spec.nodeName=…`) ; évincés (`status.phase=Failed`). Ce qui est critique : la production a perdu un réplica de base (CNPG : pod du nœud non prêt, réplication synchrone encore assurée par l'autre réplica), un nœud RabbitMQ (quorum 2/3 : OK), des pods de l'API (remplacés). **Capacité** : `kubectl describe nodes | grep -A5 'Allocated resources'` sur les deux autres. Gravité : SEV2 (redondance perdue, production à risque si un second nœud tombe), message d'état sous 30 min.
2. **Condition du nœud** : `DiskPressure` (variante 1) ou `NotReady` avec « Kubelet stopped posting node status » (variantes 2 et 3).
3. **Sur le nœud** (SSH : il répond, c'est la machine qui va bien, pas Kubernetes) :

**Variante 1 — disque plein**

- `df -h /var/lib/kubelet` : 96 % ; `sudo du -xh --max-depth=2 /var | sort -h | tail` → `/var/log/medisphere` ; `ls -la --time-style=full-iso /var/log/medisphere/` : un fichier `trace-debug-mediagenda.log` de plusieurs dizaines de Go, d'aujourd'hui, sans contenu lisible (`fallocate`) ; aucun service n'écrit dedans (`sudo lsof +D /var/log/medisphere`).
- Le kubelet a franchi son seuil d'éviction (`nodefs.available < 10 %`) : il a d'abord fait le ménage des images, puis évincé des pods (les `BestEffort` puis les plus gros consommateurs) ; *taint* `node.kubernetes.io/disk-pressure`.
- Rétablissement : après avoir identifié l'auteur (Lucas : « des traces de débogage pour Julien ») et vérifié qu'il n'y a rien à garder, suppression du fichier ; la pression disparaît en moins d'une minute, le *taint* aussi. Ménage des pods évincés (`kubectl delete pod -A --field-selector status.phase=Failed` après lecture de la liste).
- Prévention : alerte de remplissage des disques des nœuds **avant** le seuil d'éviction (80 %, RB-213) ; `/var/log` des nœuds réservé aux journaux système (journald borné), les traces applicatives vont dans Loki.

**Variante 2 — kubelet ne démarre plus**

- `systemctl status kubelet` : `activating (auto-restart)` en boucle ; `journalctl -u kubelet -b | tail` : `unknown flag: --max-pod` (« Error: failed to parse kubelet flag »).
- `/etc/default/kubelet` (lu par le drop-in de kubeadm) : `KUBELET_EXTRA_ARGS="… --max-pod=150"`, modifié aujourd'hui. Le bon nom serait `--max-pods`, et de toute façon ce réglage appartient à la `KubeletConfiguration` (`maxPods`), pas aux options.
- Rétablissement et correction : rôle `k8s_travailleur` (ou `k8s_noeud`, selon qui gère ce fichier) rejoué sur ce nœud (`--check --diff` d'abord : il montre la ligne à retirer), qui redémarre kubelet ; à défaut, restaurer la version du rôle à la main et rejouer le rôle ensuite. Le nœud repasse `Ready` en moins d'une minute.
- Si le rôle ne gère pas `/etc/default/kubelet` : c'est le trou que la panne a montré ; le rôle doit gérer **tout** fichier qui change le comportement du kubelet (ticket PLAT-3306-a, ou MR directement).

**Variante 3 — containerd ne démarre plus**

- `systemctl status containerd` : `failed` ; `journalctl -u containerd -b | tail` : erreur de lecture de `/etc/containerd/config.toml` (table TOML non fermée) ; kubelet journalise `container runtime is down` / `connection refused` sur `/run/containerd/containerd.sock`.
- Les conteneurs du nœud **tournent encore** (`ps -ef | grep containerd-shim`) : `KillMode=process` dans l'unité de containerd.io laisse vivre les *shims* ; c'est pour cela que les pods du nœud ont continué à répondre un moment. Mais sans runtime, plus rien ne démarre ni ne s'arrête, et le nœud est `NotReady`.
- Fin du fichier : un bloc « Miroir interne pour les images de la plateforme (Lucas, PLAT-3306) ». Les miroirs du lab sont déjà configurés par `hosts.toml` (rôle `containerd`, M14) : ce bloc était inutile **et** invalide.
- Correction : rôle `containerd` rejoué sur ce nœud (`--check --diff` puis application) ; containerd redémarre, reprend les conteneurs existants ; kubelet repasse `Ready`.

**Pourquoi pas l'horloge** (Pour aller plus loin de l'énoncé) : une dérive d'horloge sur un travailleur casse, dans l'ordre, la validation TLS par le kubelet du certificat de l'API (s'il recule avant sa date de début), les tickets `cephx` des volumes RBD montés (E/S bloquées), les poignées de main WireGuard de Cilium (un horodatage plus ancien que le dernier vu est rejeté par les pairs comme un rejeu, **même après** correction de l'heure si elle a avancé), les jetons projetés. Elle se voit avant de casser par `node_timex_offset_seconds` et `node_timex_sync_status` (node_exporter) : alerte à 100 ms. L'injection ne la pratique pas : le retour arrière n'est pas sûr.

**Messages d'état types** (SEV2) : début « un serveur du cluster est hors service ; la production fonctionne sur les deux autres, sans marge ; diagnostic en cours ; prochain point HH:MM » ; fin « serveur rétabli à HH:MM ; cause : <disque rempli par un fichier de diagnostic | configuration du service de nœud modifiée à la main> ; capacité complète ; prévention : <…> ».

**Main courante attendue** : `[ouverture]` (nœud, condition, impact sur la production), `[action]` capacité restante (chiffres), `[action]` cause sur le nœud (fichier, date, auteur), `[décision]` réparer en place plutôt que vider le nœud (pourquoi), `[action]` rôle rejoué (`--check` puis application), `[clôture]`.

Runbook : [`RB-333-noeud-travailleur-malade.md`](fichiers/S06/medisphere/docs/exploitation/runbooks/RB-333-noeud-travailleur-malade.md).

**Explications**

`Ready` et les conditions de pression sont posés par le kubelet lui-même ; quand le kubelet ne peut plus rien dire (arrêté, ou sans runtime), c'est le contrôleur de nœuds qui constate le silence au bout de `node-monitor-grace-period` (50 s) et passe le nœud en `Unknown`, puis évince ses pods au bout de 5 min (*taints* `NoExecute` et `tolerationSeconds: 300`). Les pods de StatefulSet ne sont pas recréés ailleurs tant que leur ancien pod n'est pas confirmé arrêté : c'est une protection contre le « cerveau divisé », pas une panne. Le diagnostic se fait donc **sur** le nœud, avec systemd et les fichiers.

**Alternatives**

- Vider le nœud (`kubectl drain`) puis le reconstruire par le code (OpenTofu + Ansible) : la bonne réponse si la cause n'est pas trouvée en 30 min ou si le nœud est suspect ; ici, la cause est trouvée et la réparation sûre.
- Redémarrer la VM : rétablit la variante 3 si containerd repart… non, il échouera de nouveau au démarrage ; ne règle rien en variantes 1 et 2 non plus.

**Pièges classiques**

- `kubectl delete node` « pour forcer la replanification » : le nœud perd son objet, ses étiquettes et ses *taints* (`dedie=bdd` sur `k8s-w03`) ; il revient sans eux à la reconnexion du kubelet.
- Forcer la suppression des pods `Terminating` de StatefulSet pendant que le nœud peut revenir : deux exemplaires possibles du même pod.
- Supprimer des fichiers dans `/var/lib/containerd` pour libérer de la place.
- Corriger le fichier à la main sans rejouer Ansible : la dérive suivante passera aussi inaperçue.

**En production chez MédiSphère**

Passe Ansible en `--check` planifiée sur tous les nœuds (dérive détectée la nuit), alertes sur `kubelet` et `containerd` (`up{job="kubelet"}`, `node_systemd_unit_state` si le collecteur systemd est activé), alerte de disque à 80 % et journaux applicatifs hors des nœuds ; un nœud suspect se vide et se reconstruit (bétail, pas animal de compagnie).

---

### F3-S07 — Mardi soir : incident chronométré

Le script tire une panne d'un réservoir de pannes déjà traitées dans les modules et l'injecte par le script du module lui-même. Le corrigé de chaque possibilité est celui du module :

| Tirage | Panne | Corrigé | Ce que le check de S07 vérifie |
|---|---|---|---|
| `15:40` | M15-E40 « le certificat n'est jamais délivré » (TSIG, `caBundle`, sélecteur DNS-01, `kind` de l'émetteur) | [`modules/15-kubernetes-reseau/corrige/04-expert.md`](../../../modules/15-kubernetes-reseau/corrige/04-expert.md) | `step-ca-acme` prêt ; `wb-essais/joker-repetition` prêt s'il existe |
| `16:41` | M16-E41 « l'archivage des WAL échoue » (identifiants, compartiment, CA de l'`ObjectStore` `cnpg-s3`) | [`modules/16-kubernetes-stockage/corrige/04-expert.md`](../../../modules/16-kubernetes-stockage/corrige/04-expert.md) | condition `ContinuousArchiving` vraie sur `mediagenda-db` (recette) |
| `27:20` | M27-E20 « MédiNotif ne consomme plus » (permission, message empoisonné sans limite de livraison, nom de file) | [`modules/27-donnees-messaging/corrige/04-expert.md`](../../../modules/27-donnees-messaging/corrige/04-expert.md) | file `notifications` du vhost `medinotif-recette` : au moins un consommateur, moins de 100 messages prêts |
| `27:22` | M27-E22 « le cache ne sert plus » (ACL, `noeviction`, certificat d'une autre autorité) | [`modules/27-donnees-messaging/corrige/04-expert.md`](../../../modules/27-donnees-messaging/corrige/04-expert.md) | `/pret` de la recette à 200, aucune erreur de cache sur 5 min |
| `28:19` | M28-E19 « MédiNotif ne monte plus en charge » (KEDA en pause, vhost faux) | [`modules/28-plateforme-dev/corrige/04-expert.md`](../../../modules/28-plateforme-dev/corrige/04-expert.md) | `ScaledObject` `medinotif` (recette) prêt, sans pause, sur le bon vhost |

**Ce qui est évalué en plus de la réparation** (check et auto-évaluation) :
- l'heure d'ouverture est celle de l'appel, la clôture tombe dans les 45 min ;
- un message d'état au moins toutes les 15 min (le check exige `durée / 15` entrées `[état]`, au moins une) et au moins un courriel ;
- la gravité : toutes ces pannes touchent la recette ou des objets d'essai → **SEV3** (SEV4 défendable pour M15-E40 si le joker réel n'est pas menacé) ; un SEV3 de nuit n'appelle personne : le rétablissement peut même attendre le matin si la procédure le dit — à condition de l'écrire en `[décision]`. Une astreinte qui réveille Claire pour la recette à 21 h a mal classé ;
- le recours aux runbooks : l'index (S01) mène en une minute au runbook du module (RB-151, RB-167, RB-277, RB-279, RB-285).

**Explications** : un chronométré mesure le **tri** plus que la virtuosité : qualifier vite (environnement, impact, gravité), retrouver le runbook, rétablir, écrire. Ceux qui dépassent le temps l'ont presque toujours perdu au début, en diagnostiquant avant d'avoir situé l'environnement touché.

**Pièges classiques** : diagnostiquer en production une panne de recette ; oublier les messages d'état « parce qu'on est presque au bout » ; ouvrir le corrigé du module « juste pour vérifier ».

**En production chez MédiSphère** : les incidents de nuit sur la recette attendent le matin sauf démo ou campagne annoncée ; la procédure le dit, l'astreinte le consigne.
