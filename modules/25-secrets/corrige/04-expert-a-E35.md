### M25-E35 — Panne : le coffre est scellé après un redémarrage

**Points non vérifiés en conditions réelles** — signale tes retours, ils corrigent le workbook :
- `break-E35.sh` n'a pas été joué contre une grappe OpenBao. Il suppose que l'unité du paquet `.deb` recharge par SIGHUP (`systemctl reload openbao`, comme le rôle `certificats_acme` le fait déjà) et que ce rechargement relit le certificat **et** la clé de l'écouteur.
- Variante 2 : le nombre de descripteurs qu'OpenBao 2.7 ouvre au démarrage (Raft, deux bases bbolt, deux écouteurs, connexion à `kms01`, connexions de grappe) n'a pas été mesuré. Avec 64, le nœud peut démarrer et rester en attente (panne **latente**, révélée par la charge ou par une bascule), ou ne pas démarrer du tout. Le script accepte les deux cas et le symptôme affiché s'adapte. Relève le nombre réel (`ls /proc/<PID>/fd | wc -l`) et signale-le.
- Les messages de `curl` cités suivent curl 8 avec OpenSSL 3 (Debian 13) ; leur libellé exact peut varier d'une version à l'autre.

**Démarche de diagnostic**

*Symptômes* : un nœud sur trois ne répond plus au contrôle de Nadia, `OpenBaoScelle` a sonné pour ce nœud ; la VIP répond. Variante 2 (si le nœud a démarré) : tout est vert, seul l'aveu de Lucas signale un problème.

*Hypothèses*, de la plus grave à la plus fine : (a) le nœud est **scellé** (seal `transit`, `kms01`, jeton de `kms.env`) ; (b) le processus est **arrêté** ou redémarre en boucle ; (c) le nœud tourne mais est **injoignable** sur 8200 (écoute, pare-feu local) ; (d) il répond mais est **refusé** (certificat : nom, échéance, autorité) ; (e) il est **bridé** (limites de ressources) ; (f) il est **sorti de Raft**. Une seule observation sépare déjà (a) des autres : un nœud scellé **répond**, avec un 503 et `"sealed": true`.

**Étape 1 — Observer depuis les clients (adm01).** Le code seul ne suffit pas : il faut le message.

```
admin@adm01:~$ for n in vault01 vault02 vault03 openbao; do
    printf '%-8s ' "$n"
    curl -s -o /dev/null --max-time 5 -w '%{http_code} %{errormsg}\n' \
      "https://$n.par1.medisphere.internal:8200/v1/sys/health"
  done
vault01  429
vault02  200
vault03  000 Failed to connect to vault03.par1.medisphere.internal port 8200 after 1 ms: Couldn't connect to server
openbao  200
```

Trois familles de réponses. `Couldn't connect` (refus immédiat) : rien n'écoute à cette adresse, ou le processus est arrêté (variantes 1, et 2 si le nœud n'a pas démarré). `SSL: no alternative certificate subject name matches target host name 'vault03.par1.medisphere.internal'` : le nœud répond, mais sous une autre identité (variante 3). `429` partout : rien à voir de l'extérieur (variante 2 latente). Aucun 503 : l'hypothèse (a) est déjà très affaiblie.

D'où vient « une requête sur trois » ? Du contrôle de Nadia, qui interroge **chaque nœud par son nom**. Les clients réels (CI, ESO, cert-manager, Ansible) passent par la VIP, donc par l'actif : ils ne voient **rien**. Et `OpenBaoScelle` ? Son expression est `vault_core_unsealed == 0` **ou** `up == 0` : Prometheus n'arrive plus à lire le nœud (`up == 0`), l'alerte sonne avec le titre « scellé ou ne répond pas ». Nadia a lu « scellé ». Dans l'interface de Prometheus, la cible `vault03` donne la raison exacte (`connection refused` ou `x509: certificate is valid for vault01…, not vault03…`).

