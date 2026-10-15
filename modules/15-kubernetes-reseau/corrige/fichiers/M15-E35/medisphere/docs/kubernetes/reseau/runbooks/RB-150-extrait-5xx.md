<!-- Section ajoutée à RB-150 (M15-E22) après M15-E35. À insérer après « Premières vérifications ». -->

## Erreur 5xx renvoyée par la Gateway

**Reconnaître** : le TLS est négocié, la réponse porte `server: envoy`, le corps n'est pas celui de l'application. Le nom, l'adresse, le BGP, l'écouteur et le certificat sont donc sains : la panne est derrière l'écouteur.

| Corps ou code | Étage probable | Aller à |
|---|---|---|
| `no healthy upstream` (503) | aucun point de terminaison prêt | 1, puis 3 |
| `upstream connect error … connection failure … 111` (503) | point de terminaison sans écoute sur le port | 2 |
| `upstream request timeout` (504), ou délai dépassé | politique qui jette, ou application lente | 4 |
| 500 sans corps d'application | référence de la route non résolue | 0 |

0. **Route** : `kubectl -n <espace> get httproute <route> -o jsonpath='{.status.parents}' | jq` — `Accepted` et `ResolvedRefs` à `True`. `ResolvedRefs=False` : le Service ou le port du `backendRefs` n'existe pas (`kubectl get svc <svc> -o jsonpath='{.spec.ports}'`).
1. **Sélecteur** : `kubectl -n <espace> get svc <svc> -o jsonpath='{.spec.selector}'` comparé à `kubectl -n <espace> get pods --show-labels`. EndpointSlice vide (`kubectl get endpointslices -l kubernetes.io/service-name=<svc>`) : aucun pod ne correspond, ou aucun n'est prêt (3).
2. **Ports** : `targetPort` du Service comparé à `kubectl get pod <pod> -o jsonpath='{.spec.containers[*].ports}'` (numéro ou nom). Preuve sans la Gateway : `kubectl port-forward pod/<pod> 18000:<port-du-conteneur>` répond, `kubectl port-forward svc/<svc> 18001:<port>` échoue.
3. **Pods non prêts** : `kubectl describe pod` (événements de la sonde `readinessProbe`), journaux ; `/pret` de MédiAgenda dépend de PostgreSQL et Valkey (aller voir leur état, puis le DNS : RB-150 § DNS).
4. **Politiques** : `hubble observe --namespace <espace> --verdict DROPPED` ; un flux depuis l'identité `ingress` refusé vers l'API : voir la matrice des flux du cluster et les politiques de l'espace.
5. **Ce que Cilium a programmé** (en cas de doute sur 1-2) : `kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg service list | grep <ClusterIP>`.

**Qui a changé quoi** : `kubectl get svc <svc> -o yaml --show-managed-fields` (gestionnaire et heure de chaque champ), `git log -p` du dépôt de déploiement, journal d'audit de l'API (M14-E27).

**Corriger** : par le dépôt de déploiement, jamais en adaptant les pods à un Service fautif. **Interdit** : supprimer les politiques de l'espace pour « tester ».
