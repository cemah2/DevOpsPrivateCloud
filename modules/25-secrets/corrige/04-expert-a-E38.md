**Points non testés en conditions réelles (M25-E38)** — signale tes retours, ils corrigent le workbook :
- **Validé sur banc** (OpenBao **2.6.4** officiel en serveur de développement, PostgreSQL 16 local avec les rôles `openbao` et `mediagenda_api` de M25-E14) : `max_ttl` inférieur à `default_ttl` accepté par le rôle, bail émis à 600 s ; mise à jour **partielle** d'un rôle et d'une connexion (seuls les champs envoyés changent ; `verify_connection` joue avec le nouveau mot de passe) ; `revoke-prefix` sur `db-mediagenda/creds/mediagenda-api-recette` (sans `/` final) ne touche que ce rôle, comptes supprimés de `pg_roles`, baux de prod intacts ; un changement du mot de passe d'`openbao` **n'est pas vu** tant qu'une connexion du pool d'OpenBao reste ouverte (identifiants délivrés, `rotate-root` réussi), puis, sessions coupées, `password authentication failed for user "openbao"` sur `creds` comme sur `rotate-root` ; révocations en échec réessayées (`failed to revoke lease … attempts=N next_attempt=…`) puis réussies une fois la connexion rendue ; reprise par [`reprise-openbao.sql`](fichiers/M25-E38/k8s/espaces/mediagenda-recette/sql/reprise-openbao.sql) (mot de passe tiré dans PostgreSQL, tube, `rotate-root`) ; `bao write … password=-` **garde** le saut de ligne final (d'où `tr -d '\r\n'`).
- **Scripts** : `break-E38.sh` injecté, vérifié et annulé pour les variantes 1 à 3 contre ce banc (`kubectl` remplacé par un bouchon qui joue le SQL sur la base locale) ; variante 4 : seul le chemin « panne non constatée → annulation » est joué (pas de Cilium sur le banc). `check-E38.sh` joué avec des réponses simulées (état sain, variantes 1 et 4). `shellcheck -x` et `bash -n` propres.
- **Non vérifié** : l'effet d'une `ingressDeny` Cilium sur un flux arrivé par le LoadBalancer `externalTrafficPolicy: Local` (attendu : la source 10.10.20.2x est conservée, et la documentation de Cilium donne le refus prioritaire sur toute autorisation) ; le texte exact des événements d'ESO 2.13 quand le générateur échoue (attendu : l'erreur d'OpenBao recopiée) et le maintien du Secret existant en cas d'échec ; les trois règles du ruler de Loki, écrites sur le modèle de celles de M25-E21 (vérifiées sur Loki 3.7.9) mais pas évaluées ; PostgreSQL 18 (CNPG) au lieu de 16 pour `VALID UNTIL`, `gen_random_uuid()` et `sha256()` (inchangés depuis la 13).

---

### M25-E38 — Panne : MédiAgenda perd sa base

**Démarche de diagnostic**

*Symptômes* : en recette, l'API répond 500 (`/pret` 503) par périodes ; `password authentication failed for user "v-…"` dans ses journaux ; la base répond à d'autres comptes.

*Hypothèses* : (a) le compte de l'API **meurt trop tôt** (durée du rôle, plafond du montage) ; (b) il a été **supprimé** avant l'heure (révocation) ; (c) le coffre **ne délivre plus** de compte : connexion d'administration refusée (mot de passe d'`openbao`), base injoignable (réseau, Service, primaire), ou ESO qui ne s'authentifie plus au coffre (M25-E37) ; (d) le compte est délivré mais l'application ne le **reprend** pas (Reloader, annotation du Rollout, E15) ; (e) côté base : rôle de groupe `mediagenda_api` ou option ADMIN d'`openbao` perdus (CNPG `inRoles`, M25-E14). La clé est la **chronologie** : quand le compte est né, quand il devait mourir, quand il a cessé de marcher.

**Étape 1 — Le compte refusé, et son âge**

