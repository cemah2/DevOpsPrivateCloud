# Final F1 — Phase 2 : Socle et usine — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. Il existe d'autres solutions valables que celles-ci.

**Ce qui a été vérifié pour écrire ce corrigé** (bac à sable, octobre 2026) : `outils/netbox-provision.py` modifié rend les données simulées du M11 **et** celles du profil `k8s-noeud` (`tests/donnees/netbox-k8s.json`) ; le preseed rendu passe `debconf-set-selections -c` et `outils/verifier-rendu.sh` du M11 ; `tests/test_profil_k8s.py` passe (pytest, 7 tests) ; `ruff format` sur les deux outils Python ; YAML des extraits. **Non rejoués** : `tofu validate` de `envs/f1` et `envs/k8s/usine.tf` (pas d'OpenTofu dans le bac à sable : schémas du fournisseur `e-breuninger/netbox` 5.8 — ressource `netbox_mac_address`, source de données `netbox_platform` — à vérifier sur ta version), l'installation réelle par debian-installer (recette de partitionnement, netplan au premier démarrage), la réinscription par `ipahost`.

---

### F1-S05 — Reconstruire `lb02` et `dns02` depuis le code

**Solution de référence**

Fiche : [`CHG-3105-lb02-dns02.md`](fichiers/S05/medisphere/docs/day0/changements/CHG-3105-lb02-dns02.md) ; compte rendu : [`reconstruction-socle.md`](fichiers/S05/medisphere/docs/day0/reconstruction-socle.md).

*1. Préalables (pour `lb02`).*

```
admin@adm01:~$ ssh lb01 'ip -4 -o addr show | grep 10.10.70.200'          # lb01 maître
admin@adm01:~$ curl -fsS -o /dev/null -w '%{http_code}\n' https://sso.par1.medisphere.internal/realms/medisphere/.well-known/openid-configuration
admin@adm01:~$ ssh ipa01 'kinit <MOI> && ipa host-disable lb02.par1.medisphere.internal'
```

`ipa host-disable` révoque le *keytab* et les certificats de l'hôte, mais garde l'entrée, ses groupes d'hôtes et les règles HBAC qui la citent. C'est le geste qui permet la réinscription par le rôle, une fois celui-ci étendu (extrait : [`freeipa_client/tasks/main.yml.extrait`](fichiers/S05/ansible/roles/freeipa_client/tasks/main.yml.extrait)). `ipa host-del` marche aussi, mais il faut alors que le code de l'annuaire (`plateforme/identite/annuaire/`) déclare les appartenances de l'hôte, sinon elles sont perdues.

*2. Destruction et création par le code : deux MR.* Extrait : [`repartiteurs.tf.extrait`](fichiers/S05/infra/socle/repartiteurs.tf.extrait).
- MR 1 (branche protégée `conf/f1-s05-lb02-retrait`) : l'entrée `lb02` sort de `local.repartiteurs`. Le plan détruit la VM 1011, sa VM NetBox, son adresse, ses enregistrements DNS, et **rien d'autre**. La règle `destruction.rego` refuse le plan tant que l'étiquette de MR `destruction-autorisee` n'est pas posée : Karim (ou toi, Maintainer) la pose **après** avoir lu le plan. Apply manuel.
- MR 2 : l'entrée revient. Le plan crée la VM (nouvelle instance cloud-init, donc nouvelles clés d'hôte SSH), l'adresse imposée 10.10.70.11, A et PTR. Apply.

*3. Gestes listés* : `qm set 1011 --startup order=3` en root ; `ssh-keygen -R lb02 ; ssh-keygen -R lb02.par1.medisphere.internal ; ssh-keygen -R 10.10.70.11` sur `adm01` et `runner01` (si leur `known_hosts` contient des entrées nominatives en plus de la ligne `@cert-authority`).

