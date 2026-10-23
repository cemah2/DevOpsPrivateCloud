# Final F3 — Phase 4 : mercredi

Deux incidents où le symptôme ment : « tout est lent » alors qu'une seule brique est en cause, puis « l'application ne se déploie plus » alors que l'application va très bien. Même discipline : main courante, gravité, messages d'état, correction par le code, contrôle, clôture. Rappel : [`00-introduction.md`](00-introduction.md).

---

### F3-S08 — Mercredi : le stockage ralentit tout  `BF` `★★★★`

> **Ticket INC-5908** — *De : Claire Morel*
> *(Le détail s'affiche à l'injection : tout le monde se plaint de lenteurs en même temps, sans livraison récente.)*

**Objectifs pédagogiques**
- Trouver le **point commun** de symptômes dispersés (Grafana, Loki, recette, production, déploiements) au lieu de traiter chaque symptôme.
- Diagnostiquer Ceph sous incident : santé détaillée, PG, OSD, drapeaux, quotas, latences, et l'hyperviseur sous les OSD.
- Rétablir sans perdre de PG ni de données, en sachant ce qu'on peut faire pendant que des écritures attendent.

**Prérequis** : M08 (Ceph : santé, OSD, drapeaux, quotas, performances, RB-08x), M09 (limites de disques Proxmox), M16 (ceph-csi, `k8s-rbd`), M21 (alertes et tableaux Ceph) ; F3-S07 clos.
**Durée indicative** : 1 h 30 (temps cible).

**Contexte technique**
- `ceph-par1` : `ceph01-03` (VMID 2081-2083, Rocky Linux 10, cephadm, Tentacle 20.2), trois OSD par nœud (deux `ssd`, un `hdd`) ; commandes `ceph` sur le nœud `_admin` (`ceph01`, `sudo`). Les PVC de `k8s-par1` sont dans le pool `k8s-rbd` (StorageClass `ceph-rbd`) ; Thanos, Loki et Tempo écrivent dans le RGW.
- Les spécifications cephadm sont dans `plateforme/ceph`, les VMs dans `plateforme/infra` (état `ceph`).
- L'injection vérifie qu'une sauvegarde récente de la base de production existe (ses volumes sont dans `k8s-rbd`).
- ⚠️ **Interdit** : marquer un OSD `out` ou le détruire « pour voir », supprimer un pool, un PG ou une image RBD, redémarrer plusieurs nœuds Ceph à la fois.

**Injection** : `lab/bin/break F3 8` (3 variantes).

**Travail demandé**
1. Ouvre INC-5908 ; premier message d'état dans les 15 min (Claire l'exige) ; recense les symptômes et cherche ce qu'ils ont en commun.
2. Diagnostique Ceph jusqu'à la cause racine, et jusqu'à son origine (qui, quand, par quel chemin : commande à la main, hyperviseur, code).
3. Rétablis (décision consignée), suis le retour à la normale (PG, latences, écritures en attente), puis corrige ou empêche la récidive par le code (spécifications, état OpenTofu des VMs, garde-fous).
4. Écris **RB-334** « Stockage Ceph lent ou bloqué ».

**Critères de réussite**
- [ ] Ceph est en `HEALTH_OK`, sans drapeau qui suspend la reconstruction ou les E/S ; tous les OSD sont `up` et `in` ; la latence de commit des OSD est sous 100 ms.
- [ ] Le quota du pool `k8s-rbd` laisse de la marge (pas de quota, ou au moins 1,5 fois le stocké) ; aucun disque des VMs Ceph n'a de limite d'E/S côté Proxmox.
- [ ] Le contrôle de santé est vert.
- [ ] INC-5908 est ouvert et clos, avec au moins **deux** messages d'état consignés et envoyés ; RB-334 est publié.

**Vérification** : `lab/bin/check F3 8`

<details><summary>Indice 1</summary>

`ceph health detail` d'abord, puis `ceph -s`, `ceph osd tree`, `ceph osd dump | grep flags`, `ceph osd perf`, `ceph df detail` (colonnes de quota). Dans Grafana, le tableau Ceph du M21 montre la latence par OSD. Si un seul nœud est en cause, la question suivante est : Ceph, la VM, ou ce qu'il y a sous la VM ?
</details>

<details><summary>Indice 2</summary>

Pour savoir qui a fait quoi : `ceph log last 200` et le journal d'audit du moniteur (`ceph log last 200 audit`), l'historique des tâches de Proxmox (`pvesh get /cluster/tasks`) et `qm config` des VMs Ceph, comparé à ce que décrit `plateforme/infra`.
</details>

**Pour aller plus loin** (facultatif) : ajoute une règle d'alerte sur l'âge des drapeaux `noout` (pas plus de 4 h sans ticket) et sur l'occupation des pools rapportée à leur quota, avec leurs tests `promtool`.

