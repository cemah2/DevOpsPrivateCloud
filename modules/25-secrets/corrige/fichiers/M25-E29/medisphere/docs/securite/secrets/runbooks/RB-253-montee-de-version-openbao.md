# RB-253 — Montée de version d'OpenBao

> `docs/securite/secrets/runbooks/RB-253-montee-de-version-openbao.md` — M25-E29 (CHG-2629). Dernière application : 2.6.4 → 2.7.1, `<DATE>`, durée `<DURÉE>`.

## 1. Préparation (la veille)

1. Lire les notes de version de **chaque** version franchie (`https://openbao.org/community/release-notes/`) et les dépréciations ; écrire l'analyse dans le ticket `CHG-` (ruptures, ce qui nous touche, ce qui ne nous touche pas). Pour 2.7 : stockage `file` supprimé (nous : Raft), seals de nuage et `pkcs11` en greffons (nous : `transit`, intégré), méthodes LDAP/Kerberos/RADIUS et moteur LDAP en greffons (nous : aucun), `plugin_auto_register` vrai par défaut (aucun greffon externe), FQDN à point final refusés par la PKI (vérifier les rôles de `pki-services` et les demandes de cert-manager), nouvelle option `tls_auto_reload` (le SIGHUP de `cert-renewer@openbao` reste).
2. Relever l'empreinte du `.deb` dans `checksums.txt` (signature vérifiée), MR sur `group_vars/role_coffre/openbao.yml` et `group_vars/role_kms/openbao.yml`.
3. Le **fichier de configuration du paquet change** (`/etc/openbao/openbao.hcl` : `file` → `pebbledb` dans `/opt/openbao/data` en 2.7.1). Ansible installe avec `force-confdef,force-confold` (garde le nôtre) ; une installation **à la main** (`apt install ./openbao_….deb`) pose la question de dpkg : répondre **N** (garder la version installée). Accepter la version du paquet = un nœud qui redémarre sur un stockage vide, **non initialisé**.
4. Retour arrière écrit et vérifié (§5) ; dépositaires de `kms01` prévenus (§3).

## 2. Grappe, en roulement (fenêtre : 30 min)

1. Instantané : sur le nœud actif `sudo systemctl start openbao-instantane.service`, puis vérifier l'objet (journal). Garder sa clé dans le ticket.
2. Pour chaque nœud **en attente**, l'un après l'autre :
   `uv run ansible-playbook playbooks/coffre.yml --limit <nœud> -e openbao_redemarrer=true`
   puis : `sys/health` du nœud → `429`, version 2.7.1 ; `bao operator raft autopilot state` → `Healthy`, tolérance 1 ; journal du nœud sans `[ERROR]` nouveau.
3. Nœud actif : `bao operator step-down` (adressé au nœud actif), attendre qu'un nœud **déjà monté** soit actif (`sys/leader`), puis le playbook sur l'ancien actif.
4. Contrôles d'ensemble : trois `version: 2.7.1`, VIP sur l'actif, boucle d'écriture sans trou au-delà du passage de témoin, un pipeline qui lit un secret, un `ExternalSecret` rafraîchi, alertes muettes.

Ordre imposé : nœuds en attente d'abord. Monter l'actif en premier ferait prendre la main par un nœud **ancien** sur des données déjà touchées par la nouvelle version.

## 3. `kms01`, en dernier et seul

Pendant ces minutes, **aucun nœud de la grappe ne peut redémarrer** (ne rien toucher d'autre). Playbook `kms.yml -e openbao_redemarrer=true` → `kms01` redémarre **scellé** → trois dépositaires (RB-251 § 4) → `sys/health` 200, version 2.7.1. Contrôle : redémarrer **un** nœud en attente de la grappe, il doit se desceller seul.

## 4. Ce qu'on a observé (2.6.4 → 2.7.1)

- Indisponibilité en écriture : uniquement au passage de témoin (`<MESURE>`, souvent aucun échec).
- Un nœud monté puis redescendu en 2.6.4 **démarre** et se descelle, mais son journal montre `read-only post-unseal setup failed: failed to load response wrapping policy: check-and-set parameter did not match the current version` : la 2.7.1 a réécrit des structures internes que la 2.6.4 relit mal. Un nœud « qui tourne » n'est pas un nœud sain.

## 5. Retour arrière

- **Pendant le roulement, aucun nœud encore actif en 2.7.1** (seuls des nœuds en attente montés) : reprendre la 2.6.4 sur ces nœuds est possible mais déconseillé (§4) ; préférer finir le roulement si la 2.7.1 fonctionne.
- **Après que la 2.7.1 a écrit** (un nœud 2.7.1 a été actif) : le seul retour arrière propre est l'**instantané** de §2.1 restauré sur une grappe réinstallée en 2.6.4 (RB-252 § 6), avec la perte des écritures faites depuis. Décision : Claire Morel.
- Jamais : redescendre un nœud à la fois en espérant que la grappe « se recale ».

## 6. Durée et charge

Préparation 1 h ; roulement 20 min ; `kms01` 10 min (dépositaires compris) ; contrôles 15 min.
