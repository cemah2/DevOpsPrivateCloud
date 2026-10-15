# Sous le capot : un conteneur construit à la main

> Démonstration de formation (PLAT-1360). Durée : une heure. Hôte : une VM Debian 13 jetable (ou `ctr01` pendant le module 12), en root. Scripts : `capot-manuel.sh` (partie 1) et `capot-runc.sh` (partie 2).
> ⚠️ Tout ce qui monte ou démonte se fait dans un shell lancé par `unshare --mount` : un `pivot_root` ou un `umount` dans l'espace de noms de l'hôte peut le rendre inutilisable jusqu'au redémarrage.

## L'idée

Un conteneur n'est pas un objet du noyau. C'est un **processus ordinaire** auquel on a donné :

| Pièce | Mécanisme du noyau | Commande de la démonstration |
|---|---|---|
| sa propre vue des processus, des montages, du nom d'hôte, de l'IPC, du réseau | espaces de noms (`pid`, `mnt`, `uts`, `ipc`, `net`, et `user`, `cgroup`) | `unshare --pid --fork --mount --uts --ipc --net --mount-proc`, puis `nsenter -t <pid> -a` pour y entrer |
| des limites de ressources | cgroup v2 (`memory.max`, `pids.max`, `cpu.max`) | `mkdir /sys/fs/cgroup/capot-manuel`, écriture des limites, PID écrit dans `cgroup.procs` |
| un système de fichiers fait de couches | overlayfs (`lowerdir` en lecture seule, `upperdir` qui reçoit les écritures, `workdir`) | `mount -t overlay overlay -o lowerdir=…,upperdir=…,workdir=… fusion` |
| une autre racine | `pivot_root` (dans un espace `mnt` privé : `mount --make-rprivate /`) | `cd fusion && pivot_root . ancienne && umount -l /ancienne` |
| moins de privilèges | capacités, seccomp, `no_new_privs`, LSM | (laissé à `runc` : voir partie 2) |

## Partie 1 — à la main

1. **L'image** : `skopeo copy docker://docker.io/library/debian:trixie-slim oci:/srv/capot/oci:trixie` donne une disposition OCI : `index.json` → manifeste (configuration + liste ordonnée des couches) → blobs `tar+gzip`. Les couches s'extraient dans l'ordre ; un fichier `.wh.<nom>` d'une couche supérieure signifie « supprimer `<nom>` », `.wh..wh..opq` « répertoire opaque ».
2. **Overlay** : les couches extraites deviennent `lowerdir` ; toute écriture dans `fusion` apparaît dans `upperdir` (copie sur écriture). C'est exactement ce que fait le *snapshotter* `overlayfs` de containerd, une couche par répertoire.
3. **cgroup** : `cat /sys/fs/cgroup/cgroup.controllers` (contrôleurs proposés), `cgroup.subtree_control` (ceux délégués aux enfants), `memory.max` = 32M, `pids.max` = 16, puis `echo <pid> > cgroup.procs`. Au-delà de 16 processus : `fork: Resource temporarily unavailable`. (Sur un hôte systemd, la manière propre est `systemd-run --scope -p MemoryMax=32M -p TasksMax=16`.)
4. **Isolement** : `unshare` crée les espaces de noms, `--fork` fait du nouveau processus le PID 1 de l'espace `pid`, `--mount-proc` remonte `/proc` pour qu'il ne voie que ses processus. `readlink /proc/<pid>/ns/pid` diffère de celui de l'hôte.
5. **Racine** : `pivot_root` échange la racine du processus et la nouvelle (qui doit être un point de montage) ; l'ancienne est démontée paresseusement. `chroot` ne suffit pas : il ne change que le répertoire racine de résolution, et un root s'en échappe.
6. **Entrer** : `nsenter -t <pid> -a ps -ef` exécute une commande dans tous les espaces de noms du processus : c'est ce que fait `docker exec` (plus le cgroup et le profil de sécurité).

## Partie 2 — avec runc

- **Paquet OCI** (*bundle*) : un répertoire avec `config.json` et `rootfs/` (`umoci unpack --image /srv/capot/oci:trixie /srv/capot/bundle`). `runc spec` écrit un modèle.
- **Lancement** : `runc run -d capot` (sans terminal, entrées-sorties redirigées), `runc list`, `runc state capot`, `runc ps capot` ; arrêt : `runc kill capot KILL && runc delete capot`.
- **Ce que `runc` fait de `config.json`** :

| Champ de `config.json` | Pièce de la partie 1 | Commande équivalente |
|---|---|---|
| `linux.namespaces` (`pid`, `network`, `ipc`, `uts`, `mount`, `cgroup`) | espaces de noms | `unshare --pid --net --ipc --uts --mount --cgroup` |
| `root.path`, `root.readonly` | nouvelle racine, en lecture seule | `pivot_root` + `mount -o remount,ro,bind /` |
| `mounts` (`/proc`, `/dev` en tmpfs, `/dev/pts`, `/sys` en lecture seule…) | montages internes | `mount -t proc proc /proc`… |
| `linux.cgroupsPath` | cgroup dédié | `mkdir /sys/fs/cgroup/capot` + `cgroup.procs` |
| `linux.resources.memory.limit`, `linux.resources.pids.limit` | limites | `memory.max`, `pids.max` |
| `hostname` | nom d'hôte de l'espace `uts` | `hostname capot` |
| `process.args`, `process.env`, `process.cwd` | le processus lancé | `exec sleep infinity` |
| `process.user` (`uid`, `gid`) | identité | `setpriv --reuid … --regid …` |
| `process.capabilities` (`bounding`, `effective`…) | capacités réduites | `capsh --drop=…` / `setpriv --bounding-set` |
| `process.noNewPrivileges`, `linux.seccomp` | plus de gain de privilège, filtre d'appels système | `setpriv --no-new-privs`, filtre seccomp |
| `linux.maskedPaths`, `linux.readonlyPaths` | `/proc/kcore`, `/proc/sys`… masqués ou en lecture seule | montages par-dessus |

Vérification sur la démonstration : `cat /sys/fs/cgroup/capot/memory.max` → `67108864`, `pids.max` → `32` ; `nsenter -t <pid> -u hostname` → `capot`.

## Ce qu'ajoutent containerd et Docker

`runc` sort dès que le conteneur est lancé. **containerd** gère les images (contenu, *snapshotter* qui prépare `rootfs`), lance un **shim** (`containerd-shim-runc-v2`) par conteneur, qui en reste le parent, garde ses entrées-sorties et son code de sortie : containerd et dockerd peuvent redémarrer sans tuer les conteneurs. **Docker** ajoute l'API, la construction (BuildKit), le réseau (ponts, NAT, DNS embarqué), les volumes, les journaux. `ctr -n capot run …` montre containerd seul ; `ctr -n moby containers list` montre les conteneurs de Docker (ne pas y toucher).
