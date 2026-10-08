# Module 09 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. Dans un cluster, « j'ai redémarré le nœud et ça remarche » est presque toujours faux : un redémarrage efface la preuve (règle posée à chaud, votes attendus en mémoire, horloge), peut déclencher une clôture ou une reprise HA, et laisse la cause en place pour la prochaine fois.

Les scripts d'injection sont dans `corrige/pannes/` (`_m09-commun.sh` : exécution root sur les nœuds, sauvegarde et restauration de fichiers y compris dans `/etc/pve`, table nftables dédiée, désarmement et réarmement de la HA, VMs de test 191-197). Chaque modification est journalisée sur le nœud touché dans `/var/lib/workbook/pannes.log` (copies d'origine dans `/var/lib/workbook/M09-EXX.*`) et sur `adm01` dans `~/.local/state/workbook/M09-EXX/`.

Les sorties reproduites sont **représentatives** : identifiants, horodatages, numéros d'époque et formulations exactes varient selon les versions. Elles suivent la documentation de Proxmox VE 9.2 (Corosync 3.1 / knet, pmxcfs, `pve-ha-manager`), de Ceph Tentacle 20.2 et de Proxmox Backup Server 4.

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) :
- libellé exact de `ha-manager status` quand la pile HA est désarmée (`disarm-ha`, nouveauté 9.2) : les scripts cherchent le mot « disarm » ; la façon dont le désarmement libère les watchdogs suit les notes de développement de la fonction ;
- prise en compte à chaud de `quorum { expected_votes }` au rechargement de Corosync (E35 v2) : votequorum relit `expected_votes` au rechargement d'après `man votequorum` ; si ton lab ne perd pas le quorum, le script passe à une autre variante ;
- comportement de `pveproxy` quand le certificat ne correspond plus à la clé (E36 v3 : refus de démarrer attendu) et adresse publiée dans `.members` quand `/etc/hosts` donne une autre adresse au nom du nœud (E36 v4) ;
- état HA obtenu avec une règle d'affinité négative sur trois ressources quand un nœud passe en maintenance (E37 v2 : `error` d'après la documentation des règles strictes ; selon la version, la ressource peut aussi rester sur le nœud en maintenance) ;
- message exact de migration pour une ISO locale montée (E38 v2), de PBS pour un namespace inexistant (E41 v3), de pmxcfs pour un disque plein (E42 v2) et refus (ou non) d'un point de montage non vide par pmxcfs selon la version de FUSE utilisée (E42 v3) ;
- présence de `/root/.ssh/authorized_keys` sous forme de lien vers `/etc/pve/priv/authorized_keys` en 9.2 (E40 v3 : le script fonctionne dans les deux cas).

---

## Méthode commune aux pannes de cluster

1. **Vue par nœud.** Sur chacun des trois nœuds, dans cet ordre : `corosync-quorumtool -s` (membre, votes, quorum), `corosync-cfgtool -s` (liens), `systemctl status corosync pve-cluster`, `findmnt /etc/pve`. Une boucle depuis `adm01` suffit :
   ```
   admin@adm01:~$ for n in 51 52 53; do echo "== 10.10.10.$n"; ssh root@10.10.10.$n 'corosync-quorumtool -s | grep -E "Quorate|votes|Quorum:"; corosync-cfgtool -s | grep -E "LINK|nodeid"'; done
   ```
2. **Couche par couche.** Corosync (réseau, clé, configuration) → votequorum (votes) → pmxcfs (`/etc/pve`, `.members`) → API (`pveproxy`, tickets, certificats) → stockage (Ceph, ZFS, PBS) → HA (CRM, LRM, règles) → opérations (migration, réplication, sauvegarde). Le premier étage qui échoue est ton suspect.
3. **État chargé, pas seulement le fichier.** `corosync-cmapctl` (configuration réellement chargée), `nft list ruleset` (règles réellement actives), `ha-manager status -v`, `ceph health detail`, `pvesr status`, `pvesm status`.
4. **Chercher ce qui a bougé.** `find /etc -newermt '-12 hours' -type f`, `ls -l --time-style=full-iso /etc/pve/…`, `journalctl --since`, comparaison des fichiers et sommes de contrôle entre nœuds (un nœud sain est ton meilleur témoin).
5. **Corriger à la source, puis faire converger le code.** Rôles `pve_noeud` et `pve_cluster`, états OpenTofu `hv` et `hv-invites` ; second passage sans changement.
6. **Prévenir** : quelle sonde de `ms-verif-cluster`, quelle vérification de RB-090/RB-092, quel test Molecule aurait vu la panne avant l'utilisateur ?

---

### M09-E35 — Panne : le cluster a perdu le quorum

**Démarche de diagnostic**

