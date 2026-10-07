# Module 03 — Corrigé du palier 4 : Expert

> ⚠️ Corrigé — à lire après avoir cherché.

Scripts de panne : [`pannes/break-E19.sh`](pannes/break-E19.sh) à [`pannes/break-E22.sh`](pannes/break-E22.sh) (fonctions communes : [`pannes/_m03-commun.sh`](pannes/_m03-commun.sh)). Synthèse d'astreinte : [`fichiers/M03-E25/medisphere/docs/socle/runbooks/RB-038-diagnostic-build-demarrage.md`](fichiers/M03-E25/medisphere/docs/socle/runbooks/RB-038-diagnostic-build-demarrage.md).

---

### M03-E19 — Panne : le build attend SSH indéfiniment

**Démarche de diagnostic**

*Symptôme* : « Waiting for SSH to become available... » jusqu'au délai maximal (`ssh_timeout`, 15 min et plus dans le projet).

*Ce que veut dire le message.* Avec `proxmox-iso`, Packer ne connaît pas l'adresse de la VM : la fonction qui la fournit au communicateur interroge l'**agent QEMU** (`network-get-interfaces`). Tant que l'agent ne répond pas, chaque tentative échoue et Packer reste à l'étape « attente de SSH ». Dans le journal détaillé :

```
admin@adm01:~$ grep -m3 -E 'Error getting SSH address|guest agent|Waiting for SSH' /tmp/e19.log
… [DEBUG] Error getting SSH address: 500 QEMU guest agent is not running
```

(libellé exact selon la version du plugin.) Le message couvre donc toutes les étapes **avant** SSH : démarrage de l'installeur, réseau, *preseed*, installation, redémarrage, agent.

*Hypothèses dans l'ordre du chemin*, départagées par la **console** de la VM 9090 :

| Console | Étape | Variante |
|---|---|---|
| « Network autoconfiguration failed » (ou configuration réseau manuelle proposée) | DHCP | 2 |
| « Failed to retrieve the preconfiguration file » | serveur HTTP de Packer | 1 |
| « Bad archive mirror » / impossible de télécharger les composants | DNS (le *preseed* est lu par adresse IP) | 3 |
| installation terminée, redémarrage, invite `login:` | agent absent | 4 |

**Variante 1 — flux HTTP de Packer fermé sur `gw01`.** Le fichier persistant a été modifié et rechargé : la règle laisse passer 8000-8099 au lieu de 8100-8199.

```
admin@adm01:~$ ssh gw01 "sudo nft list chain inet filter forward" | grep -n 'tcp dport 8'
14:  iifname "ens19.99" ip daddr 10.10.10.10 tcp dport 8000-8099 accept comment "VMs de build Packer vers le serveur HTTP de Packer sur adm01 (M03-E05)"
admin@adm01:~$ ssh gw01 "sudo tcpdump -ni ens19.99 -c 5 'tcp portrange 8100-8199'"
IP 10.10.99.142.48212 > 10.10.10.10.8137: Flags [S] …      (SYN répétés, aucune réponse)
```

