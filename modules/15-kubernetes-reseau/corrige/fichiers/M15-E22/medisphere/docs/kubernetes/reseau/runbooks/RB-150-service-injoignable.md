# RB-150 — Une application du cluster ne répond plus

| | |
|---|---|
| **Portée** | Applications de `k8s-par1` publiées par `gw-par1` (`*.apps.par1.medisphere.internal`), accès depuis le lab et, pour les noms publiés, depuis l'extérieur par `lb01`/`lb02` |
| **Symptômes** | « le site ne s'ouvre pas », délai dépassé, erreur de certificat, 404, 403, 503 « no healthy upstream », nom introuvable |
| **Gravité** | selon l'application (MédiAgenda recette : P3 ; production, à partir du M20 : P1) |
| **Propriétaire** | Équipe Plateforme ; version 1.0 (PLAT-1622, M15-E22) |
| **Liens** | RB-151 (certificat non délivré), RB-152 (BGP du cluster), RB-073 (sessions BGP de la bordure), RB-140 (nœud NotReady), `docs/kubernetes/reseau/entree-du-cluster.md` |

**Règle d'or** : ce runbook ne **modifie** rien avant l'étape « Corriger ». Toutes les commandes de diagnostic sont en lecture. Note l'heure et chaque résultat dans le ticket au fil de l'eau.

## Arbre de décision (une minute)

```
curl -sSv https://<NOM>/<SONDE> depuis adm01
 ├─ « Could not resolve host »                  → 1. DNS
 ├─ délai dépassé / « No route to host »        → 2. Adresse et annonce (BGP)
 ├─ erreur TLS (certificat, nom, expiré)        → 3. Certificat
 ├─ 404 (réponse de la Gateway, « server: envoy ») → 4. Route
 ├─ 503 « no healthy upstream » / 502           → 5. Service, EndpointSlices, pods
 ├─ 403 « Access denied » / délai vers le pod   → 6. Politiques
 └─ tout va bien depuis adm01, pas dehors       → 7. Répartiteurs
```

Pré-requis d'accès : `adm01` avec ton kubeconfig personnel (lecture suffit), `hubble`, `cilium`, `dig`, SSH vers `gw01`/`gw02` (compte `supervision` ou personnel).

## 1. DNS

```
admin@adm01:~$ dig +short <NOM>                                   # attendu : 10.10.41.10
admin@adm01:~$ dig +short @10.10.20.10 -p 5300 <NOM>              # autoritaire primaire
admin@adm01:~$ dig @10.10.20.10 <NOM> +dnssec | grep -E 'status|flags'   # NOERROR, flag ad
admin@adm01:~$ kubectl -n <ESPACE> get httproute -o wide
admin@adm01:~$ kubectl -n external-dns logs deploy/external-dns --since=30m | tail -20
```

| Constat | Signification | Action / escalade |
|---|---|---|
| L'autoritaire a le nom, pas les récurseurs | cache négatif (TTL négatif 300 s) | attendre 5 min ; ne pas vider le cache sans raison |
| `SERVFAIL` partout sur `*.apps` | chaîne DNSSEC cassée (DS de `apps` dans `par1`) | P2 Plateforme (RB-064, délégation `envs/k8s/dns-apps.tf`) |
| Nom absent de l'autoritaire, route `Accepted` | ExternalDNS ne publie pas (journal : `REFUSED` = clé ou adresse refusée, la cause exacte est dans `journalctl -u pdns` sur `dns01` ; `NOTAUTH` = serveur qui ne fait pas autorité pour la zone visée ; ou filtre) | Plateforme ; vérifier l'étiquette `medisphere.internal/dns`, le domaine, la Gateway visée |
| Route non `Accepted` | voir 4 | — |

## 2. Adresse et annonce

```
admin@adm01:~$ kubectl -n passerelles get gateway gw-par1        # ADDRESS 10.10.41.10, PROGRAMMED True
admin@adm01:~$ kubectl -n passerelles get svc cilium-gateway-gw-par1   # EXTERNAL-IP 10.10.41.10
admin@adm01:~$ cilium bgp peers                                 # 6 sessions « established »
admin@gw01:~$ sudo vtysh -c 'show ip route 10.10.41.10'          # 3 prochains sauts 10.10.40.6x
admin@adm01:~$ kubectl get ippools                              # lb-par1 : DISABLED false, CONFLICTING False
```

