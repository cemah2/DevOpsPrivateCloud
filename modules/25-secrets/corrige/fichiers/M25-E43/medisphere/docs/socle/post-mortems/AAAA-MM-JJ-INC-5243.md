# Post-mortem — INC-5243 « la nuit où le coffre s'est fermé »

> Exemple rédigé pour un tirage (E36 v2 + E41 v2 + E42 v4) ; adapte à ton tirage. Modèle :
> `modules/00-lab/ressources/M00-E46/modele-post-mortem.md`. Aucun jeton, aucune valeur, aucun
> accesseur complet.

## Résumé

Samedi, de 2 h 10 à 4 h 05, la grappe OpenBao a tourné **sans marge** (`vault03` scellé après un
redémarrage) pendant que deux consommateurs étaient en panne : la CI de MédiAgenda ne lisait plus ses
secrets et MédiDoc refusait les appels mTLS de MédiAgenda en recette. Aucun impact en production ;
aucune donnée perdue ; aucun dépositaire réveillé.

## Chronologie

| Heure | Événement |
|---|---|
| 02:10 | `OpenBaoScelle` (vault03), `OpenBaoToleranceNulle` ; Nadia ouvre INC-5243 |
| 02:14 | triage : VIP 200, vault01 200, vault02 429, vault03 000 ; `autopilot state` : tolérance 0 |
| 02:20 | première communication (coffre dégradé, aucun redémarrage autorisé) |
| 02:31 | vault03 : `start-limit-hit` ; journal `Error configuring seal "transit": … connection refused` |
| 02:36 | depuis vault03 : `curl kms01…/sys/health` → refusé ; depuis vault02 : 200 ; `nft list ruleset` : table `durcissement_sortie` |
| 02:44 | `pare_feu_local` rejoué sur vault03, `reset-failed` + `start` : descellé, tolérance 1 |
| 03:05 | CI : `bao write auth/gitlab/login …` → `error validating claims: claim "ref_protected" does not match any associated bound claim values` |
| 03:22 | rôle `ci-mediagenda-api` rétabli par le pipeline de `plateforme/secrets` (dérive vue au plan) |
| 03:40 | recette : ghostunnel de MédiDoc `bad certificate` ; `mediagenda-mtls` sans `TLS Web Client Authentication` |
| 03:58 | rôle `services-k8s` rétabli (pipeline), `cmctl renew` ; appel de bout en bout OK |
| 04:05 | contrôles E36, E41, E42 verts ; communication de fin ; `--annuler` |

## Causes

1. **vault03** : une table nftables posée à la main (« durcissement des sorties ») rejetait la sortie
   vers `kms01:8200` ; invisible tant que le nœud tournait, fatale au redémarrage suivant.
2. **CI** : `bound_claims.ref_protected` du rôle `ci-mediagenda-api` modifié à la main avec une valeur
   d'un autre type que celle envoyée par GitLab (chaîne `"true"`).
3. **mTLS** : `client_flag` retiré du rôle `services-k8s` ; les certificats réémis n'avaient plus
   l'usage client, le serveur de MédiDoc les refusait.

## Extraits de diagnostic

```
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://vault03.par1.medisphere.internal:8200/v1/sys/health
000
root@vault03:~# journalctl -u openbao -b --no-pager | grep -m1 'configuring seal'
Error configuring seal "transit": Put "https://kms01.par1.medisphere.internal:8200/v1/transit/encrypt/autodescellement-par1": dial tcp 10.10.20.24:8200: connect: connection refused
admin@adm01:~$ bao operator raft autopilot state | grep -i tolerance
Failure Tolerance:    0
```

## Détection

| Cause | Ce qui a sonné | Ce qui aurait dû sonner avant |
|---|---|---|
| vault03 / filtrage | `OpenBaoScelle` **après** le redémarrage | l'essai quotidien `openbao-essai-kms` (M25-E42) aurait échoué dès la pose de la table : `OpenBaoAutodescellementEnEchec` la veille |
| CI / `ref_protected` | un pipeline rouge, vu par Julien | `OpenBaoPolitiqueModifiee` ne couvre que les politiques : ajouter une règle d'audit sur l'écriture de `auth/gitlab/role/*` hors du pipeline |
| mTLS / `client_flag` | rien (le certificat est « prêt ») | une sonde mTLS de bout en bout en recette ; `tofu plan` planifié chaque nuit qui signale toute dérive |

## Actions

| Action | Porteur | Échéance |
|---|---|---|
| Essai quotidien de l'auto-descellement sur les trois nœuds | plateforme | fait (M25-E42) |
| `tofu plan` planifié chaque nuit sur `plateforme/secrets`, alerte si non vide | plateforme | J+15 |
| Règle d'audit « configuration d'auth modifiée hors pipeline » | sécurité | J+15 |
| RB-255 « coffre fermé » | plateforme | fait |
