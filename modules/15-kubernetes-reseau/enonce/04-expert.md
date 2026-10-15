# Module 15 — Palier 4 : Expert

Le réseau de `k8s-par1` est en service : Cilium remplace kube-proxy, les IP de service sont attribuées par LB IPAM et annoncées en BGP à la bordure, la Gateway `gw-par1` sert le HTTPS de `*.apps.par1.medisphere.internal` avec un joker délivré par cert-manager, ExternalDNS publie les noms, les espaces `mediagenda-*` sont fermés par défaut et le trafic entre nœuds est chiffré. Nadia Roussel pose la question rituelle : « Et quand ça casse un dimanche soir, par où tu commences ? » Karim Benali a préparé huit pannes, celles que les post-mortems publics et les forums racontent le plus souvent : un Service qui ne mène nulle part, un DNS qui ne répond plus dans les pods, un espace de noms muré par une politique, une adresse de service que personne ne route, une Gateway qui refuse le TLS, un certificat qui ne vient jamais, un nom qui n'est plus publié, des pods qui ne se joignent plus d'un nœud à l'autre. Une astreinte en combine trois. Puis tu descends dans les tables eBPF de Cilium, et tu passes les questions d'entretien.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec trois règles propres au réseau d'un cluster :
- **Suis le chemin, couche par couche.** Nom (DNS public, puis DNS du cluster) → adresse (LB IPAM, annonce BGP, route de la bordure) → écouteur (Gateway, TLS, `allowedRoutes`) → route (`HTTPRoute`, ses conditions) → Service (port, sélecteur, EndpointSlice) → pod (prêt, sonde) → politique (L3/L4/L7) → nœud (agent Cilium, tunnel, chiffrement). Chaque étage a son outil et sa preuve ; ne saute pas d'étage parce que « ça ressemble à ».
- **Lis les conditions avant les journaux.** Gateway API, cert-manager, LB IPAM et ExternalDNS écrivent leur diagnostic dans `status.conditions` (`Accepted`, `ResolvedRefs`, `Programmed`, `Ready`, `io.cilium/lb-ipam-request-satisfied`…) et dans les événements (`kubectl events`). Hubble dit ce qui est jeté, par qui et pourquoi (`hubble observe --verdict DROPPED`). Les journaux viennent ensuite.
- **L'état réel peut différer du dépôt.** Tout le réseau du cluster est décrit dans `plateforme/k8s` (M15-E23) et la bordure dans `plateforme/ansible`. Une modification à chaud qui « répare » sans passer par le dépôt sera défaite au prochain `task appliquer` ou rejeu Ansible ; à l'inverse, une dérive à chaud est souvent **la** cause. `kubectl diff`, `helm get values`, `vtysh -c 'show running-config'` comparé à `/etc/frr/frr.conf` sont des outils de diagnostic à part entière.

> **Rappels** : tout se lance depuis `adm01` avec ton kubeconfig personnel (`~/.kube/config`, groupe `medisphere:plateforme-admins`). Les CLI `cilium` et `hubble` y sont installées (M14). Dans un agent Cilium, la commande de diagnostic s'appelle `cilium-dbg` : `kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status` (le `ds/cilium` choisit un pod au hasard ; pour un nœud précis, prends le pod de ce nœud : `kubectl -n kube-system get pods -l k8s-app=cilium -o wide`). Les nœuds se joignent en SSH (`admin` + sudo), la bordure aussi (`gw01`, `gw02`).

## Règles du jeu des pannes (M15-E35 à M15-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 15 35
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 à 5 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle). Si une variante ne s'applique pas à ton lab (objet absent, choix différent du tien dans un exercice précédent), le script en essaie une autre. Une injection prend de quelques secondes à cinq minutes : certaines attendent que le symptôme soit réellement observable (rechargement de CoreDNS, retrait des routes après le redémarrage gracieux BGP, intervalle d'ExternalDNS).
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 15 35`) : il doit être vert. Le script de panne refuse d'ailleurs de casser un cluster où `https://mediagenda-recette.apps.par1.medisphere.internal/pret` ne répond pas 200 depuis `adm01`, ou dont les témoins ne se joignent pas d'un travailleur à l'autre.
- **Témoins.** À la première injection, le script crée (s'ils n'existent pas) des témoins qu'il ne supprime jamais :
  - l'espace `wb-pannes` (PSA `baseline`) ;
  - le DaemonSet `sonde` : un pod par travailleur, image `nicolaka/netshoot:v0.16` tirée par le cache Harbor (`registry.par1.medisphere.internal/dockerhub/…`). Chaque pod répond `sonde-<nœud>` sur le port TCP 8080 et contient `dig`, `curl`, `nc`, `tcpdump`, `iperf3`. C'est ton premier instrument : `kubectl -n wb-pannes exec <pod> -- nc -w 3 <IP-d-un-autre-pod> 8080` ;
  - la NetworkPolicy `sonde-interne` : trafic interne à l'espace et DNS vers `kube-dns`, rien d'autre.

  Si ta politique de base à l'échelle du cluster (M15-E28) isole les espaces au point d'interdire le trafic interne à `wb-pannes`, la préparation échoue avec un message clair : ajoute une exception pour cet espace dans `plateforme/k8s` (MR), c'est un bon exercice. Les témoins ne gênent pas le mini-projet ; tu peux supprimer `wb-pannes` après la recette (M15-E46).
- Certaines pannes ajoutent un **objet témoin** propre à leur ticket (un Service, une route, un certificat) : le ticket le nomme. L'annulation les supprime.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `~/.local/state/workbook/` sur `adm01`, ni `/var/lib/workbook/` sur les nœuds et la bordure : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 15 35 --annuler` remet l'état sain (filet de sécurité, pas un correctif : compte l'exercice comme non réussi). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne (sinon elle reste marquée active et bloque l'astreinte M15-E43 et le mini-projet) : l'annulation ne rétablit que ce qui porte encore la marque de la panne et ne revient jamais sur ta réparation.
- **Où agissent les pannes.** Objets du cluster dans `wb-*`, `mediagenda-*`, `passerelles`, `cert-manager`, `external-dns` et `kube-system` (Corefile, configuration de Cilium), avec le kubeconfig d'administration ; les travailleurs `k8s-w01` à `w03` par SSH (configuration courante uniquement, rien d'écrit sur disque) ; et, pour une seule variante, la **passerelle de secours** de la bordure (celle qui ne porte pas la VIP 10.10.40.1), dans la configuration courante de FRR. Jamais la VIP, jamais keepalived, jamais `pve01` ni son réseau, jamais `pbs01`. Aucune donnée n'est détruite ; chaque objet modifié est sauvegardé avant.
- **Ta réparation passe par le code.** Une correction à chaud est permise pour rétablir le service ; elle doit ensuite être reportée dans `plateforme/k8s` ou `plateforme/ansible` par une MR (ou la cause doit être retirée du dépôt si c'est là qu'elle se trouve), sinon le prochain `task appliquer` ou le prochain rejeu la défera. Le contrôle vérifie l'état réel ; la revue de Karim vérifiera le dépôt.
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/kubernetes/journal/` de `~/medisphere` (publié par MR) : heure, hypothèse, commande, résultat observé, conclusion. Il alimente le post-mortem de M15-E43.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Attention — bordure** : une panne peut concerner une passerelle. Tu ne **bascules jamais** la VIP pour « tester » (pas de `systemctl stop keepalived`, pas d'arrêt de `gw01`/`gw02`) : la bascule coupe les tunnels WireGuard et toutes les sessions de l'atelier. Sur FRR, préfère `vtysh -c 'show …'` ; pour corriger, rejoue le playbook de la bordure (`playbooks/bordure-frr.yml`, qui fait un `reload` sans couper les sessions) plutôt qu'un `systemctl restart frr` qui fait tomber **toutes** les sessions BGP de la passerelle.

> ⚠️ **Attention — pare-feu des nœuds** : sur un nœud Kubernetes, Cilium et kubelet posent leurs propres règles (tables `cilium_*`, chaînes `KUBE-*` en mode iptables-nft). Pour retirer une règle posée à côté d'eux, supprime **la** table ou **la** règle en cause (`nft delete table …`, `nft delete rule … handle N`), jamais `nft flush ruleset` ni `iptables -F` : tu effacerais aussi les règles dont dépendent les pods du nœud, jusqu'au prochain redémarrage de l'agent Cilium.

> ⚠️ **Attention — agents Cilium** : redémarrer l'agent d'**un** nœud (`kubectl -n kube-system delete pod <cilium-xxxxx>`) est sans risque pour les connexions en cours (le chemin de données eBPF reste chargé pendant le redémarrage). Redémarrer **tous** les agents à la fois (`kubectl rollout restart ds/cilium`) pendant une panne réseau rend le diagnostic impossible et peut aggraver la coupure : un nœud à la fois, et seulement quand tu sais pourquoi.

---

### M15-E35 — Panne : le service ne répond plus  `BF` `★★`

> **Ticket INC-4241** — *De : Julien Petit*
> *(Le détail du ticket s'affiche à l'injection.)* La recette de MédiAgenda renvoie une erreur 5xx alors que les pods tournent. Démonstration client à 15 h.

**Objectifs pédagogiques**
- Remonter de l'erreur HTTP de la Gateway jusqu'au Service, à son EndpointSlice et aux pods, et distinguer « aucun point de terminaison », « point de terminaison injoignable » et « port de Service introuvable ».
- Lire les conditions d'une `HTTPRoute` (`Accepted`, `ResolvedRefs`) et ce que Cilium programme pour un Service (`cilium-dbg service list`).
- Compléter le runbook RB-150 (M15-E22) avec ce que la panne t'a appris.

**Prérequis** : M15-E03, M15-E07, M15-E12, M15-E22 ; `lab/bin/check 15 35` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : la route `mediagenda` (espace `mediagenda-recette`) envoie le trafic de `mediagenda-recette.apps.par1.medisphere.internal` vers le Service de l'API (`mediagenda-api`, port 80, premier `backendRefs` de la route). MédiAgenda écoute sur le port 8000 du conteneur (port nommé `http`) et expose `/sante` (vivacité) et `/pret` (disponibilité). Le proxy de la Gateway de Cilium (Envoy) envoie directement aux adresses des pods que Cilium lui donne à partir des EndpointSlices.

**Injection** : `lab/bin/break 15 35` (3 variantes).

**Travail demandé**
1. Reproduis depuis `adm01` avec `curl -sv` : code exact, corps de la réponse, en-têtes ajoutés par Envoy. Qu'est-ce que ce code dit, et ne dit pas, de l'étage en cause ?
2. Lis les conditions de la route et l'état de la Gateway. Puis descends : Service (ports, `targetPort`, sélecteur), EndpointSlices (adresses, ports, `ready`), pods (étiquettes, ports déclarés, état de préparation).
3. Pour chaque étage, écris dans ton journal la commande et la preuve que l'étage est sain ou cassé. Vérifie ton hypothèse **depuis l'intérieur du cluster**, sans la Gateway : depuis un pod témoin, joins le Service par son nom, puis un pod par son adresse.
4. Trouve ce qui a changé et qui l'a changé (dépôt `plateforme/k8s` pour la route, `mediagenda/api` — dossier `k8s/recette/`, M14 — pour le Service, `kubectl diff`, champ `managedFields`), corrige à la racine (dépôt et cluster), et vérifie de bout en bout.
5. Ajoute à RB-150 une section « Erreur 5xx de la Gateway » : l'arbre « route → Service → EndpointSlice → pod », avec pour chaque branche la commande et ce qu'elle doit montrer.

**Critères de réussite**
- [ ] `https://mediagenda-recette.apps.par1.medisphere.internal/pret` répond 200 depuis `adm01`.
- [ ] La route est acceptée et ses références résolues ; l'EndpointSlice du Service contient des points de terminaison prêts sur le port réel de l'application.
- [ ] Ton journal contient la preuve de l'étage en cause et la commande qui l'a montrée ; RB-150 est complété et publié ; la correction est dans le dépôt.

