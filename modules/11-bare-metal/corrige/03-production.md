# Module 11 — Palier 3 : Production — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les fichiers de référence sont dans [`fichiers/`](fichiers/) : `M11-E13/` (rôle `pxe` en HTTPS, construction d'iPXE, gabarits sans secret, entrées de la matrice des flux, ADR-0111), `M11-E14/` (fichier de réponse PVE, rôle `pve_reponses`, préparation), `M11-E15/` (orchestrateur, inventaire des serveurs bare-metal, accueil Ansible, pipeline), `M11-E16/` (ADR-0110), `M11-E18/` (inventaire Redfish). Ils prolongent ceux des paliers 1 et 2 : les **noms de variables** de tes rôles `pxe` et `kea_dhcp4` et les sous-commandes de ton `outils/netbox-provision.py` (M11-E06) peuvent différer ; aligne-les plutôt que de tout remplacer.

Commandes représentatives de iPXE (amont 2.0), Kea 3.0, nginx 1.26, Proxmox VE 9.2, NetBox 4.6, iLO 4 2.x. Les sorties exactes varient.

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) :
- prise en charge des signatures **ECDSA** (racine et intermédiaire step-ca en P-256) par la version d'iPXE construite : le script de construction refuse une source sans code ECDSA, mais seul l'essai `imgfetch https://…` dans le shell iPXE le prouve ; si ta version échoue, essaie la dernière étiquette de l'amont et signale-le ;
- construction automatique d'une archive cpio par iPXE autour d'un fichier dont la ligne de commande est un chemin (`initrd <url> /preseed.cfg`), en BIOS **et** en UEFI (passage de plusieurs initrd au noyau par le micrologiciel UEFI) ;
- valeur `!` de `passwd/user-password-crypted` dans le preseed (compte `admin` verrouillé) ;
- nom exact du fichier et arguments du script iPXE produits par `prepare-iso --pxe-loader ipxe` (PVE 9.2), et format du corps JSON envoyé par l'installateur (le service ne dépend que de la présence des MAC) ;
- privilège `VM.GuestAgent.FileRead` (PVE 9) et point d'API `agent/file-read` utilisés par l'orchestrateur ;
- emplacement exact du réglage « IPMI/DCMI over LAN » dans l'interface de l'iLO 4 selon la version du firmware, et présence de `IPMI.ProtocolEnabled` dans `Managers/1/NetworkService` ;
- structure de la ressource `FirmwareInventory` d'un iLO 4 (clé `Current`, tableaux `Name`/`VersionString`).

---

### M11-E13 — Sécuriser la chaîne de provisioning

**Solution**

*1. Analyse* — modèle : [`fichiers/M11-E13/medisphere/docs/provisioning/securite-chaine.md`](fichiers/M11-E13/medisphere/docs/provisioning/securite-chaine.md). Le point clé : HTTPS ne protège qu'**à partir du chargeur iPXE**. DHCP et TFTP restent usurpables ; ce qui les compense ici, c'est l'isolation du VLAN 60, et en production la surveillance DHCP des commutateurs et Secure Boot.

*2. Certificat de `pxe01`* — rôle [`pxe`](fichiers/M11-E13/ansible/roles/pxe/) (version E13), [`host_vars/pxe01/certificats.yml`](fichiers/M11-E13/ansible/inventories/lab/host_vars/pxe01/certificats.yml), [`playbooks/pxe01.yml`](fichiers/M11-E13/ansible/playbooks/pxe01.yml). Ordre du premier passage : le rôle `pxe` installe nginx avec le seul port 80 (le site HTTPS n'est rendu que si le certificat existe) ; `certificats_acme` arrête nginx, laisse le client `step` répondre au défi HTTP-01 sur le port 80, émet le certificat (chaîne complète), redémarre nginx ; le playbook rappelle `nginx.yml`, qui rend cette fois le serveur 443. Flux (fragment [`pare_feu-vlan60.yml`](fichiers/M11-E13/ansible/inventories/lab/host_vars/gw01/pare_feu-vlan60.yml)) : `pxe01` → `ca01:443` et `ca01` → `pxe01:80`.

```
admin@adm01:~$ openssl s_client -connect 10.10.60.10:443 -servername pxe01.par1.medisphere.internal </dev/null 2>/dev/null \
  | grep -E '^ *[0-9] s:|^ *i:|Verify return code'
 0 s:CN = pxe01.par1.medisphere.internal
   i:O = MédiSphère, CN = MédiSphère Intermediate CA
 1 s:O = MédiSphère, CN = MédiSphère Intermediate CA
   i:O = MédiSphère, CN = MédiSphère Root CA
Verify return code: 0 (ok)
admin@adm01:~$ curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' http://pxe01.par1.medisphere.internal/boot.ipxe
301 https://pxe01.par1.medisphere.internal/boot.ipxe
```

*3. iPXE de confiance* — [`ipxe/construire-ipxe.sh`](fichiers/M11-E13/provisioning/ipxe/construire-ipxe.sh) et [`ipxe/version.env`](fichiers/M11-E13/provisioning/ipxe/version.env). La VM jetable 2117 est créée par OpenTofu (état `provisioning`, ressource conditionnelle activée le temps de l'exercice, clone lié de l'image dorée `current`, `vsandbox`, étiquette `env-m11`) :

```
admin@adm01:~$ git ls-remote --tags https://github.com/ipxe/ipxe.git 'v2.0.0^{}'     # commit à reporter dans version.env
admin@adm01:~$ openssl x509 -in /usr/local/share/ca-certificates/medisphere-root-ca.crt -noout -fingerprint -sha256
admin@adm01:~$ scp ~/src/provisioning/ipxe/{construire-ipxe.sh,version.env} \
      /usr/local/share/ca-certificates/medisphere-root-ca.crt m11-build:
admin@m11-build:~$ sudo apt-get install -y git gcc make binutils perl liblzma-dev openssl
admin@m11-build:~$ ./construire-ipxe.sh medisphere-root-ca.crt
…
# iPXE v2.0.0 (…), racine 3f9c…
5d1e…  undionly.kpxe
a07b…  ipxe.efi
admin@adm01:~$ scp -r m11-build:sortie-ipxe ~/artefacts/ipxe-v2.0.0-ms1
```

Publication dans le registre de paquets génériques du projet (jeton jamais en argument : en-têtes lus depuis une substitution de processus), puis destruction de la VM 2117 :

```
admin@adm01:~$ for f in undionly.kpxe ipxe.efi; do
    curl -sS --fail -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<~/.config/workbook/gitlab-admin.token)") \
      --upload-file ~/artefacts/ipxe-v2.0.0-ms1/$f \
      "https://git01.par1.medisphere.internal/api/v4/projects/plateforme%2Fprovisioning/packages/generic/ipxe/v2.0.0-ms1/$f"
  done
```

Les empreintes vont dans [`host_vars/pxe01/pxe.yml`](fichiers/M11-E13/ansible/inventories/lab/host_vars/pxe01/pxe.yml) : le rôle télécharge les binaires **sur le contrôleur** (`pxe01` ne joint plus la forge), vérifie l'empreinte, les copie, puis vérifie à nouveau l'empreinte du fichier en place. Test dans le shell iPXE de `bm01` (Ctrl-B) :

```
iPXE> dhcp
iPXE> imgfetch https://pxe01.par1.medisphere.internal/boot.ipxe
https://pxe01.par1.medisphere.internal/boot.ipxe... ok
iPXE> imgstat
boot.ipxe : 789 bytes [script]
iPXE> imgfetch https://ipxe.org/
https://ipxe.org/... Permission denied (https://ipxe.org/0216eb3c)
```

Le second essai **doit** échouer : la racine du projet iPXE n'est plus de confiance (c'est le but de `TRUST=`). Le code exact varie ; décode-le sur `https://ipxe.org/err/<code>`.

