# RB-243 — Sauvegarder et restaurer l'identité (Keycloak, FreeIPA)

| | |
|---|---|
| Ticket | PLAT-2525 (M24-E25) |
| Portée | `idp01` (Keycloak 26 + PostgreSQL 17), `ipa01` (FreeIPA 4.13) |
| Dernière restauration d'essai | <AAAA-MM-JJ>, Keycloak, RTO mesuré <N> min (§6) |
| Accès nécessaires | Vault `critique` (clé privée age, identité S3), `adm01`, console Proxmox |

## 1. Ce qui est sauvegardé, où, et qui peut le lire

| Quoi | Comment | Où | Fréquence, rétention |
|---|---|---|---|
| Base `keycloak` (royaumes, clés de signature privées, secrets des clients, OTP et WebAuthn, comptes de `master`, sessions persistées) | `pg_dump -Fc` (instantané transactionnel), contrôle `pg_restore --list`, chiffrement age | `s3://identite-sauvegardes/idp01/` | chaque nuit 01:20 ; 35 jours (cycle de vie) ; versionné, non effaçable par l'hôte |
| Annuaire FreeIPA (données LDAP) | `ipa-backup --data --online` | `s3://identite-sauvegardes/ipa01/` et 3 copies locales `/var/lib/ipa/backup/` | chaque nuit 01:30 ; 35 jours |
| FreeIPA complet (configuration, CA Dogtag et ses clés, Kerberos) | `ipa-backup` (services **arrêtés** quelques minutes) | `/var/lib/ipa/backup/ipa-full-*`, puis chiffré et envoyé à la main (§5) | avant chaque changement (RB-245) |
| VMs 1030 et 1031 | `vzdump` mode instantané, tâche `identite-nuit` | PBS `ds-lab`, espace de noms `par1/identite` (stockage `pbs-par2-identite`) | chaque nuit 01:45 ; rétention de la tâche |

**Qui peut lire** : une archive se déchiffre avec la clé **privée** age (Vault `critique` de `plateforme/ansible`, `secrets/identite-sauvegardes.yml`, et copie papier au coffre). L'identité S3 des hôtes peut lire les objets **chiffrés** mais pas les déchiffrer. Une sauvegarde déchiffrée donne **tout** : signer des jetons pour n'importe qui, se faire passer pour n'importe quel service, se connecter en `kc-secours` (empreinte du mot de passe) — d'où l'isolement de toute restauration.

## 2. Contrôles quotidiens

- `lab/bin/check 24 25` ; sur chaque hôte : `systemctl list-timers identite-sauvegarde.timer`, `cat /var/lib/identite-sauvegarde/dernier-succes` (époque, objet, taille) ; échec → courriel `ms-alerte@identite-sauvegarde.service`.
- PBS : `pvesm list pbs-par2-identite` sur `pve01`.

## 3. Récupérer une archive (sur `adm01`, sans fichier clair)

```
admin@adm01:~$ ( set -a; . ~/.config/workbook/s3-identite.env; set +a
>   export RCLONE_CONFIG_IDS3_TYPE=s3 RCLONE_CONFIG_IDS3_PROVIDER=Other RCLONE_CONFIG_IDS3_REGION=us-east-1 \
>     RCLONE_CONFIG_IDS3_ENDPOINT=https://s3-01.par1.medisphere.internal:8333 RCLONE_CONFIG_IDS3_FORCE_PATH_STYLE=true \
>     RCLONE_CONFIG_IDS3_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" RCLONE_CONFIG_IDS3_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
>   rclone lsl ids3:identite-sauvegardes/idp01/ | sort -k2,3 | tail -n 3 )
```

La clé privée est lue dans le Vault et passée à `age` par un descripteur (`-i <(…)`), jamais écrite :

```
admin@adm01:~/src/ansible$ cle() { uv run ansible-vault view secrets/identite-sauvegardes.yml \
>   | sed -n 's/^identite_age_cle_privee: *"\{0,1\}\(AGE-SECRET-KEY-[^"]*\)"\{0,1\}$/\1/p'; }
```

## 4. Restaurer Keycloak

**Sur une VM d'essai** (contrôle trimestriel, ou avant une montée de version : E33) — `idp-resto`, 2242, 10.10.99.42 :

1. `envs/m24` : `groupes = ["resto"]`, apply (≈ 2 min).
2. Isolation et base vide **avant** tout secret : `uv run ansible-playbook -i inventories/essai-resto playbooks/identite-essai-resto.yml --tags isolation,base`. La tâche « Preuve — ipa01 injoignable » doit passer.
3. Restauration en flux (la clé reste sur `adm01`) :
   ```
   admin@adm01:~/src/ansible$ rclone cat ids3:identite-sauvegardes/idp01/<OBJET>.dump.age \
   >   | age -d -i <(cle) \
   >   | ssh admin@10.10.99.42 'sudo -u postgres pg_restore --no-owner --role=keycloak -d keycloak --exit-on-error'
   ```
