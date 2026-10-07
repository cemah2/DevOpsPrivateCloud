# Module 06 — Introduction : les services socle

## Fini le provisoire

Lundi, 9 h 10. La revue du module 05 s'est bien passée : le socle est déclaré, son état est chiffré sur `s3-01`, chaque VM est configurée par Ansible. Dans la foulée, Claire Morel envoie le programme suivant.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Nadia Roussel
> **Objet** : Services socle — on remplace tout ce qui est « provisoire »
>
> Bonjour,
>
> Le bloc B commence dans quelques semaines : cluster Proxmox, Ceph, OpenStack. Des dizaines de machines, des centaines d'adresses. Avant cela, je veux que les **services d'infrastructure** du socle soient dignes d'une production. Aujourd'hui :
> - une CA fabriquée à la main avec `openssl` signe le certificat de GitLab, et sa clé dort sur `adm01` ;
> - dnsmasq fait à la fois le DNS et le DHCP : impossible de le piloter par API, impossible d'avoir un secondaire ;
> - les adresses IP sont choisies dans un tableau Markdown ;
> - chaque nouvelle VM nous fait accepter une empreinte SSH les yeux fermés.
>
> Ce que je veux à la fin du module :
> 1. une **PKI** interne : racine hors ligne, intermédiaire en ligne sur `ca01`, certificats TLS délivrés automatiquement (ACME), certificats SSH pour les hôtes et pour nous ;
> 2. une **source de vérité** : NetBox sur `nbx01`, d'où partent les adresses, les noms et l'inventaire ;
> 3. un **DNS** séparé en serveur faisant autorité et résolveur (PowerDNS), piloté par API, doublé par `dns02` ;
> 4. un **DHCP** moderne (Kea), qui publie ses baux dans le DNS et survit à la perte d'un serveur ;
> 5. une heure authentifiée, des sauvegardes testées, une supervision qui prévient **avant** l'expiration d'un certificat.
>
> Karim fixe la règle technique : « une nouvelle VM, c'est OpenTofu ; une configuration, c'est un rôle Ansible testé ; un flux, c'est une ligne dans `pare_feu.yml`. Pas d'installation à la main. » Sophie suivra la PKI de près : c'est la pièce que l'auditeur HDS regardera en premier.
>
> Premier jalon : la PKI, NetBox et PowerDNS, sans interrompre le DNS du lab. Karim te fait d'abord passer le test habituel.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 06, le socle est en version **v1** (étiquette `socle-v1` du dépôt `plateforme/medisphere`), l'état d'entrée du bloc B :