*4. Chaîne en HTTPS* — [`ipxe/boot.ipxe`](fichiers/M11-E13/provisioning/ipxe/boot.ipxe), gabarits [`ipxe-debian.ipxe.j2`](fichiers/M11-E13/provisioning/gabarits/ipxe-debian.ipxe.j2) et [`ipxe-rocky.ipxe.j2`](fichiers/M11-E13/provisioning/gabarits/ipxe-rocky.ipxe.j2). Dans Kea, la classe iPXE (option 77) désigne `https://pxe01.par1.medisphere.internal/boot.ipxe` (variable de la classe dans `group_vars/role_dns/kea.yml`). Le preseed est ajouté à l'initrd par iPXE (`initrd …/preseed/bm01.cfg /preseed.cfg`) : d-i lit `/preseed.cfg` à la racine de son initrd avant même le réseau. Le kickstart aussi (`inst.ks=file:/ks.cfg`) : dracut le lit dans l'initrd. Pour Rocky, le dépôt officiel est en HTTPS : Anaconda vérifie le certificat avec les autorités publiques qu'il connaît. Pour Debian, le miroir reste en HTTP : `Release` est signé par l'archive, et les clés de l'archive sont **dans l'initrd** que nous avons servi en HTTPS ; les paquets sont vérifiés par leurs sommes. La racine MédiSphère et la clé publique d'`adm01` sont, elles aussi, remises par iPXE (`/medisphere-root-ca.crt`, `/authorized_keys`) et copiées par `late_command`.

*5. Secrets* — [`preseed.cfg.j2`](fichiers/M11-E13/provisioning/gabarits/preseed.cfg.j2), [`kickstart.ks.j2`](fichiers/M11-E13/provisioning/gabarits/kickstart.ks.j2). Choix retenu : **aucun** mot de passe. root verrouillé (`passwd/root-login false` ; `rootpw --lock`), `admin` verrouillé (`!` ; `user --lock`), connexion par la clé d'`adm01`, sudo par une règle `90-admin` (comme les images dorées), accès console de secours par le compte `secours` qu'apporte le rôle `base` au premier passage d'Ansible. Historique :

```
admin@adm01:~/src/provisioning$ git log -p --all -S 'password' -- preseed kickstart gabarits | grep -E '^\+.*(passw|rootpw|--password)'
```

Un mot de passe en clair trouvé dans l'historique est compromis : il ne sert plus (comptes verrouillés), on le note au registre des secrets comme « révoqué », et on décide (avec Sophie) s'il faut réécrire l'historique (perturbant pour tous les clones) ; ne réécris pas sans décision.

*6. VLAN 60* — fragment [`pare_feu-vlan60.yml`](fichiers/M11-E13/ansible/inventories/lab/host_vars/gw01/pare_feu-vlan60.yml) : la règle « lab vers Internet » ne s'applique plus au VLAN 60, qui ne sort qu'en 80/443 ; `pxe01` seul joint `ca01:443`. Vérification depuis `pxe01` :

```
admin@pxe01:~$ dig +short @10.10.20.10 deb.debian.org | head -n 1          # DNS : oui
admin@pxe01:~$ timeout 3 bash -c '</dev/tcp/10.10.10.10/22' && echo ouvert || echo fermé   # adm01 : fermé
admin@pxe01:~$ timeout 3 bash -c '</dev/tcp/10.10.20.12/443' && echo ouvert || echo fermé  # git01 : fermé
admin@pxe01:~$ timeout 3 bash -c '</dev/tcp/10.10.20.11/443' && echo ouvert || echo fermé  # ca01 : ouvert (pxe01 seul)
```

*7. iLO* — dans l'interface de l'iLO 4 (compte administrateur), section *Administration → Access Settings* (selon le firmware : *Security → Access Settings*), décocher **IPMI/DCMI over LAN** et appliquer (l'iLO peut redémarrer : le serveur, non). Vérification en Redfish, identifiants hors de la ligne de commande (`curl -K-` lit sa configuration sur l'entrée standard) :

