# Module 02 — Corrigé du palier 4 : Expert

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la même trame qu'aux modules 00 et 01 : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif : « j'ai réinstallé `medictl` et ça remarche » est un échec pédagogique si tu ne sais pas ce qui était cassé, parce que la même cause cassera le poste suivant.

Scripts d'injection : `corrige/pannes/break-E35.sh` à `break-E43.sh` (bibliothèque commune `lab/lib/pannes-lib.sh`) ; scripts « défectueux » et fichiers déposés par les pannes : `corrige/fichiers/M02-EXX/panne/`. Sur chaque hôte modifié, les actions sont journalisées dans `/var/lib/workbook/pannes.log`, avec une copie de l'état d'origine dans `/var/lib/workbook/M02-EXX.*`.

Fichiers de solution : [`fichiers/M02-E37/`](fichiers/M02-E37/), [`M02-E39/`](fichiers/M02-E39/), [`M02-E40/`](fichiers/M02-E40/) (scripts corrigés), [`M02-E41/`](fichiers/M02-E41/) (chien de garde), [`M02-E43/`](fichiers/M02-E43/) (post-mortem d'exemple), [`M02-E44/`](fichiers/M02-E44/) (spécification exécutable et analyse). Les scripts ont été vérifiés avec ShellCheck 0.11 (`-x`), bats-core 1.13 et Bash 5.2 ; les pannes E37 et E39 ont été rejouées sur leurs jeux de données (variantes et contrôles).

Les sorties de commandes reproduites sont **représentatives** : horodatages, PID, numéros de tâche et libellés exacts varient selon tes versions.

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) : le message exact de `pveproxy` pour un jeton expiré ou un compte désactivé (E36), la durée réelle d'un `pvesh` par SSH sur ton matériel (E40 v3 : si l'inventaire passe sous 30 s, l'injection le signale et s'annule), le libellé de `systemctl status` pour un service sauté par une condition (E41 v3), le nom du fichier `.pth` d'installation éditable selon la version de uv (E42 v4).

---

## Méthode commune aux pannes d'outillage

1. **Reproduire dans les conditions réelles** : sous systemd pour un service, dans un clone propre pour la CI, avec le lanceur réellement appelé pour un outil installé. « Chez moi ça marche » est une information sur *chez moi*, pas sur l'outil.
2. **Lire la configuration effective**, pas celle qu'on croit : `systemctl cat`/`show`, `type -a`, `head -n 1` du lanceur, droits **effectifs** d'un jeton, variables héritées d'un groupe GitLab.
3. **Un maillon à la fois** : configuration locale → transport (TLS) → authentification → autorisation → données → logique de l'outil. Chaque maillon a son instrument.
4. **Pour un script qui détruit des données : constat d'abord**, cause ensuite. Ce qui a disparu se mesure contre une sauvegarde et une politique, avant d'ouvrir le script.
5. **Corriger dans le dépôt** (MR, test qui reproduit le bogue), puis déployer ; une correction faite seulement sur `adm01` reviendra.
6. **Prévenir** : quel test, quelle option d'analyse statique, quelle sonde aurait arrêté ou détecté la panne ?

---

### M02-E35 — Panne : le script marche à la main mais pas la nuit

**Démarche de diagnostic**

*Symptômes* : `ms-verif-sauvegardes.service` en échec (alerte `ms-alerte` reçue), le même script lancé par `admin` dans un terminal réussit.

*Hypothèses* (tout ce qui diffère entre un terminal et le service) : utilisateur et groupe (`User=`), `HOME` et dossier de travail, variables d'environnement (`Environment=`, `EnvironmentFile=`, rien de ton `~/.bashrc`), `PATH` (celui de systemd), commande exécutée (`ExecStart=` : quel fichier ?), protections du bac à sable (`ProtectHome=`, `ProtectSystem=`, `PrivateTmp=`…), délai (`TimeoutStartSec=`), absence de terminal.

**Étape 1 — Le message exact, côté service.**

```
admin@adm01:~$ systemctl status ms-verif-sauvegardes.service --no-pager
admin@adm01:~$ journalctl -u ms-verif-sauvegardes -n 20 -o cat --no-pager
admin@adm01:~$ journalctl -t ms-alerte -p crit -n 5 --no-pager
```

**Étape 2 — La configuration effective.** `systemctl cat` affiche le fichier d'unité **et chaque drop-in**, avec son chemin en commentaire ; `systemctl show` donne les valeurs appliquées ; `systemd-delta --type=extended,overridden` liste tout ce qui étend ou remplace une unité.

```
admin@adm01:~$ systemctl cat ms-verif-sauvegardes.service
admin@adm01:~$ systemctl show ms-verif-sauvegardes.service -p User -p ExecStart -p Environment -p ProtectHome
admin@adm01:~$ systemd-delta --type=extended,overridden | grep ms-verif
```

**Étape 3 — Reproduire hors du timer.** `sudo systemctl start ms-verif-sauvegardes.service` rejoue le service à l'identique. Pour isoler **une** propriété, `systemd-run` crée une unité transitoire :

```
admin@adm01:~$ sudo systemd-run --wait --pipe --collect -p User=admin -p ProtectHome=yes \
                 ls -l /home/admin/.config/workbook/
ls: cannot access '/home/admin/.config/workbook/': No such file or directory
admin@adm01:~$ sudo systemd-run --wait --pipe --collect -p User=admin -p ProtectHome=read-only \
                 /usr/local/bin/ms-verif-sauvegardes
```

**Variante 1 — durcissement trop strict (`ProtectHome=yes`).**

```
… ERREUR fichier de configuration illisible : /home/admin/.config/workbook/pbs-lecture.env
admin@adm01:~$ systemctl show ms-verif-sauvegardes -p ProtectHome
ProtectHome=yes
```

Un drop-in `20-durcissement.conf` (« SEC-380 ») remplace `ProtectHome=read-only` de l'unité par `yes` : `/home`, `/root` et `/run/user` deviennent vides et inaccessibles pour le service. Dans un terminal, aucune protection : le script lit ses fichiers. Correctif : retirer le drop-in (`sudo rm …/20-durcissement.conf && sudo systemctl daemon-reload`) ; l'intention de durcissement est déjà satisfaite par l'unité (`ProtectHome=read-only`, `ProtectSystem=strict`, `NoNewPrivileges=yes`…). Si l'on veut aller plus loin sans casser : `ProtectHome=tmpfs` **avec** `BindReadOnlyPaths=/home/admin/.config/workbook`, testé par `systemctl start`.

**Variante 2 — le service tourne en root (`User=root`).**

```
… ERREUR fichier de configuration illisible : /root/.config/workbook/pbs-lecture.env
admin@adm01:~$ systemctl show ms-verif-sauvegardes -p User
User=root
```

Le drop-in `10-journal.conf` (« CHG-380 : écrire un rapport dans /var/log/ms-outils ») change l'utilisateur, donc `HOME` (systemd le positionne selon `User=`), donc le chemin des fichiers d'accès. C'est aussi une régression de sécurité : un contrôle en lecture seule n'a aucune raison de tourner en root. Correctif : retirer le drop-in. Pour le besoin d'origine (un rapport sur disque), `LogsDirectory=ms-outils` crée `/var/log/ms-outils` appartenant à l'utilisateur du service, sans privilège ; ou mieux, rien : le journal systemd **est** le rapport.

**Variante 3 — proxy imposé au service.**

```
… ERREUR API Proxmox : … Failed to connect to 10.10.20.250 port 3128 … Couldn't connect to server
… ERREUR API Proxmox VE injoignable ou refus : liste des VMs impossible
admin@adm01:~$ systemctl show ms-verif-sauvegardes -p Environment
Environment=http_proxy=http://10.10.20.250:3128 https_proxy=http://10.10.20.250:3128 no_proxy=localhost,127.0.0.1,.medisphere.internal
```

Le drop-in `30-proxy.conf` (« modèle commun des services ») envoie toutes les connexions HTTPS de `curl` vers un proxy (adresse réservée aux tests, où rien n'écoute). `no_proxy` exempte les noms en `.medisphere.internal`, mais le script appelle `pve01` et `pbs01` **par adresse IP** : aucune entrée ne correspond. Dans ton terminal, ces variables n'existent pas. Correctif : retirer le drop-in (le contrôle n'a pas besoin d'Internet) ; si un proxy est réellement imposé, exempter les adresses internes (`curl` accepte les réseaux en notation CIDR dans `no_proxy` depuis la 7.86 : `no_proxy=localhost,127.0.0.1,.medisphere.internal,10.0.0.0/8`).

**Variante 4 — `ExecStart` redirigé vers une vieille copie.**

```
admin@adm01:~$ systemctl cat ms-verif-sauvegardes.service | tail -n 4
# /etc/systemd/system/ms-verif-sauvegardes.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/local/sbin/ms-verif-sauvegardes
admin@adm01:~$ head -n 4 /usr/local/sbin/ms-verif-sauvegardes
#!/bin/bash
# ms-verif-sauvegardes 0.3.0 — contrôle des sauvegardes PBS des VMs du socle.
# Copie déployée à la main avant la bibliothèque commune (lib/ms-commun.sh) et le jeton
# en lecture seule. Lit ~/.config/workbook/pve-api.env.
```

Le terminal exécute `/usr/local/bin/ms-verif-sauvegardes` (premier dans le `PATH`), le service une copie 0.3.0 d'avant M02-E26, posée dans `/usr/local/sbin` et rendue active par un `systemctl edit` (le `ExecStart=` vide remet la liste à zéro, la ligne suivante la remplace). Cette copie lit `pve-api.env` (le jeton **d'écriture**) et interroge le contenu de `pbs-par2` par l'API de `pve01`, ce que le jeton ne voit pas (filtrage de M02-E26) : échec. Correctif : retirer `override.conf`, mettre la vieille copie de côté comme pièce du dossier (puis la supprimer), `daemon-reload`, relancer. Signale à Sophie qu'un service planifié a tourné avec le jeton d'écriture.

**Après chaque correctif**

```
admin@adm01:~$ sudo systemctl daemon-reload && sudo systemctl start ms-verif-sauvegardes.service
admin@adm01:~$ systemctl show ms-verif-sauvegardes.service -p Result -p ExecMainStatus
Result=success
ExecMainStatus=0
```

