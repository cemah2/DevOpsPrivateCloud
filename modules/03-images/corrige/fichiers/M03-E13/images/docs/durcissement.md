# Durcissement des images dorées MédiSphère

> Ticket SEC-450 (Sophie Laurent). Appliqué par `scripts/durcir.sh` dans chaque image dorée
> (`debian13-gold`, puis `rocky10-gold`), vérifié à chaque build par le script lui-même et sur
> un clone par `tests/tester-image.sh`. Dernière revue : AAAA-MM-JJ, Sophie Laurent et Karim Benali.

## Principes

- **Référentiels** : guide ANSSI « Recommandations de configuration d'un système GNU/Linux »
  (ANSSI-BP-028, v2.0, niveau *intermédiaire* visé) et CIS Benchmark de la distribution
  (Debian Linux 12/13, Rocky/RHEL 10), profil *Level 1 – Server*. Chaque mesure ci-dessous cite
  le **thème** du référentiel ; le numéro exact de la recommandation est à reporter depuis la
  version du guide que l'audit utilise (les numéros changent d'une version à l'autre).
- **Image ≠ hôte** : l'image porte ce qui vaut pour **toutes** les VMs. Ce qui dépend du rôle
  (pare-feu local, comptes applicatifs, journaux distants) est posé par Ansible (module 04).
- **Rien qui empêche l'exploitation** : cloud-init, l'agent QEMU, SSH par clé depuis `adm01`,
  la construction par Packer et les tests doivent continuer de fonctionner (vérifié par le
  pipeline).

## Mesures

| # | Mesure | Où | Référence (thème) | Vérification |
|---|---|---|---|---|
| S1 | Root et mots de passe refusés en SSH | `sshd_config.d/10-medisphere.conf` (E09) | ANSSI : accès distant SSH ; CIS : serveur SSH | `sshd -T` |
| S2 | Pas de X11, d'agent, de redirection TCP ni de tunnel | `05-durcissement.conf` | ANSSI : SSH, fonctions inutiles ; CIS : serveur SSH | `sshd -T` |
| S3 | 3 essais, 30 s pour s'authentifier, `MaxStartups` | `05-durcissement.conf` | CIS : serveur SSH | `sshd -T` |
| S4 | Algorithmes : échange de clés hybride ou X25519, AEAD/CTR, MAC ETM SHA-2 ; ni SHA-1 ni CBC | ajoutés par `durcir.sh` (filtrés par `ssh -Q`) | ANSSI : recommandations pour OpenSSH ; CIS : serveur SSH | `sshd -T`, `ssh-audit` (facultatif) |
| S5 | Sessions inactives fermées (3 × 300 s), journal `VERBOSE` (empreinte de la clé) | `05-durcissement.conf` | CIS : serveur SSH | `sshd -T` |
| S6 | Bannière légale | `/etc/issue.net` | CIS : bannières | `sshd -T` (banner) |
| N1 | Redirections ICMP ni acceptées ni émises, pas de routage par la source, martiens journalisés | `sysctl.d/60-medisphere-durcissement.conf` | ANSSI : paramètres réseau IPv4/IPv6 ; CIS : paramètres réseau | `sysctl` (all **et** interface) |
| N2 | Pointeurs noyau masqués, `dmesg` réservé, `ptrace` restreint, BPF non privilégié interdit, `kexec` interdit | idem | ANSSI : paramètres du noyau ; CIS : durcissement des processus | `sysctl` |
| N3 | Protections des liens et fichiers dans les répertoires partagés, pas de *core dump* setuid | idem | ANSSI : paramètres des systèmes de fichiers | `sysctl` |
| M1 | DCCP, SCTP, RDS, TIPC non chargeables | `modprobe.d/medisphere-durcissement.conf` | ANSSI : modules noyau ; CIS : modules réseau | `modprobe -n -v` |
| M2 | cramfs, freevxfs, hfs, hfsplus, jffs2 non chargeables | idem | CIS : modules de systèmes de fichiers | `modprobe -n -v` |
| M3 | Stockage USB, FireWire, Thunderbolt non chargeables | idem | CIS : modules de systèmes de fichiers | `modprobe -n -v` |
| F1 | `/dev/shm` : `noexec,nosuid,nodev` | `/etc/fstab` | ANSSI : options de montage ; CIS : options de montage | `findmnt` |
| A1 | auditd actif ; identités, sudo, sshd, cloud-init, sysctl, modules, élévations tracés | `audit/rules.d/50-medisphere.rules` | ANSSI : journalisation ; CIS : auditd (partiel) | `auditctl -l` |
| R1 | Pas de LLMNR ni de mDNS (ports 5355 fermés) | `resolved.conf.d/60-medisphere.conf` | ANSSI : services réseau ; CIS : services | `ss -tlnu` |
| R2 | Aucun port TCP en écoute hors SSH (hors boucle locale) | contrôlé par `durcir.sh` | ANSSI : minimisation des services | `ss -Htln` |
| U1 | Correctifs de sécurité automatiques | `apt.conf.d/` (E09) | ANSSI : mises à jour ; CIS : mises à jour | `apt-config dump` |
| J1 | Journal persistant | `journald.conf.d/50-medisphere.conf` (E09) | ANSSI : journalisation | `/var/log/journal` |

