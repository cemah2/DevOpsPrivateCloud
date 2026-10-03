# Module 00 — Palier 1 : Découverte

Première semaine dans l'équipe Plateforme. Karim veut d'abord mesurer ton niveau, Claire veut un état des lieux précis de `pve01` et la récupération des données de `hp01` avant tout le reste. Ensuite seulement, tu prépares l'hyperviseur, tu poses le réseau isolé du lab, tu construis le routeur `gw01` à la main, et tu fabriques le template qui servira à toutes les VMs du workbook. À la fin du palier, `adm01` et `dns01` tournent, joignables depuis `pve01`, et le lab sort sur Internet à travers un pare-feu que tu as écrit.

Prérequis matériel : accès root à `pve01` (web et SSH), accès à `hp01`, un accès de secours à la console de `pve01`. Lis [`00-introduction.md`](00-introduction.md) avant de commencer, en particulier les règles de sécurité.

---

### M00-E01 — Test de positionnement Linux  `Q` `★★`

> **Ticket PLAT-101** — *De : Karim Benali*
> Bienvenue ! Comme à chaque arrivée, je te fais passer le questionnaire Linux qu'on utilise en entretien. Ce n'est pas éliminatoire : il nous dit sur quoi t'épauler, et à toi quels modules lire de près.
> Réponds par écrit, sans moteur de recherche ni IA, en 1 h 30 maximum. Ensuite, corrige-toi avec la grille.

