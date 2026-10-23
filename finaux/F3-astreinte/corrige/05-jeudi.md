# Corrigé — Final F3, phase 5 : jeudi

> ⚠️ Corrigé : à n'ouvrir qu'après avoir cherché. Les heures des exemples sont celles d'une exécution type du lab (jeudi 2026-11-05) ; les tiennes viennent de ta main courante.

**Non testé en conditions réelles** (à vérifier sur ton lab, retours bienvenus) : sorties exactes de `ip -j route` avec des groupes de prochains sauts (`nhid`) ; comportement de zebra (FRR 10.7) face à une route noyau plus prioritaire pour une /32 apprise en BGP ; délai réel de chute d'une session BGP filtrée avec le redémarrage gracieux de Cilium ; mise à jour partielle d'un rôle `kubernetes` d'OpenBao 2.7 (le script de panne renvoie tous les champs par prudence) ; nom et étiquettes de la métrique `cilium_bgp_control_plane_session_state` en Cilium 1.20.

---

### F3-S10 — Jeudi : les secrets ne suivent plus

#### Démarche de diagnostic

**Symptômes.** `ExternalSecret` `mediagenda-db-api` en erreur (Argo CD *Degraded*), puis des pods de l'API qui perdent leur base les uns après les autres. Le caractère **progressif** est la signature d'un renouvellement qui ne se fait plus : chaque instance garde son identifiant jusqu'à la fin de son bail (1 h), et Reloader ne redémarre rien tant que le Secret ne change pas.

**Hypothèses**, du client vers le coffre : (a) ESO n'atteint plus le coffre (adresse, réseau, VIP) ; (b) ESO l'atteint mais n'est plus autorisé (rôle, audience, politique) ; (c) le coffre ne délivre plus (moteur `db-mediagenda`, connexion à PostgreSQL : c'était M25-E38) ; (d) le coffre lui-même (scellé, sans leader : M25-E35/E39).

**Commandes, dans l'ordre.**

```
admin@adm01:~$ kubectl -n mediagenda-recette describe externalsecret mediagenda-db-api | sed -n '/Conditions/,$p'
admin@adm01:~$ kubectl -n mediagenda-recette get secretstore openbao -o jsonpath='{.spec.provider.vault.server}{"\n"}'
admin@adm01:~$ kubectl -n mediagenda-recette get vaultdynamicsecrets -o custom-columns=NOM:.metadata.name,SERVEUR:.spec.provider.server
admin@adm01:~$ curl -s --max-time 5 https://openbao.par1.medisphere.internal:8200/v1/sys/health | jq '{sealed, standby}'
admin@adm01:~$ for n in vault01 vault02 vault03; do printf '%s ' $n; curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 https://$n.par1.medisphere.internal:8200/v1/sys/health; done
admin@adm01:~$ bao read -format=json auth/k8s-par1/role/eso-mediagenda-recette | jq '.data | {token_policies, bound_service_account_names, bound_service_account_namespaces, audience}'
```

Les trois réponses du coffre (VIP, chaque nœud, adresse vue par ESO) **départagent** les variantes.

**Variante 1 — la VIP n'est portée par personne.** La VIP ne répond pas (délai) ; les nœuds répondent `200`, `429`, `429` ; le message d'ESO parle de délai de connexion (`context deadline exceeded`, `i/o timeout`).

```
admin@adm01:~$ for n in vault01 vault02 vault03; do ssh $n 'echo "$(hostname) keepalived=$(systemctl is-active keepalived)"; ip -br -4 addr show eth0'; done
vault02 keepalived=inactive
eth0   UP   10.10.20.22/24                       # pas de 10.10.20.200
vault01 keepalived=active …                       # en FAULT : chk_openbao_actif échoue (429)
admin@adm01:~$ ssh vault02 'sudo journalctl -u keepalived --since -3h | tail -n 5'
… Stopping keepalived … Stopped                    # arrêt propre : quelqu'un l'a arrêté
```

