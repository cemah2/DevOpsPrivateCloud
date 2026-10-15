# Module 15 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Les fichiers complets sont dans [`fichiers/`](fichiers/), un dossier par exercice, sous la forme d'un **extrait des projets** : `fichiers/M15-EXX/k8s/…` = chemins de `plateforme/k8s`, `…/ansible/…` = `plateforme/ansible`, `…/infra/…` = `plateforme/infra`, `…/outils/…` = `plateforme/outils`, `…/medisphere/…` = la documentation ; `…/essais/…` et les fichiers à la racine d'un dossier se posent dans `~/m15/eXX/` sur `adm01`. On **superpose** les dossiers dans l'ordre (E10, E11…) : un fichier d'un exercice plus récent remplace le précédent (exemple : `values.yaml` de cert-manager en E13 puis E14). Les `*.extrait*` sont des morceaux à intégrer dans un fichier existant (l'emplacement est dit en tête), les `*.exemple` des modèles sans valeur réelle.

**Ce qui a été vérifié, ce qui ne l'a pas été.**
- *CRD et champs* : relevés dans les sources au tag exact — documentation de Cilium **v1.20.2** (`lb-ipam.rst`, `bgp-control-plane-configuration.rst`, `bgp-control-plane-operation.rst`, `gateway-api/*.rst`, `ingress-reference.rst`, `upgrade-current.inc`), CRD de la Gateway API **v1.6.1** (`standard-install.yaml` de la publication : versions servies, filtres d'`HTTPRoute`, `TLSRoute` v1), chart et notes de version de cert-manager **v1.21.2** (`config.gatewayAPI.enabled`, `dns01RecursiveNameservers*`), documentation d'ExternalDNS **v0.23.0** (`docs/flags.md`, tutoriel RFC2136, sources Gateway API, préfixe d'annotations), page *Dynamic DNS Update* de PowerDNS **5.0** (ordre des autorisations, `metadata add`, `NOTIFY-DNSUPDATE`, `dnsupdate-require-tsig`), notes de version de MetalLB **0.16.1**, code d'`agnhost` 2.61 (`netexec`, `grpc-health-checking`, `connect` ; l'image du module est la 2.66.1, mêmes sous-commandes : à vérifier sur ton lab).
- *Validation outillée* : tous les manifestes de `fichiers/` et de `ressources/E21-…` passent `kubeconform` 0.8.0 en mode strict, avec les schémas Kubernetes 1.36 et ceux générés depuis les CRD Cilium 1.20.2, Gateway API v1.6.1, cert-manager 1.21.2 et MetalLB 0.16.1 ; les values de cert-manager et d'ExternalDNS ont été rendues par `helm template` avec les charts épinglés ; `ingress2gateway` 1.2.0 a été **compilé et lancé** sur les Ingress fournis (sortie réelle dans [`fichiers/M15-E18/`](fichiers/M15-E18/)) ; la configuration HAProxy d'E20 a été rendue par Ansible depuis le gabarit du rôle `haproxy` (M07-E28) et déclarée valide par `haproxy -c` (HAProxy **2.8** de l'environnement de rédaction, chemins de certificats remplacés : à refaire avec la 3.2 du lab, ce que fait le rôle avant chaque rechargement) ; les expressions Jinja de `dnsupdate.yml` ont été évaluées sur des sorties simulées de `pdnsutil` ; `outils/schemas-crd.sh` (E23) a produit les schémas des CRD utilisés pour `kubeconform` ; OpenTofu n'était pas disponible (`dns-apps.tf` et `envs/m15-essai/` non passés à `tofu validate`) ; les fichiers Ansible passent `ansible-lint` (profil `production`) et `yamllint` ; les scripts et checks passent ShellCheck et `bash -n`.

**Non rejoués sur un cluster réel** (signalés « ⚠️ À vérifier sur ton lab ») : forme exacte des sorties de `cilium bgp peers` et des conditions des objets ; nombre de chemins ECMP réellement installés par FRR 10.7 avec `maximum-paths 8` ; comportement du proxy L7 de Cilium vis-à-vis de la chaîne de requête dans `path` ; prise en charge du filtre `CORS` par Cilium 1.20 ; rechargement du Secret `apps-joker` par l'Envoy de la Gateway sans coupure ; autocontrôle DNS-01 de cert-manager dirigé vers un serveur faisant autorité ; lecture de `/dev/stdin` par `kubectl create secret --from-file` (évitée : l'outil passe par `yq`) ; durée de bascule des répartiteurs avec le nouveau frontal TCP ; publication d'`ExternalIP` par le plan de contrôle BGP avec le remplacement de kube-proxy (E11, étape 7).

**Où lancer les commandes.** `admin@adm01:~$` avec ton kubeconfig personnel (groupe `medisphere:plateforme-admins`) ; `admin@gw01:~$` / `admin@gw02:~$` en SSH pour `vtysh` (`sudo vtysh -c '…'`) ; `admin@dns01:~$` pour `pdnsutil` (`sudo -u pdns pdnsutil …`). Les identités en lecture (`k8s-checks.kubeconfig`) ne servent qu'aux vérifications.

---

### M15-E10 — LB IPAM : des adresses de service en 10.10.41.0/24

**Solution**

Fichiers : [`lb-par1.yaml`](fichiers/M15-E10/k8s/composants/cilium/lb-ipam/lb-par1.yaml), [`essai-lb.yaml`](fichiers/M15-E10/essais/essai-lb.yaml), [`erreurs.yaml`](fichiers/M15-E10/essais/erreurs.yaml), [`gw-essai-adresse.extrait.yaml`](fichiers/M15-E10/essais/gw-essai-adresse.extrait.yaml).

1. **Lecture.** Un Service dont `loadBalancerClass` n'est pas géré par Cilium (ni vide, ni `io.cilium/bgp-control-plane`, ni `io.cilium/l2-announcer`) est **entièrement ignoré** : pas d'adresse, pas même une condition (`default-lb-service-ipam: none` inverse le défaut). `allowFirstLastIPs` ne vaut que pour les blocs `cidr` (adresses réseau et diffusion) ; un bloc `start`/`stop` n'est pas concerné. Modifier un pool peut **réattribuer** des adresses de Services existants (issue 40358 citée par la documentation) : un changement du pool est donc un changement à part entière (MR qui dit qui est touché).
2. **Inventaire.** Au palier 1, `gw-essai` utilise la classe `cilium-nodeport` (Service `NodePort`, `CiliumGatewayClassConfig`) et `gw-attente` a été supprimée : la commande ne liste normalement **rien**. S'il reste un Service `LoadBalancer`, on le supprime ou on lui fixe une adresse de 10.10.41.11-19 ; pour une Gateway de la classe `cilium`, par `spec.addresses: [{type: IPAddress, value: 10.10.41.1X}]` ([extrait](fichiers/M15-E10/essais/gw-essai-adresse.extrait.yaml)) : c'est la méthode documentée (*Gateway API Addresses Support*) ; l'ancienne annotation `io.cilium/lb-ipam-ips` dans `spec.infrastructure.annotations` existe encore mais **l'emporte** sur `spec.addresses` si les deux sont présentes et sera dépréciée. Modifier directement le Service serait écrasé par le contrôleur de Cilium.
3. **Pool.**
   ```
   admin@adm01:~/src/k8s$ task appliquer          # ou : kubectl apply --server-side -f composants/cilium/lb-ipam/
   admin@adm01:~$ kubectl get ippools
   NAME      DISABLED   CONFLICTING   IPS AVAILABLE   AGE
   lb-par1   false      False         190             5s
   admin@adm01:~$ kubectl get ippool lb-par1 -o jsonpath='{.status.conditions}' | jq -c '.[] | {type, message}'
   ```
   190 adresses, aucune utilisée (`cilium.io/IPsUsed` = 0). Un seul bloc `start`/`stop` : avec deux tirets (`- start:` puis `- stop:`), on écrirait deux blocs incomplets que l'admission refuse.
4. **Essais.** `essai-lb` reçoit 10.10.41.20 (annotation `lbipam.cilium.io/ips`). `essai-lb-a` et `essai-lb-b` reçoivent tous deux 10.10.41.22 : même `lbipam.cilium.io/sharing-key`, même espace, aucun port en commun (80 et 8081). L'adresse est demandée **sur les deux** : la documentation dit qu'un Service à clé de partage qui demande une adresse l'ajoute à l'ensemble de la clé, mais si le Service **sans** demande est créé le premier, il prend la première adresse libre… c'est-à-dire 10.10.41.10. Essaie-le (crée `essai-lb-b` sans annotation d'adresse, constate `.10`, supprime) : c'est exactement le piège qui menace `gw-par1`, d'où la convention écrite en tête de `lb-par1.yaml`. Une adresse libérée est réutilisable tout de suite. Si les ports se recouvraient, LB IPAM ajouterait une **seconde** adresse à l'ensemble de la clé. ⚠️ À vérifier sur ton lab : l'ordre exact d'attribution automatique (première adresse libre) n'est pas une garantie documentée ; ne t'y fie jamais, demande l'adresse.
5. **Joignabilité.**
   ```
   admin@k8s-w01:~$ curl -s http://10.10.41.20/hostname ; echo
   agnhost-7c9d…-x2k4q
   admin@adm01:~$ ip route get 10.10.41.20
   10.10.41.20 via 10.10.10.1 dev ens18 src 10.10.10.10
   admin@gw01:~$ ip route get 10.10.41.20
   10.10.41.20 via <IP-GW-WAN-VIP ou routeur du LAN maison> dev ens18 …     # route par défaut !
   ```
   Depuis un nœud ou un pod, l'eBPF de Cilium intercepte l'adresse (le remplacement de kube-proxy traite les adresses `LoadBalancer` comme des frontaux, dès la socket pour un nœud). Depuis `adm01`, le paquet part vers la bordure, qui n'a **aucune** route vers 10.10.41.0/24 (aucune interface, aucune annonce) : il part vers Internet par la route par défaut et se perd (ou, selon les règles de la matrice, est refusé en transit). C'est le travail d'E11.
6. **Chemin de données.**
   ```
   admin@adm01:~$ kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg service list | grep -A2 10.10.41.20
   42   10.10.41.20:80/TCP    LoadBalancer   1 => 10.240.1.17:8080/TCP (active)
                                              2 => 10.240.2.33:8080/TCP (active)
   ```
   Frontal de type `LoadBalancer`, deux *backends* (les pods `agnhost`, adresses de pods 10.240.x). Les mêmes *backends* apparaissent pour le ClusterIP et le NodePort du Service.
7. **Erreurs.** (a) `kubectl -n wb-essais get svc essai-hors-pool -o jsonpath='{.status.conditions}'` → `io.cilium/lb-ipam-request-satisfied` = `False`, message indiquant que l'adresse demandée n'appartient à aucun pool correspondant ; le Service reste `<pending>`. (b) `essai-conflit` apparaît `CONFLICTING True`, condition `cilium.io/PoolConflict` (« Pool conflicts since CIDR … overlaps … from IP Pool 'lb-par1' ») ; c'est le **dernier** pool créé qui est marqué, `lb-par1` continue de servir. Suppression des deux objets.

**Explications**

Hors nuage, un Service `LoadBalancer` a besoin de trois choses que Kubernetes ne fournit pas : une **adresse** (ici LB IPAM, dans l'opérateur Cilium), un **chemin de données** vers les pods (l'eBPF de l'agent, qui programme l'adresse comme frontal sur chaque nœud) et une **annonce** pour que le reste du réseau sache où envoyer les paquets (BGP en E11 ; ou ARP/NDP en mode L2). LB IPAM écrit l'adresse dans `status.loadBalancer.ingress` et ses décisions dans `status.conditions` du Service : tout le diagnostic est là. Un pool sans `serviceSelector` sert tous les Services ; les pools ne doivent pas se recouvrir (le dernier venu est mis en conflit, *soft error*).

**Alternatives**
- *Plusieurs pools* (un par usage : `passerelles` avec `serviceSelector` sur l'espace, un pour les essais) : rend la réservation de `.10` réelle au lieu d'une convention, mais la décision du PLAN est un pool unique ; c'est une option pour l'ADR-0150.
- *`spec.loadBalancerIP`* : déprécié depuis Kubernetes 1.24, toujours lu par Cilium ; l'annotation est la forme recommandée.
- *L2 announcements* (`CiliumL2AnnouncementPolicy`, encore `v2alpha1`) : seulement si les adresses de service sont dans le réseau des nœuds, ce qui n'est pas notre plan d'adressage.

**Pièges classiques**
- Créer le pool avant d'avoir fixé l'adresse des Services en attente : le premier prend `.10`.
- Écrire `start` et `stop` dans deux éléments de `blocks`.
- Chercher l'erreur dans les journaux au lieu de `status.conditions` du Service.
- Croire qu'un `curl` réussi depuis un nœud prouve la joignabilité depuis le lab.
- Laisser dans `wb-essais` les politiques de refus d'E06 : les essais échouent pour une tout autre raison.

**En production chez MédiSphère**
Alerte sur `cilium.io/IPsAvailable` (moins de 20 adresses libres) au M21 ; inventaire des adresses attribuées reporté dans NetBox (préfixe 10.10.41.0/24, une adresse par Service publié) ; politique d'admission (Kyverno, M26) qui refuse l'annotation `lbipam.cilium.io/ips` hors des espaces de la plateforme, pour qu'une équipe ne s'empare pas de l'adresse d'une autre.

---

### M15-E11 — BGP : annoncer les services à la bordure

**Solution**

Fichiers : [`frr.yml`](fichiers/M15-E11/ansible/inventories/lab/group_vars/role_routeur/frr.yml) (remplace celui de M07), [`ms-verif-reseau.conf.extrait`](fichiers/M15-E11/outils/etc/ms-verif-reseau.conf.extrait), [`values.yaml.extrait`](fichiers/M15-E11/k8s/composants/cilium/values.yaml.extrait), [`bgp-par1.yaml`](fichiers/M15-E11/k8s/composants/cilium/bgp/bgp-par1.yaml), [`bordure.yaml`](fichiers/M15-E11/k8s/composants/cilium/bgp/bordure.yaml), [`services-lb.yaml`](fichiers/M15-E11/k8s/composants/cilium/bgp/services-lb.yaml), [`noeuds.yaml`](fichiers/M15-E11/k8s/cluster/noeuds.yaml) et [`etiqueter-noeuds.sh`](fichiers/M15-E11/k8s/outils/etiqueter-noeuds.sh), [`Taskfile.reseau-bgp.extrait.yml`](fichiers/M15-E11/k8s/Taskfile.reseau-bgp.extrait.yml), [`bgp.md`](fichiers/M15-E11/medisphere/docs/kubernetes/reseau/bgp.md), [`essai-hors-pool.yaml`](fichiers/M15-E11/essais/essai-hors-pool.yaml).

1. **Lecture.** Six sessions : chaque travailleur (AS 65040, 10.10.40.61-63) vers `gw01` (10.10.40.2) et `gw02` (10.10.40.3), AS 65000. Tant que `neighbor K8S shutdown` existe, FRR refuse toute session du groupe : un voisin dynamique créé par la plage d'écoute hérite du `shutdown` du groupe ; la connexion TCP est acceptée puis fermée, l'agent Cilium reste en `active`/`connect`. Une `CiliumBGPPeerConfig` sans annonce sélectionnée établit la session mais **n'annonce rien** (« Default configuration is to not advertise any prefix ») : piège classique, tout est vert sauf le résultat.
2. **Bordure.** Trois changements dans `frr.yml` (lire l'en-tête du fichier) : retrait de `neighbor K8S shutdown`, `neighbor K8S maximum-prefix 200` dans l'AF IPv4, `maximum_paths: 8` dans `frr_bgp` (le rôle le rend en `maximum-paths 8`). Avant le pipeline :
   ```
   admin@gw01:~$ sudo vtysh -c 'show bgp summary'        # état de référence (à garder dans le ticket)
   ```
   Après :
   ```
   admin@gw01:~$ sudo vtysh -c 'show bgp peer-group K8S'
   BGP peer-group K8S, remote AS 65040
     Peer-group type is external
     Configured address-families: IPv4 Unicast;
     1 listen range(s)
       IPv4:
         10.10.40.0/24
     Peer-group members:
   ```
   (Pas encore de membres : Cilium n'est pas configuré.) `ms-verif-reseau.conf` reçoit les trois travailleurs dans `MS_BGP_TOUS` (ils parlent aux **deux** passerelles, pas seulement au maître).
3. **Nœuds et Cilium.** `cluster/noeuds.yaml` + `outils/etiqueter-noeuds.sh` (idempotent, `--verifier` pour la dérive, E23) plutôt qu'un `kubectl label` qui serait oublié à la reconstruction d'un nœud. Values : `bgpControlPlane.enabled: true`, puis :
   ```
   admin@adm01:~/src/k8s$ cilium upgrade --version <VERSION-CILIUM> --reset-values --values composants/cilium/values.yaml
   admin@adm01:~$ kubectl -n kube-system rollout restart deployment/cilium-operator daemonset/cilium
   admin@adm01:~$ kubectl -n kube-system rollout status daemonset/cilium --timeout=10m && cilium status --wait
   admin@adm01:~$ cilium config view | grep bgp-control-plane
   enable-bgp-control-plane                          true
   admin@adm01:~$ kubectl get crd | grep ciliumbgp
   ciliumbgpadvertisements.cilium.io      …
   ciliumbgpclusterconfigs.cilium.io      …
   ciliumbgpnodeconfigoverrides.cilium.io …
   ciliumbgpnodeconfigs.cilium.io         …
   ciliumbgppeerconfigs.cilium.io         …
   ```
   `cilium upgrade` ne fait que réécrire la ConfigMap `cilium-config` (`enable-bgp-control-plane`) : comme au palier 1, `rollOutCiliumPods` vaut `false`, c'est le `rollout restart` qui fait lire le réglage à l'opérateur (qui produira les `CiliumBGPNodeConfig`) et aux agents (qui démarrent le plan de contrôle BGP). Les CRD `ciliumbgp*`, elles, existent déjà : l'opérateur 1.20 les enregistre toutes à son démarrage, quel que soit ce réglage (`pkg/k8s/apis/cilium.io/client/register.go`) ; leur présence ne prouve donc pas que le plan de contrôle est actif, `enable-bgp-control-plane: "true"` dans `cilium-config` et des agents redémarrés, si. Le DaemonSet redémarre les agents par vagues, sans impact sur les connexions établies (le chemin de données eBPF reste en place).
4. **Objets BGP.** `bgp-par1` sélectionne `bgp=par1`, une instance `localASN: 65040`, deux pairs nommés `gw01`/`gw02` qui pointent vers `bordure` ; `bordure` fixe 3/9 s et `connectRetryTimeSeconds: 5`, une famille `ipv4/unicast` qui sélectionne `bgp.medisphere.internal/annonce: services` ; `services-lb` porte cette étiquette et annonce `LoadBalancerIP` de tous les Services (`NotIn` sur une clé factice). Pas de `localPort` : la bordure est passive (plage d'écoute), l'agent actif.
5. **Lectures.**
   ```
   admin@adm01:~$ cilium bgp peers
   Node      Local AS   Peer AS   Peer Address    Session State   Uptime   Family         Received   Advertised
   k8s-w01   65040      65000     10.10.40.2:179  established     2m       ipv4/unicast   0          2
             65040      65000     10.10.40.3:179  established     2m       ipv4/unicast   0          2
   k8s-w02   …
   admin@adm01:~$ cilium bgp routes advertised ipv4 unicast
   admin@adm01:~$ kubectl get ciliumbgpnodeconfigs k8s-w01 -o jsonpath='{.status.bgpInstances[0].peers}' | jq
   admin@gw01:~$ sudo vtysh -c 'show bgp summary'
   Neighbor        V  AS    MsgRcvd MsgSent  Up/Down State/PfxRcd   PfxSnt Desc
   *10.10.40.61    4  65040 …                00:02:10            2        0 noeuds Kubernetes…
   *10.10.40.62    4  65040 …                                    2        0
   *10.10.40.63    4  65040 …                                    2        0
   * - dynamic neighbor
   admin@gw01:~$ sudo vtysh -c 'show ip route 10.10.41.20'
   Routing entry for 10.10.41.20/32
     Known via "bgp", distance 20, metric 0, best
     * 10.10.40.61, via ens19.40, weight 1
     * 10.10.40.62, via ens19.40, weight 1
     * 10.10.40.63, via ens19.40, weight 1
   ```
   `Received 0` côté Cilium : `RM-K8S-OUT` refuse tout, comme voulu ; `PfxSnt 0` côté FRR confirme. Deux préfixes reçus au moins : `.20` (`essai-lb`) et `.22` (adresse partagée d'E10), plus toute autre adresse attribuée. ⚠️ À vérifier sur ton lab : le libellé exact des colonnes de `cilium bgp peers` (CLI 0.20) et le nombre de prochains sauts installés (ECMP).
6. **Trafic.** Les 20 requêtes répondent, réparties sur les deux pods. Le trafic entre par le nœud que la bordure a choisi par hachage ECMP (5-tuple) ; ce nœud n'est pas forcément celui d'un pod : avec `externalTrafficPolicy: Cluster`, l'eBPF le renvoie vers un pod d'un autre nœud (dans le tunnel VXLAN, avec traduction de la source sauf DSR). `hubble observe --ip 10.10.41.20` montre l'entrée sur un nœud et la traduction vers l'adresse du pod.
7. **Politique.** Avec `ExternalIP` ajouté, Cilium **annonce** 10.10.42.10/32 (`cilium bgp routes advertised ipv4 unicast` le montre) ; la bordure le rejette à l'entrée : `show bgp ipv4 unicast 10.10.42.10/32` → « Network not in table ». `received-routes` n'est disponible qu'avec `soft-reconfiguration inbound` (absent du groupe : on ne garde pas en mémoire ce qu'on refuse) ; on peut le voir indirectement avec `show bgp neighbors 10.10.40.61` (compteur de préfixes reçus/acceptés). Sans `RM-K8S-IN`, n'importe quel utilisateur capable de créer un Service avec `externalIPs` détournerait l'adresse de son choix dans tout le lab (c'est la CVE-2020-8554 de Kubernetes, transposée au routage). ⚠️ À vérifier sur ton lab : avec le remplacement de kube-proxy, Cilium ne traite les `externalIPs` que si la fonction est activée (`externalIPs.enabled`) ; si rien n'est annoncé, note-le, l'essai garde son intérêt (lecture de la politique d'entrée).
8. **Travailleur perdu.** `kubectl drain k8s-w02 --ignore-daemonsets`, retrait de `bgp: par1` dans `noeuds.yaml` puis `task etiquettes` : la session de `w02` se ferme proprement (message `Cease`), `gw01` retire ses chemins en moins d'une seconde ; la boucle depuis `adm01` ne perd rien ou une requête (connexion en cours sur `w02`). Remise en place inverse. À comparer en E25 avec un arrêt brutal (détection par la durée de maintien : 9 s).
9. **Documentation** : [`bgp.md`](fichiers/M15-E11/medisphere/docs/kubernetes/reseau/bgp.md).

**Explications**

Le plan de contrôle BGP v2 sépare le **qui** (`CiliumBGPClusterConfig` : quels nœuds, quelle instance, quels pairs), le **comment** (`CiliumBGPPeerConfig` : temporisateurs, familles, mot de passe, *graceful restart*) et le **quoi** (`CiliumBGPAdvertisement` : quels préfixes, quels attributs), reliés par des sélecteurs d'étiquettes. L'opérateur en déduit un `CiliumBGPNodeConfig` par nœud, dont le `status` porte l'état réel des sessions. L'annonce d'une adresse `LoadBalancer` en `/32` par **chaque** travailleur, plus l'ECMP de la bordure, donne une répartition de charge et une tolérance à la panne d'un nœud sans aucun équipement en plus. Côté FRR, `bgp ebgp-requires-policy` impose des politiques explicites ; la plage d'écoute rend la bordure indifférente au nombre de nœuds (jusqu'à `bgp listen limit 16`).

**Alternatives**
- *Sessions vers la VIP .1* : la VIP change de passerelle, la session tombe à chaque bascule VRRP ; et seul le maître aurait les routes.
- *TCP-MD5* (`authSecretRef`, Secret dans `kube-system`) : protège contre une session usurpée sur le VLAN 40. Le M07 ne l'a pas mis sur le groupe `K8S` ; c'est défendable tant que le VLAN ne porte que les nœuds et que `RM-K8S-IN` borne ce qui est accepté ; à reprendre dans l'ADR-0150 (et le mot de passe devra être identique sur toute la plage d'écoute).
- *BFD* : détection sous la seconde ; Cilium 1.20 ne le propose pas dans le plan de contrôle v2 documenté (à vérifier), d'où des temporisateurs courts.
- *Annoncer les PodCIDR* (routage natif, sans tunnel) : discuté en E29.
- *MetalLB en BGP* : voir E19.

**Pièges classiques**
- Oublier l'étiquette de la `CiliumBGPAdvertisement` (session établie, rien d'annoncé).
- Étiqueter les nœuds à la main : la reconstruction d'un nœud (M14-E23) perd l'étiquette et le nœud cesse d'annoncer sans alerte.
- Laisser les nœuds de contrôle annoncer (sélecteur trop large) : le trafic des applications passe par le plan de contrôle.
- Mettre `soft-reconfiguration inbound` « pour voir » en production : mémoire, et rien de plus qu'un `debug`.
- Oublier `ms-verif-reseau` : la supervision de la bordure ne voit pas une session Kubernetes tombée.

**En production chez MédiSphère**
Alertes sur l'état des sessions (métriques Cilium `cilium_bgp_*` et FRR, M21), *graceful restart* évalué en E25, procédure de maintenance d'un nœud (retrait de l'étiquette avant arrêt) dans RB-152, communautés BGP pour distinguer les adresses « publiques » des adresses internes si la bordure doit un jour les traiter différemment.

---

### M15-E12 — La Gateway principale `gw-par1` et le TLS

**Solution**

Fichiers : [`passerelles.yaml`](fichiers/M15-E12/k8s/espaces/passerelles.yaml), [`exposition.extrait.yaml`](fichiers/M15-E12/k8s/espaces/exposition.extrait.yaml), [`gw-par1.yaml`](fichiers/M15-E12/k8s/composants/passerelles/gw-par1.yaml), [`redirection-https.yaml`](fichiers/M15-E12/k8s/composants/passerelles/redirection-https.yaml) (version E12 ; E15 lui ajoute une étiquette), [`httproute-mediagenda.yaml`](fichiers/M15-E12/k8s/espaces/mediagenda-recette/httproute-mediagenda.yaml), [`route-refusee.yaml`](fichiers/M15-E12/essais/route-refusee.yaml), [`joker-manuel.sh`](fichiers/M15-E12/essais/joker-manuel.sh).

1. **Lecture.** Le modèle de rôles de la Gateway API : le **fournisseur d'infrastructure** (ici Cilium, et l'équipe Plateforme qui l'installe) possède la `GatewayClass` ; l'**opérateur du cluster** (équipe Plateforme) possède les `Gateway` (adresses, noms, certificats, qui peut s'y attacher) ; les **équipes applicatives** possèdent leurs `HTTPRoute`. `allowedRoutes` garantit que seules les routes des espaces choisis s'attachent à un écouteur, et que leurs noms recoupent celui de l'écouteur. Il **ne garantit pas** qu'une équipe admise ne prenne pas le nom d'une autre (deux routes de deux espaces pour `x.apps…` : la plus ancienne gagne, conflit silencieux) : c'est une convention (`<application>-<env>.apps…`) et, au M26, une politique d'admission.
2. **Espaces.** `passerelles` (PSA `restricted`, aucun pod n'y tourne), étiquette `medisphere.internal/exposition: oui` sur `passerelles`, `mediagenda-recette`, `wb-essais` ; **pas** sur `mediagenda-dev` (étape 7). Seule la plateforme écrit les objets `Namespace` (RBAC du M14) : l'étiquette est une décision de la plateforme.
3. **Certificat manuel.** [`joker-manuel.sh`](fichiers/M15-E12/essais/joker-manuel.sh) : `step ca certificate` dans `/run/user/<uid>` (tmpfs), Secret produit par `kubectl create secret tls --dry-run=client -o yaml | kubectl apply -f -`, répertoire effacé par un `trap` même en cas d'erreur. `step ca certificate` écrit la chaîne (feuille + intermédiaire), ce qu'attend l'Envoy. Durée : 7 jours (plafond du provisioner `admin` depuis M06-E27) — d'où l'urgence d'E13-E14. ⚠️ À vérifier sur ton lab : si une politique de provisioner refuse les jokers, le message de `step` le dit ; le provisioner `admin` de M06 n'en a pas.
4. **Gateway.**
   ```
   admin@adm01:~/src/k8s$ task appliquer
   admin@adm01:~$ kubectl -n passerelles get gateway gw-par1
   NAME      CLASS    ADDRESS       PROGRAMMED   AGE
   gw-par1   cilium   10.10.41.10   True         20s
   admin@adm01:~$ kubectl -n passerelles get gateway gw-par1 -o jsonpath='{range .status.listeners[*]}{.name}{" "}{range .conditions[*]}{.type}={.status} {end}{"\n"}{end}'
   http Accepted=True Programmed=True ResolvedRefs=True
   https Accepted=True Programmed=True ResolvedRefs=True
   admin@adm01:~$ kubectl -n passerelles get svc
   NAME                     TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)
   cilium-gateway-gw-par1   LoadBalancer   10.96.…        10.10.41.10   80:3…/TCP,443:3…/TCP
   ```
   Si le Secret manque, l'écouteur `https` passe en `ResolvedRefs=False` (`InvalidCertificateRef`) et la Gateway reste servie sur 80 : c'est la première chose à lire. `allowedRoutes.kinds` limite aussi le **type** de route par écouteur (`GRPCRoute` permise sur `https` pour E16).
5. **Route MédiAgenda.** Dans `espaces/mediagenda-recette/` : elle appartient à l'application (elle suivra le dépôt de déploiement de MédiAgenda au M17) et non à l'entrée. `parentRefs` vise `gw-par1` de `passerelles`, `sectionName: https` ; aucun `ReferenceGrant` : la route et le Service sont dans le même espace.
6. **Essais.** `/sante` → `{"statut":"ok",…}` (200) ; en HTTP → `301 Moved Permanently`, `location: https://mediagenda-recette.apps…/sante`. `openssl s_client` : `issuer=… MédiSphère Intermediate CA`, `subject=CN=*.apps.par1.medisphere.internal`, `notAfter` à 7 jours. Avec `-servername essai.ailleurs.internal` : la poignée de main aboutit (l'Envoy présente le seul certificat qu'il a), puis une requête reçoit 404 (aucune route pour ce nom) — ou, selon la version, la poignée de main échoue faute de chaîne de filtres correspondant au SNI. ⚠️ À vérifier sur ton lab.
7. **Délégation.** `essai-refus` dans `mediagenda-dev` : `status.parents[0].conditions` → `Accepted=False`, `reason: NotAllowedByListeners`. La route existe, elle n'est simplement attachée à rien ; aucun trafic.
8. **NetBox/DNS.** Adresse 10.10.41.10/32 (préfixe 10.10.41.0/24 du VLAN 41), rôle *VIP*, `dns_name: gw-par1.par1.medisphere.internal`, description « Gateway principale de k8s-par1 (DEV-1612) ». Après `medictl dns sync` : `dig +short gw-par1.par1.medisphere.internal` → 10.10.41.10, `dig +short -x 10.10.41.10` → le nom.
9. **Adresse client.** Le journal JSON de MédiAgenda (`client`) montre l'adresse de l'**Envoy** (un nœud) ; l'en-tête `X-Forwarded-For` (et `X-Envoy-External-Address`) contient celle du client (`adm01`, 10.10.10.10) : l'Envoy de Cilium conserve l'adresse source jusqu'à lui (TPROXY), quelle que soit `externalTrafficPolicy` (page *Reference*). Uvicorn n'utilise `X-Forwarded-For` que si on le lui demande (`--forwarded-allow-ips`) : à demander à Julien pour la production.

**Explications**

La Gateway est un objet de **plateforme** : une adresse, des noms, des certificats, une règle de délégation. Cilium la réalise avec l'Envoy de chaque nœud (DaemonSet `cilium-envoy`) et un Service `LoadBalancer` qui reçoit l'adresse de LB IPAM, annoncée en BGP ; le trafic arrivé sur n'importe quel nœud est remis à l'Envoy **local** par TPROXY, qui applique les routes et sort vers les pods avec l'identité `ingress` (E17). Le HTTP n'existe que pour rediriger (et pour les défis HTTP-01) ; l'ordre des choses est donc : écouteurs → routes de plateforme (redirection) → routes des équipes.

**Alternatives**
- *Une Gateway par équipe* : isolation plus forte (adresse, certificat, configuration), mais autant d'adresses, de certificats et de points de supervision ; la GEP `ListenerSet` (standard en v1.6) permet de déléguer des écouteurs sans multiplier les Gateways.
- *Mode « réseau hôte »* de la Gateway Cilium (écoute directe sur les nœuds) : pas de LB IPAM ni de BGP, mais adresse = nœuds ; écarté.
- *Certificat par application* plutôt qu'un joker : moins de portée en cas de fuite de la clé, plus d'objets ; le joker est défendable parce que sa clé ne quitte pas `passerelles`.

**Pièges classiques**
- Secret du certificat dans un autre espace que la Gateway sans `ReferenceGrant` (ou, pire, avec un `ReferenceGrant` trop large : E21).
- Nom d'hôte de route qui ne recoupe pas celui de l'écouteur (`apps.par1.medisphere.internal` lui-même n'est pas couvert par `*.apps…`).
- Route de redirection attachée aux deux écouteurs : boucle de redirection en HTTPS.
- Oublier `sectionName` : la route s'attache à **tous** les écouteurs compatibles (et la redirection redirigerait aussi le HTTPS).

**En production chez MédiSphère**
Supervision de l'échéance du joker (E26), de l'état `Programmed`, du code de retour par route (métriques Envoy au M21) ; durcissement TLS et en-têtes en E33 ; journaux d'accès de l'Envoy (Cilium *access logs*) vers Loki au M22, pour la traçabilité HDS.

---

### M15-E13 — cert-manager et l'ACME de step-ca

**Solution**

Fichiers : [`pare_feu.yml.extrait`](fichiers/M15-E13/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [`matrice-flux.extrait.md`](fichiers/M15-E13/medisphere/docs/socle/matrice-flux.extrait.md), [`values.yaml`](fichiers/M15-E13/k8s/composants/cert-manager/values.yaml) (version E13), [`clusterissuer-step-ca-acme.yaml`](fichiers/M15-E13/k8s/composants/cert-manager/clusterissuer-step-ca-acme.yaml) (version E13), [`certificate-essai-http01.yaml`](fichiers/M15-E13/essais/certificate-essai-http01.yaml), [`clusterissuer-sans-cabundle.yaml`](fichiers/M15-E13/essais/clusterissuer-sans-cabundle.yaml), [`installer-cmctl.sh`](fichiers/M15-E13/essais/installer-cmctl.sh), [`cert-manager.yaml`](fichiers/M15-E13/k8s/espaces/cert-manager.yaml) (l'espace, décrit dans le dépôt après sa création par `--create-namespace`).

1. **Chaîne d'objets.**
   ```
   Certificate (toi, ou cert-manager depuis une annotation de Gateway)
     └─ CertificateRequest (contrôleur certificates : une par émission, porte la CSR)
          └─ Order (contrôleur acme : une commande ACME par CSR)
               └─ Challenge (un par nom à prouver)
                    └─ solveur : HTTPRoute temporaire + pod/Service cm-acme-http-solver (HTTP-01)
                                 ou TXT _acme-challenge (DNS-01, E14)
     └─ Secret (clé privée + chaîne), réécrit à chaque renouvellement
   ClusterIssuer step-ca-acme ── compte ACME (Secret step-ca-acme-compte)
   ```
2. **Flux.** Définitions `NET_K8S_LB` et `GW_PAR1` (servent aussi en E14, E20), règle `$CA01` → `$GW_PAR1` TCP 80, sortie `$V_K8S`. Depuis `ca01` : `curl -sI http://gw-par1.par1.medisphere.internal/` → `HTTP/1.1 404 Not Found`, `server: envoy` : le chemin est ouvert, aucune route ne correspond (normal).
3. **Installation.** Values : `crds.enabled` et `crds.keep` (CRD gérées par le chart, conservées en cas de désinstallation), `config.gatewayAPI.enabled: true` (nouveau nom 1.21 ; `enableGatewayAPI` fonctionne encore mais est déprécié), deux réplicas du contrôleur (élection de chef) et du webhook, PDB. L'ordre compte : les CRD de la Gateway API doivent exister **avant** le démarrage du contrôleur (sinon : `kubectl -n cert-manager rollout restart deploy cert-manager`). Contrôles :
   ```
   admin@adm01:~$ kubectl -n cert-manager get deploy
   NAME                      READY   UP-TO-DATE   AVAILABLE
   cert-manager              2/2     2            2
   cert-manager-cainjector   1/1     1            1
   cert-manager-webhook      2/2     2            2
   admin@adm01:~$ kubectl -n cert-manager logs deploy/cert-manager | grep -i gateway | head -3
   ```
   Le journal montre le démarrage des contrôleurs `gateway-shim` et du solveur HTTPRoute.
4. **Émetteur.** `caBundle` = `base64 -w0 /usr/local/share/ca-certificates/medisphere-root-ca.crt` (une racine **publique** : versionnable) ; solveur sans sélecteur (défaut) `http01.gatewayHTTPRoute.parentRefs` → `gw-par1`, `passerelles`, `sectionName: http`. `kubectl describe clusterissuer step-ca-acme` → `Status: Acme: Uri: https://ca01…/acme/acme/account/…`, condition `Ready=True`, `The ACME account was registered with the ACME server`.
5. **Émission.**
   ```
   admin@adm01:~$ kubectl apply -f ~/m15/e13/certificate-essai-http01.yaml
   admin@adm01:~$ kubectl -n wb-essais get certificaterequest,order,challenge
   admin@adm01:~$ kubectl -n wb-essais get httproute         # cm-acme-http-solver-xxxxx, dans wb-essais
   admin@ca01:~$ sudo journalctl -u step-ca --since -5min | grep -i acme
   admin@adm01:~$ kubectl -n wb-essais get certificate essai-http01 -o jsonpath='{.status.notBefore} {.status.notAfter}{"\n"}'
   ```
   La route temporaire est dans l'espace du **Certificate** (`wb-essais`, admis par l'écouteur) ; elle vise `/.well-known/acme-challenge/<jeton>` en `Exact` pour le nom demandé, et disparaît après validation. Durée : 30 jours (le provisioner `acme` impose 720 h ; cert-manager n'a rien demandé). `status.renewalTime` ≈ 20 jours après l'émission (renouvellement aux 2/3 par défaut).
6. **Renouvellement forcé.** `cmctl renew essai-http01 -n wb-essais` (cmctl 2.6.1, dépôt `cert-manager/cmctl` : la CLI n'est plus livrée avec cert-manager) ; une nouvelle `CertificateRequest` (révision 2) ; `kubectl -n wb-essais get secret essai-http01-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -serial` change. (`kubectl cert-manager renew` est le même binaire installé comme greffon de kubectl.) La page *Certificate resource* ne documente aucune annotation de renouvellement : `cmctl renew` est **la** méthode recommandée. Supprimer le Secret déclenche aussi une ré-émission, mais la documentation la déconseille explicitement (« not a recommended solution ») : pendant l'émission, plus aucun certificat n'est servi.
7. **Sans `caBundle`.** `step-ca-acme-essai` reste `Ready=False`, message `Failed to register ACME account: … x509: certificate signed by unknown authority`. L'image de cert-manager (distroless) ne contient que les autorités publiques : la racine MédiSphère doit être fournie à **chaque** émetteur ACME privé.
8. **Joker.** Un nom joker ne peut être prouvé que par DNS-01 (RFC 8555 : l'autorité exige de contrôler la zone, pas un serveur) ; il faut donc écrire dans le DNS : E14.

**Explications**

cert-manager transforme le cycle de vie d'un certificat en objets Kubernetes réconciliés : une échéance qui approche crée une nouvelle `CertificateRequest`, et ainsi de suite. L'ACME de `ca01` est le même que celui des serveurs du socle (M06-E18) : même provisioner, même politique (30 jours, renouvellement automatique), mais le « client ACME » est désormais un contrôleur du cluster. Avec HTTP-01 par la Gateway API, cert-manager crée une `HTTPRoute` plutôt qu'un `Ingress` ; la Gateway doit avoir un écouteur 80 qui admet l'espace du `Certificate`.

**Alternatives**
- *Émetteur `ca` de cert-manager* avec une intermédiaire dédiée au cluster : pas d'ACME, pas de défi, mais une clé d'autorité dans un Secret du cluster ; refusé par la politique de certification (M06-E33).
- *step-issuer* (émetteur externe de Smallstep, provisioner JWK) : pas de défi non plus ; une dépendance de plus.
- *Annotations de Gateway* (`cert-manager.io/cluster-issuer` sur `gw-par1`) : cert-manager crée lui-même un `Certificate` par écouteur ; pratique, mais le `Certificate` n'est plus dans le dépôt (on garde un `Certificate` explicite en E14).

**Pièges classiques**
- `caBundle` en PEM brut au lieu de base64 (refusé à l'admission, ou émetteur jamais prêt).
- Activer la Gateway API dans les values après l'installation sans redémarrer le contrôleur.
- Espace du `Certificate` non admis par l'écouteur `http` : route temporaire `Accepted=False`, défi qui expire.
- Flux `ca01` → Gateway oublié : l'autocontrôle de cert-manager **réussit** (il interroge depuis le cluster), `ca01` échoue ; le message est dans l'`Order`.
- Supprimer le Secret de compte ACME : un nouveau compte est créé, sans conséquence avec step-ca (pas de limite), mais les journaux de `ca01` perdent la continuité.

**En production chez MédiSphère**
Métriques de cert-manager (`certmanager_certificate_expiration_timestamp_seconds`) et alerte à 7 jours de l'échéance (M21) ; ARI quand step-ca l'exposera ; journal d'audit des `CertificateRequest` (qui a demandé quoi : champ `spec.username` de la requête) pour Sophie.

---

### M15-E14 — Défis DNS-01 par RFC 2136 : la zone `apps`

**Solution**

Fichiers (Ansible) : [`ajouter-tsig.sh`](fichiers/M15-E14/ansible/outils/ajouter-tsig.sh), [`vault-lab.yml.exemple`](fichiers/M15-E14/ansible/inventories/lab/group_vars/role_dns/vault-lab.yml.exemple), [`defaults/main.yml.extrait`](fichiers/M15-E14/ansible/roles/powerdns_auth/defaults/main.yml.extrait), [`tasks/main.yml`](fichiers/M15-E14/ansible/roles/powerdns_auth/tasks/main.yml), [`tasks/dnsupdate.yml`](fichiers/M15-E14/ansible/roles/powerdns_auth/tasks/dnsupdate.yml), [`powerdns_auth.yml`](fichiers/M15-E14/ansible/inventories/lab/group_vars/role_dns/powerdns_auth.yml), [`dnssec.yml`](fichiers/M15-E14/ansible/inventories/lab/group_vars/role_dns/dnssec.yml), [`dnsupdate-k8s.yml`](fichiers/M15-E14/ansible/inventories/lab/group_vars/role_dns/dnsupdate-k8s.yml), [`pare_feu_local.yml`](fichiers/M15-E14/ansible/inventories/lab/host_vars/dns01/pare_feu_local.yml), [`pare_feu.yml.extrait`](fichiers/M15-E14/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [`dnsupdate.extrait.yml`](fichiers/M15-E14/ansible/molecule/powerdns_auth/dnsupdate.extrait.yml) (Molecule). OpenTofu : [`dns-apps.tf`](fichiers/M15-E14/infra/envs/k8s/dns-apps.tf), [`terraform.tfvars.extrait`](fichiers/M15-E14/infra/envs/k8s/terraform.tfvars.extrait). Kubernetes : [`secret-tsig.sh`](fichiers/M15-E14/k8s/outils/secret-tsig.sh), [`values.yaml`](fichiers/M15-E14/k8s/composants/cert-manager/values.yaml) et [`clusterissuer-step-ca-acme.yaml`](fichiers/M15-E14/k8s/composants/cert-manager/clusterissuer-step-ca-acme.yaml) (versions E14), [`certificat-apps-joker.yaml`](fichiers/M15-E14/k8s/composants/passerelles/certificat-apps-joker.yaml), [`nsupdate-essai.yaml`](fichiers/M15-E14/essais/nsupdate-essai.yaml). Registre : [`registre-secrets.extrait.md`](fichiers/M15-E14/medisphere/docs/socle/registre-secrets.extrait.md).

1. **Lecture.**
   - PowerDNS 5.0 vérifie : d'abord la signature TSIG si le message est signé (invalide : `REFUSED`) ; `dnsupdate=yes` (sinon `REFUSED`, **sans rien journaliser**) ; adresse autorisée par le réglage global `allow-dnsupdate-from` **ou** par la métadonnée `ALLOW-DNSUPDATE-FROM` de la zone (l'une **ou** l'autre) ; puis, si la zone a `TSIG-ALLOW-DNSUPDATE`, signature par l'une des clés listées. Tous ces refus répondent `REFUSED` (RFC 3007) : seul le journal de `pdns` dit lequel (« Remote not listed in allow-dnsupdate-from or domainmetadata », « TSIG key required, but packet does not contain key », « Received a TSIG signed message with a non-validating key »… dans `rfc2136handler.cc` et `packethandler.cc` au tag `auth-5.0.1`). Depuis 5.0, `dnsupdate-require-tsig=yes` refuserait en plus toute mise à jour non signée de toute zone (à proposer pour tout le serveur : Kea signe déjà les siennes).
   - Ce que peut la clé `certmanager-k8s` : **tout** dans la zone `apps` (ajouter, remplacer, supprimer n'importe quel enregistrement, y compris le A de `mediagenda-recette.apps…`), depuis le VLAN 40 ; **rien** ailleurs. Pour la limiter aux TXT `_acme-challenge`, il faudrait une politique Lua (*Pour aller plus loin*).
   - L'autocontrôle : par défaut cert-manager interroge les serveurs **faisant autorité** de la zone (les NS : `dns01`, `dns02`)… sur le port 53, qui est chez nous celui des **récurseurs**, avec leur cache négatif (300 s). On le dirige donc vers `10.10.20.10:5300`, et seulement lui (`dns01RecursiveNameserversOnly`). Prix : on ne vérifie plus que le secondaire a la valeur ; `NOTIFY-DNSUPDATE` la lui pousse, et `ca01` interroge les récurseurs (qui, eux, peuvent avoir mis en cache une réponse négative d'une tentative précédente : un nouvel essai immédiat après un échec peut échouer encore pendant 5 min).
2. **Secrets.** Depuis `~/src/ansible` : `outils/ajouter-tsig.sh certmanager-k8s` puis `outils/ajouter-tsig.sh externaldns-k8s` : 32 octets aléatoires (`openssl rand -base64 32`), directement vers `ansible-vault encrypt` par un tube ; registre des secrets : deux lignes ([extrait](fichiers/M15-E14/medisphere/docs/socle/registre-secrets.extrait.md)). Pourquoi Vault `lab` et non `critique` : la portée est limitée à `apps` et la clé doit de toute façon vivre aussi dans le cluster (décision à écrire dans l'ADR-0150).
3. **Rôle.** Nouvelles variables `powerdns_auth_cles_dnsupdate` et `powerdns_auth_zones_dnsupdate`, nouveau fichier [`dnsupdate.yml`](fichiers/M15-E14/ansible/roles/powerdns_auth/tasks/dnsupdate.yml) inclus **après** `replication.yml` (pour que la clé `axfr-par1` soit déjà autorisée à transférer la zone ; `tsigkey activate … primary` **ajoute** une clé à `TSIG-ALLOW-AXFR`). Chaque écriture est précédée d'une lecture ; `TSIG-ALLOW-DNSUPDATE` est réécrite par « `set` vide puis un `add` par clé » quand la liste diffère (la page 5.0 précise qu'on n'écrit pas les clés en une seule valeur séparée par des virgules) ; secrets en variable d'environnement, `no_log`. Le rôle ne touche **que** les zones listées : les métadonnées que `kea_ddns` pose sur `par1` et les inverses ne bougent pas. Scénario Molecule : zone d'essai, une mise à jour signée acceptée depuis la boucle locale, une non signée refusée, second passage sans changement.
4. **Inventaire et flux.** `powerdns_auth.yml` (zone `apps`, `contenu: api`), `dnssec.yml` (zone signée ; **pas** d'ancre nouvelle sur les récurseurs : `apps` est sous `par1`), `dnsupdate-k8s.yml`, flux bordure `$V_K8S`/`$NET_K8S` → `$DNS01` TCP/UDP 5300 et pare-feu local de `dns01` (règle 5300 depuis 10.10.40.0/24). Après le pipeline :
   ```
   admin@adm01:~$ for s in 10.10.20.10 10.10.20.16; do dig +noall +answer @$s -p 5300 apps.par1.medisphere.internal SOA; done
   apps.par1.medisphere.internal. 300 IN SOA dns01.par1.medisphere.internal. hostmaster.medisphere.internal. 2026100801 3600 900 1209600 300
   apps.par1.medisphere.internal. 300 IN SOA dns01.par1.medisphere.internal. hostmaster.medisphere.internal. 2026100801 3600 900 1209600 300
   admin@adm01:~$ dig +short @10.10.20.10 -p 5300 apps.par1.medisphere.internal NS
   admin@adm01:~$ dig +short @10.10.20.16 -p 5300 apps.par1.medisphere.internal DNSKEY
   admin@dns01:~$ sudo -u pdns pdnsutil metadata get apps.par1.medisphere.internal TSIG-ALLOW-DNSUPDATE ALLOW-DNSUPDATE-FROM NOTIFY-DNSUPDATE TSIG-ALLOW-AXFR
   TSIG-ALLOW-DNSUPDATE = certmanager-k8s, externaldns-k8s
   ALLOW-DNSUPDATE-FROM = 10.10.40.0/24
   NOTIFY-DNSUPDATE = 1
   TSIG-ALLOW-AXFR = axfr-par1, externaldns-k8s
   ```
   (Le numéro de série suit `INCEPTION-INCREMENT` : il change avec les signatures.)
5. **Délégation.** `sudo -u pdns pdnsutil zone export-ds apps.par1.medisphere.internal` → ligne `… IN DS <keytag> 13 2 <empreinte>` ; `ds_apps` dans `terraform.tfvars` ; `tofu plan` annonce deux `powerdns_record` (NS, DS) dans `par1.` ; `apply`. Vérification par un récurseur :
   ```
   admin@adm01:~$ dig @10.10.20.10 apps.par1.medisphere.internal SOA +dnssec | grep -E 'flags:|status'
   ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: …
   ;; flags: qr rd ra ad; QUERY: 1, ANSWER: 2, AUTHORITY: 0, ADDITIONAL: 1
   ```
   `ad` : la chaîne racine de confiance `par1` (ancre) → DS de `apps` dans `par1` → DNSKEY de `apps` est validée. Avec un DS faux : `status: SERVFAIL` sur tout `*.apps`.
6. **`nsupdate` à la main.** `outils/secret-tsig.sh certmanager-k8s wb-essais tsig-essai`, puis le pod d'essai : `update add` accepté, TXT visible sur `dns01` **et** `dns02` dans la seconde (NOTIFY), puis `update delete`. Depuis `adm01`, même envoi : `update failed: REFUSED` — l'adresse 10.10.10.10 n'est ni dans `allow-dnsupdate-from` (127.0.0.1, 10.10.20.16) ni dans `ALLOW-DNSUPDATE-FROM` de la zone, et (avant même PowerDNS) le pare-feu local de `dns01` laisse passer `adm01` sur 5300 (diagnostic, M06-E30), donc c'est bien PowerDNS qui refuse : `journalctl -u pdns` sur `dns01` le dit (« Remote not listed in allow-dnsupdate-from or domainmetadata. Sending REFUSED »). Suppression de `tsig-essai` et du pod.
7. **cert-manager.** `outils/secret-tsig.sh certmanager-k8s cert-manager tsig-certmanager-k8s` (Secret de l'espace de cert-manager : un `ClusterIssuer` lit ses Secrets dans le *cluster resource namespace*). Second solveur avec `selector.dnsZones: [apps.par1.medisphere.internal]` et `dns01.rfc2136` (`nameserver: 10.10.20.10:5300`, `tsigKeyName`, `tsigAlgorithm: HMACSHA256`, `tsigSecretSecretRef`) ; values : `dns01RecursiveNameservers: "10.10.20.10:5300"` et `dns01RecursiveNameserversOnly: true`, puis `helm upgrade` (mêmes options qu'en E13).
8. **Joker.** `Certificate` `apps-joker` (Secret du même nom : cert-manager **reprend** le Secret créé à la main en E12 et le réécrit). Pendant l'émission :
   ```
   admin@adm01:~$ watch -n2 "dig +short @10.10.20.10 -p 5300 _acme-challenge.apps.par1.medisphere.internal TXT"
   "q2V…"                                   # présent pendant quelques secondes
   admin@adm01:~$ kubectl -n passerelles describe challenge | grep -E 'Type|State|Reason'
   admin@adm01:~$ openssl s_client -connect 10.10.41.10:443 -servername mediagenda-recette.apps.par1.medisphere.internal </dev/null 2>/dev/null | openssl x509 -noout -dates
   ```
   Le nom du défi d'un joker est `_acme-challenge.apps.par1.medisphere.internal` (le `*.` est retiré) : il est **dans** la zone `apps` (juste sous son sommet). La Gateway sert le nouveau certificat sans redémarrage : le contrôleur de Cilium surveille le Secret et pousse la nouvelle configuration à l'Envoy (SDS). ⚠️ À vérifier sur ton lab : délai entre la réécriture du Secret et le nouveau certificat servi (quelques secondes attendues).

**Explications**

RFC 2136 est le protocole de mise à jour du DNS lui-même : pas d'API HTTP, pas de clé d'API capable de tout, une autorisation **par zone** (adresse + clé TSIG). C'est ce qui permet de donner au cluster un droit d'écriture borné à `apps`, ce que la clé d'API de PowerDNS (M06-E14) ne sait pas faire. La zone est déléguée proprement (NS et DS dans `par1`) pour que la validation DNSSEC des récurseurs reste vraie de bout en bout ; elle est signée à la volée par le primaire, y compris après chaque mise à jour, et transférée signée au secondaire.

**Alternatives**
- *Fournisseur `pdns` (API HTTP)* d'ExternalDNS et un *webhook* PowerDNS pour cert-manager : clé d'API qui peut réécrire **toutes** les zones ; refusé (ticket).
- *Délégation de `_acme-challenge` par CNAME* vers une zone de défis séparée (`acme-dns`) : la zone applicative n'est plus modifiable par cert-manager du tout ; plus sûr, plus de pièces.
- *Clé unique* pour cert-manager et ExternalDNS : moins de secrets, mais une compromission d'ExternalDNS permettrait d'émettre des certificats ; deux clés, deux rotations indépendantes.
- *Zone non signée* : plus simple, mais la zone `par1` est signée et ses enfants doivent être soit signés (DS), soit prouvés non signés : autant signer.

**Pièges classiques**
- Envoyer les mises à jour au port 53 (récurseur) : `NOTIMP` ou `REFUSED`, et on cherche la faute dans TSIG.
- `metadata set … TSIG-ALLOW-DNSUPDATE "a,b"` : une seule valeur « a,b », aucune clé valide.
- DS copié avec le mauvais type de condensé (1 = SHA-1) ou d'une clé en cours de roulement.
- Oublier le pare-feu **local** de `dns01` (le pare-feu de la bordure ne suffit pas).
- Secret TSIG encodé deux fois en base64 dans le Secret Kubernetes (la documentation de cert-manager le signale) : `stringData` évite le piège.
- Le Secret d'un `ClusterIssuer` dans l'espace du `Certificate` au lieu de `cert-manager`.

**En production chez MédiSphère**
Politique Lua limitant `certmanager-k8s` aux TXT `_acme-challenge.*` ; `dnsupdate-require-tsig=yes` sur tout l'autoritaire ; rotation annuelle des deux clés (procédure : `ajouter-tsig.sh`, pipeline, `secret-tsig.sh`, redémarrage d'ExternalDNS) ; supervision du numéro de série de `apps` sur `dns01` et `dns02` (écart = NOTIFY ou AXFR cassé) ; la clé d'un roulement DNSSEC de `apps` suit RB-064 (DS à changer dans `dns-apps.tf`).

---

### M15-E15 — ExternalDNS : publier les noms automatiquement

**Solution**

Fichiers : [`external-dns.yaml`](fichiers/M15-E15/k8s/espaces/external-dns.yaml) (et, sur le même modèle, [`cert-manager.yaml`](fichiers/M15-E13/k8s/espaces/cert-manager.yaml) d'E13), [`values.yaml`](fichiers/M15-E15/k8s/composants/external-dns/values.yaml), [`redirection-https.yaml`](fichiers/M15-E15/k8s/composants/passerelles/redirection-https.yaml) (version E15), [`route-essai-dns.yaml`](fichiers/M15-E15/essais/route-essai-dns.yaml), [`essai-lb-nom.extrait.yaml`](fichiers/M15-E15/essais/essai-lb-nom.extrait.yaml), [`garde-fous.yaml`](fichiers/M15-E15/essais/garde-fous.yaml), [`entree-du-cluster.md`](fichiers/M15-E15/medisphere/docs/kubernetes/reseau/entree-du-cluster.md).

1. **Lecture.** La boucle d'ExternalDNS : lire les **sources** (routes, Services) → calculer les enregistrements voulus → lire ce que le **fournisseur** contient → ne garder que ce que le **registre** dit lui appartenir → appliquer la différence. Avec `rfc2136`, la seule façon de lire la zone est l'AXFR : sans `--rfc2136-axfr`, ExternalDNS ne voit rien et se comporte en `create-only` (il ne supprime jamais). Le registre TXT écrit, à côté de chaque nom, un TXT `heritage=external-dns,external-dns/owner=k8s-par1,…` : c'est la preuve de propriété ; ExternalDNS ne touche jamais un nom dont le TXT n'a pas son propriétaire. Deux clusters avec le **même** propriétaire dans la même zone se croient chacun maître des noms de l'autre : chacun supprime ce que l'autre a créé (politique `sync`), en boucle.
2. **Installation.** Espace, Secret (`outils/secret-tsig.sh externaldns-k8s external-dns tsig-externaldns-k8s`), values, `helm upgrade --install … --version 1.23.0`. Le secret passe par `EXTERNAL_DNS_RFC2136_TSIG_SECRET` (ExternalDNS lit chaque drapeau aussi en variable `EXTERNAL_DNS_<DRAPEAU>`, méthode du tutoriel) : il n'apparaît ni dans les arguments du pod ni dans `ps`. Journal (JSON) :
   ```
   admin@adm01:~$ kubectl -n external-dns logs deploy/external-dns | jq -r .msg | head
   ```
   On y lit la configuration, l'AXFR de `apps.par1.medisphere.internal.`, puis les ajouts (`Adding RR: mediagenda-recette.apps… A 10.10.41.10` et son TXT). ⚠️ À vérifier sur ton lab : les libellés exacts des messages selon la version.
3. **Exclusion.** Sans elle, `redirection-https` (nom `*.apps…`, écouteur `http`) fait publier un **joker** `*.apps.par1.medisphere.internal A 10.10.41.10` : tout nom résout, ExternalDNS ne sert plus à rien et une faute de frappe d'un utilisateur arrive sur la Gateway (404 au lieu de NXDOMAIN). Étiquette `medisphere.internal/dns: non` sur la route + `labelFilter: "medisphere.internal/dns!=non"` (un sélecteur `!=` retient aussi les objets **sans** l'étiquette). Contrôles : `dig +short mediagenda-recette.apps.par1.medisphere.internal` → 10.10.41.10 ; `dig inexistant.apps.par1.medisphere.internal` → `status: NXDOMAIN`. Si le joker a déjà été publié, ExternalDNS (propriétaire) le **supprime** de lui-même au cycle suivant.
4. **Cycle de vie.** Route `essai-dns` : nom publié en moins d'une minute (`triggerLoopOnEvent: true` réagit à l'événement ; sinon `interval: 1m`), joignable en HTTPS sans `--resolve` (joker TLS + nom DNS) ; route supprimée : A et TXT supprimés au cycle suivant. Côté client, un nom supprimé peut encore résoudre jusqu'au TTL (60 s, `--rfc2136-min-ttl`) et un nom nouveau rester introuvable jusqu'au TTL négatif du SOA (300 s) si quelqu'un l'a demandé avant sa création : c'est le délai à annoncer aux équipes.
5. **Service.** Annotation `external-dns.kubernetes.io/hostname: essai-lb.apps.par1.medisphere.internal` sur `essai-lb` : A vers **son** adresse (10.10.41.20), pas celle de la Gateway. Un Service sans annotation n'est pas publié (pas de `--fqdn-template`), y compris `cilium-gateway-gw-par1`.
6. **Garde-fous.** (a) Nom hors zone : la route n'est même pas acceptée sur l'écouteur `https` (nom hors `*.apps`) ; attachée à l'écouteur `http` (sans nom), elle l'est, mais `--domain-filter` l'écarte : rien n'est écrit, et de toute façon la clé n'a aucun droit sur `par1`. (b) Route sur `gw-essai` : ignorée (`--gateway-name=gw-par1`, `--gateway-namespace=passerelles`) : une Gateway d'essai ne publie pas de nom de production.
7. **TXT de propriété.**
   ```
   admin@k8s-w01:~$ dig +noall +answer @10.10.20.10 -p 5300 a-mediagenda-recette.apps.par1.medisphere.internal TXT
   a-mediagenda-recette.apps.par1.medisphere.internal. 60 IN TXT "heritage=external-dns,external-dns/owner=k8s-par1,external-dns/resource=httproute/mediagenda-recette/mediagenda"
   ```
   Le préfixe `a-` (type d'enregistrement) est le format du registre TXT des versions récentes ; selon la version, un second TXT sans préfixe peut coexister (ancien format). La ressource d'origine est notée : on sait **quel objet** a créé le nom. ⚠️ À vérifier sur ton lab : format exact en 0.23. (L'AXFR complet se fait depuis un nœud ou un pod, avec la clé, depuis le VLAN 40 : `dig … AXFR -k <fichier>`.)
8. **Documentation** : [`entree-du-cluster.md`](fichiers/M15-E15/medisphere/docs/kubernetes/reseau/entree-du-cluster.md).

**Explications**

ExternalDNS fait du DNS un **état dérivé** des objets du cluster, comme cert-manager pour les certificats. Les trois verrous de ce déploiement se complètent : la clé TSIG ne vaut que pour `apps` (PowerDNS), le filtre de domaine et la Gateway visée bornent ce qu'ExternalDNS **veut** écrire, le registre TXT borne ce qu'il **ose** supprimer. Le joker TLS couvre tous les noms : publier un nom ne demande donc aucune émission de certificat, seulement une route acceptée.

**Alternatives**
- *Enregistrement joker DNS* (`*.apps → 10.10.41.10`) écrit une fois pour toutes, sans ExternalDNS : zéro pièce mobile, mais tout nom résout (fautes de frappe, noms abandonnés) et aucune trace de qui utilise quoi.
- *Registre `crd`* (`DNSEndpoint`) : pas de TXT dans la zone, mais l'état de propriété vit dans le cluster (perdu avec lui).
- *Fournisseur `pdns`* (API) : refusé en E14 (portée de la clé).

**Pièges classiques**
- Oublier `--rfc2136-axfr` : les noms s'ajoutent, ne se suppriment jamais.
- Secret en argument (`--rfc2136-tsig-secret=…`) : lisible par quiconque lit les pods de l'espace.
- Annotations en `external-dns.alpha.kubernetes.io/…` (anciens tutoriels) : ignorées en 0.23 sans `--enable-legacy-annotation-prefix`.
- Propriétaire identique sur deux clusters (ou entre un essai et la production).
- Chercher le nom sur les récurseurs juste après la création et conclure à une panne (cache négatif).

**En production chez MédiSphère**
Métriques d'ExternalDNS (`external_dns_registry_errors_total`, `…_source_errors_total`) et alerte au M21 ; une instance par cluster, propriétaire = nom du cluster ; procédure de reprise : si la zone est restaurée d'une sauvegarde, ExternalDNS recrée ce qui manque au premier cycle (c'est un avantage de la politique `sync`).

---

### M15-E16 — Routage avancé : poids, en-têtes, réécritures, gRPC et TLS

**Solution**

Fichiers : [`charges.yaml`](fichiers/M15-E16/charges.yaml), [`httproute-essai-avance.yaml`](fichiers/M15-E16/httproute-essai-avance.yaml), [`mesure.sh`](fichiers/M15-E16/mesure.sh), [`grpc.yaml`](fichiers/M15-E16/grpc.yaml), [`tls.yaml`](fichiers/M15-E16/tls.yaml), [`croise.yaml`](fichiers/M15-E16/croise.yaml).

1. **Priorité des règles** (spécification `HTTPRoute`, *Matching precedence*, recopiée en tête du fichier de route) : chemin `Exact`, puis `PathPrefix` le plus long ; puis méthode ; puis le plus d'en-têtes ; puis le plus de paramètres de requête ; puis la route la plus ancienne, puis l'ordre alphabétique `espace/nom` ; enfin l'ordre des règles. L'ordre d'écriture n'est qu'un dernier recours.
2. **Route.** Quatre règles nommées (`name`, standard en v1.6) : `canari-force` (`/` + en-tête `X-Canari: oui` → v2), `prefixe-v2` (`/v2` réécrit en `/` → v2), `anciennes-adresses` (`/ancien` → 301 vers `/…`, sans `backendRefs`), `defaut-canari-10` (`/` → 90/10). Le filtre `RequestHeaderModifier` est **par règle** : il est répété (sauf sur la redirection, qui ne transmet rien). `set` plutôt que `add` : un client ne peut pas imposer sa propre valeur (essai : `-H 'X-Medisphere-Env: prod'` renvoie toujours `essai`).
3. **Mesure** (`mesure.sh`) : par exemple `182 agnhost-v1`, `18 agnhost-v2` sur 200 ; 20/20 v2 avec l'en-tête ; `/v2/hostname` → un pod v2 ; `/ancien/hostname` → `301 https://essai.apps…/hostname` ; en-tête `essai`. L'écart à 90/10 est normal : la répartition est **statistique** (tirage pondéré par requête dans l'Envoy, et la boucle `curl` ouvre une connexion par requête) ; sur 200 tirages, l'écart type est d'environ 4 requêtes.
4. **gRPC.** `GRPCRoute` `essai-grpc` (correspondance exacte `grpc.health.v1.Health/Check`) vers le Service `agnhost-grpc` (`appProtocol: kubernetes.io/h2c` : HTTP/2 en clair entre l'Envoy et le pod). Depuis `adm01` :
   ```
   admin@adm01:~$ P=~/DevOpsPrivateCloud/modules/15-kubernetes-reseau/ressources
   admin@adm01:~$ grpcurl -import-path "$P" -proto E16-health.proto \
       -servername grpc-essai.apps.par1.medisphere.internal -authority grpc-essai.apps.par1.medisphere.internal \
       -d '{}' 10.10.41.10:443 grpc.health.v1.Health/Check
   {
     "status": "SERVING"
   }
   ```
   ALPN négocié : `h2` (`openssl s_client -alpn h2 …` le montre) ; sans `h2`, pas de gRPC. `Watch` (non déclaré dans la route) reçoit `UNIMPLEMENTED`/404 de l'Envoy : la route filtre au niveau de la méthode.
5. **TLS de bout en bout.** `kubectl get crd tlsroutes.gateway.networking.k8s.io -o jsonpath='{.spec.versions[*].name}'` → `v1 v1alpha2 v1alpha3` avec seule `v1` servie (canal standard v1.6.1) : aucune ancienne `TLSRoute` n'existait. `Certificate` `tls-essai` (DNS-01, nom dans `apps`), backend `agnhost netexec` en HTTPS sur 8443 avec ce certificat, `gw-essai-tls` (10.10.41.21, écouteur `TLS`, `Passthrough`), `TLSRoute` v1 `essai-tls`.
   ```
   admin@adm01:~$ openssl s_client -connect 10.10.41.21:443 -servername tls-essai.apps.par1.medisphere.internal </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer
   subject=CN=tls-essai.apps.par1.medisphere.internal
   issuer=… MédiSphère Intermediate CA
   ```
   Le sujet est celui du backend, pas `*.apps…` : l'Envoy n'a fait que lire le SNI et relayer le flux. Le backend voit l'adresse de l'**Envoy** (nouvelle connexion TCP), pas celle du client (page *Reference* : *TLS Passthrough and source IP visibility*). cert-manager ne gère pas un écouteur `Passthrough` (il n'y a pas de certificat côté Gateway : c'est le backend qui le porte, ici par son propre `Certificate`). Gateway dédiée : un écouteur `TLS` `Passthrough` et un écouteur `HTTPS` sur le même port d'une même Gateway sont permis par la spécification, mais ce montage n'est pas décrit par la documentation de Cilium 1.20 ; on ne l'essaie pas sur l'entrée de production. ⚠️ À vérifier sur ton lab si tu veux l'essayer sur une Gateway d'essai.
6. **Référence croisée.** Sans `ReferenceGrant` : `ResolvedRefs=False`, `reason: RefNotPermitted`, et la Gateway répond 500 pour ce nom. Avec le `ReferenceGrant` **dans `wb-essais-2`** (espace de la cible), `from` = `HTTPRoute` de `wb-essais`, `to` = `Service` nommé `agnhost-v3` : `ResolvedRefs=True`. Un `to` sans `name` ouvrirait **tous** les Services de l'espace.
7. **Nettoyage** : `kubectl delete ns wb-essais-2`, `kubectl -n wb-essais delete -f tls.yaml` (libère 10.10.41.21 et retire l'annonce BGP).

**Explications**

Ces fonctions, qui étaient des annotations propres à chaque contrôleur Ingress, sont des **champs** de la Gateway API : portables, validés à l'admission, lisibles dans `status`. Le canari par poids et par en-tête suffit pour un déploiement progressif manuel ; Argo Rollouts (M20) manipulera ces mêmes poids automatiquement à partir de métriques.

**Alternatives**
- *Canari par deux routes* (une par version) : impossible de répartir ; les poids doivent être dans une même règle.
- *TLS terminé à la Gateway puis ré-chiffré* vers le backend (`BackendTLSPolicy`, standard en v1.6) : la Gateway voit le HTTP (routes, en-têtes, journaux) et le backend garde du TLS ; discuté en E33.
- *gRPC sur `HTTPRoute`* : possible (c'est du HTTP/2), mais sans correspondance par service/méthode.

**Pièges classiques**
- `ReplacePrefixMatch` sans correspondance `PathPrefix` sur la règle (refusé à l'admission).
- Préfixe `/v2/` au lieu de `/v2` : les préfixes Gateway API se comparent **par segment**, `/v2/` est accepté mais `/v2` seul ne correspond plus.
- `ReferenceGrant` créé dans l'espace de la **source**.
- Ancienne `TLSRoute` `v1alpha2` dans un cluster mis à jour : l'installer de la CRD standard v1.6 la rend illisible (notes de mise à jour de Cilium 1.20) — sauvegarder d'abord.
- Oublier que `grpcurl` a besoin de la définition du service quand le serveur n'expose pas la réflexion.

**En production chez MédiSphère**
Aucun canari « à la main » en production : Argo Rollouts (M20) ; les en-têtes de forçage (`X-Canari`) sont filtrés à l'entrée (`RequestHeaderModifier` `remove`) pour les clients extérieurs ; le TLS de bout en bout est réservé aux cas où le client l'exige et documenté dans l'ADR-0150 (perte de visibilité de l'entrée).

---

### M15-E17 — Les politiques réseau de MédiAgenda

**Exemple de solution**

Fichiers : [`politiques-mediagenda/`](fichiers/M15-E17/k8s/espaces/politiques-mediagenda/) (README, refus par défaut, DNS, API ↔ données, entrée de l'API en CNP L7), [`flux-mediagenda.md`](fichiers/M15-E17/medisphere/docs/kubernetes/reseau/flux-mediagenda.md), [`essais-politiques.sh`](fichiers/M15-E17/essais/essais-politiques.sh).

1. **Matrice.** Sept flux autorisés (DNS, Gateway → API en L7, kubelet → API, API → PostgreSQL, API → Valkey, tâches du M14 → PostgreSQL, réplication de Valkey) et la liste de ce qui est refusé explicitement. Les deux derniers s'oublient facilement : ils ne se voient pas pendant un parcours de l'API, seulement à la prochaine migration (le Job reste bloqué) ou dans `valkey-cli info replication` (`master_link_status:down`) ; Hubble les montre en `DROPPED` si on regarde au bon moment. Les manifestes n'ont **pas** de champ `namespace` : `kubectl apply -n <espace> -f espaces/politiques-mediagenda/` pour chacun des deux espaces (Kustomize fera cela proprement au M17).
2. **Politiques.**
   - `refus-par-defaut` : `podSelector: {}`, `policyTypes: [Ingress, Egress]`, aucune règle.
   - `sortie-dns` : vers les pods `k8s-app=kube-dns` de `kube-system` (sélecteur d'espace **et** de pod dans le **même** élément `to` : un ET ; deux éléments feraient un OU), UDP et TCP 53.
   - `api-vers-donnees`, `taches-vers-postgresql` et `postgresql-depuis-api`/`valkey-depuis-api` : l'autorisation est écrite **des deux côtés** (sortie du client, entrée de la base), sinon le refus par défaut de l'autre côté l'emporte. `valkey-replication` ouvre 6379 entre les seuls pods Valkey, dans les deux sens.
   - `api-entree` (CiliumNetworkPolicy) : `fromEntities: [ingress]` sur 8000 avec la liste des méthodes et chemins ; `fromEntities: [host]` sur 8000 limité aux sondes. Les chemins sont des expressions régulières comparées au chemin entier : `(\?.*)?` laisse passer la chaîne de requête de `/api/v1/creneaux?date=…`. ⚠️ À vérifier sur ton lab : si `/api/v1/creneaux?date=2026-10-08` reçoit 403, ta version compare le chemin **sans** la chaîne de requête et l'ajout est inutile (sans effet néfaste).
3. **Preuves** (`essais-politiques.sh`) : `/sante`, `/pret`, liste, créneaux → 200 ; `/metrics`, `PUT /api/v1/rendez-vous/1`, `/docs` (documentation OpenAPI de FastAPI, publiée par défaut !) → **403** `Access denied` du proxy ; le pod latéral de `wb-essais` n'ouvre pas 5432 (`connect` expire) ; Hubble :
   ```
   admin@adm01:~$ hubble observe -n mediagenda-recette --verdict DROPPED --since 5m -o compact
   wb-essais/essai-lateral:41234 (ID:…) <> mediagenda-recette/postgresql-…:5432 (ID:…) policy-verdict:none INGRESS DENIED (TCP Flags: SYN)
   … Policy denied DROPPED (TCP Flags: SYN)
   admin@adm01:~$ hubble observe -n mediagenda-recette --protocol http --since 5m -o compact | grep 403
   ingress:… -> mediagenda-recette/mediagenda-api-…:8000 http-request DROPPED (HTTP/1.1 GET https://…/metrics)
   ```
   (Sorties abrégées : leur forme exacte varie selon la version de Hubble.) Pendant un parcours complet de l'API, aucune autre chute : les sondes passent (identité `host`), le DNS passe.
4. **MR** : description avec la liste des essais et de leurs résultats (copie de la sortie du script).

**Explications**

Le refus par défaut transforme chaque flux en **décision écrite**. Les deux mondes se complètent : `NetworkPolicy` standard pour le L3/L4 entre pods (portable, connu de tous), `CiliumNetworkPolicy` pour ce que le standard ne sait pas dire : les identités réservées (`ingress`, `host`, `world`, `kube-apiserver`), le L7 (HTTP, DNS) et les noms (`toFQDNs`). Les politiques s'additionnent (union des autorisations) ; aucune ne peut retirer ce qu'une autre accorde (sauf les règles `Deny` de Cilium, à manier avec prudence). Avec le remplacement de kube-proxy, la traduction Service → pod a lieu **avant** la politique de sortie : on écrit les politiques sur les pods, jamais sur l'adresse d'un Service.

**Alternatives**
- *Tout en CiliumNetworkPolicy* : un seul langage, mais les équipes qui connaissent le standard (et les outils de revue) le perdent ; le standard reste le défaut, Cilium seulement pour ce qu'il apporte.
- *Politique d'espace par AdminNetworkPolicy* (API `policy.networking.k8s.io`, en évolution) : la plateforme pourrait imposer le refus par défaut à tous les espaces ; à suivre (CCNP de base en E28).
- *Laisser `/metrics` publique et filtrer au M21* : non, le ticket dit « pas publique ».

**Pièges classiques**
- Oublier TCP 53 (réponses tronquées, DNSSEC) ou viser l'adresse du Service `kube-dns`.
- Mettre `namespaceSelector` et `podSelector` dans **deux** éléments (`- namespaceSelector…` puis `- podSelector…`) : c'est un OU, qui ouvre CoreDNS **et** tous les pods de l'espace courant.
- Écrire l'autorisation API → base d'un seul côté.
- Penser que la Gateway est « le monde » (`world`) : c'est l'identité `ingress` ; et `world` n'atteint de toute façon pas les pods directement (tunnel).
- Une règle L7 sans la liste complète : tout ce qui manque reçoit 403, y compris les sondes si elles passent par la même règle.

**En production chez MédiSphère**
Ces politiques deviennent un modèle commun (chart MédiAgenda au M17, politique de plateforme au M26 qui refuse un espace sans refus par défaut) ; Hubble UI (E26) et les métriques `hubble_drop_total` (M21) remplacent la lecture à la main ; revue de la matrice des flux à chaque nouvelle dépendance (critère de MR).

---

### M15-E18 — Migrer les Ingress d'InfoGér vers la Gateway API

**Solution**

Fichiers : [`sortie-brute.yaml`](fichiers/M15-E18/sortie-brute.yaml) et [`avertissements.txt`](fichiers/M15-E18/avertissements.txt) (sortie **réelle** d'ingress2gateway 1.2.0 sur les fichiers fournis), [`migration.md`](fichiers/M15-E18/migration.md) (tableau des 32 annotations et conclusion), [`routes-migrees.yaml`](fichiers/M15-E18/routes-migrees.yaml), [`essais-comportement.sh`](fichiers/M15-E18/essais-comportement.sh).

1. **Installation.** Page des publications du projet `kubernetes-sigs/ingress2gateway`, version 1.2.0 (7 juillet 2026), archive Linux amd64 et fichier de sommes de contrôle ; `sha256sum -c`, binaire dans `~/.local/bin`. (Alternative : `go install github.com/kubernetes-sigs/ingress2gateway@v1.2.0` — attention, le chemin de module est `github.com/…` et non `sigs.k8s.io/…`, et il faut Go 1.25.5 ou plus récent. C'est ainsi que la sortie de ce corrigé a été produite.)
2. **Tableau** : voir [`migration.md`](fichiers/M15-E18/migration.md). Points saillants : `rewrite-target` à groupe de capture, `limit-rps`, les trois `auth-*` d'`admin`, `whitelist-source-range`, les deux *snippets*, l'affinité par cookie et le SSO de `dossier`.
3. **Conversion.** 432 lignes, 5 Gateways (une par espace, classe `nginx`), 8 `HTTPRoute`, 1 `GRPCRoute`, 1 `TLSRoute`, 22 avertissements. Fidèle : redirections, `app-root`, canari (poids 80/20 et en-tête, fusionnés dans la même route), gRPC, *passthrough*, CORS (filtre `CORS`, standard en v1.6). De travers : délais (`proxy-read-timeout` 60 → `timeouts.request: 10m0s`), expressions régulières doublées et élargies (`(?i)(?i)/rdv(/|$)(.*).*.*`). Refusé avec avertissement : 14 annotations. **En silence** : le délai de 3 600 s des flux gRPC (l'outil prévient seulement que le gRPC « n'est pas entièrement implémenté »). Note aussi l'avertissement « certificat auto-signé » pour `www.portail…` et `dossier…` : ingress-nginx servait ces noms en HTTPS avec son certificat par défaut, ce que l'outil ne reproduit pas.
4. **Adaptation** : tout s'accroche à `gw-par1` (`sectionName: https`), noms `<application>-infoger.apps…`, pas de certificat ni de redirection HTTP par application (le joker et `redirection-https` les fournissent), préfixes au lieu d'expressions régulières.
5. **Essais** (`essais-comportement.sh`, dans `wb-essais` avec les charges d'E16) : `portail` `/` → 302 `/accueil` ; ancien nom → 308 vers l'URL **fixe** `https://portail-infoger.apps…/accueil` (chemin perdu, comme nginx ; un `RequestRedirect` avec seulement `hostname` garderait le chemin : comportement différent, à proposer aux équipes) ; `api-rdv` `/rdv/hostname` → 200, ≈ 80/20, 100 % v2 avec `X-Version-Rdv: v2` ; `/RDV/hostname` → 404 (nginx : 200 car comparaison sans casse) ; `notif` → `SERVING` (par l'adresse : pas de source `gateway-grpcroute` dans ExternalDNS, à ajouter si l'application est migrée).
6. **Conclusion** : en tête de [`migration.md`](fichiers/M15-E18/migration.md).

**Explications**

Une migration Ingress → Gateway API se fait **annotation par annotation** : l'outil fait le gros du travail mécanique (et le fait bien sur les fonctions devenues standard), mais il ne peut pas inventer ce que la Gateway API n'a pas (authentification, limites de débit, extraits de configuration). Ces annotations sont précisément celles qui ont fait d'ingress-nginx un risque (exécution de configuration fournie par les utilisateurs : CVE-2025-1974, « IngressNightmare ») : leur absence est une **décision** à prendre, pas une lacune à combler.

**Alternatives**
- *Garder ingress-nginx 1.15.1 « le temps de migrer »* : plus aucun correctif de sécurité depuis mars 2026 ; refusé (ticket).
- *Autre contrôleur Ingress* (le contrôleur Ingress de Cilium existe) : migre les objets sans migrer les annotations nginx ; ne fait que déplacer le problème.
- *Émetteurs spécialisés d'ingress2gateway* (`envoy-gateway`, `kgateway`…) : traduisent davantage (limites de débit, authentification) vers les CRD de **leur** projet ; pas de cible Cilium.

**Pièges classiques**
- Appliquer la sortie telle quelle : cinq Gateways de classe `nginx`, aucune n'existe.
- Croire qu'un `timeouts.request` reproduit `proxy-read-timeout` (délai total contre délai entre lectures).
- Oublier la sensibilité à la casse des préfixes.
- Rater l'Ingress `admin` parce qu'il choisit sa classe par l'**annotation** obsolète `kubernetes.io/ingress.class` (ici l'outil l'a prise en compte ; d'autres outils non).
- Promettre la migration de `dossier` sans voir que *passthrough* + cookie + SSO est impossible.

**En production chez MédiSphère**
Un tableau de migration par équipe, une date par application, et une règle : aucune application ne migre avec une fonction « perdue » non validée par son propriétaire. ingress-nginx peut être essayé sur `m15-essai` pour comparer un comportement précis (facultatif, VM détruite en fin de module) ; jamais sur `k8s-par1`.

---

### M15-E19 — MetalLB en comparaison

**Solution**

Fichiers : [`envs/m15-essai/`](fichiers/M15-E19/infra/envs/m15-essai/) (`versions.tf`, `providers.tf`, `variables.tf`, `main.tf`), [`m15-essai.yml`](fichiers/M15-E19/ansible/playbooks/m15-essai.yml), [`kubeadm-init.sh`](fichiers/M15-E19/kubeadm-init.sh), [`cilium-essai.sh`](fichiers/M15-E19/cilium-essai.sh), [`essai-l2.yaml`](fichiers/M15-E19/metallb/essai-l2.yaml), [`essai-service.yaml`](fichiers/M15-E19/metallb/essai-service.yaml).

1. **Lecture.** En L2, un **seul** nœud (l'annonceur, élu par le *memberlist* des speakers) répond aux requêtes ARP pour l'adresse : tout le trafic de ce Service entre par lui (pas de répartition entre nœuds à l'entrée), et la bascule après sa perte dépend de la détection par les speakers (quelques secondes) et du rafraîchissement des caches ARP des voisins (ARP gratuit envoyé par le nouvel annonceur). En BGP, chaque nœud annonce l'adresse (ECMP), comme Cilium en E11. 0.16 : le backend BGP par défaut devient **FRR-K8s** (le mode FRR est déprécié, le mode natif reste) ; les métriques passent en HTTPS seulement (fin de kube-rbac-proxy) ; les annonces gagnent un `serviceSelector` ; `BGPPeer` est en `v1beta2`.
2. **VM et cluster.**
   ```
   admin@adm01:~/src/infra/envs/m15-essai$ tofu init && tofu apply
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/m15-essai.yml
   admin@adm01:~$ ssh m15-essai 'sudo VERSION=v1.36.<PATCH> bash -s' < ~/m15/e19/kubeadm-init.sh
   admin@adm01:~$ ssh m15-essai sudo cat /etc/kubernetes/admin.conf > ~/.kube/m15-essai.conf && chmod 600 ~/.kube/m15-essai.conf
   admin@adm01:~$ KUBECONFIG=~/.kube/m15-essai.conf ~/m15/e19/cilium-essai.sh
   admin@adm01:~$ KUBECONFIG=~/.kube/m15-essai.conf kubectl get nodes
   NAME        STATUS   ROLES           AGE   VERSION
   m15-essai   Ready    control-plane   6m    v1.36.…
   ```
   ⚠️ Le pool d'adresses de pods par défaut de Cilium (`10.0.0.0/8`) **recouvre le lab** : sans `clusterPoolIPv4PodCIDRList=10.244.0.0/16`, les pods ne joignent plus `dns01` ni le cache Harbor. (Le kubeconfig `admin.conf` d'un essai jetable sur `adm01` est acceptable ; il disparaît avec la VM.)
3. **MetalLB.** `helm upgrade --install metallb metallb/metallb --version 0.16.1 …`. Le speaker utilise le réseau de l'hôte et des capacités réseau (`NET_RAW` pour l'ARP) : l'espace doit être en PSA `privileged` (la documentation d'installation le demande ; le chart ne le pose pas sur un espace créé par `--create-namespace`) ; ici le cluster d'essai n'applique pas de niveau PSA par défaut, mais sur `k8s-par1` (`baseline` hors `mediagenda-*`), il faudrait l'étiquette `pod-security.kubernetes.io/enforce: privileged` : un espace privilégié de plus, argument contre MetalLB.
4. **L2.** `essai-l2` reçoit 10.10.99.230 ; `curl http://10.10.99.230/hostname` depuis `adm01` répond ; `ip neigh show 10.10.99.230` sur la passerelle maître → l'adresse MAC de `m15-essai` (`bc:24:11:…`) ; `kubectl describe svc essai-l2` → événement `nodeAssigned … announcing from node "m15-essai" with protocol "layer2"`.
5. **Adresse demandée** : `metallb.io/loadBalancerIPs: 10.10.99.235` (préfixe `metallb.io/` ; `metallb.universe.tf/` est déprécié) ; hors pool : `AllocationFailed` dans les événements du Service (pas de condition dans `status`, contrairement à LB IPAM).
6. **Comparaison** (`~/m15/e19/comparaison.md`, exemple) :

   | Critère | MetalLB L2 | MetalLB BGP (FRR-K8s) | Cilium LB IPAM + BGP | Cilium L2 announcements |
   |---|---|---|---|---|
   | Attribution | `IPAddressPool` | idem | `CiliumLoadBalancerIPPool` | idem |
   | Annonce | ARP depuis un nœud | BGP depuis chaque nœud | BGP depuis chaque nœud (`CiliumBGP*`) | ARP depuis un nœud (bail Kubernetes) |
   | Bascule | détection memberlist + ARP gratuit : quelques s | durée de maintien BGP (BFD possible) | durée de maintien BGP (3/9 s ici) | expiration du bail (paramétrable) |
   | ECMP / répartition à l'entrée | non | oui | oui | non |
   | Adresses hors réseau des nœuds | non | oui | oui | non |
   | Chemin de données | celui du CNI / kube-proxy | idem | eBPF de Cilium (même agent) | idem |
   | Composants à maintenir | contrôleur + speakers | + FRR-K8s | aucun de plus | aucun de plus |
   | Privilèges | espace `privileged` | idem | agent Cilium (déjà là) | idem |
   | Observabilité | métriques HTTPS, événements | + FRR | `status` des CRD, `cilium bgp`, Hubble | `status` |
   | Maturité | très répandu, stable | backend récent (FRR-K8s) | stable (BGP v2) | beta (`v2alpha1`) |

   Conclusion : sur `k8s-par1`, Cilium fait déjà le chemin de données, l'attribution et l'annonce BGP ; MetalLB ajouterait un composant privilégié pour une fonction déjà couverte. MetalLB reste pertinent pour un cluster dont le CNI ne fait pas de BGP (k3s de l'agence au M18 par exemple).
7. `ssh m15-essai sudo poweroff` entre deux séances ; destruction au mini-projet.

**Explications**

Les deux projets font la même chose en trois étapes (attribuer, programmer, annoncer) ; la différence est **qui** fait le chemin de données et combien de pièces il faut maintenir. MetalLB s'appuie sur kube-proxy ou le CNI pour la programmation ; Cilium fait tout dans le même agent, d'où moins de pièces et un diagnostic unique (`cilium-dbg`, Hubble).

**Alternatives** : kube-vip (mode service, L2 ou BGP) ; OpenELB ; un équilibreur matériel ou HAProxy externe (comme `lb01`/`lb02`) devant des NodePorts.

**Pièges classiques**
- Laisser le pool de pods par défaut de Cilium sur un cluster d'essai du lab.
- Choisir des adresses L2 hors du réseau du nœud : pas d'erreur, juste aucune réponse.
- Configurer un `BGPPeer` vers la bordure « pour voir » : session refusée (politique), et c'est une modification d'un équipement partagé.
- Installer MetalLB à côté de LB IPAM sur le même cluster sans `loadBalancerClass` : deux contrôleurs se disputent les Services.

**En production chez MédiSphère** : décision dans l'ADR-0150 (Cilium seul) ; MetalLB documenté comme solution de repli pour une distribution sans BGP dans le CNI (M18).

---

### M15-E20 — Publier une application hors du lab par `lb01`/`lb02`

**Solution**

Fichiers : [`haproxy.yml`](fichiers/M15-E20/ansible/inventories/lab/group_vars/role_lb/haproxy.yml) (remplace la version de M07-E28), [`pare_feu.yml.extrait`](fichiers/M15-E20/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [`entree-du-cluster.extrait-E20.md`](fichiers/M15-E20/medisphere/docs/kubernetes/reseau/entree-du-cluster.extrait-E20.md).

1. **Chemins après le changement.**
   ```
   GitLab     : client ─443─▶ fe_tls_sni (SNI gitlab.par1…) ─▶ be_terminaison_locale ─abns+PROXY v2─▶ fe_publication (TLS) ─▶ be_gitlab ─TLS─▶ git01
   MédiAgenda : client ─443─▶ fe_tls_sni (SNI mediagenda-recette.apps…, publié) ─▶ be_k8s_gw_par1 ─TLS intact─▶ 10.10.41.10:443 ─▶ gw-par1 ─▶ pods
   essai.apps : client ─443─▶ fe_tls_sni (SNI en .apps…, non publié) ─▶ connexion refusée
   ```
2. **Configuration** (lire les commentaires du fichier). Points clés : `mode tcp` et `option tcplog` + un `log-format` TCP (celui des `defaults` est HTTP) ; les `acl` déclarées **avant** les règles ; `tcp-request inspect-delay 5s`, puis `set-var(sess.sni) req.ssl_sni,lower` **si** `req.ssl_hello_type 1`, puis le refus des noms `.apps` non publiés, **puis** `accept` (une règle `accept` arrête l'évaluation des règles `tcp-request content` qui la suivent : un refus placé après ne serait jamais lu) ; `be_terminaison_locale` → `abns@publication` avec `send-proxy-v2`, et `fe_publication` écoute sur `abns@publication accept-proxy ssl crt …`. La liste des noms publiés est une variable (`k8s_noms_publies`), rendue en `-m str` sur une liste. Toutes les sections TCP portent `tls: true` : le rôle ne les rend que si la terminaison locale existe (certificats présents), jamais l'une sans l'autre. Le rôle valide par `haproxy -c` avant de recharger (rechargement sans coupure : `expose-fd listeners`, M07-E28).
3. **Flux.** `$V_DMZ`, `[$LB01, $LB02]` → `$V_K8S`, `$GW_PAR1`, TCP 443 ; seule ouverture. MR relue par Karim, pipeline (secours d'abord).
4. **Vérifications** :
   ```
   admin@adm01:~$ curl -sS --resolve mediagenda-recette.apps.par1.medisphere.internal:443:10.10.70.200 \
       https://mediagenda-recette.apps.par1.medisphere.internal/sante
   {"statut":"ok","version":"…"}
   admin@adm01:~$ openssl s_client -connect 10.10.70.200:443 -servername mediagenda-recette.apps.par1.medisphere.internal </dev/null 2>/dev/null | openssl x509 -noout -subject
   subject=CN=*.apps.par1.medisphere.internal                          # le joker du CLUSTER
   admin@adm01:~$ curl -sS --resolve essai.apps.par1.medisphere.internal:443:10.10.70.200 https://essai.apps.par1.medisphere.internal/
   curl: (35) Recv failure: Connection reset by peer
   admin@adm01:~$ curl -sS https://essai.apps.par1.medisphere.internal/hostname         # en direct : répond
   admin@adm01:~$ curl -sS https://gitlab.par1.medisphere.internal/-/readiness          # inchangé
   ```
   Journal de GitLab (`/var/log/gitlab/nginx/gitlab_access.log` sur `git01`) : l'adresse du client (10.10.10.10) apparaît toujours, grâce au protocole PROXY puis `X-Forwarded-For`.
5. **Depuis le LAN maison** : `curl --resolve mediagenda-recette.apps.par1.medisphere.internal:443:<IP-GW-WAN-VIP> https://…/sante` (avec la racine MédiSphère installée sur le poste, ou `--cacert`).
6. **Bascule** : `sudo systemctl stop keepalived` sur le maître ; la VIP passe en ~3 s (M07) ; les connexions établies sur l'ancien maître sont perdues (pas de synchronisation d'état entre HAProxy), les nouvelles passent ; boucle à une requête par seconde : 2 à 4 échecs, identiques pour MédiAgenda et GitLab. ⚠️ À vérifier sur ton lab.
7. **Adresse client.** MédiAgenda voit l'adresse de l'Envoy ; l'Envoy voit celle du **répartiteur** (10.10.70.10/11), pas celle du client : en TCP relayé, il n'y a pas d'en-tête à ajouter. Options : protocole PROXY vers la Gateway (`gatewayAPI.enableProxyProtocol` de Cilium : s'applique à **tous** les clients de la Gateway, qui devraient tous l'envoyer — les clients internes du lab ne le font pas : écarté) ; ou terminer le TLS sur les répartiteurs pour ce nom (certificat ACME dédié sur `lb01`/`lb02`, ré-chiffrement vers la Gateway, `X-Forwarded-For`) : plus de pièces, mais journal d'accès complet. À trancher dans l'ADR-0150 selon l'exigence HDS de traçabilité.
8. **Documentation** : [extrait](fichiers/M15-E20/medisphere/docs/kubernetes/reseau/entree-du-cluster.extrait-E20.md).

**Explications**

Le SNI voyage **en clair** dans le `ClientHello` (tant qu'on n'utilise pas ECH) : un répartiteur peut aiguiller par nom sans posséder la clé privée. C'est ce qui permet de garder une seule adresse et un seul port publics pour des services terminés à des endroits différents. Le passage par une adresse abstraite (`abns@`) et le protocole PROXY conservent pour les services locaux tout ce qu'ils avaient (adresse client, en-têtes, limitation de débit par adresse).

**Alternatives**
- *Terminer tout le TLS sur les répartiteurs* (certificat `*.apps` ou par nom sur `lb01`/`lb02`) : visibilité HTTP complète, mais une seconde copie de la clé, ou une seconde émission ; et le cluster ne maîtrise plus son certificat public.
- *Une seconde VIP* pour Kubernetes : séparation nette, mais une adresse publique de plus (et la redirection WAN est sur 443 d'une seule VIP).
- *Publier tout `*.apps`* : simple, mais la Hubble UI, les essais et tout ce qui se publie en interne deviendraient visibles dehors.

**Pièges classiques**
- `accept` avant les autres règles `tcp-request content` (refus jamais appliqué).
- Garder le `log-format` HTTP sur un frontal TCP (avertissement, journal inutilisable).
- Oublier `accept-proxy` d'un côté ou `send-proxy-v2` de l'autre : GitLab casse (en-tête PROXY interprété comme du TLS) ou perd l'adresse client.
- Publier un nom dehors sans vérifier que le client extérieur fait confiance à la racine MédiSphère.
- Ouvrir 10.10.41.0/24 entier au lieu de la seule adresse de `gw-par1`.

**En production chez MédiSphère**
Liste des noms publiés revue par Sophie (données de santé exposées à l'extérieur) ; supervision du backend `be_k8s_gw_par1` (métriques HAProxy, M21) ; le jour où l'adresse client est exigée, terminaison sur les répartiteurs pour les noms concernés.

---

### M15-E21 — Revue : politiques et routes du stagiaire

**Revue attendue** (fichiers de [`ressources/E21-medidoc-lucas/`](../ressources/E21-medidoc-lucas/) ; version corrigée : [`fichiers/M15-E21/corrige/`](fichiers/M15-E21/corrige/)).

| # | Fichier | Gravité | Défaut | Correction |
|---|---|---|---|---|
| 1 | `00-namespace.yaml` | bloquant | PSA `privileged` sur un espace applicatif : tout pod peut monter l'hôte, prendre le réseau de l'hôte, tourner en root ; MédiDoc n'en a aucun besoin (« ne démarrait pas chez moi » = un défaut du manifeste du pod, pas de l'espace) | `restricted` (M14-E18), corriger le pod |
| 2 | `00-namespace.yaml` | majeur | redéfinit un espace qui appartient à la plateforme (`espaces/medidoc-dev.yaml`, M14-E33) : deux sources de vérité, la dernière application gagne | MR sur le fichier de la plateforme, étiquette d'exposition seulement |
| 3 | `01-gateway.yaml` | majeur | une Gateway par équipe : contraire à l'ADR-0150 (une entrée partagée), une adresse, un écouteur, des noms à maintenir en double | s'attacher à `gw-par1` |
| 4 | `01-gateway.yaml` | bloquant | `addresses: 10.10.41.10` = l'adresse de `gw-par1` : LB IPAM ne la donnera pas (déjà attribuée, sans clé de partage) → `Programmed=False` ; avec une clé de partage, deux Envoy se disputeraient les ports 80/443 | supprimer (pas de Gateway propre) |
| 5 | `01-gateway.yaml` | bloquant | écouteur HTTP sans redirection, `from: All` : données de santé en clair, routes de **n'importe quel** espace | rien sur 80 hors redirection (fournie par `gw-par1`) |
| 6 | `01-gateway.yaml` | majeur | écouteur `*.apps.par1.medisphere.internal` : la Gateway de MédiDoc revendique **tous** les noms des autres équipes | sans objet après #3 |
| 7 | `02-referencegrant.yaml` | bloquant | `ReferenceGrant` dans `passerelles` vers **tous** les Secrets (`to` sans `name`), pour les Gateways de `medidoc-dev` : l'équipe obtient l'usage du joker (se faire passer pour n'importe quel `*.apps`) et de tout Secret futur de `passerelles` | supprimer ; et Lucas n'a pas le droit d'écrire dans `passerelles` (RBAC) : la MR n'aurait pas pu s'appliquer |
| 8 | `02-referencegrant.yaml` | mineur | `v1beta1` : encore servie en v1.6.1, mais `v1` existe | `gateway.networking.k8s.io/v1` |
| 9 | `03-httproute.yaml` | majeur | parent `gw-medidoc` (sans `sectionName`) | `gw-par1`, `passerelles`, `sectionName: https` |
| 10 | `03-httproute.yaml` | bloquant (fonctionnel) | `backendRefs` port 80 alors que le Service expose 8080 : `ResolvedRefs=False`, 500 | port 8080 |
| 11 | `03-httproute.yaml` | mineur | second nom `medidoc.par1.medisphere.internal` : hors de l'écouteur (ignoré), hors de la zone d'ExternalDNS (jamais publié), source de confusion | retirer |
| 12 | `03-httproute.yaml` | majeur | `PathPrefix /` publie `/metrics`, `/healthz`, `/readyz` à toute personne qui atteint l'entrée | `/documents` seulement (et politique L7, #21-#22) |
| 13 | `05-certificate.yaml` | bloquant (fonctionnel) | `issuerRef.kind: Issuer` : aucun `Issuer` `step-ca-acme` dans `medidoc-dev` → jamais émis | `ClusterIssuer` (ou rien : #16) |
| 14 | `05-certificate.yaml` | majeur | `duration: 8760h` : contraire à la politique (30 jours, M06-E27) ; le provisioner `acme` plafonne de toute façon | pas de `duration` |
| 15 | `05-certificate.yaml` | mineur | `rotationPolicy: Never` : la même clé pour toujours | `Always` |
| 16 | `05-certificate.yaml` | mineur | certificat inutile : le joker de `gw-par1` couvre `medidoc-dev.apps…` | supprimer |
| 17 | `06-networkpolicy.yaml` | bloquant | « refus par défaut » qui **autorise tout** en entrée (`ingress: - {}`) | refus sans règle + autorisations explicites |
| 18 | `06-networkpolicy.yaml` | majeur | sortie `0.0.0.0/0:8333` : tout hôte du monde sur ce port | `toFQDNs` vers `s3-01` (ou bloc /32) |
| 19 | `06-networkpolicy.yaml` | bloquant (fonctionnel) | `policyTypes: Egress` sans règle DNS : plus de résolution, MédiDoc ne trouve pas `s3-01` | `sortie-dns` vers CoreDNS |
| 20 | `07-ciliumnetworkpolicy.yaml` | majeur | `endpointSelector app: medidoc` alors que les pods portent `app.kubernetes.io/name: medidoc` (cf. Service) : la politique ne sélectionne **rien** | même étiquette que le Service |
| 21 | `07-ciliumnetworkpolicy.yaml` | majeur | `fromEntities: [world, cluster]` : tout pod du cluster ; la Gateway est l'identité `ingress` | `ingress` (+ `host` pour les sondes) |
| 22 | `07-ciliumnetworkpolicy.yaml` | mineur | règle L7 `.*`/`/.*` : n'interdit rien, ajoute le proxy | liste des méthodes et chemins |
| 23 | `07-ciliumnetworkpolicy.yaml` | bloquant | `toFQDNs: matchPattern: "*"` : sortie vers **n'importe quel** nom (exfiltration de documents patients) ; et sans règle DNS L7, `toFQDNs` n'apprend aucune adresse (rien ne passe) | `matchName: s3-01.par1.medisphere.internal` + règle `dns` vers CoreDNS |
| 24 | `08-secret-s3.yaml` | bloquant | identifiants S3 **en clair** dans le dépôt (et dans l'historique de la MR) | retirer, **révoquer** le mot de passe, Vault + outil (M25 : External Secrets) |
| 25 | `08-secret-s3.yaml` | majeur | point de terminaison `http://` : `s3-01` est en HTTPS (PLAN §4.8) | `https://` (et `MEDIDOC_CA_FILE`) |
| 26 | `description-mr.md` | majeur (processus) | « on resserrera après la démo », « testé sur mon kind » : aucune preuve sur le cluster cible, sécurité reportée | essais sur `k8s-par1` listés dans la MR, refus par défaut dès le premier jour |

**Preuves** (exemples) : `kubectl apply --dry-run=server` de `01-gateway.yaml` dans `wb-essais` (espace changé) puis lecture des conditions → `Programmed=False`, raison liée à l'adresse ; `03-httproute.yaml` → `ResolvedRefs=False` (`BackendNotFound` : port inexistant) ; `kubeconform` de `05-certificate.yaml` passe (le schéma ne sait pas que l'`Issuer` n'existe pas : la validation de syntaxe ne remplace pas la revue) ; `hubble observe` d'un pod MédiDoc avec `06-networkpolicy.yaml` : `DNS` refusé.

**Réponse à Lucas** (exemple) : « Merci Lucas, la structure est bonne (un fichier par objet, des noms clairs, l'idée de réutiliser le joker). Avant tout le reste : retire le Secret S3 du dépôt **aujourd'hui** (on change le mot de passe), remets l'espace en `restricted` et remplace ta Gateway par une route sur `gw-par1` : ce sont trois blocages de sécurité. Ensuite les politiques (refus par défaut réel, entrée depuis `ingress`, sortie vers `s3-01` seulement) et les ports. Pour la prochaine fois : teste sur `k8s-par1` dans `wb-essais` (pas sur kind, qui n'a ni Cilium ni nos Gateways), lis les conditions des objets après `apply`, et relis la page *entrée du cluster*. On regarde ça ensemble demain matin ? »

**Barème indicatif** : 12 défauts avec gravité et correction = attendu ; les bloquants #1, #4, #5, #7, #17, #23, #24 sont obligatoires.

**Pièges classiques** : s'arrêter à ce que `kubeconform` ou `--dry-run=server` signale (ils ne voient ni l'`Issuer` absent, ni une politique qui ne sélectionne rien, ni un secret en clair) ; noter « à revoir » sans gravité ni correction ; corriger le Secret dans le fichier sans exiger la **révocation** (l'historique Git le garde) ; relire les politiques une à une sans se demander ce qu'elles donnent **ensemble**.

**En production chez MédiSphère** : ces défauts deviennent des contrôles automatiques plutôt que des remarques de revue : Gitleaks dans le pipeline (M17), `kubeconform` avec les schémas des CRD (M15-E23), politiques d'admission qui refusent une Gateway d'équipe, un `fromEntities: [world]` ou un `toFQDNs` joker (M26), modèle de MR qui exige les essais sur `k8s-par1`.

---

### M15-E22 — Runbook : un service n'est plus joignable

**Exemple de rédaction** : [`RB-150-service-injoignable.md`](fichiers/M15-E22/medisphere/docs/kubernetes/reseau/runbooks/RB-150-service-injoignable.md).

**Grille de relecture « Nadia »** (2 points par ligne, 20 au total ; acceptable à 14, aucun 0 sur les lignes marquées *)

| Critère | 0 | 1 | 2 |
|---|---|---|---|
| Modèle du socle (portée, symptômes, accès, étapes, escalade, retour, historique) * | absent | partiel | complet |
| Arbre de décision en tête, tenant sur un écran * | absent | liste | arbre fondé sur le symptôme réel (`curl -v`) |
| Lecture seule pendant le diagnostic * | commandes qui modifient | ambigu | explicite, correction séparée |
| Couche DNS (récurseurs, autoritaire, ExternalDNS, DNSSEC) | absente | « dig » seul | les trois niveaux et le cache négatif |
| Couche adresse/annonce (LB IPAM, BGP, bordure) | absente | une commande | côté cluster **et** côté bordure |
| Gateway, certificat, route (conditions) | absente | `kubectl get` | lecture des conditions et de leurs raisons |
| Service, EndpointSlices, pods | absente | pods seuls | du sélecteur aux sondes |
| Politiques (Hubble) | absente | « vérifier les netpol » | Hubble avec verdicts, identité `ingress` |
| Accès extérieur (répartiteurs) | absent | cité | SNI, liste des noms publiés |
| Escalade et essai réel consigné * | absents | escalade seule | escalade par couche + essai dans l'historique |

**Pièges classiques** : un runbook qui commence par « redémarrer le pod » ; des commandes qui exigent des droits d'administration pour lire ; oublier que le symptôme vu de l'extérieur (répartiteurs) et de l'intérieur peuvent différer ; ne pas dire **qui** appeler.

**En production chez MédiSphère** : le runbook est relu par l'astreinte avant d'entrer en service, rejoué à chaque panne réelle ou simulée (M15-E35 et suivants complètent RB-150) et daté ; chaque commande citée est exécutable avec l'identité en lecture de l'astreinte, et les liens vers RB-151 (certificat) et RB-152 (BGP) évitent de tout réécrire ici.

---

### M15-E23 — Le réseau du cluster décrit par le code

**Exemple de solution**

Fichiers : [`versions.env`](fichiers/M15-E23/k8s/composants/versions.env), [`Taskfile.reseau.yml`](fichiers/M15-E23/k8s/Taskfile.reseau.yml), [`derive-reseau.sh`](fichiers/M15-E23/k8s/outils/derive-reseau.sh), [`schemas-crd.sh`](fichiers/M15-E23/k8s/outils/schemas-crd.sh), [`gitlab-ci.extrait.yml`](fichiers/M15-E23/k8s/ci/gitlab-ci.extrait.yml), [`reconstruction.md`](fichiers/M15-E23/medisphere/docs/kubernetes/reseau/reconstruction.md). Les autres fichiers du dépôt sont ceux des exercices E10 à E20 (superposés), plus ceux du palier 1 (`composants/coredns/`, `composants/gateway-api/`).

1. **Contenu du dépôt** (`plateforme/k8s`) :
   ```
   composants/versions.env                     versions épinglées (une seule source)
   composants/gateway-api/                     v1.6.1/ (CRD du canal standard) + SHA256SUMS-v1.6.1 (M15-E07)
   composants/cilium/values.yaml               KPR, Gateway API, BGP, Hubble (M14, M15-E07/E08/E11)
   composants/cilium/lb-ipam/lb-par1.yaml      (E10)
   composants/cilium/bgp/                      bgp-par1, bordure, services-lb (E11)
   composants/coredns/                         Corefile géré (M15-E04)
   composants/cert-manager/                    values.yaml, clusterissuer-step-ca-acme.yaml (E13, E14)
   composants/external-dns/values.yaml         (E15)
   composants/passerelles/                     gw-par1, redirection-https, certificat-apps-joker (E12, E14, E15)
   cluster/noeuds.yaml                         étiquettes gérées (E11)
   espaces/{passerelles,cert-manager,external-dns}.yaml, étiquettes d'exposition (E12, E15)
   espaces/politiques-mediagenda/              (E17) ; espaces/mediagenda-recette/httproute-mediagenda.yaml (E12)
   outils/{etiqueter-noeuds,secret-tsig,derive-reseau,schemas-crd}.sh
   Taskfile.yml  (includes: reseau: ./Taskfile.reseau.yml)
   ```
2. **Tâches.** `task reseau:installer` enchaîne les tâches dans l'ordre de [`reconstruction.md`](fichiers/M15-E23/medisphere/docs/kubernetes/reseau/reconstruction.md) (Task s'arrête à la première commande en échec) ; les releases existantes sont reprises par `helm upgrade --install` (même nom, même espace : aucune réinstallation). `task reseau:derive` : `kubectl diff --server-side --force-conflicts` par répertoire (code 1 = différence ; sans `--force-conflicts`, un champ modifié à la main par un autre gestionnaire de champs fait échouer le dry-run pour conflit au lieu de montrer la dérive), versions et valeurs des releases Helm (sous-ensemble : la CLI `cilium` ajoute des valeurs détectées à l'installation, qui ne sont pas une dérive), étiquettes des nœuds (`--verifier`). Code 1 au moindre écart.
3. **CI.** `valider-manifestes` : kubeconform 0.8.0 strict, schémas Kubernetes 1.36 et schémas générés depuis les CRD (outil `schemas-crd.sh`, régénéré à chaque montée de version) ; `versions-epinglees` : aucune version flottante, aucune version hors de `versions.env`, chaque version avec son correctif.
4. **Documentation** : [`reconstruction.md`](fichiers/M15-E23/medisphere/docs/kubernetes/reseau/reconstruction.md).
5. **Preuve** (exemples acceptables) : désinstallation d'ExternalDNS (`helm uninstall`) puis `task reseau:installer` : la release revient, les noms sont toujours là (`sync` ne supprime que ce qu'il possède, et il les possède encore) ; ou suppression et recréation de `lb-par1`… **non** : réattribution d'adresses possible (E10) — un mauvais choix de preuve, à éviter ; ou `task reseau:installer` contre `m15-essai` (sans BGP ni zone, les tâches correspondantes échouent proprement : la preuve porte sur l'ordre et l'idempotence). Consigner `task reseau:derive` avant et après.

**Explications**

Un composant de plateforme est reproductible quand trois choses sont dans le dépôt : **quoi** (manifestes, values), **quelle version** (épinglée, une seule source), **dans quel ordre**. La dérive est le complément indispensable : sans elle, un `kubectl edit` d'urgence devient la vraie configuration et la prochaine reconstruction l'efface. Ce que les contrôleurs **produisent** (Services de Gateway, Secrets de certificats, `CiliumBGPNodeConfig`) n'est jamais dans le dépôt.

**Alternatives** : Helmfile (M17) pour les releases ; Argo CD (M20) qui fait la dérive en continu et la corrige ; Kustomize pour les politiques par espace.

**Pièges classiques**
- `kubectl diff` sans `--server-side` (comparaison fausse sur les champs par défaut).
- Versionner un Secret « pour que la reconstruction marche ».
- Oublier les prérequis hors cluster (bordure, DNS, délégation) : la reconstruction « réussit » et rien n'est joignable.
- Une tâche de dérive qui écrit (`apply` au lieu de `diff`).

**En production chez MédiSphère** : Argo CD (M20) remplace `task reseau:installer` et la dérive devient une alerte ; `versions.env` est mis à jour par Renovate (M13) avec une MR par version.