**Objectifs pédagogiques**
- Évaluer honnêtement tes acquis en administration Linux de production.
- Identifier les notions à retravailler avant les modules qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h 30 (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 25 questions. Pour les QCM, justifie ton choix en une ou deux phrases : la justification compte autant que la lettre.

1. Sur un serveur, `df -h /var` indique 100 % d'utilisation, mais `du -sh /var` ne totalise que 40 % de la taille du système de fichiers. Donne au moins deux causes possibles, la commande qui confirme chacune, et comment libérer l'espace sans redémarrer.

2. *(QCM)* Une application écrit `No space left on device` alors que `df -h` montre 35 % d'espace libre sur le système de fichiers concerné. Que vérifies-tu en premier ?
   - A. `fsck` du système de fichiers
   - B. `df -i`
   - C. `lsblk -f`
   - D. `dmesg | grep -i error`

3. Une machine de 8 cœurs affiche un *load average* de 24, mais `top` montre 85 % d'*idle*. Comment est-ce possible ? Comment identifies-tu les processus en cause ?

4. Interprète cette sortie. Le serveur manque-t-il de mémoire ? Qu'est-ce qui t'inquiète et que vérifies-tu ensuite ?
   ```
   $ free -h
                  total        used        free      shared  buff/cache   available
   Mem:           125Gi        98Gi       1.2Gi       2.1Gi        28Gi        27Gi
   Swap:          8.0Gi       7.9Gi       100Mi
   ```

5. Le noyau a tué un processus PostgreSQL. Où le constates-tu ? Comment le noyau a-t-il choisi sa victime ? Donne deux moyens de protéger ce service. Quelle différence avec un OOM survenant dans un cgroup limité par `MemoryMax=` ?

6. *(QCM)* L'unité `app.service` doit démarrer après `postgresql.service` et être arrêtée dès que PostgreSQL s'arrête, **y compris s'il s'arrête de lui-même** (plantage). Quelle combinaison est correcte ?
   - A. `After=postgresql.service` seul
   - B. `Wants=postgresql.service`
   - C. `Requires=postgresql.service` et `After=postgresql.service`
   - D. `BindsTo=postgresql.service` et `After=postgresql.service`

7. Donne les commandes `journalctl` pour : (a) les messages de priorité *err* ou plus grave de `nginx.service` depuis le démarrage en cours ; (b) tout le journal du démarrage précédent ; (c) les messages du noyau de la dernière heure ; (d) suivre en direct deux unités à la fois. Que faut-il vérifier pour que (b) fonctionne ?

8. Tu dois modifier la ligne `ExecStart=` d'un service fourni par un paquet Debian. Comment procèdes-tu pour que la modification survive aux mises à jour du paquet ? Quel est le piège propre à `ExecStart=` ?

9. *(QCM)* Un processus est dans l'état `D` depuis 20 minutes et `kill -9` n'a aucun effet. Que se passe-t-il ? Complète ta réponse : que faire face à un processus dans l'état `Z` ?
   - A. Le processus intercepte et ignore SIGKILL
   - B. Il attend une entrée/sortie non interruptible dans le noyau
   - C. C'est un zombie : il faut tuer son parent
   - D. Il faut d'abord lui envoyer SIGSTOP

10. Le dossier `/srv/echanges` est partagé par le groupe `compta`. Les fichiers créés par chaque membre doivent appartenir au groupe `compta` et être modifiables par tout le groupe, mais un membre ne doit pas pouvoir supprimer les fichiers des autres. Quels mécanismes utilises-tu ? Donne les commandes.

11. *(QCM, plusieurs réponses possibles)* Tu crées `/etc/sudoers.d/admin.conf` pour accorder `NOPASSWD` à `admin`, mais rien ne change. Quelles sont les causes possibles ?
    - A. Le nom du fichier contient un point
    - B. Les droits du fichier sont `0644`
    - C. Une règle lue plus loin redéfinit les droits d'`admin`
    - D. Il faut redémarrer le service `sudo`

12. `ssh admin@srv` répond `Permission denied (publickey)` alors que ta clé publique est bien dans `~admin/.ssh/authorized_keys`. Décris ta démarche côté client et côté serveur, et cite trois causes fréquentes.

13. Pour administrer des serveurs derrière un bastion, compare `ProxyJump` et le transfert d'agent (`ForwardAgent`). Lequel recommandes-tu, et pourquoi ?

14. *(QCM)* Sur un hôte Proxmox VE, pourquoi la documentation recommande-t-elle `apt full-upgrade` (ou `dist-upgrade`) plutôt que `apt upgrade` ?
    - A. `apt upgrade` ne met jamais à jour le noyau
    - B. `apt upgrade` n'installe ni ne supprime aucun paquet, ce qui peut bloquer des mises à jour qui ont de nouvelles dépendances et laisser le système dans un état incohérent
    - C. `apt full-upgrade` fait passer à la version majeure suivante de Debian
    - D. Il n'y a aucune différence sur Proxmox VE

15. Après l'ajout d'un disque dans `/etc/fstab`, le serveur redémarre en *emergency mode*. Pourquoi ? Comment rends-tu la ligne robuste (au moins deux options) et comment teste-t-on une modification de `fstab` avant de redémarrer ?

16. Un pool LVM-thin est sur-alloué (la somme des tailles des volumes dépasse la taille du pool). Que se passe-t-il quand le pool atteint 100 % ? Comment le surveilles-tu, et comment t'en prémunis-tu ?

17. *(QCM)* Lequel de ces systèmes de fichiers ne peut pas être réduit ? Quelle conséquence en tires-tu pour les disques de VMs ?
    - A. ext4
    - B. XFS
    - C. Btrfs
    - D. Tous peuvent être réduits

18. Un service tombe avec `Too many open files`. Où lis-tu la limite effective du processus ? Comment l'augmentes-tu proprement pour un service systemd ? Pourquoi `/etc/security/limits.conf` ne suffit-il pas ?

19. Explique ce que font `set -e`, `set -u` et `set -o pipefail`, puis donne deux situations où `set -e` ne se comporte pas comme on l'attend.

20. Ce script supprime les exports CSV de plus de 30 jours. Trouve au moins quatre défauts et propose une version correcte.
    ```bash
    #!/bin/bash
    DIR=$1
    for f in $(ls $DIR/*.csv); do
      if [ $(stat -c %Y $f) -lt $(date -d '30 days ago' +%s) ]; then
        rm $f
      fi
    done
    ```

21. Interprète cette sortie : quels services sont joignables depuis le réseau ? Que signifie la dernière ligne ?
    ```
    $ ss -tlnp
    State  Recv-Q Send-Q   Local Address:Port  Peer Address:Port Process
    LISTEN 0      128            0.0.0.0:22         0.0.0.0:*    users:(("sshd",pid=812,fd=3))
    LISTEN 0      244          127.0.0.1:5432       0.0.0.0:*    users:(("postgres",pid=1022,fd=6))
    LISTEN 0      511                  *:80               *:*    users:(("nginx",pid=1101,fd=6))
    LISTEN 0      4096     127.0.0.53%lo:53         0.0.0.0:*    users:(("systemd-resolve",pid=640,fd=14))
    LISTEN 129    128           10.0.0.5:8080       0.0.0.0:*    users:(("java",pid=2210,fd=41))
    ```

22. Un processus semble figé. Cite au moins trois outils ou sources d'information qui te permettent de savoir **ce qu'il attend**, sans le redémarrer.

23. Pour une tâche de purge nocturne sur un serveur de production, compare `cron` et un *timer* systemd sur au moins quatre critères, puis donne ton choix.

24. Tu dois activer un paramètre d'un module noyau (par exemple `nested` de `kvm_intel`). Comment lis-tu la valeur courante ? Comment la rends-tu persistante ? Dans quel cas faut-il régénérer l'initramfs ?

25. Pourquoi la synchronisation horaire est-elle critique sur une plateforme ? Cite quatre composants ou mécanismes qui cassent sans elle. Comment vérifies-tu qu'un hôte est synchronisé avec chrony ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 25 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille du corrigé (0, 1 ou 2 points) et calculé ton score sur 50.
- [ ] Tu as reporté dans tes notes la liste des notions à retravailler et les modules associés.

<details><summary>Indice 1</summary>

Ne laisse aucune question blanche : une réponse partielle mais raisonnée vaut des points, et la grille récompense la démarche de diagnostic plus que la mémorisation.
</details>

<details><summary>Indice 2</summary>

Pour les questions de diagnostic, structure ta réponse en « hypothèse → commande qui la confirme ou l'infirme → action ». C'est la forme attendue en entretien comme en astreinte.
</details>

**Pour aller plus loin** (facultatif) : refais le test à la fin du bloc A (module 06) sans relire le corrigé, et compare les deux scores.

---

### M00-E02 — Test de positionnement réseau  `Q` `★★`

> **Ticket PLAT-102** — *De : Karim Benali*
> Deuxième partie : le réseau. Chez nous, la moitié des incidents « applicatifs » finissent en problème de MTU, de route ou de DNS. Même règle : par écrit, sans aide, 1 h 30 maximum.

**Objectifs pédagogiques**
- Évaluer tes acquis réseau sur les sujets qui reviennent en production : routage, VLAN, filtrage à états, NAT, MTU, DNS, DHCP.
- Repérer les notions à consolider avant les modules réseau (00, 07, 15).

**Prérequis** : aucun.
**Durée indicative** : 1 h 30 (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 24 questions, en justifiant les QCM.

1. *(QCM)* Un hôte a l'adresse 10.10.40.77/23. Quelles sont l'adresse de réseau et l'adresse de diffusion ? 10.10.41.0 est-elle une adresse d'hôte valide dans ce réseau ?
   - A. 10.10.40.0 et 10.10.40.255
   - B. 10.10.40.0 et 10.10.41.255
   - C. 10.10.41.0 et 10.10.41.255
   - D. 10.10.40.64 et 10.10.40.127

2. Un serveur Linux est configuré en 10.10.20.15/24 avec la passerelle 10.10.2.1 (faute de frappe). Que se passe-t-il, précisément, pour : (a) un ping vers 10.10.20.10 ; (b) un ping vers 9.9.9.9 ?

3. Voici la table de routage de `pve01`. Quelle route le noyau choisit-il pour 10.10.20.10, 10.10.99.5, 10.20.10.10 et 192.168.1.40 ? Quelle commande donne la réponse du noyau sans envoyer de paquet ?
   ```
   default via 192.168.1.1 dev vmbr0 proto kernel onlink
   10.10.0.0/16 via 192.168.1.40 dev vmbr0
   10.10.20.0/24 via 192.168.1.41 dev vmbr0
   192.168.1.0/24 dev vmbr0 proto kernel scope link src 192.168.1.20
   ```

4. Sur un bridge Linux *VLAN-aware*, explique les notions de PVID et d'*egress untagged*. Que devient une trame non étiquetée qui arrive sur le port d'une VM configurée sans tag ? Une VM branchée avec `tag=20` peut-elle recevoir le trafic du VLAN 30 ?

5. *(QCM)* Deux machines du même VLAN ont, par erreur, la même adresse IPv4. Quel est le symptôme le plus typique ? Comment le confirmes-tu ?
   - A. Aucune des deux machines ne répond plus
   - B. Des connexions qui fonctionnent puis se coupent de façon intermittente ; l'adresse MAC associée à l'IP change dans le cache ARP des voisins
   - C. Le switch désactive le port de la seconde machine
   - D. Le noyau Linux refuse de configurer l'adresse en double

6. Explique pourquoi un routage asymétrique casse les connexions TCP qui traversent un pare-feu à états, même quand toutes les routes sont « correctes ». Quel paramètre du noyau Linux peut, lui aussi, rejeter ces paquets sur un routeur ?

7. *(QCM)* Quelle est la différence entre `snat` et `masquerade` dans nftables ?
   - A. Aucune, ce sont des synonymes
   - B. `masquerade` utilise l'adresse de l'interface de sortie au moment du paquet et oublie les connexions quand l'interface tombe ; `snat` utilise une adresse fixée dans la règle
   - C. `snat` ne fonctionne qu'en IPv6
   - D. `masquerade` fonctionne sans suivi de connexion

8. Un client obtient `Connection timed out` sur un port d'un serveur, et `Connection refused` sur un autre port du même serveur. Que t'apprend chaque message sur ce qui se passe sur le chemin ou sur le serveur ? Quand préférer `reject` à `drop` dans un pare-feu ?

9. Sophie (RSSI) propose : « Pour la sécurité, on bloque tout l'ICMP sur le pare-feu. » Réponds-lui avec trois arguments techniques, et propose une politique ICMP raisonnable pour IPv4 et IPv6.

10. Depuis qu'un site distant passe par un tunnel, SSH se connecte mais un `ls -l` sur un gros dossier fige ; `curl https://…` reste bloqué juste après l'envoi du *Client Hello*. Explique le phénomène, comment le prouver avec `ping`, et donne deux corrections possibles.

11. *(QCM)* Un serveur accumule des milliers de sockets dans l'état `CLOSE_WAIT`. Qui est en cause ?
    - A. Le client, qui ne ferme pas ses connexions
    - B. Le réseau, qui perd les segments FIN
    - C. L'application locale, qui ne ferme pas ses sockets après que le pair a fermé
    - D. Le noyau, saturé de `TIME_WAIT`

12. Cette capture est faite sur `adm01`. Interprète-la. Où captures-tu ensuite pour localiser le problème ? À quoi ressemblerait la capture si le port était simplement fermé sur un serveur joignable ?
    ```
    10:01:02.100 IP 10.10.10.10.51544 > 10.10.20.10.5432: Flags [S], seq 1234567, win 64240, length 0
    10:01:03.130 IP 10.10.10.10.51544 > 10.10.20.10.5432: Flags [S], seq 1234567, win 64240, length 0
    10:01:05.150 IP 10.10.10.10.51544 > 10.10.20.10.5432: Flags [S], seq 1234567, win 64240, length 0
    ```

13. Écris les commandes `tcpdump` pour : (a) capturer sur `ens19` (le trunk de `gw01`) le trafic DNS du VLAN 20 en affichant les étiquettes 802.1Q ; (b) capturer sur `ens19.20` tout le trafic sauf SSH, sans résolution de noms ; (c) enregistrer une capture longue dans 10 fichiers tournants de 100 Mo.

14. Quelle est la différence entre un serveur DNS faisant autorité et un résolveur récursif ? Qu'est-ce que le TTL et le cache négatif ? Pourquoi, après la création d'un enregistrement qui manquait, certains clients reçoivent-ils encore `NXDOMAIN` ?

15. *(QCM)* `dig app.par1.medisphere.internal` répond correctement, mais `curl http://app.par1.medisphere.internal` échoue avec `Could not resolve host`. Quelle est la cause la plus probable ?
    - A. `dig` utilise un autre port que `curl`
    - B. `dig` interroge directement le serveur DNS, alors que `curl` passe par la résolution système (NSS : `/etc/nsswitch.conf`, `/etc/hosts`, éventuellement systemd-resolved)
    - C. `curl` ne gère pas le domaine `.internal`
    - D. Le TTL a expiré entre les deux commandes

16. Quel nom DNS faut-il créer pour la résolution inverse de 10.10.20.10 ? Cite deux services ou situations où une résolution inverse absente ou fausse pose problème.

17. Décris l'échange DHCP (DORA). Pourquoi un serveur DHCP situé dans un autre VLAN que les clients ne reçoit-il rien sans configuration particulière ? Que fait un relais DHCP, et à quoi sert le champ `giaddr` ?

18. Ton LAN domestique distribue de l'IPv6 (SLAAC), le lab est IPv4 uniquement. Quels effets ou risques pour : (a) une VM branchée par erreur sur `vmbr0` ; (b) le pare-feu de `gw01` en politique `drop`, si tu oublies l'ICMPv6 ?

19. *(QCM)* Deux serveurs sont reliés par un agrégat 802.3ad (LACP) de 2 × 10 Gb/s, avec `xmit_hash_policy layer3+4`. Une seule copie `rsync` entre eux plafonne à environ :
    - A. 20 Gb/s
    - B. 10 Gb/s
    - C. 5 Gb/s
    - D. Cela dépend uniquement du switch

20. Pourquoi une boucle de niveau 2 est-elle catastrophique, alors qu'une boucle de routage IP ne l'est « que » partiellement ? Pourquoi Proxmox VE configure-t-il ses bridges avec `bridge-stp off`, et dans quel cas faudrait-il l'activer ?

21. OSPF ou BGP dans un datacenter moderne ? Définis eBGP et iBGP en une phrase chacun. Pourquoi annoncer en BGP les IP de services Kubernetes (VLAN 41) plutôt que de les router statiquement ?

22. Explique le fonctionnement de VRRP (keepalived) : comment l'adresse virtuelle bascule, comment les voisins apprennent la nouvelle adresse MAC, et ce qu'est un *split-brain* dans ce contexte.

23. WireGuard : que signifie *cryptokey routing* ? Quel double rôle joue `AllowedIPs`, en émission et en réception ? Pourquoi `PersistentKeepalive` est-il utile derrière un NAT ?

24. Une VM « n'a pas Internet ». Diagnostique à partir de ces sorties. Si le problème trouvé était corrigé et que la VM n'avait toujours pas Internet, quelles seraient tes trois vérifications suivantes, dans l'ordre ?
    ```
    $ ip -br addr
    lo               UNKNOWN        127.0.0.1/8 ::1/128
    ens18            UP             10.10.20.10/24 fe80::be24:11ff:fe4a:1b2c/64
    $ ip route
    10.10.20.0/24 dev ens18 proto kernel scope link src 10.10.20.10
    $ ping -c1 10.10.20.1
    64 bytes from 10.10.20.1: icmp_seq=1 ttl=64 time=0.31 ms
    ```

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 24 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille du corrigé et calculé ton score sur 48.
- [ ] Tu as reporté dans tes notes les notions à retravailler et les modules associés.

<details><summary>Indice 1</summary>

Pour les questions de routage, raisonne toujours dans l'ordre : quelle route le noyau choisit-il (préfixe le plus long), quelle adresse MAC il doit résoudre (passerelle ou destination), et par quelle interface sort le paquet. Puis refais le même raisonnement pour la réponse.
</details>

<details><summary>Indice 2</summary>

Pour les questions de filtrage, distingue toujours le premier paquet d'une connexion (évalué par les règles) des paquets suivants (acceptés par le suivi de connexion, *conntrack*).
</details>

**Pour aller plus loin** (facultatif) : pour chaque question où tu as eu 0, reproduis la situation dans le lab une fois `gw01` construit (E10) : c'est le meilleur moyen d'ancrer la notion.

---

### M00-E03 — Inventaire de l'existant sur `pve01`  `RED` `★`

> **Ticket PLAT-103** — *De : Claire Morel*
> InfoGér nous a laissé un hyperviseur sans aucune documentation. Avant que quiconque y crée la moindre VM, je veux un inventaire écrit : version, matériel, disques, stockages, réseau, VMs existantes et ressources disponibles.
> Le document doit permettre à quelqu'un qui n'a jamais vu la machine de savoir ce qu'il peut faire **sans rien casser**.

**Objectifs pédagogiques**
- Collecter l'état d'un hôte Proxmox VE avec les outils en ligne de commande, sans rien modifier.
- Identifier les contraintes (VMs perso, disques utilisés, VMID occupés) qui conditionnent le reste du module.
- Produire une documentation exploitable par un tiers.

**Prérequis** : accès root SSH à `pve01`.
**Durée indicative** : 1 h.

**Contexte technique**

Le document se nomme `lab/inventaire-local.md`, dans ta copie du dépôt sur `pve01`. Il est ignoré par git (il décrit ton réseau domestique) : il reste local. Il servira de référence pour tout le workbook, en particulier sa dernière section qui fixe les valeurs entre chevrons (`<IP-PVE01>`, `<LAN-MAISON>`…).

**Travail demandé**

1. Copie le modèle ci-dessous dans `lab/inventaire-local.md`.
2. Collecte les informations **uniquement avec des commandes de lecture** (aucune modification de `pve01`) et complète chaque champ marqué `À COMPLÉTER`. Pour chaque information, garde en commentaire la commande qui l'a fournie : quelqu'un doit pouvoir mettre l'inventaire à jour dans six mois.
3. Pour chaque disque physique, conclus explicitement : « contient des données à préserver » ou « vierge, réaffectable ». En cas de doute, la réponse est « à préserver ».
4. Liste les VMID occupés et signale tout conflit avec les plages du workbook (1000-1099, 2000-3999, 5000-5999, 9000-9099).
5. Évalue la RAM et l'espace disque réellement disponibles pour le lab, en tenant compte des VMs perso qui démarrent automatiquement.
6. Note dans la section 7 les valeurs que tu connais déjà ; celles qui seront fixées plus tard restent « à définir en EXX ».

Modèle à copier :

```markdown
# Inventaire local du lab — pve01

> Rédigé le : À COMPLÉTER — Par : À COMPLÉTER
> Document local, ignoré par git : il décrit mon réseau domestique.

## 1. Proxmox VE
- Version (sortie de `pveversion`) : À COMPLÉTER
- Version de Debian et du noyau : À COMPLÉTER
- Nom du nœud (`<NOEUD>`) : À COMPLÉTER
- Cluster (autonome ou membre d'un cluster) : À COMPLÉTER
- Abonnement : À COMPLÉTER
- Dépôts APT configurés (fichiers et état) : À COMPLÉTER
- Pare-feu Proxmox (datacenter / nœud) : À COMPLÉTER

## 2. Matériel (CPU, RAM)
- CPU (modèle, cœurs/threads, VT-x) : À COMPLÉTER
- RAM totale / utilisée / disponible : À COMPLÉTER
- Virtualisation imbriquée active : À COMPLÉTER

## 3. Disques et stockages
| Disque (/dev/disk/by-id/…) | Taille | Type | Utilisation actuelle (partitions, VG, pool ZFS, montage) | Conclusion |
|---|---|---|---|---|
| À COMPLÉTER | | | | |

| Stockage Proxmox | Type | Support physique | Contenus autorisés | Utilisé / total |
|---|---|---|---|---|
| À COMPLÉTER | | | | |

- Santé des disques (SMART, usure des SSD/NVMe) : À COMPLÉTER

## 4. Réseau
- Interfaces physiques (nom, état, débit) : À COMPLÉTER
- Bridges et leurs ports : À COMPLÉTER
- Adresse IP de pve01, passerelle, DNS : À COMPLÉTER
- LAN maison : sous-réseau, box, plage DHCP de la box : À COMPLÉTER
- Particularités (IPv6, VLANs déjà utilisés, bonding) : À COMPLÉTER

## 5. VMs et conteneurs existants
| VMID | Nom | Type | État | Démarrage auto | RAM | Disques (stockage) | Remarque |
|---|---|---|---|---|---|---|---|
| À COMPLÉTER | | | | | | | |

- VMID en conflit avec les plages du workbook : À COMPLÉTER
- Sauvegardes existantes des VMs perso (où, quand) : À COMPLÉTER

## 6. Ressources libres et contraintes
- RAM utilisable pour le lab : À COMPLÉTER
- Espace libre par stockage : À COMPLÉTER
- Contraintes (VMs à ne jamais arrêter, créneaux de redémarrage possibles…) : À COMPLÉTER

## 7. Valeurs du lab
| Valeur | Ma valeur |
|---|---|
| `<NOEUD>` | À COMPLÉTER |
| `<LAN-MAISON>` | À COMPLÉTER |
| `<IP-BOX>` | À COMPLÉTER |
| `<IP-PVE01>` | À COMPLÉTER |
| `<IP-HP01-LAN>` | À COMPLÉTER |
| `<IP-GW01-WAN>` | à définir en E10 (hors plage DHCP de la box) |
| `<DNS-PUBLIC>` | à définir en E12 |
| `<DNS-AMONT>` | à définir en E13 |
| Stockage `local-nvme` | à définir en E07 |
| Stockage `ssd-lab` | à définir en E07 |
| Stockage `hdd-bulk` | à définir en E07 |
```

**Critères de réussite**
- [ ] `lab/inventaire-local.md` existe, contient les sept sections et plus aucun `À COMPLÉTER`.
- [ ] La sortie de `pveversion` y figure.
- [ ] Chaque disque physique a une conclusion explicite (à préserver / réaffectable).
- [ ] Les VMID occupés sont listés, avec les éventuels conflits.
- [ ] Aucune commande de modification n'a été lancée sur `pve01` pendant l'exercice.

**Vérification** : `lab/bin/check 00 03` (contrôle de forme uniquement : la qualité du contenu s'évalue avec le corrigé).

<details><summary>Indice 1</summary>

Proxmox VE a sa propre famille de commandes (`pveversion`, `pvesm`, `qm`, `pct`, `pvesh`, `pvecm`, `pvesubscription`), mais c'est aussi un Debian : les outils classiques (`lsblk`, `ip`, `lscpu`, `free`, `findmnt`) restent valables. Pour les disques, croise toujours trois vues : le bloc (`lsblk`), le gestionnaire de volumes (LVM ou ZFS) et la configuration Proxmox (`/etc/pve/storage.cfg`).
</details>

<details><summary>Indice 2</summary>

`pvesh get /cluster/resources` donne une vue d'ensemble des VMs, conteneurs et stockages en un seul appel. `lsblk` accepte une liste de colonnes (`-o`) : le numéro de série, le caractère rotatif et le transport (nvme, sata) t'aident à distinguer les trois disques.
</details>

**Pour aller plus loin** (facultatif) : écris un petit script en lecture seule qui régénère les sections 1 à 5 automatiquement. Tu le reprendras au module 02.

---

### M00-E04 — Sauvegarde vérifiée des photos de `hp01`  `LAB` `★`

> **Ticket CHG-104** — *De : Claire Morel* — *Cc : Sophie Laurent*
> Le serveur de PAR2 va être réinstallé en serveur de sauvegarde. Avant ça, on récupère **toutes** les données qu'il contient, et on prouve qu'on les a récupérées intactes : manifeste de sommes de contrôle calculé sur la source, copie, vérification complète sur la destination, rapport archivé.
> Sophie : « Sans manifeste vérifié, pas de réinstallation. Et une seule copie, ce n'est pas une sauvegarde. »

**Objectifs pédagogiques**
- Migrer un volume de données sans perte, avec preuve d'intégrité vérifiable par un tiers.
- Maîtriser `rsync` (préservation des métadonnées, reprise, simulation) et `sha256sum`.
- Appliquer la règle 3-2-1 à un cas concret.

**Prérequis** : E03 (tu sais quels disques de `pve01` sont libres ou utilisés).
**Durée indicative** : 2 h de travail actif, plus le temps de transfert et de calcul des sommes (plusieurs heures pour quelques centaines de Go).

**Contexte technique**

- Destination conventionnelle sur `pve01` : `/mnt/hdd-bulk/sauvegarde-photos-hp01/`, organisée ainsi :
  ```
  /mnt/hdd-bulk/sauvegarde-photos-hp01/
  ├── MANIFEST.sha256              # sommes calculées SUR hp01, avant la copie
  ├── VERIFICATION-<AAAA-MM-JJ>.txt # sortie complète de la vérification sur pve01
  ├── LISEZMOI.txt                 # provenance, date, volumes, autres copies
  └── donnees/                     # les fichiers copiés, arborescence d'origine
  ```
- `/mnt/hdd-bulk` est le point de montage du HDD de `pve01`, qui deviendra le stockage `hdd-bulk` en E07. Si tes photos vont sur un autre support visible depuis `pve01`, adapte le chemin et déclare-le dans `lab/lab.env` (`WB_PHOTOS_DIR=…`).
- Les chemins du manifeste sont **relatifs** à la racine des photos (`./2019/IMG_0001.jpg`), pour être vérifiables depuis `donnees/`.

> ⚠️ **Attention** : pendant tout l'exercice, `hp01` est une **source en lecture seule**. N'utilise jamais `--delete`, `--remove-source-files`, ni un `rsync` dans le sens destination → source. Ne réinstalle pas `hp01` : c'est l'objet de l'E20, et seulement après validation de cet exercice.

**Travail demandé**

1. **État des lieux sur `hp01`.** Identifie le système de `hp01`, l'emplacement exact des photos, leur volume et leur nombre de fichiers. Note-les.
   ```
   root@hp01:~# du -sh <CHEMIN-PHOTOS>
   root@hp01:~# find <CHEMIN-PHOTOS> -type f | wc -l
   ```
   Si `hp01` n'est pas sous Linux (Windows, NAS…), lis l'indice 1 avant de continuer.

2. **Préparer la destination sur `pve01`.** Vérifie l'espace disponible : il faut au moins le volume des photos plus 10 %. Selon ton inventaire :
   - le HDD est **vierge** : crée une partition et un système de fichiers ext4 étiqueté `hdd-bulk`, monte-le sur `/mnt/hdd-bulk` de façon persistante (par UUID, avec l'option `nofail`) ;
   - le HDD **contient déjà des données** : ne le reformate pas ; crée le dossier sur le système de fichiers existant et rends-le accessible sous `/mnt/hdd-bulk` (ou adapte `WB_PHOTOS_DIR`) ;
   - tu utilises **un autre support** : monte-le sur `pve01` et adapte `WB_PHOTOS_DIR`.

   > ⚠️ **Attention** : avant de partitionner le HDD, vérifie sur trois indices indépendants qu'il est vierge (aucune signature avec `wipefs -n`, absent de `pvs`/`zpool status`/`findmnt`, numéro de série conforme à ton inventaire). Un `mkfs` sur le mauvais disque détruit une VM perso.

3. **Figer la source et calculer le manifeste sur `hp01`.** Arrête tout ce qui pourrait modifier les photos (synchronisation, import automatique). Calcule le manifeste **sur la source**, en chemins relatifs, avec un ordre de tri stable, et écris-le **hors** du dossier des photos :
   ```
   root@hp01:~# cd <CHEMIN-PHOTOS>
   root@hp01:<CHEMIN-PHOTOS># find . -type f -print0 | LC_ALL=C sort -z \
       | nice -n 19 ionice -c3 xargs -0 sha256sum > /root/MANIFEST.sha256
   root@hp01:<CHEMIN-PHOTOS># wc -l /root/MANIFEST.sha256
   ```
   Le nombre de lignes doit être égal au nombre de fichiers de l'étape 1.

4. **Copier depuis `pve01`**, dans une session qui survit à une déconnexion (`tmux`), en simulant d'abord :
   ```
   root@pve01:~# tmux new -s photos
   root@pve01:~# rsync -aHAX --numeric-ids --dry-run --itemize-changes \
       root@<IP-HP01-LAN>:<CHEMIN-PHOTOS>/ /mnt/hdd-bulk/sauvegarde-photos-hp01/donnees/ | tail
   root@pve01:~# rsync -aHAX --numeric-ids --partial --info=progress2 \
       root@<IP-HP01-LAN>:<CHEMIN-PHOTOS>/ /mnt/hdd-bulk/sauvegarde-photos-hp01/donnees/
   root@pve01:~# scp root@<IP-HP01-LAN>:/root/MANIFEST.sha256 /mnt/hdd-bulk/sauvegarde-photos-hp01/
   ```
   Explique dans tes notes le rôle de chaque option, et celui de la barre oblique finale de la source.

5. **Vérifier intégralement sur `pve01`** et archiver le rapport :
   ```
   root@pve01:~# cd /mnt/hdd-bulk/sauvegarde-photos-hp01/donnees
   root@pve01:…/donnees# LC_ALL=C sha256sum -c ../MANIFEST.sha256 > ../VERIFICATION-$(date +%F).txt 2>&1; echo "code retour : $?"
   root@pve01:…/donnees# grep -c ': OK$' ../VERIFICATION-*.txt; grep -v ': OK$' ../VERIFICATION-*.txt
   ```
   Puis fais une seconde passe de contrôle indépendante, qui compare source et destination octet par octet sans rien copier :
   ```
   root@pve01:~# rsync -aHAX --checksum --dry-run --itemize-changes \
       root@<IP-HP01-LAN>:<CHEMIN-PHOTOS>/ /mnt/hdd-bulk/sauvegarde-photos-hp01/donnees/
   ```
   Cette commande ne doit rien afficher.

6. **Documenter.** Rédige `LISEZMOI.txt` dans le dossier de sauvegarde : hôte et chemin d'origine, dates de copie et de vérification, nombre de fichiers, volume, commandes utilisées, emplacement des autres copies.

7. **Appliquer la règle 3-2-1.** Avant la réinstallation de `hp01` (E20), il faudra au moins deux copies vérifiées **hors de `hp01`**, dont une hors de `pve01` (disque externe débranché après copie, ou stockage distant chiffré). Réalise cette seconde copie maintenant, ou planifie-la et note la date dans `LISEZMOI.txt`.

**Critères de réussite**
- [ ] `MANIFEST.sha256` a été calculé sur `hp01` avant la copie et se trouve dans le dossier de sauvegarde.
- [ ] Le dernier `VERIFICATION-*.txt` compte autant de lignes `: OK` que le manifeste a de lignes, et aucun échec.
- [ ] Le nombre de fichiers dans `donnees/` est égal au nombre de lignes du manifeste.
- [ ] La passe `rsync --checksum --dry-run` n'affiche aucune différence.
- [ ] `LISEZMOI.txt` existe ; la seconde copie hors de `pve01` est faite ou datée.
- [ ] La sauvegarde ne se trouve pas sur le disque système de `pve01`.
- [ ] Aucun fichier n'a été modifié ni supprimé sur `hp01`.

**Vérification** : `lab/bin/check 00 04` (le contrôle recalcule les sommes d'un échantillon de 200 fichiers ; `WB_PHOTOS_FULLCHECK=1 lab/bin/check 00 04` les recalcule toutes).

<details><summary>Indice 1</summary>

Si `hp01` n'est pas sous Linux : s'il partage les photos en SMB, monte le partage **en lecture seule** sur `pve01` (paquet `cifs-utils`, option `ro`) et fais tourner `sha256sum` puis `rsync` localement sur `pve01`, depuis le point de montage. Les options `-A` et `-X` n'ont alors pas de sens : retire-les. S'il n'y a ni SSH ni partage, démarrer `hp01` sur un système Linux « live » (clé USB) et monter son disque en lecture seule est une solution propre.
</details>

<details><summary>Indice 2</summary>

`rsync` interprète différemment `source/` (le *contenu* du dossier) et `source` (le dossier lui-même). Fais toujours un `--dry-run` et regarde les chemins de destination avant la vraie copie. `tmux attach -t photos` te ramène dans la session si ta connexion SSH coupe.
</details>

<details><summary>Indice 3</summary>

Si `sha256sum -c` signale des fichiers `FAILED` ou introuvables : ne recopie pas tout. Regarde d'abord si ces fichiers ont été modifiés sur la source après le calcul du manifeste (dates de modification), ou si leurs noms contiennent des caractères spéciaux. Puis relance `rsync` (il ne recopie que les différences) et revérifie ces seuls fichiers.
</details>

**Pour aller plus loin** (facultatif) : refais la vérification complète dans six mois (`sha256sum -c`) pour détecter une corruption silencieuse du HDD ; regarde comment `restic` ou `borg` automatisent la règle 3-2-1 avec déduplication et chiffrement.

---

### M00-E05 — Comprendre l'architecture du lab  `Q` `★★`

> **Ticket PLAT-105** — *De : Karim Benali*
> Avant de poser le premier câble virtuel, je veux être sûr que tu as compris l'architecture et ses compromis. Relis l'introduction du module et `PLAN.md` §3-4, puis réponds. On en discutera en revue d'architecture vendredi.

**Objectifs pédagogiques**
- Comprendre les choix d'architecture du socle et leurs conséquences (isolation, chemins de trafic, points uniques de défaillance).
- Savoir justifier un choix technique et en énoncer les limites.

**Prérequis** : lecture de `00-introduction.md` et de `PLAN.md` §3 et §4.
**Durée indicative** : 1 h.

**Travail demandé**

Réponds aux 18 questions, par écrit.

1. Pourquoi `vmbr1` n'a-t-il aucun port physique ? Cite trois conséquences, positives ou négatives.
2. Décris le trajet complet d'une requête HTTPS de `adm01` vers `deb.debian.org` puis de sa réponse : interfaces traversées, étiquettes VLAN, décisions de routage, traduction d'adresse, suivi de connexion.
3. `pve01` envoie un ping à 10.10.20.10. Décris l'aller et le retour. Pourquoi la réponse n'est-elle pas traduite (NAT) par `gw01` ? Que se passerait-il si `pve01` n'avait pas de route vers 10.10.0.0/16 ?
4. Pourquoi les VLANs 31 (STOR-CLU), 32 (COROSYNC) et 51 (OS-TUN) ne sont-ils pas routés ? Qu'est-ce que cela impose aux VMs qui en ont besoin ?
5. Le VLAN 41 (K8S-LB) n'a pas non plus de sous-interface sur `gw01`, mais pour une autre raison. Laquelle ? Comment `gw01` saura-t-il joindre ces adresses plus tard ?
6. *(QCM, plusieurs réponses possibles)* `gw01` s'arrête. Qu'est-ce qui continue de fonctionner ?
   - A. `adm01` joint `dns01`
   - B. Deux VMs du VLAN 40 communiquent entre elles
   - C. `pve01` se connecte en SSH à `adm01`
   - D. Les sauvegardes de `pve01` vers `pbs01` aboutissent
   - E. L'interface web de `pve01` reste accessible depuis ton poste
7. Pourquoi un routeur Debian + nftables construit à la main plutôt qu'une appliance (OPNsense, pfSense) ? Donne deux avantages et deux inconvénients. Que ferait MédiSphère en production ?
8. Liste les points uniques de défaillance (SPOF) du socle tel qu'il sera à la fin du module 00. Pour chacun, indique le module du workbook où il pourra être atténué, ou pourquoi on l'accepte.
9. À quoi servent les plages de VMID (1000-1099, 2000-3999, 5000-5999, 9000-9099) ? Que vérifies-tu avant de créer la VM 5001 ?
10. Pourquoi un pool `lab` et des comptes `wb-admin@pve` / `wb-automation@pve` plutôt que `root@pam` pour tout ? Raisonne en « rayon d'impact » (*blast radius*).
11. Le trafic de sauvegarde de `pve01` vers `pbs01` passe par `gw01` et le tunnel `wg0`, alors que les deux machines sont sur le même LAN. Pourquoi ce choix ? Quels en sont les coûts ?
12. L'interface `wg0` a une MTU inférieure à 1500. Pourquoi ? Quels symptômes apparaîtraient si cette différence était mal gérée, et où la traiter ?
13. Pourquoi un DNS provisoire (dnsmasq) au module 00, remplacé par PowerDNS au module 06, plutôt que PowerDNS tout de suite ? Pourquoi le domaine `medisphere.internal` plutôt que `medisphere.local` ou `medisphere.lan` ?
14. Pourquoi les VMs se synchronisent-elles sur la passerelle de leur VLAN plutôt que directement sur des serveurs NTP d'Internet ?
15. Pour atteindre le lab depuis ton poste, compare une route statique (sur ta box ou ton poste) vers 10.10.0.0/16 et le VPN d'administration `wg1`.
16. Le socle consomme environ 24 Go de RAM et un profil lourd jusqu'à 80 Go, sur 128 Go. Pourquoi la règle « un seul profil lourd à la fois » ? Quels mécanismes (ballooning, KSM, cache ARC de ZFS, swap) peuvent te donner une fausse impression de marge ?
17. Toutes les VMs du workbook viennent du template cloud-init, sauf `gw01`, installé à la main depuis l'ISO. Pourquoi cette exception ?
18. Que faut-il sauvegarder pour pouvoir reconstruire le socle après la perte totale de `pve01` ? Classe les éléments en « reconstructible par code » et « à sauvegarder ».

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 18 questions avant d'ouvrir le corrigé.
- [ ] Pour chaque question où ta réponse diffère du corrigé, tu sais expliquer l'écart.
- [ ] Ta liste de SPOF (question 8) est reportée dans tes notes : tu la compléteras au fil des modules.

<details><summary>Indice 1</summary>

Pour les questions de chemin (2, 3, 6), dessine le schéma de l'introduction et suis le paquet avec ton doigt, un saut à la fois : à chaque équipement, demande-toi « quelle table de routage, quelle règle de filtrage, quelle traduction ? ».
</details>

<details><summary>Indice 2</summary>

Une architecture de lab est un compromis entre réalisme, simplicité et ressources. Pour les questions « pourquoi », cherche ce que le choix permet d'**apprendre** autant que ce qu'il permet de **faire**.
</details>

---

### M00-E06 — Préparer `pve01` (dépôts, mises à jour, virtualisation imbriquée)  `LAB` `★`

> **Ticket PLAT-106** — *De : Karim Benali*
> L'hyperviseur n'a pas été mis à jour depuis le départ d'InfoGér et pointe sur le dépôt *enterprise* sans abonnement : `apt update` échoue. Remets les dépôts d'aplomb, applique les mises à jour, et active la virtualisation imbriquée : on en aura besoin pour le cluster Proxmox imbriqué (module 09) et OpenStack (module 10).
> Si l'hôte est encore en 8.x, ne le monte pas en 9 aujourd'hui : fais-moi un plan de montée de version.

**Objectifs pédagogiques**
- Configurer les dépôts Proxmox VE (format deb822 en PVE 9, `.list` en PVE 8).
- Appliquer des mises à jour sur un hyperviseur en production, en maîtrisant l'impact.
- Activer et vérifier la virtualisation imbriquée de façon persistante.

**Prérequis** : E03.
**Durée indicative** : 1 h (hors redémarrage).

**Contexte technique**

| Version de `pve01` | Base Debian | Format des dépôts | Fichiers concernés |
|---|---|---|---|
| Proxmox VE 9.x (référence) | 13 trixie | deb822 (`.sources`) | `/etc/apt/sources.list.d/*.sources` |
| Proxmox VE 8.x | 12 bookworm | une ligne par dépôt (`.list`) | `/etc/apt/sources.list`, `/etc/apt/sources.list.d/*.list` |

Sans abonnement, le dépôt à utiliser est `pve-no-subscription`. Le dépôt Ceph *enterprise* éventuellement présent doit, lui aussi, être désactivé ou remplacé par son équivalent *no-subscription*.

> ⚠️ **Attention** : une mise à jour peut installer un nouveau noyau ou redémarrer des services de virtualisation. Lis la liste des paquets avant de valider. Si des VMs perso tournent, choisis le moment du redémarrage et sauvegarde-les avant.

**Travail demandé**

1. Relève la version exacte :
   ```
   root@pve01:~# pveversion -v | head -n 5
   root@pve01:~# grep VERSION_CODENAME /etc/os-release
   ```
2. Inspecte les dépôts configurés et leur état :
   ```
   root@pve01:~# ls -l /etc/apt/sources.list /etc/apt/sources.list.d/
   root@pve01:~# apt update
   ```
   Repère les dépôts en erreur (`401 Unauthorized` sur `enterprise.proxmox.com`).
3. Désactive le ou les dépôts *enterprise* et active `pve-no-subscription`, **dans le format de ta version** :
   - en PVE 9 : un dépôt deb822 se désactive par une ligne `Enabled: no` dans sa strophe ; le dépôt *no-subscription* se déclare dans `/etc/apt/sources.list.d/proxmox.sources` ;
   - en PVE 8 : commente la ligne `deb` du dépôt *enterprise* et ajoute une ligne `deb` pour `pve-no-subscription`.

   L'interface web (*Nœud → Updates → Repositories*) fait la même chose : utilise-la pour contrôler ton résultat.
4. Relance `apt update` : aucune erreur ne doit subsister. Liste les mises à jour (`apt list --upgradable`), puis applique-les avec `apt full-upgrade`. Note si un nouveau noyau a été installé et planifie le redémarrage.
5. Vérifie que le nom du nœud se résout vers son adresse du LAN (et non `127.0.1.1`), exigence de Proxmox VE :
   ```
   root@pve01:~# hostname --ip-address
   root@pve01:~# grep "$(hostname)" /etc/hosts
   ```
6. Vérifie la virtualisation imbriquée et rends-la persistante :
   ```
   root@pve01:~# grep -c -w vmx /proc/cpuinfo
   root@pve01:~# cat /sys/module/kvm_intel/parameters/nested
   ```
   Crée `/etc/modprobe.d/kvm-intel.conf` avec l'option `nested=Y` du module `kvm_intel`, même si la valeur courante est déjà `Y`. Si elle valait `N`, la nouvelle valeur ne s'appliquera qu'au rechargement du module, c'est-à-dire, en pratique, au prochain redémarrage.
7. Vérifie que `pve01` est à l'heure (`chronyc tracking`).
8. **Si `pve01` est en 8.x** : lance `pve8to9 --full`, lis chaque avertissement, et rédige dans ton inventaire un plan de montée de version (prérequis, sauvegardes, étapes, retour arrière, créneau). Ne l'exécute pas dans cet exercice.

**Critères de réussite**
- [ ] `apt update` se termine sans erreur ; aucun dépôt *enterprise* n'est actif sans abonnement.
- [ ] Le dépôt `pve-no-subscription` (ou *enterprise* avec abonnement) est connu d'APT.
- [ ] Les mises à jour sont appliquées et le redémarrage éventuel est fait ou planifié.
- [ ] `/sys/module/kvm_intel/parameters/nested` vaut `Y` et l'option est persistante dans `/etc/modprobe.d/`.
- [ ] Le nom du nœud se résout vers une adresse non *loopback*.
- [ ] Si `pve01` est en 8.x : la sortie de `pve8to9 --full` est analysée et le plan de montée de version rédigé.

**Vérification** : `lab/bin/check 00 06`

<details><summary>Indice 1</summary>

En deb822, un fichier `.sources` contient une ou plusieurs strophes séparées par une ligne vide ; chaque strophe a des champs `Types:`, `URIs:`, `Suites:`, `Components:`, `Signed-By:`. Compare avec le fichier `pve-enterprise.sources` existant : le dépôt *no-subscription* n'en diffère que par deux champs.
</details>

<details><summary>Indice 2</summary>

La syntaxe d'un fichier de `modprobe.d` est décrite dans `man modprobe.d` : une ligne `options <module> <paramètre>=<valeur>`. Le module s'écrit `kvm_intel` ou `kvm-intel`, les deux formes sont acceptées.
</details>

**Pour aller plus loin** (facultatif) : en PVE 9, `apt modernize-sources` convertit d'anciens fichiers `.list` au format deb822. Lis sa page de manuel et compare son résultat avec ta configuration.

---

### M00-E07 — Organiser les stockages sans rien casser  `LAB` `★★`

> **Ticket PLAT-107** — *De : Karim Benali*
> Tous les modules du workbook supposent trois stockages Proxmox aux noms stables : `local-nvme` pour les disques système des VMs, `ssd-lab` pour ce qui est gourmand en I/O (OSD Ceph virtuels, bases), `hdd-bulk` pour les ISO, snippets, imports et sauvegardes locales.
> Fais-les correspondre à l'existant. Règle absolue : on ne reformate pas un disque qui porte des données, et on ne déclare jamais deux fois le même support sous deux noms.

**Objectifs pédagogiques**
- Identifier sans ambiguïté les disques et leur usage (bloc, LVM, ZFS, montages, configuration Proxmox).
- Choisir un type de stockage Proxmox selon l'usage (LVM-thin, ZFS, répertoire) et le justifier.
- Créer ou déclarer des stockages en ligne de commande, de façon non destructive.

**Prérequis** : E03, E04 validé si tes photos sont sur le HDD, E06.
**Durée indicative** : 1 h 30 à 2 h.

**Contexte technique**

| Nom logique | Support | Contenus attendus | Usage |
|---|---|---|---|
| `local-nvme` | NVMe | `images` (et `rootdir`) | Disques système des VMs, template |
| `ssd-lab` | SSD | `images` (et `rootdir`) | OSD Ceph virtuels, VMs intensives en I/O |
| `hdd-bulk` | HDD, monté sur `/mnt/hdd-bulk` | `iso`, `snippets`, `backup`, `import` (et `vztmpl`, `images`) | ISO, snippets cloud-init, images à importer, sauvegardes locales, disques volumineux peu sollicités (MinIO) |

Si un nom logique ne peut pas être créé sans risque (par exemple, le NVMe est entièrement occupé par le *thin pool* `local-lvm` qui porte tes VMs perso), garde le stockage existant, déclare la correspondance dans `lab/lab.env` (`WB_STORAGE_NVME=local-lvm`) et dans la section 7 de ton inventaire.

> ⚠️ **Attention** : `wipefs -a`, `sgdisk --zap-all`, `pvcreate`, `zpool create` et `mkfs` détruisent les données du disque visé. Avant toute commande de ce type, applique la **règle des trois preuves** : (1) `wipefs -n` ne montre aucune signature ; (2) le disque n'apparaît ni dans `pvs`, ni dans `zpool status`, ni dans `findmnt`, ni dans `/etc/pve/storage.cfg` ; (3) son numéro de série (`/dev/disk/by-id/`) correspond à celui noté comme « réaffectable » dans ton inventaire. Désigne toujours les disques par leur chemin `/dev/disk/by-id/…`, jamais par `/dev/sdX`, dont l'ordre peut changer d'un démarrage à l'autre.

**Travail demandé**

1. Établis la carte complète des disques et de leur usage :
   ```
   root@pve01:~# lsblk -o NAME,SIZE,TYPE,ROTA,TRAN,MODEL,SERIAL,FSTYPE,MOUNTPOINTS
   root@pve01:~# ls -l /dev/disk/by-id/ | grep -v -e part -e wwn-
   root@pve01:~# pvs; vgs; lvs
   root@pve01:~# zpool status; zfs list
   root@pve01:~# pvesm status; cat /etc/pve/storage.cfg
   ```
2. Pour chacun des trois supports, place-toi dans l'un des cas suivants et décide :
   - **support déjà utilisé par un stockage Proxmox** : réutilise-le sans le reformater. Selon la technologie, tu peux soit y créer un espace dédié au lab (un *dataset* ZFS, un nouveau *thin pool* dans l'espace libre d'un groupe de volumes), soit garder le stockage existant et faire la correspondance de nom ;
   - **support vierge** : choisis la technologie (LVM-thin, ZFS ou répertoire) selon l'usage du tableau ci-dessus, et écris ta justification en trois lignes dans l'inventaire ;
   - **support utilisé hors Proxmox** (données) : ne le touche pas ; réserve-lui l'usage `hdd-bulk` si c'est un système de fichiers monté, sinon documente la contrainte.
3. Crée ou déclare les trois stockages avec `pvesm` (pas avec l'interface web : tu dois savoir le faire en ligne de commande). Pour `hdd-bulk` en type répertoire, Proxmox doit considérer le stockage hors ligne si le disque n'est pas monté.
4. Vérifie que les trois stockages sont actifs et ont les bons contenus, et qu'aucun support n'est déclaré deux fois.
5. Mets à jour la section 3 et la section 7 de ton inventaire (correspondance des noms, justification des choix).

**Critères de réussite**
- [ ] `pvesm status` montre `local-nvme`, `ssd-lab` et `hdd-bulk` (ou leurs équivalents déclarés dans `lab/lab.env`) à l'état `active`.
- [ ] `local-nvme` et `ssd-lab` acceptent le contenu `images` ; `hdd-bulk` accepte au moins `iso`, `snippets`, `backup` et `import`.
- [ ] Si `hdd-bulk` est de type répertoire, il est déclaré comme point de montage externe.
- [ ] Aucun support n'est déclaré sous deux noms de stockage différents.
- [ ] Les VMs perso démarrent et fonctionnent comme avant ; aucun disque portant des données n'a été reformaté.
- [ ] L'inventaire documente les choix et la correspondance des noms.

**Vérification** : `lab/bin/check 00 07`

<details><summary>Indice 1</summary>

Une installation par défaut de Proxmox VE crée soit un groupe de volumes `pve` avec un *thin pool* `data` (stockage `local-lvm`), soit un pool ZFS `rpool` avec un *dataset* `rpool/data` (stockage `local-zfs`). Dans le second cas, un *dataset* supplémentaire suffit pour un stockage dédié au lab. Dans le premier, regarde la colonne `VFree` de `vgs`.
</details>

<details><summary>Indice 2</summary>

`pvesm add <type> <nom> …` : les options dépendent du type (`man pvesm`, section *STORAGE TYPES* et options `--vgname`, `--thinpool`, `--pool`, `--path`, `--content`, `--is_mountpoint`). La documentation Proxmox avertit explicitement contre deux configurations de stockage pointant sur le même support : deux identifiants de volume différents désigneraient la même image disque.
</details>

<details><summary>Indice 3</summary>

Pour choisir entre LVM-thin et ZFS sur un SSD unique destiné à porter des disques de VMs qui feront elles-mêmes tourner Ceph : pense au surcoût d'écriture (copy-on-write sur copy-on-write), à la consommation de RAM du cache ARC et à ce que tu gagnes réellement sans redondance.
</details>

**Pour aller plus loin** (facultatif) : mets en place la surveillance du remplissage des *thin pools* (`lvs -o+data_percent,metadata_percent`) et lis la section *Thin Provisioning* de `man lvmthin` sur l'extension automatique.

---

### M00-E08 — Pool, utilisateurs, groupes et rôles  `LAB` `★`

> **Ticket SEC-108** — *De : Sophie Laurent*
> Personne n'administre le lab en `root@pam`. Je veux des comptes nominatifs dans un groupe, des droits limités à un pool dédié, et rien sur le reste de l'hyperviseur. L'audit HDS nous demandera qui a fait quoi : un compte partagé `root`, c'est un constat d'écart.

**Objectifs pédagogiques**
- Comprendre le modèle de permissions de Proxmox VE : chemins, rôles, privilèges, propagation, groupes, pools.
- Créer un pool, un groupe et un utilisateur, et leur accorder le moindre privilège.
- Vérifier les droits effectifs d'un utilisateur.

**Prérequis** : E07 (les stockages existent).
**Durée indicative** : 45 min.

**Contexte technique**

| Objet | Valeur |
|---|---|
| Pool | `lab`, commentaire « Workbook MédiSphère » |
| Groupe | `wb-admins` |
| Utilisateur humain | `wb-admin@pve` (royaume Proxmox VE), membre de `wb-admins` |
| Droits sur le pool | rôle `PVEAdmin` sur `/pool/lab` pour le groupe |
| Droits sur les stockages | rôle `PVEDatastoreUser` sur `/storage/<stockage>` pour chacun des trois stockages du lab |
| Droits ailleurs | aucun (en particulier, rien sur `/`) |

Le compte d'automatisation `wb-automation@pve` et son jeton seront créés en E17. Le droit d'utiliser le bridge `vmbr1` sera accordé en E09, une fois le bridge créé.

**Travail demandé**

1. Crée le pool, le groupe et l'utilisateur, avec un mot de passe robuste :
   ```
   root@pve01:~# pveum pool add lab --comment "Workbook MédiSphère"
   root@pve01:~# pveum group add wb-admins --comment "Administrateurs du lab"
   root@pve01:~# pveum user add wb-admin@pve --groups wb-admins --comment "<TON-NOM>"
   root@pve01:~# pveum passwd wb-admin@pve
   ```
2. Accorde les droits au **groupe** (jamais directement à l'utilisateur) :
   ```
   root@pve01:~# pveum acl modify /pool/lab --groups wb-admins --roles PVEAdmin
   root@pve01:~# pveum acl modify /storage/local-nvme --groups wb-admins --roles PVEDatastoreUser
   ```
   Fais de même pour `ssd-lab` et `hdd-bulk` (ou leurs équivalents).
3. Liste les privilèges contenus dans `PVEAdmin` et `PVEDatastoreUser` (`pveum role list`). Explique dans tes notes pourquoi on n'a pas simplement ajouté les stockages au pool.
4. Vérifie les droits effectifs :
   ```
   root@pve01:~# pveum user permissions wb-admin@pve --path /pool/lab
   root@pve01:~# pveum user permissions wb-admin@pve --path /
   ```
5. Connecte-toi à l'interface web avec `wb-admin` (royaume *Proxmox VE authentication server*). Que vois-tu ? Que ne vois-tu pas ? Vérifie en particulier que tes VMs perso sont invisibles.

**Critères de réussite**
- [ ] Le pool `lab`, le groupe `wb-admins` et l'utilisateur actif `wb-admin@pve` (membre du groupe) existent.
- [ ] Le groupe a `PVEAdmin` sur `/pool/lab` et `PVEDatastoreUser` sur chacun des trois stockages du lab.
- [ ] `wb-admin@pve` n'a aucune permission sur `/` et ne voit pas les VMs perso.
- [ ] `wb-admin@pve` a le privilège `VM.Allocate` sur `/pool/lab`.

**Vérification** : `lab/bin/check 00 08`

<details><summary>Indice 1</summary>

Les permissions Proxmox se lisent « sur tel chemin, tel utilisateur ou groupe a tel rôle, propagé ou non vers les sous-chemins ». Les membres d'un pool (VMs et stockages) héritent des droits posés sur `/pool/<nom>`.
</details>

<details><summary>Indice 2</summary>

Compare les privilèges `Datastore.Allocate` et `Datastore.AllocateSpace` dans la documentation (`pveum`, section *Privileges*) : l'un permet de supprimer n'importe quel volume du stockage, l'autre seulement d'y allouer de l'espace.
</details>

**Pour aller plus loin** (facultatif) : active un second facteur TOTP pour `wb-admin@pve` depuis l'interface web (*Datacenter → Permissions → Two Factor*), puis vérifie qu'il est exigé à la connexion.

---

### M00-E09 — Créer le bridge du lab `vmbr1`  `LAB` `★★`

> **Ticket PLAT-109** — *De : Karim Benali*
> Le lab a besoin de son propre segment de niveau 2, qui porte tous les VLANs du plan d'adressage et qui ne touche **jamais** le LAN maison. Crée `vmbr1` : bridge VLAN-aware, sans port physique. Et ne coupe pas l'accès à l'hyperviseur en le faisant.

**Objectifs pédagogiques**
- Comprendre le bridge Linux VLAN-aware tel que l'utilise Proxmox VE.
- Modifier la configuration réseau d'un hyperviseur en production avec un filet de sécurité.
- Accorder le droit d'utiliser un bridge à un groupe.

**Prérequis** : E08.
**Durée indicative** : 45 min.

**Contexte technique**

| Paramètre | Valeur |
|---|---|
| Nom | `vmbr1` |
| Ports physiques | aucun |
| VLAN-aware | oui, VLANs 2 à 4094 autorisés |
| Adresse IP sur `pve01` | aucune (`pve01` ne doit pas être présent dans les VLANs du lab) |
| STP | désactivé |
| Commentaire | « Lab MédiSphère — VLANs du workbook » |
| Droit d'usage | rôle `PVESDNUser` pour le groupe `wb-admins` sur `/sdn/zones/localnetwork/vmbr1` |

Proxmox VE utilise *ifupdown2* : `ifreload -a` applique les changements de `/etc/network/interfaces` sans redémarrer. L'interface web écrit dans `/etc/network/interfaces.new` puis applique ce fichier.

> ⚠️ **Attention** : une erreur sur `vmbr0` te coupe de `pve01` (web et SSH). Ne modifie **que** la strophe de `vmbr1`, garde un accès console, et pose un filet de sécurité avant d'appliquer.

**Travail demandé**

1. Sauvegarde la configuration et programme un retour arrière automatique dans 10 minutes :
   ```
   root@pve01:~# cp -a /etc/network/interfaces /root/interfaces.avant-vmbr1
   root@pve01:~# systemd-run --on-active=10min --unit=retour-reseau \
       /bin/sh -c 'cp /root/interfaces.avant-vmbr1 /etc/network/interfaces && ifreload -a'
   ```
2. Ajoute la strophe de `vmbr1` dans `/etc/network/interfaces` selon le tableau ci-dessus (ou utilise l'API : `pvesh create /nodes/<NOEUD>/network …`, puis `pvesh set /nodes/<NOEUD>/network` pour appliquer).
3. Applique avec `ifreload -a`, vérifie que tu as toujours accès à `pve01`, puis annule le retour arrière :
   ```
   root@pve01:~# systemctl stop retour-reseau.timer
   ```
4. Vérifie l'état du bridge dans le noyau :
   ```
   root@pve01:~# ip -d link show vmbr1
   root@pve01:~# bridge vlan show dev vmbr1
   root@pve01:~# ip link show master vmbr1
   ```
5. Accorde au groupe `wb-admins` le droit d'utiliser `vmbr1` (voir tableau). Vérifie dans l'interface web, *Datacenter → Permissions → Add*, que le chemin proposé correspond.

**Critères de réussite**
- [ ] `vmbr1` existe, VLAN-aware (`vlan_filtering 1`), sans port physique et sans adresse IP.
- [ ] La strophe est persistante : `ifquery vmbr1` montre `bridge-vlan-aware yes`, `bridge-ports none` et `bridge-vids 2-4094`.
- [ ] `vmbr0` et l'accès à `pve01` sont intacts ; le retour arrière programmé est annulé.
- [ ] Le groupe `wb-admins` a `PVESDNUser` sur `/sdn/zones/localnetwork/vmbr1`.

**Vérification** : `lab/bin/check 00 09`

<details><summary>Indice 1</summary>

Inspire-toi de la strophe de `vmbr0` : même structure (`auto`, `iface … inet manual`, options `bridge-…`), mais sans port ni adresse. `man interfaces` (fourni par ifupdown2) et `ifquery --help` t'aident à valider la syntaxe.
</details>

<details><summary>Indice 2</summary>

`ifquery --check vmbr1` compare l'état réel de l'interface avec ce que décrit la configuration : pratique pour vérifier qu'`ifreload` a bien tout appliqué.
</details>

**Pour aller plus loin** (facultatif) : compare avec un bridge non VLAN-aware : quand une VM a un `tag` sur un tel bridge, Proxmox crée à la volée une sous-interface VLAN et un bridge par VLAN. Pourquoi le modèle VLAN-aware est-il préférable avec 13 VLANs ?

---

### M00-E10 — Construire le routeur/pare-feu `gw01`  `LAB` `★★`

> **Ticket PLAT-110** — *De : Karim Benali* — *Cc : Sophie Laurent*
> Il nous faut le routeur du lab : une VM Debian minimale, une patte sur le LAN maison, un trunk vers `vmbr1`, une passerelle par VLAN routé, du NAT vers l'extérieur et un filtrage strict. Sophie a fixé la matrice des flux ci-dessous ; tout ce qui n'y est pas est interdit et journalisé.
> C'est la seule VM qu'on installe à la main : profites-en pour comprendre chaque fichier.

**Objectifs pédagogiques**
- Créer une VM en ligne de commande (`qm`) et installer Debian depuis l'ISO.
- Configurer un routeur Linux : sous-interfaces VLAN, routage, *sysctl*.
- Écrire un pare-feu nftables à états, lisible et commenté, avec NAT sortant.
- Rendre le lab joignable depuis `pve01` par une route statique persistante.

**Prérequis** : E07, E08, E09.
**Durée indicative** : 3 à 4 h.

**Contexte technique**

*La VM*

| Paramètre | Valeur |
|---|---|
| VMID / nom | 1000 / `gw01` |
| Pool, étiquettes | `lab` ; `socle`, `reseau` |
| Système | Debian 13 « trixie », ISO *netinst* officielle, installation minimale (serveur SSH et utilitaires usuels) |
| Ressources | 1 vCPU, 2 Go de RAM (1 Go suffit), disque de 16 Go sur `local-nvme` |
| Contrôleur disque | VirtIO SCSI single |
| `net0` | VirtIO sur `vmbr0` → `ens18` (WAN) |
| `net1` | VirtIO sur `vmbr1`, **sans tag** (trunk) → `ens19` |
| Démarrage | automatique avec `pve01`, en premier (`order=1`) |
| Agent QEMU | activé (paquet `qemu-guest-agent` dans la VM) |
| Nom complet | `gw01.par1.medisphere.internal` |
| Compte | `admin`, membre de `sudo`, `sudo` sans mot de passe (convention du lab) ; connexion SSH par clé uniquement |

*Adressage*

| Interface | Adresse |
|---|---|
| `ens18` | `<IP-GW01-WAN>` fixe, choisie **hors de la plage DHCP** de ta box ; passerelle `<IP-BOX>` |
| `ens19` | aucune (interface parente du trunk) |
| `ens19.<VLAN>` pour 10, 20, 30, 40, 50, 52, 60, 70, 99 | `10.10.<VLAN>.1/24` |
| VLANs 31, 32, 41, 51 | **pas** de sous-interface |

*Fichiers imposés (les checks et les exercices suivants s'y réfèrent)*

| Rôle | Fichier |
|---|---|
| Réseau | `/etc/network/interfaces` (ifupdown, prise en charge native des VLANs) |
| Routage | `/etc/sysctl.d/99-routeur.conf` |
| Pare-feu | `/etc/nftables.conf` : table `inet filter` (chaînes `input`, `forward`, `output`) et table `ip nat` (chaîne `postrouting`) ; politique `drop` en `input` et `forward` |
| Droits d'administration | `/etc/sudoers.d/90-workbook` |

*Matrice des flux (SEC-110, Sophie Laurent)*

| # | Source | Destination | Décision |
|---|---|---|---|
| 1 | Tout | Paquets d'une connexion établie ou liée | autoriser (paquets « invalides » : rejeter) |
| 2 | LAN maison (`<LAN-MAISON>`) | `gw01` en SSH | autoriser |
| 3 | VLAN MGMT (10) | `gw01` en SSH | autoriser |
| 4 | Tout | `gw01` en ICMP (ping et messages d'erreur, débit limité) ; ICMPv6 nécessaire au fonctionnement d'IPv6 sur le WAN | autoriser |
| 5 | VLAN MGMT (10) | Tous les VLANs routés | autoriser |
| 6 | VLAN MGMT (10) | `pve01` (`<IP-PVE01>`) en SSH (22) et API/web (8006) | autoriser |
| 7 | LAN maison | VLANs routés, en SSH uniquement | autoriser — **provisoire** : remplacé par le VPN d'administration en E16 |
| 8 | VLAN MGMT et `pve01` | VLANs routés, ping (*echo-request*) | autoriser |
| 9 | VLANs routés | Internet (tout sauf le LAN maison), avec traduction d'adresse | autoriser |
| 10 | Tout le reste : entre VLANs, du lab vers le LAN maison, IPv6 traversant | | **interdire** |
| 11 | Tout refus (`input` et `forward`) | | journaliser avec limitation de débit, compter |

Traduction d'adresse : le trafic du lab qui sort par `ens18` est masqué derrière `<IP-GW01-WAN>`, **sauf** celui destiné à `pve01`, qui a une route de retour vers le lab : il voit ainsi les vraies adresses sources (utile à son pare-feu, E27).

Les services que `gw01` rendra plus tard (DNS vers `dns01` en E13, relais DHCP en E14, WireGuard en E16 et E21, NTP en E31) ajouteront leurs propres règles : n'anticipe pas.

*Accès depuis `pve01`*

- `pve01` joint le lab par une **route statique persistante** vers 10.10.0.0/16 via `<IP-GW01-WAN>` (et vers 10.20.0.0/16, qui servira en E21, et 10.255.1.0/24, le futur VPN d'administration de E16), déclarée dans `/etc/network/interfaces` de `pve01`.
- `pve01` se connecte à `gw01` en SSH avec une clé dédiée `/root/.ssh/id_ed25519_lab` et un alias `gw01` dans `/root/.ssh/config` (utilisateur `admin`, adresse `<IP-GW01-WAN>`). Les checks utilisent cet alias.

**Travail demandé**

1. **Choisis `<IP-GW01-WAN>`** : une adresse libre de ton LAN, hors de la plage DHCP de la box (vérifie qu'elle ne répond pas au ping et n'apparaît pas dans la liste des baux de la box). Reporte-la dans ton inventaire.
2. **Télécharge l'ISO** Debian 13 *netinst* sur `hdd-bulk` et vérifie sa somme SHA-512 avec le fichier `SHA512SUMS` publié par Debian.
3. **Crée la VM 1000** avec `qm create`, conformément au tableau. Construis la commande toi-même à partir de `qm help create` ; garde-la dans tes notes.
4. **Installe Debian** depuis la console noVNC : nom `gw01`, domaine `par1.medisphere.internal`, interface principale `ens18` (l'installateur peut utiliser le DHCP de ta box), pas de mot de passe root (le premier utilisateur reçoit alors `sudo`), utilisateur `admin`, uniquement « serveur SSH » et « utilitaires usuels du système ».
5. **Post-installation** : installe `qemu-guest-agent` et `nftables` ; configure `sudo` sans mot de passe pour `admin` dans `/etc/sudoers.d/90-workbook` (nom imposé ; c'est le seul endroit où ce fichier est créé, E15 y reviendra seulement pour discuter la politique) ; génère la clé dédiée sur `pve01`, installe-la dans le compte `admin` de `gw01`, crée l'alias `gw01` sur `pve01`, puis interdis l'authentification SSH par mot de passe sur `gw01`.
6. **Réseau de `gw01`** : écris `/etc/network/interfaces` (adresse fixe sur `ens18`, trunk `ens19`, les neuf sous-interfaces). Applique depuis la **console** (pas depuis une session SSH qui passe par l'interface que tu modifies).
7. **Routage** : active le routage IPv4 de façon persistante dans `/etc/sysctl.d/99-routeur.conf`, avec les réglages qu'un routeur doit avoir (redirections ICMP, filtrage par chemin inverse). Justifie chaque ligne en commentaire.
8. **Pare-feu** : écris `/etc/nftables.conf` qui implémente la matrice. Exigences de forme : variables (`define`) pour les interfaces et réseaux, une règle par ligne de la matrice avec le numéro en commentaire, compteurs sur les refus. Avant de l'appliquer, vérifie la syntaxe et programme un filet de sécurité (vidage automatique des règles dans 5 minutes) ; puis active le service `nftables`.
9. **Route sur `pve01`** : ajoute les routes vers 10.10.0.0/16, 10.20.0.0/16 et 10.255.1.0/24 via `<IP-GW01-WAN>` dans la strophe de `vmbr0`, de façon persistante, et applique-les.
   > ⚠️ **Attention** : c'est la seule modification de la strophe de `vmbr0` du module, l'interface qui porte l'accès à `pve01` **et** le réseau de tes VMs perso. N'ajoute que des lignes, sans toucher à l'adresse, à la passerelle ni à `bridge-ports` ; vérifie l'absence de `/etc/network/interfaces.new` ; pose le même filet de sécurité qu'en E09 (copie du fichier et retour arrière programmé) et garde la console ouverte avant `ifreload -a`.
10. **Teste** : depuis `pve01`, ping de 10.10.10.1 et 10.10.99.1, SSH `gw01` ; depuis `gw01`, accès à Internet ; compteurs nftables qui bougent sur les refus.

**Critères de réussite**
- [ ] La VM 1000 `gw01` est dans le pool `lab`, démarre avec `pve01`, `net0` sur `vmbr0` et `net1` sur `vmbr1` sans tag ; l'agent QEMU répond.
- [ ] `ssh gw01` fonctionne depuis `pve01` avec la clé dédiée ; `sudo -n true` réussit ; l'authentification par mot de passe est refusée.
- [ ] Les neuf sous-interfaces portent `10.10.<VLAN>.1/24` et sont persistantes ; aucune interface pour les VLANs 31, 32, 41, 51.
- [ ] `net.ipv4.ip_forward = 1`, persistant dans `/etc/sysctl.d/99-routeur.conf`.
- [ ] `nftables` est actif et activé au démarrage ; `/etc/nftables.conf` est valide ; politiques `drop` en `input` et `forward` ; `masquerade` en sortie de `ens18`.
- [ ] `pve01` a une route persistante vers 10.10.0.0/16 via `gw01` et joint 10.10.10.1.
- [ ] `gw01` joint Internet.

**Vérification** : `lab/bin/check 00 10`

<details><summary>Indice 1</summary>

Pour `qm create`, les options utiles sont `--name`, `--pool`, `--tags`, `--ostype`, `--cores`, `--memory`, `--scsihw`, `--scsi0` (syntaxe `<stockage>:<taille en Go>`), `--ide2` (ISO, `media=cdrom`), `--boot`, `--net0`/`--net1` (`virtio,bridge=…`), `--agent`, `--onboot`, `--startup`. Garde le type de machine par défaut : c'est lui qui donne les noms `ens18` et `ens19` dans la VM.
</details>

<details><summary>Indice 2</summary>

Dans `/etc/network/interfaces`, une interface nommée `ens19.20` est automatiquement configurée comme sous-interface VLAN 20 de `ens19` (voir `man interfaces`, section *VLAN AND BRIDGE INTERFACES*). L'interface parente se déclare en méthode `manual`. Pour nftables, structure ta chaîne `forward` du plus spécifique au plus général : l'ordre des règles est l'ordre d'évaluation, et la première décision (`accept`/`drop`) l'emporte.
</details>

<details><summary>Indice 3</summary>

Méfie-toi d'une règle `limit rate … log … drop` : quand la limite est dépassée, la règle ne correspond plus du tout, le paquet n'est donc **pas** rejeté par elle et continue vers la règle suivante. Sépare la journalisation (limitée) de la décision. Filet de sécurité : `systemd-run --on-active=5min /usr/sbin/nft flush ruleset`. Route persistante sur `pve01` : une ligne `up ip route replace …` dans la strophe de `vmbr0`.
</details>

**Pour aller plus loin** (facultatif) : ajoute une console série à `gw01` (`qm set 1000 --serial0 socket` et `console=ttyS0` dans GRUB) pour pouvoir le dépanner avec `qm terminal 1000` même quand son réseau est cassé ; restreins les VLANs visibles par `net1` avec l'option `trunks=` et pèse le pour et le contre.

---

### M00-E11 — Fabriquer le template cloud-init `tpl-debian13`  `LAB` `★★`

> **Ticket PLAT-111** — *De : Karim Benali*
> Plus aucune VM installée à la main après `gw01`. On part de l'image *genericcloud* officielle de Debian 13, on en fait un template Proxmox avec cloud-init, l'agent QEMU et une console série, et toutes les VMs du workbook en seront des clones.

**Objectifs pédagogiques**
- Comprendre cloud-init dans Proxmox VE : lecteur cloud-init, données générées (*user-data*, *network-config*, *meta-data*), *vendor-data* personnalisé via les snippets.
- Importer une image disque dans une VM et la convertir en template.
- Configurer une VM pour l'exploitation : agent QEMU, console série, contrôleur SCSI adapté.

**Prérequis** : E07 (`hdd-bulk` accepte `snippets` et `import`), E09, E10 (clé `/root/.ssh/id_ed25519_lab`).
**Durée indicative** : 1 h 30.

**Contexte technique**

| Paramètre | Valeur |
|---|---|
| VMID / nom | 9000 / `tpl-debian13`, pool `lab`, étiquettes `template`, `debian13` |
| Image | `debian-13-genericcloud-amd64.qcow2`, depuis <https://cloud.debian.org/images/cloud/trixie/latest/>, somme vérifiée avec `SHA512SUMS` |
| Emplacement de l'image | `/mnt/hdd-bulk/import/` (contenu `import` de `hdd-bulk`) |
| Matériel | 2 vCPU, 2 Go, type de CPU `x86-64-v2-AES`, contrôleur `virtio-scsi-single`, disque `scsi0` importé sur `local-nvme` (8 Go, `discard`, `iothread`, `ssd`), `net0` VirtIO sur `vmbr1` |
| Console | `serial0` de type `socket`, affichage `vga` redirigé sur `serial0` |
| Cloud-init | lecteur sur `ide2` ; utilisateur `admin` (l'image Debian lui donne `sudo` sans mot de passe : rien à ajouter, contrairement à `gw01`) ; clé `/root/.ssh/id_ed25519_lab.pub` ; résolveur `10.10.20.10` ; domaine de recherche `par1.medisphere.internal` |
| Vendor-data | snippet `vendor-debian13.yaml` sur `hdd-bulk`, qui installe et démarre `qemu-guest-agent` et règle le fuseau horaire `Europe/Paris` |
| Agent | activé, avec `fstrim_cloned_disks` |

**Travail demandé**

1. Télécharge l'image et `SHA512SUMS` dans `/mnt/hdd-bulk/import/`, vérifie la somme. Examine l'image (`qemu-img info`) : format, taille virtuelle.
2. Écris le snippet `vendor-debian13.yaml` dans le répertoire `snippets` de `hdd-bulk`. Il commence obligatoirement par `#cloud-config`.
3. Crée la VM 9000 sans disque, avec le matériel du tableau.
4. Importe l'image comme disque de la VM :
   ```
   root@pve01:~# qm disk import 9000 /mnt/hdd-bulk/import/debian-13-genericcloud-amd64.qcow2 local-nvme
   root@pve01:~# qm config 9000 | grep unused
   ```
   Rattache le volume importé en `scsi0` avec les options du tableau, agrandis-le à 8 Go, et fais de `scsi0` le seul périphérique d'amorçage.
5. Ajoute le lecteur cloud-init en `ide2` et configure les paramètres cloud-init du tableau, dont le *vendor-data* (`--cicustom`).
6. Inspecte ce que Proxmox génère :
   ```
   root@pve01:~# qm cloudinit dump 9000 user
   root@pve01:~# qm cloudinit dump 9000 network
   ```
   Repère où se trouvent l'utilisateur, la clé SSH et le nom d'hôte.
7. **Sans démarrer la VM**, convertis-la en template (`qm template 9000`). Observe le nouveau nom du volume disque.
8. Rédige dans tes notes : pourquoi ne faut-il pas démarrer la VM avant de la convertir ?

**Critères de réussite**
- [ ] La VM 9000 `tpl-debian13` est un template du pool `lab`.
- [ ] `scsihw: virtio-scsi-single`, disque `scsi0` sur `local-nvme`, amorçage sur `scsi0`.
- [ ] Lecteur cloud-init en `ide2` ; `ciuser: admin`, clé SSH, `nameserver: 10.10.20.10`, `searchdomain: par1.medisphere.internal`.
- [ ] `serial0: socket` et `vga: serial0` ; agent activé.
- [ ] `cicustom` référence `hdd-bulk:snippets/vendor-debian13.yaml`, qui existe, commence par `#cloud-config` et installe `qemu-guest-agent`.

**Vérification** : `lab/bin/check 00 11`

<details><summary>Indice 1</summary>

L'image *genericcloud* n'a pas de mot de passe et n'accepte que des clés SSH : sans cloud-init, impossible de s'y connecter. Elle ne contient pas non plus l'agent QEMU, d'où le *vendor-data*. Pourquoi *vendor* et pas *user* ? Lis la description de l'option `cicustom` dans `qm help set` : un *user-data* personnalisé **remplace** celui que Proxmox génère.
</details>

<details><summary>Indice 2</summary>

`qm disk import` crée un volume `unusedN`. On le rattache avec `qm set 9000 --scsi0 <volume>,<options>`. Pour la console série : `--serial0 socket --vga serial0`. Pour le lecteur cloud-init : `--ide2 <stockage>:cloudinit`. Agrandissement : `qm disk resize`.
</details>

<details><summary>Indice 3</summary>

Dans le *vendor-data*, `packages:` installe des paquets au premier démarrage (après `package_update: true`), et `runcmd:` exécute des commandes à la fin du premier démarrage. L'agent est normalement démarré par udev quand le port virtio de l'agent apparaît : juste après son installation, il faut le démarrer explicitement.
</details>

**Pour aller plus loin** (facultatif) : compare avec l'option `import-from` de `qm set` (import et rattachement en une commande) et avec la construction d'images par Packer (module 03).

---

### M00-E12 — Déployer `adm01` et `dns01` depuis le template  `LAB` `★`

> **Ticket PLAT-112** — *De : Claire Morel*
> Premières VMs du socle : `adm01`, ton poste d'administration dans le VLAN MGMT, et `dns01`, le futur DNS dans le VLAN INFRA. Clones complets du template, adressage fixe par cloud-init, rangées dans le pool et étiquetées. Je veux pouvoir les recréer à l'identique en dix minutes.

**Objectifs pédagogiques**
- Cloner un template (clone complet vs lié) et personnaliser le clone par cloud-init.
- Placer une VM dans un VLAN sur un bridge VLAN-aware.
- Vérifier le premier démarrage d'une VM cloud-init (console série, agent, statut cloud-init).

**Prérequis** : E10, E11.
**Durée indicative** : 1 h.

**Contexte technique**

| | `adm01` | `dns01` |
|---|---|---|
| VMID | 1001 | 1002 |
| Clone | complet, depuis 9000, sur `local-nvme` | idem |
| Ressources | 2 vCPU, 2 Go | 1 vCPU, 1 Go |
| Disque | agrandi à 20 Go | 8 Go (taille du template) |
| Réseau | `vmbr1`, `tag=10` | `vmbr1`, `tag=20` |
| Adresse | 10.10.10.10/24, passerelle 10.10.10.1 | 10.10.20.10/24, passerelle 10.10.20.1 |
| Étiquettes | `socle`, `admin` | `socle`, `dns` |
| Démarrage | automatique, `order=3` | automatique, `order=2` |

*Résolveur provisoire* : la cible est 10.10.20.10 pour toutes les VMs du lab, mais `dns01` ne sert pas encore de DNS (E13). Or, au premier démarrage, cloud-init doit résoudre les noms des miroirs Debian pour installer l'agent QEMU. Pour ces deux VMs, surcharge donc le résolveur du template par un **résolveur public** noté `<DNS-PUBLIC>` (par exemple `9.9.9.9`, à noter dans ton inventaire). Pas ta box : la matrice de `gw01` interdit au lab de joindre le LAN maison. C'est provisoire : en E13, tu basculeras `gw01`, `adm01` et `dns01` sur 10.10.20.10 ; le template, lui, garde 10.10.20.10 pour les futures VMs.

**Travail demandé**

1. Clone le template pour créer `adm01` :
   ```
   root@pve01:~# qm clone 9000 1001 --name adm01 --full 1 --pool lab --storage local-nvme
   ```
2. Personnalise le clone :
   ```
   root@pve01:~# qm set 1001 --cores 2 --memory 2048 --tags "socle;admin" \
       --net0 virtio,bridge=vmbr1,tag=10 \
       --ipconfig0 ip=10.10.10.10/24,gw=10.10.10.1 \
       --nameserver <DNS-PUBLIC> --searchdomain par1.medisphere.internal \
       --onboot 1 --startup order=3
   root@pve01:~# qm disk resize 1001 scsi0 20G
   ```
3. Démarre `adm01` et suis le premier démarrage sur la console série (`qm terminal 1001`, sortie avec `Ctrl+O`). Attends que l'agent réponde (`qm guest cmd 1001 ping`).
4. Fais de même pour `dns01`, d'après le tableau, **sans** reprendre les commandes ci-dessus telles quelles.
5. Ajoute les alias `adm01` et `dns01` dans `/root/.ssh/config` de `pve01` (même modèle que `gw01` : utilisateur `admin`, clé dédiée), puis connecte-toi.
6. Dans chaque VM, vérifie : le nom complet (`hostname -f`), la fin de cloud-init (`cloud-init status --long`), la taille du système de fichiers racine, l'agent, l'accès à Internet.
7. Vérifie le filtrage de `gw01` : `adm01` (MGMT) joint `dns01` ; `dns01` (INFRA) ne peut pas initier de connexion vers `adm01`.

**Critères de réussite**
- [ ] Les VMs 1001 `adm01` et 1002 `dns01` sont des clones complets, dans le pool `lab`, étiquetées, démarrées, avec démarrage automatique.
- [ ] `net0` est sur `vmbr1` avec `tag=10` (adm01) et `tag=20` (dns01) ; les adresses et passerelles cloud-init sont conformes.
- [ ] L'agent QEMU répond pour les deux VMs ; cloud-init a terminé (`status: done`).
- [ ] `ssh adm01` et `ssh dns01` fonctionnent depuis `pve01` ; `sudo -n true` réussit ; `hostname -f` renvoie le nom complet.
- [ ] Les deux VMs joignent Internet ; `adm01` joint `dns01` ; `dns01` ne peut pas initier de connexion vers `adm01`.

**Vérification** : `lab/bin/check 00 12`

<details><summary>Indice 1</summary>

Si la VM démarre mais que tu ne peux pas t'y connecter : la console série (`qm terminal`) te montre les messages de cloud-init, et `qm cloudinit dump <vmid> network` ce que Proxmox lui a transmis. Une VM sans réseau dans un VLAN vient souvent d'un `tag` manquant ou d'une passerelle absente sur `gw01`.
</details>

<details><summary>Indice 2</summary>

Si l'agent ne répond pas : regarde dans la VM si le paquet `qemu-guest-agent` est installé (sinon cloud-init n'a pas pu joindre les miroirs : DNS, route, NAT ?) et si le service tourne. `cloud-init status --long` et `/var/log/cloud-init-output.log` disent ce qui a échoué.
</details>

**Pour aller plus loin** (facultatif) : écris un script qui crée l'une des deux VMs à partir de variables (VMID, nom, VLAN, IP, ressources), et qui refuse de s'exécuter si le VMID est déjà pris. Tu le retrouveras sous une autre forme avec l'API (E18) puis Terraform (module 05).
