# RB-061 — Restaurer un service socle depuis la sauvegarde applicative (PAR2)

| | |
|---|---|
| Services | PowerDNS + Kea (`dns01`), NetBox (`nbx01`), step-ca (`ca01`) |
| Sauvegardes | quotidiennes, rôle `sauvegarde_pbs` : `wb-backup-socle.timer` (dns01 01:55, ca01 02:00, nbx01 02:05) → PBS `ds-lab`, espace `par1/<hôte>`, groupe `host/<hôte>`, archive `socle.pxar`, chiffrée côté client |
| Rédigé | M06-E28 (PLAT-754) — testé le AAAA-MM-JJ sur la VM 2068, voir `../tests/restauration.md` |
| RPO | ≤ 24 h (dernière sauvegarde de la nuit) ; DNS et DHCP : quasi nul tant que `dns02` vit (copies vivantes) |
| RTO mesuré | PowerDNS __ min · NetBox __ min · step-ca __ min |

## 0. Choisir la bonne méthode

| Situation | Méthode |
|---|---|
| La VM entière est perdue ou corrompue, la sauvegarde de nuit `lab-nuit` est bonne | **RB-002** (restaurer la VM) : plus simple et plus rapide |
| Une donnée est perdue ou abîmée (zone supprimée, objets NetBox écrasés par une synchronisation, base step-ca corrompue) et le reste de la VM est sain | ce runbook, sur l'hôte en place |
| Reconstruction sur une autre machine (migration, PRA) | OpenTofu + Ansible (RB-060) recréent l'hôte, puis ce runbook remet les données |
| Test périodique | ce runbook sur la VM 2068 `m06-restau` (§5) |

**`dns02` n'a pas de sauvegarde applicative** : ses zones sont une copie de `dns01` (AXFR) et ses baux une copie de ceux de `dns01` (HA). On le reconstruit par le code ; il se remplit seul.

## 1. Ce qu'il faut avoir sous la main

- La **clé de chiffrement** de l'hôte (`pbs-<hôte>.key` : copie hors ligne, ou reconstruite depuis la *paperkey*, M00-E36). Elle est aussi dans Vault (`vault_pbs_cle_<hôte>`) : Vault et la copie hors ligne doivent être **indépendants** du site perdu.
- Un jeton PBS capable de **lire** `par1/<hôte>` : celui de l'hôte (`DatastoreBackup` permet de relire ses propres sauvegardes) ou, en crise, un compte d'administration de PBS.
- `proxmox-backup-client` sur `adm01` (dépôt `pbs-client`).
- Pour step-ca : le mot de passe de la clé de l'intermédiaire (Vault, identité `critique`), **qui n'est pas dans la sauvegarde**.

## 2. Récupérer l'archive (adm01)

```
admin@adm01:~$ set -a; . ~/.config/workbook/pbs-<HÔTE>.env; set +a      # 600, effacé à la fin
admin@adm01:~$ proxmox-backup-client snapshot list --ns par1/<HÔTE>
admin@adm01:~$ proxmox-backup-client catalog dump host/<HÔTE>/<HORODATAGE> --ns par1/<HÔTE> --keyfile <CLÉ> | head -50
admin@adm01:~$ proxmox-backup-client restore host/<HÔTE>/<HORODATAGE> socle.pxar /var/tmp/restau-<HÔTE> --ns par1/<HÔTE> --keyfile <CLÉ>
admin@adm01:~$ cd /var/tmp/restau-<HÔTE> && sha256sum -c SHA256SUMS
```

Puis copie vers l'hôte cible (`scp -r … <CIBLE>:/var/tmp/`), droits 700.

## 3. PowerDNS et Kea (dns01)

**Préalable** : `dns02` sert le DNS et le DHCP pendant l'opération (vérifier `status-get` : RB-062 §1).

