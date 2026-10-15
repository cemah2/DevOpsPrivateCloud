# Module 15 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

### M15-E46 — Mini-projet : réseau Kubernetes MédiSphère v1

Il n'y a pas de solution unique : ce corrigé donne un **plan de travail** éprouvé, les points de contrôle de chaque étape, la préparation des deux démonstrations et la **grille de revue** avec laquelle Claire, Karim, Sophie, Nadia et Julien évaluent la livraison. Les fichiers de référence sont ceux des exercices du module ; les nouveaux sont le modèle d'[`architecture.md`](fichiers/M15-E46/medisphere/docs/kubernetes/reseau/architecture.md), la page de libre-service [`publier-une-application.md`](fichiers/M15-E46/medisphere/docs/kubernetes/reseau/publier-une-application.md), et les outils de détection de dérive (`derive-reseau.sh` de M15-E23 et [`derive-bordure-noeuds.sh`](fichiers/M15-E43/plateforme-k8s/outils/derive-bordure-noeuds.sh) du palier 4), qui servent ici de check-list « rien hors du dépôt ».

**Solution**

*Plan de travail recommandé* (dans cet ordre : chaque étape supprime une source d'écart pour la suivante)

1. **État des lieux** (1 h) : `lab/bin/check 15 46`, puis les contrôles détaillés rouges, `lab/bin/check 14 46` (le cluster) et `outils/derive-reseau.sh` + `outils/derive-bordure-noeuds.sh` (dépôt contre réalité). Inventaire des restes :
   ```
   admin@adm01:~$ kubectl get gateway,httproute,grpcroute,tlsroute -A
   admin@adm01:~$ kubectl get cnp,ccnp,netpol -A
   admin@adm01:~$ kubectl get svc -A --field-selector spec.type=LoadBalancer
   admin@adm01:~$ kubectl get certificates,ciliumnodeconfigs,referencegrants -A
   admin@adm01:~$ ls ~/.local/state/workbook/pannes-actives/
   ```
   Chaque objet est soit dans le dépôt (et justifié), soit supprimé : `gw-essai` et les routes de démonstration de E07/E16, les Services jetables de E10, les politiques d'essai de E06/E28, la `TLSRoute` de E16 (et la CRD expérimentale si plus rien ne l'utilise : avertissement de E16 sur la disparition des objets), les certificats d'essai de E13.
2. **`m15-essai`** (30 min) : `tofu destroy` de l'état `m15-essai` (MetalLB et ingress-nginx de comparaison partent avec la VM), objets NetBox et enregistrements DNS par le même code ; `qm status 2151` doit répondre « inexistant ». Vérifier qu'aucune IngressClass `nginx` n'existe sur `k8s-par1`.
3. **Le cluster par le code** (2 à 3 h) : `kubectl diff` sans écart sur tous les composants (`task reseau:derive`, M15-E23) ; `kubeadm` : `proxy.disabled: true` dans la `ClusterConfiguration` de `cluster/kubeadm-config.yaml` (M15-E08 : `kubeadm upgrade` saute alors l'extension kube-proxy) et consigne vérifiée dans RB-142 (M14) ; CoreDNS par `composants/coredns/`. Reconstruction de la configuration réseau sur un cluster vide **répétée** (kind jetable sur `adm01` ou `m15-essai` recréée le temps de l'essai puis détruite) : c'est la démonstration de Karim.
4. **L'entrée** (2 h) : sessions BGP (`cilium bgp peers`, deux par nœud sélectionné), routes sur `gw01` **et** `gw02` (`derive-bordure-noeuds.sh --bordure` sans écart), redémarrage gracieux mesuré et écrit dans l'ADR-0150 ; Gateway durcie (E33) ; joker `Ready` et date de renouvellement connue ; ExternalDNS publie et nettoie (route jetable créée puis supprimée) ; publication externe vérifiée par la VIP des répartiteurs :
   ```
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' --resolve mediagenda-recette.apps.par1.medisphere.internal:443:10.10.70.200 https://mediagenda-recette.apps.par1.medisphere.internal/sante
   200
   ```