Le commentaire de la règle dit encore « serveur HTTP de Packer » : la règle existe, elle a été **altérée**. Correctif : remettre `8100-8199` dans `/etc/nftables.conf` (procédure M00-E21 : `nft -c -f`, retour arrière programmé, `systemctl reload nftables`). Variante de repli (si ta règle n'avait pas cette forme) : une règle de rejet ajoutée à chaud en tête de chaîne, absente du fichier ; elle disparaît avec `systemctl reload nftables`. Dans les deux cas, compare l'état chargé (`nft list ruleset`) au fichier : un écart est toujours une information.

**Variante 2 — plus de bail DHCP sur le VLAN 99.**

```
admin@adm01:~$ ssh dns01 "sudo journalctl -u dnsmasq --since -10min | grep -E 'DHCP(DISCOVER|OFFER)'"
dnsmasq-dhcp[612]: DHCPDISCOVER(ens18) 10.10.99.1 bc:24:11:5a:7e:02 no address available
admin@adm01:~$ ssh dns01 "grep -n dhcp-range /etc/dnsmasq.d/medisphere.conf"
67:dhcp-range=set:sandbox,10.10.99.0,static,255.255.255.0,12h
```

En mode `static`, dnsmasq ne sert que les clients déclarés par `dhcp-host` : « no address available ». Correctif : remettre la plage dynamique `10.10.99.100,10.10.99.199`, `dnsmasq --test`, `systemctl restart dnsmasq`. Effet de bord à noter : les VMs déjà présentes sur `vsandbox` auraient perdu leur adresse à l'échéance de leur bail.

**Variante 3 — DNS du VLAN 99 rejeté.** Le *preseed* arrive (URL par adresse IP), l'installeur ne résout plus `deb.debian.org`.

```
admin@adm01:~$ ssh gw01 "sudo nft -a list chain inet filter forward | head -n 8"
    ip saddr 10.10.99.0/24 ip daddr 10.10.20.10 meta l4proto { tcp, udp } th dport 53 drop # handle 57
admin@adm01:~$ ssh gw01 "sudo nft -c -f /etc/nftables.conf && grep -c 'th dport 53 drop' /etc/nftables.conf"
0
```

Règle de rejet **ajoutée à chaud**, en tête, absente du fichier : elle ne survivrait pas à un redémarrage, mais elle est active. Correctif : `sudo nft delete rule inet filter forward handle 57` (ou `systemctl reload nftables`, qui recharge le fichier). Prévention : comparer régulièrement règles chargées et fichier (ce que fait le contrôle de E19).

**Variante 4 — agent absent du système installé.** L'installation se termine, la VM redémarre sur une invite de connexion… et Packer attend toujours.

```
root@pve01:~# qm guest cmd 9090 ping
QEMU guest agent is not running
admin@adm01:~/src/images$ git status --short && git diff
 M debian13-base/http/preseed.cfg
-d-i pkgsel/include string qemu-guest-agent cloud-init cloud-guest-utils netplan.io systemd-resolved sudo ca-certificates
+d-i pkgsel/include string cloud-init cloud-guest-utils netplan.io systemd-resolved sudo ca-certificates
```

La copie de travail a été modifiée (les « essais de Lucas ») : `--brouillon` l'a construite telle quelle. Correctif : `git restore debian13-base/http/preseed.cfg`. C'est aussi la variante qui montre pourquoi `construire.sh` refuse par défaut un dépôt modifié, et pourquoi la CI (E15) ne construit que des commits de `main`.

*Cause racine et correctif* : ci-dessus. Puis build d'essai complet (`-var vm_id=9090`), suppression de 9090, `lab/bin/check 03 19`, et `lab/bin/break 03 19 --annuler` pour clore (rien n'est écrasé : l'annulation ne restaure un fichier que s'il est encore dans l'état cassé).

**Prévention**
- Faire échouer vite : une étape de contrôle avant le build (`outils/construire.sh` ou un job CI) qui vérifie depuis la machine de build le DHCP (bail d'une VM de sonde), la résolution DNS et l'accès au serveur HTTP ; ou une limite de temps courte pour l'installation (`ssh_timeout` adapté à la durée réelle mesurée, marge comprise).
- `gw01` : alerte quand règles chargées et fichier divergent ; règles du lab commentées avec leur exercice (une règle altérée se repère à son commentaire).
- RB-038, tableau « console → étape → commande ».

**Explications**

« Waiting for SSH » est un symptôme de **fin de chaîne** : toutes les étapes qui précèdent le produisent. La console de la VM est l'instrument qui situe l'étape en une minute ; le journal détaillé de Packer dit ce qu'il attend vraiment (l'agent). Ensuite seulement, on mesure le maillon : bail DHCP dans le journal de dnsmasq, SYN sans réponse au `tcpdump`, compteurs nftables, `git diff`.

**Pièges classiques**
- Augmenter `ssh_timeout` : on attend plus longtemps la même panne.
- Relancer le build sans la console ouverte : on rate le seul message utile.
- Construire sur 9001 pour « reproduire » : `-force` supprime l'image de base.
- Corriger `gw01` en ajoutant une règle permissive au lieu de trouver celle qui a changé.

**En production chez MédiSphère**
Le pipeline de construction a une étape de pré-vol (réseau de build, accès API, espace disque) et une limite de temps par étape ; les règles de `gw01` sont gérées par Ansible (module 04), ce qui rend toute dérive visible au prochain passage.

---

### M03-E20 — Panne : les clones se marchent dessus

**Démarche de diagnostic**

*Symptômes* : SSH arrive sur l'une ou l'autre VM, avertissements de clé d'hôte, comportements croisés.

*Hypothèses* : ce qui identifie une machine à chaque couche — adresse **MAC** (L2), identifiant de client **DHCP** dérivé du **`machine-id`** (L3), **nom** (DNS, DHCP), **clés d'hôte** SSH (L7). Chacune a une signature propre.

**Étape 1 — Ne pas se fier à SSH.** Le multiplexage de `adm01` peut réutiliser une connexion vers la « mauvaise » VM : `-o ControlPath=none` pour chaque essai. Par l'agent, sans réseau :

```
root@pve01:~# for v in 2038 2039; do echo "== $v"; qm config $v | grep ^net0
  qm guest exec $v -- cat /etc/machine-id | grep out-data
  qm guest exec $v -- hostname | grep out-data
  qm guest exec $v -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | grep out-data
  qm guest exec $v -- ip -4 -o addr show scope global | grep out-data; done
```

**Étape 2 — Lire la fabrication.** `qm config 9095` (notes : « préparée à la main ») ; dans une VM, `ls /etc/cloud/cloud.cfg.d/`.

**Variante 1 — `machine-id` conservé.** Machine-id identiques, MAC différentes, **même adresse** :

```
admin@adm01:~$ ssh dns01 "sudo journalctl -u dnsmasq --since -1h | grep -E 'DHCPACK.*10\.10\.99'"
dnsmasq-dhcp[612]: DHCPACK(ens18) 10.10.99.147 bc:24:11:2c:91:0a mediagenda-test1
dnsmasq-dhcp[612]: DHCPACK(ens18) 10.10.99.147 bc:24:11:d4:07:5e mediagenda-test2
dnsmasq-dhcp[612]: … client provides name / client-id ff:…:… (identique pour les deux)
```

`systemd-networkd` présente un identifiant de client (DUID) dérivé du `machine-id` ; dnsmasq rend le même bail. Réparation de chaque VM (par la console ou l'agent, le réseau étant instable) :

```
admin@mediagenda-test2:~$ sudo rm -f /etc/machine-id /var/lib/dbus/machine-id
admin@mediagenda-test2:~$ sudo systemd-machine-id-setup && sudo reboot
```

(Une seule des deux suffit à lever le conflit ; les deux pour la propreté.) Correction de la fabrication : `cloud-init clean --machine-id` (ou fichier `uninitialized`) dans la préparation : c'est `scripts/preparer-clonage.sh` (E07).

**Variante 2 — clés d'hôte conservées.** Empreintes identiques ; `/etc/cloud/cloud.cfg.d/90-mediagenda.cfg` contient `ssh_deletekeys: false`. cloud-init a bien vu une nouvelle instance, mais avec `ssh_deletekeys: false` il ne régénère que les types de clés **manquants** : les clés de l'image survivent. Conséquence : chaque VM peut se faire passer pour l'autre sans que SSH ne le signale (`known_hosts` sans valeur). Réparation : retirer le fichier, `sudo rm /etc/ssh/ssh_host_*`, `sudo ssh-keygen -A`, `sudo systemctl restart ssh`, puis `ssh-keygen -R <IP>` sur `adm01`. Fabrication : supprimer les clés à la préparation, ne jamais désactiver `ssh_deletekeys`.

**Variante 3 — nom figé.** `hostname` donne `mediagenda-test` sur les deux ; `90-mediagenda.cfg` contient `preserve_hostname: true`. Le nom fourni par Proxmox (*user-data*, `hostname: mediagenda-test1`) est ignoré ; les deux VMs envoient le même nom à dnsmasq, le DNS dynamique du lab ne sait plus qui est qui. Réparation : retirer la clé, `sudo hostnamectl set-hostname mediagenda-test1` (resp. `…2`), renouveler le bail. Fabrication : pas de nom dans l'image, pas de `preserve_hostname`.

**Variante 4 — même adresse MAC.** Machine-id, clés et noms sont distincts : l'image est saine. Mais `qm config` montre la même MAC sur `net0` pour les deux VMs (le « script de Lucas » a recopié la ligne `net0` avec sa MAC). Sur le bridge, la table d'apprentissage bascule d'un port à l'autre ; ARP et DHCP deviennent imprévisibles. Réparation (VM arrêtée) : `qm set 2039 --net0 virtio,bridge=vsandbox` (sans `macaddr` : Proxmox en génère une). Fabrication : rien dans l'image ; corriger le script de création (ne jamais fixer la MAC d'un clone). C'est la variante qui rappelle de vérifier **les deux côtés** avant d'accuser l'image.

*Vérification* : `lab/bin/check 03 20` ; puis `tests/tester-image.sh 9095` **avant** l'annulation : il échoue sur les variantes 1 à 3 (machine-id, clé ou nom), et réussit sur la variante 4 (l'image est bonne). Clore : `lab/bin/break 03 20 --annuler` (détruit 2038, 2039, 9095).

