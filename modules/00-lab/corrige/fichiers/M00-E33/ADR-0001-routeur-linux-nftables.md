# ADR-0001 — Construire le routeur/pare-feu du lab sur Debian + nftables

- Statut : accepté
- Date : 2026-10-XX
- Décideurs : Claire Morel (responsable infrastructure), équipe Plateforme
- Consultés : Karim Benali (ingénieur plateforme senior), Sophie Laurent (RSSI)

## Contexte et problème

Le site PAR1 est isolé du réseau d'accueil sur un bridge dédié (`vmbr1`) portant 13 VLANs. Il faut une fonction de routage inter-VLAN, de filtrage, de NAT sortant, de terminaison VPN (site-à-site vers PAR2 et accès d'administration), de relais DHCP et de serveur de temps. Cette brique est sur le chemin critique de tout le reste (GitLab, NetBox, Kubernetes, OpenStack) et sera reproduite en haute disponibilité au module 07. Quelle implémentation retenir ?

## Facteurs de décision

- Maîtrise et diagnostic : l'équipe doit comprendre et dépanner chaque paquet (pannes M00-E38 à E46, F3 astreinte).
- Automatisation : configuration en fichiers texte, versionnable dans Git et pilotable par Ansible (module 04) puis générée depuis NetBox (module 06).
- Évolutivité : BGP/OSPF avec FRR (module 07, 15), VRRP avec keepalived, WireGuard multi-sites.
- Ressources du lab : 1 vCPU / 1-2 Go maximum pour cette fonction (budget mémoire PLAN §3.3).
- Conformité HDS / ISO 27001 : règles relues en MR, traçabilité des changements, journalisation.
- Coût : aucune licence.

## Options envisagées

1. VM Debian 13 + nftables + WireGuard + chrony + relais DHCP (routeur Linux « à la main »).
2. Appliance OPNsense (ou pfSense CE) en VM.
3. Fonctions intégrées de Proxmox : zone SDN Simple avec SNAT et passerelle portée par l'hôte.

## Décision

Option retenue : « VM Debian + nftables », parce qu'elle est la seule qui satisfait à la fois la maîtrise fine (chaque règle est un texte lisible et testable), l'automatisation par Git/Ansible sans API propriétaire, et l'évolution vers FRR/keepalived que demandent les modules 07 et 15, dans un budget de 1 Go de RAM.

### Conséquences

- Positives : configuration entièrement textuelle et versionnée ; mêmes outils de diagnostic que sur n'importe quel serveur Linux (`nft`, `ip`, `tcpdump`, `conntrack`) ; terrain d'exercice pour les pannes ; aucune dépendance à l'hyperviseur.
- Négatives :
  - pas d'interface graphique ni de journal de pare-feu consultable par un non-spécialiste ;
  - point unique de défaillance (une seule VM) tant que le module 07 n'a pas ajouté `gw02` + VRRP (adresses `.2-.3` réservées) ;
  - la qualité dépend de la rigueur de l'équipe (pas de garde-fous d'une appliance) ;
  - mises à jour de sécurité à gérer comme pour tout serveur Debian.
- Actions induites :
  - règles nftables relues en MR (module 01) et déployées par Ansible (module 04) ;
  - sauvegarde PBS quotidienne de `gw01` et restauration testée (M00-E37, « pour aller plus loin ») ;
  - supervision de `gw01` (module 21) ; journalisation des refus vers Loki (module 22) ;
  - haute disponibilité VRRP au module 07 ;
  - revue de cette décision si l'équipe Réseau est créée ou si un besoin d'IDS/IPS apparaît.

## Analyse des options

### VM Debian + nftables
- Pour : maîtrise totale, fichiers texte, compatible Ansible/Git, FRR/keepalived natifs, empreinte minimale, compétence Linux transférable.
- Contre : tout est à construire (pas d'interface, pas de modèles) ; risque d'erreur humaine plus élevé ; HA à construire.

### OPNsense / pfSense en VM
- Pour : interface web complète, HA CARP intégrée, nombreux plugins (IDS Suricata, HAProxy, ACME), journalisation consultable, familier pour beaucoup d'équipes réseau.
- Contre : configuration dans un XML monolithique, peu adaptée à la revue de code et à Ansible ; FreeBSD (compétence différente du reste de la plateforme) ; empreinte mémoire plus élevée ; on apprend l'outil plutôt que le mécanisme ; licence et support commerciaux pour pfSense Plus.

### SDN Proxmox (zone Simple + SNAT)
- Pour : zéro VM à gérer, intégré à l'hyperviseur, DHCP/IPAM intégrés.
- Contre : la passerelle et le NAT vivent sur l'hôte, qui devient routeur et pare-feu (surface d'attaque, mélange des rôles) ; pas de VPN, pas de relais DHCP, filtrage inter-VLAN limité au pare-feu Proxmox ; ne fonctionne pas avec une zone VLAN ; peu d'occasions d'apprendre le routage ; couplage fort à `pve01` (perte de l'hôte = perte du routage, sans possibilité de restaurer la fonction ailleurs).

## Liens

- PLAN.md §4.1 et §4.3 bis ; tickets PLAT-110 (construction de `gw01`), PLAT-128 (SDN).
- ADR à venir : haute disponibilité de la passerelle (module 07).