Cause racine : keepalived arrêté sur le **nœud actif**. Par conception (M25-E24), seuls les nœuds actifs sont éligibles (`curl -f` échoue sur 429) : arrêter keepalived sur l'actif retire la VIP de tout le monde. Correctif par le code : rejouer `playbooks/coffre.yml --limit vault02` par le pipeline d'Ansible (le rôle `keepalived` du M07 garantit `state: started, enabled: true`) ; la VIP revient dans les secondes qui suivent (`ip -br addr` sur `vault02`). Si le pipeline lui-même dépend du coffre (jetons `id_tokens` + `bao`), il échoue tant que la VIP manque : c'est **le** cas de geste d'exception documenté — `sudo systemctl start keepalived` sur l'actif, consigné, puis pipeline rejoué pour prouver que le code converge (aucun changement attendu).

⚠️ **Gravité.** La production passe par la même VIP : ses identifiants expireront à la fin de leur bail courant (heure d'émission dans l'audit d'OpenBao, ou `bao list sys/leases/lookup/db-mediagenda/creds/mediagenda-api-prod` puis `bao lease lookup`). C'est un **SEV1** latent : à relever dès que c'est compris, avec l'échéance dans le message d'état.

**Variante 2 — le rôle d'ESO a été « restreint ».** Le magasin est prêt (il s'authentifie et lit le KV), mais le générateur reçoit `permission denied` sur `db-mediagenda/creds/mediagenda-api-recette`.

```
admin@adm01:~$ bao read -format=json auth/k8s-par1/role/eso-mediagenda-recette | jq .data.token_policies
[ "eso-mediagenda-recette-kv" ]
admin@adm01:~$ bao policy read eso-mediagenda-recette-kv | head -3
# eso-mediagenda-recette-kv — moindre privilège pour ESO en recette (PLAT-3310, F3-S10).
admin@adm01:~/src/secrets$ tofu -chdir=tofu plan
  # vault_kubernetes_auth_backend_role.eso_espace["mediagenda-recette"] will be updated in-place
      ~ token_policies = [ - "eso-mediagenda-recette-kv", + "eso-mediagenda-recette" ]
```

Cause racine : modification directe de la configuration d'OpenBao, hors de `plateforme/secrets` (dérive). L'audit (Loki, locataire `audit`, `{service="openbao"} |= "auth/k8s-par1/role/eso-mediagenda-recette"`) donne l'heure et l'identité. Correctif : relancer le pipeline de `main` de `plateforme/secrets` (le `tofu apply` remet `token_policies`) ; supprimer `eso-mediagenda-recette-kv` **par MR** si tu décides de la garder sous gestion, sinon `bao policy delete` consigné (une politique créée hors du code n'a pas de ressource OpenTofu à retirer). Si la restriction répond à un vrai besoin (moindre privilège), elle se fait en code : séparer `chemins_creds` du KV dans le gabarit `eso-espace.hcl.tftpl`, avec revue.

**Variante 3 — deux causes : client épinglé sur un nœud, et ce nœud arrêté.** La VIP répond ; un nœud répond `000` ; le magasin et les générateurs de la recette visent `https://vault0N.par1.medisphere.internal:8200`.

```
admin@adm01:~$ kubectl -n mediagenda-recette get secretstore openbao -o yaml | yq '.spec.provider.vault.server'
https://vault03.par1.medisphere.internal:8200
admin@adm01:~$ ssh vault03 'systemctl is-active openbao'
inactive
admin@adm01:~$ bao operator raft list-peers       # deux voteurs sains sur trois : quorum gardé
```

Causes : (1) épinglage du client sur un nœud (dérive par rapport à `plateforme/k8s/espaces/mediagenda-recette/80-openbao.yaml` et `90-openbao-dynamique.yaml`) ; (2) openbao arrêté sur ce nœud. Chacune seule est sans effet visible : c'est leur **conjonction** qui coupe la recette. Correctifs : `task appliquer` dans `plateforme/k8s` (le diff `kubectl diff -f espaces/mediagenda-recette/` montre l'écart avant) ; `playbooks/coffre.yml --limit vault03` (le rôle démarre openbao) puis vérifier `429` et `bao operator raft list-peers`. Redémarrer seulement le nœud « répare » l'incident et laisse une panne latente : le prochain arrêt du nœud recoupera la recette.

**Après chaque variante** : rafraîchissement forcé, vérification d'un bail neuf, de l'API, et des **autres** environnements.

