# RKE2 au profil CIS (M18-E04)

Rôle Ansible `rke2` (`plateforme/ansible`), variables `group_vars/role_rke2/rke2.yml`. Essai :
`essai-cis/`.

## Qui fait quoi (guide de durcissement CIS de RKE2, page SELinux)

| Exigence | Fournie par | Comment |
|---|---|---|
| Paramètres noyau (`vm.panic_on_oom`, `kernel.panic`, `kernel.panic_on_oops`, `vm.overcommit_memory`…) | **l'hôte** (rôle) | copie de `/usr/share/rke2/rke2-cis-sysctl.conf` (RPM) vers `/etc/sysctl.d/60-rke2-cis.conf`, rechargement **avant** le premier démarrage |
| Utilisateur et groupe `etcd` dans `/etc/passwd` et `/etc/group` | **l'hôte** (rôle) | `useradd -r -U -M -s /sbin/nologin etcd` (modules `group` et `user`) |
| Vérification de ces deux points, refus de démarrer sinon | RKE2 | `profile: cis` |
| `protect-kernel-defaults=true` du kubelet | RKE2 | posé par le profil |
| etcd en pod statique sous l'utilisateur `etcd`, dossier de données à `etcd:etcd` | RKE2 | posé par le profil |
| Pod Security `restricted` partout sauf `kube-system` et deux espaces d'opérateurs | RKE2 | `/etc/rancher/rke2/rke2-pss.yaml` + `--admission-control-config-file` |
| NetworkPolicies par défaut (`kube-system`, `kube-public`, `default`) | RKE2 | appliquées par le profil |
| Droits 600 sur manifestes et fichiers de configuration | RKE2 | appliqués par le profil |
| SELinux : politique `rke2-selinux` + `selinux: true` | RPM | dépendance `rke2-common` → `rke2-selinux` ; `/etc/sysconfig/rke2-server` |
| firewalld désactivé, NetworkManager qui ignore les interfaces du CNI | **l'hôte** (rôle) | page « Known Issues » |
| Ce qui reste à ta charge | **toi** | contrôles CIS « manuels » (journalisation d'audit, rotation, politiques réseau des applications, gestion des Secrets, comptes), le durcissement de l'OS (CIS Rocky Linux), la sauvegarde etcd, le pare-feu en amont (bordure) |
