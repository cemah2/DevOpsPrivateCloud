# Module 21 — Palier 4 : Expert

La supervision de MédiSphère tourne : kube-prometheus-stack sous Argo CD, Prometheus redondant derrière Thanos Query (10.10.41.60), Alertmanager (10.10.41.61) qui écrit à l'astreinte, Grafana et ses tableaux versionnés, des SLO, un compartiment `thanos-k8s-par1` qui garde deux ans d'historique, et `mon01` qui surveille le tout depuis l'extérieur. Nadia Roussel pose la question qui compte : « Le jour où c'est la supervision qui ment, qui s'en aperçoit ? » Une supervision ne tombe presque jamais en panne franche : elle devient **muette** (une cible disparaît, une règle ne se charge pas, un courriel ne part plus), **bavarde** (une alerte qui sonne sans arrêt jusqu'à ce que plus personne ne la lise), **aveugle** (un tableau vide, un historique troué, un témoin qui ne voit plus rien) ou **gloutonne** (une étiquette de trop et Prometheus s'effondre). Karim Benali a préparé huit pannes de ce genre, une astreinte en combine trois. Puis tu ouvres la base de Prometheus pour voir ce qu'il y a dans un bloc, et tu passes les questions d'entretien.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec trois règles propres à la supervision :
- **Remonte la chaîne, maillon par maillon.** Une donnée passe par : la cible (`/metrics` qui répond), la découverte (ServiceMonitor, ScrapeConfig, fichier de cibles), le sélecteur de Prometheus, le réseau (politiques, pare-feu, TLS), la collecte (`up`, `scrape_samples_*`), le stockage (tête, blocs, sidecar, compartiment, Store Gateway), la requête (Thanos Query, règles d'enregistrement), l'affichage (source de données et variables de Grafana) ; une alerte, elle, ajoute la règle (chargée ? évaluée ?), Alertmanager (route, inhibition, silence, regroupement) et le transport (SMTP). Chaque maillon a sa page ou son API : **Status → Targets / Service Discovery / Rules / TSDB Status** de Prometheus, `/api/v1/stores` de Thanos Query, `amtool` et l'API v2 d'Alertmanager, l'inspecteur de requêtes de Grafana.
- **Une absence de signal n'est pas un signal d'absence.** « Pas d'alerte » peut vouloir dire « tout va bien » ou « plus rien ne mesure ». Chaque panne de ce palier se termine par la question : *qu'est-ce qui aurait dû me prévenir, et pourquoi n'a-t-il rien dit ?*
- **Git fait foi, Argo CD réconcilie.** Une réparation à la main sur un objet géré par Argo CD est défaite en quelques secondes (`selfHeal`). Les corrections passent par une MR dans `plateforme/observabilite`, `mediagenda/deploiement` ou `plateforme/ansible`. Seuls les objets hors Git (Secrets créés par `secrets-k8s.sh`, silences, témoins de `wb-pannes`) se réparent sur place, et la réparation se reporte dans la procédure qui les crée.

> **Rappels** : tout se lance depuis `adm01`. Vues : `http://prometheus.apps.par1.medisphere.internal:9090` (Thanos Query, vue globale dédupliquée), `http://alertmanager.apps.par1.medisphere.internal:9093`, `https://grafana.apps.par1.medisphere.internal`, `https://mon01.par1.medisphere.internal:8025` (Mailpit, boîtes `astreinte@`, `plateforme@`…), `http://mon01.par1.medisphere.internal:9090` et `:9093` (témoin). Pour parler à **un** Prometheus du cluster plutôt qu'à la vue globale : `kubectl -n supervision port-forward pod/prometheus-kps-0 9091:9090` (l'objet Prometheus s'appelle `kps`, M21-E02). `amtool` lit l'Alertmanager du cluster avec `--alertmanager.url=http://alertmanager.apps.par1.medisphere.internal:9093`.

## Règles du jeu des pannes (M21-E35 à M21-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 21 35
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 à 5 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab (ta configuration diffère de celle du corrigé, ou **ta CI refuse la modification** : c'est alors elle qui a gagné), le script en essaie une autre.
- **Comment les pannes touchent ce qui est dans Git.** Comme une vraie erreur humaine : Lucas Martin ouvre une MR (jeton d'emprunt d'identité créé par ton jeton d'administration GitLab `WB_GITLAB_ADMIN_TOKEN_FILE`, puis révoqué), elle est fusionnée (fusion automatique quand le pipeline réussit, si ton projet l'exige), Argo CD synchronise. Le commit porte le marqueur `M21-EXX`. Une injection de ce type prend **5 à 20 minutes** (pipeline, synchronisation, effet constaté). L'annulation passe par une seconde MR (`revert(...)`), jamais par une réécriture d'historique, et seulement si la marque de la panne est encore dans le fichier.
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 21 35`) : il doit être vert. Le script refuse de casser une supervision qui ne va pas bien (vue globale ou Alertmanager muets, Applications `kube-prometheus-stack` et `observabilite` non synchronisées).
- **Témoins.** À la première injection, le script crée dans l'espace **`wb-pannes`** (celui du M14, créé s'il n'existe plus) une petite application qu'il ne supprime jamais : `temoin-metriques` (deux pods, image Python tirée par le cache Harbor), son Service, son ServiceMonitor, sa PrometheusRule et une CiliumNetworkPolicy qui autorise la collecte depuis `supervision` sans mettre les pods en refus par défaut. Son comportement est piloté par la ConfigMap `temoin-etat`. Ses alertes : `TemoinFileAttenteHaute` (gravité **critique**, équipe `plateforme` : elle va à l'astreinte), `EssaiChaineAlerteCritique` et `EssaiChaineAlerteAvertissement` (l'« essai mensuel de la chaîne d'alerte »). Au repos, aucune ne s'allume.
  - Pour que Prometheus collecte `wb-pannes`, le script pose sur l'espace les étiquettes demandées par les sélecteurs d'espaces de l'objet Prometheus (`serviceMonitorNamespaceSelector`, `ruleNamespaceSelector`) et sur les objets celles des sélecteurs d'objets. Si ta politique réseau de l'espace `supervision` (M21-E29) restreint la **sortie** de Prometheus, autorise `wb-pannes` (port 8000) avant le palier : le script te le dira s'il ne voit pas la cible.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les VMs, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause. L'historique Git, lui, est un outil de diagnostic légitime (qui a changé quoi, quand).
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 21 35 --annuler` remet l'état sain (filet de sécurité, pas un correctif). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne (sinon elle reste marquée active et bloque l'astreinte M21-E43 et le mini-projet) : l'annulation ne revient jamais sur ta réparation.
- Les pannes n'agissent que sur les objets de `supervision`, `wb-pannes` et `mediagenda-*`, sur les dépôts `plateforme/observabilite` et `mediagenda/deploiement`, sur `mon01` et sur trois VMs du socle (`WB_M21_VMS_PANNE`, par défaut `nbx01 dns02 runner01`). **Aucune donnée n'est supprimée** : ni bloc du compartiment `thanos-k8s-par1`, ni volume, ni série. Jamais sur `pve01`, `pbs01` ou une VM hors du pool `lab`.
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/kubernetes/journal/` de `~/medisphere` (publié par MR) : heure, hypothèse, commande, résultat, conclusion. Les runbooks du palier sont **RB-217** (« Une cible, une règle ou un tableau a disparu »), **RB-218** (« Les alertes sont muettes ou bavardes ») et **RB-219** (« Cardinalité et historique long »), dans `docs/observabilite/metriques/runbooks/` : chaque panne y ajoute sa section.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Les gestes interdits du palier**, sauf mention explicite dans ta démarche avec sa justification : supprimer un objet du compartiment `thanos-k8s-par1` ou lancer `thanos tools bucket` avec une sous-commande qui écrit (`cleanup`, `mark`, `rewrite`, `retention`) ; activer l'API d'administration d'un Prometheus **du cluster** ; `delete_series` ou `clean_tombstones` sur quelque Prometheus que ce soit ; désactiver l'auto-synchronisation d'une Application sans la rétablir ; corriger à la main un objet géré par Argo CD et en rester là ; recréer un Secret de stockage objet à partir d'une ancienne copie plutôt que de la source (Vault `critique`, `secrets-k8s.sh`).

> ⚠️ **Profil mémoire** : la panne M21-E38 fait monter la mémoire des deux Prometheus de plusieurs centaines de mégaoctets pendant une dizaine de minutes ; ne la lance pas pendant une autre opération lourde (OpenSearch du M22, reconstruction d'un nœud). La variante 2 de M21-E39 redémarre les deux réplicas de Prometheus l'un après l'autre.

---

### M21-E35 — Panne : une cible a disparu  `BF` `★★`

> **Ticket INC-4835** — *De : Julien Petit ou Nadia Roussel*
> *(Le détail du ticket s'affiche à l'injection : selon le cas, le tableau RED de MédiAgenda est vide pour la recette, ou une VM du socle n'a plus aucune courbe alors qu'elle répond en SSH.)* Personne n'a été alerté : c'est l'utilisateur du tableau qui s'en est aperçu.

**Objectifs pédagogiques**
- Distinguer une cible **disparue** (plus de série `up` du tout) d'une cible **en échec** (`up == 0`, avec une erreur lisible), et savoir où chacune se diagnostique (Service Discovery contre Targets).
- Remonter la découverte : ServiceMonitor → sélecteur de Prometheus → Service → port nommé → points de terminaison ; ScrapeConfig → cibles ; puis le réseau (CiliumNetworkPolicy, Hubble, pare-feu local) et TLS.
- Écrire l'alerte qui aurait prévenu (cible muette **et** cible disparue).

**Prérequis** : M21-E07, M21-E08, M21-E13, M21-E15 ; M15 (Hubble) ; `lab/bin/check 21 35` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : les ServiceMonitors de MédiAgenda vivent dans `mediagenda/deploiement` (composant `components/supervision`, M21-E07) ; les cibles des VMs viennent de la ScrapeConfig `vms` générée depuis NetBox (M21-E08), en HTTPS avec la racine MédiSphère. Une cible disparue n'a pas de ligne rouge dans la page *Targets* : elle n'y est plus du tout. Hubble (`hubble observe --verdict DROPPED`) voit les paquets refusés par une politique Cilium ; il ne voit pas ceux que jette un pare-feu sur une VM.

**Injection** : `lab/bin/break 21 35` (5 variantes).

**Travail demandé**
1. Constate sans rien toucher : la série `up` existe-t-elle encore ? Depuis quand (`up` sur 6 h, `count` par job) ? Que disent *Status → Targets* et *Status → Service Discovery* (étiquettes découvertes, cibles écartées par le relabeling) d'un des deux Prometheus ?
2. Classe la panne : disparue ou en échec. Pour une cible en échec, lis l'erreur exacte (`lastError` de `/api/v1/targets`) et reproduis la collecte **depuis le même endroit que Prometheus** (un pod de débogage dans `supervision`, ou `curl` depuis un nœud). Pour une cible disparue, remonte la découverte jusqu'au maillon qui ne correspond plus.
3. Trouve la cause racine et son origine (commit, objet posé à la main, fichier modifié sur une VM, date). Corrige au bon endroit : MR dans le dépôt concerné, ou retrait de ce qui n'a rien à faire là, puis report dans le code (rôle Ansible, politique de la plateforme).
4. Vérifie le retour : cibles `up == 1` dans les trois espaces de MédiAgenda (et sur toutes les VMs), courbes revenues dans le tableau, trou visible et expliqué.
5. L'alerte `CibleInjoignable` (M21-E15) couvre les VMs en échec : a-t-elle sonné ? Pourquoi (pas) ? Ajoute (MR dans `plateforme/observabilite`) ce qui manquait : une cible **en échec** pour les applications, et une cible **disparue** (`absent()` ou `absent_over_time()` par job attendu), avec `gravite`, `equipe`, `runbook_url` et leurs tests `promtool test rules`. Commence **RB-217** avec la section `## Une cible a disparu ou est muette`.

**Critères de réussite**
- [ ] Toutes les cibles de MédiAgenda (`mediagenda-dev`, `mediagenda-recette`, `mediagenda-prod`) et toutes les cibles node_exporter (`job="vms"` et nœuds Kubernetes) sont `up == 1`.
- [ ] Aucune CiliumNetworkPolicy d'un espace `mediagenda-*` ne refuse le trafic de `supervision` ; le ServiceMonitor de MédiAgenda porte l'étiquette retenue par Prometheus.
- [ ] Des alertes chargées couvrent la cible en échec et la cible disparue, avec leurs tests ; RB-217 contient sa section ; ton journal contient l'erreur exacte et l'origine de la panne.

**Vérification** : `lab/bin/check 21 35`

<details><summary>Indice 1</summary>

`count by (job, namespace) (up)` maintenant et `offset 1h` : un job dont le compte tombe à zéro a **disparu**. *Status → Service Discovery* montre, pour chaque ServiceMonitor, les cibles découvertes et celles qui ont été écartées (« dropped ») avec leurs étiquettes `__meta_*` : c'est là que se voit un port nommé qui ne correspond plus. Un ServiceMonitor que Prometheus ne retient pas n'apparaît même pas dans la liste.
</details>

<details><summary>Indice 2</summary>

Pour une cible en échec : `curl -s http://prometheus.apps.par1.medisphere.internal:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up") | {scrapeUrl, lastError}'`. Une erreur `context deadline exceeded` sans réponse fait penser au réseau (Hubble pour le cluster, `nft list ruleset` et compteurs sur la VM) ; une erreur `x509` au certificat (`openssl s_client -connect <vm>:9100 -CAfile …` depuis un nœud, et la configuration web de node_exporter, M21-E08).
</details>

<details><summary>Indice 3</summary>

`git log -p` du dépôt concerné (ou l'historique des MR) dit ce qui a changé et quand ; `kubectl get ciliumnetworkpolicies -A` liste les politiques, y compris celles que personne n'a versionnées (Argo CD ne les signale que si elles appartiennent à une de ses Applications). Pour l'alerte de disparition : la documentation de Prometheus (*absent*, *absent_over_time*) et les règles `TargetDown` de kube-prometheus-stack montrent deux manières de faire, avec leurs limites.
</details>

**Pour aller plus loin** : la métrique `prometheus_sd_discovered_targets` et la page *Service Discovery* permettent d'alerter sur une **baisse** du nombre de cibles découvertes par job plutôt que sur leur absence totale. Écris la règle, et explique pourquoi elle est plus fragile qu'elle n'en a l'air (déploiements, mise à l'échelle).

---

### M21-E36 — Panne : l'alerte ne part plus  `BF` `★★★`

> **Ticket INC-4836** — *De : Nadia Roussel*
> J'ai lancé l'essai mensuel de la chaîne d'alerte (alerte `EssaiChaineAlerteCritique`, témoins de `wb-pannes`). Elle est bien active dans Prometheus, mais rien n'est arrivé dans la boîte `astreinte@` de Mailpit. Je ne prends pas l'astreinte ce soir sans la preuve que les critiques arrivent.

**Objectifs pédagogiques**
- Suivre une alerte de bout en bout : règle (`pending` puis `firing`), envoi à Alertmanager, regroupement, route, inhibition, silence, récepteur, transport SMTP ; savoir lire l'état d'une alerte dans Alertmanager (`receivers`, `status.inhibitedBy`, `status.silencedBy`).
- Utiliser `amtool` en lecture : `alert query`, `silence query`, `config routes test`, `config routes show` ; lire les métriques d'Alertmanager (`alertmanager_notifications_total`, `alertmanager_notifications_failed_total` et son étiquette `reason`).
- Prévenir : essais de routage en CI, alerte sur les échecs d'envoi, règle de vie des silences.

**Prérequis** : M21-E06, M21-E15, M21-E16, M21-E32 ; `lab/bin/check 21 36` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : la configuration d'Alertmanager vit dans les valeurs de kube-prometheus-stack (`plateforme/observabilite`, `kps/values.yaml`, M21-E06) ; la CI la vérifie (`amtool check-config`) et rejoue les essais de routage `alertmanager/routes-tests.txt` (M21-E07). Mailpit garde tous les messages reçus et a une API de recherche. Le Prometheus et l'Alertmanager **témoins** de `mon01` ne sont pas concernés par cette panne.

**Injection** : `lab/bin/break 21 36` (4 variantes). L'injection déclenche aussi l'essai (ConfigMap `temoin-etat` de `wb-pannes`, clé `essai`).

**Travail demandé**
1. Prouve chaque maillon dans l'ordre, sans rien modifier : l'alerte est-elle `firing` dans Prometheus (pas seulement `pending`) ? Alertmanager la connaît-il, et dans quel état (`active`, `suppressed`) ? Vers quel(s) récepteur(s) ? Un envoi a-t-il été tenté, a-t-il échoué, pour quelle raison ?
2. Reproduis la décision de routage avec la configuration **chargée** (pas celle de ton dépôt local) : `amtool config routes test` avec les étiquettes exactes de l'alerte.
3. Trouve la cause racine et son origine (commit, silence, auteur, date), corrige au bon endroit et vérifie que le courriel `EssaiChaineAlerteCritique` arrive dans `astreinte@`.
4. Ajoute ce qui aurait détecté la panne avant Nadia : un essai de routage de plus dans `alertmanager/routes-tests.txt` pour une alerte critique de la plateforme ; et pour les échecs d'envoi, kube-prometheus-stack fournit déjà `AlertmanagerFailedToSendAlerts` : par quel chemin part-elle quand c'est le courriel qui est cassé ? Relis le chemin de secours de M21-E28 (alertes `Alertmanager…` envoyées aussi à l'Alertmanager témoin) : l'astreinte a-t-elle reçu quelque chose de `mon01`, quand, avec quelle gravité ? Fais en sorte qu'un échec d'envoi des courriels atteigne l'astreinte **en critique**, par ce chemin qui ne dépend pas du courriel du cluster.
5. Complète **RB-218** avec une section `## L'alerte n'arrive pas` : l'arbre de décision maillon par maillon, la commande qui prouve chaque maillon, et la règle de l'équipe sur les silences (durée maximale, commentaire, auteur).

**Critères de réussite**
- [ ] Une alerte critique de la plateforme est routée vers le récepteur de l'astreinte, qui écrit à `astreinte@medisphere.internal` ; le smarthost est `smtp.par1.medisphere.internal:25` partout ; aucune inhibition ne permet à une alerte moins grave d'éteindre une critique ; aucun silence actif de plus de 7 jours sur toute une équipe ou toute une gravité.
- [ ] L'essai en cours est arrivé dans la boîte `astreinte@` ; aucun envoi en échec depuis 15 minutes.
- [ ] Les essais de routage et le chemin de secours des échecs d'envoi sont dans `plateforme/observabilite`, pipeline vert ; RB-218 contient sa section.

**Vérification** : `lab/bin/check 21 36`

<details><summary>Indice 1</summary>

`amtool --alertmanager.url=http://alertmanager.apps.par1.medisphere.internal:9093 alert query alertname=EssaiChaineAlerteCritique --silenced --inhibited` montre si l'alerte est éteinte et par quoi ; l'API (`/api/v2/alerts?filter=alertname="EssaiChaineAlerteCritique"`) donne en plus la liste des `receivers`. `amtool silence query` liste les silences avec leur auteur, leur commentaire et leur fin.
</details>

<details><summary>Indice 2</summary>

`curl -s http://alertmanager.apps.par1.medisphere.internal:9093/api/v2/status | jq -r .config.original > /tmp/am.yml` récupère la configuration réellement chargée ; `amtool config routes test --config.file=/tmp/am.yml --verify.receivers=astreinte-mail gravite=critique equipe=plateforme alertname=EssaiChaineAlerteCritique` la met à l'épreuve. Les journaux d'Alertmanager (`kubectl -n supervision logs alertmanager-kps-0 -c alertmanager`) disent pourquoi un envoi échoue.
</details>

<details><summary>Indice 3</summary>

Une règle d'inhibition éteint les **cibles** quand une **source** est active et que les étiquettes de `equal` sont identiques (ou absentes des deux côtés). Écris sur papier, pour l'essai critique, quelles sources possibles sont actives en même temps qu'elle.
</details>

**Pour aller plus loin** : le témoin de `mon01` reçoit-il les alertes du cluster (M21-E28) ? Si l'Alertmanager du cluster ne sait plus envoyer de courriel, quelle alerte part, par quel chemin, et en combien de temps ? Mesure-le en arrêtant l'envoi de façon contrôlée (smarthost faux en `recette` d'Alertmanager… ou en lisant ta politique d'alerte). Et si c'est le flux `K8S_TRAV` → `mon01`:9093 qui est coupé en même temps ? Un second chemin, **tiré** par le témoin (une sonde de la vue globale, comme pour le Watchdog), ne dépend plus de ce flux.

---

### M21-E37 — Panne : les tableaux de bord sont vides  `BF` `★★`

> **Ticket INC-4837** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection : selon le cas, des panneaux affichent « No data », un tableau n'affiche plus que des erreurs de source de données, ou les vues longues s'arrêtent à deux semaines.)* Lucas a fusionné une MR « de rangement » dans `plateforme/observabilite` tout à l'heure. Claire présente ces tableaux au comité de direction demain matin.

**Objectifs pédagogiques**
- Diagnostiquer un tableau vide par l'**inspecteur de requête** de Grafana : requête envoyée, variables interpolées, source de données, réponse brute.
- Situer la cause : variable de tableau, source de données (UID, URL), règle d'enregistrement, données elles-mêmes.
- Protéger les tableaux *as code* : ce que la CI de M21-E17 contrôle, ce qu'elle ne contrôle pas, et ce qu'on peut y ajouter.

**Prérequis** : M21-E05, M21-E14, M21-E17, M21-E19, M21-E24 ; `lab/bin/check 21 37` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : les tableaux sont des JSON de `plateforme/observabilite/tableaux/`, chargés par le *sidecar* de Grafana depuis des ConfigMaps (M21-E17) ; on ne les modifie pas dans l'interface. La source de données par défaut est provisionnée par les valeurs de kube-prometheus-stack (`grafana.sidecar.datasources`, M21-E24 : Thanos Query). Les règles d'enregistrement sont dans `regles/` (M21-E14).

**Injection** : `lab/bin/break 21 37` (4 variantes).

**Travail demandé**
1. Ouvre un panneau vide, puis **Inspect → Query** : quelle requête est partie, vers quelle source, avec quelles variables, et qu'a-t-elle répondu ? Rejoue-la dans *Explore*, puis directement contre la vue globale.
2. Remonte : la variable a-t-elle des valeurs ? La source existe-t-elle (UID, URL) ? La métrique ou la règle d'enregistrement citée produit-elle des séries ? Sur quelle période ?
3. Trouve la MR en cause, comprends son intention, corrige par une nouvelle MR qui garde ce que la MR voulait de bon (s'il y a quelque chose de bon).
4. Ajoute à la CI de `plateforme/observabilite` un contrôle qui aurait arrêté cette MR : par exemple, chaque règle d'enregistrement citée par un tableau existe dans `regles/`, chaque variable `label_values()` cite une étiquette qui existe, ou aucune source n'est citée par son UID. Explique dans la MR ce que ton contrôle ne voit pas.
5. Complète **RB-217** avec une section `## Un tableau est vide`.

**Critères de réussite**
- [ ] Chaque tableau versionné dans `tableaux/` est présent dans Grafana, ne cite aucune source inconnue, ses variables `label_values()` ont des valeurs et les règles d'enregistrement qu'il cite produisent des données.
- [ ] La source par défaut de Grafana est Thanos Query ; le pipeline de `main` de `plateforme/observabilite` est vert, avec ton nouveau contrôle.
- [ ] RB-217 contient sa section ; ton journal cite la requête envoyée par le panneau et sa réponse.

**Vérification** : `lab/bin/check 21 37`

<details><summary>Indice 1</summary>

L'inspecteur de requête affiche la requête **après** interpolation des variables : une variable vide donne souvent une requête du genre `{namespace=~""}`. Le menu des variables (**Dashboard settings → Variables**) affiche l'aperçu des valeurs de chacune.
</details>

<details><summary>Indice 2</summary>

`curl -s https://grafana.apps.par1.medisphere.internal/api/frontend/settings -H "Authorization: Bearer $(cat ~/.config/workbook/grafana-checks.token)" | jq '.datasources'` liste les sources visibles avec leur UID. Pour les données : *Status → Rules* de la vue globale montre les règles d'enregistrement chargées, et une requête sur plus de 15 jours qui s'arrête net raconte quelque chose sur le chemin qu'elle a pris.
</details>

**Pour aller plus loin** : Grafana 13 sait synchroniser des tableaux depuis Git (*Git Sync*). Compare avec le *sidecar* : qui écrit dans Git, qui relit, que devient une modification faite dans l'interface, et comment la CI s'insère dans chacun des deux modèles.

---

### M21-E38 — Panne : Prometheus déborde  `BF` `★★★`

> **Ticket INC-4838** — *De : Karim Benali*
> La mémoire des deux réplicas de Prometheus grimpe depuis un quart d'heure et le nombre de séries en tête a pris plusieurs dizaines de milliers d'un coup. Grafana commence à ramer. L'équipe MédiAgenda a branché ce matin son « module de rapports » sur l'application de recette de `wb-pannes`. Trouve ce qui gonfle, protège Prometheus tout de suite, puis prépare ce qu'on dit à l'équipe.

**Objectifs pédagogiques**
- Mesurer la cardinalité et le *churn* : `prometheus_tsdb_head_series`, `prometheus_tsdb_head_series_created_total`, *Status → TSDB Status*, `scrape_samples_scraped` et `scrape_series_added` par cible, `count by (__name__)`.
- Arrêter l'hémorragie au bon endroit (relabeling à la collecte, limites par cible et globales) sans perdre ce qui est utile, en comprenant pourquoi `labeldrop` seul est un piège.
- Expliquer à une équipe ce qu'une étiquette coûte, et ce qui ne doit **jamais** être une étiquette (identifiants, chemins bruts, données personnelles).

**Prérequis** : M21-E13, M21-E14, M21-E30 ; `lab/bin/check 21 38` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : les cibles de `wb-pannes` sont collectées toutes les 15 secondes. Les séries déjà ingérées ne quittent la **tête** qu'à la compaction suivante (blocs de 2 h) : la mémoire ne redescend pas tout de suite, c'est normal. Elles restent ensuite dans les blocs, puis dans le compartiment Thanos, jusqu'à la fin de leur rétention : **ne supprime rien** (gestes interdits du palier). L'API d'administration est désactivée dans le cluster (M21-E29).

**Injection** : `lab/bin/break 21 38` (3 variantes). L'injection attend que la tête ait grossi (jusqu'à 10 min).

**Travail demandé**
1. Quantifie : séries en tête maintenant et il y a 1 h, séries créées par minute, mémoire des pods Prometheus. Trouve la métrique et l'étiquette responsables, et la cible qui les expose (*TSDB Status*, `topk(10, count by (__name__)({__name__=~".+"}))` sur une période courte, `scrape_series_added`).
2. Évalue la gravité : combien de séries au bout d'une journée à ce rythme ? Que coûte-t-elle en mémoire par réplica (M21-E30) ? Y a-t-il en plus un problème de **données** (lis les valeurs de l'étiquette) ?
3. Protège Prometheus **tout de suite**, à l'endroit le plus proche de la source : le ServiceMonitor de l'application (`metricRelabelings`), plus une limite par cible (`sampleLimit`, `labelLimit` ou `labelValueLengthLimit`) choisie à partir de ce que la cible expose normalement. Vérifie l'effet par `scrape_samples_post_metric_relabeling`.
4. Rédige la réponse à l'équipe MédiAgenda (dans ton journal) : ce qui s'est passé, le coût, ce qu'il faut exposer à la place (un compteur agrégé, un histogramme, des journaux ou des traces pour l'identifiant), et, si la variante l'exige, ce qu'en dit Sophie Laurent.
5. L'alerte de capacité de M21-E30 (`PrometheusSeriesProchesDuBudget`) a-t-elle sonné, et au bout de combien de temps ? Ajoute une alerte sur le **rythme de création** des séries, qui aurait prévenu en quelques minutes. Complète **RB-219** avec une section `## Cardinalité` (mesurer, contenir, prévenir) et vérifie que la plateforme a une limite globale (`enforcedSampleLimit` ou `enforcedLabelLimit`).

**Critères de réussite**
- [ ] La cible témoin est collectée (deux pods `up`) avec moins de 1 000 échantillons par collecte après relabeling, et son ServiceMonitor porte une limite.
- [ ] Prometheus a une limite globale par cible, une alerte sur `prometheus_tsdb_head_series` et une sur le rythme de création des séries ; aucune série n'a été supprimée.
- [ ] RB-219 contient sa section ; ton journal contient les chiffres (avant, pic, après) et la réponse à l'équipe.

**Vérification** : `lab/bin/check 21 38`

<details><summary>Indice 1</summary>

`sort_desc(scrape_series_added)` et `sort_desc(scrape_samples_scraped)` désignent la cible coupable en une requête. *TSDB Status* (sur un des deux Prometheus, par `port-forward`) donne les étiquettes au plus grand nombre de valeurs et les métriques au plus grand nombre de séries **de la tête**.
</details>

<details><summary>Indice 2</summary>

Retirer l'étiquette (`labeldrop`) fait de milliers de séries **une seule**, alimentée par des milliers d'échantillons différents au même instant : Prometheus n'en garde qu'un, rejette les autres (échantillons dupliqués, compteur `prometheus_target_scrapes_sample_duplicate_timestamp_total`, avertissement dans son journal) et la valeur gardée ne veut plus rien dire — la cible reste pourtant `up`. Le bon geste dépend de ce que la métrique vaut sans l'étiquette : la garder agrégée côté application, ou la jeter (`action: drop` sur `__name__`). Lis *metric_relabel_configs* dans la documentation de Prometheus et `metricRelabelings` dans l'API de prometheus-operator.
</details>

<details><summary>Indice 3</summary>

Une limite trop basse transforme la cible en `up == 0` (« sample limit exceeded ») : plus de données du tout. Choisis-la au-dessus de ce que la cible expose **après** ton relabeling, avec de la marge.
</details>

**Pour aller plus loin** : prometheus-operator propose plusieurs garde-fous globaux (`enforcedSampleLimit`, `enforcedLabelLimit`, `enforcedLabelValueLengthLimit`, `enforcedTargetLimit`, `enforcedBodySizeLimit` : vérifie les noms dans la référence de l'API de ta version) qui se traduisent en limites de collecte de Prometheus. Pour chacun, dis ce qui se passe quand il se déclenche (que voit l'équipe fautive, que voit l'astreinte ?), et lequel aurait arrêté cette panne-ci : attention, aucune collecte ne dépassait quelques milliers d'échantillons.

---

### M21-E39 — Panne : les données anciennes ont disparu  `BF` `★★★`

> **Ticket INC-4839** — *De : Claire Morel ou Karim Benali*
> *(Le détail s'affiche à l'injection : selon le cas, les vues longues de Grafana sont vides ou s'arrêtent après quelques jours, avec parfois un avertissement de réponse partielle ; ou les sidecars Thanos n'envoient plus rien vers le compartiment.)* On a payé un stockage objet pour garder deux ans : qu'est-ce qui se passe, et est-ce qu'on a perdu quelque chose ?

**Objectifs pédagogiques**
- Situer chaque morceau de l'historique : tête et blocs locaux (sidecars), blocs du compartiment (Store Gateway), blocs compactés et sous-échantillonnés (Compactor), et savoir qui sert quelle période (`/api/v1/stores` : `minTime`, `maxTime`, `labelSets`).
- Lire un échec d'accès au stockage objet (journaux du Store, du sidecar ; `thanos_objstore_bucket_operation_failures_total`) et le vérifier hors de Thanos, en lecture (`s3-thanos.env`).
- Répondre précisément à « a-t-on perdu des données ? » par l'inventaire du compartiment, **sans rien y écrire**.

**Prérequis** : M21-E24, M21-E25, M21-E30 ; `lab/bin/check 21 39` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : Thanos Query (10.10.41.60) agrège les deux sidecars et le Store Gateway ; le Compactor est seul à écrire dans le compartiment en dehors des sidecars (M21-E25). Le Secret `thanos-objstore` est créé hors Git par `secrets-k8s.sh` (composant `thanos`) à partir d'Ansible Vault `critique`. Les données locales de chaque Prometheus couvrent 15 jours : **si ton lab a moins de 15 jours d'historique, une coupure du Store ne se voit pas sur les courbes** ; cherche les autres signaux (page *Stores* de Thanos Query, avertissements de réponse partielle, journaux).

**Injection** : `lab/bin/break 21 39` (3 variantes).

**Travail demandé**
1. Inventorie ce que la vue globale sait servir : `/api/v1/stores` (composants, erreurs, fenêtre de temps de chacun), et, en lecture seule, ce que contient le compartiment (`thanos tools bucket inspect` avec la configuration de `s3-thanos.env`, ou la page *bucket web* de M21-E25). Le dernier bloc envoyé date de quand ?
2. Trouve le composant en cause et lis son erreur (journaux, métriques `thanos_*`), puis la cause racine et son origine (MR, Secret, auteur, date).
3. Corrige au bon endroit : MR dans `plateforme/observabilite`, ou Secret recréé **depuis la source de vérité** par `secrets-k8s.sh` (jamais depuis une vieille copie), puis redémarrage contrôlé de ce qui doit relire sa configuration.
4. Réponds à Claire par écrit (journal) : les données ont-elles été perdues, lesquelles, pourquoi (ou pourquoi pas) ? Que se serait-il passé si la panne avait duré 16 jours ?
5. Les alertes de M21-E25 (`ThanosSidecarEnvoisArretes`, `ThanosQueryStoreManquant`…) ont-elles sonné ? Pour chacune, explique pourquoi (ou pourquoi pas) en relisant son expression face à **ta** variante, puis complète-les (MR, tests) pour que la panne que tu viens de vivre soit détectée. Complète **RB-219** avec une section `## Historique long (Thanos)`.

**Critères de réussite**
- [ ] Thanos Query voit deux sidecars et au moins un Store Gateway sains, sans aucune erreur ; le Store ne masque pas l'historique (pas de `--min-time` de moins de 30 jours) ; ses pods sont prêts.
- [ ] Les sidecars ont leur stockage objet, l'expéditeur de blocs tourne et n'a pas échoué depuis 6 h.
- [ ] Les alertes complétées sont chargées avec leurs tests, dont une qui détecte un sidecar sans expéditeur de blocs ; RB-219 contient sa section ; ta réponse à Claire est dans le journal ; **aucun objet du compartiment n'a été supprimé ni modifié**.

**Vérification** : `lab/bin/check 21 39`

<details><summary>Indice 1</summary>

`curl -s http://prometheus.apps.par1.medisphere.internal:9090/api/v1/stores | jq '.data | map_values(map({name, lastError, minTime: (.minTime/1000|todate), maxTime: (.maxTime/1000|todate)}))'` : un composant absent, en erreur, ou dont la fenêtre ne commence que très récemment, dit déjà presque tout.
</details>

<details><summary>Indice 2</summary>

`kubectl -n supervision logs <pod du Store>` et `kubectl -n supervision logs prometheus-kps-0 -c thanos-sidecar` ; la ligne de commande réelle du conteneur (`kubectl get pod … -o jsonpath='{.spec.containers[*].args}'`) et celle du sidecar (générée par l'opérateur à partir de l'objet Prometheus) disent ce que chacun a reçu.
</details>

<details><summary>Indice 3</summary>

`thanos tools bucket inspect --objstore.config-file=…` ne fait que lire. Prépare son fichier de configuration à partir de `~/.config/workbook/s3-thanos.env` dans un fichier 600 que tu effaces ensuite, ou passe le contenu par `--objstore.config` lu depuis une variable. Ne lance aucune autre sous-commande de `thanos tools bucket`.
</details>

**Pour aller plus loin** : le Store Gateway peut être partagé par plages de temps (`--min-time`, `--max-time`) ou par empreinte (*sharding* par relabeling des blocs). Dans quel cas le ferais-tu à MédiSphère, et quel contrôle garantirait qu'aucune période n'est servie par personne ?

---

### M21-E40 — Panne : l'alerte sonne sans arrêt  `BF` `★★`

> **Ticket INC-4840** — *De : Nadia Roussel*
> Ma boîte `astreinte@` se remplit de courriels `TemoinFileAttenteHaute` (service de rappels témoin, `wb-pannes`) : des dizaines dans l'heure, pour ce qui est visiblement le même problème. À ce rythme, je vais finir par ne plus les lire, et c'est comme ça qu'on rate la vraie. Je veux **un** courriel utile par problème.

**Objectifs pédagogiques**
- Relier le nombre de notifications aux réglages qui le produisent : `for` et `keep_firing_for` côté règle, `group_by`, `group_wait`, `group_interval`, `repeat_interval` côté route, et `send_resolved`.
- Distinguer une alerte qui **bat** (condition qui oscille autour du seuil), une alerte **répétée** (relance trop fréquente) et une alerte **éclatée** (regroupement trop fin).
- Mesurer le bruit (`ALERTS`, `alertmanager_notifications_total`, Mailpit) et le réduire sans rendre l'alerte aveugle.

**Prérequis** : M21-E15, M21-E16, M21-E32 ; `lab/bin/check 21 40` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : la règle `TemoinFileAttenteHaute` fait partie des témoins (PrometheusRule `temoin-metriques` de `wb-pannes`, hors Git : en vrai, elle serait dans le dépôt de l'équipe) ; la route de l'astreinte est dans les valeurs de kube-prometheus-stack. La file témoin a plusieurs comportements possibles ; le ticket ne dit pas lequel.

**Injection** : `lab/bin/break 21 40` (3 variantes).

**Travail demandé**
1. Mesure le bruit : courriels reçus par heure (Mailpit), changements d'état de l'alerte (`changes(ALERTS{alertname="TemoinFileAttenteHaute"}[1h])`, ou `ALERTS` en graphe), notifications envoyées par récepteur. Regarde aussi la grandeur surveillée (`temoin_file_attente`) : oscille-t-elle, reste-t-elle haute ?
2. Classe le bruit (battement, répétition, éclatement) et trouve le réglage en cause et son origine.
3. Corrige au bon endroit, en gardant l'alerte capable de te réveiller pour un vrai problème : quel `for` pour une file qui déborde, quelle relance pour un incident connu, quel regroupement pour un service à plusieurs pods ?
4. Ajoute un essai de routage (`routes-tests.txt`) ou un test de règle (`promtool test rules`) qui aurait refusé la modification.
5. Complète **RB-218** avec une section `## Trop de courriels` : comment reconnaître chaque type de bruit, et les valeurs de référence de MédiSphère (renvoie à la politique d'alerte de M21-E32).

**Critères de réussite**
- [ ] Aucune route ne relance plus d'une fois par heure ni ne regroupe par pod (ou pas du tout) ; la règle témoin attend au moins une minute avant de sonner.
- [ ] Au plus 4 courriels `TemoinFileAttenteHaute` reçus par `astreinte@` dans les 30 dernières minutes.
- [ ] RB-218 contient sa section ; le test qui protège le réglage est dans le pipeline.

**Vérification** : `lab/bin/check 21 40`

<details><summary>Indice 1</summary>

`ALERTS{alertname="TemoinFileAttenteHaute"}` en graphe sur 1 h : des créneaux qui s'allument et s'éteignent sans cesse ne racontent pas la même histoire qu'une ligne continue, ni qu'une dizaine de lignes parallèles. Compare avec les sujets des courriels (nombre d'alertes par courriel, `[FIRING:N]`).
</details>

<details><summary>Indice 2</summary>

`group_interval` gouverne l'envoi des **changements** d'un groupe ; `repeat_interval` la relance d'un groupe **inchangé** ; une relance ne peut pas partir plus souvent que `group_interval`. La documentation de configuration d'Alertmanager (*route*) et celle des règles d'alerte (*for*, *keep_firing_for*) suffisent.
</details>

**Pour aller plus loin** : ajoute à la politique d'alerte une revue mensuelle du bruit : une requête qui classe les alertes par nombre de notifications sur 30 jours (`alertmanager_notifications_total` ne suffit pas : pourquoi ?) et ce que l'équipe fait des cinq premières.

---

### M21-E41 — Panne : une règle ne se charge pas  `BF` `★★`

> **Ticket INC-4841** — *De : Julien Petit*
> Lucas nous a ajouté hier une alerte d'équipe, `MediagendaValkeyMemoireHaute` (MR fusionnée dans `mediagenda/deploiement`, pipeline vert). *(La suite du ticket s'affiche à l'injection.)* On a eu une éviction de Valkey cette nuit sans alerte. Je veux cette règle chargée en dev et en recette, et une protection pour que ça ne se reproduise pas.

**Objectifs pédagogiques**
- Suivre une PrometheusRule de Git jusqu'à l'évaluation : synchronisation Argo CD, admission (webhook de prometheus-operator), sélection par l'opérateur (`ruleSelector`, `ruleNamespaceSelector`), ConfigMap de règles générée, rechargement de Prometheus, groupe évalué.
- Lire les signaux de chaque étage : état de synchronisation et message d'Argo CD, refus du webhook, `prometheus_rule_group_last_evaluation_timestamp_seconds`, *Status → Rules*.
- Mettre la validation des règles là où l'équipe les écrit.

**Prérequis** : M21-E07, M21-E15, M21-E29 ; M20 (Argo CD) ; `lab/bin/check 21 41` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : les règles d'équipe vivent dans le dépôt de l'équipe, avec ses ServiceMonitors (composant `components/supervision`) ; leur pipeline ne fait que `kustomize build` et `kubeconform` (M20-E30). Les règles de la plateforme, elles, passent par `promtool` dans la CI de `plateforme/observabilite`. Les deux finissent dans le même Prometheus si les sélecteurs les retiennent.

**Injection** : `lab/bin/break 21 41` (3 variantes).

**Travail demandé**
1. Suis la règle étage par étage et note ce que chacun dit : l'objet est-il dans le cluster ? Argo CD a-t-il synchronisé, avec quel message ? L'opérateur l'a-t-il retenue (le groupe est-il dans *Status → Rules*) ? Pourquoi ?
2. Trouve la cause racine et corrige-la au bon endroit (MR dans `mediagenda/deploiement`, ou objet de la plateforme hors du dépôt de l'équipe : à qui revient-il ?).
3. Vérifie que la règle est **évaluée** (pas seulement présente) dans les deux environnements.
4. Protège : ajoute au pipeline de `mediagenda/deploiement` une validation des PrometheusRule par `promtool` (extraction du `spec` de chaque objet rendu par `kustomize build`) et un contrôle de l'étiquette de sélection. Fais relire la MR par Julien (simulé).
5. Complète **RB-217** avec une section `## Une règle ne se charge pas`.

**Critères de réussite**
- [ ] Toutes les PrometheusRule du cluster sont chargées par Prometheus (leurs groupes sont visibles dans la vue globale), dont `mediagenda-valkey` en dev et en recette.
- [ ] Les Applications `mediagenda-dev` et `mediagenda-recette` sont Synced et Healthy, dernière synchronisation réussie.
- [ ] Le pipeline de `mediagenda/deploiement` valide les règles avec `promtool` ; RB-217 contient sa section.

**Vérification** : `lab/bin/check 21 41`

<details><summary>Indice 1</summary>

`kubectl -n mediagenda-dev get prometheusrules --show-labels`, puis l'objet Prometheus : `kubectl -n supervision get prometheus kps -o jsonpath='{.spec.ruleSelector}{"\n"}{.spec.ruleNamespaceSelector}'` et les étiquettes de l'espace (`kubectl get ns mediagenda-dev --show-labels`). L'opérateur range les règles retenues dans des ConfigMaps `prometheus-kps-rulefiles-*` de `supervision`.
</details>

<details><summary>Indice 2</summary>

`argocd app get mediagenda-dev` (ou la page de l'Application) affiche le message de la dernière synchronisation, ressource par ressource. Un refus d'admission y apparaît tel que l'API l'a renvoyé. Reproduis-le hors Argo CD : `kustomize build overlays/dev | kubectl apply --dry-run=server -f -`.
</details>

**Pour aller plus loin** : les PrometheusRule d'équipe pourraient être validées à l'admission par une politique de la plateforme (ValidatingAdmissionPolicy du M14 : étiquette de sélection obligatoire sur toute PrometheusRule des espaces `mediagenda-*`). Écris-la, et compare avec le contrôle en CI : qui voit l'erreur, quand, et que se passe-t-il pour un `kubectl apply` à la main ?

---

### M21-E42 — Panne : la supervision hors cluster est aveugle  `BF` `★★★`

> **Ticket INC-4842** — *De : Nadia Roussel*
> *(Le détail s'affiche à l'injection : selon le cas, le témoin de `mon01` annonce des pannes que personne ne voit, a perdu des sondes sans rien dire, ou n'a pas transmis l'essai mensuel.)* Le témoin est ce qui doit me prévenir quand le cluster entier tombe : s'il est faux, je n'ai plus rien. Lucas est intervenu sur `mon01` cette semaine.

**Objectifs pédagogiques**
- Diagnostiquer une supervision **hors cluster**, sur une VM : unités systemd, fichiers de configuration, rechargement à chaud (`SIGHUP`, `/-/reload`), pages et API locales du Prometheus, de l'Alertmanager et du blackbox_exporter témoins.
- Déboguer une sonde : `/probe?target=…&module=…&debug=true` de blackbox_exporter, page `/config`, résolution DNS et famille d'adresses.
- Comprendre ce qui surveille le témoin lui-même, et le combler.

**Prérequis** : M21-E11, M21-E12, M21-E28 ; `lab/bin/check 21 42` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : `mon01` (10.10.20.19) est configuré par le rôle Ansible `supervision_temoin` (M21-E11) : configuration dans `/etc/prometheus/`, données dans `/var/lib/prometheus/`, fichiers de cibles relus à chaud (`file_sd_configs`), blackbox en local (127.0.0.1:9115). Le témoin joint la vue globale et l'Alertmanager du cluster (10.10.41.60-61) et Mailpit sur la même VM (`smtp.par1.medisphere.internal:25`). Le prochain passage d'Ansible remettrait les fichiers en ordre : ne compte pas dessus pour réparer, compte dessus pour **prouver** l'écart (`--check --diff`).

**Injection** : `lab/bin/break 21 42` (4 variantes).

**Travail demandé**
1. Sur `mon01`, sans rien modifier : état des unités (`systemctl status`), configuration réellement chargée (`/api/v1/status/config` du Prometheus témoin, `/config` de blackbox, `/api/v2/status` de l'Alertmanager témoin), cibles (`/api/v1/targets`), journaux (`journalctl -u … --since -1h`).
2. Rejoue une sonde à la main avec `debug=true` et compare avec ce que tu obtiens depuis `adm01` (`curl -v`).
3. Prouve l'écart avec le code : `ansible-playbook playbooks/supervision-temoin.yml --limit mon01 --check --diff` (par le pipeline protégé, ou en vérification seule depuis `adm01` selon ADR-0040). Trouve ce qui a changé, quand, et pourquoi c'était une mauvaise idée.
4. Corrige par le code (rejeu du rôle, ou MR si le rôle doit changer), puis vérifie que le témoin voit juste : toutes les sondes en succès, vue globale et Alertmanager du cluster joints, essai de l'Alertmanager témoin reçu.
5. Ajoute au témoin l'alerte qui lui manquait (par exemple : nombre de cibles d'un job en baisse, aucun envoi réussi depuis N heures, échecs de rechargement `prometheus_config_last_reload_successful == 0`) et dis **qui** la reçoit si c'est le témoin qui est malade. Complète **RB-218** avec une section `## Le témoin de mon01 se trompe`.

**Critères de réussite**
- [ ] Sur `mon01`, Prometheus, Alertmanager et blackbox_exporter tournent ; blackbox sonde en IPv4 ; le témoin joint 10.10.41.60 et 10.10.41.61 ; chaque fichier de cibles contient des cibles, toutes `up`, toutes les sondes en succès ; l'Alertmanager témoin envoie par `smtp.par1.medisphere.internal:25`.
- [ ] Aucune règle nftables locale ne coupe la sortie de `mon01` vers la supervision du cluster ; le rôle rejoué en `--check` ne trouve plus d'écart.
- [ ] L'alerte ajoutée est chargée sur le témoin ; RB-218 contient sa section.

**Vérification** : `lab/bin/check 21 42`

<details><summary>Indice 1</summary>

`curl -s 'http://127.0.0.1:9115/probe?target=https://grafana.apps.par1.medisphere.internal/api/health&module=https_2xx&debug=true'` sur `mon01` raconte la sonde pas à pas : résolution, connexion, TLS, code HTTP. `curl -s http://127.0.0.1:9115/config` affiche la configuration chargée, valeurs par défaut comprises.
</details>

<details><summary>Indice 2</summary>

Un fichier de cibles vide ou commenté est un fichier **valide** : Prometheus n'a rien à redire, il n'a simplement plus rien à sonder. Compare le nombre de cibles par job avec le code (`host_vars/mon01/supervision_temoin.yml`). Pour le réseau : `sudo nft list ruleset` sur `mon01`, et les compteurs des règles.
</details>

<details><summary>Indice 3</summary>

L'API v2 de l'Alertmanager témoin (`/api/v2/alerts`) montre l'alerte d'essai ; ses métriques (`/metrics`, `alertmanager_notifications_failed_total` et l'étiquette `reason`) et son journal disent pourquoi l'envoi échoue.
</details>

**Pour aller plus loin** : qui surveille le témoin ? Le cluster le sonde (M21-E28), mais si `mon01` dit « tout va bien » alors qu'il est aveugle, rien ne le détecte. Propose un contrôle croisé (le cluster compte les sondes du témoin par fédération ; une sonde « canari » volontairement en échec qui doit **toujours** être rouge) et écris-en une.

---

### M21-E43 — Astreinte : une nuit agitée  `BF` `★★★★`

> **Ticket INC-4843** — *De : Nadia Roussel (responsable astreinte)* — priorité P2
> Tu es d'astreinte. Mardi, 3 h 40 : plusieurs remontées sur la supervision (le détail s'affiche à l'injection). La supervision, c'est ce qui me réveille quand les centres de santé ne peuvent plus prendre rendez-vous : à 8 h, elle doit être fiable de bout en bout. Tiens-moi informée toutes les 30 minutes, puis rédige le post-mortem avec le modèle de l'équipe.

**Objectifs pédagogiques**
- Gérer un incident à causes multiples **sur l'outil de diagnostic lui-même** : savoir de quel instrument on peut encore se fier, et en changer (vue globale, un Prometheus en direct, le témoin, Mailpit, Hubble, `kubectl`).
- Prioriser par risque : d'abord ce qui empêcherait d'apprendre une vraie panne (alertes muettes, témoin aveugle), puis ce qui menace la supervision (débordement), puis ce qui gêne (tableaux, historique).
- Communiquer pendant l'incident et rédiger un post-mortem sans recherche de coupable, centré sur la **détection**.

**Prérequis** : M21-E35 à M21-E42 (au moins une variante de chacun).
**Durée indicative** : 2 h de rétablissement + 45 min de post-mortem.

**Contexte technique** : le script tire **trois** pannes distinctes parmi celles de M21-E35 à M21-E42 (jamais E36 avec E40, jamais E38 avec E39), avec une variante au hasard pour chacune, et les injecte ensemble ; les pannes qui passent par une MR attendent le pipeline et Argo CD : l'injection prend **15 à 45 minutes**. Les symptômes se recouvrent (une alerte muette cache une cible disparue ; un témoin qui crie au loup cache une vraie coupure). `--variante N` (1 à 44) force le trio, pas les variantes. `--annuler` retire les trois. Modèle de post-mortem : [`modules/00-lab/ressources/M00-E46/modele-post-mortem.md`](../../00-lab/ressources/M00-E46/modele-post-mortem.md).

**Injection** : `lab/bin/break 21 43`

**Travail demandé**
1. **Triage (15 min max)** : liste les symptômes, leur impact (qui ne serait plus prévenu de quoi ?), et vérifie tes instruments : la vue globale répond-elle, l'Alertmanager du cluster envoie-t-il (essai par `amtool alert add` vers `plateforme@`), le témoin voit-il juste ? Envoie la première communication.
2. **Diagnostic** : traite les pannes dans un ordre que tu justifies ; tiens ton journal horodaté ; garde les sorties qui prouvent chaque cause.
3. **Rétablissement** : corrige chaque cause racine par le chemin normal (MR, Secret depuis la source, rôle Ansible) ; après chaque correction, relance **tous** tes tests de départ.
4. **Clôture** : communication de fin d'incident, `--annuler` pour clore, puis post-mortem dans `docs/kubernetes/post-mortems/AAAA-MM-JJ-INC-4843.md`, publié par MR, avec une section **Détection** : pour chaque cause, ce qui aurait dû la signaler et pourquoi ça n'a pas marché.

**Critères de réussite**
- [ ] Toutes les vérifications de M21-E35 à M21-E42 sont vertes (le contrôle les rejoue toutes) et aucune panne n'est encore marquée active.
- [ ] Le post-mortem existe, contient une chronologie horodatée, les trois causes racines, des extraits de diagnostic, l'analyse de la détection, des actions avec responsable et échéance, et aucun secret (clé S3, mot de passe SMTP, jeton).
- [ ] Le journal contient au moins quatre communications d'incident espacées d'environ 30 minutes.

**Vérification** : `lab/bin/check 21 43`

<details><summary>Indice 1</summary>

Ordre de confiance des instruments : `kubectl` et les API brutes (`/api/v1/targets`, `/api/v2/alerts`, `/api/v1/stores`) avant Grafana ; un Prometheus en direct (`port-forward`) avant la vue globale si elle se contredit ; Mailpit pour savoir ce qui est **réellement** parti. Les contrôles `lab/bin/check 21 35` à `21 42` sont des sondes ciblées : lance-les pendant le triage.
</details>

<details><summary>Indice 2</summary>

Une alerte muette est la pire des trois : tant qu'elle l'est, les autres pannes (et toute vraie panne du lab) passent inaperçues. Rétablis d'abord le chemin des alertes, puis vérifie-le par un essai, avant de chercher le reste.
</details>

**Pour aller plus loin** : fais-toi injecter une astreinte par quelqu'un d'autre et chronomètre le temps jusqu'au **premier diagnostic juste** ; compare avec ton astreinte du M14 (M14-E43), qui n'avait pas de supervision.

---

### M21-E44 — Sous le capot : WAL, blocs et chunks  `LAB` `★★★★`

> **Ticket PLAT-2244** — *De : Karim Benali*
> Pendant les pannes, on a parlé de « tête », de « compaction », de « blocs de 2 h » et de « tombstones » comme de choses magiques. Je veux que tu ouvres une base Prometheus et que tu **montres** ce qu'il y a dedans : le journal d'écriture, la tête, un bloc, son index, ses chunks, comment ils se compactent et ce que coûte une série. Sur le témoin de `mon01`, jamais sur le cluster. Compte rendu pour les prochains arrivants.

**Objectifs pédagogiques**
- Décrire le chemin d'un échantillon : collecte → WAL (segments, *checkpoint*) → tête (*head block*, chunks en mémoire puis `chunks_head/` projetés en mémoire) → bloc persistant de 2 h (`meta.json`, `index`, `chunks/`, `tombstones`) → compaction en blocs plus longs → rétention.
- Utiliser `promtool tsdb list`, `analyze` (et `--extended`), `dump` sur un **instantané** pris par l'API d'administration, et relier leurs chiffres aux métriques `prometheus_tsdb_*`.
- Comprendre ce que change Thanos (blocs de 2 h envoyés tels quels, compaction déléguée au Compactor) et ce que coûtent une série, un chunk, un échantillon.

**Prérequis** : M21-E11 (rôle `supervision_temoin`), M21-E25, M21-E30, M21-E38 ; M04 (pipeline protégé du dépôt Ansible).
**Durée indicative** : 3 h.

**Contexte technique**
- Prometheus témoin **3.13 LTS** sur `mon01` : données dans `/var/lib/prometheus/data`, `promtool` de la même version dans `/usr/local/bin/` ; rétention 30 jours ; mémoire bornée à 600 Mo par l'unité systemd.
- L'**API d'administration** (`--web.enable-admin-api`) n'est activée **que sur `mon01`**, et seulement le temps de cet exercice : elle permet aussi de supprimer des séries (`delete_series`) et de nettoyer les *tombstones*. Elle est jointe depuis MGMT et le VLAN 40 (fédération) ; personne d'autre ne joint le port 9090 de `mon01` (pare-feu, M21-E11).
- Travaille sur `adm01` dans `~/m21/e44/` (700). Un instantané est fait de **liens physiques** vers les blocs : il ne coûte presque rien au moment où il est pris, puis de plus en plus à mesure que la compaction et la rétention suppriment les originaux. Il ne doit pas rester sur `mon01`.

> ⚠️ **Attention** : avec l'API d'administration ouverte, une seule requête `POST /api/v1/admin/tsdb/delete_series` efface des données sans retour possible. N'appelle **que** `snapshot`. Referme l'API à la fin de l'exercice (le contrôle le vérifie). Retour arrière : la variable du rôle remise à `false` et le rôle rejoué ; rien d'autre n'est modifié.

**Travail demandé**
1. **Ouvrir l'API, par le code.** Ajoute au rôle `supervision_temoin` une variable `supervision_temoin_api_admin` (défaut `false`) qui pose `--web.enable-admin-api` dans l'unité de Prometheus ; MR, pipeline, puis passage à `true` pour `mon01` et rejeu du rôle. Vérifie avec `/api/v1/status/flags`.
2. **La base vivante, en lecture.** Sur `mon01` : `sudo ls -la /var/lib/prometheus/data`, `wal/` (segments, `checkpoint.NNNNNNNN`), `chunks_head/`, les dossiers de blocs (identifiants ULID), `lock`, `queries.active`. Relève depuis `adm01` : `prometheus_tsdb_head_series`, `prometheus_tsdb_head_chunks`, `prometheus_tsdb_head_min_time` et `max_time`, `prometheus_tsdb_wal_segment_current`, `prometheus_tsdb_blocks_loaded`, `prometheus_tsdb_compactions_total`, `prometheus_tsdb_storage_blocks_bytes`.
3. **L'instantané.** `curl -XPOST http://mon01.par1.medisphere.internal:9090/api/v1/admin/tsdb/snapshot` ; relève son nom ; mesure la place qu'il prend vraiment (`du -sh` du dossier et de l'ensemble, `stat` d'un fichier `index` : nombre de liens). Copie-le vers `~/m21/e44/instantane/` (`ssh mon01 'sudo tar -C … -cf - .' | tar -C … -xf -`), puis **supprime-le de `mon01`** (seulement le sous-dossier de `snapshots/` que tu as créé).
4. **Les blocs.** Télécharge `promtool` de la **même version** que le témoin (archive Prometheus 3.13.x, empreinte vérifiée) dans `~/m21/e44/outils/`. `promtool tsdb list -r ~/m21/e44/instantane` ; lis le `meta.json` du bloc le plus ancien et du plus récent (`minTime`, `maxTime`, `stats`, `compaction.level`, `compaction.sources`) ; explique les durées que tu observes et le niveau de compaction.
5. **L'analyse.** `promtool tsdb analyze` sur le bloc le plus gros puis avec `--extended` : séries, étiquettes les plus coûteuses, *churn*, échantillons par chunk. `promtool tsdb dump --match='probe_success' --min-time=… --max-time=…` sur une heure (crée un dossier `wal/` vide dans ta copie si l'outil le réclame) ; compte les échantillons et retrouve l'intervalle de collecte.
6. **Refermer.** Variable remise à `false`, rôle rejoué, `/api/v1/status/flags` vérifié. Supprime ta copie si tu n'en as plus besoin.
7. **Compte rendu** (squelette fourni : [`ressources/E44-tsdb/compte-rendu-squelette.md`](../ressources/E44-tsdb/compte-rendu-squelette.md)) : `docs/observabilite/metriques/analyses/tsdb-sous-le-capot.md` avec `## Le WAL et la tête`, `## Les blocs`, `## La compaction et la rétention`, `## Analyse et cardinalité`, `## Réponses aux questions` ; chiffres relevés (identifiants de blocs, nombre de séries, tailles) ; aucun secret. Publie-le par MR.

**Questions d'analyse** (à traiter dans le compte rendu)
1. À quoi sert le WAL, que se passe-t-il au redémarrage (*replay*), et à quoi sert le *checkpoint* ? Pourquoi un redémarrage de Prometheus peut-il prendre plusieurs minutes sur une grosse tête ?
2. Qu'est-ce que `chunks_head/`, et qu'a-t-il changé pour la mémoire et le temps de redémarrage depuis Prometheus 2.19 ?
3. Pourquoi les blocs sont-ils **immuables** ? Comment une suppression de séries est-elle alors possible (tombstones), et quand l'espace est-il réellement libéré ?
4. Comment la rétention par durée et par taille (`retention.size`) décide-t-elle quoi supprimer ? Pourquoi la rétention ne descend-elle jamais en dessous d'un bloc ?
5. Avec un sidecar Thanos qui envoie les blocs, l'opérateur doit empêcher Prometheus de compacter un bloc avant son envoi. Il a longtemps fixé la durée des blocs à 2 h (`min-block-duration` = `max-block-duration`) ; avec Prometheus ≥ 3.9 et Thanos ≥ 0.42, l'opérateur 0.94 garde la compaction locale et la **retarde** (M21-E24 : `--storage.tsdb.delay-compact-file.path`). Pourquoi faut-il l'une ou l'autre précaution ? Qu'est-ce qui est envoyé au compartiment dans chaque cas, qui compacte le compartiment, et où ?
6. Que mesure « échantillons par chunk » de `analyze --extended`, et pourquoi un chunk se ferme-t-il vers 120 échantillons pour une série collectée régulièrement ?
7. D'après tes chiffres, combien coûte une série en mémoire et sur disque sur le témoin ? Rapproche-le du débordement de M21-E38.
8. Pourquoi faut-il travailler sur un instantané (ou une copie de bloc) et jamais sur le répertoire de données d'un Prometheus en marche ?

**Critères de réussite**
- [ ] Le compte rendu existe, est commité, contient les sections demandées, cite WAL, *checkpoint*, `chunks_head`, `meta.json`, ULID, compaction et `promtool tsdb`, avec un identifiant de bloc réel et des nombres de séries relevés.
- [ ] Les 8 questions sont traitées ; aucun secret dans le compte rendu.
- [ ] Plus aucun instantané dans `/var/lib/prometheus/data/snapshots/` de `mon01` ; l'API d'administration du témoin est refermée ; aucune n'est ouverte dans le cluster.

**Vérification** : `lab/bin/check 21 44`

<details><summary>Indice 1</summary>

La documentation *Storage* de Prometheus (format sur disque, compaction, rétention, instantanés) et les articles de Ganesh Vernekar sur la tête et le WAL (*Prometheus TSDB*, parties 1 à 7) décrivent tout ce que tu vas voir. `promtool tsdb --help` et `promtool tsdb dump --help` donnent les options exactes de ta version.
</details>

<details><summary>Indice 2</summary>

`jq '{minTime: (.minTime/1000|todate), maxTime: (.maxTime/1000|todate), stats, compaction}' meta.json`. Les durées de blocs de Prometheus suivent une progression par facteur 3 à partir de 2 h, plafonnée à 10 % de la rétention (et à 31 jours) : calcule le plafond du témoin.
</details>

<details><summary>Indice 3</summary>

Un ULID commence par l'horodatage de sa création (48 bits, en millisecondes) : `python3 -c 'import sys; b="0123456789ABCDEFGHJKMNPQRSTVWXYZ"; print(sum(b.index(c)*32**i for i,c in enumerate(reversed(sys.argv[1][:10]))))' <ULID>` le décode. Compare avec `minTime` et `maxTime` du bloc.
</details>

**Pour aller plus loin** : prends un bloc du compartiment `thanos-k8s-par1` **en lecture** (`thanos tools bucket ls`, puis téléchargement d'un bloc de niveau 1 et d'un bloc sous-échantillonné dans `~/m21/e44/`) et compare leurs `meta.json` (section `thanos` : `labels`, `downsample.resolution`, `source`).

---

### M21-E45 — Questions expert : PromQL et Prometheus  `Q` `★★★`

> **Ticket PLAT-2245** — *De : Karim Benali*
> Dernière étape avant la recette de la supervision v1 : ces questions, je les pose en entretien. Réponds par écrit, en argumentant. Pas de recherche pendant la première passe ; vérifie ensuite dans la documentation et corrige-toi en couleur.

**Objectifs pédagogiques**
- Consolider la compréhension de PromQL et du fonctionnement interne de Prometheus, Alertmanager et Thanos manipulés dans ce module.
- S'entraîner à argumenter une réponse technique comme en entretien ou en revue.

**Prérequis** : paliers 1 à 3 du module, M21-E44.
**Durée indicative** : 2 h 30.

**Questions**

1. Que calcule exactement `rate(http_requests_total[5m])` ? Explique l'extrapolation aux bords de la fenêtre, le traitement d'une remise à zéro du compteur, et pourquoi `increase()` peut renvoyer une valeur non entière pour un compteur entier.
2. QCM — Une cible est collectée toutes les 30 s. Quelle fenêtre minimale choisir pour `rate()` dans une alerte ?
   a) `[30s]` ; b) `[1m]` ; c) `[2m]`, au moins quatre fois l'intervalle de collecte ; d) peu importe, `rate()` interpole.
3. `rate` contre `irate` : que fait chacune, dans quel cas `irate` est-elle utile, et pourquoi ne faut-il pas l'utiliser dans une alerte ou une règle d'enregistrement ?
4. QCM — Quelle expression donne le 95ᵉ centile de latence de MédiAgenda, tous pods confondus, à partir d'un histogramme classique ?
   a) `avg(histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])))` ; b) `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))` ; c) `histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])))` ; d) `quantile(0.95, rate(http_request_duration_seconds_sum[5m]))`.
5. Pourquoi faut-il **d'abord** appliquer `rate` puis `sum`, et jamais `rate(sum(...))` ? Que deviennent les remises à zéro dans le second cas ?
6. Qu'est-ce que la « péremption » (*staleness*) : marqueurs de péremption, délai de recherche (*lookback delta*, 5 min par défaut) ; que voit une requête instantanée 3 minutes après la disparition d'une cible, et 6 minutes après ?
7. `absent(up{job="vms"})` contre `absent_over_time(up{job="vms"}[10m])` contre `count(up{job="vms"}) < 12` : que détecte chacune, que rate-t-elle ?
8. QCM — `rate(http_requests_total{code=~"5.."}[5m]) / rate(http_requests_total[5m])` est censé donner le taux d'erreurs par pod. Le résultat vaut 1 partout où il existe, et rien pour les pods sans erreur. Pourquoi ?
   a) on ne peut pas diviser deux `rate()` ; b) la correspondance de vecteurs se fait sur **toutes** les étiquettes : chaque série 5xx de gauche ne trouve à droite que la série du **même** `code`, d'où 1 ; il faut agréger des deux côtés sur les étiquettes voulues ; c) `=~` est interdit dans un sélecteur passé à `rate()` ; d) il manque le modificateur `bool`.
   (Réécris l'expression correcte.)
9. Comment fonctionnent `for` et `keep_firing_for` ? Que devient l'état `pending` d'une alerte au redémarrage de Prometheus (`for_outage_tolerance`, `for_grace_period`) ?
10. Comment Prometheus nomme-t-il une règle d'enregistrement selon la convention `niveau:métrique:opérations`, et pourquoi enregistrer `sum by (le, job) (rate(..._bucket[5m]))` plutôt que le centile lui-même ?
11. Calcule la cardinalité d'une métrique `http_requests_total{methode, chemin, code, pod}` avec 5 méthodes, 40 chemins (gabarits), 8 codes et 6 pods ; puis avec des chemins **bruts** contenant un identifiant de rendez-vous. Que coûte chaque cas en mémoire, à 3 Ko par série (ordre de grandeur), sur deux réplicas ?
12. Fédération, *remote write*, sidecar Thanos : pour chacun, qu'est-ce qui est copié, quand, avec quelle perte possible, et pourquoi MédiSphère utilise la fédération entre `mon01` et le cluster mais le sidecar vers le RGW ?
13. Comment Thanos Query déduplique-t-il les deux réplicas (étiquette de réplica, `--query.replica-label`), et que se passe-t-il si les deux réplicas n'ont pas la même étiquette externe en dehors de celle de réplica ?
14. QCM — Le Compactor de Thanos tourne en deux instances sur le même compartiment. Que se passe-t-il ?
   a) rien, ils se partagent le travail ; b) ils compactent les mêmes blocs en parallèle et créent des blocs qui se chevauchent, puis s'arrêtent (*halt*) ou corrompent la vue ; c) le second attend un verrou ; d) le RGW refuse la seconde connexion.
