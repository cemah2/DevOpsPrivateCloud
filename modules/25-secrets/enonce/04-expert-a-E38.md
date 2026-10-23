### M25-E38 — Panne : MédiAgenda perd sa base  `BF` `★★★`

> **Ticket INC-5238** — *De : Julien Petit*
> En recette, toutes les heures environ, l'API renvoie des 500 pendant un moment ; les journaux disent `password authentication failed for user "v-…"`. Parfois ça revient seul, parfois non. Personne n'a livré, la base répond quand je m'y connecte avec mon compte de lecture. La prod va bien, mais elle tourne sur les mêmes identifiants dynamiques depuis E15 : je veux comprendre avant que ça lui arrive. *(Le détail s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Suivre de bout en bout la vie d'un identifiant dynamique : générateur `VaultDynamicSecret` → ExternalSecret → Secret → Reloader → pod ; bail dans OpenBao → compte `v-…` et `VALID UNTIL` dans PostgreSQL → révocation (`DROP ROLE`).
- Situer une panne d'identifiants dans le temps : **quand** le compte est né, **quand** il devait mourir, **quand** il a été remplacé — et en déduire la cause.
- Distinguer quatre familles de cause : durée du rôle, révocation, connexion d'administration du coffre (`openbao`), réseau entre le coffre et la base.
- Reprendre la main sur la connexion d'un moteur `database` sans qu'aucun humain ne connaisse le mot de passe, et réapprovisionner les consommateurs sans attendre.

**Prérequis** : M25-E14, M25-E15, M25-E21 (audit dans Loki), M25-E23 (RB-250) ; `lab/bin/check 25 14` et `lab/bin/check 25 15` verts avant l'injection.
**Durée indicative** : 50 min (temps cible), prévention comprise.

**Contexte technique**
- Recette : moteur `db-mediagenda/`, connexion **`mediagenda-recette`** (`postgresql://…@10.10.41.64:5432/mediagenda`, `sslmode=verify-ca`, compte PostgreSQL **`openbao`** dont seul OpenBao connaît le mot de passe depuis `rotate-root`), rôle **`mediagenda-api-recette`** (`default_ttl` 1 h, `max_ttl` 24 h, `CREATE ROLE … VALID UNTIL '{{expiration}}' IN ROLE mediagenda_api`, révocation `DROP ROLE`). Code : `plateforme/secrets`, `tofu/db-mediagenda.tf`.
- Cluster CNPG **`mediagenda-db`** de l'espace **`mediagenda-recette`** : rôles gérés `openbao` et `mediagenda_api`, Service **`mediagenda-db-openbao`** (LoadBalancer 10.10.41.64, `externalTrafficPolicy: Local`), CiliumNetworkPolicy **`mediagenda-db-depuis-openbao`** (5432 ouvert à 10.10.20.21-23).
- ESO : générateur **`mediagenda-api`** (`db-mediagenda/creds/mediagenda-api-recette`), ExternalSecret **`mediagenda-db-api`** (`refreshInterval` 30 min, clés `uri` et `username`), Rollout `mediagenda` redémarré par **Reloader** quand le Secret change (≈ 2 min, E15).
- Ton jeton `plateforme-admin` lit la configuration du moteur, demande des identifiants **de recette**, liste les baux, fait `rotate-root`, révoque. `kubectl cnpg psql` te donne le superutilisateur local de la base. Audit : Loki, locataire `audit`, `{service="openbao"}` ; journal d'OpenBao : `journalctl -u openbao` sur le nœud actif. Hubble est disponible (`hubble observe`).
- La panne ne touche **que** la recette ; elle agit avec ton jeton d'administration et ton kubeconfig.

> ⚠️ **Attention** :
> - **Rien sur la prod** pendant le diagnostic : ni `rotate-root`, ni révocation, ni `force-sync` sur `mediagenda-prod`. Si tu dois comparer, **lis** seulement.
> - Ne révoque **jamais** des baux « pour voir » ou « pour nettoyer » : chaque bail révoqué est un compte supprimé, et les sessions ouvertes avec lui meurent. Un `bao read …/creds/…` d'essai crée un vrai compte : révoque **ce** bail-là (`bao lease revoke <BAIL>`) dès l'essai fini.
> - Si tu dois redonner un mot de passe au compte `openbao`, garde ta session `kubectl cnpg psql` ouverte jusqu'au `rotate-root` réussi (c'est ton accès de secours), et qu'aucun mot de passe n'apparaisse ni à l'écran, ni dans l'historique, ni en argument d'une commande (tubes seulement). Retour arrière : la même procédure, rejouée (`identifiants-dynamiques.md` § 4).
> - Ne modifie pas une CiliumNetworkPolicy à la main : MR `plateforme/k8s`.

**Injection** : `lab/bin/break 25 38` (4 variantes).

