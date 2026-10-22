# Module 22 — Journaux : palier 4 — Expert

Les journaux de MédiSphère sont centralisés, cloisonnés, conservés selon des règles écrites, protégés. Nadia Roussel pose la question qu'elle pose à la fin de chaque module : « Le jour où les journaux eux-mêmes tombent en panne, au moment précis où on en a besoin, qui sait quoi faire ? » Karim Benali a préparé quatre pannes tirées de vrais incidents de plateformes de journaux — un nœud qui devient muet, Loki qui refuse d'écrire, des requêtes qui expirent, une équipe qui ne voit plus rien — puis une astreinte où il faut **enquêter par les journaux** pendant que l'outillage des journaux fait des siennes. Tu finis sous le capot : ce que deviennent une ligne, un chunk et un index entre Alloy et le compartiment.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Trois règles propres aux journaux :
- **Suis la ligne.** Une ligne de journal passe par la source (application, journald, fichier du pod), le collecteur (Alloy : découverte, lecture, positions, traitement, affectation du locataire, envoi), Loki (distributeur, limites, ingester, WAL, vidage vers le stockage), puis revient par la requête (requêteur, index, chunks, limites de requête) jusqu'à Grafana (source, en-tête du locataire). Situe l'étage avant de toucher quoi que ce soit : chacun a ses métriques, ses journaux et son interface (`alloy` sur le port 12345, `/metrics` et `/config` de Loki, l'inspecteur de requête de Grafana).
- **Les journaux de l'outil de journaux sont ailleurs.** Quand Loki ou Alloy vont mal, leurs propres journaux n'arrivent peut-être plus dans Loki : `kubectl logs`, `journalctl` sur le nœud, et les métriques dans Prometheus (`loki_*`, `loki_write_*`, `alloy_*`).
- **Le code fait foi, l'historique aussi.** Loki, Alloy et Grafana sont configurés par `plateforme/observabilite`, appliqué par Argo CD : un changement à chaud est défait au prochain passage d'Argo CD. Corrige par une MR, et lis `git log` : la plupart des pannes de configuration ont un auteur et une date.

> **Rappels** : tout se lance depuis `adm01`. `LOKI_ADDR=http://loki.apps.par1.medisphere.internal:3100` et `logcli --org-id=<locataire>` ; Grafana pour les sources par locataire ; ton kubeconfig personnel pour le cluster ; `argocd` (lecture et synchronisation) ; SSH vers les nœuds (`admin` + `sudo`).

## Règles du jeu des pannes (M22-E19 à M22-E23)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 22 19
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab (ta configuration diffère de celle du corrigé), le script en essaie une autre. Une injection prend **de 2 à 15 minutes** : certaines passent par un commit dans GitLab, une MR, le pipeline et la synchronisation d'Argo CD, et le script attend de constater l'effet.
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 22 19`) : il doit être vert. Le script refuse de casser un lab qui ne va pas bien (Loki pas prêt, Applications `loki` ou `alloy` pas `Synced/Healthy`, Alloy absent d'un nœud, aucune ligne récente).
- **Prérequis techniques** : le jeton d'administration GitLab de M01 (`WB_GITLAB_ADMIN_TOKEN_FILE`, portée `api`, à date d'expiration courte) ; `yq` de mikefarah (v4) et `jq` sur `adm01` ; les fichiers `plateforme/observabilite` aux emplacements du module (`loki/values.yaml`, `alloy/values.yaml`, `alloy/config.alloy`, `grafana/sources-loki.yaml`) — sinon les variables `WB_M22_FICHIER_*` de `lab/lab.env` les désignent.
- **Commits de Lucas.** Certaines pannes modifient `plateforme/observabilite` par un commit signé « Lucas Martin » (marqueur `M22-EXX` dans le message) ; si `main` refuse la poussée directe, elles passent par une MR que le script fusionne après son pipeline. C'est un vrai changement : il apparaît dans `git log`, dans l'historique d'Argo CD et dans le journal d'audit de GitLab. Corrige comme tu le ferais d'un vrai commit fautif (revert par MR, ou correction par MR).
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les nœuds, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 22 19 --annuler` remet l'état sain (filet de sécurité, pas un correctif). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne : l'annulation ne défait jamais ta réparation (elle ne touche un fichier que s'il est encore exactement dans l'état injecté), et une panne laissée ouverte bloque l'astreinte M22-E23 et le mini-projet.
- Les pannes n'agissent que sur : les nœuds de `k8s-par1` (un fichier de journald, un répertoire renommé, une taint), les objets des espaces `journaux` et `wb-pannes`, un Role et un RoleBinding ajoutés dans `mediagenda-recette` (E23), et le dépôt `plateforme/observabilite`. **Aucune donnée n'est détruite** : aucun objet du compartiment `loki-k8s-par1`, aucune rétention raccourcie, aucun journal système effacé (au pire renommé), et les seuls rendez-vous supprimés en E23 sont ceux que la panne a elle-même créés.
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/kubernetes/journal/` de `~/medisphere` : heure, hypothèse, commande, résultat observé, conclusion. Il alimente les runbooks RB-222 à RB-224 et le post-mortem de M22-E23.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Effets de bord** : pendant une panne d'écriture (E20), des lignes de journal du lab sont **réellement perdues** (Alloy abandonne après ses tentatives) ; ne lance pas ces pannes pendant un exercice d'un autre module qui a besoin de ses journaux. Une panne de requête (E21) ou de locataire (E22) peut faire croire à une perte de données : c'est le but, n'y réponds jamais en touchant à la rétention ou au compartiment.

---

### M22-E19 — Panne : plus aucun journal d'un nœud  `BF` `★★`

> **Ticket INC-4919** — *De : Nadia Roussel* (ou Sophie Laurent, selon le cas)
> *(Le détail s'affiche à l'injection : selon le cas, plus aucun journal d'un nœud, plus aucun journal système d'un nœud alors que ses pods journalisent, ou plus aucun journal des nœuds de contrôle ni de l'audit.)*

**Objectifs pédagogiques**
- Suivre la collecte d'un nœud de bout en bout : pod Alloy du nœud (ordonnancement, tolérances), sources (fichiers des pods, journald), positions, envoi.
- Distinguer « Alloy ne tourne pas sur ce nœud » de « Alloy tourne mais n'a rien à lire » et de « Alloy lit mais Loki ne reçoit pas ».
- Connaître le stockage de journald (persistant, volatil, aucun) et ce qu'il implique pour un collecteur.

**Prérequis** : M22-E03, M22-E07 ; `lab/bin/check 22 19` vert avant l'injection.
**Durée indicative** : 20 à 30 min (temps cible).

**Contexte technique** : Alloy (DaemonSet `alloy`, espace `journaux`) lit `/var/log/pods` et `/var/log/journal` de son nœud (montages `hostPath`), garde ses positions dans `/var/lib/alloy` du nœud, et expose son interface et ses métriques sur le port 12345 (`kubectl -n journaux port-forward pod/<alloy-…> 12345`). Les nœuds de contrôle portent la taint `node-role.kubernetes.io/control-plane:NoSchedule`, `k8s-w03` la taint `dedie=bdd:NoSchedule`.

**Injection** : `lab/bin/break 22 19` (4 variantes).

**Travail demandé**
1. Constate sans rien toucher : depuis quand le nœud est-il muet (requête Loki sur `{node="…"}`), qu'est-ce qui manque exactement (pods, journald, audit), le nœud lui-même va-t-il bien (`kubectl get nodes`, pods du nœud) ?
2. Situe l'étage : le pod Alloy du nœud existe-t-il, est-il prêt, que disent son interface (composants en erreur) et ses journaux ? Sinon, pourquoi le DaemonSet ne le planifie-t-il pas (`desiredNumberScheduled`, événements, taints, tolérances) ? Si Alloy tourne, sur le nœud : journald écrit-il encore, et où (`journalctl --header`, `systemd-analyze cat-config systemd/journald.conf`) ?
3. Trouve la cause racine et son auteur (commit, annotation, fichier, journal du nœud), corrige-la au bon endroit (Git si c'est la configuration d'Alloy, le nœud par Ansible si c'est le système), sans perdre ce qu'il reste du journal.
4. Vérifie le retour : lignes récentes de chaque nœud, journal d'audit, `lab/bin/check 22 19`. Ce qui n'a pas été collecté pendant la panne l'est-il après coup ? Pourquoi ?
5. Écris le runbook **RB-222** « Des journaux manquent (nœud, équipe) » (`docs/observabilite/journaux/runbooks/RB-222-*.md`) : un arbre de décision par étage (planification du DaemonSet, état d'Alloy, sources sur le nœud, envoi), avec la commande qui prouve chaque branche. Ajoute ce qui aurait dû alerter (Alloy absent d'un nœud, nœud muet depuis 10 min).

**Critères de réussite**
- [ ] Alloy est prêt sur les six nœuds, avec une tolérance qui couvre les nœuds de contrôle ; aucune taint de maintenance oubliée.
- [ ] Chaque nœud a des lignes récentes dans Loki, le journal d'audit aussi ; journald est persistant sur chaque nœud.
- [ ] RB-222 est publié ; ton journal contient l'étage en cause et sa preuve.

**Vérification** : `lab/bin/check 22 19`

<details><summary>Indice 1</summary>

`kubectl -n journaux get ds alloy -o wide` compare le nombre de pods souhaités et prêts au nombre de nœuds. `kubectl describe node <nœud>` (section `Taints`) et `kubectl -n journaux get ds alloy -o jsonpath='{.spec.template.spec.tolerations}'` disent si le DaemonSet a le droit d'y aller. Un DaemonSet ne tolère d'office que quelques taints posées par Kubernetes lui-même.
</details>

<details><summary>Indice 2</summary>

Si Alloy tourne sur le nœud, écris une ligne de test dans journald (`logger -t essai "ligne de test"`) et cherche-la dans Loki puis sur le nœud (`journalctl -t essai`). `journalctl --header | grep 'File path'` dit où journald écrit ; `ls -ld /var/log/journal* /run/log/journal` complète le tableau. Ce qu'Alloy voit dépend de ce qui est monté dans son conteneur.
</details>

<details><summary>Indice 3</summary>

`git log -p -- alloy/` dans `plateforme/observabilite`, l'historique de l'Application `alloy` dans Argo CD, les annotations du nœud, la date des fichiers de `/etc/systemd/journald.conf.d/` : la panne a laissé une trace. Un répertoire du journal renommé se remet en place et se recharge (`journalctl --flush`) ; on ne le supprime pas.
</details>

**Pour aller plus loin** : mesure combien de temps Alloy met à rattraper un nœud après 10 minutes d'arrêt de son pod (métrique `loki_write_sent_entries_total` et âge des lignes) ; écris l'alerte « nœud muet » en LogQL (*ruler*) et en PromQL (`kube_daemonset_status_number_ready`), et compare.

---

### M22-E20 — Panne : Loki refuse les écritures  `BF` `★★★`

> **Ticket INC-4920** — *De : Julien Petit, Karim Benali ou Nadia Roussel, selon le cas*
> *(Le détail s'affiche à l'injection : selon le cas, des journaux d'une équipe qui n'arrivent presque plus, les journaux des nouveaux déploiements qui n'arrivent pas, ou Loki qui renvoie des erreurs 500 et se plaint de son stockage.)*

**Objectifs pédagogiques**
- Lire un refus d'écriture des deux côtés : codes HTTP et messages reçus par Alloy (`429`, `400`, `500`), raisons comptées par Loki (`loki_discarded_samples_total{reason,tenant}`), échecs de vidage vers le stockage.
- Relier chaque raison à son mécanisme : débit et rafale par locataire, nombre de flux actifs, identifiants du stockage objet.
- Corriger dans la configuration par locataire sans élargir les limites des autres, et chiffrer ce qui a été perdu.

**Prérequis** : M22-E13, M22-E14 ; `lab/bin/check 22 20` vert avant l'injection.
**Durée indicative** : 30 à 45 min (temps cible).

**Contexte technique** : les limites par locataire sont dans `loki.runtimeConfig` de `loki/values.yaml` (ConfigMap `loki-runtime`) ; les limites effectives publiées se lisent par `/config/tenant/v1/limits`, les autres dans le ConfigMap. Les identifiants du compartiment sont dans le Secret `loki-objstore` (hors Git), créé par `plateforme/k8s/outils/secrets-k8s.sh` à partir d'Ansible Vault `critique` (`secrets/loki.yml`). Le WAL de Loki est sur son volume : ce qui a été reçu et pas encore vidé survit à un redémarrage.

**Injection** : `lab/bin/break 22 20` (3 variantes).

**Travail demandé**
1. Mesure le symptôme : quels locataires, quels flux, depuis quand ; compare ce que montre `kubectl logs` d'un pod concerné et ce que Loki a reçu.
2. Regarde les deux côtés : journaux et interface d'Alloy (erreurs d'envoi, code HTTP, message de Loki), métriques `loki_write_*` d'Alloy, métriques `loki_discarded_*` et `loki_ingester_*` de Loki, journal du pod `loki-0`.
3. Trouve la cause racine et son auteur ; corrige au bon endroit (MR dans `plateforme/observabilite`, ou secret par la procédure de M22-E02 — jamais un secret dans Git). Si Loki doit redémarrer, vérifie que rien de ce qu'il avait reçu n'est perdu (WAL, vidage).
4. Chiffre la perte : combien de lignes ont été abandonnées par Alloy pendant la panne (`loki_write_dropped_entries_total`), lesquelles, et peut-on les récupérer ?
5. Écris le runbook **RB-223** « Loki refuse les écritures » : tableau raison → symptôme → preuve → correctif (débit, rafale, flux, taille de ligne, âge des lignes, stockage), et ce qu'il ne faut jamais faire (lever toutes les limites de tous les locataires).

**Critères de réussite**
- [ ] Les locataires reçoivent de nouveau leurs lignes ; aucune ligne rejetée ni échec de vidage depuis 10 minutes ; la lecture du stockage sur 24 h fonctionne.
- [ ] Les limites de chaque locataire sont de nouveau cohérentes avec leur volume (débit ≥ 1 Mo/s pour les applications, limite de flux au moins le double des flux actifs).
- [ ] RB-223 est publié ; ton journal chiffre les lignes perdues.

**Vérification** : `lab/bin/check 22 20`

<details><summary>Indice 1</summary>

`kubectl -n journaux logs ds/alloy --since=10m | grep -i -E 'error|429|500'` sur le nœud qui porte le pod concerné, et dans Prometheus : `sum by (tenant, reason) (rate(loki_discarded_samples_total[5m]))`. Le message de Loki est explicite : il dit quelle limite, pour quel locataire, et souvent la valeur.
</details>

<details><summary>Indice 2</summary>

Pour un problème de stockage : `kubectl -n journaux logs loki-0 -c loki | grep -i -E 's3|bucket|denied|signature'`, puis une requête sur une plage ancienne (qui doit lire le compartiment). Compare les identifiants du Secret avec ceux de `~/.config/workbook/s3-loki.env` **sans les afficher** (une empreinte `sha256sum` suffit).
</details>

**Pour aller plus loin** : provoque toi-même un `429` sur le locataire `essai` (limite basse, `ressources/E13-effacement/pousser-essai.sh` en boucle) et mesure le comportement d'Alloy (`max_backoff_retries`, `retry_on_http_429`) ; lis dans la documentation d'Alloy ce que change le WAL expérimental de `loki.write` en 1.21.

---

### M22-E21 — Panne : les requêtes expirent  `BF` `★★★`

> **Ticket INC-4921** — *De : Nadia Roussel*
> Mon tableau « Activité par espace sur 24 h » (locataire plateforme) affiche une erreur depuis ce matin, et dans Explore les requêtes sur plusieurs heures échouent alors que celles sur 5 minutes passent. *(Le détail s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Lire une erreur de requête Loki et la relier à la limite qui la produit : délai, durée maximale de la plage, nombre de séries, découpage.
- Utiliser l'inspecteur de requête de Grafana, `logcli --stats` et `/config/tenant/v1/limits` pour prouver une hypothèse avant de changer quoi que ce soit.
- Distinguer une limite de protection légitime d'un réglage fautif, et corriger sans désarmer les protections.

**Prérequis** : M22-E14 ; `lab/bin/check 22 21` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 22 21` (3 variantes).

**Travail demandé**
1. Reproduis l'erreur hors de Grafana (`logcli`, `curl` sur `query_range`) et note le code HTTP et le message exact. La même requête passe-t-elle pour un autre locataire ? sur une plage plus courte ?
2. Lis les limites effectives du locataire concerné et compare-les à celles d'un locataire qui fonctionne ; retrouve qui a changé quoi, et quand.
3. Corrige par une MR ; explique dans la description pourquoi la valeur d'origine était juste (référence aux mesures de `performance.md`).
4. Vérifie le tableau de Nadia sur 24 h et une requête sur 7 jours.
5. Écris le runbook **RB-224** « Requêtes Loki lentes ou en échec » : messages fréquents (délai, plage, séries, lignes, octets lus) et leur limite, lecture de `--stats`, reformulations qui allègent une requête, et quand augmenter une limite (jamais sans mesure).

**Critères de réussite**
- [ ] Le tableau de Nadia sur 24 h et une requête sur 7 jours répondent pour le locataire `plateforme`.
- [ ] Chaque locataire a un délai d'au moins 30 s, une durée de plage d'au moins 7 jours et au moins 100 séries ; le découpage des requêtes est actif.
- [ ] RB-224 est publié.

**Vérification** : `lab/bin/check 22 21`

<details><summary>Indice 1</summary>

`curl -s -G -H 'X-Scope-OrgID: plateforme' "$LOKI_ADDR/loki/api/v1/query_range" --data-urlencode 'query=…' --data-urlencode since=24h -w '\n%{http_code}\n'` montre le message brut, que Grafana résume parfois. `curl -s -H 'X-Scope-OrgID: plateforme' "$LOKI_ADDR/config/tenant/v1/limits"` montre les limites qui s'appliquent vraiment à ce locataire.
</details>

<details><summary>Indice 2</summary>

Une limite par locataire peut venir de deux endroits : `limits_config` (pour tous) ou une surcharge du locataire dans `runtimeConfig`. `git log -p -- loki/values.yaml` dans `plateforme/observabilite` dit lequel a bougé.
</details>

**Pour aller plus loin** : mesure l'effet de `split_queries_by_interval: 0` (découpage désactivé) sur la requête de 7 jours, puis l'effet du cache des résultats sur la deuxième exécution ; ajoute les deux mesures à `performance.md`.

---

### M22-E22 — Panne : les journaux d'une équipe ont disparu  `BF` `★★`

> **Ticket INC-4922** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection : selon le cas, la source Grafana de MédiAgenda ne montre plus rien de récent, ou MédiDoc ne retrouve plus ses journaux d'hier.)* On a perdu nos journaux ?

**Objectifs pédagogiques**
- Distinguer **perte** de données et **perte de vue** : journaux écrits dans un autre locataire, source Grafana mal réglée, profondeur de requête réduite.
- Vérifier le chemin du locataire de bout en bout : règle d'affectation dans Alloy, en-tête de la source Grafana, limites du locataire.
- Rassurer avec des preuves, avant de réparer.

**Prérequis** : M22-E03, M22-E06, M22-E13 ; `lab/bin/check 22 22` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 22 22` (3 variantes).

**Travail demandé**
1. Avant tout : les données existent-elles encore ? Cherche-les **directement dans Loki** depuis `adm01`, dans le locataire de l'équipe puis dans les autres, sur la période qui « manque ».
2. Situe l'étage : collecte (dans quel locataire arrivent aujourd'hui les flux de l'équipe ?), consultation (que demande Grafana à Loki, avec quel en-tête ?), limites (jusqu'où le locataire peut-il remonter ?).
3. Trouve la cause racine et son auteur ; corrige par une MR. Si des lignes ont été écrites dans le mauvais locataire pendant la panne, décide de ce qu'on en fait (les laisser, les signaler, les effacer par RB-221 ?) et justifie-le au regard de la politique.
4. Réponds à Julien : ce qui a été perdu (rien, ou quoi exactement), ce qui a été mal rangé, ce qui est rétabli.
5. Ajoute à **RB-222** une branche « une équipe ne voit plus ses journaux » : les trois étages, la commande qui prouve chacun, et la règle « ne jamais toucher à la rétention pour réparer un problème de vue ».

**Critères de réussite**
- [ ] Les journaux récents de MédiAgenda et de MédiDoc arrivent dans leur locataire, et plus aucun dans `plateforme`.
- [ ] La source Grafana « Loki — mediagenda » renvoie les journaux récents ; MédiDoc peut remonter sur toute sa rétention.
- [ ] RB-222 contient la branche sur les locataires ; ta réponse à Julien est dans ton journal.

**Vérification** : `lab/bin/check 22 22`

<details><summary>Indice 1</summary>

`logcli query --org-id=plateforme --since=1h '{namespace=~"mediagenda-.+"}'` : si des lignes de MédiAgenda sont là, elles ont été écrites dans le mauvais locataire. L'inspecteur de requête de Grafana (*Query inspector*) montre la requête envoyée ; l'en-tête, lui, se lit dans la définition de la source (code), pas dans l'interface.
</details>

<details><summary>Indice 2</summary>

Une requête qui ne renvoie que les dernières minutes, toujours la même durée, quelle que soit la plage demandée, ressemble à une limite. `curl -s -H 'X-Scope-OrgID: medidoc' "$LOKI_ADDR/config/tenant/v1/limits"` et l'historique de `loki/values.yaml` le confirment ou l'infirment.
</details>

**Pour aller plus loin** : écris une alerte du *ruler* qui sonne quand des flux d'espaces `mediagenda-*` ou `medidoc-*` apparaissent dans le locataire `plateforme`.

---

### M22-E23 — Astreinte : enquête par les journaux  `BF` `★★★★`

> **Ticket INC-4923** — *De : Nadia Roussel (astreinte)* — *Copie : Julien Petit, Sophie Laurent*
> *(Le détail s'affiche à l'injection.)* Des rendez-vous ont disparu en recette. Sophie veut savoir **qui**, **quand** et **comment**, preuves à l'appui, et que cela ne puisse pas se reproduire. Et pour corser le tout, l'outillage des journaux fait des siennes.

**Objectifs pédagogiques**
- Mener une enquête **uniquement par les journaux** : journaux applicatifs (locataire `mediagenda`), journal d'audit de l'API (locataire `audit`), événements Kubernetes, en reliant les heures, les identifiants et les identités.
- Rétablir d'abord ce qui empêche d'enquêter (une panne de M22-E19 à M22-E22) sans détruire de preuve.
- Conclure avec des preuves, remédier (droits retirés), et écrire un post-mortem qui tient devant la RSSI.

**Prérequis** : M22-E07 (journal d'audit), M22-E12 (RB-220), M22-E19 à M22-E22 ; `lab/bin/check 22 23` vert avant l'injection (il rejoue ceux de E19 à E22) ; aucune panne M22 active.
**Durée indicative** : 1 h 30 (enquête et rétablissement) + 45 min (post-mortem).

**Contexte technique** : MédiAgenda journalise en JSON une ligne par requête (`méthode`, `chemin`, `code`, `client`) et un événement par création et suppression de rendez-vous (`rdv_id`), jamais de donnée patient. Le journal d'audit de l'API (politique de M14-E27) trace les accès sensibles (dont `pods/exec`) au niveau `Metadata` : qui, quoi, quand, d'où. L'injection prend 10 à 20 minutes.

**Injection** : `lab/bin/break 22 23` (une panne enchaînée parmi E19 à E22, variante au hasard).

**Travail demandé**
1. **Rétablir l'outillage.** Lis le symptôme de l'outillage, répare-le comme en E19-E22 (sans toucher aux données), et vérifie que tu peux de nouveau interroger les locataires `mediagenda` et `audit` sur la période de l'incident.
2. **Enquêter.** À partir de ce que dit Julien (praticien, date des rendez-vous), retrouve dans les journaux de MédiAgenda **quand** les rendez-vous ont été supprimés, par quelles requêtes, depuis quelle adresse ; déduis-en **comment** (que veut dire l'adresse cliente ?). Puis, dans le journal d'audit, retrouve **qui** : quelle identité a fait quoi sur quel pod, à la même minute, et d'où venaient ses droits (création des objets RBAC, auteur, date).
3. **Remédier.** Sans attendre la fin du post-mortem : retire les droits fautifs (en le traçant), vérifie qu'aucun autre compte de service n'a de droit d'`exec` dans les espaces applicatifs. Préviens Julien des rendez-vous à recréer.
4. **Prévenir.** Propose (et écris dans le post-mortem) au moins une alerte tirée des journaux qui aurait détecté l'incident (par exemple : un `exec` dans un pod d'un espace `mediagenda-*` par une identité hors de l'équipe), et le contrôle d'admission ou de RBAC qui l'aurait empêché.
5. **Post-mortem.** Rédige `docs/kubernetes/post-mortems/AAAA-MM-JJ-INC-4923-*.md` avec le modèle de l'équipe (`modules/00-lab/ressources/M00-E46/modele-post-mortem.md`) : chronologie à la minute, causes (incident et panne de l'outillage), détection, preuves (requêtes LogQL et extraits **sans** secret ni jeton), actions.

**Critères de réussite**
- [ ] La panne de l'outillage est réparée et close ; toutes les vérifications de E19 à E22 sont vertes.
- [ ] Aucun compte de service de `wb-pannes` n'a plus de droit dans `mediagenda-recette`.
- [ ] Le post-mortem identifie l'identité, le geste (`exec`), l'heure et la preuve dans chaque locataire, sans recopier de secret.

**Vérification** : `lab/bin/check 22 23`

<details><summary>Indice 1</summary>

Commence large et resserre : `sum by (namespace) (count_over_time({namespace="mediagenda-recette"} |= "supprimé" [5m]))` sur la journée, puis les lignes autour de la bonne tranche, en JSON (`| json`) pour lire `rdv_id`, `methode`, `client`. Une adresse cliente `127.0.0.1` veut dire que la requête est née **dans** le pod.
</details>

<details><summary>Indice 2</summary>

Dans le locataire `audit`, un geste se trouve par sa ressource et sa sous-ressource (`pods`, `exec`), son espace et sa fenêtre de temps ; l'identité est dans le champ `user` (métadonnée structurée de E07, ou dans la ligne JSON). Un compte de service s'écrit `system:serviceaccount:<espace>:<nom>`. Ses droits viennent d'un RoleBinding : cherche sa création dans l'audit aussi.
</details>

<details><summary>Indice 3</summary>

Ton propre nom apparaît aussi dans l'audit à l'heure de l'injection (le script de panne agit avec ton kubeconfig, comme au M14) : en production, ce serait l'identité de la personne qui a préparé « l'outil ». Ne le confonds pas avec l'identité qui a supprimé.
</details>

**Pour aller plus loin** : transforme l'alerte du point 4 en règle du *ruler* (locataire `audit`) avec son test, et ajoute à RB-220 une section « enquête » avec les requêtes qui t'ont servi.

---

### M22-E24 — Sous le capot : ingestion, chunks et index TSDB  `LAB` `★★★★`

> **Ticket PLAT-2324** — *De : Karim Benali*
> Tu sais exploiter Loki. Maintenant je veux que tu saches ce qu'il y a dedans : ce que devient une ligne entre Alloy et le compartiment, à quoi ressemble un chunk, ce que contient l'index d'une journée, ce que fait le compactor, et comment une requête retrouve ses données. Une page, des objets réels de **notre** compartiment, pas des schémas recopiés.

**Objectifs pédagogiques**
- Suivre le chemin d'écriture : distributeur (validation, limites, hachage du flux), ingester (chunk en tête, WAL, points de reprise), vidage (chunk compressé, entrée d'index TSDB), téléversement de l'index.
- Lire le stockage : clés des chunks, tables d'index par jour et par locataire, fichiers du compactor et des demandes d'effacement, répertoires locaux de `loki-0`.
- Suivre le chemin de lecture : découpage, index, ingesters pour le récent, stockage pour l'ancien, filtres.

**Prérequis** : M22-E13, M22-E14, M22-E16 (versionnage).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Lecture du compartiment avec les identifiants de `~/.config/workbook/s3-loki.env` (`aws s3 ls`, `aws s3api list-objects-v2`, `head-object`, `get-object`) — **en lecture seulement**.
- L'image de Loki ne contient pas de shell : pour regarder dans `loki-0`, un conteneur éphémère de débogage qui partage l'espace de processus (`kubectl debug -it loki-0 -n journaux --image=registry.par1.medisphere.internal/dockerhub/library/busybox:1.37 --target=loki -- sh`, puis `ls /proc/1/root/var/loki`). Il ne modifie rien ; quitte-le proprement.
- L'outil `chunks-inspect` du dépôt de Loki (`cmd/chunks-inspect`, version 3.7) se construit avec Go 1.26 sur `adm01` et lit un chunk téléchargé.
- `logcli` : `series`, `stats`, `volume`, `query --stats`.

> ⚠️ **Attention** : on ne modifie **rien** dans le compartiment ni dans `loki-0`. Pas d'`aws s3 rm`, pas d'`aws s3 cp` **vers** le compartiment, pas d'écriture dans `/proc/1/root/var/loki`. Un chunk ou un index modifié à la main corrompt les requêtes de tout un locataire. Travaille sur des copies dans `~/m22/e24/`.

**Travail demandé**
1. **Écrire une ligne et la suivre.** Pousse dans le locataire `essai` une ligne repérable (horodatage, flux connu) ; suis-la : métriques du distributeur et de l'ingester, flux en mémoire, WAL de `loki-0` (répertoire, segments, points de reprise), puis, après le vidage, son chunk dans le compartiment. Ne force pas le vidage (`POST /flush` existe) : attends l'inactivité du flux (`chunk_idle_period`) et explique pourquoi un vidage forcé sur une plateforme partagée a un coût.
2. **Lire un chunk.** Télécharge ce chunk dans `~/m22/e24/`, inspecte-le avec `chunks-inspect` (en-tête, étiquettes, blocs, compression, intervalle de temps) ; explique la forme de sa clé (locataire, empreinte du flux, début, fin, somme de contrôle).
3. **Lire l'index.** Liste les tables d'index du compartiment (`index/loki_index_N/`) : à quoi correspond `N`, que contient une table (fichiers par locataire, fichiers produits par l'ingester puis par le compactor), quelle taille par rapport aux chunks de la même journée ?
4. **Compactor.** Repère ce qu'il a produit et où il travaille (`/var/loki/compactor`), les demandes d'effacement (E13), les marques de rétention ; relie aux métriques du compactor.
5. **Chemin de lecture.** Avec `logcli query --stats`, compare une requête sur les 10 dernières minutes et la même sur hier : d'où viennent les données (ingester ou stockage), combien de chunks, d'octets ?
6. **Rédige** `docs/observabilite/journaux/sous-le-capot.md` : schéma du chemin d'écriture et de lecture, une clé de chunk **réelle** et une table d'index **réelle** du compartiment, ce que contient le volume de `loki-0` et ce qu'on perd s'il disparaît, et trois questions que tu poserais à un candidat.

**Critères de réussite**
- [ ] `sous-le-capot.md` décrit distributeur, ingester, WAL, chunks, index TSDB, compactor et requêteur.
- [ ] Il cite une clé de chunk et une table d'index qui existent (ou ont existé) dans `loki-k8s-par1`.

**Vérification** : `lab/bin/check 22 24`

<details><summary>Indice 1</summary>

Les clés de chunks commencent par le locataire ; `aws s3 ls s3://loki-k8s-par1/essai/ --recursive --endpoint-url https://rgw.par1.medisphere.internal | sort -k1,2 | tail` montre les plus récentes. Le deuxième élément de la clé ne se lit dans aucune étiquette : compare les clés de deux flux qui ne diffèrent que d'une étiquette.
</details>

<details><summary>Indice 2</summary>

`N` dans `loki_index_N` est un numéro de période : le nombre de jours depuis le 1er janvier 1970 (la période d'index est de 24 h). `date -u -d @$((N * 86400))` le vérifie. Les fichiers d'une table sont compressés (`.gz`) : on peut en compter et en mesurer, pas les lire sans outil.
</details>

**Pour aller plus loin** : construis `tools/tsdb/index-analyzer` du dépôt de Loki et analyse une table d'index téléchargée ; compare le nombre de séries avec `logcli series` sur la même journée.