**Vérification** : `lab/bin/check 15 35`

<details><summary>Indice 1</summary>

`kubectl -n mediagenda-recette get httproute mediagenda -o yaml` (bloc `status.parents`), `kubectl -n mediagenda-recette get svc,endpointslices -o wide`, `kubectl -n mediagenda-recette get pods --show-labels -o wide`. Une EndpointSlice sans adresse et une EndpointSlice dont les adresses répondent « connexion refusée » ne mènent pas au même étage.
</details>

<details><summary>Indice 2</summary>

`kubectl get svc <svc> -o jsonpath='{.spec.selector}'` comparé à `--show-labels` ; `kubectl get pod <pod> -o jsonpath='{.spec.containers[*].ports}'` comparé au `targetPort` ; le `port` du Service comparé au `port` du `backendRefs` de la route. Dans un agent : `cilium-dbg service list` montre le frontal et ses backends avec leurs ports.
</details>

<details><summary>Indice 3</summary>

`kubectl get svc <svc> -o yaml --show-managed-fields` montre quel gestionnaire (`kubectl-edit`, `kubectl-client-side-apply`, `helm`…) a écrit chaque champ, et quand. `git log -p` dans `mediagenda/api` (`k8s/recette/`) dit si le changement y est.
</details>

**Pour aller plus loin** : ajoute au pipeline de `mediagenda/api` (ou à un test local `kubeconform` + `jq`) une vérification qui échoue si le sélecteur d'un Service ne correspond à aucune étiquette de gabarit de Deployment du même rendu, ou si un `targetPort` ne correspond à aucun `containerPort`.

---

### M15-E36 — Panne : la résolution DNS échoue dans les pods  `BF` `★★`

> **Ticket INC-4242** — *De : Julien Petit*
> *(Le détail du ticket s'affiche à l'injection : selon le cas, des noms internes de MédiSphère qui ne résolvent plus, ou un déploiement dont les nouveaux pods ne sont jamais prêts.)*