*PowerDNS* (base complète) :
```
admin@dns01:~$ sudo systemctl stop pdns
admin@dns01:~$ sudo sh -c 'mkdir /var/lib/powerdns/avant-restau && cp -a /var/lib/powerdns/pdns.sqlite3* /var/lib/powerdns/avant-restau/'
admin@dns01:~$ sudo rm -f /var/lib/powerdns/pdns.sqlite3-wal /var/lib/powerdns/pdns.sqlite3-shm   # un journal restant serait rejoué sur la base restaurée
admin@dns01:~$ sudo install -o pdns -g pdns -m 0640 /var/tmp/restau-dns01/powerdns/pdns.sqlite3 /var/lib/powerdns/pdns.sqlite3
admin@dns01:~$ sudo -u pdns sqlite3 /var/lib/powerdns/pdns.sqlite3 'PRAGMA integrity_check;'      # sous pdns : aucun fichier créé au nom de root
admin@dns01:~$ sudo systemctl start pdns
```
⚠️ **Numéros de série** : la base restaurée a des numéros de série **plus anciens** que ceux de `dns02`. `dns02` ne retransférera pas (il croit être à jour) et continuera de servir les données récentes. Après restauration, pour chaque zone : `sudo -u pdns pdnsutil zone increase-serial <ZONE>` jusqu'à dépasser le numéro de série de `dns02` (ou, plus simple, régler le numéro de série au-dessus de celui de `dns02` avec la méthode de M06-E32, question 3), puis vérifier l'égalité des numéros sur 10.10.20.10:5300 et 10.10.20.16:5300.

Les clés DNSSEC sont **dans** la base : la zone restaurée garde sa clé, les ancres des récurseurs restent valables. Si la sauvegarde précède un roulement de clé (RB-064), vérifier `pdnsutil zone list-keys` contre les ancres **avant** de redémarrer.

*Une seule zone* (erreur humaine) : préférer réinjecter les enregistrements par le code (OpenTofu, synchronisation NetBox de M06-E15) ; la base restaurée sert de référence (ouvre la copie avec `sqlite3` et compare la table `records`).

*Kea* : les baux se reconstruisent seuls (`dns02` les a ; à défaut, les clients les redemandent au renouvellement). Restaurer les baux n'est utile qu'après la perte **des deux** serveurs :
```
admin@dns01:~$ sudo systemctl stop isc-kea-dhcp4-server
admin@dns01:~$ sudo install -o _kea -g _kea -m 0640 /var/tmp/restau-dns01/kea/var-lib-kea/kea-leases4.csv /var/lib/kea/kea-leases4.csv
admin@dns01:~$ sudo systemctl start isc-kea-dhcp4-server
```
(L'export JSON `baux-lease4-get-all.json` peut aussi être réinjecté bail par bail avec `lease4-add`.) La configuration de Kea, elle, vient du code (rôle `kea_dhcp4`) ; `etc-kea.tar` sert de référence.

## 4. NetBox (nbx01)

1. Hôte prêt : rôle `netbox` appliqué, **même version** de NetBox que `release.yaml` de l'archive (sinon : restaurer sur la version d'origine, puis monter de version par la procédure officielle), `configuration.py` restauré **ou** redéployé depuis Vault — `SECRET_KEY` et `API_TOKEN_PEPPERS` doivent être identiques à ceux de la sauvegarde, sinon les jetons v2 restaurés sont inutilisables (et les sessions perdues).
2. Restauration de la base :
   ```
   admin@nbx01:~$ sudo systemctl stop netbox netbox-rq
   admin@nbx01:~$ sudo -u postgres dropdb netbox && sudo -u postgres createdb -O netbox netbox
   admin@nbx01:~$ sudo -u postgres pg_restore --no-owner --role=netbox -d netbox /var/tmp/restau-nbx01/netbox/netbox.pgdump
   admin@nbx01:~$ sudo tar -C /opt/netbox/netbox -xf /var/tmp/restau-nbx01/netbox/media.tar
   admin@nbx01:~$ sudo /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py migrate --check   # rien à appliquer attendu
   admin@nbx01:~$ sudo systemctl start netbox netbox-rq
   ```
3. Vérifier : `curl -s -H "Authorization: Bearer $(cat ~/.config/workbook/netbox-checks.token)" https://nbx01.par1.medisphere.internal/api/status/` ; nombre de VMs, préfixes, adresses ; dernier objet modifié (journal des modifications) = veille de la sauvegarde.
4. **Synchronisations** : désactiver le timer de synchronisation Proxmox → NetBox (M06-E11) **avant** la restauration et ne le relancer qu'après vérification : sinon il « corrige » la base restaurée avec l'état réel, ce qui peut être voulu (rattrapage) ou masquer un problème. Décider explicitement (ADR-0060).

## 5. step-ca (ca01)