**Prévention**
- La préparation au clonage reste dans le code (E07), jamais faite « à la main » ; aucune image hors du projet.
- Le test d'image compare deux clones (E14) ; tout template d'essai passe le test avant d'être cloné pour quelqu'un.
- Les VMs sont créées par un outil (OpenTofu, M05) qui ne fixe jamais de MAC.

**Explications**

Une identité dupliquée est une panne **silencieuse** : rien ne casse au démarrage, tout devient incohérent ensuite, et les symptômes changent avec le temps (baux, caches ARP, `known_hosts`). La méthode consiste à énumérer les identités par couche et à les comparer **par un canal qui ne dépend pas d'elles** (agent QEMU, console).

**Pièges classiques**
- Diagnostiquer par SSH avec le multiplexage actif : on interroge la même VM deux fois.
- Régénérer le `machine-id` en laissant un fichier vide sans redémarrer : rien ne change tant que `systemd-networkd` n'a pas redemandé un bail.
- Réparer les VMs et oublier l'image : la prochaine VM de Lucas aura le même problème.
- Accuser l'image quand c'est la création (variante 4).

**En production chez MédiSphère**
Un contrôle périodique du parc (inventaire NetBox, module 06) détecte les MAC, noms et empreintes SSH en double ; une alerte DHCP signale un même bail attribué à deux MAC.

---

### M03-E21 — Panne : cloud-init ignore la configuration

**Démarche de diagnostic**

*Symptôme* : nouvelle adresse et clé de Julien non appliquées après redémarrage.

*Côté Proxmox, ce que la VM devrait recevoir :*

```
root@pve01:~# qm cloudinit dump 2037 network | grep -A3 eth0     # adresse 10.10.99.37/24 attendue
root@pve01:~# qm cloudinit dump 2037 user | grep -c ssh-ed25519  # 2 clés attendues
root@pve01:~# qm cloudinit dump 2037 meta
instance-id: 3b6f…c21e
root@pve01:~# qm config 2037 | grep -E '^(ide|sata|scsi)[0-9]+: .*cloudinit'
```

