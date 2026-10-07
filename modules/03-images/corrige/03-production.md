# Module 03 — Corrigé du palier 3 : Production

> ⚠️ Corrigé — à lire après avoir cherché.

Fichiers de référence : `corrige/fichiers/M03-E13/` à `M03-E17/` (état du projet après chaque exercice ; un fichier non repris est inchangé depuis l'exercice précédent, en particulier `outils/pve.sh`, `construire.sh`, `version-image.sh`, `publier-image.sh` de M03-E10).

---

### M03-E13 — Durcir une image

**Solution**

Fichiers : [`fichiers/M03-E13/images/`](fichiers/M03-E13/images/)

| Fichier | Rôle |
|---|---|
| `scripts/durcir.sh` | applique et **vérifie** chaque mesure ; échoue le build au moindre écart ; Debian et famille RHEL |
| `fichiers/durcissement/ssh/05-durcissement.conf` | SSH (hors algorithmes, ajoutés par le script) |
| `fichiers/durcissement/sysctl/60-medisphere-durcissement.conf` | noyau et réseau |
| `fichiers/durcissement/modprobe/medisphere-durcissement.conf` | modules interdits |
| `fichiers/durcissement/audit/50-medisphere.rules` | règles auditd |
| `fichiers/durcissement/resolved/60-medisphere.conf` | LLMNR et mDNS désactivés |
| `fichiers/durcissement/issue.net` | bannière légale |
| `debian13-gold/build.pkr.hcl` | appel de `durcir.sh` (étape « 2 bis ») |
| `docs/durcissement.md` | mesures, références, exceptions, mesure avant/après |

*1. Place dans le build.* Le durcissement s'exécute **après** `gold-debian13.sh` (il installe `auditd`, modifie des fichiers que le contenu a posés) et **avant** le manifeste des paquets (qui doit lister `auditd`) et la préparation au clonage (qui reste la dernière étape). `gold-debian13.sh` efface `/tmp/fichiers` à la fin : les fichiers de durcissement sont déposés dans un dossier à part (`/tmp/durcissement`), effacé par `durcir.sh`.

```hcl
  provisioner "file" {
    source      = "${path.root}/../fichiers/durcissement/"
    destination = "/tmp/durcissement"
  }
  provisioner "shell" {
    execute_command  = "chmod +x '{{ .Path }}'; sudo env {{ .Vars }} '{{ .Path }}'"
    environment_vars = ["DURCISSEMENT=/tmp/durcissement"]
    script           = "${path.root}/../scripts/durcir.sh"
  }
```

*2. SSH.* Le fichier `05-durcissement.conf` est lu **avant** `10-medisphere.conf` (E09), `50-cloud-init.conf` et le reste de `sshd_config` : sshd retient la première valeur lue, donc nos réglages gagnent toujours. Les listes d'algorithmes sont construites par le script en ne gardant que ce que `ssh -Q kex|cipher|mac` connaît : Debian 13 (OpenSSH 10.0) propose l'échange hybride post-quantique `mlkem768x25519-sha256`, Rocky 10 aussi ; une version plus ancienne refuserait de démarrer sur un nom inconnu. Contrôle final sur la configuration **effective** :

```
admin@m03-durci:~$ sudo sshd -T | grep -E '^(x11forwarding|allowagentforwarding|allowtcpforwarding|maxauthtries|logingracetime|clientalive|banner|macs|kexalgorithms|ciphers) '
x11forwarding no
allowagentforwarding no
allowtcpforwarding no
maxauthtries 3
logingracetime 30
clientaliveinterval 300
clientalivecountmax 3
banner /etc/issue.net
kexalgorithms mlkem768x25519-sha256,sntrup761x25519-sha512,sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org
ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes128-ctr
macs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
```

Par défaut, OpenSSH 10 propose encore `hmac-sha1` et `hmac-sha1-etm@openssh.com` parmi les MAC : c'est l'écart que l'exigence « aucun SHA-1 » vise. Le client Go de Packer (`x/crypto/ssh`) et OpenSSH de `adm01` et `runner01` connaissent `curve25519-sha256`, ChaCha20-Poly1305, AES-GCM et les MAC ETM SHA-2 : la construction et les tests continuent de fonctionner. `systemctl reload` ne coupe pas la session SSH de Packer en cours.

*3. Noyau.* Sur un hôte qui ne route pas, une interface accepte les redirections ICMP si `all` **ou** l'interface l'autorise (documentation `ip-sysctl` du noyau, `accept_redirects`) : régler `all` ne suffit pas. Les motifs `net.ipv4.conf.*.…` de `sysctl.d` (systemd-sysctl, `sysctl.d(5)`) couvrent `all`, `default` et chaque interface existante, et la règle udev `99-systemd.rules` réapplique les clés à chaque nouvelle interface. Le script applique le fichier avec `/usr/lib/systemd/systemd-sysctl` (qui comprend les motifs) et vérifie les valeurs.

```
admin@m03-durci:~$ sudo sysctl net.ipv4.conf.all.accept_redirects net.ipv4.conf.eth0.accept_redirects net.ipv4.conf.all.send_redirects net.ipv4.conf.all.log_martians kernel.kptr_restrict
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.eth0.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.log_martians = 1
kernel.kptr_restrict = 2
```

`kptr_restrict = 2` cache les adresses du noyau même à root (1 les montre à qui a `CAP_SYSLOG`) : c'est ce que demande Sophie.

*4. Modules.* `install <module> /bin/false` fait échouer **tout** chargement, explicite compris ; `blacklist` n'empêche que le chargement automatique par alias. Vérification : `modprobe -n -v sctp` affiche `install /bin/false`. **Ne jamais** interdire `isofs` (ni `udf`) : le lecteur cloud-init de Proxmox est une image ISO 9660 étiquetée `cidata` ; sans `isofs`, cloud-init ne trouve plus sa configuration (symptôme identique à M03-E21). Le script refuse de continuer si ce cas se présente. Sur la famille RHEL, `/etc/modprobe.d` est copié dans l'initramfs : `dracut -f --regenerate-all`.

*5. `/dev/shm`.* Ligne `tmpfs /dev/shm tmpfs defaults,nosuid,nodev,noexec 0 0` dans `/etc/fstab` et `mount -o remount`. (`/tmp` est déjà un tmpfs `nosuid,nodev` sous Debian 13 : c'est une valeur par défaut, elle n'entre pas dans les mesures.)

*6. Audit.* `auditd` installé, règles dans `/etc/audit/rules.d/50-medisphere.rules`, chargées par `augenrules --load` : identités, sudo, sshd, cloud-init, `sysctl.d`, `modprobe.d`, chargement de modules, élévations de privilèges par un humain (`auid >= 1000`). Pas de règle sur `adjtimex` : chronyd ajuste l'horloge en permanence et noierait le journal.

*7. Surface.* Debian 13 *genericcloud* active `systemd-resolved`, qui répond par défaut en **LLMNR** sur toutes les interfaces (TCP et UDP 5355) : c'est le seul port inattendu d'un clone de la v1. `LLMNR=no` et `MulticastDNS=no` dans `resolved.conf.d`. Le script vérifie ensuite qu'aucun port TCP n'écoute hors boucle locale, sauf 22.

*8. Mesure avant/après.* Lynis (paquet Debian `lynis`, version 3.1.x) sur un clone de la v1 puis sur 2035, même version, `lynis audit system --quick` : l'indice de durcissement gagne typiquement une quinzaine de points ; les suggestions restantes (partitions séparées, mot de passe GRUB, AIDE, politique de mots de passe, pare-feu local) sont toutes dans le tableau des exceptions de `docs/durcissement.md`. Les chiffres exacts dépendent de la version de Lynis : note les tiens.

*9. Recette.*

```
admin@adm01:~/src/images$ outils/construire.sh debian13-gold
admin@adm01:~$ ssh pve01 qm clone <VMID-NOUVELLE> 2035 --name m03-durci --full 1 --storage local-nvme --pool lab
admin@adm01:~$ ssh pve01 "qm set 2035 --net0 virtio,bridge=vsandbox --ipconfig0 ip=dhcp --ciuser admin --sshkeys /root/adm01.pub --ciupgrade 0 --tags env-m03 && qm start 2035"
admin@adm01:~/DevOpsPrivateCloud$ lab/bin/check 03 13
```

(`/root/adm01.pub` : copie de `~/.ssh/id_ed25519.pub` sur `pve01`, `qm set --sshkeys` prend un **fichier**.) Puis `outils/publier-image.sh <VMID-NOUVELLE>`, et `qm destroy 2035 --purge` une fois le contrôle vert.

**Explications**

Un durcissement d'image a trois ennemis : la mesure qui n'est pas effective (écrite dans le mauvais fichier, écrasée par un autre, non appliquée à l'interface), la mesure qui casse une fonction dont on dépend (cloud-init, agent, construction), et la mesure qu'on ne sait pas justifier en audit. D'où les trois choix structurants : vérifier la **configuration effective** dans le script lui-même (le build échoue plutôt que de produire une image fausse), tenir la liste des dépendances de la plateforme (lecteur ISO, SSH de Packer, agent) et documenter chaque mesure **et** chaque exception avec sa raison et sa compensation. Le test d'image (E14) refait les vérifications essentielles sur un clone, après le premier démarrage : c'est là que les mesures « appliquées pendant le build mais perdues au démarrage » se révèlent.

**Alternatives**
- **Rôle Ansible de durcissement** (par exemple la collection `devsec.hardening`) appliqué par Packer (provisioner `ansible`) : réutilisable sur les VMs existantes, mais une dépendance de plus dans le build ; c'est l'approche naturelle à partir du module 04, où le même rôle servira à l'image et au parc.
- **OpenSCAP** avec un profil ANSSI ou CIS (`scap-security-guide`) en remédiation automatique : couverture large et rapport d'audit standard, mais des centaines de règles à trier (beaucoup cassent un environnement *cloud*) ; traité au module 26.
- **Crypto-policies** sur la famille RHEL (`update-crypto-policies`) plutôt que des listes d'algorithmes dans sshd : cohérent pour tout le système (TLS, SSH, Kerberos) ; ici on garde la même mesure sur les deux familles pour la lisibilité, la politique système restant une piste d'amélioration.

**Pièges classiques**
- Écrire les réglages SSH dans `sshd_config` après la ligne `Include` : ceux de `sshd_config.d` gagnent, les tiens sont ignorés silencieusement.
- Une liste d'algorithmes copiée d'un guide plus récent que l'OpenSSH de l'image : sshd ne démarre plus, et la VM n'est plus joignable qu'à la console.
- `blacklist usb-storage` « parce que le CIS le dit » : un `modprobe usb-storage` le charge quand même.
- Interdire `isofs`/`udf` avec les systèmes de fichiers « exotiques » : cloud-init perd sa source de données.
- Régler `net.ipv4.conf.all.*` seulement, ou `default` seulement : les interfaces existantes gardent leur valeur.
- Mesurer avant/après avec deux versions différentes de l'outil d'audit.
- Supprimer un service pour faire baisser un score sans vérifier ce qui en dépendait (`systemd-resolved` fournit le résolveur des VMs Debian : on retire LLMNR, pas le service).

**En production chez MédiSphère**
Le référentiel de durcissement est un document de la RSSI, versionné et relu à chaque version majeure de distribution ; chaque exception a un propriétaire et une date de revue. Le même rôle Ansible durcit l'image et le parc (module 04), un contrôle de conformité outillé (OpenSCAP, module 26) tourne chaque semaine sur les clones de test et sur un échantillon de VMs, et ses écarts remontent comme des alertes, pas comme un rapport PDF.

---

### M03-E14 — Tester automatiquement une image

**Solution**

Fichier : [`fichiers/M03-E14/images/tests/tester-image.sh`](fichiers/M03-E14/images/tests/tester-image.sh) (utilise `outils/pve.sh` de M03-E10).

*1. Deux clones.* Une identité « unique » ne se prouve qu'en comparant deux instances : un seul clone peut avoir un `machine-id` bien formé… identique à celui de tous ses frères. Le test crée deux clones liés (VMID libres de 2030-2033), les démarre en parallèle (le second démarrage ne coûte presque rien en temps) et compare `machine-id`, empreintes des clés d'hôte et adresses DHCP. Il vérifie en plus que la clé d'hôte est plus récente que le démarrage du clone (`stat -c %Y` contre `date +%s - /proc/uptime`) : une clé héritée du template serait plus ancienne.

*2. Clé jetable et `known_hosts`.* `ssh-keygen` dans un dossier temporaire, clé publique encodée en URL puis passée en `sshkeys` (double encodage de l'API, M00-E18). Le test ne dépend plus de la clé de `adm01` et tourne tel quel sous `gitlab-runner`. `known_hosts` propre au test avec `StrictHostKeyChecking=accept-new` : la clé d'hôte est apprise à la première connexion. Risque résiduel : un équipement capable d'usurper l'adresse d'une VM de test sur le VLAN 99 au moment exact de la première connexion ; il faudrait contrôler `gw01` ou le VLAN bac à sable. L'alternative (lire l'empreinte par l'agent QEMU avant de se connecter) demande `VM.GuestAgent.FileRead` ou `Unrestricted` au jeton : plus de droits pour un gain faible. `ControlPath=none` : sans lui, une connexion maîtresse encore ouverte vers la même adresse (une ancienne VM de test qui avait reçu la même IP) serait réutilisée, et le test interrogerait **une autre machine** sans le savoir (M00-E15, rappelé en E10).

*3. Contrôles.* Les commandes de `/usr/sbin` (`sysctl`, `modprobe`, `sshd`) ne sont pas dans le `PATH` de l'utilisateur `admin` sur Debian : le test préfixe chaque commande distante par `PATH=$PATH:/usr/sbin:/sbin`. Choix notables :

| Contrôle | Commande | Pourquoi ainsi |
|---|---|---|
| cloud-init | `cloud-init status --wait` (code 0) | 2 = erreurs récupérables : une clé dépréciée ou un module en échec passent inaperçus si on l'accepte |
| nom | `hostname` = nom de la VM | prouve que le *user-data* de Proxmox a été appliqué à **cette** instance |
| temps | `chronyc waitsync 12` puis `^*` sur la passerelle | attente bornée (2 min) ; la source attendue est **calculée** (route par défaut), pas codée en dur |
| CA | `openssl verify -CAfile <magasin consolidé> <certificat>` | la présence du fichier ne prouve pas qu'`update-ca-certificates` a été lancé |
| sshd, noyau, modules, auditd, ports | `sshd -T`, `sysctl`, `modprobe -n -v`, `ss -Htln` | configuration **effective** après le premier démarrage (E13) |
| build | `id packer`, historique de root | la préparation (E07) a bien eu lieu |
| famille | lue dans `/etc/os-release` | magasin de certificats, outil de correctifs et SELinux diffèrent sur Rocky (E25) |

*4. JUnit.* Un `testcase` par contrôle, `failure message` avec la dernière ligne d'erreur. En CI, `artifacts:reports:junit` l'affiche dans l'onglet *Tests* du pipeline et dans la MR.

*5. Nettoyage.* Tableau des VMID rempli **au fil des clonages**, piège `EXIT` (déclenché aussi par `exit` dans `echec`, et par Ctrl-C qui termine le script) ; garde-fou : une VM n'est détruite que si son nom est celui que le test lui a donné. `--garder` ne garde qu'en cas d'échec.

*6. Le test du test.*

```
root@pve01:~# qm clone <VMID-CURRENT> 9091 --name essai-mal-prepare --full 1 --storage local-nvme --pool lab
root@pve01:~# qm set 9091 --net0 virtio,bridge=vsandbox --ipconfig0 ip=dhcp --ciuser admin --sshkeys /root/adm01.pub
root@pve01:~# qm start 9091      # premier démarrage : machine-id, clés, état cloud-init
root@pve01:~# qm shutdown 9091 && qm template 9091
admin@adm01:~/src/images$ tests/tester-image.sh --junit /tmp/e14.xml 9091; echo "code=$?"
…
  [KO] machine-id initialisés et différents d'un clone à l'autre — 3f9c…e1 / 3f9c…e1
  [OK] clés d'hôte SSH différentes d'un clone à l'autre
  [KO] clés d'hôte générées au premier démarrage du clone (pas héritées du template)
  [KO] adresses DHCP différentes — même adresse 10.10.99.142 : identifiant DHCP partagé ?
…
== essai-mal-prepare : NON CONFORME
code=1
root@pve01:~# qm destroy 9091 --purge
```

Selon l'ordre des choses, la seconde VM peut ne jamais obtenir d'adresse distincte, ou les deux répondre sur la même : c'est la panne de M03-E20. Les clés d'hôte, elles, sont différentes (cloud-init voit une nouvelle instance et les régénère, `ssh_deletekeys` valant vrai par défaut)… mais **plus anciennes que le démarrage** sur l'une des deux ? Non : elles sont neuves ; c'est le contrôle de date qui échoue si la régénération n'a pas eu lieu. Note précisément ce que ton test a vu : c'est ce qui rend un test utile, pas son code retour seul. Sur `current` : `code=0`, environ 3 à 4 minutes (deux clones liés, attente de chrony comprise).

**Explications**

Un test d'image vérifie des **promesses** faites aux consommateurs, observées là où elles comptent : sur un clone, après son premier démarrage, de l'extérieur. Vérifier le template lui-même (fichiers absents, `machine-id` vide) est utile pendant le build (E07) mais ne prouve pas le comportement des clones. Le test est autonome (clé, `known_hosts`, multiplexage, droits) parce qu'il doit tourner à l'identique sur un poste et en CI : un test qui ne tourne que « chez toi » ne protège pas la publication.

**Alternatives**
- **Goss** ou **Testinfra** (module 29) : contrôles déclaratifs, lisibles, avec un vrai rapport ; la mécanique de clonage et de nettoyage reste nécessaire autour.
- **Tester dans le build** (provisioners de vérification sur la VM de construction) : plus rapide, mais teste la VM **avant** la préparation au clonage, pas un clone.
- **Un seul clone + comparaison au template** (empreintes enregistrées dans le manifeste) : moins de ressources, mais suppose que le manifeste ne contienne aucune identité, ce qui est justement ce qu'on veut éviter.

**Pièges classiques**
- `cloud-init status` sans `--wait` : « running » au moment du test, faux négatif aléatoire.
- Accepter le code 2 de `cloud-init status` « parce qu'il y a toujours un avertissement » : on rate les régressions.
- Oublier `ControlPath=none` : le test « passe » en parlant à la VM du test précédent.
- Calculer la liste des VMs à détruire à la fin (par nom ou par plage) : on détruit la VM d'un autre test, ou on oublie celle dont le clonage a échoué à moitié.
- Tester la présence de `/usr/local/share/ca-certificates/…crt` au lieu de la confiance effective.
- Coder 10.10.99.1 en dur : le jour où le test tourne sur un autre VNet, il ment.

**En production chez MédiSphère**
Le test d'image est un **contrat** versionné avec le catalogue : chaque promesse de `docs/socle/images.md` a son contrôle, chaque incident d'image (palier 4) ajoute le sien. Les rapports JUnit sont conservés avec les artefacts de build (90 jours) : ils prouvent à l'auditeur que la version en service a été testée, et comment.

---

### M03-E15 — Pipeline de construction d'images

**Solution**

Fichiers : [`fichiers/M03-E15/`](fichiers/M03-E15/) — `images/.gitlab-ci.yml`, `installer-packer-runner01.sh`, `gw01-nftables-extrait.nft`.

*1. Le runner.* Copier l'ancre de `pve01` puis lancer le script sur `runner01` :

```
admin@adm01:~$ scp ~/.config/workbook/pve-root-ca.pem runner01:/tmp/pve01-root-ca.crt
admin@adm01:~$ scp installer-packer-runner01.sh runner01:/tmp/        # ta version du script
admin@adm01:~$ ssh runner01 "sudo EMPREINTE_HASHICORP='<EMPREINTE>' IP_PVE01=<IP-PVE01> bash /tmp/installer-packer-runner01.sh"
runner01 prêt : Packer v1.16.1, autorité de pve01 approuvée, API joignable
```

`<EMPREINTE>` : celle relevée sur la page officielle de HashiCorp (comme en E02), jamais copiée d'un fichier du dépôt. Le plugin s'installe au premier `packer init` d'un job, dans `~gitlab-runner/.config/packer/plugins/` ; les jobs suivants le réutilisent (`packer plugins installed` sous `gitlab-runner`).

*2. Les flux.* Trois règles sur `gw01` (fichier d'extrait), puis sur `pve01` :

```
root@pve01:~# pvesh create /cluster/firewall/ipset --name automation --comment "Machines d'automatisation (runner01)"
root@pve01:~# pvesh create /cluster/firewall/ipset/automation --cidr 10.10.20.15 --comment runner01
root@pve01:~# cat /etc/pve/firewall/cluster.fw     # relire avant d'activer
root@pve01:~# pvesh create /cluster/firewall/rules --type in --action ACCEPT --source +automation --proto tcp --dport 8006 --enable 1 --comment "API pour runner01 (M03-E15)"
root@pve01:~# pve-firewall compile | grep -n automation
```

L'IPSet porte le nom `automation` imposé par PLAN.md §4.8 ; s'il existait déjà, on n'y ajoute que l'entrée. Test depuis `runner01` : `curl -s -o /dev/null -w '%{http_code}\n' https://<IP-PVE01>:8006/api2/json/version` → `401` (TLS vérifié, pas de jeton). Depuis `runner01`, `ssh` vers une VM de `vsandbox` ; depuis une VM de `vsandbox`, `curl http://10.10.20.15:8100/` (refus de connexion **après** routage : `Connection refused`, pas un délai dépassé, tant qu'aucun Packer n'écoute). Matrice des flux : trois lignes (source, destination, port, motif, exercice).

*3. Les secrets.* Quatre variables de projet (*Settings → CI/CD → Variables*) : `PKR_VAR_proxmox_url` (`https://<IP-PVE01>:8006/api2/json`), `PKR_VAR_proxmox_username` (`wb-packer@pve!packer`), `PKR_VAR_proxmox_node`, protégées ; `PKR_VAR_proxmox_token` protégée, masquée et cachée (*Masked and hidden*, GitLab ≥ 17.4 : la valeur n'est plus relisible dans l'interface). Un pipeline de MR part d'une branche non protégée : GitLab n'y injecte pas les variables protégées. C'est voulu : sinon, n'importe quel développeur qui ouvre une MR pourrait modifier `.gitlab-ci.yml` pour afficher (ou utiliser) le jeton. Le job `packer-validate` déclare des valeurs **factices** de la bonne forme (les blocs `validation` les acceptent) ; sur `main`, les variables du projet ont priorité sur celles du fichier.

*4. Le pipeline.* Points clés du fichier :

| Besoin | Mécanisme |
|---|---|
| hooks Packer en CI | dette de E02 soldée : `SKIP: gitleaks` seulement |
| validation sans secret | `packer-validate`, valeurs factices, MR et `main` |
| construction planifiée ou manuelle | `rules` : `schedule` sur `main` → automatique ; `main` hors MR → `when: manual` + `allow_failure: true` |
| images de base | jobs `build-base:*`, manuels seulement, jamais planifiés |
| VMID transmis | `outils/version-image.sh` avant le build, `build.env` en `artifacts:reports:dotenv` → `$IMAGE_VMID` dans `test:*` et `publish:*` (`needs`) |
| un seul build à la fois | `resource_group: packer-pve01` sur tous les jobs de build |
| build jamais interrompu | `interruptible: false` |
| rapport de test | `tests/tester-image.sh --junit …`, `artifacts:reports:junit` |
| image rejetée identifiable | `rejeter:*` (`when: on_failure` dans la règle) : étiquette `rejete` |
| publication | `outils/publier-image.sh` (rejoue le test : la règle « pas de `current` sans test » ne dépend pas de la CI), puis rotation (E16) ; `resource_group: publication-images` |
| HTTP de Packer sur le runner | `PKR_VAR_http_bind_address: "10.10.20.15"` |
| traçabilité | artefacts `manifests/` (journal, manifeste JSON, paquets) conservés 90 jours |

`when:` se met **dans la règle**, pas au niveau du job : un `when` de job sert de valeur par défaut à toutes les règles qui n'en définissent pas (les anciennes versions de GitLab refusaient carrément la combinaison). Avec `when: manual` au niveau du job, la règle `schedule` deviendrait manuelle elle aussi : plus aucun build hebdomadaire. La rotation n'existe pas encore au début de E15 : commente la ligne jusqu'à E16, ou fais E16 juste après.

*5. La planification.* *Build → Pipeline schedules → New schedule* : description « Images dorées hebdomadaires », intervalle personnalisé `40 5 * * 1` (lundi 5 h 40), fuseau *Europe/Paris*, branche `main`. Le pipeline tourne **avec les droits du propriétaire** de la planification : il doit pouvoir fusionner sur `main` (branche protégée), et s'il quitte le projet ou est bloqué, la planification devient inactive. Propriétaire recommandé : un compte de service de l'équipe (ou au minimum le référent, avec la reprise de propriété — *Take ownership* — décrite dans RB-031).

*6. La preuve.* Pendant un build manuel, un second pipeline de `main` lancé à la main montre son job de build en état « *Waiting for resource: packer-pve01* », puis il démarre quand le premier se termine.

**Explications**

Le pipeline transforme une procédure en système : l'image se reconstruit sans mémoire humaine, chaque version porte la trace de son commit, de ses outils et de son test, et rien de dangereux ne peut s'exécuter en parallèle. Le partage des responsabilités est net : la CI orchestre, les scripts du projet (`construire.sh`, `tester-image.sh`, `publier-image.sh`, `rotation-images.sh`) font le travail et portent les garde-fous, à l'identique sur un poste et sur le runner. C'est ce qui permet de construire à la main depuis `adm01` si le runner est en panne, sans contourner les règles.

**Alternatives**
- **Un job unique** « build-test-publish » : plus simple, mais un échec de test laisse un template sans trace dans l'interface CI et sans rapport séparé.
- **Pipeline enfant** par famille (`trigger: include:`) : utile au-delà de deux familles.
- **Runner dédié** (étiquette `packer`) sur une VM du VLAN MGMT : évite d'ouvrir INFRA → `pve01`, au prix d'un hôte de plus ; à considérer si d'autres jobs non fiables partagent `runner01`.
- **Déclenchement sur nouvelle ISO** (veille des `SHA256SUMS` de Debian) au lieu d'un build manuel des bases.

**Pièges classiques**
- Mettre le jeton en variable non protégée « pour que la validation marche en MR ».
- Oublier `http_bind_address` : Packer écoute sur `runner01` mais annonce l'adresse de `adm01` à l'installeur.
- Ouvrir 8006 dans le pare-feu Proxmox au niveau du centre de données avec une source trop large, ou activer une règle sans l'avoir relue (`pve-firewall compile`).
- `resource_group` sur le job de test seulement : deux builds tournent quand même en parallèle.
- Un build interruptible : un push sur `main` annule le build planifié au milieu, la VM de build reste.
- Une planification au nom d'une personne qui part : plus aucune image, sans alerte.

**En production chez MédiSphère**
La chaîne d'images est un service : son pipeline planifié est supervisé (alerte si aucun succès depuis 8 jours, module 21), ses artefacts sont conservés selon la politique d'archivage d'audit, son jeton est émis par Vault avec une durée courte (module 25), et le runner qui construit est dédié, durci, et n'exécute que les projets de la plateforme.

---

### M03-E16 — Cycle de vie : rotation et retrait des images

**Solution**

Fichiers : [`fichiers/M03-E16/images/outils/rotation-images.sh`](fichiers/M03-E16/images/outils/rotation-images.sh), [`fichiers/M03-E16/docs/socle/runbooks/RB-030-retrait-image.md`](fichiers/M03-E16/docs/socle/runbooks/RB-030-retrait-image.md).

*1. Où est le lien ?* Sur un stockage **LVM-thin** (cas le plus courant pour `local-nvme`) :

```
root@pve01:~# qm config 2033 | grep ^scsi0
scsi0: local-nvme:vm-2033-disk-0,iothread=1,size=8G
root@pve01:~# lvs -o lv_name,origin,pool_lv | grep -E 'base-9010|vm-2033'
  base-9010-disk-0                     data
  vm-2033-disk-0    base-9010-disk-0   data
```

Le volume du clone s'appelle simplement `vm-2033-disk-0` : le lien n'existe que dans les métadonnées LVM (colonne `origin`), invisible pour l'API (ni la configuration, ni `GET …/storage/local-nvme/content` ne le montrent). Sur **ZFS** (ou un stockage fichier qcow2, ou Ceph RBD), le volume s'écrit `local-nvme:base-9010-disk-0/vm-2033-disk-0` dans la configuration du clone, et le contenu du stockage expose un champ `parent` : l'API suffit. Le code de `pve-storage` le confirme : `clone_image` du plugin LVM-thin renvoie `vm-<ID>-disk-N` (instantané thin `lvcreate -s`), celui de ZFS `base-…/vm-…`. Conséquence observée dans `PVE::Storage::vdisk_free` : Proxmox refuse de supprimer un volume de base « still in use by linked clones » quand il le détecte (ZFS, fichiers), mais **pas** sur LVM-thin, où l'instantané thin survit à la suppression de son origine (« LVM-thin allows deletion of still referenced base volumes », commentaire du code).

*2-3. L'outil.* Rotation par famille : tri par `[date, numéro]` (numéro en nombre), conservation de `current`, des 3 plus récentes non rejetées et de la plus récente rejetée ; suppression par `DELETE /nodes/<NOEUD>/qemu/<VMID>?purge=1&destroy-unreferenced-disks=1` et attente de la tâche. Détection des clones liés : (1) toujours, les configurations de toutes les VMs visibles, à la recherche de `:base-<VMID>-…/…` ; (2) sur LVM-thin, avec `--ssh-pve pve01` (depuis `adm01`), `lvs -o lv_name,origin` en root ; sans cet accès (CI), un **avertissement** explique que les clones liés sont indétectables par l'API mais qu'ils survivraient (instantanés indépendants). Ce choix repose sur une règle de consommation : les VMs durables sont des clones **complets** (ADR-0030) ; les clones liés ne vivent que le temps d'un test. Une équipe qui préfère la prudence absolue fera refuser l'outil sur LVM-thin sans `--ssh-pve` : la rotation ne tournera alors qu'à la main. Les deux choix se défendent ; l'important est qu'il soit écrit.

*4. Les essais.*

```
admin@adm01:~/src/images$ outils/rotation-images.sh --retirer 9010
== SIMULATION : retrait de 9010
  avertissement : local-nvme est en LVM-thin, les clones liés de 9010 n'y sont pas visibles par l'API
  (ils survivraient à la suppression : instantanés thin indépendants ; --ssh-pve pour vérifier)
  [simulation] suppression de 9010 (deb13-gold-20261007-1)
== terminé (SIMULATION)
admin@adm01:~/src/images$ outils/rotation-images.sh --retirer 9010 --ssh-pve pve01
  REFUS 9010 (deb13-gold-20261007-1) : clones liés détectés : 2033
== 1 refus : voir ci-dessus (rien n'a été supprimé pour ces versions)
admin@adm01:~/src/images$ outils/rotation-images.sh --retirer <VMID-CURRENT>
  REFUS 9013 (deb13-gold-20261014-1) : version current — publie d'abord une autre version (outils/publier-image.sh)
```

Sur ZFS, le premier appel refuse déjà, sans `--ssh-pve`. Puis `qm destroy 2033 --purge`, et `outils/rotation-images.sh --famille debian13 --appliquer`.

*5. En CI.* Ligne `outils/rotation-images.sh --famille "$FAMILLE" --appliquer` dans `.publish` (fichier de E15). Un refus (code 3) fait échouer le job de publication **après** la publication : c'est le signal qu'il faut lire RB-030, pas un échec de l'image.

*6. Le runbook.* RB-030 (fichier de référence) : règles, rotation en échec, retrait d'urgence (republier d'abord la version précédente, qui est retestée), communication, VMs créées depuis l'image retirée, et l'explication LVM-thin.

**Explications**

Une politique de rétention répond à trois besoins contradictoires : libérer de la place, permettre le **retour arrière** (garder des versions récentes testées), et ne jamais casser ce qui dépend d'une image. `current` est protégée par construction ; le retour arrière est possible sur trois versions ; la dépendance (clone lié) est le seul cas dangereux, et sa détectabilité dépend du stockage : c'est une limite de la plateforme qu'un outil sérieux **dit** plutôt qu'il ne la cache.

**Alternatives**
- **Rétention par âge** (30 jours) plutôt que par nombre : simple, mais une famille qui ne se construit plus (CI en panne) perdrait toutes ses versions.
- **Archivage** des versions retirées en sauvegarde PBS (`vzdump` du template) avant suppression : permet un retour très en arrière ; à prévoir si un éditeur certifie une version précise.
- **Marquage de provenance** des VMs (étiquette `img-<version>` posée par OpenTofu au clonage) : rend la question « qui utilise cette image ? » répondable par l'API, quel que soit le stockage (piste pour M05).

**Pièges classiques**
- Trier les versions comme des chaînes (`-10` avant `-2`).
- Supprimer `current` « parce que c'est la plus vieille » après un retour arrière.
- Croire l'API sur LVM-thin : aucune trace ne veut pas dire aucun clone.
- Un outil destructeur sans mode simulation par défaut, ou qui continue après un refus et renvoie 0.
- Supprimer les templates à la main dans l'interface « pour aller vite » : aucun garde-fou, aucune trace.

**En production chez MédiSphère**
La rotation tourne après chaque publication et signale ses refus ; un contrôle hebdomadaire compare la liste des templates aux VMs qui en sont issues (étiquettes de provenance, module 05) ; le retrait d'urgence est une procédure d'astreinte testée deux fois par an, avec communication aux équipes et suivi des VMs à reconstruire.

---

### M03-E17 — ADR : stratégie d'images de MédiSphère

**Solution**

Exemple complet : [`fichiers/M03-E17/ADR-0030-strategie-images.md`](fichiers/M03-E17/ADR-0030-strategie-images.md). Ce n'est pas « la » bonne réponse : une autre décision bien argumentée est acceptable.

**Grille d'auto-évaluation** (sur 20 ; seuil : 14, sans critère éliminatoire)

*Éliminatoire* : une identité ou un secret admis dans l'image ; aucune option écartée argumentée ; aucune conséquence négative.

| Critère | Points | Attendu |
|---|---|---|
| Contexte | 2 | le problème (preuve, Rocky, consommateurs) et pourquoi décider maintenant |
| Facteurs de décision | 3 | mesurables ou vérifiables (délai de correctif, temps de mise à disposition, coût, preuve, dérive) |
| Options | 4 | au moins trois, dont image par rôle et image du fournisseur ; avantages **et** inconvénients de chacune |
| Décision | 5 | contenu / jamais dans l'image ; familles et règle d'ajout ; rythme base et dorée ; version et publication ; consommation (étiquettes, clone complet, VMs existantes) ; rétention et retrait ; outil et licence |
| Conséquences et risques | 4 | négatives nommées (délai d'une semaine, deux mécanismes, sérialisation, BUSL) ; risques avec traitement (LVM-thin, dérive, runner, pool `lab` unique pour le jeton) |
| Forme | 2 | format des ADR précédents, liens vers les livrables, relecteurs nommés |

**Explications**

La difficulté d'un ADR d'images n'est pas le choix de l'option 3 (presque toutes les organisations y arrivent) : c'est d'en écrire les **règles de consommation**. Ce sont elles que les modules 04 et 05 appliqueront (sélection par étiquettes au moment de la création, clone complet pour le durable, une VM existante n'est jamais « mise à jour par l'image »), et ce sont elles qui rendent la rotation sûre. Un ADR qui ne parle que de Packer est un mode d'emploi, pas une décision.

**Pièges classiques**
- Comparer des options sans critères (« plus moderne », « plus simple »).
- Oublier les VMs **existantes** : l'image ne les met pas à jour, il faut dire qui le fait.
- Taire la licence de Packer, ou en faire un critère éliminatoire sans lire ce qu'elle interdit.

**En production chez MédiSphère**
L'ADR est relu par la RSSI (contenu, preuve) et par les équipes consommatrices (contrat) ; il est cité par les ADR du module 05 (OpenTofu) et revu à chaque nouvelle famille d'OS ou à chaque changement d'outil.

---

### M03-E18 — Questions de production : images et chaîne de confiance

**1.** Chaîne Debian : clé OpenPGP de signature des images Debian (publiée sur `debian.org`, empreinte vérifiable par plusieurs canaux) → signature `SHA512SUMS.sign` (ou `SHA256SUMS.sign`) → fichier de sommes → somme de l'ISO téléchargée → ISO sur `hdd-bulk` (vérifiée par `deposer-iso.sh`, E05). Le **miroir compromis** est arrêté par la signature : il peut changer l'ISO et le fichier de sommes, pas produire une signature valide. Un attaquant qui contrôle **aussi** le site où tu as lu l'empreinte de la clé gagne si tu n'as vérifié l'empreinte que là : la parade est de la recouper par un autre canal (page <https://www.debian.org/CD/verify> consultée depuis un autre réseau, toile de confiance OpenPGP, empreinte déjà vérifiée lors d'un build précédent) et de la **figer** dans le dépôt une fois vérifiée. Intégrité (somme) et authenticité (signature) ne sont pas la même propriété.

**2. Réponse b.** La contrainte `~> 1.2.4` autorise 1.2.4 ≤ v < 1.3.0 ; `packer init` installe la plus récente disponible dans cette plage et contrôle l'archive avec la somme SHA256 publiée avec la version. a) Faux : `~>` n'est pas une égalité (il faudrait `= 1.2.4`) ; c) faux : `~> 1.2.4` borne la mineure (ce serait `~> 1.2`) ; d) faux : la somme est vérifiée. Ce n'est pas une **signature** de l'éditeur : d'où l'intérêt de figer la version exacte et de la tracer dans le manifeste.

**3.** Figer la version rend le build **reproductible** et explicable (une même révision du code donne le même outillage) et évite qu'un plugin publié la veille change le comportement d'un build planifié la nuit. Contrepartie : on ne reçoit plus les correctifs tout seuls. Compensation : une mise à jour **délibérée** par MR (Renovate, module 13, ou une revue mensuelle), testée par le pipeline ; la version effectivement utilisée est relevée par `construire.sh` et inscrite dans les notes et le manifeste.

**4.** (1) Le *user-data* de construction (compte `packer`, clé publique, sudo) et ses traces (`/var/lib/cloud`, `/var/log/cloud-init*.log`, `/etc/sudoers.d/90-cloud-init-users`) ; (2) l'historique du shell et les journaux (`/root/.bash_history`, `journalctl`, `/var/log/installer`, `/root/anaconda-ks.cfg` qui contient le *kickstart* et parfois un mot de passe chiffré) ; (3) les clés d'hôte SSH et le `machine-id` (identités) ; (4) les caches et listes de paquets (`/var/cache/apt`, sources avec identifiants d'un dépôt privé) ; (5) les fichiers temporaires des provisioners (`/tmp/fichiers`, scripts avec variables d'environnement), et les variables passées par `environment_vars` si un script les écrit. La préparation au clonage (E07) et le test (E14) existent pour ça.

**5.** Oui : `/run/cloud-init/instance-data-sensitive.json` (lisible par root seulement) contient le *user-data* ; `instance-data.json` (lisible par tous) en masque les clés sensibles connues ; le journal peut contenir des extraits selon le niveau de détail. Un `cipassword` serait lisible dans le *user-data* (Proxmox l'y écrit, éventuellement haché) **et** dans le lecteur `cidata`, que tout utilisateur pouvant monter un CD dans la VM lit, et dans `/var/lib/cloud/instance/user-data.txt`. Règle : aucun secret par cloud-init sans chiffrement ni durée de vie courte ; les comptes s'authentifient par clé ; les secrets applicatifs viennent d'un coffre (module 25).

**6. Réponse b.** `systemd-networkd` dérive le DUID (identifiant de client DHCP) du `machine-id` ; dnsmasq identifie le client par cet identifiant et lui rend le même bail, malgré des MAC différentes. a) Faux : c'est justement l'effet le plus visible. c) Faux : rien n'empêche le démarrage. d) Faux : cloud-init régénère les clés d'hôte pour une nouvelle instance, pas le `machine-id` (c'est le rôle de `cloud-init clean --machine-id` **avant** la conversion).

**7.** (1) Les **VMs neuves** : une image vieille de trois mois démarre avec trois mois de correctifs à appliquer, pendant lesquels elle est exposée, et qui allongent le premier démarrage ; (2) `unattended-upgrades` ne fait que la **sécurité** et n'applique pas tout (paquets retenus, redémarrage nécessaire pour un noyau) ; (3) la reconstruction **teste** régulièrement toute la chaîne (ISO, dépôts, scripts) : une chaîne qui ne tourne qu'une fois par an est cassée le jour où on en a besoin.

**8.** L'état doit garder le **VMID ou le nom** du template effectivement cloné (`deb13-gold-…`) et la date. `current` est un pointeur mobile : mercredi il désigne une autre version ; si OpenTofu relit la sélection à chaque plan, il proposera de **recréer** la VM de mardi. On sépare donc la sélection (au moment de la création) de la référence (enregistrée), et on ignore la source de clonage dans les changements ultérieurs (module 05).

**9. Réponse b.** `resource_group` sérialise les jobs du même groupe, tous pipelines confondus : le second job attend (« Waiting for resource ») puis s'exécute. a) Faux : il n'échoue pas. c) Faux : `resource_group` s'applique à n'importe quel job, environnement ou non. d) Faux : c'est `interruptible` avec l'annulation automatique des pipelines redondants qui annule, et seulement sur une même branche, pour un job interruptible.