```
admin@adm01:~$ kubectl -n mediagenda-recette logs -l app.kubernetes.io/name=mediagenda -c api --since=1h --timestamps \
    | grep -m3 'password authentication failed'
admin@adm01:~$ kubectl -n mediagenda-recette get secret mediagenda-db-api -o jsonpath='{.data.username}' | base64 -d; echo
v-k8s-par1-mediagen-Xb2…-1792…
admin@adm01:~$ kubectl -n mediagenda-recette get es mediagenda-db-api \
    -o jsonpath='{.status.refreshTime}{"  "}{.status.conditions[?(@.type=="Ready")].status}{"\n"}'
admin@adm01:~$ kubectl -n mediagenda-recette describe es mediagenda-db-api | sed -n '/Events/,$p'
admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda -c \
    "SELECT r.rolname, r.rolvaliduntil FROM pg_roles r JOIN pg_auth_members m ON m.member = r.oid
      JOIN pg_roles g ON g.oid = m.roleid WHERE g.rolname = 'mediagenda_api' AND r.rolname LIKE 'v-%' ORDER BY 2"
```

Le nom du compte vient de la clé `username` (jamais `uri`, qui contient le mot de passe). Le gabarit de nom du greffon tronque le nom du rôle à 8 caractères (`mediagen`) : comptes `api` et `migrateur` se distinguent par leur rôle de groupe, d'où la jointure. Trois lectures possibles : compte **présent, `VALID UNTIL` déjà passé** et ExternalSecret à l'heure (durée trop courte : variante 1) ; compte **absent** alors qu'il devait vivre encore (supprimé : variante 2) ; ExternalSecret **en erreur**, compte présent mais bientôt expiré, comptes expirés qui s'accumulent (le coffre ne délivre plus et ne révoque plus : variantes 3 et 4).

**Étape 2 — Le coffre**

```
admin@adm01:~$ bao list sys/leases/lookup/db-mediagenda/creds/mediagenda-api-recette
admin@adm01:~$ bao lease lookup db-mediagenda/creds/mediagenda-api-recette/<BAIL>    # issue_time, expire_time, ttl
admin@adm01:~$ bao read db-mediagenda/roles/mediagenda-api-recette
admin@adm01:~$ bao read db-mediagenda/config/mediagenda-recette                       # jamais de mot de passe affiché
admin@vault01:~$ sudo journalctl -u openbao --since -2h | grep -E 'failed to revoke|mediagenda' | tail
```

Audit (Grafana, Loki, locataire `audit`) — ce qui a été demandé ou modifié sur le moteur et sur les baux :

```logql
{service="openbao"} | json type="type", chemin="request.path", op="request.operation", qui="auth.display_name", erreur="error"
  | type="response" | chemin=~"db-mediagenda/.+|sys/leases/revoke.*"
  | line_format "{{.op}} {{.chemin}} {{.qui}} {{.erreur}}"
```

Un identifiant d'essai, **révoqué aussitôt** : `bao read -format=json db-mediagenda/creds/mediagenda-api-recette | jq -r .lease_id`, puis `bao lease revoke <BAIL>` (ne jamais afficher la réponse complète : elle contient le mot de passe).

**Étape 3 — La base et le réseau** (si le coffre ne délivre plus)

```
admin@vault01:~$ timeout 5 bash -c '</dev/tcp/10.10.41.64/5432' && echo ouvert || echo fermé     # sur le nœud ACTIF
admin@adm01:~$ kubectl -n mediagenda-recette get svc mediagenda-db-openbao -o wide
admin@adm01:~$ kubectl -n mediagenda-recette get ciliumnetworkpolicies
admin@adm01:~$ hubble observe --namespace mediagenda-recette --port 5432 --verdict DROPPED --last 20
admin@adm01:~$ kubectl -n mediagenda-recette get cluster mediagenda-db -o jsonpath='{.spec.managed.roles[?(@.name=="openbao")]}'; echo
```

**Variante 1 — `max_ttl` du rôle ramené à 10 min.**

```
admin@adm01:~$ bao read -format=json db-mediagenda/roles/mediagenda-api-recette | jq -c '.data | {default_ttl, max_ttl}'
{"default_ttl":3600,"max_ttl":600}
```