**Prévention**
- Les unités vivent dans `plateforme/outils` (dossier `systemd/`) et s'installent par la tâche du Taskfile : un drop-in posé à la main est une dérive, détectable par `systemd-delta` dans un contrôle quotidien.
- Règle d'équipe : toute modification d'une unité se termine par `systemctl start` et la lecture du résultat (c'est l'action n° 1 du post-mortem d'exemple de E43).
- Le guide d'astreinte donne la commande « rejouer comme le service » (voir [`fichiers/M02-E46/docs/astreinte.md`](fichiers/M02-E46/docs/astreinte.md), section 3).

**Explications**

Un service systemd ne part pas d'un shell de connexion : il reçoit un environnement minimal (`PATH` de systemd, `HOME`/`USER` selon `User=`, rien de `~/.profile`), éventuellement un bac à sable de fichiers (espaces de noms de montage pour `ProtectHome`, `ProtectSystem`, `PrivateTmp`), et la commande exacte de `ExecStart=`. Les drop-ins (`<unité>.d/*.conf`) sont lus après le fichier principal, dans l'ordre alphabétique, et chaque affectation remplace la précédente (une liste comme `ExecStart=` ou `Environment=` se remet à zéro par une affectation vide). C'est puissant et invisible : d'où `systemctl cat`, qui est le seul affichage fidèle.

**Alternatives**
- `systemctl edit --full` réécrit l'unité au lieu d'un drop-in : plus lisible, mais l'unité livrée n'est plus mise à jour par la tâche d'installation.
- `systemd-analyze verify` ne détecte rien ici : les quatre configurations sont **valides**, seulement incompatibles avec le script.

**Pièges classiques**
- Relancer le script en `admin` dans un terminal et conclure « faux positif ».
- Modifier l'unité principale sans voir le drop-in qui l'écrase.
- Oublier `daemon-reload` : systemd continue d'appliquer l'ancienne configuration (`systemctl status` l'indique : « Warning: The unit file … changed on disk »).
- « Corriger » en lançant le contrôle en root ou en lui donnant le jeton d'écriture.

**En production chez MédiSphère**
Les unités sont déployées par Ansible (module 04) depuis le dépôt, avec un contrôle de dérive ; un test de fumée lance chaque service après déploiement. La reproduction « comme le service » fait partie du runbook d'astreinte.

---

### M02-E36 — Panne : `medictl` ne parle plus à Proxmox

**Démarche de diagnostic**

*Symptômes* : `medictl vm list --pool lab` échoue ou renvoie une liste vide ; `ms-snapshot` en erreur ; les VMs tournent.

*Hypothèses*, par maillon : fichier d'accès (`pve-api.env` : présent, lisible, complet) ; TLS (CA présentée vs certificat de `pve01`) ; authentification (secret, jeton existant et non expiré, compte actif) ; autorisation (ACL du jeton **et** de l'utilisateur) ; données.

**Étape 1 — Ce que dit `medictl`.**

```
admin@adm01:~$ medictl -vv vm list --pool lab
medictl : liste des VMs : jeton refusé (401). Secret erroné, jeton supprimé ou expiré       (v1, v4)
medictl : liste des VMs : certificat de Proxmox refusé. Vérifie PVE_CACERT …                (v3)
VMID  NOM  ÉTAT …                                                                               (v2 : en-tête seul)
admin@adm01:~$ medictl config        # configuration effective, secret masqué
```

En variante 2, `medictl` réussit (code 0) avec une liste vide : pour lui, « aucune VM visible » n'est pas une erreur. Pour un humain qui sait que le pool contient des VMs, c'est un symptôme de droits.

**Étape 2 — Contourner `medictl`, un maillon à la fois.** Le secret passe par un en-tête lu dans une substitution de processus (jamais en argument, jamais affiché) :

```
admin@adm01:~$ source ~/.config/workbook/pve-api.env      # dans un shell que tu fermeras ensuite
admin@adm01:~$ entete() { printf 'Authorization: PVEAPIToken=%s=%s\n' "$PVE_TOKEN_ID" "$PVE_TOKEN_SECRET"; }
admin@adm01:~$ curl -sS -o /dev/null -w '%{http_code}\n' --cacert "$PVE_CACERT" -H @<(entete) "$PVE_API_URL/version"; echo "curl=$?"
admin@adm01:~$ curl -sS --cacert "$PVE_CACERT" -H @<(entete) "$PVE_API_URL/cluster/resources?type=vm" | jq '.data | length'
admin@adm01:~$ exit
```

| Résultat | Maillon | Variantes |
|---|---|---|
| `curl=60`, « SSL certificate problem: unable to get local issuer certificate » | TLS | 3 |
| `401` | authentification | 1, 4 |
| `200` sur `/version`, `0` VM visible | autorisation | 2 |

**Étape 3 — Côté `pve01`.**

```
root@pve01:~# pveum user list | grep wb-automation                         # colonne enable
root@pve01:~# pveum user token list wb-automation@pve                      # colonne expire (époque Unix)
root@pve01:~# date -d @<EXPIRE>
root@pve01:~# pveum acl list | grep -E 'wb-automation'
root@pve01:~# pveum user token permissions wb-automation@pve lab --path /pool/lab
root@pve01:~# grep -E 'wb-automation' /var/log/pveproxy/access.log | tail -n 5     # codes 401/200
```

**Variante 1 — jeton expiré.** `expire` est dans le passé (il y a une heure). Le secret est juste ; le jeton n'est plus valable. Correctif : `pveum user token modify wb-automation@pve lab --expire "$(date -d '+1 year' +%s)"` (le secret ne change pas), **et** une rotation planifiée : une expiration est une sécurité, sa date doit être suivie, pas découverte.

**Variante 2 — ACL de l'utilisateur retirée.** `pveum acl list` ne montre plus que l'ACL du **jeton** sur `/pool/lab` ; `pveum user token permissions … --path /pool/lab` est vide. Le jeton a la séparation des privilèges : ses droits effectifs sont l'**intersection** des siens et de ceux de l'utilisateur (M00-E17). Sans droit pour l'utilisateur, plus aucun droit pour le jeton, et l'API **filtre** (liste vide, code 200) au lieu de refuser ; `ms-snapshot` refuse alors toute VM (« invisible pour le jeton : hors du pool lab », code 3), et le jeton `!lecture` de M02-E26 est touché de la même façon. Correctif : `pveum acl modify /pool/lab --users wb-automation@pve --roles WBAutomation`. Puis expliquer la séparation des privilèges à la personne qui a fait la « revue des accès » : l'ACL n'était pas redondante.

**Variante 3 — mauvaise autorité de certification.**

```
admin@adm01:~$ openssl x509 -in ~/.config/workbook/pve-root-ca.pem -noout -subject -fingerprint -sha256
subject=CN=MédiSphère CA provisoire
admin@adm01:~$ ssh pve01 openssl x509 -in /etc/pve/pve-root-ca.pem -noout -subject -fingerprint -sha256
subject=CN=Proxmox Virtual Environment, OU=…, O=PVE Cluster Manager CA
```

Le fichier `PVE_CACERT` a été remplacé par la racine de la PKI provisoire de M01 (« mise à jour des certificats ») : elle signe le certificat de `git01`, pas celui de `pve01`. Correctif : recopier la CA de `pve01` par un canal de confiance (SSH, dont la clé d'hôte est connue) : `scp pve01:/etc/pve/pve-root-ca.pem ~/.config/workbook/pve-root-ca.pem && chmod 600 …`, puis comparer l'empreinte. **Ne pas** « réparer » avec `verify=False` ou `curl -k`.

**Variante 4 — compte désactivé.** `pveum user list` : `enable 0`, commentaire « Désactivé lors de la revue trimestrielle des accès (SEC-381) ». Un jeton hérite de l'état de son utilisateur : tous les jetons du compte sont refusés (401). Correctif technique : `pveum user modify wb-automation@pve --enable 1` ; correctif humain : la revue des accès avait une raison (compte sans propriétaire identifié ?) : réactiver **avec** Sophie, et documenter le propriétaire et l'usage du compte dans l'inventaire (comptes et jetons, M00-E50).

**Vérification**

```
admin@adm01:~$ medictl vm list --pool lab --format json | jq length
admin@adm01:~$ ms-snapshot --dry-run --pool lab
admin@adm01:~$ sudo systemctl start ms-verif-sauvegardes.service
```

**Prévention**
- Une sonde quotidienne (dans `ms-verif-sauvegardes` ou à côté) : jeton accepté, nombre de VMs du socle visibles ≥ attendu, expiration du jeton à plus de 30 jours ; alerte sinon.
- `medictl vm list` : avertissement sur la sortie d'erreur quand aucune VM n'est visible (« droits du jeton ? »).
- Jetons et comptes d'automatisation inventoriés avec propriétaire, usage et date de rotation ; la revue des accès consulte l'inventaire avant de désactiver.

**Explications**

Chaque maillon a sa signature : la vérification TLS échoue **avant** tout échange HTTP (code `curl` 60, `SSLError` en Python) ; l'authentification produit un 401 (identité inconnue, refusée ou expirée) ; l'autorisation produit un 403 quand l'appel lui-même est interdit, et une liste filtrée quand l'API trie les objets visibles. Proxmox VE filtre `/cluster/resources` selon `VM.Audit` : c'est confortable pour une interface, piégeux pour un outil qui doit distinguer « rien » de « rien de visible ».

**Pièges classiques**
- Régénérer un jeton (nouveau secret à redistribuer partout) alors qu'il suffisait de prolonger son expiration.
- Donner `Administrator` au jeton « pour voir si c'est les droits ».
- Coller la commande `curl` avec le secret dans le ticket.
- Oublier que le jeton `!lecture` dépend du même utilisateur (variante 2).

**En production chez MédiSphère**
Les jetons d'automatisation sont émis et renouvelés par Vault (module 25), avec une durée de vie courte ; les droits effectifs attendus de chaque identité sont décrits dans un fichier versionné et comparés chaque nuit à la réalité.

---

### M02-E37 — Panne : le nettoyage a supprimé trop de choses

**Démarche de diagnostic**

*Symptômes* : rapports récents ou sous conservation légale absents après le premier passage réel du script de purge ; le script se dit correct.

**Étape 1 — Le constat, sans toucher à la zone.**

```
admin@adm01:~$ cd /opt/workbook/m02/e37
admin@adm01:/opt/workbook/m02/e37$ cat journal/purge-*.log
admin@adm01:/opt/workbook/m02/e37$ diff <(tar -tzf sauvegardes/rapports-*.tar.gz | grep -v '/$' | sort) \
                                         <(find rapports -type f | sort) | grep '^<' | wc -l
admin@adm01:/opt/workbook/m02/e37$ awk -F'\t' '$1 == "CONSERVER" {print $2}' attendu.tsv \
                                     | while IFS= read -r f; do [[ -f $f ]] || echo "PERDU $f"; done
admin@adm01:/opt/workbook/m02/e37$ awk -F'\t' '$1 == "PURGER" {print $2}' attendu.tsv \
                                     | while IFS= read -r f; do [[ -e $f ]] && echo "RESTÉ $f"; done
```

Ordres de grandeur obtenus en rejouant les variantes sur le jeu fourni (35 fichiers à conserver dont 2 hors zone, 30 à purger) :

| Variante | Perdus (devaient rester) | Restés (devaient partir) | Signature dans la zone |
|---|---|---|---|
| 1 | 33 (toute la racine) | 0 | `rapports/` a disparu, `.zone-de-test` compris |
| 2 | 15 (tous les PDF récents, `a-conserver/` compris) | 9 (les vieux JSON) | aucun PDF ne reste |
| 3 | 33 | 0 | `rapports/` existe, vide sauf `.zone-de-test` |
| 4 | 21 (tous les fichiers récents) | 21 (tous les vieux) | exactement l'inverse de la politique |

`hors-zone/` est intact dans tous les cas : la sauvegarde et le journal aussi, parce qu'ils ne sont pas sous la racine.

**Étape 2 — La cause.** ShellCheck sur le script de Lucas :

| Variante | Défaut | ShellCheck |
|---|---|---|
| 1 | `rm -rf "$RACINE/$appli"` : la boucle définit `appli_retiree`, `appli` n'existe pas, vaut `""` sans `set -u` : `rm -rf "$RACINE/"` | **SC2154** (`appli is referenced but not assigned`) et SC2115 (`${var:?}`) |
| 2 | `find … -mtime +30 -name '*.json' -o -name '*.pdf' -delete` : `-a` implicite plus prioritaire que `-o`, `-delete` ne s'applique qu'à la seconde branche : **tous** les PDF, sans condition d'âge ni d'exclusion | **SC2146** (`This action ignores everything before the -o`) |
| 3 | `cd "$app/tmp"` non vérifié : `medi-notif` n'a pas de `tmp/`, le `cd` échoue, `rm -rf ./*` vide la racine | **SC2164** (`cd … \|\| exit`) |
| 4 | `-mtime -"$RETENTION_JOURS"` : « modifié il y a **moins** de 30 jours » | rien : c'est une erreur de logique, seul un test sur données la voit |

Reproduction sur un jeu neuf, dans un dossier jetable :

```
admin@adm01:~$ t="$(mktemp -d)"; bash ~/DevOpsPrivateCloud/modules/02-scripting/ressources/M02-E37/fabriquer-donnees.sh "$t/z"
admin@adm01:~$ printf 'RACINE=%s\nRETENTION_JOURS=30\nAPPLIS_RETIREES="legacy-rdv"\n' "$t/z/rapports" >"$t/purge.conf"
admin@adm01:~$ cp /opt/workbook/m02/e37/bin/ms-purge-rapports "$t/" && (cd "$t" && bash -x ./ms-purge-rapports -c purge.conf) 2>&1 | grep -E 'rm|find|cd'
```

**Étape 3 — La restauration sélective.**

```
admin@adm01:/opt/workbook/m02/e37$ cp -a rapports rapports.avant-restauration 2>/dev/null || true   # retour arrière
admin@adm01:/opt/workbook/m02/e37$ r="$(mktemp -d)"; tar -C "$r" -xzf sauvegardes/rapports-*.tar.gz
admin@adm01:/opt/workbook/m02/e37$ printf 'RACINE=%s\nRETENTION_JOURS=30\nAPPLIS_RETIREES="legacy-rdv"\n' "$r/rapports" >"$r/purge.conf"
admin@adm01:/opt/workbook/m02/e37$ <SCRIPT-CORRIGÉ> -c "$r/purge.conf"            # la politique, appliquée à la sauvegarde
admin@adm01:/opt/workbook/m02/e37$ rsync -a --ignore-existing "$r/rapports/" rapports/   # seulement ce qui manque
admin@adm01:/opt/workbook/m02/e37$ bin/ms-purge-rapports -n && bin/ms-purge-rapports     # ce qui devait partir (v2, v4)
```

`tar` restaure les dates de modification d'origine (comportement par défaut à l'extraction), `rsync -a` les conserve. Un `cp` sans `-a` donnerait aux fichiers restaurés la date du jour : la purge suivante les croirait récents et les garderait des mois de trop (ou, avec un bogue inverse, les supprimerait). En variante 1, `rsync` recrée aussi le témoin `.zone-de-test`. `<SCRIPT-CORRIGÉ>` : le script de l'étape 4, que tu écris **avant** de restaurer.

**Étape 4 — Le script corrigé** : [`fichiers/M02-E37/ms-purge-rapports`](fichiers/M02-E37/ms-purge-rapports). Points clés :
- `set -euo pipefail` ; configuration **lue puis validée** (`RACINE` absolue, résolue par `readlink -f`, ni `/`, ni caractère de motif ; `RETENTION_JOURS` entier ≥ 1 ; noms d'applications par liste blanche) avant toute action ;
- refus (code 3) d'une racine sans `.zone-de-test` ou `.zone-purgeable` ;
- **une seule** fonction `supprimer` par laquelle passe toute suppression : elle refuse un chemin hors de la racine et sert aussi le `--dry-run` (même chemin de code, donc un plan qui ne ment pas, comme en M02-E27) ;
- plus de `cd` : chemins absolus ; `find` avec parenthèses, `! -path "$RACINE/*/a-conserver/*"` et `-mtime +N`, résultats lus en tableau par `-print0` et `mapfile -d ''`, code de `find` vérifié par `wait "$!"`.

Tests bats à verser dans `plateforme/outils` : [`fichiers/M02-E37/tests/bats/ms-purge-rapports.bats`](fichiers/M02-E37/tests/bats/ms-purge-rapports.bats) (11 tests) et son jeu de données [`tests/bats/fixtures/fabriquer-donnees.sh`](fichiers/M02-E37/tests/bats/fixtures/fabriquer-donnees.sh), copié dans le projet (un test ne dépend pas du workbook). Ils vérifient l'état exact de la politique, l'idempotence, le `--dry-run`, les refus (racine non marquée, configuration invalide, nom d'application dangereux), l'usage, et un test de régression par variante. Contrôle de leur pertinence : rejoués contre les quatre versions de Lucas, ils échouent à chaque fois (9 à 10 tests en échec sur 11).

**Prévention**
- ShellCheck **bloquant** en CI (trois variantes sur quatre étaient signalées) ; un script de purge sans tests sur données fabriquées ne passe pas en revue.
- Pour tout script destructeur : `--dry-run` obligatoire, premier passage réel sous surveillance, sauvegarde vérifiée juste avant ; politique de rétention traduite en **tests**, pas seulement en code.
- Marqueur de zone purgeable (`.zone-purgeable`) : une erreur de configuration (`RACINE=/`) devient un refus.

**Explications**

Un script de suppression se juge sur ses **pires** entrées : variable vide, dossier absent, nom avec espaces, motif sans correspondance, `cd` raté. Bash n'aide pas : une variable non définie vaut la chaîne vide (sauf `set -u`), un `cd` raté laisse dans le dossier courant (sauf `set -e` ou `|| exit`), et `rm -rf` ne demande rien. `find` a sa propre grammaire : opérateurs `!`, `-a` (implicite) puis `-o` par ordre de priorité, actions comprises (`-delete`, `-print`) ; `-mtime +N` signifie « plus de N jours **entiers** » (donc au moins N+1), `-mtime -N` « moins de N ».

**Alternatives**
- Déplacer vers une corbeille datée (`mv` sur le même système de fichiers), purgée par un second passage plus tard : les erreurs deviennent réversibles pendant quelques jours.
- `tmpreaper`/`systemd-tmpfiles` (règles `d`/`e` avec âge) pour les fichiers temporaires : déclaratif, testé, mais moins expressif pour les exceptions métier (`a-conserver/`).

**Pièges classiques**
- Relancer le script de Lucas « pour voir » sur la zone.
- Restaurer toute la sauvegarde : les fichiers qui devaient partir reviennent (et la purge suivante les supprime… si elle est correcte).
- Restaurer avec `cp` sans `-a` (dates perdues).
- Corriger le seul bogue de sa variante sans relire le reste : le script de Lucas en contient plusieurs.

**En production chez MédiSphère**
La purge de données soumises à obligation légale fait l'objet d'une procédure validée par la RSSI (Sophie) : jeu de test de référence, revue à deux, premier passage en `--dry-run` archivé, journal des suppressions conservé (preuve de conformité), sauvegarde vérifiée avant chaque passage.

---

### M02-E38 — Panne : rouge en CI, vert en local

**Démarche de diagnostic**

*Symptômes* : variantes 1 à 3, la MR de Lucas est rouge, Lucas dit que `uv run pytest` passe chez lui ; variante 4, tous les pipelines, `main` compris, sont rouges sur le lint ShellCheck alors que `task lint` est vert sur `adm01`.

*Différences possibles entre `adm01` et `runner01`* (et la commande qui les montre) : copie de travail non propre (`git status`, fichiers ignorés : `git status --ignored`) ; verrou de dépendances (`uv lock --check`) ; configuration et secrets de l'utilisateur (`ls ~/.config/workbook`, aucun sur `runner01`) ; outils installés et leurs versions (`command -v`, `--version`, en `gitlab-runner`) ; variables CI du projet **et héritées** (*Paramètres → CI/CD → Variables*) ; accès réseau (`runner01` ne joint pas `pve01`) ; commande exécutée (`uv run` vs `task`).

**Étape 1 — Le job en échec** (onglet *Pipelines* de la MR, ou `GET /projects/:id/pipelines/:id/jobs?scope=failed`).

**Étape 2 — Comme la CI, sur `adm01`.**

```
admin@adm01:~$ d="$(mktemp -d)" && git clone -q --branch <BRANCHE> git@git01.par1.medisphere.internal:plateforme/outils.git "$d" && cd "$d"
admin@adm01:/tmp/tmp.X$ task ci
```

**Variante 1 — dépendance ajoutée sans verrou.** Job `ruff` (ou `pytest`, `build`) en échec dès la tâche `setup` :

```
$ uv sync --locked
error: The lockfile at `uv.lock` needs to be updated, but `--locked` was provided. To update the lockfile, run `uv lock`.
```

Lucas a ajouté `tabulate` à `pyproject.toml` (MR « rendu tabulaire ») sans committer `uv.lock`. `uv run pytest` sans option **reverrouille et synchronise en silence** : chez lui, `uv.lock` a été modifié et `tabulate` installé, d'où le vert ; `git status` lui aurait montré `uv.lock` modifié. Le clone propre reproduit l'échec (`task ci` utilise `--locked`). Correctif : sur sa branche, `uv lock` puis commit de `uv.lock` (`build(deps): ajouter tabulate`), et la question de fond en revue : une dépendance de plus pour un tableau Markdown, est-ce justifié ? Prévention : le hook pre-commit `uv-lock` (dépôt `astral-sh/uv-pre-commit`) qui refuse un commit quand le verrou n'est plus à jour, ou `UV_LOCKED=1` dans l'environnement des développeurs.

**Variante 2 — test qui lit ta configuration et appelle le vrai Proxmox.** Job `pytest` :

```
FAILED tests/python/test_cli_vm_list.py::test_vm_list_json_valide - AssertionError: medictl : … fichier d'accès … introuvable
```

Le test invoque `medictl vm list` par `CliRunner` **sans** les fixtures du projet (`faux_client`, `fichier_env`) : sur `adm01`, `medictl` lit `~/.config/workbook/pve-api.env` et interroge le vrai Proxmox ; sur `runner01`, il n'y a ni fichier, ni route vers `pve01`. Le vert local est le vrai problème : un test qui touche la production n'a pas sa place dans la suite (M02-E18, M02-E24). Correctif (commentaire de revue à Lucas) :

```python
def test_vm_list_json_valide(runner, faux_client) -> None:
    resultat = runner.invoke(app, ["vm", "list", "--pool", "lab", "--format", "json"])
    assert resultat.exit_code == 0, resultat.output
    assert isinstance(json.loads(resultat.stdout), list)
```

Prévention : une fixture `autouse` dans `conftest.py` qui pointe `HOME` et `MEDICTL_ENV_FILE` vers un dossier temporaire vide et retire les `PVE_*` ; tout test qui oublie les fixtures échoue alors **aussi en local**. Pour aller plus loin, `pytest-socket` (`--disable-socket`) interdit tout accès réseau pendant les tests.

**Variante 3 — outil présent sur `adm01`, absent de `runner01`.** Job `pytest` :

```
FileNotFoundError: [Errno 2] No such file or directory: 'yq'
```

`yq` a été installé sur `adm01` en M02-E06 (introduction du module), pas sur `runner01` (M02-E24 n'installe que ShellCheck, shfmt, jq, bats, Task). Le clone propre sur `adm01` **passe** : la différence n'est pas dans le dépôt mais dans la machine. Deux corrections défendables : (a) si le test est utile, rendre la dépendance explicite et reproductible : ajouter `yq` au script d'installation de `runner01` (même version, empreinte vérifiée) **et** à la précondition des tâches qui l'utilisent ; (b) si non, réécrire le test sans outil externe (lire le YAML en Python demanderait une dépendance de développement, `pyyaml` ; ou interroger Task lui-même). Mauvaise correction : `pytest.skip` si `yq` est absent (le test ne tournerait jamais en CI, donc jamais).

**Variante 4 — variable CI héritée du groupe.** Job `shellcheck` (et `pre-commit` si son hook ShellCheck tourne) : des centaines de remarques `SC2250 (style): Prefer putting braces around variable references`, absentes en local. Clone propre sur `adm01` : vert. Rien ne diffère dans le dépôt ni dans les outils (même version de ShellCheck) : le runner reçoit autre chose. `man shellcheck`, section *ENVIRONMENT* : `SHELLCHECK_OPTS` est lue comme des options par défaut. *Paramètres → CI/CD → Variables* du projet affiche la variable héritée du groupe `plateforme` : `SHELLCHECK_OPTS=--enable=all --severity=style`, description « SEC-382 : ShellCheck au niveau d'exigence maximal ». Correctif : en parler à Sophie (l'intention est légitime : plus d'exigence), retirer la variable, et porter l'exigence **dans le dépôt** (`.shellcheckrc`, par MR, règle par règle, comme `check-set-e-suppressed` en M02-E39) : une règle de qualité invisible, qui change le résultat de tous les projets d'un coup et que personne ne peut reproduire en local, est une mauvaise règle.

**Vérification** : pipeline de `main` relancé et vert ; MR de Lucas corrigée (variantes 1 à 3) ou fermée avec explication ; `lab/bin/check 02 38`.

**Prévention (commune)**
- Les développeurs lancent `task test`/`task ci` (mêmes commandes que la CI, `--locked`), pas `uv run pytest`.
- Les outils de `runner01` et ceux de `adm01` viennent du même script, aux mêmes versions (M02-E24, puis Ansible au module 04).
- Les options de qualité vivent dans le dépôt ; les variables CI de groupe sont réservées aux secrets et aux paramètres d'infrastructure, et documentées.

**Explications**

« Vert en local, rouge en CI » a toujours la même structure : le résultat dépend d'une entrée qui n'est pas dans le dépôt. Les quatre variantes en montrent quatre familles : état local non commité (verrou), données et secrets de l'utilisateur, outillage de la machine, configuration injectée par la plateforme. Le clone propre sépare les deux premières des deux dernières en une commande.

**Pièges classiques**
- `allow_failure: true` ou un `skip` « en attendant ».
- Activer `CI_DEBUG_TRACE` pour voir les variables : sur un projet qui a des variables protégées et masquées, le journal du job peut les révéler à quiconque lit les journaux.
- Comparer les versions des outils en `admin` sur `runner01` (M02-E24 : c'est `gitlab-runner` qui compte).

**En production chez MédiSphère**
Les jobs tournent dans des images figées et signées (modules 12, 13 et 19) : l'outillage de la machine disparaît comme source de différence. Les variables de groupe sont gérées en IaC (provider GitLab d'OpenTofu) avec revue.

---

### M02-E39 — Panne : `set -e` ne fait pas ce qu'on croit

**Démarche de diagnostic**

*Symptômes* : code 0, « Terminé : 3 hôte(s) archivé(s) », mais l'archive de `dns01` ne contient que 2 journaux sur 3 et le spool de `dns01` est vide.

**Étape 1 — Le constat.**

```
admin@adm01:~$ cd /opt/workbook/m02/e39
admin@adm01:/opt/workbook/m02/e39$ cat journal/archivage-*.log
tar: ./dnsmasq.log.1: Cannot open: Permission denied
tar: Exiting with failure status due to previous errors
… dns01 : archive bin/../archives/dns01-AAAAMMJJ.tar.gz vérifiée
… dns01 : spool vidé
…
… Terminé : 3 hôte(s) archivé(s)
code retour : 0
admin@adm01:/opt/workbook/m02/e39$ tar -tzf archives/dns01-*.tar.gz
./
./dnsmasq.log
./dnsmasq-dhcp.log
admin@adm01:/opt/workbook/m02/e39$ cat attendu/dns01.liste
```

`tar` a signalé une erreur (code 2 : « Exiting with failure status ») ; le script a continué, déclaré l'archive vérifiée (`gzip -t` ne vérifie que la **lisibilité** de l'archive, pas son contenu) et vidé le spool. `rm -f` supprime un fichier en mode 000 : il faut le droit d'écriture sur le **dossier**, pas sur le fichier.

**Étape 2 — Pourquoi le script a continué** (selon la variante ; `diff` entre le script et une version « naïve » suffit à repérer la construction) :

| Variante | Construction | Règle de Bash |
|---|---|---|
| 1 | `tar -cf - . \| gzip -9 > archive` avec `set -eu` (sans `pipefail`) | le code d'un tube est celui de sa **dernière** commande (`gzip`, 0) |
| 2 | `if archiver "$h"; then purger …` | `-e` est ignoré dans le test d'un `if` ; « If a compound command or shell function executes in a context where -e is being ignored, none of the commands executed within the compound command or function body will be affected by the -e setting » : tout le corps de `archiver` s'exécute sans `-e`, son code est celui de sa dernière commande (`log`, 0) |
| 3 | `local erreurs=$(tar …)` | le code de la ligne est celui de la commande interne `local` (0), pas de la substitution |
| 4 | `archive=$(archiver "$h")` | « Subshells spawned to execute command substitutions inherit the value of the -e option from the parent shell. When not in POSIX mode, Bash clears the -e option in such subshells » : dans la substitution, `tar` échoue sans arrêter la fonction, qui rend 0 (`echo`) ; `shopt -s inherit_errexit` change ce comportement |

Démonstration minimale (variante 2) :

```bash
#!/usr/bin/env bash
set -euo pipefail
f() { false; echo "f continue malgré false"; }
if f; then echo "f a « réussi »"; fi
f                      # ici, le script s'arrête
```

**Étape 3 — ShellCheck.** Sans option : rien pour les variantes 1, 2 et 4 ; **SC2155** (« Declare and assign separately to avoid masking return values ») pour la variante 3. Avec les vérifications optionnelles :

```
admin@adm01:~$ shellcheck --list-optional | grep -A1 -E 'set-e|masked'
admin@adm01:~$ shellcheck -o check-set-e-suppressed,check-extra-masked-returns bin/ms-archiver-journaux
```

`check-set-e-suppressed` signale la variante 2 (**SC2310** : « This function is invoked in an 'if' condition so set -e will be disabled »). La variante 4 (`x=$(fonction)` dans une simple affectation) n'est pas signalée par ShellCheck 0.11 (SC2311 vise d'autres formes d'appel en substitution ; à vérifier sur ta version), la variante 1 (absence de `pipefail`) non plus. Conclusion : ShellCheck réduit le risque, il ne remplace pas la vérification explicite du résultat.

**Étape 4 — Récupérer les journaux.** La sauvegarde de 01:00 a été faite par root ; elle contient le fichier en mode 000 :

```
admin@adm01:/opt/workbook/m02/e39$ tar -tzvf sauvegardes/spool-*.tar.gz | grep dns01
---------- root/root  … spool/dns01/dnsmasq.log.1
-rw-r--r-- root/root  … spool/dns01/dnsmasq.log
…
admin@adm01:/opt/workbook/m02/e39$ r="$(mktemp -d)"; tar -C "$r" -xzf sauvegardes/spool-*.tar.gz spool/dns01/dnsmasq.log.1
admin@adm01:/opt/workbook/m02/e39$ chmod 640 "$r/spool/dns01/dnsmasq.log.1" && cp -a "$r/spool/dns01/dnsmasq.log.1" spool/dns01/
```

Extrait par `admin`, le fichier appartient à `admin` avec le mode 000 de l'archive : son propriétaire peut le `chmod`. Les deux autres journaux sont dans l'archive de 02:00 : ne les remets pas dans le spool, ils seraient archivés deux fois. Le mode 000 vient de l'agent de collecte (umask ou copie défectueuse) : un ticket pour l'équipe qui le gère, sinon la panne revient chaque nuit, et un script **correct** échouera bruyamment chaque nuit (c'est le comportement voulu).

**Étape 5 — Le script corrigé** : [`fichiers/M02-E39/ms-archiver-journaux`](fichiers/M02-E39/ms-archiver-journaux). Principes :
- `set -euo pipefail` **et** `shopt -s inherit_errexit`, mais surtout : la fonction d'archivage est appelée dans un `||` (pour continuer avec les autres hôtes), donc **`-e` n'y agit pas** : chaque étape y teste explicitement son résultat (`if ! tar …; then … return 1; fi`) ;
- liste des fichiers à archiver établie **avant** (`find -printf '%P\n'`), archive écrite sous un nom temporaire `*.partiel`, puis comparée à cette liste (`diff <(tar -tzf …) <(printf …)`), puis renommée ;
- seuls les fichiers de la liste sont retirés du spool (un fichier arrivé pendant l'archivage reste) ;
- code 1 si un hôte est en erreur, les autres hôtes étant traités ; messages sur la sortie d'erreur.

```
admin@adm01:/opt/workbook/m02/e39$ install -m 755 <SCRIPT-CORRIGÉ> bin/ms-archiver-journaux && bin/ms-archiver-journaux; echo $?
… dns01 : 1 fichier(s) archivé(s) dans …/archives/dns01-AAAAMMJJ-HHMMSS.tar.gz
… terminé : tous les hôtes sont archivés
0
```

**Étape 6 — Projet** : tests [`fichiers/M02-E39/tests/bats/ms-archiver-journaux.bats`](fichiers/M02-E39/tests/bats/ms-archiver-journaux.bats) (spool fabriqué par la copie de `fabriquer-spool.sh` dans `tests/bats/fixtures/`) : spool sain → code 0 et archives complètes ; fichier illisible → code 1, spool de `dns01` intact, `gw01` et `git01` archivés, aucune archive `.partiel` ; archive incomplète simulée (faux `tar` en tête du `PATH` qui « oublie » un fichier sans erreur) → code 1, spool conservé ; second passage ; refus et usage. Le test « fichier illisible » se saute lui-même s'il tourne avec un compte qui lit tout (root) : en CI, `gitlab-runner` n'est pas root. Rejoués contre les versions de Lucas, ils échouent (3 à 4 tests sur 6). Dans `.shellcheckrc` : `enable=check-set-e-suppressed` est un bon compromis : il signale (SC2310) chaque fonction appelée dans une condition, et chaque appel **voulu** doit alors être annoté (`# shellcheck disable=SC2310` avec la raison, comme dans le script corrigé) : la revue voit où `-e` ne protège plus rien ; `check-extra-masked-returns` produit beaucoup de remarques sur `$(date …)` et similaires : à évaluer sur le projet avant de l'imposer.

**Prévention**
- Contrat écrit en tête du script (« un fichier ne quitte le spool que s'il est dans une archive vérifiée ») et testé.
- Supervision du **résultat** (nombre de fichiers archivés par hôte et par nuit) en plus du code de sortie.
- Revue : toute fonction appelée dans un `if`, `||`, `&&`, `!` ou `$(…)` est lue comme si `set -e` n'existait pas.

**Explications**

`set -e` est une heuristique de POSIX, pas un mécanisme d'exceptions : il agit sur le code de retour d'une **commande simple** dans un contexte où ce code n'est pas déjà « utilisé ». Dès qu'un code est testé (`if`, `while`, `&&`, `||`, `!`), Bash considère que le script s'en occupe et suspend `-e` pour toute la commande testée, fonctions comprises. Les substitutions de commande, les tubes et les commandes internes qui « absorbent » un code (`local`, `export`, `declare` avec affectation) complètent la liste. Bash Hackers et la *BashFAQ/105* concluent la même chose : on peut garder `set -e` comme filet, jamais comme seule défense.

**Alternatives**
- Réécrire en Python (`subprocess.run(…, check=True)`, `tarfile`) : les erreurs deviennent des exceptions ; le contrôle de contenu de l'archive reste à écrire (M02-E45, question 17).
- `trap '…' ERR` avec `set -E` pour journaliser la ligne fautive : mêmes contextes muets que `-e`.

**Pièges classiques**
- Ajouter `pipefail` et croire le problème réglé (variantes 2 à 4).
- `gzip -t` comme « vérification » de sauvegarde.
- Restaurer les journaux dans le spool **et** les laisser dans l'archive (doublons).
- Lancer le script en root pour « régler » le fichier illisible : le problème de l'agent de collecte reste, et le script n'a plus de raison de tourner en root.

**En production chez MédiSphère**
Les journaux de sécurité sont expédiés en continu vers une plateforme centrale (module 22) avec accusé de réception ; l'archivage local devient un tampon. Toute perte de journal est un incident de sécurité déclaré (HDS, ISO 27001 A.8.15).

---

### M02-E40 — Panne : l'inventaire met dix minutes

**Démarche de diagnostic**

*Symptôme* : résultat juste, durée de plusieurs minutes.

**Étape 1 — Mesure de départ.**

```
admin@adm01:/opt/workbook/m02/e40$ time bin/ms-inventaire-lab -o /dev/null
```

**Étape 2 — Profil.**

```
admin@adm01:/opt/workbook/m02/e40$ PS4='+ ${EPOCHREALTIME} ' bash -x bin/ms-inventaire-lab -o /dev/null 2>/tmp/trace.txt
admin@adm01:~$ grep -cE '^\++ [0-9.]+ curl ' /tmp/trace.txt; grep -cE '^\++ [0-9.]+ (ssh|dig|sleep) ' /tmp/trace.txt
admin@adm01:~$ awk '{t=$2; if (p) printf "%.3f %s\n", t-p, prev; p=t; prev=$0}' /tmp/trace.txt | sort -rn | head
root@pve01:~# tail -f /var/log/pveproxy/access.log | grep -v ' 200 '
```

La commande `awk` affiche les lignes de trace suivies des plus longs intervalles : la commande lente est celle qui **précède** l'intervalle.

| Variante | Profil | Calcul (pool de ~6 VMs) |
|---|---|---|
| 1 | ~9 000 `curl`, presque tous en `403` (journal d'accès de `pve01`) | 9 000 × ~30 ms (connexion TLS + refus) ≈ 4 à 5 min |
| 2 | peu d'appels, mais des `sleep 1`, `2`, `4`, `8`, `16` en série ; codes `403` (contenu de `pbs-par2`) et `500` (agent d'une VM arrêtée ou sans agent, template) | 31 s d'attente par appel voué à l'échec × 2 par VM ≈ 6 min |
| 3 | ~15 `ssh pve01 pvesh get …` par VM | 90 × (SSH + démarrage de `pvesh`, ~0,5 à 1 s) ≈ 1 min ou plus |
| 4 | `dig @10.10.10.1` : chaque requête attend son délai complet | 2 requêtes × ~15 s par VM (délai et essais par défaut de `dig`) ≈ 3 min |

Coût unitaire mesuré à part :

```
admin@adm01:~$ time curl -s -o /dev/null --cacert … -H @<(…) "$PVE_API_URL/nodes/<NOEUD>/qemu/1234/status/current"
admin@adm01:~$ time ssh pve01 pvesh get /version --output-format json
admin@adm01:~$ time dig +short @10.10.10.1 dns01.par1.medisphere.internal
```

**Causes et correctifs**

- **V1 — balayer au lieu de lister.** InfoGér parcourait 1000-9999 et sautait les erreurs. `GET /cluster/resources?type=vm` renvoie en **un** appel toutes les VMs visibles avec `vmid`, `name`, `status`, `maxcpu`, `maxmem`, `pool`, `tags`, `node`, `template`. Correctif : une liste, puis seulement les appels qui apportent une information absente (adresse par l'agent QEMU).
- **V2 — reprendre ce qui ne réussira jamais.** La fonction `api` reprend **toute** erreur avec un délai doublé. Or `403` (droit absent) et `500 VM … not running` (agent) sont définitifs. Règle (M02-E17) : on ne reprend que les erreurs transitoires (réseau, délai, `502`/`503`/`504`) et en nombre borné ; on évite surtout l'appel inutile (agent d'une VM arrêtée ou template). La colonne « dernière sauvegarde » est de toute façon vide avec le jeton `!lab` (filtrage, M02-E26) : la retirer, ou la remplir par l'API de PBS avec le jeton de lecture.
- **V3 — un processus par champ.** Chaque `ssh pve01 pvesh get` paie une connexion (même multiplexée) et le démarrage de `pvesh` (Perl, chargement des modules de Proxmox), pour lire **un** champ d'un document déjà complet. Correctif : l'API par HTTPS avec le jeton, un appel pour la liste (et un par VM au plus pour la configuration si elle est vraiment nécessaire). Bonus de sécurité : plus de `root` sur `pve01` pour un inventaire.
- **V4 — un résolveur qui ne répond pas.** `DNS_INVENTAIRE=10.10.10.1` (passerelle MGMT) : `gw01` ne sert pas de DNS et son pare-feu jette en silence ; `dig` attend son délai et réessaie. Correctif : le résolveur du système (`getent hosts`, donc `dns01`), ou `dig +time=1 +tries=1` si un serveur précis est voulu. Un refus explicite (ICMP « port unreachable ») aurait été instantané : un `drop` coûte du temps à chaque client.

Script corrigé : [`fichiers/M02-E40/ms-inventaire-lab`](fichiers/M02-E40/ms-inventaire-lab) (+ [`inventaire.conf`](fichiers/M02-E40/inventaire.conf)) : un appel de liste, un appel à l'agent par VM démarrée (délai 5 s, sans reprise), résolution par `getent`, secret passé à `curl` par un fichier d'en-tête temporaire en 600. Mesure typique : 1 à 3 s pour le socle.

**Étape 5 — Règle générale** (pour `CONTRIBUTING.md`) : « Avant d'optimiser, compter : nombre d'appels × coût unitaire. Un appel par objet est suspect, un processus par champ est une erreur, une reprise sur une erreur définitive est une attente programmée. »

**Explications**

La lenteur d'un script d'exploitation vient rarement du calcul : elle vient d'**attentes** (réseau, délais, `sleep`) et de **démarrages** (processus, connexions TLS) multipliés par un nombre d'objets. Le profil par traces horodatées suffit à le montrer, sans outil spécial. Le journal d'accès de `pveproxy` est un instrument précieux : il montre ce que le serveur reçoit réellement (et combien de requêtes en échec un outil lui envoie).

**Pièges classiques**
- Paralléliser d'abord (M02-E28) : 9 000 appels inutiles en parallèle restent 9 000 appels inutiles, et chargent `pveproxy`.
- Optimiser `jq` ou les `echo` (quelques millisecondes) en ignorant les attentes.
- Augmenter le `timeout` du contrôle au lieu de corriger.

**En production chez MédiSphère**
L'inventaire vient de NetBox (module 06), alimenté par synchronisation ; les outils qui interrogent Proxmox exposent leur durée et leur nombre d'appels comme métriques, et une alerte signale une dérive.

---

### M02-E41 — Panne : le contrôle planifié ne tourne plus

**Démarche de diagnostic**

*Symptôme* : aucun passage du contrôle depuis plusieurs jours, aucune alerte.

**Étape 1 — L'état complet.**

```
admin@adm01:~$ systemctl list-timers --all ms-verif-sauvegardes.timer
admin@adm01:~$ systemctl status ms-verif-sauvegardes.timer ms-verif-sauvegardes.service --no-pager
admin@adm01:~$ systemctl show ms-verif-sauvegardes.timer -p LoadState -p ActiveState -p UnitFileState -p TimersCalendar -p NextElapseUSecRealtime
admin@adm01:~$ systemctl show ms-verif-sauvegardes.service -p Result -p ConditionResult -p ExecMainExitTimestamp
admin@adm01:~$ journalctl -u ms-verif-sauvegardes.timer -n 20 --no-pager
admin@adm01:~$ systemctl cat ms-verif-sauvegardes.timer ms-verif-sauvegardes.service
```

| Variante | Ce qu'on voit | Cause |
|---|---|---|
| 1 | timer `inactive (dead)`, mais `enabled` ; `NEXT` vide ; journal du timer : « Stopped … » | timer arrêté à chaud (`systemctl stop`) : il ne reviendra qu'au prochain démarrage de `adm01` |
| 2 | `Loaded: bad-setting` ; journal : `Failed to parse calendar specification, ignoring: *-*-* 30:07:00` puis `Timer unit lacks value setting. Refusing.` | drop-in `10-horaire.conf` : `OnCalendar=` (remise à zéro) puis une expression invalide recopiée d'une crontab (« 30 7 » lu à l'envers) ; plus aucun déclencheur, systemd refuse le timer |
| 3 | timer sain ; service : `Condition: start condition unmet … ConditionPathExists=/etc/ms-outils/controle-actif was not met` (libellé selon la version) ; `ConditionResult=no`, `Result=success` | drop-in `90-gel.conf` (« gel de l'outillage pendant la migration du datastore ») jamais levé : le service est **sauté**, ce qui n'est pas un échec |
| 4 | timer actif, `NEXT` dans plusieurs jours, un lundi ; `TimersCalendar={ OnCalendar=Mon *-*-* 07:30:00 … }` | drop-in `20-audit.conf` : contrôle hebdomadaire « pendant l'audit » ; il ne tourne plus que le lundi |

Provenance : la date des drop-ins (`ls -l --time-style=full-iso /etc/systemd/system/ms-verif-sauvegardes.*.d/`) et les commandes `sudo` du journal (`journalctl _COMM=sudo --since -7d | grep -E 'systemctl|ms-verif'`) disent quand et qui ; leur commentaire dit pourquoi.

Tester une expression **avant** de la poser :

```
admin@adm01:~$ systemd-analyze calendar '*-*-* 30:07:00'
Failed to parse calendar specification '*-*-* 30:07:00': Invalid argument
admin@adm01:~$ systemd-analyze calendar --iterations 3 '*-*-* 07:30:00'
```

**Correctifs** : v1, `sudo systemctl start ms-verif-sauvegardes.timer` (et comprendre pourquoi il a été arrêté) ; v2 et v4, retirer le drop-in (`sudo rm …`, `daemon-reload`, `systemctl restart …timer`) ; v3, lever le gel **avec** son demandeur (Karim), retirer le drop-in, et si un gel est encore nécessaire un jour, le faire dans le script (avertissement journalisé, code ≠ 0 ou alerte explicite au-delà d'une date) plutôt que par une condition muette. Dans tous les cas, prouver le passage réel :

```
admin@adm01:~$ sudo systemctl start ms-verif-sauvegardes.service
admin@adm01:~$ systemctl show ms-verif-sauvegardes.service -p ConditionResult -p Result
ConditionResult=yes
Result=success
admin@adm01:~$ systemctl list-timers ms-verif-sauvegardes.timer      # NEXT : demain 07:30
```

**Pourquoi aucune alerte** : `OnFailure=` ne se déclenche que si le service **échoue** ; un service jamais démarré (v1, v2, v4) ou sauté par une condition (v3) n'échoue pas. Les notifications PBS signalent les échecs de sauvegarde, pas l'absence de contrôle.

**Chien de garde** : [`fichiers/M02-E41/bin/ms-verif-fraicheur`](fichiers/M02-E41/bin/ms-verif-fraicheur), avec [`ms-verif-fraicheur.service`](fichiers/M02-E41/systemd/ms-verif-fraicheur.service) et [`.timer`](fichiers/M02-E41/systemd/ms-verif-fraicheur.timer) (toutes les heures, `OnFailure=ms-alerte@%n.service`, utilisateur éphémère). Pour chaque timer donné, il vérifie : chargé, actif, activé, prochaine échéance à moins de 26 h, dernier passage du service déclenché exécuté (`ConditionResult=yes`), réussi, terminé il y a moins de 26 h. Il détecte les quatre variantes.

```
admin@adm01:~$ /usr/local/bin/ms-verif-fraicheur ms-verif-sauvegardes.timer
ms-verif-sauvegardes.timer         KO  prochaine échéance dans 96 h
```

Ses limites (à écrire dans le journal) : il tourne sur `adm01`, comme le contrôle : `adm01` éteinte, ou systemd qui ne lance plus rien, et les deux se taisent ensemble ; un `systemctl stop ms-verif-fraicheur.timer` le fait taire lui aussi. Pour voir ces cas, il faut un observateur **extérieur** qui attend un signe de vie : le contrôle pousse un « battement » (fichier horodaté sur un autre hôte, métrique), et l'observateur alerte sur son **absence** (règle « absent » de Prometheus, module 21).

**Prévention**
- Unités dans le dépôt, drop-ins interdits hors MR (dérive détectée par `systemd-delta`) ; `systemd-analyze calendar` et `systemd-analyze verify` dans la CI du projet pour les unités versionnées.
- Toute suspension d'un contrôle (gel, audit) a une date de fin et un ticket, et se voit dans le contrôle lui-même.

**Pièges classiques**
- Regarder seulement le journal du **service** (vide : il n'a pas tourné) et pas celui du **timer**.
- `systemctl enable` en croyant démarrer le timer (v1 : il est déjà `enabled`) ; il faut `start` (ou `enable --now`).
- Recopier une crontab dans `OnCalendar` : l'ordre des champs n'est pas le même (`minute heure …` contre `AAAA-MM-JJ HH:MM:SS`).

**En production chez MédiSphère**
Chaque contrôle planifié publie une métrique « dernier succès » ; Alertmanager alerte sur l'âge de cette métrique et sur son absence (*dead man's switch*), depuis l'infrastructure de supervision, hors des machines surveillées.

---

### M02-E42 — Panne : l'environnement Python est cassé

**Démarche de diagnostic**

*Symptômes* : variantes 1 et 2, `medictl` ne marche plus ; variantes 3 et 4, `task test` et `uv run medictl --version` plantent dans `~/src/outils`.

**Étape 1 — Quelle chaîne d'exécution ?**

```
admin@adm01:~$ type -a medictl
admin@adm01:~$ ls -l "$(command -v medictl)"; readlink -f "$(command -v medictl)"
admin@adm01:~$ head -n 1 "$(readlink -f "$(command -v medictl)")"
admin@adm01:~$ uv tool list; uv tool dir; uv python dir
admin@adm01:~$ python3 -c 'import importlib.util as u; print(u.find_spec("medictl"))'
```

**Variante 1 — interpréteur de l'outil disparu.**

```
admin@adm01:~$ medictl --version
-bash: /home/admin/.local/bin/medictl: cannot execute: required file not found
admin@adm01:~$ head -n 1 ~/.local/share/uv/tools/medictl/bin/medictl
#!/home/admin/.local/share/uv/tools/medictl/bin/python
admin@adm01:~$ ls -l ~/.local/share/uv/tools/medictl/bin/python
… python -> /home/admin/.local/share/uv/python/cpython-3.13.5-linux-x86_64-gnu/bin/python3.13
```

Le message de Bash (« required file not found ») vise l'**interpréteur** du shebang, pas le lanceur : le lanceur existe, le Python vers lequel pointe l'environnement de l'outil n'existe plus (« ménage » dans `~/.local/share/uv/python`). Correctif : `uv tool install --force --reinstall medictl --index outils=<URL-REGISTRE>` (même index qu'en M02-E25 ; `--reinstall` recrée l'environnement). Prévention : `python-preference = "only-system"` dans `~/.config/uv/uv.toml` (les outils utilisent `/usr/bin/python3.13`, mis à jour par `apt`) ; ne jamais nettoyer les dossiers de uv à la main (`uv python uninstall`, `uv cache prune` le font proprement).

**Variante 2 — vieux paquet installé par `pip --user`.**

```
admin@adm01:~$ medictl --version
medictl 0.1.0
admin@adm01:~$ head -n 1 ~/.local/bin/medictl ; ls -l ~/.local/bin/medictl
#!/usr/bin/python3
-rwxr-xr-x 1 admin admin … ~/.local/bin/medictl        # un fichier, plus un lien vers l'environnement de uv
admin@adm01:~$ python3 -c 'import medictl; print(medictl.__file__)'
/home/admin/.local/lib/python3.13/site-packages/medictl/__init__.py
admin@adm01:~$ cat ~/.local/lib/python3.13/site-packages/medictl-0.1.0.dist-info/INSTALLER
pip
```

Un prototype 0.1.0 a été installé par `pip install --user --break-system-packages` : le lanceur de pip a remplacé celui de uv dans `~/.local/bin` (même nom, même dossier), et le paquet est dans le site utilisateur, visible de **tout** Python 3.13 du système. `uv tool list` continue d'annoncer la bonne version : il ne regarde que ses propres reçus. Correctif : archiver puis retirer `~/.local/lib/python3.13/site-packages/medictl` et `medictl-0.1.0.dist-info` (et le lanceur), puis `uv tool install --force medictl --index outils=<URL-REGISTRE>` (`--force` réécrit le lanceur). L'option `--break-system-packages` porte bien son nom : Debian l'interdit par défaut (PEP 668) précisément pour cela.

**Variante 3 — paquet présent dans les métadonnées, absent sur le disque.**

```
admin@adm01:~/src/outils$ uv run --no-sync medictl --version
ModuleNotFoundError: No module named 'typer'
admin@adm01:~/src/outils$ uv pip show typer | head -n 2
Name: typer
Version: 0.27.x
admin@adm01:~/src/outils$ ls .venv/lib/python3.13/site-packages/ | grep -i typer
typer-0.27.x.dist-info
admin@adm01:~/src/outils$ uv sync --locked; uv run --no-sync python -c 'import typer'   # toujours en échec
```

uv (comme pip) juge un paquet installé d'après son dossier `*.dist-info` ; il ne vérifie pas que les fichiers listés dans `RECORD` existent. `uv sync` ne fait donc rien. Correctif : `uv sync --locked --reinstall-package typer`, ou, plus simple et plus sûr, `rm -rf .venv && uv sync --locked` : `.venv` est **jetable**, il se reconstruit à l'identique à partir de `uv.lock`.

**Variante 4 — un `.pth` qui masque le paquet du projet.**

```
admin@adm01:~/src/outils$ uv run --no-sync python -c 'import medictl; print(medictl.__file__)'
/opt/workbook/m02/e42/compat-infoger/medictl/__init__.py
admin@adm01:~/src/outils$ uv run --no-sync python -c 'import sys; print("\n".join(sys.path))'
admin@adm01:~/src/outils$ grep -H . .venv/lib/python3.13/site-packages/*.pth
…/00-compat-infoger.pth:/opt/workbook/m02/e42/compat-infoger
…/medictl.pth:/home/admin/src/outils/src
```

Au démarrage, le module `site` lit les fichiers `.pth` de `site-packages` **par ordre alphabétique** : chaque ligne qui est un chemin existant est ajoutée à `sys.path`, chaque ligne qui commence par `import` est **exécutée**. `00-compat-infoger.pth` passe avant le `.pth` de l'installation éditable du projet : le vieux module InfoGér est trouvé en premier, sans `cli`, d'où `No module named 'medictl.cli'`. Correctif : retirer le `.pth` (ou recréer `.venv`), puis traiter le besoin « compatibilité InfoGér » autrement (un module distinct, nommé autrement, dans le projet). Note de sécurité : un `.pth` est un moyen discret d'exécuter du code dans **chaque** interpréteur de l'environnement ; un fichier `.pth` inattendu se traite comme une alerte.

**Vérification** : `medictl --version` (version de `uv tool list`), `cd ~/src/outils && task test`, `lab/bin/check 02 42`.

**Règles d'hygiène** (proposition pour `CONTRIBUTING.md`)
1. Les outils s'installent par `uv tool install` depuis le registre ; jamais `pip install --user`, jamais `--break-system-packages` (v2).
2. `.venv` et les environnements d'outils sont jetables : en cas de doute, on les recrée (`rm -rf .venv && uv sync --locked`, `uv tool install --force --reinstall`) ; on ne les répare pas à la main et on n'y dépose rien (v3, v4).
3. Interpréteur : le Python 3.13 de Debian (`python-preference = "only-system"`) ; pas de « ménage » manuel dans `~/.local/share/uv` (v1).

**Explications**

Un programme Python installé est une chaîne : une commande trouvée dans le `PATH` → un lanceur → son shebang (interpréteur **absolu**) → l'environnement de cet interpréteur (`pyvenv.cfg`, `site-packages`, `.pth`, site utilisateur sauf dans un venv isolé) → le paquet importé. Chaque maillon peut être remplacé sans que les autres le sachent : uv croit son outil installé (reçu), pip croit son paquet installé (`dist-info`), Python importe le premier module trouvé dans `sys.path`. Le diagnostic consiste à remonter la chaîne réelle, pas à faire confiance aux inventaires.

**Pièges classiques**
- `uv tool uninstall medictl && uv tool install …` en variante 2 : le paquet du site utilisateur reste visible du Python système, et le prochain `pip --user` recommence.
- Chercher dans le code de `medictl` une erreur qui vient de l'environnement.
- Réinstaller sans avoir lu `head -n 1` du lanceur : on ne saura jamais ce qui était cassé.

**En production chez MédiSphère**
Les postes d'administration sont gérés par Ansible (module 04) : version de `medictl` épinglée, environnement recréé à chaque mise à jour, détection des installations `pip --user`. À terme, les outils sont distribués en conteneur ou en binaire autonome (module 12), ce qui supprime la dépendance au Python du poste.

---

### M02-E43 — Astreinte : l'outillage en panne

**Démarche de diagnostic**

Comme en M00-E46, la difficulté est **méthodologique** : deux pannes déjà connues, des symptômes qui se recouvrent, et des outils de diagnostic qui peuvent eux-mêmes être touchés.

**1. Triage (10 minutes).** Liste brute des symptômes, puis :

```
admin@adm01:~/DevOpsPrivateCloud$ for x in 35 36 37 38 39 41 42; do lab/bin/check 02 "$x" >"/tmp/check-$x.txt" 2>&1 & done; wait
admin@adm01:~/DevOpsPrivateCloud$ lab/bin/check 02 40          # plus long : il mesure une exécution
admin@adm01:~/DevOpsPrivateCloud$ grep -l 'KO' /tmp/check-*.txt
```

| Symptôme | Impact | Outil touché | Dépend de |
|---|---|---|---|
| alerte du contrôle des sauvegardes | on ne sait plus si les sauvegardes existent (risque HDS) | `ms-verif-sauvegardes` | systemd, jetons `!lecture`, réseau vers `pbs01` |
| `medictl` muet ou en erreur | interventions sans instantané | `medictl`, `ms-snapshot` | jeton `!lab`, CA, environnement Python |

**2. Ordre de traitement.** D'abord les **instruments** : environnement Python (E42) et accès à l'API (E36), parce qu'ils conditionnent `medictl`, `ms-snapshot` et le contrôle des sauvegardes ; ensuite ce qui protège les données (E35, E41 : savoir si les sauvegardes existent ; E37, E39 : données supprimées ou perdues, à figer avant tout) ; enfin la CI (E38) et la performance (E40). Exception : un script qui détruit des données et **tourne encore** (E37, E39 planifiés) passe en premier, pour arrêter l'hémorragie.

**3. Masquages typiques de ce module.**

| Paire | Ce qu'on voit d'abord | Ce qui reste caché |
|---|---|---|
| E35 + E36 (v2) | contrôle en échec : « fichier de configuration illisible » | après le drop-in retiré, nouvel échec : « aucune VM … visible » (ACL de l'utilisateur) |
| E41 + E35 | le contrôle ne tourne plus | une fois le timer réparé, il tourne… et échoue (environnement du service) |
| E36 + E42 | `medictl` en erreur Python (v1, v2) | une fois l'outil réinstallé, `medictl` renvoie un 401 ou une liste vide |
| E36 (v3) + E38 | MR rouge en CI | la correction est validée en local… avec un `medictl` qui ne joint plus Proxmox : tu crois ton test local cassé par ta correction |
| E40 + E36 | inventaire lent | une fois corrigé, l'inventaire est rapide… et vide (droits) |

Après chaque correction : **rejouer tous les contrôles du triage**. Un message qui change est un progrès, pas une régression.

**4. Communication** (exemples) :

> **[INC-2850] 09:10 — En cours.** Impact : le contrôle des sauvegardes de 07:30 n'a pas abouti et `medictl` ne voit plus les VMs. Sauvegardes de la nuit vérifiées à la main sur `pbs01` : présentes. Intervention de 14 h : en attente des instantanés. Prochain point : 09:40.

> **[INC-2850] 09:45 — Partiellement rétabli.** Première cause corrigée (configuration du service de contrôle). Le contrôle échoue encore pour une seconde cause, côté droits Proxmox, en cours. Prochain point : 10:15.

> **[INC-2850] 10:20 — Résolu.** Droits rétablis, contrôle des sauvegardes et `medictl` opérationnels, instantanés possibles pour 14 h. Post-mortem sous 5 jours ouvrés.

**5. Post-mortem.** Exemple complet : [`fichiers/M02-E43/post-mortem-exemple.md`](fichiers/M02-E43/post-mortem-exemple.md) (paire E35 v1 + E36 v2). Grille d'évaluation : celle de M00-E46 (sans recherche de coupable ; chronologie sourcée ; deux causes prouvées ; détection ; actions typées avec responsable et échéance ; explication du masquage).

**Annulation** si nécessaire : `lab/bin/break 02 43 --annuler`. **Vérification** : `lab/bin/check 02 43` (post-mortem présent et commité, aucune panne active, contrôles de E35 à E42 rejoués).

**Pièges classiques**
- Réinstaller `medictl` avant de savoir s'il est en cause (on détruit la preuve d'E42 et on ne règle pas E36).
- Conclure « le contrôle est réparé » parce que le message d'erreur a disparu, sans vérifier `Result=success`.
- Relancer un script de purge ou d'archivage pour « voir s'il marche » pendant l'incident.

**En production chez MédiSphère**
L'outillage d'exploitation est un service à part entière : propriétaire, supervision de ses contrôles planifiés, astreinte, post-mortems. Le workbook final F3 (« semaine d'astreinte ») mélange pannes d'infrastructure et pannes d'outillage.

---

### M02-E44 — Sous le capot : expansions, sous-shells et descripteurs

**Solution**

- Spécification exécutable : [`fichiers/M02-E44/tests/bats/sous-le-capot.bats`](fichiers/M02-E44/tests/bats/sous-le-capot.bats) (20 tests, Bash 5.2, bats-core 1.13, ShellCheck et shfmt propres) ;
- analyse avec le tableau de revue, les 14 réponses et l'audit : [`fichiers/M02-E44/docs/analyses/sous-le-capot-bash.md`](fichiers/M02-E44/docs/analyses/sous-le-capot-bash.md).

Résultats attendus des expériences des étapes 1 à 3 (avec `n=3`) :

```
{1..3}            {1,2}                         # accolades avant variables
~  /home/admin                                  # tilde issu d'une variable : littéral
0  1  2  1  3                                   # $vide, "$vide", "$@", "$*", $@
a.log b.log  *.log  *.absent                    # globbing du contenu non protégé ; pas de correspondance : littéral
[a]                                             # sauts de ligne finaux supprimés
0                                               # tube : sous-shell
<PID> <PID> 0  /  <PID> <AUTRE-PID> 1           # $$ constant, $BASHPID et BASH_SUBSHELL changent
7 /home/admin                                   # exit et cd dans ( … ) restent dans le sous-shell
err (à l'écran) ; un.txt : out ; deux.txt : out err
10 (ou plus) ; l-wx------ … 10 -> …/trace.txt
/dev/fd/63 ; 4
```

L'option dont dépend une des corrections du compteur est `lastpipe` : elle ne prend effet que si le contrôle des tâches est désactivé, ce qui est le cas d'un script mais pas d'un terminal interactif (où `set +m` serait nécessaire) ; d'où la consigne de vérifier « dans un script ».

Expérience du verrou hérité (étape 3) :

```bash
#!/usr/bin/env bash
set -euo pipefail
exec {v}>/tmp/demo.verrou
flock -n "$v" || { echo "déjà verrouillé" >&2; exit 3; }
sleep 300 &           # hérite du descripteur $v : il tient le verrou
# sleep 300 {v}>&- &  # correction : le descripteur est fermé pour l'enfant
echo "fin du script"
```

```
admin@adm01:~$ bash demo.sh; flock -n /tmp/demo.verrou true; echo $?
fin du script
1
admin@adm01:~$ fuser -v /tmp/demo.verrou
                     USER        PID ACCESS COMMAND
/tmp/demo.verrou:    admin      4242 F.... sleep
```

Dans `plateforme/outils`, `lock_or_die` (E13) ouvre ainsi un descripteur et le verrouille pour toute la durée du script : tout processus lancé en arrière-plan pendant ce temps (un `ssh` de `ms-etat-hotes` qui survivrait, un `sleep` de test) prolonge le verrou. La règle d'équipe qui en découle : un script qui tient un verrou ne laisse aucun enfant derrière lui (M02-E28, M02-E30), ou ferme le descripteur pour ses enfants.

**Explications**

Presque tous les « comportements étranges » de Bash se déduisent de trois mécanismes : l'**ordre** des expansions (et le fait que le découpage et le globbing s'appliquent aux résultats non protégés), le **processus** dans lequel chaque morceau s'exécute (sous-shell ou non), et la **table des descripteurs** (copiée à chaque redirection, héritée à chaque `fork`). Une spécification exécutable les fige : elle sert de documentation vérifiée, de test de non-régression lors d'une montée de version de Bash (Debian 14 changera de version), et de support de revue (« voir le test n° 8 »).

**Alternatives**
- Documenter sans tests : moins coûteux, mais rien ne garantit que la note reste vraie.
- Remplacer Bash par Python dès qu'un script manipule des données (ADR-0020) : réduit la surface, pas le besoin de comprendre les scripts existants.

**Pièges classiques**
- Tester dans le shell de bats (options, `set -e` de bats, fonctions définies) au lieu d'un `bash` neuf : les résultats changent.
- Un test « verrou » qui laisse un `sleep` orphelin quand il échoue (d'où `teardown`).
- Des tests qui décrivent ce que fait **ta** machine (locale, `HOME`) plutôt que Bash.

**En production chez MédiSphère**
La spécification fait partie de la CI de `plateforme/outils` ; la grille de revue Bash de `CONTRIBUTING.md` renvoie à ses tests. Les nouveaux arrivants commencent par la lire.

---

### M02-E45 — Questions expert : shell et Python

**1. Contextes de `set -e`** (avec `f() { false; echo suite; }`) — vérifié sur Bash 5.2.
- a) `f` : **arrêt** à `false`, dans la fonction ; `suite` n'est pas affiché.
- b) `if f; then …` : pas d'arrêt ; `-e` est ignoré dans **tout** le corps de `f` (`suite` s'affiche), `f` rend 0.
- c) `f || echo raté` : pas d'arrêt, même règle ; `f` rend 0 (code d'`echo suite`), « raté » n'est pas affiché.
- d) `x=$(f)` : pas d'arrêt ; dans la substitution, Bash (hors mode POSIX) **retire** `-e` : `false` n'arrête pas le sous-shell, qui rend 0 ; avec `shopt -s inherit_errexit`, le sous-shell s'arrêterait sur `false` et rendrait 1, puis l'affectation arrêterait le script.
- e) `local y; y=$(f)` : comme d) (affectation séparée : son code est celui de la substitution, ici 0). Avec `local y=$(f)`, ce serait le code de `local`, toujours 0.
- f) `echo "$(f)"` : pas d'arrêt ; le code de la ligne est celui d'`echo`.
Seule a) arrête le script. Morale : le corps d'une fonction ne doit jamais compter sur `-e` (M02-E39).