```
admin@adm01:~$ kubectl -n mediagenda-recette annotate externalsecret mediagenda-db-api force-sync=$(date +%s) --overwrite
admin@adm01:~$ kubectl -n mediagenda-recette get externalsecret mediagenda-db-api
admin@adm01:~$ bao list sys/leases/lookup/db-mediagenda/creds/mediagenda-api-recette
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://mediagenda-recette.apps.par1.medisphere.internal/pret
admin@adm01:~$ kubectl -n mediagenda-prod get externalsecret mediagenda-db-api     # variante 1 : la prod aussi
```

**Prévention.** Politique Kyverno [`coffre-par-la-vip`](fichiers/S10/politiques/kyverno/validation/coffre-par-la-vip.yaml) (aucun client du coffre ne vise un nœud) ; sonde du témoin `mon01` sur la VIP **et** sur chaque nœud (alerte « VIP injoignable » critique en 2 min, ce que `MagasinSecretsEnErreur` à 10 min ne remplace pas) ; contrôle de dérive périodique de `plateforme/secrets` (`tofu plan -detailed-exitcode` planifié en CI, alerte sur code 2) ; runbook [RB-336](fichiers/S10/medisphere/docs/exploitation/runbooks/RB-336-secrets-ne-suivent-plus.md).

#### Messages d'état types

- **Début (09:52)** — *Objet : [INC-5910] SEV2 — MédiAgenda recette perd l'accès à sa base* — « Depuis 09:31 environ, l'API de recette perd sa base par vagues (identifiants non renouvelés). Production : pas d'erreur à cette heure, exposition en cours d'évaluation. Responsable : astreinte Plateforme. Prochain point : 10:20. »
- **Point d'étape (10:05, relève de gravité)** — *Objet : [INC-5910] SEV1 — chaîne des secrets coupée, production exposée* — « Cause identifiée : l'adresse commune du coffre ne répond plus (coffre lui-même sain). Production, CI et Ansible en dépendent : les identifiants de production expirent à 10:24 si rien n'est fait. Correction en cours par le code ; pas de livraison d'ici là. Prochain point : 10:20 ou avant. »
- **Fin (10:52)** — *Objet : [INC-5910] Résolu — secrets renouvelés partout* — « Adresse du coffre rétablie à 10:31 ; identifiants renouvelés en recette et en production à 10:33 ; recette saine à 10:37, aucune erreur en production. Impact : recette indisponible 66 min, 7 pipelines relancés. Post-mortem lundi. »

#### Main courante (extrait type)

```
- 09:43 INC-5910 [ouverture] Julien : ES mediagenda-db-api en erreur, 500 en recette (password authentication failed). Gravité SEV2 provisoire.
- 09:48 INC-5910 [action] VIP 10.10.20.200:8200 sans réponse ; vault01 429, vault02 200, vault03 429 : coffre sain, chemin coupé.
- 09:52 INC-5910 [état] Message 1 envoyé (recette, SEV2, prochain point 10:20).
- 10:01 INC-5910 [action] keepalived inactive sur vault02 (actif) ; aucun nœud ne porte la VIP (script de suivi : seul l'actif est éligible).
- 10:04 INC-5910 [décision] Gravité relevée SEV1 : prod et CI passent par la VIP ; baux de prod jusqu'à 10:24.
- 10:05 INC-5910 [état] Message 2 (SEV1, échéance prod 10:24).
- 10:12 INC-5910 [décision] Épingler la prod sur vault02 écarté (panne latente). Pipeline Ansible impossible sans coffre : geste d'exception.
- 10:31 INC-5910 [action] sudo systemctl start keepalived sur vault02 (exception) ; VIP portée ; pipeline coffre.yml relancé : aucun changement.
- 10:37 INC-5910 [action] force-sync recette et prod ; baux neufs ; /pret recette 200.
- 10:52 INC-5910 [clôture] Stable depuis 15 min. Actions : PLAT-3310 (politique VIP), PLAT-3371 (sonde VIP). Post-mortem INC-5910.
- 10:53 INC-5910 [état] Message de fin envoyé.
```

#### Explications

Un identifiant dynamique découple la **cause** (renouvellement impossible) du **symptôme** (fin de bail) d'au plus une heure ; ESO garde la dernière valeur du Secret tant qu'il ne peut pas la remplacer, et Reloader ne réagit qu'à un changement. La VIP du coffre, portée par le seul nœud actif, est un point unique *logique* au-dessus d'une grappe redondante : la grappe tolère la perte d'un nœud, la VIP ne tolère pas la perte de keepalived sur l'actif. Le coffre est sain ; c'est le **chemin** qui est cassé — d'où l'importance de sonder chaque nœud par son nom.

