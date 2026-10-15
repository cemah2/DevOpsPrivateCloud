# Module 15 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. Sur un réseau de cluster, « j'ai supprimé la politique et ça remarche » ou « j'ai redémarré Cilium » sont des non-réponses : le premier ouvre ce qui devait rester fermé, le second efface la preuve (état de l'agent, compteurs, connexions suivies) et peut aggraver la coupure.

Les scripts d'injection sont dans `corrige/pannes/` (`_m15-commun.sh` : accès au cluster avec le kubeconfig d'administration, sauvegarde et remise en état des objets, témoins de `wb-pannes`, précondition « entrée et réseau sains », choix de la passerelle de secours). Chaque objet modifié est sauvegardé sur `adm01` dans `~/.local/state/workbook/k8s/M15-EXX/` (YAML de la convention du bloc C et copie JSON) ; les actions sur les nœuds et la bordure sont journalisées sur l'hôte dans `/var/lib/workbook/pannes.log`.

Les sorties reproduites sont **représentatives** : noms de pods, identités, adresses et formulations exactes varient selon ton cluster et la version. Elles suivent la documentation de Cilium 1.20, Gateway API v1.6, cert-manager 1.21, ExternalDNS 0.23, FRR 10.7 et PowerDNS Authoritative 5.0.

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) :
- Messages exacts d'Envoy (Gateway de Cilium) : `no healthy upstream` pour un Service sans point de terminaison prêt, `upstream connect error … connection failure` pour un port fermé ; code 500 pour un `backendRefs` qui vise un port absent du Service (E35 v3 ; la raison `BackendNotFound` et son message, elles, sont celles du code de l'opérateur au tag `v1.20.2`, `operator/pkg/gateway-api/routechecks/route_checks.go`).
- E36 v1 : délai réel de prise en compte du Corefile par le greffon `reload` (30 s à 2 min selon la propagation du ConfigMap) ; le script attend jusqu'à 3 min.
- E36 v2, E37 v1 : comportement de `egressDeny`/`ingressDeny` avec `toEndpoints`/`fromEntities: [all]` et `enableDefaultDeny` (champ introduit en Cilium 1.16) ; en particulier, l'effet d'un `ingressDeny` depuis `all` sur les sondes du kubelet (entité `host`).
- E38 v2 : l'annonce `ExternalIP` à la place de `LoadBalancerIP` retire bien les /32 des Services `LoadBalancer` (aucun Service de `k8s-par1` n'a d'`externalIPs`) ; délai de retrait avec le redémarrage gracieux (le script attend jusqu'à 5 min).
- E38 v5 : en FRR 10.7, la modification d'une liste de préfixes est réévaluée automatiquement (temporisation `bgp route-map delay-timer`) ; le script force en plus `clear bgp ipv4 unicast * soft in`, qui n'interrompt aucune session.
- E39 : raisons exactes des conditions posées par Cilium (`InvalidCertificateRef`, `RefNotPermitted`, `NotAllowedByListeners`) et comportement d'Envoy pour un écouteur non programmé (réinitialisation pendant la négociation, ou écouteur absent).
- E40 v3 : message exact de cert-manager quand aucun solveur ne convient au nom (`no configured challenge solvers can be used for this challenge`) ; message de step-ca si le solveur HTTP-01 sans sélecteur est choisi pour un joker.
- E41 : nom du TXT de propriété (format « nouveau » préfixé `a-`, ou nom lui-même) selon la version et les options d'ExternalDNS 0.23 ; comportement d'ExternalDNS à qui il manque les droits sur les HTTPRoute (erreurs répétées ou arrêt du processus).
- E42 v2 : prise en compte de `tunnel-port` par une `CiliumNodeConfig` (cilium.io/v2) au redémarrage de l'agent, et absence de repli automatique ; E42 v1 : les paquets WireGuard et VXLAN traversent bien la chaîne `input` de netfilter sur Debian 13 (pas de court-circuit par eBPF avant netfilter).
- E44 : noms exacts des sous-commandes `cilium-dbg bpf …` en 1.20 (`bpf ipcache list` contre `map get cilium_ipcache`, options de `bpf lb list`), et présence de `bpftool` dans Debian 13 (paquet `bpftool`).

---

## Méthode commune aux pannes du réseau du cluster

1. **Reproduire depuis plusieurs points.** Depuis `adm01` (le chemin complet), depuis un pod témoin (sans la Gateway ni la bordure), depuis un nœud (sans le CNI côté client). La comparaison situe la panne avant même d'ouvrir un objet.
2. **Suivre le chemin, étage par étage**, avec l'outil propre à chacun :

   | Étage | Objet | Commande de preuve |
   |---|---|---|
   | Nom public | zone `apps` | `dig @10.10.20.10 <nom> A` et `TXT`, `dig @10.10.20.16` |
   | Adresse | LB IPAM, BGP, bordure | `kubectl get svc -A`, `cilium bgp peers`, `vtysh -c 'show bgp summary'`, `ip route` sur les passerelles |
   | Écouteur | Gateway | `kubectl get gateway -o yaml` (`status.listeners`), `openssl s_client -servername` |
   | Route | HTTPRoute | `status.parents[].conditions` |
   | Service | Service, EndpointSlice | `kubectl get svc,endpointslices -o wide`, `cilium-dbg service list` |
   | Pod | Pod, sondes | `kubectl get pods -o wide`, `describe`, journaux |
   | Politique | NP, CNP, CCNP | `hubble observe --verdict DROPPED`, `cilium-dbg bpf policy get` |
   | DNS du cluster | CoreDNS, `resolv.conf` | `dig` depuis un pod, `hubble observe --protocol dns` |
   | Chemin entre nœuds | agent, tunnel, chiffrement | `cilium-health status --probe`, `cilium-dbg status --verbose`, `tcpdump` |
3. **Lire les conditions et les événements** (`kubectl events -n <espace>`, `describe`) : la Gateway API, cert-manager, LB IPAM et ExternalDNS y écrivent la raison de leurs refus.
4. **Chercher ce qui a bougé** : `managedFields` (`kubectl get … --show-managed-fields`) dit quel gestionnaire a écrit quel champ et quand ; `kubectl diff -f` compare au dépôt ; `helm get values` et `helm history` pour les composants installés par Helm ; `kubectl rollout history` pour un gabarit ; sur la bordure, `vtysh -c 'show running-config'` contre `/etc/frr/frr.conf`. Les fiches d'audit du serveur d'API (M14-E27) disent **qui**.
5. **Corriger à la racine, puis faire converger le code.** Une correction à chaud qui n'est pas dans `plateforme/k8s` ou `plateforme/ansible` sera défaite ; une cause présente dans le dépôt reviendra au prochain `task appliquer`.
6. **Prévenir** : quel contrôle de `ms-verif-k8s-reseau`, quelle règle de pipeline (`kubeconform`, test de politiques), quelle métrique (M21) aurait vu la panne avant l'utilisateur ?

Deux scripts automatisent l'étape 4 : `outils/derive-reseau.sh` de M15-E23 ([fichier](fichiers/M15-E23/k8s/outils/derive-reseau.sh)) pour le cluster (manifestes, values Helm, étiquettes) et [`derive-bordure-noeuds.sh`](fichiers/M15-E43/k8s/outils/derive-bordure-noeuds.sh), écrit pour ce palier, pour ce que le premier ne voit pas (configuration courante de FRR, pare-feu des nœuds). Planifiés ensemble, ils sont l'outil de prévention commun du palier.

---

### M15-E35 — Panne : le service ne répond plus

**Démarche de diagnostic**

*Symptômes* : `https://mediagenda-recette.apps.par1.medisphere.internal/` répond 503 (variantes 1 et 2) ou 500 (variante 3) ; pods `Running`, journaux de l'application muets (aucune requête n'arrive).

*Hypothèses* : la Gateway n'a pas de destination (aucun point de terminaison prêt) ; elle en a, mais ils refusent la connexion (mauvais port) ; la route ne sait pas résoudre son backend (port ou Service inexistant) ; une politique jette le trafic Gateway → API (c'est E37 : le symptôme est alors un délai dépassé ou un 503 après expiration, et Hubble montre `DROPPED`).

**Étape 1 — Reproduire et lire la réponse d'Envoy.**

```
admin@adm01:~$ curl -sv https://mediagenda-recette.apps.par1.medisphere.internal/pret
< HTTP/2 503
< content-type: text/plain
< server: envoy
no healthy upstream                                     # variante 1
upstream connect error or disconnect/reset before headers. reset reason: connection failure,
transport failure reason: delayed connect error: 111    # variante 2 (111 = ECONNREFUSED)
< HTTP/2 500                                            # variante 3
```

Le TLS est négocié et `server: envoy` répond : nom, adresse, BGP, écouteur et certificat sont sains. La panne est **derrière** l'écouteur. `no healthy upstream` veut dire « Envoy n'a aucune destination prête » ; `connection failure … 111` veut dire « il en a, mais personne n'écoute sur ce port » ; un 500 sans corps d'application pointe la route elle-même.

**Étape 2 — La route.**

```
admin@adm01:~$ kubectl -n mediagenda-recette get httproute mediagenda -o jsonpath='{.status.parents[0].conditions}' | jq -c '.[] | {type,status,reason}'
{"type":"Accepted","status":"True","reason":"Accepted"}
{"type":"ResolvedRefs","status":"True","reason":"ResolvedRefs"}     # variantes 1 et 2
{"type":"ResolvedRefs","status":"False","reason":"BackendNotFound"}  # variante 3 : message « Service port 80 could not be resolved for backend … »
```

**Étape 3 — Service, EndpointSlice, pods.**

```
admin@adm01:~$ kubectl -n mediagenda-recette get svc mediagenda-api -o wide
NAME             TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE   SELECTOR
mediagenda-api   ClusterIP   10.96.41.187   <none>        80/TCP    12d   app.kubernetes.io/name=mediagenda-api-v2   # v1
admin@adm01:~$ kubectl -n mediagenda-recette get endpointslices -l kubernetes.io/service-name=mediagenda-api
NAME                   ADDRESSTYPE   PORTS     ENDPOINTS   AGE
mediagenda-api-x7kq2   IPv4          <unset>   <unset>     12d        # v1 : vide
mediagenda-api-x7kq2   IPv4          8080      10.240.3.17,10.240.5.22   # v2 : port 8080
admin@adm01:~$ kubectl -n mediagenda-recette get pods --show-labels -o wide
admin@adm01:~$ kubectl -n mediagenda-recette get pod <pod> -o jsonpath='{.spec.containers[0].ports}'
[{"containerPort":8000,"name":"http","protocol":"TCP"}]
```

(Nom et port de la route du corrigé de M15-E12 : Service `mediagenda-api`, port 80, `targetPort: http` → 8000 du conteneur, comme au M14.)

**Étape 4 — Vérifier de l'intérieur, sans la Gateway.**

```
admin@adm01:~$ kubectl -n wb-pannes exec ds/sonde -- curl -s -m 3 -o /dev/null -w '%{http_code}\n' http://10.240.3.17:8000/pret
```