**Travail demandé**
1. **Date le symptôme.** Dans les journaux de l'API, relève le nom exact du compte refusé et l'heure des premiers refus. Compare avec : l'heure du dernier rafraîchissement de l'ExternalSecret (`status.refreshTime`, événements), les redémarrages du Rollout, et, dans PostgreSQL, l'existence de ce compte et son `rolvaliduntil`. Écris une phrase : « le compte X, né à …, devait vivre jusqu'à …, a cessé de marcher à … ».
2. **Interroge le coffre.** Baux actifs sous `db-mediagenda/creds/mediagenda-api-recette` (combien, quelle durée à l'émission), configuration du rôle et de la connexion, et l'audit : demandes d'identifiants en erreur, révocations, écritures sur `db-mediagenda/roles/*` ou `config/*`. Lis aussi le journal d'OpenBao du nœud actif (révocations en échec).
3. **Interroge le chemin réseau** si le coffre ne joint plus la base : depuis le nœud actif, un test TCP vers 10.10.41.64:5432 ; dans le cluster, les politiques de l'espace et les flux refusés (Hubble).
4. **Conclus et corrige** par le bon canal : `plateforme/secrets` (pipeline) pour le coffre, `plateforme/k8s` pour la base et le réseau, procédure de bris de glace de `identifiants-dynamiques.md` § 4 pour une connexion perdue. Puis **réapprovisionne** l'API sans attendre le cycle d'ESO, et vérifie `/pret` en continu pendant le redémarrage.
5. **Explique** pour chaque cause pourquoi le symptôme est **périodique**, **unique** ou **permanent**, et combien de temps la prod aurait tenu dans la même situation.
6. **Préviens** : des règles d'audit dans le ruler de Loki qui auraient sonné avant Julien — **`IdentifiantsDynamiquesEnEchec`** (demandes `creds` en erreur) et **`OpenBaoBauxRevoquesEnMasse`** (révocation par préfixe réussie) ; une section « Quand l'application perd sa base » dans `docs/securite/secrets/identifiants-dynamiques.md` (dont une règle liant la durée des identifiants à l'intervalle de rafraîchissement) ; ton journal de diagnostic.

**Critères de réussite**
- [ ] Le rôle `mediagenda-api-recette` a de nouveau `default_ttl` 1 h et `max_ttl` 24 h, et un identifiant vit au moins un cycle d'ESO plus 10 min.
- [ ] En recette, l'ExternalSecret `mediagenda-db-api` est `Ready` et rafraîchi depuis moins de 35 min, au moins un bail `mediagenda-api-recette` est actif, `/pret` répond 200.
- [ ] Aucune CiliumNetworkPolicy de `mediagenda-recette` ne refuse 10.10.20.21-23 sur 5432 ; `mediagenda-db-depuis-openbao` est intacte ; aucun humain ne connaît le mot de passe d'`openbao`.
- [ ] Les règles `IdentifiantsDynamiquesEnEchec` et `OpenBaoBauxRevoquesEnMasse` sont chargées par le ruler de Loki (locataire `audit`) ; ton journal de diagnostic (un fichier dont le nom contient `INC-5238`, dans le dossier des journaux du palier) date la naissance et la mort du compte refusé et nomme la cause.

**Vérification** : `lab/bin/check 25 38`

<details><summary>Indice 1</summary>

Le Secret `mediagenda-db-api` a une clé `username` : lis-la seule (`kubectl get secret … -o jsonpath='{.data.username}' | base64 -d`), jamais `uri`. Ce nom, cherché dans `pg_roles`, répond à deux questions d'un coup : le compte existe-t-il encore, et jusqu'à quand était-il valable ? Un compte **absent** et un compte **expiré** ne racontent pas la même histoire.
</details>

<details><summary>Indice 2</summary>

Trois horloges tournent : le bail (durée = la plus petite entre `default_ttl` et `max_ttl` du rôle, plafonnée par le montage), le cycle d'ESO (30 min) et le redémarrage par Reloader. Si la première est plus courte que la deuxième, le trou revient à **chaque** cycle. Si ESO n'arrive plus à obtenir un identifiant, l'ancien Secret reste en place et l'application tient… jusqu'au `VALID UNTIL` de son compte.
</details>

<details><summary>Indice 3</summary>

Une connexion déjà ouverte survit à un changement de mot de passe comme à une nouvelle politique réseau : OpenBao ne voit la panne qu'à sa **prochaine** connexion. Pour savoir lequel des deux, le message d'erreur d'OpenBao suffit souvent (`password authentication failed for user "openbao"` ou un délai dépassé). Et si OpenBao ne peut plus s'authentifier, il ne peut pas non plus faire `rotate-root` : quelqu'un d'autre doit lui redonner un mot de passe, sans le connaître.
</details>

**Pour aller plus loin** (facultatif) : mesure sur un banc (`wb-essais`) ce que devient une session PostgreSQL **ouverte** quand son compte atteint `VALID UNTIL` sans être supprimé (la vérification du mot de passe n'a lieu qu'à la connexion) ; compare avec un `DROP ROLE`. Lis la [documentation des baux](https://openbao.org/docs/concepts/lease/), de l'[API des baux](https://openbao.org/api-docs/system/leases/) (`revoke-prefix`, `revoke-force`) et du [moteur database](https://openbao.org/api-docs/secret/databases/#rotate-root-credentials) ; le [rafraîchissement forcé d'ESO](https://external-secrets.io/latest/introduction/faq/) ; les [politiques de refus de Cilium](https://docs.cilium.io/en/stable/security/policy/deny/).

---
