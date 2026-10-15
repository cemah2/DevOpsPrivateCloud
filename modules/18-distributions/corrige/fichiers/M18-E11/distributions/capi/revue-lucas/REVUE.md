# Revue de la MR !7 « capi : cluster de recette pour l'équipe MédiAgenda » (M18-E11, PLAT-1911)

> Relue par l'équipe Plateforme. Gravité : **bloquant** (ne doit pas être appliqué),
> **majeur** (ne marchera pas, ou nous expose), **mineur** (à corriger, sans urgence).
> Validation : `kubectl apply --dry-run=server` contre le cluster de gestion dans un espace d'essai ;
> `--dry-run=client` ne lit pas les schémas des CRD ni les webhooks.

## Secrets et droits

- **Bloquant** — `identifiants.yaml` : jeton Proxmox **en clair dans le dépôt** (l'historique Git le garde même après suppression). → Supprimer le fichier, purger la branche, **révoquer** le jeton ; créer le Secret depuis `adm01` (`capi/identifiants.sh`).
- **Bloquant** — jeton `root@pam!capi` : tous les droits sur `pve01` (et toutes les VMs, personnelles comprises) pour un contrôleur qui tourne dans un cluster. → `wb-capi@pve!capi` (rôle `WBCapi` sur le pool `lab`, M18-E08).
- **Bloquant** — Secret sans clé `insecure` ni `root_ca` : CAPMOX v0.9.1 **désactive la vérification TLS** quand `insecure` est absente (`pkg/scope/cluster.go`) ; le jeton part vers n'importe quel serveur qui se fait passer pour `pve01`. → `insecure: "false"` et `root_ca` = ancre de `pve01`.
- **Majeur** — `users: root` avec la clé du **portable personnel** de Lucas : accès root à tous les nœuds par une clé hors de notre gestion (pas d'expiration, pas de révocation). → compte `admin`, clé de `adm01` seulement (et, au M24, certificats SSH courts).
- **Mineur** — URL `https://192.168.1.20:8006` écrite en dur (adresse du LAN maison) : → la valeur vient de `pve-capi.env` (`<IP-PVE01>`), et le certificat de `pve01` doit porter ce que l'on appelle.

## Adresses et réseau

- **Bloquant** — VIP `10.10.40.155` **dans** la plage des nœuds (`10.10.40.150-169`) : l'IPAM peut donner cette adresse à une machine ; deux hôtes répondront en ARP pour la même adresse. Et la plage est celle de `capi-essai` : les deux clusters se disputeront les mêmes adresses. → VIP hors plage (`.211`), plage propre (`.170-.179`).
- **Majeur** — pods en `192.168.0.0/16` (valeur du gabarit) : chevauche le LAN maison (`<LAN-MAISON>`, ex. 192.168.1.0/24) ; les nœuds ne joindraient plus `pve01` ni les postes. → `10.244.0.0/16` (et services `10.96.0.0/12` explicites).
- **Majeur** — `bridge: vsandbox` : VLAN 99 en DHCP, alors que les adresses viennent de l'IPAM du VLAN 40 (passerelle 10.10.40.1) ; aucune route, aucun accès à Harbor par les règles du VLAN 40. → `vk8s`.
- **Majeur** — `dnsServers: 8.8.8.8, 8.8.4.4` : la bordure n'autorise le DNS que vers `dns01`/`dns02`, et les noms internes (`registry.par1.medisphere.internal`) n'existent pas chez Google. → `10.10.20.10`, `10.10.20.16`.
- **Mineur** — pas de NTP : l'horloge des nœuds dérive, etcd et les certificats n'aiment pas cela. → `ntp.servers: [10.10.40.1]`.

## Image, version, stockage

- **Bloquant** — `KubeadmControlPlane.version: v1.36.5` alors que le template 9060 contient kubeadm/kubelet **1.36.4** : `kubeadm init` échoue (les binaires de la machine ne sont pas à la version demandée) ; en outre, le `MachineDeployment` est en v1.36.4. → v1.36.4 partout tant que l'image est 9060 ; une nouvelle version = un nouveau template (9061) et de nouveaux `ProxmoxMachineTemplate`.
- **Majeur** — `templateSelector` avec `matchPolicy: subset` : **refusé par l'API** (valeurs `exact`, `uniqueSubset`, `bestSubset` ; la documentation de CAPMOX parle de `resolutionPolicy`/`subset`, le code non) ; et `matchTags: [capi]` désignera plusieurs templates dès que 9061 existera. → `templateID: 9060` (choix explicite), ou un sélecteur assez précis (`k8s-v1.36.4`).
- **Majeur** — `format: qcow2` sur `local-nvme` (LVM-thin ou ZFS, stockage bloc) : le clone échoue. → ne pas préciser de format (le template est brut).
- **Majeur** — pas de `pool: lab` : le jeton `wb-capi` n'a `VM.Allocate` que sur ce pool, le clone sera **refusé** ; et les VMs seraient hors du périmètre du lab. → `pool: lab` (+ étiquettes `env-m18`, `recette-agenda`).
- **Majeur** — `vmIDRange` 5180-5199 : déborde sur **5191-5193** (banc k3s HA de M18-E07, PLAN §4.6). → 5180-5189.

## Disponibilité et ressources

- **Majeur** — plan de contrôle à **2** nœuds : etcd a besoin de 2 membres sur 2 pour écrire ; la perte d'un seul nœud arrête l'API. Deux nœuds sont **moins** disponibles qu'un. → 1 (recette, assumé) ou 3.
- **Majeur** — nœud de contrôle à 1 vCPU / 1 Gio : le contrôle préalable de kubeadm refuse moins de 2 vCPU (`NumCPU`), et 1 Gio ne suffit pas à etcd + kube-apiserver. → 2 vCPU, 4 Go.
- **Majeur** — kube-vip `:latest` et **sans** le correctif `super-admin.conf` : version non reproductible, et avec Kubernetes ≥ 1.29 kube-vip n'a aucun droit pendant `kubeadm init` → il ne prend jamais la VIP, l'init attend une API injoignable. → `v1.2.4` et le script de préparation du gabarit de CAPMOX.

## Ce qui ne marchera jamais

- **Majeur** — `ClusterResourceSet` sélectionne `cni: calico` alors que le `Cluster` porte `cni: cilium` : Cilium n'est jamais installé, les nœuds restent `NotReady`. → mêmes étiquettes ; et le ConfigMap `cilium` doit exister **dans l'espace** `recette-agenda`, rendu avec la VIP de ce cluster.
- **Mineur** — `strategy: Reconcile` : le CRS réapplique Cilium à chaque changement du ConfigMap, en concurrence avec une future montée de version par Helm. → `ApplyOnce` (ou le fournisseur d'extensions Helm de CAPI).
- **Mineur** — `allowedNodes`/`sourceNode: "pve01"` : `pve01` est le nom du lab, pas forcément celui du nœud Proxmox (`pvesh get /nodes`). → `<NOEUD>`.
- **Mineur** — pas de racine MédiSphère ni de miroirs Harbor : images tirées d'Internet, quotas de Docker Hub. → fichiers comme dans `capi-essai`.

## Pour la suite

« `--dry-run=client` passe » ne prouve que la syntaxe YAML. Tester : `kubectl apply --dry-run=server`
sur le cluster de gestion (schémas et webhooks de CAPI et CAPMOX), puis relire la cohérence avec le
plan (adresses, VMID, VNet) et avec l'image (version) — ce qu'aucun outil ne voit. Mémoire : ce
second cluster ajoute 12 Go ; il ne sera appliqué qu'après l'ADR-0180.
