# ADR-0110 — Outil de provisioning bare-metal

- **Statut** : accepté
- **Date** : <AAAA-MM-JJ>
- **Décideurs** : Claire Morel ; consultés : Sophie Laurent, Karim Benali, Nadia Roussel
- **Ticket** : PLAT-1233

## Contexte

52 serveurs à installer d'ici six mois (40 à PAR1, 12 à PAR2), deux constructeurs (contrôleurs Redfish), puis ~20 par an ; équipe Plateforme de quatre personnes. Exigences : HDS (traçabilité, isolation, secrets), NetBox source de vérité (ADR-0060), DHCP du socle par Kea (`dns01`/`dns02`), PKI step-ca, systèmes Debian 13, Rocky 10 et Proxmox VE 9.

Mesures du module 11 (lab) : installation Debian par la chaîne maison <…> min, Rocky <…> min, PVE <…> min ; MAAS : déploiement Ubuntu <…> min, 9 gestes manuels pour le mettre en service (DHCP à basculer, images, pilote Proxmox, TLS du snap), DHCP en conflit avec Kea ; chaîne maison : 0 geste après la déclaration NetBox (E15).

## Options

| Critère | MAAS 3.7 | Tinkerbell | Chaîne maison (NetBox + Kea + `pxe01`) |
|---|---|---|---|
| Qui fait foi | base de MAAS (synchronisation NetBox à écrire) | ressources Kubernetes (`Hardware`, `Workflow`) | **NetBox** |
| DHCP | le sien (ou relais vers lui) : Kea retiré du VLAN | le sien (Smee) ou externe | Kea du socle (HA, DDNS) |
| Systèmes | Ubuntu de première classe ; autres par images personnalisées (Packer MAAS) | images (tout ce qui s'écrit sur disque) | Debian, Rocky, PVE par leurs installateurs officiels |
| Contrôleurs | Redfish, IPMI, Proxmox… intégrés | Rufio (Redfish, IPMI) | Redfish par script (E08, E18) ; VMs par l'API Proxmox |
| Découverte du matériel, tests, effacement | **intégrés** (*commissioning*, *hardware tests*, *erase*) | partiels (actions de workflow) | à écrire |
| Dépendances d'exécution | Ubuntu + snap + PostgreSQL | **Kubernetes** (module 14, pas encore en production) | rien de plus que le socle |
| Sécurité | comptes MAAS, TLS à configurer, snap à suivre | RBAC Kubernetes | celle du socle (step-ca, Vault, matrice des flux) ; chaîne HTTPS (ADR-0111) |
| Exploitation, montées de version | snap à canal suivi, migrations PostgreSQL | chart Helm, projet jeune | nos scripts : à maintenir, tests dans le pipeline |
| Compétences | nouvelles (MAAS, Ubuntu) | Kubernetes avancé | déjà acquises (Kea, nginx, Ansible, Python) |
| Pérennité | Canonical, AGPL | CNCF (sandbox), communauté | interne |

## Décision

**Chaîne maison**, parce qu'elle garde NetBox comme seule source de vérité et Kea comme seul DHCP, n'ajoute aucune dépendance d'exécution, et qu'elle a installé nos trois systèmes sans geste humain dans le lab. MAAS est **retiré** (`maas01` détruite, compte `wb-maas` supprimé) ; Tinkerbell est **en veille** jusqu'à la mise en production de Kubernetes (module 14).

Révision si : plus de 150 serveurs ou plus de 3 constructeurs ; besoin de *commissioning*/effacement certifié que nous ne savons pas couvrir en 3 mois ; Kubernetes de production disponible (réévaluer Tinkerbell).

## Conséquences

- Positives : une seule source de vérité ; pas de second DHCP ; sécurité alignée sur le socle.
- Négatives : découverte du matériel, tests de *commissioning*, effacement sécurisé et mise à jour des firmwares sont **à notre charge** ; pas d'interface pour les autres équipes ; dépendance à nos scripts (`netbox-provision.py`, `provisionner.py`).
- Actions : effacement sécurisé (procédure, F6) — Sophie ; inventaire Redfish étendu aux nouveaux serveurs (E18) — Nadia ; tests d'installation complets dans le pipeline — Karim ; `maas01` et `wb-maas` retirés au mini-projet M11-E25 ; réévaluation Tinkerbell après le module 14.