Ce test est **jeté** par les politiques (la sortie des témoins est limitée à leur espace, et `mediagenda-recette` n'accepte que la Gateway) : c'est attendu, et Hubble le confirme (`DROPPED`, `POLICY_DENIED`). Pour tester l'API sans la Gateway, utilise un `kubectl port-forward` (qui passe par le kubelet, pas par le réseau des pods) :

```
admin@adm01:~$ kubectl -n mediagenda-recette port-forward pod/<pod> 18000:8000 &
admin@adm01:~$ curl -s localhost:18000/pret        # 200 : l'application est saine
admin@adm01:~$ kubectl -n mediagenda-recette port-forward svc/mediagenda-api 18001:80 &
admin@adm01:~$ curl -s localhost:18001/pret        # v1 : kubectl ne trouve aucun pod pour le sélecteur ; v2 : kubectl journalise « connection refused » sur le port 8080 du pod
```

Et ce que Cilium a programmé :

```
admin@adm01:~$ kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg service list | grep 10.96.41.187
42   10.96.41.187:80      ClusterIP                                       # v1 : aucun backend
42   10.96.41.187:80      ClusterIP      1 => 10.240.3.17:8080 (active)   # v2
```

**Variante 1 — sélecteur du Service modifié.** Le sélecteur porte `…-v2` : aucun pod ne correspond, l'EndpointSlice est vide, Envoy n'a aucune destination. **Variante 2 — `targetPort` à 8080.** Les points de terminaison existent, mais MédiAgenda écoute sur 8000 : refus de connexion. **Variante 3 — `port` du Service changé.** La route vise le port 80 d'un Service qui n'expose plus que le port 8000 : la référence ne se résout pas, la Gateway renvoie 500 (comportement imposé par la spécification pour un `backendRefs` invalide).

**Qui l'a fait ?**

```
admin@adm01:~$ kubectl -n mediagenda-recette get svc mediagenda-api -o yaml --show-managed-fields | grep -B2 -A12 'manager:'
  - manager: kubectl-replace            # ou kubectl-edit, kubectl-patch
    operation: Update
    time: "2026-…"
admin@adm01:~/src/mediagenda-api$ git log -p -- k8s/recette/   # rien : la modification n'est pas dans le dépôt
```

**Correctif** : remettre le Service conforme au dépôt (`kubectl apply -f k8s/recette/40-api.yaml` depuis `~/src/mediagenda-api`, comme au M14-E21), jamais l'inverse (adapter les pods au sélecteur fautif). Vérifier : EndpointSlice peuplée, `cilium-dbg service list` avec les bons backends, `/pret` en 200.

**Prévention** : RB-150 complété ([extrait](fichiers/M15-E35/medisphere/docs/kubernetes/reseau/runbooks/RB-150-extrait-5xx.md)) ; contrôle de cohérence dans le pipeline de `mediagenda/api` (sélecteur ⇔ étiquettes de gabarit, `targetPort` ⇔ `containerPort`, `backendRefs.port` ⇔ `ports[].port`) ; détection de dérive (`derive-reseau.sh`, `kubectl diff`) planifiée ; en M20, GitOps corrigera la dérive de lui-même et la signalera.

**Explications**

Un Service n'est qu'une **promesse** : une adresse virtuelle et un sélecteur. Le contrôleur d'EndpointSlices transforme le sélecteur en liste d'adresses de pods prêts et de ports **résolus** (un `targetPort` nommé est traduit pod par pod). Cilium lit ces EndpointSlices et programme ses tables (`cilium_lb4_services_v2`, `cilium_lb4_backends_v3`) ; la Gateway de Cilium donne à Envoy les mêmes destinations. Aucune de ces étapes ne vérifie que l'application écoute réellement sur le port : seule la sonde de disponibilité du pod le prouve, et elle utilise le port du **conteneur**, pas celui du Service. D'où les pods « prêts » derrière un Service cassé.

**Alternatives**
- `targetPort` nommé (`http`) plutôt que numérique : le Service survit à un changement de port de l'application, à condition que le nom soit stable ; c'est le choix recommandé.
- Tests synthétiques par la Gateway (sonde externe) plutôt que par les seuls pods : c'est la seule mesure qui voit ce que voit l'utilisateur.

**Pièges classiques**
- Corriger les étiquettes des pods (en modifiant le Deployment) pour qu'elles correspondent au sélecteur fautif : impossible sans recréer le Deployment (sélecteur immuable), et cela fige l'erreur.
- Confondre `port` (ce que les clients visent), `targetPort` (ce que le pod écoute) et `nodePort`.
- Conclure « l'application est en panne » parce que la Gateway répond 503, sans lire le corps de la réponse.
- Tester avec `curl` depuis un pod d'un autre espace et prendre un refus de politique pour une panne du Service.

**En production chez MédiSphère**
Une alerte sur « Service sans point de terminaison prêt » (métrique de kube-state-metrics, M21), le contrôle de cohérence dans tous les pipelines de déploiement, et l'interdiction des modifications manuelles hors bris de glace (droits RBAC de M14, GitOps en M20).

---

### M15-E36 — Panne : la résolution DNS échoue dans les pods

**Démarche de diagnostic**

*Symptômes* : variante 1, les noms `*.medisphere.internal` expirent depuis les pods, alors que les noms du cluster et d'Internet résolvent, et que tout résout depuis `adm01` ; variantes 2 et 3, le déploiement de MédiAgenda en recette reste bloqué : le nouveau pod n'est jamais prêt et journalise un nom de base introuvable, les anciens pods servent toujours.

*Hypothèses* : CoreDNS en panne ou mal configuré (tout l'espace des noms ou un seul bloc) ; la requête n'arrive pas à CoreDNS (politique, chemin réseau) ; le pod n'interroge pas CoreDNS (`dnsPolicy`, `dnsConfig`) ; l'amont (`dns01`/`dns02`) ne répond pas ; recherche courte (`ndots`, `search`) mal comprise.

**Étape 1 — Ce qui échoue et ce qui marche, et où.**

```
admin@adm01:~$ kubectl -n wb-pannes exec ds/sonde -- sh -c 'for n in kubernetes.default.svc.cluster.local s3-01.par1.medisphere.internal deb.debian.org; do echo "$n: $(dig +short +time=2 +tries=1 $n | head -1)"; done'
kubernetes.default.svc.cluster.local: 10.96.0.1
s3-01.par1.medisphere.internal:                    # variante 1 : rien (délai dépassé)
deb.debian.org: 151.101.…
```

Pour les variantes 2 et 3, le témoin résout tout : la panne est propre à l'espace ou au pod.

```
admin@adm01:~$ kubectl -n mediagenda-recette get pods
mediagenda-api-6c9…-abcde   1/1   Running   0   3d
mediagenda-api-6c9…-fghij   1/1   Running   0   3d
mediagenda-api-7f4…-klmno   0/1   Running   0   6m     # nouveau gabarit, jamais prêt
admin@adm01:~$ kubectl -n mediagenda-recette logs mediagenda-api-7f4…-klmno | tail -2
{"niveau":"ERROR","message":"PostgreSQL injoignable","erreur":"… failed to resolve host 'postgresql' …"}
```

**Étape 2 — Le `resolv.conf` du pod.**

```
admin@adm01:~$ kubectl -n mediagenda-recette exec mediagenda-api-6c9…-abcde -- cat /etc/resolv.conf
search mediagenda-recette.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
admin@adm01:~$ kubectl -n mediagenda-recette exec mediagenda-api-7f4…-klmno -- cat /etc/resolv.conf
nameserver 10.10.20.10                                  # variante 3 : résolveurs du nœud
nameserver 10.10.20.16
search par1.medisphere.internal
```

Variante 3 : le nouveau pod hérite du `resolv.conf` du **nœud** : `dnsPolicy: Default`. `dns01` ne connaît pas `postgresql.mediagenda-recette.svc.cluster.local`. Variante 2 : le `resolv.conf` est normal, la requête part vers `10.96.0.10`… et n'arrive pas :

```
admin@adm01:~$ hubble observe --namespace mediagenda-recette --port 53 --verdict DROPPED -o compact
Oct  8 10:41:07.112: mediagenda-recette/mediagenda-api-7f4…-klmno:51237 (ID:31842) <> kube-system/coredns-…:53 (ID:10243) policy-verdict:none DENIED (UDP)
Oct  8 10:41:07.112: mediagenda-recette/mediagenda-api-7f4…-klmno:51237 (ID:31842) <> kube-system/coredns-…:53 (ID:10243) Policy denied by denylist DROPPED (UDP)
admin@adm01:~$ kubectl -n mediagenda-recette get cnp
NAME                    AGE   VALID
interdire-kube-system   12m   True
admin@adm01:~$ kubectl -n mediagenda-recette get cnp interdire-kube-system -o yaml
  egressDeny:
  - toEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: kube-system
```

« Policy denied by denylist » (raison `POLICY_DENY`, distincte de `POLICY_DENIED` qui signale l'absence d'autorisation) : un refus explicite. CoreDNS **est** dans `kube-system` : la politique, posée pour « qu'aucune application ne parle aux composants de kube-system » (annotation `SEC-1612`), interdit aussi le DNS. Un refus l'emporte sur toute autorisation, y compris la règle DNS de E17.

Pourquoi les anciens pods marchent : ils ont résolu le nom de la base au démarrage et gardent leurs connexions (pool psycopg, client Valkey) ; ils ne refont une requête DNS qu'à la reconnexion. Une panne DNS ne se voit souvent qu'**au déploiement suivant** ou après le redémarrage d'une dépendance.

**Variante 1 — Corefile.**

```
admin@adm01:~$ kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}'
medisphere.internal:53 {
    errors
    cache 30
    forward . 10.10.20.1                    # au lieu de 10.10.20.10 10.10.20.16
}
.:53 {
    …
    forward . 10.10.20.10 10.10.20.16
}
admin@adm01:~$ kubectl -n kube-system logs -l k8s-app=kube-dns --since=10m | grep -m3 medisphere
[ERROR] plugin/errors: 2 s3-01.par1.medisphere.internal. A: read udp 10.240.1.23:44120->10.10.20.1:53: i/o timeout
admin@adm01:~$ dig +time=2 +tries=1 @10.10.20.1 s3-01.par1.medisphere.internal   # depuis adm01 : pas de réponse
admin@adm01:~/src/k8s$ kubectl diff -f composants/coredns/   # montre l'écart avec le dépôt
```

La passerelle (VIP `.1` du VLAN 20) ne sert pas de DNS : le bloc `medisphere.internal` ne reçoit jamais de réponse, le bloc `.` (Internet, et `cluster.local` traité par le greffon `kubernetes`) n'est pas concerné. Le greffon `errors` de CoreDNS le dit en clair.

**Correctif**
- V1 : Corefile du dépôt réappliqué (`task appliquer` ou la cible de `composants/coredns/`), attendre le rechargement (journal `[INFO] Reloading` puis `Reloading complete`), vérifier depuis un témoin.
- V2 : supprimer `interdire-kube-system` **après avoir prévenu Sophie** (c'est une demande de sécurité légitime mal traduite), puis lui proposer la bonne formulation : un refus vers `kube-system` **sauf** le DNS est impossible à écrire avec un `egressDeny` (un refus ne connaît pas d'exception) ; la bonne réponse est l'absence d'autorisation : le `refus-par-defaut` de l'espace interdit déjà tout `kube-system` sauf ce que E17 autorise (DNS). La demande SEC-1612 était donc **déjà satisfaite** ; à documenter dans la matrice des flux du cluster.
- V3 : `dnsPolicy` retiré du gabarit (ou `ClusterFirst`) dans `mediagenda/api` (`k8s/recette/`), réappliqué ; le déploiement se termine.

Dans tous les cas : `kubectl -n mediagenda-recette rollout status deploy/mediagenda-api` se termine, `/pret` répond 200 par la Gateway.

**Prévention** : test DNS dans `ms-verif-k8s-reseau` **depuis un pod** (un nom du cluster, un nom `medisphere.internal`, un nom Internet) ; règle de politique (Kyverno au M26) qui interdit `dnsPolicy: Default`/`None` hors des espaces de plateforme ; revue obligatoire de toute politique de refus (`*Deny`) par l'équipe Plateforme ; alerte sur les échecs de déploiement (`kube_deployment_status_condition{condition="Progressing",status="false"}`, M21).

**Explications**

`ndots:5` : un nom qui contient moins de 5 points est d'abord essayé avec chaque suffixe de `search`. `postgresql` devient `postgresql.mediagenda-recette.svc.cluster.local` au premier essai : c'est voulu. `s3-01.par1.medisphere.internal` (3 points) passe d'abord par les trois suffixes (trois `NXDOMAIN`, en A et en AAAA, soit six requêtes) avant d'être essayé tel quel : c'est le coût de `ndots:5`, d'où la recommandation d'écrire les noms externes avec un point final ou de baisser `ndots` par `dnsConfig` pour les applications qui en résolvent beaucoup. `dnsPolicy` vaut `ClusterFirst` **par défaut** ; `Default` signifie « comme le nœud » (le nom est historique et trompeur) ; `None` impose de tout fournir par `dnsConfig`.

**Alternatives**
- NodeLocal DNSCache : un cache DNS par nœud (adresse locale au lien) réduit la charge de CoreDNS et les délais de `conntrack` UDP ; il ajoute un composant à surveiller et doit être autorisé par les politiques (c'est une adresse du nœud).
- Règles DNS L7 de Cilium (`toPorts.rules.dns`) : elles permettent de restreindre **quels noms** un pod peut résoudre ; utiles avec `toFQDNs`, mais une règle trop étroite produit exactement le symptôme de la variante 2 (`REFUSED` renvoyé par le proxy DNS de Cilium).

**Pièges classiques**
- Tester depuis `adm01` ou un nœud et conclure « le DNS marche » : ni l'un ni l'autre ne passe par CoreDNS ni par les politiques des pods.
- Redémarrer CoreDNS : la variante 1 revient (le Corefile est le même), les variantes 2 et 3 ne sont pas concernées.
- Ajouter une autorisation DNS en plus : elle ne lève pas un refus explicite (variante 2).
- Oublier la sortie TCP 53 : les réponses de plus de 512 octets (ou tronquées) repassent en TCP ; une politique UDP seule produit des échecs rares et incompréhensibles.

**En production chez MédiSphère**
Supervision de CoreDNS (taux de `SERVFAIL`, latence, pertes vers l'amont, M21), deux pods au moins répartis sur deux nœuds (PDB), Corefile versionné et testé (`coredns -conf … -dns.port` dans le pipeline), et revue sécurité des politiques de refus.

---

### M15-E37 — Panne : plus rien ne passe dans l'espace de noms

**Démarche de diagnostic**

*Symptômes* : `/pret` ne répond plus depuis `adm01` (503 ou délai dépassé) ; les pods de `mediagenda-recette` sont `Running` mais deviennent non prêts (variantes 1 et 3) ou restent prêts mais injoignables depuis la Gateway (variante 2, selon la politique touchée).

*Hypothèses* : une règle de refus posée sur l'espace ; une autorisation qui ne sélectionne plus ses pods ; une autorisation dont les ports ne correspondent plus ; une politique de cluster (CCNP) modifiée ; la Gateway elle-même (E39) — écartée si le TLS est négocié et qu'Envoy répond.

**Étape 1 — Les verdicts.**

```
admin@adm01:~$ hubble observe --namespace mediagenda-recette --verdict DROPPED -o compact --last 20
# Variante 1 : tout ce qui entre dans un pod de l'espace est refusé, sondes comprises
… ingress (ID:8) -> mediagenda-recette/mediagenda-api-…:8000 (ID:31842) Policy denied by denylist DROPPED (TCP Flags: SYN)
… 10.10.40.62 (host) -> mediagenda-recette/mediagenda-api-…:8000 Policy denied by denylist DROPPED (TCP Flags: SYN)
# Variante 2 : la Gateway (identité réservée « ingress ») vers l'API, faute d'autorisation
… ingress (ID:8) -> mediagenda-recette/mediagenda-api-…:8000 (ID:31842) policy-verdict:none INGRESS DENIED (TCP Flags: SYN)
# Variante 3 : l'API vers PostgreSQL, en sortie
… mediagenda-recette/mediagenda-api-…:41762 (ID:31842) -> mediagenda-recette/postgresql-0:5432 (ID:19077) policy-verdict:none EGRESS DENIED (TCP Flags: SYN)
```

Lis trois choses : la **direction** (`INGRESS`/`EGRESS`), la raison (`denylist` = un refus explicite ; `policy-verdict:none` = aucune autorisation), les **identités** de part et d'autre. L'identité `ingress` (réservée, n° 8) est celle d'Envoy de la Gateway de Cilium : c'est elle que E17 autorise vers l'API, pas un pod de `passerelles`.

**Étape 2 — Les politiques qui sélectionnent le pod.**

```
admin@adm01:~$ kubectl -n mediagenda-recette get netpol,cnp ; kubectl get ccnp
admin@adm01:~$ kubectl -n mediagenda-recette get pods --show-labels
admin@adm01:~$ kubectl -n kube-system exec <agent-du-nœud-de-l-api> -c cilium-agent -- cilium-dbg endpoint list | grep mediagenda-api
1234   Enabled  Enabled   31842   k8s:app.kubernetes.io/name=mediagenda-api …   10.240.3.17   ready
admin@adm01:~$ kubectl -n kube-system exec <agent> -c cilium-agent -- cilium-dbg bpf policy get 1234
POLICY   DIRECTION   LABELS (source:key[=value])                  PORT/PROTO   PROXY PORT   AUTH TYPE   BYTES   PACKETS   PREFIX
Allow    Ingress     reserved:ingress                             8000/TCP     NONE         disabled    …                 # absente en v2
Deny     Ingress     reserved:all                                 ANY          NONE         disabled    …                 # v1
Allow    Egress      k8s:app.kubernetes.io/name=postgresql …      5432/TCP     …                                           # devenue 6432 en v3
```

**Variante 1 — `quarantaine`.** Une CNP `ingressDeny: fromEntities: [all]` sur `endpointSelector: {}` : **tout** ce qui entre dans un pod de l'espace est refusé, y compris les sondes du kubelet (entité `host`) ; les pods deviennent non prêts, la Gateway n'a plus de destination. L'annotation dit d'où elle vient (le modèle d'isolement d'incident de Sophie) : elle a été appliquée dans le mauvais espace. **Variante 2 — sélecteur changé.** Une autorisation (celle qui vise l'API) a un `podSelector` (ou `endpointSelector`) suffixé `-v2` : elle ne sélectionne plus rien, elle n'apparaît dans aucun verdict, et le `refus-par-defaut` s'applique seul. **Variante 3 — port 6432.** Les règles de port 5432 sont devenues 6432 (« préparation du pooler », qui n'existe pas encore) : l'API ne joint plus PostgreSQL, `/pret` passe en 503, les pods deviennent non prêts.

Les connexions établies tombent elles aussi : Cilium évalue la politique pour chaque paquet qui n'est pas une réponse, pas seulement à l'ouverture (contrairement à ce que beaucoup supposent) ; l'application voit ses connexions à PostgreSQL expirer.

**Correctif**
- V1 : `kubectl -n mediagenda-recette delete cnp quarantaine` **après** accord de Sophie (c'est un objet de sécurité), puis revue avec elle : le modèle d'isolement doit viser un pod par étiquette (`medisphere.internal/quarantaine: oui`), jamais `{}`, et être posé par une procédure (runbook de réponse à incident, M26).
- V2 et V3 : réappliquer les politiques du dépôt (`kubectl diff -f` montre l'écart) ; si le dépôt contient l'erreur (MR de Lucas fusionnée), corriger par MR.
- Vérifier : `hubble observe --namespace mediagenda-recette --verdict DROPPED` ne montre plus que les flux qui doivent être refusés ; `/pret` stable ; le témoin vers l'API toujours refusé.

*Question de l'étape 5* : une NetworkPolicy « tout autoriser » n'aurait rien changé en variante 1 (un refus l'emporte) ; dans tous les cas elle aurait supprimé l'isolement exigé par HDS pour un espace qui porte des données de santé, sans dire quelle règle manquait. On répare la règle, on n'ouvre pas l'espace.

**Prévention** : test de non-régression des politiques dans le pipeline de `plateforme/k8s` (flux attendus et interdits de la matrice, M15-E32) ; alerte sur la hausse brutale des `DROPPED` par espace (métrique Hubble `hubble_drop_total`, M21) ; les politiques de refus et de quarantaine relues par la RSSI ; les étiquettes utilisées par les politiques fixées dans un contrat d'étiquettes (`app.kubernetes.io/name`, `medisphere.internal/role`) que le chart (M17) respecte.

**Explications**

Le modèle de Kubernetes est **additif** : un pod non sélectionné par aucune politique est ouvert ; dès qu'une politique le sélectionne dans une direction, cette direction devient « tout refuser sauf l'union des autorisations ». Cilium ajoute les refus explicites (`ingressDeny`, `egressDeny`), évalués **avant** les autorisations, et les politiques de cluster. Une politique dont le sélecteur ne correspond à rien est valide et silencieuse : c'est la panne la plus difficile à voir, parce qu'aucun verdict ne la cite ; seule la comparaison « politique → pods sélectionnés » la révèle. Cilium traduit tout en **identités** : les étiquettes du pod (et de son espace) donnent un numéro d'identité, et la table de politique du point de terminaison contient des couples (identité, port, direction).

**Alternatives**
- Politiques par CNP uniquement (sélecteurs riches, L7, entités) ou par NetworkPolicy standard uniquement (portables, comprises par tous les outils) : MédiSphère garde le `refus-par-defaut` en standard (lisible par n'importe quel auditeur et indépendant du CNI) et les règles fines en CNP.
- Politiques générées depuis la matrice des flux (un fichier, un générateur) : supprime l'écart entre la documentation et la réalité, au prix d'un outil à maintenir.

**Pièges classiques**
- Supprimer la politique de refus par défaut (`refus-par-defaut`) « pour tester » : interdit par le ticket, et le test ne dit rien de la règle qui manque.
- Ne regarder que l'entrée : la variante 3 est un refus en **sortie**, côté API.
- Chercher le pod de la Gateway dans les verdicts : avec Cilium, l'identité source est `ingress`, pas un pod.
- Oublier les CCNP (`kubectl get ccnp`) : elles ne sont pas dans l'espace.

**En production chez MédiSphère**
Les politiques sont du code relu (MR, test de flux), l'isolement d'incident est une procédure outillée, et Hubble est la première source de vérité pendant un incident : ses métriques et ses flux sont conservés (M21-M22) pour le post-mortem.

---

### M15-E38 — Panne : l'adresse du LoadBalancer est injoignable

**Démarche de diagnostic**

*Symptômes* : variante 1, un nouveau Service reste en `<pending>`, le reste fonctionne ; variantes 2 à 4, plus aucune adresse de 10.10.41.0/24 ne répond depuis `adm01` (délai dépassé), alors que depuis un nœud `curl -k https://10.10.41.10` répond ; variante 5, rien de visible pour les utilisateurs, mais la passerelle de secours n'a plus de route vers les services.

*Hypothèses*, dans l'ordre du chemin : attribution (pool désactivé, épuisé, sélecteur de Service, conflit) → sélection des nœuds BGP → sessions (AS, adresse, mot de passe, pare-feu, port 179) → annonces (ce que Cilium annonce) → politique d'entrée de la bordure → installation dans le noyau des passerelles → routage de retour.

**Étape 1 — Attribution.**

```
admin@adm01:~$ kubectl get svc -A --field-selector spec.type=LoadBalancer
NAMESPACE    NAME                     TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)
passerelles  cilium-gateway-gw-par1   LoadBalancer   10.96.112.40   10.10.41.10   80:3…/TCP,443:3…/TCP
wb-pannes    temoin-lb                LoadBalancer   10.96.201.9    <pending>     8080:3…/TCP        # v1
admin@adm01:~$ kubectl get ciliumloadbalancerippool
NAME      DISABLED   CONFLICTING   IPS AVAILABLE   AGE
lb-par1   true       False         186             20d                                         # v1
admin@adm01:~$ kubectl -n wb-pannes get svc temoin-lb -o jsonpath='{.status.conditions}' | jq -c '.[]'
{"type":"io.cilium/lb-ipam-request-satisfied","status":"False","reason":"no_pool","message":"There are no enabled CiliumLoadBalancerIPPools that match this service"}
```

**Variante 1 — pool désactivé.** `disabled: true` arrête les **nouvelles** attributions et garde les anciennes (comportement documenté) : rien ne casse… jusqu'au prochain Service, ou jusqu'à ce qu'un Service existant soit recréé et perde son adresse. C'est une panne latente, révélée ici par le témoin. (L'épuisement se lit sur la colonne `IPS AVAILABLE` et la même condition, raison `out_of_ips` selon la version.)

**Étape 2 — Sessions et annonces, côté Cilium.**

```
admin@adm01:~$ cilium bgp peers
Node       Local AS   Peer AS   Peer Address   Session State   Uptime   Family         Received   Advertised
k8s-w01    65040      65000     10.10.40.2     established     3h2m     ipv4/unicast   0          4
k8s-w01    65040      65000     10.10.40.3     established     3h2m     ipv4/unicast   0          4
…
# v2 : sessions établies, Advertised = 0
# v3 : aucune ligne (aucun nœud ne parle BGP)
# v4 : Local AS 64040, état « active » ou « connect », uptime 0
admin@adm01:~$ cilium bgp routes advertised ipv4 unicast
admin@adm01:~$ kubectl get ciliumbgpnodeconfigs
No resources found                                       # v3
admin@adm01:~$ kubectl get ciliumbgpclusterconfig bgp-par1 -o yaml | yq '.spec'
nodeSelector:
  matchLabels:
    bgp: PAR1                                            # v3 : les nœuds portent bgp=par1
bgpInstances:
- name: par1
  localASN: 64040                                        # v4
admin@adm01:~$ kubectl get ciliumbgpadvertisements -o yaml | yq '.items[].spec.advertisements'
- advertisementType: Service
  service:
    addresses:
    - ExternalIP                                         # v2 : au lieu de LoadBalancerIP
```

**Étape 3 — Côté bordure (sur les deux passerelles, en lecture).**

```
admin@gw01:~$ sudo vtysh -c 'show bgp summary'
Neighbor        V   AS   MsgRcvd MsgSent  Up/Down State/PfxRcd PfxSnt Desc
*10.10.40.61    4 65040     2210    2207 03:02:11            4 (Policy)
…                                                         # v4 : Neighbor absent ou « Active »
admin@gw01:~$ sudo vtysh -c 'show bgp neighbors 10.10.40.61' | grep -iA2 'notification\|last reset'
  Last reset 00:01:12,  Notification sent (OPEN Message Error/Bad Peer AS)           # v4
admin@gw01:~$ sudo journalctl -u frr --since -15min | grep -i 'bad peer\|65040'
admin@gw01:~$ ip -4 route show proto bgp | grep 10.10.41
10.10.41.10 nhid 61 proto bgp metric 20
	nexthop via 10.10.40.61 dev ens19.40 weight 1
	nexthop via 10.10.40.62 dev ens19.40 weight 1
	nexthop via 10.10.40.63 dev ens19.40 weight 1      # sain : une /32, trois chemins (ECMP)
```

Le `*` devant l'adresse signale un voisin **dynamique** (plage d'écoute `bgp listen range`) ; `PfxSnt (Policy)` rappelle que `RM-K8S-OUT` refuse tout envoi, comme prévu. **Variante 4** : la bordure attend l'AS 65040 pour la plage K8S ; l'OPEN arrive avec 64040, FRR répond par une NOTIFICATION *Bad Peer AS* et la session ne monte jamais. **Variantes 2 et 3** : la passerelle n'apprend plus rien (aucune annonce, ou aucun voisin), et retire les routes **après** le délai de redémarrage gracieux, ce qui explique la panne « qui arrive deux minutes après le changement ».

**Variante 5 — la passerelle de secours.**

```
admin@gw02:~$ ip -4 route show proto bgp | grep -c 10.10.41
0
admin@gw02:~$ sudo vtysh -c 'show bgp ipv4 unicast summary' | grep 10.10.40.6
*10.10.40.61    4 65040  …   03:05:40            0 (Policy)     # sessions établies, 0 préfixe accepté
admin@gw02:~$ sudo vtysh -c 'show ip prefix-list PL-DEPUIS-K8S'
ZEBRA: ip prefix-list PL-DEPUIS-K8S: 1 entries
   seq 10 permit 10.10.41.0/24
BGP: ip prefix-list PL-DEPUIS-K8S: 1 entries
   seq 10 permit 10.10.41.0/24                               # « le 32 » a disparu
admin@gw02:~$ diff <(sudo vtysh -c 'show running-config' | sed '1,/^!/d') <(sudo sed '1,/^!/d' /etc/frr/frr.conf)
<  ip prefix-list PL-DEPUIS-K8S seq 10 permit 10.10.41.0/24
>  ip prefix-list PL-DEPUIS-K8S seq 10 permit 10.10.41.0/24 le 32
admin@gw02:~$ sudo journalctl -u frr --since -1d | grep -i 'vtysh\|config'   # trace de la modification à chaud, si journalisée
```

`permit 10.10.41.0/24` sans `le 32` n'accepte **que** le préfixe /24 exact ; les nœuds annoncent des /32 : tout est refusé, sans erreur. La configuration courante diffère du fichier généré par Ansible : quelqu'un a modifié FRR à chaud (`vtysh` interactif), sans l'écrire. Tant que `gw01` est maître, aucun utilisateur ne s'en aperçoit ; à la maintenance de jeudi, la VIP passerait sur `gw02`… sans aucune route vers Kubernetes. On le prouve **sans** basculer, en lisant la table de `gw02`.

**Correctif**
- V1 : `disabled: false` (ou retrait du champ) dans `plateforme/k8s/composants/cilium/lb-ipam.yaml`, `task appliquer` ; le témoin reçoit une adresse en quelques secondes.
- V2 à V4 : objets BGP du dépôt réappliqués (`kubectl diff -f composants/cilium/bgp/` montre l'écart) ; si la MR fautive est dans le dépôt, MR de correction. Vérifier `cilium bgp peers` (deux sessions établies par nœud sélectionné, préfixes annoncés), puis les deux passerelles.
- V5 : rejouer `playbooks/bordure-frr.yml` sur `gw02` (le rôle génère le fichier et fait un `reload` : seules les différences sont appliquées, aucune session ne tombe) ; vérifier que `diff` ne montre plus rien et que `ip route` contient les /32.
- Partout : `nc -zv 10.10.41.10 443` depuis `adm01`, `/pret` en 200.

**Prévention** : RB-152 complété d'une section de diagnostic ([extrait](fichiers/M15-E38/medisphere/docs/kubernetes/reseau/runbooks/RB-152-extrait-diagnostic.md)) ; dans `ms-verif-k8s-reseau` : sessions par passerelle, nombre de /32 reçus par passerelle **et par nœud**, Services en `<pending>`, condition du pool ; dans la sonde de la bordure (M07-E29) : écart entre configuration courante et fichier (`derive-bordure-noeuds.sh --bordure`) ; droits : plus personne n'a de `vtysh` en écriture hors bris de glace (le groupe `frrvty` réservé au compte d'automatisation).

**Explications**

LB IPAM attribue, BGP annonce, la bordure accepte et installe, le noyau route : quatre décisions indépendantes, quatre endroits où la panne se cache. Le plan de contrôle BGP v2 de Cilium découpe aussi la configuration en quatre objets : `CiliumBGPClusterConfig` (quels nœuds, quelle instance, quels voisins), `CiliumBGPPeerConfig` (temporisateurs, redémarrage gracieux, familles et **sélecteur d'annonces**), `CiliumBGPAdvertisement` (quoi annoncer) et, produit par l'opérateur, `CiliumBGPNodeConfig` (la configuration effective de chaque nœud, à lire en premier quand rien ne se passe). Côté bordure, `bgp ebgp-requires-policy` impose des politiques explicites ; une liste de préfixes trop stricte refuse sans bruit, d'où l'intérêt de `show bgp … received-routes` (avec `soft-reconfiguration inbound`, activée le temps du diagnostic) pour voir ce qui arrive **avant** la politique.

**Alternatives**
- Annonces en L2 (`CiliumL2AnnouncementPolicy`, ARP) au lieu de BGP : pas de bordure à configurer, mais un seul nœud répond par adresse (pas d'ECMP) et la bascule dépend d'un bail ; écarté par l'ADR-0150.
- Annonce du /24 agrégé plutôt que des /32 : moins de routes, mais la bordure enverrait le trafic à un nœud qui n'a peut-être pas de backend local (`externalTrafficPolicy: Local` impossible).
- Mot de passe TCP-MD5 (ou TCP-AO) sur les sessions : ajoute une authentification ; il faut alors gérer le Secret côté Cilium (`authSecretRef`) et la clé côté bordure (Vault `lab`), et une rotation coordonnée.

**Pièges classiques**
- Basculer la VIP « pour voir » : coupe les tunnels et toutes les sessions de l'atelier, et ne prouve rien qu'une lecture de table ne prouve déjà.
- `systemctl restart frr` : toutes les sessions (Lyon, Kubernetes) tombent ; `reload` suffit.
- Regarder une seule passerelle.
- Croire que le pool désactivé « coupe » les services existants, ou à l'inverse qu'il est sans conséquence.
- Corriger l'étiquette des nœuds pour qu'elle corresponde au sélecteur fautif : le dépôt (M14 : étiquettes posées par Ansible) la remettra.

**En production chez MédiSphère**
BFD entre nœuds et bordure pour une détection sous la seconde, redémarrage gracieux court et justifié (ADR-0150), plafond de préfixes par voisin, authentification des sessions, supervision du nombre de préfixes et des écarts de configuration, et une procédure de maintenance de bordure qui commence par vérifier la table de la passerelle qui va devenir maître.

---

### M15-E39 — Panne : la Gateway refuse le HTTPS

**Démarche de diagnostic**

*Symptômes* : variantes 1 et 2, toutes les applications publiées en HTTPS échouent dès la négociation (le port 443 accepte la connexion TCP, puis la coupe), le port 80 redirige toujours ; variante 3, MédiAgenda recette répond 404 avec un certificat valide, les autres applications répondent.

*Hypothèses* : certificat absent, mal référencé ou expiré ; écouteur refusé ou non programmé ; route refusée par l'écouteur (espace non admis, nom hors du joker, type de route non admis) ; référence croisée sans `ReferenceGrant` ; problème d'Envoy (agent Cilium) — écarté si d'autres écouteurs fonctionnent.

**Étape 1 — Reproduire au bon étage.**

```
admin@adm01:~$ openssl s_client -connect 10.10.41.10:443 -servername mediagenda-recette.apps.par1.medisphere.internal -brief </dev/null
Connecting to 10.10.41.10
40E7…:error:0A000126:SSL routines::unexpected eof while reading      # v1, v2 : aucun certificat présenté
CONNECTION ESTABLISHED                                                 # v3
Protocol version: TLSv1.3
Peer certificate: CN = *.apps.par1.medisphere.internal
Verification: OK
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://mediagenda-recette.apps.par1.medisphere.internal/sante
404                                                                    # v3
```

**Étape 2 — L'état de la Gateway, écouteur par écouteur.**

```
admin@adm01:~$ kubectl -n passerelles get gateway gw-par1 -o json | jq -c '.status.listeners[] | {name, attachedRoutes, c: [.conditions[] | {type,status,reason}]}'
{"name":"http","attachedRoutes":1,"c":[{"type":"Accepted","status":"True",…},{"type":"ResolvedRefs","status":"True",…},{"type":"Programmed","status":"True",…}]}
{"name":"https","attachedRoutes":4,"c":[…,{"type":"ResolvedRefs","status":"False","reason":"InvalidCertificateRef"},{"type":"Programmed","status":"False","reason":"Invalid"}]}   # v1
{"name":"https","attachedRoutes":4,"c":[…,{"type":"ResolvedRefs","status":"False","reason":"RefNotPermitted"},…]}                                                            # v2
admin@adm01:~$ kubectl -n passerelles get gateway gw-par1 -o jsonpath='{.spec.listeners[?(@.protocol=="HTTPS")].tls.certificateRefs}'
[{"group":"","kind":"Secret","name":"apps-joker-tls"}]                 # v1 : le Secret s'appelle apps-joker
[{"group":"","kind":"Secret","name":"apps-joker","namespace":"cert-manager"}]   # v2
admin@adm01:~$ kubectl -n passerelles get certificate apps-joker -o jsonpath='{.spec.secretName}'
apps-joker
admin@adm01:~$ kubectl -n passerelles get secret apps-joker-tls
Error from server (NotFound): secrets "apps-joker-tls" not found
```

(Noms du corrigé de M15-E12/E14 : Certificate et Secret `apps-joker` ; la variante 1 vise un nom voisin inexistant, `apps-joker-tls` « à la mode des tutoriels ».)

**Variante 1 — Secret absent.** L'écouteur référence un Secret qui n'existe pas : `ResolvedRefs=False/InvalidCertificateRef`, écouteur non programmé, Envoy n'a pas de chaîne de filtres TLS pour ces noms et coupe. **Variante 2 — mauvais espace.** La référence vise `cert-manager` sans `ReferenceGrant` : `RefNotPermitted` (et, de toute façon, le Secret n'y est pas). Le port 80 fonctionne dans les deux cas : c'est un autre écouteur.

**Variante 3 — route refusée par l'écouteur.**

```
admin@adm01:~$ kubectl -n mediagenda-recette get httproute mediagenda -o json | jq -c '.status.parents[] | {p: .parentRef.name, c: [.conditions[] | {type,status,reason}]}'
{"p":"gw-par1","c":[{"type":"Accepted","status":"False","reason":"NotAllowedByListeners"},…]}
admin@adm01:~$ kubectl -n passerelles get gateway gw-par1 -o jsonpath='{.spec.listeners[?(@.name=="https")].allowedRoutes}'
{"namespaces":{"from":"Selector","selector":{"matchLabels":{"medisphere.internal/exposition":"oui"}}}}
admin@adm01:~$ kubectl get ns mediagenda-recette --show-labels
NAME                 STATUS   AGE   LABELS
mediagenda-recette   Active   30d   kubernetes.io/metadata.name=mediagenda-recette,pod-security.kubernetes.io/enforce=restricted,…   # plus d'étiquette d'exposition
admin@adm01:~$ kubectl get ns mediagenda-recette -o yaml --show-managed-fields | grep -B3 -A8 'manager: kubectl-'
```

L'espace a perdu `medisphere.internal/exposition: oui` : l'écouteur n'admet plus ses routes, Envoy n'a pas de route pour ce nom et répond 404 (le certificat joker, lui, est servi). Selon ta configuration d'ExternalDNS, le nom peut aussi disparaître de la zone au cycle suivant (une route non acceptée n'est plus une source) : c'est une conséquence, pas une deuxième panne.

**Correctif** : V1 et V2, réappliquer la Gateway du dépôt (référence au Secret `apps-joker` de `passerelles`) ; V3, réappliquer la définition de l'espace (`plateforme/k8s/espaces/`), ce qui remet l'étiquette. Vérifier : conditions toutes `True`, `attachedRoutes` revenu à sa valeur, `openssl s_client … Verification: OK`, `/sante` en 200, `curl -I http://…` en 301/308, et les autres applications publiées.

*Question de l'étape 5* : un `ReferenceGrant` dans `cert-manager` qui autorise les Gateway de `passerelles` à lire ses Secrets ouvrirait **tous** les Secrets de cet espace (dont la clé du compte ACME de l'émetteur) à quiconque peut modifier une Gateway ; la frontière d'espace est exactement ce que la Gateway API protège. Le certificat d'un écouteur vit avec la Gateway.

**Prévention** : contrôle « toutes les conditions de toutes les Gateway et routes à `True` » dans `ms-verif-k8s-reseau`, avec la raison ; étiquettes d'espace posées par le seul dépôt (et VAP ou Kyverno au M26 qui refuse leur retrait hors du compte d'automatisation) ; test synthétique HTTPS (nom, certificat, code) par application publiée.

**Explications**

La Gateway API sépare les rôles : l'équipe Plateforme possède la Gateway (adresse, écouteurs, certificats, quels espaces peuvent s'y attacher), les équipes possèdent leurs routes. Le lien est **à double sens** : la route demande un parent (`parentRefs`), l'écouteur l'accepte ou non (`allowedRoutes` : espaces, types, et intersection des noms). Les références entre espaces (route → Service d'un autre espace, Gateway → Secret d'un autre espace) exigent un `ReferenceGrant` posé **par le propriétaire de la cible**. Chaque refus est écrit dans une condition à raison normalisée : c'est l'interface de diagnostic de l'API.

**Alternatives**
- Un certificat par application (HTTP-01 ou DNS-01 par nom) plutôt qu'un joker : une clé compromise n'expose qu'un nom, au prix d'un écouteur (ou d'un `ListenerSet`, canal expérimental) par nom ; le joker est le compromis de l'ADR-0150 pour la zone `apps`.
- Admission par `from: All` : plus simple, mais n'importe quel espace pourrait publier n'importe quel nom de la zone ; refusé par Sophie.

**Pièges classiques**
- Poser un certificat à la main dans un Secret du bon nom : interdit par le ticket, et cert-manager l'écraserait (ou ne le renouvellerait jamais).
- Créer un `ReferenceGrant` pour « faire passer » la variante 2.
- Lire les seules conditions globales de la Gateway (`Accepted`, `Programmed` peuvent rester `True` quand un seul écouteur est cassé, selon l'implémentation).
- Tester sans SNI (`openssl s_client` sans `-servername`) : Envoy choisit l'écouteur par le nom présenté.

**En production chez MédiSphère**
Supervision des conditions et de l'expiration des certificats présentés (pas seulement des objets), séparation des droits (seuls les comptes de la plateforme modifient Gateway et étiquettes d'espace), et revue de chaque nouvel écouteur.

---

### M15-E40 — Panne : le certificat n'est jamais délivré

**Démarche de diagnostic**

*Symptômes* : `wb-essais/joker-repetition` reste `READY False` ; selon la variante, le `Challenge` reste en attente avec une erreur de mise à jour DNS (v1), l'émetteur lui-même n'est plus prêt (v2), aucun `Challenge` n'est créé et l'`Order` échoue (v3), ou même pas de `CertificateRequest` approuvée (v4).

*Hypothèses* par étage : `Certificate` (spécification, émetteur référencé) → `CertificateRequest` (approbation, émetteur trouvé) → émetteur (compte ACME, confiance TLS vers `ca01`) → `Order` (identifiants, autorisations) → `Challenge` (solveur choisi, présentation du défi, propagation, validation par `ca01`) → horloge et quotas.

**Étape 1 — Descendre la chaîne.**

```
admin@adm01:~$ kubectl -n wb-essais get certificate,certificaterequest,order,challenge
NAME                                           READY   SECRET                  AGE
certificate.cert-manager.io/joker-repetition   False   joker-repetition-tls    18m
NAME                                                    APPROVED   DENIED   READY   ISSUER         AGE
certificaterequest.cert-manager.io/joker-repetition-1   True                False   step-ca-acme   18m
NAME                                                    STATE     AGE
order.acme.cert-manager.io/joker-repetition-1-28…       pending   18m       # v1
order.acme.cert-manager.io/joker-repetition-1-28…       errored   17m       # v3
NAME                                                              STATE     DOMAIN                          AGE
challenge.acme.cert-manager.io/joker-repetition-1-28…-1735…      pending   apps.par1.medisphere.internal   18m   # v1
admin@adm01:~$ kubectl -n wb-essais describe challenge joker-repetition-1-28…-1735… | sed -n '/Status:/,$p'
  Presented:   false
  Processing:  true
  Reason:      error instantiating rfc2136 challenge solver: … dns: bad authentication   # ou NOTAUTH / tsig verify failure
```

**Variante 1 — TSIG.** Côté autoritaire :

```
admin@dns01:~$ sudo journalctl -u pdns --since -10min | grep -i 'update\|tsig' | tail -3
… Packet for 'apps.par1.medisphere.internal' denied: Signature with TSIG key 'certmanager' not allowed      # formulation à vérifier
… TSIG key 'certmanager' for domain 'apps.par1.medisphere.internal' not found
admin@dns01:~$ sudo -u pdns pdnsutil metadata get apps.par1.medisphere.internal TSIG-ALLOW-DNSUPDATE
TSIG-ALLOW-DNSUPDATE = externaldns-k8s, certmanager-k8s
admin@adm01:~$ kubectl get clusterissuer step-ca-acme -o jsonpath='{.spec.acme.solvers[*].dns01.rfc2136}' | jq
{"nameserver":"10.10.20.10:5300","tsigAlgorithm":"HMACSHA256","tsigKeyName":"certmanager","tsigSecretSecretRef":{"key":"secret","name":"tsig-certmanager-k8s"}}
```

La clé s'appelle `certmanager-k8s` côté PowerDNS ; l'émetteur signe avec un nom de clé inconnu : la mise à jour est refusée, le défi n'est jamais présenté. (Un secret faux sous le bon nom donne un refus de signature, `BADSIG`, que tu distingues de la même façon.)

**Variante 2 — `caBundle`.**

```
admin@adm01:~$ kubectl describe clusterissuer step-ca-acme | sed -n '/Conditions:/,$p'
    Message:  Failed to verify ACME account: Get "https://ca01.par1.medisphere.internal/acme/acme/directory": tls: failed to verify certificate: x509: certificate signed by unknown authority
    Reason:   ErrRegisterACMEAccount
    Status:   False
    Type:     Ready
admin@adm01:~$ kubectl get clusterissuer step-ca-acme -o jsonpath='{.spec.acme.caBundle}' | base64 -d | openssl x509 -noout -subject -fingerprint -sha256
subject=O=MediSphere, CN=MediSphere CA provisoire
sha256 Fingerprint=3A:…
admin@adm01:~$ openssl x509 -in /usr/local/share/ca-certificates/medisphere-root-ca.crt -noout -subject -fingerprint -sha256
subject=… CN=MédiSphère Root CA …
sha256 Fingerprint=9F:…                                   # différente
```

La CA de confiance de l'émetteur n'est plus la racine MédiSphère : c'est une « CA provisoire » (celle des modules 01 à 06, retirée au M06 et régénérée ici). cert-manager ne peut plus parler à `ca01`.

**Variante 3 — sélecteur du solveur.**

```
admin@adm01:~$ kubectl -n wb-essais describe order joker-repetition-1-28… | grep -A3 Reason
  Reason:  Failed to determine a valid solver configuration for the set of domains on the Order: no configured challenge solvers can be used for this challenge
admin@adm01:~$ kubectl get clusterissuer step-ca-acme -o json | jq '.spec.acme.solvers[] | {selector, type: (keys - ["selector"])}'
{"selector":{"dnsZones":["app.par1.medisphere.internal"]},"type":["dns01"]}      # « app » au lieu de « apps »
{"selector":null,"type":["http01"]}
```

cert-manager choisit, pour chaque nom, le solveur dont le sélecteur est le plus précis ; `app.par1…` ne couvre pas `*.apps.par1…`, le seul candidat restant est HTTP-01, qui ne valide pas un joker : aucun solveur utilisable. Un nom simple (`x.apps…`) serait passé par HTTP-01 : la panne ne touche que les jokers… c'est-à-dire, à l'échéance, le renouvellement d'`apps-joker`.

**Variante 4 — émetteur introuvable.**

```
admin@adm01:~$ kubectl -n wb-essais get certificate joker-repetition -o jsonpath='{.spec.issuerRef}'
{"name":"step-ca-acme"}                                         # pas de « kind » : Issuer par défaut
admin@adm01:~$ kubectl -n wb-essais describe certificaterequest joker-repetition-1 | grep -A2 Reason
  Reason:  Pending … Referenced "Issuer" not found: issuer.cert-manager.io "step-ca-acme" not found
```

Sans `kind`, `issuerRef` désigne un `Issuer` **de l'espace**. Ici l'erreur est dans la demande de Karim (le témoin), pas dans l'émetteur ; la correction est dans le `Certificate` (`kind: ClusterIssuer`).

**Écarter l'horloge et les quotas** : `timedatectl` sur un nœud et sur `ca01` (synchronisés sur la passerelle, M00) ; un écart d'horloge se manifeste par des certificats « pas encore valides » ou des jetons JWS refusés (`badNonce`, `unauthorized`), pas par un défi DNS refusé. step-ca n'applique pas de quota par défaut (contrairement à Let's Encrypt, dont les limites — 50 certificats par domaine enregistré et par semaine, 5 doublons par semaine — se lisent dans la raison de l'`Order` : `rateLimited`) ; une boucle de redemandes peut en revanche remplir la base de `ca01` : `kubectl get certificaterequests -A | wc -l` le dit.

**Correctif** : V1 à V3, émetteur du dépôt réappliqué (`kubectl diff -f composants/cert-manager/clusterissuer.yaml` montre l'écart) ; V4, `kind: ClusterIssuer` ajouté au `Certificate`. cert-manager réessaie seul avec un délai croissant ; pour relancer proprement : `cmctl renew -n wb-essais joker-repetition` (si `cmctl` est installé), ou suppression de la `CertificateRequest` en échec (jamais du Secret d'un certificat en service). Vérifier : `READY True` en moins de deux minutes, `dig +norec -p 5300 @10.10.20.10 _acme-challenge.apps.par1.medisphere.internal TXT` vide après coup (nettoyage), `apps-joker` toujours prêt.

**Prévention** : RB-151 ([modèle](fichiers/M15-E40/medisphere/docs/kubernetes/reseau/runbooks/RB-151-certificat-non-delivre.md)) ; test ACME de bout en bout hebdomadaire (DNS-01 **et** HTTP-01, jetable) ; alerte sur `certmanager_certificate_ready_status{condition="False"}` et sur l'expiration à moins de 21 jours (M21) ; `caBundle` construit depuis le **même** fichier que la racine installée par Ansible (une seule source).

**Explications**

cert-manager découpe une émission en objets successifs, chacun avec son état et sa raison : lire la chaîne de haut en bas donne l'étage en panne sans ouvrir un journal. DNS-01 par RFC 2136 suppose quatre choses : la bonne clé (nom, algorithme, secret), le droit de la clé sur la zone (`TSIG-ALLOW-DNSUPDATE`), le droit de l'adresse source (`ALLOW-DNSUPDATE-FROM` 10.10.40.0/24 : les pods sortent par l'adresse du nœud, masquée par Cilium) et la propagation (cert-manager vérifie la présence du TXT sur les autoritaires avant de demander la validation). La confiance TLS envers l'ACME interne n'est **pas** celle des nœuds : c'est le `caBundle` de l'émetteur.

**Alternatives**
- `trust-manager` pour distribuer la racine MédiSphère dans le cluster (un seul objet source) ; utile quand plusieurs composants (cert-manager, applications) doivent faire confiance à la même CA.
- Solveur DNS-01 par webhook PowerDNS (API) : écarté (clé d'API de tout le serveur, PLAN §4.10).

**Pièges classiques**
- Supprimer le Secret du joker pour « forcer » : le service perd son certificat jusqu'à la réémission, qui échoue pour la même raison.
- Afficher le Secret TSIG dans le journal ou le ticket.
- Chercher l'erreur dans le `Certificate` alors que la raison est trois objets plus bas.
- Corriger la clé côté PowerDNS (renommer `certmanager-k8s`) au lieu de l'émetteur : ExternalDNS, qui utilise l'autre clé, n'est pas touché, mais le dépôt et le registre des secrets deviennent faux.

**En production chez MédiSphère**
Deux émetteurs (ACME interne et un émetteur de secours documenté), supervision des expirations et des échecs, renouvellement à mi-vie (cert-manager renouvelle aux deux tiers par défaut), et ARI dès que step-ca le propose, pour que la CA puisse demander un renouvellement anticipé.

---

### M15-E41 — Panne : le nom n'est plus publié

**Démarche de diagnostic**

*Symptômes* : variantes 1 et 3, la route témoin est acceptée mais son nom n'apparaît jamais (`NXDOMAIN`), les noms existants résolvent ; variante 2, le nom d'une route supprimée reste publié.

*Hypothèses* : ExternalDNS arrêté ou en erreur ; il ne voit pas la route (source absente, droits RBAC, route non acceptée, filtre d'annotation) ; il la voit mais l'écarte (filtre de domaine, propriété) ; il essaie mais la mise à jour est refusée (clé TSIG, zone) ; le secondaire n'est pas à jour.

**Étape 1 — La zone.**

```
admin@adm01:~$ dig +short +norec -p 5300 @10.10.20.10 temoin-dns.apps.par1.medisphere.internal          # v1, v3 : rien
admin@adm01:~$ dig +short +norec -p 5300 @10.10.20.10 a-mediagenda-recette.apps.par1.medisphere.internal TXT
"heritage=external-dns,external-dns/owner=k8s-par1,external-dns/resource=httproute/mediagenda-recette/mediagenda"
admin@adm01:~$ dig +short +norec -p 5300 @10.10.20.10 a-temoin-dns.apps.par1.medisphere.internal TXT    # v2 : le TXT orphelin, propriétaire k8s-par1
```

**Étape 2 — ExternalDNS.**

```
admin@adm01:~$ kubectl -n external-dns logs deploy/external-dns --since=10m | tail
# v1
time="…" level=info msg="All records are already up to date"
admin@adm01:~$ kubectl -n external-dns get deploy external-dns -o jsonpath='{.spec.template.spec.containers[0].args}' | jq -r '.[]'
--domain-filter=app.par1.medisphere.internal          # v1
--txt-owner-id=k8s-par2                               # v2
# v3
time="…" level=error msg="failed to sync *v1.HTTPRoute: … httproutes.gateway.networking.k8s.io is forbidden: User \"system:serviceaccount:external-dns:external-dns\" cannot list resource \"httproutes\" …"
admin@adm01:~$ kubectl auth can-i list httproutes.gateway.networking.k8s.io --as=system:serviceaccount:external-dns:external-dns
no
```

**Variante 1 — filtre de domaine.** `app.par1…` au lieu de `apps.par1…` : ExternalDNS ne gère plus aucun nom de la zone ; il ne crée plus rien, et ne supprime rien non plus (les noms existants restent, d'où « seuls les nouveaux noms manquent »). **Variante 3 — droits.** La règle du ClusterRole sur `gateway.networking.k8s.io` a disparu : l'informateur ne peut pas lister les routes ; selon la version, ExternalDNS journalise l'erreur en boucle ou s'arrête et redémarre (`CrashLoopBackOff`).

**Variante 2 — propriétaire.** Le nom témoin a été créé par `k8s-par1` ; ExternalDNS tourne maintenant en `k8s-par2` (« copie de la configuration du futur cluster ») : il considère que **tous** les noms existants appartiennent à quelqu'un d'autre, ne les modifie plus et ne les supprime plus. La route a été supprimée : le nom reste, orphelin, pointé vers la Gateway (un nom que l'on peut détourner en créant une route du même nom : c'est le risque soulevé par Sophie). Le niveau `debug` le dit : `Skipping endpoint … because owner id does not match`.

**Correctif** : arguments et ClusterRole du dépôt réappliqués (`helm upgrade` avec les values du dépôt, ou `task appliquer` ; `helm get values external-dns -n external-dns` comparé au fichier). V2 : une fois le propriétaire `k8s-par1` rétabli, ExternalDNS (politique `sync`) supprime de lui-même le A et le TXT orphelins au cycle suivant ; s'il avait fallu le faire à la main :

```
admin@adm01:~/src/ansible$ umask 077; k="$(mktemp -p "$XDG_RUNTIME_DIR")"
admin@adm01:~/src/ansible$ printf 'key "externaldns-k8s" { algorithm hmac-sha256; secret "%s"; };\n' \
  "$(uv run ansible-vault view inventories/lab/group_vars/role_dns/vault-lab.yml | yq -r '.vault_powerdns_tsig_externaldns_k8s')" > "$k"
admin@adm01:~/src/ansible$ nsupdate -k "$k" <<'EOF'
server 10.10.20.10 5300
zone apps.par1.medisphere.internal
update delete temoin-dns.apps.par1.medisphere.internal A
update delete a-temoin-dns.apps.par1.medisphere.internal TXT
send
EOF
admin@adm01:~/src/ansible$ rm -f "$k"
```

(Variable du Vault et fichier de celui de M15-E14 ; le fichier de clé vit en mémoire, dans `$XDG_RUNTIME_DIR`, en 600, le temps de la commande ; `-y` exposerait le secret dans la liste des processus.)  Vérifier : création puis suppression d'une route jetable, nom publié puis retiré en moins de deux minutes sur `dns01` et `dns02`.

**Prévention** : contrôle de cohérence « routes acceptées ⇔ noms publiés » (manquants **et** orphelins) dans `ms-verif-k8s-reseau` ; `txt-owner-id` dérivé du nom du cluster dans les values (une seule variable) et revue des values de tout nouveau cluster ; alerte sur les erreurs d'ExternalDNS (`external_dns_source_errors_total`, `external_dns_registry_errors_total`, M21).

**Explications**

ExternalDNS est une boucle : lire les sources (routes acceptées, Services), calculer les noms voulus, lire la zone, comparer, appliquer le plan. Le registre TXT dit, pour chaque nom, quel ExternalDNS en est propriétaire : il ne modifie et ne supprime que ce qui lui appartient. C'est ce qui permet de partager une zone entre plusieurs clusters, et ce qui fige tout quand l'identifiant change. La politique `sync` supprime ce qui n'a plus de source ; `upsert-only` ne supprime jamais (plus sûr pendant une migration, mais laisse des orphelins à nettoyer).

**Alternatives**
- Un sous-domaine par cluster (`apps.par1…` pour `k8s-par1`, plus tard `apps.par2…`) : chaque ExternalDNS a sa zone et sa clé, le registre TXT devient une sécurité supplémentaire plutôt que la seule frontière ; c'est la recommandation de l'ADR-0150 pour la suite.
- Registre `dynamodb`/`aws-sd` : sans objet ici ; le TXT est le seul registre adapté à RFC 2136.

**Pièges classiques**
- Créer le nom à la main dans la zone : ExternalDNS ne le gérera jamais (pas de TXT), et il deviendra orphelin à son tour.
- Changer `txt-owner-id` pour « repartir de zéro » : tous les noms existants deviennent intouchables.
- Oublier `dns02` : un secondaire en retard (NOTIFY bloqué, AXFR refusé) donne des réponses différentes selon le résolveur.
- Croire que la route acceptée suffit : ExternalDNS doit aussi la **voir** (droits) et la **retenir** (filtres).

**En production chez MédiSphère**
Une zone par cluster, des clés TSIG par composant et par zone, une alerte sur les orphelins, et la politique `sync` avec un garde-fou (ExternalDNS ne supprime que dans sa zone et sous son identifiant).

---

### M15-E42 — Panne : les pods ne se joignent plus entre nœuds

**Démarche de diagnostic**

*Symptômes* : erreurs intermittentes sur MédiAgenda (environ une requête sur trois : celles qu'Envoy, sur un nœud, envoie à un pod d'un autre nœud qui passe par le nœud cassé) ; nœuds `Ready`, pods `Running`.

*Hypothèses* : un nœud dont le chemin de données est cassé (agent Cilium, tunnel, chiffrement, pare-feu du noyau, MTU) ; une politique (écartée : les erreurs suivent un nœud, pas un espace) ; la bordure (écartée : le trafic interne au cluster ne la traverse pas).

**Étape 1 — Matrice de connectivité.**

```
admin@adm01:~$ kubectl -n wb-pannes get pods -o wide
sonde-4xk2p   1/1   Running   10.240.3.41   k8s-w01
sonde-9mfqz   1/1   Running   10.240.4.12   k8s-w02
sonde-tr7wd   1/1   Running   10.240.5.33   k8s-w03
admin@adm01:~$ for p in sonde-4xk2p sonde-9mfqz sonde-tr7wd; do for ip in 10.240.3.41 10.240.4.12 10.240.5.33; do printf '%s → %s : ' $p $ip; kubectl -n wb-pannes exec $p -- sh -c "nc -w 2 $ip 8080 </dev/null || echo ÉCHEC"; done; done
sonde-4xk2p → 10.240.4.12 : ÉCHEC
sonde-9mfqz → 10.240.3.41 : ÉCHEC
sonde-9mfqz → 10.240.5.33 : ÉCHEC
sonde-tr7wd → 10.240.4.12 : ÉCHEC
…                                    # tout ce qui touche k8s-w02 échoue, le reste passe
admin@adm01:~$ kubectl -n kube-system exec <agent-de-k8s-w01> -c cilium-agent -- cilium-health status --probe
Cluster health:   5/6 reachable   (2026-10-…)
  k8s-w02 … Host connectivity to 10.10.40.62: ICMP to stack: OK, HTTP to agent: OK
            Endpoint connectivity to 10.240.4.87: ICMP to stack: Connection timed out, HTTP to agent: Connection timed out
```

Le nœud est joignable (ICMP et HTTP vers l'agent, par l'adresse du nœud) ; ses **points de terminaison** ne le sont pas : c'est le chemin pod à pod (tunnel, chiffrement), pas le nœud.

**Étape 2 — Comparer le nœud cassé et un nœud sain.**

```
admin@adm01:~$ kubectl -n kube-system exec <agent-de-k8s-w02> -c cilium-agent -- cilium-dbg status --verbose | sed -n '/Encryption/,/Cluster health/p'
admin@k8s-w02:~$ ip -d link show cilium_vxlan | grep -o 'vxlan.*dstport [0-9]*'
vxlan external … dstport 8473                           # v2 : 8472 sur les autres nœuds
admin@k8s-w02:~$ ip link show cilium_wg0
12: cilium_wg0: <POINTOPOINT,NOARP> mtu 1405 qdisc noqueue state DOWN …     # v3 : drapeau UP absent
admin@k8s-w02:~$ sudo nft list ruleset | grep -B3 -A3 'dport 8472\|dport 51871'
table inet wb_durcissement {                            # v1
	chain entree {
		type filter hook input priority filter - 5; policy accept;
		udp dport 8472 counter packets 0 bytes 0 drop comment "durcissement InfoGer : ports non documentes"
		udp dport 51871 counter packets 18342 bytes 2… drop comment "durcissement InfoGer : ports non documentes"
admin@adm01:~$ kubectl -n kube-system get ciliumnodeconfigs
NAME           AGE
essai-tunnel   25m                                       # v2
admin@adm01:~$ kubectl -n kube-system get ciliumnodeconfig essai-tunnel -o yaml | yq '.spec'
nodeSelector: {matchLabels: {kubernetes.io/hostname: k8s-w02}}
defaults: {tunnel-port: "8473"}
```

**Étape 3 — Capturer des deux côtés.**

```
admin@k8s-w01:~$ sudo tcpdump -ni eth0 -c 5 'udp port 51871 and host 10.10.40.62'
10:52:01.1 IP 10.10.40.61.51871 > 10.10.40.62.51871: UDP, length 128     # part de w01
admin@k8s-w02:~$ sudo tcpdump -ni eth0 -c 5 'udp port 51871 and host 10.10.40.61'
10:52:01.1 IP 10.10.40.61.51871 > 10.10.40.62.51871: UDP, length 128     # arrive sur w02… et n'a jamais de réponse (v1 : jeté après la capture)
```

`tcpdump` capture **avant** netfilter : un paquet vu par `tcpdump` puis jamais traité est le signe d'un filtrage local (v1, compteur de la règle `drop` qui monte). En v2, on capture avec `udp port 8472 or udp port 8473` **à l'intérieur** du tunnel chiffré… c'est-à-dire sur `cilium_wg0`, pas sur `eth0` : w02 envoie vers le port 8473 d'un nœud qui écoute sur 8472, et inversement. En v3, rien ne sort de w02 vers les autres nœuds en 51871 : l'interface WireGuard est arrêtée, le trafic chiffré n'a plus de chemin (et Cilium, en mode chiffrement, ne retombe pas en clair).

**Variante 1 — pare-feu.** Le « durcissement » d'InfoGér jette les ports « non documentés » : VXLAN et surtout WireGuard (le seul qui passe sur le fil quand le chiffrement est actif). **Variante 2 — surcharge par nœud.** Une `CiliumNodeConfig` d'essai, oubliée, change le port du tunnel sur un seul nœud ; elle ne s'est appliquée qu'au redémarrage de l'agent, ce qui explique le décalage entre la pose et la panne. **Variante 3 — interface arrêtée.** Le script de durcissement a arrêté les interfaces qu'il ne connaissait pas.

**Correctif**
- V1 : `sudo nft delete table inet wb_durcissement` (ou les règles `iptables` correspondantes), sur le seul nœud ; demander à InfoGér la source du script, et s'il est rejoué par une tâche planifiée (`systemctl list-timers`, `crontab -l`, `/etc/cron.d/`).
- V2 : supprimer la `CiliumNodeConfig` (elle n'est dans aucun dépôt), puis redémarrer l'agent de **ce** nœud (`kubectl -n kube-system delete pod <cilium-de-w02>`) : la surcharge ne disparaît qu'au redémarrage, comme elle est apparue.
- V3 : `sudo ip link set cilium_wg0 up` (ou redémarrer l'agent du nœud, qui reconstruit ses interfaces).
- Vérifier : matrice complète, `cilium-health status --probe` à 6/6, 50 requêtes sans erreur (`for i in $(seq 50); do curl -s -o /dev/null -w '%{http_code}\n' https://…/pret; done | sort | uniq -c`).

**Prévention** : `cilium-health` dans `ms-verif-k8s-reseau` (sonde forcée, alerte au premier nœud injoignable) ; le rôle Ansible `k8s_noeud` affirme l'absence de règles de pare-feu étrangères sur les ports du cluster (tâche de vérification, `--check` dans la détection de dérive) et documente les ports dans `docs/kubernetes/reseau/matrice-flux-cluster.md` (« ports non documentés » n'aura plus d'excuse) ; `CiliumNodeConfig` interdites hors du dépôt (une VAP ou Kyverno au M26 qui refuse leur création par un autre compte que celui de l'automatisation) ; aucun accès administrateur d'InfoGér aux nœuds sans ticket de changement.

**Explications**

Avec Cilium en tunnel VXLAN et WireGuard, un paquet de pod à pod entre deux nœuds suit : `lxc*` du pod (programme `cil_from_container`) → décision de politique et recherche de l'adresse distante dans l'*ipcache* (identité, nœud de tunnel) → encapsulation VXLAN par `cilium_vxlan` (UDP 8472 vers l'adresse du nœud) → routage vers `cilium_wg0` → chiffrement WireGuard (UDP 51871) → `eth0`. À l'arrivée, l'ordre inverse. Chaque étage peut casser seul, et chacun se prouve par un outil : `cilium-dbg monitor`, `ip -d link`, `tcpdump` sur chaque interface, `nft list ruleset`. La santé de Cilium sonde deux choses distinctes : le **nœud** (adresse du nœud) et un **point de terminaison de santé** (adresse de pod) ; seul le second traverse le tunnel.

**Alternatives**
- Routage natif (sans tunnel, M15-E29) : supprime VXLAN et son port, mais exige que la bordure (ou les nœuds entre eux) route les adresses de pods ; WireGuard reste possible.
- IPsec plutôt que WireGuard : rotation de clés plus contrôlable, accélération matérielle possible, mais configuration et diagnostic plus lourds ; écarté à l'ADR-0150.

**Pièges classiques**
- Redémarrer tous les agents : la variante 2 s'étend alors au moment où l'agent de w02 redémarre… sans rien corriger, et les variantes 1 et 3 restent.
- `nft flush ruleset` sur le nœud : efface aussi les règles de Cilium et de kubelet.
- Capturer sur `eth0` en cherchant du VXLAN alors que le chiffrement est actif : on ne voit que de l'UDP 51871.
- Conclure « problème réseau de Proxmox » parce que le ping entre nœuds marche mal pour les gros paquets : vérifier d'abord la MTU de Cilium (pour aller plus loin de l'énoncé).

**En production chez MédiSphère**
Sonde de connectivité permanente entre tous les nœuds (Cilium la fournit), alertes sur `cilium_unreachable_nodes` et `cilium_unreachable_health_endpoints` (M21), images de nœuds immuables (pas de script tiers), et changements de chemin de données (tunnel, chiffrement, MTU) uniquement par le dépôt avec une fenêtre et un retour arrière.

---

### M15-E43 — Astreinte : plus rien n'entre dans le cluster

**Démarche de diagnostic**

Il n'y a pas une solution, mais une **méthode** ; les causes sont celles de M15-E35 à M15-E42, traitées par leur corrigé.

*Triage (10 minutes)*

1. Instruments : `kubectl get nodes` (kubeconfig valide), `cilium status` (agents prêts), `hubble status`, `ssh k8s-w01 true`, `ssh gw02 true`, témoins `kubectl -n wb-pannes get pods -o wide`.
2. Cartographie : `for e in 35 36 37 38 39 40 41 42; do lab/bin/check 15 $e | tail -2; done` : une liste de rouges, pas encore des causes.
3. Trois tests de référence, relancés après chaque correction :
   - **de l'extérieur** : `curl -sv https://mediagenda-recette.apps.par1.medisphere.internal/pret` depuis `adm01` (nom, adresse, TLS, route, application) ;
   - **de l'intérieur** : depuis un témoin, `dig` d'un nom du cluster et d'un nom `medisphere.internal`, et la matrice des témoins ;
   - **en court-circuitant l'entrée** : `kubectl -n mediagenda-recette port-forward svc/<svc> 18001:80` puis `curl localhost:18001/pret` (application et ses dépendances, sans Gateway ni bordure).
4. Première communication (modèle) :
   > 23 h 25 — INC-4250 — MédiAgenda recette injoignable depuis l'extérieur depuis 23 h 10. Impact : recette indisponible, campagne client de 7 h menacée. Constat : au moins trois anomalies distinctes (entrée du cluster, réseau interne, application), liées à trois interventions sans ticket. Prochain point : 23 h 55.

*Ordre de traitement, justifié par les dépendances*

1. **L'entrée** (E38 ou E39) : tant qu'elle est coupée, aucun test de l'extérieur ne dit rien de l'aval. Prouver la cause, corriger, vérifier que le TLS est négocié et qu'Envoy répond (même un 503 est un progrès : la suite du chemin devient observable).
2. **Le réseau du cluster** (E36 ou E42) : il fausse tous les tests applicatifs (DNS en panne : pods non prêts ; nœud cassé : erreurs intermittentes qui ressemblent à une application instable). Les tests de l'intérieur le montrent indépendamment de l'entrée : il peut être diagnostiqué **en parallèle** du point 1, mais corrigé après, pour ne changer qu'une chose à la fois.
3. **L'application et la publication** (E35, E37, E40 ou E41) : avec l'entrée et le réseau rétablis, le test de l'extérieur dit enfin la vérité. E40 (certificat de répétition) et E41 (nom d'une route neuve) ne bloquent pas la recette : ils se traitent en dernier, mais avant de clore, parce qu'ils menacent le **prochain** changement.

*Pièges propres à l'astreinte* : « réparer » la deuxième panne en croyant réparer la première (redémarrer tous les agents Cilium, supprimer des politiques) ; corriger à chaud sans reporter dans le dépôt, à 2 h du matin, puis oublier ; ne pas relancer les trois tests après chaque correction ; clore sans `lab/bin/break 15 43 --annuler`.

*Post-mortem* : modèle de l'équipe, exemple rédigé dans [`fichiers/M15-E43/medisphere/docs/kubernetes/post-mortems/2026-10-15-INC-4250.md`](fichiers/M15-E43/medisphere/docs/kubernetes/post-mortems/2026-10-15-INC-4250.md) (une combinaison E38 v4 + E42 v1 + E37 v3). Points attendus : chronologie horodatée (détection, triage, chaque hypothèse, chaque correction, retour au nominal) ; trois causes racines **et** une cause commune (trois changements sans ticket, dont deux à chaud hors dépôt) ; détection (la sonde externe a vu la conséquence, rien n'a vu les causes : ni la dérive de configuration, ni `cilium-health`, ni les `DROPPED`) ; actions avec responsable et échéance, dont la détection de dérive planifiée (`derive-reseau.sh` de M15-E23 et [`derive-bordure-noeuds.sh`](fichiers/M15-E43/k8s/outils/derive-bordure-noeuds.sh)), les contrôles manquants de `ms-verif-k8s-reseau`, et la règle « aucun changement sans ticket, même pour InfoGér ».

**Explications**

Une astreinte multi-causes se gagne par l'ordre et par les instruments : trois points de test (extérieur, intérieur, court-circuit) découpent le chemin en segments que l'on peut juger séparément, et la relance systématique des trois tests après chaque correction évite de croire réparé ce qui ne l'est pas. La cause commune (changements non tracés) compte plus que les trois causes techniques : c'est elle qu'on corrige pour que la nuit suivante soit calme.

**Alternatives** : avec deux personnes d'astreinte, l'une prend l'entrée, l'autre le réseau interne (tests de l'intérieur), la coordination passant par le journal d'incident ; avec GitOps (M20), la dérive aurait été corrigée et signalée automatiquement en quelques minutes, ce qui aurait réduit l'incident à une seule cause.

**Pièges classiques** : supprimer `refus-par-defaut`, désactiver le chiffrement, basculer la VIP, poser un certificat à la main (tous interdits par le ticket : ils transforment un incident de disponibilité en incident de sécurité) ; un post-mortem qui désigne Lucas ou InfoGér au lieu du processus.

**En production chez MédiSphère** : GitOps avec détection de dérive (M20), alertes sur les causes (M21) et pas seulement sur les symptômes, changements tracés et relus pour tous (y compris le prestataire), et répétition d'astreinte trimestrielle sur un environnement de recette.

---

### M15-E44 — Sous le capot : eBPF et les tables de Cilium

**Solution**

Modèle de compte rendu : [`fichiers/M15-E44/medisphere/docs/kubernetes/reseau/analyses/sous-le-capot-ebpf.md`](fichiers/M15-E44/medisphere/docs/kubernetes/reseau/analyses/sous-le-capot-ebpf.md). Les sorties ci-dessous sont représentatives (identifiants, adresses et colonnes varient).

**0. Préparation.** Les deux autorisations temporaires, dans un fichier local (pas dans le dépôt, puisqu'on les retire) :

```yaml
# /tmp/e44-temporaire.yaml — à supprimer à la fin de l'exercice
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: {name: e44-temoin-sortie, namespace: wb-pannes}
spec:
  endpointSelector: {matchLabels: {app.kubernetes.io/name: sonde}}
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: mediagenda-recette
            app.kubernetes.io/name: mediagenda-api
      toPorts: [{ports: [{port: "8000", protocol: TCP}]}]
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: {name: e44-temoin-entree, namespace: mediagenda-recette}
spec:
  endpointSelector: {matchLabels: {app.kubernetes.io/name: mediagenda-api}}
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: wb-pannes
            app.kubernetes.io/name: sonde
      toPorts: [{ports: [{port: "8000", protocol: TCP}]}]
```

(Étiquettes de l'API posées au M14.) Un témoin joint alors le **Service** sur son port (80), traduit vers le port 8000 d'un pod.

**1. Programmes eBPF.**

```
admin@adm01:~$ kubectl debug node/k8s-w01 -it --profile=sysadmin --image=registry.par1.medisphere.internal/dockerhub/nicolaka/netshoot:v0.16
root@k8s-w01:/# chroot /host bpftool net show            # bpftool du nœud (paquet bpftool) ; sinon celui de l'image s'il existe
xdp:
tc:
eth0(2) tcx/ingress cil_from_netdev prog_id 812 link_id 14
eth0(2) tcx/egress cil_to_netdev prog_id 815 link_id 15
cilium_net(3) tcx/ingress cil_to_host prog_id 801 …
cilium_host(4) tcx/ingress cil_to_host prog_id 798 …
cilium_host(4) tcx/egress cil_from_host prog_id 799 …
cilium_vxlan(5) tcx/ingress cil_from_overlay prog_id 790 …
cilium_vxlan(5) tcx/egress cil_to_overlay prog_id 791 …
cilium_wg0(12) tcx/egress cil_to_wireguard prog_id 820 …
lxc7a1b…(31) tcx/ingress cil_from_container prog_id 1204 …
lxc7a1b…(31) tcx/egress cil_to_container prog_id 1210 …
root@k8s-w01:/# chroot /host bpftool cgroup tree /sys/fs/cgroup | head
CgroupPath
ID       AttachType      AttachFlags     Name
/sys/fs/cgroup
1031     cgroup_inet4_connect multi      cil_sock4_connect
1033     cgroup_udp4_sendmsg  multi      cil_sock4_sendmsg
1035     cgroup_udp4_recvmsg  multi      cil_sock4_recvmsg
1037     cgroup_inet4_getpeername multi  cil_sock4_getpeername
```

Noyau 6.12 : Cilium s'attache en **tcx** (successeur de tc/cls_bpf) quand il est disponible. Sens : `cil_from_container` est attaché à l'**entrée** de l'interface `lxc` côté hôte, c'est-à-dire la **sortie** du pod. Les programmes du cgroup racine (`cil_sock4_connect`…) sont le *socket LB* : au moment du `connect()`, l'adresse ClusterIP est remplacée par celle d'un backend, avant qu'un seul paquet existe ; `getpeername` rend à l'application l'adresse qu'elle croyait joindre.

**2. Un Service vu par Cilium.**

```
admin@adm01:~$ kubectl -n kube-system exec cilium-7qz2m -c cilium-agent -- cilium-dbg service list | grep -A2 10.96.41.187
ID   Frontend            Service Type   Backend
42   10.96.41.187:80/TCP   ClusterIP    1 => 10.240.3.17:8000/TCP (active)
                                        2 => 10.240.5.22:8000/TCP (active)
admin@adm01:~$ kubectl -n kube-system exec cilium-7qz2m -c cilium-agent -- cilium-dbg bpf lb list | grep -A3 10.96.41.187
SERVICE ADDRESS          BACKEND ADDRESS (REVNAT_ID) (SLOT)
10.96.41.187:80/TCP (0)  0.0.0.0:0 (42) (0) [ClusterIP, non-routable]
10.96.41.187:80/TCP (1)  10.240.3.17:8000/TCP (42) (1)
10.96.41.187:80/TCP (2)  10.240.5.22:8000/TCP (42) (2)
admin@adm01:~$ kubectl -n mediagenda-recette scale deploy/mediagenda-api --replicas=3   # une troisième ligne apparaît (slot 3), puis --replicas=2
```

Le *slot* 0 est l'en-tête du service (nombre de backends, drapeaux) ; chaque *slot* suivant pointe un backend. Le Service de la Gateway (`cilium-gateway-gw-par1`) apparaît trois fois : ClusterIP, NodePort (sur chaque adresse de nœud et `0.0.0.0`) et `LoadBalancer` 10.10.41.10:443 ; ses backends ne sont pas des pods mais le proxy Envoy local (redirection vers le port du proxy, marqué `L7LoadBalancer` ou équivalent selon la version).

**3. Suivi de connexion et NAT.**

```
admin@adm01:~$ kubectl -n wb-pannes exec sonde-4xk2p -- sh -c 'while :; do curl -s -o /dev/null http://10.96.41.187/sante; sleep 1; done' &
admin@adm01:~$ kubectl -n kube-system exec cilium-7qz2m -c cilium-agent -- cilium-dbg bpf ct list global | grep 10.240.3.41 | head -3
TCP OUT 10.240.3.41:50122 -> 10.240.5.22:8000 expires=21612 Packets=0 Bytes=0 RxFlagsSeen=0x1b … TxFlagsSeen=0x1b … SourceSecurityID=40213 …
```

L'entrée de suivi porte l'adresse du **pod**, pas la ClusterIP : la traduction a eu lieu au `connect()` (socket LB), le paquet n'a jamais porté 10.96.41.187. `expires` est en secondes depuis le démarrage du nœud (comparer avec `cat /proc/uptime`). `cilium-dbg bpf nat list` est vide pour ce flux (pas de NAT entre pods) ; il contient des entrées pour ce qui sort vers l'extérieur du cluster par l'adresse du nœud (masquerade), par exemple les requêtes de CoreDNS vers `dns01`.

**4. Identités et politiques.**

```
admin@adm01:~$ kubectl -n kube-system exec cilium-7qz2m -c cilium-agent -- cilium-dbg endpoint list | grep -E 'sonde|mediagenda-api'
ENDPOINT   POLICY (ingress)   POLICY (egress)   IDENTITY   LABELS                                              IPv4          STATUS
1877       Enabled            Enabled           40213      k8s:app.kubernetes.io/name=sonde …                  10.240.3.41   ready
admin@adm01:~$ kubectl -n kube-system exec cilium-7qz2m -c cilium-agent -- cilium-dbg identity get 40213
ID      LABELS
40213   k8s:app.kubernetes.io/name=sonde
        k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=wb-pannes
        k8s:io.kubernetes.pod.namespace=wb-pannes …
admin@adm01:~$ kubectl -n kube-system exec cilium-7qz2m -c cilium-agent -- cilium-dbg bpf ipcache list | grep -E '10.240.3.41|10.240.5.22'
10.240.3.41/32   identity=40213 encryptkey=0 tunnelendpoint=0.0.0.0 flags=<none>
10.240.5.22/32   identity=31842 encryptkey=0 tunnelendpoint=10.10.40.63 flags=<none>
admin@adm01:~$ kubectl -n kube-system exec <agent-de-k8s-w03> -c cilium-agent -- cilium-dbg bpf policy get 2204
POLICY   DIRECTION   LABELS (source:key[=value])                PORT/PROTO   PROXY PORT   AUTH TYPE   BYTES     PACKETS   PREFIX
Allow    Ingress     k8s:app.kubernetes.io/name=sonde …          8000/TCP     NONE         disabled    48210     612       16
Allow    Ingress     reserved:ingress                            8000/TCP     NONE         disabled    …
Allow    Egress      …
```

(Selon la version, l'*ipcache* se lit par `cilium-dbg bpf ipcache list` ou `cilium-dbg map get cilium_ipcache` ; la colonne `encryptkey` vaut 0 avec WireGuard, qui n'utilise pas d'index de clé IPsec.) Les compteurs `BYTES`/`PACKETS` de la règle montent à chaque requête de la boucle.

**5. Suivre un paquet.**

```
admin@adm01:~$ kubectl -n kube-system exec <agent-de-k8s-w03> -c cilium-agent -- cilium-dbg monitor --related-to 2204 --type trace --type drop --type policy-verdict
-> endpoint 2204 flow 0x… identity 40213->31842 state new ifindex lxc… : 10.240.3.41:50140 -> 10.240.5.22:8000 tcp SYN
Policy verdict log: flow 0x… local EP ID 2204, remote ID 40213, proto 6, ingress, action allow, auth: disabled, match L3-L4, 10.240.3.41:50140 -> 10.240.5.22:8000 tcp SYN
admin@adm01:~$ hubble observe --from-pod wb-pannes/sonde-4xk2p --to-namespace mediagenda-recette -o compact --last 5
wb-pannes/sonde-4xk2p:50140 (ID:40213) -> mediagenda-recette/mediagenda-api-…:8000 (ID:31842) to-overlay FORWARDED (TCP Flags: SYN)
wb-pannes/sonde-4xk2p:50140 (ID:40213) -> mediagenda-recette/mediagenda-api-…:8000 (ID:31842) to-endpoint FORWARDED (TCP Flags: SYN)
```

Puis, entrée retirée (`kubectl delete cnp -n mediagenda-recette e44-temoin-entree`) : `Policy verdict … ingress, action deny` et `xx drop (Policy denied) … identity 40213->31842`, dans Hubble `policy-verdict:none INGRESS DENIED`. Enfin `kubectl delete -f /tmp/e44-temporaire.yaml --ignore-not-found`, et suppression du pod `node-debugger-k8s-w01-…`.

**Réponses aux questions d'analyse**

1. Le *socket LB* traduit au `connect()` : le noyau crée la socket directement vers le backend, donc la table de suivi, `tcpdump` dans le pod et toute la suite du chemin ne voient que l'adresse du pod. L'application, elle, voit la ClusterIP (grâce à `getpeername`). Conséquence : une capture « vers 10.96.x.x » dans le pod est vide ; il faut capturer vers les adresses des backends.
2. kube-proxy en iptables : une chaîne `KUBE-SERVICES` parcourue règle par règle (une par Service), puis `KUBE-SVC-*` avec des règles probabilistes par backend et `KUBE-SEP-*` (DNAT). Recherche linéaire en nombre de Services, et chaque mise à jour réécrit la table entière (`iptables-restore`) : avec 10 000 Services, des secondes de mise à jour et de la latence ajoutée à chaque nouvelle connexion. Cilium : des tables de hachage (recherche en temps constant), mises à jour entrée par entrée.
3. Les adresses changent (pod recréé, nouvelle adresse) et se réutilisent ; une identité dérivée des étiquettes est stable et partagée par tous les pods qui ont les mêmes étiquettes de sécurité (même identité, donc même table de politique, calculée une fois). Au redémarrage d'un pod, seule l'association adresse → identité de l'*ipcache* change, la politique non.
4. Les tables eBPF sont préallouées à la création (taille fixe connue du vérifieur, mémoire verrouillée) ; table de suivi pleine : les nouvelles connexions ne peuvent plus être suivies et sont jetées (`CT: Map insertion failed`), visible dans `cilium-dbg metrics list` (`cilium_drop_count_total` raison `CT map insertion failed`) et dans `hubble observe --verdict DROPPED`. On dimensionne par `bpf-ct-global-tcp-max` (ou `bpf-map-dynamic-size-ratio`).
5. Redémarrage de l'agent : oui, les programmes et les tables restent dans le noyau, la connexion continue (observé : la boucle de `curl` ne perd rien). Suppression de la politique : non, la politique est évaluée pour chaque paquet qui n'est pas une réponse, la connexion est coupée au paquet suivant (observé à l'étape 5).
6. Le paquet est encapsulé par `cilium_vxlan`, puis l'encapsulé est routé vers `cilium_wg0` qui le chiffre : sur `cilium_vxlan` on voit encore le paquet du pod en clair (dans son en-tête VXLAN), sur `eth0` seulement de l'UDP 51871 chiffré.
7. XDP traiterait l'équilibrage du Service `LoadBalancer` au plus tôt, dans le pilote, avant l'allocation des tampons : gain réel pour des millions de paquets par seconde. Sur `k8s-par1` : pilote virtio-net (XDP natif possible mais avec contraintes de files et de MTU), un trafic modeste, et un proxy L7 (Envoy) de toute façon sur le chemin de la Gateway : aucun gain mesurable, une complexité de plus. Non activé, écrit dans l'ADR-0150.

**Explications**

Cilium n'est pas une boîte noire : chaque décision a une trace dans une table lisible (`service list`/`bpf lb list` pour les Services, `bpf ct list` pour les connexions, `bpf ipcache list` pour « qui est cette adresse », `bpf policy get` pour « qui a le droit de me parler »), et chaque paquet peut être suivi (`monitor`, Hubble). C'est ce qui rend le diagnostic de M15-E35 à M15-E42 possible sans hypothèse invérifiable.

**Alternatives** : `pwru` (suivi d'un paquet dans les fonctions du noyau) et `bpftrace` pour aller plus bas ; `cilium-dbg debuginfo` produit un instantané complet à joindre à un ticket d'assistance (attention : il contient des adresses et des noms, pas de secrets, à relire avant envoi).

**Pièges classiques** : un `monitor` sans filtre sur un nœud chargé ; `bpftool map dump` d'une grande table (des centaines de milliers de lignes) ; oublier le pod de diagnostic de nœud (privilégié, monté sur `/`) ; laisser les politiques temporaires.

**En production chez MédiSphère** : les métriques de l'agent (`cilium_bpf_map_pressure`, `cilium_drop_count_total`, `cilium_policy_*`) en supervision (M21), le compte rendu comme support d'accueil, et `cilium-dbg debuginfo` dans la procédure d'escalade.

---

### M15-E45 — Questions expert : réseau Kubernetes

1. **Modèle réseau** : (a) chaque pod a sa propre adresse et tous les pods se joignent sans NAT, quel que soit leur nœud ; (b) les agents d'un nœud (kubelet) joignent tous les pods de ce nœud ; (c) l'adresse qu'un pod voit pour lui-même est celle que les autres voient. (a) et (b) sont du ressort du **CNI** (Cilium : IPAM, routes, tunnel) ; les **Services** (adresse virtuelle stable, équilibrage) sont du ressort de kube-proxy ou de son remplaçant (Cilium KPR) ; la découverte par nom est celle du **DNS du cluster** (CoreDNS, greffon `kubernetes`). Le modèle ne dit rien des politiques ni du chiffrement : ce sont des extensions.
2. **QCM — b.** Sans backend, Cilium répond immédiatement : le *socket LB* fait échouer le `connect()` (`ECONNREFUSED`), et le chemin tc renvoie un ICMP « destination injoignable » (réglage `serviceNoBackendResponse` du chart, `reject` par défaut, `drop` possible ; à vérifier sur ta version). (a) était le comportement de certaines configurations kube-proxy (paquets jetés silencieusement, attente) ; (c) faux, la ClusterIP n'est routée nulle part hors de la traduction ; (d) faux, le DNS résout le Service indépendamment de ses points de terminaison (sauf Service *headless*, qui ne renvoie alors aucune adresse).
3. **`externalTrafficPolicy`** : `Cluster` (défaut) : tout nœud qui reçoit le trafic l'envoie à n'importe quel backend (un saut de plus possible), l'adresse source est masquée (SNAT vers le nœud) sauf mode DSR, tous les nœuds sélectionnés annoncent l'adresse ; `Local` : le nœud n'envoie qu'à ses backends locaux, l'adresse source est préservée, **seuls** les nœuds qui ont un backend prêt annoncent la /32 (Cilium retire l'annonce quand le dernier pod local disparaît) ; l'équilibrage se fait par nœud (ECMP de la bordure), donc déséquilibré si les pods sont mal répartis. Pour la Gateway de Cilium, le backend est Envoy (présent sur chaque nœud) : `Local` coûte peu et garde la source jusqu'à Envoy (en-tête `X-Forwarded-For`).
4. **`ndots:5`** permet à un nom comme `svc.ns.svc` (jusqu'à 4 points, le cas `<svc>.<ns>.svc.cluster` compris) d'être complété par la liste `search` avant d'être tenté tel quel. Coût : un nom externe à moins de 5 points déclenche jusqu'à 3 essais inutiles (`NXDOMAIN`), doublés en A et AAAA. Réduire : écrire les noms externes avec un point final (`s3-01.par1.medisphere.internal.`) ; baisser `ndots` par `dnsConfig.options` pour l'application (2 ou 3 garde `<svc>.<ns>` fonctionnel) ; un cache local (NodeLocal DNSCache) qui absorbe les `NXDOMAIN` (ne réduit pas le nombre de requêtes, mais leur coût).
5. **CNP en plus de NetworkPolicy** : règles L7 (méthodes et chemins HTTP, Kafka retiré en 1.20, DNS), `toFQDNs`, entités (`host`, `kube-apiserver`, `ingress`, `world`, `cluster`), refus explicites (`*Deny`), politiques à l'échelle du cluster (CCNP), sélection de nœuds (politiques d'hôte), `enableDefaultDeny`, chiffrement mutuel (déprécié en 1.20). Garder le `refus-par-defaut` en NetworkPolicy standard : lisible par tout auditeur et tout outil, indépendant du CNI (portable en cas de changement), et c'est l'invariant de sécurité HDS (un objet simple, une seule intention) ; les CNP portent les règles fines.
6. **QCM — b.** Dans Cilium, un refus correspondant à un flux l'emporte toujours sur une autorisation, quel que soit le type de politique ou l'ordre de création. (a) et (c) faux (aucune priorité par type ni par ordre) ; (d) faux : `enableDefaultDeny` règle le comportement *par défaut* d'un point de terminaison sélectionné, pas l'effet d'un refus explicite.
7. **`toFQDNs`** : la règle DNS L7 (`toPorts.rules.dns`) fait passer les requêtes DNS du pod par le proxy DNS de l'agent, qui apprend les réponses (nom → adresses) et crée des identités de CIDR pour ces adresses, autorisées ensuite par la règle `toFQDNs`. Sans règle DNS L7, le proxy ne voit pas les réponses : aucune adresse n'est apprise, tout est refusé. TTL très court : Cilium garde les adresses au moins `tofqdns-min-ttl` (et les connexions établies vivantes), sinon une adresse expirerait entre la résolution et la connexion ; un service à adresses tournantes peut remplir le cache (`tofqdns-endpoint-max-ip-per-hostname`).
8. **LB IPAM et BGP** : l'**opérateur** Cilium (LB IPAM) attribue l'adresse depuis un pool ; le `CiliumBGPClusterConfig` (sélecteur) et l'`externalTrafficPolicy` décident quels nœuds l'annoncent ; la bordure installe une /32 avec trois prochains sauts (ECMP, hachage par flux). Perte d'un nœud : la bordure s'en aperçoit à l'expiration du temps de maintien (ou par BFD), ou plus tard si le redémarrage gracieux garde les routes ; perte d'un pod : avec `Local`, l'agent retire l'annonce immédiatement (un UPDATE de retrait), convergence en secondes ; avec `Cluster`, rien ne change côté BGP.
9. **Redémarrage gracieux** : protège le trafic pendant un redémarrage **planifié** de l'agent BGP (mise à jour de Cilium) : la bordure garde les routes, le chemin de données du nœud continue. Masque une vraie perte : si le nœud est **mort**, la bordure continue d'y envoyer le trafic jusqu'à la fin du temps de redémarrage. Avec 120 s, une panne de nœud détectée en 10 s par le temps de maintien devient 2 minutes de trou noir pour un tiers des flux ; d'où un temps court, et BFD pour distinguer « l'agent redémarre » de « le nœud est mort ».
10. **QCM — b.** RFC 8212, appliquée par `bgp ebgp-requires-policy` : sans politique de sortie, FRR n'annonce rien à ce voisin (et sans politique d'entrée, n'accepte rien) ; `show bgp summary` affiche `(Policy)`. (a) faux, la session s'établit ; (c) était le comportement d'avant RFC 8212 ; (d) faux, aucune exception pour les routes connectées.
11. **Gateway API contre Ingress** : trois rôles (fournisseur d'infrastructure : `GatewayClass` ; opérateur : `Gateway`, écouteurs, certificats, admission ; développeurs : routes), délégation explicite entre espaces (`allowedRoutes`, `ReferenceGrant`), et des fonctions standard là où Ingress dépendait d'annotations propres à chaque contrôleur. Équivalents des annotations de M15-E18 : `nginx.ingress.kubernetes.io/ssl-redirect` → `RequestRedirect` sur l'écouteur HTTP ; `rewrite-target` → filtre `URLRewrite` ; `canary-weight` → `backendRefs` pondérés ; `proxy-body-size`, `configuration-snippet` → pas d'équivalent standard (politique propre à l'implémentation, ou à abandonner : c'était aussi la source des failles d'ingress-nginx).
12. **`ReferenceGrant`** : sans lui, toute personne qui peut créer une route dans son espace pourrait diriger du trafic vers le Service d'un autre espace (contourner ses politiques, son authentification) ou faire servir par une Gateway le Secret (certificat et clé) d'un autre espace. Le propriétaire de la **cible** décide, dans son espace : c'est le principe du consentement explicite (vulnérabilité CVE-2021-25740 des `Endpoints` d'Ingress comme exemple historique du risque).
13. **TLS** : terminaison (Envoy de la Gateway voit le clair, la clé est dans le Secret de l'écouteur, toutes les fonctions L7 possibles) ; ré-chiffrement (`BackendTLSPolicy` : clair dans Envoy seulement, l'application a sa propre clé, L7 possible, confiance à configurer vers le backend) ; passage direct (`TLSRoute` : la Gateway ne voit que le SNI, la clé reste dans l'application, aucune fonction L7, aucun en-tête ajouté). MédiSphère : terminaison par défaut, passage direct pour les applications qui exigent l'authentification mutuelle de bout en bout (M15-E33).
14. **Renouvellement** : cert-manager calcule `renewalTime` (par défaut aux deux tiers de la durée, ou `renewBefore`) ; à l'échéance, il crée une nouvelle `CertificateRequest` → `Order` → `Challenge` ; tant que la nouvelle émission échoue, l'**ancien** certificat reste servi et cert-manager réessaie avec un délai croissant (jusqu'à une heure entre deux essais, à vérifier sur ta version) ; au bout de 10 jours d'échec, le certificat approche de l'expiration sans que rien ne casse : seule la supervision le voit. ARI (*ACME Renewal Information*, pris en charge depuis 1.21) : la CA indique la fenêtre de renouvellement souhaitée, et peut l'avancer (révocation massive, incident) : cert-manager renouvelle alors plus tôt.
15. **RFC 2136 + TSIG** : la clé ne donne que le droit de mettre à jour **une zone** (métadonnée `TSIG-ALLOW-DNSUPDATE` de `apps`), depuis une plage d'adresses (`ALLOW-DNSUPDATE-FROM`), et chaque mise à jour est journalisée avec le nom de la clé ; une clé d'API PowerDNS donne tout le serveur (toutes les zones, la configuration). RFC 2136 est un standard : le jour où l'autoritaire change, cert-manager et ExternalDNS n'ont rien à changer. Métadonnées : `TSIG-ALLOW-DNSUPDATE` (quelles clés), `ALLOW-DNSUPDATE-FROM` (d'où), et une zone **dédiée** (`apps`) pour que la clé ne puisse rien toucher d'autre ; plus DNSSEC (la zone est re-signée à chaque mise à jour) et des clés distinctes par composant.
16. **Registre TXT** : il marque chaque nom géré avec son propriétaire, pour qu'ExternalDNS ne touche jamais un nom créé par un humain ou par un autre ExternalDNS. Deux clusters avec le **même** identifiant : chacun supprime les noms de l'autre (politique `sync`) au cycle suivant, puis l'autre les recrée : oscillation et coupures. Identifiants **différents** : cohabitation correcte, chacun ses noms ; un même nom demandé par les deux reste à celui qui l'a créé. `upsert-only` : pendant une migration (deux clusters servent le même nom, ou reprise de noms existants), ou quand une suppression accidentelle serait grave ; au prix d'orphelins à nettoyer.
17. **WireGuard dans Cilium** : chiffré par défaut, le trafic de pod à pod entre nœuds (y compris par un Service ClusterIP et derrière Envoy) ; non chiffré : le trafic pod ↔ nœud distant et de nœud à nœud (kubelet, etcd, API) sauf `encryption.nodeEncryption=true` (bêta, nœuds de contrôle exclus par défaut), et le trafic qui sort du cluster. Chaque agent génère sa paire de clés, publie la clé publique dans l'annotation de son objet `CiliumNode`, et configure les pairs à partir de celles des autres ; changement de clé : redémarrage de l'agent avec une nouvelle clé (pas de rotation planifiée intégrée). Aucune règle de bordure pour l'UDP 51871 : les nœuds sont tous sur le VLAN 40, le trafic entre eux ne traverse pas la passerelle.
18. **QCM — b.** Le paquet du pod est encapsulé en VXLAN, puis l'encapsulé est chiffré par WireGuard : sur l'interface physique, seulement de l'UDP 51871 entre les adresses des nœuds. (a) serait vrai sans WireGuard ; (c) en routage natif sans chiffrement ; (d) avec IPsec.
19. **Remplacement de kube-proxy et kubeadm** : supprimer le DaemonSet et la ConfigMap `kube-proxy`, nettoyer les règles `KUBE-*` des nœuds, et empêcher la réinstallation : avec kubeadm v1beta4, `proxy.disabled: true` dans la `ClusterConfiguration` (enregistrée dans la ConfigMap `kubeadm-config`), que `kubeadm upgrade` respecte (M15-E08) ; pour une installation neuve, `skipPhases: [addon/kube-proxy]` (ou `--skip-phases`) a le même effet à l'`init`. Supprimer seulement la ConfigMap `kube-proxy` ne suffit pas : `upgrade apply` recréerait l'extension. Pendant la bascule d'un nœud, les Services restent servis par les règles iptables existantes (kube-proxy arrêté ne les efface pas) jusqu'à ce que l'agent Cilium prenne le relais ; c'est pourquoi on supprime kube-proxy **avant** de redémarrer les agents, puis on nettoie. Accès à l'API : les agents ne peuvent pas compter sur le Service `kubernetes` (c'est eux qui le programment) : ils utilisent `k8sServiceHost`/`k8sServicePort` (VIP `k8s-api.par1.medisphere.internal:8443`), d'où l'obligation de ces deux valeurs en mode KPR.
20. **« Mon service est injoignable »** : questions d'abord (depuis où, quel nom, depuis quand, quel changement récent, tout le monde ou certains), puis le chemin : nom (`dig` sur `dns01`/`dns02`) → adresse (`kubectl get svc`, `cilium bgp peers`, `ip route` sur les deux passerelles) → écouteur (`status.listeners`, `openssl s_client -servername`) → route (`status.parents`) → Service et EndpointSlice → pod (prêt, journaux) → politique (`hubble observe --verdict DROPPED`) → DNS du cluster et chemin entre nœuds (`dig` depuis un témoin, `cilium-health`). Gestes interdits sans preuve : supprimer une politique, redémarrer tous les agents ou CoreDNS, basculer la bordure, poser un certificat ou un enregistrement DNS à la main, modifier à chaud ce qui est dans un dépôt.

**Grille d'auto-évaluation** : 18 à 20 réponses justes et argumentées : niveau attendu pour le poste ; 14 à 17 : reprendre les exercices des questions manquées (E38 et E44 pour 8, 9, 18 ; E39 et E16 pour 11 à 13 ; E14, E15, E40, E41 pour 14 à 16) ; moins de 14 : refaire le palier 2 avant le mini-projet.