5. **Politiques** (1 à 2 h) : refus par défaut (`refus-par-defaut`, M15-E17) dans `mediagenda-dev` **et** `mediagenda-recette` (le contrôle vérifie les deux), autorisations de E17 rejouées dans `mediagenda-dev`, CCNP de base (E28), Hubble UI restreinte ; test de non-régression des politiques (E37, pour aller plus loin) dans le pipeline si tu l'as écrit.
6. **Libre-service** (1 h) : [`publier-une-application.md`](fichiers/M15-E46/medisphere/docs/kubernetes/reseau/publier-une-application.md), vérifiée en refaisant la publication de MédiDoc en `medidoc-dev` avec les seuls droits du groupe `medisphere:mediagenda-devs` (ou d'un groupe MédiDoc créé au M14-E33) : `kubectl --as=… --as-group=…` pour montrer que l'équipe peut créer route et politique d'entrée, mais pas modifier la Gateway ni l'étiquette de son espace.
7. **Exploitation** (1 à 2 h) : `ms-verif-k8s-reseau` planifié avec les contrôles ajoutés au palier 4 (sessions et routes par passerelle, conditions Gateway/routes, expirations, cohérence noms, `cilium-health`, `DROPPED` par espace) ; RB-150 complété (E35), RB-151 (E40), RB-152 (E38) publiés.
8. **Bordure et flux** (1 h) : `group_vars/role_routeur/pare_feu.yml` et `docs/socle/matrice-flux.md` (BGP 179 depuis 10.10.40.0/24 vers les passerelles ; VLAN 40 → autoritaire de `dns01` TCP/UDP 5300 pour RFC 2136 ; MGMT et DMZ → 10.10.41.0/24 en 80/443 ; aucun flux pour WireGuard, intra-VLAN : écrit) ; matrice des flux du cluster à jour (ports 8472 et 51871 entre nœuds, qu'aucun « durcissement » ne doit fermer).
9. **Documentation et livraison** (3 à 4 h) : `architecture.md` ([modèle](fichiers/M15-E46/medisphere/docs/kubernetes/reseau/architecture.md)) avec les temps **mesurés** des démonstrations, ADR-0150, matrice, runbooks, analyses (E29, E44), page de libre-service, registre des secrets (clés TSIG `externaldns-k8s` et `certmanager-k8s` : Vault `lab` et Secrets des espaces `external-dns` et `cert-manager` ; compte ACME de l'émetteur : Secret de `cert-manager` ; jamais de valeur) ; MR, pipelines verts, étiquette `k8s-reseau-v1`.

*Démonstration de Nadia — un travailleur, puis la passerelle de secours* (à répéter **avant** la revue)

| Étape | Action | Attendu |
|---|---|---|
| 1 | Sur `adm01` : boucle de mesure `while :; do curl -s -o /dev/null -w '%{http_code} %{time_total}\n' --max-time 2 https://mediagenda-recette…/pret; sleep 0.2; done \| tee mesure.txt` | `200` |
| 2 | `qm shutdown 2145` (`k8s-w02`) depuis `pve01`, ou arrêt brutal `qm stop` pour le cas pire | — |
| 3 | `cilium bgp peers`, `vtysh -c 'show bgp summary'` sur `gw01` | sessions de `k8s-w02` tombées (immédiatement à l'arrêt propre : NOTIFICATION ; après le temps de maintien ou le redémarrage gracieux à l'arrêt brutal) |
| 4 | Boucle | quelques erreurs ou délais au moment de l'arrêt (flux en cours vers `k8s-w02`), puis `200` ; durée mesurée et notée |
| 5 | Supervision (≤ 5 min) | alerte de `ms-verif-k8s-reseau` : sessions et nœud manquants |
| 6 | `qm start 2145`, attendre `Ready` et les sessions | retour sans intervention |
| 7 | `qm shutdown` de la passerelle de **secours** (vérifier d'abord laquelle porte la VIP : `ip addr` sur les deux) | **aucune** erreur dans la boucle : la VIP n'a pas bougé ; alerte de la sonde de bordure ; redémarrage, sessions rétablies |

Points de discussion attendus : pourquoi l'arrêt brutal coûte plus que l'arrêt propre (temps de maintien, redémarrage gracieux qui garde des routes vers un nœud mort : intérêt de BFD) ; pourquoi la perte de la passerelle de secours est invisible, et ce qui se passerait avec la maître (VRRP, routes BGP déjà présentes sur l'autre : c'est la preuve que la panne latente de E38 v5 aurait été grave) ; ce que `externalTrafficPolicy` change à l'étape 4.

*Démonstration de Julien — nouvelle route en direct* : avec son kubeconfig, dans `medidoc-dev`, la route et la politique de la page de libre-service ; chronomètre jusqu'au premier `200` (attendu : 1 à 3 minutes, l'essentiel étant l'intervalle d'ExternalDNS et le cache négatif des résolveurs : interroger `dns01` directement montre le nom avant `adm01`, dont le récurseur a peut-être mis en cache un `NXDOMAIN` — durée du cache négatif = TTL minimal du SOA de la zone `apps`).

**Explications**

Le mini-projet vérifie surtout la **cohérence** et l'**absence de dérive** : chaque brique a été construite dans un exercice, mais la livraison exige qu'elles tiennent ensemble et que le dépôt dise exactement ce qui tourne. Le palier 4 a montré que la plupart des pannes réelles du réseau d'un cluster sont des écarts entre l'intention (le dépôt) et la réalité (un objet modifié à chaud, un script tiers, une surcharge oubliée) : d'où la place de `derive-reseau.sh` et de la reconstruction depuis le dépôt dans la revue. Le contrôle global revérifie aussi ce que le module a promis aux suivants : un chemin de publication en libre-service (M16, M17), des objets reprenables par GitOps (M20), des métriques exposées (M21).

**Alternatives**
- Garder `m15-essai` comme cluster de recette des changements réseau : utile en production (pré-production du chemin de données), mais 4 Go permanents ; écarté par le PLAN, à rediscuter dans l'ADR-0150 pour la suite.
- Plusieurs Gateway (une par environnement, ou une interne et une exposée) plutôt qu'une seule : isolement des écouteurs et des certificats, au prix d'adresses et d'objets en plus ; la Gateway unique est le compromis du lab, noté comme point unique.
- Publication externe en terminaison TLS sur `lb01`/`lb02` plutôt qu'en passage direct : les répartiteurs verraient le trafic en clair et devraient porter un certificat de la zone `apps` ; écarté (une seule terminaison, dans le cluster).

**Pièges classiques**
- Corrections du palier 4 restées à chaud : `kubectl diff` les révèle, la reconstruction de Karim les perd.
- `m15-essai` détruite à la main dans Proxmox : l'état OpenTofu et NetBox gardent la VM.
- Politiques de `mediagenda-dev` oubliées (seul `recette` a été soigné pendant le module).
- Démonstration de Nadia jamais répétée : la passerelle « de secours » était la maître ce jour-là (pas de préemption : la VIP reste où elle a basculé la dernière fois).
- Secret TSIG copié dans la documentation « pour référence » : le contrôle global le cherche.

**En production chez MédiSphère**
Deux Gateway au moins (interne et exposée) sur des nœuds dédiés, BFD vers la bordure, GitOps avec détection de dérive (M20), alertes sur les causes du palier 4 (M21), revue trimestrielle des politiques et des noms publiés, et un exercice de reprise semestriel (perte d'un nœud, d'une passerelle, de `ca01`, de `dns01`) dont les résultats complètent `architecture.md`.

**Grille de revue (auto-évaluation si tu travailles seul)**

| Relecteur | Critère | Attendu |
|---|---|---|
| Claire | Contrôle global | `lab/bin/check 15 46` entièrement vert, sans contrôle ignoré |
| Claire | Rien de provisoire | `m15-essai` absente (Proxmox, état OpenTofu, NetBox, DNS), aucun objet d'essai non justifié, aucune panne active |
| Claire | Points uniques | listés dans `architecture.md` avec l'impact et le module qui les traitera |
| Karim | Code | `plateforme/k8s` décrit tout (valeurs, CRD, politiques, espaces), `derive-reseau.sh` et `derive-bordure-noeuds.sh` sans écart, reconstruction depuis le dépôt réussie, MR relues |
| Karim | Bordure | voisins et politiques par Ansible, configuration courante de FRR identique au fichier sur les deux passerelles, aucun `restart` pendant le module |
| Sophie | Politiques | refus par défaut dans les deux environnements, autorisations au plus juste, refus explicites justifiés, Hubble UI restreinte |
| Sophie | Documents | ADR-0150, matrice des flux du cluster et de la bordure, registre des secrets (emplacements seulement), aucune clé en clair |
| Sophie | TLS | TLS 1.2 minimum, HSTS, joker par cert-manager, aucune clé privée hors des Secrets prévus |
| Nadia | Résilience | démonstrations répétées, temps mesurés et écrits, supervision qui alerte, retour sans intervention |
| Nadia | Runbooks | RB-150, RB-151, RB-152 à jour des pannes du palier 4, post-mortem INC-4250 publié |
| Julien | Libre-service | nouvelle route publiée en HTTPS valide en moins de 5 minutes, sans ticket ; page claire sur ce qui exige un ticket |
| Tous | Présentation | 10 minutes : le chemin d'une requête, les compromis, ce qui n'est pas redondant, ce que M16, M17, M20, M21 et M25 consommeront |

Une livraison est acceptée quand tous les critères sont remplis ; un critère manquant est noté comme action (responsable, échéance) dans le compte rendu de recette, jamais passé sous silence.