15. Pourquoi le sous-échantillonnage de Thanos ne réduit-il pas toujours la place prise, et pourquoi garde-t-on les données brutes 30 jours alors qu'on a du 5 min et du 1 h ?
16. Alertmanager : expliquer `group_wait`, `group_interval`, `repeat_interval` par un exemple chronologique (première alerte à 3 h 00, deuxième du même groupe à 3 h 02, résolution à 3 h 20, réglages 30 s / 5 min / 4 h). Combien de courriels, à quelles heures ?
17. Comment deux Alertmanager en grappe évitent-ils d'envoyer deux fois le même courriel (gossip, position dans la grappe, délai de `peer_timeout`) ? Pourquoi Prometheus doit-il envoyer ses alertes aux deux ?
18. Prometheus 3 : qu'ont changé les noms UTF-8 pour PromQL (syntaxe `{"nom.avec.points"}`), les sélecteurs de plage (bord gauche exclu), l'expression régulière `.` (qui inclut désormais les fins de ligne), et le format de collecte (`scrape_protocols`) ? Lequel de ces changements peut fausser une alerte existante sans erreur ?
19. Un SLO de 99,5 % sur 28 jours : quel budget d'erreur en minutes ? Pourquoi alerter sur le **taux de consommation** (*burn rate*) avec deux fenêtres (par exemple 1 h et 5 min à 14,4) plutôt que sur le taux d'erreur instantané ?
20. Tu dois supprimer d'urgence des séries contenant des adresses de courriel de patients (M21-E38, variante RGPD) de **toute** la chaîne. Décris les étapes : relabeling, Prometheus (tête et blocs locaux), compartiment Thanos (outil, garde-fous), sauvegardes ; qui décide, qui exécute, et ce que tu documentes.

**Critères de réussite**
- [ ] Les 20 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses).
- [ ] Après correction, tu as identifié tes trois points les plus faibles et noté un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour 1 à 11 : documentation de Prometheus (*Querying basics*, *Operators* — priorité et correspondance de vecteurs —, *Functions*, *Histograms and summaries*, *Recording rules*, *Alerting rules*, *Staleness*), *Naming practices*, et ton travail de M21-E04, M21-E14, M21-E15, M21-E38.
</details>

<details><summary>Indice 2</summary>

Pour 12 à 20 : *Federation*, *Remote write*, documentation de Thanos (*Query*, *Compactor*, *Sidecar*), configuration et *high availability* d'Alertmanager, guide de migration vers Prometheus 3 (*Prometheus 3.0 migration guide*), *SRE Workbook* chapitre « Alerting on SLOs », ton M21-E26, M21-E27 et M21-E44.
</details>

**Pour aller plus loin** : choisis trois questions et transforme chacune en mini-démonstration sur le lab (5 minutes, reproductible, sur le témoin ou dans `wb-essais`), à présenter à Karim.
