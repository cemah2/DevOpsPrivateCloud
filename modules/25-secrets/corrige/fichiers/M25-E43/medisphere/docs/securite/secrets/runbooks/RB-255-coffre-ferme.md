# RB-255 — Le coffre est fermé

> M25-E43 (INC-5243). **Quand** : OpenBao ne répond plus par la VIP, ou répond mais sans marge (un
> seul nœud sain, plus de leader, nœuds scellés), ou refuse tout (audit bloquant). **Qui** : l'astreinte
> plateforme ; elle appelle les dépositaires **seulement** si l'arbre ci-dessous le demande.
> **Durée cible** : coffre rétabli en 30 min quand `kms01` est sain ; 1 h 30 quand il faut trois
> dépositaires. Runbooks liés : RB-250 (fuite), RB-251 (descellement), RB-252 (restauration), RB-253
> (montée de version).

## 0. Ce qu'on ne fait JAMAIS

- Redémarrer **plusieurs** nœuds « pour voir », ou un nœud alors que la tolérance d'autopilot est à 0.
- Redémarrer ou sceller `kms01` (il revient **scellé** : trois dépositaires).
- Effacer `/var/lib/openbao`, lancer `raft remove-peer` sur un nœud seulement « lent », restaurer un
  instantané sur la grappe de production (RB-252 : grappe neuve, isolée).
- Désactiver l'audit, élargir une politique, créer un jeton racine « en attendant », passer une
  identité à `*`.
- Afficher, copier ou coller une clé de récupération ou un jeton dans un ticket ou un canal.

## 1. Constater (5 min, sans rien changer)

```
admin@adm01:~$ for n in vault01 vault02 vault03 kms01; do printf '%-8s %s %s\n' $n \
    "$(curl -s -o /dev/null -w '%{http_code}' https://$n.par1.medisphere.internal:8200/v1/sys/health)" \
    "$(curl -s https://$n.par1.medisphere.internal:8200/v1/sys/seal-status | jq -c '{type, sealed}')"; done
admin@adm01:~$ curl -s -o /dev/null -w 'VIP %{http_code}\n' https://openbao.par1.medisphere.internal:8200/v1/sys/health
admin@adm01:~$ bao operator raft list-peers ; bao operator raft autopilot state | head -n 20
```

Codes : 200 actif, 429 en attente, 503 scellé, 501 non initialisé, 000 injoignable (processus arrêté
ou flux coupé). Note l'heure : c'est T0 du post-mortem.

## 2. Arbre de décision

| Constat | Cas | Aller à |
|---|---|---|
| VIP 200, un nœud 503/000, les autres 200/429 | **un nœud perdu** (marge nulle) | § 3 |
| aucun 200, deux nœuds 429 ou plus, `list-peers` sans leader | **plus de leader** (quorum) | § 4 |
| plusieurs nœuds 503, `kms01` 200 | **auto-descellement** en échec | § 5 (RB-251) |
| `kms01` 503 (scellé) ou 000 | **`kms01` fermé** | § 6 |
| nœuds 200/429 mais toutes les requêtes en 500 « internal error » | **audit bloquant** | § 7 |
| VIP 000 alors qu'un nœud répond 200 | **VIP** (keepalived) | § 8 |

## 3. Un nœud perdu

`systemctl status openbao` et `journalctl -u openbao -b` sur le nœud. Seal (`Error configuring seal`,
`failed to unseal core`) → § 5 ; disque (`no space left`) → libérer **hors** de `/var/lib/openbao`
(journaux, paquets), puis `systemctl reset-failed openbao && systemctl start openbao` ; certificat
(`x509`) → `cert-renewer@openbao`, M25-E35. Un seul nœud à la fois ; attendre `autopilot state` sain
avant toute autre action.

## 4. Plus de leader

- Compter les nœuds **vivants** : à trois, il en faut deux. Remettre en service le nœud arrêté
  (`qm start`, puis `systemctl start openbao`) : la grappe réélit seule.
- Un pair retiré de la configuration Raft (`list-peers` à deux) : le nœud retiré doit **rejoindre**
  (`bao operator raft join` ou `retry_join` au démarrage) — jamais réinitialisé seul.
- Horloges : `chronyc tracking` sur chaque nœud ; flux 8201 entre nœuds : `nft list ruleset`.
- Dernier recours, perte définitive de deux nœuds : récupération par `peers.json` (documentation
  *Raft — outage recovery*), **avec** Karim et un instantané récent vérifié ; jamais seul la nuit.

## 5. L'auto-descellement échoue

RB-251 § « Un nœud ne se descelle plus alors que kms01 répond » : réseau, jeton, politique, clé.
Un nœud qui **réessaie** (processus vivant) revient seul quand la cause est levée ; un nœud en
`start-limit-hit` demande `systemctl reset-failed openbao && systemctl start openbao`.

## 6. `kms01` fermé

1. `kms01` injoignable (000) : VM, réseau, service ; **ne pas** le redémarrer si son processus tourne.
2. `kms01` scellé (503) : appeler **trois** dépositaires (liste et téléphones : `garde-des-parts.md`,
   astreinte des dépositaires). Descellement : `outils/openbao-parts.sh desceller` avec
   `secrets/kms01-init.yml`, chacun sa part, sur `kms01` directement.
3. Puis les nœuds de la grappe : ils réessaient seuls (processus vivants) ou `reset-failed` + `start`.
4. Pendant ce temps, la grappe **déjà descellée** sert normalement : rien ne presse côté clients
   tant qu'aucun nœud ne redémarre.

## 7. Audit bloquant

OpenBao refuse de répondre sans trace (HTTP 500, journal : `no audit backend succeeded`). Cause
habituelle : `/var/log` plein ou fichier d'audit illisible. Libérer de l'espace (rotation `logrotate -f`,
anciens journaux compressés hors de la machine), vérifier le propriétaire de `/var/log/openbao/`,
`systemctl reload openbao` (SIGHUP). Ne **jamais** retirer le dispositif d'audit de `openbao.hcl`.

## 8. VIP absente ou sur le mauvais nœud

`ip -br addr` sur les trois nœuds, `journalctl -t keepalived-transition`, script de suivi
(`chk_openbao_actif`) : il doit tester `sys/health` **sans** `standbyok`. En attendant : les clients
peuvent viser le nœud actif par son nom (CLI d'astreinte seulement, jamais dans une configuration).

## 9. Les consommateurs pendant la fermeture

| Consommateur | Ce qui se passe | Échéance |
|---|---|---|
| CI (jobs qui lisent le coffre) | échec immédiat à la connexion | tout de suite ; relancer les jobs après |
| ESO | le rafraîchissement échoue, le **Secret existant reste** | rien tant que le Secret est bon ; une rotation en attente ne passe pas |
| MédiAgenda (identifiants dynamiques) | le bail en cours vit jusqu'à son terme ; pas de renouvellement | **1 h** au plus : priorité absolue en prod |
| cert-manager (PKI de services) | renouvellements en échec | les certificats durent 48 h |
| Ansible, `medictl` | échec à la lecture | à la prochaine exécution |

## 10. Après

- Vérifier : trois nœuds descellés, un actif, autopilot sain (tolérance ≥ 1), VIP, `kms01` descellé,
  essai d'auto-descellement vert, `lab/bin/check 25 42`.
- Consommateurs : baux PostgreSQL renouvelés (`bao list sys/leases/lookup/db-mediagenda/creds/…`),
  ExternalSecret `Ready`, jobs de CI relancés, `Certificate` prêts.
- Post-mortem dans les cinq jours ouvrés ; révocation de tout jeton racine régénéré ; mise à jour de
  ce runbook.
