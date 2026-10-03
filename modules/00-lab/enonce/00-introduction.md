# Module 00 — Introduction : positionnement et montage du lab

## Premier jour chez MédiSphère

Lundi, 8 h 47. Ton badge fonctionne, ton poste est prêt. Le premier mail de ta boîte de réception t'attend.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent
> **Objet** : Bienvenue dans l'équipe Plateforme — ton premier chantier
>
> Bonjour et bienvenue !
>
> Comme je te l'ai dit en entretien, le contrat avec InfoGér se termine dans 18 mois et nous construisons notre propre cloud privé. Avant d'y mettre la moindre application de santé, il nous faut un **socle** : un hyperviseur propre sur PAR1, un réseau isolé et filtré, un DNS, l'heure juste partout, un accès d'administration sécurisé, et des sauvegardes hors site sur PAR2 qu'on sait **restaurer**. Tout le reste (Git, Ansible, Terraform, Kubernetes…) sera posé dessus.
>
> Ton programme des prochaines semaines :
> 1. **Karim** va d'abord te faire passer notre test de positionnement Linux et réseau. Ce n'est pas un examen : il sert à savoir où t'épauler.
> 2. Tu fais l'**inventaire** de `pve01`. Attention : il héberge déjà des machines qui ne nous appartiennent pas (« VMs perso » dans le jargon de l'équipe). On n'y touche pas, on ne reformate rien, on ne réinstalle rien.
> 3. Le vieux serveur de PAR2 (`hp01`) contient encore des **données qu'on ne doit pas perdre**. Tu les récupères avec une preuve d'intégrité **avant** toute réaffectation. Sophie demandera la preuve.
> 4. Ensuite tu montes le réseau du lab, le routeur `gw01`, le template de VMs, et les premières VMs du socle.
>
> Règle d'or de l'équipe : *ce qui n'est pas vérifié n'est pas fait, ce qui n'est pas documenté n'existe pas.*
>
> Bon courage, ma porte est ouverte.
> Claire

Dans la réalité de ton lab : les « VMs perso » sont les tiennes, et les « données à préserver » de `hp01` sont tes **photos personnelles**. Le workbook les traite avec le même sérieux qu'un actif d'entreprise.

---

## Ce que tu construis dans ce module

À la fin du module 00, le **socle** est en place :

