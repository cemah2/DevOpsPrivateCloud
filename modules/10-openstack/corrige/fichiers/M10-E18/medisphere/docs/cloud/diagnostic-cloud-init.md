# Diagnostic : « l'instance ignore sa configuration »

> M10-E18 (PLAT-1128). Pour l'astreinte et le support. Du plus simple au plus profond ; s'arrêter dès que la cause est trouvée.

## 1. Côté API (sans entrer dans l'instance)

| Question | Commande | Normal |
|---|---|---|
| Les données ont-elles été transmises ? | `openstack server show <instance> -c user_data -c properties -c key_name -c config_drive` (administrateur : `--os-compute-api-version 2.3` pour voir `user_data`) | `user_data` non vide, encodé en base64 |
| L'instance a-t-elle une adresse et un port actif ? | `openstack port list --server <instance> --long` | port `ACTIVE` |
| Le sous-réseau a-t-il le DHCP ? | `openstack subnet show <sous-réseau> -c enable_dhcp` | `True` (sinon : config drive obligatoire) |

## 2. Console de l'instance

`openstack console log show <instance> | grep -iE 'cloud-init|ci-info|metadata'` : cloud-init imprime ses étapes, ses adresses (`ci-info`) et ses erreurs d'accès au service de métadonnées. « Failed to connect to 169.254.169.254 » ou une attente de 120 s : passer à 4.

## 3. Dans l'instance (SSH ou console)

```
cloud-init status --long          # done / error / running, et la source de données
cloud-init query --all | less     # ce que cloud-init a reçu (métadonnées, vendor data)
sudo cat /var/log/cloud-init.log | grep -E 'WARNING|ERROR|Traceback'
sudo cat /var/log/cloud-init-output.log   # sortie des commandes (runcmd, paquets)
cloud-init schema --system        # validité des données utilisateur
```
Causes fréquentes : en-tête `#cloud-config` absent ou précédé d'un espace ; YAML invalide (tabulations) ; paquet introuvable (sortie HTTP du VLAN 52, M10-E12) ; données fournisseur désactivées par l'utilisateur (`vendor_data: {enabled: false}`) ; données utilisateur qui redéfinissent `ntp` ou `ca_certs` (elles l'emportent).

## 4. Service de métadonnées (OVN)

Sur le calcul qui héberge l'instance (`openstack server show -c OS-EXT-SRV-ATTR:host`, administrateur) :
```
sudo docker ps --filter name=neutron_ovn_metadata_agent       # Up (healthy)
sudo ip netns | grep ovnmeta-<id du réseau>                   # l'espace existe
sudo ip netns exec ovnmeta-<id du réseau> ip -4 a             # 169.254.169.254 présent
sudo tail -50 /var/log/kolla/neutron/neutron-ovn-metadata-agent.log
```
Puis sur `osctl01` : `sudo tail -50 /var/log/kolla/nova/nova-metadata.log` (requêtes reçues, erreurs de signature « metadata_proxy_shared_secret »).

## 5. Contournement

Recréer l'instance avec `--use-config-drive` : la configuration arrive par un disque, sans réseau. Ouvrir un incident si le service de métadonnées est en cause.