4. Keycloak de la **même version** que la sauvegarde : `… --tags keycloak` (construction, démarrage).
5. Preuves :
   ```
   admin@adm01:~$ R=--resolve=sso.par1.medisphere.internal:8443:10.10.99.42
   admin@adm01:~$ curl -sk https://10.10.99.42:9000/health/ready | jq -r .status
   admin@adm01:~$ curl -sk $R https://sso.par1.medisphere.internal:8443/realms/medisphere/.well-known/openid-configuration | jq -r .issuer
   admin@adm01:~$ diff <(curl -sk $R https://sso.par1.medisphere.internal:8443/realms/medisphere/protocol/openid-connect/certs | jq -r '.keys[]|select(.use=="sig").kid' | sort) \
   >                   <(curl -s https://sso.par1.medisphere.internal/realms/medisphere/protocol/openid-connect/certs | jq -r '.keys[]|select(.use=="sig").kid' | sort) && echo "kid identiques"
   admin@adm01:~$ for h in idp01 10.10.99.42; do ssh admin@$h "sudo -u postgres psql -d keycloak -XtAc \"SELECT r.name, count(u.id) FROM realm r LEFT JOIN user_entity u ON u.realm_id = r.id GROUP BY r.name ORDER BY 1\""; done
   ```
6. Nettoyage : `groupes = []`, apply (la VM et son disque disparaissent) ; sur `adm01`, rien à effacer (aucun fichier clair n'a été écrit).

**Sur `idp01` (production)** — base perdue ou corrompue, `idp01` sain ou reconstruit (OpenTofu `socle`, rôles communs, `identite.yml` **sans démarrer** : arrêt du service juste après le premier passage) :

1. Annonce (RB-246), session `admin` sur `idp01`, accès de secours des services prêts (RB-240).
2. `sudo systemctl stop keycloak` ; `sudo -u postgres dropdb keycloak && sudo -u postgres createdb --owner=keycloak --encoding=UTF8 keycloak`.
3. Restauration en flux comme ci-dessus, vers `admin@idp01`.
4. `sudo systemctl start keycloak` ; preuves du point 5 ; connexion d'un personnage ; `tofu plan` vide dans `plateforme/identite`.
5. Ce qui manque depuis la sauvegarde (RPO ≤ 24 h) : OTP enregistrés depuis (les personnes concernées le réenregistrent), rotations de secrets ou de clés faites depuis (les rejouer par OpenTofu : le code est la référence), personnes arrivées depuis (la synchronisation de la fédération les rapporte d'elle-même).

## 5. FreeIPA

Une restauration de l'annuaire se fait **sur un serveur réinstallé au même nom** (`ipa01.par1.medisphere.internal`, même royaume, même version) : `ipa-restore` refuse un autre nom, et un second `ipa01` sur le réseau ferait se croiser Kerberos, DNS et les inscriptions des hôtes. On ne la joue donc pas sur une VM jetable du lab ; on joue :

- chaque mois, la **vérification** de l'archive : `rclone cat …/ipa01/<OBJET>.tar.age | age -d -i <(cle) | tar -tvf - | grep -E '/header$|ipa-data'` ;
- en cas de perte d'`ipa01` : **d'abord** la restauration de la VM depuis PBS (`pbs-par2-identite`, VMID 1031, sauvegarde de la nuit : le plus rapide, ≈ <N> min) ; si la VM n'est pas récupérable : réinstallation par `annuaire-serveur.yml` au même nom **avec la même CA** (la sauvegarde complète d'avant le dernier changement contient la CA et ses clés), puis `ipa-restore` de la dernière archive `--data`, puis `ipa-healthcheck`, `kinit admin`, liaison de `svc-keycloak`, connexion d'un personnage à Keycloak.
- Sauvegarde complète manuelle (avant un changement) : `sudo ipa-backup` (services arrêtés ≈ 2 min : Keycloak refuse les connexions pendant ce temps), puis `sudo tar -C /var/lib/ipa/backup -cf - ipa-full-<HORO> | age -r <CLÉ-PUBLIQUE> | rclone rcat ids3:identite-sauvegardes/ipa01/<HORO>-complet.tar.age`.

## 6. RTO et RPO mesurés

| Étape (essai du <AAAA-MM-JJ>) | Durée |
|---|---|
| VM `idp-resto` (OpenTofu) | <N> min |
| Isolation et base vide (playbook) | <N> min |
| Restauration de la base (flux) | <N> s |
| Installation et construction de Keycloak (playbook) | <N> min |
| Premier démarrage et preuves | <N> min |
| **Total (RTO Keycloak, VM neuve)** | **<N> min** |

RPO : 24 h (sauvegarde nocturne) ; avant un changement : sauvegarde à la main, RPO de quelques minutes.
