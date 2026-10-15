# Talos Linux — fiche de l'essai `talos-essai`

> M18-E05 et E06 (PLAT-1905, CHG-1906). Code : `envs/m18/talos.tf` et `talos-schema.yaml`
> (`plateforme/infra`), `talos/` (`plateforme/distributions`).

## Image

- Image Factory, schéma `talos-schema.yaml` (extension `siderolabs/qemu-guest-agent`), identifiant
  `ce4c9805…7515` (empreinte du contenu : même schéma = même identifiant, partout) ;
- disque **nocloud** `nocloud-amd64.raw.zst` téléchargé par Proxmox, empreinte fixée ;
- installeur (montées de version) : `factory.talos.dev/nocloud-installer/<schéma>:<version>`
  (plus d'image `ghcr.io/siderolabs/installer` depuis Talos 1.14).

## Ce qui est versionné, ce qui ne l'est pas

| Versionné (`plateforme/distributions`) | Jamais versionné en clair |
|---|---|
| `talos/versions.env`, `noeuds.txt`, `noeuds/*.yaml`, `patches/` | `controlplane.yaml`, `worker.yaml` (contiennent les autorités et jetons) |
| `generer.sh`, `appliquer.sh` | `talosconfig` (clé du client `os:admin`) |
| `secrets/talos-secrets.yaml.vault` (chiffré) | `talos-secrets.yaml` (bundle en clair, `~/.config/workbook/m18/`, 600) |

## Cycle

1. `generer.sh` → `~/.cache/m18/talos/` ; 2. `appliquer.sh talos-0N --maintenance` (premier
contact, `--insecure`) ; 3. `talosctl bootstrap` une seule fois sur `talos-01` ;
4. `talosctl kubeconfig` → `~/.config/workbook/m18/talos.kubeconfig` ; 5. ensuite, toute
modification = patch dans le dépôt, `generer.sh`, `appliquer.sh <nœud> --essai` puis sans option.

## Exploiter sans SSH

| Besoin | Commande |
|---|---|
| état d'ensemble | `talosctl -n 10.10.99.85 health` (après E06, sans découverte : `--control-plane-nodes 10.10.99.85 --worker-nodes 10.10.99.86,10.10.99.87`), `talosctl dashboard` |
| services | `talosctl -n <ip> service` (`service kubelet status`) |
| journaux | `talosctl -n <ip> logs kubelet --tail 50`, `logs machined`, `dmesg` |
| ressources | `talosctl -n <ip> get <type>` (`members`, `hostname`, `addresses`, `routes`, `extensions`, `machineconfig`) |
| système | `talosctl -n <ip> memory`, `processes`, `mounts`, `disks`, `netstat`, `time` |
| configuration | `talosctl -n <ip> get machineconfig -o yaml`, `talosctl patch mc …` |

## Ce qui manque par rapport à Debian

Pas d'agent de supervision installé à la main (extensions ou DaemonSets), pas de SSH de secours
(console série en lecture et `talosctl` seulement), pas d'Ansible : l'inventaire NetBox n'a pas ces
VMs (écart noté) ; la sauvegarde PBS des VMs a moins d'intérêt (l'état est etcd + la configuration).

## Écarts notés

- `DiscoveryServiceConfig` par défaut : envoie des données chiffrées de membres au service public
  `discovery.talos.dev` (Sidero) : supprimé en E06 (souveraineté, HDS).
- Adresses fixes sur `vsandbox` (10.10.99.85-87) au lieu du DHCP : point d'accès stable.