#### Alternatives

- Contourner en épinglant les clients sur un nœud : rétablit vite, crée la panne de la variante 3. Acceptable seulement en dernier recours, consigné, et défait dans l'incident.
- Allonger les baux pour gagner du temps (`default_ttl`) : retarde le symptôme, ne répare rien, et contredit la politique de durée courte du M25.
- Relancer openbao sur l'actif pour « faire bouger » la VIP : provoque une élection, une coupure de tous les clients, et ne règle rien si keepalived est arrêté.

#### Pièges classiques

- Conclure « la prod va bien » en regardant la prod **maintenant** au lieu de l'heure d'expiration de ses baux.
- Lire `sys/health` par la VIP seulement : délai d'attente = « coffre en panne », alors qu'il est sain.
- Réparer à la main sans repasser par le code : la dérive reste (variante 2), ou l'épinglage reste (variante 3).
- Révoquer des baux « pour forcer le renouvellement » : coupe immédiatement les instances encore saines.

#### En production chez MédiSphère

Deux adresses de secours dans les clients ou un répartiteur devant la grappe (étude PLAT-3374, ADR), alerte de témoin sur la VIP, contrôle de dérive planifié de `plateforme/secrets`, fiche de changement pour toute intervention sur keepalived (processus du F4), et un exercice de jeu trimestriel « keepalived arrêté sur l'actif ».

---

### F3-S11 — Jeudi : la moitié des noms ne répond plus

#### Démarche de diagnostic

**Symptômes.** « Une partie » des noms ou des adresses échoue, pas les mêmes selon les personnes : signature d'un **exemplaire malade** dans un ensemble redondant (deux récurseurs, deux passerelles, trois annonceurs BGP par adresse, ECMP).

**Hypothèses.** (a) Résolution : un récurseur répond mal (`SERVFAIL`, mauvaise réponse) ; (b) chemin : une adresse de service n'est plus annoncée, ou est routée vers un mauvais prochain saut, sur la passerelle maître ; (c) filtrage : une règle de pare-feu.

**Première séparation (5 min) : le nom ou le chemin ?**

```
admin@adm01:~$ for s in 10.10.20.10 10.10.20.16; do echo "== $s"; dig +dnssec +time=2 +tries=1 @$s git01.par1.medisphere.internal A | grep -E 'status|flags'; done
admin@adm01:~$ for s in 10.10.20.10 10.10.20.16; do dig +short +time=2 @$s grafana.apps.par1.medisphere.internal; done
admin@adm01:~$ for i in $(seq 1 10); do curl -s -o /dev/null -w '%{http_code} ' --max-time 3 https://grafana.apps.par1.medisphere.internal/api/health; done; echo
admin@adm01:~$ ssh mon01 'for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code} " --max-time 3 https://grafana.apps.par1.medisphere.internal/api/health; done'
```

**Variante 1 — dns02 ne valide plus `par1`.**

```
== 10.10.20.16
;; ->>HEADER<<- opcode: QUERY, status: SERVFAIL, id: …
admin@adm01:~$ dig +cd @10.10.20.16 git01.par1.medisphere.internal +short    # validation désactivée : répond
10.10.20.12
admin@adm01:~$ ssh dns02 'sudo rec_control get-tas'
par1.medisphere.internal. 12345 13 2 9f…a0                     # empreinte
admin@adm01:~$ ssh dns01 'sudo rec_control get-tas'
par1.medisphere.internal. 12345 13 2 9f…a1                     # dernier chiffre différent
admin@adm01:~$ ssh dns02 'sudo journalctl -u pdns-recursor --since -1h | grep -i bogus | tail -n 3'
```

Cause : l'ancre de confiance de `par1.medisphere.internal` sur `dns02` ne correspond plus à la clé de la zone : toute réponse de `par1` (et de `apps.par1`, signée sous elle) est « bogus », donc `SERVFAIL`. Les VMs interrogent `dns01` en premier et ne voient presque rien ; CoreDNS répartit sur les deux récurseurs et ne réessaie pas un `SERVFAIL` : les **pods** échouent une fois sur deux. Correctif par le code : `playbooks/dns01.yml --limit dns02 --tags powerdns_recursor` par le pipeline Ansible ; le gabarit réécrit `recursor.yml` depuis `powerdns_recursor_ancres`, le gestionnaire redémarre le récurseur, et les tâches `ancres.yml` vérifient le drapeau `ad`. Avant : `diff` du fichier des deux récurseurs pour prouver la dérive.

