# Architecture du réseau de `k8s-par1` (réseau Kubernetes v1)

| | |
|---|---|
| **État** | `k8s-reseau-v1` (M15-E46) |
| **Décisions** | ADR-0150 (réseau et entrée du cluster) |
| **Exploitation** | RB-150 (service injoignable), RB-151 (certificat non délivré), RB-152 (BGP) ; `ms-verif-k8s-reseau` |
| **Flux** | `matrice-flux-cluster.md` (cluster), `docs/socle/matrice-flux.md` (bordure) |

> Modèle de corrigé : adapte les noms, versions et valeurs à ce que tu as réellement livré.

## Le chemin d'une requête

```
poste (MGMT ou extérieur par lb01/lb02, VIP 10.10.70.200, TLS en passage direct)
  │  DNS : mediagenda-recette.apps.par1.medisphere.internal → 10.10.41.10 (dns01/dns02, publié par ExternalDNS)
  ▼
bordure gw01/gw02 (VIP .1)  ── route /32 10.10.41.10 apprise en BGP (AS 65040 → 65000), ECMP sur k8s-w01..03
  ▼
nœud k8s-w0N (ens18) ── eBPF (cil_from_netdev) ── Service LoadBalancer de la Gateway ── Envoy (proxy L7 de Cilium)
  │  écouteur HTTPS *.apps… (joker apps-joker, cert-manager / step-ca), HTTPRoute « mediagenda »
  ▼
backend : pod de l'API (éventuellement sur un autre nœud : VXLAN chiffré par WireGuard, UDP 51871)
  │  politiques : default-deny + « ingress → API 8000 » ; API → PostgreSQL 5432, Valkey 6379, DNS
  ▼
MédiAgenda (port 8000)
```

## Composants et versions

| Composant | Version | Installé par | Configuration |
|---|---|---|---|
| Cilium (KPR, VXLAN, WireGuard, Hubble relay et UI, LB IPAM, BGP v2, Gateway API) | 1.20.x | CLI `cilium` (Helm) | `plateforme/k8s/composants/cilium/` |
| CRD Gateway API (canal standard) | v1.6.x | `kubectl apply --server-side` | `composants/gateway-api/` |
| CoreDNS | celui de kubeadm 1.36 | kubeadm | `composants/coredns/` |
| cert-manager | 1.21.x | Helm | `composants/cert-manager/` |
| ExternalDNS | 0.23.x | Helm | `composants/external-dns/` |

## Ce qui se passe quand…

| Panne | Effet | Détection | Retour |
|---|---|---|---|
| un travailleur s'arrête | ses sessions BGP tombent ; la bordure retire ses chemins (temps de maintien / redémarrage gracieux : **mesuré : N s**) ; ses pods sont recréés ailleurs | `ms-verif-k8s-reseau` (sessions), nœud `NotReady` | automatique |
| la passerelle de secours s'arrête | rien pour le trafic (la VIP est sur l'autre) | sonde de la bordure | automatique |
| la passerelle maître s'arrête | VRRP bascule la VIP ; la passerelle restante a déjà ses routes BGP ; **mesuré : N s** de perte | sonde de la bordure | automatique, retour sans préemption |
| l'agent Cilium d'un nœud redémarre | chemin de données conservé ; sessions BGP maintenues par le redémarrage gracieux | événements, `cilium status` | automatique |
| CoreDNS (un pod) | l'autre pod répond ; deux pods sur deux nœuds (PDB) | `ms-verif` (DNS depuis un pod) | automatique |
| cert-manager arrêté | rien d'immédiat ; aucun renouvellement | expirations surveillées | à rétablir avant 21 j |
| ExternalDNS arrêté | noms existants inchangés ; nouveaux noms non publiés | cohérence routes ⇔ noms | à rétablir |
| `ca01` arrêté | émissions et renouvellements impossibles | test ACME hebdomadaire | **point unique** (M06) |
| `dns01` arrêté | résolution par `dns02` ; **aucune mise à jour** (RFC 2136 sur le primaire seulement) | `ms-verif` | **point unique pour les mises à jour** |

## Ce qui n'est pas redondant

Un seul hyperviseur physique (`pve01`), un seul site, une seule autorité de certification (`ca01`), un seul autoritaire primaire pour les mises à jour (`dns01`), une seule Gateway. Modules qui les traiteront : F5 (PRA, PAR2), M25 (secrets et PKI), M29 (tests de résilience).

## Ce que consomment les modules suivants

- M16 : publication des interfaces (tableau de bord de stockage éventuel) par la Gateway ; politiques vers `ceph-par1` (VLAN 30, hors Cilium).
- M17 : le chart `mediagenda` produit la route, la politique d'entrée et l'étiquette d'espace décrites dans `publier-une-application.md`.
- M20 : GitOps reprend `plateforme/k8s/composants/` tel quel (détection de dérive native).
- M21 : métriques Cilium, Hubble, cert-manager, ExternalDNS déjà exposées ; tableaux de bord et alertes.
- M25 : secrets TSIG et compte ACME passent du Vault Ansible à OpenBao (External Secrets).
- M26 : Kyverno reprend les règles notées « au M26 » (étiquettes d'exposition, `dnsPolicy`, `CiliumNodeConfig`).