**2. `trap … ERR`.** Le piège `ERR` n'est pas hérité par les fonctions, substitutions et sous-shells, sauf avec `set -E` (`errtrace`). Il se déclenche dans les mêmes conditions que la sortie de `set -e` (commande qui échoue hors condition, hors liste `&&`/`||` non finale, hors `!`), parce que Bash utilise la même logique pour décider si un échec est « non traité ». Donc : muet dans un `if`, après `||`, dans un tube sans `pipefail`, etc.

**3. `exec` en fin de script.** `exec` remplace le processus du shell par le programme : même PID, plus de shell parent. Conséquences : le processus principal du service (`MainPID`) est maintenant le programme lui-même, pas un shell qui attend son enfant et diffère ses `trap` (M02-E30) ; à l'arrêt, systemd envoie SIGTERM à tous les processus du groupe de contrôle (`KillMode=control-group` par défaut), mais c'est le programme qui le reçoit en tant que processus principal et dont la sortie termine le service ; le code de sortie du service est celui du programme ; les `trap` du script ne s'exécutent jamais (le shell n'existe plus), y compris `trap … EXIT` : un nettoyage doit être fait **avant** l'`exec`. C'est le bon schéma pour un enveloppeur qui prépare l'environnement puis passe la main.

**4. QCM `ssh` dans une boucle — réponse b.** `ssh` lit son entrée standard (pour la transmettre à la commande distante) et consomme le reste de `hotes.txt`. a) est faux (`read` lit une ligne entière et ne découpe qu'à l'affectation de plusieurs variables). c) est faux : le code de `ssh` n'est pas testé par `while`. d) ferait perdre la **dernière** ligne, pas toutes sauf la première. Corrections : `ssh -n` (ou `< /dev/null`), ou lire le fichier sur un autre descripteur : `while read -r h <&3; do …; done 3< hotes.txt`. (C'est le défaut corrigé dans la version « SSH » de l'inventaire d'E40.)

