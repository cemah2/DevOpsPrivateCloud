# Post-mortem — INC-2620 — Sauvegardes hors site interrompues (tunnel PAR1-PAR2 et datastore PBS)

> Exemple de corrigé M00-E46, pour la paire E43 variante 2 + E42 variante 3. Heures fictives.

| | |
|---|---|
| **Statut** | Relu |
| **Date de l'incident** | AAAA-MM-JJ |
| **Rédacteur** | <apprenant>, astreinte Plateforme |
| **Relecteurs** | Nadia Roussel, Karim Benali |
| **Sévérité** | P2 : aucune interruption de service utilisateur, mais perte de la capacité de sauvegarde et de restauration hors site (exigence HDS) |
| **Durée d'impact** | 02:10 → 08:31 (6 h 21) |
| **Services touchés** | sauvegarde et restauration depuis PAR2 ; accès d'administration à `pbs01` ; synchronisation NTP de `pbs01` |

## 1. Résumé

Dans la nuit, la sauvegarde planifiée des VMs du socle vers `pbs01` (site PAR2) a échoué. Deux causes
indépendantes se sont cumulées : le tunnel WireGuard PAR1-PAR2 ne transportait plus le réseau PAR2
(10.20.0.0/16 retiré des `AllowedIPs` de `gw01`), et le datastore `ds-lab` avait été placé en mode
maintenance « lecture seule ». La seconde cause était masquée par la première. Les deux ont été
corrigées à 07:58 et 08:24 ; une sauvegarde complète a réussi à 08:31. Aucune donnée perdue ; le RPO
du socle a atteint 30 h au lieu de 24 h.

## 2. Impact

- Aucune sauvegarde valide de la nuit pour `gw01`, `adm01`, `dns01` ; RPO effectif 30 h.
- Restauration depuis PAR2 impossible pendant 6 h 21 (aucune demande pendant la période).
- `pbs01` sans source NTP (dérive mesurée : 40 ms, sans conséquence).
- Conformité : écart au plan de sauvegarde à consigner au registre HDS (une nuit manquée).

## 3. Chronologie

| Heure | Événement | Source |
|---|---|---|
| J-1 18:40 | Modification de `/etc/wireguard/wg0.conf` sur `gw01` appliquée par `wg syncconf` (préparation d'un futur sous-réseau PAR2, non tracée) | `stat /etc/wireguard/wg0.conf` (date de modification), historique du shell de `gw01` |
| J-1 19:05 | `ds-lab` placé en mode maintenance `read-only` (vérification de disque prévue, jamais lancée) | journal des tâches PBS |
| 02:10 | Échec de la tâche de sauvegarde planifiée : `pbs-par2` injoignable | notification PVE, tâche `vzdump` |
| 06:52 | Alerte supervision : stockage `pbs-par2` inactif | interface PVE |
| 07:31 | Prise en charge par l'astreinte ; triage : 2 symptômes, hypothèse d'une cause unique (tunnel) | journal d'astreinte |
| 07:40 | Communication n° 1 (#astreinte) | canal |
| 07:44 | `wg show wg0` : poignée de main récente ; `ping 10.255.0.2` OK ; `ping 10.20.10.10` → `Required key not available` | journal |
| 07:49 | `wg show wg0 allowed-ips` : seul 10.255.0.2/32 ; route 10.20.0.0/16 toujours vers `wg0` | journal |
| 07:58 | Correction de `AllowedIPs` dans `wg0.conf`, `wg syncconf` ; `pbs-par2` actif | journal |
| 08:02 | Sauvegarde manuelle de `dns01` : **échec**, « datastore in maintenance mode » | tâche `vzdump` |
| 08:10 | Communication n° 2 : tunnel rétabli, seconde cause en analyse | canal |
| 08:16 | `proxmox-backup-manager datastore show ds-lab` : `maintenance-mode type=read-only` ; personne ne revendique de maintenance en cours (Karim confirmé par téléphone) | journal |
| 08:24 | Mode maintenance levé | journal des tâches PBS |
| 08:31 | Sauvegarde manuelle de `gw01`, `adm01`, `dns01` : réussie, notification de succès reçue | tâches `vzdump` |
| 08:35 | Communication n° 3 : résolu, surveillance du job de la nuit | canal |

## 4. Causes

### 4.1 Causes racines

1. **Routage par clé incomplet sur `gw01`.** `AllowedIPs = 10.255.0.2/32` pour le pair `pbs01` : WireGuard
   refusait d'émettre vers 10.20.10.10 (`ENOKEY`) et aurait rejeté tout paquet venant de PAR2. La route
   système 10.20.0.0/16 via `wg0`, créée au démarrage par `wg-quick`, n'a pas été modifiée par
   `wg syncconf` : l'incohérence route/AllowedIPs était invisible sans `wg show`.
   Preuve : `ping 10.20.10.10` → `sendmsg: Required key not available` ; `wg show wg0 allowed-ips`.
2. **Datastore en lecture seule.** `ds-lab` en mode maintenance `read-only` depuis la veille 19:05 ;
   les lectures (listes, restaurations) restaient possibles, les écritures étaient refusées.
   Preuve : `proxmox-backup-manager datastore show ds-lab`, message de la tâche de 08:02.

### 4.2 Facteurs contributifs

- Deux modifications à chaud sans ticket de changement ni annonce.
- Aucune supervision de l'état du datastore ni de la joignabilité **à travers** le tunnel (seulement l'état du stockage côté PVE, sondé toutes les heures).
- Notification d'échec reçue à 02:10 mais non lue avant 06:52 (pas d'astreinte de nuit pour une P2 : choix assumé, à confirmer).
- Masquage : la cause 2 ne pouvait apparaître qu'après la correction de la cause 1.

