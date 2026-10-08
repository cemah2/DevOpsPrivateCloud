# Module 07 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

### M07-E46 — Mini-projet : socle MédiSphère v2

Il n'y a pas de solution unique : ce corrigé donne un **plan de travail**, les points de contrôle, le déroulé de la démonstration et la **grille de revue**. Les fichiers de référence sont ceux des exercices (`corrige/fichiers/M07-EXX/`) ; seul [`docs/socle/reseau/architecture.md`](fichiers/M07-E46/medisphere/docs/socle/reseau/architecture.md) est nouveau.

**Solution**

*Plan de travail recommandé*

1. **État des lieux** (1 h) : `lab/bin/check 07 46`, puis les contrôles détaillés rouges (`07 24` à `07 30`, `07 12`, `07 13`, `07 15`, `07 16`). Recenser ce qui vise encore une adresse propre :
   ```
   root@pve01:~# ip route | grep -E '10\.(10|20)\.0\.0/16|10\.255\.1\.0/24'           # via <IP-GW-WAN-VIP>
   root@pbs01:~# grep -E 'Endpoint' /etc/wireguard/wg0.conf                           # <IP-GW-WAN-VIP>:51820
   admin@adm01:~/src$ grep -rnE '10\.10\.[0-9]+\.1\b' ansible/inventories ansible/roles infra outils/etc | grep -v '/24'
   ```
   Chaque occurrence restante est soit une VIP **voulue** (passerelle par défaut des VMs, extrémité vue par LYO1, options DHCP), soit à corriger.
2. **Aligner le code** (2 à 3 h) : `routeurs.yml --check --diff` à `changed=0` sur les deux passerelles, idem pour les répartiteurs ; `tofu plan` de l'état `socle` sans changement ; jeux de règles identiques (`nft -s list ruleset`) ; configurations HAProxy identiques au nom près.
3. **Lyon en attente** : dans FRR, `neighbor 10.255.2.2 shutdown` (la session apparaît « Idle (Admin) » : ni alerte, ni tentative de connexion) ; le pair `wg2` reste dans `wireguard.yml` (aucun effet sans pair) ; `MS_BGP_MAITRE` et `MS_BGP_TOUS` de `ms-verif-reseau.conf` vidés, avec un commentaire qui explique comment les rétablir. La règle d'entrée `wg2` reste dans la matrice, marquée « en attente » dans son motif.
4. **MTU** : deux VMs jetables du VLAN 30 (MTU 9000 sur la carte Proxmox et dans l'invité), `ping -M do -s 8972` de l'une à l'autre, **et** vers 10.10.30.2 et 10.10.30.3 (les deux passerelles), puis destruction des VMs.
5. **Maquette** (1 h) : `tofu destroy` de l'état `m07-maquette` (dix VMs ; l'état reste, vide) ; VNets `vfab1-8` : conservées si tu comptes rejouer la maquette (une VNet vide ne coûte rien) ou retirées par le même code (choix noté) ; reconstruction documentée dans `reseau/architecture.md` et prouvée par un `tofu plan` qui annonce les dix VMs. `leaf01` disparu : retirer `10.10.99.251` des voisins attendus de la supervision (sa session tombe : la règle du voisin peut rester dans FRR en `shutdown`, comme Lyon).
6. **Exploitation et documentation** (3 à 4 h) : `ms-verif-reseau` et `ms-verif-services` verts ; runbooks RB-070, RB-071, RB-072 relus (RB-071 joué de bout en bout) ; `reseau/architecture.md` ; ADR-0070 ; matrice générée ; inventaire du socle et NetBox (`gw02`, `lb01`, `lb02`, groupes FHRP) ; registre des secrets (clés WireGuard des passerelles, empreintes et mots de passe des statistiques HAProxy, clé de supervision, jeton de lecture de la CI pour la matrice).
7. **Répétition de la démonstration** (1 h, deux fois), puis **livraison** : MR fusionnées, pipelines verts, `lab/bin/check 07 46` vert, étiquette `socle-v2`.

*Démonstration de référence*

| Temps | Action | Ce qu'on montre |
|---|---|---|
| T−5 min | `ms-verif-reseau` vert ; `cat /run/bordure/etat` sur les deux passerelles | état nominal : `gw01` maître |
| T−2 min | depuis le LAN maison : `git clone` d'un dépôt de 1 à 2 Go par `https://gitlab.par1.medisphere.internal` (résolu vers la VIP WAN, redirection 443) ; depuis le VPN : consultation de NetBox ; `ms-mesure-bascule` vers 10.10.20.10 depuis une VM du VLAN 99 et vers `pve01` depuis `adm01` | trafic réel, traduit et redirigé |
| T0 | Nadia : `qm stop 1000` | panne franche, sans prévenir |
| T+5 s | `cat /run/bordure/etat` sur `gw02` : `MASTER` ; mesures : ≈ 3,6 s de perte | la bordure a basculé |
| T+1 min | le clone continue (somme de contrôle à la fin) ; NetBox répond ; `ms-verif-reseau` : seule la redondance est rouge, alerte reçue | les connexions ont survécu (conntrackd) |
| T+5 min | `qm start 1000` ; `gw01` revient en `BACKUP` (`nopreempt`) | pas de seconde coupure |
| T+10 min | RB-071 §3 joué par Nadia : retour sur `gw01` (≈ 0,6 s) ; `ms-verif-reseau` vert | retour planifié, sans le concepteur |