**5. `printf` plutôt qu'`echo`.** `echo` interprète certaines valeurs comme des options ou des séquences, selon le shell et ses options (`xpg_echo`) : `var='-n'` n'affiche rien, `var='-e'` aussi, `var='a\nb'` donne une ou deux lignes selon `-e`/`xpg_echo`/le shell `/bin/sh`. `printf '%s\n' "$var"` affiche la valeur telle quelle, partout.

**6. `/tmp/ms-diag.$$` en root.** Le nom est prévisible (PID visibles, faible plage) : un utilisateur local crée à l'avance `/tmp/ms-diag.<PID>` comme lien symbolique vers `/etc/shadow` ou `/root/.bashrc` ; root suit le lien et écrase la cible (le noyau protège en partie : `fs.protected_symlinks=1` empêche de suivre dans `/tmp` un lien appartenant à un autre utilisateur ; il ne faut pas compter dessus, et un fichier préexistant ordinaire peut aussi être lu par l'attaquant). Parade : `mktemp` (création atomique `O_EXCL`, nom aléatoire, mode 600), dans un dossier non partagé. `PrivateTmp=yes` donne au service un `/tmp` privé (espace de noms de montage) : aucun autre utilisateur ne peut y préparer quoi que ce soit, et il est vidé à l'arrêt.

