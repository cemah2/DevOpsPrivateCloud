# RB-185 — RKE2 ne démarre plus sur un serveur

| | |
|---|---|
| Portée | Serveurs RKE2 avec `profile: cis` (Rocky Linux 10, RPM, SELinux) |
| Symptôme | `rke2-server` en échec ou en redémarrage, nœud `NotReady`, etcd à N-1 membres |
| Rédigé par | Équipe Plateforme — M18-E22 (INC-4522) |

> ⚠️ Un seul serveur à la fois. Ne redémarre jamais un deuxième serveur pendant l'incident (quorum). Pas de `rke2-killall.sh`, pas de `--cluster-reset`.

## 1. Lire la première erreur

```
systemctl status rke2-server --no-pager
journalctl -u rke2-server -b --no-pager | grep -m 10 -E 'level=(fatal|error)|Error:'
uv run ansible-playbook playbooks/m18.yml --limit <NŒUD> --check --diff      # depuis ~/src/ansible
```

## 2. Messages typiques

| Message (à confirmer sur ta version) | Cause | Correctif sans affaiblir le profil |
|---|---|---|
| paramètre noyau invalide (`vm.overcommit_memory`, `kernel.panic`…) | `/etc/sysctl.d/60-rke2-cis.conf` absent ou valeurs changées | copier `/usr/share/rke2/rke2-cis-sysctl.conf`, `restorecon`, `sysctl -p <ce fichier>` |
| utilisateur ou groupe `etcd` manquant | compte supprimé | recréer avec l'**UID/GID d'origine** (`ls -n /var/lib/rancher/rke2/server/db/etcd`) |
| `yaml: line N: …` | `config.yaml` modifié à la main | rejouer le rôle ; reporter le besoin dans `rke2_config` |
| tirages en échec `registry…/rancher/…` | `system-default-registry` vers un registre sans les images | retirer ; passer par les miroirs de `registries.yaml` |
| `protect-kernel-defaults` incompatible avec le profil | quelqu'un a tenté de « contourner » | remettre la configuration du rôle |

## 3. Vérifications de l'hôte du profil CIS (à garder vertes)

`profile: cis` ; compte et groupe `etcd` ; paramètres de `rke2-cis-sysctl.conf` appliqués ; SELinux `Enforcing` (`getenforce`) ; `firewalld` arrêté (problème connu avec Canal).

## 4. Après

Trois nœuds `Ready`, trois pods `etcd-*` prêts, rôle rejoué un serveur à la fois sans changement, journal de diagnostic publié.

## 5. Ce qu'on ne fait jamais

Retirer `profile`, poser `protect-kernel-defaults: false`, `setenforce 0`, `systemctl restart systemd-sysctl` sur un nœud en service, recréer `etcd` avec un UID neuf, redémarrer un second serveur.
