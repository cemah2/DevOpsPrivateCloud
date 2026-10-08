# ADR-0100 — Réseau du cloud par ML2/OVN, répartiteurs Octavia par le fournisseur OVN

- Statut : acceptée
- Date : AAAA-MM-JJ (décision prise au déploiement, M10-E04 ; écrite et complétée par PLAT-1156, M10-E30)
- Décideurs : Claire Morel (responsable infrastructure), équipe Plateforme
- Consultés : Karim Benali (technique), Julien Petit (besoins des équipes), Sophie Laurent (sécurité)
- ADR liées : ADR-0101 (Kolla-Ansible comme outil de déploiement)

Cette ADR couvre deux décisions **liées** : le fournisseur OVN d'Octavia n'existe que si le réseau est OVN, et le choix d'Octavia pèse sur la capacité calculée pour le réseau. Les séparer obligerait à les relire ensemble.

## Contexte et problème

MédiSphère ouvre un IaaS interne (M10) : réseaux de projets isolés, routeurs, IP flottantes, groupes de sécurité, répartiteurs à la demande. Contraintes du lab et de la cible :
- un seul contrôleur (16 Go) et deux calculs de **8 Go** : chaque Go consommé par l'infrastructure est un Go de moins pour les équipes ;
- une petite équipe Plateforme, une astreinte (Nadia) qui doit dépanner sans expert réseau ;
- besoins exprimés par MédiAgenda (E31) : un répartiteur TCP devant deux serveurs d'application, adresse source des clients visible par l'application (journalisation HDS), pas de terminaison TLS demandée à ce stade (l'application termine le TLS elle-même) ;
- Kolla-Ansible 2026.1 : `neutron_plugin_agent: openvswitch` par défaut ; Octavia désactivé par défaut ; le mécanisme **Linux Bridge** de Neutron a été retiré (plus une option : tout tutoriel qui l'utilise est caduc).

## Facteurs de décision

1. Fonctions nécessaires aujourd'hui (E31) et probables demain (L7, TLS).
2. Ressources consommées sur des calculs de 8 Go.
3. Haute disponibilité et temps de bascule.
4. Diagnostic par l'astreinte (outils, compétences, documentation).
5. Sécurité (surface, secrets, réseaux de gestion).
6. Maturité et feuille de route en amont.
7. Coût d'un changement d'avis plus tard.

## Décision 1 — Réseau : ML2/OVN

### Options

| Critère | **ML2/OVN** (retenu) | ML2/Open vSwitch (agents) |
|---|---|---|
| Architecture | `ovn-northd` + bases Nord/Sud (Raft) sur le contrôleur, `ovn-controller` sur chaque châssis ; routage, DHCP, métadonnées (agent par calcul) et groupes de sécurité (ACL) programmés dans OVS | `neutron-openvswitch-agent` par nœud, agents L3 (espaces de noms, iptables), DHCP (dnsmasq), métadonnées sur les nœuds réseau ; échanges par RabbitMQ |
| Routage est-ouest | distribué sur chaque calcul (pas de passage par le nœud réseau) — mesuré en E24 : continue sans contrôleur | centralisé sur l'agent L3 (ou DVR, plus complexe) |
| IP flottantes / SNAT | par le *gateway chassis* (`osctl01`) ; distribuables (`neutron_ovn_distributed_fip`) au prix d'une carte externe par calcul | agent L3 (HA par VRRP entre nœuds réseau) ou DVR |
| Mémoire et processus | moins d'agents ; pas de dnsmasq ni d'espaces de noms par réseau/routeur | un dnsmasq par réseau, un espace de noms par routeur, agents Python sur chaque nœud |
| Charge RabbitMQ | faible (OVN a sa propre base) | forte (agents ↔ serveur) |
| HA | bases OVN en Raft (3 contrôleurs), bascule des *gateway chassis* par BFD (secondes) | L3 HA (keepalived dans les espaces de noms), bascule en secondes à dizaines de secondes |
| Diagnostic | `ovn-nbctl`, `ovn-sbctl`, `ovn-trace` (trace logique d'un paquet), `ovs-ofctl` ; abstraction de plus | `ip netns`, `iptables`, `tcpdump` dans les espaces de noms : connu des administrateurs Linux |
| Maturité | pilote de référence de Neutron en amont depuis plusieurs séries ; développements nouveaux concentrés sur OVN | mature, maintenu, mais moins d'évolutions |
| Prérequis Octavia OVN | **oui** | non disponible |

### Décision

**ML2/OVN** (`neutron_plugin_agent: "ovn"`), passerelle sur `osctl01`, IP flottantes non distribuées.

## Décision 2 — Répartiteurs : Octavia, fournisseur OVN (amphora en option future)

### Options

| Critère | **Fournisseur OVN** (retenu) | Fournisseur amphora | Pas d'Octavia (HAProxy dans les instances) |
|---|---|---|---|
| Couches | L4 seulement : TCP, UDP, SCTP | L4 et **L7** (HTTP, politiques et règles L7) | ce que l'équipe configure |
| Terminaison TLS | **non** | oui (`TERMINATED_HTTPS`, certificats dans Barbican) | oui, à la charge de l'équipe |
| Algorithmes | **`SOURCE_IP_PORT` seulement** | `ROUND_ROBIN`, `LEAST_CONNECTIONS`, `SOURCE_IP` | tous ceux d'HAProxy |
| Adresse source vue par les membres | **celle du client** (pas de traduction d'adresse) : les groupes de sécurité des membres doivent autoriser les clients | adresse de l'amphore (SNAT) ; client dans `X-Forwarded-For` en HTTP | selon configuration |
| Contrôles de santé | TCP, UDP-CONNECT, SCTP (adresse source propre au fournisseur, à autoriser dans les groupes de sécurité) | HTTP, HTTPS, TCP, PING, TLS-HELLO, UDP-CONNECT | à la charge de l'équipe |
| Ressources | **aucune VM** : règles OVN dans le chemin de données de chaque châssis | une VM amphore par répartiteur (deux en actif/passif), ≈ 1 Go chacune + image, gabarit, réseau de gestion `lb-mgmt-net`, certificats d'Octavia | deux instances par équipe, toujours |
| HA, bascule | inhérente (distribuée, pas de VM à reconstruire) | VRRP entre amphores (secondes) ; reconstruction d'une amphore perdue (minutes) | à la charge de l'équipe |
| Diagnostic | `ovn-nbctl lb-list`, statut Octavia | journaux d'amphore, SSH de gestion, health-manager | chez l'équipe |
| Sécurité | pas de VM de service ni de réseau de gestion à protéger | réseau de gestion entre contrôleur et amphores, certificats à faire tourner, images d'amphores à patcher | variable selon les équipes |

### Décision

**Octavia activé avec le seul fournisseur OVN** (`octavia_provider_drivers: "ovn:OVN provider"`, `octavia_provider_agents: "ovn"`). Le fournisseur amphora n'est pas déployé.

## Conséquences

Positives :
- aucune VM de service sur les calculs de 8 Go ; répartiteurs instantanés à créer et qui survivent à la perte du contrôleur (plan de données) ;
- adresse des clients visible par MédiAgenda sans en-tête à interpréter ;
- un seul plan réseau à maîtriser (OVN) pour le réseau et les répartiteurs.

Négatives (ce que Julien ne pourra **pas** demander) :
- pas de terminaison TLS ni de routage HTTP (chemin, en-têtes, redirections) : l'application termine son TLS, ou l'équipe ajoute un proxy L7 dans ses instances ;
- pas d'équilibrage `ROUND_ROBIN` : avec `SOURCE_IP_PORT`, la répartition dépend du port source des clients (bonne sur beaucoup de connexions, inégale sur peu) ;
- les groupes de sécurité des membres doivent laisser entrer les **clients** (et l'adresse des contrôles de santé) : piège classique documenté dans `libre-service.md` ;
- statistiques et observabilité plus pauvres qu'avec HAProxy ;
- IP flottantes centralisées sur `osctl01` : la perte du contrôleur coupe le nord-sud (E24) tant qu'il n'y a pas trois nœuds réseau ou des IP flottantes distribuées ;
- l'astreinte doit apprendre `ovn-trace` et la lecture des bases OVN (formation, runbooks du palier 4).

## Conditions de révision

La décision 2 est rouverte si l'une de ces conditions est mesurée :
- au moins **deux** équipes demandent, dans un trimestre, une terminaison TLS ou du routage L7 qu'un proxy dans leurs instances ne peut pas raisonnablement fournir (tickets DEV-) ;
- la capacité des calculs dépasse **32 Go** allouables par nœud (le coût mémoire des amphores devient marginal) ;
- un besoin réglementaire impose une inspection ou une journalisation HTTP centralisée au point d'entrée.

La décision 1 est rouverte si : une régression d'OVN bloque une montée de série ; ou l'astreinte enregistre plus de trois incidents réseau par trimestre non résolus faute de compétence OVN malgré la formation.

Effort d'un retour arrière : réseau OVN → OVS = migration lourde (outil de migration de Neutron, fenêtre longue) : à éviter, d'où l'importance de la décision 1. Ajout d'amphora = activation d'un fournisseur supplémentaire dans Kolla (réseau de gestion, image, certificats), sans toucher aux répartiteurs OVN existants.

## Sources

- Mesures du module : E16 (Octavia OVN), E24 (continuité sans contrôleur : est-ouest maintenu, nord-sud coupé), E31 (adresse source et groupes de sécurité).
- Kolla-Ansible 2026.1 : *Neutron* (OVN), *Octavia* (fournisseur OVN), valeurs par défaut (`group_vars/all/`), notes de version (retrait de Linux Bridge).
- ovn-octavia-provider : *OVN as a Provider Driver for Octavia* (limitations).
- Octavia : *Provider feature support matrix*.

## Relecture

| Relecteur | Avis |
|---|---|
| Karim Benali | Favorable. Demande que `ovn-trace` figure dans les runbooks du palier 4. |
| Julien Petit | Favorable pour la recette ; la production de MédiAgenda terminera le TLS dans l'application (ADR applicative à venir). Condition de révision « deux équipes » acceptée. |
| Sophie Laurent | Favorable : pas de réseau de gestion d'amphores ni de certificats supplémentaires à gérer. Rappelle que l'adresse client visible impose des groupes de sécurité précis (relu dans E31). |