Proxmox calcule l'`instance-id` à partir du contenu du *user-data* et du *network-config* : chaque changement de l'onglet Cloud-Init le modifie, et cloud-init, voyant un nouvel identifiant, rejoue les modules « par instance » (clés, réseau). C'est ce mécanisme qui est cassé, à l'un de ses maillons.

*Dans la VM* (par ta clé sur l'ancienne adresse DHCP, ou par l'agent) :

```
admin@agenda-dev01:~$ cloud-init status --long
admin@agenda-dev01:~$ sudo cat /run/cloud-init/ds-identify.log | tail -n 20
admin@agenda-dev01:~$ sudo cat /run/cloud-init/cloud-init-generator.log
admin@agenda-dev01:~$ blkid -t LABEL=cidata
admin@agenda-dev01:~$ sudo cat /var/lib/cloud/data/instance-id; cloud-init query instance_id
admin@agenda-dev01:~$ sudo grep -E 'restored from|new instance|is new|datasource' /var/log/cloud-init.log | tail
```

**Variante 1 — lecteur cloud-init retiré.** `qm config 2037` : plus de lecteur `cloudinit`. Dans la VM : `blkid -t LABEL=cidata` vide, `status: disabled`, `boot_status_code: disabled-by-generator` ; `ds-identify.log` : « No ds found … Disabled cloud-init ». Sans source, `ds-identify` désactive cloud-init (politique par défaut sur x86_64 : `notfound=disabled`) ; la VM garde sa configuration précédente. Correctif : `qm set 2037 --ide2 local-nvme:cloudinit` (VM arrêtée), redémarrer. Explication pour Julien : le « CD » de la VM **est** la configuration cloud-init.

**Variante 2 — liste de sources sans NoCloud.** Lecteur présent, `blkid` le voit, mais `status: disabled`, `disabled-by-generator` ; `ds-identify.log` :

```
/etc/cloud/cloud.cfg.d/95-datasources.cfg set datasource_list: [ ConfigDrive, OpenStack ]
…
No ds found [mode=search, notfound=disabled]. Disabled cloud-init [1]
```

`ds-identify` lit `datasource_list` dans les fichiers de configuration (la **dernière** occurrence l'emporte, d'où `95-`) et ne cherche que ces sources : ConfigDrive veut un volume `config-2`, OpenStack un DMI d'OpenStack ; NoCloud n'est pas cherché. Correctif : supprimer le fichier, redémarrer. Prévention : ne jamais surcharger `datasource_list` dans une image Proxmox (et si on le fait, `[ NoCloud, None ]`).

**Variante 3 — cache figé (`manual_cache_clean`).** Statut `done`, source `DataSourceNoCloud`… et rien n'est appliqué. Dans `/var/log/cloud-init.log` :

```
… stages.py[DEBUG]: manual cache clean set from config
… stages.py[DEBUG]: restored from cache: DataSourceNoCloud [seed=/dev/sr0]
```

et `/var/lib/cloud/data/instance-id` ≠ `qm cloudinit dump 2037 meta`. Avec `manual_cache_clean: true`, cloud-init fait **confiance** au cache de l'instance sans comparer l'identifiant : il ne voit jamais de nouvelle instance. Correctif : retirer `/etc/cloud/cloud.cfg.d/95-cache.cfg` **et** le marqueur `/var/lib/cloud/instance/manual-clean` (que cloud-init écrit dans ce mode et que `ds-identify` lit aussi), puis redémarrer : au démarrage suivant, l'identifiant est vérifié, l'instance est nouvelle, la configuration s'applique. (`sudo cloud-init clean --logs` puis redémarrage force le même résultat.)

**Variante 4 — marqueur de désactivation.** `status: disabled`, `boot_status_code: disabled-by-marker-file`, `detail: Cloud-init disabled by /etc/cloud/cloud-init.disabled`. Correctif : supprimer le fichier, redémarrer. Demander qui l'a posé et pourquoi (« accélérer les redémarrages » : la réponse est E23, pas la désactivation).

*Vérification* : `ip -4 addr` (10.10.99.37), `ssh -o ControlPath=none admin@10.10.99.37`, `cloud-init status --long` (`done`, NoCloud), `sudo cloud-init schema --system` ; `lab/bin/check 03 21` ; puis `lab/bin/break 03 21 --annuler` (détruit 2037).

**Prévention**
- L'image ne contient aucune surcharge de `datasource_list`, de cache ou de désactivation (contrôle ajouté à `tests/tester-image.sh` : changer la clé du clone, redémarrer, vérifier).
- Documenter pour les équipes (`docs/socle/images.md`) : le lecteur cloud-init fait partie du matériel de la VM.

**Explications**

Trois questions, dans l'ordre : cloud-init **tourne-t-il** (`status`, `boot_status_code`) ? A-t-il **trouvé sa source** (`ds-identify.log`, `detail`) ? A-t-il **vu une nouvelle instance** (`instance-id` comparé à Proxmox, « restored from cache ») ? Chaque variante casse un maillon différent, et chacune a sa ligne de journal qui la prouve. `cloud-init status --long` distingue les désactivations (`disabled-by-generator`, `disabled-by-marker-file`, `disabled-by-kernel-command-line`) : c'est la première commande à taper.

