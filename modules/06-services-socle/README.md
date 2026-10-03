# Module 06 — Services socle

| | |
|---|---|
| **Bloc** | A — Fondations automatisées |
| **Niveau** | Cœur |
| **Profil de lab** | Socle (+ `ca01`, `nbx01`, `dns02`, permanents, créés dans ce module ; VMs d'essai 2060-2069) |
| **Prérequis** | Module 05 (OpenTofu, `s3-01`) ; module 04 (rôles Ansible) |
| **Durée indicative** | 40 à 50 heures |

## Contexte MédiSphère

Le socle tient avec des solutions provisoires : dnsmasq fait à la fois le DNS et le DHCP, une CA bricolée avec `openssl` signe le certificat de GitLab, les adresses IP sont choisies dans un tableau Markdown, et chaque nouvelle VM impose d'accepter aveuglément une empreinte de clé SSH. Avant de construire le cloud privé (bloc B), Claire Morel veut des **services d'infrastructure de production** : une **source de vérité** (NetBox) d'où partent les adresses, les noms et l'inventaire ; un **DNS** séparé en serveur faisant autorité et récurseur (PowerDNS), piloté par API ; un **DHCP** moderne (Kea) ; une **PKI** interne (step-ca) qui délivre automatiquement des certificats TLS par ACME et des certificats SSH. Sophie Laurent y voit la pièce maîtresse de la conformité HDS : traçabilité des actifs, chiffrement partout, identités vérifiables.

## Objectifs

À la fin de ce module, tu sais :
- déployer et opérer une PKI interne (racine, intermédiaire, ACME, certificats SSH d'hôte et d'utilisateur, renouvellement) ;
- faire de NetBox la source de vérité du socle et l'exploiter par son API (inventaire Ansible, allocation d'adresses depuis OpenTofu) ;
- séparer DNS faisant autorité et récursif avec PowerDNS, le piloter par API, ajouter un secondaire et signer une zone ;
- remplacer le DHCP de dnsmasq par Kea, avec mise à jour dynamique du DNS et haute disponibilité ;
- intégrer ces services : ajouter un hôte au socle de la source de vérité jusqu'au certificat, sans geste manuel ;
- sauvegarder, superviser et dépanner ces services.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M06-E01 | Test de positionnement : services d'infrastructure | Q | ★★ | 1 |
| M06-E02 | Déployer `ca01` et initialiser step-ca | LAB | ★★ | 1 |
| M06-E03 | Faire confiance à la nouvelle PKI | LAB | ★★ | 1 |
| M06-E04 | Déployer NetBox sur `nbx01` | LAB | ★★ | 1 |
| M06-E05 | Modéliser MédiSphère dans NetBox | LAB | ★ | 1 |
| M06-E06 | PowerDNS Authoritative sur `dns01` | LAB | ★★ | 1 |
| M06-E07 | PowerDNS Recursor et zones relayées | LAB | ★★ | 1 |
| M06-E08 | Basculer le DNS du lab sans coupure | LAB | ★★★ | 1 |
| M06-E09 | Questions : DNS, DHCP et PKI | Q | ★★ | 1 |
| M06-E10 | L'API NetBox : jetons, REST et GraphQL | LAB | ★★ | 2 |
| M06-E11 | Synchroniser Proxmox vers NetBox | LIBRE | ★★★ | 2 |
| M06-E12 | Inventaire Ansible depuis NetBox | LAB | ★★ | 2 |
| M06-E13 | Allouer les adresses depuis NetBox avec OpenTofu | LAB | ★★★ | 2 |
| M06-E14 | Piloter PowerDNS par API et par OpenTofu | LAB | ★★ | 2 |
| M06-E15 | Le DNS généré depuis la source de vérité | LAB | ★★★ | 2 |
| M06-E16 | Kea DHCPv4 remplace dnsmasq | LAB | ★★ | 2 |
| M06-E17 | Kea : API de contrôle et mise à jour dynamique du DNS | LAB | ★★★ | 2 |
| M06-E18 | Certificats automatiques par ACME pour GitLab et NetBox | LAB | ★★ | 2 |
| M06-E19 | Certificats SSH d'hôte : fin de la confiance aveugle | LAB | ★★★ | 2 |
| M06-E20 | Certificats SSH d'utilisateur et bastion `adm01` | LAB | ★★★ | 2 |
| M06-E21 | Une heure de référence fiable et authentifiée | LAB | ★★ | 2 |
| M06-E22 | Revue de la configuration DNS du stagiaire | REV | ★★ | 2 |
| M06-E23 | Runbook : ajouter un hôte au socle | RED | ★★ | 2 |
| M06-E24 | DNS secondaire `dns02` : transferts de zone et TSIG | LAB | ★★★ | 3 |
| M06-E25 | Kea en haute disponibilité | LAB | ★★★ | 3 |
| M06-E26 | DNSSEC sur la zone interne | LAB | ★★★ | 3 |
| M06-E27 | La PKI en production : durées de vie, renouvellement, révocation | LAB | ★★ | 3 |
| M06-E28 | Sauvegarder et restaurer les services socle | LIBRE | ★★★ | 3 |
| M06-E29 | Superviser les services socle et l'expiration des certificats | LAB | ★★ | 3 |
| M06-E30 | Durcir les services et mettre à jour la matrice des flux | LAB | ★★ | 3 |
| M06-E31 | ADR : flux d'autorité autour de la source de vérité | RED | ★★ | 3 |
| M06-E32 | Questions de production : services d'infrastructure | Q | ★★★ | 3 |
| M06-E33 | Rédiger la politique de certification de la PKI | RED | ★★ | 3 |
| M06-E34 | Un nouveau service complet en temps limité | CHRONO | ★★★ | 3 |
| M06-E35 | Panne : un nom interne ne se résout plus | BF | ★★★ | 4 |
| M06-E36 | Panne : les VMs sandbox n'obtiennent plus d'adresse | BF | ★★ | 4 |
| M06-E37 | Panne : certificat refusé | BF | ★★★ | 4 |
| M06-E38 | Panne : connexion SSH par certificat refusée | BF | ★★★ | 4 |
| M06-E39 | Panne : NetBox en erreur | BF | ★★ | 4 |
| M06-E40 | Panne : l'inventaire NetBox ne renvoie plus d'hôtes | BF | ★★ | 4 |
| M06-E41 | Panne : SERVFAIL sur la zone signée | BF | ★★★ | 4 |
| M06-E42 | Panne : les baux n'apparaissent plus dans le DNS | BF | ★★ | 4 |
| M06-E43 | Astreinte : les services socle en panne | BF | ★★★★ | 4 |
| M06-E44 | Sous le capot : une résolution DNS et une émission ACME pas à pas | LAB | ★★★ | 4 |
| M06-E45 | Questions expert : DNS, DHCP, PKI | Q | ★★★ | 4 |
| M06-E46 | Mini-projet : socle MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 45 exercices + mini-projet · 9 break & fix · 4 questionnaires · 1 revue · 3 rédactions · 1 chronométré.

## Hôtes créés ou transformés dans ce module

| Hôte | VMID | Adresse | Rôle | Exercice |
|---|---|---|---|---|
| `ca01` | 1003 | 10.10.20.11 | step-ca (PKI TLS et SSH, ACME) | E02 |
| `nbx01` | 1005 | 10.10.20.13 | NetBox (source de vérité) | E04 |
| `dns01` | 1002 | 10.10.20.10 | dnsmasq → PowerDNS Recursor + Authoritative, Kea DHCPv4 | E06-E08, E16 |
| `dns02` | 1008 | 10.10.20.16 | Autoritaire secondaire, récurseur, Kea de secours | E24, E25 |

VMs d'essai du module : 2060-2069 (pool `lab`, VNet `vsandbox`). Toutes les nouvelles VMs sont créées par OpenTofu (module 05) et configurées par Ansible (module 04).

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 06 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 06 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