*4. Configuration par la CI* (jobs manuels de `main` de `plateforme/ansible`, ou ton équivalent) : `site.yml --limit lb02` (rôles communs : `base`, `ca_lab`, `ssh_ca_hote`…), `repartiteurs.yml` (HAProxy, keepalived, certificats ACME), `inscription-ipa.yml`, `node-exporter.yml`, `journaux-vms.yml`, `durcissement.yml`, puis `conformite-mesure.yml` pour lancer l'analyse sans attendre la minuterie hebdomadaire. Les noms sont ceux des corrigés des modules : garde les tiens.

*5. Vérifications.*

```
admin@adm01:~$ ssh lb02 'sudo haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl is-active keepalived && ip -4 -o addr show | grep -c 10.10.70.200'   # 0 attendu
admin@adm01:~$ ssh lb02 'sudo journalctl -u keepalived -n 20 | grep -i "entering backup"'
admin@adm01:~$ lab/bin/check F1 5
```

*6. `dns02`*, même chemin (MR sur `socle/dns02.tf`), après que `lb02` est entièrement revenue. Points propres à `dns02` :
- le rôle de l'autoritaire secondaire demande les zones au primaire (AXFR signé TSIG `axfr-par1`) : vérifier les numéros de série de chaque zone sur les deux serveurs (`dig @127.0.0.1 -p 5300 <zone> SOA` sur chacun) ;
- le récurseur (ancres positives DNSSEC de `par1`) : `dig @10.10.20.16 git01.par1.medisphere.internal +dnssec` avec le bit `ad` ;
- Kea : pendant l'absence de `dns02`, `dns01` passe en `partner-down` après le délai de la HA ; au retour, `dns02` se resynchronise (baux) puis l'état redevient `hot-standby`. Le relais des passerelles (M06-E25) n'a rien à changer.

*7. Durées et dette* : le compte rendu donne les temps par étape et chaque geste manuel avec un ticket.

**Explications**

Une VM « reconstruite par le code » doit revenir dans **tous** les endroits qui la connaissent : la VM elle-même (OpenTofu), son identité réseau (NetBox, DNS), sa configuration (Ansible), son identité de confiance (certificats SSH et TLS, annuaire), sa surveillance (node_exporter, Alloy, conformité). Chacun de ces rattachements est soit dans le code, soit un geste : la répétition sur deux VMs redondantes les fait tous apparaître sans risque.

La voie « deux MR » a un mérite pédagogique et un défaut : elle rend la destruction **visible** et relue (le relecteur voit exactement ce qui disparaît), mais elle supprime aussi les objets NetBox et DNS, puis les recrée ; entre les deux, `lb02.par1.medisphere.internal` ne résout plus. C'est acceptable pour une VM redondante, pas pour une VM unique.

L'annuaire refuse une réinscription par sécurité : une machine qui reprendrait le nom d'un hôte inscrit hériterait de ses règles HBAC et sudo. La désactivation est la **décision humaine** qui dit « c'est bien la même machine, reconstruite » ; le rôle étendu ne réinscrit qu'une entrée sans *keytab*.

**Alternatives**
- `tofu apply -replace='module.repartiteur["lb02"].proxmox_virtual_environment_vm.vm'` depuis un job manuel du pipeline (variable `REMPLACER` passée à `tofu plan -replace=…`), garde-fous inchangés : une seule MR, NetBox et DNS conservés, VM recréée seule. Plus rapide ; la règle conftest voit un remplacement (`["delete","create"]`) et exige la même étiquette.
- Restauration PBS de la VM au lieu d'une reconstruction : plus rapide, mais ne prouve rien sur le code (c'est le retour arrière, pas l'objectif).
- `ipa host-del` + appartenances déclarées dans `annuaire/` : plus « code », mais l'entrée et son historique disparaissent.