**Pièges classiques**
- `cloud-init clean` puis redémarrage sans chercher la cause : marche pour la variante 3, pas pour les autres, et masque le problème.
- `cloud-init single --name …` à la main : applique une fois, ne corrige rien.
- Corriger la configuration réseau à la main dans la VM : elle sera réécrite au prochain changement d'instance.
- Oublier le marqueur `manual-clean` (variante 3) : `ds-identify` continue à court-circuiter la détection.

**En production chez MédiSphère**
Les VMs durables sont configurées par OpenTofu (paramètres cloud-init) et Ansible (rôle) ; un changement d'adresse est un changement d'infrastructure (MR), pas un clic. Le test d'image vérifie à chaque build qu'un changement de configuration cloud-init est bien appliqué au redémarrage.

---

### M03-E22 — Panne : la VM Rocky ne démarre pas

**Démarche de diagnostic**

*Symptôme* : VM « running », pas d'agent, pas de réseau.

*Méthode* : situer l'étape de démarrage par la **console** (redémarrage observé), puis comparer la configuration de la VM à celle du template testé :

```
root@pve01:~# diff <(qm config <TEMPLATE> | grep -Ev '^(name|digest|template|tags|description|meta|vmgenid|smbios1|#)') \
                   <(qm config 2036 | grep -Ev '^(name|digest|template|tags|description|meta|vmgenid|smbios1|#)')
```

