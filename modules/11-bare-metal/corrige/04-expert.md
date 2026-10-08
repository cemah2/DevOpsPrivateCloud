# Module 11 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. Dans une chaîne de démarrage réseau, « j'ai relancé le rendu et ça remarche » est le piège principal : le rendu réécrit ce que sert `pxe01` et efface la preuve, sans dire pourquoi le fichier servi avait changé.

Les scripts d'injection sont dans `corrige/pannes/` (`_m11-commun.sh` : modifications de texte mémorisées et réversibles sans écraser une réparation, empreintes des fichiers posés, sonde TFTP, appel signé de l'API de MAAS). Chaque modification est journalisée sur l'hôte touché dans `/var/lib/workbook/pannes.log` (copies d'origine dans `/var/lib/workbook/M11-EXX.*`), et sur `adm01` dans `~/.local/state/workbook/M11-EXX/`.

Les sorties reproduites sont **représentatives** : messages des ROM PXE, codes iPXE et libellés des installateurs varient selon les versions.

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) :
- message exact de la ROM PXE de QEMU (iPXE intégré à SeaBIOS) et d'OVMF pour une offre sans fichier ou un TFTP muet (E19) ;
- codes d'erreur iPXE exacts pour un script à l'en-tête invalide, un 403 et un certificat d'une autre autorité (E20) ;
- écran exact d'Anaconda (Rocky 10) pour une source d'installation introuvable et un disque `ignoredisk` absent (E21) ;
- noms des paramètres d'alimentation du pilote Proxmox de MAAS 3.7 (`power_vm_name` ou équivalent, `power_verify_ssl`) et magasin de certificats réellement utilisé par le snap pour *verify SSL* (E22 : la variante 4 n'est retenue que si elle a un effet constaté) ;
- emplacement des journaux du snap MAAS 3.7 (`journalctl -u snap.maas.pebble`, `/var/snap/maas/common/log/`).

---

## Méthode commune aux pannes de provisioning

1. **Situer l'étage à la console.** Le dernier message lisible dit où l'on est : micrologiciel (DHCP de la ROM), TFTP, iPXE (DHCP d'iPXE, HTTPS, script), noyau, installateur. Note-le mot pour mot.
2. **Chercher le témoin de l'étage chez son serveur.** Kea (journal, baux), `tftpd-hpa` (journal en `--verbose`), nginx (`pxe-access.log`, `pxe-error.log`), installateur (consoles secondaires). Aucune trace = l'étape n'a pas eu lieu.
3. **Capturer quand les journaux ne suffisent pas.** Sur `pve01`, `tcpdump -ni tapNNNNi0` voit tout ce qu'émet et reçoit la VM, sans rien changer.
4. **Comparer le servi au rendu.** `diff` entre le fichier servi par `pxe01` (`curl` depuis `adm01`) et le rendu du code (`netbox-provision.py rendre` dans un dossier temporaire) ; `--check --diff` du rôle Ansible concerné. Un écart **est** souvent la panne ; il faut ensuite trouver **qui** l'a introduit.
5. **Corriger à la source, puis faire converger.** Une correction à chaud est permise pour rétablir le service ; le second passage du code doit donner `changed=0`.
6. **Prévenir** : quelle validation du pipeline, quelle sonde aurait vu la panne avant l'arrivée d'une palette ?

---

### M11-E19 — Panne : le serveur ne démarre pas sur le réseau

**Démarche de diagnostic**

*Symptôme* (selon le ticket) : un serveur reste au stade de la ROM PXE ; selon la variante, sans adresse, avec une adresse mais sans fichier, ou avec un fichier qu'il ne peut pas télécharger.

*Hypothèses* : DHCP qui ne répond pas (Kea, relais, filtrage) ; offre incomplète (classe, option, serveur suivant) ; serveur TFTP absent ou qui refuse (service, chemin, droits).

**Étape 1 — Ce que voit la machine.** Console de `bm01` et `bm03` : comparer BIOS et UEFI est la mesure la plus rentable (une différence pointe vers les classes de Kea).

**Étape 2 — Ce qui passe sur le fil**, sur `pve01`, pendant un démarrage :

```
root@pve01:~# timeout 120 tcpdump -ni tap2112i0 -vv 'port 67 or port 68 or port 69'
```

**Étape 3 — Les serveurs** : `journalctl -u isc-kea-dhcp4-server --since -10min` sur `dns01` ; `journalctl -u tftpd-hpa --since -10min` sur `pxe01` ; `journalctl -u dnsmasq` sur la passerelle maître.

**Variante 1 — serveur suivant faux.** La capture montre DISCOVER, OFFER, REQUEST, ACK : l'OFFER contient `file "undionly.kpxe"` mais `server-ip 10.10.60.12` (champ `siaddr`), puis des RRQ TFTP vers 10.10.60.12 sans réponse. Aucune ligne dans le journal de `tftpd-hpa`. Confirmation :

```
admin@dns01:~$ sudo grep -n '"next-server"' /etc/kea/kea-dhcp4.conf
```

Puis la configuration **chargée** par la commande `config-get` de l'API de Kea (M06-E17, en HTTPS depuis M06-E25) : le fichier et la mémoire peuvent différer si Kea n'a pas été relancé.

Cause : `next-server` du sous-réseau 60 modifié sur `dns01` **et** `dns02` (fichier rendu par Ansible, modifié à la main). Correctif : `ansible-playbook playbooks/dns01.yml --limit role_dns --check --diff` montre l'écart ; on rejoue le rôle `kea_dhcp4` (qui teste la configuration et redémarre Kea). Si la valeur fausse est **dans** le code, c'est une MR. Prévention : sonde qui vérifie `siaddr` dans une offre réelle (`perfdhcp` ou capture planifiée), détection de dérive du rôle.

**Variante 2 — classe BIOS fausse.** BIOS : « No boot filename received » ; UEFI : normal. La capture de `bm01` montre une OFFER **sans** champ `file` ; celle de `bm03`, `file "ipxe.efi"`. Le DISCOVER de `bm01` porte l'option 93 = 0 (`Client-System-Arch Option 93, length 2: 0`). Dans la configuration : `option[93].hex == 0x0006` (IA32 EFI, que plus personne n'utilise) au lieu de `0x0000`. Journal de Kea en `DEBUG` (temporairement) : aucune classe BIOS évaluée vraie pour ce client. Correctif et prévention : comme la variante 1 ; plus un test Molecule du rôle qui vérifie la présence des trois codes d'architecture attendus.

