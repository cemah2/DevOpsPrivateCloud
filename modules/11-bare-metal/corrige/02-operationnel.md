# Module 11 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Comme au palier 1 : `fichiers/M11-EXX/` reproduit les projets (`ansible/`, `infra/`, `provisioning/`, `medisphere/`), on superpose dans l'ordre des exercices ; `*.extrait` = morceau à intégrer, `*.exemple` = modèle sans valeur réelle.

**Ce qui a été testé, ce qui ne l'a pas été.**
- *netbox-provision.py* : 16 tests pytest (contrôle, refus, rendu déterministe, suppression d'une machine retirée, lecture d'un fichier d'environnement sans l'exécuter, pagination vers un autre hôte refusée, code de sortie), ruff propre ; kickstart rendu validé par `ksvalidator -v RHEL10` (pykickstart 3.78) ; réservations rendues lues par le gabarit Kea et la configuration complète validée par `kea-dhcp4 -t` (Kea 3.0.4). `uv.lock` produit avec uv 0.12.
- *alim.sh* : exécuté contre une imitation HTTPS de l'API Proxmox (états, idempotence, `cycle` qui attend l'arrêt, cible introuvable, refus sur `hp01`) ; *redfish.sh* : transmission des identifiants par `curl -K -` vérifiée (guillemets et barres obliques inverses échappés).
- *MAAS 3.7* : paramètres du pilote `proxmox` lus dans son code source (`src/provisioningserver/drivers/power/proxmox.py`, branche 3.7) ; lecture de la clé d'API sur l'entrée standard par `maas login … -` lue dans `src/maascli/cli.py`. *Image Ubuntu* : signature de `SHA256SUMS` vérifiée avec la clé `D2EB 4462 6FDD C30B 513D 5BB7 1A5D 6C4C 7DB8 7C81` le 8 octobre 2026.
- *OpenTofu 1.13.1* : `tofu validate` et `tofu fmt` de `envs/provisioning` (avec `maas01.tf`). *Ansible* : ansible-lint 26 en profil `production` sur le rôle `maas`. *Shell* : ShellCheck et `bash -n` sur tous les scripts.

**Non rejoués sur un lab réel** : NetBox 4.6 (création des objets `dcim.mac-addresses`, filtres utilisés), l'iLO 4 (chemins Redfish, fiche `Oem.Hp.Privileges` des comptes, comportement d'ipmitool selon le privilège), MAAS de bout en bout (initialisation, magasin de certificats vu par le snap, mise en service et déploiement de VMs Proxmox, API des évènements). Ils sont signalés « ⚠️ À vérifier sur ton lab ».

---

### M11-E06 — Des installations décrites par NetBox

**Solution**

Fichiers (dans `plateforme/provisioning`) : [`donnees/bm.yml`](fichiers/M11-E06/provisioning/donnees/bm.yml) et [`outils/declarer-bm.py`](fichiers/M11-E06/provisioning/outils/declarer-bm.py) (réception) ; [`outils/netbox-provision.py`](fichiers/M11-E06/provisioning/outils/netbox-provision.py), [`parametres.yml`](fichiers/M11-E06/provisioning/parametres.yml), gabarits [`ipxe-hote.ipxe.j2`](fichiers/M11-E06/provisioning/gabarits/ipxe-hote.ipxe.j2), [`rocky10.ks.j2`](fichiers/M11-E06/provisioning/gabarits/rocky10.ks.j2), [`kea-reservations.yml.j2`](fichiers/M11-E06/provisioning/gabarits/kea-reservations.yml.j2) ; tests [`tests/test_netbox_provision.py`](fichiers/M11-E06/provisioning/tests/test_netbox_provision.py) et [`tests/donnees/netbox.json`](fichiers/M11-E06/provisioning/tests/donnees/netbox.json) ; [`pyproject.toml`](fichiers/M11-E06/provisioning/pyproject.toml), [`uv.lock`](fichiers/M11-E06/provisioning/uv.lock), [`.gitlab-ci.yml`](fichiers/M11-E06/provisioning/.gitlab-ci.yml). Dans `plateforme/ansible` : [`kea.yml`](fichiers/M11-E06/ansible/inventories/lab/group_vars/role_dns/kea.yml) (lit les réservations), exemple de fichier généré [`kea_reservations_prov.yml`](fichiers/M11-E06/ansible/inventories/lab/group_vars/role_dns/kea_reservations_prov.yml), configuration rendue [`kea-dhcp4-vlan60.rendu.json`](fichiers/M11-E06/ansible/kea-dhcp4-vlan60.rendu.json).

