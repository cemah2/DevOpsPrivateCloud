# Reconstruire le réseau de `k8s-par1`

| | |
|---|---|
| **Portée** | Tout ce qui fait le réseau du cluster : Cilium, CRD Gateway API, LB IPAM, BGP, CoreDNS, cert-manager, ExternalDNS, `gw-par1`, politiques de MédiAgenda |
| **Références** | PLAT-1623 (M15-E23) ; `plateforme/k8s` : `Taskfile.reseau.yml`, `composants/versions.env` |
| **Durée mesurée** | <À MESURER> min pour `task reseau:installer` sur un cluster vide de réseau (cible : moins de 30 min) |

## 1. Prérequis hors du cluster (dépôts cités, rien n'est dupliqué)

| Prérequis | Où | Vérification |
|---|---|---|
| Bordure : groupe `K8S` ouvert, politiques, ECMP | `plateforme/ansible` `group_vars/role_routeur/frr.yml` | `sudo vtysh -c 'show bgp peer-group K8S'` sur `gw01`/`gw02` |
| Flux : TCP 179 (VLAN 40 → passerelles), `ca01` → 10.10.41.10:80, VLAN 40 → `dns01`:5300, `lb01`/`lb02` → 10.10.41.10:443 | `group_vars/role_routeur/pare_feu.yml`, `host_vars/dns01/pare_feu_local.yml` | `docs/socle/matrice-flux.md` à jour |
| Zone `apps` signée, clés TSIG, autorisations | `group_vars/role_dns/{powerdns_auth,dnssec,dnsupdate-k8s,vault-lab}.yml` | `dig @10.10.20.10 -p 5300 apps.par1.medisphere.internal SOA` |
| Délégation NS + DS de `apps` dans `par1` | `plateforme/infra` `envs/k8s/dns-apps.tf` | `dig apps.par1.medisphere.internal SOA +dnssec` : bit `ad` |
| Répartiteurs (publication extérieure) | `group_vars/role_lb/haproxy.yml` | `curl --resolve … 10.10.70.200` |
| Cluster lui-même (kubeadm, nœuds) | M14-E23 | `kubectl get nodes` |

## 2. Ordre (`task reseau:installer`)

1. CRD Gateway API (`v1.6.x`, canal standard, fichier vendu + empreinte) — **avant** Cilium, qui ne démarre son contrôleur Gateway que si elles existent.
2. Cilium (`cilium upgrade --values`) : remplacement de kube-proxy, Gateway API, BGP ; attente `cilium status --wait`.
3. Espaces (`passerelles`, `cert-manager`, `external-dns`), étiquettes de nœuds (`bgp=par1`).
4. Pool `lb-par1`, objets BGP ; CoreDNS.
5. Secrets TSIG depuis le Vault (`outils/secret-tsig.sh`).
6. cert-manager puis `step-ca-acme` (attente `Ready`).
7. ExternalDNS.
8. `gw-par1`, `redirection-https`, `apps-joker` (attente `Programmed` puis `Ready`).
9. Politiques et routes de MédiAgenda.

Chaque étape s'arrête à la première erreur (Task). Relancer `task reseau:installer` est sans danger : tout est déclaratif (`apply --server-side`, `helm upgrade --install`).

## 3. Vérifications

```
admin@adm01:~/src/k8s$ task reseau:derive             # « Aucune dérive. »
admin@adm01:~$ cilium bgp peers                        # 6 sessions établies
admin@adm01:~$ curl -sS https://mediagenda-recette.apps.par1.medisphere.internal/pret
admin@adm01:~$ for e in 10 11 12 13 14 15 17; do ~/DevOpsPrivateCloud/lab/bin/check 15 $e; done
```

## 4. Ce qui n'est PAS dans le dépôt (et pourquoi)

- Le Service `cilium-gateway-gw-par1`, les `CiliumBGPNodeConfig`, les `Order`/`Challenge`, les Secrets de certificats : **générés** par les contrôleurs.
- Les secrets TSIG : Vault `lab` de `plateforme/ansible` (recréés par l'outil).
- Les releases Helm : décrites par chart + version + values (Helmfile les reprendra au M17).

## 5. Preuve de reproductibilité

<Date, méthode choisie (ex. : désinstallation puis réinstallation d'ExternalDNS et de cert-manager hors heures, `m15-essai` comme cible d'essai, essai à blanc `kubectl apply --dry-run=server`), durée, résultat de `task reseau:derive` avant et après, incidents.>
