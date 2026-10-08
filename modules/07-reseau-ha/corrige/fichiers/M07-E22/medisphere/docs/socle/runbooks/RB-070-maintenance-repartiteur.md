# RB-070 — Maintenance d'un répartiteur (`lb01`, `lb02`)

| | |
|---|---|
| Quand | Mise à jour des paquets (HAProxy, keepalived, noyau), redémarrage, changement de configuration hors pipeline habituel, reconstruction d'un répartiteur |
| Pas ici | Ajout d'un service publié (MR sur `group_vars/role_lb/`, appliquée par le pipeline : sans coupure) ; panne en cours (RB-072, puis ce runbook pour remettre en service) ; changement de la VIP ou du VRID (changement `CHG-` dédié) |
| Qui | Équipe Plateforme ; astreinte pour l'étape « répartiteur en attente » seulement |
| Durée | 30 min par répartiteur ; fenêtre annoncée pour le maître (coupure des connexions longues) |
| Accès | `adm01`, `sudo` sur `lb01`/`lb02`, console Proxmox (`qm terminal 1010`/`1011`) |
| Références | ADR-0071 (pas de préemption, écoute sur toutes les adresses), RB-060 (reconstruction), RB-072 (diagnostic), `docs/socle/publication-services.md` |

## Ce qu'il faut savoir avant

- La VIP 10.10.70.200 n'a **pas de préemption** : un répartiteur qui revient ne la reprend pas.
  Le retour à la situation nominale (VIP sur `lb01`) est une étape **à part** (§4).
- Déplacer la VIP **coupe** les connexions en cours sur l'ancien maître (aucune synchronisation
  d'état) : clones et poussées Git en HTTPS, sessions WebSocket de GitLab, téléchargements longs.
- Les deux répartiteurs écoutent sur toutes leurs adresses : chacun se teste **en direct**
  (`curl --resolve`), y compris celui qui attend.
- keepalived suit HAProxy : un HAProxy arrêté sur le maître fait **basculer** la VIP. On n'arrête
  donc jamais HAProxy sur le maître pour « le mettre en maintenance » : on déplace d'abord la VIP.

