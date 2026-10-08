# Cluster de virtualisation `hv-par1` — virtualisation MédiSphère v1

> Modèle (corrigé M09-E46). Document de référence de l'exploitation ; à tenir à jour par MR à chaque changement.

## 1. Architecture

```
                                pve01 (lab : hyperviseur physique)
   ┌───────────────────────────────────────────────────────────────────────────────────┐
   │  hv01 (2091)                 hv02 (2092)                 hv03 (2093)               │
   │  PVE 9.2, 4 vCPU, 12 Go      idem                        idem                      │
   │  MON MGR OSD×2               MON MGR OSD×2               MON MGR OSD×2             │
   │  zpool tank                  zpool tank                  zpool tank                │
   │  keepalived (VIP .200)       keepalived                  keepalived                │
   └──┬──────────┬──────────┬──────────┬──────────┬──────────────────────────────────────┘
      │ MGMT     │ COROSYNC │ STOR-PUB │ STOR-CLU │ trunk invités (VLAN 99, …)
      │ VLAN 10  │ VLAN 32  │ VLAN 30  │ VLAN 31  │ vmbr1 VLAN-aware dans les nœuds
      │ lien 1   │ lien 0   │ Ceph pub.│ Ceph clu.│ SDN : zone VLAN « invites », zone EVPN (AS 65090)
      │ API, VIP │          │ migration│          │
```

| Élément | Valeur |
|---|---|
| Nœuds | `hv01-03`, MGMT 10.10.10.51-53, COROSYNC 10.10.32.51-53, STOR-PUB 10.10.30.71-73, STOR-CLU 10.10.31.71-73 |
| Point d'accès de l'API | VIP keepalived 10.10.10.200 `hv.par1.medisphere.internal` (VRID 110) |
| Corosync | deux liens (0 : VLAN 32, 1 : MGMT), trois votes, pas de QDevice |
| Stockages | `ceph-vm` (RBD hyperconvergé, size 3 / min_size 2), `zfs-local` (pool `tank`, réplication), `local`/`local-lvm`, `pbs-par2` (sauvegardes, `par1/hv`, chiffrées) |
| HA | ressources par VM, règles d'affinité de nœud et de ressources, chien de garde émulé `i6300esb` (lab ; matériel en production) |
| Migration | `secure`, 10.10.30.0/24, `bwlimit` 300 Mio/s |
| Sécurité | pare-feu de cluster (`pve_pare_feu`), TOTP, certificats step-ca (renouvellement mTLS), SSH par clé |
| Supervision | `ms-verif-cluster` (5 min, `ms-alerte@`), `ms-capacite-cluster` (revue mensuelle) |
| Code | `plateforme/infra` (`hv`, `hv-invites`), `plateforme/ansible`, `plateforme/outils` |

## 2. Dépendances au socle

| Dépend de | Pour | Si indisponible |
|---|---|---|
| DNS (`dns01`/`dns02`) | noms des nœuds, de la VIP, ACME | cluster et VMs continuent ; nouveaux certificats et accès par nom impossibles |
| `ca01` | émission initiale des certificats 8006 ; renouvellements | certificats valides jusqu'à 30 jours ; alerte à 10 jours |
| `pbs01` (PAR2, `wg0`) | sauvegardes des VMs et de la configuration | plus de sauvegardes (alerte de la sonde à 26 h) ; aucun impact sur la production |
| `gw01`/`gw02` | sortie (dépôts, PBS), accès depuis le VPN | administration depuis `adm01` toujours possible (même VLAN) |
| `adm01` | administration, sonde | cluster autonome ; plus de supervision (point unique, voir § 4) |

## 3. Ce qui se passe quand…

| Panne | Effet | Rétablissement | Runbook |
|---|---|---|---|
| un nœud | VMs HA relancées ailleurs en ~3 min ; Ceph dégradé (2 copies) ; VMs non HA arrêtées | réparer ou RB-091 | RB-091 |
| un lien Corosync | aucun (second lien) | réparer le lien ; la sonde le signale | palier 4 |
| deux nœuds | perte de quorum : le nœud restant se redémarre (s'il porte des ressources HA) ; Ceph sans quorum de MON : I/O figées | rétablir un nœud | RB-091, palier 4 |
| un OSD | Ceph recopie (après 10 min, ou `noout` si maintenance) | remplacer le disque | RB-080 (M08), adapté |
| la VIP | API par les noms des nœuds toujours possible | keepalived | palier 4 |
| `pmxcfs` en lecture seule | plus aucune modification de configuration | voir causes (quorum, service) | palier 4 |

## 4. Points uniques de défaillance restants

- `pve01` : tout le cluster est imbriqué sur un seul hyperviseur (propre au lab ; en production, trois serveurs physiques).
- `adm01` porte la supervision : une sonde extérieure (PAR2) est à ajouter (module 21).
- Un seul réseau physique sous les VLAN (lab) : les « deux liens » Corosync partagent le même pont.
- Chien de garde émulé, pas matériel (lab).

## 5. Exploitation

- Maintenance d'un nœud : RB-090 ; reconstruction : RB-091 ; mises à jour : RB-092 (CHG-1059, changement standard) ; montée majeure de Ceph : CHG-1054 et playbook.
- Reconstruction complète depuis le code : `plateforme/infra`, `envs/hv/Taskfile.yml` (`task reconstruire`), mesures dans `tests/reconstruction-hv-par1.md`.
- Choix de plateforme pour une nouvelle charge : ADR-0090 ; capacité : `capacite-hv-par1.md`, règle d'acceptation par `ms-capacite-cluster`.

## 6. Ce que les modules suivants traiteront

M10 (OpenStack, recettes en libre-service, ADR-0090) ; M14 (nœuds Kubernetes sur `hv-par1`) ; M21 (métriques, alertes, sonde extérieure, latence Corosync) ; M22 (journaux d'accès et de tâches centralisés) ; M24 (identités et TOTP par Keycloak, realm LDAP/OIDC) ; M25 (secrets : jetons et clés) ; F1 (reconstruction avec le reste de la plateforme) ; F5 (PRA : cluster à PAR2 ?).