- `ca01` : **step-ca**, autorité intermédiaire d'une racine **hors ligne** ; ACME pour tous les services HTTPS du socle ; CA SSH (certificats d'hôte et d'utilisateur) ; la CA provisoire est retirée partout ;
- `nbx01` : **NetBox**, source de vérité du socle (sites, VLAN, préfixes, plages, équipements, VMs), synchronisée avec Proxmox, alimentant l'inventaire Ansible et l'allocation d'adresses d'OpenTofu ;
- `dns01` et `dns02` : **PowerDNS** Authoritative (zones internes, API, transferts signés TSIG, DNSSEC) et **Recursor** (seul point d'entrée des clients) ; **Kea DHCPv4** en haute disponibilité avec mise à jour dynamique du DNS ; dnsmasq désinstallé ;
- `gw01` : serveur de temps authentifié (NTS) ;
- les sauvegardes applicatives, la supervision des services et des certificats, la politique de certification, l'ADR-0060 (qui fait foi pour quoi), les runbooks RB-060 et suivants.

Le **palier 1** (ce fichier et `01-decouverte.md`) pose les trois briques : la PKI (E02, E03), NetBox (E04, E05), PowerDNS (E06 à E08), en bascule douce, sans coupure du DNS du lab.

## Architecture du module

```
                                 adm01 (1001) 10.10.10.10 — VLAN 10 MGMT
                     ~/pki-racine (racine HORS LIGNE, chiffrée) · step, uv, ansible, tofu
                                │ SSH, HTTPS, API (MGMT joint tout le lab)
   ═════════════════════════════╪══════════════════════ gw01 (routage, filtrage, NTP/NTS) ═══
                                │                                VLAN 20 INFRA 10.10.20.0/24
  ┌─────────────────────────────┼───────────────────────────────────────────────────────────┐
  │  dns01 (1002) .10           │      ca01 (1003) .11          nbx01 (1005) .13            │
  │  ┌───────────────────────┐  │      ┌──────────────────┐     ┌─────────────────────────┐ │
  │  │ PowerDNS Recursor :53 │◄─┼──────│ step-ca :443     │     │ nginx :443 (TLS)        │ │
  │  │  (clients du lab)     │  │ DNS  │  intermédiaire   │     │ gunicorn 127.0.0.1:8001 │ │
  │  │   │ zones internes    │  │      │  ACME, CA SSH    │     │ NetBox 4.6 · netbox-rq  │ │
  │  │   ▼ (relais, RD=0)    │  │      └──────────────────┘     │ PostgreSQL 17 · Valkey  │ │
  │  │ PowerDNS Auth :5300   │  │                               └─────────────────────────┘ │
  │  │  gsqlite3 · API :8081 │  │      git01 (1004) .12   s3-01 (1006) .14   runner01 .15   │
  │  │ dnsmasq : DHCP seul   │  │      (certificats émis par ca01 à partir de E03)          │
  │  │  (→ Kea en E16)       │  │                                                           │
  │  └───────────────────────┘  │      dns02 (1008) .16 : secondaire (palier 3)             │
  └─────────────────────────────┴───────────────────────────────────────────────────────────┘
           ▲ récursion vers Internet (gw01 laisse sortir dns01 en UDP/TCP 53, M00-E13)
```

Points structurants :

- **Un seul point d'entrée DNS pour les clients : le récurseur.** Le serveur faisant autorité n'écoute jamais sur le port 53 : il ne répond qu'au récurseur (et à l'API). Les clients du lab gardent 10.10.20.10 comme résolveur ; rien ne change pour eux, même pendant la bascule (E08).
- **La racine de la PKI n'est sur aucune machine en ligne.** `ca01` ne détient que l'intermédiaire. Tout ce qui fait confiance au socle fait confiance à la **racine** : on peut remplacer l'intermédiaire sans toucher un seul client.
- **NetBox décrit l'intention, Proxmox la réalité.** Les deux se confrontent (synchronisation E11, ADR-0060 en E31) ; pour l'instant (E05), NetBox est rempli à partir du plan d'adressage.

### Hôtes du module

| Hôte | VMID | Adresse | Ressources | Étiquettes | Rôle(s) Ansible | Exercice |
|---|---|---|---|---|---|---|
| `ca01` | 1003 | 10.10.20.11 | 1 vCPU, 1 Go, 10 Go | `socle`, `role-pki` | `step_ca` | E02 |
| `nbx01` | 1005 | 10.10.20.13 | 2 vCPU, 4 Go, 30 Go | `socle`, `role-netbox` | `netbox` | E04 |
| `dns01` | 1002 | 10.10.20.10 | existant (2 Go conseillés) | `socle`, `role-dns` | `powerdns_auth`, `powerdns_recursor` (puis `kea_dhcp4`) | E06-E08 |
| `dns02` | 1008 | 10.10.20.16 | 1 vCPU, 2 Go, 10 Go | `socle`, `role-dns` | mêmes rôles (secondaire) | E24 |

VMs d'essai : 2060-2069 (pool `lab`, étiquette `env-m06`, VNet `vsandbox` sauf mention). Instances Molecule : la plage 2045-2049 du projet `plateforme/ansible` (M04-E24), partagée entre scénarios.