**Explications**

Le mini-projet vérifie l'**intégration** : chaque mécanisme a été construit dans un exercice ; leur valeur vient de ce qu'ils basculent **ensemble** (VIP, traduction, tunnels, connexions) et de ce que rien autour (hyperviseur, site de sauvegarde, postes, supervision) ne s'accroche à une passerelle précise. Le contrôle global revérifie les acquis du module 06 **à travers** la nouvelle bordure : les résolveurs, la PKI et NetBox doivent répondre par la VIP des VLAN, et GitLab et NetBox par leurs noms publiés ; une régression du socle est le risque principal d'un module qui a changé l'adresse de la passerelle de tous les réseaux.

**Alternatives**
- Garder la maquette LYO1 (agence raccordée en permanence) : réaliste, mais 2 Go de mémoire et deux VMs à entretenir pendant tout le bloc B ; la décision du module est de la détruire et de garder le code.
- Préemption au lieu de `nopreempt` : la démonstration montrerait deux coupures (départ et retour automatique) ; défendable si l'équipe préfère un état nominal invariable.

**Pièges classiques**
- Un contrôle de M06 qui vise `10.10.10.1` pour `gw01` : il vise maintenant la VIP (la passerelle active). Les contrôles de M06 qui parlent de `gw01` par son **nom** restent justes.
- Détruire la maquette « à la main » dans Proxmox : l'état `m07-maquette` croit les VMs présentes ; le prochain `apply` les recrée.
- Une alerte de supervision laissée rouge (Lyon, `leaf01`) pendant la recette : on finit par ne plus regarder les alertes.
- Oublier de supprimer la règle d'amorçage de `gw02` (E24) ou une règle `TEST-E32`.
- Étiquette `socle-v2` posée avant la fusion de la documentation.

**En production chez MédiSphère**
La recette inclurait une seconde démonstration de panne **de nuit**, sans l'équipe Plateforme, avec l'astreinte seule et les runbooks (préparation de F3), et la mesure serait versée au dossier de continuité d'activité.

**Grille de revue (auto-évaluation si tu travailles seul)**

| Relecteur | Critère | Attendu |
|---|---|---|
| Claire | Contrôle global | `lab/bin/check 07 46` entièrement vert, sans contrôle ignoré |
| Claire | Démonstration | panne franche de la passerelle active : perte mesurée ≤ 5 s, clone et navigation non interrompus, retour par RB-071 |
| Claire | Points uniques restants | listés dans `reseau/architecture.md` (`pve01`, box, LAN maison, `ca01`, `nbx01`, `s3-01`) avec leur impact et le module qui les traitera |
| Karim | Code | `routeurs.yml` et `repartiteurs.yml` à `changed=0`, `tofu plan` sans changement, jeux de règles et configurations identiques sur chaque paire |
| Karim | ADR-0070 | options comparées sur les mêmes critères, décision appuyée par les mesures, conditions de révision |
| Karim | Règle des adresses propres | aucun outil, voisin ou pair ne vise une VIP pour joindre une passerelle précise ; aucune extrémité externe ne vise une adresse propre |
| Sophie | Matrice v2 | générée depuis le code, chaque règle référencée, BGP/VRRP/conntrackd limités à leurs sources, DMZ filtrée localement |
| Sophie | Secrets | clés WireGuard en Vault `critique`, identiques sur les deux passerelles, inscrites au registre ; empreintes (pas de mots de passe) dans HAProxy ; clé de supervision limitée par commande forcée |
| Nadia | Runbooks | RB-070 et RB-071 jouables par un tiers ; cas anormaux (cerveau divisé, aucune VIP) traités |
| Nadia | Supervision | `ms-verif-reseau` vert, alertes testées, mesures exportées pour le module 21 |
| Julien | Points d'entrée | GitLab et NetBox par leurs noms publiés, TLS 1.2+, HSTS ; service de M07-E34 retiré |
| Tous | Présentation | 10 minutes : avant/après, chiffres, risques, ce que le module 08 consommera (VLAN 30/31 en MTU 9000, publication de RGW) |

Une livraison est acceptée quand tous les critères sont remplis ; un critère manquant est noté comme action (responsable, échéance) dans le compte rendu de recette.