**Étape 2 — Mesurer depuis le nœud.** On l'interroge comme keepalived le fait : sous son nom, par la boucle locale.

```
admin@vault03:~$ systemctl status openbao --no-pager | head -4
admin@vault03:~$ sudo journalctl -u openbao --since today --no-pager | grep -Ei 'error|warn|reload|too many' | tail -20
admin@vault03:~$ curl -s --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt \
    --resolve vault03.par1.medisphere.internal:8200:127.0.0.1 \
    https://vault03.par1.medisphere.internal:8200/v1/sys/seal-status | jq '{sealed, type}'
{ "sealed": false, "type": "transit" }
admin@vault03:~$ sudo ss -ltn 'sport = :8200 or sport = :8201'
admin@vault03:~$ systemctl show openbao -p LimitNOFILE -p DropInPaths -p NRestarts
admin@vault03:~$ pid=$(systemctl show -p MainPID --value openbao)
admin@vault03:~$ sudo grep 'open files' /proc/$pid/limits; sudo ls /proc/$pid/fd | wc -l
admin@adm01:~$ openssl s_client -connect vault03.par1.medisphere.internal:8200 \
    -servername vault03.par1.medisphere.internal </dev/null 2>/dev/null \
    | openssl x509 -noout -subject -ext subjectAltName -enddate
admin@adm01:~$ bao operator raft list-peers
admin@adm01:~$ bao operator raft autopilot state
```

Le nœud est **descellé** : (a) écartée. Raft le compte parmi les trois `voter`, autopilot le dit sain : (f) écartée. C'est attendu : Raft et le transfert de requêtes passent par **8201** (`cluster_address`), pas par l'écouteur API. La grappe peut être parfaitement saine pendant qu'un de ses nœuds est invisible de tous ses clients. Ce qui différencie les variantes, ce sont les trois lignes suivantes : `ss`, les limites et le certificat présenté.

**Étape 3 — Comparer avec Git.**

```
admin@adm01:~/src/ansible$ git switch main && git pull
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/coffre.yml --limit vault03 --check --diff
admin@vault03:~$ systemctl cat openbao | grep -E '^# /|LimitNOFILE'
admin@vault01:~$ systemctl cat openbao | grep -E '^# /|LimitNOFILE'      # un nœud sain, pour comparer
```

Ansible compare ce qu'il **gère** : le gabarit `openbao.hcl`, la surcharge `medisphere.conf`, le certificat (par `step certificate verify --host`). Ce qu'il ne gère pas, il ne le voit pas. `systemctl cat` montre au contraire tout ce que systemd applique, dans l'ordre.

**Variante 1 — écouteur limité à la boucle locale.**

```
admin@vault03:~$ sudo ss -ltn 'sport = :8200 or sport = :8201'
State  Recv-Q Send-Q Local Address:Port  Peer Address:Port
LISTEN 0      4096       127.0.0.1:8200       0.0.0.0:*
LISTEN 0      4096     10.10.20.23:8201       0.0.0.0:*
```

et dans le `--check --diff` :

```
-  address         = "127.0.0.1:8200"
+  address         = "0.0.0.0:8200"
```

Le nœud a redémarré avec un écouteur API qui n'accepte que la boucle locale. Pour lui-même, tout va bien : `chk_openbao_actif` l'interroge par `127.0.0.1`. Pour Prometheus, `adm01` et les autres nœuds, il n'existe plus. `api_addr` annonce toujours `https://vault03…:8200`, une adresse qui ne répond plus. C'est l'écart le plus simple à voir dans Git, parce que le fichier est géré par le rôle. Cause : modification à la main de `openbao.hcl`, prise en compte au redémarrage de la maintenance (un changement d'adresse d'écouteur demande un redémarrage, pas un SIGHUP).