**10.** Les variables protégées ne sont injectées que dans les pipelines de branches (ou étiquettes) protégées. Une MR vient d'une branche non protégée, éventuellement d'un contributeur sans droit de fusion : s'il recevait le jeton, il lui suffirait de modifier `.gitlab-ci.yml` dans sa MR pour l'afficher, l'exfiltrer ou s'en servir. Avec `wb-packer` (rôle `WBPacker` sur `/pool/lab`), il pourrait créer, modifier, arrêter ou **détruire n'importe quelle VM du pool `lab`**, socle compris, et lire leur configuration.

**11.** Supprimer `gw01` : **oui**, et c'est le point à retenir : `gw01` est dans le pool `lab`, et `WBPacker` porte `VM.Allocate` sur `/pool/lab` (pour `-force` et la conversion en template). Lire `pbs-par2` : **non**, le jeton n'a de droits que sur `/storage/local-nvme` (`PVEDatastoreUser`) et `/storage/hdd-bulk` (lecture). Démarrer une VM du socle branchée sur `vinfra` : **oui** (`VM.PowerMgmt` sur le pool ; le démarrage ne vérifie pas `SDN.Use`) ; **changer** la carte d'une VM vers `vinfra` : non, il faut `SDN.Use` sur ce VNet. Améliorations : un pool dédié aux templates et aux VMs de build (`images`), distinct de celui du socle, avec `WBPacker` sur ce seul pool ; c'est une évolution à proposer (PLAN.md fixe aujourd'hui le pool unique `lab`).

**12.** Les notes prouvent ce que le **build** a déclaré (commit, versions, date, test) ; elles ne prouvent pas que personne ne les a modifiées : quiconque a `VM.Config.Options` sur le template (dont le jeton `wb-packer`) peut les réécrire. Pour un manifeste infalsifiable par l'équipe : le **signer** dans la CI avec une clé que l'équipe ne détient pas (clé du runner dans un coffre, ou signature sans clé type Sigstore, module 13), conserver le manifeste et sa signature hors de Proxmox (artefact CI, stockage objet à rétention verrouillée), et faire vérifier la signature par les consommateurs.

**13.** Oui : la BUSL 1.1 de HashiCorp autorise l'usage en production, y compris commercial, **sauf** pour proposer un produit concurrent des offres de HashiCorp. Construire ses propres images en interne est permis. Proposer à des clients un service de construction d'images basé sur Packer pourrait être considéré comme concurrent : à faire valider juridiquement. Risque à long terme : changement de conditions, évolution du plugin Proxmox (communautaire) ; repli : `virt-builder`, `mkosi`, `diskimage-builder`, ou scripts autour de l'API Proxmox et de `virt-customize`, plus coûteux à maintenir (ADR-0030, option 4).

**14.** À la mise en service : la version de l'image (`rocky10-gold-AAAAMMJJ-N`) enregistrée avec la VM, son manifeste (liste des paquets et versions, date), le rapport de test du pipeline, et sur la VM `dnf updateinfo list --security` vide (ou la liste des avis appliqués) à la date. Ensuite : `dnf-automatic` en mode sécurité, journalisé ; un contrôle périodique (`dnf check-update --security`, OpenSCAP, module 26) dont le résultat est conservé ; la reconstruction des VMs depuis une image récente selon une fréquence convenue avec l'éditeur.

**Grille d'auto-évaluation** : 1 point par question (QCM : bonne réponse et justification des fausses), 14 au total. Moins de 10 : relis l'introduction (concepts), E02, E05, E10 et E15 ; les questions 4, 10 et 11 sont celles que l'auditeur posera en premier.