Un bail dure le plus petit de `default_ttl` et `max_ttl` (lui-même plafonné par le montage, 24 h) : 10 min. `VALID UNTIL` suit (`{{expiration}}`), et OpenBao fait `DROP ROLE` à la fin du bail. ESO ne redemande qu'au bout de 30 min : chaque cycle laisse **20 min** sans compte valable, puis l'API remarche 10 min après le redémarrage par Reloader. C'est le « toutes les heures environ » du ticket : **périodique**, sans aucune erreur côté coffre. Audit : `update db-mediagenda/roles/mediagenda-api-recette` par un jeton de personne ; `tofu plan` de `plateforme/secrets` : `vault_database_secret_backend_role.mediagenda["mediagenda-api-recette"]`, `max_ttl 600 -> 86400`. Correctif : apply de `main` par le pipeline (le dépôt a raison), puis rafraîchissement forcé :

```
admin@adm01:~$ kubectl -n mediagenda-recette annotate es mediagenda-db-api force-sync=$(date +%s) --overwrite
admin@adm01:~$ kubectl argo rollouts get rollout mediagenda -n mediagenda-recette --watch
```

Les comptes déjà délivrés gardent leur bail de 10 min (la durée est fixée à l'émission) : seul un nouveau compte vit 1 h. Prod : même effet si l'on touche `mediagenda-api-prod`.

**Variante 2 — baux révoqués « par ménage ».**

```
admin@adm01:~$ bao list sys/leases/lookup/db-mediagenda/creds/mediagenda-api-recette
No value found at sys/leases/lookup/db-mediagenda/creds/mediagenda-api-recette
```

Plus aucun bail, et le compte du Secret est **absent** de `pg_roles` alors qu'il devait vivre encore une demi-heure. Audit : `update sys/leases/revoke-prefix/db-mediagenda/creds/mediagenda-api-recette` (ou une série de `sys/leases/revoke`). La révocation a fait `DROP ROLE` de tous les comptes en service : les sessions ouvertes cessent de fonctionner, les nouvelles connexions sont refusées. ESO ne le sait pas : le Secret garde un compte mort jusqu'au rafraîchissement suivant (≤ 30 min), puis tout repart seul — panne **unique**, qui « revient seule ». Redémarrer les pods ne sert à rien (ils relisent le même Secret). Correctif : rafraîchissement forcé tout de suite (commande ci-dessus). Le « ménage » n'avait aucun objet : un bail expiré est révoqué par OpenBao lui-même, et `revoke-prefix` est un geste d'incident (RB-250). Remarque pour le post-mortem : `plateforme-admin` porte `sys/leases/revoke-prefix/*` (M25-E23), donc **aussi** sur `db-mediagenda/creds/mediagenda-api-prod` ; en prod, la même commande coupe la prod pour ≤ 30 min.

**Variante 3 — mot de passe d'`openbao` changé dans PostgreSQL.**

```
admin@adm01:~$ kubectl -n mediagenda-recette describe es mediagenda-db-api | sed -n '/Events/,$p'
  Warning  …  … password authentication failed for user "openbao" …
admin@vault01:~$ sudo journalctl -u openbao --since -1h | grep 'failed to revoke lease' | tail -1
… failed to revoke lease: lease_id=db-mediagenda/creds/mediagenda-api-recette/… error="… password authentication failed for user \"openbao\" …" attempts=2 …
```

Le coffre ne peut plus **ni créer ni supprimer** de compte. ESO passe en erreur et **garde** l'ancien Secret : l'API tient jusqu'au `VALID UNTIL` de son compte (≤ 1 h), puis chaque nouvelle connexion est refusée : panne **permanente**, qui ne revient pas seule. Les comptes expirés non supprimés s'accumulent dans `pg_roles`. Qui a changé le mot de passe ? Deux pistes : `passwordSecret` revenu dans `managed.roles` du Cluster (CNPG réapplique alors le mot de passe de ce Secret, M25-E14), ou un `ALTER ROLE` à la main (PostgreSQL ne le journalise pas par défaut : question pour le post-mortem). `rotate-root` échoue, puisqu'OpenBao doit d'abord se connecter. Reprise par le superutilisateur de CNPG ([`reprise-openbao.sql`](fichiers/M25-E38/k8s/espaces/mediagenda-recette/sql/reprise-openbao.sql)) :

> ⚠️ **Attention** : ouvre d'abord une session de secours (`kubectl cnpg psql mediagenda-db -n mediagenda-recette`) et garde-la jusqu'à la fin. Le mot de passe provisoire est tiré **dans** PostgreSQL et ne passe que par le tube ; s'il échoue en route, rejoue simplement la commande.

```
admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -X -qAt -d mediagenda -f - \
    < ~/src/k8s/espaces/mediagenda-recette/sql/reprise-openbao.sql | tr -d '\r\n' \
    | bao write db-mediagenda/config/mediagenda-recette password=-
Success! Data written to: db-mediagenda/config/mediagenda-recette
admin@adm01:~$ bao write -f db-mediagenda/rotate-root/mediagenda-recette
admin@adm01:~$ kubectl -n mediagenda-recette annotate es mediagenda-db-api force-sync=$(date +%s) --overwrite
```

L'écriture n'envoie que `password` : le reste de la connexion est conservé, et `verify_connection` refuse un mot de passe faux. Après `rotate-root`, plus personne ne connaît le mot de passe. OpenBao réessaie seul les révocations en échec ; un bail abandonné après trop d'échecs (« irrévocable ») laisse un compte `v-…` expiré à supprimer (`identifiants-dynamiques.md` § 6). Le code ne change pas (`tofu plan` vide : le mot de passe n'est pas dans l'état). Prod : même mécanique, l'API de prod tombe dans l'heure.

**Variante 4 — politique réseau qui refuse le coffre.**

```
admin@vault01:~$ timeout 5 bash -c '</dev/tcp/10.10.41.64/5432' && echo ouvert || echo fermé
fermé
admin@adm01:~$ hubble observe --namespace mediagenda-recette --port 5432 --verdict DROPPED --last 5
… 10.10.20.21:… -> mediagenda-recette/mediagenda-db-1:5432 … DROPPED (Policy denied by denylist)
admin@adm01:~$ kubectl -n mediagenda-recette get cnp mediagenda-db-quarantaine -o yaml | sed -n '/annotations/,$p'
```

ESO en erreur avec un délai dépassé (et non une authentification refusée), révocations en échec, puis même chronologie que la variante 3. La politique `mediagenda-db-quarantaine` (« durcissement SEC-2638 ») pose `ingressDeny` depuis `10.10.20.0/24` vers 5432 : un **refus** l'emporte sur toute autorisation, y compris `mediagenda-db-depuis-openbao`. Elle n'est pas dans `plateforme/k8s` (objet créé à la main). Elle était de surcroît **inutile** : les instances sont déjà en refus par défaut, seules 10.10.20.21-23 sont autorisées ; un « durcissement » s'écrit en resserrant les autorisations, pas en ajoutant un refus large. Correctif : avec l'accord de l'auteur du ticket SEC-2638 (annotation), suppression de l'objet hors Git, consignée dans le journal et le ticket (`kubectl -n mediagenda-recette delete cnp mediagenda-db-quarantaine`) ; si une exigence demeure, MR `plateforme/k8s`. Puis rafraîchissement forcé. OpenBao se reconnecte seul à la requête suivante.

**Pourquoi la panne n'apparaît pas à l'instant du changement (variantes 3 et 4).** Le greffon PostgreSQL d'OpenBao garde un pool de connexions ouvertes (`max_open_connections` 4) : un changement de mot de passe ou une nouvelle politique Cilium ne touchent pas une connexion déjà établie. La panne se révèle à la **prochaine** connexion : bascule du primaire CNPG, changement de leader d'OpenBao, redémarrage d'un nœud — souvent la nuit, sans lien apparent. L'injection coupe les sessions d'`openbao` pour que tu la voies tout de suite.

**Clôture commune** : boucle `curl` sur `/pret` pendant le redémarrage (aucun 503), `pg_stat_activity` montre le nouveau compte, `lab/bin/check 25 38`, `lab/bin/break 25 38 --annuler`, journal ([modèle](fichiers/M25-E38/medisphere/docs/socle/journal/AAAA-MM-JJ-INC-5238.md)).

**Prévention**
- **Audit** : trois règles ajoutées au ruler de Loki ([extrait](fichiers/M25-E38/observabilite/loki/regles/audit/openbao.yaml.extrait)) : `IdentifiantsDynamiquesEnEchec` (demandes `creds` en erreur depuis 5 min : variantes 3 et 4, **avant** que l'application tombe), `OpenBaoBauxRevoquesEnMasse` (variante 2), `MoteurDatabaseModifie` (variante 1, à rapprocher d'une MR).
- **Règle de durée** : vie d'un identifiant ≥ 2 cycles d'ESO, écrite dans [`identifiants-dynamiques.md` § 6](fichiers/M25-E38/medisphere/docs/securite/secrets/identifiants-dynamiques.md.extrait) avec la démarche en quatre questions ; le plan planifié de `plateforme/secrets` (M25-E40) signale toute dérive du rôle.
- **Base et réseau** : `passwordSecret` ne revient jamais dans le rôle `openbao` (relecture des MR du Cluster) ; politiques réseau des bases uniquement dans Git, relues par l'équipe Plateforme.

**Explications**

| Variante | Côté coffre | Côté base | Forme du symptôme | La prod |
|---|---|---|---|---|
| 1. `max_ttl` 10 min | baux de 10 min, aucune erreur | comptes expirés puis supprimés à 10 min | **périodique** : 20 min de panne par cycle de 30 | idem si son rôle est touché |
| 2. révocation | plus aucun bail | comptes supprimés d'un coup | **unique**, ≤ 30 min, guérit seule | ≤ 30 min de coupure |
| 3. mot de passe d'`openbao` | `creds` et révocations en erreur (authentification) | comptes expirés qui s'accumulent | **permanente**, après ≤ 1 h | tombe dans l'heure |
| 4. `ingressDeny` | `creds` et révocations en erreur (délai) | idem | **permanente**, après ≤ 1 h | tombe dans l'heure |

La marge du montage E14/E15 vient de trois horloges : bail 1 h, cycle d'ESO 30 min, redémarrage par Reloader ≈ 2 min. Tant que le bail dure au moins deux cycles, un rafraîchissement raté ne coupe rien. ESO ne renouvelle **pas** les baux et ne révoque pas les anciens : il redemande. `VALID UNTIL` n'est contrôlé qu'à l'authentification : une session ouverte survit à l'expiration du mot de passe, pas à `DROP ROLE`.

**Alternatives**
- Raccourcir `refreshInterval` (10 min) : plus de marge, trois fois plus de comptes et de révocations ; ne dispense pas de la règle de durée.
- Application qui relit un fichier monté et reconnecte son pool à l'erreur d'authentification (E15, « Pour aller plus loin ») : plus de redémarrage, mais la panne de délivrance (3, 4) reste.
- Rôle **statique** (`static-roles`) pour l'API : un seul compte, mot de passe tourné par OpenBao ; supprime les révocations, garde la dépendance à la connexion `openbao`.
- Variante 3 : redonner un mot de passe **connu** puis l'écrire à la main dans OpenBao : marche, mais un humain l'a vu ; le tube + `rotate-root` évite qu'il existe hors du coffre.

**Pièges classiques**
- Redémarrer les pods de l'API : ils relisent le même Secret, avec le même compte mort.
- Lancer `rotate-root` pour « réparer » la variante 3 : il échoue (il lui faut une connexion) — la reprise passe par la base.
- Supprimer l'ExternalSecret pour forcer : Argo CD le recrée, et l'on perd l'historique des événements ; `force-sync` suffit.
- « Faire le ménage » des comptes `v-…` par `revoke-prefix` ou `DROP ROLE` : on coupe les comptes en service.
- Recopier `uri` du Secret, ou la réponse complète de `bao read …/creds/…`, dans le journal ou le ticket.
- Se croire tiré d'affaire parce que l'API répond encore en variante 3 ou 4 : elle tombe au `VALID UNTIL` de son compte.
- Toucher à la prod « pour comparer » : `force-sync` et `rotate-root` y ont les mêmes effets.

**En production chez MédiSphère**

`IdentifiantsDynamiquesEnEchec` est **critique** pour la prod (l'astreinte a moins d'une heure) ; `OpenBaoBauxRevoquesEnMasse` exige un numéro d'incident ; le plan planifié de `plateforme/secrets` et la règle de durée sont relus à chaque MR du moteur ; la procédure de reprise de la connexion est répétée une fois par semestre en recette (bascule du primaire puis vérification que le coffre délivre encore).

---
