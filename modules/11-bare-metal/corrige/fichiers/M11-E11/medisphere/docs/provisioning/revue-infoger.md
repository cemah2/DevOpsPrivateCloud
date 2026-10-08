# Revue des fichiers d'installation d'InfoGér (SEC-1216)

| | |
|---|---|
| Fichiers | `preseed-infoger.cfg` (Debian, `app-prod-01` à `06`), `ks-infoger.cfg` (Rocky, `db-prod-01` et `02`) — archive du partage `\\infoger-nas\deploiement\` |
| Revue | <MOI>, JJ/MM/AAAA ; relecture : Sophie Laurent |
| Outils | lecture ; `debconf-set-selections -c` et `ksvalidator` passent : les défauts ne sont pas syntaxiques |

## Défauts

| # | Fichier, lignes | Défaut | Risque | Gravité | Correction |
|---|---|---|---|---|---|
| 1 | preseed `passwd/root-*`, `passwd/user-*` ; ks `rootpw --plaintext`, `user … --plaintext` | Mots de passe **en clair**, le même pour root et `support`, sur tous les serveurs, dans un fichier servi en HTTP | Quiconque a lu le fichier (VLAN, partage, sauvegardes d'InfoGér) a le mot de passe root de tous les serveurs | Critique | Empreintes (`passwd/*-crypted`, `--iscrypted`), root verrouillé, mot de passe par serveur ; **le mot de passe est compromis** : le changer partout |
| 2 | preseed `debian-installer/allow_unauthenticated true` | Apt accepte des paquets **non signés** pendant l'installation | Un intermédiaire sur le chemin du miroir injecte un paquet piégé, exécuté en root | Critique | Supprimer la ligne ; un problème de clé se corrige (trousseau), il ne se contourne pas |
| 3 | preseed `late_command … curl -k … \| bash` | Exécution en root d'un script **téléchargé sans vérification TLS** depuis le serveur d'un **tiers** | InfoGér (ou quiconque contrôle `pxe.infoger.local` ou le réseau) exécute ce qu'il veut sur chaque serveur installé ; le serveur n'existe plus : contenu inconnu | Critique | Pas de script externe ; ce qui doit être fait au premier démarrage est dans notre dépôt, vérifié (empreinte) ou fait par Ansible |
| 4 | preseed `PermitRootLogin yes` (late_command) ; ks `%post` idem | Connexion SSH de root **par mot de passe** | Combiné à 1 : accès root à distance avec un mot de passe connu | Critique | Rien dans le preseed (défaut Debian : `prohibit-password`) ; `ssh_durci` (M04) au premier passage d'Ansible |
| 5 | ks `sshkey --username=root "… support@infoger"`, `%post` `support ALL=(ALL) NOPASSWD: ALL` | **Clé SSH du prestataire** dans root, compte `support` sudo sans mot de passe | Porte dérobée de l'ancien prestataire, active après la fin du contrat | Critique | Supprimer ; aucune clé tierce ; comptes nominatifs ou certificats d'utilisateur (M06-E20) |
| 6 | preseed `apt-setup/services-select` vide, `pkgsel/upgrade none` | Pas de dépôt de **sécurité**, aucune mise à jour à l'installation | Serveurs vulnérables dès le premier jour, et qui le restent | Majeure | `security, updates` ; `full-upgrade` |
| 7 | ks `url --url=http://pxe.infoger.local/rocky/9/… --noverifyssl` | Paquets d'un **miroir du prestataire**, en HTTP, Rocky **9** | Source non maîtrisée (et disparue) ; version ancienne | Majeure | Miroir officiel en HTTPS (ou miroir interne), version courante (Rocky 10, PLAN §6) |
| 8 | ks `zerombr` + `clearpart --all` sans `--drives` ni `ignoredisk` ; preseed `/dev/sda`, `regular` | Tous les disques effacés (ks) ; « premier disque » non déterministe (preseed) ; pas de LVM | Une réinstallation d'un serveur de base de données **efface les disques de données** ; installation sur une clé USB ou un disque de données | Majeure | `ignoredisk --only-use=` + `clearpart --drives=` (par chemin stable `/dev/disk/by-path/…`) ; LVM |
| 9 | ks `selinux --disabled`, `firewall --disabled` | Protections désactivées « parce qu'elles gênent PostgreSQL » | Surface d'attaque, et SELinux désactivé ne se réactive pas sans réétiquetage | Majeure | `enforcing`, pare-feu actif avec les seuls ports de PostgreSQL ; corriger le contexte SELinux de PostgreSQL au lieu de désactiver |
| 10 | preseed `netcfg/get_hostname medisphere` ; ks `--hostname=db.medisphere.local` ; `reboot` en fin des deux | Même nom pour tous ; domaine `.local` (réservé à mDNS, RFC 6762) ; redémarrage en fin d'installation | Collisions de noms, résolution imprévisible ; réinstallation en boucle avec un démarrage réseau prioritaire | Mineure | Nom par serveur (source de vérité) ; `par1.medisphere.internal` ; extinction |

## Contrôles sur les serveurs installés

À lancer sur chacun, en lecture :
```
sudo sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication)'
sudo grep -rn 'infoger' /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys 2>/dev/null
getent passwd support; sudo ls -l /etc/sudoers.d/; sudo cat /etc/sudoers.d/support 2>/dev/null
grep -rhE '^deb|^URIs|^Suites' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null   # Debian : security ?
sudo apt-config dump | grep -i 'AllowUnauthenticated'                                     # Debian : reste-t-il ?
getenforce; systemctl is-enabled firewalld; dnf repolist                                  # Rocky
sudo passwd -S root; sudo lastlog | grep -v 'Never'; sudo last -n 50                       # connexions
sudo find / -xdev -newer /etc/hostname -path /proc -prune -o -type f -perm -4000 -print 2>/dev/null   # suid ajoutés après l'installation
```
Et, parce que `postinstall.sh` a exécuté un contenu inconnu : inventaire des comptes, des tâches planifiées (`/etc/cron*`, `systemctl list-timers`), des services activés et des clés autorisées, comparé à un serveur de référence ; en cas de doute, réinstallation.

## Conclusion

Fichiers à **retirer** de tout partage ; une copie unique conservée comme pièce (audit HDS, éventuelle procédure contre l'ancien prestataire) dans un coffre à accès restreint, avec la mention « mots de passe compromis » ; changement immédiat des mots de passe root et suppression du compte `support` et de la clé d'InfoGér sur les huit serveurs ; ticket de sécurité (SEC-12xx) pour le suivi.