**Variante 2 — une session BGP de la passerelle maître ne monte plus.**

```
admin@adm01:~$ ssh gw01 'ip -br -4 addr | grep -c " 10.10.40.1/"'          # 1 : gw01 est maître
admin@adm01:~$ ssh gw01 'sudo vtysh -c "show bgp summary"' | grep 10.10.40.6
*10.10.40.61  4 65040 …  05:12:33   4 (Policy)
*10.10.40.62  4 65040 …  00:04:51   Active          # ne monte plus
*10.10.40.63  4 65040 …  05:12:33   4 (Policy)
admin@adm01:~$ ssh gw02 'sudo vtysh -c "show bgp summary"' | grep 10.10.40.62   # établie côté gw02
admin@adm01:~$ ssh gw01 'ip -4 route show 10.10.41.0/24 root 10.10.41.0/24' | grep -E 'blackhole|62'
admin@adm01:~$ ssh gw01 'sudo nft list chain inet filter input' | head -n 8
		ip saddr 10.10.40.62 tcp dport 179 drop          # en tête de chaîne, absent du fichier généré
admin@adm01:~$ ssh gw01 'sudo grep -n "179" /etc/nftables.conf'   # le fichier généré par le rôle pare_feu : pas de « drop »
```

Les adresses que `k8s-w02` était seul à annoncer (services en `externalTrafficPolicy: Local` dont tous les pods sont sur `k8s-w02`) tombent sur la route de rejet de 10.10.41.0/24 sur `gw01` : injoignables depuis tout ce qui passe par la maître ; les autres adresses gardent deux chemins sur trois (ECMP). Cause : règle nftables posée à la main sur la maître, hors de la matrice des flux. Correctif par le code : rejouer `playbooks/routeurs.yml` (rôle `pare_feu`, une passerelle à la fois, la maître en dernier) : `/etc/nftables.conf` est régénéré et rechargé, la règle disparaît ; la session remonte (`show bgp summary`), la /32 réapparaît avec `k8s-w02` comme prochain saut.

**Variante 3 — une route noyau envoie une partie des flux dans un trou.**

```
admin@adm01:~$ ssh gw01 'ip -4 route show 10.10.41.10'
10.10.41.10 metric 10
	nexthop via 10.10.40.61 dev ens19.40 weight 1
	nexthop via 10.10.40.249 dev ens19.40 weight 1       # aucune machine en .249
10.10.41.10 nhid … proto bgp metric 20 …                # la route BGP, moins prioritaire
admin@adm01:~$ ssh gw01 'ip neigh show 10.10.40.249'
10.10.40.249 dev ens19.40 FAILED
admin@adm01:~$ ssh gw01 'sudo vtysh -c "show ip route 10.10.41.10"'      # « K>* » : route noyau sélectionnée
admin@adm01:~$ ssh gw02 'ip -4 route show 10.10.41.10'                   # rien d'anormal sur gw02
```

Le hachage ECMP (par défaut sur les adresses source et destination) envoie toujours les flux d'un même client par le même saut : certains clients n'ont **jamais** le problème, d'autres **toujours** — d'où « pas les mêmes selon les personnes ». Cause : route posée à la main (essai oublié), de métrique meilleure que BGP. Correctif : aucun rôle ne retire une route qu'il n'a pas posée : geste d'exception consigné `sudo ip route del 10.10.41.10/32 metric 10` sur `gw01`, puis vérification (`show ip route 10.10.41.10` → `B>*`, trois prochains sauts) ; prévention : contrôle des routes hors FRR dans la vérification du rôle `pare_feu` (ou une tâche dédiée qui échoue s'il existe une route de 10.10.41.0/24 qui n'est pas `proto bgp` ou la route de rejet).

**Vérification commune** : les deux récurseurs, les deux passerelles, trois sources (`adm01`, `mon01`, un pod de `wb-diagnostic`), puis `lab/bin/check F3 11`.

