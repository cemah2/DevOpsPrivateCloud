# Module 18 — Corrigé du palier 4 : Expert

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. Avec les distributions, « je réinstalle le nœud » est la pire des réparations : elle efface la preuve (journal, fichiers), ne corrige pas la cause (le code qui l'a produite la reproduira), et sur un nœud de contrôle elle met le quorum en jeu.

Les scripts d'injection sont dans `corrige/pannes/`. `_m18-commun.sh` contient les fonctions partagées :
- accès aux clusters d'essai (kubeconfig et talosconfig de `~/.config/workbook/m18/`) ;
- exécution sur les nœuds par SSH ou par l'agent QEMU ;
- essai des variantes (une variante sans effet sur ton lab passe à la suivante) ;
- branche locale « de Lucas » dans `~/src/distributions`.

Les fichiers modifiés sur un nœud sont sauvegardés dans `/var/lib/workbook/` de ce nœud ; l'état de la panne est dans `~/.local/state/workbook/M18-EXX/` sur `adm01`.

**Vérifié pendant la rédaction** :
- talosctl **v1.14.2** : génération d'un `talosconfig` d'un autre cluster et remplacement du contexte par `yq` (E20 variante 1, injection et annulation rejouées en local) ;
- refus du correctif de Lucas par la validation stricte : `talosctl machineconfig patch` répond `error decoding document v1alpha1/KubeNodeConfig/ (line 7): unknown keys found during decoding: nodeLabels: …` (sortie réelle), et accepte le correctif une fois `nodeLabels` remplacé par `labels` ;
- création et annulation de la branche `lucas/talos-zones` (dépôt de test) ;
- contrôle de l'empreinte de CA d'un jeton k3s (`check-E19`, sur fichiers de test).

**Points non testés en conditions réelles** (aucun cluster de la bonne version sur le banc de rédaction) :
- les messages exacts de k3s, RKE2 et CAPMOX cités ci-dessous : ils viennent de la documentation et des sources, **à confirmer sur ta version** ;
- E20 variante 3 : réinitialisation de `STATE` et `EPHEMERAL` puis retour en maintenance sur 10.10.99.87 (le lecteur nocloud ne porte que le réseau ; d'après le code de la plateforme nocloud de Talos 1.14, un `user-data` `#cloud-config` n'est pas pris pour une configuration de machine) ;
- E21 : refus d'un jeton Proxmox expiré par l'API de Proxmox VE 9 et réaction de CAPMOX ; ordre clone → réservation d'adresse dans CAPMOX 0.9 (d'après les raisons de la condition `VirtualMachineProvisioned`) ; `pvesh get /pools --poolid lab` sur PVE 9 ;
- E22 variante 4 : comportement exact de RKE2 quand `system-default-registry` change (échec du tirage du *runtime* ou des pods statiques : le nœud reste `NotReady` dans les deux cas).

---

## Méthode commune aux pannes de distribution

1. **Situer l'étage** :
   - Kubernetes : nœud, conditions, événements ;
   - service de la distribution : `systemctl status`, `journalctl -u … -b` ;
   - API de l'OS : `talosctl` ;
   - fournisseur d'infrastructure : conditions des objets Cluster API, journaux des contrôleurs, API Proxmox.
2. **Lire la première erreur** du dernier démarrage, pas la dernière ligne : les messages suivants sont des conséquences (nouvelles tentatives, délais dépassés).
3. **Comparer** avec un nœud sain (`rke2-01`, `talos-02`) et avec ce que produit le code (`ansible-playbook --check --diff --limit`, `talos/appliquer.sh <nœud> --essai`).
4. **Corriger à la racine**, dans le code, rejouer, vérifier que le second passage ne change rien.
5. **Prévenir** : quel contrôle (CI, gestionnaire du rôle, validation, alerte M21) aurait arrêté la panne avant l'utilisateur ?

---

### M18-E19 — Panne : le nœud k3s ne rejoint plus le cluster

**Démarche de diagnostic**

*Symptômes* : `k3s-ha02` `NotReady` (condition `Ready=Unknown`, « Kubelet stopped posting node status ») ; `k3s-agent` redémarre en boucle (`systemctl status k3s-agent` : `activating (auto-restart)`).

*Hypothèses* : jeton refusé, mauvaise adresse de serveur, superviseur injoignable (réseau, pare-feu), certificats refusés (horloge, CA), identité du nœud refusée (mot de passe de nœud), ressources.

**Étape 1 — Constater.**

```
admin@adm01:~$ export KUBECONFIG=~/.config/workbook/m18/k3s-ha.kubeconfig
admin@adm01:~$ kubectl get nodes -o wide
admin@adm01:~$ kubectl describe node k3s-ha02 | sed -n '/Conditions/,/Addresses/p'
admin@k3s-ha02:~$ systemctl status k3s-agent --no-pager
admin@k3s-ha02:~$ journalctl -u k3s-agent -b --no-pager | grep -m 20 -Ei 'level=(error|fatal)|failed|refused|x509|token'
admin@k3s-ha02:~$ sudo cat /etc/rancher/k3s/config.yaml; systemctl cat k3s-agent | grep -E 'EnvironmentFile|ExecStart'
```

Lis le **premier** message d'erreur après le dernier `Starting k3s agent`. La séquence de l'agent (doc *Architecture* et *token*) est : lire sa configuration → télécharger `/cacerts` du serveur **sans** authentification → comparer l'empreinte au jeton → demander ses certificats au superviseur avec le jeton et son mot de passe de nœud → démarrer containerd et le kubelet → ouvrir le tunnel vers le serveur. Chaque variante casse une étape différente.

**Variante 1 — jeton d'un autre cluster.** Le journal montre que l'empreinte de la CA du serveur ne correspond pas à celle du jeton (message du type *token CA hash does not match the Cluster CA certificate hash*, à vérifier sur ta version). Preuve sans toucher à rien :