### Ports et flux du palier 1

| Flux | Port | Exercice | État sur `gw01` |
|---|---|---|---|
| `adm01` → `ca01`, `nbx01`, `dns01` (SSH, HTTPS, API) | 22, 443, 5300, 8081 | E02-E08 | existant : MGMT joint tout le lab |
| `runner01` → `ca01`, `nbx01`, `dns01` | 443, 8081 | E02-E08 | même VLAN INFRA : rien à ouvrir |
| tout le lab → `dns01` (DNS) | 53 UDP et TCP | E08 | existant (M00-E13) |
| `dns01` → Internet (résolution itérative) | 53 UDP et TCP | E07 | existant (M00-E13) |
| `ca01`, `nbx01`, `dns01` → Internet (paquets, PyPI, GitHub) | 80, 443 | E02-E07 | existant (« lab vers Internet ») |

Aucun flux nouveau à ouvrir au palier 1. Les suivants (ACME vers d'autres VLANs, NTS…) passent par `host_vars/gw01/pare_feu.yml`.

---

## Le chemin imposé

Toute machine du module suit le même chemin, celui que tu as construit aux modules 04 et 05 :

1. **OpenTofu** : la VM est déclarée dans l'état `socle` de `plateforme/infra`, par le module `vm-debian` de `plateforme/tofu-modules` (clone complet de l'image dorée `current`, étiquettes `socle` + `role-…`), et créée par le pipeline (plan en MR, `apply` protégé).
2. **DNS** : le nom est déclaré là où vit le DNS du moment (le rôle `dnsmasq` jusqu'à E08, PowerDNS ensuite, NetBox à partir de E15).
3. **Ansible** : la VM apparaît dans l'inventaire dynamique grâce à ses étiquettes ; `site.yml` lui applique `base`, `ssh_durci`, puis son rôle propre. Un nouveau rôle a son **scénario Molecule** et passe `ansible-lint` (profil `production`) avant d'entrer dans `main`.
4. **Secrets** : en Vault, identité `critique` pour tout ce qui permet d'usurper une identité ou de réécrire un service (clés de CA, clés d'API, poivres des jetons), `lab` pour le reste ; chacun inscrit au **registre des secrets** (`docs/socle/registre-secrets.md`).
5. **Documentation** : inventaire du socle, matrice des flux, runbooks, dans `plateforme/medisphere`.

Une installation à la main n'est permise que pour **explorer** (sur une VM d'essai 2060-2069 ou dans un dossier temporaire), annoncée comme telle dans l'énoncé.

---

## Concepts clés

Une synthèse pour se repérer ; les exercices et les liens « Pour aller plus loin » approfondissent.

**DNS faisant autorité et DNS récursif.** Un serveur **faisant autorité** détient les données d'une zone et répond avec le drapeau `aa` ; il ne cherche jamais ailleurs. Un **résolveur récursif** ne détient rien : il interroge les serveurs faisant autorité, de la racine jusqu'à la zone, met en cache, et valide les signatures DNSSEC. Les mélanger dans un même processus (comme dnsmasq) empêche de les sécuriser, de les dimensionner et de les répliquer séparément. Ici : PowerDNS Authoritative pour `medisphere.internal`, PowerDNS Recursor pour les clients, qui **relaie** les zones internes vers l'autoritaire (*forward zones*, requêtes sans récursion).

**Zone, SOA, numéro de série, délégation.** Une zone a un enregistrement SOA (serveur primaire, contact, numéro de série, minuteries) et des NS. Un secondaire ne recopie une zone que si son **numéro de série augmente** : toute modification doit l'incrémenter (format usuel `AAAAMMJJnn`). Une **délégation** (NS dans la zone parente, plus la « colle » si le serveur est dans la zone déléguée) découpe l'espace de noms.