**7. QCM `subprocess.run` — réponse b.** Sans `check=True`, `run` renvoie un `CompletedProcess` dont il faut tester `returncode` ; aucune exception, aucun avertissement (a, c faux), aucune relance (d). Avec `shell=True` et une f-string, toute valeur contrôlée par un tiers (nom de fichier, argument) peut injecter des commandes (`; rm -rf …`) : passer une **liste** d'arguments, sans shell (règles ruff/bandit S602, S603, S604).

**8. `requests` sans `timeout`.** Aucun délai par défaut : si `pve01` accepte la connexion mais ne répond jamais, l'appel attend indéfiniment (le service planifié reste « activating » jusqu'à `TimeoutStartSec`, la CLI ne rend jamais la main). `timeout=(connexion, lecture)` : le premier borne l'établissement de la connexion TCP, le second l'attente **entre deux octets** reçus. Aucun des deux ne borne la **durée totale** : un serveur qui envoie un octet toutes les 9 s avec un délai de lecture de 10 s tient indéfiniment. Pour une borne totale : délai global applicatif (fil de surveillance, `signal.alarm` dans le fil principal, ou délai de l'outil appelant, comme `ms-attendre` en E30).

**9. Magasin de certificats de `requests`.** Par défaut, `verify=True` utilise le paquet `certifi` (racines Mozilla embarquées), **pas** le magasin du système ; les variables `REQUESTS_CA_BUNDLE` et `CURL_CA_BUNDLE` le remplacent pour toute la session si `verify` n'est pas fourni explicitement (`trust_env`) ; `verify="<fichier>"` impose un fichier. Un environnement qui définit `REQUESTS_CA_BUNDLE` (pour un proxy d'entreprise, par exemple) changerait silencieusement l'autorité utilisée. `medictl` passe donc explicitement `PVE_CACERT` : l'autorité de confiance est une donnée de **sa** configuration, pas de l'environnement. Piège connu : quand `verify` est fixé sur la **session** (c'est ce que fait proxmoxer) et non sur chaque requête, `requests` applique quand même `REQUESTS_CA_BUNDLE` par-dessus (fusion des réglages d'environnement avant ceux de la session). Parades : `session.trust_env = False` (ignore aussi les proxys de l'environnement : à décider consciemment), ou refuser de démarrer si `REQUESTS_CA_BUNDLE`/`CURL_CA_BUNDLE` sont définis. Vérifié avec requests 2.34 : `Session.merge_environment_settings` renvoie le fichier de `REQUESTS_CA_BUNDLE` même quand `session.verify` désigne `PVE_CACERT`.