---

### F3-S09 — Mercredi : la livraison est bloquée  `BF` `★★★`

> **Ticket INC-5909** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection : une livraison de MédiAgenda n'arrive pas en recette ; l'application, elle, va bien.)*

**Objectifs pédagogiques**
- Suivre une livraison de bout en bout (MR, pipeline, signature, promotion, Argo CD, Rollout et son analyse) et trouver l'étage bloqué.
- Distinguer un **refus légitime** de l'outillage (le canary est mauvais) d'une **panne de l'outillage** (l'application est bonne).
- Débloquer sans contourner les garde-fous (signature, analyse, GitOps) ni livrer à la main.

**Prérequis** : M19 (CI, runner protégé `k8s-par1-protege`, signature), M20 (Argo CD, identifiants de dépôts, Rollouts, analyses), M21-E18 (analyse Prometheus du canary), M25 (ESO, OpenBao) ; F3-S08 clos.
**Durée indicative** : 1 h (temps cible).

**Contexte technique**
- Chaîne : `mediagenda/api` (CI : construction, analyse, **signature sur le runner protégé**, promotion par MR) → `mediagenda/deploiement` (overlays) → Application `mediagenda-recette` (synchronisation automatique) → Rollout `mediagenda` (canary par le plugin Gateway API, analyse d'arrière-plan `taux-erreur-mediagenda`, ClusterAnalysisTemplate de `plateforme/gitops`).
- Argo CD lit les dépôts du groupe `mediagenda` avec les identifiants `repo-creds-mediagenda` (ExternalSecret, OpenBao `kv/plateforme/argocd/depot-mediagenda`).
- L'injection assure un trafic de recette (témoin `wb-pannes/trafic-recette` du M27) : un canary qui ne reçoit pas de trafic n'est jamais déclaré sain, par conception.
- ⚠️ **Interdit** : `kubectl apply` ou `kubectl argo rollouts promote --full` pour « faire passer » sans avoir compris ; désactiver l'analyse, la signature ou la politique Kyverno ; pousser une image à la main.

**Injection** : `lab/bin/break F3 9` (3 variantes ; jusqu'à 30 min : commits, synchronisation, analyse du canary).

**Travail demandé**
1. Ouvre INC-5909 ; dis à Julien, dès le premier message d'état, ce que tu sais de l'application et ce que tu ne sais pas encore.
2. Trouve l'étage qui bloque et la cause racine, auteur et date compris.
3. Répare l'outillage par le chemin normal, puis laisse la livraison **arriver par la chaîne** (relance documentée si nécessaire).
4. Prévention : ce qui aurait attrapé la panne avant Julien (test, alerte, revue) ; écris **RB-335** « Livraison bloquée ».

**Critères de réussite**
- [ ] L'analyse `taux-erreur-mediagenda` mesure la révision canary (`rollouts_pod_template_hash`).
- [ ] L'Application `mediagenda-recette` est `Synced`/`Healthy`, sans erreur de comparaison, sur le dernier commit de `mediagenda/deploiement` ; le Rollout de recette est `Healthy`, non abandonné, révision stable = révision courante.
- [ ] Le gestionnaire du runner protégé est prêt ; aucun job protégé de `mediagenda/api` n'attend depuis plus de 15 min ; le contrôle de santé est vert.
- [ ] INC-5909 est ouvert et clos, avec au moins un message d'état consigné et envoyé ; RB-335 est publié.

**Vérification** : `lab/bin/check F3 9`

<details><summary>Indice 1</summary>

Remonte depuis la recette : l'Application voit-elle le dernier commit (révision, conditions) ? Le Rollout a-t-il commencé, à quelle étape s'est-il arrêté, pourquoi (`kubectl argo rollouts get rollout`, `AnalysisRun` et leurs mesures) ? Rien en recette et rien dans Argo CD : remonte vers la CI (pipelines de la dernière étiquette, jobs en attente et leurs étiquettes de runner).
</details>

<details><summary>Indice 2</summary>

Une mesure d'analyse en **erreur** n'est pas une mesure en **échec** : copie la requête de l'`AnalysisRun` (arguments résolus) dans Prometheus et regarde ce qu'elle renvoie, puis compare les étiquettes qu'elle cherche avec celles des séries réelles. Pour un dépôt illisible, le message de l'Application et l'âge du Secret (`kubectl get secret … -o jsonpath='{.metadata.managedFields}'`, statut de l'ExternalSecret) disent quand et par qui il a changé — sans lire sa valeur.
</details>

**Pour aller plus loin** (facultatif) : ajoute à la CI de `plateforme/gitops` un test qui rejoue chaque requête des `ClusterAnalysisTemplate` sur Prometheus avec un hachage réel de la recette et échoue si elle ne renvoie rien.