(`<TEMPLATE>` : l'image Rocky `current`, ou 9002 ; la ligne `net0` diffère toujours par la MAC.)

**Variante 1 — CPU `x86-64-v2-AES`.** Console : le noyau démarre, puis

```
Fatal glibc error: CPU does not support x86-64-v3
[    2.1] Kernel panic - not syncing: Attempted to kill init! exitcode=0x00007f00
```

Rocky Linux 10 (comme RHEL 10) est compilé pour le niveau de microarchitecture **x86-64-v3** (AVX2, BMI2, FMA…) ; le modèle `x86-64-v2-AES`, défaut de Proxmox et choix de nos VMs Debian, ne l'annonce pas. Le noyau démarre, mais le premier programme de l'espace utilisateur (init, lié à la glibc) s'arrête : panique. Correctif : `qm set 2036 --cpu x86-64-v3` (ou `host`), redémarrer.

**Variante 2 — contrôleur `lsi`.** Console : le noyau démarre, puis dracut attend un disque qui n'arrive pas :

```
dracut-initqueue[…]: Warning: dracut-initqueue: timeout, still waiting for following initqueue hooks:
dracut-initqueue[…]: Warning: Could not boot.
Warning: /dev/mapper/rl-root does not exist
Entering emergency mode.
```

Le contrôleur LSI 53C895A émulé (pilote `sym53c8xx`) n'est pas pris en charge par les noyaux RHEL récents (pilote non livré) : aucun disque n'apparaît. Correctif : `qm set 2036 --scsihw virtio-scsi-single`. Sur Debian, le même changement fonctionnerait (pilote présent dans le noyau générique) : la différence vient du noyau et de l'initramfs de la distribution, pas de Proxmox.

**Variante 3 — micrologiciel inversé.** Image installée en BIOS (SeaBIOS), VM passée en OVMF : écran OVMF, tentative PXE, puis « BdsDxe: No bootable option or device was found » ou *UEFI Interactive Shell* ; Proxmox signale aussi « no efidisk configured » au démarrage. (Dans l'autre sens : « No bootable device ».) Le disque n'a pas de partition système EFI (ou pas de code de démarrage BIOS) : le micrologiciel ne trouve rien à lancer. Correctif : revenir au micrologiciel du template (`qm set 2036 --bios seabios`, ou `ovmf` avec son `efidisk0`).

**Variante 4 — ordre d'amorçage.** `boot: order=net0` : iPXE s'exécute, obtient une adresse de dnsmasq (pas de fichier de démarrage), puis « No more network devices » et « No bootable device ». Correctif : `qm set 2036 --boot order=scsi0;net0` (ou l'ordre du template), redémarrer.

*Vérification* : `qm guest cmd 2036 ping`, `qm guest exec 2036 -- cat /etc/os-release` ; `lab/bin/check 03 22` ; puis `lab/bin/break 03 22 --annuler`.

**Correction de la recette.** Le réglage fautif était dans le **script de création de Julien** (le template est correct : la précondition de la panne l'a démarré avec succès). Où l'imposer : dans le template (le clone l'hérite) et **nulle part ailleurs** ; la recette ne doit surcharger que ce qui est propre à la VM (nom, réseau, ressources). Pour le CPU, la variable `cpu_type` du projet refuse déjà tout ce qui est inférieur à v3 pour Rocky (E06) ; côté consommateurs, OpenTofu (M05) lira le type de CPU dans le template plutôt que de l'écrire.

**Explications**

Un démarrage échoue à une étape précise, et chaque étape a ses messages : micrologiciel (rien à amorcer), chargeur, noyau et initramfs (pilotes, disque racine), espace utilisateur (instructions du processeur, init). La console donne l'étape ; le **diff** avec le template, qui est la référence testée, donne la cause en une commande.

**Pièges classiques**
- Réinstaller ou recloner sans comprendre : la recette refera la même erreur.
- Passer le CPU en `host` « pour que ça marche » sans mesurer la conséquence sur la migration à chaud (cluster, module 09) : `x86-64-v3` suffit et reste migrable entre hôtes compatibles.
- Chercher dans la VM (journaux) alors qu'elle n'a jamais atteint un système où écrire.

**En production chez MédiSphère**
Les VMs sont créées par OpenTofu à partir des réglages matériels du template ; les modules interdisent la surcharge du CPU, du contrôleur et du micrologiciel. Les templates Rocky ont une console série pour lire le démarrage sans interface graphique.

---

### M03-E23 — Sous le capot : mesurer un premier démarrage

**Solution**

*1. Chronologie extérieure.* Exemple de script (brouillon) :

```bash
#!/usr/bin/env bash
# ~/m03/e23/chrono.sh VMID IP — horodatage d'un démarrage vu de l'extérieur (depuis adm01).
set -euo pipefail
v="$1" ip="$2"; t0=$(date +%s.%N)
ms() { awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN { printf "%.1f s", b - a }'; }
ssh pve01 qm start "$v"
until ssh pve01 qm guest cmd "$v" ping >/dev/null 2>&1; do sleep 0.5; done; echo "agent : $(ms)"
until ssh -o ControlPath=none -o ConnectTimeout=2 -o BatchMode=yes admin@"$ip" true 2>/dev/null; do sleep 0.5; done; echo "ssh : $(ms)"
ssh -o ControlPath=none admin@"$ip" cloud-init status --wait >/dev/null; echo "cloud-init done : $(ms)"
```

(Adresse fixe `ipconfig0` sur 2034 pour connaître l'IP à l'avance, par exemple 10.10.99.34/24 ; ou lecture de l'adresse par l'agent.) Ordres de grandeur sur `pve01` (NVMe, 2 vCPU, clone lié, `ciupgrade=0`) : agent vers 6-9 s, SSH vers 8-12 s, cloud-init terminé vers 15-25 s. Tes chiffres font foi.

*2. Vu de l'intérieur.*

```
admin@m03-boot:~$ systemd-analyze time
Startup finished in 1.8s (kernel) + 14.6s (userspace) = 16.4s
graphical.target reached after 14.5s in userspace.
admin@m03-boot:~$ systemd-analyze critical-chain
graphical.target @14.5s
└─multi-user.target @14.5s
  └─cloud-final.service @11.2s +3.2s
    └─cloud-config.service @9.8s +1.3s
      └─cloud-init-network.service @6.1s +3.6s
        └─systemd-networkd-wait-online.service @4.0s +2.0s
          └─systemd-networkd.service @3.7s +0.2s
…
admin@m03-boot:~$ cloud-init analyze show | grep -E 'Finished stage|Total Time'
admin@m03-boot:~$ cloud-init analyze blame | head
     02.41100s (init-network/config-ssh)
     01.02900s (modules-final/config-scripts_user)
     …
```

(Sorties indicatives.) `blame` mesure chaque unité **séparément**, y compris celles qui tournent en parallèle et celles qui ne retardent rien : la somme dépasse le total. `critical-chain` montre la chaîne de dépendances qui a fixé l'heure d'arrivée de la cible : c'est elle qu'il faut raccourcir. Dans cloud-init, `config-ssh` domine souvent le premier démarrage : génération des clés d'hôte (RSA 3072 surtout). `cloud-init analyze boot` relie les horodatages du noyau, de l'espace utilisateur et du démarrage de cloud-init.

*3. Comparaisons* (médianes de 3 essais, valeurs indicatives) :

| Cas | Agent | SSH | cloud-init done | Remarque |
|---|---|---|---|---|
| Premier démarrage, lié, `ciupgrade=0` | 7 s | 10 s | 19 s | référence |
| Second démarrage (redémarrage) | 6 s | 8 s | 11 s | modules « par instance » sautés : clés d'hôte, utilisateurs, `package_update_upgrade_install` |
| Premier démarrage, `ciupgrade=1` | 7 s | 10 s | 60-180 s | `package_upgrade: true` dans le *user-data* : `apt update` + mise à niveau, dépend du réseau et de l'âge de l'image |
| Clone complet (au lieu de lié) | idem | idem | idem | coût au **clonage** (copie de 8 Go : 20-60 s) et non au démarrage |
| `ssh_genkeytypes: [ed25519]` (*vendor-data*) | idem | −1 à −2 s | −1 à −2 s | plus de clé RSA à générer |

*4. Leviers* (pour Molecule, des dizaines de VMs par jour) : (1) **`ciupgrade=0`** + image reconstruite chaque semaine : de une à plusieurs minutes gagnées, levier de **clonage** (paramètre cloud-init) ; (2) **clones liés** pour l'éphémère : quelques dizaines de secondes par VM, levier de **clonage** ; (3) **types de clés d'hôte réduits** et modules inutiles retirés (`ssh_genkeytypes`, `cloud_final_modules`), une à deux secondes, levier d'**image**. Les gains au démarrage (attente du réseau, délai de GRUB) existent mais pèsent moins.

*5. Rapport* : protocole (matériel, version de l'image, méthode, nombre d'essais), tableau, extraits commentés (`critical-chain`, `cloud-init analyze blame`), leviers chiffrés ; puis `qm destroy 2034 --purge`.

**Explications**

Un démarrage se mesure de deux points de vue qui ne coïncident pas : l'extérieur (ce que voit l'outil qui attend la VM : agent, SSH, cloud-init terminé) et l'intérieur (unités systemd, étapes de cloud-init). Les outils internes mesurent des durées d'unités ; seul `critical-chain` (et le graphe `plot`) dit ce qui a **retardé** le résultat. Les fréquences de cloud-init expliquent l'écart entre premier et second démarrage : ce qui est « par instance » ne se paie qu'une fois, sauf si l'identifiant d'instance change (M03-E21).

**Pièges classiques**
- Une seule mesure : le cache de page de l'hôte rend le deuxième essai plus rapide.
- Additionner `blame` et conclure qu'une unité « coûte » ce qu'elle affiche.
- Désactiver `systemd-networkd-wait-online` pour gagner deux secondes : cloud-init (étape réseau) et les services qui ont besoin du réseau démarrent alors trop tôt.
- Comparer en changeant deux variables à la fois.

**En production chez MédiSphère**
Le temps de mise à disposition d'une VM est un indicateur de la plateforme (module 21), mesuré à chaque build par le test d'image ; une régression de plus de 20 % bloque la publication.

---

### M03-E24 — Questions expert : images et démarrage

**1.** Le **générateur** systemd (`cloud-init-generator`, très tôt, avant le chargement des unités) lance `ds-identify` et active ou non `cloud-init.target`. `cloud-init-local` (avant le réseau) : trouve la source de données locale et écrit la configuration réseau (`network-config` → netplan/networkd ou NetworkManager). `cloud-init-network` (`cloud-init.service` avant 24.3 ; réseau disponible) : modules d'initialisation, par exemple `ssh` (clés d'hôte, clés autorisées), `users_groups`, `set_hostname`. `cloud-config` : modules de configuration, par exemple `timezone`, `apt_configure`, `runcmd` (qui **écrit** le script). `cloud-final` (tard, après `multi-user`) : `package_update_upgrade_install`, `scripts_user` (exécute `runcmd`), `final_message`.

**2.** `ds-identify` détecte **rapidement** et **sans réseau** quelles sources sont plausibles (étiquettes de volumes `cidata`/`config-2`, DMI, ligne de commande du noyau) et désactive cloud-init quand il n'y a rien : sans lui, cloud-init essaierait chaque source de la liste, dont des sources réseau avec délais d'attente, sur des machines qui ne sont pas des instances de nuage. Sur x86_64, politique par défaut `search,found=all,maybe=all,notfound=disabled` : aucune source → cloud-init désactivé (`disabled-by-generator`).

**3. Réponse b.** Proxmox calcule l'`instance-id` du *meta-data* (SHA-1 du *user-data* et du *network-config* générés) ; un changement de clé change le *user-data*, donc l'identifiant ; cloud-init détecte une nouvelle instance et rejoue les modules « par instance ». a) Faux : Proxmox ne touche pas au disque de la VM. c) Faux : le module `ssh` est bien « par instance ». d) Faux : l'agent ne gère pas les clés.