**10. QCM `no_proxy` et adresse IP — réponse b.** `requests` (comme `curl`) compare l'hôte de l'URL aux entrées de `no_proxy` : un nom est comparé par suffixe de domaine, une adresse IP aux entrées qui sont des adresses ou des réseaux CIDR. `.medisphere.internal` ne correspond pas à une adresse IP : la requête passe par le proxy (a faux). c) est faux : `no_proxy` accepte noms et adresses. d) est faux : `requests` lit `https_proxy` et `HTTPS_PROXY` (la casse ne change pas la logique d'exemption). C'est la variante 3 de M02-E35.

**11. `sys.path` dans un environnement uv.** Le lanceur `.venv/bin/python` est un lien vers un interpréteur de base ; au démarrage, Python trouve `pyvenv.cfg` à côté, en déduit `sys.prefix` (l'environnement) distinct de `sys.base_prefix`, et n'ajoute **pas** le site utilisateur ni les `site-packages` du système (sauf `include-system-site-packages = true`). Ordre : dossier du script (ou chaîne vide pour `-c`), `PYTHONPATH`, bibliothèque standard, `site-packages` de l'environnement, puis chemins ajoutés par les `.pth` de `site-packages`, lus par ordre alphabétique. Une ligne de `.pth` qui est un chemin est **ajoutée** ; une ligne qui commence par `import` est **exécutée** à chaque démarrage. D'où le vecteur d'attaque : déposer un `.pth` dans un `site-packages` accessible en écriture, c'est faire exécuter du code par chaque programme Python de l'environnement, sans modifier aucun fichier de code (E42 v4 en montre la version « innocente »).

**12. Lanceur `uv tool`.** Dans `~/.local/bin`, un lien vers `…/uv/tools/medictl/bin/medictl`, petit script dont le shebang est le **chemin absolu** de l'interpréteur de l'environnement de l'outil, lui-même lien vers un Python de base. Si ce Python disparaît, le noyau ne peut plus lancer le script : « cannot execute: required file not found » (E42 v1). Avec le Python 3.13 de Debian, l'interpréteur de base est géré par `apt` (mises à jour de sécurité, jamais supprimé par un ménage), au prix d'une version mineure figée par la distribution ; un Python téléchargé par uv doit être mis à jour et conservé par l'équipe elle-même.

**13. `uv sync`, `--locked`, `--frozen`.** Sans option : si `uv.lock` ne correspond plus à `pyproject.toml`, uv **reverrouille** (modifie `uv.lock`) puis synchronise : pratique en développement, dangereux en CI (le build ne teste pas ce qui est commité). `--locked` : refuse (erreur) si le verrou doit changer : c'est le bon choix en CI et dans les tâches du Taskfile. `--frozen` : utilise le verrou tel quel **sans vérifier** qu'il correspond : pour un déploiement où l'on veut exactement le verrou, même si `pyproject.toml` a bougé (le job de publication de E25 l'utilise pour `uv version`). En local : `uv sync` ou `task setup` (qui est `--locked`) ; ne jamais committer un `pyproject.toml` modifié sans `uv.lock` (E38 v1).

**14. QCM SIGTERM — réponse b.** Python laisse SIGTERM à son action par défaut (terminaison par le noyau) : ni `finally`, ni gestionnaires `atexit`, ni vidage des tampons d'écriture. a) est faux : seul SIGINT est traduit en `KeyboardInterrupt`. c) faux. d) faux : systemd attend `TimeoutStopSec`, puis envoie SIGKILL. Arrêt propre : `signal.signal(signal.SIGTERM, gestionnaire)` qui lève une exception (par exemple `SystemExit(143)`) pour que les `finally` s'exécutent, et un nettoyage borné dans le temps. La tâche Proxmox (clonage) continue de toute façon : elle est exécutée par `pvedaemon` sur `pve01`, pas par `medictl` ; l'outil arrêté doit donc être **relançable** (idempotence, M02-E27) plutôt que d'essayer d'annuler.

**15. Signaux et fils.** Python exécute les gestionnaires de signaux uniquement dans le fil principal de l'interpréteur principal (le gestionnaire C ne fait que noter le signal ; le fil principal l'exécute entre deux instructions). Si le fil principal est bloqué dans `executor.shutdown(wait=True)` ou un `future.result()` sans délai, la réaction peut être retardée ; les fils de travail ne sont pas interrompus par le signal. Pour un outil à `ThreadPoolExecutor` : le fil principal attend avec des délais courts (`wait(…, timeout=…)`), réagit au signal en levant un drapeau (`threading.Event`) que les fils consultent, et annule les tâches non commencées (`executor.shutdown(cancel_futures=True)`).