Variables de la procédure : `CIBLE` (le répartiteur à traiter), `AUTRE` (l'autre).

## 0. Contrôles d'entrée — ARRÊT si l'un échoue

```
admin@adm01:~$ CIBLE=lb02 ; AUTRE=lb01
admin@adm01:~$ for h in lb01 lb02; do echo "$h: $(ssh $h 'ip -o -4 addr show dev ens18 | grep -c " 10.10.70.200/"')"; done
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt \
    --resolve lb.par1.medisphere.internal:443:$(dig +short $AUTRE.par1.medisphere.internal) https://lb.par1.medisphere.internal/sante
admin@adm01:~$ ssh $AUTRE 'echo "show stat" | sudo socat stdio unix-connect:/run/haproxy/admin.sock' | awk -F, '$2 ~ /^(git01|nbx01)$/ {print $1, $2, $18}'
admin@adm01:~$ ssh $AUTRE 'systemctl is-active keepalived haproxy'
```
Attendus : **une seule** VIP portée ; `AUTRE` répond `200` en direct ; tous les serveurs publiés
`UP` vus par `AUTRE` ; ses deux services `active`. Sinon : **ne pas continuer**, ouvrir un ticket
(RB-072). Noter dans le ticket qui porte la VIP au départ.

Annonce (si `CIBLE` porte la VIP) : canal de l'équipe et équipes de développement, « coupure des
connexions longues vers GitLab/NetBox à <HH:MM>, < 5 s ».

## 1. Instantané

```
admin@adm01:~$ ms-snapshot --prefix avant-rb070 $( [ "$CIBLE" = lb01 ] && echo 1010 || echo 1011 )
```
Contrôle : l'instantané apparaît dans `qm listsnapshot <VMID>` sur `pve01`.

## 2. Si `CIBLE` porte la VIP : la déplacer de façon contrôlée

1. **Vider** les nouvelles connexions de `CIBLE` sans les couper : rien à faire côté HAProxy (la
   VIP décide d'où arrivent les clients). On réduit seulement le temps de bascule perçu.
2. **Déplacer la VIP** en arrêtant keepalived sur `CIBLE` (HAProxy continue de servir les
   connexions déjà établies sur son adresse propre, le temps qu'elles se terminent) :
   ```
   admin@adm01:~$ ssh $CIBLE sudo systemctl stop keepalived
   admin@adm01:~$ ssh $AUTRE 'ip -o -4 addr show dev ens18 | grep " 10.10.70.200/"'      # la VIP est arrivée
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' --cacert … https://lb.par1.medisphere.internal/sante   # 200
   ```
   Arrêter keepalived envoie une annonce de priorité 0 : `AUTRE` prend la VIP en moins d'une
   seconde (pas d'attente du délai de détection).
3. **Attendre la fin des connexions** encore ouvertes sur `CIBLE` :
   ```
   admin@adm01:~$ ssh $CIBLE 'echo "show info" | sudo socat stdio unix-connect:/run/haproxy/admin.sock | grep -E "^CurrConns"'
   ```
   Attendre `CurrConns: 0`, au plus **10 minutes** (au-delà : connexions WebSocket qui ne finiront
   pas d'elles-mêmes ; noter et continuer). La durée vient des délais d'HAProxy (`timeout tunnel 1h`
   pour GitLab) : on n'attend pas une heure, on accepte de couper ce qui reste.

Si `CIBLE` ne porte pas la VIP : arrêter keepalived quand même (évite qu'il ne la prenne pendant
l'intervention si `AUTRE` défaillait — on préfère alors une alerte franche).

**Retour arrière de l'étape 2** : `ssh $CIBLE sudo systemctl start keepalived` (pas de préemption :
la VIP reste sur `AUTRE`, ce qui est sans risque).

## 3. Intervenir sur `CIBLE`

Selon le cas :
- **Paquets** : `sudo apt-get update && sudo apt-get -y upgrade` ; vérifier que HAProxy reste en
  3.2 (`haproxy -v`) ; redémarrer si le noyau ou la libc a changé (`/run/reboot-required`).
- **Configuration** : appliquer par le pipeline (`playbooks/repartiteurs.yml --limit $CIBLE`) ;
  l'application recharge HAProxy, ce qui est sans effet sur les clients (aucun).
- **Redémarrage** : `ssh $CIBLE sudo systemctl reboot`, puis attendre le retour SSH.

Contrôles après intervention :
```
admin@adm01:~$ ssh $CIBLE 'sudo haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl is-active haproxy'
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' --cacert … --resolve lb.par1.medisphere.internal:443:<IP-CIBLE> https://lb.par1.medisphere.internal/sante
admin@adm01:~$ for n in gitlab netbox; do curl -s -o /dev/null -w "$n %{http_code}\n" --cacert … --resolve $n.par1.medisphere.internal:443:<IP-CIBLE> https://$n.par1.medisphere.internal/; done
admin@adm01:~$ ssh $CIBLE 'echo "show stat" | sudo socat stdio unix-connect:/run/haproxy/admin.sock' | awk -F, '$2 ~ /^(git01|nbx01)$/ {print $2, $18}'
```
Attendus : configuration valide, `200` en direct, services publiés servis par `CIBLE`, serveurs `UP`.

**Retour arrière de l'étape 3** : restaurer l'instantané (`qm rollback <VMID> avant-rb070-…`) si
`CIBLE` ne revient pas sain en 15 minutes ; la VIP est sur `AUTRE`, le service n'est pas touché.

## 4. Remettre `CIBLE` en attente, puis revenir à la situation nominale

```
admin@adm01:~$ ssh $CIBLE sudo systemctl start keepalived
admin@adm01:~$ ssh $CIBLE 'journalctl -u keepalived -n 5 --no-pager'        # « Entering BACKUP STATE »
```
Attendu : `CIBLE` en BACKUP, VIP toujours sur `AUTRE`, **une seule** VIP portée.

**Retour à `lb01` maître** (seulement si `lb01` vient d'être traité et porte désormais la
priorité la plus haute, dans une fenêtre annoncée, car c'est une nouvelle coupure des connexions
longues) : appliquer l'étape 2 à `lb02` (arrêt de keepalived sur `lb02` → VIP sur `lb01`), puis
`ssh lb02 sudo systemctl start keepalived`. On peut aussi **ne pas** revenir : sans préemption,
`lb02` maître est une situation saine ; noter dans le ticket qui porte la VIP.

## 5. Clore

- Supprimer l'instantané (`ms-snapshot` ou `qm delsnapshot`) une fois la situation stable 24 h.
- Ticket : heure de chaque étape, durée de coupure mesurée côté client, connexions coupées.
- Si les deux répartiteurs sont à traiter : `lb02` d'abord (en attente : aucune coupure), puis
  `lb01` (une coupure), et rester sur `lb02` maître jusqu'à la fenêtre de retour.

## Reconstruire un répartiteur

Suivre RB-060 (`tofu apply -replace` du module `repartiteur["<CIBLE>"]` dans l'état `socle`, puis
`site.yml`). Propre aux répartiteurs : l'autre porte la VIP pendant toute l'opération (contrôles
d'entrée §0) ; le nouveau répartiteur obtient ses certificats par ACME **au premier passage** de
`repartiteurs.yml` (le défi est relayé par `AUTRE`, qui tient la VIP) ; keepalived démarre BACKUP.

## Pièges connus

- Arrêter **HAProxy** sur le maître au lieu de keepalived : la VIP bascule aussi (script de suivi),
  mais après 2 contrôles en échec (4 s) pendant lesquels les nouvelles connexions échouent.
- `qm shutdown` du maître sans étape 2 : bascule au bout du délai de détection (≈ 3 annonces
  manquées) ; même effet, moins propre.
- Deux répartiteurs avec keepalived arrêté (étape 2 sur l'un pendant que l'autre est en panne) :
  plus de VIP. D'où les contrôles d'entrée.
- Mise à jour qui change de branche d'HAProxy (dépôt mal configuré) : la vérification `haproxy -v`
  après `upgrade` l'attrape avant le retour en service.
- Oublier que le **défi ACME** passe par la VIP : une reconstruction pendant que la VIP est
  absente échoue à l'émission des certificats.