1. **Modéliser.** Un script idempotent plutôt qu'un import CSV : il se rejoue (une palette de plus = quatre lignes dans `bm.yml`), il ne crée pas de doublon, et il ne touche **pas** au statut d'un équipement existant (le statut appartient à la chaîne et aux humains). Ordre imposé par les références : étiquette, rôle, type, plateformes → équipement → interface `eno1` → objet MAC (rattaché à l'interface) → `primary_mac_address` de l'interface → IP (rattachée à l'interface, avec `dns_name`) → `primary_ip4` de l'équipement.
   ```
   admin@adm01:~/src/provisioning$ uv run outils/declarer-bm.py --simulation
   + extras/tags/ {'slug': 'env-m11'}
   + dcim/device-roles/ {'slug': 'serveur-bm'}
   …
   admin@adm01:~/src/provisioning$ uv run outils/declarer-bm.py
   …
   NetBox à jour.
   ```
   Numéro de série : un identifiant stable du « matériel » — ici `PVE-VM-<VMID>` ; l'UUID SMBIOS de la VM (`qm config <VMID> | grep smbios1`) ferait aussi l'affaire, et c'est ce qu'un vrai serveur présente au BMC.
2. **Ouvrir la lecture.** Dans *Admin → Permissions*, la permission en lecture de M06-E10 (`automatisation-referentiel`) reçoit en plus : `dcim | device`, `dcim | interface`, `dcim | MAC address`, `dcim | platform`, `dcim | device role`. Rien en écriture : le jeton en lecture (`netbox-ansible.env`) suffit à la génération, et l'écriture du statut `active` (M11-E15) se décidera à part.
   ```
   admin@adm01:~$ ( set -a; . ~/.config/workbook/netbox-ansible.env; set +a
       curl -s -H @<(printf 'Authorization: Bearer %s\n' "$NETBOX_TOKEN") \
         'https://nbx01.par1.medisphere.internal/api/dcim/devices/?role=serveur-bm&brief=true' | jq .count )
   4
   ```
   (Le jeton n'apparaît ni dans `ps` — l'en-tête passe par un descripteur — ni dans l'historique.) La lecture de ses propriétés (`users/tokens/?key=…`, avec le jeton des checks) montre `write_enabled: false`.
3. **Générer.** Trois étapes séparées :
   - `lire_netbox()` : équipements du rôle `serveur-bm` du site `par1`, interface `eno1`, MAC primaire (champ `primary_mac_address`, avec repli sur `mac_address`), IP primaire, puis son `dns_name` (la représentation brève de `primary_ip4` ne le contient pas : une requête par adresse) ;
   - `controler()` : fonction **pure** (testée sans réseau) qui sépare valides et refus — nom `bmNN`, MAC valide et unique, IP dans 10.10.60.0/24 et dans .100-.199 et unique, plate-forme connue, `dns_name` = nom + domaine ; un refus d'une machine `planned` rend le code de sortie 1 ;
   - `rendre()` : dans un dossier **neuf** à chaque fois (une machine retirée de NetBox ne laisse aucun fichier), tri par nom (rendu déterministe : deux exécutions donnent les mêmes octets), Jinja2 en `StrictUndefined` (une variable oubliée est une erreur, pas une chaîne vide dans un kickstart).
   ```
   admin@adm01:~/src/provisioning$ uv run outils/netbox-provision.py rendre \
       --kea-ansible ~/src/ansible/inventories/lab/group_vars/role_dns/kea_reservations_prov.yml
   [rendu]  bm01   planned    debian-13  02:4d:53:60:00:01 10.10.60.101    → installation
   [rendu]  bm02   planned    rocky-10   02:4d:53:60:00:02 10.10.60.102    → installation
   [rendu]  bm03   planned    debian-13  02:4d:53:60:00:03 10.10.60.103    → installation
   [rendu]  bm04   planned    rocky-10   02:4d:53:60:00:04 10.10.60.104    → installation
   Bilan : 4 machine(s) rendue(s), 0 refusée(s), 7 fichier(s) dans /home/admin/src/provisioning/rendu.
   ```
   Debian n'a pas de fichier par machine : le nom passe par la ligne de commande du noyau (`hostname=bm01 domain=…`), et le preseed générique suffit. Rocky en a un (`network … --hostname=`), rendu depuis `gabarits/rocky10.ks.j2`. Les valeurs publiques communes (URL, version de Rocky, empreintes, clé publique) sont dans `parametres.yml`.
   Pipeline : `ruff`, `pytest`, puis rendu sur `tests/donnees/netbox.json` et `outils/verifier.sh` sur le dépôt **et** le rendu (en-têtes iPXE, mots de passe, debconf, `ksvalidator`, ShellCheck). Le pipeline ne joint pas NetBox : il teste le code et les gabarits, pas les données.
4. **Appliquer.**
   - Réservations : le fichier `kea_reservations_prov.yml` est **généré mais versionné** dans `plateforme/ansible` (MR, relecture du diff, pipeline). `kea.yml` le lit : `reservations: "{{ kea_reservations_prov | default([]) }}"` dans le sous-réseau 60. Kea 3.0 accepte les réservations dans la plage dynamique (comportement par défaut) et ne donne pas une adresse réservée à un autre client.
   - Fichiers : `outils/publier.sh` (le rendu `rendu/http/` est fusionné aux fichiers du dépôt, puis `rsync --delete` dossier par dossier).
   - DNS : `medictl dns sync --dry-run` puis `medictl dns sync` (M06-E15) publient les quatre `bmNN.par1.medisphere.internal` et leurs PTR (zone inverse `10.10.in-addr.arpa`). ⚠️ À vérifier sur ton outil de M06-E15 : s'il ne lit que les adresses rattachées à des VMs, étends son filtre aux interfaces d'équipements.
   ```
   admin@adm01:~$ for n in 1 2 3 4; do dig +short @10.10.20.10 bm0$n.par1.medisphere.internal; dig +short @10.10.20.10 -x 10.10.60.10$n; done
   ```
5. **Démontrer.** Effacer le disque proprement : `qm stop 2112`, puis `tofu apply -replace='proxmox_virtual_environment_vm.bm["bm01"]'` dans `envs/provisioning` (la VM est recréée à l'identique, disque vide, **même MAC**) — c'est le geste qui correspond à « un serveur neuf ». `qm set 2112 --delete scsi0` puis un nouveau disque ferait diverger la VM de son code (OpenTofu verrait la différence au prochain plan). Puis `outils/alim.sh bm01 allumer` (ou `qm start 2112`) : iPXE trouve `ipxe/mac-02-4d-53-60-00-01.ipxe`, affiche « bm01 : installation de Debian 13… », l'installateur reçoit `hostname=bm01`, Kea donne 10.10.60.101 (réservation), la machine s'éteint en fin d'installation. Idem `bm02` (Rocky, kickstart `bm02.ks`).
6. **Clore.** NetBox : `bm01` et `bm02` en `active` ; `netbox-provision.py rendre` → leurs scripts deviennent « disque local » ; `publier.sh` ; `alim.sh bm01 allumer` → menu de la machine, `exit`, Debian démarre sur son disque. Contrôle : `qm guest cmd 2112 get-host-name` → `bm01`.
7. **Refus.** MAC de `bm01` recopiée sur l'objet MAC de `bm03` (ou une seconde MAC égale) :
   ```
   [rendu]  bm02   …
   [refus]  bm01   active     MAC 02:4d:53:60:00:01 en double dans NetBox
   [refus]  bm03   planned    MAC 02:4d:53:60:00:01 en double dans NetBox
   Au moins une machine « planned » est refusée : corrige NetBox avant de publier.
   ```
   (code 1). Les **deux** machines sont refusées : l'outil ne sait pas laquelle a raison. Aucun script n'est rendu pour elles ; si l'on publiait quand même, `bm03` arriverait au menu (défaut : disque local) au lieu d'être installée avec l'identité d'une autre.

**Explications**

- **Qui écrit quoi.** NetBox = l'intention (saisie par la réception, statut par la chaîne). `plateforme/provisioning` = la transformation (code et gabarits, relus en MR). `plateforme/ansible` = la configuration de Kea (un fichier généré, mais relu et tracé comme le reste). `pxe01` = un miroir de publication, reconstructible à tout instant. Un fichier n'a qu'un écrivain : c'est ce qui rend la chaîne rejouable.
- **Pourquoi pas l'API de Kea (`reservation-add`).** Le hook `host_cmds` est libre depuis Kea 2.7.7 (donc dans Kea 3.0), mais ses commandes écrivent dans une **base d'hôtes** (MySQL ou PostgreSQL) ; sans elle, une réservation ajoutée en mémoire disparaît au prochain passage d'Ansible qui réécrit la configuration, et il faudrait la pousser sur les deux pairs. Le fichier rendu par Ansible garde un seul écrivain et un historique. ⚠️ À vérifier sur ta version : l'option `operation-target` de `host_cmds` (mémoire / base) décrite dans l'ARM de Kea 3.0 ; elle ne change pas la question de la propriété.
- **Pourquoi des équipements et pas des VMs dans NetBox.** La chaîne doit traiter le lab comme le parc physique : un serveur a un numéro de série, une interface physique, une MAC saisie à la réception, une plate-forme décidée ; une VM NetBox serait rattachée au cluster `pve01` et entrerait dans la synchronisation Proxmox → NetBox de M06-E11 (qui créerait des doublons). Le commentaire du type d'équipement le dit.

**Alternatives**
- *Config templates de NetBox* (`render-config`) : le gabarit vit dans NetBox (ou dans un *data source* Git synchronisé), le rendu se fait par l'API. Une dépendance de moins, mais le rendu échoue quand NetBox est en panne, et la validation (`ksvalidator`) doit se faire ailleurs.
- *Ansible comme générateur* (`netbox.netbox.nb_lookup` + `template`) : tout dans un seul outil ; mais les tests unitaires du contrôle et du rendu sont plus lourds qu'avec pytest.
- *Un webhook NetBox* (changement de statut → pipeline de génération) : supprime l'étape manuelle de 3.1 ; c'est la direction de M11-E15.

**Pièges classiques**
- `mac_address` de l'interface en **écriture** sur NetBox ≥ 4.2 : le champ est en lecture seule (il reflète la MAC primaire) ; il faut créer l'objet MAC puis le désigner.
- MAC en majuscules dans NetBox, minuscules dans iPXE (`${netX/mac:hexhyp}`) : script `mac-02-4D-…` jamais trouvé. L'outil normalise en minuscules.
- Le rendu qui **ajoute** sans jamais supprimer : un serveur décommissionné garde un script « installer » sur `pxe01` ; s'il redémarre un jour sur le VLAN 60, il se réinstalle.
- Un générateur qui écrit les réservations directement dans `/etc/kea/` : effacées au prochain passage d'Ansible, et différentes entre `dns01` et `dns02`.
- Oublier de passer en `active` avant de rallumer : réinstallation (c'est exactement ce que M11-E15 automatise).
- `requests` sans `verify=` : il utilise le magasin de `certifi`, qui ne contient pas la racine MédiSphère (« certificate verify failed »). L'outil passe le magasin du système.

**En production chez MédiSphère**

Saisie de la réception par import du bon de livraison (CSV du constructeur), contrôle croisé MAC/numéro de série par le BMC avant l'installation (Redfish, M11-E18), génération déclenchée par webhook et publication par le pipeline, journal de chaque installation (qui, quand, quelle version des gabarits) dans un champ personnalisé de l'équipement.

---

### M11-E07 — IPMI et Redfish : découvrir l'iLO de `hp01`

**Solution**

Fichiers : [`ilo-hp01.env.exemple`](fichiers/M11-E07/ilo-hp01.env.exemple), [`outils/redfish.sh`](fichiers/M11-E07/provisioning/outils/redfish.sh), [`pare_feu.yml.extrait`](fichiers/M11-E07/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait).

1. **Repérage** (*Information → Overview* et *Administration → Licensing*, *Access Settings*) : firmware 2.xx (2.82 conseillé, PLAN §6 ; Redfish existe à partir de 2.30), licence *iLO Standard* le plus souvent sur ces machines. La licence Standard ne donne ni la console graphique à distance une fois le système démarré, ni le média virtuel par script : ce sont des fonctions *iLO Advanced*. Redfish, IPMI, capteurs, journaux et alimentation sont disponibles en Standard. *IPMI/DCMI over LAN* : activé par défaut sur iLO 4.
2. **Compte.** *Administration → User Administration → New* : `wb-redfish`, privilège **Login** seulement (en iLO 4, « Login » est implicite pour tout compte ; les cases sont *Administer User Accounts*, *Remote Console Access*, *Virtual Power and Reset*, *Virtual Media*, *Configure iLO Settings* : toutes décochées). Justification : la lecture Redfish (inventaire, capteurs, journaux) et IPMI au niveau `USER` ne demandent rien d'autre ; *Virtual Power and Reset* donnerait le droit d'éteindre `hp01` (PBS, QDevice) à un compte dont le mot de passe vit dans un fichier sur `adm01` : non, et pas « au cas où ». Mot de passe :
   ```
   admin@adm01:~$ install -m 600 /dev/null ~/.config/workbook/ilo-hp01.env
   admin@adm01:~$ mdp="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"   # pas de guillemet ni de barre oblique inverse
   admin@adm01:~$ { printf 'ILO_HOST="%s"\nILO_NOM_TLS="%s"\nILO_USER="wb-redfish"\n' '<IP-ILO-HP01>' '<NOM-TLS-ILO>'; printf 'ILO_PASSWORD="%s"\n' "$mdp"; } > ~/.config/workbook/ilo-hp01.env
   admin@adm01:~$ unset mdp
   ```
   Pour le saisir dans l'iLO, ouvre le fichier dans un éditeur (ou `less`) et copie la valeur : elle ne passe ni par l'historique ni par un argument.
   (`printf` est une commande interne du shell : la valeur n'apparaît pas dans `ps`, et la ligne de l'historique ne contient que `"$mdp"`.) Ligne au registre des secrets : compte, où, qui, rotation (90 jours), révocation (suppression du compte dans l'iLO).
3. **Flux** : deux lignes de transit (`adm01` → `<IP-ILO-HP01>` TCP 443 et UDP 623), voir l'extrait. La sortie vers le LAN maison est traduite : l'iLO voit l'adresse WAN de la passerelle maître.
4. **Confiance.**
   ```
   admin@adm01:~$ openssl s_client -connect <IP-ILO-HP01>:443 -showcerts </dev/null 2>/dev/null \
                    | openssl x509 > ~/m11/e07/ilo.pem
   admin@adm01:~$ openssl x509 -in ~/m11/e07/ilo.pem -noout -subject -issuer -serial -dates -ext subjectAltName -fingerprint -sha256
   subject=CN = ILOCZ12345678, …
   issuer=CN = Default Issuer (Do not trust), O = Hewlett Packard Enterprise, …
   serial=…
   sha256 Fingerprint=AB:CD:…
   admin@adm01:~$ ssh pbs01 "openssl s_client -connect <IP-ILO-HP01>:443 </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256"
   sha256 Fingerprint=AB:CD:…                         # même empreinte, autre chemin réseau
   admin@adm01:~$ install -m 600 ~/m11/e07/ilo.pem ~/.config/workbook/ilo-hp01.pem
   ```
   Le second chemin part de `hp01`, sur le LAN de l'iLO, sans passer par la bordure du lab : un intermédiaire placé sur la bordure ou dans le lab ne peut pas falsifier les deux. Le numéro de série affiché par *Administration → Security → SSL Certificate* confirme. Pourquoi une connexion par l'adresse échoue : le certificat porte un **nom** (CN, parfois sans SAN), pas l'adresse IP ; `curl https://<IP>` refuse (« no alternative certificate subject name matches »). Contournement sans désactiver la vérification : `--resolve <NOM-TLS-ILO>:443:<IP-ILO-HP01>` et l'URL avec le nom. Le certificat n'est pas autosigné (émetteur « Default Issuer ») : curl l'accepte quand même comme ancre parce qu'il active la validation de chaîne partielle (*partial chain*, défaut depuis 7.68) ; l'ancre est alors **ce** certificat, et le nom est vérifié. ⚠️ À vérifier sur ton lab : si ton iLO présente un certificat sans CN exploitable, régénère-le (changer le nom d'hôte de l'iLO le régénère) ou passe directement au remplacement par un certificat de la PKI (M11-E13).
5. **Redfish.** `redfish.sh` : `GET` seulement, chemin qui commence par `/redfish/v1`, fichier d'accès en 600 vérifié, identifiants par `curl -K -`, `--cacert` + `--resolve`. Relevés :
   ```
   admin@adm01:~/src/provisioning$ R=outils/redfish.sh
   admin@adm01:~/src/provisioning$ $R /redfish/v1/Systems/1/ | jq '{Model, SerialNumber, BiosVersion, PowerState, Mem: .MemorySummary.TotalSystemMemoryGiB, CPU: .ProcessorSummary}'
   admin@adm01:~/src/provisioning$ $R /redfish/v1/Chassis/1/Thermal/ | jq -r '.Temperatures[] | "\(.Name)\t\(.ReadingCelsius) °C"' ; $R /redfish/v1/Chassis/1/Thermal/ | jq -r '.Fans[] | "\(.FanName // .Name)\t\(.CurrentReading) \(.Units // "%")"'
   admin@adm01:~/src/provisioning$ $R /redfish/v1/Chassis/1/Power/ | jq '.PowerControl[0].PowerConsumedWatts'
   admin@adm01:~/src/provisioning$ $R /redfish/v1/Managers/1/ | jq -r .FirmwareVersion
   admin@adm01:~/src/provisioning$ $R '/redfish/v1/Managers/1/LogServices/IEL/Entries/' | jq -r '.Members[-5:][]["@odata.id"]'
   admin@adm01:~/src/provisioning$ $R /redfish/v1/Systems/1/ | jq '.Actions'
   {"#ComputerSystem.Reset": {"ResetType@Redfish.AllowableValues": ["On","ForceOff","ForceRestart","Nmi","PushPowerButton"], "target": "/redfish/v1/Systems/1/Actions/ComputerSystem.Reset/"}}
   ```
   (Noms des champs selon le firmware : les capteurs d'iLO 4 sont dans le schéma Redfish 1.0, les détails sous `Oem.Hp` ; les entrées de journal d'une collection se lisent une par une ou avec `$expand` selon le firmware. ⚠️ À vérifier sur ton iLO.) Aucune valeur de `ResetType` n'est essayée.
6. **IPMI.**
   ```
   admin@adm01:~$ ( set -a; . <(sed -n 's/^ILO_PASSWORD=/IPMI_PASSWORD=/p' ~/.config/workbook/ilo-hp01.env); set +a
       H=<IP-ILO-HP01>
       ipmitool -I lanplus -H $H -U wb-redfish -E -L USER chassis status
       ipmitool -I lanplus -H $H -U wb-redfish -E -L USER sdr elist
       ipmitool -I lanplus -H $H -U wb-redfish -E -L USER sel list | tail -n 5 )
   ```
   Sans `-L USER`, ipmitool demande `ADMINISTRATOR` : refus à l'ouverture de session (« Unable to establish IPMI v2 / RMCP+ session »). La variable n'existe que dans le sous-shell. Comparatif :

   | | IPMI over LAN | Redfish |
   |---|---|---|
   | Contenu | capteurs (SDR), journal (SEL), alimentation, FRU ; extensions par constructeur | tout le modèle du serveur (inventaire détaillé, firmware, réseau, stockage, journaux), actions, abonnements à des évènements |
   | Transport | UDP 623, chiffrement RMCP+ optionnel, faible | HTTPS, TLS vérifiable |
   | Authentification | RAKP : empreinte du mot de passe récupérable hors ligne par quiconque connaît un nom de compte ; « cipher 0 » sur certains BMC | HTTP basic ou session (jeton), sur TLS |
   | Automatisation | sortie texte à analyser, outil `ipmitool` | JSON, schémas publiés (DMTF), bibliothèques, Ansible (`community.general.redfish_*`) |
7. **Sécurité** (dans le journal) : IPMI 2.0 a une faiblesse **de conception** (RAKP) qu'aucun firmware ne corrige ; tout BMC qui l'expose laisse récupérer l'empreinte des mots de passe de ses comptes ; Redfish fait tout ce qu'IPMI fait. Un BMC donne l'alimentation, la console et le média virtuel : c'est un accès physique à distance, sous le système et ses protections ; il vit sur un réseau de gestion dédié, joignable seulement des postes d'administration (ici : `adm01`, par une règle explicite).

**Explications**

Le BMC a son propre micrologiciel, ses propres comptes et sa propre pile réseau : il ne profite d'aucune protection du système du serveur (pare-feu local, mises à jour de la distribution, journalisation centrale). D'où le compte dédié, le flux limité et, plus tard, la mise à jour de son firmware et la journalisation de ses évènements (M11-E18).

**Alternatives**
- *Remplacer tout de suite le certificat* par un certificat de la PKI (CSR générée par l'iLO, signée par step-ca) : vérification « normale » par nom DNS, mais iLO 4 ne fait pas ACME et le provisioner JWK `admin` est limité à 7 jours (M06-E27) : il faut un provisioner dédié aux équipements, à durée longue et à noms contraints. C'est l'objet de M11-E13.
- *Sessions Redfish* (`POST /redfish/v1/SessionService/Sessions/`, jeton `X-Auth-Token`, `DELETE` en fin) plutôt que l'authentification basique à chaque requête : moins d'expositions du mot de passe, sessions visibles dans l'iLO ; un peu plus de code.
- *`ilorest`* (outil HPE) : pratique, mais spécifique au constructeur ; Redfish « nu » marchera aussi avec les iDRAC des prochains serveurs.

**Pièges classiques**
- `curl -k` « juste pour voir » laissé dans un script.
- Épingler le certificat récupéré par **le même** chemin que celui qu'on veut protéger, sans second contrôle : on épingle peut-être celui de l'attaquant.
- `ipmitool -P <mot de passe>` : visible dans `ps` par tous les utilisateurs de `adm01`.
- Cocher *Virtual Power and Reset* « pour E08 » et l'oublier.
- Interroger l'iLO trop souvent (sondes toutes les secondes) : les BMC ont peu de ressources, l'interface web ralentit.

**En production chez MédiSphère**

Réseau de gestion dédié (VLAN OOB) avec les BMC de tous les serveurs, comptes nominatifs par LDAP/annuaire (iLO 4 sait s'y connecter) plus un compte de service par outil, IPMI over LAN désactivé, certificats de la PKI, firmware suivi (M11-E18) et évènements des BMC renvoyés vers la journalisation centrale (Redfish *EventService* ou syslog distant de l'iLO).

---

### M11-E08 — Piloter l'alimentation par API

**Solution**

Fichiers : [`outils/alim.sh`](fichiers/M11-E08/provisioning/outils/alim.sh), [`pve-maas.env.exemple`](fichiers/M11-E08/pve-maas.env.exemple).

1. **Le pilote de MAAS** (`proxmox.py`, branche 3.7) : il se connecte par jeton (`Authorization: PVEAPIToken=<utilisateur>!<jeton>=<secret>` ; si le nom du jeton n'a pas de `!`, il préfixe l'utilisateur) ou par mot de passe (`POST access/ticket`) ; il cherche la VM dans `GET cluster/resources?type=vm` par VMID **ou** par nom (`power_vm_name`), et lève « No VMs returned! Are permissions set correctly? » si la liste est vide ; `power_on` → `POST nodes/<nœud>/qemu/<vmid>/status/start` si la VM n'est pas `running` ; `power_off` → `…/status/stop` ; `power_query` lit le `status` de `cluster/resources`. `power_reset` n'est **pas** implémenté, et `can_set_boot_order = False` : MAAS ne change pas l'ordre de démarrage des VMs. Conséquences : privilèges **`VM.Audit`** (voir la VM dans `cluster/resources`) et **`VM.PowerMgmt`** (start/stop) suffisent ; les VMs doivent démarrer sur le réseau d'abord (c'est le cas depuis E03). Rien de `VM.Config.*`.
2. **Compte** (sur `pve01`) :
   ```
   root@pve01:~# pveum role add WBMaas --privs "VM.Audit VM.PowerMgmt"
   root@pve01:~# pveum user add wb-maas@pve --comment "Pilotage d'alimentation bm01-04 (M11-E08, MAAS M11-E10)"
   root@pve01:~# pveum user token add wb-maas@pve maas --privsep 1 --expire $(date -d '+90 days' +%s) --comment "outils/alim.sh, MAAS"
   ┌──────────────┬──────────────────────────────────────┐
   │ full-tokenid │ wb-maas@pve!maas                     │
   │ value        │ xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx │   ← affiché UNE fois : directement dans pve-maas.env
   root@pve01:~# for v in 2112 2113 2114 2115; do
                   pveum acl modify /vms/$v --users wb-maas@pve --roles WBMaas
                   pveum acl modify /vms/$v --tokens 'wb-maas@pve!maas' --roles WBMaas
                 done
   root@pve01:~# pveum user permissions 'wb-maas@pve!maas'
   ```
   **Les deux ACL** : avec la séparation des privilèges, les droits du jeton sont l'intersection de ceux de l'utilisateur et des siens ; sans ACL pour l'utilisateur, le jeton n'a rien. Pas de mot de passe pour `wb-maas@pve` : il ne se connecte jamais à l'interface. Preuves :
   ```
   admin@adm01:~$ ( H=$(mktemp); trap 'rm -f $H' EXIT
       . <(grep -E '^PVE_(API_URL|TOKEN_ID|TOKEN_SECRET|CACERT)=' ~/.config/workbook/pve-maas.env)
       printf 'Authorization: PVEAPIToken=%s=%s\n' "$PVE_TOKEN_ID" "$PVE_TOKEN_SECRET" > $H
       curl -s --cacert "$PVE_CACERT" -H @$H "$PVE_API_URL/cluster/resources?type=vm" | jq -r '.data[].name'
       curl -s -o /dev/null -w '%{http_code}\n' --cacert "$PVE_CACERT" -H @$H -X POST "$PVE_API_URL/nodes/<NOEUD>/qemu/2111/status/start"
       curl -s -o /dev/null -w '%{http_code}\n' --cacert "$PVE_CACERT" -H @$H -X PUT --data 'cores=4' "$PVE_API_URL/nodes/<NOEUD>/qemu/2114/config"
       curl -s -o /dev/null -w '%{http_code}\n' --cacert "$PVE_CACERT" -H @$H "$PVE_API_URL/nodes/<NOEUD>/storage" )
   bm01
   bm02
   bm03
   bm04
   403        # pxe01 : pas de droit sur /vms/2111
   403        # pas de VM.Config.CPU
   200        # … mais une liste VIDE de stockages (« data: [] ») : l'API filtre, elle ne refuse pas
   ```
   (Le `source` ne lit que les lignes `PVE_…` : le fichier n'est pas exécuté en entier, mais ses valeurs le sont par le shell ; c'est acceptable pour ton propre fichier, pas pour un fichier d'origine inconnue. Les outils, eux, ne l'exécutent pas.)
3. **L'outil** : lis [`alim.sh`](fichiers/M11-E08/provisioning/outils/alim.sh). Points clés : la VM est cherchée **par nom** dans ce que le jeton voit (comme MAAS) ; `allumer`/`eteindre` ne font rien si l'état est déjà le bon (code 0, message explicite) ; `cycle` = `stop`, **attente** de `stopped` (interrogation de `status/current`, délai maximal 120 s), puis `start` et attente de `running` ; `arreter-propre` utilise `shutdown` (ACPI) pour un système qui répond ; `hp01` n'accepte que `etat` et `types` (Redfish, par `redfish.sh`) et toute autre action sort en **3** avec la raison. Les secrets passent par `curl -K -`.
4. **Démonstration** :
   ```
   admin@adm01:~/src/provisioning$ outils/alim.sh bm03 allumer; outils/alim.sh bm03 allumer; outils/alim.sh bm03 etat; outils/alim.sh bm03 eteindre
   bm03 (2114) : allumée
   bm03 (2114) : déjà allumée
   bm03 (2114) : running
   bm03 (2114) : éteinte
   admin@adm01:~/src/provisioning$ outils/alim.sh hp01 etat; outils/alim.sh hp01 types
   hp01 : On (ProLiant …, série CZ…)
   On
   ForceOff
   ForceRestart
   Nmi
   PushPowerButton
   admin@adm01:~/src/provisioning$ outils/alim.sh hp01 cycle; echo $?
   alim.sh : hp01 porte PBS et le QDevice : action « cycle » refusée. Un redémarrage de hp01 suit la procédure annoncée (…).
   3
   ```
5. **Facultatif — redémarrage annoncé de `hp01`.** Fiche de changement (CHG-12xx), fenêtre choisie hors sauvegardes : `ssh pbs01 'proxmox-backup-manager task list'` sans tâche en cours ni planifiée dans l'heure ; prévenir (le QDevice n'existe plus après M09, mais PBS oui) ; ajouter *Virtual Power and Reset* à `wb-redfish` ; `POST /redfish/v1/Systems/1/Actions/ComputerSystem.Reset/` avec `{"ResetType": "PushPowerButton"}` (arrêt propre par ACPI, puis le même pour rallumer) plutôt que `ForceRestart` (coupure brutale d'un serveur qui écrit des sauvegardes) ; mesurer le retour (`ping 10.20.10.10` par le tunnel, `proxmox-backup-manager datastore list`) ; **retirer** le privilège ; consigner. C'est le seul cas où un `POST` part vers l'iLO, et il ne passe pas par `alim.sh`.

**Explications**

Un outil d'alimentation est une arme : son jeton doit être limité aux machines qu'il pilote (ACL par VM, pas sur le pool `lab`, qui contient tout le socle — voir ADR-0030) et à l'action « alimenter ». Un outil sûr par construction refuse ce qui ne devrait jamais lui être demandé (`hp01`), même si le compte le permettait : deux barrières valent mieux qu'une.

**Alternatives**
- *ACL sur un pool dédié* (`bm` contenant 2112-2115) : une ACL au lieu de quatre, et une VM ajoutée au pool est couverte d'office — ce qui est aussi le risque. Les ACL par VM sont plus verbeuses mais exactes.
- *Proxmox comme « faux BMC »* : il existe des émulateurs IPMI/Redfish pour les VMs (*VirtualBMC*, *sushy-tools*), mais ils ne pilotent que libvirt ou OpenStack, pas Proxmox (annexe des versions) ; d'où le pilote `proxmox` natif de MAAS.

**Pièges classiques**
- ACL seulement pour le jeton : `/cluster/resources` renvoie une liste vide, MAAS dit « Are permissions set correctly? ».
- Rôle avec `VM.Config.Options` « pour l'ordre de démarrage » : inutile (le pilote ne sait pas le changer) et dangereux (il pourrait modifier la VM).
- `cycle` sans attente : `start` sur une VM encore `running` ne fait rien, et l'outil annonce un redémarrage qui n'a pas eu lieu.
- Jeton sans expiration : il sera encore valide dans trois ans, dans un fichier oublié.

**En production chez MédiSphère**

Sur les vrais serveurs, le même outil parle Redfish aux BMC (pilote par constructeur), avec un compte de service par BMC dans Vault (M25), et chaque action d'alimentation est journalisée (qui, quand, quel serveur) et refusée sur les serveurs étiquetés « critique » sans fiche de changement.

---

### M11-E09 — Installer MAAS

**Solution**

Fichiers : [`infra/outils/creer-tpl-ubuntu2404.sh`](fichiers/M11-E09/infra/outils/creer-tpl-ubuntu2404.sh), [`envs/provisioning/maas01.tf`](fichiers/M11-E09/infra/envs/provisioning/maas01.tf) ; rôle [`maas`](fichiers/M11-E09/ansible/roles/maas/), [`playbooks/maas.yml`](fichiers/M11-E09/ansible/playbooks/maas.yml), [`group_vars/role_maas/maas.yml`](fichiers/M11-E09/ansible/inventories/lab/group_vars/role_maas/maas.yml).

1. **Template.** Le script vit dans `plateforme/infra` (`outils/`) : il crée une ressource Proxmox comme le code d'OpenTofu, et c'est là qu'on cherchera comment 9050 a été fait. Chaîne : empreinte de la clé « UEC Image Automatic Signing Key » **écrite dans le script** (`D2EB 4462 6FDD C30B 513D 5BB7 1A5D 6C4C 7DB8 7C81`, comparée entre la page *Verifying Ubuntu cloud images* et `keyserver.ubuntu.com`), téléchargement de la clé dans un trousseau temporaire, `gpg --status-fd` exige `VALIDSIG` **de cette empreinte** (une bonne signature d'une autre clé ne suffit pas), puis `sha256sum -c --ignore-missing`. Construction comme `tpl-debian13` (M00) : `qm create`, `qm disk import`, `scsi0` depuis `unused0`, lecteur cloud-init, console série, agent, `qm template`. URL : `releases/24.04/release/` redirige vers `releases/noble/release/` : le script utilise la seconde (et `--proto-redir =https`).
   ```
   root@pve01:~# STOCKAGE=local-nvme ./creer-tpl-ubuntu2404.sh
   ubuntu-24.04-server-cloudimg-amd64.img: OK
   Template 9050 tpl-ubuntu2404 créé depuis ubuntu-24.04-server-cloudimg-amd64.img (signature et empreinte vérifiées).
   ```
   Étiquettes NetBox : `role-maas` doit exister avant l'`apply` (comme `env-m11` et `role-pxe` en E02).
2. **VM** : `maas01.tf` reprend le schéma de `vm-debian` v2 (VM NetBox → interface → adresse **imposée** 10.10.60.11 → IP primaire → VM Proxmox clonée de 9050, cloud-init avec l'adresse lue dans NetBox → A et PTR).
3. **Rôle `maas`** : PostgreSQL 16 (paquet `postgresql` d'Ubuntu 24.04) ; rôle et base créés par `psql` **sur l'entrée standard** (le mot de passe n'est jamais un argument), idempotents (`\gexec` conditionnel) ; `pg_hba.conf` : une ligne `host maasdb maas 127.0.0.1/32 scram-sha-256` insérée avant les règles générales (la documentation de MAAS propose `0/0 md5` : inutile ici, région et base sont sur la même VM) ; snap `maas` au canal `3.7/stable` (`community.general.snap`) ; `maas init region+rack --database-uri "postgres://maas:…@localhost/maasdb" --maas-url http://10.10.60.11:5240/MAAS`, une seule fois (fichier témoin) ; ancres de confiance (racine MédiSphère, ancre de `pve01`) dans `/usr/local/share/ca-certificates/` puis `update-ca-certificates` et redémarrage de MAAS ; contrôle final de l'API (`/api/2.0/version/`). **Exception consignée** : l'URI contient le mot de passe le temps de `maas init` (visible dans `ps` sur `maas01`) ; `no_log` le tient hors des journaux d'Ansible ; MAAS le stocke ensuite dans sa configuration (`regiond.conf`, lisible par root). La documentation ne propose pas d'autre moyen pour la région ; l'alternative serait l'authentification `peer`/`trust` locale, que MAAS en snap ne sait pas utiliser simplement. **Pas de Molecule** : le rôle cible Ubuntu (nos instances Molecule sont des clones de l'image Debian `current`), il installe un snap de 500 Mo et ne sert qu'à une VM d'évaluation détruite en fin de module ; il passe ansible-lint, et son application sur `maas01` se vérifie par le check.
4. **Administration** :
   ```
   admin@maas01:~$ sudo maas createadmin --username <MOI> --email <MOI>@medisphere.internal
   Password:                                   # saisi au clavier, deux fois
   admin@maas01:~$ sudo maas apikey --username <MOI> | ssh adm01 'umask 077; cat > ~/.config/workbook/maas-api.key'
   admin@maas01:~$ sudo maas apikey --username <MOI> | maas login maas01 http://10.10.60.11:5240/MAAS/ -
   You are now logged in to the MAAS server at http://10.10.60.11:5240/MAAS/api/2.0/ with the profile name 'maas01'.
   admin@maas01:~$ maas maas01 maas set-config name=upstream_dns value=10.10.20.10
   admin@maas01:~$ maas maas01 maas set-config name=ntp_servers value=10.10.60.1
   admin@maas01:~$ maas maas01 maas set-config name=ntp_external_only value=true
   admin@maas01:~$ maas maas01 sshkeys create key="$(cat ~/.ssh/authorized_keys | head -n 1)"
   ```
   (`ssh adm01` depuis `maas01` suppose un agent transféré ; sinon, copie la clé par l'interface web, *Preferences → API keys*, dans le fichier ouvert avec `install -m 600 /dev/null` puis un éditeur.) La clé (`consommateur:jeton:secret`) ne s'affiche à l'écran que si tu l'y envoies.
5. **Images** : la sélection par défaut de MAAS 3.7 contient Ubuntu 24.04 amd64 ; `maas maas01 boot-resources import`, suivi par `maas maas01 boot-resources is-importing` et l'onglet *Images*. Stockage : `/var/snap/maas/common/maas/image-storage/` (quelques centaines de Mo par série et architecture, plus les noyaux) ; le rack en garde une copie pour le démarrage réseau.
6. **Lecture** : `sudo maas status` (services `regiond`, `rackd`, `bind9`, `dhcpd` (arrêté), `ntp`, `proxy`, `syslog`, `http`) ; ports : 5240 (interface et API de la région), 5241-5247 (RPC internes région ↔ rack), 5248 (HTTP du rack : images de démarrage), 69/UDP (TFTP), 53 (DNS de MAAS, `bind9`), 8000 (mandataire `squid` pour les machines déployées), 123 (NTP). Un autre serveur DHCP sur le VLAN : MAAS le **détecte** (sondes DHCP du rack, affichées dans l'onglet du VLAN) et le signale, mais n'empêche rien — c'est à nous de n'en avoir qu'un (E10).

**Explications**

MAAS se compose d'une **région** (API, base, interface, DNS) et de **racks** (DHCP, TFTP, HTTP de démarrage, au plus près des machines) ; en `region+rack`, les deux sont sur la même VM. Le snap embarque toutes ses dépendances sauf la base : la base « de test » (`maas-test-db`) est déconseillée en production parce qu'elle vit dans un autre snap, sans sauvegarde ni supervision standard.

**Alternatives**
- *Paquets Debian de MAAS* (PPA `maas/3.7`) au lieu du snap : mises à jour par apt, fichiers aux emplacements habituels ; Canonical recommande le snap.
- *Template par Packer* (`proxmox-clone` depuis l'image cloud, M03) : reproductible et versionné, plus lourd pour un template d'évaluation.

**Pièges classiques**
- `pg_hba.conf` recopié de la documentation (`0/0 md5`) : base joignable depuis tout le VLAN 60, méthode faible.
- Un mot de passe de base avec `@`, `:` ou `/` mis tel quel dans l'URI : `maas init` échoue ou se connecte ailleurs. Le rôle l'encode (`urlencode`).
- `maas login` avec la clé en argument : dans l'historique et dans `ps`.
- Oublier `--maas-url` : MAAS prend une adresse devinée, parfois celle d'une autre interface ; les machines ne joignent plus la région.
- Les rôles du socle (`base`, `ssh_durci`) appliqués tels quels à Ubuntu : des tâches propres à Debian échouent ; le playbook ne les applique que s'ils le permettent.

**En production chez MédiSphère**

Région en haute disponibilité (deux ou trois régions, PostgreSQL répliqué), un rack par salle, TLS sur l'interface (`maas config-tls enable` avec un certificat de la PKI), authentification des opérateurs par l'annuaire (Candid ou Keycloak via OIDC, M24), sauvegarde de la base (M27).

---

### M11-E10 — MAAS : inventorier et déployer des machines

**Solution**

Fichiers : [`CHG-1215-dhcp-vlan60-maas.md`](fichiers/M11-E10/medisphere/docs/provisioning/changements/CHG-1215-dhcp-vlan60-maas.md), [`pare_feu.yml.extrait`](fichiers/M11-E10/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [`cluster.fw.extrait`](fichiers/M11-E10/pve/cluster.fw.extrait).

1. **Préparer.** La fiche : lis-la, elle sert de modèle (prérequis, aller, retour, critère d'abandon, retour arrière par instantanés). Flux : une ligne dans la matrice, puis sur `pve01` (même méthode qu'en M03-E15) :
   ```
   root@pve01:~# pvesh create /cluster/firewall/ipset --name maas --comment "maas01 : pilote d'alimentation proxmox (M11-E10)"
   root@pve01:~# pvesh create /cluster/firewall/ipset/maas --cidr 10.10.60.11 --comment maas01
   root@pve01:~# pvesh create /cluster/firewall/rules --type in --action ACCEPT --source +maas --proto tcp --dport 8006 --enable 1 --comment "API pour maas01 (M11-E10)"
   admin@maas01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://<IP-PVE01>:8006/api2/json/version
   401        # TLS accepté (ancre de pve01 dans le magasin du système), authentification demandée : c'est le bon résultat
   ```
   IPSet dédié : il disparaît avec `maas01` sans qu'on relise `automation`, et la raison du flux reste lisible.
2. **Basculer** : la fiche, étapes 1 à 7. La preuve de « jamais deux serveurs » : la sonde `nmap` vide entre l'étape 3 et l'étape 6, puis une seule offre (`Server Identifier: 10.10.60.11`). Configuration du sous-réseau dans MAAS :
   ```
   admin@maas01:~$ maas maas01 subnet update 10.10.60.0/24 gateway_ip=10.10.60.1 dns_servers="10.10.20.10 10.10.20.16"
   admin@maas01:~$ maas maas01 ipranges create type=reserved start_ip=10.10.60.1 end_ip=10.10.60.99 comment="statiques, VIP, pxe01, maas01"
   admin@maas01:~$ maas maas01 ipranges create type=reserved start_ip=10.10.60.200 end_ip=10.10.60.254 comment="VIP et équipements"
   admin@maas01:~$ maas maas01 ipranges create type=dynamic start_ip=10.10.60.150 end_ip=10.10.60.199 comment="mise en service (MAAS)"
   admin@maas01:~$ RACK=$(maas maas01 rack-controllers read | jq -r '.[0].system_id')
   admin@maas01:~$ maas maas01 vlan update 0 untagged dhcp_on=True primary_rack=$RACK
   ```
   (`0` = identifiant de `fabric-0`, `untagged` = le VLAN sans étiquette de cette fabrique, vu de `maas01` ; lis-les dans `fabrics read`.)
3. **Machines.**
   ```
   admin@maas01:~$ maas maas01 machines create hostname=bm01 architecture=amd64/generic mac_addresses=02:4d:53:60:00:01 \
       power_type=proxmox power_parameters_power_address=<IP-PVE01> power_parameters_power_user=wb-maas@pve \
       power_parameters_power_token_name=maas power_parameters_power_vm_name=2112 power_parameters_power_verify_ssl=y
   ```
   puis *Machines → bm01 → Configuration → Power* : coller le secret du jeton dans le champ masqué `power_token_secret` (pas en argument). Idem `bm03`, désignée cette fois par son **nom** (`power_parameters_power_vm_name=bm03`) : le pilote cherche la VM dans `cluster/resources` par VMID ou par nom ; un VMID ne change jamais, un nom peut changer (M11-E22 s'en souviendra). `maas maas01 machine query-power-state <id>` → `off`. Mise en service : à la création, MAAS lance d'office le *commissioning* (sinon `machine commission <id>`) : il allume la VM par l'API Proxmox, elle démarre sur le réseau, reçoit un système éphémère, inventorie le matériel (`lshw`, `lsblk`, LLDP…), exécute les tests par défaut (`smartctl-validate` est sauté sur un disque virtuel, `memtester` court), remonte les résultats et l'éteint. L'inventaire de MAAS (2 CPU, 2 Gio, un disque de 20 Gio `QEMU HARDDISK`, une interface virtio avec la MAC fixée) correspond à `qm config` ; ce qu'il ajoute : modèle de CPU, numéro de série SMBIOS, firmware (BIOS/UEFI), vitesse de lien.
4. **Déployer** : `maas maas01 machine deploy <id> distro_series=noble` (ou l'interface). MAAS allume, la machine démarre sur le réseau, écrit l'image Ubuntu sur le disque (*curtin*), configure le réseau (adresse « auto » prise dans 10.10.60.100-149), la clé SSH de l'utilisateur MAAS, puis redémarre — encore sur le réseau d'abord : c'est MAAS qui répond « démarre sur ton disque ». Connexion : `ssh ubuntu@10.10.60.1xx` avec la clé enregistrée en E09 (compte `ubuntu`, pas `admin` : nos standards ne sont pas appliqués, il faudrait du cloud-init personnalisé dans `user_data`). Durées typiques sur le lab : 3-5 min de mise en service, 4-6 min de déploiement (image écrite, pas d'installateur).
5. **Rendre la main** : `machine release <id>` (sans effacement ; `erase=true quick_erase=true` pour un effacement rapide des disques), étapes « retour » de la fiche, `bm01` arrive au menu de **notre** chaîne (ou à son script par MAC). Vérification **avant** l'arrêt (`lab/bin/check 11 10`, partie MAAS), puis `sudo snap stop maas` et `qm shutdown 2116`, puis nouvelle vérification (retour à Kea).
6. **Bilan** (modèle) :

   | | Chaîne maison | MAAS |
   |---|---|---|
   | Source de vérité | NetBox | sa base PostgreSQL (à synchroniser avec NetBox) |
   | Ajout d'une machine | saisie NetBox + génération + MR | création (ou découverte automatique au premier démarrage : *enlistment*) |
   | Inventaire et tests matériels | aucun (à faire : M11-E18) | oui, intégrés, comparables entre machines |
   | Installation | installateur (10-20 min), nos standards | image (4-6 min), standards par `user_data` |
   | Systèmes | Debian, Rocky, Proxmox VE | Ubuntu (et images personnalisées) ; Debian et Rocky demandent des images construites (*packer-maas*) |
   | Réseau | Kea, nos relais, notre DNS | son DHCP, son DNS, son mandataire sur le VLAN |
   | Exploitation | des briques connues et déjà supervisées | une application de plus (base, HA, mises à jour, sauvegardes) |
   | Gestes manuels de l'essai | — | secret du jeton saisi dans l'interface, plages IP, bascule DHCP |

**Explications**

MAAS est un automate de cycle de vie : *New* (connue, pas inventoriée) → *Commissioning* → *Ready* (inventoriée, testée, éteinte, disponible) → *Allocated* → *Deploying* → *Deployed* → *Releasing* → *Ready*. Chaque transition qui touche la machine passe par le pilote d'alimentation et par **son** démarrage réseau ; d'où l'exigence d'être le DHCP du VLAN, et l'ordre « réseau d'abord » des VMs.

**Alternatives**
- *Garder Kea et faire pointer le VLAN 60 vers MAAS par des classes* (`next-server` = 10.10.60.11, fichiers de MAAS) : MAAS ne le prend pas en charge officiellement (il veut voir et gérer les baux) ; on perd la mise en service fiable.
- *Un VLAN séparé pour MAAS* (un VLAN 61, par exemple) : aucun changement de DHCP sur le 60, essais en parallèle de la chaîne maison ; un VLAN de plus à créer (zone SDN, passerelles, matrice). Pour un essai durable, c'est la meilleure solution ; pour un essai de quelques heures, la fiche de changement suffit.

**Pièges classiques**
- Activer le DHCP de MAAS avant d'avoir retiré Kea : offres concurrentes, machines qui démarrent tantôt chez l'un, tantôt chez l'autre.
- `power_verify_ssl=n` « pour que ça marche » : c'est le `curl -k` de MAAS.
- Vérification TLS en échec alors que `curl` réussit depuis `maas01` : le snap lit les certificats de son propre environnement ; ⚠️ à vérifier sur ton lab (après `update-ca-certificates` côté système, redémarre MAAS ; si le pilote échoue encore, regarde les journaux `/var/snap/maas/common/log/rackd.log`).
- Oublier les plages réservées : MAAS attribue 10.10.60.10 ou .11 (pxe01, lui-même) à une machine déployée.
- Machines laissées *Deployed* avant le retour à Kea : elles gardent une adresse statique de MAAS dans la plage dynamique de Kea (conflits plus tard). Les libérer d'abord.

**En production chez MédiSphère**

Si MAAS était retenu (ADR-0110) : VLAN de provisioning qui lui est propre, synchronisation NetBox ↔ MAAS (les tags et l'état de MAAS deviennent des champs de NetBox), images Debian et Rocky construites et signées, `user_data` qui applique nos standards, pilote Redfish pour les vrais serveurs, HA de la région.

---

### M11-E11 — Revue : les fichiers d'installation du prestataire

**Réponse attendue** (un modèle de [`revue-infoger.md`](fichiers/M11-E11/medisphere/docs/provisioning/revue-infoger.md) est fourni). Les deux fichiers passent `debconf-set-selections -c` et `ksvalidator` : **aucun validateur ne voit ces défauts**, ils sont sémantiques.

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

**Contrôles sur les serveurs installés** (à lancer sur chacun, en lecture) :
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

**Conclusion** : fichiers à **retirer** de tout partage ; une copie unique conservée comme pièce (audit HDS, éventuelle procédure contre l'ancien prestataire) dans un coffre à accès restreint, avec la mention « mots de passe compromis » ; changement immédiat des mots de passe root et suppression du compte `support` et de la clé d'InfoGér sur les huit serveurs ; ticket de sécurité (SEC-12xx) pour le suivi.

**Pièges classiques** : s'arrêter aux mots de passe (le pire, ce sont 3 et 5) ; corriger les fichiers sans traiter les serveurs déjà installés ; « archiver » en laissant la copie sur le partage.

---

### M11-E12 — Runbook : provisionner un serveur

**Réponse attendue** : [`RB-110-provisionner-un-serveur.md`](fichiers/M11-E12/medisphere/docs/provisioning/runbooks/RB-110-provisionner-un-serveur.md) — un modèle complet, à comparer avec le tien.

**Ce qui fait un bon RB-110**
- Un **contrôle d'état de la chaîne** avant de commencer : si `pxe01` ou Kea est en panne, mieux vaut le savoir avant d'avoir allumé le serveur.
- Les **données de réception** obligatoires, avec l'endroit où on les lit sur un vrai serveur (étiquette, bon de livraison, BMC) ; le statut `planned` expliqué en une phrase.
- Chaque étape = **une commande + un résultat attendu** ; la sortie de l'outil de génération lue ligne par ligne (`[refus]` = arrêt).
- L'avertissement « **efface les disques** » là où c'est vrai (installation, réinstallation), pas partout.
- Le passage en `active` **avant** de rallumer, en gras : c'est l'erreur la plus probable (réinstallation en boucle).
- Le dépannage par **symptôme** (ce que voit l'opérateur à la console), avec la première commande et la suite.
- Les secrets : **où** les trouver, jamais leur valeur.
- Une section « exécutions » : un runbook qu'on n'a jamais suivi tel quel n'est pas un runbook.

**Pièges classiques** : un runbook qui raconte la chaîne au lieu de dire quoi faire ; des étapes « vérifier que tout va bien » sans commande ; aucune mention du retour arrière ; un runbook écrit pour soi (« lancer le script habituel »).

**En production chez MédiSphère** : le runbook est la base de l'automatisation de M11-E15 ; chaque étape manuelle restante y est une dette visible, et les contrôles d'acceptation deviennent un script (`outils/accepter.sh`) appelé par la chaîne.