Correctif : le rôle, sur ce seul nœud, redémarrage autorisé. Le nœud est **en attente** (vérifie-le d'abord : `sys/health` local = 429). Il se descelle seul par `kms01`.

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/coffre.yml --limit vault03 -e openbao_redemarrer=true
```

**Variante 2 — limite de descripteurs écrasée par une surcharge oubliée.**

```
admin@vault03:~$ systemctl cat openbao | grep -E '^# /|LimitNOFILE'
# /usr/lib/systemd/system/openbao.service
# /etc/systemd/system/openbao.service.d/medisphere.conf
LimitNOFILE=65536
# /etc/systemd/system/openbao.service.d/override.conf
LimitNOFILE=64
admin@vault03:~$ sudo grep 'open files' /proc/$pid/limits
Max open files            64                   64                   files
```

`override.conf` est le fichier que crée `systemctl edit openbao` : Lucas l'a utilisé pour un « essai de charge » et l'a oublié. systemd lit les surcharges par **ordre alphabétique** de nom de fichier, et pour un réglage à valeur unique comme `LimitNOFILE`, la dernière valeur l'emporte : `override.conf` passe après `medisphere.conf`. `LimitNOFILE` fixe les limites **souple et dure**. Le runtime Go relève de lui-même la limite souple jusqu'à la limite dure, mais pas au-delà : 64 descripteurs pour tout le processus. Chaque connexion cliente, chaque connexion Raft, chaque fichier ouvert en consomme un. Selon la marge, le nœud ne démarre pas (`NRestarts` grimpe, `too many open files` au journal), ou il démarre et tient en attente, où il ne reçoit presque rien. Le jour où il devient actif, toute la charge arrive sur lui : `accept: too many open files`, délais, refus.

Le `--check --diff` n'affiche **rien** : le rôle ne connaît pas `override.conf`. C'est l'écart le plus sournois des trois, et la raison de la prévention ci-dessous.

Correctif, le nœud étant en attente (ou arrêté) : retirer le fichier, **recharger systemd**, redémarrer. Puis corriger le rôle par une MR ([extrait](fichiers/M25-E35/ansible/roles/openbao/tasks/configuration.yml.extrait), [variable](fichiers/M25-E35/ansible/roles/openbao/defaults/main.yml.extrait)) pour que la prochaine fois le `--check` le montre et que l'application le retire.

```
admin@vault03:~$ sudo rm /etc/systemd/system/openbao.service.d/override.conf
admin@vault03:~$ sudo systemctl daemon-reload
admin@vault03:~$ sudo systemctl restart openbao
admin@vault03:~$ sudo grep 'open files' /proc/$(systemctl show -p MainPID --value openbao)/limits
Max open files            65536                65536                files
```

Sans `daemon-reload`, `systemctl restart` relance le service avec l'**ancienne** configuration chargée (systemd le signale par un avertissement « unit file … changed on disk »).

**Variante 3 — le nœud se présente sous un autre nom.**

```
admin@adm01:~$ openssl s_client -connect vault03.par1.medisphere.internal:8200 \
    -servername vault03.par1.medisphere.internal </dev/null 2>/dev/null \
    | openssl x509 -noout -subject -ext subjectAltName -enddate
subject=CN=vault01.par1.medisphere.internal
X509v3 Subject Alternative Name:
    DNS:vault01.par1.medisphere.internal, DNS:openbao.par1.medisphere.internal
notAfter=…
```

Le certificat est **valide** : bonne racine, pas expiré, et sa clé correspond (le nœud a rechargé sans erreur). Seulement, il a été émis pour `vault01`. Quelqu'un a recopié le certificat et la clé de `vault01` sur `vault03`, puis rechargé le service (SIGHUP). Tout client qui joint `vault03` **par son nom** le refuse : Prometheus, ton `curl`, et `chk_openbao_actif` du nœud lui-même. Un client qui le joindrait par le nom du service l'accepterait, puisque `openbao.par1.medisphere.internal` figure dans le certificat. Le `--check --diff` est trompeur : on voit `included: …/emettre.yml for vault03` (le rôle a vu que le certificat ne se vérifie pas pour `vault03`), mais les tâches `command` sont sautées en simulation et le récapitulatif annonce `changed=0`.

Correctif : réémettre le certificat **du nœud** par le rôle (ACME, défi HTTP-01 relayé par HAProxy, puis SIGHUP, sans redémarrage).

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/coffre.yml --limit vault03
```

Ni `step ca renew` (il renouvellerait l'identité de `vault01`, par TLS mutuel avec ce certificat), ni une nouvelle copie depuis un autre nœud. Une clé privée qui a voyagé entre deux machines n'est plus propre à aucune des deux. Note-le dans le journal : la clé de `vault01` a été exposée sur `vault03` (dans le lab, c'est le script de panne qui l'a copiée ; en production, on réémettrait aussi le certificat de `vault01`).

**Réponse à Nadia : et si l'actif redémarre cet après-midi ?** Les deux nœuds en attente se disputent l'élection : le nœud malade a environ une chance sur deux de prendre la main.

| Cause | Le nœud malade devient actif | Effet pour les clients |
|---|---|---|
| Écouteur sur 127.0.0.1 | `chk_openbao_actif` passe (boucle locale, 200) : keepalived lui donne la VIP | les requêtes arrivent sur 10.10.20.200:8200, où rien n'écoute : **tout** tombe |
| `LimitNOFILE=64` | la VIP le suit tant que son contrôle passe | la charge réelle épuise les descripteurs : délais et refus, contrôle qui échoue par moments, VIP instable |
| Certificat d'un autre nœud | `chk_openbao_actif` échoue (nom du nœud) : le nœud reste en FAULT | personne ne porte la VIP : **tout** tombe, alors que le coffre est descellé et que Raft est sain |

Réponse écrite : « oui, un risque sur deux de coupure totale ; la maintenance de Lucas attend la réparation de `vault03` ». C'est aussi pour cela que l'avertissement de l'énoncé interdit le `step-down` « pour voir ».

**Clôture commune** : boucle `curl` de l'étape 1 (trois codes 200/429, aucun message d'erreur), `lab/bin/check 25 35`, puis `lab/bin/break 25 35 --annuler` et journal ([modèle](fichiers/M25-E35/medisphere/docs/securite/secrets/journal/AAAA-MM-JJ-INC-5235.md)).

**Prévention**
- **Dérive détectée par Ansible en mode vérification.** Le job `derive` de `plateforme/ansible` (M04-E29, `site.yml --check --diff` chaque nuit) voit la variante 1 telle quelle, à condition que `site.yml` importe `coffre.yml` et que ses tâches ne soient pas exclues par une étiquette : vérifie-le. Pour les deux autres, il faut d'abord que le rôle les **voie**. [Le rôle `openbao`](fichiers/M25-E35/ansible/roles/openbao/tasks/configuration.yml.extrait) liste le dossier de surcharge et retire tout fichier non déclaré (`openbao_surcharges_declarees`). En `--check`, chaque fichier en trop apparaît en `changed`. [Le rôle `certificats_acme`](fichiers/M25-E35/ansible/roles/certificats_acme/tasks/main.yml.extrait) compte un certificat à réémettre comme un changement, visible en simulation. Après toute maintenance manuelle, on lance soi-même le `--check --diff` du groupe touché, avant de rendre la main.
- **Alerte qui dit ce qu'elle a vu.** [`OpenBaoScelle` est scindée](fichiers/M25-E35/observabilite/regles/secrets.yaml.extrait) : `vault_core_unsealed == 0` pour un nœud qui répond et se dit scellé ; `OpenBaoInjoignable` pour `up == 0`, avec dans la description « ne pas desceller, vérifier depuis le nœud, pas de bascule avant réparation ». Les [tests unitaires](fichiers/M25-E35/observabilite/tests/secrets.test.yaml.extrait) de la règle sont mis à jour dans la même MR. Bonus : un avertissement sur l'écart entre la limite et l'usage des descripteurs, si l'exportateur expose `process_max_fds` (à vérifier sur ta version).
- **Revue de MR.** Toute modification des nœuds du coffre passe par une MR de `plateforme/ansible`, relue par un second membre de `plateforme-admins`. Le gabarit de MR du groupe `role_coffre` demande le `--check --diff` d'un nœud, l'ordre de passage (en attente d'abord) et le retour arrière. Une maintenance de nuit sans MR se termine par un `--check --diff` vert, collé dans le ticket de changement.

**Explications**

Un nœud OpenBao empile trois couches indépendantes. La **barrière** est scellée ou non : c'est ce que disent `sys/seal-status` et `vault_core_unsealed`. **Raft** parle sur 8201 avec ses propres certificats internes, et autopilot y mesure la santé. L'**écouteur API** sur 8200 porte le TLS du nœud, et c'est par lui que passent les clients, la supervision et keepalived. Une panne d'une couche laisse les autres intactes. Toute la difficulté est de ne pas conclure d'une couche à l'autre : « Raft le voit sain » ne dit rien de l'API, et « l'API ne répond pas » ne dit rien de la barrière.

La configuration **effective** n'est pas le fichier que l'on croit. Un écouteur se lit avec `ss`, une limite dans `/proc/<PID>/limits`, une unité avec `systemctl cat`, un certificat dans ce que le serveur **présente**. Les trois variantes ont un point commun : le fichier de référence (gabarit, `medisphere.conf`, demande ACME) n'a pas changé ou n'est pas en cause, mais ce qui tourne a changé.

Enfin, le contrôle de santé de la VIP regarde le nœud **depuis lui-même**. C'est voulu, la décision appartient au nœud qui porte la VIP. Mais ce contrôle ne garantit pas que les clients le joignent. D'où un contrôle complémentaire **depuis l'extérieur**, par nom (la supervision), avec une alerte qui ne confond pas « scellé » et « injoignable ».

**Alternatives**
- Comparer les trois nœuds d'un coup : `ansible role_coffre -b -m ansible.builtin.command -a 'systemctl show openbao -p LimitNOFILE -p DropInPaths'` ou `diff <(ssh vault01 sudo cat /etc/openbao/openbao.hcl) <(ssh vault03 sudo cat /etc/openbao/openbao.hcl)` (les noms et l'adresse de grappe diffèrent normalement).
- `bao status` avec `BAO_ADDR=https://vault03…:8200` : même information que `sys/health`, avec le message d'erreur du client Go (`dial tcp … connection refused`, `x509: certificate is valid for …`).
- Réparer la variante 2 en remettant `LimitNOFILE=65536` **dans** `override.conf` : ça remarche, mais un fichier non géré reste, et le prochain essai le réécrira.

**Pièges classiques**
- Croire le titre de l'alerte et partir sur `kms01`, le jeton du seal ou les dépositaires, alors que le nœud répond descellé par la boucle locale.
- Faire un `step-down` ou redémarrer l'actif « pour voir » : le nœud malade peut prendre la main (tableau ci-dessus).
- Redémarrer un nœud sans vérifier qu'il est **en attente**.
- Variante 1 : corriger le fichier par `sed` sans repasser le rôle, puis oublier le redémarrage (un changement d'adresse d'écouteur n'est pas relu par SIGHUP).
- Variante 2 : relever `LimitNOFILE` dans `medisphere.conf`, qui l'est déjà, ou oublier `daemon-reload`.
- Variante 3 : conclure « certificat expiré » sans lire le sujet et les noms ; lancer `step ca renew`, qui renouvelle la mauvaise identité.

**En production chez MédiSphère**

Une maintenance des nœuds du coffre suit un ticket de changement : MR relue, un nœud en attente à la fois, `--check --diff` vert du groupe avant et après, contrôle externe par nom des trois nœuds, puis seulement le nœud actif (passage de témoin). Un réglage d'essai se fait sur la VM jetable (`bao-essai`), jamais sur la grappe. La dérive nocturne couvre le coffre et ouvre un ticket. `OpenBaoInjoignable` et `OpenBaoScelle` renvoient à deux sections distinctes du RB-251.