**Variante 3 — chargeurs illisibles.** Offre complète, RRQ vers 10.10.60.10, réponse TFTP **ERROR** (`Access violation` ou `Permission denied` selon le client). Journal de `tftpd-hpa` : `RRQ from 10.10.60.1xx filename undionly.kpxe` suivi d'un refus. Sur `pxe01` :

```
admin@pxe01:~$ ls -l /srv/tftp/
-rw------- 1 root root  … ipxe.efi
-rw------- 1 root root  … undionly.kpxe
```

`tftpd-hpa` lâche ses droits pour le compte `tftp` : il ne lit que les fichiers lisibles par tous. Correctif : rejouer le rôle `pxe` (mode `0644` déclaré dans la tâche de copie, empreinte vérifiée). Prévention : la tâche de copie fixe toujours `mode`, et la sonde TFTP de RB-111 lit les deux chargeurs.

**Variante 4 — relais du VLAN 60 retiré.** Plus aucune OFFER : la capture sur `tap2112i0` ne montre que des DISCOVER répétés ; rien n'arrive sur `ens18` de `dns01` (capture `port 67`). Sur la passerelle maître (celle qui porte la VIP 10.10.60.1) :

```
admin@gw01:~$ sudo grep -n 'dhcp-relay' /etc/dnsmasq.d/*.conf
3:# dhcp-relay=10.10.60.2,10.10.20.10
4:# dhcp-relay=10.10.60.2,10.10.20.16
5:dhcp-relay=10.10.99.2,10.10.20.10
```

Les lignes du VLAN 60 sont commentées sur **les deux** passerelles (« ménage » de fin de MAAS) ; le VLAN 99 marche encore. Correctif : rejouer le rôle `relais_dhcp` sur `gw01` et `gw02` (la variable qui liste les VLAN relayés contient le 60). Prévention : le relais est une donnée du code, jamais une modification à la main ; la fiche de changement de M11-E10 (retour à Kea) doit lister le relais dans sa vérification de fin.

**Vérification** : `bm01` et `bm03` arrivent au script iPXE ; `lab/bin/check 11 19` ; `lab/bin/check 06 36` (VLAN 99) ; puis `lab/bin/break 11 19 --annuler`.

**Explications**

