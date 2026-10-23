# Module 25 — Palier 3 : Production — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Validé hors lab pour ce corrigé** (banc local, binaires officiels) : **OpenBao 2.6.4 et 2.7.1** (paquets `.deb` et archives de la publication, empreintes relevées dans `checksums.txt`) en **grappe Raft de trois nœuds** avec TLS et `retry_join`, plus un quatrième OpenBao jouant `kms01` ; autopilot (passage non électeur → électeur, réglages) ; passage de témoin, arrêt propre (SIGINT) et arrêt brutal (SIGKILL) du nœud actif sous une boucle d'écriture ; **migration Shamir → `transit`** dans l'ordre de la documentation ; redémarrage simultané sans intervention ; nœud redémarré pendant que `kms01` est arrêté ; **instantané** pris avec un jeton *batch* au moindre privilège, **restauration** `-force` sur un nœud neuf scellé par `transit` (données, jetons et clés de récupération de la production) ; **montée de version en roulement 2.6.4 → 2.7.1** et redescente d'un nœud ; `generate-root` par le nouveau point d'accès authentifié avec les clés de récupération ; enveloppement d'un `secret_id` ; quotas de débit ; audit déclaré ; en-têtes, TLS 1.3, durées de vie ; télémétrie (noms et types des métriques, nœud scellé) ; `bao operator validate-config` du gabarit final rendu ; **HashiCorp Vault 2.2.0** (configuration d'OpenBao, seal `transit` contre OpenBao, audit par l'API, espaces de noms, restauration d'un instantané d'OpenBao). Fournisseur OpenTofu **`hashicorp/vault` 5.13.0** (OpenTofu 1.13.2) contre OpenBao 2.7.1 : `vault_raft_autopilot`, `vault_auth_backend` avec `tune`, `vault_quota_rate_limit`, `vault_policy`, `vault_approle_auth_backend_role`, `vault_kv_secret_v2` avec métadonnées (apply puis plan vide). Scripts `bascule.sh`, `openbao-instantane` (avec un `rclone` simulé), `controle-ages.sh`, `openbao-parts-p3.sh` (décodage local du jeton) exécutés sur le banc ; `promtool` 3.5.0 : `check rules` et tous les tests de `tests/secrets.test.yaml` ; `tofu fmt` des fichiers OpenTofu ; `shellcheck -x` et `bash -n` de tous les scripts ; les checks rejoués sur le banc (cas sain et cas d'avant l'exercice).

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- le relais HAProxy du défi ACME sur les nœuds du coffre (`retry-on conn-failure` + `option redispatch 1` quand deux serveurs sur trois refusent la connexion) : même montage qu'au M07-E12, qui porte la même réserve ;
- keepalived et la VIP (aucun VRRP sur le banc : nœuds sur la boucle locale) ; les mesures de bascule du banc sont **sans** le délai du script de suivi (≈ 2 à 4 s de plus pour les clients de la VIP) ;
- l'unité systemd durcie (`ProtectSystem=strict`, `SystemCallFilter=@system-service`, `MemoryDenyWriteExecute`) : écrite d'après `man systemd.exec` et le comportement connu des programmes Go, jamais démarrée sous systemd ;
- `rclone` 1.6x de Debian 13 avec SeaweedFS pour l'envoi des instantanés (le script a été joué avec un `rclone` simulé), et la lecture du cycle de vie par `aws s3api get-bucket-lifecycle-configuration` sur SeaweedFS ;
- l'API d'administration de Keycloak 26.8 utilisée par la rotation (`POST …/client-secret`, `DELETE …/client-secret/rotated`) et le comportement de « secret tourné » selon la politique de client du royaume ; la lisibilité de l'attribut `client.secret.creation.time` par le compte `wb-checks` (`view-clients`) ;
- l'API GitLab 19.5 des jetons d'accès de projet (création, révocation) ;
- `vault_jwt_auth_backend_role` (rôle `ci-secrets-rotation`) et le pipeline planifié (pas de GitLab sur le banc) ;
- les métriques de cert-manager (`certmanager_certificate_expiration_timestamp_seconds{issuer_name=…}`) et le libellé `instance` des sondes du témoin (URL complète de la cible, comme au M21) ;
- l'effet d'un `max_lease_ttl` abaissé sur les baux **déjà émis** (plafonnés au renouvellement suivant, d'après la documentation).

**Faits que ce palier fixe pour la suite** : VIP 10.10.20.200 sur le nœud actif (VRID 120, script `chk_openbao_actif`) ; relais du défi ACME par HAProxy (port 80 des nœuds, défi de `step` en 8402) ; `kms01` scellé par Shamir (`secrets/kms01-init.yml`, clé `kms01_init`), jeton de seal périodique 168 h (`vault_openbao_kms_jeton`, Vault `critique`), jeton `vault_kms01_jeton_generation` (politique `generation-racine`), `auth/token` de `kms01` réglé à 8760 h ; AppRole **`openbao-instantanes`** et politique du même nom ; rôle Ansible **`openbao_instantane`** ; S3 : identité et compartiment `openbao-instantanes` ; `bao-restauration` 10.10.99.52 et `bao-essai` **10.10.99.51** (adresses fixes, état `envs/m25`) ; règles `regles/secrets.yaml` (dont `OpenBaoToleranceNulle`, `OpenBaoInstantaneEnRetard`) ; tableau `plateforme-openbao` ; durcissement : `openbao_unite_durcie`, `tls13`, baux 1 h / 24 h, quotas `global` et `approle-connexion` (sur `auth/approle/login`) ; politique `wb-checks` étendue (Raft, autopilot, quotas) ; rôle JWT et politique **`ci-secrets-rotation`**, métadonnées KV `proprietaire` et `rotation` ; outils `outils/openbao-parts-p3.sh` (`plateforme/ansible`), `outils/bascule.sh`, `outils/secret-id-enveloppe.sh`, `outils/instantane-vers-restauration.sh`, `outils/rotation/` (`plateforme/secrets`).

Fichiers de solution : `corrige/fichiers/M25-E24/` à `M25-E33/` ; script de lancement d'E34 : `corrige/pannes/break-E34.sh`. Les fichiers `*.extrait` ne montrent que ce qui change dans un fichier d'un autre exercice ; l'état complet du rôle `openbao` en fin de palier est dans `fichiers/M25-E28/ansible/roles/openbao/`.

**Ce qui reste promis** : la clé maîtresse d'etcd dans le coffre (KMS v2, M14) et la KEK de `ceph-rbd-chiffre` dans un KMS externe (M16) **ne sont pas** livrées : ADR-0251 (E31) l'écrit et fixe les conditions de réexamen. La protection de la clé de l'intermédiaire de `ca01` par un HSM ou un KMS (M06) reste une option de l'ADR-0250 (seal PKCS#11, « Révision »). Les rotations des jetons Proxmox, clés WireGuard, clés cephx, identités S3 (M00, M07, M08, M09, M21) sont **inscrites** à la politique de rotation (E33) avec leur période et leur rappel, pas automatisées. Le compte RGW de lecture pour l'exploration des journaux (M22-E4x) n'est pas créé ici.

---

### M25-E24 — Grappe Raft à trois nœuds et VIP

**Solution**

Fichiers : [`socle/coffre.tf`](fichiers/M25-E24/infra/socle/coffre.tf) (remplace `vault01.tf`), [`group_vars/role_coffre/`](fichiers/M25-E24/ansible/inventories/lab/group_vars/role_coffre/) (`openbao.yml`, `certificats.yml`, `haproxy.yml`, `keepalived.yml`, `pare_feu_local.yml`), [`playbooks/coffre.yml`](fichiers/M25-E24/ansible/playbooks/coffre.yml), [`pare_feu.yml.extrait`](fichiers/M25-E24/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [`tofu/autopilot.tf`](fichiers/M25-E24/secrets/tofu/autopilot.tf), [`wb-checks.hcl.extrait`](fichiers/M25-E24/secrets/politiques/wb-checks.hcl.extrait), [`plateforme-admin.hcl.extrait`](fichiers/M25-E24/secrets/politiques/plateforme-admin.hcl.extrait) (exploitation de Raft, `sys/step-down` avec `sudo`), [`tofu-secrets.hcl.extrait`](fichiers/M25-E24/secrets/politiques/tofu-secrets.hcl.extrait), [`outils/bascule.sh`](fichiers/M25-E24/outils/bascule.sh), [`grappe.md`](fichiers/M25-E24/medisphere/docs/securite/secrets/grappe.md).

*Avant tout* : instantané à la main (avertissement de l'énoncé). Avec ton jeton `plateforme-admin` :

```
admin@adm01:~$ bao operator raft snapshot save ~/m25/e24/avant.snap
admin@adm01:~$ age -R ~/src/ansible/pki/openbao-restauration.pub -o ~/m25/e24/avant.snap.age ~/m25/e24/avant.snap && shred -u ~/m25/e24/avant.snap
```

(la clé publique de restauration est créée ici si elle n'existe pas encore : `age-keygen`, privée directement dans `ansible-vault encrypt --encrypt-vault-id critique`, voir E26). Copie `avant.snap.age` hors de `adm01` (`s3-01`, compartiment de l'équipe).

*1. VMs.* `coffre.tf` remplace `vault01.tf` par **une** ressource itérée (`for_each` sur `vault01-03`) et deux blocs **`moved`** : sans eux, OpenTofu verrait `module.vault01` disparaître et `module.coffre["vault01"]` apparaître, et **détruirait** `vault01`. Le plan doit dire `module.vault01 … has moved to module.coffre["vault01"]` et ne créer que `vault02`, `vault03`, la VIP NetBox. La variable `openbao_sur_vip` (faux) garde le nom du service sur 10.10.20.21 jusqu'à l'étape 6.

```
admin@adm01:~/src/infra/socle$ tofu plan -out coffre.plan | grep -E 'moved|will be (created|destroyed)'
  # module.vault01.… has moved to module.coffre["vault01"].…
  # module.coffre["vault02"].proxmox_virtual_environment_vm.vm will be created
  …
admin@adm01:~/src/infra/socle$ tofu apply coffre.plan
root@pve01:~# qm set 1022 --startup order=4 && qm set 1023 --startup order=4
```

*2. Configuration Raft.* Le rôle du palier 1 avait prévu `openbao_raft_rejoindre` : on la calcule dans `group_vars/role_coffre/openbao.yml` (tous les nœuds du groupe, triés). Réponses : un nœud **vide et non initialisé** essaie chaque `leader_api_addr` jusqu'à trouver un nœud **descellé** qui accepte de lui donner le défi de jonction (`sys/storage/raft/bootstrap/challenge`), le résout avec les clés de la barrière… qu'il n'a pas encore : avec Shamir, la jonction se termine **quand on le descelle** (il reçoit le trousseau chiffré par Raft) ; avec `transit` (E25), tout seul. Un nœud **déjà membre** (données Raft présentes) ignore `retry_join`. `vault01` peut donc recevoir la liste sans risque ; elle sert le jour où on le reconstruit vide. Ajouter un nœud change la configuration des autres (le rôle prévient qu'un redémarrage serait nécessaire) : ce n'est pas utile, la liste ne sert qu'aux nœuds vides ; le prochain redémarrage planifié l'appliquera.

*3. Certificats.* Deux noms par nœud (`vaultNN.par1…` et `openbao.par1…`), défi HTTP-01 : le nom du nœud mène au nœud ; le nom du service mène à la VIP, donc au nœud **actif**. Même solution qu'au M07-E12 : `ecoute_http: ":8402"` (le serveur de défi de `step` écoute sur 8402 chez le seul demandeur) et un **relais HAProxy** sur le port 80 de chaque nœud (`fe_acme` → `be_acme`, trois serveurs en 8402, `retries 3`, `retry-on conn-failure`, `option redispatch 1`) : le nœud actif reçoit le défi, essaie les trois, deux refusent la connexion, le troisième répond. Le **renouvellement** (`cert-renewer@openbao`, `step ca renew`) se fait par TLS mutuel avec le certificat en place : ni défi ni port 80. Contrôle :

```
admin@adm01:~$ for n in 01 02 03; do echo | openssl s_client -connect vault$n.par1.medisphere.internal:8200 \
    -servername openbao.par1.medisphere.internal -verify_return_error 2>/dev/null | openssl x509 -noout -ext subjectAltName; done
X509v3 Subject Alternative Name:
    DNS:vault01.par1.medisphere.internal, DNS:openbao.par1.medisphere.internal
…
```

*4. Rejoindre.* Un hôte à la fois : `uv run ansible-playbook playbooks/coffre.yml --limit vault02`, puis trois dépositaires descellent **sur l'adresse du nœud** (`BAO_ADDR=https://vault02.par1.medisphere.internal:8200 outils/openbao-parts.sh desceller <N> <IDENTITÉ>`). Juste après :

```
admin@adm01:~$ bao operator raft list-peers
Node       Address                               State       Voter
----       -------                               -----       -----
vault01    vault01.par1.medisphere.internal:8201 leader      true
vault02    vault02.par1.medisphere.internal:8201 follower    false
```

`false` : autopilot garde un nouveau serveur **non électeur** tant qu'il n'a pas été sain pendant `server_stabilization_time` (10 s par défaut) — le temps de rattraper le journal Raft sans fausser le quorum. Une dizaine de secondes plus tard, `Voter true`. Même chose pour `vault03`. Observé sur le banc : `Status: non-voter` dans `autopilot state` à la jonction, `voter` 10 s après.

*5. Autopilot.* Valeurs par défaut lues : `cleanup_dead_servers false`, `last_contact_threshold 10s`, `dead_server_last_contact_threshold 24h`, `server_stabilization_time 10s`, `min_quorum 0`, `max_trailing_logs 1000`. Choix (`autopilot.tf`) : `cleanup_dead_servers = true` **et** `min_quorum = 3`. Ce que fait réellement le nettoyage : autopilot ne retire jamais un pair si la grappe passait sous `min_quorum` ; dans une grappe de trois, **il ne retire donc rien**. C'est voulu : un nœud arrêté pour maintenance ou restauré depuis PBS doit retrouver sa place. Le réglage prendra effet si la grappe grandit. Il est stocké dans Raft (`sys/storage/raft/autopilot/configuration`) : en code par `vault_raft_autopilot` du fournisseur `hashicorp/vault`, essayé contre OpenBao — à une nuance près : écris les durées comme OpenBao les **relit** (`"24h0m0s"`), sinon chaque `plan` annonce un changement `"24h0m0s" -> "24h"`.

*6. VIP.* `keepalived.yml` : instance `VI_OPENBAO`, VRID 120, unicast (adresses tirées de `coffre_adresses` : avec `serial: 1`, les faits des autres nœuds ne sont pas connus), sans préemption, script `chk_openbao_actif` = `curl -fsS --resolve vaultNN.par1…:8200:127.0.0.1 https://vaultNN.par1…:8200/v1/sys/health`. `curl -f` échoue sur 429, 501, 503 : seuls les nœuds actifs portent la VIP. Le playbook place keepalived **après** OpenBao et vérifie à la fin qu'une seule VIP existe. Ensuite seulement : `openbao_sur_vip = true`, `tofu apply` (TTL 300 s), et les trois vérifications (CLI, un pipeline qui lit un secret, un `ExternalSecret` rafraîchi par l'annotation `force-sync`). Ajoute les définitions `OPENBAO` et `COFFRE` à la matrice de la bordure ([extrait](fichiers/M25-E24/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait)) et remplace `VAULT01` partout.

*7. Bascules.* `outils/bascule.sh <étiquette> 120` dans un terminal, l'épreuve dans un autre :

```
admin@adm01:~/src/secrets$ outils/bascule.sh step-down 60
écritures : 160, échecs : 0
aucune indisponibilité en écriture
changements de nœud actif : vault01→vault02 (10:42:13.017)
admin@adm01:~/src/secrets$ outils/bascule.sh qm-stop 90
écritures : 205, échecs : 13
plus longue indisponibilité en écriture : 8.06 s (de 10:51:40.952 à 10:51:49.238)
changements de nœud actif : vault02→vault03 (10:51:49.238)
```

Ordres de grandeur mesurés sur le banc (sans keepalived, en écrivant par un nœud en attente) : **passage de témoin** : 0 à 1 échec (le nœud actif rend le verrou, un autre le prend dans la seconde) ; **arrêt propre** (`systemctl stop`, SIGINT) : 0 échec — l'arrêt propre fait lui-même un passage de témoin ; **arrêt brutal** (SIGKILL / `qm stop`) : ≈ 8 s (expiration du délai d'élection Raft, nouvelle élection, prise du verrou d'actif, reconstruction des montages et des baux). Par la VIP, ajoute le délai de keepalived (2 échecs × 2 s). Dans `journalctl -u openbao` du nouveau nœud actif : `entering candidate state`, `election won`, `entering leader state`, `acquired lock, enabling active operation`, `post-unseal setup complete` ; dans `journalctl -t keepalived-transition` : passage `MASTER` du même nœud, `FAULT` de l'ancien.

*8. Documentation.* [`grappe.md`](fichiers/M25-E24/medisphere/docs/securite/secrets/grappe.md) (schéma, règles, tableau des mesures) ; matrice des flux : nœuds ↔ 8200-8201 et VRRP, `ca01` → nœuds et VIP 80, nœuds ↔ 8402.

**Explications**

Le stockage Raft intégré réplique les données (chiffrées par la barrière) sur chaque nœud ; le **leader Raft** ordonne les écritures, le **nœud actif** d'OpenBao (celui qui tient le verrou HA, stocké lui aussi dans Raft) sert les requêtes. Les nœuds en attente répondent quand même : ils **transmettent** la requête au nœud actif par le port 8201 (*request forwarding*, TLS interne de la grappe) — c'est pour cela que la boucle peut écrire par n'importe quel nom. Ils ne savent pas servir eux-mêmes une lecture (les *performance standby* sont une fonction de Vault Enterprise). Le quorum est de 2 sur 3 : une panne tolérée, deux pannes = plus d'actif possible, plus aucune lecture.

**Alternatives**
- **HAProxy devant les trois nœuds** (vérification `sys/health`) au lieu d'une VIP : un saut de plus, TLS à re-chiffrer ou à passer en TCP ; utile si l'on veut équilibrer la charge vers des *performance standby* (pas chez nous).
- **DNS à trois enregistrements** : les clients essaieraient un nœud en attente, qui transmet ; simple, mais un nœud **scellé** reste dans le DNS et répond 503.
- Certificats : défi **DNS-01** (pas de relais), mais le client `step` ne le fait pas ; un client ACME qui le sait (certbot et sa clé TSIG pour PowerDNS) ajoute un outil et un secret.
- Cinq nœuds : tolérance de deux pannes, mais tous sur `pve01` (E32, question 12).

**Pièges classiques**
- Oublier les blocs `moved` : OpenTofu détruit `vault01` et ses données.
- Initialiser `vault02` par erreur (`bao operator init` sur la mauvaise adresse) : il devient une grappe à lui seul ; il faut l'arrêter, vider **son** `/var/lib/openbao` (lui seul, nouveau et vide de données de production), recommencer.
- Desceller par la VIP : la part va au nœud actif, déjà descellé ; on descelle **chaque** nœud sur son adresse.
- Script keepalived avec `?standbyok=true` : tous les nœuds répondent 200, la VIP peut rester sur un nœud en attente.
- Certificat sans `127.0.0.1` et script en `https://127.0.0.1` : la vérification TLS échoue, toutes les instances en FAULT, plus de VIP (d'où `--resolve`).
- Bloc d'audit différent d'un nœud à l'autre : le nœud qui devient actif refuse de prendre la main (`failed to validate audit device config … file_path differs`) et rend le verrou : ≈ 10 s d'écritures en échec à chaque bascule vers lui (observé). La configuration vient du même gabarit sur les trois nœuds.
- Durées d'autopilot écrites `"24h"` dans OpenTofu : différence perpétuelle au `plan`.

**En production chez MédiSphère**
Trois nœuds sur trois hyperviseurs (règle d'anti-affinité Proxmox HA, M09) et une grappe indépendante à PAR2 (F5) ; supervision de la VIP et des transitions keepalived (E27) ; bascules mesurées à chaque montée de version (E29) et inscrites à l'ADR-0250.

---

### M25-E25 — Auto-descellement : `kms01` et migration du seal

**Solution**

Fichiers : [`socle/kms.tf`](fichiers/M25-E25/infra/socle/kms.tf), rôle [`openbao_kms`](fichiers/M25-E25/ansible/roles/openbao_kms/), [`group_vars/role_kms/openbao.yml`](fichiers/M25-E25/ansible/inventories/lab/group_vars/role_kms/openbao.yml), [`host_vars/kms01/`](fichiers/M25-E25/ansible/inventories/lab/host_vars/kms01/), [`playbooks/kms.yml`](fichiers/M25-E25/ansible/playbooks/kms.yml), politiques de `kms01` ([`kms-autodescellement.hcl`](fichiers/M25-E25/kms01/kms-autodescellement.hcl), [`generation-racine.hcl`](fichiers/M25-E25/kms01/generation-racine.hcl)), rôle `openbao` : [`seal-transit.yml`](fichiers/M25-E25/ansible/roles/openbao/tasks/seal-transit.yml), [`medisphere.conf.j2`](fichiers/M25-E25/ansible/roles/openbao/templates/medisphere.conf.j2), extraits du gabarit et des variables ; [`openbao.yml.extrait`](fichiers/M25-E25/ansible/inventories/lab/group_vars/role_coffre/openbao.yml.extrait), [`vault-critique-kms.yml.exemple`](fichiers/M25-E25/ansible/inventories/lab/group_vars/role_coffre/vault-critique-kms.yml.exemple), [`kms01-init.yml.exemple`](fichiers/M25-E25/ansible/secrets/kms01-init.yml.exemple), [`outils/openbao-parts-p3.sh`](fichiers/M25-E25/ansible/outils/openbao-parts-p3.sh), [`pare_feu.yml.extrait`](fichiers/M25-E25/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [RB-251](fichiers/M25-E25/medisphere/docs/securite/secrets/runbooks/RB-251-descellement-et-redemarrage.md).

*1. `kms01`.* `tofu apply` (état `socle`, `qm set 1024 --startup order=3` : **avant** la grappe), `playbooks/kms.yml`, puis initialisation en cérémonie, comme en E03, avec la clé `kms01_init` :

```
admin@adm01:~/src/ansible$ BAO_ADDR=https://kms01.par1.medisphere.internal:8200 bao operator init -format=json -key-shares=5 -key-threshold=3 \
    | PARTS_CLE=kms01_init JETON_POUR=<MOI> outils/openbao-parts.sh chiffrer pki/openbao-depositaires.txt \
    | uv run ansible-vault encrypt --encrypt-vault-id critique --output secrets/kms01-init.yml -
admin@adm01:~/src/ansible$ PARTS_FICHIER=secrets/kms01-init.yml PARTS_CLE=kms01_init \
    BAO_ADDR=https://kms01.par1.medisphere.internal:8200 outils/openbao-parts.sh desceller 1 ~/cles/<MOI>.age   # ×3 dépositaires
admin@adm01:~/src/ansible$ PARTS_FICHIER=secrets/kms01-init.yml PARTS_CLE=kms01_init outils/openbao-parts.sh jeton-racine ~/cles/<MOI>.age
admin@adm01:~$ export BAO_ADDR=https://kms01.par1.medisphere.internal:8200
admin@adm01:~$ bao secrets enable transit
admin@adm01:~$ bao write -f transit/keys/autodescellement-par1
admin@adm01:~$ bao read -format=json transit/keys/autodescellement-par1 | jq '.data | {type, exportable, deletion_allowed}'
{ "type": "aes256-gcm96", "exportable": false, "deletion_allowed": false }
admin@adm01:~$ bao policy write kms-autodescellement ~/src/ansible/kms01/kms-autodescellement.hcl
admin@adm01:~$ bao policy write generation-racine ~/src/ansible/kms01/generation-racine.hcl
admin@adm01:~$ bao write sys/auth/token/tune max_lease_ttl=8760h
```

`kms01` n'est pas géré par `plateforme/secrets` : OpenTofu y aurait besoin d'un jeton **permanent** à forts droits (il n'y a pas d'humain OIDC sur `kms01`, et pas de jeton racine permanent) ; sa configuration tient en cinq commandes, rejouées en cérémonie et consignées dans `~/m25/e25/kms01.md`. Pourquoi `auth/token/tune` : le maximum de durée **plafonne aussi la période** des jetons périodiques, sans avertissement (essayé : `-period=168h` avec un maximum de 24 h donne un bail de 24 h).

*2. Jeton.* La sortie de `bao token create` va directement dans le Vault `critique` ([modèle](fichiers/M25-E25/ansible/inventories/lab/group_vars/role_coffre/vault-critique-kms.yml.exemple)) : `-orphan` (il ne meurt pas avec le jeton racine qu'on va révoquer), `-no-default-policy` (pas de `cubbyhole`, pas de `lookup-self`, et donc **pas de `renew-self`** : c'est pourquoi la [politique](fichiers/M25-E25/kms01/kms-autodescellement.hcl) donne `update` sur `auth/token/renew-self`, le seul droit du jeton sur lui-même), `-policy=kms-autodescellement`, `-period=168h`. Contrôle par l'**accesseur** : `bao token lookup -accessor <ACCESSEUR>` → `orphan true`, `period 168h`, `policies [kms-autodescellement]`, `explicit_max_ttl 0`. Le serveur OpenBao de chaque nœud le **renouvelle** (paramètre `disable_renewal` à `false` par défaut) grâce à ce droit : tant qu'un nœud tourne, la période repart, et `last_renewal_time` (même `lookup -accessor`, après le premier démarrage avec le seal) est renseigné. Sans `renew-self`, l'essai de renouvellement échoue **sans bruit** et le jeton meurt au bout de sa période : la grappe continue de tourner (clé racine en mémoire), mais plus aucun nœud ne peut redémarrer (M25-E42). Il ne meurt que si **aucun** nœud ne l'a renouvelé pendant 7 jours (grappe arrêtée plus longtemps) ou s'il est révoqué : RB-251 § 6. Même geste pour le jeton de génération (`-policy=generation-racine -period=8760h`, `vault_kms01_jeton_generation`), puis `bao token revoke -self` du jeton racine de `kms01`.

*3. Configuration.* Bloc `seal "transit"` sans jeton (adresse, clé, montage, `tls_ca_cert` = racine MédiSphère, `tls_server_name`), jeton dans `BAO_TOKEN` (nom exact de la variable dans la documentation du seal) lu par systemd depuis `/etc/openbao/kms.env` (root, 600 : systemd le lit **avant** de passer à l'utilisateur `openbao`). Pas dans `openbao.hcl` : il est lisible par le groupe `openbao`, part dans les diffs d'Ansible et les sauvegardes de configuration. ⚠️ N'écris jamais `BAO_ADDR` dans `kms.env` : la même variable sert d'adresse par défaut au seal **et** au client.

*4. Migration.* Avec `openbao_redemarrer=false`, le rôle **écrit** la configuration sur les trois nœuds sans redémarrer. Puis, dans l'ordre de la documentation :

```
admin@adm01:~$ for n in 01 02 03; do printf 'vault%s %s\n' $n "$(curl -s -o /dev/null -w '%{http_code}' https://vault$n.par1.medisphere.internal:8200/v1/sys/health)"; done
vault01 200
vault02 429
vault03 429
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/coffre.yml --limit vault02 -e openbao_redemarrer=true
admin@adm01:~$ curl -s https://vault02.par1.medisphere.internal:8200/v1/sys/seal-status | jq -c '{type, sealed, recovery_seal, migration}'
{"type":"transit","sealed":true,"recovery_seal":true,"migration":true}
admin@adm01:~/src/ansible$ BAO_ADDR=https://vault02.par1.medisphere.internal:8200 outils/openbao-parts-p3.sh migrer 1 ~/cles/<MOI>.age   # ×3
part acceptée : 3/3 ; scellé=false ; migration=true
admin@adm01:~$ curl -s https://vault02.par1.medisphere.internal:8200/v1/sys/seal-status
{"errors":["barrier seal type of \"shamir\" does not match loaded type of \"transit\""]}
```

Cette dernière réponse (et un `sys/health` en 500) est **normale** : le nœud tourne avec une configuration `transit`, mais la barrière enregistrée dans les données est encore `shamir` ; son journal dit `entering seal migration mode` puis `unsealing using migration seal`. Même chose pour `vault03`. Puis passage de témoin du nœud actif (`BAO_ADDR=https://vault01…:8200 bao operator step-down`) : le nouvel actif (déjà configuré en `transit`) **fait la migration** — journal : `seal migration initiated`, `migrating from shamir to auto-unseal: to=transit`, `seal migration complete`. Les autres nœuds en attente retrouvent un `seal-status` cohérent. Enfin l'ancien actif, `vault01` : playbook avec `openbao_redemarrer=true` : il redémarre et se **descelle seul**.

*5. Épreuves.* (a) `qm reboot 1021 ; qm reboot 1022 ; qm reboot 1023` : les trois reviennent descellés (`type: transit, sealed: false`), un actif, la VIP revient ; heures et extraits de journal dans `~/m25/e25/`. (b) `kms01` arrêté, `vault02` redémarré : le processus **s'arrête** au démarrage (`Error configuring seal "transit": Put "https://kms01…/v1/transit/encrypt/autodescellement-par1": … connection refused`), avant même d'ouvrir son écouteur ; `Restart=on-failure`, `RestartSec=5`, `StartLimitBurst=3` sur 60 s : au bout de trois essais, `start-limit-hit`, systemd **abandonne**. `kms01` revenu (il est **scellé** : trois dépositaires), `vault02` ne revient pas seul : `systemctl reset-failed openbao && systemctl start openbao`. (c) Grappe déjà descellée, `kms01` arrêté une heure : **rien** ne change pour les clients (la clé racine est en mémoire) ; le renouvellement du jeton échoue dans les journaux ; le danger est un redémarrage pendant ce temps.

*6. Clés de récupération.* `bao status` : `Seal Type transit`, `Recovery Seal Type shamir`, `Total Recovery Shares 5`, `Threshold 3`. Une part présentée à `sys/unseal` d'un nœud descellé ne fait rien ; elle sert à `generate-root` (E28), à `rekey -target=recovery`, et à une migration inverse. Commentaire dans `secrets/openbao-init.yml` et décision écrite des dépositaires mise à jour.

*7. RB-251* : [fichier](fichiers/M25-E25/medisphere/docs/securite/secrets/runbooks/RB-251-descellement-et-redemarrage.md).

**Explications**

La barrière chiffre les données avec le **trousseau** ; le trousseau est chiffré par la **clé racine** ; la clé racine est soit reconstituée par Shamir à chaque démarrage, soit stockée **chiffrée par le seal** (ici : `transit/encrypt` sur `kms01`) dans les données Raft. Au démarrage, le nœud demande `transit/decrypt` à `kms01` et obtient la clé racine en mémoire. Une copie du disque d'un nœud contient la clé racine chiffrée et les données chiffrées : sans `kms01` (et son jeton), rien. Les parts Shamir initiales deviennent des clés de **récupération** : un second secret partagé qui autorise les opérations sensibles (générer un jeton racine, changer les clés) mais ne descelle plus rien.

**Alternatives**
- **`static`** : une clé AES-256 dans un fichier ou une variable du nœud ; auto-descellement sans dépendance, mais la clé est **à côté** des données : un vol de la VM entière donne tout (ADR-0250).
- **PKCS#11 / HSM** : greffon KMS externe depuis la 2.7 ; la cible si MédiSphère achète un HSM.
- **Seal High Availability** (plusieurs seals à la fois) : à lire dans la documentation ; réduirait la dépendance à un seul `kms01`.
- `kms01` en grappe : trois VMs de plus pour un service qui ne sert qu'au démarrage ; la sauvegarde PBS et la procédure suffisent au lab.

**Pièges classiques**
- Migrer l'actif en premier : il redémarre, la grappe élit un nœud **Shamir** pendant que lui attend `-migrate`… et l'ordre de la documentation est rompu.
- Lancer `unseal -migrate` par la VIP : la part arrive au nœud actif.
- Jeton non orphelin, créé avec le jeton racine qu'on révoque ensuite : la révocation en cascade emporte le jeton du seal ; la grappe tourne… jusqu'au prochain redémarrage.
- `max_lease_ttl` de `kms01` à 24 h sans régler `auth/token` : le jeton « de 7 jours » vit 24 h ; une grappe arrêtée un week-end ne redémarre plus.
- Relever `min_decryption_version` de `autodescellement-par1` après une rotation de la clé : la clé racine chiffrée par une ancienne version devient illisible (c'est une variante de panne au palier 4).
- Croire que `systemd` relancera seul un nœud dès que `kms01` revient : après `StartLimitBurst`, il faut `reset-failed`.

**En production chez MédiSphère**
`kms01` sur un autre hyperviseur que la grappe (ou un HSM), supervisé (E27), sauvegardé (E26) ; dépositaires de `kms01` joignables 24 h/24 (astreinte) ; essai semestriel du redémarrage complet (grappe **et** `kms01`) inscrit au calendrier de l'astreinte.

---

### M25-E26 — Instantanés chiffrés et restauration éprouvée

**Solution**

Fichiers : rôle [`openbao_instantane`](fichiers/M25-E26/ansible/roles/openbao_instantane/) (script [`openbao-instantane.sh`](fichiers/M25-E26/ansible/roles/openbao_instantane/files/openbao-instantane.sh), unité, minuterie), [`group_vars/role_coffre/openbao_instantane.yml`](fichiers/M25-E26/ansible/inventories/lab/group_vars/role_coffre/openbao_instantane.yml), [`playbooks/coffre-instantanes.yml`](fichiers/M25-E26/ansible/playbooks/coffre-instantanes.yml), [`seaweedfs.yml.extrait`](fichiers/M25-E26/ansible/inventories/lab/host_vars/s3-01/seaweedfs.yml.extrait), [`outils/s3/`](fichiers/M25-E26/infra/outils/s3/), [`politiques/openbao-instantanes.hcl`](fichiers/M25-E26/secrets/politiques/openbao-instantanes.hcl), [`tofu/instantanes.tf`](fichiers/M25-E26/secrets/tofu/instantanes.tf), [`envs/m25/`](fichiers/M25-E26/infra/envs/m25/), [`host_vars/bao-restauration/openbao.yml`](fichiers/M25-E26/ansible/inventories/lab/host_vars/bao-restauration/openbao.yml), [`outils/instantane-vers-restauration.sh`](fichiers/M25-E26/outils/instantane-vers-restauration.sh), [RB-252](fichiers/M25-E26/medisphere/docs/securite/secrets/runbooks/RB-252-sauvegarde-restauration-openbao.md).

*1. Lecture.* Un instantané est une archive gzip : `meta.json`, `state.bin`, `SHA256SUMS`, `SHA256SUMS.sealed` (observé). `state.bin` contient les paires clé/valeur du stockage **chiffrées par la barrière** : aucun secret lisible. Il faut en plus la clé racine, qui est dans l'instantané… chiffrée par le seal : donc `kms01` et la **même** clé de transit (ou une restauration sur la grappe d'origine). Un nœud en attente sait prendre un instantané (la requête est transmise, observé) ; on ne le fait que sur l'actif pour éviter trois copies par heure et pour que la minuterie ait un comportement simple (un seul envoi, quel que soit l'actif). Capacité : `read` sur `sys/storage/raft/snapshot`, rien d'autre (essayé avec un jeton *batch* portant cette seule politique).

*2. Stockage objet.* Modèle M14-E24 : identité `openbao-instantanes` (`Read`, `Write`, `List` sur le compartiment), compartiment versionné, [politique](fichiers/M25-E26/infra/outils/s3/politique-openbao-instantanes.json) qui refuse à cette identité la suppression et la modification de la configuration, [cycle de vie](fichiers/M25-E26/infra/outils/s3/cycle-de-vie-openbao-instantanes.json) de 30 jours, posés avec l'identité d'administration. Essai : écrire puis supprimer avec l'identité → `AccessDenied` à la suppression (voulu : un nœud compromis ne peut pas effacer les sauvegardes).

*3. Rôle.* Le script : `sys/leader` (`is_self`) → sortie si en attente ; connexion AppRole (role_id + secret_id lus dans `/etc/openbao/instantanes.env`, passés à `curl` par l'entrée standard) → jeton *batch* ; `bao operator raft snapshot save` dans le `/tmp` **privé** de l'unité ; contrôle de forme (`gzip -t`, `meta.json`, `state.bin`) ; `age -r <clé publique>` puis effacement du clair ; `rclone copyto` (configuration entière par variables `RCLONE_CONFIG_BAOS3_*`) et relecture de la taille ; trace `dernier-succes` et métrique *textfile*. Unité `Type=oneshot`, `PrivateTmp`, `ProtectSystem=strict` avec deux chemins inscriptibles, `OnFailure=ms-alerte@%n.service`. Pourquoi les secrets de la sauvegarde (identité S3, `secret_id`, clé publique) restent dans Ansible Vault : la sauvegarde du coffre ne doit pas dépendre du coffre.

*4. Premier envoi.*

```
admin@adm01:~$ for n in 01 02 03; do ssh vault$n.par1.medisphere.internal 'sudo systemctl start openbao-instantane.service; sudo journalctl -u openbao-instantane -n 1 -o cat'; done
openbao-instantane: nœud en attente (actif : https://vault02.par1.medisphere.internal:8200) : rien à faire
openbao-instantane: envoyé : s3://openbao-instantanes/horaire/2026-11-03/vault02-20261103T101507Z.snap.age (412873 octets chiffrés, 412673 en clair) en 2 s
openbao-instantane: nœud en attente (actif : https://vault02.par1.medisphere.internal:8200) : rien à faire
admin@adm01:~$ ( set -a; . ~/.config/workbook/s3-openbao-instantanes.env; set +a
>   aws --endpoint-url https://s3-01.par1.medisphere.internal:8333 s3 cp s3://openbao-instantanes/horaire/2026-11-03/vault02-20261103T101507Z.snap.age - | head -c 22 )
age-encryption.org/v1
```

*5. PBS.* Stockage `pbs-par2-secrets` (espace de noms `par1/secrets`), tâche `secrets-nuit` sur 1021-1024. La sauvegarde d'une VM en attente contient ses données Raft d'une heure donnée : restaurée **seule**, elle rejoint la grappe et rattrape par Raft (le leader lui envoie les journaux ou un instantané) ; c'est un moyen de reconstruire un nœud, pas une sauvegarde des données. Les trois VMs restaurées ensemble ont été prises à des instants différents : Raft garde l'état du nœud élu, des écritures peuvent disparaître. Pour `kms01`, PBS est **la** sauvegarde (sa clé de transit n'existe nulle part ailleurs).

*6. Restauration éprouvée.* (RB-252 § 5, en entier.) Points notables :

```
admin@adm01:~$ bao kv put -mount=kv wb-essais/rpo ecrit_a="$(date +%T)"         # après le dernier instantané
admin@adm01:~/src/infra/envs/m25$ tofu apply -var 'groupes=["restauration"]'
admin@adm01:~$ BAO_ADDR=https://bao-restauration.par1.medisphere.internal:8200 bao operator init -recovery-shares=1 -recovery-threshold=1 -format=json > "$XDG_RUNTIME_DIR/resto-init.json"
admin@adm01:~/src/ansible$ ../secrets/outils/instantane-vers-restauration.sh bao-restauration
objet : s3://openbao-instantanes/horaire/2026-11-03/vault02-20261103T101507Z.snap
412673 octets reçus
admin@bao-restauration:~$ jq -r .root_token /run/…/resto-init.json | bao login -no-print -     # (copié par scp, 600)
admin@bao-restauration:~$ bao operator raft snapshot restore -force /var/tmp/restauration.snap
admin@bao-restauration:~$ sudo systemctl restart openbao && bao status | grep -E 'Seal Type|Sealed'
Seal Type                transit
Sealed                   false
```

Constats (observés sur le banc) : le jeton racine de la grappe neuve **cesse d'exister** à la restauration (403) ; un jeton de la production encore valide fonctionne ; `bao operator raft list-peers` ne montre **que** `bao-restauration` (la configuration Raft reste celle du nœud) ; les **clés de récupération de la production** permettent un `generate-root` sur la copie (elles viennent de l'instantané) ; `kv/wb-essais/rpo` est **absent** (RPO = écart entre l'instantané et ce secret) ; après redémarrage, le nœud se descelle seul (même clé de transit). La connexion OIDC ne marche pas (pas de flux vers Keycloak : voulu). T1 noté quand un secret ancien est lu.

*7. Nettoyage.* `tofu apply -var 'groupes=[]'`, révocation du jeton d'essai sur `kms01` par son accesseur (jeton de génération puis `generate-root` sur `kms01` : le palier l'a outillé), MR qui retire la règle temporaire, `shred -u` des fichiers de `$XDG_RUNTIME_DIR`.

*8. RB-252* : [fichier](fichiers/M25-E26/medisphere/docs/securite/secrets/runbooks/RB-252-sauvegarde-restauration-openbao.md), mesures remplies.

**Explications**

Un instantané Raft est **cohérent** (pris par le leader à un index donné), complet (configuration, montages, politiques, jetons, baux) et petit ; il ne vaut rien sans la clé racine. C'est la bonne propriété pour une sauvegarde qui part sur une autre machine, et le bon risque à surveiller : la sauvegarde du coffre dépend de `kms01`. RPO : au plus une heure plus la durée d'envoi (minuterie horaire) ; RTO : dominé par la création de la VM.

**Alternatives**
- Instantanés plus fréquents (toutes les 15 min) : RPO plus court, quatre fois plus d'objets ; rien n'empêche d'ajouter un instantané **avant** chaque changement (fait en E29).
- *Snapshot agent* de Vault Enterprise : sans objet ici.
- Copie de `/var/lib/openbao` à chaud : incohérente ; à froid : il faut arrêter un nœud.
- Chiffrement par la clé de transit d'OpenBao au lieu d'`age` : on ne déchiffrerait la sauvegarde qu'avec un coffre vivant.

**Pièges classiques**
- Restaurer une copie **vivante** avec des flux ouverts : son gestionnaire d'expiration révoque les identifiants PostgreSQL émis par la production, `rotate-root` peut changer le mot de passe du rôle `openbao`.
- Jeton d'essai sur `kms01` créé avec une autre clé de transit : la clé racine de l'instantané reste illisible, la restauration semble réussir mais le nœud ne se descelle plus au redémarrage.
- `snapshot restore` sans `-force` sur une grappe neuve : refusé (clés différentes) ; **avec** `-force` sur la production par erreur : retour arrière d'une heure de toute la grappe.
- Laisser l'instantané clair dans `/var/tmp` de la VM ou sur `adm01`.
- `secrets/` du rôle en clair dans l'inventaire (identité S3) au lieu du Vault `critique`.

**En production chez MédiSphère**
Copie des instantanés vers PAR2 (réplication du compartiment, F5) ; alerte sur l'âge (E27) ; essai trimestriel par l'astreinte (RB-252 § 9) ; `kms01` restauré dans le même essai une fois par an.

---

### M25-E27 — Superviser OpenBao

**Solution**

Fichiers : [`scrape/openbao.yaml`](fichiers/M25-E27/observabilite/scrape/openbao.yaml), [`regles/secrets.yaml`](fichiers/M25-E27/observabilite/regles/secrets.yaml), [`tests/secrets.test.yaml`](fichiers/M25-E27/observabilite/tests/secrets.test.yaml), [`tableaux/plateforme/openbao.json`](fichiers/M25-E27/observabilite/tableaux/plateforme/openbao.json), [`supervision_temoin.yml.extrait`](fichiers/M25-E27/ansible/inventories/lab/host_vars/mon01/supervision_temoin.yml.extrait), extraits de pare-feu ([bordure](fichiers/M25-E27/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [nœuds](fichiers/M25-E27/ansible/inventories/lab/group_vars/role_coffre/pare_feu_local.yml.extrait), [`kms01`](fichiers/M25-E27/ansible/inventories/lab/host_vars/kms01/pare_feu_local.yml.extrait)), [`supervision.md`](fichiers/M25-E27/medisphere/docs/securite/secrets/supervision.md). Configuration : variables `openbao_telemetrie` et `openbao_metriques_sans_jeton` du gabarit final (E28).

*1. Exposition.* Bloc `telemetry` (`prometheus_retention_time = "24h"`, `disable_hostname = true`) et, dans l'écouteur, `telemetry { unauthenticated_metrics_access = true }` ; un nœud à la fois (`openbao_redemarrer=true --limit …`, en attente d'abord). Choix (A, sans jeton) écrit dans `supervision.md` : un nœud **scellé** ne valide aucun jeton, or c'est quand il est scellé qu'on veut ses métriques. Observé : `/v1/sys/metrics?format=prometheus` d'un nœud scellé répond, avec `vault_core_unsealed{cluster=""} 0`.

*2. Collecte.* Flux bordure (travailleurs → nœuds et `kms01` 8200), pare-feu locaux, MR, `up{job="openbao"}` à 1 pour les quatre cibles.

*3. Alertes.* Sept règles ; les trois pièges de métriques (vérifiés sur la grappe d'essai) sont écrits en tête du fichier : `vault_core_unsealed` et `vault_core_active` existent en **deux** séries par nœud (`cluster=""` à 0, émise avant que le nom de grappe soit connu, et `cluster="<nom>"`) → `max by (instance)` ; un processus arrêté n'émet rien → `or up == 0` ; `vault_autopilot_*` n'est émis que par l'actif ; `vault_audit_log_request_failure` est un **compteur** → `increase(…[5m]) > 0`. Tests : quatre groupes de cas, dont le nœud arrêté, le nœud scellé (`kms01`), la double série `cluster=""`, le compteur stable, l'instantané en retard.

```
admin@adm01:~/src/observabilite$ yq '.spec' regles/secrets.yaml > build/regles/secrets.yml && cd tests && promtool test rules secrets.test.yaml
Unit Testing:  secrets.test.yaml
  SUCCESS
```

*4. Sonde extérieure.* Module `openbao_sante` (`valid_status_codes: [200, 429]`) pour les quatre nœuds, `https_2xx` pour la VIP (seul l'actif répond 200 : si la VIP est sur un nœud en attente ou nulle part, la sonde le voit).

*5. Tableau.* Onze panneaux (état, actif, tolérance, index Raft, dernier contact, requêtes, latence, baux, échecs d'audit, âge de l'instantané, appels au seal). La durée restante du jeton de `kms01` n'est **pas** une métrique : `supervision.md` dit pourquoi et renvoie à RB-251.

*6. Épreuve.* `bao operator seal` ne s'adresse qu'au nœud actif (et le scellerait : bascule). Pour un nœud en attente : `sudo systemctl stop openbao` (le processus disparaît : c'est `up == 0` qui déclenche `OpenBaoScelle`), ou redémarrage pendant que `kms01` est arrêté (vrai nœud scellé… qui ne démarre même pas, cf. E25). Alerte reçue à `astreinte@`, puis résolue.

**Explications**

OpenBao hérite de la télémétrie de Vault (bibliothèque go-metrics, préfixe `vault_`) : des résumés (`_count`, `_sum`, quantiles), des compteurs sans suffixe `_total`, des jauges. L'état important (scellé, actif, quorum) est en jauges ; l'audit et le seal en compteurs.

**Alternatives**
- Jeton de lecture (`sys/metrics`) dans un Secret de `supervision` : métriques muettes quand le nœud est scellé.
- Seulement la sonde `sys/health` : suffit pour « vivant / scellé / actif », ne dit rien du quorum, de l'audit, des baux.
- Métriques de l'audit par Loki (nombre de requêtes par chemin, refus) : complémentaires (M25-E21), pas un remplacement.

**Pièges classiques**
- `vault_core_unsealed == 0` sans `max by` : l'alerte sonne en permanence sur la série `cluster=""`.
- Alerte « scellé » sans `up` : un nœud arrêté est silencieux, donc « pas scellé ».
- Collecter la VIP au lieu des nœuds : on ne voit qu'un nœud à la fois, et jamais `kms01`.
- `vault_audit_log_request_failure > 0` sans `increase` : l'alerte ne s'éteint jamais après un incident.

**En production chez MédiSphère**
SLO de disponibilité du coffre (requêtes réussies sur la VIP, M21-E26) ; alertes du ruler de Loki sur l'audit (M25-E21) ; tableau dans le dossier « Plateforme » de Grafana, lien depuis RB-251.

---

### M25-E28 — Durcir OpenBao : jeton racine, enveloppement, systemd, TLS

**Solution**

Fichiers : gabarit final [`openbao.hcl.j2`](fichiers/M25-E28/ansible/roles/openbao/templates/openbao.hcl.j2), surcharge [`medisphere.conf.j2`](fichiers/M25-E28/ansible/roles/openbao/templates/medisphere.conf.j2), [variables](fichiers/M25-E28/ansible/roles/openbao/defaults/main.yml.extrait), [`group_vars/role_coffre/openbao.yml`](fichiers/M25-E28/ansible/inventories/lab/group_vars/role_coffre/openbao.yml) et [`role_kms/openbao.yml`](fichiers/M25-E28/ansible/inventories/lab/group_vars/role_kms/openbao.yml) (état en fin d'E28) ; dans `plateforme/secrets` : [`plateforme-admin.hcl.extrait`](fichiers/M25-E28/secrets/politiques/plateforme-admin.hcl.extrait), [`methodes.tf.extrait`](fichiers/M25-E28/secrets/tofu/methodes.tf.extrait), [`quotas.tf`](fichiers/M25-E28/secrets/tofu/quotas.tf) (et [`tofu-secrets.hcl.extrait`](fichiers/M25-E28/secrets/politiques/tofu-secrets.hcl.extrait) pour que le pipeline les gère), [`wb-checks.hcl.extrait`](fichiers/M25-E28/secrets/politiques/wb-checks.hcl.extrait) (lecture des quotas par les vérifications), [`outils/secret-id-enveloppe.sh`](fichiers/M25-E28/secrets/outils/secret-id-enveloppe.sh) ; dans `plateforme/ansible` : [`openbao-parts-p3.sh`](fichiers/M25-E25/ansible/outils/openbao-parts-p3.sh) (sous-commandes `racine-*`) ; documentation : [`procedure-jeton-racine.md`](fichiers/M25-E28/medisphere/docs/securite/secrets/procedure-jeton-racine.md), [`durcissement-openbao.md`](fichiers/M25-E28/medisphere/docs/securite/secrets/durcissement-openbao.md).

*1. Jeton racine.* Preuves qu'il n'en existe aucun : (a) l'audit (Loki, locataire `audit`) : `count_over_time({service="openbao"} |= `"token_policies":["root"]` [24h])` vaut 0 ; (b) les accesseurs : `bao list auth/token/accessors` puis `bao token lookup -accessor <A>` pour chacun (la politique `wb-checks` sait le faire, c'est ce que fait le check) : aucun ne porte `root` ; (c) l'alerte `OpenBaoJetonRacineUtilise` (E21) est restée muette. Dans les versions de référence, la génération passe par **`sys/generate-root-token`**, authentifié ; l'ancien `sys/generate-root` non authentifié est désactivé (essayé : 405 « unsupported operation » ; 403 sans jeton sur le nouveau). Politique minimale **essayée** : `read`, `update`, `delete` sur `sys/generate-root-token/attempt` et `update` sur `sys/generate-root-token/update`, **sans** `sudo` — donnée à `plateforme-admin` seulement. Répétition (trois terminaux pour trois dépositaires) :

```
admin@adm01:~/src/ansible$ bao login -method=oidc
admin@adm01:~/src/ansible$ outils/openbao-parts-p3.sh racine-debut
nonce : 3205a6f7-22e0-0bd2-f85a-8f3d17c0d3d3 ; parts requises : 3 ; OTP rangé dans /run/user/1000/openbao-otp
karim@adm01:~/src/ansible$ outils/openbao-parts-p3.sh racine-part 2 ~/cles/karim.age 3205a6f7-22e0-0bd2-f85a-8f3d17c0d3d3
part acceptée : 1/3
…
nadia@adm01:~/src/ansible$ outils/openbao-parts-p3.sh racine-part 4 ~/cles/nadia.age 3205a6f7-22e0-0bd2-f85a-8f3d17c0d3d3
terminé : jeton encodé = A1B2…
admin@adm01:~/src/ansible$ outils/openbao-parts-p3.sh racine-fin A1B2…
jeton racine chargé dans ~/.vault-token. Fais l'action prévue, puis : bao token revoke -self
admin@adm01:~$ bao token lookup -format=json | jq -c .data.policies && bao token revoke -self && bao login -method=oidc
["root"]
```

Le décodage se fait **localement** (encodé XOR OTP, essayé) : `bao operator generate-root -decode=… -otp=…` mettrait les deux sur une ligne de commande, et les deux réunis **sont** le jeton. Les réponses du nouveau point d'accès sont enveloppées dans `.data` (contrairement à l'ancien). Les parts utilisées sont les **clés de récupération** (depuis E25). Pour `kms01` : même procédure avec `PARTS_FICHIER=secrets/kms01-init.yml PARTS_CLE=kms01_init` et le jeton `vault_kms01_jeton_generation` chargé par `bao login -`.

*2. Enveloppement.*

```
admin@adm01:~/src/secrets$ JETON=$(outils/secret-id-enveloppe.sh medictl)          # jeton d'enveloppement seul, 5 min
admin@adm01:~$ printf '%s' "$JETON" | bao write -format=json sys/wrapping/lookup token=- | jq -c '.data | {creation_path, creation_ttl}'
{"creation_path":"auth/approle/role/medictl/secret-id","creation_ttl":300}
admin@adm01:~$ BAO_TOKEN="$JETON" bao unwrap -format=json | jq -r '.data.secret_id' | install -m 600 /dev/stdin ~/.config/medictl/secret_id   # (destinataire)
admin@adm01:~$ BAO_TOKEN="$JETON" bao unwrap
Error unwrapping: … wrapping token is not valid or does not exist
```

(`token=-` lit l'entrée standard : `printf '%s'`, pas `<<<`, qui ajoute un saut de ligne et rend le jeton « invalide » — essayé ; `bao unwrap` sans argument déballe le jeton courant, ici passé par l'environnement, jamais en argument.) Un second déballage échoue : si le destinataire voit cette erreur, quelqu'un a déballé avant lui ; l'audit dit qui (`sys/wrapping/unwrap`, identité, adresse). Pour `openbao-instantanes`, le rôle Ansible prend un jeton d'enveloppement (`openbao_instantane_secret_id_enveloppe`, passé par `-e @fichier-chiffré`) et le nœud déballe lui-même (tâche du rôle, essayée avec `curl` contre le banc) : le `secret_id` ne transite jamais en clair par Ansible. Dans l'audit : réponse de `auth/approle/role/<rôle>/secret-id` avec un bloc `wrap_info` (et sans `data`).

*3. Unité.* Surcharge `medisphere.conf` (gabarit final) : `ProtectSystem=strict`, `ReadWritePaths=/var/lib/openbao /var/log/openbao`, `ProtectHome`, protections du noyau, de l'horloge, du nom d'hôte, `ProtectProc=invisible`, `RestrictAddressFamilies`, `RestrictNamespaces`, `LockPersonality`, `MemoryDenyWriteExecute`, `SystemCallFilter=@system-service` avec `SystemCallErrorNumber=EPERM` (un appel refusé apparaît en erreur dans le journal au lieu de tuer le processus). Le fichier du paquet n'est pas modifié (c'est un fichier de configuration du paquet : dpkg poserait une question à chaque montée). `systemd-analyze security openbao.service` : note le score avant et après (l'unité du paquet part déjà de `ProtectSystem=full`, `NoNewPrivileges`, `CapabilityBoundingSet=CAP_SYSLOG`). Un nœud en attente à la fois ; après chaque redémarrage, `journalctl -u openbao -p warning` vide.

*4. Écouteur.* `tls_min_version = "tls13"`, `disable_unauthed_generate_root_endpoints = true` (déjà le comportement par défaut : l'écrire empêche qu'une valeur par défaut changeante le rouvre), `custom_response_headers` (`X-Content-Type-Options`, `X-Frame-Options`). Avant d'ajouter : `curl -sI …/v1/sys/health` montre déjà `strict-transport-security: max-age=31536000; includeSubDomains` et `cache-control: no-store` ; l'interface (`/ui/`) envoie sa propre `content-security-policy` et `x-content-type-options`. Preuves (essayées) :

```
admin@adm01:~$ openssl s_client -connect vault01.par1.medisphere.internal:8200 -tls1_2 </dev/null 2>&1 | grep -m1 alert
…:tlsv1 alert protocol version:…
admin@adm01:~$ curl -sI https://openbao.par1.medisphere.internal:8200/v1/sys/health | grep -i '^x-'
x-content-type-options: nosniff
x-frame-options: DENY
```

*5. Baux.* `default_lease_ttl = "1h"`, `max_lease_ttl = "24h"` dans le gabarit, et un `tune` explicite par méthode ([extrait](fichiers/M25-E28/secrets/tofu/methodes.tf.extrait) ; `oidc` était déjà à 8 h). Deux comportements **essayés** : (a) si `default_lease_ttl` dépasse `max_lease_ttl` (défaut 768 h), le serveur **refuse de démarrer** (`cannot have DefaultLeaseTTL larger than MaxLeaseTTL`) : on écrit toujours les deux ; (b) le maximum plafonne aussi la **période** des jetons périodiques, sans avertissement (d'où `auth/token` relevé sur `kms01`). Les baux déjà émis gardent leur durée jusqu'à leur renouvellement, plafonné alors (documentation).

*6. Quotas.* [`quotas.tf`](fichiers/M25-E28/secrets/tofu/quotas.tf) : `global` (chemin vide, 200/s par client) et `approle-connexion` sur **`auth/approle/login`**, 10 par minute, blocage 5 min. Essayé : un quota sur le montage entier (`auth/approle/`) frappe aussi la lecture des rôles par OpenTofu (`429` au `plan`) ; sur `…/login`, seules les connexions comptent :

```
admin@adm01:~$ for i in $(seq 1 12); do curl -s -o /dev/null -w '%{http_code} ' -d '{"role_id":"x","secret_id":"y"}' https://openbao.par1.medisphere.internal:8200/v1/auth/approle/login; done; echo
400 400 400 400 400 400 400 400 400 400 429 429
```

Vérifie ensuite qu'aucun client légitime ne s'en approche : `lab/bin/check` se connecte **une** fois par vérification (`_m25p_connexion`), les instantanés une fois par heure, `medictl` une fois par lancement. Un second quota identique à un existant est refusé (`quota rule with similar properties exists`).

*7. Preuves* : [`durcissement-openbao.md`](fichiers/M25-E28/medisphere/docs/securite/secrets/durcissement-openbao.md).

**Explications**

Un jeton racine contourne toutes les politiques et n'expire pas : le garder, c'est garder une clé passe-partout. OpenBao le rend **régénérable** à condition de réunir un seuil de clés de récupération (plusieurs personnes) et, depuis la 2.6, d'être déjà authentifié (une personne identifiée lance, d'autres apportent les parts). L'enveloppement remplace le secret à transmettre par une **référence** à usage unique et de courte durée : l'intercepter ne sert qu'une fois et se voit. Le durcissement systemd réduit ce qu'un processus compromis peut toucher ; il ne protège pas les secrets en mémoire (d'où `LimitCORE=0`, `MemorySwapMax=0`).

**Alternatives**
- Garder un jeton racine sous scellé (enveloppe papier, Vault `critique`) : rapide en crise, mais un jeton qui existe peut fuir ; la régénération à trois est la pratique recommandée.
- Réactiver l'ancien `sys/generate-root` non authentifié le temps d'une crise (paramètre d'écouteur) : à réserver au cas où plus aucune méthode d'authentification ne marche (Keycloak perdu **et** pas de jeton de génération) — écrit dans la procédure comme dernier recours.
- *Control Groups* (2.7) : exiger une approbation pour lire certains chemins, au lieu d'un jeton racine pour les gestes rares.
- Quotas « nombre de baux » (`sys/quotas/lease-count`) : utiles contre une application qui fuit ses identifiants dynamiques.

**Pièges classiques**
- Décoder le jeton avec `-decode=… -otp=…` sur la ligne de commande (visible par `ps`, historique).
- Oublier de révoquer le jeton racine régénéré, ou de revenir à l'identité OIDC (le `~/.vault-token` reste celui du jeton racine).
- `ProtectSystem=strict` sans `ReadWritePaths` pour `/var/log/openbao` : l'audit ne peut plus écrire, OpenBao **refuse toutes les requêtes** (`OpenBaoAuditEnEchec`).
- Quota sur `auth/approle/` : OpenTofu, les checks et `medictl` reçoivent des 429.
- `max_lease_ttl` seul dans la configuration : le serveur ne démarre plus.

**En production chez MédiSphère**
Revue trimestrielle des accesseurs et de l'audit des générations ; scénarios de crise répétés (Keycloak perdu : jeton de génération et parts) ; durcissement de l'hôte par le rôle `durcissement` (M26) et contrôle de l'unité par `systemd-analyze security` dans la CI des rôles.

---

### M25-E29 — Monter de version la grappe sans coupure

**Solution**

Fichiers : extraits de version ([`role_coffre`](fichiers/M25-E29/ansible/inventories/lab/group_vars/role_coffre/openbao.yml.extrait), [`role_kms`](fichiers/M25-E29/ansible/inventories/lab/group_vars/role_kms/openbao.yml.extrait)), [`paquet.yml.extrait`](fichiers/M25-E29/ansible/roles/openbao/tasks/paquet.yml.extrait), [RB-253](fichiers/M25-E29/medisphere/docs/securite/secrets/runbooks/RB-253-montee-de-version-openbao.md).

*1. Notes de version* (2.7.0, puis 2.7.1) : stockage `file` supprimé du serveur (nous : Raft) ; seals `awskms`, `azurekeyvault`, `gcpckms`, `ocikms`, `alicloudkms`, `pkcs11` et distribution HSM retirés (greffons KMS externes) — nous : `transit`, intégré ; méthodes LDAP, Kerberos, RADIUS et moteur LDAP en greffons — aucun chez nous ; `plugin_auto_register` vrai par défaut — aucun greffon externe ; FQDN à point final refusés par la PKI (Go 1.27) — à vérifier dans les rôles de `pki-services` et les `Certificate` de cert-manager ; nouvelles options `tls_auto_reload` (le rechargement par SIGHUP de `cert-renewer@openbao` reste valable) ; **le fichier de configuration du paquet change** (2.7.1 : stockage `pebbledb` dans `/opt/openbao/data`) — le rôle installe avec `force-confold` et garde le nôtre ; à la main, dpkg pose la question : répondre **N**. Ce qui ne nous concerne pas : module Go déplacé, en-tête `X-Vault-Request` de l'agent et du proxy (nous ne les utilisons pas).

*2. Retour arrière, essayé.* Sur le banc, un nœud en attente monté en 2.7.1 puis redescendu en 2.6.4 **démarre et se descelle**, mais son journal montre `read-only post-unseal setup failed: failed to load response wrapping policy: check-and-set parameter did not match the current version`. Conclusion écrite dans RB-253 : réinstaller l'ancien paquet n'est pas un retour arrière fiable dès qu'un nœud 2.7.1 a écrit ; le seul retour propre est l'**instantané** pris juste avant, restauré sur une grappe réinstallée en 2.6.4.

*3. Roulement.* Le rôle du palier 1 ne redémarre pas sur un changement de **paquet** (seulement de configuration), et `bao version` lit le binaire sur disque : l'extrait `paquet.yml` ajoute la notification et un contrôle de la version **servie** (`sys/health`, champ `version`). Puis :

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/coffre.yml --limit vault03 -e openbao_redemarrer=true
admin@adm01:~$ curl -s 'https://vault03.par1.medisphere.internal:8200/v1/sys/health?standbyok=true' | jq -c '{version, standby, sealed}'
{"version":"2.7.1","standby":true,"sealed":false}
admin@adm01:~$ bao operator raft autopilot state | grep -E 'Healthy|Failure Tolerance'
Healthy:                         true
Failure Tolerance:               1
```

Puis l'autre nœud en attente ; puis `BAO_ADDR=https://<actif>…:8200 bao operator step-down`, contrôle qu'un nœud **2.7.1** a pris la main, et l'ancien actif. Observé sur le banc : seule l'étape du passage de témoin coupe les écritures (zéro à un échec), versions mélangées sans erreur pendant le roulement.

*4. `kms01`* : `playbooks/kms.yml -e openbao_redemarrer=true`, trois dépositaires, `sys/health` 200 en 2.7.1 ; puis redémarrage d'**un** nœud en attente de la grappe pour prouver que le seal fonctionne avec le nouveau `kms01`.

*5. Vérifications* et *6. RB-253* : voir le runbook.

**Explications**

L'ordre (en attente d'abord, actif en dernier) garantit qu'à aucun moment un nœud **ancien** ne prend la main sur des données qu'une version plus récente a déjà réécrites, et qu'il n'y a qu'**un** passage de témoin. Autopilot d'OpenBao ne fait pas de montée automatisée (la page ne la décrit pas ; c'est une fonction de Vault Enterprise).

**Alternatives**
- Remplacer les nœuds par des VMs neuves en 2.7.1 qui rejoignent (`retry_join`), puis retirer les anciennes (`remove-peer`) : propre, mais demande de la mémoire pour un quatrième nœud.
- Arrêt complet et redémarrage en 2.7.1 : une coupure de quelques minutes, plus simple ; refusé par le ticket.

**Pièges classiques**
- Monter l'actif en premier.
- Accepter le fichier de configuration du paquet à la question de dpkg : nœud neuf, vide, non initialisé, sur `pebbledb`.
- Contrôler la version avec `bao version` (binaire) et non `sys/health` (service).
- Redémarrer un nœud de la grappe pendant que `kms01` est redémarré (scellé).

**En production chez MédiSphère**
Mineures d'abord sur une grappe de recette (restaurée depuis un instantané de la production : E26), fenêtre de changement `CHG-`, playbook de roulement automatisé (Pour aller plus loin), RB-253 relu à chaque mineure.

---

### M25-E30 — Comparer : HashiCorp Vault 2.2

**Solution**

Fichiers : [`essai/vault.hcl`](fichiers/M25-E30/essai/vault.hcl), [`comparatif-vault.md`](fichiers/M25-E30/medisphere/docs/securite/secrets/comparatif-vault.md) ; VM par [`envs/m25`](fichiers/M25-E26/infra/envs/m25/) (`groupes = ["essai"]`, 10.10.99.51).

*1. Installation.* Sur `bao-essai` : `curl -fsSLO https://releases.hashicorp.com/vault/<VERSION>/vault_<VERSION>_linux_amd64.zip` et `vault_<VERSION>_SHA256SUMS` (+ `.sig`) ; `gpg --verify` du fichier d'empreintes avec la clé publique de HashiCorp (récupérée sur leur site, empreinte comparée à celle qu'ils publient), puis `sha256sum -c --ignore-missing`. Utilisateur `vault`, unité minimale (`/etc/vault.d/vault.hcl`, `EnvironmentFile=/etc/vault.d/kms.env`). Démarré avec la configuration d'un nœud OpenBao : **refus** — `disable_mlock must be configured 'true' or 'false'` (Vault ≥ 1.20 l'exige ; OpenBao l'ignore comme « champ inconnu ») : on ajoute `disable_mlock = true` (Raft intégré, pas de swap, et mlock d'un processus qui mappe sa base gonflerait la mémoire verrouillée). Le reste passe tel quel.

*2. Gestes communs* (observés avec Vault 2.2.0) : `vault operator init -recovery-shares=…` avec le seal `transit` vers `kms01` (OpenBao) : **fonctionne** (même API transit ; clé `essai-vault` créée pour l'essai, jeton dans `VAULT_TOKEN`) ; KV v2, politique, AppRole : identiques ; **audit** : `vault audit enable file file_path=…` fonctionne, alors qu'OpenBao refuse (« use declarative, config-based audit device management ») ; instantané Raft : même commande.

*3. Différences.* `vault namespace create equipe` → `enterprise-only feature` ; dans OpenBao 2.6.4, `bao namespace create equipe` fonctionne (observé). Montage `agent-registry/` présent par défaut dans Vault 2.2. Le reste (réplication, HSM, `vault-kube-kms`, *Control Groups*) : lu dans les documentations, reporté comme tel dans le tableau.

*4. Clients.* Le fournisseur OpenTofu est le même (`hashicorp/vault`, MPL) : un `tofu plan` de `plateforme/secrets` contre `bao-essai` (variables `VAULT_ADDR`, `VAULT_TOKEN` d'essai) applique nos ressources ; ESO, `community.hashi_vault`, Cosign parlent l'API Vault : rien ne change côté client hormis l'adresse et les variables d'environnement (`VAULT_*` / `BAO_*`).

*5. Migration* : l'instantané d'OpenBao 2.7.1 restauré (`-force`) dans Vault 2.2.0 est **accepté**, le nœud se descelle, les anciens jetons existent… et le montage `kv/` a **disparu** de la table des montages (observé : seuls `cubbyhole`, `identity`, `sys`, `agent-registry`). Pas de passage par instantané ; dans les deux sens, la migration est applicative (configuration par OpenTofu, secrets KV recopiés par l'API, dynamiques régénérés).

*6. Nettoyage* : `tofu apply -var 'groupes=[]'`, sur `kms01` (jeton racine régénéré) : `bao token revoke -accessor …`, `bao write transit/keys/essai-vault/config deletion_allowed=true` puis `bao delete transit/keys/essai-vault` ; MR qui retire le flux.

*7. Compte rendu* : le fichier lié.

**Explications**

Le fork (Vault 1.14, 2023) a gardé l'API, mais chaque produit évolue : OpenBao a durci des comportements (audit déclaratif après CVE-2025-6000, `generate-root` authentifié, mlock retiré) et ajouté des fonctions que Vault réserve à l'Enterprise (espaces de noms) ; Vault a ajouté des montages et des exigences de configuration. Les clients restent compatibles parce qu'ils ne parlent que les chemins historiques.

**Alternatives**
Comparer aussi Infisical (MIT + commercial) ou Conjur OSS sur le même banc : API différentes, il faudrait réécrire OpenTofu, la CI et Ansible ; noté une ligne chacun dans l'ADR.

**Pièges classiques**
- Réutiliser la clé de transit de la grappe pour l'essai : l'essai saurait déchiffrer la clé racine de la production.
- Oublier `disable_mlock` et conclure que « Vault ne démarre pas sur Debian 13 ».
- Juger la licence sur un résumé : lire la BUSL et l'*Additional Use Grant*, et écrire la conclusion comme une lecture, pas comme un avis juridique.

**En production chez MédiSphère**
Refaire l'essai à chaque mineure majeure de l'un ou l'autre (divergence d'API), et quand l'ADR-0250 arrive à sa révision.

---

### M25-E31 — ADR : le coffre de MédiSphère et le chiffrement d'etcd

Modèles : [`ADR-0250-coffre.md`](fichiers/M25-E31/medisphere/docs/securite/secrets/adr/ADR-0250-coffre.md), [`ADR-0251-chiffrement-etcd.md`](fichiers/M25-E31/medisphere/docs/securite/secrets/adr/ADR-0251-chiffrement-etcd.md). Les valeurs `<MESURE>` viennent de **tes** comptes rendus (E24, E25, E26, E29) : un ADR qui ne cite pas ses mesures n'aide pas le comité.

Points d'évaluation :
- ADR-0250 : trois produits au moins **et** une option qu'on écarte pour une vraie raison (le nuage public : souveraineté et juridiction des données de santé, pas « c'est cher ») ; la comparaison des seals montre la propriété clé (où est la clé qui ouvre la clé racine, et qui peut la voler avec les données) ; conséquences négatives avec action : `kms01` point unique au démarrage, un seul hyperviseur, pas de réplication, ESO *alpha*, divergence d'API, dépendance de la sauvegarde à Ansible Vault.
- ADR-0251 : dit **explicitement** que la promesse du M14 (« KMS v2 avec le coffre au M25 ») et de l'ADR-0160 (KEK dans un KMS externe) n'est pas tenue, pourquoi (aucun plugin KMS v2 maintenu pour OpenBao ; `vault-kube-kms` = Vault Enterprise et bêta ; Trousseau abandonné ; fournisseurs KMS de ceph-csi non documentés avec OpenBao), ce qui compense, et à quelle condition **observable** on rouvre (publication d'un plugin maintenu, sortie de bêta + licence, refus d'un auditeur, HSM).
- Erreur fréquente : présenter un plugin KMS v2 « maison » comme une solution simple. Il se place sur le chemin de **chaque** lecture de Secret par le serveur d'API, sur les trois nœuds de contrôle, avec une dépendance de démarrage au coffre : c'est un composant critique sans communauté.

---

### M25-E32 — Questions de production : secrets

1. **Secret zéro.** CI : aucun (jeton d'identité signé par GitLab, vérifié par OpenBao ; la confiance est dans GitLab et ses clés). Pods : le jeton de compte de service projeté (signé par le serveur d'API, audience `openbao.medisphere.internal`) ; la confiance est dans le cluster. Ansible (pipeline) : JWT de CI ; Ansible sur `adm01` par une personne : OIDC. `medictl` et instantanés : un `secret_id` AppRole sur disque (lié à une adresse, enveloppé à la livraison) — c'est le secret zéro le plus classique. Grappe → `kms01` : le jeton périodique de `kms.env`. **Le plus fragile** : le jeton de `kms01` (il ouvre la clé racine de toute la grappe, il vit sur trois disques) ; compensé par sa politique (chiffrer/déchiffrer une seule clé), le filtrage de `kms01` (seuls les trois nœuds), l'absence de valeur utile sans les données chiffrées, et l'audit de `kms01`. Les `secret_id` sur disque viennent ensuite (liés à une adresse : moins utiles volés).
2. Oui, lisibles : `rotate` ajoute une version, les anciennes restent utilisables pour **déchiffrer** tant que `min_decryption_version` le permet. Ordre : rotation → réécriture de chaque fichier (SOPS : ré-chiffrement de la clé de données par la nouvelle version, `rewrap` côté transit) → contrôle qu'aucun fichier ne référence plus l'ancienne version → `min_decryption_version` relevé → éventuellement `trim`. Relever avant de réécrire = fichiers illisibles.
3. Refus argumenté : un identifiant de 30 jours ressemble à un mot de passe statique (fuite exploitable 30 jours, rien à révoquer « vite »), multiplie les rôles vivants dans PostgreSQL et le coût de révocation. Les reconnexions coûtent peu (un pool qui renouvelle avant expiration, ESO qui rafraîchit toutes les 30 min). Proposer : TTL 1 h, `max_ttl` 24 h, et un pool configuré pour recréer ses connexions (durée de vie des connexions < TTL).
4. Grappe Raft étendue : écritures soumises à la latence inter-sites, quorum à répartir sur trois sites (deux ne suffisent pas : un site qui tombe emporte la majorité), coffre coupé en cas de partition. Grappe indépendante à PAR2 alimentée par les instantanés horaires : RPO 1 h, RTO = restauration (E26), simple, mais lecture seule en pratique (ou divergence si on y écrit). Réplication (performance/DR) : **Vault Enterprise** seulement. Pour un RPO d'une heure : grappe indépendante + instantanés (et `kms01` de PAR2 ou une seconde clé de transit).
5. Côté OpenBao : un bail par identifiant (mémoire, révocations, stockage Raft), charge d'expiration ; côté base : création/suppression de rôles, droits à donner, verrous de catalogue, connexions plus nombreuses ; côté application : reconnexions, gestion de l'expiration, dépendance au coffre au démarrage. Cas où un statique tourné vaut mieux : un client qui ne sait pas recharger ses identifiants sans redémarrer et dont le redémarrage est coûteux (vieille application PHP de Legacy-RDV), ou un service tiers sans API de création d'utilisateurs.
6. Un HSM garderait les clés racines **hors** de toute VM : le seal (à la place de `kms01`, greffon PKCS#11 KMS en 2.7), la clé de la CA intermédiaire de services, la clé de signature Cosign (clés externes de transit/PKI en 2.7). Attaques couvertes : vol ou copie d'une VM (y compris `kms01`), extraction de clé par un administrateur système. Intégration : greffon KMS externe (`openbao-plugins`), configuration du seal par le greffon, haute disponibilité du HSM lui-même (deux appareils), et une nouvelle cérémonie.
7. Lecture de `kv/data/mediagenda/prod/*` : l'identité ESO de `mediagenda-prod` (rôle `eso-mediagenda-prod`), et quiconque a une politique qui couvre ce chemin (`plateforme-admin` **ne l'a pas** ; vérifier `bao policy read` de chaque politique, et les groupes externes). Peut se donner le droit : qui peut **modifier les politiques** (pipeline de `plateforme/secrets` après MR, `plateforme-admin` directement par l'API). L'auditeur le verrait dans l'audit (écriture de politique, alerte `OpenBaoPolitiqueModifiee`) et dans l'historique Git. Rendre impossible pour une seule personne : retirer `sys/policies/acl/*` en écriture à `plateforme-admin` (seul le pipeline, après MR **approuvée par un autre**), *Control Groups* sur les chemins sensibles, et alerte sur tout jeton racine.
8. L'audit (Loki, locataire `audit`, un an) : requêtes de lecture de `kv/data/mediagenda/prod/…` ce jour-là, identité (nom d'affichage, entité, rôle), adresse ; pour les identifiants dynamiques, `db-mediagenda/creds/…` et l'identifiant de bail ; les valeurs et jetons sont en HMAC (`sys/audit-hash/fichier` pour vérifier qu'une valeur donnée correspond). Limites : rétention, HMAC (on ne lit pas le secret, on le reconnaît), lecture par un pod = l'identité du compte de service, pas la personne. Intégrité : journal écrit sur deux supports (fichier local + Loki), Loki en écriture seule pour Alloy, alertes sur les trous, et (mieux) un second dispositif d'audit vers un collecteur à écriture unique.
9. Ne **rien** redémarrer ; restaurer `kms01` depuis PBS (RB-251 § 7) ; si impossible : tant que la grappe tourne, exporter ce qui peut l'être (KV), préparer une grappe neuve avec un nouveau seal, réinjecter ; prévenir. Si un nœud redémarre avant : il reste arrêté (seal injoignable) ; à trois nœuds on en perd un, à deux de plus le coffre s'arrête et **toutes les données sont perdues** sauf ce qu'on a exporté (les instantanés sont illisibles sans la clé).
10. `bao token lookup` (s'il est encore valide) ou par l'accesseur trouvé dans l'audit (HMAC du jeton : `sys/audit-hash`) : politiques, création, entité ; l'audit sur la fenêtre : chemins lus avec ce jeton. Révoquer : le jeton (et ses enfants), puis tourner chaque secret qu'il a lu (RB-250). Ne pas révoquer : l'identité de la machine elle-même si elle est légitime (le compte de service), ni « tous les jetons » (coupure générale) ; réduire les journaux qui l'ont exposé.
11. Raft réplique **les erreurs aussi** : une suppression est appliquée sur les trois nœuds en quelques millisecondes. Ce qui protège : les versions de KV (suppression douce, `undelete`, sauf `destroy`/`metadata delete`), Git pour la configuration (`plateforme/secrets`), et l'**instantané** (RPO 1 h) — restauration de la grappe entière, ou restauration sur une copie isolée pour récupérer une valeur.
12. Cinq nœuds sur un seul hyperviseur : tolérance de deux pannes de **VM**, aucune contre la perte de `pve01` (même domaine de panne) ; écritures plus lentes (quorum de 3 sur 5) ; deux Go de mémoire de plus. Utile seulement si les nœuds sont sur des hôtes ou des sites différents.

---

### M25-E33 — Une politique de rotation automatisée

Une solution (d'autres sont valables si elles respectent les contraintes) :

- [`politique-rotation.md`](fichiers/M25-E33/medisphere/docs/securite/secrets/politique-rotation.md) : vingt types, période, méthode, automatique ou non, propriétaire, preuve, alerte ; ce qui reste manuel et pourquoi. [`RB-254-rotation.md`](fichiers/M25-E33/medisphere/docs/securite/secrets/runbooks/RB-254-rotation.md).
- Pipeline planifié de `plateforme/secrets` ([`.gitlab-ci.yml.extrait`](fichiers/M25-E33/secrets/.gitlab-ci.yml.extrait)) : connexion par jeton d'identité (`jwt=-` : le jeton passe par l'entrée standard, jamais en argument), rôle [`ci-secrets-rotation`](fichiers/M25-E33/secrets/tofu/rotation.tf) lié au projet, à `main` protégée, jeton *batch* de 15 min ; [politique](fichiers/M25-E33/secrets/politiques/ci-secrets-rotation.hcl) : `read`, `update`, `patch` sur `kv/data/plateforme/*`, `patch` des métadonnées, `rotate-root` des connexions de bases ; rien d'autre.
- Rotations ([`outils/rotation/`](fichiers/M25-E33/secrets/outils/rotation/)) : **clients Keycloak** (`client-keycloak.sh` : régénération par le compte `svc-rotation` du royaume — rôle `manage-clients` exigé par Keycloak 26.8 —, nouvelle version KV, l'ancien secret reste valable comme « secret tourné » ; `client-keycloak-verifier.sh` quinze minutes plus tard : le nouveau secret est accepté — Keycloak répond `unauthorized_client` au lieu d'`invalid_client` quand on présente un secret **juste** avec un grant interdit, sans créer de session —, le consommateur est sain, puis invalidation de l'ancien) ; **jetons GitLab** (`jeton-gitlab.sh` : création d'un jeton neuf plutôt que l'API `rotate`, qui révoque l'ancien sur-le-champ ; révocation de l'ancien après vérification) ; **compte de service** (`rotate-root` du rôle PostgreSQL `openbao` des deux connexions : seul OpenBao le connaît).
- **Âges** ([`controle-ages.sh`](fichiers/M25-E33/secrets/outils/rotation/controle-ages.sh), essayé) : métadonnées `proprietaire` et `rotation` sur chaque secret de `kv/plateforme/` (posées par `bao kv metadata patch`, ou par `custom_metadata` de `vault_kv_secret_v2` pour les secrets créés par OpenTofu — essayé) ; âge = `created_time` de la **version courante** : `updated_time` change aussi quand on ne modifie que les métadonnées (observé), il ferait passer un secret ancien pour neuf. Le job échoue → courriel du pipeline à `plateforme@`.
- Clés : `bao write -f transit/keys/sops-plateforme/rotate` (par `plateforme-admin`), réécriture des fichiers SOPS, puis `min_decryption_version` ; trousseau : `bao operator rotate` (chemin `sys/rotate/keyring`, observé) en cérémonie (`procedure-jeton-racine.md` : `plateforme-admin` n'a volontairement pas `sys/rotate`).

Pièges : `bao kv put` au lieu de `patch` (efface les autres champs du secret) ; `rotate` de GitLab (coupure) ; invalider l'ancien secret Keycloak avant que le consommateur ait suivi ; politique de rotation sans propriétaire ni preuve ; jeton d'identité passé en argument de `bao write`.

---

### M25-E34 — Rotation d'urgence en temps limité

Démarche attendue (journal de référence, à comparer au tien) :

1. **T0 + 0 à 5 min — périmètre.** RB-250 : quels secrets (client `grafana`, `kv/plateforme/grafana/oidc` ; robot Harbor de tirage de la recette, `kv/mediagenda/recette/harbor-pull`), qui les consomme (Grafana par l'`ExternalSecret` de `supervision` ; les kubelets qui tirent les images de `mediagenda-recette` par le Secret `harbor-pull`, produit par l'`ExternalSecret` du même nom), où ils sont copiés (Secrets Kubernetes, ticket — à faire purger), qui les a lus depuis la fuite (audit : lectures de ces chemins).
2. **Grafana (5 à 20 min).** `outils/rotation/client-keycloak.sh grafana plateforme/grafana/oidc` (ou la même chose à la main dans la console de Keycloak puis `bao kv patch … client_secret=-`) ; forcer le rafraîchissement de l'`ExternalSecret` (annotation `force-sync`, permise) ; Reloader redémarre Grafana (ou annotation de gabarit, M25-E15) ; connexion SSO essayée ; **puis** invalidation de l'ancien secret (`client-keycloak-verifier.sh`, ou « invalider le secret tourné » dans la console). Sans politique de secret tourné, l'ancien secret meurt immédiatement : quelques secondes d'échec de connexion SSO pour qui se connecte à ce moment-là (les sessions ouvertes continuent), acceptable et à écrire dans le journal.
3. **Robot Harbor (20 à 40 min).** Sans coupure, il faut que **deux** identifiants soient valables le temps de la bascule : un robot ne porte qu'un secret, donc on crée un **second** robot de tirage (projet `mediagenda`, droit `pull` seul, même durée de vie que le premier) dans Harbor, on écrit son `dockerconfigjson` dans une nouvelle version de `kv/mediagenda/recette/harbor-pull` (par l'entrée standard, sans l'afficher), on force le rafraîchissement de l'`ExternalSecret` `harbor-pull` (annotation `force-sync`), puis on prouve qu'un tirage passe avec le nouveau Secret (redémarrage contrôlé d'un pod de la recette avec `imagePullPolicy: Always` le temps de l'essai, ou un pod de diagnostic de `mediagenda-recette` qui tire l'image de l'API) ; **puis** on supprime l'ancien robot dans Harbor. Les pods en marche ne sont pas touchés : un identifiant de tirage ne sert qu'au démarrage d'un pod sur un nœud. Preuve que l'ancien est refusé : `curl -u` sur le point de jeton de Harbor (`/service/token`) avec l'ancien identifiant lu depuis la copie du ticket conservée en preuve (fichier 600, jamais affiché) → **401**. Le journal d'audit de Harbor garde la création et la suppression des robots.
4. **Preuves (40 à 45 min).** Métadonnées des deux chemins (`bao kv metadata get` : nouvelle version, heure de création) ; audit (écritures par ton identité, lectures par les deux identités ESO **après** l'écriture) ; état des deux `ExternalSecret` (`refreshTime`, `Ready`) ; sondes du témoin et taux d'erreurs de la recette sur la fenêtre.
5. **Reste à faire** (écrit, pas forcément fait dans le temps) : purge du ticket et de ses copies (courriels), rotation des sessions Grafana ouvertes si l'on craint un usage du secret de client (un secret de client volé permet d'échanger un code d'autorisation volé : sans code, il ne sert à rien), revue de qui a lu les deux chemins depuis la fuite, rappel à Lucas (RB-250, communication).

Ce que vérifie `lab/bin/check 25 34` : nouvelles versions KV après T0, secret du client régénéré dans Keycloak après T0, `ExternalSecret` rafraîchis après T0 et prêts, moins d'une minute d'indisponibilité (sonde de Grafana sur le témoin, minutes à plus de 50 % de 5xx sur la recette), journal sur `main` avec cinq étapes horodatées et des preuves. Il ne peut pas vérifier que les **anciens** secrets sont refusés (il faudrait les connaître) : c'est ton journal qui le prouve.