**Prévention.** Sondes DNS **par récurseur** sur le témoin ([extrait](fichiers/S11/ansible/sondes-dns.extrait.yml)) ; alerte sur l'état des sessions BGP de Cilium ([règle](fichiers/S11/observabilite/regles/reseau-bordure.yaml) et [tests](fichiers/S11/observabilite/tests/reseau-bordure.test.yaml)) ; contrôle de dérive des passerelles ; runbook [RB-337](fichiers/S11/medisphere/docs/exploitation/runbooks/RB-337-noms-intermittents.md).

#### Messages d'état types

- **Début** — *[INC-5911] SEV2 — échecs intermittents de résolution / d'accès aux services* — « Depuis 14:00 environ, une partie des noms ou des adresses de services ne répond pas, selon le poste. Production concernée : oui (pods) / à préciser. Diagnostic en cours, exemplaire par exemplaire. Prochain point : 14:45. »
- **Point d'étape** — « L'un des deux [récurseurs DNS | passerelles] est en cause, l'autre est sain ; correction par le code en cours, sans coupure prévue. Prochain point : 15:15. »
- **Fin** — « Rétabli à 15:02, vérifié depuis trois sources et sur les deux exemplaires. Cause : modification hors du code de [ancre DNSSEC de dns02 | pare-feu de gw01 | table de routage de gw01]. Prévention : sondes par exemplaire, contrôle de dérive (PLAT-3311). »

#### Main courante (extrait type, variante 3)

```
- 14:08 INC-5911 [ouverture] Nadia : pages *.apps injoignables pour certains cabinets et collègues, pas pour d'autres. SEV2.
- 14:15 INC-5911 [action] adm01 : 10/10 KO vers grafana.apps ; mon01 : 10/10 OK. DNS : dns01 et dns02 NOERROR + ad. → chemin, pas nom.
- 14:16 INC-5911 [état] Message 1 (SEV2, prochain point 14:45).
- 14:24 INC-5911 [action] gw01 maître : 10.10.41.10 a une route metric 10 (ECMP via .61 et .249) devant la route BGP ; .249 FAILED. gw02 sain.
- 14:27 INC-5911 [décision] Retrait manuel de la route (aucun rôle ne la gère), exception consignée.
- 14:28 INC-5911 [action] sudo ip route del 10.10.41.10/32 metric 10 sur gw01 ; show ip route → B>*, 3 sauts.
- 14:35 INC-5911 [action] Vérifié adm01, mon01, pod wb-diagnostic : 30/30 OK.
- 14:36 INC-5911 [état] Message 2 (rétabli, observation 15 min).
- 14:52 INC-5911 [clôture] Stable. Action PLAT-3311 : contrôle des routes hors FRR dans le rôle pare_feu.
```

#### Explications

Dans une architecture redondante, une panne d'**un** exemplaire ne se voit qu'à moitié, et différemment selon le client (ordre des serveurs dans `resolv.conf`, répartition de CoreDNS, hachage ECMP, passerelle maître). La seule méthode fiable est de court-circuiter la redondance : interroger chaque exemplaire directement, depuis plusieurs sources, et comparer à ce que le code génère.

#### Alternatives

- Variante 1 : `rec_control reload-yaml` après correction du fichier recharge les ancres sans vider le cache (RB-064) ; ajouter temporairement une ancre négative (NTA) pour `par1` rétablit le service **en désactivant DNSSEC** : à proscrire hors urgence documentée.
- Variante 2 : basculer la VIP sur `gw02` (saine) rétablit tout de suite, au prix d'une bascule de bordure ; envisageable si la correction tarde, en le consignant.
- Variante 3 : `ip route replace` vers les seuls bons sauts « répare » aussi, mais laisse une route hors FRR : non.

#### Pièges classiques

- Tester depuis `adm01` seulement et conclure « ça marche » (ou « tout est cassé »).
- Redémarrer FRR ou keepalived sur la maître « pour voir » : bascule et coupure de tout le lab.
- Corriger sur une passerelle et oublier l'autre (ou l'inverse : la panne ne vit que sur la maître).
- Désactiver la validation DNSSEC pour faire disparaître le `SERVFAIL`.

#### En production chez MédiSphère

Sondes de bout en bout par exemplaire (chaque récurseur, chaque passerelle via son adresse propre), BFD entre bordure et nœuds si la version de Cilium le permet, contrôle de dérive des équipements de réseau (configuration vivante comparée au code, chaque nuit), et interdiction des modifications à chaud hors fiche de changement.