## Exceptions et écarts assumés

| Référence | Mesure non appliquée | Raison | Compensation | Revue |
|---|---|---|---|---|
| CIS : partitions | Partitions séparées `/tmp`, `/var`, `/var/log`, `/home` | Image *cloud* à partition unique redimensionnée au clonage ; le partitionnement fixerait des tailles pour tous les rôles | `/tmp` en tmpfs (`nosuid,nodev`, Debian 13) ; quotas et volumes dédiés par Ansible pour les rôles qui écrivent beaucoup (bases de données, journaux) | annuelle |
| CIS : chargeur d'amorçage | Mot de passe GRUB | Console accessible uniquement par l'API Proxmox (comptes nominatifs, MFA en M24) ; un mot de passe GRUB partagé par toutes les VMs serait un secret dans l'image | droits Proxmox `VM.Console` restreints | annuelle |
| CIS : mots de passe | Politique de mots de passe (pwquality, expiration) | Aucun mot de passe : authentification par clé uniquement (S1) | S1, comptes injectés par cloud-init | — |
| ANSSI : IPv6 | Désactivation d'IPv6 | IPv6 non routé par `gw01` mais nécessaire localement (`::1`) ; le désactiver casse des logiciels | redirections IPv6 refusées (N1) | à la mise en service d'IPv6 |
| CIS : pare-feu local | Pare-feu local (nftables) dans l'image | Dépend du rôle : posé par Ansible (M04) ; filtrage déjà assuré par `gw01` et le pare-feu Proxmox | `gw01`, pare-feu Proxmox | M04 |
| CIS : intégrité des fichiers | AIDE (intégrité des fichiers) | Base de référence à construire **après** le rôle applicatif, sinon fausses alertes | à évaluer au module 26 (OpenSCAP, Falco) | M26 |
| — | `kernel.sysrq` laissé à la valeur de la distribution | Utile pour diagnostiquer une VM bloquée depuis la console série | accès à la console limité (Proxmox) | annuelle |

## Mesure avant/après

Outil : Lynis 3.1 (paquet Debian `lynis`), lancé sur un clone de l'image **avant** (9010, v1 de
E09) et **après** durcissement (clone de test 2035), même version de Lynis, même profil :

```
admin@m03-durci:~$ sudo lynis audit system --quick --no-colors | tee /tmp/lynis.txt | grep 'Hardening index'
```

| Image | Indice de durcissement Lynis | Avertissements | Suggestions |
|---|---|---|---|
| `deb13-gold-AAAAMMJJ-1` (avant) | à relever | à relever | à relever |
| `deb13-gold-AAAAMMJJ-N` (après) | à relever | à relever | à relever |

L'indice n'est pas un objectif : une suggestion de Lynis non suivie est soit une exception
ci-dessus, soit une mesure qui relève du rôle (Ansible). Le contrôle de conformité outillé
(OpenSCAP, profils CIS/ANSSI) est traité au module 26.

## Procédure de modification

1. MR sur `plateforme/images` modifiant `fichiers/durcissement/` ou `scripts/durcir.sh` **et**
   ce document (mesure, référence, vérification) ; relecture par Sophie Laurent.
2. Le pipeline construit l'image, `durcir.sh` vérifie chaque mesure, `tests/tester-image.sh`
   vérifie un clone ; la nouvelle version n'est publiée (`current`) qu'après ces deux contrôles.
3. Toute nouvelle exception est datée, justifiée et revue.