```
admin@adm01:~$ set -a; source ~/.config/workbook/ilo-hp01.env; set +a
admin@adm01:~$ printf 'user = "%s:%s"\n' "$ILO_USER" "$ILO_PASSWORD" \
  | curl -sS -K- --cacert "$ILO_CACERT" "https://$ILO_HOST/redfish/v1/Managers/1/NetworkService/" | jq '.IPMI'
{ "Port": 623, "ProtocolEnabled": false }
admin@adm01:~$ IPMI_PASSWORD="$ILO_PASSWORD" ipmitool -I lanplus -H "$ILO_HOST" -U "$ILO_USER" -E chassis status
Error: Unable to establish IPMI v2 / RMCP+ session
```

(`--cacert "$ILO_CACERT"` si tu as épinglé le certificat de l'iLO en M11-E07 ; rien si tu l'as remplacé par un certificat step-ca.) Compte `wb-redfish` : seul *Login* reste coché ; *Virtual Power and Reset*, donné en M11-E08 pour l'essai facultatif de redémarrage, est retiré (plus aucun exercice ne pilote l'alimentation de `hp01`). Fiche CHG-1230 : avant, après, retour arrière (recocher la case).

*8. ADR-0111* — modèle : [`ADR-0111-confiance-demarrage-reseau.md`](fichiers/M11-E13/medisphere/docs/socle/adr/ADR-0111-confiance-demarrage-reseau.md).

*9.* Réinstallation de `bm01` et `bm03` : la console montre `https://pxe01.par1.medisphere.internal/…` pour chaque téléchargement après le chargeur, et `pxe-access.log` sur `pxe01` les requêtes correspondantes.

**Vérification** : `lab/bin/check 11 13`.

**Explications**

iPXE n'a pas de magasin de certificats : ses racines de confiance sont compilées. `TRUST=` remplace la racine par défaut (celle du projet iPXE, qui signe les certificats « croisés » distribués par `ca.ipxe.org`) ; `CERT=` ajoute des certificats disponibles **sans** leur faire confiance (utile pour un intermédiaire que le serveur n'enverrait pas). Avec notre seule racine, un binaire iPXE refuse tout serveur HTTPS hors de la PKI MédiSphère, y compris Internet : c'est voulu, la chaîne n'a rien à y faire. La vérification TLS d'iPXE est complète (chaîne, nom, dates) ; elle dépend donc de l'**horloge** de la machine (RTC), et d'un éventuel répondeur OCSP désigné par le certificat (step-ca n'en met pas par défaut).

**Alternatives**
- `EMBED=` un script dans le binaire (`dhcp` puis `chain https://…/boot.ipxe`) : la classe iPXE de Kea devient inutile et la boucle de chargement disparaît ; mais le moindre changement d'URL impose une reconstruction.
- Signature des images (`imgtrust`, `imgverify`) avec une clé de signature de code dédiée : protège même en HTTP et contre un `pxe01` compromis en lecture ; coût : signer chaque rendu dans la CI (ADR-0111, option 3).
- Remplacer le certificat autosigné de l'iLO par un certificat step-ca (CSR générée par l'iLO, signée par `step ca sign`, importée) : supprime l'épinglage, au prix d'un renouvellement manuel (l'iLO 4 ne parle pas ACME).

**Pièges classiques**
- Donner la racine avec `CERT=` au lieu de `TRUST=` : le binaire fonctionne… et fait toujours confiance à la racine d'iPXE.
- Construire avec une version d'iPXE sans ECDSA : « Permission denied » sur tous les téléchargements HTTPS, alors que `curl` depuis `adm01` réussit.
- Oublier que `pxe01` doit **renouveler** son certificat (flux `pxe01` → `ca01:443`) : tout casse au bout de 30 jours.
- Mettre le preseed en HTTPS dans `url=` : d-i ne connaît pas la racine MédiSphère et échoue ; `debian-installer/allow_unauthenticated_ssl` désactive la vérification : interdit.
- Garder l'empreinte d'un mot de passe dans un fichier servi « parce que ce n'est qu'une empreinte » (voir E17, question 6).
- Couper IPMI sur IP depuis une session IPMI, ou modifier les comptes de l'iLO sans garder une session administrateur ouverte.

**En production chez MédiSphère**
Secure Boot sur les serveurs physiques (shim signé, iPXE 2.0), surveillance DHCP (*DHCP snooping*) et VLAN de provisioning sans autre équipement que les ports des serveurs en installation ; reconstruction d'iPXE dans le pipeline (VM éphémère, construction reproductible, empreinte comparée à celle d'une seconde construction) ; alerte si le binaire servi diffère de l'empreinte du code.

---

### M11-E14 — Provisionner un nœud Proxmox VE par le réseau

**Solution**