**Pièges classiques**
- Démarrer `lb02` recréée avant que keepalived soit configuré… avec une configuration d'avant qui lui donnerait la priorité : ici la VM neuve n'a pas keepalived, puis reçoit la configuration du code (`nopreempt`, priorité de secours) : vérifier quand même que la VIP n'a pas bougé (journal de `lb01`).
- Oublier `ipa host-disable` : le rôle s'arrête sur le contrôle du M24 — c'est le comportement voulu.
- Des `known_hosts` nominatifs sur `runner01` : le premier pipeline Ansible échoue sur « REMOTE HOST IDENTIFICATION HAS CHANGED ».
- Croire que la conformité est calculée : la minuterie est hebdomadaire, le score reste celui… d'aucune analyse.
- Faire `dns02` pendant que `dns01` est en maintenance (ou l'inverse) : plus aucun DNS dans le lab.

**En production chez MédiSphère**
Toute VM du socle a un runbook de reconstruction et un temps mesuré ; les gestes manuels sont résorbés un par un (ordre de démarrage par un rôle `pve_*`, accueil d'une VM neuve qui enchaîne conformité et inscription). Les VMs uniques (`ca01`, `git01`, `ipa01`…) se reconstruisent sur une **copie** (VMID de test, autre adresse) avant d'être jamais refaites pour de vrai.

---

### F1-S06 — L'usine prépare un nœud Kubernetes

**Solution de référence**

Document de synthèse : [`usine-k8s.md`](fichiers/S06/medisphere/docs/day0/usine-k8s.md).

*1. NetBox (compte `<MOI>`, interface ou API)* : plate-forme **`k8s-noeud`** (fabricant facultatif) ; champ personnalisé `pxe_action` : ajoute le type d'objet *virtualization > virtual machine* à ses types d'objets ; la permission de `svc-automatisation` couvre déjà les VMs, leurs interfaces et adresses (M06), et les entrées de journal (M11-E15).

*2. Le profil dans `plateforme/provisioning`* (branche `conf/f1-s06-profil-k8s`, MR) :
- [`gabarits/k8s-noeud.cfg.j2`](fichiers/S06/provisioning/gabarits/k8s-noeud.cfg.j2) : le preseed du M11-E13, avec une recette de partitionnement **sans swap**, `netplan.io` et `chrony`, l'adresse de **service** statique écrite pour netplan (carte reconnue par sa MAC et renommée `eth0`), résolveurs et NTP de la plate-forme, `/etc/cloud/cloud.cfg.d/` vide, un témoin `/etc/medisphere-usine`, extinction finale ;
- [`gabarits/ipxe-hote.ipxe.j2`](fichiers/S06/provisioning/gabarits/ipxe-hote.ipxe.j2) : `k8s-noeud` prend la branche Debian ;
- [`outils/netbox-provision.py`](fichiers/S06/provisioning/outils/netbox-provision.py) : lit aussi les VMs de plate-forme `k8s-noeud` (`lire_netbox_vms`), retient comme adresse de provisioning l'**unique** adresse de `ens18` dans 10.10.60.0/24, garde l'adresse de service à part (`Machine.ip_service`, propriétés `service_adresse`, `service_passerelle`), contrôle un nom `k8s-cpNN`/`k8s-wNN`/`f1-usine-*` ; les réservations Kea, les scripts iPXE par MAC et la publication sont inchangés ;
- [`outils/provisionner.py`](fichiers/S06/provisioning/outils/provisionner.py) : trouve un équipement **ou** une VM `k8s-noeud` (`_chemin`, `_type` pour écrire dans NetBox), VMID autorisés 2112-2115 **plus 2146 et 3101**, s'arrête après l'installation si l'adresse de service est hors du VLAN 60, `--apres-bascule`, vérification du profil en SSH (clé d'hôte confirmée par l'agent QEMU) à la place de l'accueil des serveurs `bm` ;
- tests : [`tests/test_profil_k8s.py`](fichiers/S06/provisioning/tests/test_profil_k8s.py) et [`tests/donnees/netbox-k8s.json`](fichiers/S06/provisioning/tests/donnees/netbox-k8s.json) ; pipeline : [`gitlab-ci.extrait.yml`](fichiers/S06/provisioning/gitlab-ci.extrait.yml).

```
admin@adm01:~/src/provisioning$ uv run pytest -q
admin@adm01:~/src/provisioning$ uv run outils/netbox-provision.py rendre --depuis-json tests/donnees/netbox-k8s.json
admin@adm01:~/src/provisioning$ PATH="$PWD/.venv/bin:$PATH" outils/verifier-rendu.sh rendu/http
```

*3. Droits Proxmox (root, geste listé)* :

```
root@pve01:~# pveum acl modify /vms/3101 --roles WBProvision --users wb-provision@pve --tokens 'wb-provision@pve!provision'
root@pve01:~# pveum acl modify /vms/2146 --roles WBProvision --users wb-provision@pve --tokens 'wb-provision@pve!provision'
```

Le jeton est à séparation des privilèges (M11) : sans ACL propre au jeton, il n'a aucun droit. Après l'essai : `pveum acl delete /vms/3101 --roles WBProvision --users wb-provision@pve --tokens 'wb-provision@pve!provision'`. Registre des secrets mis à jour (portée du jeton).

*4. L'essai.* `plateforme/politiques` : plage de `envs/f1` ([`plages-vmid.yaml.extrait`](fichiers/S06/politiques/rego/donnees/plages-vmid.yaml.extrait)). `plateforme/infra` : nouvel état [`envs/f1/`](fichiers/S06/infra/envs/f1/) (`essai.tf`, `avec_essai = true` dans la MR). Le plan crée la VM 3101 (éteinte, vide, `vprov`, démarrage réseau), sa VM NetBox `planned` de plate-forme `k8s-noeud`, l'interface `ens18` avec sa MAC, 10.10.60.191 (service = provisioning) et le nom DNS. Puis :
- le pipeline de `plateforme/provisioning` (job `deployer` sur `main`) rend la réservation Kea (fichier de variables à reporter dans `plateforme/ansible`, `kea_reservations_prov.yml`, comme au M11) et le script iPXE ;
- *Run pipeline*, variable `EQUIPEMENT=f1-usine-essai`, job manuel `provisionner` : `staged`/`installer`, rendu, allumage, PXE, installation (≈ 20 min), extinction, `pxe_action=local`, rendu, allumage, SSH, DNS, clé d'hôte lue par l'agent, vérification du profil, `active`.

Vérifications sur la machine (avec la clé confirmée) : voir `usine-k8s.md` §5. Puis `avec_essai = false`, MR, apply : la VM, ses objets NetBox et son nom disparaissent ; le rendu suivant retire la réservation et le script iPXE (le `--delete` de `publier.sh`).

*5. `k8s-w03` désactivé.* [`envs/k8s/usine.tf`](fichiers/S06/infra/envs/k8s/usine.tf), [`variables.tf.extrait`](fichiers/S06/infra/envs/k8s/variables.tf.extrait), [`noeuds.tf.extrait`](fichiers/S06/infra/envs/k8s/noeuds.tf.extrait) : variable `noeuds_usine` (vide par défaut), filtre du module `vm-noeud`, ressources de l'usine (VM Proxmox vide, VM NetBox `k8s-noeud` avec ses deux adresses, DNS). Le plan de la MR doit dire **« No changes »** : c'est la preuve que le cluster en service n'est pas touché. La procédure de phase 3 est écrite dans `usine-k8s.md` §6.

*6. Contrôle* : `lab/bin/check F1 6`.

**Explications**

*Deux identités réseau.* Un serveur physique a souvent une carte d'installation et une carte de service, ou la même carte sur deux VLAN selon l'étape (le port du commutateur change de VLAN après installation). Ici, la MAC ne change pas, la carte change de VNet (`vprov` → `vk8s`) : c'est l'équivalent du changement de VLAN du port. La réservation Kea et le script iPXE étant indexés par la MAC, la même MAC dans les deux phases évite toute ambiguïté ; l'adresse de provisioning (10.10.60.163) n'est utilisée que pendant l'installation.

*Pourquoi l'usine s'arrête.* Le système installé porte déjà sa configuration de service (VLAN 40) : le démarrer sur le VLAN 60 le laisserait sans réseau. La bascule est une modification de **matériel** (la carte de la VM), donc le travail d'OpenTofu, pas de l'usine. `--apres-bascule` reprend où l'usine s'est arrêtée, sans rien réinstaller : la clé d'hôte est lue par l'agent QEMU (canal hors réseau, comme au M11-E15), ce qui évite le « je fais confiance à la première clé venue » au premier contact d'Ansible.

*Pourquoi pas de doublon avec les rôles.* Ce que font `containerd` et `k8s_noeud` (modules, sysctl, dépôt Kubernetes, paquets) reste dans les rôles : un nœud cloné et un nœud de l'usine passent par les **mêmes** rôles et convergent vers le même état. L'installateur ne règle que ce que les rôles **supposent** déjà présent (pas de swap, `eth0` en netplan, agent, racine de la PKI, compte `admin`).

*Pourquoi un plan vide.* Le code de la phase 3 est fusionné **avant** la fenêtre, relu à froid, et sa seule activation est une variable. C'est le même principe que `avec_k8s_w04` au M14.

**Alternatives**
- Déclarer `k8s-w03` comme **équipement** NetBox (rôle `serveur-k8s`) plutôt que comme VM : plus fidèle à un serveur physique, mais l'inventaire `netbox-k8s.yml`, `medictl dns sync` et les checks des modules lisent des VMs ; tout serait à adapter.
- Une règle de calcul pour l'adresse de provisioning (100 + suffixe) sans objet NetBox : moins d'objets, mais NetBox ne montre plus la réservation (et ses doublons).
- Construire une **image** de nœud (Packer ou image-builder, M18) et la copier sur le disque par l'usine (à la Tinkerbell) : plus rapide qu'un installateur, mais c'est une image dorée de plus à maintenir.
- Laisser l'usine faire la bascule par l'API de Proxmox (jeton avec `VM.Config.Network`) : une étape de moins, mais le jeton de l'usine pourrait alors rebrancher n'importe quelle carte de ses VMs ; ici, le matériel reste à OpenTofu.

**Pièges classiques**
- Un preseed qui garde la recette `atomic` : un swap apparaît, le rôle le neutralise, mais le disque garde une partition inutile et le profil ne fait pas ce qu'il dit.
- Configurer le réseau de service en `ifupdown` (`/etc/network/interfaces`) : les rôles des modules supposent netplan et `eth0` ; `k8s_reseau_stockage` écrit un fichier netplan pour `eth1`.
- Oublier `--unique`… ici, l'inverse : recréer la VM d'essai avec une MAC aléatoire casse la réservation et le script iPXE.
- Une ACL donnée à l'utilisateur `wb-provision@pve` seulement : le jeton à séparation des privilèges n'hérite de rien.
- Activer `noeuds_usine` sur un nœud **existant** : création et destruction de ressources différentes avec le même VMID et la même adresse (VM 2146 « already exists », adresse en double dans NetBox) ; en phase 3, la VM a déjà été détruite.
- Oublier la plage de `envs/f1` dans `plateforme/politiques` : le plan est refusé (comportement voulu) ; la contourner par une exception générale serait la vraie faute.
- Laisser la VM d'essai, ou sa réservation Kea, après l'essai.

**En production chez MédiSphère**
Sur du matériel, la « bascule » est un changement de VLAN du port de commutateur (par le code du réseau) ou une seconde carte ; les contrôleurs Redfish remplacent l'API de Proxmox pour l'alimentation ; Secure Boot impose un chargeur signé. Le profil `k8s-noeud` est testé chaque nuit par un essai d'installation détruit par le test (à la façon de Terratest, M29), et le jeton de l'usine n'a de droits que sur les machines en cours d'installation (ACL posées et retirées par l'orchestrateur lui-même, avec un compte plus privilégié et tracé).