1. Hôte prêt : paquet `step-ca` de la **même version** (`version.txt`), utilisateur `step`, service arrêté.
2. Restaurer :
   ```
   admin@ca01:~$ sudo systemctl stop step-ca
   admin@ca01:~$ sudo mv /etc/step-ca /etc/step-ca.avant-restau
   admin@ca01:~$ sudo cp -a /var/tmp/restau-ca01/stepca/etc/step-ca /etc/step-ca
   admin@ca01:~$ sudo chown -R step:step /etc/step-ca
   ```
   puis remettre le fichier de mot de passe de l'intermédiaire depuis Vault (rôle `step_ca`, ou à la main en 600 `step:step`), et `sudo systemctl start step-ca`.
3. Vérifier : `curl -s https://ca01.par1.medisphere.internal/health` → `ok` ; `step ca provisioner list` ; émission d'un certificat d'essai (`admin`, 1 h), vérifié contre la racine (`step certificate verify`), puis révoqué (RB-063).
4. Conséquences à connaître :
   - les certificats émis **après** la sauvegarde sont absents de la base restaurée ; leur renouvellement s'appuie sur le certificat présenté et sa chaîne, il devrait rester possible (⚠️ à vérifier sur ta version lors du test : renouvelle un certificat émis entre la sauvegarde et la restauration) ;
   - une révocation faite après la sauvegarde est **perdue** : la rejouer depuis l'historique de RB-063 ;
   - les comptes ACME créés depuis la sauvegarde sont perdus : les clients ACME en recréent un à la prochaine émission.

## 6. Test de restauration (VM 2068) — à faire au moins deux fois par an

⚠️ La VM de test reçoit des **secrets de production** (clé de l'intermédiaire, `SECRET_KEY` de NetBox, base DNS avec clés DNSSEC).

1. VM 2068 `m06-restau` : clone lié de l'image `current`, VNet `vsandbox`, pool `lab`, étiquette `env-m06`, 4 Go (NetBox). Aucun enregistrement DNS, aucun nom de production dans son `/etc/hosts` sauf pour **elle-même** (`127.0.0.1 ca01.par1.medisphere.internal` pour le test de la CA, local à la VM).
2. Avant d'y copier quoi que ce soit : filtrage d'entrée local (nftables, politique `drop`, SSH depuis 10.10.10.10 seulement). Les autres VMs sandbox ne doivent pas pouvoir joindre la CA ni NetBox restaurés.
3. Restaurer les trois services (§3 à §5) en appliquant les rôles Ansible à 2068 avec un inventaire de test (`-i 10.10.99.x,`), émission ACME désactivée (pas d'accès à `ca01` depuis `vsandbox`, et surtout pas de certificat de production pour une VM de test).
4. Preuves (feuille de temps) :
   - PowerDNS : `dig @127.0.0.1 -p 5300 par1.medisphere.internal SOA` = numéro de série de la sauvegarde ; un enregistrement connu présent ; `pdnsutil zone show` montre la clé DNSSEC ;
   - NetBox : `/api/status/` répond ; le jeton des checks (**jeton de production**, preuve des *peppers*) liste les VMs du socle, via `curl --resolve nbx01.par1.medisphere.internal:443:<IP-2068>` depuis `adm01` ;
   - step-ca : `/health` ok, certificat d'essai émis et vérifié par la racine MédiSphère.
5. Fin : `qm stop 2068 && qm destroy 2068 --purge` sur `pve01` ; sur `adm01`, `shred -u` des copies de clés et `rm -rf /var/tmp/restau-*` ; variables PBS effacées de la session.

## Pièges connus

- Restaurer une base DNS ancienne sans relever les numéros de série : `dns02` garde ses données, `dns01` sert les anciennes, les clients reçoivent des réponses différentes selon le résolveur.
- NetBox restauré avec un autre `API_TOKEN_PEPPERS` : tous les jetons v2 deviennent invalides (OpenTofu, synchronisation, checks).
- step-ca : copier la base Badger pendant que le service tourne (copie incohérente) ; oublier que le mot de passe de l'intermédiaire n'est pas dans l'archive.
- Laisser tourner une CA restaurée joignable : elle émet des certificats que tout le socle croit.

## Historique

| Date | Auteur | Changement |
|---|---|---|
| AAAA-MM-JJ | <apprenant> | Création (M06-E28), test sur VM 2068 |