**16. `logging.basicConfig()`.** Il ne configure le journal racine que s'il n'a encore **aucun** gestionnaire : le premier appel gagne, les suivants ne font rien (sauf `force=True`). Une bibliothèque qui l'appelle à l'import impose donc son format, son niveau et sa destination à l'outil. Règle : une bibliothèque ne configure jamais la journalisation (elle se contente de `logging.getLogger(__name__)`, éventuellement un `NullHandler`) ; l'outil configure le journal racine **une fois**, dans son point d'entrée (`medictl` le fait selon `-v`). Secret : ne jamais le passer à un appel de journal ; en défense, un `logging.Filter` qui remplace le secret connu par `***` dans chaque message (ce que fait `journal.masquer` de `medictl`), et `repr=False` sur le champ de configuration.

**17. `ms-archiver-journaux` en Python.** Gratuitement : les erreurs deviennent des exceptions qui remontent par défaut (`tarfile`, `os.remove`, `subprocess.run(check=True)`), les structures de données sont réelles (listes de fichiers, ensembles pour comparer), pas de découpage ni de globbing involontaires, des tests confortables (pytest, `tmp_path`). À écrire soi-même : le contrat (lister avant, comparer l'archive à la liste, ne supprimer que ce qui est archivé), l'atomicité (écrire dans un fichier temporaire du même dossier puis `os.replace`), la poursuite des autres hôtes en cas d'erreur sur l'un (un `try/except` par hôte, code final 1), la gestion des droits (`PermissionError` à traiter comme un échec de l'hôte), les codes retour de la convention, et la journalisation. Python évite les pièges de `set -e`, pas les erreurs de conception.

**18. Quel outil aurait arrêté quoi.**

| Panne | Arrêtée par | Pas vue par |
|---|---|---|
| E37 v1 (variable non définie) | ShellCheck (SC2154) ; `set -u` | — |
| E37 v2 (précédence de `find`) | ShellCheck (SC2146) ; test sur données | revue rapide (la ligne « a l'air juste ») |
| E37 v3 (`cd` non vérifié) | ShellCheck (SC2164) ; test avec une application sans `tmp/` | test sur un jeu où toutes les applications ont `tmp/` |
| E37 v4 (`-mtime -30`) | **seulement** un test sur données datées, ou une revue attentive | ShellCheck |
| E39 (`set -e` contourné) | test « fichier illisible » ; partiellement ShellCheck avec `check-set-e-suppressed` (v2) et SC2155 (v3) | ShellCheck par défaut (v1, v2, v4), revue qui « fait confiance au mode strict » |
| E42 (environnement) | rien dans le code : contrôle de l'environnement (`lab/bin/check 02 42`), règles d'hygiène, gestion de configuration | ruff, pytest en CI (environnement neuf à chaque job), revue de code |

Conclusion : l'analyse statique attrape vite et pour rien les erreurs **de forme** ; les tests sur données attrapent les erreurs **de logique** ; la revue attrape les erreurs **d'intention** (« pourquoi supprimer tout `tmp/` ? ») ; et aucun ne voit l'**environnement**, qui relève de la gestion de configuration et de la supervision. Il faut les quatre.

**Points faibles** : relis les questions où ta réponse divergeait, et refais l'exercice correspondant (E39 pour 1-2, E44 pour 4-6, E42 pour 11-12, E30 pour 14-15).