La ROM PXE suit un automate simple (RFC 2131, spécification PXE 2.1) : DHCP avec option 60 `PXEClient` et option 93, puis téléchargement TFTP du fichier `file` depuis `siaddr` (ou l'option 66). Chaque message d'erreur correspond à une étape : pas d'offre, offre sans fichier, serveur muet, serveur qui refuse. Le relais transforme un broadcast en unicast : une panne de relais est invisible côté serveur.

**Alternatives** : `proxyDHCP` (un second serveur qui ne donne que les informations PXE, sans adresse : `dnsmasq --dhcp-range=…,proxy`) — utile quand on ne maîtrise pas le DHCP principal, inutile ici.

**Pièges classiques**
- Redémarrer Kea « pour voir » avec une configuration fausse : il refuse de démarrer, et c'est **tout** le DHCP du lab qui tombe. Toujours `kea-dhcp4 -t` d'abord.
- Corriger seulement `dns01` : `dns02` (en attente) servira la mauvaise valeur le jour où il prendra la main.
- Confondre « la VM n'a pas d'adresse » (DHCP) et « la VM a une adresse mais ne charge rien » (TFTP).

**En production chez MédiSphère**
Sonde PXE de bout en bout (VM de test sur le VLAN de provisioning qui démarre jusqu'au script iPXE toutes les heures), alerte sur l'écart entre configuration servie et code.

---

### M11-E20 — Panne : iPXE s'arrête en chemin

**Démarche de diagnostic**

*Symptôme* : iPXE est chargé, obtient une adresse, puis échoue avec un code `https://ipxe.org/…` avant le noyau.

*Hypothèses* : script invalide (en-tête, syntaxe) ; ressource introuvable ou interdite (404, 403) ; TLS refusé (chaîne, nom, date, racine) ; DNS.

**Étape 1 — Décoder le code** : `https://ipxe.org/err/<code>` dit le module émetteur (format d'image, HTTP, X.509).

**Étape 2 — Rejouer dans le shell iPXE** (Ctrl-B) :

```
iPXE> dhcp
iPXE> imgfetch https://pxe01.par1.medisphere.internal/boot.ipxe
iPXE> imgstat
iPXE> imgfetch https://pxe01.par1.medisphere.internal/ipxe/mac-${mac:hexhyp}.ipxe
```

**Étape 3 — Comparer avec `adm01` et lire nginx** :

```
admin@adm01:~$ curl -sS -v https://pxe01.par1.medisphere.internal/boot.ipxe 2>&1 | grep -E 'issuer|HTTP/|^#!'
admin@pxe01:~$ sudo tail -n 20 /var/log/nginx/pxe-access.log /var/log/nginx/pxe-error.log
```

**Variante 1 — en-tête du script.** `imgfetch` réussit, `imgstat` montre `boot.ipxe : 789 bytes` **sans** `[script]` ; `chain` répond « Exec format error ». La première ligne servie est `#! ipxe` : iPXE ne reconnaît un script qu'à la chaîne exacte `#!ipxe` en tête de fichier. `diff` avec `ipxe/boot.ipxe` du dépôt : la ligne modifiée à la main sur `pxe01`. Correctif : redéployer depuis le code (job `deployer`) ; chercher qui a modifié le fichier (`stat`, journal d'audit, `last`). Prévention : `outils/verifier-rendu.sh` dans le pipeline, et une sonde qui compare les empreintes servies et rendues.

**Variante 2 — scripts par MAC interdits.** `boot.ipxe` passe (ligne de bienvenue avec la MAC), puis « Permission denied » sur `mac-….ipxe`. `pxe-access.log` : `GET /ipxe/mac-bc-24-11-…ipxe HTTP/1.1" 403` ; `pxe-error.log` : `open() "/srv/http/ipxe/mac-….ipxe" failed (13: Permission denied)`. Les fichiers sont en `0600 root:root` : nginx (`www-data`) ne peut pas les lire. Cause : rendu déposé avec un umask restrictif. Correctif : redéployer avec des droits explicites (`mode: "0644"` dans la tâche de dépôt). Prévention : la tâche de dépôt fixe toujours le mode ; la sonde lit un script par MAC.

**Variante 3 — certificat d'une autre autorité.** « Permission denied » dès `boot.ipxe`, aucune ligne dans `pxe-access.log` (la poignée de main TLS échoue avant la requête HTTP). Depuis `adm01` :

```
admin@adm01:~$ openssl s_client -connect 10.10.60.10:443 -servername pxe01.par1.medisphere.internal -showcerts </dev/null 2>/dev/null \
  | grep -E '^ *[0-9] s:|^ *i:|Verify return code'
 0 s:CN = pxe01.par1.medisphere.internal
   i:O = MédiSphère, CN = MédiSphère CA provisoire
Verify return code: 20 (unable to get local issuer certificate)
```

Le navigateur du collègue a accepté **après un avertissement** : il a court-circuité la vérification que fait iPXE. Le fichier pointé par `ssl_certificate` a été remplacé (dates, `stat`) par une « restauration de configuration ». Correctif : réémettre par la voie normale (rôle `certificats_acme` : il détecte un certificat qui ne se vérifie plus contre la racine et le remplace), `nginx -t && systemctl reload nginx`. Prévention : la restauration d'une configuration n'inclut jamais un certificat ; sonde d'émetteur et d'expiration (M06-E29) étendue à `pxe01`.

**Vérification** : `bm01` et `bm03` atteignent le noyau de l'installateur ; `lab/bin/check 11 20` ; `lab/bin/break 11 20 --annuler`.

**Explications**

iPXE télécharge d'abord, interprète ensuite : un téléchargement réussi suivi d'un « Exec format error » n'est **pas** un problème réseau. Pour TLS, iPXE n'a que les racines compilées (M11-E13) : il ne demande jamais à l'utilisateur d'accepter un certificat, ce qui est exactement ce qu'on attend d'une chaîne de démarrage.

**Alternatives** : activer la journalisation de débogage d'iPXE (construction avec `DEBUG=tls,x509,http`) pour une analyse fine, dans une VM jetable, jamais en production.

**Pièges classiques**
- Corriger le fichier à la main sur `pxe01` : le prochain rendu le refait… ou pas, selon l'origine de l'écart.
- Conclure « iPXE ne fait pas de HTTPS » parce que `ipxe.org` est refusé : c'est voulu depuis E13.
- Tester avec un navigateur au lieu d'un client qui vérifie (`curl`, `openssl s_client`).

**En production chez MédiSphère**
Sonde qui démarre une VM jusqu'au script de la MAC ; empreintes servies comparées aux empreintes rendues ; alerte d'émetteur et d'échéance sur le certificat de `pxe01`.

---

### M11-E21 — Panne : l'installation reste bloquée

**Démarche de diagnostic**

*Symptôme* : l'installateur démarre puis s'arrête sur un écran qui attend.

*Hypothèses* : question non préremplie (d-i) ; source d'installation injoignable ; disque introuvable ; réseau de l'installateur ; fichier de réponse non lu.

**Étape 1 — L'écran et la console secondaire.** d-i : Alt-F4 (journal en direct), `/var/log/syslog` depuis Alt-F2. Anaconda : Alt-F2 (shell), `/tmp/anaconda.log`, `/tmp/packaging.log`, `/tmp/storage.log`, `lsblk`.

**Étape 2 — Le fichier servi contre le rendu** :

```
admin@adm01:~/src/provisioning$ uv run outils/netbox-provision.py rendre --sortie /tmp/rendu
admin@adm01:~$ curl -sS https://pxe01.par1.medisphere.internal/kickstart/bm03.ks | diff -u /tmp/rendu/kickstart/bm03.ks -
admin@adm01:~$ curl -sS https://pxe01.par1.medisphere.internal/preseed/bm01.cfg | diff -u /tmp/rendu/preseed/bm01.cfg -
```

**Variante 1 — preseed : confirmation du partitionnement absente.** Écran : « Écrire les modifications sur les disques ? » (partman). Alt-F4 : `debconf (developer): <-- INPUT critical partman/confirm`. Le preseed servi a la ligne `#d-i partman/confirm boolean true` (commentée). `debconf-set-selections -c` l'accepte : une ligne commentée est une ligne valide. C'est la limite des validateurs syntaxiques. Correctif : redéployer depuis le code ; trouver l'auteur. Prévention : `verifier-rendu.sh` exige `partman/confirm` et `partman/confirm_nooverwrite` (contrôle **sémantique**), et le pipeline teste une installation complète.

**Variante 2 — source d'installation introuvable.** Anaconda : « Error setting up base repository » ou « Installation source » en erreur dans le résumé texte. `/tmp/packaging.log` : `Failed to download metadata … /BaseOs/x86_64/os/repodata/repomd.xml (404)`. L'URL servie contient `BaseOs` (casse) : dans la commande `url` du kickstart, ou dans `inst.repo` du script iPXE de la machine si le kickstart n'a pas de `url`. `ksvalidator` ne vérifie pas qu'une URL existe. Correctif : redéployer ; prévention : le pipeline teste chaque URL de dépôt (`curl -f …/repodata/repomd.xml`).

**Variante 3 — disque absent.** Anaconda s'arrête sur une erreur de stockage (« Disk "sdb" given in ignoredisk command does not exist » ou « No usable disks » selon la version). `lsblk` : un seul disque, `sda`. Correctif : redéployer. Prévention : le gabarit prend le disque d'une donnée NetBox (ou d'un défaut unique), et `verifier-rendu.sh` exige `ignoredisk` ; en production, désigner le disque par un identifiant stable (`/dev/disk/by-id/…` ou `--only-use=` d'après le numéro de série remonté par l'inventaire), pas par un nom qui dépend de l'ordre de détection.

**Vérification** : installation complète sans intervention ; `lab/bin/check 11 21` ; `lab/bin/break 11 21 --annuler`.

**Explications**

Un installateur automatique n'échoue presque jamais bruyamment : il **pose la question** à laquelle personne n'a répondu. En `priority=critical`, d-i ne pose que les questions critiques non préremplies : chaque arrêt pointe donc vers une clé précise. Anaconda, lui, regroupe les problèmes dans son résumé et attend une action.

**Alternatives** : `debian-installer/exit/poweroff` + délai maximal côté orchestrateur (E15) : un blocage devient un échec visible (`failed` au bout du délai) au lieu d'une attente silencieuse.

**Pièges classiques**
- Croire qu'un fichier qui passe `ksvalidator` ou `debconf-set-selections -c` est bon.
- Répondre à la question à la console et laisser l'installation finir : la machine est installée, la cause est toujours là.
- Désigner le disque par `sdX` sur du matériel où l'ordre de détection varie.

**En production chez MédiSphère**
Installation de test de chaque gabarit à chaque MR (VM éphémère), délai maximal par étape dans l'orchestrateur, et journal de l'installateur récupéré automatiquement en cas d'échec (`%onerror` du kickstart, `preseed/late_command` ne suffit pas car il n'est jamais atteint).

---

### M11-E22 — Panne : MAAS ne pilote plus les machines

**Démarche de diagnostic**

*Symptôme* : état d'alimentation « Error » dans MAAS pour une ou toutes les machines.

*Hypothèses* : identité refusée (jeton expiré, supprimé, secret faux) ; droits insuffisants (rôle, ACL, séparation des privilèges) ; machine introuvable (nom, identifiant) ; TLS (ancre, nom, horloge) ; réseau (flux `maas01` → `pve01:8006`).

**Étape 1 — Reproduire dans MAAS** :

```
admin@maas01:~$ maas admin machines read | jq -r '.[] | "\(.system_id) \(.hostname) \(.power_state)"'
admin@maas01:~$ maas admin machine query-power-state <SYSTEM_ID>
admin@maas01:~$ maas admin machine power-parameters <SYSTEM_ID>
```

(`admin` = nom de ton profil CLI.) **Étape 2 — Côté Proxmox** :

```
root@pve01:~# tail -n 20 /var/log/pveproxy/access.log | grep 'wb-maas'
… "GET /api2/json/nodes/pve01/qemu/2113/status/current HTTP/1.1" 401 …    (identité)
… "GET /api2/json/nodes/pve01/qemu/2113/status/current HTTP/1.1" 403 …    (droits)
root@pve01:~# pveum user token list wb-maas@pve
root@pve01:~# pveum user token permissions wb-maas@pve maas
root@pve01:~# pveum role list | grep WBMaas
```

**Étape 3 — Reproduire hors de MAAS**, depuis `maas01`, même confiance TLS (secret dans un fichier temporaire 600, jamais en argument) :

```
admin@maas01:~$ umask 077; printf 'Authorization: PVEAPIToken=wb-maas@pve!maas=%s\n' "$(read -rs s; echo "$s")" > /tmp/entete-pve
admin@maas01:~$ curl -sS -H @/tmp/entete-pve https://<IP-PVE01>:8006/api2/json/nodes/pve01/qemu/2113/status/current | jq .data.status
admin@maas01:~$ rm -f /tmp/entete-pve
```

**Variante 1 — jeton expiré.** `401` dans `access.log` pour toutes les VMs. `pveum user token list wb-maas@pve` : `expire` dans le passé (une heure avant l'injection). Cause : « campagne de rotation » qui a mis une expiration sans renouveler. Correctif : décision avec Sophie — soit une nouvelle expiration raisonnable (`pveum user token modify wb-maas@pve maas --expire <EPOCH>`), soit un nouveau jeton (secret à mettre dans MAAS et au registre des secrets). Prévention : alerte à J-15 sur l'expiration des jetons, rotation outillée (nouveau jeton, mise à jour du consommateur, révocation de l'ancien).

**Variante 2 — privilège retiré.** `403` sur `status/current` ; `pveum user token permissions` ne montre plus `VM.Audit` sur `/vms/2112`… Le rôle `WBMaas` a perdu `VM.Audit` lors d'une revue : MAAS doit **lire** l'état avant d'agir. Correctif : `pveum role modify WBMaas --privs "VM.Audit,VM.PowerMgmt"` (exactement la liste du code ou du registre), et documenter pourquoi chaque privilège est nécessaire. Prévention : le rôle est décrit dans le code (rôle Ansible de configuration de `pve01` ou ADR-0030) avec la justification de chaque privilège.

**Variante 3 — VM renommée.** Une seule machine en erreur. `access.log` : aucune requête pour sa VM, ou une recherche par nom qui échoue ; `power-parameters` montre que MAAS désigne la VM par son **nom** (`bm02`), or `qm config 2113` donne `name: bm02-ancien`. Correctif : rendre son nom à la VM (le code OpenTofu le fait : `tofu plan` dans l'état `provisioning` le montre en écart) ; mieux, désigner les VMs par leur **identifiant** dans MAAS, stable. Prévention : la dérive OpenTofu (plan planifié) aurait signalé le renommage.

**Variante 4 — ancre TLS retirée de `maas01`.** Aucune requête dans `access.log` (la poignée de main échoue avant). `curl` sur `maas01` : `SSL certificate problem: unable to get local issuer certificate`. Le fichier de l'ancre de `pve01` a disparu de `/usr/local/share/ca-certificates/` (mises à jour + `update-ca-certificates --fresh`). Correctif : réinstaller l'ancre par le code (rôle Ansible de `maas01`), `update-ca-certificates`, `snap restart maas`. Ne **jamais** décocher *verify SSL*. Prévention : la racine fait partie de la configuration convergée de `maas01`, pas d'un geste d'installation.

**Vérification** : `query-power-state` réussit pour les quatre machines ; un cycle arrêt/démarrage de `bm02` par MAAS ; `lab/bin/check 11 22` ; `lab/bin/break 11 22 --annuler` ; puis arrêt de MAAS (`sudo snap stop maas`).

**Explications**

Un pilote d'alimentation est un **client d'API** comme un autre : identité (jeton), autorisation (rôle et ACL sur un chemin), désignation de la cible (nom ou identifiant), transport (TLS). Le statut HTTP sépare les deux premières familles (401 contre 403) ; l'absence de requête dans le journal du serveur désigne le transport ou la désignation.

**Alternatives** : jeton avec séparation des privilèges (`--privsep 1`) et ACL posées sur le **jeton** : le compte peut avoir plus de droits que son jeton, et un jeton compromis vaut moins. Plus sûr, mais il faut des ACL pour le jeton lui-même (sinon il n'a aucun droit).

**Pièges classiques**
- Donner `PVEVMAdmin` (ou `Administrator`) « pour que ça marche ».
- Désactiver *verify SSL*.
- Régénérer le jeton sans mettre à jour MAAS **et** le registre des secrets.
- Laisser MAAS démarré après l'exercice : son DHCP ou son proxy pourraient se réveiller.

**En production chez MédiSphère**
Sonde quotidienne d'interrogation de l'alimentation par l'outil retenu (ADR-0110) ; expiration des jetons surveillée ; privilèges documentés avec leur justification.

---

### M11-E23 — Sous le capot : un démarrage PXE paquet par paquet

**Solution**

*Captures* (filtres et durée bornés ; `bm01` en position d'installation, éteinte) :

```
root@pve01:~# timeout 300 tcpdump -ni tap2112i0 -s 0 -w /root/bm01.pcap \
    'port 67 or port 68 or port 69 or port 53 or port 443 or (udp and portrange 1024-65535)' &
admin@dns01:~$ sudo timeout 300 tcpdump -ni ens18 -s 0 -w /tmp/dns01-bm01.pcap 'port 67' &
root@pve01:~# qm start 2112
```

Après le démarrage du noyau de l'installateur : `qm stop 2112`, rapatriement des captures sur ton poste (`scp`), **suppression** sur `pve01` et `dns01`. Même chose pour `bm03` (`tap2114i0`). Lecture : `tshark -r bm01.pcap -Y 'dhcp' -T fields -e frame.time_relative -e dhcp.option.dhcp -e dhcp.option.client_system_architecture -e dhcp.option.user_class -e dhcp.ip.relay -e dhcp.file` ; `tftp` ; `tls.handshake.extensions_server_name`.

*Compte rendu* — modèle : [`demarrage-pxe.md`](fichiers/M11-E23/medisphere/docs/provisioning/analyses/demarrage-pxe.md). Réponses attendues aux questions :

a. Deux DHCP : la ROM obtient adresse et chargeur ; iPXE ne réutilise pas l'état de la ROM et refait un DHCP en s'annonçant (option 77 `iPXE`, option 175) ; Kea le classe et lui donne l'URL HTTPS. Sans cette classe, iPXE recevrait `undionly.kpxe` et se rechargerait en boucle.
b. Le relais renseigne `giaddr` (son adresse dans le VLAN 60), envoie en unicast depuis le port 67 vers chaque serveur Kea ; Kea choisit le sous-réseau `id: 60` d'après `giaddr` et répond au relais, qui rediffuse au client. Côté `dns01`, l'adresse source est celle de la passerelle, jamais celle du client.
c. `tsize` (taille annoncée, RFC 2349) et `blksize` (RFC 2348), confirmés par un OACK (RFC 2347). À 512 octets, il faut environ trois fois plus d'allers-retours qu'à 1 432 ; sur un réseau local, le gain se mesure en dixièmes de seconde pour un chargeur de 70 à 1 000 Kio.
d. TLS 1.2 (iPXE ne parle pas TLS 1.3), suite ECDHE-ECDSA avec AES-GCM (celle que tu observes) ; le nom apparaît en clair dans la requête DNS puis dans l'extension SNI du ClientHello.
e. En général, le téléchargement de l'initrd puis l'installateur lui-même ; l'étage réseau (DHCP, TFTP) pèse quelques secondes. Gagner 30 % : miroir local (`apt-cacher-ng`), initrd plus léger, parallélisme des installations.
f. Option 93 (0 contre 7), fichier (`undionly.kpxe` contre `ipxe.efi`), taille du chargeur, et côté UEFI le micrologiciel tente parfois IPv6 ou HTTP Boot avant PXE IPv4 selon l'ordre configuré.

**Vérification** : `lab/bin/check 11 23`.

**Explications**

Lire un démarrage sur le fil, c'est relier chaque message à la RFC qui le décrit : RFC 2131/2132 (DHCP et options), RFC 4578 (options PXE 93, 94, 97), RFC 3004 (user-class), RFC 1350 et 2347-2349 (TFTP et options), RFC 5246 (TLS 1.2), RFC 9110 (HTTP).

**Pièges classiques**
- Capturer sur `vmbr1` ou sur l'interface physique de `pve01` : trop de bruit, et l'interface `tap` de la VM suffit.
- Oublier les ports éphémères du TFTP : seul le RRQ part vers le port 69, les données reviennent depuis un autre port.
- Laisser une capture tourner (disque plein) ou la commiter.

**En production chez MédiSphère**
Capture à la demande sur les ports des commutateurs (*port mirroring*), jamais permanente ; les captures sont des données d'exploitation (adresses, noms) à durée de conservation courte.

---

### M11-E24 — Questions expert : provisioning

1. Mise sous tension → micrologiciel UEFI (POST) → pile réseau UEFI (SNP/MNP) → DHCP avec options 60 `PXEClient`, 93 = 7, 94, 97 → OFFER avec fichier et serveur (ou proxyDHCP) → TFTP du chargeur (`ipxe.efi`) → exécution (vérification Secure Boot si actif) → iPXE : DHCP (option 77) → DNS → HTTPS (script, noyau, initrd) → `boot` : iPXE passe la main au noyau (EFI stub) avec ses initrd → noyau → installateur. Chaque étape est déclenchée par la réussite de la précédente ; l'ordre de démarrage UEFI (`BootOrder`) décide de la tentative réseau.
2. **c.** Sans `siaddr` ni option 66, le client n'a pas de serveur TFTP désigné : la plupart des ROM échouent (« TFTP open timeout » vers 0.0.0.0) ; certaines essaient le serveur DHCP (option 54). a : seulement pour certaines ROM, ce n'est pas le cas général ; b : le relais n'est jamais un serveur TFTP ; d : HTTP Boot exige une offre spécifique (option 60 `HTTPClient` et une URL).
3. TFTP est en UDP, un bloc par aller-retour, sans fenêtre (débit borné par la latence), sans reprise, sans authentification ; HTTP(S) utilise TCP (fenêtre, débit plein), permet de gros fichiers (initrd de plusieurs centaines de Mo) et TLS. Chiffrable : temps de transfert d'un initrd de 100 Mo en TFTP (blocs de 1 432 octets, ~70 000 allers-retours) contre HTTP, taille maximale (TFTP limité à 32 ou 4 Go selon `blksize` et le bouclage des numéros de bloc), confiance (aucune contre une chaîne vérifiée).
4. Le *chainloading* : un chargeur (ROM PXE) charge iPXE, qui charge à son tour un script ou une image. Comme iPXE refait un DHCP, il recevrait le même fichier et se rechargerait sans fin ; la classe sur l'option 77 lui donne une URL de script à la place. Autre méthode : intégrer un script au binaire (`EMBED=`), qui ignore le nom de fichier du DHCP.
5. Le client annonce `HTTPClient` dans l'option 60 et un code d'architecture HTTP dans l'option 93 (16 = x64 UEFI HTTP) ; l'offre doit contenir une URL dans le champ fichier et l'option 60 `HTTPClient` en retour. Non utilisé ici : support variable selon les micrologiciels (OVMF le permet), pas de BIOS, TLS du micrologiciel avec son propre magasin de certificats — iPXE donne une chaîne uniforme BIOS et UEFI.
6. **b.** `undionly.kpxe` s'appuie sur l'interface UNDI de la ROM PXE de la carte (petit, compatible partout) ; `ipxe.pxe` embarque les pilotes d'iPXE. a : c'est l'inverse ; c : non ; d : `.kpxe` est un format BIOS (PXE), l'UEFI utilise `.efi`.
7. Micrologiciel → vérifie le chargeur avec les clés de `db` (Microsoft UEFI CA en général) → **shim**, signé par Microsoft, contient la clé de la distribution (ou une clé enrôlée par l'administrateur, MOK) → vérifie le chargeur suivant (GRUB ou iPXE signé) → vérifie le noyau. iPXE 2.0 se distribue avec un shim et un binaire signés, ce qui permet Secure Boot sans enrôler de clé ; ses propres images téléchargées doivent alors être vérifiées par iPXE (signatures) pour que la chaîne tienne.
8. Le preseed de l'initrd est chargé **avant** la configuration du réseau : il peut répondre aux questions posées avant que d-i ne puisse télécharger quoi que ce soit (langue, clavier, `netcfg/*`, choix de l'interface, miroir). Par `url=`, ces questions doivent passer par la ligne de commande du noyau (`netcfg/get_hostname=…`), car le preseed n'arrive qu'après le réseau.
9. `inst.repo` : source d'installation (et de l'image de deuxième étape) ; `inst.stage2` : seulement l'image de deuxième étape ; `url` du kickstart : source des paquets, prioritaire sur `inst.repo` pour l'installation. Une version mineure différente entre noyau/initrd et dépôt : l'image de deuxième étape ne correspond plus aux modules du noyau chargé (« Failed to mount… », modules introuvables) ; il faut le même *build*.
10. **b.** Anaconda refuse un `ignoredisk` qui désigne un disque inexistant, ou ne trouve aucun disque utilisable, et s'arrête. a : `--only-use` exclut tous les autres disques ; c : non ; d : un kickstart sans disque utilisable ne peut pas réussir.
11. RAKP (IPMI 2.0) : le contrôleur renvoie, à quiconque donne un nom de compte valide, une empreinte HMAC-SHA1 dérivée du mot de passe, attaquable hors ligne ; cela n'exige aucune authentification préalable, juste l'accès à UDP 623. S'y ajoutent *cipher 0*, les comptes par défaut et l'absence de TLS. Redfish passe par HTTPS avec authentification de session ou basique sur TLS : l'attaque hors ligne disparaît (restent les mots de passe faibles).
12. `@odata.id` est l'URI de chaque ressource ; un client suit les liens depuis `/redfish/v1/` au lieu de construire des chemins. `Actions` décrit les opérations possibles (ex. `#ComputerSystem.Reset` avec sa `target`) et `ResetType@Redfish.AllowableValues` la liste des valeurs acceptées **par ce contrôleur** (`On`, `ForceOff`, `GracefulShutdown`, `ForceRestart`, `Nmi`, `PushPowerButton`…) : toutes ne sont pas implémentées partout, d'où la lecture préalable.
13. Lire la liste des VMs et leur état (`VM.Audit`), les démarrer et les arrêter (`VM.PowerMgmt`) ; selon la version, modifier l'ordre de démarrage pour un démarrage réseau (`VM.Config.Options`, à confirmer). Un jeton à séparation des privilèges sans ACL propre n'a **aucun** droit : toutes les requêtes répondent 403, même si le compte a les droits.
14. *Enlistment* : une machine inconnue démarre sur le réseau, MAAS lui sert une image éphémère qui l'enregistre ; *commissioning* : la machine redémarre sur l'image éphémère, qui inventorie le matériel (processeurs, mémoire, disques, cartes, LLDP) et lance des tests. La chaîne maison perd l'inventaire automatique et les tests avant mise en service ; on le remplace par un démarrage sur une image d'inventaire (Debian live + script qui remonte `lshw`/`lsblk`/`ip link` vers NetBox par l'orchestrateur), ou par l'inventaire Redfish du contrôleur (E18) pour ce qu'il expose.
15. Écrasement (`shred`, une passe suffit sur les disques modernes, mais ne couvre pas les zones remappées des SSD) ; effacement sécurisé du firmware (ATA Secure Erase par `hdparm`, NVMe Format avec `--ses=1` ou Sanitize par `nvme-cli`) ; effacement cryptographique (disque chiffré, destruction de la clé, ou `--ses=2` en NVMe). Intégration : un gabarit iPXE « effacement » servi aux équipements `decommissioning`, qui démarre une image dédiée, efface, produit un rapport (numéro de série, méthode, horodatage) remonté au journal NetBox, puis éteint ; la preuve d'effacement est une exigence HDS.

**Grille** : une réponse est juste si elle donne le mécanisme **et** sa conséquence pratique ; pour les QCM, la justification des mauvaises options compte autant que la bonne lettre.
