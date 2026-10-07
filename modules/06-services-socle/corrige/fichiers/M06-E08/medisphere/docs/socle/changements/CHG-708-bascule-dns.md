# CHG-708 — Bascule du DNS du lab de dnsmasq vers PowerDNS

| | |
|---|---|
| Demandeur | Claire Morel |
| Réalisation | équipe Plateforme (`<MOI>`) |
| Relecture | Karim Benali (MR de bascule), Nadia Roussel (procédure) |
| Type | Changement normal, planifié, avec fenêtre annoncée |
| Hôte | `dns01` (VMID 1002, 10.10.20.10) |
| Date prévue | `<DATE>` à `<HEURE>` (créneau sans pipeline planifié) |
| Durée de la fenêtre | 30 minutes (opération : 1 minute ; contrôles : 15 minutes) |
| Impact attendu | aucune résolution en échec ; latence de quelques secondes possible pour les questions posées pendant ~1 s |

## 1. Objet

Le port 53 de 10.10.20.10 (résolveur de tout le lab) passe de dnsmasq à PowerDNS Recursor 5.4, qui relaie les zones internes à PowerDNS Authoritative 5.0 (127.0.0.1:5300). dnsmasq continue de servir le DHCP du VLAN 99 jusqu'à M06-E16 (Kea).

## 2. Préalables (à cocher la veille)

- [ ] PowerDNS Authoritative sert les cinq zones (`medisphere.internal`, `par1…`, `par2…`, `10.10.in-addr.arpa`, `20.10.in-addr.arpa`) : `lab/bin/check 06 06` vert.
- [ ] Le Recursor d'essai répond sur 10.10.20.10:5301 : `lab/bin/check 06 07` vert.
- [ ] `comparer-resolveurs.sh` (dnsmasq :53 contre Recursor :5301) : **0 écart** sur les questions de référence. Résultat joint à la MR.
- [ ] MR de bascule relue et approuvée (`dnsmasq_dns_actif: false`, `powerdns_recursor_ecoute` sur le port 53), **non fusionnée** avant le créneau.
- [ ] Instantané de `dns01` possible : `ms-snapshot --prefix avant-chg708 1002`.
- [ ] Accès console à `dns01` vérifié (`qm terminal 1002` depuis `pve01`).
- [ ] Annonce faite (canal de l'équipe) : créneau, impact attendu, contact.

## 3. Déroulé

| # | Action | Qui / où | Contrôle |
|---|---|---|---|
| 1 | Instantané : `ms-snapshot --prefix avant-chg708 1002` | `adm01` | instantané listé |
| 2 | Sonde de 3 minutes lancée **avant** la bascule : `sonde-continue.sh -d 180` (et une seconde depuis une VM sandbox) | `adm01` | la sonde tourne, aucun échec |
| 3 | Fusion de la MR, puis job `appliquer` avec le playbook `playbooks/bascule-dns.yml` (ou, à défaut, depuis `adm01` : `uv run ansible-playbook playbooks/bascule-dns.yml`) | forge | job vert |
| 4 | Contrôle immédiat : `dig @10.10.20.10 CH TXT version.bind` répond PowerDNS ; `ss -lnup 'sport = :53'` sur `dns01` ne montre que `pdns_recursor` | `adm01`, `dns01` | conforme |
| 5 | Bilan de la sonde : 0 échec « client » | `adm01` | joint au ticket |
| 6 | `lab/bin/check 06 08` | `adm01` | vert |
| 7 | Passage complet `site.yml --check` : aucun changement sur `dns01` | forge | `changed=0` |
| 8 | Suppression de l'instantané après 24 h sans incident | `adm01` | — |

## 4. Retour arrière

- **Automatique** : si un contrôle du playbook échoue, il remet les deux configurations précédentes, rend le port 53 à dnsmasq et s'arrête en erreur. Ensuite : `git revert` de la MR **avant** tout nouveau passage de `site.yml` (sinon il refait la bascule).
- **Manuel**, si un problème apparaît après coup (dans les 24 h) : revert de la MR de bascule, puis `playbooks/bascule-dns.yml` n'est pas fait pour revenir en arrière ; appliquer `playbooks/dns01.yml` après le revert : le Recursor quitte le port 53 (retour sur 5301), dnsmasq le reprend. Fenêtre de refus d'une à deux secondes (pas de table « silence »).
- **Dernier recours** : retour à l'instantané `avant-chg708` (perd les baux DHCP émis entre-temps).

## 5. Effets connus

- Les noms des baux DHCP du VLAN 99 (`sbxNN.par1.medisphere.internal`), publiés jusqu'ici par dnsmasq, ne sont plus résolus : retour avec la mise à jour dynamique du DNS par Kea (M06-E17).
- `dns01` n'a plus de cache dnsmasq : le premier accès à chaque nom Internet est un peu plus lent (cache vide du Recursor).

## 6. Compte rendu (à remplir après)

| | |
|---|---|
| Début / fin | |
| Résultat de la sonde (questions, échecs bruts, échecs client, pire latence) | |
| Écarts au déroulé | |
| Incidents | |