**DNSSEC et ancres.** Un résolveur validant part d'une **ancre de confiance** (la clé de la racine) et suit la chaîne de signatures. Une zone interne comme `medisphere.internal` n'est pas déléguée depuis la racine signée : la racine **prouve** qu'elle n'existe pas, et un résolveur strict jugerait ses réponses « bogus ». On déclare donc une **ancre négative** (*negative trust anchor*) en attendant de signer la zone (E26) et d'en déclarer la clé.

**PKI à deux niveaux.** La **racine** signe des intermédiaires et rien d'autre ; sa clé reste **hors ligne**. L'**intermédiaire**, en ligne, signe les certificats finaux. Les clients font confiance à la racine ; le serveur présente sa **chaîne** (son certificat + l'intermédiaire). Si l'intermédiaire est compromis, on le révoque et on en signe un autre avec la racine : aucun client n'est à reconfigurer. Les durées sont **courtes** (30 jours pour un serveur) parce que le renouvellement est automatique (ACME) : un certificat volé expire vite.

**ACME.** Le protocole de Let's Encrypt (RFC 8555) : un client prouve qu'il contrôle un nom (défi HTTP-01 sur le port 80, DNS-01 par un enregistrement TXT, TLS-ALPN-01 sur le port 443), puis obtient et renouvelle son certificat sans intervention. step-ca est un serveur ACME interne.

**Certificats SSH.** Une CA SSH signe la clé publique d'un hôte (« je certifie que cette clé est celle de `git01` ») ou d'un utilisateur (« cette clé vaut pour `admin` pendant 16 heures »). Le client fait confiance à la CA (`@cert-authority`) au lieu d'accepter chaque empreinte à la première connexion ; le serveur fait confiance à la CA au lieu de gérer des `authorized_keys`.

**Source de vérité.** Un seul endroit où l'on **décide** (adresse, nom, rôle, statut) ; les autres outils en dérivent (DNS, inventaire, IaC) ou s'y confrontent (Proxmox dit ce qui tourne réellement). NetBox modélise le centre de données (sites, baies, équipements), l'adressage (VLAN, préfixes, plages, adresses) et la virtualisation (clusters, VMs, interfaces), avec une API complète.

**DHCP moderne.** Kea (successeur d'ISC DHCP, en fin de vie) : configuration JSON, API de contrôle, base de baux, mise à jour du DNS (RFC 2136, signée TSIG), haute disponibilité par deux serveurs qui se synchronisent. Palier 2 et 3.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | step-ca 0.30 / step CLI 0.31 (dépôt APT Smallstep) ; NetBox 4.6 (installation native, Python 3.13, PostgreSQL 17 et Valkey 8 de Debian 13) ; PowerDNS Authoritative 5.0 et Recursor 5.4 (repo.powerdns.com, suites `trixie-auth-50` et `trixie-rec-54`) ; Kea 3.0 (dépôt ISC `kea-3-0`) ; chrony 4.6 |
| Changements de version | voir [`annexes/versions-bloc-A.md`](../../../annexes/versions-bloc-A.md), section « Services socle » : jetons NetBox v2, configuration YAML du Recursor, Debian 13 trop ancien pour step-ca, PowerDNS et Kea |
| PKI | racine « MédiSphère Root CA » (hors ligne, `~/pki-racine` sur `adm01`), intermédiaire « MédiSphère Intermediate CA » sur `ca01` ; step-ca dans `/etc/step-ca` (compte `step`), `https://ca01.par1.medisphere.internal` (port 443) ; certificats publics de la PKI versionnés dans `pki/` du projet `plateforme/ansible` ; racine installée sous `/usr/local/share/ca-certificates/medisphere-root-ca.crt` sur tous les hôtes (rôle `medisphere.socle.ca_lab`) |
| Provisioners step-ca | `admin` (JWK, émission manuelle, mot de passe dans `~/.config/workbook/step-admin.pass`), `acme` (ACME, 30 jours au plus), `sshpop` (renouvellement SSH) |
| NetBox | `https://nbx01.par1.medisphere.internal` ; installation dans `/opt/netbox-<version>` désignée par `/opt/netbox` ; services `netbox`, `netbox-rq`, `nginx`, `postgresql`, `valkey-server` ; jetons **v2** : `Authorization: Bearer nbt_<clé>.<jeton>` |
| DNS | `dns01` : Recursor sur 127.0.0.1:53 et 10.10.20.10:53 (après E08), Authoritative sur 127.0.0.1:5300 et 10.10.20.10:5300, API sur 10.10.20.10:8081 (clients : `dns01`, `adm01`, `runner01`) ; zones `medisphere.internal`, `par1.medisphere.internal`, `par2.medisphere.internal`, `10.10.in-addr.arpa`, `20.10.in-addr.arpa` |
| Groupes d'inventaire | `role_pki` (`ca01`), `role_netbox` (`nbx01`), `role_dns` (`dns01`, puis `dns02`) : étiquettes Proxmox `role-pki`, `role-netbox`, `role-dns` |
| Secrets du palier 1 | Vault `critique` : mots de passe des clés en ligne de `ca01`, clé chiffrée et mot de passe du provisioner `admin`, clé Django et poivres des jetons de NetBox, clé TLS de `nbx01`, clé de l'API PowerDNS. Vault `lab` : mots de passe PostgreSQL et `admin` de NetBox. Sur `adm01` : `~/.config/workbook/step-admin.pass`, `netbox-checks.token`, `netbox-moi.token` (600) |
| Documentation | `docs/socle/pki/` (cérémonie de la racine, politique de certification en E33), `docs/socle/changements/` (fiches de changement), runbooks RB-060 et suivants, ADR-0060 |
| Brouillons | `~/m06/eXX/` sur `adm01` (non versionnés) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton compte GitLab personnel (M01-E05), aussi ton compte nominatif NetBox (E04) |
| `<NOEUD>` | Nom du nœud Proxmox de `pve01` |
| `<IP-PVE01>` | Adresse de `pve01` sur le LAN maison (enregistrement A de `pve01`) |
| `<DNS-AMONT>` | Résolveur(s) amont choisis en M00-E13, si tu préfères relayer Internet plutôt que résoudre depuis la racine (E07) |

### Variables de `lab/lab.env`

Rien de nouveau : `WB_NETBOX_URL` et `WB_NETBOX_TOKEN_FILE` existent déjà dans `lab/lab.env.example` (jeton v2 **en lecture seule** des vérifications, créé en E04). Les vérifications utilisent aussi `WB_SRC` (copies de travail `~/src/ansible`, `~/src/infra`, `~/src/outils`), `WB_DEPOT` (documentation), `WB_PVE_HOST` (configuration des VMs, lue en root sur `pve01`) et le jeton GitLab des checks.

---

## Règles du module

1. **Le DNS du lab ne s'interrompt pas.** Tout ce qui touche à `dns01` se prépare à côté de l'existant (autres ports, autre service), se compare, puis bascule par une procédure écrite avec retour arrière. Une coupure du DNS se voit partout en quelques minutes : forge, runner, sauvegardes, `apt`.
2. **Instantané avant toute intervention sur un hôte du socle** : `ms-snapshot --prefix avant-m06 <VMID>` (M02-E11), supprimé une fois le changement validé.
3. **La clé de la racine ne touche jamais une machine en ligne autre que `adm01`**, et sur `adm01` elle n'existe que chiffrée, dans `~/pki-racine` (700). Elle ne va ni dans un dépôt, ni dans Vault, ni dans un ticket. Sa phrase de passe est dans ton gestionnaire de mots de passe, pas dans un fichier.
4. **Pas de vérification TLS désactivée** (`curl -k`, `validate_certs: false`, `verify=False`) : un échec TLS est un diagnostic à faire, pas un obstacle à contourner. Les clients qui ont leur propre magasin de confiance (Python `requests`, GitLab, Node…) se configurent explicitement.
5. **Un secret ne passe jamais en argument de commande** (visible dans `ps` et l'historique) : fichier en 600, entrée standard ou variable d'environnement d'un processus unique.
6. **Accès de secours** : avant de toucher à un hôte du socle, vérifie la console Proxmox (`qm terminal <VMID>`) et l'agent QEMU (`qm guest cmd <VMID> ping`).
7. **Nettoie derrière toi** : VMs 2060-2069 détruites en fin d'exercice, instances Molecule détruites même en cas d'échec, brouillons de `~/m06/` sans secret.

---

## Préparer `adm01`

Les outils viennent des modules précédents ; ce module ajoute seulement le client `step` (E02). Vérifie avant de commencer :

```
admin@adm01:~$ tofu version
admin@adm01:~$ cd ~/src/ansible && uv run ansible --version | head -n 1
admin@adm01:~$ dig +short @10.10.20.10 s3-01.par1.medisphere.internal
admin@adm01:~$ ssh-add -l
admin@adm01:~$ lab/bin/check 05 46
```

Le dernier contrôle (mini-projet du module 05) doit être vert : ce module crée des VMs par le pipeline de `plateforme/infra` et les configure par celui de `plateforme/ansible`. S'il ne l'est pas, termine le module 05 d'abord.

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 06 <XX>`. Elles sont en lecture seule : configuration Proxmox lue sur `pve01`, état des hôtes en SSH (avec `sudo -n` pour les fichiers protégés), questions DNS, points publics des API (step-ca, NetBox avec le jeton en lecture des checks, PowerDNS), fichiers de tes copies de travail, API GitLab en lecture.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M06-EXX/` : `ansible/` reproduit l'arborescence de `plateforme/ansible`, `infra/` celle de `plateforme/infra`, `outils/` celle de `plateforme/outils`, `medisphere/` celle de la documentation. Même quand ta vérification est verte, lis « Pièges classiques ».
- Les scripts de panne (`corrige/pannes/`) révèlent les causes : ne les lis pas avant d'avoir résolu. Au palier 4, `lab/bin/break 06 XX --annuler` sert aussi à **clore** une panne que tu as réparée : il ne restaure que ce qui est encore dans l'état cassé, sans écraser ta réparation.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─┬─ E04 ─ E05
                 └─ E06 ─ E07 ─ E08 ─ E09
```

1. **E01** — positionnement, à froid.
2. **E02 → E03** — la PKI d'abord : NetBox (E04) a besoin d'un certificat, et le retrait de la CA provisoire doit être fait avant que de nouveaux services ne s'y attachent.
3. **E04 → E05** et **E06 → E08** sont indépendants : tu peux les mener en parallèle. La bascule E08 se planifie (fiche de changement) : réserve-lui un créneau calme.
4. **E09** — en dernier : il demande d'avoir pratiqué.

Durée indicative du palier 1 : 14 à 18 heures.

## Pour aller plus loin

- step-ca : <https://smallstep.com/docs/step-ca/> — en particulier « Production considerations » : <https://smallstep.com/docs/step-ca/certificate-authority-server-production/>
- NetBox 4.6 : <https://netboxlabs.com/docs/netbox/> (installation, configuration, API REST)
- PowerDNS Authoritative : <https://doc.powerdns.com/authoritative/> · Recursor : <https://doc.powerdns.com/recursor/>
- Kea : <https://kea.readthedocs.io/>
- RFC 1034/1035 (DNS), RFC 4033-4035 (DNSSEC), RFC 7646 (ancres de confiance négatives), RFC 8555 (ACME), RFC 5280 (certificats X.509), RFC 9499 (terminologie DNS). Le TLD `.internal` est réservé à l'usage privé par une résolution de l'ICANN (juillet 2024) : il ne sera jamais délégué depuis la racine.