*1. Fichier de réponse* — [`pve-answer/bm04.toml`](fichiers/M11-E14/provisioning/pve-answer/bm04.toml), dérivé de celui de `hv01` : `fqdn`, réseau `from-answer` avec l'adresse réservée dans NetBox, interface choisie par sa MAC (`filter.ID_NET_NAME_MAC`), `root-password-hashed` (empreinte yescrypt d'un mot de passe aléatoire conservé dans le Vault), `root-ssh-keys` (clé d'`adm01`).

```
admin@adm01:~$ mkpasswd -m yescrypt          # demande le mot de passe sans écho ; l'empreinte seule va dans le fichier
admin@adm01:~/src/provisioning$ proxmox-auto-install-assistant validate-answer pve-answer/bm04.toml
The answer file was parsed successfully, no errors found!
```

*2. Service de réponse* — rôle [`pve_reponses`](fichiers/M11-E14/ansible/roles/pve_reponses/) : programme Python sans dépendance ([`serveur.py`](fichiers/M11-E14/ansible/roles/pve_reponses/files/serveur.py)), unité durcie (utilisateur dédié, `ProtectSystem=strict`, `IPAddressAllow=localhost`), emplacement nginx `location = /pve/reponse` (POST seulement, VLAN 60 et `adm01`), jeton en Vault ([`host_vars/pxe01/pve_reponses.yml`](fichiers/M11-E14/ansible/inventories/lab/host_vars/pxe01/pve_reponses.yml)). Essais depuis `adm01` (jeton lu dans un fichier temporaire 600, jamais en argument) :

```
admin@adm01:~$ curl -sS -o /dev/null -w '%{http_code}\n' -X POST https://pxe01.par1.medisphere.internal/pve/reponse -d '{}'
403
admin@adm01:~$ curl -sS -o /dev/null -w '%{http_code}\n' -X POST -H @"$HOME/.cache/entete-pve" \
    https://pxe01.par1.medisphere.internal/pve/reponse -d '{"network_interfaces":[{"mac":"aa:bb:cc:dd:ee:ff"}]}'
404
```

(`~/.cache/entete-pve`, 600, contient `Authorization: Bearer <nom>:<secret>` ; supprime-le après l'essai.)

*3. Préparation* — [`outils/preparer-pve-pxe.sh`](fichiers/M11-E14/provisioning/outils/preparer-pve-pxe.sh) : vérifie la chaîne de `pxe01`, calcule l'empreinte SHA-256 de **son certificat** et appelle :

```
proxmox-auto-install-assistant prepare-iso proxmox-ve_9.2-1.iso --fetch-from http \
  --url https://pxe01.par1.medisphere.internal/pve/reponse --cert-fingerprint <EMPREINTE> \
  --answer-auth-token <nom>:<secret> --pxe-loader ipxe --output ~/pve-pxe/9.2
```

`--pxe-loader ipxe` implique `--pxe` : la sortie est un **dossier** contenant `vmlinuz`, `initrd.img` et un script pour iPXE. L'outil n'accepte le jeton qu'en argument : exception documentée dans le script et au registre des secrets (outil lancé sur `adm01`, jeton à usage unique renouvelé après l'installation). Dépôt sur `pxe01` : [`playbooks/pve-installateur.yml`](fichiers/M11-E14/ansible/playbooks/pve-installateur.yml) (`/srv/http/pve/9.2/`, réservé au VLAN 60 et à `adm01` par le rôle `pxe`).

*4. Script iPXE* — [`gabarits/ipxe-pve.ipxe.j2`](fichiers/M11-E14/provisioning/gabarits/ipxe-pve.ipxe.j2) : recopie les arguments de la ligne `kernel` du script produit par l'outil (ils dépendent de la version de l'ISO). Mémoire de `bm04` portée à 8 Go et disque à 32 Go dans `~/src/infra` (`tofu plan` montre une modification en place, pas un remplacement), puis démarrage par la chaîne (statut `staged` + `pxe_action=installer` si l'orchestrateur de E15 est déjà en place, sinon rendu manuel du script de `bm04`).

*5. Vérification du nœud* :

```
admin@adm01:~$ ssh root@<IP-BM04> pveversion
pve-manager/9.2.x/… (running kernel: 6.17…)
admin@adm01:~$ ssh root@<IP-BM04> cat /etc/pve/pve-root-ca.pem > /tmp/bm04-ca.pem
admin@adm01:~$ curl -sS -o /dev/null -w '%{http_code}\n' --cacert /tmp/bm04-ca.pem https://bm04.par1.medisphere.internal:8006/
200
```

Le premier `ssh root@…` présente une clé inconnue : compare son empreinte à celle affichée sur la console de `bm04` (agent QEMU absent sur un nœud fraîchement installé) avant d'accepter.

*6. Renouvellement* — modèle : [`docs/provisioning/pve-pxe.md`](fichiers/M11-E14/medisphere/docs/provisioning/pve-pxe.md). L'empreinte épinglée est celle du **certificat**, renouvelé tous les 20 jours environ : l'initrd se prépare au moment de l'installation et ne se garde pas.

*7. Nettoyage* : `tofu apply -replace=<adresse de bm04>` avec la mémoire et le disque d'origine (VM vide, même MAC), NetBox `bm04` → `planned`, `ansible-playbook playbooks/pve-installateur.yml -e pve_version=9.2 -e pve_etat=absent`, nouveau jeton dans le Vault, rôle `pve_reponses` réappliqué.

**Vérification** : `lab/bin/check 11 14`.

**Explications**

L'installateur PXE de Proxmox n'est pas un installateur réseau au sens de d-i : l'initrd **contient** l'ISO entière (environ 1,5 Go), chargée en mémoire par iPXE puis montée en mémoire par l'installateur. D'où la mémoire de la VM (plusieurs fois la taille de l'initrd) et l'intérêt de l'UEFI (pas de limite de chargement en mémoire basse). Le fichier de réponse est obtenu par un POST : l'installateur décrit la machine (DMI, interfaces et MAC, disques) ; le serveur peut donc choisir la réponse sur n'importe quel critère, ce que fait un service minimal en Python.

**Alternatives**
- `--fetch-from iso` : un fichier de réponse dans l'initrd, donc un initrd par machine : simple, mais secret (empreinte) servi à quiconque télécharge l'initrd.
- Source de l'URL par DHCP (option 250) ou par l'enregistrement TXT `proxmox-auto-installer.<domaine>` : un seul initrd pour toutes les machines, l'URL vient de Kea.
- Installer Debian 13 par preseed puis ajouter les paquets Proxmox (méthode documentée « Install Proxmox VE on Debian ») : chemin unique avec les autres serveurs, mais plus long et moins standard pour le support.

**Pièges classiques**
- Laisser `bm04` à 2 Go : chargement interrompu ou panique du noyau, sans message explicite côté iPXE.
- Épingler l'empreinte de la **clé** (ou d'un ancien certificat) : refus après le renouvellement suivant.
- Servir `/pve/` à tout le lab : l'initrd contient le jeton.
- Oublier le *kebab-case* (avertissements en 9.1+, refus à terme).
- Garder la VM : un nœud Proxmox imbriqué inutilisé consomme 8 Go de `pve01`.

**En production chez MédiSphère**
Nœuds PVE installés par le même pipeline que les autres serveurs (orchestrateur de E15 avec un gabarit `pve`), jeton par lot d'installation, script `[first-boot]` qui enregistre le nœud dans NetBox et le prépare à rejoindre le cluster (la jonction reste une décision humaine).

---

### M11-E15 — De la source de vérité au serveur en service

**Solution** (une conception possible)

*Conception* — modèle : [`docs/provisioning/orchestration.md`](fichiers/M11-E15/medisphere/docs/provisioning/orchestration.md). Deux idées portent tout :
1. **La machine ne rappelle personne.** Les installateurs **éteignent** la machine en fin d'installation (`d-i debian-installer/exit/poweroff boolean true`, `poweroff` du kickstart) ; l'orchestrateur, qui pilote déjà l'alimentation, observe l'état `stopped`. Aucun jeton sur la machine.
2. **Ce qui est servi à une MAC dépend de NetBox.** Un champ personnalisé `pxe_action` (`installer` ou `local`) sur les équipements, écrit par l'orchestrateur seul ; le rendu (M11-E06, à modifier) sert le gabarit d'installation si `status = staged` **et** `pxe_action = installer`, et [`ipxe-local.ipxe.j2`](fichiers/M11-E13/provisioning/gabarits/ipxe-local.ipxe.j2) (`exit` : le micrologiciel passe au disque) dans **tous** les autres cas. Un équipement `active` ne peut donc jamais se réinstaller, et une machine `planned` qui démarre par accident non plus.

*Outils* — [`outils/provisionner.py`](fichiers/M11-E15/provisioning/outils/provisionner.py) (états, délais, reprise, journal NetBox, code de retour), [`outils/verifier-rendu.sh`](fichiers/M11-E15/provisioning/outils/verifier-rendu.sh) (validation du rendu dans le pipeline), [`.gitlab-ci.yml`](fichiers/M11-E15/provisioning/.gitlab-ci.yml) (job manuel `provisionner`, variable `EQUIPEMENT`, `resource_group`), [`playbooks/accueil-bm.yml`](fichiers/M11-E15/ansible/playbooks/accueil-bm.yml) et [`inventories/lab/netbox-bm.yml`](fichiers/M11-E15/ansible/inventories/lab/netbox-bm.yml) (équipements `serveur-bm` aux statuts `staged` et `active`, groupe `role_serveur_bm`).

*Premier contact SSH sans confiance aveugle* — après l'installation, la clé d'hôte n'est pas encore signée. Plutôt que `StrictHostKeyChecking=accept-new`, l'orchestrateur lit `/etc/ssh/ssh_host_ed25519_key.pub` **dans** la machine par l'agent QEMU (API Proxmox `agent/file-read`, canal qui ne passe pas par le réseau du VLAN 60) et exige que `sshd` présente cette clé-là. Les VMs `bm*` ont l'option `agent` activée dans OpenTofu et le paquet `qemu-guest-agent` est installé par les deux gabarits. Sur un serveur physique, ce canal serait la console série de l'iLO.

*Droits* (registre des secrets) :

```
root@pve01:~# pveum role add WBProvision --privs "VM.Audit,VM.PowerMgmt,VM.GuestAgent.FileRead"
root@pve01:~# pveum user add wb-provision@pve --comment "Orchestrateur de provisioning (M11-E15)"
root@pve01:~# for v in 2112 2113 2114 2115; do pveum acl modify /vms/$v --users wb-provision@pve --roles WBProvision; done
root@pve01:~# pveum user token add wb-provision@pve provision --privsep 0 --expire "$(date -d '+90 days' +%s)"
```

> ⚠️ Ces commandes ne touchent que des objets nouveaux de `pve01` (un rôle, un compte, des ACL sur les VMs 2112-2115). Retour arrière : `pveum user delete wb-provision@pve` puis `pveum role delete WBProvision`.

Le secret s'affiche une seule fois : il va dans `~/.config/workbook/pve-provision.env` (600, format de `pve-api.env`) et dans la variable protégée de type fichier `PVE_ENV_FICHIER` du projet. NetBox (compte `<MOI>`) : champ personnalisé `pxe_action` (sélection `installer`/`local`, objets *dcim.device*) ; permission « svc-automatisation équipements bm » : *dcim.device* (*view*, *change*), contrainte `{"role__slug": "serveur-bm"}` ; *extras.journalentry* (*add*, *view*).

*Démonstration* :

```
admin@adm01:~/src/provisioning$ set -a; source ~/.config/workbook/netbox-provision.env; set +a   # NETBOX_URL, NETBOX_TOKEN
admin@adm01:~/src/provisioning$ uv run outils/provisionner.py bm01
10:02:11 installation : début (statut staged, script iPXE d'installation)
10:19:40 installation : terminée (machine éteinte)
10:21:02 premier démarrage : SSH ouvert, nom résolu
10:21:15 clé d'hôte : clé ED25519 lue par l'agent QEMU
10:23:48 accueil Ansible : racine, clé d'hôte signée, rôle base
10:23:50 mise en service : bm01 en service (10.10.60.101)
admin@adm01:~/src/provisioning$ uv run outils/provisionner.py bm01; echo $?
10:24:30 bm01 : déjà en service, rien à faire
0
admin@adm01:~$ ssh -o StrictHostKeyChecking=yes bm01.par1.medisphere.internal hostname   # aucune question
admin@adm01:~/src/ansible$ uv run ansible-inventory -i inventories/lab/netbox-bm.yml --graph role_serveur_bm
```

(`netbox-provision.env` est un nom d'exemple : utilise le fichier où tu ranges le jeton `svc-automatisation` en écriture.) En CI : *Build → Pipelines → Run pipeline* sur `main`, variable `EQUIPEMENT=bm03`, puis le job manuel `provisionner`. Redémarrage de contrôle : `qm reboot 2112` → la console montre « en service, démarrage sur le disque local », puis le système installé.

**Vérification** : `lab/bin/check 11 15`.

**Explications**

Un orchestrateur fiable se décrit par ses **états** et les **conditions observables** de ses transitions. Les conditions choisies ici sont toutes observables sans la coopération de la machine : alimentation, port, DNS, clé lue hors réseau. Chaque transition écrit dans NetBox **avant** l'action qui en dépend (`pxe_action=local` avant de rallumer), ce qui rend la reprise sûre : un arrêt brutal de l'orchestrateur laisse un état cohérent et lisible.

**Alternatives**
- Rappel de la machine en fin d'installation (`late_command`/`%post` qui appelle un point d'entrée sur `pxe01`, sans jeton, qui bascule le script de la MAC) : plus rapide (pas d'arrêt), mais une machine du VLAN peut alors basculer le démarrage d'une autre : il faut l'authentifier, et on retombe sur le problème du secret.
- Ordre de démarrage modifié par l'API (disque en premier après installation) : marche pour les VMs, pas pour un serveur physique dont on ne pilote pas le micrologiciel de façon portable (Redfish `Boot.BootSourceOverrideTarget` le permet pour **un** démarrage : c'est l'équivalent physique, à retenir pour la production).
- Déclenchement par NetBox (*event rule* → webhook → API de déclenchement de GitLab) : supprime le bouton, mais une erreur de saisie dans NetBox lance alors une installation.

**Pièges classiques**
- `exit` d'iPXE en UEFI : l'entrée de démarrage suivante doit exister ; et l'installateur Rocky place sa propre entrée en tête de l'ordre UEFI (voir `orchestration.md`, limites).
- Passer `active` **avant** l'accueil : un serveur « en service » sans clé signée ni rôle `base`.
- `accept-new` au premier contact : une machine usurpée sur le VLAN 60 serait accueillie et signée par la CA SSH.
- Relancer l'orchestrateur sur une machine `active` qui ne répond plus et la réinstaller « pour voir » : perte de données ; c'est un incident, pas un provisioning.
- Oublier de redonner le rendu « local » **déployé** sur `pxe01` avant de rallumer : réinstallation en boucle.

**En production chez MédiSphère**
Même chaîne, alimentation par Redfish (`ComputerSystem.Reset`, `BootSourceOverrideTarget=Pxe` pour un seul démarrage) ; files d'installation parallèles bornées ; tableau de bord des équipements `staged` depuis plus d'une heure ; test d'installation complet de chaque gabarit dans le pipeline (VM éphémère sur le VLAN 60).

---

### M11-E16 — ADR : MAAS, Tinkerbell ou chaîne maison ?

**Solution**

Modèle : [`ADR-0110-outil-de-provisioning.md`](fichiers/M11-E16/medisphere/docs/socle/adr/ADR-0110-outil-de-provisioning.md). La décision du modèle (chaîne maison, MAAS retiré, Tinkerbell en veille) n'est pas la seule défendable : une équipe qui prévoit des centaines de serveurs, plusieurs constructeurs et peu de temps de développement peut retenir MAAS, à condition de dire comment NetBox et MAAS se partagent la vérité (MAAS fait foi pour l'état de déploiement, NetBox pour l'intention, synchronisation à écrire) et ce que devient Kea sur le VLAN de provisioning.

**Grille d'auto-évaluation**

| Critère | Attendu |
|---|---|
| Contexte | Volumes, sites, constructeurs, équipe, exigences HDS ; mesures du module (temps, gestes, incidents) |
| Comparaison | Tableau sur les critères de l'énoncé, sans case « oui/non » vide de sens ; « qui fait foi » et « qui sert le DHCP » traités en premier |
| Honnêteté | Ce que l'option retenue ne fait pas (découverte, tests matériels, effacement, interface) est écrit, avec qui le fera |
| Décision | Tranchée, avec le sort des deux autres options et des conditions de révision mesurables |
| Conséquences | Négatives listées, actions avec responsable ou module (dont `maas01` et `wb-maas` au mini-projet) |
| Forme | MADR, deux pages au plus, liens vers ADR-0060 et ADR-0111 |

**Explications**

L'erreur la plus fréquente est de comparer des listes de fonctions. Les vrais coûts d'un outil de provisioning sont ailleurs : une **seconde source de vérité** (la base de MAAS) qu'il faut synchroniser, un **second DHCP** qui ne coexiste pas avec celui du socle, une **dépendance d'exécution** (snap, PostgreSQL, Kubernetes) qu'il faut sauvegarder, superviser et mettre à jour.

**Pièges classiques**
- Retenir Tinkerbell pour sa modernité alors que Kubernetes n'est pas en production : la chaîne de provisioning dépendrait de la plateforme qu'elle sert à construire.
- Oublier la reprise après sinistre : avec quoi réinstalle-t-on le premier serveur si l'outil lui-même est perdu (final F5) ?

**En production chez MédiSphère**
L'ADR est relue à la première palette réelle : temps mesurés sur du vrai matériel, contrôleurs des deux constructeurs, effacement certifié exigé ou non par l'hébergeur HDS.

---

### M11-E17 — Questions de production : provisioning

1. **Sur le VLAN 60 après E13.** Un attaquant peut toujours répondre au DHCP plus vite que Kea, désigner son serveur TFTP et servir **son** chargeur : la machine exécute alors n'importe quoi (rien ne vérifie le chargeur sans Secure Boot). Il ne peut plus, une fois **notre** iPXE chargé, se faire passer pour `pxe01` (pas de certificat MédiSphère), ni lire les fichiers de réponse en clair sur le fil (HTTPS), ni modifier les paquets (signatures). Mesures réseau : *DHCP snooping* (seuls les ports de confiance répondent au DHCP), *port security* / 802.1X sur les ports du VLAN de provisioning, ACL qui limitent le TFTP à `pxe01`.
2. **b.** iPXE vérifie la chaîne jusqu'à une racine de confiance ; l'intermédiaire n'est pas compilé, il est **présenté** par `pxe01` (chaîne complète). a : inutile, la racine n'a pas changé ; c : nécessaire seulement si le certificat de `pxe01` a été émis par l'ancien intermédiaire révoqué — mais ce n'est pas une action « iPXE » ; d : jamais.
3. Parce que tout ce qui est sur la machine (fichier de réponse, disque, mémoire) est lisible par quiconque y accède pendant ou après l'installation, et qu'un jeton d'écriture permettrait de modifier NetBox ou d'allumer d'autres machines. L'orchestrateur observe ce qu'il contrôle : la machine s'**éteint** en fin d'installation, il lit l'état d'alimentation.
4. Mécanisme 1 : le script iPXE servi à la MAC d'un équipement `active` est `exit` (dépend de NetBox et du rendu). Mécanisme 2, indépendant : l'ordre de démarrage met le disque en premier après l'installation (UEFI : l'installateur le fait souvent ; physique : Redfish `BootSourceOverrideTarget` pour un démarrage réseau **ponctuel** au lieu d'un ordre permanent). Un troisième garde-fou : `boot.ipxe` rend la main au micrologiciel pour toute MAC inconnue.
5. Selon l'étape : avant le chargeur, la machine réessaie puis passe au disque (vide : arrêt sur « no bootable device ») ; pendant le téléchargement du noyau/initrd, échec iPXE et retour au micrologiciel ; installateur Debian ou Rocky lancé : il n'a plus besoin de `pxe01` (fichier de réponse dans l'initrd, paquets depuis les miroirs) et **termine** ; machines installées : aucun effet. Redondance : le besoin réel est une reprise rapide (reconstruction par le code en 15 minutes) plutôt qu'une haute disponibilité ; un second `pxe01` compliquerait le TFTP (adresse unique dans l'offre) pour un service qui ne sert que pendant les installations.
6. **b.** Une empreinte se casse hors ligne (dictionnaire, force brute) ; avec SHA-512 *crypt* et un mot de passe faible, c'est rapide ; yescrypt ralentit, ne protège pas un mot de passe faible. a : faux ; c : d-i accepte SHA-512 et yescrypt ; d : faux, l'empreinte d'un compte utilisateur sert à `sudo` et à la console. D'où le choix de E13 : pas de mot de passe du tout.
7. `apt` vérifie la signature de `Release` (ou `InRelease`) avec les clés de l'archive Debian présentes dans l'initrd, puis la somme de chaque fichier d'index et de chaque paquet. Le transport n'a pas à être de confiance. Le maillon critique est **la clé de l'archive** dans l'initrd : si l'initrd était servi en HTTP et remplacé, la garantie tomberait ; c'est pourquoi l'initrd vient de `pxe01` en HTTPS.
8. Deux serveurs DHCP autoritaires sur le même domaine de diffusion se disputent les clients : offres contradictoires, adresses en double, classes PXE différentes, machines qui démarrent un coup sur MAAS un coup sur `pxe01`. Au palier 2 : sous-réseau 60 retiré de Kea **et** relais du VLAN 60 coupé sur les passerelles avant d'activer le DHCP de MAAS, avec fiche de changement et retour arrière, puis l'inverse en fin de M11-E10.
9. IPMI 2.0 : l'échange RAKP envoie, à quiconque connaît un nom de compte, une empreinte HMAC calculée avec le mot de passe, cassable hors ligne ; le chiffrement « cipher 0 » (authentification nulle) existe sur certains contrôleurs ; comptes par défaut et anonymes ; pas de TLS. Redfish passe par HTTPS avec authentification de session : on garde le protocole qui se protège, on coupe l'autre.
10. **a.** Secure Boot n'exécute qu'une image signée par une clé de `db`. b : la lenteur ne provoque pas un refus ; c : 0x0000 est le code BIOS, un client UEFI annonce 0x0007 ; d : le certificat n'intervient qu'après le chargement d'iPXE.
11. À remonter : état réel observé (statut d'installation, date, version du système installé, numéro de série, versions de firmware, MAC découvertes) dans des champs **distincts** de l'intention ou dans le journal. À ne pas écrire automatiquement : l'intention (rôle, site, adresse attribuée, nom), que seul un humain ou le code d'infrastructure fixe (ADR-0060 : un seul écrivain par information, la réalité à côté de l'intention).
12. Filtre NetBox sur `firmware_ilo` (et le modèle) : liste immédiate des équipements dont la version est inférieure à la version corrigée. Il manque : la correspondance automatique « avis de sécurité → versions vulnérables » (source lisible par machine du constructeur), la fraîcheur garantie de l'inventaire (`inventaire_maj` surveillé), et le même inventaire pour tous les composants (cartes, contrôleurs de stockage).

**Grille** : une réponse est juste si elle donne le mécanisme **et** la conséquence d'exploitation ; pour les QCM, la justification des mauvaises options compte autant que la bonne lettre.

---

### M11-E18 — Inventaire matériel et firmware

**Solution**

*1. Exploration* (identifiants hors de la ligne de commande, comme en E13) :

```
admin@adm01:~$ set -a; source ~/.config/workbook/ilo-hp01.env; set +a
admin@adm01:~$ ilo() { printf 'user = "%s:%s"\n' "$ILO_USER" "$ILO_PASSWORD" \
    | curl -sS -K- --cacert "$ILO_CACERT" "https://$ILO_HOST$1"; }
admin@adm01:~$ ilo /redfish/v1/ | jq '{Systems, Managers, Chassis}'
admin@adm01:~$ ilo /redfish/v1/Systems/1/ | jq '{Model, SerialNumber, BiosVersion, ProcessorSummary, MemorySummary, Oem: (.Oem.Hp.links // .Oem.Hp.Links)}'
admin@adm01:~$ ilo /redfish/v1/Managers/1/ | jq '{FirmwareVersion}'
admin@adm01:~$ ilo /redfish/v1/Systems/1/FirmwareInventory/ | jq '.Current | map_values(map({Name, VersionString}))'
```

| Information | Chemin | Champ |
|---|---|---|
| Numéro de série | `Systems/1` | `SerialNumber` |
| Version du BIOS (ROM système) | `Systems/1` | `BiosVersion` |
| Version de l'iLO | `Managers/1` | `FirmwareVersion` |
| Processeurs | `Systems/1/Processors/<n>` | `Model`, `Socket` |
| Mémoire | `Systems/1/Memory/<n>` (iLO 4 : extension HPE selon le firmware) | `DeviceLocator`/`Name`, `CapacityMiB`/`SizeMB`, `PartNumber` |
| Firmwares | lien `FirmwareInventory` (section `Oem.Hp` de `Systems/1`) | `Current.<composant>[].VersionString` |

*2. NetBox* (compte `<MOI>`) : champs personnalisés `firmware_bios`, `firmware_ilo` (texte) et `inventaire_maj` (date) sur *dcim.device* ; permissions de `svc-automatisation` : *dcim.device* (*view*, *change*) avec la contrainte `[{"role__slug": "serveur-bm"}, {"name": "hp01"}]` (une liste de contraintes est une **disjonction**) ; *dcim.inventoryitem* (*view*, *add*, *change*, *delete*) avec `{"device__name": "hp01"}`. Essai de refus :

```
admin@adm01:~$ curl -sS -o /dev/null -w '%{http_code}\n' -X PATCH -H "Content-Type: application/json" \
    -H @<(printf 'Authorization: Bearer %s\n' "$(<~/.config/workbook/netbox-auto.token)") \
    -d '{"comments": "essai de droits"}' https://nbx01.par1.medisphere.internal/api/dcim/devices/<ID-DE-PVE01>/
403
```

*3. Script* — [`outils/inventaire-redfish.py`](fichiers/M11-E18/provisioning/outils/inventaire-redfish.py) : session Redfish (jeton `X-Auth-Token`, refermée en fin de passage), navigation par liens, champs absents tolérés, éléments d'inventaire marqués `discovered` (seuls ceux-là sont mis à jour ou supprimés), `--dry-run` qui sort en code 3 s'il reste des écarts.

```
admin@adm01:~/src/provisioning$ uv run outils/inventaire-redfish.py --dry-run
hp01 : <MODÈLE> série CZ…, BIOS J… , iLO 2.82 Feb 06 2023
  firmware : iLO 2.82 Feb 06 2023
  firmware : System ROM J… 
  écart : serial : '' → 'CZ…'
  écart : élément d'inventaire à créer : CPU 1
…
admin@adm01:~/src/provisioning$ uv run outils/inventaire-redfish.py && uv run outils/inventaire-redfish.py --dry-run; echo $?
…
0
```

*4. Planification* — job `inventaire` du pipeline, déclenché par une planification hebdomadaire (*Build → Pipeline schedules*), variables protégées `NETBOX_TOKEN` et `ILO_ENV` (type fichier) ; flux `runner01` → iLO 443 (fragment de E13). Échec : le job échoue (code ≠ 0), notification de la forge.

```yaml
inventaire:
  stage: valider
  script:
    - uv sync --frozen
    - uv run outils/inventaire-redfish.py
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule" && $TACHE == "inventaire"
```

*5. Comparaison* — modèle : [`docs/provisioning/firmware.md`](fichiers/M11-E18/medisphere/docs/provisioning/firmware.md).

**Vérification** : `lab/bin/check 11 18`.

**Explications**

Redfish est une API **hypermédia** : chaque ressource donne les liens vers les suivantes. Un client qui suit les liens à partir de `/redfish/v1/` fonctionne sur un iLO 4, un iLO 5 ou un autre constructeur ; un client qui code `Systems/1` en dur casse au premier serveur multi-nœuds. Les extensions des constructeurs (`Oem`) portent souvent l'information la plus utile (inventaire des firmwares sur l'iLO 4, standardisé ensuite dans `UpdateService/FirmwareInventory`).

**Alternatives**
- `ipmitool fru` et `ipmitool mc info` : numéro de série et version du contrôleur, mais IPMI sur IP est coupé (E13).
- `dmidecode` sur `hp01` lui-même : exact, mais demande un accès au système qui porte PBS, et ne voit pas le firmware de l'iLO.
- Outils du constructeur (HPE OneView, iLO Amplifier) : inventaire et conformité des firmwares intégrés, payants.

**Pièges classiques**
- Écraser à chaque passage des éléments d'inventaire saisis à la main (pas de marqueur `discovered`).
- Ouvrir une session Redfish par appel sans la refermer : l'iLO 4 a un nombre de sessions limité, et refuse ensuite toute connexion (y compris la tienne dans le navigateur).
- `verify=False` « parce que l'iLO est autosigné » : c'est ce que l'épinglage de M11-E07 évite.
- Donner à `svc-automatisation` le droit de modifier **tous** les équipements.

**En production chez MédiSphère**
Collecte quotidienne sur tous les contrôleurs, alerte si `inventaire_maj` dépasse 8 jours, rapprochement automatique avec les avis de sécurité du constructeur, et mises à jour de firmware planifiées par lots avec la fenêtre de maintenance de chaque site.
