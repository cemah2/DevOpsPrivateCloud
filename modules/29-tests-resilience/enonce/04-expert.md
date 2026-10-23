# Module 29 — Palier 4 : Expert

Les tests tournent, la charge est mesurée chaque nuit, les expériences de chaos ont leur bibliothèque et leur bouton d'arrêt, la première journée de jeu a eu lieu. Nadia Roussel pose sa question rituelle : « Et le jour où **l'outillage de test** lui-même ment, ou casse quelque chose ? » Un filet de sécurité qui laisse passer, une expérience qui refuse de s'arrêter, des VMs de test qui s'accumulent, des tests rouges que tout le monde finit par ignorer, une journée de jeu qui réveille une vraie faiblesse : ce sont les incidents les plus vicieux, parce qu'on fait confiance à l'outil. Tu finis sous le capot de Chaos Mesh, pour savoir exactement ce qu'il pose sur un nœud et comment l'enlever à la main.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Trois règles propres aux tests et au chaos :
- **Prouve que le filet peut encore attraper.** Un test vert ne prouve rien tant qu'on n'a pas vu le même test rouge sur un cas connu. Garde des cas de référence (« plan dangereux », « VM dérivée ») et rejoue-les.
- **Le chaos laisse des traces sur les nœuds.** Une expérience, c'est un objet dans l'API **et** des règles réelles (`tc`, `iptables`, processus de stress) posées par le `chaos-daemon` dans les espaces de noms des conteneurs. Supprimer l'objet ne suffit pas toujours ; vérifier sur le nœud, si.
- **Le code fait foi, l'historique aussi.** Politiques, CI, valeurs des charts, manifestes : tout est dans Git. `git log` trouve l'auteur et la date de la plupart des pannes.

> **Rappels** : tout se lance depuis `adm01`. Ton kubeconfig personnel pour le cluster (OIDC), `admin.conf` en bris de glace ; SSH `admin` + `sudo` vers les nœuds et les VMs ; `kubectl cnpg`, `k6`, `opa`, `conftest`, `crictl` (sur les nœuds) ; les clones `~/src/resilience`, `~/src/politiques`, `~/src/infra`, `~/src/ansible`, `~/src/tofu-modules`, `~/src/gitops`.