**4.** Fichier **vide** : systemd génère un nouvel identifiant au démarrage et le garde en mémoire (`/run/machine-id`) puis le persiste, **sans** considérer ce démarrage comme un « premier démarrage ». Fichier **`uninitialized`** : même génération, **et** `ConditionFirstBoot=yes` est vrai : les unités de premier démarrage (presets, `systemd-firstboot`) s'exécutent. `cloud-init clean --machine-id` écrit `uninitialized` pour qu'un clone d'image se comporte comme un système neuf (doc cloud-init, *clean* ; `machine-id(5)`, section *First Boot Semantics*, qui fait foi sur ta version de systemd).

**5.** Debian 13 avec cloud-init désactivé : rien ne régénère les clés (le paquet `openssh-server` ne les crée qu'à l'installation) ; sshd refuse de démarrer faute de clé d'hôte (« no hostkeys available »). ⚠️ À vérifier sur ta version : relis `systemctl cat ssh.service` sur un clone Debian 13 (une version future pourrait ajouter une génération automatique, comme sur RHEL). Rocky 10 : les unités `sshd-keygen@.service` génèrent les clés manquantes avant `sshd.service` : SSH démarre, avec des clés propres au clone. Dans les deux cas, cloud-init est le mécanisme normal ; l'écart montre pourquoi le test (E14) vérifie l'**âge** des clés.

**6.** LVM-thin : le clone lié est un instantané thin (`lvcreate -s` du volume `base-…`), nommé `vm-<ID>-disk-N` ; la configuration du clone ne mentionne pas le template ; l'instantané est indépendant de son origine : Proxmox laisse supprimer la base, le clone survit (provenance perdue). ZFS : `zfs clone` de l'instantané `base-…@__base__`, nommé `base-<T>-disk-N/vm-<ID>-disk-M` dans la configuration ; le clone dépend de l'instantané : Proxmox refuse de supprimer la base tant qu'un clone existe (et ZFS aussi).