**Objectifs pédagogiques**
- Suivre une requête DNS depuis un pod : `resolv.conf` du pod (selon `dnsPolicy`), Service `kube-dns`, pods CoreDNS, bloc du Corefile qui répond, résolveur amont.
- Distinguer une panne de CoreDNS, une panne de politique (la requête n'arrive jamais) et une panne de configuration du pod.
- Prouver chaque hypothèse avec Hubble et `dig`, depuis le bon point du chemin.

**Prérequis** : M15-E04, M15-E05, M15-E06, M15-E17, M15-E28 ; M14-E42 conseillé ; `lab/bin/check 15 36` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : le Corefile de `k8s-par1` (ConfigMap `kube-system/coredns`, géré dans `plateforme/k8s/composants/coredns/`, M15-E04) transfère le reste du monde vers `dns01`/`dns02` et contient un bloc `medisphere.internal` explicite. Le greffon `reload` de CoreDNS relit le Corefile de lui-même, en 30 s à 2 min (le temps que le kubelet propage le ConfigMap). Un pod MédiAgenda qui ne résout pas le nom de sa base ne devient jamais prêt (`/pret` en 503) ; pendant une mise à jour progressive, les anciens pods continuent de servir.

**Injection** : `lab/bin/break 15 36` (3 variantes).

**Travail demandé**
1. Reproduis depuis un pod témoin, puis depuis un pod de l'application concernée (ou un pod éphémère attaché : `kubectl debug -it <pod> --image=<image netshoot du cache Harbor> --target=<conteneur>`) : quels noms échouent, lesquels marchent, avec quelle erreur (`NXDOMAIN`, `SERVFAIL`, délai dépassé) ?
2. Compare le `/etc/resolv.conf` des deux pods. Explique ce que donnent `ndots:5` et la liste `search` pour le nom court de la base, et combien de requêtes part pour un nom externe.
3. Regarde passer (ou ne pas passer) les requêtes : `hubble observe --protocol dns`, `--verdict DROPPED`, journaux de CoreDNS (le greffon `log` peut être activé temporairement **par le dépôt** ; dis-le dans ton journal). Interroge CoreDNS directement (`dig @<IP de kube-dns>`) puis l'amont (`dig @10.10.20.10`).
4. Corrige à la racine, par le dépôt concerné, et vérifie que tous les noms (cluster, `medisphere.internal`, Internet) résolvent depuis les pods et que le déploiement en cours se termine.
5. Réponds dans ton journal : pourquoi une politique qui « n'interdit que kube-system » casse-t-elle tout le DNS de l'espace ? Pourquoi `dnsPolicy: Default` ne veut-il pas dire « la valeur par défaut » ?

**Critères de réussite**
- [ ] Depuis un pod de `mediagenda-recette` et depuis un témoin : `kubernetes.default.svc.cluster.local`, le nom de la base de MédiAgenda, `s3-01.par1.medisphere.internal` et un nom Internet résolvent.
- [ ] Le Corefile du cluster est celui du dépôt (transfert vers `dns01` et `dns02`, bloc `medisphere.internal`) ; les déploiements de MédiAgenda sont terminés, toutes leurs répliques prêtes.
- [ ] La correction est dans le dépôt ; ton journal contient la trace Hubble ou `dig` qui a désigné la cause.

**Vérification** : `lab/bin/check 15 36`

<details><summary>Indice 1</summary>

`kubectl exec <pod> -- cat /etc/resolv.conf`, puis `dig +search <nom>` et `dig <nom>.` (avec le point final) : la différence entre les deux est celle de la liste `search`. `kubectl -n kube-system get svc kube-dns` donne l'adresse à interroger directement.
</details>

<details><summary>Indice 2</summary>

`hubble observe --namespace <espace> --port 53` montre si la requête sort du pod, et `--verdict DROPPED` si une politique la jette (le champ `drop_reason_desc` dit laquelle, `POLICY_DENIED` ou `POLICY_DENY`). `kubectl get cnp,ccnp,netpol -A` liste toutes les politiques ; `kubectl -n kube-system get cm coredns -o yaml` et `git diff` dans `plateforme/k8s` comparent le Corefile vivant au dépôt.
</details>

<details><summary>Indice 3</summary>

`kubectl get deploy <d> -o jsonpath='{.spec.template.spec.dnsPolicy}'`, et `kubectl rollout history deploy/<d> --revision=N` pour comparer deux gabarits. Dans Cilium, une règle de refus (`ingressDeny`, `egressDeny`) l'emporte toujours sur une autorisation, quel que soit l'ordre des politiques.
</details>

**Pour aller plus loin** : mesure, depuis un pod, le nombre de requêtes émises pour résoudre `s3-01.par1.medisphere.internal` avec `ndots:5` puis avec `dnsConfig.options: [{name: ndots, value: "2"}]` (`tcpdump -ni any port 53` dans le pod témoin) ; écris dans `docs/kubernetes/reseau/` la recommandation de MédiSphère pour les applications qui résolvent beaucoup de noms externes (FQDN avec point final, `ndots`, NodeLocal DNSCache).

---

### M15-E37 — Panne : plus rien ne passe dans l'espace de noms  `BF` `★★`

> **Ticket INC-4243** — *De : Nadia Roussel*
> *(Le détail du ticket s'affiche à l'injection.)* Les pods de `mediagenda-recette` sont Running, mais plus aucun ne reçoit de trafic, ou ils n'arrivent plus à parler entre eux. Interdiction de supprimer la politique de refus par défaut « pour voir si ça repasse ».

**Objectifs pédagogiques**
- Trouver **la** politique qui jette un flux, parmi des NetworkPolicy, des CiliumNetworkPolicy et des CiliumClusterwideNetworkPolicy, à partir du verdict de Hubble et de l'état calculé par l'agent.
- Comprendre l'addition des politiques (union des autorisations, primauté des refus, *default deny* déclenché par la sélection) et le rôle des identités.
- Corriger sans ouvrir plus que nécessaire, et prouver que le *default deny* est intact.

**Prérequis** : M15-E05, M15-E06, M15-E17, M15-E21 ; `lab/bin/check 15 37` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : `mediagenda-recette` est fermé par la NetworkPolicy de refus par défaut de M15-E17 (tous les pods, entrée et sortie) et ouvert par les autorisations de M15-E17 : DNS vers `kube-dns`, Gateway → API, API → PostgreSQL (5432) et Valkey (6379), et la règle L7 de l'API. Cilium applique la politique à chaque paquet qui n'est pas une réponse : une connexion établie tombe dès que la politique qui l'autorisait disparaît.

**Injection** : `lab/bin/break 15 37` (3 variantes).

**Travail demandé**
1. Cartographie les flux de l'espace qui devraient exister (matrice de M15-E32) et ceux qui passent réellement : `hubble observe --namespace mediagenda-recette`, avec les verdicts.
2. Pour un flux jeté, identifie le pod source, le pod destination, leurs **identités** Cilium et leurs étiquettes, et la direction (entrée ou sortie) où il est refusé.
3. Liste toutes les politiques qui sélectionnent le pod concerné, dans les deux directions, et la règle qui manque ou qui refuse. Vérifie ce que l'agent du nœud a réellement calculé pour ce point de terminaison.
4. Corrige à la racine, dans le dépôt (ou retire du cluster ce qui n'est dans aucun dépôt, après avoir prévenu Sophie : c'est peut-être un objet de sécurité légitime posé au mauvais endroit). Vérifie que les flux attendus passent et que les autres restent refusés (un essai depuis un pod témoin vers l'API doit toujours être jeté).
5. Note dans ton journal la réponse à : « Pourquoi ajouter une NetworkPolicy `allow-all` n'aurait-il pas suffi dans un des cas, et pourquoi aurait-ce été une faute dans tous les cas ? »

**Critères de réussite**
- [ ] `/pret` répond 200 de façon stable depuis `adm01`.
- [ ] La NetworkPolicy de refus par défaut est intacte ; les politiques qui s'appliquent à l'espace (de l'espace et du cluster) sont celles des dépôts ; l'API joint PostgreSQL sur 5432.
- [ ] Un pod de `wb-pannes` ne joint toujours pas l'API de MédiAgenda (preuve Hubble `DROPPED` dans ton journal).

**Vérification** : `lab/bin/check 15 37`

<details><summary>Indice 1</summary>

`hubble observe --namespace mediagenda-recette --verdict DROPPED -o compact` puis `-o json | jq` pour les champs `source.identity`, `destination.identity`, `traffic_direction`, `drop_reason_desc`. `cilium-dbg identity get <id>` donne les étiquettes d'une identité.
</details>

<details><summary>Indice 2</summary>

`kubectl -n mediagenda-recette get netpol,cnp`, et `kubectl get ccnp` : n'oublie pas les politiques de cluster. Dans l'agent du nœud du pod : `cilium-dbg endpoint list` (colonnes `POLICY (ingress) ENFORCEMENT`), puis `cilium-dbg endpoint get <id> -o jsonpath='{.status.policy}'` ou `cilium-dbg bpf policy get <id>`.
</details>

<details><summary>Indice 3</summary>

Compare le sélecteur de chaque politique (`podSelector`, `endpointSelector`) aux étiquettes réelles des pods (`kubectl get pods --show-labels`), et les ports des règles aux ports réellement utilisés (`hubble observe` les montre). Une politique qui ne sélectionne plus rien est silencieuse : elle n'apparaît dans aucun verdict.
</details>

**Pour aller plus loin** : écris un test de non-régression des politiques de `mediagenda-recette` (script dans `plateforme/k8s/outils/`) qui lance, depuis des pods éphémères étiquetés comme la Gateway, l'API et un intrus, les flux attendus et interdits de la matrice, et échoue au premier écart ; branche-le sur le pipeline de `plateforme/k8s` (il servira au M19).

---

### M15-E38 — Panne : l'adresse du LoadBalancer est injoignable  `BF` `★★★`

> **Ticket INC-4244** — *De : Nadia Roussel ou Julien Petit*
> *(Le détail du ticket s'affiche à l'injection : selon le cas, un Service qui n'obtient pas d'adresse, plus aucune adresse de 10.10.41.0/24 joignable, ou une alerte de la sonde de la bordure.)*

**Objectifs pédagogiques**
- Suivre une adresse de service de bout en bout : attribution (LB IPAM), sélection des nœuds qui parlent BGP, sessions, annonces, politique d'entrée de la bordure, table de routage du noyau des passerelles.
- Diagnostiquer une session BGP des deux côtés (Cilium et FRR) et lire un refus d'OPEN.
- Repérer une dérive de configuration à chaud sur une passerelle sans la faire basculer.
- Compléter le runbook RB-152 (BGP) avec un arbre de diagnostic.

**Prérequis** : M15-E10, M15-E11, M15-E25 ; M07-E16, M07-E35 (RB-073 « session BGP ») ; `lab/bin/check 15 38` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : pool `lb-par1` (10.10.41.10-10.10.41.199) ; `CiliumBGPClusterConfig` `bgp-par1` (AS 65040, nœuds choisis par étiquette), `CiliumBGPPeerConfig` `bordure`, `CiliumBGPAdvertisement` des IP de Service ; côté bordure, groupe `K8S` en écoute passive sur 10.10.40.0/24 (AS 65000, `RM-K8S-IN` / `PL-DEPUIS-K8S`, `RM-K8S-OUT` refuse tout). Le redémarrage gracieux est actif (M15-E25) : une passerelle garde les routes d'un voisin perdu pendant `restartTimeSeconds` avant de les retirer. La CLI `cilium bgp peers` et `cilium bgp routes` (sur `adm01`) interrogent tous les agents ; dans un agent, `cilium-dbg bgp …` est déprécié en 1.20 au profit de `cilium-dbg shell -- bgp/…` (consulte l'aide de ta version).

**Injection** : `lab/bin/break 15 38` (5 variantes).

> ⚠️ **Attention** : une des variantes ne se voit que sur la passerelle de **secours**. Tu ne la prouves pas en basculant la VIP : tu la prouves en lisant la table de cette passerelle (`ip route`, `vtysh -c 'show bgp …'`). Ne modifie pas FRR à la main sur une passerelle : la correction passe par Ansible.

**Travail demandé**
1. Situe la panne : le Service a-t-il une adresse ? Les nœuds ont-ils des sessions établies, avec quelles passerelles ? Qu'annoncent-ils ? Que reçoit, accepte et installe chaque passerelle ? Écris un tableau « étage / commande / état » dans ton journal.
2. Pour une session qui ne monte pas, lis-la des deux côtés : état et dernière erreur côté Cilium, `show bgp neighbors` et journal de FRR côté bordure (notification envoyée ou reçue, code).
3. Pour des routes reçues mais pas installées, montre la décision de la politique d'entrée (avec `show bgp ipv4 unicast neighbors <IP> received-routes` si la copie avant politique est disponible, ou `show route-map`, `show ip prefix-list`) et compare la configuration courante de FRR au fichier généré par Ansible.
4. Corrige à la racine (dépôt `plateforme/k8s` pour les objets Cilium, rejeu de `playbooks/bordure-frr.yml` pour la bordure), puis prouve la convergence : routes présentes sur **les deux** passerelles, adresse joignable depuis `adm01`, nouveau Service servi.
5. Complète `RB-152` (créé en M15-E25, `docs/kubernetes/reseau/runbooks/`) d'une section « Diagnostic » : arbre de décision (adresse attribuée ? nœuds sélectionnés ? session établie ? annonce émise ? route acceptée ? route installée ?), commandes des deux côtés, précautions (pas de bascule, pas de `restart frr`), renvoi vers RB-073.

**Critères de réussite**
- [ ] Aucun Service `LoadBalancer` en `<pending>` ; le pool est actif ; la Gateway a 10.10.41.10.
- [ ] `bgp-par1` est en AS 65040, voisins 10.10.40.2 et 10.10.40.3 en AS 65000, et sélectionne des travailleurs ; les IP `LoadBalancer` sont annoncées.
- [ ] Les **deux** passerelles ont une route BGP vers 10.10.41.10 et leur configuration courante de FRR est celle du fichier généré par Ansible ; 10.10.41.10:443 répond depuis `adm01`.
- [ ] RB-152 est complété et publié ; la correction est dans le dépôt concerné.

**Vérification** : `lab/bin/check 15 38`

<details><summary>Indice 1</summary>

`kubectl get svc -A | grep pending`, `kubectl get ciliumloadbalancerippool -o wide` (colonnes `DISABLED`, `CONFLICTING`, `IPS AVAILABLE`), `kubectl describe svc <svc>` (condition `io.cilium/lb-ipam-request-satisfied`). Puis `cilium bgp peers` et `cilium bgp routes advertised ipv4 unicast` depuis `adm01`.
</details>

<details><summary>Indice 2</summary>

`kubectl get ciliumbgpclusterconfig bgp-par1 -o yaml` (sélecteur, AS, voisins) comparé aux étiquettes des nœuds (`kubectl get nodes --show-labels`) et à la bordure (`vtysh -c 'show running-config'`, section `router bgp 65000`). `kubectl get ciliumbgpnodeconfigs` montre, nœud par nœud, ce que l'opérateur a produit. Sur une passerelle : `vtysh -c 'show bgp summary'`, `vtysh -c 'show bgp neighbors <IP-du-nœud>'` (« Last reset », « Notification »), `journalctl -u frr --since -30min`.
</details>

<details><summary>Indice 3</summary>

Sur chaque passerelle, `ip -4 route show proto bgp | grep 10.10.41` dit ce qui est installé ; `vtysh -c 'show ip prefix-list PL-DEPUIS-K8S'` ce que la politique accepte. `diff <(vtysh -c 'show running-config') /etc/frr/frr.conf` (en ignorant l'en-tête) révèle une modification à chaud.
</details>

**Pour aller plus loin** : ajoute à la sonde de la bordure (M07-E29) un contrôle par passerelle « nombre de routes 10.10.41.0/24 reçues de chaque nœud du groupe K8S » avec un seuil, et à `ms-verif-k8s-reseau` (M15-E26) un contrôle « chaque nœud sélectionné a deux sessions établies ».

---

### M15-E39 — Panne : la Gateway refuse le HTTPS  `BF` `★★★`

> **Ticket INC-4245** — *De : Nadia Roussel ou Julien Petit*
> *(Le détail du ticket s'affiche à l'injection : selon le cas, toutes les applications publiées échouent dès la négociation TLS, ou une seule répond 404 avec un certificat valide.)* Karim veut que le certificat reste émis par cert-manager : pas de certificat posé à la main.

**Objectifs pédagogiques**
- Lire l'état d'une Gateway écouteur par écouteur (`Accepted`, `ResolvedRefs`, `Programmed`, nombre de routes attachées) et relier chaque raison (`InvalidCertificateRef`, `RefNotPermitted`, `NotAllowedByListeners`, `NoMatchingListenerHostname`) à sa cause.
- Comprendre les frontières d'espace de noms de la Gateway API : `allowedRoutes`, références croisées et `ReferenceGrant`.
- Tester le TLS au bon étage : SNI, certificat présenté, chaîne, nom.

**Prérequis** : M15-E12, M15-E13, M15-E16 ; `lab/bin/check 15 39` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : `gw-par1` (espace `passerelles`, 10.10.41.10) : écouteur HTTP (80, redirection vers HTTPS) et écouteur HTTPS (443, `*.apps.par1.medisphere.internal`, certificat joker `apps-joker` émis par cert-manager dans `passerelles`), routes admises depuis les espaces étiquetés `medisphere.internal/exposition: oui`. Avec Cilium, un écouteur dont le certificat est introuvable n'est pas programmé : Envoy n'a aucune chaîne de filtres pour ce nom et coupe la négociation.

**Injection** : `lab/bin/break 15 39` (3 variantes).

**Travail demandé**
1. Reproduis : `curl -sv https://…`, puis `openssl s_client -connect 10.10.41.10:443 -servername <nom> -brief`. Le TCP s'établit-il ? Un certificat est-il présenté, lequel ? Quelle réponse HTTP, le cas échéant ?
2. Lis l'état complet de la Gateway et de la route (`kubectl describe`, `-o yaml`), écouteur par écouteur, et relève la raison exacte de chaque condition à `False`.
3. Relie la raison à l'objet en cause et prouve-le (existence et emplacement du Secret, étiquettes de l'espace de la route, `ReferenceGrant` présents) ; cherche qui a changé quoi (`managedFields`, dépôt).
4. Corrige à la racine, sans créer de Secret ni de `ReferenceGrant` de contournement, et vérifie : TLS valide (CA MédiSphère, nom), 200 sur `/sante`, redirection du port 80 intacte, autres applications publiées intactes.
5. Dans ton journal, explique pourquoi un `ReferenceGrant` vers l'espace `cert-manager` aurait été une « réparation » dangereuse, même si le Secret s'y était trouvé.

**Critères de réussite**
- [ ] `gw-par1` est `Accepted` et `Programmed`, tous ses écouteurs ont `ResolvedRefs` et `Programmed` à `True` ; le certificat HTTPS est référencé dans l'espace `passerelles`.
- [ ] La route `mediagenda` est acceptée par `gw-par1` ; `/sante` répond 200 en TLS vérifié ; le port 80 redirige ; les objets en cause sont conformes aux dépôts.
- [ ] La raison exacte de la condition en échec figure dans ton journal ; la correction est dans le dépôt.

**Vérification** : `lab/bin/check 15 39`

<details><summary>Indice 1</summary>

`kubectl -n passerelles get gateway gw-par1 -o yaml` : bloc `status.listeners[]`, avec `attachedRoutes` et des conditions par écouteur. `kubectl -n mediagenda-recette get httproute mediagenda -o jsonpath='{.status.parents}' | jq`.
</details>

<details><summary>Indice 2</summary>

`kubectl -n passerelles get certificate,secret` ; `kubectl get gateway gw-par1 -o jsonpath='{.spec.listeners[?(@.protocol=="HTTPS")].tls}'` ; `kubectl get ns --show-labels` ; `kubectl get referencegrants -A`.
</details>

<details><summary>Indice 3</summary>

Les raisons sont définies par la spécification : lis la [référence de l'API Gateway](https://gateway-api.sigs.k8s.io/reference/api-spec/) aux types `ListenerConditionReason` et `RouteConditionReason`. Une route refusée par un écouteur n'est pas une route cassée : c'est l'écouteur qui la refuse.
</details>

**Pour aller plus loin** : ajoute à `ms-verif-k8s-reseau` (M15-E26) un contrôle « toutes les conditions de toutes les Gateway et de toutes les routes sont à `True` », qui liste la raison de chaque écart : c'est la meilleure alerte précoce de la Gateway API.

---

### M15-E40 — Panne : le certificat n'est jamais délivré  `BF` `★★★`

> **Ticket INC-4246** — *De : Karim Benali*
> *(Le détail du ticket s'affiche à l'injection.)* Un certificat de répétition du renouvellement du joker reste à « False » ; je ne veux pas découvrir le jour J que le vrai ne se renouvellera pas.

**Objectifs pédagogiques**
- Suivre la chaîne d'objets de cert-manager (`Certificate` → `CertificateRequest` → `Order` → `Challenge`) et lire l'état et la raison à chaque étage.
- Diagnostiquer un défi DNS-01 par RFC 2136 : solveur choisi, mise à jour signée TSIG, droits de la zone dans PowerDNS, propagation vérifiée par cert-manager.
- Diagnostiquer la confiance entre cert-manager et l'ACME de `ca01` (`caBundle`).
- Rédiger le runbook RB-151 (certificat non délivré).

**Prérequis** : M15-E13, M15-E14 ; M06 (step-ca, PowerDNS, TSIG) ; `lab/bin/check 15 40` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : ClusterIssuer `step-ca-acme` (serveur `https://ca01.par1.medisphere.internal/acme/acme/directory`, CA MédiSphère dans `caBundle`, solveur DNS-01 `rfc2136` vers l'autoritaire de `dns01` (port 5300) avec la clé `certmanager-k8s` pour la zone `apps.par1.medisphere.internal`, solveur HTTP-01 par la Gateway). Un joker ne peut être validé que par DNS-01. Le certificat témoin `wb-essais/joker-repetition` est créé par l'injection ; ne le supprime pas : il doit finir délivré. La clé privée du compte ACME (`privateKeySecretRef`) et le secret TSIG sont des Secrets : ne les affiche jamais dans ton journal. L'horloge et les quotas ACME ne font pas partie des variantes injectées, mais tes hypothèses doivent les écarter, preuve à l'appui.

**Injection** : `lab/bin/break 15 40` (4 variantes).

**Travail demandé**
1. Descends la chaîne d'objets du certificat témoin jusqu'au `Challenge` (ou jusqu'à l'étage où elle s'arrête) ; relève l'état, la raison et le message de chacun, et les événements.
2. Écarte ou confirme, preuve à l'appui : l'émetteur lui-même (prêt ? sa raison ?), la confiance TLS vers `ca01`, le solveur choisi pour ce nom, la mise à jour DNS (refusée ? par qui ? avec quel code ?), l'horloge des nœuds et de `ca01`, un quota.
3. Côté DNS, montre ce que voit l'autoritaire : journal de PowerDNS sur `dns01` pendant une tentative, métadonnées de la zone `apps` (`TSIG-ALLOW-DNSUPDATE`, `ALLOW-DNSUPDATE-FROM`), clés connues. Côté cert-manager, journaux du contrôleur filtrés sur le nom du `Challenge`.
4. Corrige à la racine par le dépôt `plateforme/k8s`, laisse cert-manager reprendre (ou force une nouvelle tentative proprement) et vérifie que le témoin est délivré et que l'enregistrement `_acme-challenge` a été nettoyé.
5. Rédige `RB-151 — Certificat non délivré` dans `docs/kubernetes/reseau/runbooks/` : la chaîne d'objets, les causes classées par étage avec la commande qui les révèle (dont l'horloge et les quotas), la manière sûre de relancer, et quand prévenir l'équipe PKI.

**Critères de réussite**
- [ ] `step-ca-acme` est prêt, pointe vers `ca01` avec la CA MédiSphère, et son solveur RFC 2136 vise `dns01` avec la clé `certmanager-k8s` pour la zone `apps.par1.medisphere.internal`.
- [ ] `wb-essais/joker-repetition` et `passerelles/apps-joker` sont `Ready`, comme tous les certificats de `passerelles`, `wb-*` et `mediagenda-*`.
- [ ] RB-151 est publié ; ton journal montre l'étage en cause (raison de l'objet et, pour un refus DNS, le code de réponse) sans aucun secret.

**Vérification** : `lab/bin/check 15 40`

<details><summary>Indice 1</summary>

`kubectl -n wb-essais describe certificate joker-repetition`, puis `kubectl -n wb-essais get certificaterequest,order,challenge` et `describe` de chacun ; `kubectl describe clusterissuer step-ca-acme`. Si la CLI `cmctl` est installée, `cmctl status certificate -n wb-essais joker-repetition` résume tout.
</details>

<details><summary>Indice 2</summary>

`kubectl -n cert-manager logs deploy/cert-manager | grep -i <nom-du-challenge>` ; sur `dns01`, `journalctl -u pdns --since -15min` (les mises à jour refusées y sont journalisées avec la clé et la raison), `sudo -u pdns pdnsutil metadata get apps.par1.medisphere.internal` (vérifie la syntaxe sur ta version), `sudo -u pdns pdnsutil tsigkey list`.
</details>

<details><summary>Indice 3</summary>

Compare le `ClusterIssuer` vivant au dépôt (`kubectl diff -f`). Pour la confiance : `kubectl get clusterissuer step-ca-acme -o jsonpath='{.spec.acme.caBundle}' | base64 -d | openssl x509 -noout -subject -fingerprint -sha256`, à comparer avec la racine installée sur `adm01`. Pour le solveur : la documentation de cert-manager sur les [sélecteurs de solveurs](https://cert-manager.io/docs/configuration/acme/#adding-multiple-solver-types) dit lequel est choisi pour un nom donné.
</details>

**Pour aller plus loin** : un test de bout en bout planifié (CronJob dans `wb-system`, ou job du pipeline) qui demande chaque semaine un certificat jetable par DNS-01 et par HTTP-01, vérifie sa délivrance en moins de 5 minutes et le supprime : c'est ce test, pas l'expiration du joker, qui doit vous apprendre qu'une chaîne ACME est cassée.

---

### M15-E41 — Panne : le nom n'est plus publié  `BF` `★★`

> **Ticket INC-4247** — *De : Julien Petit ou Sophie Laurent*
> *(Le détail du ticket s'affiche à l'injection : selon le cas, une nouvelle route dont le nom n'apparaît jamais, ou un nom qui reste publié alors que sa route a disparu.)*

**Objectifs pédagogiques**
- Comprendre la boucle de réconciliation d'ExternalDNS : sources lues, filtres, plan de changements, registre TXT de propriété, politique de synchronisation.
- Diagnostiquer ExternalDNS par ses journaux, ses arguments et ses droits RBAC, et la zone par l'autoritaire et le secondaire.
- Nettoyer sans risque un enregistrement orphelin.

**Prérequis** : M15-E14, M15-E15 ; `lab/bin/check 15 41` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : ExternalDNS (espace `external-dns`, Helm, fournisseur `rfc2136`, `--domain-filter=apps.par1.medisphere.internal`, sources `gateway-httproute` et `service`, `--txt-owner-id=k8s-par1`, politique `sync`, intervalle d'une minute) publie sur `dns01` avec la clé `externaldns-k8s` ; `dns02` reçoit la zone par AXFR après NOTIFY. Chaque nom géré est accompagné d'un enregistrement TXT qui dit quel propriétaire l'a créé. La route témoin `mediagenda-recette/temoin-dns` (`temoin-dns.apps.par1.medisphere.internal`) est créée par l'injection.

**Injection** : `lab/bin/break 15 41` (3 variantes).

**Travail demandé**
1. Reproduis en interrogeant directement les autoritaires (`dig +norec -p 5300 @10.10.20.10`, puis `@10.10.20.16`, sans passer par un récurseur et son cache) pour le nom concerné et pour un nom sain ; enregistrements A **et** TXT. Que dit l'enregistrement de propriété ?
2. Lis ce que fait ExternalDNS : état du pod, journaux (sources, nombre de points de terminaison trouvés, changements prévus et appliqués, erreurs), arguments réels du conteneur.
3. Compare les arguments au fichier de values du dépôt (`helm get values`, `kubectl diff`), et les droits du compte de service à ce dont la source `gateway-httproute` a besoin.
4. Corrige à la racine par le dépôt ; vérifie la publication d'un nouveau nom et le retrait d'un nom dont la route disparaît (crée et supprime une route jetable dans `wb-essais` si son espace est admis par la Gateway, sinon dans `mediagenda-recette`).
5. Pour un enregistrement orphelin : explique pourquoi ExternalDNS ne le supprimait pas, puis supprime-le **proprement** (laisse ExternalDNS le faire, ou `nsupdate` avec la clé d'ExternalDNS en supprimant le A **et** son TXT), jamais à la main dans la base de PowerDNS.

**Critères de réussite**
- [ ] ExternalDNS tourne avec la configuration du dépôt (filtre `apps.par1.medisphere.internal`, propriétaire `k8s-par1`, source `gateway-httproute`) et voit les routes attachées à `gw-par1`.
- [ ] `mediagenda-recette.apps…` résout vers 10.10.41.10 sur `dns01` et `dns02`, avec un TXT de propriété `k8s-par1` ; le nom témoin est publié si la route existe, absent sinon.
- [ ] Ton journal contient la ligne de journal d'ExternalDNS (ou l'enregistrement TXT) qui a désigné la cause ; la correction est dans le dépôt.

**Vérification** : `lab/bin/check 15 41`

<details><summary>Indice 1</summary>

`kubectl -n external-dns logs deploy/external-dns --since=10m`, puis `kubectl -n external-dns get deploy external-dns -o jsonpath='{.spec.template.spec.containers[0].args}' | jq` (adapte le nom au tien). Le niveau `debug` (`--log-level=debug`, par les values) liste chaque point de terminaison trouvé.
</details>

<details><summary>Indice 2</summary>

`dig +norec -p 5300 @10.10.20.10 <nom> TXT` et `… a-<nom> TXT` : selon la version et le format du registre, le TXT de propriété porte le nom lui-même ou un nom préfixé (lis la [documentation du registre TXT](https://kubernetes-sigs.github.io/external-dns/latest/docs/registry/txt/)). `kubectl auth can-i list httproutes.gateway.networking.k8s.io --as=system:serviceaccount:external-dns:<sa>`.
</details>

<details><summary>Indice 3</summary>

Un ExternalDNS ne touche jamais un enregistrement dont le TXT désigne un autre propriétaire, même avec la politique `sync` : c'est ce qui permet à deux clusters de partager une zone. Demande-toi qui, aujourd'hui, est propriétaire de chaque nom de la zone.
</details>

**Pour aller plus loin** : ajoute à `ms-verif-k8s-reseau` un contrôle de cohérence « noms des routes acceptées ⇔ enregistrements A de la zone `apps` » (transfert de zone autorisé en lecture depuis `adm01`, ou requêtes nom par nom) qui signale les noms manquants **et** les orphelins.

---

### M15-E42 — Panne : les pods ne se joignent plus entre nœuds  `BF` `★★★`

> **Ticket INC-4248** — *De : Nadia Roussel*
> *(Le détail du ticket s'affiche à l'injection.)* Depuis le passage d'InfoGér ce matin, MédiAgenda en recette échoue une requête sur trois environ ; tous les nœuds sont Ready et tous les pods Running.

**Objectifs pédagogiques**
- Isoler un défaut de chemin de données à un nœud, par une matrice de connectivité pod à pod et la santé de Cilium (`cilium-health`).
- Suivre un paquet inter-nœuds à travers les étages : veth du pod, programmes eBPF, tunnel VXLAN, chiffrement WireGuard, interface physique, pare-feu du nœud.
- Lire le chemin de données de l'agent d'un nœud (configuration effective, surcharges par nœud) et du noyau (interfaces, règles nftables).

**Prérequis** : M15-E02, M15-E05, M15-E24, M15-E29 ; `lab/bin/check 15 42` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : routage en tunnel VXLAN (UDP 8472) chiffré par WireGuard (`cilium_wg0`, UDP 51871) : un paquet de pod à pod entre deux nœuds est d'abord encapsulé en VXLAN, puis chiffré ; sur le fil, on ne voit que de l'UDP 51871 entre les adresses des nœuds (10.10.40.61-63). Les témoins de `wb-pannes` (un par travailleur) sont faits pour la matrice de connectivité.

**Injection** : `lab/bin/break 15 42` (3 variantes).

**Travail demandé**
1. Construis la matrice de connectivité des témoins (chaque pod vers chaque autre, par adresse de pod) et déduis-en le nœud en cause. Confirme avec `cilium-health status` depuis deux agents différents.
2. Sur le nœud en cause et sur un nœud sain, compare : état de l'agent (`cilium-dbg status --verbose` : chiffrement, tunnel, santé), configuration effective de l'agent, interfaces `cilium_*`, règles de pare-feu du noyau.
3. Capture le trafic sur l'interface physique des deux nœuds (`tcpdump -ni <interface> udp port 51871 or udp port 8472`) pendant un essai : les paquets partent-ils, arrivent-ils, qui ne répond pas ? Montre aussi ce que Hubble ou `cilium-dbg monitor --type drop` voient.
4. Corrige à la racine (ce qui a été posé hors de tout dépôt est retiré ; ce qui vient d'un dépôt y est corrigé), et prouve le retour : matrice complète, `cilium-health` vert, 50 requêtes successives sans erreur sur MédiAgenda recette.
5. Propose dans ton journal le contrôle qui aurait vu la panne avant Nadia (où il tourne, à quelle fréquence, ce qu'il mesure).

**Critères de réussite**
- [ ] Un agent Cilium prêt par nœud ; la configuration effective de chaque agent et le filtrage de chaque travailleur ne contiennent rien d'autre que ce que posent les dépôts et Cilium ; `cilium_vxlan` et `cilium_wg0` sont actives.
- [ ] `cilium-health status --probe` : tous les nœuds et points de santé joignables ; `/pret` répond 200 de façon stable.
- [ ] Ton journal contient la matrice de connectivité initiale et la capture (ou la trace Hubble) qui prouve la cause.

**Vérification** : `lab/bin/check 15 42`

<details><summary>Indice 1</summary>

`kubectl -n wb-pannes get pods -o wide` donne les adresses et les nœuds ; une boucle `for ip in …; do kubectl -n wb-pannes exec <pod> -- nc -w 2 $ip 8080; done` par pod source fait la matrice. `kubectl -n kube-system exec <agent> -c cilium-agent -- cilium-health status --probe`.
</details>

<details><summary>Indice 2</summary>

`cilium-dbg status --verbose` (sections `Encryption`, `Routing`, `Cluster health`) ; une `CiliumNodeConfig` (espace `kube-system`) peut surcharger, pour les nœuds qu'elle sélectionne, une clé de la configuration de Cilium au redémarrage de l'agent : `kubectl -n kube-system get ciliumnodeconfigs` ; `cilium-dbg config --all` dans l'agent (ou `cilium config view` depuis `adm01`, qui ne montre que la configuration commune). Sur le nœud : `ip -d link show cilium_vxlan`, `ip link show cilium_wg0`, `sudo nft list ruleset | less` (cherche ce qui n'est ni Cilium ni kube).
</details>

<details><summary>Indice 3</summary>

Un `tcpdump` des deux côtés tranche entre « ça ne part pas », « ça part mais n'arrive pas » et « ça arrive mais personne ne le prend ». Le port de destination d'un paquet VXLAN est celui configuré sur le nœud **émetteur** ; le port d'écoute est celui configuré sur le nœud **récepteur**.
</details>

**Pour aller plus loin** : la MTU est la cause classique suivante de « ça marche pour les petites requêtes, pas pour les grosses ». Calcule la MTU des pods de `k8s-par1` (1500 moins l'en-tête VXLAN, moins celui de WireGuard), vérifie-la (`ip route` dans un pod, `cilium-dbg status --verbose`), et montre avec `ping -M do -s <taille>` entre deux témoins la taille maximale qui passe.

---

### M15-E43 — Astreinte : plus rien n'entre dans le cluster  `BF` `★★★★`

> **Ticket INC-4250** — *De : Nadia Roussel (responsable astreinte)* — priorité P1
> Tu es d'astreinte. Jeudi, 23 h 10 : la sonde externe ne joint plus MédiAgenda en recette, où une campagne de tests de charge du client démarre à 7 h (le détail des remontées s'affiche à l'injection). Il y a eu trois interventions dans la journée, aucune avec un ticket de changement. Tiens-moi informée toutes les 30 minutes, puis rédige le post-mortem avec le modèle de l'équipe.

**Objectifs pédagogiques**
- Gérer un incident réseau à causes multiples : trier, prioriser par dépendances (le chemin d'entrée d'abord, puis le réseau du cluster, puis l'application), éviter qu'une panne en masque une autre ou qu'un correctif en déclenche une nouvelle.
- Garder les garde-fous de sécurité pendant l'incident (aucune politique de refus par défaut supprimée, chiffrement maintenu, aucun certificat posé à la main, aucune bascule de la bordure).
- Communiquer pendant l'incident et rédiger un post-mortem sans recherche de coupable.

**Prérequis** : M15-E35 à M15-E42 (au moins une variante de chacun).
**Durée indicative** : 2 h de rétablissement + 45 min de post-mortem.

**Contexte technique** : le script tire **trois** pannes parmi celles de M15-E35 à M15-E42 : une qui touche l'entrée du cluster (adresse ou TLS), une qui touche le réseau du cluster (DNS ou chemin entre nœuds) et une qui touche l'application ou ses services de publication (Service, politiques, certificat, nom). Les symptômes se recouvrent : tant que l'entrée est coupée, tu ne peux pas voir ce qui est cassé derrière. `--variante N` (1 à 16) force la combinaison, pas les sous-variantes. `--annuler` retire les trois. Modèle de post-mortem : [`modules/00-lab/ressources/M00-E46/modele-post-mortem.md`](../../00-lab/ressources/M00-E46/modele-post-mortem.md).

**Injection** : `lab/bin/break 15 43`

**Travail demandé**
1. **Triage (10 min max)** : liste les symptômes, leur impact (qui ne peut plus faire quoi ?) et tes hypothèses de regroupement. Vérifie d'abord tes instruments : kubeconfig valide, `cilium status`, `hubble` qui répond, accès SSH aux nœuds et aux passerelles, témoins de `wb-pannes`. Envoie la première communication.
2. **Diagnostic** : traite les pannes dans un ordre que tu justifies par les dépendances du chemin. Tiens ton journal horodaté ; garde la preuve de chaque cause (condition, verdict Hubble, sortie `vtysh`, capture).
3. **Rétablissement** : corrige chaque cause racine, par le dépôt ; après chaque correction, relance **tous** tes tests de départ (une correction en amont révèle souvent la panne suivante).
4. **Clôture** : communication de fin d'incident, `--annuler` pour clore, puis post-mortem dans `docs/kubernetes/post-mortems/AAAA-MM-JJ-INC-4250.md` publié par MR.

**Critères de réussite**
- [ ] Toutes les vérifications de M15-E35 à M15-E42 sont vertes (le contrôle les rejoue toutes) et aucune panne n'est encore marquée active.
- [ ] Le post-mortem contient une chronologie horodatée, les trois causes racines avec leur preuve (sorties Hubble, Cilium, `vtysh`, conditions ou événements), l'analyse de la détection (qu'est-ce qui aurait dû alerter avant la sonde externe ?) et des actions correctives avec responsable et échéance — dont au moins une sur la gestion des changements.
- [ ] Le journal contient au moins trois communications d'incident espacées d'environ 30 minutes.

**Vérification** : `lab/bin/check 15 43`

<details><summary>Indice 1</summary>

Ordre du chemin : nom public → adresse (LB IPAM, BGP, bordure) → écouteur (Gateway, TLS) → route → Service → pod → politique → DNS du cluster → chemin entre nœuds. Mais teste aussi **de l'intérieur** (pods témoins, `kubectl port-forward`, `curl` depuis un nœud vers l'adresse de service) : c'est le seul moyen de voir l'aval tant que l'amont est coupé.
</details>

<details><summary>Indice 2</summary>

Les contrôles `lab/bin/check 15 35` à `15 42` sont des sondes ciblées : lance-les pendant le triage pour cartographier ce qui est rouge. Un contrôle rouge n'est pas forcément une panne injectée : ce peut être la conséquence d'une autre. Pour les trois « interventions sans ticket », `kubectl get events -A --sort-by=.lastTimestamp`, les `managedFields` et `git log` des dépôts sont tes témoins.
</details>

**Pour aller plus loin** : fais-toi injecter une astreinte par quelqu'un d'autre (`--variante` tirée par lui), chronomètre le temps jusqu'au **premier diagnostic juste** en plus du temps de rétablissement, et compare-le à celui de M14-E43 : quel outil vous a fait gagner le plus de temps ?

---

### M15-E44 — Sous le capot : eBPF et les tables de Cilium  `LAB` `★★★★`

> **Ticket PLAT-1644** — *De : Karim Benali*
> Pendant les pannes, tout le monde a dit « c'est Cilium » comme on disait « c'est le réseau ». Je veux que tu saches **montrer** ce que Cilium a réellement programmé dans le noyau pour un Service, une connexion et une politique, et suivre un paquet du pod au pod en le prouvant à chaque étage avec un outil différent. Compte rendu pour les prochains arrivants, et pour moi quand j'ouvrirai un ticket chez Isovalent ou sur le Slack de Cilium.

**Objectifs pédagogiques**
- Lister et relier les programmes eBPF attachés par Cilium (points d'attache tc/tcx, cgroup, XDP éventuel) et les tables (*maps*) qu'ils consultent.
- Lire les tables de répartition de charge, de suivi de connexion, de NAT, d'identités (*ipcache*) et de politique, et relier chaque entrée à l'objet Kubernetes qui l'a produite.
- Suivre un paquet de Service de bout en bout avec `cilium-dbg monitor` et Hubble, et expliquer où se fait la traduction d'adresse (à la connexion, dans le cgroup, ou par paquet, en tc).

**Prérequis** : M15-E02, M15-E03, M15-E05, M15-E08 ; M15-E37 et M15-E42 conseillés.
**Durée indicative** : 3 h.

**Contexte technique**
- Dans l'agent : `cilium-dbg` (sous-commandes `bpf`, `service`, `endpoint`, `identity`, `monitor`, `map`). Sur le nœud : `bpftool` (paquet Debian `bpftool`, installé par le playbook des outils de diagnostic de M15-E02 ; à défaut, dans un conteneur de diagnostic de nœud `kubectl debug node/<nœud> -it --image=<image netshoot du cache Harbor> --profile=sysadmin`, à supprimer après usage).
- Objet d'étude : le Service de MédiAgenda en recette (`mediagenda-api`, port 80 vers le port 8000 des pods, adresse ClusterIP en 10.96.0.0/16) et une connexion depuis un pod témoin de `wb-pannes` vers ce Service. Pour que la connexion soit permise, crée **temporairement** (par le dépôt, ou à la main en le notant dans ton journal) deux autorisations étroites : la sortie « témoins de `wb-pannes` → API de MédiAgenda, TCP 8000 » (la politique `sonde-interne` ne permet aux témoins que le trafic interne et le DNS) et l'entrée « témoins → API, TCP 8000 » dans `mediagenda-recette`. Tu les retires à la fin.

> ⚠️ **Attention** : `bpftool` sait aussi **modifier** (`map update`, `map delete`, `prog detach`, `net detach`…) et `cilium-dbg` aussi (`bpf ct flush`, `bpf lb delete`, `service delete`, `endpoint config`). Dans cet exercice, seules les opérations de lecture sont permises : `bpftool prog show`, `net show`, `cgroup tree`, `map show`, `map dump` (sur une petite table) ; `cilium-dbg … list`, `get`, `status`, `monitor`. Un `monitor` sans filtre sur un nœud chargé produit des milliers de lignes : filtre toujours (`--type drop`, `--related-to <id>`, `--from`/`--to`). Supprime le pod de diagnostic de nœud à la fin (`kubectl get pods -A | grep node-debugger`).

**Travail demandé**
1. **Programmes eBPF.** Sur un travailleur : liste les programmes attachés aux interfaces (`bpftool net show`) et au cgroup racine (`bpftool cgroup tree /sys/fs/cgroup`). Pour l'interface physique, `cilium_host`, `cilium_vxlan`, `cilium_wg0` et le `lxc*` d'un pod témoin : quel programme, à quel point d'attache, dans quel sens ? Que font les programmes `cil_sock4_connect` (ou équivalent) du cgroup ?
2. **Un Service vu par Cilium.** Montre l'entrée du Service de MédiAgenda dans `cilium-dbg service list` puis dans `cilium-dbg bpf lb list` : frontal, backends, ports, identifiant de service. Fais varier le nombre de réplicas de l'API (2 → 3 → 2) et montre la table qui change. Que contient la table pour le NodePort de la Gateway, et pour son adresse 10.10.41.10 ?
3. **Suivi de connexion.** Depuis le pod témoin, ouvre une connexion vers le Service (`curl` en boucle ou `nc` maintenu ouvert). Trouve-la dans `cilium-dbg bpf ct list global` : quelles adresses y figurent (ClusterIP ou adresse du pod ?), pourquoi, et quelle durée de vie restante. Montre ce que contient `cilium-dbg bpf nat list` pour un flux qui sort du cluster (un `curl` vers `s3-01` depuis le témoin, si la politique le permet ; sinon explique pourquoi la table est vide pour ce pod).
4. **Identités et politiques.** Donne l'identité numérique du pod témoin et celle des pods de l'API (`cilium-dbg endpoint list`, `cilium-dbg identity get`), et retrouve l'adresse du témoin dans l'*ipcache* (`cilium-dbg bpf ipcache list` ou `map get cilium_ipcache` selon ta version) avec son identité et, pour une adresse d'un autre nœud, l'adresse du tunnel. Montre la règle de ta politique temporaire dans `cilium-dbg bpf policy get <id-du-point-de-terminaison-de-l-API>` : identité autorisée, port, direction, compteurs d'octets et de paquets qui augmentent pendant ta boucle.
5. **Suivre un paquet.** Avec `cilium-dbg monitor --related-to <id>` sur le nœud de l'API (et `hubble observe --from-pod … --to-pod …`), suis une requête : traduction du Service, entrée dans le tunnel, sortie, livraison au pod, verdict de politique. Retire ensuite l'autorisation d'entrée et montre le même essai en `DROPPED` (raison, direction, compteur), puis retire l'autorisation de sortie.
6. **Compte rendu.** Rédige `docs/kubernetes/reseau/analyses/sous-le-capot-ebpf.md` (à distinguer de `chemin-paquet.md` de M15-E02, qu'il approfondit) : `## Programmes eBPF`, `## Un Service vu par Cilium`, `## Suivi de connexion et NAT`, `## Identités et politiques`, `## Suivre un paquet`, puis `## Réponses aux questions`. Sorties annotées (réduites à l'utile), adresse ClusterIP réelle du Service étudié, aucun secret. Publie-le par MR.

**Questions d'analyse** (à traiter dans le compte rendu)
1. Pourquoi, avec le *socket LB*, la connexion du témoin vers le Service apparaît-elle dans la table de suivi avec l'adresse du **pod** de l'API et non avec la ClusterIP ? Qu'est-ce que ça change pour `tcpdump` dans le pod, et pour une application qui journalise l'adresse de destination ?
2. Où kube-proxy faisait-il la même traduction (chaînes `KUBE-SVC-*` en iptables), et pourquoi le remplacement par eBPF passe-t-il mieux à l'échelle (complexité d'une recherche, coût d'une mise à jour de 10 000 Services) ?
3. Pourquoi Cilium décide-t-il des politiques par **identité** et non par adresse IP ? Que se passe-t-il quand un pod redémarre avec une nouvelle adresse ? Quand deux pods ont exactement les mêmes étiquettes ?
4. Pourquoi les tables eBPF ont-elles une taille fixe (`bpf-ct-global-tcp-max`, `bpf-lb-map-max`…) ? Que se passe-t-il quand la table de suivi de connexion est pleine, et quelle métrique le dit ?
5. Une connexion établie survit-elle au redémarrage de l'agent Cilium ? À la suppression de la politique qui l'autorisait ? Justifie avec ce que tu as observé.
6. Avec WireGuard, à quel étage le paquet est-il chiffré, et pourquoi `tcpdump` sur `cilium_vxlan` montre-t-il encore le paquet en clair ?
7. Qu'apporterait XDP (`loadBalancer.acceleration`) à la Gateway de MédiSphère, et pourquoi n'est-il pas activé sur `k8s-par1` (pilote virtio, mode de chargement, gain réel) ?

**Critères de réussite**
- [ ] Le compte rendu `analyses/sous-le-capot-ebpf.md` existe, est commité, contient les sections demandées, cite `bpftool`, `bpf lb list`, `bpf ct list`, `bpf policy get`, `bpf ipcache`, `cilium-dbg monitor` (ou `hubble observe`) et l'adresse ClusterIP réelle du Service étudié.
- [ ] Les 7 questions sont traitées.
- [ ] Les politiques temporaires sont retirées ; aucun pod `node-debugger-*` ne reste ; tous les agents Cilium sont prêts.

**Vérification** : `lab/bin/check 15 44`

<details><summary>Indice 1</summary>

`kubectl -n kube-system get pods -l k8s-app=cilium -o wide` pour l'agent du nœud voulu ; `cilium-dbg service list | grep <ClusterIP>` donne l'identifiant de service ; `cilium-dbg bpf lb list --frontends` (selon la version) distingue les frontaux. `cilium-dbg endpoint list -o json | jq` relie un point de terminaison à son pod.
</details>

<details><summary>Indice 2</summary>

`cilium-dbg bpf ct list global | grep <IP-du-témoin>` ; `cilium-dbg bpf policy get <id> -n` (identités numériques) ou sans `-n` (étiquettes). `cilium-dbg monitor --type trace --type drop --related-to <id>` ; `hubble observe --pod wb-pannes/<pod> --follow`. La [référence des commandes](https://docs.cilium.io/en/v1.20/cmdref/) liste les sous-commandes exactes de ta version.
</details>

<details><summary>Indice 3</summary>

Les noms des programmes et des tables sont dans le code de Cilium (`bpf/bpf_lxc.c`, `bpf/bpf_host.c`, `bpf/bpf_sock.c`, `bpf/lib/maps.h`) ; la page [eBPF Datapath](https://docs.cilium.io/en/v1.20/network/ebpf/) les décrit. `bpftool prog show name <nom>` donne l'identifiant, `bpftool prog show id <id>` les tables utilisées (`map_ids`).
</details>

**Pour aller plus loin** : mesure le coût d'une mise à jour de Service avec 500 Services jetables dans `wb-essais` (temps de propagation dans `bpf lb list`, CPU de l'agent dans `kubectl top`), puis supprime-les ; compare à ce qu'aurait fait kube-proxy en mode iptables (`iptables-save | wc -l` sur un cluster d'essai, M15-E19).

---

### M15-E45 — Questions expert : réseau Kubernetes  `Q` `★★★`

> **Ticket PLAT-1645** — *De : Karim Benali*
> Dernière étape avant la recette du réseau v1 : ces questions, je les pose en entretien pour un poste d'ingénieur plateforme. Réponds par écrit, en argumentant. Pas de recherche pendant la première passe ; vérifie ensuite dans la documentation et corrige-toi en couleur.

**Objectifs pédagogiques**
- Consolider les mécanismes manipulés dans le module : modèle réseau de Kubernetes, Cilium et eBPF, Services et kube-proxy, DNS, politiques, LB IPAM et BGP, Gateway API, cert-manager, ExternalDNS, chiffrement.
- S'entraîner à argumenter une réponse technique comme en entretien ou en revue d'architecture.

**Prérequis** : paliers 1 à 3 du module, M15-E44.
**Durée indicative** : 2 h 30.

**Questions**

1. Énonce les trois exigences du modèle réseau de Kubernetes et dis lesquelles sont remplies par le CNI, par kube-proxy (ou son remplaçant) et par le DNS du cluster.
2. QCM — Un Service `ClusterIP` a un sélecteur qui ne correspond à aucun pod. Un client du cluster s'y connecte. Que se passe-t-il avec Cilium en remplacement de kube-proxy ?
   a) la connexion reste en attente jusqu'à expiration ; b) le client reçoit immédiatement un refus (ICMP ou RST) ; c) le paquet part vers la passerelle par défaut du nœud ; d) le DNS du cluster ne résout plus le nom du Service.
3. `externalTrafficPolicy: Local` contre `Cluster` sur un Service `LoadBalancer` annoncé en BGP : effet sur l'adresse source vue par le pod, sur l'équilibrage, sur les annonces BGP (quels nœuds annoncent ?), et sur ce qui se passe quand le dernier pod d'un nœud disparaît.
4. Pourquoi `ndots:5` est-il la valeur par défaut, et que coûte-t-il ? Donne deux manières de réduire ce coût sans casser la résolution des noms courts de Services.
5. NetworkPolicy standard et CiliumNetworkPolicy : qu'est-ce que la seconde exprime que la première ne peut pas exprimer (cite au moins quatre choses) ? Pourquoi garder malgré tout le `refus-par-defaut` en NetworkPolicy standard chez MédiSphère ?
6. QCM — Dans un espace, une NetworkPolicy autorise l'entrée depuis le pod A vers le pod B, et une CiliumNetworkPolicy contient un `ingressDeny` depuis le même pod A vers B. Le trafic A → B est :
   a) autorisé, la NetworkPolicy standard est prioritaire ; b) refusé, un refus l'emporte toujours ; c) autorisé ou refusé selon l'ordre de création ; d) refusé seulement si `enableDefaultDeny` est vrai.
7. Comment fonctionne `toFQDNs` dans Cilium (proxy DNS, cache, identités de CIDR) ? Pourquoi une règle `toFQDNs` sans règle DNS L7 associée ne fonctionne-t-elle pas, et que se passe-t-il quand le TTL de la réponse est très court ?
8. LB IPAM et BGP : qui attribue l'adresse, qui décide quels nœuds l'annoncent, et que fait la bordure quand trois nœuds annoncent la même /32 ? Quelle est la différence de convergence entre la perte d'un nœud (session tombée) et la perte d'un pod (annonce retirée) ?
9. Redémarrage gracieux BGP : que protège-t-il, que masque-t-il ? Pourquoi un temps de redémarrage trop long peut-il transformer un incident de 10 secondes en incident de 2 minutes ?
10. QCM — Avec `bgp ebgp-requires-policy` actif sur FRR, un voisin eBGP est configuré sans route-map de sortie. Que se passe-t-il ?
    a) FRR refuse de démarrer la session ; b) la session s'établit, mais FRR n'annonce rien à ce voisin ; c) FRR annonce toute sa table ; d) la session s'établit et seules les routes connectées sont annoncées.
11. Gateway API contre Ingress : rôles (fournisseur d'infrastructure, opérateur de cluster, développeur), délégation entre espaces, ce qui était une annotation propre au contrôleur et devient un champ standard. Cite trois annotations d'ingress-nginx de M15-E18 et leur équivalent.
12. Pourquoi la Gateway API exige-t-elle un `ReferenceGrant` pour qu'une route vise un Service d'un autre espace, ou qu'une Gateway utilise un Secret d'un autre espace ? Quel est le risque évité ?
13. TLS sur la Gateway : terminaison, ré-chiffrement vers le backend (`BackendTLSPolicy`), passage direct (`TLSRoute`). Pour chacun : qui voit le trafic en clair, où est la clé privée, quelles fonctions L7 restent possibles ?
14. cert-manager : décris le chemin d'un renouvellement automatique (quand il se déclenche, quels objets sont créés, ce qui se passe si le défi échoue pendant 10 jours). Que change ACME ARI ?
15. DNS-01 par RFC 2136 contre API PowerDNS : pourquoi MédiSphère a-t-elle choisi RFC 2136 + TSIG (périmètre de la clé, journalisation, indépendance du fournisseur) ? Quelles métadonnées de zone rendent ce choix sûr ?
16. ExternalDNS : pourquoi le registre TXT existe-t-il, et que se passe-t-il si deux clusters partagent la même zone avec le même `txt-owner-id` ? avec des identifiants différents ? Quand préférer la politique `upsert-only` à `sync` ?
17. WireGuard dans Cilium : qu'est-ce qui est chiffré par défaut (pod à pod entre nœuds), qu'est-ce qui ne l'est pas (nœud à nœud, sauf option), comment les clés sont distribuées et changées. Pourquoi aucune règle de bordure n'est-elle nécessaire pour l'UDP 51871 ?
18. QCM — Un pod du nœud A joint un pod du nœud B ; Cilium est en tunnel VXLAN avec WireGuard. Sur l'interface physique de A, `tcpdump` montre :
    a) de l'UDP 8472 vers B ; b) de l'UDP 51871 vers B ; c) le paquet du pod en clair, adresses de pods ; d) de l'ESP (IPsec).
