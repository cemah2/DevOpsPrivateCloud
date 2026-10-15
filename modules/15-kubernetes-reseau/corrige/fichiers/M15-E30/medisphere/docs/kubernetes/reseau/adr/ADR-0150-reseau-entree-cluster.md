# ADR-0150 — Réseau et entrée du cluster `k8s-par1`

- **Statut** : accepté
- **Date** : <DATE>
- **Décideurs** : Claire Morel, Karim Benali, Sophie Laurent, <MOI>
- **Tickets** : PLAT-1630 ; mesures SEC-1624 (E24), PLAT-1625 (E25), PLAT-1629 (E29)

## Contexte

Cluster kubeadm unique (`k8s-par1`, 3 nœuds de contrôle, 3 travailleurs) sur un seul site, nœuds dans le VLAN 40,
adresses de service dans 10.10.41.0/24 ; bordure `gw01`/`gw02` en VRRP (`nopreempt`) avec FRR AS 65000 et une
politique « rien sans filtre » ; répartiteurs `lb01`/`lb02` en DMZ. Données de santé (HDS) : chiffrement en transit,
cloisonnement, traçabilité. Petite équipe : une seule pile à connaître. ingress-nginx est **retiré par son projet**
depuis mars 2026 (plus aucun correctif). Versions : Kubernetes 1.36, Cilium 1.20, Gateway API v1.6 (canal standard).

## Décisions

| # | Sujet | Options envisagées | Décision |
|---|---|---|---|
| 1 | CNI | Cilium ; Calico (eBPF ou iptables) ; Flannel + NetworkPolicy tierce | **Cilium** |
| 2 | Services | kube-proxy iptables ; kube-proxy nftables ; remplacement eBPF de Cilium | **remplacement eBPF** (`kubeProxyReplacement: true`) |
| 3 | Entrée | Gateway API de Cilium ; un autre contrôleur Gateway API (Envoy Gateway, Traefik) ; ingress-nginx 1.15.1 figé | **Gateway API de Cilium** |
| 4 | Annonce des adresses | BGP de Cilium ; annonces L2 de Cilium ; MetalLB (L2 ou BGP) | **BGP de Cilium** vers la bordure |
| 5 | Routage des pods | tunnel VXLAN ; routage natif | **VXLAN** |
| 6 | Chiffrement entre nœuds | aucun ; WireGuard de Cilium ; IPsec de Cilium | **WireGuard**, flux entre pods |
| 7 | Certificats et noms | cert-manager + ACME de `ca01` + ExternalDNS RFC 2136 ; certificats et enregistrements à la main | **cert-manager + ExternalDNS** |

## Critères et faits

| # | Critère principal | Faits à l'appui |
|---|---|---|
| 1 | une seule pile pour CNI, politiques L3-L7, observabilité, entrée, BGP | Hubble (E05), politiques L7 et `toFQDNs` (E17, E28), Gateway (E12), BGP (E11) sans composant supplémentaire ; Calico couvre CNI + BGP mais pas l'entrée ni Hubble |
| 2 | prérequis de la Gateway de Cilium ; une source de vérité | la Gateway API de Cilium 1.20 **exige** `kubeProxyReplacement: true` (documentation) ; mode ipvs de kube-proxy déprécié (1.36) |
| 3 | correctifs de sécurité, rôles séparés (plateforme / équipes), portabilité | ingress-nginx : aucun correctif depuis mars 2026, inacceptable pour des données de santé sur un cluster qui doit durer ; migration des Ingress d'InfoGér réalisée (E18) ; un autre contrôleur ajouterait un composant et un Envoy de plus |
| 4 | répartition réelle, pas de dépendance à l'ARP, filtrage par la bordure | BGP : multichemin vers les trois travailleurs (E25), filtré par `PL-DEPUIS-K8S` ; annonces L2 : un seul nœud par adresse, aucune répartition, bascule par ARP gratuit ; MetalLB : équivalent fonctionnel (E19) mais un composant de plus |
| 5 | indépendance vis-à-vis du réseau sous-jacent | natif : +15 % de débit seulement (E29), exige un seul domaine L2 ou l'annonce des PodCIDR à la bordure (refusée par sa politique) |
| 6 | exigence HDS « en transit », coût, gestion des clés | WireGuard : clés gérées par les agents, aucune rotation à organiser ; coût mesuré −60 % de débit, ×2 processeur (E24) ; IPsec : clés à gérer, aucun matériel d'accélération |
| 7 | aucun ticket pour un nom ou un certificat ; clés limitées à une zone | TSIG limité à `apps.par1.medisphere.internal` (E14), certificats de 30 jours renouvelés seuls (E13), noms publiés en moins de 2 min (E15) |

## Conséquences

Positives : une seule pile à connaître ; trafic entre pods chiffré ; entrée HTTPS et noms en libre-service pour les
équipes ; convergence mesurée (E25 : perte d'un travailleur ≈ 9 à 30 s pour un tiers des requêtes, mise à jour sans
interruption mesurée).

Négatives (assumées) :
- **dépendance à un seul projet** (Cilium) pour le CNI, les Services, l'entrée et le BGP : une régression de Cilium touche tout ; atténuation : correctifs suivis (RB-153), retour arrière testé (E27) ;
- **limites de la Gateway de Cilium 1.20** : options TLS des écouteurs ignorées, pas de validation de certificat client (E33) : authentification mutuelle par *passthrough* vers un relais nginx (dette à revoir à chaque mineure) ;
- coût du chiffrement (processeur) et de l'Envoy de chaque nœud (mémoire) ;
- Hubble UI sans authentification jusqu'au module 24 ;
- l'entrée dépend de FRR sur la passerelle **maître** (RB-152 : bascule manuelle).

## Actions

| Action | Module / date |
|---|---|
| Métriques de Cilium, Hubble, cert-manager dans Prometheus, alertes | M21 |
| Authentification OIDC devant Hubble UI | M24 |
| Politiques d'admission : noms d'hôte des routes, interdiction des politiques Cilium hors plateforme | M26 |
| Montée 1.21 de Cilium dès qu'elle supporte Kubernetes 1.36 et 1.37 | ADR-0141, trimestriel |
| Réévaluer `nodeEncryption` et le mode strict de WireGuard | +6 mois |
| Réévaluer la validation client native de la Gateway | à chaque mineure de Cilium |

## Conditions de révision

Second site ou cluster de production séparé (Cluster Mesh ?) ; vraie fabric de commutateurs (BGP des PodCIDR,
routage natif) ; une mesure de E29 qui changerait d'ordre de grandeur sur du matériel réel ; un projet Cilium qui
cesserait de suivre les mineures de Kubernetes.
