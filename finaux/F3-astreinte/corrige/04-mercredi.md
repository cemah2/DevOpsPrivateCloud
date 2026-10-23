# Final F3 — Corrigé de la phase 4 : mercredi

> ⚠️ Corrigé. À n'ouvrir qu'après avoir cherché.

**Validé hors du lab** : règles et tests `promtool` de [`ceph-exploitation`](fichiers/S08/observabilite/regles/ceph-exploitation.yaml) (Prometheus 3.5, séries synthétiques) ; `shellcheck` de [`tester-analyses.sh`](fichiers/S09/gitops/outils/tester-analyses.sh).
**Points non testés en conditions réelles** : application **à chaud** des limites d'E/S d'un disque par `qm set` sur une VM en marche (Proxmox VE 9 les applique sans redémarrage par QMP ; à vérifier dans `qm monitor <VMID>` → `info block`) ; noms des séries `ceph_osd_flag_noout` et `ceph_pool_quota_bytes` du module prometheus de Tentacle 20.2 ; base de comparaison du quota (Ceph compare `max_bytes` aux octets **stockés** du pool) ; sous-commande `bao kv patch … clé=-` (lecture de la valeur sur l'entrée standard) ; reprise d'un Rollout abandonné par mise à jour de `status.abort` (ce que fait `kubectl argo rollouts retry`).

---

### F3-S08 — Mercredi : le stockage ralentit tout

**Démarche de diagnostic**

*Symptômes* : Grafana lent, Loki en retard, recette et déploiements lents, appel du support pour la production.

1. **Point commun** : tout ce qui est cité écrit sur des volumes `ceph-rbd` ou dans le RGW ; les services sans stockage (Gateway, `/sante` de l'API, DNS) répondent normalement. Hypothèse : **ceph-par1**. Gravité : SEV2 (production touchée par ricochet) ; premier message sous 15 min, comme Claire l'a demandé (la procédure dit 30 min pour un SEV2 : la demande explicite l'emporte, on la consigne).
2. `sudo ceph health detail` sur `ceph01` classe la panne :

**Variante 1 — un OSD arrêté et `noout`**

- `HEALTH_WARN` : `OSDMAP_FLAGS noout flag(s) set`, `OSD_DOWN 1 osds down`, `PG_DEGRADED`. `ceph osd tree` : un OSD `down` mais `in` ; `ceph orch ps --daemon-type osd` : `stopped`.
- Lecture : `noout` empêche Ceph de marquer l'OSD `out` au bout de 10 min, donc de reconstruire ses données ailleurs ; les PG restent `degraded` (deux copies sur trois) indéfiniment ; les E/S continuent mais avec plus de travail de pairage, et un second incident sur un autre OSD rendrait des PG inactifs (sous `min_size`).
- Origine : `sudo ceph log last 200 audit | grep -E 'noout|osd\.'` : `osd set noout` puis `orch daemon stop osd.<N>` par le compte de Lucas, sans ticket ni intervention en cours.
- Rétablissement : `sudo ceph orch daemon start osd.<N>`, attendre `up`, puis `sudo ceph osd unset noout` ; suivre la récupération (`ceph -s`) jusqu'à `active+clean`.
- Prévention : alerte `CephNooutProlonge` (4 h) [`ceph-exploitation.yaml`](fichiers/S08/observabilite/regles/ceph-exploitation.yaml) ; règle d'équipe : `noout` avec ticket et durée, retiré par la personne qui l'a posé.

**Variante 2 — les disques d'un nœud Ceph bridés par l'hyperviseur**

- `HEALTH_WARN` : `SLOW_OPS` (opérations lentes sur des OSD d'un même nœud) ; `ceph osd perf` : latences de commit de plusieurs centaines de ms sur les trois OSD d'un nœud, normales ailleurs. Dans la VM, `iostat -x 1` : peu d'IOPS, `await` très élevé, disque « occupé » sans débit.
- Hypothèse : sous la VM. Sur `pve01` :
  ```
  root@pve01:~# qm config 2082 | grep -E '^(scsi|virtio)'
  scsi1: ssd-lab:vm-2082-disk-1,iothread=1,size=64G,iops_rd=8,iops_wr=8,mbps_rd=2,mbps_wr=2
  root@pve01:~# pvesh get /cluster/tasks --output-format json | jq '.[] | select(.id == "2082") | {starttime, user, type}'
  ```
  Limites d'E/S QEMU posées sur les disques d'OSD (pas sur le disque système) ; tâche `qmconfig` récente de l'utilisateur de Lucas.
- Rétablissement : `qm set 2082 --scsiN <définition sans les clés iops_*/mbps_*>` pour chaque disque (Proxmox applique le changement à chaud) ; `ceph osd perf` revient sous quelques ms ; les `slow ops` disparaissent.
- Correction par le code : la définition des disques est dans `plateforme/infra` (état `ceph`, module `vm-noeud`) ; un `tofu plan` aurait montré la dérive : `tofu plan` planifié (nuit) sur l'état `ceph` avec alerte si le plan n'est pas vide (ticket PLAT-3308-a) ; les droits Proxmox de Lucas ne devraient pas permettre `VM.Config.Disk` sur les VMs Ceph (pool `lab` partagé : risque connu depuis l'ADR-0030).

**Variante 3 — le pool `k8s-rbd` a atteint son quota**

- `HEALTH_WARN` : `POOL_FULL pool 'k8s-rbd' is full (reached quota's max_bytes)` ; `ceph df detail` : `QUOTA BYTES` à peine au-dessus du stocké. Côté Kubernetes : les écritures des volumes **attendent** (pas d'erreur) : Prometheus ne rafraîchit plus, Loki accumule, la base de production n'écrit plus (les créations de rendez-vous attendent) ; le témoin de `mon01` finit par signaler la supervision muette.
- Origine : `ceph log last 200 audit | grep set-quota` : quota posé par Lucas « pour figer la croissance en attendant les disques ».
- Rétablissement (`[décision]` rapide : c'est la production qui attend) : `sudo ceph osd pool set-quota k8s-rbd max_bytes 0` ; les écritures reprennent seules en quelques secondes ; vérifier la base de production (réplication, pas de transaction bloquée) et le retard de Loki/Thanos qui se résorbe.
- Prévention : alerte `CephPoolProcheDuQuota` (80 %) ; un quota, s'il en faut un, se déclare dans `plateforme/ceph` avec une alerte, et se dimensionne sur la croissance mesurée ; la vraie réponse au manque de place est l'alerte de capacité du cluster (`CephPoolNearFull`, M08).

**Messages d'état types** (SEV2) : début « lenteurs générales dues au stockage commun ; la production est ralentie (prises de rendez-vous lentes) ; aucune perte de données ; diagnostic en cours ; prochain point HH:MM » ; point d'étape « cause trouvée (<un disque hors service sans reconstruction | des disques bridés | une limite de capacité>), correction en cours, retour attendu vers HH:MM » ; fin « stockage revenu à la normale à HH:MM ; reconstruction terminée à HH:MM ; aucune donnée perdue ; prévention : <alertes, contrôles de dérive> ».

**Main courante attendue** : `[ouverture]` avec la liste des symptômes et l'hypothèse du point commun, `[état]` à 15 min, `[action]` santé Ceph détaillée (codes), `[action]` origine (journal d'audit, tâches Proxmox), `[décision]` du geste (démarrer l'OSD et retirer `noout` / retirer les limites / retirer le quota) avec le retour arrière, `[action]` suivi jusqu'à `active+clean`, au moins deux `[état]`, `[clôture]`.

Runbook : [`RB-334-stockage-ceph-lent.md`](fichiers/S08/medisphere/docs/exploitation/runbooks/RB-334-stockage-ceph-lent.md).

**Explications**

Ceph est le point commun de presque toute la plateforme (volumes de Kubernetes, RGW de l'observabilité) : quand « tout est lent », c'est le premier suspect, et `ceph health detail` le confirme ou l'écarte en une commande. Les trois variantes montrent trois manières de ralentir sans rien casser : priver le cluster de sa capacité de réparation (`noout`), d'un nœud rapide (limites QEMU), ou de place (quota). Dans les trois cas, aucune donnée n'est perdue et le retour est immédiat une fois la cause retirée ; le risque est ailleurs : qu'un second incident survienne pendant que la redondance est réduite.

**Alternatives**

- Variante 1 : `ceph osd unset noout` d'abord laisse Ceph marquer l'OSD `out` et reconstruire ailleurs ; correct si l'OSD est réellement malade, inutile s'il est seulement arrêté.
- Variante 2 : migrer les PG hors des OSD lents (`ceph osd primary-affinity 0`, puis `reweight`) : contournement si la cause ne peut pas être retirée vite.
- Variante 3 : relever le quota au lieu de le retirer : à faire si une décision de capacité l'impose, avec l'alerte.

**Pièges classiques**

- Redémarrer les OSD lents (variante 2) : ils redémarrent sur les mêmes disques bridés, et la reconstruction ajoute de la charge.
- `ceph osd out` sur l'OSD arrêté sans savoir pourquoi il l'est (intervention en cours ?).
- Supprimer des images RBD « orphelines » pour faire de la place sous le quota : perte de données, pour un problème de configuration.
- Chercher la cause dans chaque service (Loki, Grafana, PostgreSQL) un par un.

**En production chez MédiSphère**

Alertes de santé Ceph routées vers l'astreinte (`CephHealthError` critique, `CephHealthWarning` avertissement), contrôle de dérive de l'infrastructure (`tofu plan` nocturne), interdiction des gestes `noout`/quota/`qm set` sans `CHG-`, et capacité suivie chaque semaine dans le rapport d'astreinte (S16).

---

### F3-S09 — Mercredi : la livraison est bloquée

**Démarche de diagnostic**

*Symptôme* : « ma livraison n'arrive pas en recette ; l'appli va bien ».

1. **Depuis la recette** (RB-335 §1) : révision synchronisée de `mediagenda-recette` contre le dernier commit de `mediagenda/deploiement` ; conditions de l'Application ; état du Rollout ; derniers `AnalysisRun`.
2. Selon l'étage :

**Variante 1 — l'analyse du canary ne mesure plus rien**

- L'Application est synchronisée sur le commit de Julien (DEV-3309) ; le Rollout a démarré une révision (poids 10 %), puis s'est **abandonné** : `Degraded`, message « RolloutAborted » ; l'`AnalysisRun` d'arrière-plan : mesures `taux-erreur` et `latence-p95` en **Error** (`consecutiveErrorLimit: 4` atteint ; l'abandon vient de la première des deux) : une requête qui renvoie un vecteur **vide** fait échouer l'évaluation de `result[0]` — même la condition `isNaN(result[0]) || …` de la latence, qui n'accepte un NaN que si une série existe.
- Copie de la requête résolue dans Prometheus : vide. Les séries de MédiAgenda portent `rollouts_pod_template_hash` (réétiquetage du ServiceMonitor, M21-E07) ; la requête cherche `pod_template_hash`. Le canary va très bien : ses requêtes réussissent (`mediagenda_http_requests_total{rollouts_pod_template_hash="<canary>"}`).
- Origine : `git log -p` de `plateforme/gitops` : commit de Lucas « étiquette pod_template_hash, comme le reste du cluster » sur la `ClusterAnalysisTemplate` `taux-erreur-mediagenda`.
- Correction : MR (revert) dans `plateforme/gitops`, synchronisation de l'Application qui porte les analyses ; vérifier la requête en direct ; puis `kubectl argo rollouts retry rollout mediagenda -n mediagenda-recette` : le canary repart, l'analyse passe, la révision devient stable.
- Prévention : [`outils/tester-analyses.sh`](fichiers/S09/gitops/outils/tester-analyses.sh) (chaque requête d'analyse rejouée avec les arguments d'un Rollout réel ; échoue si elle est vide) avant fusion de toute MR qui touche les analyses, et chaque nuit depuis `mon01` (PLAT-3309-b) ; la production utilise la même `ClusterAnalysisTemplate` : sans la réparation, **la prochaine mise en production aurait été abandonnée aussi**.

**Variante 2 — Argo CD ne lit plus les dépôts de MédiAgenda**

- L'Application n'est pas sur le dernier commit ; condition `ComparisonError` : `authentication required` (ou `HTTP Basic: Access denied`) en lisant `mediagenda/deploiement`. Toutes les Applications du groupe `mediagenda` (dev, recette, prod) ont la même erreur : ce n'est pas le dépôt, ce sont les **identifiants**.
- `kubectl -n argocd describe externalsecret repo-creds-mediagenda` : synchronisé récemment ; `bao kv metadata get -mount=kv plateforme/argocd/depot-mediagenda` : une version créée aujourd'hui (auteur visible dans le journal d'audit d'OpenBao, Loki locataire `audit`) — sans jamais lire la valeur.
- Cause : « rotation » ratée : le mot de passe du dépôt (jeton de déploiement GitLab) a été remplacé par une valeur qui n'est pas un jeton valide.
- Correction : créer un **nouveau** jeton de déploiement `read_repository` (API ou interface du groupe `mediagenda`), l'écrire dans OpenBao (`printf '%s' "$JETON" | bao kv patch -mount=kv plateforme/argocd/depot-mediagenda password=-`), forcer ESO (`kubectl -n argocd annotate externalsecret repo-creds-mediagenda force-sync=$(date +%s) --overwrite`), rafraîchir les Applications ; révoquer l'ancien jeton s'il n'avait pas expiré (RB-191). Ou, si la version précédente du secret est l'ancien jeton toujours valide : `bao kv rollback -mount=kv -version=<N> …` (geste plus rapide, rotation à refaire ensuite).
- Prévention : la rotation des identifiants de dépôt passe par un script ou un job (`ci-secrets-rotation`, M25) qui **vérifie** le jeton (`git ls-remote` avec lui) avant de l'écrire ; alerte Argo CD sur les `ComparisonError` (métrique `argocd_app_info{sync_status="Unknown"}` ou notifications d'Argo CD vers l'astreinte).

**Variante 3 — le runner protégé est hors ligne**

- Rien de nouveau dans `mediagenda/deploiement` ; dans GitLab, le pipeline de la dernière étiquette de `mediagenda/api` a un job de signature relancé (Julien) qui reste `pending` : « This job is stuck because you don't have any active runners online with any of these tags assigned to them: protege ».
- `kubectl -n gitlab-runner get deploy` : le gestionnaire `…-protege` à 0 réplica ; `kubectl get events -n gitlab-runner` et l'historique (`kubectl rollout history`, `managedFields`) : mis à 0 à la main (« maintenance » de Lucas, jamais remise).
- Correction : remettre l'état de `plateforme/k8s` (Helmfile, release `gitlab-runner-protege`, `helmfile -l name=gitlab-runner-protege apply` après `diff`) ; le runner se reconnecte, le job part, signe, la promotion s'ensuit.
- Prévention : alerte sur l'absence de runner protégé en ligne (métrique du gestionnaire `gitlab_runner_version_info` absente, ou sonde de l'API GitLab des runners), et `helmfile diff` planifié qui signale toute dérive de la couche de base.

**Messages d'état types** (SEV3 : la recette et la démo de demain sont menacées, pas la production — mais si la variante 1 est en cause, dire que la **production** serait bloquée aussi) : début « l'application est saine ; la chaîne de livraison bloque la version DEV-3309 avant la recette ; diagnostic en cours ; prochain point HH:MM » ; fin « livraison arrivée en recette à HH:MM par la chaîne normale ; cause : <analyse qui ne mesurait plus rien | identifiants du dépôt invalides | runner de signature arrêté> ; prévention : <…> ».

**Main courante attendue** : `[ouverture]`, `[action]` étage par étage (révision de l'Application, état du Rollout, mesure de l'analyse, jobs en attente), `[action]` origine (commit, version du secret, mise à l'échelle), `[décision]` (revert / nouveau jeton / remise à l'échelle), `[action]` livraison arrivée par la chaîne (révision stable, heure), `[clôture]`.

Runbook : [`RB-335-livraison-bloquee.md`](fichiers/S09/medisphere/docs/exploitation/runbooks/RB-335-livraison-bloquee.md).

**Explications**

Une chaîne de livraison a des garde-fous (signature, analyse, GitOps) qui **refusent** par défaut : c'est voulu. Quand l'outillage tombe en panne, le refus ressemble à un refus légitime ; la question décisive est « la mesure est-elle en **échec** (le canary est mauvais) ou en **erreur** (on ne sait pas mesurer) ? ». Les trois variantes montrent trois étages différents (analyse, lecture des dépôts, signature) dont aucun ne touche l'application ; la réparation ne contourne aucun garde-fou : elle répare l'outil, puis laisse la livraison passer par la chaîne.

**Alternatives**

- Variante 1 : `kubectl argo rollouts promote --full` fait passer la version sans analyse : interdit ici (l'analyse est un garde-fou de la production) ; tolérable seulement en recette, consigné, si l'analyse ne peut pas être réparée à temps pour la démo — et la production reste bloquée tant qu'elle n'est pas réparée.
- Variante 2 : identifiants de dépôt par clé SSH de déploiement au lieu de jeton : même problème de rotation, autre forme.
- Variante 3 : relancer le job sur le runner non protégé (changer ses étiquettes) : interdit, c'est exactement ce que la séparation des runners empêche (la clé de signature ne doit pas atteindre un runner partagé).

**Pièges classiques**

- Livrer à la main (`kubectl apply` du rendu) pour la démo : l'Application repasse `OutOfSync`, Argo CD l'écrase, et la vraie panne reste.
- Corriger la requête d'analyse **dans le cluster** (`kubectl edit clusteranalysistemplate`) : Argo CD la remet comme dans Git.
- Lire la valeur du secret pour « vérifier » : inutile (l'erreur d'Argo CD suffit) et contraire aux règles.
- Oublier de relancer le Rollout abandonné : la réparation est faite, la version n'arrive toujours pas.

**En production chez MédiSphère**

Les requêtes d'analyse sont testées en CI, les rotations d'identifiants sont automatisées et vérifiées, la disponibilité des runners est supervisée, et la livraison a son propre indicateur (délai entre la fusion et l'arrivée en recette, publié dans le portail) : une livraison qui stagne plus d'une heure alerte l'équipe Plateforme avant que Julien n'appelle.
