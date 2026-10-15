# RB-140 — Compléments du palier 4 (à fusionner dans RB-140 « Un nœud est NotReady »)

> Sections à ajouter à ton RB-140 (M14-E22) après M14-E35. Elles supposent la section « Constater »
> de RB-140 déjà écrite (conditions, bail, taints, événements). Rien ici ne supprime ni ne rejoint
> le nœud : ce sont des réparations sur place.

| | |
|---|---|
| Cluster | `k8s-par1` (kubeadm 1.36, containerd 2.3, Debian 13, cgroup v2) |
| Complété | M14-E35 (INC-4135) |
| Interdit sans décision écrite | `kubectl delete node`, `kubeadm reset`, suppression forcée des pods du nœud |

## Arbre de décision par étage

```
Ready = Unknown (« Kubelet stopped posting node status »)
 ├─ kubelet inactif ?                       → § Kubelet arrêté
 ├─ kubelet en échec au démarrage ?         → lire la dernière ligne « command failed »
 │    ├─ « unknown flag »                   → § Configuration du kubelet
 │    └─ « running with swap on »           → § Swap
 └─ kubelet actif, « Unauthorized »         → § Certificat client
Ready = False (« container runtime is down », « PLEG is not healthy »)
 └─ containerd inactif ou en échec          → § containerd
Ready = True + DiskPressure / MemoryPressure / PIDPressure
 └─ ressources du nœud                      → § Disque
```

## Kubelet arrêté

- Preuve : `systemctl status kubelet` (`inactive (dead)`, `disabled`) ; `journalctl -b | grep -E 'Stopped kubelet|Removed .*kubelet'`.
- Correctif : `sudo systemctl enable --now kubelet`. Vérifier que le rôle `k8s_noeud` impose `enabled: true`.

## Configuration du kubelet

- Fichiers : `/var/lib/kubelet/config.yaml` (KubeletConfiguration, écrite par kubeadm), `/var/lib/kubelet/kubeadm-flags.env`, `/etc/default/kubelet` (`KUBELET_EXTRA_ARGS`, Debian), unité `10-kubeadm.conf`.
- Preuve : `journalctl -u kubelet -b | grep 'command failed'` ; `systemctl cat kubelet`.
- Rappel de version : `--pod-infra-container-image` est supprimée depuis 1.35 ; l'image sandbox est celle de containerd (`pinned_images`).
- Correctif : retirer l'option, rejouer le rôle si le fichier est géré, `sudo systemctl restart kubelet`.

## containerd

- Preuve : `systemctl status containerd`, `journalctl -u containerd -b | tail`, condition `container runtime is down`.
- Avant tout redémarrage : `sudo containerd config dump >/dev/null` (le fichier se lit-il ?).
- Correctif : rejouer le rôle `containerd` (le `config.toml` est un modèle), puis `sudo systemctl restart containerd`. Les miroirs passent par `/etc/containerd/certs.d/*/hosts.toml`, jamais par `registry.mirrors`.
- Les conteneurs en cours survivent à l'arrêt de containerd (shims) : pas d'urgence à redémarrer le nœud.

## Swap

- Preuve : `journalctl -u kubelet | grep -i swap`, `swapon --show`, `grep swap /etc/fstab`.
- Correctif : `sudo swapoff <fichier>`, retirer la ligne de `/etc/fstab`, supprimer le fichier, relancer le kubelet. Le swap encadré (*NodeSwap*, `LimitedSwap`) est une décision d'architecture (ADR), jamais un dépannage.

## Certificat client

- Preuve : `journalctl -u kubelet | grep -i unauthorized` ; `sudo openssl verify -CAfile /etc/kubernetes/pki/ca.crt /var/lib/kubelet/pki/kubelet-client-current.pem` ; `openssl x509 -noout -dates`.
- Correctif 1 (un certificat valide existe encore) : refaire pointer `kubelet-client-current.pem` vers lui, relancer le kubelet.
- Correctif 2 : procédure kubeadm *Kubelet client certificate rotation fails* (`kubeadm kubeconfig user --org system:nodes --client-name system:node:<NŒUD>` sur un nœud de contrôle, `kubelet.conf` copié par `scp`, 600, puis retour aux chemins `kubelet-client-current.pem`).
- Ne jamais transporter un `kubelet.conf` par un dépôt ou un ticket : il contient une clé privée.

## Disque

- Preuve : `kubectl describe node` (`DiskPressure`, taint `disk-pressure`), événements `Evicted … ephemeral-storage` ; sur le nœud `df -h /var/lib/containerd`, `sudo du -xh --max-depth=1 /var/lib/containerd | sort -h`.
- Ce qui appartient à containerd se nettoie par containerd et le kubelet (`sudo crictl rmi --prune`, ramasse-miettes d'images) ; ce qui n'y a rien à faire se déplace ou se supprime après identification.
- La condition retombe après `evictionPressureTransitionPeriod` (5 min). Nettoyer les pods `Failed` évincés.

## Ce qui aurait dû alerter avant l'astreinte

- `Ready` différent de `True` depuis plus de 2 min, toute condition de pression, `kubelet` ou `containerd` inactif : sonde du workbook (`lab/bin/check 14 35`) aujourd'hui, alertes Prometheus au module 21.
- Dérive des fichiers des nœuds par rapport aux rôles : `ansible-playbook … --check --diff` planifié.