- `pve01` préparé (dépôts, mises à jour, virtualisation imbriquée, stockages nommés, pool et comptes dédiés) ;
- un bridge `vmbr1` isolé qui porte les VLANs du lab ;
- `gw01`, routeur/pare-feu Linux (nftables) entre le lab et ton réseau domestique ;
- un template cloud-init `tpl-debian13` et les VMs `adm01` (poste d'administration) et `dns01` (DNS/DHCP provisoires) ;
- un VPN d'administration WireGuard, un serveur de temps ;
- `hp01` réinstallé en Proxmox Backup Server (`pbs01`) sur le « site » PAR2, relié à PAR1 par un tunnel chiffré ;
- des sauvegardes planifiées, vérifiées, chiffrées et **restaurées** au moins une fois.

## Architecture cible du socle

```
                                   Internet
                                      │
                              ┌───────┴────────┐
                              │ Box domestique │ <IP-BOX>
                              └───────┬────────┘
             LAN maison <LAN-MAISON> (ex. 192.168.1.0/24) — « hors lab »
  ──────┬─────────────────────────────┬──────────────────────────────┬──────────
        │                             │                              │
        │ <IP-HP01-LAN>               │ <IP-PVE01>                   │ ton poste
┌───────┴─────────────────┐  ┌────────┴──────────────────────────────────────┐   wg1 10.255.1.2
│ hp01 = pbs01   (PAR2)   │  │ pve01  (PAR1)  Proxmox VE 9                   │   (VPN d'admin,
│ Proxmox Backup Server 4 │  │                                               │    UDP 51821)
│                         │  │  vmbr0 ── port physique ── LAN maison         │
│ wg0 10.255.0.2/30 ◄═════╪══╪═══════╗   │                                   │
│   (UDP 51820)           │  │       ║   │ ens18 <IP-GW01-WAN>               │
│ vmbr1 (sans port)       │  │  ┌────╨───┴───────────────────────┐           │
│   10.20.10.10/24        │  │  │ gw01 (VMID 1000) Debian 13     │           │
│ datastore ds-lab (HDD)  │  │  │ nftables, NAT, NTP, WireGuard  │           │
└─────────────────────────┘  │  │ wg0 10.255.0.1  wg1 10.255.1.1 │           │
     tunnel wg0 chiffré      │  │ ens19 (trunk, sans tag)        │           │
     au-dessus du LAN maison │  │  .10 .20 .30 .40 .50 .52 .60   │           │
                             │  │  .70 .99 → 10.10.<VLAN>.1/24   │           │
                             │  └──────────────┬─────────────────┘           │
                             │                 │                             │
                             │  vmbr1 : VLAN-aware, AUCUN port physique      │
                             │  ═══════════════╪═══════════════════════════  │
                             │     │ VLAN 10 MGMT          │ VLAN 20 INFRA   │
                             │  ┌──┴──────────────┐   ┌────┴─────────────┐   │
                             │  │ adm01 (1001)    │   │ dns01 (1002)     │   │
                             │  │ 10.10.10.10     │   │ 10.10.20.10      │   │
                             │  │ bastion, outils │   │ dnsmasq DNS/DHCP │   │
                             │  └─────────────────┘   └──────────────────┘   │
                             │  VLANs routés : 10 20 30 40 50 52 60 70 99    │
                             │  VLANs non routés : 31 32 41 51               │
                             │  Template 9000 tpl-debian13 · pool « lab »    │
                             └───────────────────────────────────────────────┘
```

Points structurants :

- **Le lab est isolé** : `vmbr1` n'a aucun port physique. Les trames étiquetées du lab ne sortent jamais de `pve01` ; ta box et ton réseau domestique ne voient que `gw01` (une IP de plus sur le LAN).
- **`gw01` est le seul point de passage** entre le lab et le reste du monde : routage inter-VLAN, filtrage, NAT sortant, serveur de temps, terminaison des tunnels WireGuard.
- **PAR2 est simulé** : `hp01` est physiquement sur ton LAN, mais son adresse « site » 10.20.10.10 n'est joignable qu'à travers le tunnel `wg0`. Le trafic de sauvegarde suit donc le chemin `pve01 → gw01 → wg0 → hp01`, comme une vraie liaison inter-sites chiffrée.

## Adresses du socle

| Élément | VMID | Interface / VLAN | Adresse | Rôle | Créé en |
|---|---|---|---|---|---|
| `pve01` | — | `vmbr0` (LAN maison) | `<IP-PVE01>` | Hyperviseur PAR1 | existant |
| `gw01` | 1000 | `ens18` → `vmbr0` (WAN) | `<IP-GW01-WAN>` | Routeur / pare-feu / NAT | E10 |
| | | `ens19.10` … `ens19.99` | `10.10.<VLAN>.1/24` (VLANs 10, 20, 30, 40, 50, 52, 60, 70, 99) | Passerelle de chaque VLAN routé | E10 |
| | | `wg0` | 10.255.0.1/30, UDP 51820 | Tunnel PAR1 ↔ PAR2 | E21 |
| | | `wg1` | 10.255.1.1/24, UDP 51821 | VPN d'administration | E16 |
| `adm01` | 1001 | VLAN 10 MGMT | 10.10.10.10/24, gw 10.10.10.1 | Poste d'admin, bastion | E12 |
| `dns01` | 1002 | VLAN 20 INFRA | 10.10.20.10/24, gw 10.10.20.1 | DNS (dnsmasq), DHCP du VLAN 99 | E12, E13 |
| `tpl-debian13` | 9000 | — | — | Template cloud-init Debian 13 | E11 |
| `hp01` / `pbs01` | — (physique) | LAN maison | `<IP-HP01-LAN>` | Extrémité WireGuard, PBS | E20 |
| | | `wg0` | 10.255.0.2/30 | Tunnel PAR2 ↔ PAR1 | E21 |
| | | `vmbr1` (sans port) | 10.20.10.10/24 | Adresse « site PAR2 » de PBS | E20, E21 |
| Ton poste | — | `wg1` | 10.255.1.2 | Client du VPN d'admin | E16 |
| VMs sandbox | 5001-5009 (et 5044, 5048 ; restaurations de test 5090-5099) | VLAN 99 SANDBOX | DHCP 10.10.99.100-199 | Exercices jetables | E14 |

Domaine interne : `par1.medisphere.internal` (PAR1), `par2.medisphere.internal` (PAR2). Résolveur des VMs du lab : 10.10.20.10. Le plan d'adressage complet est dans [`PLAN.md`](../../../PLAN.md) §4.

### Valeurs propres à ton installation

Le workbook note entre chevrons ce qui dépend de chez toi. Tu les consignes une fois pour toutes dans `lab/inventaire-local.md` (exercice E03), section « Valeurs du lab ».

| Valeur | Signification | Exemple |
|---|---|---|
| `<LAN-MAISON>` | Ton réseau domestique | `192.168.1.0/24` |
| `<IP-BOX>` | Passerelle de ton LAN (la box) | `192.168.1.1` |
| `<IP-PVE01>` | IP de `pve01` sur le LAN | `192.168.1.20` |
| `<IP-GW01-WAN>` | IP **fixe** de `gw01` sur le LAN, **hors de la plage DHCP** de la box | `192.168.1.40` |
| `<IP-HP01-LAN>` | IP de `hp01` sur le LAN | `192.168.1.30` |
| `<DNS-PUBLIC>` | Résolveur public provisoire de `adm01` et `dns01`, entre E12 et E13 | `9.9.9.9` |
| `<DNS-AMONT>` | Résolveur(s) que `dns01` interroge pour Internet (E13) | `192.168.1.1` ou un résolveur public |
| `<NOEUD>` | Nom du nœud Proxmox de `pve01` (`hostname`) | `pve01` |

> 💡 Si ton hyperviseur ne s'appelle pas `pve01`, **ne le renomme pas** (renommer un nœud Proxmox qui héberge des VMs est une opération délicate). Dans tout le workbook, `pve01` désigne ton hyperviseur principal ; `<NOEUD>` désigne son nom réel dans les chemins d'API (`/nodes/<NOEUD>/…`).

---

## Règles de sécurité du lab

Ces règles s'appliquent à **tous** les modules. Les scripts de vérification et de panne les respectent ; toi aussi.

1. **Tes VMs perso sont intouchables.** Tout ce que crée le workbook vit dans le pool Proxmox `lab` et dans les plages de VMID réservées (1000-1099 socle, 2000-3999 modules et finaux, 5000-5999 sandbox, 9000-9099 templates). Avant de créer une VM, vérifie que son VMID est libre (`qm list`, `pct list`). Si une de tes VMs perso occupe déjà un VMID du workbook, note-le dans l'inventaire (E03) : c'est le workbook qui s'adapte, pas ta VM.
2. **On ne formate jamais un disque utilisé.** Avant toute commande destructrice (`wipefs`, `sgdisk --zap-all`, `pvcreate`, `zpool create`, `mkfs`), applique la règle des trois preuves de l'E07 : pas de signature, pas d'utilisation (LVM, ZFS, montage, stockage Proxmox), numéro de série vérifié.
3. **`hp01` est en lecture seule jusqu'à la validation de l'E04.** Aucun lab ne touche `hp01` avant que la copie des photos soit faite **et vérifiée par sommes de contrôle**. La réinstallation de `hp01` (E20) n'a lieu qu'après cette validation, et idéalement après une seconde copie hors de `pve01` (règle 3-2-1, voir E04).
4. **Garde toujours un accès de secours à `pve01`** (écran-clavier, IPMI ou console série) avant de toucher à son réseau. Une erreur dans `/etc/network/interfaces` te coupe de l'interface web *et* du SSH.
5. **Sauvegarde tes VMs perso avant les opérations risquées sur `pve01`** (mise à jour majeure, modification réseau, stockage). Une sauvegarde `vzdump` vers un support externe suffit.
6. **N'expose rien sur Internet** : n'ouvre aucun port de ta box vers le lab, sauf si un exercice le demande explicitement et en connaissance de cause.
7. **Secrets** : `lab/lab.env` et `lab/inventaire-local.md` sont ignorés par git. Ne commite jamais de mot de passe, de jeton ou de clé privée.

---

## Vérifier ton travail : les checks

Chaque exercice vérifiable a un script de contrôle, lancé par `lab/bin/check <module> <exercice>`. Il est **en lecture seule** : il observe le lab, ne modifie rien. Il affiche `[OK]`, `[KO]` ou `[--]` (contrôle non applicable) pour chaque point, puis un bilan. Les messages décrivent un **symptôme** (« le stockage hdd-bulk n'est pas actif »), jamais la solution.

### D'où lancer les checks

| Exercices | Lancés depuis | Pourquoi |
|---|---|---|
| E01 à E14 | `pve01` | `adm01` n'existe pas encore (E12) puis n'est pas encore outillé (E15) |
| E15 et suivants | `adm01` | Poste d'administration du lab, comme en entreprise |

**Mise en place sur `pve01`** (à faire une fois, au début du module) :

```
root@pve01:~# apt update && apt install git bind9-dnsutils
root@pve01:~# git clone <URL-DU-DEPOT> /root/DevOpsPrivateCloud
root@pve01:~# cd /root/DevOpsPrivateCloud
root@pve01:~/DevOpsPrivateCloud# cp lab/lab.env.example lab/lab.env
```

`lab/lab.env` est ta configuration locale des checks et des scripts de panne : copie de `lab/lab.env.example`, ignorée par git. Sur `pve01`, édite-le ainsi :

```bash
WB_PVE_HOST=localhost          # les checks tournent SUR pve01 : exécution locale
WB_LAN_MAISON="192.168.1.0/24" # ton <LAN-MAISON>
```

Lancer un contrôle :

```
root@pve01:~/DevOpsPrivateCloud# lab/bin/check 00 07
```

`bind9-dnsutils` fournit `dig`, utilisé par les contrôles DNS du palier 2.

**Accès aux VMs depuis `pve01`.** À partir de l'E10, les checks se connectent aux VMs du lab en SSH avec les **alias** `gw01`, `adm01` et `dns01`, définis dans `/root/.ssh/config` de `pve01` (tu les crées en E10 et E12). Convention : utilisateur `admin` avec `sudo` sans mot de passe sur les VMs Debian (sur `gw01`, installé à la main, c'est le fichier `/etc/sudoers.d/90-workbook` posé en E10 ; sur les VMs clonées du template, cloud-init le fournit), clé dédiée `/root/.ssh/id_ed25519_lab`.

**Bascule vers `adm01` (E15).** Tu cloneras le dépôt sur `adm01` (`~/DevOpsPrivateCloud`) et tu y recréeras `lab/lab.env` à partir de `lab/lab.env.example`, cette fois avec `WB_PVE_HOST=pve01` et `WB_PBS_HOST=pbs01` (alias SSH), ainsi qu'un `~/.ssh/config` contenant les alias `pve01` et `pbs01` (connexion en `root`) et `gw01`, `dns01` (connexion en `admin` + `sudo -n`). Les checks des exercices précédents restent utilisables depuis `adm01`.

### Variables de `lab/lab.env`

Le fichier `lab/lab.env.example` fait référence : toutes ses variables ont une valeur par défaut raisonnable, tu n'adaptes que celles qui diffèrent chez toi.

| Variable | Défaut | Rôle et moment où la renseigner |
|---|---|---|
| `WB_PVE_HOST` | `pve01` | Hôte de l'hyperviseur pour les checks : `localhost` sur `pve01` (E01 à E14), `pve01` (alias SSH) sur `adm01` (E15 et suivants) |
| `WB_PBS_HOST` | `pbs01` | Alias SSH du serveur de sauvegarde, joignable par le tunnel à partir de E21 |
| `WB_SSH_OPTS`, `WB_TIMEOUT` | vide, `5` | Options SSH supplémentaires, délai des tests réseau |
| `WB_LAN_MAISON` | `192.168.1.0/24` | Ton `<LAN-MAISON>`, dès le début du module |
| `WB_PBS_LAN` | vide | `<IP-HP01-LAN>`, à renseigner sur `adm01` en E15 ; sert aux checks de E20 (accès à `hp01` avant le tunnel) et de E21 |
| `WB_STORAGE_NVME`, `WB_STORAGE_SSD`, `WB_STORAGE_BULK` | `local-nvme`, `ssd-lab`, `hdd-bulk` | Seulement si tes stockages gardent d'autres noms (E07) |
| `WB_PHOTOS_DIR` | `/mnt/hdd-bulk/sauvegarde-photos-hp01` | Si tes photos sont sauvegardées ailleurs (E04) |
| `WB_PHOTOS_FULLCHECK` | `0` | `1` pour que le check de l'E04 recalcule **toutes** les sommes (long) |
| `WB_DEPOT` | `$HOME/medisphere` | Dépôt de documentation MédiSphère sur `adm01`, créé en E25 ; à changer seulement si tu l'as placé ailleurs |

Les modules suivants utilisent les **noms logiques** `local-nvme`, `ssd-lab`, `hdd-bulk`. Si tu as dû garder d'autres noms, les variables `WB_STORAGE_*` (et la section « Valeurs du lab » de ton inventaire) font la correspondance.

---

## Indices et corrigé

- Chaque exercice propose 2 ou 3 **indices** repliés, du plus général au plus précis. Ouvre-les un par un, seulement quand tu bloques depuis un moment.
- Le **corrigé** (`corrige/`) donne une solution, mais surtout le *pourquoi*, les alternatives, les pièges classiques et ce qu'on ferait en production. Lis-le **après** avoir fini ou vraiment cherché (règle de l'équipe : 30 minutes de recherche honnête avant d'ouvrir le corrigé). Même quand ton check est vert, lis les sections « Pièges classiques » et « En production chez MédiSphère » : c'est là que se trouve l'expérience.
- Les questionnaires (`Q`) se corrigent avec la grille d'auto-évaluation du corrigé. Réponds **par écrit** avant de comparer.
- Les scripts de panne (`corrige/pannes/`) révèlent la cause : ne les lis pas avant d'avoir résolu.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ──────────────────────────────┐ (copie longue : laisse-la tourner)
                    └─ E05 ─ E06 ─ E07* ─ E08 ─ E09 ─ E10 ─ E11 ─ E12 ─ palier 2 (E13…)
                                   * pas de modification du HDD tant que l'E04 n'est pas validé
```

1. **E01, E02** — positionnement. Fais-les en premier, à froid : ils orientent ta lecture du reste du workbook.
2. **E03** — inventaire. Rien ne se fait sur `pve01` avant de savoir ce qu'il contient.
3. **E04** — lance la copie des photos tôt : elle peut durer des heures. Avance sur E05 et E06 pendant le transfert, mais **termine et valide l'E04 avant l'E07** si tes photos vont sur le HDD de `pve01`.
4. **E05** — questions d'architecture : relis ce document avant d'y répondre.
5. **E06 → E12** — dans l'ordre : chaque exercice s'appuie sur le précédent.

Durée indicative du palier 1 : 15 à 20 heures (hors temps de transfert des photos).

## Pour aller plus loin

- Documentation officielle Proxmox VE : <https://pve.proxmox.com/pve-docs/>
- Guide d'administration de Proxmox Backup Server : <https://pbs.proxmox.com/docs/>
- Wiki nftables : <https://wiki.nftables.org/>
- Debian Administrator's Handbook : <https://debian-handbook.info/>