| Constat | Signification | Action / escalade |
|---|---|---|
| `EXTERNAL-IP <pending>` | LB IPAM n'attribue pas (pool désactivé, épuisé, conflit, adresse prise) | Plateforme (`kubectl describe svc`, conditions) |
| Sessions absentes ou `active` | BGP tombé | RB-152 |
| Route absente d'une seule passerelle | session de cette passerelle tombée | RB-152 ; pas d'urgence si l'autre est maître |
| Route présente, `curl` expire quand même | voir 5 et 6 (le nœud reçoit, rien derrière) | — |

## 3. Certificat

```
admin@adm01:~$ openssl s_client -connect 10.10.41.10:443 -servername <NOM> </dev/null 2>/dev/null | openssl x509 -noout -issuer -subject -dates
admin@adm01:~$ kubectl -n passerelles get certificate apps-joker     # READY True
```

Expiré ou `READY False` → **RB-151**. Nom hors `*.apps` (ou sur deux niveaux, `a.b.apps…`) → le joker ne le couvre pas : demande de l'équipe à requalifier.

## 4. Route

```
admin@adm01:~$ kubectl -n <ESPACE> get httproute <ROUTE> -o jsonpath='{range .status.parents[*]}{.parentRef.name}{" "}{range .conditions[*]}{.type}={.status}({.reason}) {end}{"\n"}{end}'
admin@adm01:~$ kubectl get ns <ESPACE> --show-labels | grep exposition
```

| Condition | Signification | Escalade |
|---|---|---|
| `Accepted=False (NotAllowedByListeners)` | espace sans `medisphere.internal/exposition=oui` | Plateforme (décision d'exposition) |
| `Accepted=False (NoMatchingListenerHostname)` | nom hors `*.apps…` | équipe applicative |
| `ResolvedRefs=False (BackendNotFound / RefNotPermitted)` | Service ou port inexistant, autre espace sans `ReferenceGrant` | équipe applicative |

## 5. Service, EndpointSlices, pods

```
admin@adm01:~$ kubectl -n <ESPACE> get svc <SERVICE> -o wide
admin@adm01:~$ kubectl -n <ESPACE> get endpointslices -l kubernetes.io/service-name=<SERVICE>
admin@adm01:~$ kubectl -n <ESPACE> get pods -l <SÉLECTEUR DU SERVICE> -o wide
admin@adm01:~$ kubectl -n <ESPACE> get events --sort-by=.lastTimestamp | tail
```

EndpointSlice vide : sélecteur ou port cible faux, ou aucun pod prêt (`READY 0/1` : sonde de disponibilité, dépendance en panne) → équipe applicative, ou RB-140 si des nœuds sont `NotReady`.

## 6. Politiques

```
admin@adm01:~$ hubble observe -n <ESPACE> --verdict DROPPED --since 10m -o compact
admin@adm01:~$ hubble observe -n <ESPACE> --since 10m --protocol http -o compact | grep -E '403|DENIED'
admin@adm01:~$ kubectl -n <ESPACE> get netpol,cnp
```

Chute `Policy denied` de `ingress` (identité de la Gateway) vers le pod : politique d'entrée qui n'autorise pas `fromEntities: [ingress]` ; 403 L7 : méthode ou chemin absent de la politique. Changement récent ? (`git log` de `espaces/` dans `plateforme/k8s`). Escalade : propriétaire des politiques de l'espace (Plateforme pour MédiAgenda), avec l'extrait Hubble.

## 7. Répartiteurs (accès extérieur seulement)

```
admin@adm01:~$ curl -sS --resolve <NOM>:443:10.10.70.200 https://<NOM>/<SONDE>
admin@lb01:~$ sudo journalctl -u haproxy --since -15min | grep fe_tls_sni | tail
```

Refus immédiat : nom absent de `k8s_noms_publies` (voulu ? sinon MR). `be_k8s_gw_par1` DOWN : flux répartiteurs → 10.10.41.10:443 (matrice des flux) ou étape 2.

## Corriger

Uniquement par le code (MR sur `plateforme/k8s`, `plateforme/ansible`, `plateforme/infra`), sauf mesure d'urgence décidée avec l'astreinte et notée dans le ticket (et rattrapée par une MR le jour même).

## Retour à la normale

`curl` de l'arbre de décision vert depuis `adm01` (et depuis l'extérieur pour un nom publié), Hubble sans chute pendant 5 min, ticket clos avec la couche en cause, mise à jour de ce runbook si une étape a manqué.

## Historique

| Date | Version | Événement |
|---|---|---|
| <AAAA-MM-JJ> | 1.0 | Création (PLAT-1622). Essai : Service `essai-lb` de `wb-essais` au mauvais sélecteur, diagnostiqué à l'étape 5 en <N> min ; manquait : <CE QUI A MANQUÉ> |
