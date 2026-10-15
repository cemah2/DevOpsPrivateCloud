# kind — clusters de développement (M18-E02)

Fichier : `dev.yaml` (1 nœud de contrôle, 2 travailleurs, Kubernetes 1.36.4 à l'empreinte fixée).

    kind create cluster --config ~/src/distributions/kind/dev.yaml     # ≈ 1 à 2 min
    kubectl --context kind-dev get nodes
    kind delete cluster --name dev                                     # rien ne reste

## Ce que c'est

Chaque nœud est un **conteneur Docker privilégié** qui fait tourner systemd, containerd et le
kubelet (`docker exec dev-worker ps -e`) ; le plan de contrôle est installé par **kubeadm**, comme
`k8s-par1`. Privilégié parce que containerd et le kubelet doivent créer des espaces de noms, des
cgroups, monter des systèmes de fichiers et régler le réseau **à l'intérieur** du conteneur.

## Images locales

Une image construite par `docker build` est dans le magasin d'images de **Docker** sur
`m18-dev01`. Les nœuds kind ont leur **propre** containerd : ils ne la voient pas, et aucun
registre ne la connaît (`ErrImagePull`). `kind load docker-image medisphere/essai:local --name dev`
l'exporte (`docker save`) et l'importe dans le containerd de chaque nœud (`ctr -n k8s.io images
import`). Le pod doit alors utiliser `imagePullPolicy: IfNotPresent` (ou `Never`) : avec `:latest`
ou `Always`, le kubelet tente quand même un tirage. Vérification : `docker exec dev-worker crictl images | grep essai`.

## Cache Harbor

`containerdConfigPatches` fait lire `/etc/containerd/certs.d/` (format de configuration v2 de
l'image de nœud) ; `extraMounts` y monte `certs.d/` de ce dépôt et la racine MédiSphère de l'hôte.

## Limites constatées

- **LoadBalancer** : un Service `LoadBalancer` reste `<pending>` (pas de contrôleur de répartition ;
  `cloud-provider-kind` existe, mais ce n'est pas notre réseau).
- **Redémarrage de `m18-dev01`** : les conteneurs nœuds ont une politique de redémarrage
  (`restart: on-failure:1`, d'après `docker inspect`) : le cluster revient le plus souvent, mais les
  adresses des conteneurs peuvent changer ; kind ne le garantit pas. Un cluster kind se **recrée**.
- **`kubectl top`** : pas de metrics-server installé.
- **Réseau, stockage, noyau** : un seul noyau (celui de `m18-dev01`) pour tous les « nœuds » ; pas de
  vrai réseau entre nœuds (pont Docker), stockage `local-path` dans le conteneur. On n'y teste ni
  Cilium en BGP, ni ceph-csi, ni une perte de nœud réaliste.