## Règles du jeu des pannes (M29-E19 à M29-E23)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 29 19
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**. Chaque panne a 2 à 3 variantes (`--variante N` force une variante sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab (ta configuration diffère de celle du corrigé), le script en essaie une autre ; si aucune n'a d'effet, il remet tout en état et te dit quel prérequis manque. Une injection prend **de 1 à 15 minutes** : certaines passent par un commit, la synchronisation d'Argo CD, une mise à l'échelle par l'HPA, et le script attend de constater l'effet.
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 29 19`) : il doit être vert. Le script refuse de casser un lab qui ne va pas bien.
- **Prérequis techniques** sur `adm01` : le jeton d'administration GitLab de M01 (`WB_GITLAB_ADMIN_TOKEN_FILE`, portée `api`) ; `yq` de mikefarah (v4) et `jq` (M02), `opa` 1.21 et `conftest` 0.71 (M29-E03), `kubectl` ; SSH vers les nœuds de `k8s-par1`, vers `pve01` (root) et vers les VMs du socle.
- **Commits de Lucas.** Certaines pannes modifient un dépôt (`plateforme/politiques`, `plateforme/infra`, `plateforme/gitops`, `mediagenda/deploiement`) par un commit signé « Lucas Martin », avec le marqueur `M29-EXX` dans le message ; si `main` refuse la poussée directe, elles passent par une MR fusionnée par le script après son pipeline. C'est un vrai changement : il apparaît dans `git log`, dans Argo CD, dans le journal d'audit de GitLab. Corrige-le comme un vrai commit fautif (revert ou correction par MR).
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les hôtes, ni `~/.local/state/workbook/` sur `adm01`.
- Une seule panne active à la fois par exercice. `lab/bin/break 29 19 --annuler` remet l'état sain (filet de sécurité, pas un correctif). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne : l'annulation ne défait jamais ta réparation (un fichier n'est remis que s'il est encore exactement dans l'état injecté), et une panne ouverte bloque l'astreinte M29-E23 et le mini-projet.
- Les pannes n'agissent que sur : les dépôts cités plus haut ; les objets des espaces `chaos-experiences`, `mediagenda-recette`, `medinotif-recette` et `wb-essais` ; les pods de `chaos-mesh` (par leurs valeurs Git) ; les VM **2298-2299** du sous-pool `lab/terratest` sur `pve01` ; un fichier temporaire sur `adm01` ; une VM non critique du socle (`nbx01` ou `mon01`, par `WB_M29_E22_HOTES`) dont les fichiers modifiés sont sauvegardés. **Jamais** `*-prod`, `messagerie`, `kube-system`, `argocd`, `kyverno` ; aucune donnée détruite.
- **Journal de diagnostic** pour chaque panne dans `docs/qualite/journal/` de `~/medisphere` : heure, hypothèse, commande, résultat, conclusion. Il nourrit les runbooks RB-294, RB-297 et RB-293 (complété en E21) et le post-mortem de M29-E23.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Effets de bord** : E20 et E23 dégradent réellement la **recette** de MédiAgenda (latence, indisponibilité) le temps de l'exercice ; préviens Julien. E21 crée deux VMs (arrêtées) sur `pve01` ; E22 dérègle un service d'une VM du socle (l'heure, `sshd` ou l'exportateur de métriques) : la supervision de `mon01` peut alerter, c'est attendu.

---

### M29-E19 — Panne : un plan dangereux passe la CI  `BF` `★★`

> **Ticket SEC-3019** — *De : Sophie Laurent*
> *(Le détail s'affiche à l'injection : un plan de référence qui détruit une VM du socle n'est plus refusé par la chaîne de validation de `plateforme/infra`.)*

**Objectifs pédagogiques**
- Remonter la chaîne de validation d'un plan OpenTofu : job de plan, composant `validation` (`.validation:conftest-plan`), arguments de `conftest` (`--policy`, `--namespace`, `--data`), paquets Rego, règles, tests.
- Distinguer « la règle n'est pas évaluée », « la règle est évaluée mais ne peut plus se déclencher » et « la règle refuse mais le pipeline ne s'arrête pas ».
- Rendre ce type de régression **impossible à rater** : test de non-régression des politiques sur des plans réels.

**Prérequis** : M29-E03, M29-E10 ; `lab/bin/check 29 19` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : `ressources/E19-plan-dangereux/plan-dangereux.json` est la sortie `tofu show -json` d'un plan de `plateforme/infra` qui **supprime** la VM `nbx01` et crée une VM sans étiquette d'environnement ; les politiques de M29-E03 le refusaient (vérifie-le d'abord sur ton historique : `conftest test` à une date antérieure, ou le check de cet exercice). Le script vérifie, avant d'injecter, que ce plan est refusé avec **les arguments du job de plan** (espaces, `--data rego/donnees`, et le contexte que le job écrit, ici celui de l'état `socle` sans étiquette de MR) ; tu peux désigner un autre plan de référence par `WB_M29_E19_PLAN` et son état par `WB_M29_E19_ETAT`.

**Injection** : `lab/bin/break 29 19` (3 variantes).

**Travail demandé**
1. Reproduis : fais passer le plan de référence par **exactement** ce que fait la CI de `plateforme/infra` (mêmes politiques, mêmes arguments), pas par ta commande habituelle.
2. Situe l'étage : le job de validation tourne-t-il ? que dit son journal (combien de politiques, de règles évaluées, d'échecs) ? son statut compte-t-il pour le pipeline ? Les politiques de `main` refusent-elles le plan quand on les évalue toutes (`--all-namespaces`) ?
3. Trouve la cause racine et son auteur (`git log -p` dans les dépôts concernés) ; corrige par MR.
4. **Prévention** : ajoute à `plateforme/politiques` un test qui échoue si le plan de référence n'est plus refusé (le plan versionné à côté des tests, évalué en CI avec les arguments de production), et une règle de revue (`CODEOWNERS` ou approbation) sur les fichiers qui décident de ce que la CI bloque.

**Critères de réussite**
- [ ] Le plan de référence est de nouveau refusé par les politiques de `main`, avec les arguments de la CI de `plateforme/infra`.
- [ ] Aucun job de validation ni de plan de `plateforme/infra` n'est autorisé à échouer ; les paquets Rego de `rego/tofu/` sont dans les espaces évalués par la CI.
- [ ] `plateforme/politiques` contient un test de non-régression sur un plan réel (fichier JSON versionné) ; la panne est close.

**Vérification** : `lab/bin/check 29 19`

<details><summary>Indice 1</summary>

`conftest test` n'évalue que l'espace `main` par défaut, ou ceux qu'on lui donne par `--namespace` (plusieurs fois), ou tous avec `--all-namespaces`. Un paquet Rego dont le nom ne fait pas partie de la liste est ignoré **sans un mot** : la sortie dit seulement combien de tests ont été passés. Compare ce nombre avec celui d'un ancien pipeline.
</details>

<details><summary>Indice 2</summary>

`opa eval -d rego/tofu -i plan-dangereux.json 'data' --format pretty` montre ce que chaque paquet produit sur ce plan. Si une règle ne produit rien alors qu'elle devrait, lis le chemin qu'elle parcourt dans `input` et compare-le à la structure réelle du plan (`jq 'keys'`). Des tests unitaires verts ne prouvent pas que le chemin existe dans un vrai plan : ils prouvent qu'il existe dans **leur** entrée.
</details>

<details><summary>Indice 3</summary>

Un pipeline peut être vert avec un job rouge : `allow_failure`. Dans GitLab, le job apparaît alors en orange avec un point d'exclamation, et le pipeline est « passed ». La clé peut se poser dans le composant, dans le `.gitlab-ci.yml` qui l'inclut en surchargeant le job par son nom, ou dans un **modèle caché** que les jobs étendent (`extends`) : regarde aussi ceux-là.
</details>

**Pour aller plus loin** (facultatif) : ajoute à la CI de `plateforme/politiques` un test de mutation léger : pour chaque règle, une copie du plan de référence « corrigée » juste assez pour qu'elle passe, et vérifie que **seule** la règle concernée change de verdict.

---

### M29-E20 — Panne : une expérience de chaos ne s'arrête plus  `BF` `★★★`

> **Ticket INC-5620** — *De : Julien Petit* (ou Lucas Martin, selon le cas)
> *(Le détail s'affiche à l'injection : selon le cas, la recette de MédiAgenda reste lente alors que l'expérience a été supprimée, ou une expérience refuse de disparaître.)*

**Objectifs pédagogiques**
- Trouver **toutes** les expériences actives qui touchent un pod et leur état réel (`Schedule`, pause réellement prise en compte ou non, objets intermédiaires `PodNetworkChaos`).
- Comprendre le cycle de vie d'une expérience (`desiredPhase`, enregistrements par conteneur, finaliseur `chaos-mesh/records`) et ce qui bloque sa suppression.
- Retirer à la main, proprement, ce que le `chaos-daemon` n'a pas pu retirer, et le prouver sur le nœud.

**Prérequis** : M29-E13 ; RB-294 ; `lab/bin/check 29 20` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : les expériences du lab vivent normalement dans `chaos-experiences`. Le `chaos-daemon` (DaemonSet de `chaos-mesh`) pose les règles dans l'espace réseau du pod visé ; son espace de travail sur le nœud est celui du runtime containerd (`/run/containerd/containerd.sock`). Sur les nœuds, `crictl` et `nsenter` sont disponibles avec `sudo`. La configuration de Chaos Mesh vit dans `plateforme/gitops/valeurs/chaos-mesh/values.yaml` (Application `chaos-mesh`).

**Injection** : `lab/bin/break 29 20` (3 variantes).

> ⚠️ **Attention** : ne supprime **pas** le finaliseur d'une expérience « pour débloquer » avant d'avoir compris pourquoi il est là : il garantit que la panne a été retirée du pod. Sans lui, l'objet disparaît… et la latence reste. Si tu dois forcer, prévois d'abord comment tu vérifieras et retireras toi-même ce qui reste sur le nœud.

**Travail demandé**
1. Mesure le symptôme côté utilisateur (latence, erreurs de la recette) et liste ce que Chaos Mesh croit actif : toutes les expériences de tous les types, dans **tous** les espaces, les `Schedule`, les `Workflow`, les `PodNetworkChaos`.
2. Pour l'expérience en cause, lis `status.experiment` (phase désirée, enregistrements par conteneur, événements) et les finaliseurs. Lis les journaux du `chaos-controller-manager` et du `chaos-daemon` du nœud concerné.
3. Prouve sur le nœud ce qui est réellement posé dans l'espace réseau du pod visé (`crictl`, `nsenter`, `tc qdisc show`).
4. Arrête la panne **à la racine** (ce qui la recrée, ce qui empêche son retrait), puis vérifie sur le nœud qu'il ne reste rien. Si tu as dû retirer une règle à la main, dis pourquoi le contrôleur ne l'a pas fait.
5. Complète **RB-294** et écris **RB-297** « Une expérience de chaos ne s'arrête pas » : arbre de décision (qui la recrée ? qui empêche son retrait ?), commandes de preuve, retrait manuel, forçage du finaliseur en dernier recours (`chaos-mesh.chaos-mesh.org/cleanFinalizer`), vérification finale.

**Critères de réussite**
- [ ] Aucun objet de chaos hors de `chaos-experiences` ; aucune expérience « en pause » par une annotation qui n'est pas `experiment.chaos-mesh.org/pause=true` ; aucun `Schedule` non en pause n'embarque une expérience sans durée.
- [ ] Les `chaos-daemon` sont prêts sur tous les travailleurs, avec le socket containerd attendu ; aucune expérience bloquée en suppression.
- [ ] Aucun `qdisc` `netem` ne reste sur les pods de l'API MédiAgenda ; la latence p95 de la recette est revenue sous 250 ms.
- [ ] RB-297 est publié ; la panne est close.

**Vérification** : `lab/bin/check 29 20`

<details><summary>Indice 1</summary>

`kubectl api-resources --api-group=chaos-mesh.org -o name` donne tous les types ; une boucle `kubectl get <type> -A` les passe tous. Un objet qui revient après suppression a un parent : regarde `ownerReferences` et les étiquettes posées par un `Schedule`. Une expérience « en pause » l'est si son **statut** le dit (`desiredPhase`, condition `Paused`), pas parce qu'une annotation contient le mot « pause ». Un `PodNetworkChaos` porte le nom du pod visé, dans l'espace du pod : il dit ce que le contrôleur **veut** sur ce pod.
</details>

<details><summary>Indice 2</summary>

Sur le nœud : `sudo crictl pods --name <pod> -q` donne l'identifiant du bac à sable, `sudo crictl inspectp <id> | jq .info.pid` le PID qui porte l'espace réseau du pod, puis `sudo nsenter -t <PID> -n tc qdisc show`. Un `qdisc netem` qui n'appartient à aucune expérience vivante est un reste.
</details>

<details><summary>Indice 3</summary>

Si le finaliseur ne part pas, c'est que le contrôleur n'arrive pas à faire retirer la panne par le `chaos-daemon` : le daemon est-il prêt ? joint-il le runtime ? `kubectl -n chaos-mesh logs` du daemon du nœud et `kubectl -n chaos-mesh get ds chaos-daemon -o yaml` (montages, arguments) répondent. Et qui a changé sa configuration ?
</details>

**Pour aller plus loin** (facultatif) : écris une alerte Prometheus « expérience de chaos active depuis plus de 30 min » à partir des métriques du contrôleur de Chaos Mesh (`chaos_controller_manager_chaos_experiments`) et teste-la avec `promtool test rules`.

---

### M29-E21 — Panne : Terratest laisse des VMs derrière lui  `BF` `★★`

> **Ticket INC-5621** — *De : Karim Benali*
> *(Le détail s'affiche à l'injection : le pipeline Terratest de `vm-debian` échoue par intermittence et `pve01` porte des VMs que personne ne reconnaît.)*

**Objectifs pédagogiques**
- Retrouver des ressources de test orphelines par leurs **étiquettes**, leur plage de VMID et leur état local, sans confondre avec des VMs légitimes.
- Comprendre pourquoi un test d'infrastructure laisse des restes (interruption, délai de `go test`, `defer` non exécuté, destruction en échec) et comment un état local orphelin aggrave le problème.
- Nettoyer en sécurité, puis rendre la récidive improbable (code du test, délai, nettoyeur planifié).

**Prérequis** : M29-E08 ; `lab/bin/check 29 21` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : les VMs de Terratest sont en **2290-2299**, nommées `tt-<suffixe>`, étiquetées `env-m29` et `terratest`, dans le sous-pool Proxmox **`lab/terratest`**, avec une adresse allouée par NetBox (M29-E08). Terratest copie le module dans un répertoire temporaire (`test_structure.CopyTerraformFolderToTemp`) où vit l'état local du test (sous `test/fixtures/vm/` de la copie). Le budget mémoire du lab est serré (PLAN §3.3) : une VM oubliée et démarrée prend 1 Go à tout le monde.

**Injection** : `lab/bin/break 29 21` (3 variantes).

> ⚠️ **Attention** : sur `pve01`, ne détruis **rien** hors de la plage 2290-2299 et hors du sous-pool `lab/terratest`. Avant tout `qm destroy`, montre la VM (nom, étiquettes, note, date de création, disques) et vérifie qu'aucun test n'est en cours (job `terratest:vm-debian` en marche ?). De préférence, détruis avec le jeton `wb-terratest` (M29-E08) : il ne peut rien toucher d'autre.

**Travail demandé**
1. Inventorie : VMs de 2290-2299 (nom, état, étiquettes, pool, note, date de création dans `meta`), pipelines Terratest récents et leur fin, états locaux restés sur le poste qui lance les tests, adresses et VMs `terratest` restées dans NetBox.
2. Explique pourquoi le pipeline échoue par intermittence et ce qui, sur ce lab, transforme un test interrompu en VM oubliée.
3. Nettoie : de préférence avec l'état orphelin quand il est cohérent (`tofu destroy` dans son répertoire), sinon par l'API de Proxmox, VM par VM ; supprime l'état orphelin ensuite.
4. **Prévention** : vérifie et corrige le test (destruction enregistrée par `t.Cleanup` ou `defer` **avant** `InitAndApply`, délais emboîtés d'E08 : attentes du test < `go test -timeout` < `timeout` du job, protection forcée à `false`, nom et étiquettes obligatoires) ; écris `plateforme/tofu-modules/outils/nettoyer-terratest.sh` (lecture par l'API de Proxmox avec le jeton `wb-terratest`, sélection par plage **et** sous-pool **et** étiquette **et** préfixe de nom **et** âge, mode simulation par défaut, journal) et planifie-le (pipeline planifié de `plateforme/tofu-modules`) ; **complète RB-293** (M29-E08) : causes, nettoyeur, ce qui reste dans NetBox.

**Critères de réussite**
- [ ] Aucune VM dans 2290-2299 sur `pve01` ; aucun état Terratest orphelin sur `adm01`.
- [ ] Le test de `vm-debian` enregistre sa destruction avant l'application et le job fixe un délai explicite (`go test -timeout`).
- [ ] `outils/nettoyer-terratest.sh` existe (sélection par étiquette et plage, simulation par défaut) et un pipeline planifié de `plateforme/tofu-modules` l'appelle ; RB-293 est complété (nettoyeur, causes) ; la panne est close.

**Vérification** : `lab/bin/check 29 21`

<details><summary>Indice 1</summary>

`pvesh get /cluster/resources --type vm --output-format json | jq '.[] | select(.vmid >= 2290 and .vmid <= 2299)'` montre état, pool, étiquettes. `qm config <vmid> | grep -E '^(name|tags|meta|onboot)'` donne la date de création (`ctime` dans `meta`). Une VM sans l'étiquette attendue est-elle pour autant légitime ?
</details>

<details><summary>Indice 2</summary>

`go test` a un délai **par défaut** de 10 minutes ; au-delà, il fait paniquer le processus de test : ni `defer` ni `t.Cleanup` ne s'exécutent (d'où l'échéance interne d'E08, plus courte). Une destruction enregistrée **après** un `InitAndApply` qui échoue à mi-chemin ne s'exécute pas non plus (`t.Fatal` n'exécute que ce qui est déjà enregistré). Un job annulé ou un runner redémarré tue le processus : rien ne s'exécute. Cherche les répertoires temporaires de Terratest sur le poste (`find /tmp -name terraform.tfstate -path '*vm-debian*'`).
</details>

**Pour aller plus loin** (facultatif) : donne au nettoyeur une alerte : s'il trouve une VM `terratest` de plus de 2 h, il écrit une métrique dans le collecteur textfile de `node_exporter` de `runner01` et une règle de `mon01` prévient la plateforme.

---

### M29-E22 — Panne : les tests d'infrastructure sont rouges  `BF` `★★`

> **Ticket PLAT-3022** — *De : Nadia Roussel*
> *(Le détail s'affiche à l'injection : la suite Testinfra est rouge sur une VM du socle depuis cette nuit, et tout le monde commence à l'ignorer.)*

**Objectifs pédagogiques**
- Lire un échec de Testinfra comme un **signal de dérive** et non comme un test cassé : trouver ce qui a changé sur la VM, quand, par qui.
- Corriger par Ansible (le rôle, l'inventaire) et non à la main, et vérifier l'idempotence.
- Détecter plus tôt : Ansible en mode vérification planifié, tests ciblés, ce qu'un rôle doit gérer en entier (fichiers « de trop » compris).

**Prérequis** : M29-E04, M29-E10 ; M04 (rôles `base`, `ssh_durci`), M21-E08 (rôle `node_exporter`), M26 (rôle `durcissement`) ; `lab/bin/check 29 22` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : la VM visée est `nbx01` ou `mon01` (liste `WB_M29_E22_HOTES`). Le script vérifie, avant et après l'injection, le verdict de ta suite Testinfra sur cette VM par la commande `WB_M29_TESTINFRA_CMD` (défaut : la suite de `~/src/ansible/tests/infra` lancée depuis `adm01` sur l'hôte) : la panne n'est déclarée que si ta suite passe au rouge. Si aucune dérive n'est vue par ta suite, il te le dit : ta suite est trop pauvre, complète M29-E04 avant de revenir.

**Injection** : `lab/bin/break 29 22` (3 variantes).

**Travail demandé**
1. Lis l'échec (quel test, quelle assertion, quelle valeur obtenue). Décide d'abord : le test a-t-il tort ou la VM ?
2. Sur la VM, trouve la dérive et sa trace (date des fichiers, `journalctl`, historique des paquets ou des unités), sans rien corriger encore. Passe le rôle concerné en `--check --diff` sur la VM : Ansible voit-il la dérive ? S'il ne la voit pas, pourquoi ?
3. Corrige **par Ansible** : si le rôle ne sait pas ramener la VM dans l'état voulu, c'est le rôle qu'il faut compléter (MR dans `plateforme/ansible`), pas la VM qu'il faut retoucher. Rejoue le rôle deux fois (idempotence) et la suite Testinfra.
4. Écris dans ton journal comment la dérive aurait été vue plus tôt (Ansible `--check` planifié, alerte de supervision, test plus précis) et ajoute **un** test Testinfra qui l'aurait vue plus directement si la suite ne l'a attrapée que par un effet de bord.

**Critères de réussite**
- [ ] La VM est revenue dans l'état voulu : chrony synchronisé sur la passerelle du VLAN, `sshd` effectif conforme aux rôles (aucun fichier de `sshd_config.d` non géré), `node_exporter` actif et activé.
- [ ] La suite Testinfra passe sur la VM ; le rôle corrigé ne signale aucun changement à un second passage.
- [ ] La panne est close ; ton journal contient la dérive, sa preuve et la détection proposée.

**Vérification** : `lab/bin/check 29 22`

<details><summary>Indice 1</summary>

Un test d'infrastructure rouge sur **une seule** VM, alors que la même suite est verte ailleurs, désigne presque toujours la VM. `ls -lt --time-style=full-iso` dans le répertoire du service, `systemctl status`, `journalctl -u <service> --since yesterday` et `sudo sshd -T` (configuration effective) disent ce qui a bougé.
</details>

<details><summary>Indice 2</summary>

Un rôle qui pose **ses** fichiers ne voit pas un fichier **de plus** posé à côté par quelqu'un d'autre : `--check` dit « rien à changer » et la dérive reste. Pour un répertoire de type `*.d/`, le rôle doit savoir ce qui est à lui et retirer le reste (lister, comparer, supprimer), ou le test doit vérifier l'état **effectif** plutôt que les fichiers.
</details>

**Pour aller plus loin** (facultatif) : planifie chaque nuit `ansible-playbook --check --diff` sur tout le socle et publie le nombre de tâches « changed » comme métrique (collecteur textfile) ; alerte au-delà de zéro.

---

### M29-E23 — Astreinte : la journée de jeu réveille une vraie faiblesse  `BF` `★★★★`

> **Ticket INC-5623** — *De : Nadia Roussel* — *Copie : Julien Petit, Claire Morel*
> *(Le détail s'affiche à l'injection : la journée de jeu automatique de Karim, prévue pour durer une minute sur la recette, a rendu MédiAgenda indisponible bien plus longtemps.)*

**Objectifs pédagogiques**
- Mener une astreinte complète sur un incident **provoqué par une expérience** : arrêter l'expérience, rétablir, puis enquêter sans s'arrêter à « c'est la faute du chaos ».
- Distinguer le déclencheur (l'expérience), le défaut latent introduit récemment (changement de configuration) et la faiblesse de conception qui les rend dangereux ensemble.
- Rédiger un post-mortem sans reproche qui ouvre des actions sur le système, la détection et le processus.

**Prérequis** : M29-E13 à M29-E16, M29-E20 ; M28-E02 (HPA), M14-E07 (sondes) ; `lab/bin/check 29 23` vert avant l'injection.
**Durée indicative** : 1 h 30 (temps cible : service rétabli en 15 min).

**Contexte technique** : la journée de jeu automatique est un `Workflow` de `chaos-experiences` qui enchaîne des expériences courtes sur la recette ; chacune avait une hypothèse « aucun impact visible ». Les manifestes de MédiAgenda en recette viennent de `mediagenda/deploiement` (overlay `recette`), appliqués par Argo CD. Tu as les SLO de recette (E13), le tableau « Charge k6 » (E14), Loki et les événements du cluster.

**Injection** : `lab/bin/break 29 23` (2 variantes). L'injection prépare la scène, lance la journée de jeu et attend l'incident : compte 5 à 12 minutes.

**Travail demandé**
1. **Rétablir.** Arrête ce qui est encore injecté (RB-294), puis rétablis le service de la recette par le chemin le plus sûr. Note l'heure de rétablissement.
2. **Enquêter.** Chronologie à la minute : début de l'expérience, premiers 5xx, pods non prêts ou redémarrés, retour. Pour chaque étape, la preuve (événements, métriques, journaux). Pourquoi une expérience prévue pour une minute a-t-elle eu un effet plus long, ou plus large ?
3. **Causes.** Trouve le changement récent qui a rendu la recette fragile (auteur, date, intention), et la faiblesse **de conception** de MédiAgenda que l'expérience aurait révélée même sans lui. Corrige le changement par MR ; ouvre un ticket `DEV-` pour la faiblesse de conception, avec la correction proposée (le corrigé fournit un correctif d'application à proposer à l'équipe de Julien).
4. **Post-mortem.** `docs/qualite/post-mortems/AAAA-MM-JJ-INC-5623-*.md` avec le modèle de l'équipe (`modules/00-lab/ressources/M00-E46/modele-post-mortem.md`) : résumé, impact chiffré, chronologie, causes (déclencheur, défaut latent, faiblesse de conception), ce qui a bien marché, actions (système, détection, processus — dont « une journée de jeu automatique vérifie d'abord l'état de la cible »).

**Critères de réussite**
- [ ] Plus aucune expérience active sur la recette ; la journée de jeu automatique est arrêtée ou supprimée.
- [ ] MédiAgenda recette est rétablie : sonde de vivacité sur `/sante`, au moins deux réplicas prêts, budget de redémarrages stable ; le changement fautif est défait par un commit.
- [ ] Le post-mortem INC-5623 est publié avec les trois niveaux de cause ; la panne est close.

**Vérification** : `lab/bin/check 29 23`

<details><summary>Indice 1</summary>

`kubectl -n mediagenda-recette get events --sort-by=.lastTimestamp` et `kubectl -n mediagenda-recette get pods -o wide` (colonnes `RESTARTS`, `READY`) racontent la cascade. Un pod qui redémarre en boucle parce qu'une **dépendance** est absente a une sonde qui regarde trop loin ; un service qui tombe entièrement quand un seul pod disparaît n'avait qu'un pod.
</details>

<details><summary>Indice 2</summary>

`git log -p` sur l'overlay `recette` de `mediagenda/deploiement`, et l'historique de l'Application de la recette dans Argo CD : quelque chose a changé peu avant la journée de jeu. Puis relis le code de `/pret` et la façon dont Kubernetes l'utilise : que se passe-t-il pour **tous** les pods de l'API quand le cache disparaît dix secondes ?
</details>

**Pour aller plus loin** (facultatif) : ajoute à la journée de jeu automatique une étape `StatusCheck` initiale qui refuse de commencer si la cible n'a pas au moins deux pods prêts et un SLO vert, et une vérification continue qui l'interrompt dès trois échecs.

---

### M29-E24 — Sous le capot : comment Chaos Mesh injecte une panne  `LAB` `★★★★`

> **Ticket PLAT-3024** — *De : Karim Benali*
> Tu sais lancer et arrêter des expériences. Maintenant je veux que tu saches ce que Chaos Mesh **fait** sur un nœud : qui appelle qui, quelles règles il pose, où, avec quels privilèges, et comment on le voit sans son tableau de bord. Une page, avec des sorties réelles de **notre** cluster. Le jour où un `chaos-daemon` meurt au mauvais moment, c'est cette page qu'on lira.

**Objectifs pédagogiques**
- Suivre une expérience de l'API au noyau : webhook, contrôleur (`chaos-controller-manager`), objets intermédiaires (`PodNetworkChaos`), appel gRPC au `chaos-daemon` du nœud, entrée dans les espaces de noms du conteneur, commande exécutée.
- Observer sur un nœud : `tc qdisc` (`netem`) dans l'espace réseau d'un pod, `ipset` et chaînes `iptables` `CHAOS-*` pour une partition, processus `stress-ng`/`memStress` rattachés au cgroup du conteneur.
- Lire le cycle de vie d'une expérience : finaliseur, `desiredPhase`, `containerRecords`, événements, retrait.
- Mesurer les privilèges que tout cela exige et en tirer les conséquences de sécurité.

**Prérequis** : M29-E09, M29-E13, M29-E20 ; M12 (espaces de noms, cgroups), M15 (Cilium).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Tout se passe dans **`wb-essais`** (annoté) sur des pods jetables que tu crées : `cible-e24` (un serveur HTTP minimal, image de Harbor) et `client-e24` (une boucle `wget` vers `cible-e24`). Les expériences, elles, se créent dans `chaos-experiences` (VAP `medisphere-chaos-espaces`, M29-E09) et visent `wb-essais`. Aucune expérience sur la recette dans cet exercice.
- Le `chaos-daemon` tourne en `hostPID` et privilégié ; son image contient `tc`, `ipset`, `iptables` (variante *legacy*), `stress-ng`, `memStress`, `nsexec`, `toda`. Sur les nœuds Debian 13, `iptables` est la variante *nft* : ce que tu vois avec l'une ne se voit pas avec l'autre.
- `crictl` sur les nœuds (`sudo crictl inspectp`, `sudo crictl inspect`), `nsenter` (util-linux).

> ⚠️ **Attention** : sur le nœud, tu **observes** ; tu ne modifies rien dans un espace de noms de pod (pas de `tc qdisc del`, pas d'`iptables -F`) tant qu'une expérience vit : tu désynchroniserais le contrôleur et le daemon. Les seules modifications autorisées sont celles d'Ansible et la suppression de tes objets de `wb-essais`.

**Travail demandé**
1. **Préparer** : crée `cible-e24` et `client-e24` dans `wb-essais` (contexte de sécurité `restricted`), mesure la latence du client vers la cible (ligne de base).
2. **Latence** : une `NetworkChaos` `delay` (100 ms) de `client-e24` vers `cible-e24`, 10 min. Suis la chaîne : événements de l'expérience, finaliseurs, `status.experiment.containerRecords`, l'objet `PodNetworkChaos` créé (où ? nommé comment ? que contient-il ?), journaux du contrôleur, journal du `chaos-daemon` du nœud du client (appel reçu, commande). Sur le nœud : PID du bac à sable du client, `tc qdisc show` dans son espace réseau (quel arbre de files, où est le `netem` ?), puis les règles `iptables` (variante *legacy* : chaînes `CHAOS-OUTPUT` et `TC-TABLES-*`) et l'`ipset` de la cible dans le même espace. Comment le noyau sait-il quels paquets passer par la file retardée, et lesquels laisser passer sans délai ?
3. **Partition** : une `NetworkChaos` `partition` (`direction: both`) entre les deux pods, 5 min. Sur le nœud : `ipset list` et chaînes `CHAOS-INPUT`/`CHAOS-OUTPUT` dans l'espace réseau du pod — avec quelle variante d'`iptables` les vois-tu ? Que voit Cilium (`hubble observe`) pendant la partition ?
4. **Stress** : une `StressChaos` (CPU, 1 travailleur, 50 %) sur `cible-e24`, 5 min. Sur le nœud : le processus `stress-ng`, son parent, son cgroup (`/proc/<pid>/cgroup`) comparé à celui du conteneur visé ; ce que montrent `kubectl top pod` et la métrique `container_cpu_usage_seconds_total` du conteneur. Pourquoi les quotas CPU du conteneur s'appliquent-ils au stress ?
5. **Retrait** : supprime chaque expérience et observe le retrait (événements `Recovered`, `containerRecords`, disparition du finaliseur, règles absentes sur le nœud). Puis supprime `cible-e24` **pendant** une expérience de latence : que devient l'enregistrement, que fait le finaliseur ?
6. **Privilèges** : liste ce que le `chaos-daemon` exige (privilégié, `hostPID`, socket du runtime, capacités) et ce qu'un attaquant ferait de son point gRPC (port 31767) ; vérifie qui peut le joindre dans le cluster (politiques réseau de `chaos-mesh`) et propose une restriction.
7. **Rédige** `docs/qualite/sous-le-capot-chaos-mesh.md` : schéma du chemin (API → webhook → contrôleur → `PodNetworkChaos` → gRPC → daemon → `nsexec` → commande), une sortie réelle de `tc qdisc show` avec `netem`, une chaîne `CHAOS-*` réelle, un cgroup de `stress-ng` réel, le cycle de vie du finaliseur, la section privilèges, et trois questions que tu poserais à un candidat.

**Critères de réussite**
- [ ] `sous-le-capot-chaos-mesh.md` décrit `PodNetworkChaos`, gRPC, `netem`, `ipset`/`iptables`, `stress-ng` et cgroup, finaliseur et `containerRecords`, avec au moins une sortie réelle de nœud.
- [ ] Une politique réseau de l'espace `chaos-mesh` limite qui joint le port gRPC du `chaos-daemon` (au contrôleur seulement).
- [ ] À la fin : aucun pod `*-e24` dans `wb-essais`, aucune expérience `*-e24` dans `chaos-experiences`.

**Vérification** : `lab/bin/check 29 24`

<details><summary>Indice 1</summary>

L'objet `PodNetworkChaos` vit dans l'espace du **pod visé** et porte son nom ; ses champs `spec.tcs`, `spec.ipsets`, `spec.iptables` sont l'état voulu, et son statut l'état appliqué. Le contrôleur fusionne dans cet objet toutes les expériences qui touchent le même pod : c'est lui qui est ensuite envoyé au daemon.
</details>

<details><summary>Indice 2</summary>

Pour voir les règles d'une partition dans l'espace réseau du pod depuis le nœud : `sudo nsenter -t <PID> -n iptables-legacy -S` et `sudo nsenter -t <PID> -n ipset list` (si `ipset` n'est pas installé sur le nœud, exécute-le depuis le pod `chaos-daemon` du nœud : il partage l'espace de PID de l'hôte). Pour le stress, `ps -eo pid,ppid,cgroup,cmd | grep stress-ng` sur le nœud.
</details>

**Pour aller plus loin** (facultatif) : lis `pkg/chaosdaemon/tc_server.go` et `pkg/bpm/bpm.go` du dépôt de Chaos Mesh (étiquette `v2.8.6`) et retrouve, ligne par ligne, la commande que tu as vue sur le nœud.
