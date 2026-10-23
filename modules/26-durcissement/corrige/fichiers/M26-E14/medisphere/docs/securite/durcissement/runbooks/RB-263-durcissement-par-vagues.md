# RB-263 — Durcir le socle par vagues

| | |
|---|---|
| **Objet** | Appliquer (ou réappliquer) le rôle Ansible `durcissement` sur les VMs du socle sans couper le lab |
| **Quand** | Première application (M26-E14) ; changement du rôle ou des exceptions ; montée de version du référentiel |
| **Qui** | Équipe Plateforme (exécution) ; RSSI (validation des exceptions, RB-261) ; astreinte prévenue |
| **Durée** | Une vague : 30 à 90 min (mesures comprises) ; tout le socle : 1 à 2 jours, une vague à la fois |
| **Liens** | Rôle `plateforme/ansible/roles/durcissement` ; vagues `inventories/lab/durcissement.yml` ; exceptions `group_vars/all/durcissement.yml` et `exceptions.md` ; RB-240 (bris de glace, M24) ; RB-261 (dérogation) ; RB-264 (pare-feu d'hôte Cilium) |

## Règles

1. **Une vague à la fois**, dans l'ordre 0 → 6. On ne commence la vague N+1 que si la vague N est verte depuis au moins une heure (checks, alertes, Mailpit muet) et que son rapport est écrit.
2. **Jamais les deux membres d'une paire dans la même passe** : passerelles, répartiteurs, nœuds d'une grappe (OpenBao, Ceph, plan de contrôle Kubernetes). À partir de la vague 4, le playbook passe un hôte à la fois (`serial: 1`) et s'arrête au premier échec.
3. **Toujours `--check --diff` d'abord**, relu par une seconde personne pour les vagues 3 à 6.
4. **Accès de secours ouvert avant toute vague** : une session SSH root (ou `sudo -i`) déjà ouverte sur chaque hôte de la passe (elle survit au rechargement de sshd), la console Proxmox testée (`qm terminal <VMID>` ou interface web), le compte de secours local (`secours`, M04) connu, et l'agent QEMU qui répond (`qm guest exec <VMID> -- true` depuis `pve01`) : c'est la seule voie si sudo casse, puisque `su` est fermé. Pour `adm01` : session de secours **obligatoire** (le playbook l'exige : `-e durcissement_secours_confirme=true`).
5. **Sauvegarde fraîche** : instantané PBS de chaque VM de la vague daté du jour (`pvesh get /nodes/pve01/storage/pbs-par2/content --content backup`).
6. **Aucune exception improvisée** pendant une vague : une règle qui casse un service → retour arrière, puis RB-261.

## Vagues

| Vague | Hôtes | Passe | Particularités |
|---|---|---|---|
| 0 | `durci-deb`, `durci-rocky` | ensemble | VMs d'essai : le rôle y passe en premier, à chaque changement |
| 1 | `mon01`, `nbx01`, `s3-01` | ensemble | Peu critiques ; `mon01` porte Mailpit (AppArmor : E13) |
| 2 | `dns02`, `runner01`, `runner02`, `reg01` | ensemble | Docker sur `runner02`/`reg01` : exceptions de routage |
| 3 | `dns01`, `ca01`, `git01`, `idp01`, `vault01` | ensemble | `git01` : compte `git` (AllowGroups) ; `vault01` seul de sa grappe |
| 4 | `vault02`, `vault03`, `kms01`, `ipa01` | un à un | `ipa01` (Rocky, FreeIPA) : SELinux, politique crypto ; vérifier `kinit`, LDAPS, SSO après |
| 5 | `lb02`, `lb01`, `gw02`, `gw01` | un à un | Membre en attente d'abord ; bascule VRRP vérifiée entre deux |
| 6 | `k8s-w01..03`, `k8s-cp01..03`, `ceph01..03`, `adm01` | un à un | `drain`/`uncordon` (K8s) et `noout` (Ceph) faits par le playbook ; `adm01` en dernier |

## Procédure (une vague)

```
admin@adm01:~/src/ansible$ git pull && uv run ansible-lint --profile production roles/durcissement
admin@adm01:~/src/ansible$ uv run ansible-inventory --graph durcissement_vague_<N>
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/conformite-mesure.yml -e vague=<N> -e moment=avant
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/durcissement.yml -e vague=<N> --check --diff | tee ~/m26/e14/vague-<N>-check.txt
# relecture du diff (seconde personne pour N ≥ 3), sessions de secours ouvertes, puis :
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/durcissement.yml -e vague=<N> | tee ~/m26/e14/vague-<N>-application.txt
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/conformite-mesure.yml -e vague=<N> -e moment=apres
```

**Contrôles après la vague** (tous, avant de fermer les sessions de secours) :

| Contrôle | Commande | Attendu |
|---|---|---|
| Nouvelle connexion SSH (clé d'Ansible) | `ssh admin@<hôte> true` | code 0 |
| Connexion d'une personne (certificat step-ca, M24-E20) | `step ssh login … ; ssh <toi>@<hôte> sudo -l` | session ouverte, règles sudo de l'annuaire listées |
| sudo de l'automatisation | `ansible <hôte> -b -m ansible.builtin.command -a true` | `CHANGED`/`SUCCESS` |
| Services de l'hôte | `systemctl --failed` ; checks des modules concernés | aucune unité en échec ; checks verts |
| Paires (vagues 4-6) | `ip -br a` (VIP), `bao operator raft list-peers`, `ceph -s`, `kubectl get nodes` | VIP au bon endroit, quorum, `HEALTH_OK`, nœuds `Ready` |
| Intégrité | `sudo /usr/local/sbin/aide-nouvelle-base` sur chaque hôte | nouvelle base en service (le changement voulu n'est plus un écart) |
| Supervision | Alertmanager, Mailpit (`astreinte@`) | aucune nouvelle alerte liée à la vague |

Puis : rapport de vague (`rapports/vague-<N>.md`, modèle ci-dessous), MR, et seulement ensuite la vague suivante.

## Retour arrière

| Situation | Action |
|---|---|
| Le playbook échoue sur un contrôle du rôle (avant pose) | Rien n'a été posé pour ce domaine : corriger la cause (souvent une exception manquante), relancer |
| Un service ne marche plus, l'accès SSH est intact | `git revert` du commit fautif (ou exception validée en urgence par la RSSI), rejouer la vague sur l'hôte : `--limit <hôte>` |
| SSH coupé, session de secours ouverte | Dans la session : `sudo mv /etc/ssh/sshd_config.d/00-durcissement.conf /root/ ; sudo systemctl reload ssh` (ou `sshd` sur Rocky) ; puis `git revert` |
| SSH coupé, plus de session | Console Proxmox (`qm terminal <VMID>` ou interface), compte `secours` puis `sudo -i`, même correctif ; si la console ou sudo font défaut : `qm guest exec <VMID> -- mv /etc/ssh/sshd_config.d/00-durcissement.conf /root/` puis `qm guest exec <VMID> -- systemctl reload ssh` (`sshd` sur Rocky) |
| sudo cassé, session root encore ouverte | Dans la session : `visudo -c` ; retirer `/etc/sudoers.d/00-durcissement` ; `faillock --user <compte> --reset` si verrouillage |
| sudo cassé, plus de session root | `secours` passe lui aussi par sudo, et `su` est fermé par `pam_wheel` (groupe vide) : passer par l'**agent QEMU** depuis `pve01` (root dans la VM, M00) : `qm guest exec <VMID> -- visudo -c`, puis `qm guest exec <VMID> -- mv /etc/sudoers.d/00-durcissement /root/` (ou `-- faillock --user <compte> --reset`) ; puis `git revert` et rejeu |
| Hôte inutilisable | Restauration PBS de l'instantané du jour (procédure de restauration du M00), puis enquête sur une copie |

## Rapport de vague (modèle)

```
# Vague <N> — <date>

| Hôte | CIS avant | CIS après | ANSSI avant | ANSSI après | Exceptions | Redémarrage requis |
|---|---|---|---|---|---|---|

## Incidents et retours arrière
## Écarts restants (règles en échec, non justifiées) et décision
## Exceptions ajoutées (RB-261) — lien vers la MR
```