19. Remplacement de kube-proxy : que doit-on faire pour qu'une montée de version de kubeadm ne réinstalle pas kube-proxy, et que se passe-t-il pour les Services pendant la bascule d'un nœud ? Que devient l'accès à l'API depuis les agents Cilium avant qu'ils ne puissent résoudre le Service `kubernetes` ?
20. Un développeur te dit « mon service est injoignable ». Décris ta démarche, des premières questions jusqu'à la preuve de la cause, en citant pour chaque étage du chemin l'outil et l'objet que tu consultes, et les gestes que tu t'interdis tant que tu n'as pas la preuve.

**Critères de réussite**
- [ ] Les 20 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses).
- [ ] Après correction, tu as identifié tes trois points les plus faibles et noté un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour 1 à 10 : le [modèle réseau de Kubernetes](https://kubernetes.io/docs/concepts/services-networking/), les pages Cilium [Kubernetes Without kube-proxy](https://docs.cilium.io/en/v1.20/network/kubernetes/kubeproxy-free/), [Policy](https://docs.cilium.io/en/v1.20/security/policy/), [LB IPAM](https://docs.cilium.io/en/v1.20/network/lb-ipam/), [BGP Control Plane](https://docs.cilium.io/en/v1.20/network/bgp-control-plane/bgp-control-plane/) ; tes journaux de M15-E35 à M15-E38.
</details>

<details><summary>Indice 2</summary>

Pour 11 à 20 : la [documentation de la Gateway API](https://gateway-api.sigs.k8s.io/), [cert-manager ACME](https://cert-manager.io/docs/configuration/acme/), [ExternalDNS — registre TXT](https://kubernetes-sigs.github.io/external-dns/latest/docs/registry/txt/), [WireGuard dans Cilium](https://docs.cilium.io/en/v1.20/security/network/encryption-wireguard/) ; ton compte rendu de M15-E44.
</details>

**Pour aller plus loin** : choisis trois questions et transforme chacune en démonstration de 5 minutes sur le lab (reproductible, sans geste destructif), à présenter à Karim.