**7. Réponse b.** L'image dorée est reconstruite au-dessus de 9001, qui est lui-même reconstruit (et supprimé par `-force`) à chaque version de Debian : un clone lié de 9001 en dépendrait. a) Faux : un clone lié peut devenir un template (il garde sa base). c) Faux : un clone complet est plus lent. d) Faux : `full_clone = false` existe.

**8.** Dans l'ordre : (1) l'installation n'est pas terminée ou a échoué (console) ; (2) l'agent QEMU ne répond pas (`qm guest cmd <VMID> ping` en root : paquet absent, service non démarré, option `agent` de la VM désactivée) ; (3) l'agent répond mais SSH échoue (journal `PACKER_LOG=1` : connexion refusée → flux ou sshd ; authentification refusée → compte ou mot de passe du *preseed*, `ssh_username`). Avec l'agent présent, `qm guest cmd <VMID> network-get-interfaces` donne aussi l'adresse que Packer utilise : est-ce la bonne interface (`vm_interface`) ?

**9.** Niveaux définis par l'ABI x86-64 : v1 (SSE2), v2 (SSE4.2, POPCNT…), v3 (AVX2, BMI1/2, FMA, MOVBE…), v4 (AVX-512). RHEL 10 a relevé sa base à v3 pour les gains de performance du code compilé. Proxmox propose `x86-64-v2-AES` par défaut pour qu'une VM migre entre des hôtes de générations différentes ; `host` expose tout le processeur réel : meilleures performances, mais migration à chaud seulement vers un hôte identique (sinon instructions manquantes sur la destination).

**10.** Le noyau RHEL ne livre plus le pilote du contrôleur LSI 53C895A émulé (`sym53c8xx`) : sans pilote, pas de disque, dracut attend puis abandonne. Debian livre ce pilote dans son noyau générique : le même changement y fonctionnerait. L'initramfs contient le minimum pour monter la racine ; un initramfs *hostonly* (défaut de dracut sur RHEL) ne contient que les pilotes du matériel **présent lors de sa génération** : même un pilote livré par le noyau manquerait si le matériel change (piège classique en migration de VMs ; remède : `dracut -f --no-hostonly` ou régénération après changement).

**11.** Pas incohérent : `blame` mesure chaque unité séparément ; `cloud-init` attend le réseau (il est ordonné après `systemd-networkd-wait-online`) et les deux durées se chevauchent largement. On regarde `systemd-analyze critical-chain` (qui attendait qui), `systemd-analyze plot` pour le parallélisme, et `cloud-init analyze blame` pour savoir ce que cloud-init a fait de ses 25 s.

**12. Réponse b.** Par défaut, la configuration du *user-data* est fusionnée au-dessus de celle du *vendor-data* clé par clé : une même clé (`packages`) est **remplacée**. a) Faux par défaut : la fusion de listes existe, mais doit être demandée (`merge_how`). c) Faux : c'est l'inverse, le *vendor-data* est la couche basse. d) Faux : pas d'erreur de schéma.

**13.** `package_upgrade: true` dans le *user-data* généré : au premier démarrage, `apt update` puis mise à niveau complète (module `package_update_upgrade_install`, étape *final*). Coût : de une à plusieurs minutes, variable, dépendant des dépôts (échec si le dépôt est injoignable) et une VM qui change pendant ses premières minutes. À garder pour une VM durable créée à partir d'une image ancienne ; à désactiver pour l'éphémère (tests, Molecule) et quand l'image est reconstruite chaque semaine.

**14.** Démarrer un template le modifie (identité générée, journaux, état cloud-init) et, pour un template à clones liés, modifierait ce que voient les clones : Proxmox l'interdit d'ailleurs. Pour « vérifier », on clone (lié, jetable) et on teste le clone : c'est exactement `tests/tester-image.sh`.

**15.** Une image ISO 9660 (format `nocloud`, étiquette de volume `cidata`) contenant `meta-data`, `user-data`, `network-config` et `vendor-data` (format `configdrive2` : étiquette `config-2`, arborescence `openstack/latest/`). Sans démarrer la VM : `qm cloudinit dump <VMID> user|network|meta` (ce que Proxmox générerait), ou le volume `vm-<ID>-cloudinit` lui-même (`pvesm path`, puis `isoinfo -l -i …` ou montage en lecture seule sur l'hôte).

**16.** SMBIOS : fabricant (`QEMU`), produit (`Standard PC (Q35 + ICH9, 2009)` ou `i440FX`), numéro de série et UUID (champ `smbios1` de Proxmox), version du micrologiciel ; l'agent expose au contraire des informations **de** la VM vers l'hôte (interfaces, systèmes de fichiers, utilisateurs). `ds-identify` lit le DMI parce que de nombreux nuages s'y signalent (`OpenStack Nova` dans le produit, numéros de série spécifiques) : c'est rapide et sans réseau. Une VM Proxmox dont on réglerait `smbios1` pour imiter OpenStack serait détectée comme telle et irait chercher un service de métadonnées sur `169.254.169.254` : délais, puis échec, si rien n'y répond.

**Grille d'auto-évaluation** : 1 point par question (QCM : bonne réponse et justification des fausses), 16 au total. Moins de 11 : refais M03-E04 et M03-E21 (cloud-init), M03-E16 (stockage) et M03-E22 (démarrage).