```
admin@k3s-ha02:~$ sudo grep -E '^token(-file)?:' /etc/rancher/k3s/config.yaml      # n'affiche pas le jeton si token-file
admin@k3s-ha02:~$ sudo cut -c4-67 <FICHIER-DU-JETON>                                # empreinte portée par le jeton
admin@k3s-ha02:~$ curl -sk https://k3s-ha01.par1.medisphere.internal:6443/cacerts | sha256sum
```

Les deux empreintes diffèrent : le jeton vient d'un autre cluster. C'est le comportement voulu du format sécurisé (`K10<empreinte>::<identifiant>:<secret>`) : l'agent refuse de parler à un serveur dont il ne reconnaît pas la CA, **avant** d'envoyer son secret. Correctif : remettre le bon jeton par le rôle (`vault_k3s_jeton_k3s_ha` du Vault `lab`, comparé à `/var/lib/rancher/k3s/server/token` du serveur, que l'on ne copie **jamais** dans un ticket), rejouer le rôle sur `k3s-ha02`.

**Variante 2 — port 9345.** Journal : `connect: connection refused` vers `https://k3s-ha01…:9345/cacerts`. 9345 est le superviseur de **RKE2** ; k3s sert le superviseur et l'API sur le même port, 6443. Preuve : `curl -sk https://k3s-ha01…:6443/ping` répond `pong`, `ss -ltn` sur `k3s-ha01` n'écoute pas 9345. Correctif : `k3s_url` dans `host_vars/k3s-ha02/k3s.yml`, rôle rejoué.

**Variante 3 — horloge.** Premier indice, souvent : ta connexion SSH par **certificat** est refusée (certificat « pas encore valide » vu de l'hôte), alors que la connexion par clé passe. Passe par la console Proxmox ou par l'agent QEMU :

```
root@pve01:~# qm guest exec 5192 -- date -Is
root@pve01:~# qm guest exec 5192 -- timedatectl show -p NTPSynchronized -p NTP
root@pve01:~# qm guest exec 5192 -- systemctl is-active chrony
```

Journal de l'agent : `x509: certificate has expired or is not yet valid` (la CA et les certificats du serveur ont été émis « dans le futur » vu de l'agent). Correctif : `systemctl start chrony`, `chronyc makestep` (le saut est nécessaire : chrony corrige lentement un petit écart, il ne rattrape pas 400 jours sans `makestep`), puis `systemctl restart k3s-agent`. Cause racine à trouver : qui a arrêté le service de temps ? (Le rôle de base doit le garder `enabled` et `started` : le rejouer le remet.)

**Variante 4 — TCP 6443 filtré sur le serveur.** Journal : délais dépassés (`i/o timeout`) vers `k3s-ha01:6443`, pas de refus. Depuis l'agent, `curl -sk --max-time 5 https://k3s-ha01…:6443/ping` n'aboutit pas ; depuis `adm01`, si. Le filtrage est donc entre l'agent et le serveur, et propre à l'agent. Sur `k3s-ha01` :

```
admin@k3s-ha01:~$ sudo nft list ruleset | grep -n -B3 'dport 6443'
```

Une table `inet wb_m18_e19` jette le 6443 venant de l'adresse de l'agent : une règle d'essai de Sophie, non versionnée. Correctif : `sudo nft delete table inet wb_m18_e19`, puis rendre la règle impossible à poser hors du code (le pare-feu des nœuds est un rôle, comme la bordure). Ports d'un serveur k3s à garder ouverts depuis ses agents : 6443 (superviseur et API), 8472/udp (VXLAN de Flannel), 10250 (kubelet), et 2379-2380 entre serveurs en etcd intégré.

**Après chaque variante** : `kubectl get nodes` (`Ready` en moins d'une minute), rôle rejoué deux fois (`changed=0` au second), `--annuler` pour clore.

**Prévention**
- Jeton : une seule source (Vault `lab`), un nom de variable par cluster (`vault_k3s_jeton_<cluster>`), jamais de jeton dans une note.
- Adresse : variable calculée par le rôle à partir de l'inventaire, pas tapée à la main.
- Horloge : alerte sur `NTPSynchronized=no` (M21) ; service de temps imposé par le rôle de base.
- Pare-feu : règles des nœuds par le code uniquement ; contrôle `nft list ruleset` comparé au rendu du rôle.

Fichier : [RB-183](fichiers/M18-E19/medisphere/docs/kubernetes/distributions/runbooks/RB-183-noeud-k3s-ne-rejoint-pas.md).

**Pièges classiques**
- Supprimer le Secret `k3s-ha02.node-password.k3s` « pour réinitialiser » : sans comprendre, on enlève une protection (un autre hôte pourrait prendre le nom du nœud) et on ne corrige rien.
- Réinstaller l'agent avec `curl | sh` et un nouveau jeton copié du serveur : ça marche, et la cause reste.
- Régler l'horloge sans relancer le service de temps : la panne revient au prochain redémarrage.

---

### M18-E20 — Panne : le nœud Talos refuse sa configuration

**Démarche de diagnostic**

*Symptômes* : selon la variante, aucune commande `talosctl` ne passe (tous les nœuds), un correctif est refusé, ou un nœud disparaît.

*Hypothèses* : identité du client (`talosconfig`), validation de la configuration, nœud sans configuration (maintenance), réseau, version.

**Étape 1 — Situer l'étage, sans rien modifier.**

```
admin@adm01:~$ export TALOSCONFIG=~/.config/workbook/m18/talosconfig
admin@adm01:~$ talosctl config info
admin@adm01:~$ for ip in 10.10.99.85 10.10.99.86 10.10.99.87; do talosctl -n $ip version --short || echo "$ip : KO"; done
admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/talos.kubeconfig get nodes -o wide
```

- Tous les nœuds refusent, mais Kubernetes est sain : étage **client**.
- Un seul nœud refuse, et il a disparu de Kubernetes : étage **nœud**.
- Tout répond, mais `appliquer.sh --essai` échoue : étage **configuration**.

**Variante 1 — `talosconfig` d'un autre cluster.** Erreur TLS du type `transport: authentication handshake failed: tls: failed to verify certificate: x509: certificate signed by unknown authority` : le client ne reconnaît plus le certificat des nœuds, parce que la CA de son contexte a changé. Preuve :

```
admin@adm01:~$ yq -r '.contexts[.context].ca' $TALOSCONFIG | base64 -d | openssl x509 -noout -subject -fingerprint -sha256
admin@adm01:~$ yq -r '.os.ca.crt' ~/.config/workbook/m18/talos-secrets.yaml | base64 -d | openssl x509 -noout -subject -fingerprint -sha256
```

(Le chemin de la CA de l'OS dans le paquet de secrets, `os.ca.crt`, est celui de `talosctl gen secrets` 1.14 : relis ton fichier.) Les empreintes diffèrent. Correctif : régénérer **depuis le paquet de secrets**, sans toucher aux nœuds :

```
admin@adm01:~/src/distributions$ set -a; . talos/versions.env; set +a
admin@adm01:~$ talosctl gen config "$TALOS_CLUSTER" "$TALOS_ENDPOINT" --with-secrets ~/.config/workbook/m18/talos-secrets.yaml \
>   --output-types talosconfig -o /tmp/talosconfig.$$ --force
admin@adm01:~$ talosctl --talosconfig /tmp/talosconfig.$$ config endpoint 10.10.99.85
admin@adm01:~$ install -m 600 /tmp/talosconfig.$$ ~/.config/workbook/m18/talosconfig && rm -f /tmp/talosconfig.$$
```

Le paquet de secrets suffit à refaire un `talosconfig` valide : c'est pour cela qu'il est en 600 et dans le Vault. À l'inverse, le `talosconfig` ne permet pas de refaire le paquet. Prévention : `generer.sh` produit aussi le `talosconfig`, on ne lance jamais `gen config` sans `--with-secrets` dans le dossier de travail, et `talosctl config merge` plutôt qu'un écrasement.

**Variante 2 — correctif refusé.**

```
admin@adm01:~/src/distributions$ git log --oneline -3 && git show --stat HEAD
admin@adm01:~/src/distributions$ talos/appliquer.sh talos-02 --essai
… error decoding document v1alpha1/KubeNodeConfig/ (line 7): unknown keys found during decoding:
nodeLabels:
    topology.kubernetes.io/zone: par1-baie-b
```

La validation est stricte et nomme le document et le champ. Dans `KubeNodeConfig` (1.14), le champ s'appelle `labels` ; `nodeLabels` est le nom de l'ancien champ `machine.nodeLabels` de `v1alpha1`, que Lucas a recopié. Correctif sur sa branche, nouveau commit (`fix(talos): champ labels de KubeNodeConfig`). Le document se **fusionne** avec le `KubeNodeConfig` déjà rendu par `patches/worker/10-etiquettes.yaml` (même kind) : vérifie avec `--essai` que les étiquettes communes restent. Puis `talos/appliquer.sh talos-02` et `talos-03` (changement sans redémarrage), et `kubectl get nodes -L topology.kubernetes.io/zone`. Le piège voisin, que Lucas aurait pu faire : écrire `machine.nodeLabels` **et** un `KubeNodeConfig` : en 1.14, un champ `v1alpha1` et son document de remplacement s'excluent, et la configuration est refusée aussi. Prévention : un job de CI qui rend la configuration de chaque nœud (`talosctl machineconfig patch` sur la configuration générée avec des secrets factices) et la fait valider (`talosctl validate --mode metal`, à vérifier pour la plateforme `nocloud`).

**Variante 3 — `talos-03` en maintenance.**

```
admin@adm01:~$ talosctl -n 10.10.99.87 version                       # refusé (pas de configuration, pas d'identité)
admin@adm01:~$ talosctl -n 10.10.99.87 --insecure get disks          # répond : mode maintenance
admin@adm01:~$ talosctl -n 10.10.99.85 logs controller-runtime | tail # rien d'utile côté talos-01
root@pve01:~# qm terminal 2187 -iface serial0                       # ou la console : « maintenance mode »
```

La console affiche le tableau de bord de Talos en mode maintenance, avec l'adresse 10.10.99.87 (fournie par le lecteur nocloud). La partition `STATE` (configuration, identité) est vide ; `EPHEMERAL` aussi (images, données du kubelet). Avant d'envoyer quoi que ce soit en `--insecure`, vérifie que l'adresse est bien la VM 2187 (MAC `bc:24:11:99:18:87` dans `qm config 2187`, console). Correctif par le code :

```
admin@adm01:~/src/distributions$ talos/generer.sh                    # si ~/.cache/m18/talos/ est vide
admin@adm01:~/src/distributions$ talos/appliquer.sh talos-03 --maintenance
admin@adm01:~$ talosctl -n 10.10.99.87 health --wait-timeout 10m
```

Le nœud se réinstalle **pas** (il est déjà installé sur le disque) : il reçoit sa configuration, regénère son identité, rejoint le cluster. Le `Node` Kubernetes `talos-03` existant est repris (même nom). La cause (qui a lancé `talosctl reset` ?) se cherche dans l'historique : `talosctl -n 10.10.99.87 dmesg` ne la gardera pas (tout est effacé) ; c'est l'audit de l'API Talos qui manque, et une règle d'équipe (le rôle `os:admin` n'est pas pour tout le monde : `os:operator` suffit à l'astreinte de premier niveau).

**Prévention** : `talosconfig` personnels à rôle minimal (`os:operator`, `os:reader`) et durée courte (`talosctl config new --roles … --crt-ttl 24h`), paquet de secrets au Vault, CI de validation des correctifs, procédure `--maintenance` écrite (RB-184).

Fichier : [RB-184](fichiers/M18-E20/medisphere/docs/kubernetes/distributions/runbooks/RB-184-talos-diagnostic.md).

**Pièges classiques**
- `talosctl gen config` sans `--with-secrets` : un nouveau cluster, une nouvelle CA, et des nœuds qui ne te reconnaissent plus.
- `talosctl edit mc` pour « débloquer » : la configuration du nœud diverge du code.
- Envoyer une configuration `--insecure` à une adresse non vérifiée : n'importe quelle VM en maintenance sur `vsandbox` l'accepterait, secrets compris.
- `reset` sur le nœud de contrôle unique pour « recommencer » : c'est une restauration (RB-181), pas une réparation.

---

### M18-E21 — Panne : la machine reste en Provisioning

**Démarche de diagnostic**

*Symptômes* : le `MachineDeployment` affiche un réplica non prêt ; la nouvelle `Machine` reste en `Provisioning` (ou `Pending`). Selon la variante, aucune VM n'apparaît dans 5180-5189, ou une VM apparaît mais ne démarre pas.

*Hypothèses* : identité Proxmox (jeton), droits (rôle, ACL, pool), template introuvable, plus de VMID libre, plus d'adresse libre, nœud Proxmox plein, données d'amorçage absentes, point d'accès de l'API injoignable (pour une machine qui démarre mais ne rejoint pas).

**Étape 1 — Descendre la chaîne.**

```
admin@adm01:~$ export KUBECONFIG=~/.config/workbook/m18/k3s01.kubeconfig
admin@adm01:~$ clusterctl describe cluster capi-essai -n capi-essai --show-conditions all
admin@adm01:~$ kubectl get machines -n capi-essai -o wide
admin@adm01:~$ kubectl get proxmoxmachine -n capi-essai <PM> -o yaml | yq '.spec.virtualMachineID, .status'
admin@adm01:~$ kubectl get events -n capi-essai --sort-by=.lastTimestamp | tail -20
admin@adm01:~$ kubectl get ipaddressclaims,ipaddresses -n capi-essai
admin@adm01:~$ kubectl get inclusterippool -n capi-essai -o wide
admin@adm01:~$ kubectl logs -n capmox-system deploy/capmox-controller-manager --since=30m | grep -i <PM>
```

Le point décisif est le champ `spec.virtualMachineID` de la `ProxmoxMachine` et la raison de la condition `VirtualMachineProvisioned` (constantes de l'API `v1alpha2` de CAPMOX : `Cloning`, `CloningFailed`, `WaitingForStaticIPAllocation`, `WaitingForBootstrapDataReconciliation`, `WaitingForVMPowerUp`, `WaitingForCloudInit`, `VMProvisionFailed`, `TaskFailed`…).

**Variante 1 — jeton expiré.** Pas de VMID ; raison `CloningFailed` (ou erreur de réconciliation répétée) ; journal de CAPMOX avec une réponse **401** de l'API Proxmox (`authentication failure` / `invalid token`, à vérifier sur ta version) ; le `ProxmoxCluster` peut perdre sa condition `ProxmoxAvailable`. Les VMs existantes tournent toujours : le cluster de charge de travail ne dépend pas de CAPMOX pour fonctionner. Preuve de l'autre côté :

```
root@pve01:~# pveum user token list wb-capi@pve
root@pve01:~# date +%s
root@pve01:~# journalctl -u pveproxy --since -30min | grep -i 'wb-capi'
```

La colonne `expire` porte une date passée. Correctif : `pveum user token modify wb-capi@pve capi --expire 0` (ou une date de rotation planifiée, **écrite** dans le code et le registre des secrets), sans recréer le jeton (le secret changerait et il faudrait réécrire le Secret `capi-essai-proxmox`). CAPMOX reprend au cycle suivant, la machine est clonée. Prévention : expiration des jetons gérée par le code avec une alerte avant échéance (M21), rotation documentée (M25).

**Variante 2 — template hors du pool.** Pas de VMID ; erreur de clone **403** (`Permission check failed (/vms/9061, VM.Clone)`, à vérifier sur ta version). Preuve :

```
root@pve01:~# pvesh get /pools --poolid lab --output-format json | jq '.[0].members[] | select(.vmid == 9061)'
root@pve01:~# pveum user permissions 'wb-capi@pve!capi' --path /vms/9061
root@pve01:~# pveum user permissions 'wb-capi@pve!capi' --path /pool/lab
```

Le jeton a ses droits sur le pool `lab` (ACL du rôle `WBCapi`) ; le template n'en fait plus partie, donc plus de droit dessus. Correctif : remettre le template dans le pool (`pveum pool modify lab --vms 9061`), **pas** élargir le rôle ni poser une ACL sur `/`. La règle « tous les templates CAPI dans le pool `lab` » va dans le code (création du template par le pipeline d'images, ou ressource OpenTofu du pool). Variante voisine, à connaître : avec `templateSelector.matchTags`, une étiquette retirée ou posée sur deux templates donne « aucun template » ou « plusieurs templates » : même étage, même démarche.

**Variante 3 — plus d'adresse.** Une VM a été clonée (VMID présent), arrêtée ; raison `WaitingForStaticIPAllocation`. Le pool est à 0 adresse libre :

```
admin@adm01:~$ kubectl get inclusterippool capi-essai-v4-icip -n capi-essai -o jsonpath='{.status.ipAddresses}{"\n"}'
{"free":0,"outOfRange":0,"total":20,"used":20}
admin@adm01:~$ kubectl get ipaddressclaims -n capi-essai -o custom-columns=NOM:.metadata.name,PROPRIETAIRE:.metadata.ownerReferences[0].kind,ADRESSE:.status.addressRef.name
```

Les réservations d'une machine appartiennent à sa `ProxmoxMachine` (`ownerReferences`). Les `essai-lb-NN` n'ont pas de propriétaire : des réservations à la main, « pour un essai de répartiteur ». Correctif : demander à leur auteur, puis les supprimer (`kubectl delete ipaddressclaim -n capi-essai -l …` ou par nom) ; l'adresse est attribuée, la VM démarre. Si le besoin est réel, il prend une **plage à lui** (hors 10.10.40.150-169), écrite dans PLAN et la matrice d'adressage. Prévention : le pool d'un cluster n'est pas un IPAM général ; une alerte « pool à moins de 2 adresses libres » (M21) ; RBAC qui interdit de créer des `IPAddressClaim` hors des contrôleurs.

**Variante non injectée — VIP occupée.** Une machine démarre, mais `kubeadm join` n'aboutit pas, et la machine reste `Provisioned` (pas `Running`) : un autre hôte répond à l'ARP de 10.10.40.210. Preuve : `arping -I <interface> 10.10.40.210` depuis un hôte du VLAN 40 montre deux adresses MAC ; `ip neigh` sur le nœud de contrôle. Le script ne l'injecte pas : il faudrait poser une adresse sur un hôte du VLAN 40 hors du module, ce qui sortirait du périmètre des pannes. Elle est dans RB-180.

**Après** : la machine passe `Running` seule ; `--annuler` remet le nombre de travailleurs d'origine (la machine ajoutée est marquée `cluster.x-k8s.io/delete-machine`).

Fichier : [RB-180](fichiers/M18-E21/medisphere/docs/kubernetes/distributions/runbooks/RB-180-machine-capi-bloquee.md).

**Pièges classiques**
- Supprimer la `Machine` : sa remplaçante se bloque au même endroit ; une VM clonée peut rester orpheline si CAPMOX perd la trace de sa tâche.
- Donner `PVEVMAdmin` sur `/` au jeton « pour que ça marche ».
- Recréer le jeton : nouveau secret, Secret Kubernetes à réécrire, et la cause (l'expiration) n'est pas comprise.
- Agrandir le pool d'adresses sur une plage qui n'est pas à toi.
- Oublier que le compte de la plage `vmIDRange` (10 VMID) borne aussi le surplus des remplacements.

---

### M18-E22 — Panne : RKE2 ne démarre plus

**Démarche de diagnostic**

*Symptômes* : `rke2-03` `NotReady` ; `rke2-server` en échec ou en redémarrage sur ce nœud ; `rke2-01` et `rke2-02` sains, etcd à deux membres sur trois.

*Hypothèses* : vérification de l'hôte du profil CIS (compte, paramètres noyau), configuration illisible, *runtime* ou images introuvables, certificats, etcd local.

**Étape 1 — La première erreur.**

```
admin@rke2-03:~$ systemctl status rke2-server --no-pager
admin@rke2-03:~$ journalctl -u rke2-server -b --no-pager | grep -m 10 -E 'level=(fatal|error)|Error:'
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/m18.yml --limit rke2-03 --check --diff
```

`--check --diff` montre tout de suite un fichier modifié hors du code (variantes 1, 3 et 4) ; il ne voit pas un compte supprimé si le rôle ne le gère pas en état (il le gère : `useradd` idempotent, voir plus bas).

**Variante 1 — paramètres noyau.** Fatal du type `invalid kernel parameter value vm.overcommit_memory=0 - expected 1` (formulation à vérifier) : avec `profile: cis`, RKE2 impose `protect-kernel-defaults` et vérifie les valeurs comme le kubelet. Preuve : `sysctl kernel.panic vm.overcommit_memory` et `ls /etc/sysctl.d/` : le fichier `60-rke2-cis.conf` a disparu. Correctif :

```
admin@rke2-03:~$ sudo cp -f /usr/share/rke2/rke2-cis-sysctl.conf /etc/sysctl.d/60-rke2-cis.conf
admin@rke2-03:~$ sudo restorecon -v /etc/sysctl.d/60-rke2-cis.conf
admin@rke2-03:~$ sudo sysctl -p /etc/sysctl.d/60-rke2-cis.conf
admin@rke2-03:~$ sudo systemctl restart rke2-server
```

`sysctl -p` du seul fichier, pas `systemctl restart systemd-sysctl` (mise en garde du guide). Puis le rôle (`rke2_sysctl_source` → `rke2_sysctl_dest`) rejoué sans changement.

**Variante 2 — compte `etcd` supprimé.** Fatal : le profil exige l'utilisateur et le groupe `etcd`. Preuve : `getent passwd etcd` vide, et `ls -n /var/lib/rancher/rke2/server/db/etcd` montre des fichiers appartenant à un UID sans nom. **Ne lance pas** la commande du guide telle quelle :

```
admin@rke2-03:~$ ls -nd /var/lib/rancher/rke2/server/db/etcd            # UID et GID d'origine, ex. 990 989
admin@rke2-03:~$ sudo groupadd -r -g <GID> etcd
admin@rke2-03:~$ sudo useradd -r -c "etcd user" -s /sbin/nologin -M -u <UID> -g etcd etcd
admin@rke2-03:~$ sudo systemctl restart rke2-server
```

Avec un nouvel UID, etcd ne pourrait plus lire ses données (RKE2 ne refait pas la propriété de tout le dossier, **à vérifier**), et le membre resterait en échec. Puis : le rôle doit **fixer** l'UID et le GID (`rke2_etcd_uid`, `rke2_etcd_gid`) pour que trois nœuds reconstruits aient les mêmes ; et le vieux rôle de « nettoyage des comptes » de Lucas doit exclure les comptes système des services.

**Variante 3 — `config.yaml` invalide.** Fatal à la lecture de la configuration, avec un numéro de ligne (`yaml: line N: found character that cannot start any token`). Preuve : `cat -A /etc/rancher/rke2/config.yaml | grep -n '\^I'` montre la tabulation. Correctif : rejouer le rôle (qui réécrit le fichier depuis `rke2_config`) ; si l'étiquette était voulue, l'ajouter **au code** (`rke2_config.node-label`). Prévention : gestionnaire du rôle qui valide le YAML (`python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))'` ou `validate:` de `ansible.builtin.template`) avant tout redémarrage, et interdiction des modifications à la main (le fichier est déjà « géré par Ansible » en en-tête).

**Variante 4 — registre par défaut.** Le service démarre, le nœud reste `NotReady`. Le journal montre des tirages en échec : `registry.par1.medisphere.internal/rancher/rke2-runtime:…` ou `…/rancher/hardened-kubernetes:…` : `not found` ou `unauthorized`. `system-default-registry` **préfixe** toutes les images du système, plan de contrôle compris ; Harbor n'a pas de projet `rancher`. Preuve :

```
admin@rke2-03:~$ sudo grep -n system-default-registry /etc/rancher/rke2/config.yaml
admin@rke2-03:~$ sudo /var/lib/rancher/rke2/bin/crictl --runtime-endpoint unix:///run/k3s/containerd/containerd.sock images | head
admin@rke2-03:~$ sudo grep image: /var/lib/rancher/rke2/agent/pod-manifests/kube-apiserver.yaml
```

Correctif : retirer la ligne (rôle rejoué). Ce que Lucas voulait (tout par Harbor) se fait par les **miroirs** de `registries.yaml`, qui existent déjà (`docker.io` → cache `dockerhub` de Harbor, M18-E04) : les images `rancher/*` de RKE2 viennent de Docker Hub et passent donc déjà par Harbor. `system-default-registry` ne sert que pour un registre qui contient les images de RKE2 **sous leur nom d'origine** (miroir hors ligne).

**Après** : trois nœuds `Ready`, trois pods etcd prêts, `getenforce` → `Enforcing`, rôle rejoué **un serveur à la fois** sans changement.

Fichiers : [RB-185](fichiers/M18-E22/medisphere/docs/kubernetes/distributions/runbooks/RB-185-rke2-ne-demarre-pas.md), [extrait du rôle `rke2`](fichiers/M18-E22/ansible/roles/rke2/handlers/main.yml) (validation avant redémarrage) et [UID fixes](fichiers/M18-E22/ansible/roles/rke2/tasks/etcd_utilisateur.yml).

**Pièges classiques**
- `protect-kernel-defaults: false` ou retirer `profile: cis` pour « faire démarrer » : c'est exactement ce que Sophie interdit.
- `setenforce 0` parce qu'un fichier recopié n'a pas le bon contexte : `restorecon`, pas permissif.
- Recréer `etcd` avec un nouvel UID.
- Redémarrer un deuxième serveur « pour voir » : perte de quorum.

---

### M18-E23 — Sous le capot : k3s, un binaire, une base, un superviseur

**Solution**

Fichier : [modèle de synthèse](fichiers/M18-E23/medisphere/docs/kubernetes/distributions/analyses/k3s-sous-le-capot.md), [script de lecture de la base](fichiers/M18-E23/distributions/k3s/outils/kine-lire.sh).

*1. Un binaire.*

```
admin@k3s01:~$ ls -l /usr/local/bin/ | grep k3s
… crictl -> k3s   ctr -> k3s   kubectl -> k3s   k3s   k3s-killall.sh   k3s-uninstall.sh
admin@k3s01:~$ sudo ls /var/lib/rancher/k3s/data/
current  <hachage>  …
admin@k3s01:~$ sudo ls /var/lib/rancher/k3s/data/current/bin/
containerd  containerd-shim-runc-v2  runc  cni  … (iptables et autres outils embarqués)
admin@k3s01:~$ systemd-cgls -u k3s.service --no-pager | head -30
admin@k3s01:~$ sudo ss -ltnp | grep -E 'k3s|containerd'
```

- `k3s` est un exécutable « multi-appel » : il se comporte en `kubectl`, `crictl` ou `ctr` selon le nom sous lequel on l'appelle.
- Au premier démarrage, il extrait ses binaires embarqués dans `data/<hachage>/`. Le hachage est celui du contenu : deux versions de k3s cohabitent, `current` désigne celle en service.
- L'arbre des processus montre **un** processus `k3s server` (qui contient le serveur d'API, l'ordonnanceur, le contrôleur, le contrôleur cloud, kine, le kubelet et kube-proxy, en goroutines), un fils `containerd`, et les *shims* des conteneurs.
- Pas de pods statiques du plan de contrôle : `kubectl get pods -n kube-system` ne montre que les modules (CoreDNS, local-path, metrics-server).
- Ports :
  - 6443 : API **et** superviseur ;
  - 10250 : kubelet ;
  - 10257, 10259 : contrôleur et ordonnanceur, sur 127.0.0.1 ;
  - 6444 : en local, l'écouteur interne du serveur d'API derrière le superviseur (à vérifier sur ta version) ;
  - 2379-2380 sur `k3s-ha01` seulement (etcd).

*2. Une base.* [`kine-lire.sh`](fichiers/M18-E23/distributions/k3s/outils/kine-lire.sh) copie la base par `sqlite3 state.db ".backup /root/kine.XXXX/copie.db"` (cohérent même pendant les écritures), lit, et efface. Schéma de la table `kine` (relevé dans le code de kine, à confirmer par `.schema`) : `id` (auto-incrément, **c'est la révision**), `name` (la clé, `/registry/configmaps/wb-essais/temoin`), `created` (1 si cette ligne crée la clé), `deleted` (1 si elle la supprime), `create_revision`, `prev_revision` (révision de la version précédente de la même clé), `lease`, `value`, `old_value`. Vie d'une ConfigMap :
- création : une ligne `created=1` ;
- deux modifications : deux lignes, chacune avec `prev_revision` = l'`id` de la précédente ;
- suppression : une ligne `deleted=1`.

Soit quatre lignes, quatre révisions croissantes. kine **ajoute** toujours des lignes (journal en écriture seule, comme le MVCC d'etcd) ; le *watch* d'un client est servi en relisant les lignes d'`id` supérieur à la révision demandée (sondage périodique de la table). Le compactage supprime les anciennes versions des clés ; la ligne de nom `compact_rev_key` mémorise jusqu'où (révision de compactage). Sur `k3s-ha01`, `etcdctl get /registry/configmaps/wb-essais/temoin -w json` donne `create_revision`, `mod_revision`, `version` : même modèle, implémenté nativement par etcd (Raft, MVCC sur bbolt).

*3. Un superviseur.*

```
admin@adm01:~$ curl -sk https://k3s-ha01.par1.medisphere.internal:6443/cacerts | openssl x509 -noout -subject
subject=CN = k3s-server-ca@<horodatage>
admin@adm01:~$ curl -sk https://k3s-ha01.par1.medisphere.internal:6443/ping
pong
admin@adm01:~$ curl -sk https://k3s-ha01.par1.medisphere.internal:6443/version
{ "kind": "Status", … "code": 401 }
```

Le superviseur répond sans authentification à `/cacerts` (amorçage de la confiance) et `/ping` ; les chemins de l'API Kubernetes, sur le même port, exigent une authentification. Sur l'agent : `sudo ss -ltnp` montre `k3s agent` en écoute sur un port local (6444 dans les versions récentes, **à relever sur ta version**), et `/var/lib/rancher/k3s/agent/kubelet.kubeconfig` vise `https://127.0.0.1:<ce port>` : c'est le **répartiteur local** de l'agent, qui tient la liste des serveurs (apprise par le superviseur, puis par les *endpoints* du Service `kubernetes`) et bascule seul si un serveur tombe. Ajouter un serveur ne demande aucune reconfiguration des agents. Identité : le Secret `k3s-ha02.node-password.k3s` (espace `kube-system`) contient l'empreinte du mot de passe de `/etc/rancher/node/password` de l'agent ; un autre hôte qui prendrait le nom `k3s-ha02` serait refusé.

*4. containerd et modules.*
- Socket : `/run/k3s/containerd/containerd.sock`.
- Configuration générée : `/var/lib/rancher/k3s/agent/etc/containerd/config.toml` (version 3 pour containerd 2) ; gabarit facultatif `config-v3.toml.tmpl`.
- `registries.yaml` est traduit en `hosts.toml` sous `/var/lib/rancher/k3s/agent/etc/containerd/certs.d/<registre>/`.
- Commandes : `sudo k3s crictl ps`, `sudo k3s ctr -n k8s.io containers ls`.
- `AddOn` : un objet `addons.k3s.cattle.io` par fichier de `server/manifests/`, réappliqué à chaque modification du fichier.
- Le retrait du fichier : la page *Packaged Components* le dit, « deleting files out of this directory will not delete the corresponding resources from the cluster ». La ConfigMap reste, et l'`AddOn` aussi. Seul `--disable=<nom>` désinstalle activement un module (et efface son fichier) ; un fichier `.skip` posé **après** coup ne retire rien, il fait seulement ignorer le manifeste.
- Nettoyage : `kubectl delete configmap -n wb-essais addon-temoin` et `kubectl delete addon -n kube-system addon-temoin` (le nom de l'`AddOn` est celui du fichier sans extension).

*5. Synthèse* : modèle fourni.

**Explications**

k3s n'est pas « un Kubernetes allégé » : ce sont les mêmes composants, compilés ensemble et lancés dans un seul processus, avec trois ajouts :
- un magasin enfichable (kine) qui permet SQLite pour un nœud seul ;
- un superviseur qui distribue les certificats et la liste des serveurs ;
- un gestionnaire de modules (`AddOn`, `HelmChart`).

Le dépannage change d'endroit (un journal, `journalctl -u k3s`, au lieu de cinq conteneurs), pas de nature.

**Pièges classiques**
- Interroger `state.db` en place (verrous, risque de corruption, et kine écrit en continu).
- Croire que 6443 n'est que l'API : le pare-feu qui « protège l'API » coupe aussi l'enregistrement des agents.
- Supprimer un fichier de `server/manifests/` en pensant retirer un module : les objets restent. Utiliser `--disable` (désinstalle) ; un `.skip` posé avant le premier démarrage empêche l'installation, posé après il ne retire rien.

---

### M18-E24 — Questions expert : distributions et cycle de vie

**1. PKI dans la base (k3s) ou en fichiers (kubeadm).**
- k3s :
  - *avantage* : reconstruire un serveur demande la base et le jeton, rien d'autre ; les serveurs supplémentaires reçoivent la PKI du superviseur ;
  - *risque* : la sauvegarde de la base contient la PKI, chiffrée par une clé dérivée du jeton ; qui détient la sauvegarde **et** le jeton détient le cluster. Le jeton devient une clé maîtresse (Vault, rotation).
- kubeadm :
  - *avantage* : un instantané etcd volé ne donne pas la CA ;
  - *risque* : la reconstruction exige une seconde sauvegarde (`/etc/kubernetes/pki`, `sa.key`) que l'on oublie (M14-E24) ; sans elle, une restauration sur VMs neuves donne un cluster dont tous les jetons de comptes de service sont invalides.

**2. `k3s token rotate`.** Les instantanés antérieurs ont leurs données d'amorçage chiffrées par l'**ancien** jeton : les restaurer exige l'ancien jeton (`--token=<ancien>` à la restauration), et un serveur restauré repart avec lui. Il faut donc conserver l'ancien jeton aussi longtemps que les instantanés qu'il protège (rétention S3), dans le Vault, avec sa date de fin. La doc le dit en avertissement : *Snapshots taken before rotation require the old server token to restore*.

**3. Restauration RKE2 : b.**
- a) produit trois clusters etcd à un membre qui ne se connaissent pas (chaque `--cluster-reset` réinitialise l'appartenance).
- c) laisse deux membres de l'ancien cluster écrire pendant que le premier repart d'un état ancien : histoires divergentes.
- d) ramène des membres dont l'état n'est pas cohérent entre eux (sauvegardes de VMs à quelques secondes d'écart) et des identifiants de membres anciens.

**4. Talos sans SSH.**
- Avantages :
  - pas de dérive manuelle (impossible de « bricoler » un nœud) ;
  - pas de surface d'attaque SSH ni de comptes à gérer ;
  - toute action est un appel d'API authentifié par certificat et rôle, donc traçable et automatisable.
- Inconvénients :
  - un nœud dont le réseau ou l'API Talos est en panne n'est accessible que par la console (lecture seule du tableau de bord) ;
  - les outils de diagnostic habituels (`tcpdump`, `strace`, `perf`) ne sont pas là : il faut un pod de débogage privilégié (`kubectl debug node/`) ou une extension.
- Organisation :
  - accès console Proxmox documenté pour l'astreinte ;
  - paquet de secrets et `talosconfig` d'astreinte (`os:operator`) au Vault, avec procédure de bris de glace ;
  - image de débogage préparée dans Harbor ;
  - un nœud de rechange prêt à recevoir sa configuration.

**5. Pas de réparation en place.** Cluster API compare une spécification et des machines ; il ne sait pas « réparer » une machine, il sait la remplacer par une neuve conforme à la spécification. Ce modèle est fiable (chaque nœud est identique à son image) mais il impose :
- des images **complètes** (tout ce que le nœud doit avoir est dans l'image ou dans l'amorçage cloud-init, pas ajouté après coup) ;
- des images **reconstruites** à chaque correctif de sécurité (une mise à jour de paquet ne survivrait pas au remplacement suivant).

Conséquence sur les données : rien de durable sur le disque local d'un nœud (`emptyDir`, `hostPath`, `local-path`) ; les données vont sur un stockage externe au nœud (ceph-csi, M16).

**6. MHC à 40 %.**
- 2 machines, une tombe : le seuil vaut `floor(0,4 × 2) = 0`. Une machine malade dépasse 0 : la réparation est **court-circuitée**, rien n'est remplacé. La condition du MHC le dit (`RemediationAllowed=False`).
- 5 machines, 3 tombent : seuil `floor(2) = 2`, 3 > 2 : court-circuit également. C'est voulu : trois nœuds sur cinq qui tombent ensemble, c'est une panne d'infrastructure, et remplacer les machines en masse aggraverait la situation (charge sur Proxmox, perte de données locales).

**7. Cluster de gestion perdu une semaine.**
- `capi-essai` tourne normalement : ses composants ne dépendent pas du cluster de gestion.
- Les certificats du plan de contrôle (un an) ne sont pas renouvelés par le KCP (`rollout.before.certificatesExpiryDays`) pendant ce temps : sans conséquence sur une semaine, critique sur des mois.
- Une machine qui tombe n'est pas remplacée (plus de MHC) : la capacité baisse.
- Le kubeconfig du Secret `capi-essai-kubeconfig` est un certificat client émis par la CA du cluster : il ne « expire » pas parce que le cluster de gestion est absent. En revanche, si sa durée de vie est courte et que le contrôleur ne le renouvelle plus, les outils qui l'utilisent échouent à l'échéance (à vérifier : Cluster API régénère ce Secret à partir de la CA).

**8. `super-admin.conf` : b.**
- Pendant `kubeadm init`, kube-vip doit porter la VIP **avant** que l'API soit joignable par elle, donc avant que kubeadm ait créé le `ClusterRoleBinding` qui donne ses droits au groupe `kubeadm:cluster-admins` (celui de `admin.conf`, depuis 1.29). Seul `super-admin.conf` (`system:masters`, qui court-circuite le RBAC) fonctionne à ce moment-là ; ensuite, on revient à `admin.conf` pour ne pas laisser `system:masters` dans un pod.
- a) est faux : kube-vip n'a besoin de droits que sur les baux (*leases*).
- c) est faux : `admin.conf` existe pendant l'init.
- d) est faux : kube-vip lit très bien un kubeconfig à certificat.

**9. Deux fournisseurs.**
- Ce qui lie leurs versions : la version du *core* Cluster API installée dans le cluster de gestion (une seule, partagée) et le **contrat** (`v1beta1`, `v1beta2`) que chaque fournisseur implémente.
- À vérifier avant d'installer :
  - `metadata.yaml` du fournisseur : contrat de sa série ;
  - `go.mod` : version de `sigs.k8s.io/cluster-api` contre laquelle il est construit et testé (souvent la vraie limite) ;
  - matrice du README.
- Si les deux sont incompatibles :
  - deux clusters de gestion (un par fournisseur) ;
  - ou une version plus ancienne du fournisseur le plus en avance ;
  - ou attendre le fournisseur en retard.

  Jamais de *core* forcé hors de ce que l'un d'eux annonce.

**10. RKE2 vérifie sans poser.**
- Les paramètres noyau sont l'affaire du propriétaire de l'hôte (image, gestion de configuration). Les poser depuis RKE2 :
  - masquerait la dérive : qui d'autre les change ?
  - entrerait en conflit avec l'outillage de l'OS (sysctl.d, durcissement CIS de l'OS lui-même) ;
  - rendrait RKE2 responsable d'un état global de la machine.
- En vérifiant, RKE2 rend l'écart **visible** (il refuse de démarrer) au lieu de le corriger en silence, ce qui est l'esprit de `protect-kernel-defaults` du kubelet.
- On aurait perdu la détection d'une modification malveillante ou accidentelle des paramètres.

**11. kine sur base externe.**
- Ce qui est difficile à garantir :
  - *watch* : kine sonde la table, d'où une latence et une charge proportionnelles au nombre d'observateurs ;
  - révisions strictement croissantes et sans trou : dépendent de la séquence de la base et de son isolation ;
  - compactage : supprimer des lignes en concurrence avec les écritures ;
  - haute disponibilité : c'est celle de la base (réplication PostgreSQL, bascule), avec ses fenêtres de perte que etcd n'a pas (Raft valide à la majorité).
- Pour Lyon : si l'agence a déjà une base PostgreSQL gérée et sauvegardée (CloudNativePG sur un autre cluster, ou un service central joignable de façon fiable), un seul serveur k3s sans état sur une base externe se reconstruit en minutes. Avec trois machines et une liaison inter-sites incertaine, l'etcd intégré reste plus simple.

**12. system-upgrade-controller pour Lyon.** Deux `Plan` (`upgrade.cattle.io/v1`) :
- `serveurs` : `nodeSelector` sur `node-role.kubernetes.io/control-plane`, `concurrency: 1`, `cordon: true`, `version: v1.36.<N>+k3s1`, image `rancher/k3s-upgrade` (par le cache Harbor) ;
- `agents` : sélection des autres nœuds, `prepare` qui attend la fin du plan `serveurs`, `concurrency: 1`, `drain` avec respect des PDB.

Ce qui protège le quorum :
- `concurrency: 1` sur les serveurs : un seul membre etcd redémarre à la fois, et le suivant attend que le précédent soit revenu ;
- l'ordre serveurs puis agents (politique de décalage) ;
- un instantané etcd vérifié avant d'appliquer le plan.

Les noms exacts des champs sont dans la doc de system-upgrade-controller de ta version (M18-E07).