## 5. Détection et diagnostic

- Détection : notification d'échec à 02:10, alerte de supervision à 06:52, prise en charge à 07:31.
- Ce qui a accéléré : le message `Required key not available`, explicite ; le contrôle `lab/bin/check 00 43`.
- Ce qui a ralenti : l'hypothèse « cause unique » ; il a fallu une nouvelle sauvegarde pour révéler la seconde cause (8 minutes).
- Détection anticipée possible : une sonde TCP/8007 vers 10.20.10.10 depuis `pve01` (alerte dès 18:41 la veille), et une alerte « datastore en maintenance depuis plus de 2 h ».

## 6. Ce qui a bien fonctionné

- Communication toutes les 30 minutes, conforme au processus.
- Re-test complet après la première correction, qui a révélé la seconde cause avant de clore.
- Correction par `wg syncconf`, sans coupure des autres flux.

## 7. Actions

| # | Action | Type | Responsable | Échéance | Ticket |
|---|---|---|---|---|---|
| 1 | Sonde TCP/8007 vers `pbs01` depuis `pve01` et âge de la poignée de main `wg0` dans la supervision | détecter | Plateforme | J+7 | PLAT-061 |
| 2 | Alerte PBS : datastore en maintenance depuis plus de 2 h | détecter | Plateforme | J+7 | PLAT-062 |
| 3 | Alerte « âge de la dernière sauvegarde réussie > 26 h » par VM | détecter | Plateforme | J+7 | PLAT-063 |
| 4 | Toute modification de `gw01` et `pbs01` passe par un ticket CHG avec plan de retour arrière | prévenir | Claire Morel | immédiat | CHG-0921 |
| 5 | Contrôle de cohérence route/AllowedIPs ajouté au runbook RB-003 et au contrôle post-changement | prévenir | Plateforme | J+14 | PLAT-064 |
| 6 | Mention de l'écart de RPO au registre HDS | documenter | Sophie Laurent | J+2 | SEC-019 |

## 8. Enseignements

- Une poignée de main WireGuard récente prouve que le tunnel existe, pas qu'il transporte ce qu'on attend : superviser **à travers** le tunnel.
- Après une première correction, rejouer **tous** les tests initiaux : deux pannes simultanées sont plus fréquentes qu'on ne le croit quand des changements non tracés s'accumulent.
- Un mode « maintenance » sans date de fin est une panne programmée.

## Annexes

```
admin@gw01:~$ ping -c 1 10.20.10.10
PING 10.20.10.10 (10.20.10.10) 56(84) bytes of data.
ping: sendmsg: Required key not available
admin@gw01:~$ sudo wg show wg0 allowed-ips
<clé-publique-pbs01>	10.255.0.2/32
root@pbs01:~# proxmox-backup-manager datastore show ds-lab | grep -i maintenance
│ maintenance-mode │ type=read-only │
```