*Symptôme* : `cluster not ready - no quorum? (500)` partout ; les VMs tournent (la perte de quorum n'arrête pas les invités, elle gèle la configuration) ; les autres nœuds en rouge dans l'interface.

*Hypothèses* : nœuds qui ne se voient plus (réseau Corosync, filtrage, clé) ; nœuds qui se voient mais votes insuffisants (configuration de votequorum, votes attendus forcés) ; nœuds arrêtés.

**Étape 1 — Vue par nœud.**

```
root@hv01:~# corosync-quorumtool -s
Quorum information
------------------
Quorum provider:  corosync_votequorum
Nodes:            1
Node ID:          0x00000001
Ring ID:          1.6a
Quorate:          No

Votequorum information
----------------------
Expected votes:   3
Highest expected: 3
Total votes:      1
Quorum:           2 Activity blocked
Flags:

Membership information
----------------------
    Nodeid      Votes Name
0x00000001          1 10.10.32.51 (local)
```

Deux familles de sorties se rencontrent :
- **`Total votes: 1` sur chaque nœud** (variantes 1 et 3) : chaque nœud est seul, la membre est cassée. Question suivante : pourquoi ne se parlent-ils plus ?
- **`Total votes: 3`, `Expected votes: 7`, `Quorum: 4 Activity blocked`** (variante 2) : les trois nœuds se voient, mais il en faudrait quatre. Ce n'est pas le réseau, c'est le calcul.

**Variante 1 — UDP de Corosync filtré dans hv02 et hv03.**

```
root@hv01:~# corosync-cfgtool -s
Local node ID 1, transport knet
LINK ID 0 udp
        addr    = 10.10.32.51
        status:
                nodeid:          1:     localhost
                nodeid:          2:     disconnected
                nodeid:          3:     disconnected
LINK ID 1 udp
        addr    = 10.10.10.51
        status:
                nodeid:          1:     localhost
                nodeid:          2:     disconnected
                nodeid:          3:     disconnected
root@hv01:~# ping -c 2 10.10.32.52
… 2 packets transmitted, 2 received …
```

Les deux liens sont coupés alors que l'ICMP passe : quelque chose laisse passer `ping` mais pas l'UDP 5405 (lien 0) et 5406 (lien 1). Le pare-feu de Proxmox VE (M09-E26) est le premier suspect, mais `pve-firewall compile` ne montre rien de neuf. Sur `hv02` :

```
root@hv02:~# nft list ruleset | grep -B3 -A3 5404
table inet infoger_durcissement {
        chain entree {
                type filter hook input priority -5; policy accept;
                udp dport 5404-5412 counter packets 18342 bytes 2915478 drop comment "InfoGer : ports non documentes"
        }
}
```

Une table nftables posée à chaud, hors du pare-feu géré par Proxmox VE (qui n'en a pas connaissance), et dont les compteurs montent. Même table sur `hv03`. Avec `hv02` et `hv03` sourds, **aucune** partition n'a deux votes : le cluster entier est sans quorum alors qu'un seul nœud (`hv01`) est sain. Cause racine : un « script de durcissement » appliqué à la main sur deux nœuds, sans revue. Correctif : `nft delete table inet infoger_durcissement` sur les deux nœuds ; les liens se reconnectent en quelques secondes (`corosync-cfgtool -s`), le quorum revient. Prévention : la seule source des règles de filtrage d'un nœud est le pare-feu de Proxmox VE géré par le code (M09-E26) ; `ms-verif-cluster` compare `nft list tables` à la liste attendue ; RB-093 commence par `corosync-cfgtool -s` sur chaque nœud.

**Variante 2 — `expected_votes` forcé dans la configuration.**

```
root@hv01:~# corosync-quorumtool -s | grep -E 'Expected|Total|Quorum:'
Expected votes:   7
Total votes:      3
Quorum:           4 Activity blocked
root@hv01:~# corosync-cmapctl -g quorum.expected_votes
quorum.expected_votes (u32) = 7
root@hv01:~# grep -n -A4 '^quorum' /etc/pve/corosync.conf
12:quorum {
13-  provider: corosync_votequorum
14-  expected_votes: 7
15-}
```

D'après `man votequorum`, `quorum.expected_votes` **remplace** la valeur calculée à partir de la `nodelist` (trois nœuds à un vote). Quorum = 7 / 2 + 1 = 4 votes, trois présents. Le fichier a été propagé par pmxcfs (`config_version` incrémentée) et relu par Corosync sur les trois nœuds : la panne est cohérente partout, ce qui la rend plus difficile à voir qu'un nœud isolé.

Correctif, dans l'ordre :
1. Rendre le quorum **en mémoire**, sur la partition complète (les trois nœuds se voient : aucun risque de *split-brain*) : `pvecm expected 3` (ou `corosync-quorumtool -e 3`). `Quorate: Yes` revient et `/etc/pve` redevient inscriptible.
2. Corriger le fichier qui fait foi, par la méthode de la documentation :
   ```
   root@hv01:~# cp /etc/pve/corosync.conf /root/corosync.conf.avant
   root@hv01:~# cp /etc/pve/corosync.conf /etc/pve/corosync.conf.new
   root@hv01:~# nano /etc/pve/corosync.conf.new        # retirer expected_votes, incrémenter config_version
   root@hv01:~# mv /etc/pve/corosync.conf.new /etc/pve/corosync.conf
   ```
   (Le fichier temporaire est créé **dans** `/etc/pve` pour que le renommage soit atomique et propagé d'un bloc.)
3. Vérifier sur les trois nœuds : `cmp /etc/corosync/corosync.conf /etc/pve/corosync.conf`, `corosync-cmapctl -g quorum.expected_votes` (clé absente), `Expected votes: 3`.

Note : `pvecm expected 1` aurait aussi rendu `/etc/pve` inscriptible, mais c'est le mauvais réflexe : sur une partition **incomplète**, il permet à deux moitiés d'écrire chacune de leur côté. Ici, les trois nœuds étant dans la membre, `3` est la valeur juste et sans danger.

**Variante 3 — clés de Corosync divergentes sur hv02 et hv03.**

```
root@hv02:~# journalctl -u corosync --since -2h | tail -n 5
… [KNET  ] link: host: 1 link: 0 is down
… [KNET  ] host: host: 1 has no active links
… [KNET  ] rx: … Unable to decrypt/authenticate packet …  (libellé selon la version de knet)
admin@adm01:~$ for n in 51 52 53; do ssh root@10.10.10.$n 'sha256sum < /etc/corosync/authkey'; done
3f6c…  -
a09d…  -
71be…  -
```

Trois sommes différentes : chaque nœud chiffre avec sa propre clé, aucun ne déchiffre les autres. `ls -l --time-style=full-iso /etc/corosync/authkey` date la modification (la nuit). La clé n'est **pas** dans `/etc/pve` : elle est copiée une fois, à l'adhésion. Correctif : recopier la clé du nœud sain sur les deux autres, puis redémarrer Corosync sur ceux-ci :

```
root@hv01:~# scp -p /etc/corosync/authkey root@10.10.10.52:/etc/corosync/authkey
root@hv01:~# scp -p /etc/corosync/authkey root@10.10.10.53:/etc/corosync/authkey
root@hv02:~# chmod 400 /etc/corosync/authkey && systemctl restart corosync
```

(SSH entre nœuds fonctionne même sans quorum.) Quel nœud a la « bonne » clé ? Celle que partagent le plus de nœuds… sauf qu'ici les trois diffèrent. La référence est celle qui n'a pas bougé (date de modification la plus ancienne, égale à celle de la création du cluster), ou, si tout a bougé, une nouvelle clé générée sur un nœud (`corosync-keygen`) et copiée partout, Corosync arrêté sur tous les nœuds puis redémarré : c'est la procédure de rotation, à faire en fenêtre de maintenance, HA désarmée.

**Vérification** : `lab/bin/check 09 35` après `lab/bin/break 09 35 --annuler` (qui réarme la HA).

**Explications**

Le quorum est une **majorité de votes** (`Expected votes / 2 + 1`), calculée par votequorum sur la membre établie par Corosync. Sans quorum, pmxcfs passe `/etc/pve` en lecture seule (aucune partition minoritaire ne peut modifier la configuration), le CRM ne prend aucune décision, et un nœud qui porte des ressources HA cesse de nourrir son watchdog : il se clôture en une minute environ. D'où le désarmement préalable fait par le script : sans lui, les nœuds isolés auraient redémarré, effaçant la variante 1 (règles posées à chaud) et brouillant les deux autres. En production, ce désarmement **n'aurait pas eu lieu** : un quorum perdu sur tout le cluster avec la HA active, c'est la clôture de tous les nœuds qui portent des ressources HA, donc l'arrêt brutal des VMs HA. RB-093 doit le dire.

Les trois variantes ont le même symptôme et trois signatures différentes : `Total votes: 1` + liens « disconnected » + ICMP qui passe (filtrage), `Total votes: 3` + `Expected votes` anormal (configuration), `Total votes: 1` + erreurs de déchiffrement dans le journal (clé).

**Alternatives**
- Variante 2 : on peut aussi corriger `expected_votes` directement après `pvecm expected 3` par `pvecm`, mais il n'existe pas de sous-commande qui retire une clé de `corosync.conf` : l'édition par `.new` reste la méthode documentée.
- Variante 3 : `pvecm updatecerts` ne touche pas à la clé de Corosync (il gère les certificats et les clés SSH) ; ce n'est pas un raccourci.

**Pièges classiques**
- Conclure « réseau » parce que les nœuds sont rouges, sans regarder `Total votes`.
- `pvecm expected 1` sur chaque nœud « pour débloquer » : trois partitions inscriptibles, trois configurations divergentes à réconcilier, et une HA qui peut démarrer la même VM deux fois si elle est armée.
- Éditer `/etc/corosync/corosync.conf` sur un nœud : il sera écrasé au prochain changement de `/etc/pve/corosync.conf`, ou pire, il sera la seule copie différente.
- Oublier d'incrémenter `config_version` : le nouveau fichier n'est pas pris en compte (et peut être refusé).
- Redémarrer Corosync sur tous les nœuds « pour voir » : cela ne corrige aucune des trois causes.

**En production chez MédiSphère**
RB-093 (fichier de solution : [`fichiers/M09-E35/medisphere/docs/virtualisation/runbooks/RB-093-perte-quorum.md`](fichiers/M09-E35/medisphere/docs/virtualisation/runbooks/RB-093-perte-quorum.md)). `ms-verif-cluster` alerte sur : un lien Corosync « disconnected » (avant la perte de quorum : avec deux liens, un seul tombé ne se voit pas dans l'interface), des sommes de `authkey` ou de `corosync.conf` différentes entre nœuds, `Expected votes` différent du nombre de nœuds de la `nodelist`, une table nftables hors de la liste attendue. Toute modification de Corosync passe par une fiche de changement (RB-092) et la HA désarmée.

---

### M09-E36 — Panne : un nœud ne rejoint plus le cluster

**Démarche de diagnostic**

*Symptôme* : `hv03` en rouge ou avec un point d'interrogation dans l'interface de `hv01` ; erreurs 401, 595 ou délai dépassé selon l'écran.

*Hypothèses*, par étage : membre Corosync (réseau, clé, configuration) ; pmxcfs (`pve-cluster` sur `hv03`, adresse annoncée) ; API (`pveproxy`, certificat, tickets donc horloge) ; plus haut, stockage.

**Étape 1 — Trois étages, trois mesures.**

```
root@hv01:~# corosync-quorumtool -l
root@hv01:~# python3 -m json.tool /etc/pve/.members
admin@adm01:~$ curl -sS -o /dev/null -w '%{http_code}\n' --resolve hv03.par1.medisphere.internal:8006:10.10.10.53 https://hv03.par1.medisphere.internal:8006/
root@hv01:~# pvesh get /nodes/hv03/version
```

| Variante | Membre Corosync | `.members` (ip, online) | API directe | Appel relayé |
|---|---|---|---|---|
| 1 clé | `hv03` absent | `10.10.10.53`, `0` | 200 | 595 / délai |
| 2 horloge | présent | `10.10.10.53`, `1` | 200 | **401** |
| 3 certificat | présent | `10.10.10.53`, `1` | échec TLS / refus | 595 |
| 4 `/etc/hosts` | présent | **`10.10.10.63`**, `1` | 200 | 595 (`No route to host`) |

**Variante 1 — clé de Corosync de hv03 remplacée.** `hv03` seul dans sa membre (`Total votes: 1`), `hv01` et `hv02` quorate. Journal de Corosync sur `hv03` : liens « down », erreurs de déchiffrement. `sha256sum /etc/corosync/authkey` diffère de celle des deux autres nœuds. Correctif : copier la clé d'un nœud sain (`scp -p root@10.10.10.51:/etc/corosync/authkey /etc/corosync/authkey` depuis `hv03`, droits 400), `systemctl restart corosync` sur `hv03`. Sans le désarmement de la HA par l'injection, `hv03` se serait clôturé une minute après la perte du quorum et ses ressources HA seraient reparties sur `hv01`/`hv02` : c'est le comportement voulu (M09-E24), mais il aurait masqué la cause (un nœud qui redémarre en boucle sans jamais revenir).

**Variante 2 — horloge de hv03 avancée de 3 h.** Corosync ne dépend pas de l'heure : la membre est complète. Mais les appels relayés vers `hv03` portent un ticket signé et daté par `hv01` ; pour `hv03`, qui vit trois heures plus tard, ce ticket a trois heures, au-delà de sa durée de validité (deux heures) : 401.

```
root@hv03:~# timedatectl
               Local time: mar. 2026-10-20 10:14:02 CEST
System clock synchronized: no
              NTP service: inactive
root@hv03:~# systemctl is-enabled chrony
disabled
root@hv03:~# ceph health detail | grep -i clock
[WRN] MON_CLOCK_SKEW: clock skew detected on mon.hv03
```

Ceph le voit aussi (`MON_CLOCK_SKEW`), et les OSD de `hv03` peuvent ne plus renouveler leurs tickets cephx : un nœud sans heure juste finit par perdre son stockage. Correctif : `systemctl enable --now chrony`, puis `chronyc makestep` (le saut est voulu ici, la VM n'a pas de charge sensible au temps ; en production, on évalue l'effet d'un saut de trois heures sur les bases de données des invités… qui ne sont pas concernées : seul l'hôte a dérivé). Vérifier `chronyc tracking` (`Leap status : Normal`) et `chronyc sources` (la passerelle du VLAN, M00).

**Variante 3 — certificat de pveproxy remplacé.** `systemctl status pveproxy` sur `hv03` : le service ne démarre plus (ou redémarre en boucle), journal du type « failed to load local private key / key values mismatch ». Le certificat présent ne correspond plus à la clé :

```
root@hv03:~# openssl x509 -noout -pubkey -in /etc/pve/nodes/hv03/pveproxy-ssl.pem | sha256sum
root@hv03:~# openssl pkey -pubout -in /etc/pve/nodes/hv03/pveproxy-ssl.key | sha256sum
```

Deux sommes différentes. `openssl x509 -noout -issuer -dates` montre un certificat autosigné tout neuf. Correctif selon le fichier touché : pour `pveproxy-ssl.pem` (certificat ACME de M09-E26), le redemander par le client ACME intégré (`pvenode acme cert order --force`) ; pour `pve-ssl.pem`, le régénérer avec la CA du cluster (`pvecm updatecerts --force`), puis `systemctl restart pveproxy`. Ne pas copier le certificat d'un autre nœud : il porte un autre nom et une autre clé.

**Variante 4 — `/etc/hosts` faux sur hv03.**

```
root@hv03:~# getent hosts hv03
10.10.10.63     hv03.par1.medisphere.internal hv03
root@hv01:~# python3 -c 'import json;print(json.load(open("/etc/pve/.members"))["nodelist"]["hv03"])'
{'id': 3, 'online': 1, 'ip': '10.10.10.63'}
```

pmxcfs de `hv03` publie l'adresse que **son** nom résout localement ; les autres nœuds s'en servent pour relayer les appels d'API (et pour les migrations sans réseau dédié) : 595 vers une adresse où personne n'écoute. Correctif : rétablir la ligne de `/etc/hosts` (adresse MGMT), `systemctl restart pve-cluster` sur `hv03`, vérifier `.members`. Prévention : le rôle `pve_noeud` gère `/etc/hosts` (gabarit avec l'adresse de `ansible_host`) et un passage en `--check --diff` l'aurait signalé.

**Vérification** : `lab/bin/check 09 36`, puis `--annuler`.

**Explications**

« Être dans le cluster » recouvre quatre appartenances distinctes : Corosync (membre et quorum), pmxcfs (`/etc/pve` partagé et `.members`), l'API (chaque nœud relaie vers les autres avec des tickets et des certificats de cluster) et les services au-dessus (Ceph a ses propres moniteurs et son propre contrôle d'horloge). L'interface ne montre qu'une synthèse ; le point d'interrogation d'un nœud signifie en général « je n'ai pas de données récentes de lui » (`pvestatd`), ce qui peut venir de n'importe lequel des quatre étages.

**Alternatives**
- Variante 1 : réadhésion complète (`pvecm delnode` + réinstallation, M09-E29) — interdite ici, et disproportionnée pour une clé.
- Variante 3 : retirer temporairement le certificat personnalisé (`pvenode cert delete`) pour revenir au `pve-ssl.pem` du cluster, le temps de redemander le certificat ACME.

**Pièges classiques**
- Retirer `hv03` du cluster pour « repartir propre » : on transforme un fichier faux en reconstruction d'un nœud et de ses OSD.
- Corriger l'heure avec `date -s` sans réactiver chrony : la dérive revient.
- Copier `/etc/pve/nodes/hv01/pve-ssl.*` vers `hv03` : mauvais nom, mauvaise clé, et un nœud qui usurpe l'identité d'un autre.
- Ne regarder que l'interface de `hv01` : elle ne dit pas lequel des quatre étages a décroché.

**En production chez MédiSphère**
`ms-verif-cluster` compare, pour chaque nœud : présence dans la membre, adresse de `.members` contre NetBox, écart d'horloge, expiration et cohérence clé/certificat de `pveproxy`. Le rôle `pve_noeud` gère `/etc/hosts`, chrony et le certificat ACME ; toute intervention de nuit passe par une fiche de changement, même pour un prestataire.

---

### M09-E37 — Panne : une VM HA reste en erreur

**Démarche de diagnostic**

*Symptôme* : `service vm:19x (hvNN, error)` dans `ha-manager status` ; un clic sur « Démarrer » ne fait rien (la HA ne pilote plus une ressource en erreur, et `qm start` est refusé pour une ressource gérée par la HA).

**Étape 1 — Chronologie.**

```
root@hv01:~# ha-manager status -v | grep -A3 'vm:19'
root@hv01:~# journalctl -u pve-ha-crm -u pve-ha-lrm --since -1h | grep -E 'vm:19|service'
… pve-ha-crm: service 'vm:191': state changed from 'request_start' to 'started' (node = hv01)
… pve-ha-lrm: starting service vm:191
… pve-ha-lrm: unable to start service vm:191 … (exit code 255)
… pve-ha-crm: service 'vm:191' - start failed, restarting (1/1)
… pve-ha-crm: service 'vm:191' - relocate to node 'hv02'
… pve-ha-crm: service 'vm:191': state changed from 'started' to 'relocate' …
… pve-ha-crm: service 'vm:191' - migration failed …
… pve-ha-crm: recovery policy for service vm:191 failed, entering error state …
root@hv01:~# pvenode task list --typefilter qmstart --vmid 191
root@hv01:~# pvenode task log <UPID>
```

Lecture : `max_restart: 1` (une nouvelle tentative sur place), puis `max_relocate: 1` (une tentative sur un autre nœud), puis `error`. Les libellés exacts du journal varient ; la suite des états et les compteurs sont ce qu'il faut retrouver.

**Variante 1 — configuration déplacée à la main, disque local resté ailleurs.**

```
root@hv01:~# pvenode task log <UPID-qmstart>
… no such logical volume pve/vm-191-disk-0
root@hv01:~# grep scsi0 /etc/pve/nodes/hv01/qemu-server/191.conf
scsi0: local-lvm:vm-191-disk-0,size=1G
root@hv02:~# lvs pve | grep vm-191
  vm-191-disk-0 pve Vwi-a-tz-- 1.00g data …
```

La configuration est sur `hv01`, le disque sur `local-lvm` de `hv02`. Démarrage impossible sur `hv01` (volume absent), relocalisation impossible (la migration cherche le disque local sur `hv01`). Un `mv` de fichier entre `/etc/pve/nodes/*/qemu-server/` « déplace » une VM sans ses données : c'est le geste de dernier recours documenté pour reprendre la configuration d'un nœud **mort** dont le stockage est **partagé**, pas un moyen de migrer.

Correctif :
```
root@hv01:~# ha-manager set vm:191 --state disabled
root@hv01:~# mv /etc/pve/nodes/hv01/qemu-server/191.conf /etc/pve/nodes/hv02/qemu-server/191.conf
root@hv02:~# ha-manager set vm:191 --state started
```
Durable : une VM sous HA doit avoir tous ses disques sur un stockage partagé (`ceph-vm`) ou répliqué (`zfs-local` + job de réplication) ; sinon la HA ne peut rien pour elle. `qm disk move 191 scsi0 ceph-vm --delete 1` ensuite.

**Variante 2 — règle d'affinité devenue impossible.**

```
root@hv01:~# ha-manager rules config
resource-affinity: separer-pan-ha
        affinity negative
        resources vm:191,vm:192,vm:193
root@hv01:~# ha-manager status | grep -E '^lrm|vm:19'
lrm hv01 (active, …)
lrm hv02 (active, …)
lrm hv03 (maintenance mode, …)
service vm:191 (hv01, started)
service vm:192 (hv02, started)
service vm:193 (hv03, error)
```

Trois ressources qui ne doivent **jamais** partager un nœud, trois nœuds, dont un en maintenance : il n'existe plus de placement valide pour la troisième. La documentation des règles d'affinité de ressources l'annonce : une règle stricte qu'on ne peut satisfaire met la ressource en `error` (ou en `recovery` lors d'une reprise après panne). La règle était juste… tant que trois nœuds étaient disponibles. Elle rend toute maintenance impossible.

Correctif : lever le blocage (fin de la maintenance si elle n'est plus nécessaire, ou réécriture de la règle), puis sortir la ressource de l'erreur :
```
root@hv01:~# ha-manager set vm:193 --state disabled
root@hv01:~# ha-manager rules set resource-affinity separer-pan-ha --resources vm:191,vm:192     # à adapter : voir ha-manager help rules
root@hv01:~# ha-manager set vm:193 --state started
```
Une règle durable pour « jamais deux frontaux sur le même nœud » avec trois frontaux et trois nœuds n'existe pas si l'on veut aussi pouvoir faire une maintenance : soit deux frontaux (règle négative à deux ressources), soit une affinité **non stricte** (préférence). RB-090 gagne une étape : « avant `node-maintenance enable`, vérifier que chaque règle reste satisfiable sans ce nœud ».

**Variante 3 — image RBD supprimée, max_restart puis max_relocate épuisés.**

```
root@hv01:~# pvenode task log <UPID-qmstart>
… rbd: error opening image vm-191-disk-1: (2) No such file or directory
root@hv01:~# rbd -p <pool> ls | grep vm-191
vm-191-disk-0
root@hv01:~# grep scsi1 /etc/pve/qemu-server/191.conf
scsi1: ceph-vm:vm-191-disk-1,size=1G
```

La configuration référence une image qui n'existe plus : le démarrage échoue sur **tous** les nœuds, la relocalisation n'y change rien. La HA a fait exactement ce qu'on lui demande : une nouvelle tentative, une relocalisation, puis abandon. Correctif : `ha-manager set vm:191 --state disabled`, retirer la référence morte (`qm set 191 --delete scsi1`) ou restaurer le disque depuis PBS si les données comptaient (ici, disque vide : on le retire et on le note), puis `--state started`. Durable : aucun « nettoyage d'images orphelines » sans comparaison avec les configurations de VM (`pvesm list ceph-vm` liste les volumes avec leur VMID ; une image est orpheline seulement si aucune configuration ne la référence).

**Vérification** : constater `started` dans `ha-manager status`, puis `lab/bin/break 09 37 --annuler` (détruit 191-193, lève une maintenance ou une règle posée par la panne) et `lab/bin/check 09 37`.

**Explications**

Le CRM applique une politique de reprise bornée : `max_restart` tentatives sur le même nœud, puis `max_relocate` déplacements, puis `error`. L'état `error` est une protection : sans lui, une ressource impossible à démarrer ferait tourner la HA en boucle, déplacerait la charge, et pourrait masquer d'autres pannes. Il exige une décision humaine, d'où la procédure de sortie : `disabled` (la HA arrête la ressource et ne la pilote plus), correction, `started`.

**Alternatives**
- Augmenter `max_restart`/`max_relocate` : utile pour une ressource qui échoue de façon transitoire (stockage lent au démarrage), inutile pour une cause permanente.
- `ha-manager set vm:191 --state ignored` le temps de corriger à la main : la HA lâche la ressource sans l'arrêter ; utile quand la VM tourne et qu'on ne veut pas l'interrompre.

**Pièges classiques**
- `ha-manager remove` puis `add` : on perd l'historique, on ne corrige rien, la ressource repart en erreur.
- Lever la maintenance sans comprendre (variante 2) : la règle reste une bombe pour la prochaine maintenance.
- `qm start` sur une ressource HA : refusé, ou démarrage hors du contrôle de la HA.

**En production chez MédiSphère**
Contrôle d'admission des règles HA dans la MR qui les ajoute (le test de « pour aller plus loin » : chaque ressource garde un nœud possible quand on retire n'importe quel nœud), alerte sur toute ressource en `error` (`pvesh get /cluster/ha/status/current`), et vérification « tous les disques des ressources HA sur stockage partagé ou répliqué » dans `ms-verif-cluster`.

---

### M09-E38 — Panne : la migration à chaud échoue

**Démarche de diagnostic**

```
root@hv01:~# qm migrate 194 hv02 --online
root@hv01:~# pvesh get /nodes/hv01/qemu/194/migrate --target hv02 --output-format json-pretty
root@hv01:~# grep -E '^(migration|bwlimit):' /etc/pve/datacenter.cfg
```

**Variante 1 — disque local.** Le contrôle préalable liste `local_disks` (`local-lvm:vm-194-disk-1`) ; la migration est refusée d'emblée (« can't live migrate attached local disks without with-local-disks option »). Deux corrections possibles, à ne pas confondre :
- **Corriger la VM** : `qm disk move 194 scsi1 ceph-vm --delete 1` (à chaud), puis migrer. C'est la bonne réponse pour une VM qui doit rester migrable (maintenance, HA).
- Migrer **avec** le disque : `qm migrate 194 hv02 --online --with-local-disks` (copie du disque par NBD pendant la migration). Possible pour une urgence, mais la VM reste non migrable après, et la copie d'un gros disque prend du temps et du débit.

**Variante 2 — ISO locale montée.** Le contrôle préalable signale le lecteur `ide2: local:iso/outils-infoger-2019.iso` comme ressource locale (l'ISO n'existe que sur `hv01`) ; la migration est refusée. Correctif : éjecter (`qm set 194 --ide2 none,media=cdrom`) puis migrer ; si l'ISO doit rester disponible, la déposer sur un stockage partagé (CephFS ou un stockage ISO commun) et la monter depuis là.

**Variante 3 — SSH filtré vers hv02.** Le contrôle préalable ne montre rien ; la tâche reste bloquée sur la connexion puis échoue :

```
… starting migration of VM 194 to node 'hv02' (10.10.30.72)
… ssh: connect to host 10.10.30.72 port 22: Connection timed out
… ERROR: migration aborted …
root@hv01:~# ssh -o BatchMode=yes -o ConnectTimeout=5 -o HostKeyAlias=hv02 root@10.10.30.72 true
ssh: connect to host 10.10.30.72 port 22: Connection timed out
admin@adm01:~$ ssh root@10.10.10.52 true        # fonctionne : le filtre vise les nœuds, pas adm01
root@hv02:~# nft list table inet infoger_durcissement
… ip saddr { 10.10.10.51, 10.10.10.53, 10.10.32.51, … } tcp dport 22 counter packets 12 … drop …
```

La migration *secure* ouvre une session SSH root vers l'adresse du nœud cible dans le réseau de migration (10.10.30.0/24 depuis M09-E27). Correctif : supprimer la table ; la règle venait d'un « durcissement » qui interdisait le SSH entre nœuds, alors que le cluster en dépend (migration, réplication, `pvecm`, console). Si l'on veut restreindre SSH, c'est dans le pare-feu de Proxmox VE, en autorisant explicitement les nœuds (macro `SSH` depuis l'IPSet du cluster), pas par une table parallèle.

**Variante 4 — limite de bande passante.**

```
… migration status: active (transferred 1.2 MiB of 260.0 MiB), remaining 258.8 MiB …
… migration status: active (transferred 1.2 MiB of 260.0 MiB), remaining 258.8 MiB …
root@hv01:~# grep bwlimit /etc/pve/datacenter.cfg
bwlimit: migration=1
```

Environ 1 Kio/s : la migration de 256 Mio de mémoire prendrait trois jours. L'unité de `bwlimit` est le **Kio/s** ; quelqu'un a voulu écrire « 1 Gio/s » ou « 1 Gbit/s ». Correctif : arrêter la migration en cours (bouton *Stop* de la tâche, puis `qm unlock 194` si le verrou `migrate` reste), corriger `bwlimit` (par exemple `migration=819200`, soit 800 Mio/s, ou retirer la clé), relancer. La limite peut aussi être passée par migration (`--bwlimit`) : elle est utile pour ne pas saturer le VLAN 30 partagé avec Ceph public (M09-E27), à condition de la chiffrer correctement.

**Étape finale** — la migration réussie affiche la durée totale et l'interruption, par exemple `migration finished successfully (duration 00:00:09)` et `average migration speed: 120.4 MiB/s - downtime 41 ms`. Vérifier les autres VMs : `for id in $(qm list | awk 'NR>1 {print $1}'); do pvesh get /nodes/$(hostname)/qemu/$id/migrate --output-format json | jq -c "{id: $id, disques: .local_disks, ressources: .local_resources}"; done` (sur chaque nœud).

**Explications**

Une migration à chaud transfère l'état de la mémoire (pré-copie itérative, puis courte pause pour la dernière passe), pas les disques s'ils sont partagés. Tout ce qui est attaché à un nœud (disque local, ISO locale, périphérique PCI ou USB) rend la VM non migrable sans copie ou détachement. Le canal (SSH, réseau de migration) et le débit (`bwlimit`, saturation) déterminent ensuite la durée et le risque de non-convergence pour une VM qui écrit beaucoup en mémoire.

**Alternatives** : `migration_type insecure` sur un réseau isolé (débit plus élevé, aucun chiffrement : acceptable seulement sur un VLAN dédié et non routé, ce que n'est pas le VLAN 30 qui sert aussi Ceph public).

**Pièges classiques** : `--force` (n'existe que pour les ressources locales déclarées sans risque, ne règle pas un disque local) ; migrer hors ligne « pour aller vite » (interruption de service) ; oublier le verrou `migrate` après une migration interrompue.

**En production chez MédiSphère** : `ms-verif-cluster` liste chaque soir les VMs non migrables (contrôle préalable de l'API) ; RB-090 (maintenance) commence par cette liste ; `bwlimit` est posé par le rôle `pve_cluster`, avec un commentaire de l'unité.

---

### M09-E39 — Panne : les VMs se figent

**Démarche de diagnostic**

```
root@hv01:~# ceph -s
root@hv01:~# ceph health detail
root@hv01:~# ceph osd tree
root@hv01:~# ceph pg stat
root@hv01:~# ceph osd pool get <pool> all | grep -E '^(size|min_size)'
root@hv01:~# ceph osd dump | grep -E '^flags'
```

**Variante 1 — OSD arrêtés et désactivés sur hv02 et hv03.**

```
root@hv01:~# ceph health detail
HEALTH_WARN 4 osds down; 2 hosts (4 osds) down; Reduced data availability: 129 pgs inactive; Degraded data redundancy: …
[WRN] PG_AVAILABILITY: Reduced data availability: 129 pgs inactive
    pg 2.0 is stuck inactive for 5m, current state undersized+degraded+peered, last acting [1]
…
root@hv02:~# systemctl is-enabled ceph-osd@2 ceph-osd@3
disabled
disabled
```

Une seule copie de chaque PG (celle de `hv01`) : `peered` sans `active`, car il faut `min_size` = 2 copies pour accepter une écriture. Les lectures des données déjà en cache passent, les écritures attendent : les invités voient des E/S qui ne reviennent jamais (`blocked for more than 120 seconds`). Rien n'est perdu. Cause : quatre OSD arrêtés **et désactivés** (ils ne seraient pas revenus au redémarrage). Correctif : `systemctl enable --now ceph-osd@<id>` sur `hv02` et `hv03` (identifiants par `ceph osd ls-tree hv02`), puis suivre le *peering* et la récupération (`ceph -s`, `ceph -w`). Les VMs reprennent **seules** dès que leurs PG redeviennent `active` : aucun redémarrage d'invité n'est nécessaire.

**Variante 2 — trou noir MTU sur le réseau cluster de hv03.**

```
root@hv01:~# ceph health detail
HEALTH_WARN 2 osds down; … slow ops …
root@hv03:~# journalctl -u ceph-osd@4 --since -30min | grep -i 'wrongly'
… map e212 wrongly marked me down at e211
root@hv01:~# ping -M do -s 1472 -c 2 10.10.31.73      # passe
root@hv01:~# ping -M do -s 8972 -c 2 10.10.31.73      # 100 % de pertes
root@hv01:~# ping -M do -s 8972 -c 2 10.10.30.73      # passe (réseau public)
```

Les petits paquets passent, les gros disparaissent sans message d'erreur : c'est la signature d'un trou noir de MTU. Les OSD remplissent leurs battements de cœur jusqu'à `osd_heartbeat_min_size` (2000 octets par défaut) précisément pour détecter ce cas : sur le réseau cluster, ceux de `hv03` se perdent, ses OSD sont déclarés morts par les autres, se défendent (`wrongly marked me down`), reviennent, repartent : les PG font du *peering* en boucle et les écritures se figent par intermittence. Recherche du « qui » : l'interface et la MTU de `hv03` (`ip -d link`) sont justes, `pve01` et `vmbr1` ne sont pas en cause (les autres nœuds passent en 9000 entre eux), reste le filtrage local : `nft list ruleset` sur `hv03` montre la table `infoger_durcissement` (`meta length > 1500 drop` sur 10.10.31.0/24). Correctif : supprimer la table ; les OSD se stabilisent. Dans un vrai centre de données, la même signature pointe vers un commutateur ou un lien dont la MTU a été réduite : la méthode (`ping -M do` aux deux tailles, sur chaque paire d'hôtes et chaque réseau) est la même.

**Variante 3 — `min_size 3` et une maintenance.**

```
root@hv01:~# ceph osd dump | grep -E '^flags|pool'
flags noout,sortbitwise,recovery_deletes,purged_snapdirs,pglog_hardlimit
pool 2 '<pool>' replicated size 3 min_size 3 crush_rule 0 …
root@hv01:~# ceph osd tree | grep -A3 hv03
-7  0.09369  host hv03
 4  0.04689      osd.4  down  1.00000 …
 5  0.04689      osd.5  down  1.00000 …
```

`noout` et les OSD de `hv03` arrêtés : c'est une maintenance normale (RB-090), qui ne devrait rien figer avec `min_size 2` (deux copies sur trois restent, les écritures continuent en mode dégradé). Mais `min_size` a été relevé à 3 : deux copies ne suffisent plus, tous les PG passent `inactive`. Cause : un « durcissement » de `min_size` mal compris (il ne protège pas mieux les données, il réduit la disponibilité). Correctif : `ceph osd pool set <pool> min_size 2` (le service revient immédiatement), puis terminer la maintenance (redémarrer les OSD de `hv03`, `ceph osd unset noout`).

**Vérification** : `ceph -s` jusqu'à `HEALTH_OK` ; une écriture d'essai (`rados bench -p <pool> 5 write --no-cleanup` puis `rados -p <pool> cleanup`, ou `dd` dans une VM de test) ; `lab/bin/check 09 39` après `--annuler`.

**Explications**

Ceph préfère bloquer que mentir : une écriture n'est acquittée que lorsque `min_size` copies au moins l'ont reçue. Sous ce seuil, le PG reste `peered` (il connaît ses données) mais pas `active` (il refuse les écritures), et les clients RBD (QEMU) attendent indéfiniment. C'est pour cela que les invités se figent sans planter, et qu'ils reprennent seuls. Avec trois nœuds et un domaine de panne « hôte », la seule configuration qui supporte la perte d'un nœud sans gel est `3/2` ; `min_size 1` accepterait des écritures sur une seule copie (risque de perte de données si ce dernier disque meurt avant la récupération) et est explicitement déconseillé.

**Alternatives** : variante 1 : si un OSD ne redémarre pas (disque mort), on ne touche pas à `min_size` : on répare ou on remplace l'OSD (M08). Variante 2 : à court terme, on aurait pu baisser la MTU de toutes les interfaces du réseau cluster à 1500 ; c'est un contournement qui coûte en débit et laisse la cause en place.

**Pièges classiques**
- Redémarrer les VMs figées : elles se figent de nouveau au démarrage, et l'on risque de corrompre leur système de fichiers.
- `ceph osd out` des OSD arrêtés : déclenche une récupération massive vers des hôtes qui n'ont pas la place (domaine de panne « hôte » : impossible de toute façon), sans rendre le service.
- `min_size 1` « le temps de réparer ».
- Oublier `noout` à la fin d'une maintenance (variante 3) : la prochaine panne d'OSD ne déclenchera aucune récupération automatique.

**En production chez MédiSphère**
RB-094 ([`fichiers/M09-E39/medisphere/docs/virtualisation/runbooks/RB-094-ceph-pg-inactifs.md`](fichiers/M09-E39/medisphere/docs/virtualisation/runbooks/RB-094-ceph-pg-inactifs.md)). `ms-verif-cluster` alerte sur `PG_AVAILABILITY`, sur un drapeau `noout` posé depuis plus de 4 h, sur toute valeur de `min_size` différente de 2 pour un pool 3 répliques, et teste chaque nuit `ping -M do -s 8972` entre chaque paire d'hôtes sur les réseaux public et cluster.

---

### M09-E40 — Panne : la réplication est en échec

**Démarche de diagnostic**

```
root@hv01:~# pvesr status
JobID      Enabled    Target           LastSync             NextSync   Duration  FailCount State
196-0      Yes        local/hv02       2026-10-20_06:15:02  pending    3.1       2         <message d'erreur>
root@hv01:~# cat /var/log/pve/replicate/196-0
root@hv01:~# zfs list -t snapshot -o name,creation -s creation | grep vm-196
root@hv02:~# zfs list -t snapshot -o name,creation -s creation | grep vm-196
root@hv02:~# zpool list; zfs list -o space -r tank
```

**Variante 1 — pool cible presque plein.** Le journal du job se termine par `cannot receive incremental stream: out of space`. Sur `hv02`, `zfs list -o space` montre un jeu de données `tank/export-infoger` avec une `refreservation` qui prend presque tout le pool. `zpool history tank | tail` date sa création. Correctif : décider avec son propriétaire (ici, un dépôt sans propriétaire ni ticket : on le supprime après avoir vérifié qu'il est vide, `zfs get used,referenced`) ou réduire sa réservation ; relancer `pvesr schedule-now 196-0`. L'incrémental reprend où il en était : les deux instantanés de base existent toujours.

**Variante 2 — instantané de base détruit sur la cible.**

```
root@hv01:~# zfs list -t snapshot -o name | grep vm-196
tank/vm-196-disk-0@__replicate_196-0_1760940902__
root@hv02:~# zfs list -t snapshot -o name | grep vm-196
(rien)
```

La source garde son dernier instantané de réplication, la cible ne l'a plus : l'envoi incrémental n'a pas de base commune (`zfs receive` refuse). Il n'y a pas de réparation « sans repartir de zéro » : la seule base commune a disparu. Correctif : sur `hv02`, après avoir vérifié que la VM 196 tourne bien sur `hv01` (le volume de `hv02` n'est qu'une copie), supprimer la copie (`zfs destroy -r tank/vm-196-disk-0` sur `hv02`), puis relancer le job : `pvesr` refait un envoi complet (1 Gio ici, quelques secondes ; pour un disque de 500 Gio, des heures de VLAN 30 : à planifier). Cause : un nettoyage d'instantanés qui ne savait pas que `__replicate_*__` appartiennent à `pvesr`. Prévention : aucun script de rétention ZFS sur les volumes gérés par Proxmox VE, ou exclusion explicite de ce motif.

**Variante 3 — clés du cluster absentes de authorized_keys sur hv02.**

```
root@hv01:~# ssh -o BatchMode=yes -o HostKeyAlias=hv02 root@10.10.10.52 true
root@10.10.10.52: Permission denied (publickey).
root@hv02:~# ls -l /root/.ssh/authorized_keys
-rw------- 1 root root 742 oct. 20 05:58 /root/.ssh/authorized_keys
root@hv02:~# head -n 1 /root/.ssh/authorized_keys
# Fichier géré par Ansible (durcissement InfoGér) — ne pas modifier
root@hv02:~# grep -c 'root@hv0' /etc/pve/priv/authorized_keys
3
```

Les nœuds se connectent entre eux avec les clés rassemblées dans `/etc/pve/priv/authorized_keys` (partagé par pmxcfs). Le fichier de `hv02` a été remplacé par une liste qui ne contient plus que la clé de `adm01`. Correctif : rétablir le lien ou le contenu attendu par Proxmox VE (`pvecm updatecerts` sur `hv02` remet en place les clés et le lien, à confirmer sur ta version), puis tester la connexion depuis `hv01` et `hv03`. La même panne casse aussi la migration et la console des VMs de `hv02` depuis un autre nœud : vérifier les autres jobs (`pvesr status` sur chaque nœud) et les migrations vers `hv02`. Prévention : si un rôle Ansible gère les clés SSH de root, il **ajoute** des clés (`ansible.posix.authorized_key`) et ne remplace jamais le fichier.

**Vérification** : `pvesr status` à `OK` et `FailCount 0` ; `lab/bin/check 09 40` après `--annuler`.

**Explications**

`pvesr` crée un instantané `__replicate_<job>_<horodatage>__`, envoie la différence depuis le précédent par `zfs send -i | ssh … zfs receive`, puis supprime l'ancien instantané des deux côtés. Il lui faut : SSH root vers la cible, l'instantané précédent intact des deux côtés, de la place sur la cible. Le RPO est l'intervalle du job **si** chaque synchronisation réussit ; un compteur d'échecs qui monte, c'est un RPO qui s'allonge sans bruit.

**Alternatives** : variante 2 : sur ZFS, les *bookmarks* permettent un incrémental sans conserver l'instantané côté source, pas côté cible : ils ne sauvent pas ce cas.

**Pièges classiques** : supprimer le job et le recréer (même résultat qu'un envoi complet, l'historique en moins) ; supprimer le volume de la **source** par erreur ; ignorer les autres jobs touchés par la même cause (variante 3).

**En production chez MédiSphère** : alerte de `ms-verif-cluster` quand `last_sync` d'un job dépasse deux intervalles ou quand `fail_count > 0` ; seuil d'occupation des pools `tank` à 80 % ; aucun script de rétention sur `tank` hors `pvesr`.

---

### M09-E41 — Panne : la sauvegarde nocturne a échoué

**Démarche de diagnostic**

```
root@hv01:~# vzdump <VMID> --storage pbs-par2 --mode snapshot
root@hv01:~# pvesm status --storage pbs-par2
root@hv01:~# pvesm list pbs-par2 | head
root@hv01:~# awk '/^pbs: pbs-par2/,/^$/' /etc/pve/storage.cfg
root@hv01:~# ls -l --time-style=full-iso /etc/pve/storage.cfg /etc/pve/priv/storage/
```

**Variante 1 — empreinte erronée.** `pvesm status` : `pbs-par2` inactif ; message du type `error fetching datastores - fingerprint '…' not verified, abort!`. Mesure côté client, sans droit sur le serveur :

```
root@hv01:~# openssl s_client -connect 10.20.10.10:8007 </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256
sha256 Fingerprint=AB:12:…
```

L'empreinte de `storage.cfg` ne correspond à aucun certificat présenté par `pbs01`. Le serveur n'a pas changé (les sauvegardes de `pve01`, qui ont la bonne empreinte, passent). Correctif : `pvesm set pbs-par2 --fingerprint <empreinte lue, comparée à celle du registre>` ; ou, si le certificat de `pbs01` est émis par la PKI MédiSphère (M06), retirer l'empreinte (`pvesm set pbs-par2 --delete fingerprint`) pour vérifier par la chaîne de confiance. Ne jamais accepter une empreinte lue sur le réseau sans la comparer à une source sûre (registre, console de `pbs01`) : c'est exactement le cas qu'elle protège.

**Variante 2 — secret du jeton remplacé.** `pvesm status` : inactif, `401 Unauthorized` / `authentication failed`. L'identifiant du jeton (`username wb-hv@pbs!<nom>` dans `storage.cfg`) est juste ; le secret de `/etc/pve/priv/storage/pbs-par2.pw` ne l'est plus (date de modification récente). Le serveur fait foi : on ne peut pas « relire » un secret de jeton PBS, seulement le régénérer. Correctif sans toucher à `pbs01` : reprendre le secret dans Ansible Vault `critique` (où M09-E15 l'a rangé) et le réécrire sans le faire passer en argument :
repasser le playbook qui a posé le stockage en M09-E15 (rôle `pve_cluster`, limité à un nœud : le fichier est dans `/etc/pve`, donc commun), d'abord en `--check --diff` ; ou, à la main, `install -m 600 /dev/stdin /etc/pve/priv/storage/pbs-par2.pw` avec le secret collé sur l'entrée standard, jamais `echo secret >`). Si le secret n'est nulle part, il faut régénérer le jeton sur `pbs01` : c'est une modification de `pbs01`, donc une fiche de changement (interdit dans ce ticket).

**Variante 3 — namespace renommé.** `pvesm status` est **actif** (connexion, TLS et jeton sont bons), mais `pvesm list pbs-par2` est vide et la sauvegarde échoue avec un message de namespace inexistant. `storage.cfg` : `namespace par1/hyperviseurs` au lieu de `par1/hv`. Correctif : `pvesm set pbs-par2 --namespace par1/hv` ; les sauvegardes réapparaissent. Prévention : un namespace se change par une fiche de changement (renommer côté client, c'est « perdre » l'historique visible et casser la rétention).

**Vérification** : sauvegarde manuelle réussie, puis restauration d'un fichier (*File Restore* dans l'interface, ou `proxmox-file-restore`), `lab/bin/check 09 41`.

**Explications**

Le client PBS de Proxmox VE enchaîne : TCP 8007 → TLS (empreinte épinglée ou chaîne de confiance) → authentification par jeton → datastore → namespace → droits du jeton (rôle `DatastoreBackup` sur `/datastore/ds-lab/par1/hv`). `pvesm status` teste les trois premiers étages, `pvesm list` et la sauvegarde testent les suivants. Cette lecture par étages permet de répondre à Sophie sans toucher au serveur.

**Pièges classiques** : `curl -k` ou une empreinte copiée sans comparaison ; mettre le secret en argument (`pvesm set --password …` le ferait apparaître dans l'historique et `ps`) ; « corriger » sur `pbs01` un problème de client.

**En production chez MédiSphère** : `ms-verif-sauvegardes` contrôle chaque matin la dernière sauvegarde de chaque VM du cluster ; `storage.cfg` du cluster est géré par le rôle `pve_cluster` (le passage quotidien en `--check` aurait signalé les trois variantes) ; note d'écart au registre pour la nuit perdue.

---

### M09-E42 — Panne : impossible de modifier une VM

**Démarche de diagnostic**

```
admin@adm01:~$ for n in 51 52 53; do ssh root@10.10.10.$n 'hostname; ip -br a | grep -c 10.10.10.200'; done
root@<cible>:~# qm set <vmid> --description essai
root@<cible>:~# corosync-quorumtool -s | grep Quorate
root@<cible>:~# systemctl status pve-cluster --no-pager
root@<cible>:~# findmnt /etc/pve
root@<cible>:~# df -h /
root@<cible>:~# journalctl -u pve-cluster -n 50 --no-pager
```

**Variante 1 — un nœud sans quorum, utilisé en direct.**

```
root@hv03:~# qm set 105 --description essai
unable to open file '/etc/pve/nodes/hv03/qemu-server/105.conf.tmp.4242' - Permission denied
root@hv03:~# corosync-quorumtool -s | grep -E 'Quorate|Total'
Quorate:          No
Total votes:      1
root@hv01:~# corosync-quorumtool -s | grep -E 'Quorate|Total'
Quorate:          Yes
Total votes:      2
```

`hv03` est seul, sans quorum : `/etc/pve` y est en lecture seule. `hv01` et `hv02` forment la partition majoritaire et fonctionnent : Karim ne voit rien. L'interface servie par `hv03` affiche encore les VMs (la lecture marche sans quorum), d'où l'impression que « tout va bien ». Cause : table nftables `infoger_durcissement` sur `hv03` (comme M09-E35 v1, mais sur un seul nœud). Correctif : supprimer la table, le quorum revient. Si ce nœud avait porté la VIP, le script de santé de M09-E18 (`corosync-quorumtool -s`) l'aurait retirée en quelques secondes : c'est précisément pour cela que la panne a été posée sur un nœud que Julien utilisait **en direct**. Leçon : les utilisateurs et les outils passent par la VIP, jamais par l'adresse d'un nœud.

**Variante 2 — disque système plein.**

(Exemples avec `hv03` portant la VIP ; la cible des variantes 2 et 3 est le nœud de la VIP.)

```
root@hv03:~# df -h /
/dev/mapper/pve-root  7,8G  7,8G     0 100% /
root@hv03:~# journalctl -u pve-cluster -n 5
… pmxcfs[1012]: [database] crit: commit transaction failed: database or disk is full
root@hv03:~# du -xh --max-depth=2 / 2>/dev/null | sort -h | tail -n 5
… 6,1G /var/tmp
root@hv03:~# ls -lh /var/tmp
-rw-r--r-- 1 root root 6,1G … export-infoger.tar
```

pmxcfs écrit chaque modification dans `config.db` **avant** de la diffuser ; disque plein, la transaction échoue et l'écriture dans `/etc/pve` est refusée, quorum ou pas. Le moniteur Ceph du nœud s'arrête aussi au-dessous de `mon_data_avail_crit` (5 % libres) : `ceph -s` montre un MON absent. Correctif : identifier le fichier, vérifier qu'il n'est pas utile (pas de propriétaire, pas de ticket : ici un export oublié), le déplacer ou le supprimer ; puis `systemctl restart pve-cluster` si les écritures restent refusées, et relancer le MON (`systemctl reset-failed ceph-mon@hv03 && systemctl start ceph-mon@hv03`). Prévention : alerte d'occupation du `/` des nœuds à 80 % ; rien n'est déposé sur un nœud hors des stockages prévus.

**Variante 3 — pve-cluster arrêté (et point de montage pollué).**

```
root@hv03:~# systemctl status pve-cluster
○ pve-cluster.service - The Proxmox VE cluster filesystem
     Active: inactive (dead) …
root@hv03:~# ls /etc/pve
100.conf.sauvegarde
root@hv03:~# systemctl start pve-cluster; journalctl -u pve-cluster -n 5
```

`/etc/pve` n'est plus monté : le dossier sous-jacent apparaît, avec un fichier écrit pendant que pmxcfs était arrêté. Selon la version de FUSE, pmxcfs refuse de monter sur un dossier non vide (le message cite le point de montage) ou monte par-dessus, en cachant le fichier jusqu'au prochain arrêt. Correctif : arrêter ce qui écrivait dans `/etc/pve` démonté, déplacer le fichier parasite hors du dossier (`mv /etc/pve/100.conf.sauvegarde /root/`, puis l'examiner : il ne doit **pas** être réinjecté), `systemctl start pve-cluster`, vérifier `findmnt /etc/pve` et `ls /etc/pve/nodes`. Si pmxcfs a démarré par-dessus, le fichier caché se retrouve par un montage lié de `/` (`mount --bind / /mnt && ls /mnt/etc/pve`).

**Vérification** : modification de description par la VIP, `cat /etc/pve/.version` identique sur les trois nœuds ; `lab/bin/check 09 42` après `--annuler`.

**Explications**

`/etc/pve` n'est inscriptible que si **trois** conditions sont réunies : pmxcfs tourne et a monté son système de fichiers, le nœud est dans une partition quorate, et pmxcfs peut écrire sa base locale. Chaque variante en retire une. Pour les variantes 2 et 3, la VIP est restée sur le nœud malade : le script de santé de M09-E18 teste le quorum et la réponse de l'API (401 sans jeton), et les deux restent bons quand le disque est plein ou que pmxcfs est arrêté (`pveproxy` répond toujours). Un point d'accès redondant doit suivre l'état **dont dépendent les utilisateurs** : ici, la capacité d'écrire dans `/etc/pve`. Version améliorée du script, qui ajoute ces contrôles sans écrire dans `/etc/pve` : [`fichiers/M09-E42/ansible/roles/pve_cluster/templates/pve-cluster-sante.sh.j2`](fichiers/M09-E42/ansible/roles/pve_cluster/templates/pve-cluster-sante.sh.j2) (remplace le gabarit de M09-E18, mêmes variables ; à tester en Molecule avant la MR).

**Pièges classiques** : `pvecm expected 1` sur le nœud isolé de la variante 1 (deux partitions inscriptibles, *split-brain* de configuration) ; `pmxcfs -l` (mode local) sur un nœud d'un cluster vivant ; supprimer `config.db` « corrompu ».

**En production chez MédiSphère** : script de santé de la VIP étendu à pmxcfs ; accès aux nœuds en direct réservé à l'administration (les outils et les utilisateurs passent par la VIP) ; alerte disque à 80 % ; `ms-verif-cluster` vérifie le montage de `/etc/pve` et l'égalité de `.version` entre nœuds.

---

### M09-E43 — Astreinte : le cluster en détresse

**Démarche**

1. **Triage (15 min)**, dans l'ordre des dépendances : vue par nœud du quorum (M09-E35), `findmnt /etc/pve` et `df -h /` (M09-E42), `ceph -s` (M09-E39), `ha-manager status` (M09-E37), `pvesr status` (M09-E40), `pvesm status` (M09-E41), `pvecm status` et `.members` (M09-E36), contrôle préalable de migration de la VM 194 si elle existe (M09-E38). Les checks `lab/bin/check 09 35` à `09 42` font le même tour en deux minutes.
2. **Ordre de traitement** : ce qui touche la membre et le quorum d'abord (sans quorum, rien d'autre ne se corrige : ni HA, ni stockage, ni réplication), puis Ceph (les VMs figées sont l'impact utilisateur le plus fort), puis `/etc/pve`, puis HA, réplication, sauvegarde, migration. Exemple : E39 v1 + E40 v3 → Ceph d'abord (VMs figées), puis les clés SSH (la réplication peut attendre 30 minutes, son RPO se dégrade mais rien n'est perdu).
3. **Pièges des combinaisons** : une réplication qui échoue pendant une perte de quorum n'est pas forcément une panne de réplication ; une ressource HA en erreur pendant que Ceph est bloqué peut être une conséquence (démarrage impossible faute d'E/S) ; une migration qui échoue vers un nœud sans quorum aussi. Après chaque correction, relance les checks pour voir ce qui reste rouge.
4. **Communication** : premier message dans les 15 minutes (`[07:10] INC-3650 — Impact : VMs de recette figées sur ceph-vm, réplication pan-rep en échec. Hypothèse 1 : OSD de hv02/hv03 arrêtés (PG inactifs). Prochaine action : relance des OSD, ETA 07:30.`), puis toutes les 30 minutes : fait, constaté, prochaine action.
5. **Post-mortem** : exemple complet pour la paire E39 v1 + E40 v3 dans [`fichiers/M09-E43/medisphere/docs/virtualisation/post-mortems/2026-10-20-INC-3650.md`](fichiers/M09-E43/medisphere/docs/virtualisation/post-mortems/2026-10-20-INC-3650.md). Les causes racines y sont des **processus** (« consignes d'InfoGér appliquées sans revue », « durcissement hors du code ») et pas des personnes.

**Pièges classiques** : corriger la première panne trouvée et déclarer l'incident clos (la seconde attend) ; redémarrer un nœud pour « tout remettre d'aplomb » (clôture, perte des preuves) ; oublier `--annuler` à la fin (la HA reste désarmée si l'injection l'avait désarmée).

---

### M09-E44 — Sous le capot : pmxcfs, votequorum et le gestionnaire HA

**Solution** (extraits représentatifs ; le compte rendu de l'apprenant contient ses propres sorties)

1. **pmxcfs.**
   ```
   root@hv01:~# findmnt /etc/pve
   TARGET   SOURCE    FSTYPE OPTIONS
   /etc/pve /dev/fuse fuse   rw,nosuid,nodev,relatime,user_id=0,group_id=0,default_permissions,allow_other
   root@hv01:~# sqlite3 'file:/var/lib/pve-cluster/config.db?mode=ro' '.schema tree'
   CREATE TABLE tree (inode INTEGER PRIMARY KEY NOT NULL, parent INTEGER NOT NULL CHECK(typeof(parent)=='integer'), version INTEGER NOT NULL CHECK(typeof(version)=='integer'), writer INTEGER NOT NULL CHECK(typeof(writer)=='integer'), mtime INTEGER NOT NULL CHECK(typeof(mtime)=='integer'), type INTEGER NOT NULL CHECK (type in (4, 8)), name TEXT NOT NULL, data BLOB);
   root@hv01:~# cat /etc/pve/.version
   ```
   Trois modifications de la description de la VM 198 depuis `hv02` augmentent `.version` du même nombre sur les trois nœuds, et la ligne de `198.conf` dans `tree` a la nouvelle `version` et le `writer` de `hv02` (identifiant de nœud). `chmod 777` échoue (`Operation not permitted`) : pmxcfs impose `root:www-data` et des droits fixes (0640, 0600 pour `priv`). `.members`, `.vmlist`, `.clusterlog` et `.rrd` ne sont pas dans la base : ce sont des fichiers **virtuels** calculés par pmxcfs.
2. **Corosync et votequorum.**
   ```
   root@hv01:~# corosync-cmapctl | grep -E '^(totem\.(token|token_coefficient|cluster_name|link_mode)|runtime\.config\.totem\.token |quorum\.)'
   quorum.provider (str) = corosync_votequorum
   runtime.config.totem.token (u32) = 3650
   totem.cluster_name (str) = hv-par1
   totem.link_mode (str) = passive
   root@hv01:~# corosync-cmapctl | grep -E 'runtime\.votequorum\.(this_node_id|ev_barrier|lowest_node_id|highest_node_id)'
   ```
   `runtime.config.totem.token` = 3000 + (3 − 2) × 650 = 3650 ms (valeurs par défaut de `token` et `token_coefficient`). `nodelist.node.N.quorum_votes` = 1 partout.
3. **Calcul des délais** (valeurs par défaut, à confirmer dans ta configuration) : perte du *token* après ≈ 3,65 s, puis consensus (≈ 1,2 × token) et nouvelle membre en quelques secondes ; le nœud isolé n'a plus de quorum ; si son LRM est actif, il ne nourrit plus le watchdog, qui le réinitialise au bout de 60 s ; le CRM maître (dans la partition majoritaire) attend que le verrou de l'agent HA du nœud perdu expire (de l'ordre de 120 s depuis sa dernière mise à jour) avant de considérer la clôture acquise et de relancer les ressources ailleurs. Ordre de grandeur total : deux à trois minutes, cohérent avec la mesure de M09-E24.
4. **Gestionnaire HA.** `manager_status` contient `master_node`, `node_status` (`online`, `maintenance`, `fence`, `unknown`…), `service_status` (par ressource : `state`, `node`, `uid`, et `target` pendant une migration) et un horodatage. Pendant `crm-command migrate vm:198 hv03`, la suite observée est `started` → `migrate` (avec `target: hv03`) → `started` sur `hv03`. `lrm_status` de chaque nœud donne `mode` (`active`, `maintenance`…), `state` (`wait_for_agent_lock`, `active`, `lost_agent_lock`) et les résultats des dernières commandes.
5. **Watchdog.** `watchdog-mux` ouvre `/dev/watchdog` (ici le pilote `softdog`, chargé faute de watchdog matériel déclaré dans `/etc/default/pve-ha-manager`) et expose `/run/watchdog-mux.sock` ; le CRM et le LRM actifs s'y connectent et le « nourrissent » tant qu'ils ont le quorum et leur verrou. S'ils cessent (perte du quorum, processus bloqué), `watchdog-mux` cesse de nourrir le watchdog, qui réinitialise la machine. Un `softdog` dépend du noyau qu'il doit surveiller : si le noyau est figé, il ne se déclenche pas toujours. Dans une VM imbriquée, c'est acceptable pour apprendre ; en production on utilise le watchdog matériel du serveur (iTCO, IPMI) déclaré dans `/etc/default/pve-ha-manager`.

**Réponses aux questions d'analyse**
1. pmxcfs garde toute la configuration **en mémoire** sur chaque nœud et la réplique par Corosync : sa taille est bornée (la documentation cite 128 Mio pour l'ensemble et des limites par fichier). On n'y range ni images, ni sauvegardes, ni journaux, ni gros scripts.
2. Toute écriture passe par une diffusion ordonnée (CPG de Corosync, ordre total) et n'est possible qu'avec le quorum : deux écritures concurrentes sont sérialisées dans le même ordre sur tous les nœuds. Une partition minoritaire ne peut pas écrire ; à son retour, elle se resynchronise sur la majorité (elle n'a pas de modifications à apporter, sauf si quelqu'un a forcé le quorum avec `pvecm expected`, d'où le danger).
3. `config_version` dit à pmxcfs et à Corosync quelle version est la plus récente ; un fichier dont la version n'augmente pas n'est pas propagé ni rechargé. La copie `.new` puis le renommage évitent qu'un nœud lise un fichier à moitié écrit (un éditeur qui sauvegarde en plusieurs écritures déclencherait plusieurs propagations).
4. `expected_votes` (configuration) remplace le total calculé ; `pvecm expected` change la valeur **en mémoire** jusqu'au prochain redémarrage ou rechargement ; `Total votes` est la somme des votes des nœuds présents. `pvecm expected 1` sur un nœud isolé lui donne le quorum à lui seul : si l'autre partition (deux nœuds) a aussi le quorum, deux partitions écrivent dans `/etc/pve` et peuvent démarrer les mêmes VMs.
5. En mode `passive`, knet utilise le lien de plus haute priorité disponible ; si le lien 0 tombe, le trafic passe par le lien 1 sans changement de membre ; `corosync-cfgtool -s` montre le lien 0 « disconnected » et `corosync-cfgtool -n` l'état par nœud.
6. Un maître unique évite deux décisions contradictoires (démarrer la même ressource sur deux nœuds) ; il est élu par un verrou dans pmxcfs. Un LRM qui perd le contact avec le CRM continue d'exécuter ses ressources tant qu'il a le quorum et son verrou ; sans quorum, il cesse de nourrir le watchdog et le nœud se clôture.
7. Voir l'étape 3. Le CRM attend l'expiration du verrou de l'agent du nœud perdu parce que c'est la **preuve** que ce nœud ne peut plus écrire ni faire tourner les ressources (son watchdog l'a réinitialisé) : relancer avant serait risquer deux instances de la même VM sur le même disque.
8. Exemples : `corosync-cmapctl -g quorum.expected_votes` localise M09-E35 v2 ; `.members` localise M09-E36 v4 ; `manager_status` (`node_status: maintenance` + règle) localise M09-E37 v2 ; `journalctl -u pve-cluster` (base pleine) localise M09-E42 v2.

**Pièges classiques** : copier `config.db` sur `adm01` « pour l'étudier » (elle contient `/etc/pve/priv`, donc les secrets de stockage et les clés) ; activer `debug: on` dans `corosync.conf` et l'oublier (journaux énormes) ; ouvrir la base en écriture.

---

### M09-E45 — Questions expert : cluster Proxmox

1. La **membre** est l'ensemble des nœuds qui se voient (Corosync) ; le **quorum** est la décision de votequorum que cette membre détient la majorité des votes. Membre sans quorum : un nœud isolé (il est membre de sa propre membre à un nœud) ; trois nœuds qui se voient avec `expected_votes: 7` (M09-E35 v2). Quorum sans membre complète : deux nœuds sur trois, quorate, le troisième absent.
2. **b**. Avec quatre votes, le quorum est 3 : aucune moitié n'a 3 votes. (a) décrit `auto_tie_breaker`, non actif par défaut et incompatible avec un QDevice ; (c) serait un *split-brain* ; (d) le CRM n'intervient pas dans le calcul du quorum.
3. Avec un nombre pair, une coupure en deux moitiés égales laisse tout le monde sans quorum : le QDevice apporte le vote qui départage (`ffsplit` donne son vote à la moitié qui contient le plus de nœuds, ou selon une règle de départage en cas d'égalité). Avec un nombre impair, le QDevice ajoute un vote… qui peut faire tomber le cluster si le QDevice et un nœud tombent ensemble, et la documentation de Proxmox VE déconseille `ffsplit` sur un nombre impair de nœuds (il faudrait l'algorithme `lms`, qui a d'autres risques) : d'où son retrait en M09-E08.
4. `passive` : un seul lien actif à la fois, les autres en secours (plutôt que `active`, qui répartit). Corosync est très sensible à la **latence** : un lien saturé par une migration ou une récupération Ceph retarde les messages, le *token* expire, la membre est recalculée, des nœuds peuvent perdre le quorum et se clôturer alors que rien n'est en panne. Expiration du *token* : retransmissions, puis déclaration de perte, consensus, nouvelle membre.
5. **b**. La lecture de `/etc/pve` fonctionne sans quorum (pmxcfs sert sa copie locale). (a), (c) et (d) exigent une écriture dans `/etc/pve` (verrou de VM, configuration, jeton dans `user.cfg`/`priv`).
6. Les clés privées du cluster (`authkey.key` des tickets, CA du cluster), les secrets des stockages, les clés SSH partagées, les jetons d'API : tout ce qui permet de prendre le contrôle du cluster. `config.db` contient tout cela : sa sauvegarde (M09-E29) est chiffrée et rangée comme un secret `critique`.
7. Copier `/etc/pve/corosync.conf` vers `corosync.conf.new` **dans** `/etc/pve`, l'éditer, incrémenter `config_version`, renommer (la documentation recommande aussi une copie de sauvegarde avant). Éditer `/etc/corosync/corosync.conf` d'un nœud : modification locale, écrasée au prochain changement du fichier de `/etc/pve`, ou incohérente avec les autres nœuds (M09-E35).
8. Le fencing par watchdog est **autonome** : le nœud se clôture lui-même quand il perd le quorum, sans dépendre d'un équipement externe joignable. Il suffit si le watchdog est fiable (matériel) ; il est insuffisant si le nœud peut rester figé sans que le watchdog le réinitialise (`softdog` sur un noyau bloqué), ou si l'on a besoin d'une **preuve** externe de l'extinction (stockages partagés sans verrou).
9. **b**. C'est la procédure documentée. (a) recrée la ressource sans corriger ; (c) est refusé ou contourne la HA ; (d) n'efface pas l'état `error`.
10. `node-affinity` stricte : la ressource ne tourne **que** sur les nœuds listés (aucun disponible : arrêtée) ; non stricte : préférence (ailleurs si besoin). `resource-affinity` positive : ensemble ; négative : séparées. Impossible pendant une maintenance : trois ressources séparées sur trois nœuds (M09-E37 v2) ; version viable : règle négative sur deux ressources, ou la troisième en affinité de nœud non stricte.
11. `node-maintenance enable` : un nœud à vider (mise à jour, redémarrage) ; les ressources HA en partent et y reviennent. `disarm-ha freeze` : intervention sur tout le cluster (réseau Corosync, commutateurs) où l'on veut que la HA ne réagisse à rien et ne clôture personne ; `ignore` : idem mais on reprend la main sur les ressources. `--state ignored` : une seule ressource qu'on pilote à la main un moment.
12. Trois copies sur trois hôtes : on survit à la perte d'un hôte sans perte de données **et** sans gel (deux copies ≥ `min_size` 2). Nœud en maintenance : écritures sur deux copies, PG `active+undersized+degraded`. Un second OSD tombe sur un autre nœud : certains PG n'ont plus qu'une copie, sous `min_size` : `inactive`, E/S figées pour les VMs concernées (M09-E39 v3, sans le `min_size 3`).
13. La QoS ne protège pas contre la latence de file d'attente au niveau des cartes et des commutateurs lors d'une récupération Ceph à pleine bande passante ; Corosync tolère quelques millisecondes, pas des pics de centaines. Les battements de cœur des OSD sont remplis à 2000 octets pour qu'une MTU défaillante (trames de plus de 1500 perdues) se voie **au battement de cœur**, pas seulement aux transferts de données (M09-E39 v2).
14. **a** pour une VM qui doit être migrée **maintenant** sans interruption, en mesurant d'abord la taille du disque et le temps de copie ; puis déplacer le disque sur `ceph-vm` à froid ou à chaud plus tard. (b) n'existe pas pour ce cas ; (c) interrompt le service ; (d) ne change rien au disque local.
15. Réplication ZFS : RPO = intervalle du job (minutes), RTO de reprise HA rapide mais avec perte des données depuis la dernière synchronisation, réseau consommé par lots ; Ceph : RPO nul (écriture synchrone sur trois copies), RTO de reprise HA, réseau consommé en continu. Ceph pour les bases et tout ce qui ne tolère pas de perte ; ZFS répliqué pour des VMs sans état ou tolérantes (frontaux, CI), ou pour des sites sans Ceph.
16. Le *dirty bitmap* de QEMU note les blocs modifiés depuis la dernière sauvegarde : seuls ceux-là sont lus et envoyés. Il est perdu à l'arrêt de la VM (QEMU qui redémarre) ou si la dernière sauvegarde a changé côté serveur : la sauvegarde suivante relit tout le disque (mais PBS dédoublonne, donc n'envoie que les morceaux nouveaux). Le chiffrement côté client protège la confidentialité des données sur le datastore (un administrateur de `pbs01` ne les lit pas) ; il ne protège ni contre la suppression, ni contre la perte de la clé (sans elle, aucune restauration).
17. Migrer ou évacuer (si encore possible), `ceph osd out`/`destroy` des OSD du nœud mort et retrait de son MON/MGR (`pveceph mon destroy` depuis un nœud vivant), `pvecm delnode`, nettoyage de `/etc/pve/nodes/<nœud>` ; réinstallation automatique (M09-E03), adhésion (`pvecm add`), Ceph (MON, MGR, OSD). Pièges : même nom et même adresse sans avoir retiré l'ancien nœud, `known_hosts` des autres nœuds avec l'ancienne clé d'hôte (`pvecm updatecerts`), réplications et règles HA qui pointent encore vers lui (RB-091, M09-E29).
18. **b**. Trois semaines d'écart : paquets plus anciens (versions mixtes à éviter au-delà d'une mise à jour progressive), heure, et configuration de cluster obsolète (son `corosync.conf` a un `config_version` inférieur : il doit le recevoir, pas l'imposer). (a) est faux pour les paquets et l'heure ; (c) et (d) sont des parties de la réponse.
19. Un nœud à la fois pour garder le quorum et la capacité d'accueillir les VMs évacuées ; Proxmox VE d'abord (nœud par nœud, avec maintenance HA), Ceph selon son ordre propre (MON, MGR, OSD, puis MDS ; `noout` pendant chaque nœud) ; entre deux nœuds : quorum, `HEALTH_OK`, ressources HA revenues, versions (`pveversion -v`), RB-092.
20. Non : Corosync exige une latence faible et stable (la documentation de Proxmox VE recommande moins de 5 ms, idéalement bien moins) ; un tunnel WireGuard sur une liaison domestique ou WAN n'offre ni l'une ni l'autre, et une coupure de la liaison ferait perdre le quorum ou clôturerait des nœuds. À la place : PAR2 reste un site de **sauvegarde et de reprise** (PBS, réplication de sauvegardes, PRA documenté au F5), éventuellement un cluster séparé à PAR2 et une migration entre clusters (`qm remote-migrate`, en aperçu) pour des bascules planifiées.

**Pièges classiques** : répondre par cœur sans relier aux pannes vécues ; pour les QCM, oublier d'expliquer pourquoi les autres options sont fausses.
