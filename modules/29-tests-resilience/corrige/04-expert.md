# Module 29 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. Avec l'outillage de test, deux réflexes évitent la moitié des fausses pistes : **prouver que le filet attrape encore** (un cas de référence qui doit échouer) avant de croire un vert, et **vérifier sur le nœud** ce que l'API prétend (règles `tc`/`iptables` réellement posées, VMs réellement présentes).

Les scripts d'injection sont dans `corrige/pannes/` : `_m29-commun.sh` contient les fonctions partagées — état local (`~/.local/state/workbook/M29-EXX/`), **commits de Lucas** en plusieurs fichiers par l'API de GitLab (auteur « Lucas Martin », marqueur `M29-EXX`, poussée directe sur `main` si elle est permise, sinon MR fusionnée après son pipeline ; annulation par commit inverse **seulement** si chaque fichier est encore exactement dans l'état injecté), lecture et retrait d'un `netem` dans l'espace réseau d'un pod depuis son nœud (`crictl inspectp` → PID du bac à sable → `nsenter -n tc`), suppression d'une expérience avec forçage documenté du finaliseur en dernier recours, mesure du p95 de la recette. Chaque injection **vérifie son effet** (plan plus refusé, `netem` présent, VMs créées, suite Testinfra rouge, fenêtre sans API prête) ; une variante sans effet sur ton lab est défaite et la suivante est essayée.

> **Remarque sur les traces** : le commit porte l'auteur « Lucas Martin », mais c'est **ton** jeton d'administration qui l'a poussé (le *committer* et le journal d'audit de GitLab le montrent) ; les gestes sur le cluster sont faits avec ton kubeconfig. En production, ce serait l'identité de Lucas : c'est pour cela que chacun a un compte nominatif.

**Validé hors du lab** : logique d'injection d'E19 (variantes 1 et 2) rejouée à l'harmonisation sur les politiques du corrigé de M29-E03 avec OPA 1.21.3 et conftest 0.71.1, contexte `socle` compris (`opa test rego/tofu rego/donnees` reste vert, 24/24 avec les politiques actuelles de M29-E03, le plan de référence n'est plus refusé ; variante 1 sans effet avec `--all-namespaces`), puis rejouée de bout en bout à la relecture contre un faux GitLab (dépôts git locaux) : commit de Lucas, étiquette `v1.4.1`, montée de `politiques_ref` dans `plateforme/infra`, annulation par commits inverses et retrait de l'étiquette, réparation de l'apprenant respectée ; le job des exemples du composant (`tests_rego`) rejoué sur chaque variante : rouge en variante 1 (d'où la poussée directe), vert en variante 2 (exemples renommés aussi), et le job `non-regression-plans` d'E19 attrape la variante 2 ; surcharge `allow_failure` de `.plan` (variante 3) et lecture de `!reference` par yq 4.47 ; conftest renvoie **0** et « 0 tests » quand l'espace demandé ne contient aucune règle (constaté) ; job de non-régression des plans rejoué localement ; correctif `/pret` de MédiAgenda (pytest : 28 tests réussis, `ruff check`, `ruff format --check`, `git apply --check` sur le code de référence) ; `chaos-daemon` : SIGKILL du `container-kill`, `iptables-legacy`, chaînes `CHAOS-INPUT/OUTPUT` et `TC-TABLES-*` avec `CLASSIFY`, arbre `prio`/`sfq`/`netem` pour une latence ciblée, `stress-ng` lancé par `nsexec` dans l'espace de PID puis rattaché au cgroup du conteneur (code de la 2.8.6) ; manifestes validés par kubeconform `-strict` ; `shellcheck -x` et `bash -n` sur tous les scripts.

**Points non testés en conditions réelles** (signale tes retours) :
- délais entre un commit, la synchronisation d'Argo CD, le canary d'Argo Rollouts sur la recette (E23 attend jusqu'à 15 min) et la mise à l'échelle de l'HPA à une réplique (E23 v2, fenêtre de stabilisation) ;
- comportement du `chaos-daemon` 2.8 démarré avec un `--runtime-socket-path` inexistant (E20 v2 : plantage au démarrage ou erreurs à chaque appel — dans les deux cas le retrait échoue) et levée du finaliseur après réparation ;
- commande Testinfra par défaut de E22 (`--hosts=ansible://…` avec l'inventaire de `ansible.cfg`) : règle `WB_M29_TESTINFRA_CMD` si ta suite se lance autrement ;
- `qm create` sans disque avec `--pool lab/terratest` (pool imbriqué) et `--tags "env-m29;terratest"` sur Proxmox VE 9 (E21) ; emplacement exact de l'état laissé par `CopyTerraformFolderToTemp` de Terratest 1.0 (supposé `/tmp/TestVmDebian<n>/vm-debian/test/fixtures/vm/`) ;
- détection des espaces de conftest de ta CI (E19) : si ton composant passe les espaces autrement (variable, fichier), fixe `WB_M29_CONFTEST_ARGS` ;
- appli `busybox` `time -p` et `httpd` dans les pods d'E24.

---

### M29-E19 — Panne : un plan dangereux passe la CI

**Démarche de diagnostic**

*Symptômes* : le plan de référence n'est plus refusé « par la CI », sans que personne n'ait touché au plan.

*Hypothèses, par étage* : (a) le job de validation ne compte plus (statut ignoré) ; (b) il tourne mais n'évalue pas les règles (espaces, chemin des politiques) ; (c) il évalue les règles mais elles ne se déclenchent plus (logique, chemin d'`input`) ; (d) le plan n'est pas celui qu'on croit ; (e) la CI ne lit pas les politiques qu'on croit (étiquette `politiques_ref`).

*Commandes, dans l'ordre*

```
admin@adm01:~/src/infra$ git log -3 --format='%h %an %ar %s' -- .gitlab-ci.yml
admin@adm01:~/src/infra$ grep -n 'politiques_ref' .gitlab-ci.yml          # l'étiquette que la CI clone
      politiques_ref: v1.4.1                                               ← v1, v2 : montée par Lucas (numéro selon tes étiquettes)
admin@adm01:~/src/politiques$ git fetch --tags && git tag -n1 --sort=-v:refname | head -3
admin@adm01:~/src/politiques$ git log -5 --format='%h %an %ar %s' -- rego/
admin@adm01:~/src/politiques$ git checkout -q v1.4.1 && grep -rh '^package ' rego/tofu/ | sort | uniq -c
# Les arguments réels du job de plan (.validation:conftest-plan du composant, M29-E10) :
admin@adm01:~/src/ci-templates$ grep -n -- '--namespace\|--all-namespaces\|--data\|conftest test' templates/validation/template.yml
admin@adm01:~/src/politiques$ echo '{"contexte": {"etat": "socle", "etiquettes_mr": []}}' > /tmp/contexte-socle.json
admin@adm01:~/src/politiques$ conftest test --no-color -p rego/tofu --namespace tofu --data rego/donnees \
    --data /tmp/contexte-socle.json ~/DevOpsPrivateCloud/modules/29-tests-resilience/ressources/E19-plan-dangereux/plan-dangereux.json
0 tests, 0 passed, 0 warnings, 0 failures, 0 exceptions          ← variante 1 : rien n'est évalué
14 tests, 14 passed, 0 warnings, 0 failures, 0 exceptions        ← variante 2 : évalué, rien ne se déclenche
admin@adm01:~/src/politiques$ conftest test --no-color -p rego/tofu --all-namespaces --data rego/donnees --data /tmp/contexte-socle.json <plan>
admin@adm01:~/src/politiques$ opa eval -d rego/tofu -d rego/donnees -d /tmp/contexte-socle.json -i <plan> 'data' --format pretty | head -30
admin@adm01:~/src/politiques$ jq 'keys' <plan>                     # "resource_changes" … pas "resource_change"
```

(Le nombre de « tests » dépend de tes règles ; ceux-ci sont ceux du corrigé de M29-E03. Sans `--data` du contexte, la règle « contexte absent » refuse le plan **à elle seule** : on croit le filet intact alors qu'aucune autre règle ne se déclenche. Évalue les politiques **à l'étiquette** que lit la CI (`git checkout <politiques_ref>`), pas ta copie de travail ; reviens ensuite sur `main`.)

Variante 3 : dans GitLab, le dernier pipeline de la MR de démonstration de `plateforme/infra` est « passed » avec des jobs `plan:*` orange (« allowed to fail ») dont le journal dit « Plan REFUSÉ par les politiques… » ; `conftest` en local refuse bien le plan.

*Cause racine, par variante*

| Variante | Cause | Preuve |
|---|---|---|
| 1 | Commit de Lucas poussé **directement** sur `main` de `plateforme/politiques` : le paquet des règles `rego/tofu/` renommé `brouillon.tofu` (règles **et** tests, `import data.tofu` compris), puis étiquette `v1.4.1` et commit de Lucas dans `plateforme/infra` qui monte `politiques_ref` en `v1.4.1`. `opa test` reste vert ; le job de plan lance `conftest test --namespace tofu` : aucune règle dans cet espace, conftest réussit en silence (« 0 tests »). Le pipeline de `main` des politiques est **rouge** depuis (le job des exemples du composant attend un refus de `plan-envs-m29-defauts.json`) : personne ne l'a regardé | `git log -p rego/`, `grep '^package'` à l'étiquette, sortie « 0 tests », pipeline rouge des politiques |
| 2 | Commit de Lucas (poussé sur `main`, ou par une MR dont le pipeline est vert) : `resource_changes` → `resource_change` dans les règles, **dans les entrées simulées des tests et dans les plans d'exemple** de `rego/exemples/`, puis étiquette `v1.4.1` et montée de `politiques_ref` dans `plateforme/infra`. Les tests et les exemples passent (ils ne sont plus de vrais plans) ; sur un vrai plan, `input.resource_change` n'existe pas : `some rc in input.resource_change` ne produit rien, aucune règle ne se déclenche | `git log -p`, `opa eval … 'data'` (ensembles `deny` vides), `jq 'keys'` sur un vrai plan |
| 3 | Commit de Lucas dans `plateforme/infra/.gitlab-ci.yml` : `allow_failure: true` ajouté au modèle caché `.plan` (M05), que tous les jobs `plan:*` étendent et qui appelle `!reference [.validation:conftest-plan, script]` (« le temps de corriger les faux positifs ») : le job de plan échoue sur le refus, le pipeline passe | `git log -p .gitlab-ci.yml`, jobs `plan:*` orange |

*Correctif* : revert du commit fautif par MR (`git revert <sha>`) dans **chaque** dépôt touché. Variantes 1 et 2 : le plus sûr est de défaire la montée de `politiques_ref` dans `plateforme/infra` (la CI relit aussitôt `v1.4.0`, saine), puis de défaire le commit de `plateforme/politiques` ; publier ensuite une étiquette corrigée (`v1.4.2`) si d'autres changements doivent sortir. On ne déplace jamais une étiquette publiée (`v1.4.1` reste fautive : ne plus la consommer). Puis vérification : le plan est refusé **avec les arguments et l'étiquette de la CI**, `lab/bin/check 29 19`, `lab/bin/break 29 19 --annuler` pour clore (il retire l'étiquette `v1.4.1` posée par la panne si plus aucun projet ne la lit).

*Prévention* (fichiers dans [`fichiers/M29-E19/politiques/`](fichiers/M29-E19/politiques/)) :
- plans de référence versionnés ([`tests/plans/`](fichiers/M29-E19/politiques/tests/plans/)) : un plan qui **doit** être refusé, un qui doit passer ;
- job [`non-regression-plans`](fichiers/M29-E19/politiques/.gitlab-ci.extrait-E19.yml) : conftest avec **les mêmes arguments** que `.validation:conftest-plan` (`--namespace tofu`, `--data rego/donnees`, contexte `socle` versionné dans `tests/plans/contexte-socle.json`) ; échec si le plan dangereux n'est pas refusé (code 1 **et** au moins un `FAIL` : un code 2 d'erreur d'analyse ou un 127 « commande introuvable » ne sont pas des refus) ; échec si un paquet de règles n'est pas dans les espaces évalués (rend la variante 1 impossible) ; la variante 2 est attrapée parce que le plan est **réel** ;
- [`CODEOWNERS`](fichiers/M29-E19/politiques/CODEOWNERS) sur `rego/tofu/`, `tests/plans/`, `.gitlab-ci.yml` — en GitLab Free, l'approbation obligatoire des propriétaires est Premium : le garde-fou réel reste « fusion réservée aux Maintainers » + ce job ;
- une étiquette de `plateforme/politiques` ne se publie que sur un `main` au pipeline **vert** (job `non-regression-plans` compris), et une montée de `politiques_ref` dans un projet consommateur passe par une MR qui cite ce pipeline (variante 1 : l'étiquette a été posée sur un `main` rouge) ;
- dans `plateforme/infra` : aucune surcharge `allow_failure` d'un job de validation ni de `.plan`/`plan:*` (le check le vérifie) ; une exception temporaire se fait par une règle `rules:` datée dans le composant, revue, pas par une surcharge silencieuse.

**Pièges classiques**
- Tester « avec sa commande habituelle » (`--all-namespaces`, sans le contexte, depuis un autre dossier, ou sur `main` alors que la CI lit une étiquette) : on ne reproduit pas la CI.
- Corriger `main` des politiques et s'arrêter là : la CI de `plateforme/infra` lit toujours l'étiquette fautive tant que `politiques_ref` n'a pas changé.
- Conclure « les tests passent, donc les règles marchent » : les tests unitaires ne voient que leur entrée.
- Corriger en ajoutant `--all-namespaces` dans le composant sans comprendre : c'est un choix valable (un dossier qui ne contient que des règles actives), mais il change ce qui est évalué pour **tous** les projets ; décision écrite.
- Laisser le job en `allow_failure` « temporairement » : une permission qui n'expire pas.

---

### M29-E20 — Panne : une expérience de chaos ne s'arrête plus

**Démarche de diagnostic**

*Symptômes* : recette lente (au moins +300 ms par appel : chaque paquet émis par l'API est retardé) alors que l'expérience est « supprimée » (v1), « en suppression » (v2) ou « en pause » (v3).

*Hypothèses* : (a) quelque chose **recrée** l'expérience ; (b) quelque chose **empêche** son retrait ; (c) l'expérience n'est pas dans l'état qu'on croit (pause mal posée) ; (d) la lenteur ne vient pas du chaos.

*Commandes, dans l'ordre*

```
admin@adm01:~$ for t in $(kubectl api-resources --api-group=chaos-mesh.org -o name); do kubectl get "$t" -A --no-headers 2>/dev/null | sed "s|^|$t |"; done
networkchaos.chaos-mesh.org chaos-experiences controle-latence-x7k2q …         ← v1 : un enfant
schedules.chaos-mesh.org chaos-experiences controle-latence …                   ← v1 : son parent
networkchaos.chaos-mesh.org chaos-experiences diagnostic-reseau …              ← v3 : « en pause » d'après Lucas
admin@adm01:~$ kubectl -n chaos-experiences get networkchaos diagnostic-reseau -o jsonpath='{.metadata.annotations}{"\n"}{.status.experiment.desiredPhase}{"\n"}'
{"chaos-mesh.org/pause":"true", …}                                                ← v3 : mauvaise clé
Run                                                                               ← v3 : le contrôleur ne la voit pas en pause
admin@adm01:~$ kubectl -n mediagenda-recette get podnetworkchaos -o yaml | yq '.items[] | [.metadata.name, .spec.tcs[].source]'
admin@adm01:~$ kubectl -n chaos-experiences get networkchaos diagnostic-latence -o jsonpath='{.metadata.deletionTimestamp} {.metadata.finalizers}{"\n"}'
2026-11-04T09:12:31Z ["chaos-mesh/records"]                                        ← v2
admin@adm01:~$ kubectl -n chaos-mesh get pods -l app.kubernetes.io/component=chaos-daemon
admin@adm01:~$ kubectl -n chaos-mesh logs <daemon> --tail=20                     ← v2 : connexion au socket impossible
admin@adm01:~$ kubectl -n chaos-mesh get ds chaos-daemon -o jsonpath='{.spec.template.spec.containers[0].args}'
[… "--runtime-socket-path","/host-run/containerd-ancien.sock" …]
admin@k8s-w02:~$ pid=$(sudo crictl inspectp "$(sudo crictl pods --namespace mediagenda-recette --name '^mediagenda-…$' -q)" | jq .info.pid)
admin@k8s-w02:~$ sudo nsenter -t "$pid" -n tc qdisc show dev eth0
qdisc netem 1: root refcnt 2 limit 1000 delay 300ms  20ms
```

*Cause racine, par variante*

| Variante | Cause | Ce qui le prouve | Correctif |
|---|---|---|---|
| 1 | `Schedule` `controle-latence` (`*/5`, `Forbid`) qui embarque une latence de 90 min ; Lucas a supprimé l'**enfant**, le `Schedule` en a recréé un au tick suivant (`Forbid` n'empêche que le chevauchement) | `ownerReferences` et étiquette `managed-by: controle-latence` de l'enfant ; événements `Spawned` du Schedule | pause puis suppression du **Schedule** (ses enfants partent avec lui) |
| 2 | Commit de Lucas dans `plateforme/gitops` (`valeurs/chaos-mesh/values.yaml`) : `chaosDaemon.socketPath: /run/containerd/containerd-ancien.sock` → le chart monte `/run/containerd` et passe `--runtime-socket-path /host-run/containerd-ancien.sock` : le nouveau daemon ne joint plus containerd et ne démarre pas. La mise à jour progressive du DaemonSet (`maxUnavailable: 1` par défaut) **s'arrête au premier pod** : un seul nœud a perdu son daemon, les autres tournent encore avec l'ancienne configuration. Le retrait réussit sur les pods des autres nœuds et échoue sur ceux de ce nœud : le finaliseur reste, le `netem` reste là seulement (une partie des requêtes est lente) | arguments du DaemonSet, `kubectl -n chaos-mesh get pods -l app.kubernetes.io/component=chaos-daemon -o wide` (un pod en échec, sur le nœud de l'API encore ralentie), journaux du daemon, `git log -p valeurs/chaos-mesh/` | revert par MR, attendre les daemons prêts : le contrôleur réessaie, retire, lève le finaliseur — **sans** forçage |
| 3 | Lucas a « mis en pause » `diagnostic-reseau` avec l'annotation `chaos-mesh.org/pause: "true"` (le préfixe de l'annotation des **espaces**, `chaos-mesh.org/inject`) au lieu de `experiment.chaos-mesh.org/pause` : le contrôleur l'ignore, la phase désirée reste `Run` | annotations de l'objet, `status.experiment.desiredPhase: Run`, condition `Paused` à `False` | vraie pause (`experiment.chaos-mesh.org/pause=true`) puis suppression ; retirer la fausse annotation |

*Correctif commun* : vérifier ensuite **sur le nœud** que chaque pod de l'API n'a plus de `netem`, puis la mesure (p95 < 250 ms). Si un `netem` reste sans aucune expérience vivante : retrait manuel (`nsenter … tc qdisc del dev eth0 root`, ou redémarrage du pod), et explication écrite.

*Prévention* : [`RB-297`](fichiers/M29-E20/medisphere/docs/qualite/runbooks/RB-297-experience-qui-ne-s-arrete-pas.md) ; règle « jamais d'expérience hors de `chaos-experiences` » déjà technique (VAP `medisphere-chaos-espaces`, M29-E09) ; contrôle de la pause par l'état et non par l'annotation (`chaos-arret.sh` affiche les enregistrements encore `Injected` après la pause ; `desiredPhase` dit si la pause est prise) ; revue des MR des valeurs de Chaos Mesh ; alerte « expérience active > 30 min » ; `Schedule` toujours en pause hors observation.

**Pièges classiques**
- Forcer le finaliseur d'emblée (v2) : l'objet disparaît, la latence reste, et on a perdu la trace de ce qu'il fallait retirer.
- Redémarrer les daemons sans corriger les valeurs : Argo CD remet la mauvaise configuration.
- Croire une annotation sur parole (v3) : c'est l'état (`desiredPhase`, condition `Paused`) qui dit si l'expérience est en pause, pas la présence d'un mot « pause ».
- Chercher une expérience « cachée » dans un autre espace : la VAP `medisphere-chaos-espaces` (M29-E09) l'interdit ; vérifie plutôt ce que contiennent les `PodNetworkChaos` des pods visés.
- Supprimer les enfants en boucle (v1) : le parent gagne toujours.

---

### M29-E21 — Panne : Terratest laisse des VMs derrière lui

**Démarche de diagnostic**

*Symptômes* : pipeline Terratest intermittent (VMID déjà pris), VMs `tt-*` inconnues sur `pve01`.

*Commandes, dans l'ordre*

```
root@pve01:~# pvesh get /cluster/resources --type vm --output-format json \
    | jq -r '.[] | select(.vmid >= 2290 and .vmid <= 2299) | [.vmid, .name, .status, .pool, .tags] | @tsv'
2298	tt-3fa21c	stopped	lab/terratest	env-m29;terratest
2299	tt-9b07e4	stopped	lab/terratest	env-m29;terratest
root@pve01:~# qm config 2298 | grep -E '^(name|tags|meta|onboot|protection|description)'
description: Terratest M29-E08 (poste) : VM jetable, détruite par le test. Orpheline ? RB-293.
meta: creation-qemu=…,ctime=1761811234
onboot: 1                                                   ← v1
protection: 1                                               ← v3
admin@adm01:~$ find /tmp -maxdepth 6 -name terraform.tfstate -path '*vm-debian*'
/tmp/TestVmDebian184467044/vm-debian/test/fixtures/vm/terraform.tfstate
/tmp/TestVmDebian093517201/vm-debian/test/fixtures/vm/terraform.tfstate
admin@adm01:~$ jq -r '.resources[].instances[].attributes | [.vm_id, .name, .pool_id] | @tsv' /tmp/TestVmDebian*/vm-debian/test/fixtures/vm/terraform.tfstate
```

Puis l'historique des jobs `terratest:vm-debian` (annulés ? arrêtés au délai ?), la CI (`go test -timeout`, `timeout` du job, `interruptible`), le test (destruction enregistrée avant `InitAndApply` ?) et la fixture (étiquettes, `protection`). NetBox : ici, rien (la panne n'y écrit pas) ; un vrai test interrompu y laisserait l'adresse allouée (RB-293 §3).

*Cause racine, par variante*

| Variante | Ce qui a laissé les VMs | Particularité |
|---|---|---|
| 1 | test tué avant sa destruction : job annulé, runner redémarré, ou `go test` arrivé à son délai (panique : ni `t.Cleanup` ni `defer`) | une VM en `onboot: 1` : elle démarrera au prochain démarrage de `pve01` et prendra 1 Go au budget du profil |
| 2 | même cause | étiquette `terratest` **absente** (seulement `env-m29`) : un nettoyage par étiquette seule ne les voit pas ; elles restent identifiables par plage, sous-pool et préfixe de nom |
| 3 | destruction refusée : `protection: 1` sur les VMs (la fixture ne forçait pas `protection = false`) | `tofu destroy` et `qm destroy` échouent tant que la protection est là |

Le lab ne garde pas le journal d'un « vrai » job pour cette panne : la cause se déduit des indices (VMs arrêtées sans disque, états restés dans `/tmp`, `onboot`, étiquettes, protection) ; dis dans ton journal ce qui la confirmerait sur un vrai pipeline (statut `canceled`, `panic: test timed out`).

*Correctif* : nettoyage par l'état si cohérent (`tofu destroy` dans le dossier de la fixture de la copie temporaire, identifiants du test dans l'environnement), sinon VM par VM avec le jeton `wb-terratest` après les avoir montrées (protection levée, arrêt, destruction avec purge), puis suppression des dossiers temporaires. Clore : `lab/bin/break 29 21 --annuler` (il ne détruit que des VMs portant encore le nom **et** la date de création notés à l'injection).

*Prévention* : test ([extrait](fichiers/M29-E21/tofu-modules/vm-debian/test/vm_debian_test.go.extrait-E21)) — celui d'E08 enregistre déjà sa destruction par `t.Cleanup` **avant** `InitAndApply` et borne ses attentes par une échéance plus courte que `go test -timeout` ; fixture ([extrait](fichiers/M29-E21/tofu-modules/vm-debian/test/fixtures/vm/main.tf.extrait-E21)) — sous-pool, étiquettes, `demarrage_auto = false` et **`protection = false`** imposés ; CI ([extrait](fichiers/M29-E21/tofu-modules/.gitlab-ci.extrait-E21.yml)) — délais emboîtés d'E08 (`go test -timeout 35m`, `timeout: 40m`, `interruptible: false`, `resource_group: terratest`) et job planifié `nettoyage-terratest` sur `runner01` ; nettoyeur [`outils/nettoyer-terratest.sh`](fichiers/M29-E21/tofu-modules/outils/nettoyer-terratest.sh) — API de Proxmox avec le jeton `wb-terratest`, plage **et** sous-pool **et** préfixe **et** âge, étiquette contrôlée et signalée, simulation par défaut, code 3 s'il trouve des orphelines (le pipeline planifié échoue et prévient) ; [`RB-293`](fichiers/M29-E21/medisphere/docs/qualite/runbooks/RB-293-vms-de-test-orphelines.md) complété (causes, nettoyeur, NetBox) — une seule fiche pour les VMs de test, écrite en E08 et complétée ici.

**Pièges classiques**
- Détruire « tout ce qui s'appelle tt- » sans vérifier qu'aucun test ne tourne.
- Nettoyer par étiquette seule (v2) ou par nom seul (une VM légitime pourrait commencer par `tt`) : combiner les critères.
- Détruire en root sur `pve01` alors que le jeton `wb-terratest` aurait refusé une erreur de VMID.
- Supprimer l'état orphelin **avant** de s'en servir pour détruire.
- Oublier NetBox : une adresse allouée et jamais rendue finit par épuiser la plage SANDBOX.
- Destruction enregistrée après `InitAndApply` : rassurant à la lecture, inutile si l'application échoue.

---

### M29-E22 — Panne : les tests d'infrastructure sont rouges

**Démarche de diagnostic**

*Symptômes* : suite Testinfra rouge sur **une** VM (`nbx01` ou `mon01`), verte ailleurs ; « relancer » ne change rien.

*Hypothèses* : la VM a dérivé (le test a raison) ; le test est flou (dépend d'un délai, d'un ordre) ; l'environnement de test a changé (inventaire, version de Testinfra).

*Commandes, dans l'ordre*

```
admin@adm01:~/src/ansible$ uv run pytest tests/infra -q --hosts=ansible://nbx01 2>&1 | tail -20      # quel test, quelle valeur
admin@adm01:~$ ssh nbx01 'chronyc -n tracking | head -3; chronyc -n sources'                          # v1
admin@adm01:~$ ssh nbx01 'sudo sshd -T | grep -E "x11forwarding|allowtcpforwarding|maxauthtries"; ls -l --time-style=full-iso /etc/ssh/sshd_config.d/'   # v2
admin@adm01:~$ ssh nbx01 'systemctl status node_exporter --no-pager; systemctl is-enabled node_exporter; journalctl -u node_exporter --since yesterday | tail'  # v3
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/socle-base.yml --limit nbx01 --check --diff   # Ansible voit-il la dérive ?
```

*Cause racine, par variante*

| Variante | Dérive | Ansible `--check` la voit ? | Correctif par Ansible |
|---|---|---|---|
| 1 | `/etc/chrony/chrony.conf` retouché à la main : source `10.10.20.254` (inexistante), chrony plus synchronisé (`Leap status : Not synchronised`) | **oui** : le template du rôle `base` diffère | rejouer le rôle `base` (`--tags` du temps ou `--limit nbx01`) ; deuxième passage : aucun changement |
| 2 | `/etc/ssh/sshd_config.d/00-debogage.conf` posé à la main (lu **avant** `00-durcissement.conf` et `01-ssh-durci.conf`) : `X11Forwarding yes`, `AllowTcpForwarding yes`, `MaxAuthTries 10` | **non** : le rôle ne gère que **ses** fichiers ; un vrai passage échoue sur l'`assert` de `ssh_durci` (configuration effective) sans corriger | **compléter le rôle** `ssh_durci` : il possède le répertoire ([tâches](fichiers/M29-E22/ansible/roles/ssh_durci/tasks/fichiers-inconnus.yml), [défauts](fichiers/M29-E22/ansible/roles/ssh_durci/defaults/main.extrait-E22.yml)) — liste des fichiers connus, sauvegarde puis retrait des autres, rechargement |
| 3 | `node_exporter` arrêté et désactivé (`systemctl disable --now`) | **oui** : `state: started`, `enabled: true` du rôle `node_exporter` | rejouer le rôle |

Dans les trois cas, la trace : date des fichiers, journal systemd (`Stopped node_exporter…`, `Reloading ssh`), commentaire laissé dans le fichier.

*Prévention et détection plus tôt* : tests de l'**état effectif** ([`test_derive_m29.py`](fichiers/M29-E22/ansible/tests/infra/test_derive_m29.py) : fichiers inconnus de `sshd_config.d`, `sshd -T`, synchronisation de chrony sur une source du lab, `node_exporter`) ; `ansible-playbook --check --diff` planifié chaque nuit sur le socle avec le nombre de tâches « changed » publié comme métrique ; alerte de `mon01` sur `up == 0` (v3) et sur `node_timex_sync_status == 0` (v1).

**Pièges classiques**
- « C'est un test flou, je relance » : trois relances rouges identiques ne sont pas un hasard.
- Corriger à la main sur la VM : le prochain écart passera inaperçu de la même façon, et rien ne dit que la correction est conforme au rôle.
- Ajouter le fichier inconnu à la liste des fichiers connus pour « faire passer » le test.
- Modifier le test pour qu'il accepte la valeur dérivée.

---

### M29-E23 — Astreinte : la journée de jeu réveille une vraie faiblesse

**Démarche de diagnostic**

*Symptômes* : après une journée de jeu automatique annoncée « sans impact », plus aucun pod prêt de l'API de recette pendant plusieurs minutes, puis des redémarrages (v1) ou une indisponibilité au moment de la perte d'une API (v2).

*Ordre de travail* : **arrêter** (RB-294 : le Workflow et ses enfants, vérifier qu'il ne reste rien d'injecté) → **rétablir** (si des pods sont en `CrashLoopBackOff`, l'attente exponentielle se termine seule une fois la dépendance revenue ; le chemin le plus sûr est d'attendre ou de supprimer les pods pour repartir sans attente — jamais de modification à la main du Deployment, Argo CD la défait) → **enquêter** → **corriger par Git** → **écrire**.

*Commandes, dans l'ordre*

```
admin@adm01:~$ kubectl -n chaos-experiences get workflow journee-de-jeu-auto -o yaml | yq '.metadata.annotations, .status.conditions'
admin@adm01:~$ kubectl -n mediagenda-recette get events --sort-by=.lastTimestamp | tail -40
… Warning  Unhealthy  pod/mediagenda-…  Liveness probe failed: HTTP probe failed with statuscode: 503     ← v1
… Normal   Killing    pod/mediagenda-…  Container api failed liveness probe, will be restarted
admin@adm01:~$ kubectl -n mediagenda-recette get pods -l app.kubernetes.io/component=api -o wide        # RESTARTS (v1), un seul pod (v2)
admin@adm01:~$ kubectl -n mediagenda-recette get pod <pod> -o jsonpath='{.spec.containers[0].livenessProbe}'
admin@adm01:~$ kubectl -n mediagenda-recette get hpa -o wide                                            # MINPODS 1 (v2)
admin@adm01:~/src/mediagenda-deploiement$ git log -p -3 -- overlays/recette/kustomization.yaml
```

*Les trois niveaux de cause*

| Niveau | Variante 1 | Variante 2 |
|---|---|---|
| Déclencheur (voulu) | partition API ↔ Valkey 45 s + `pod-kill` d'une API | `pod-kill` d'une API, puis `container-kill` de Valkey |
| Défaut latent (changement récent) | `patches` de l'overlay recette : vivacité sur **`/pret`** → la coupure du cache fait **redémarrer** toutes les API (3 échecs de vivacité), puis `CrashLoopBackOff` : le retour du service suit le retour du cache **avec retard** | `patches` de l'overlay recette : `minReplicas: 1` de l'HPA → à charge faible, une seule API ; le `pod-kill` la supprime : aucun pod prêt le temps que le remplaçant démarre |
| Faiblesse de conception | `/pret` exige Valkey : sans le défaut latent, l'expérience aurait quand même rendu la recette indisponible pendant la coupure | idem : le `container-kill` de Valkey sort tous les pods du Service le temps du redémarrage du cache |

*Correctif* : revert du commit de Lucas par MR dans `mediagenda/deploiement` ; vérifier sonde de vivacité sur `/sante`, `minReplicas` ≥ 2, deux pods prêts ; ticket `DEV-3013` à l'équipe de Julien avec le correctif proposé : [`correctif-pret.diff`](fichiers/M29-E23/mediagenda-api/correctif-pret.diff) (fonction [`pret`](fichiers/M29-E23/mediagenda-api/src/mediagenda/app.pret.extrait.py) : 503 seulement si PostgreSQL manque, statut `degrade` si seul Valkey manque ; [tests](fichiers/M29-E23/mediagenda-api/tests/test_api.pret.extrait.py)). Clore la panne : `lab/bin/break 29 23 --annuler`.

*Post-mortem* : [`2026-11-05-INC-5623-journee-de-jeu-recette.md`](fichiers/M29-E23/medisphere/docs/qualite/post-mortems/2026-11-05-INC-5623-journee-de-jeu-recette.md).

**Explications**
- **Vivacité ≠ disponibilité** (M14-E07) : la vivacité répond à « faut-il tuer ce processus ? », la disponibilité à « faut-il lui envoyer du trafic ? ». Une dépendance absente ne se répare pas en redémarrant l'application ; un redémarrage de masse ajoute une tempête de reconnexions au retour de la dépendance.
- **`CrashLoopBackOff`** : attente de 10 s, 20 s, 40 s… (plafond 5 min) entre deux redémarrages d'un conteneur qui échoue ; une panne de 45 s peut coûter plusieurs minutes.
- **Le correctif de `/pret` ne suffit pas sous partition** : une partition **perd** les paquets au lieu de les refuser ; `ping()` vers Valkey attend alors son `socket_timeout`/`socket_connect_timeout` (2 s dans `cache.py`) avant d'échouer, et `/pret` répond en plus de 2 s. Avec `timeoutSeconds: 2` sur la sonde de disponibilité (M14), la sonde échoue quand même et les pods sortent du Service. Le ticket `DEV-3013` doit donc aussi demander un délai de ping de Valkey nettement plus court que celui de la sonde (ou une sonde à `timeoutSeconds: 3` et plus) ; à vérifier en rejouant `03-partition-valkey.yaml` (M29-E13) avec le correctif. Après un `container-kill` de Valkey, la connexion est refusée tout de suite : le correctif suffit.
- **HPA et réplicas minimaux** : `minReplicas` est la capacité de **résilience**, pas seulement de charge ; à une réplique, toute perte de pod est une panne.

**Pièges classiques**
- « C'est la faute du chaos » : l'expérience a révélé, elle n'a pas créé.
- Désactiver la journée de jeu et s'arrêter là.
- Modifier la sonde à la main dans le cluster : Argo CD la remet ; c'est le commit qu'il faut défaire.
- Un post-mortem qui nomme Lucas : sans reproche, on décrit le changement et l'absence de relecture.

---

### M29-E24 — Sous le capot : comment Chaos Mesh injecte une panne

**Solution**
- Pods jetables : [`wb-essais/cibles-e24.yaml`](fichiers/M29-E24/wb-essais/cibles-e24.yaml) (`busybox` de Harbor, contexte `restricted`) ; expériences : [`wb-essais/experiences-e24.yaml`](fichiers/M29-E24/wb-essais/experiences-e24.yaml) (une à la fois).
- Document : [`sous-le-capot-chaos-mesh.md`](fichiers/M29-E24/medisphere/docs/qualite/sous-le-capot-chaos-mesh.md).
- Politique réseau du daemon : [`k8s/espaces/chaos-mesh/30-politiques-reseau.yaml`](fichiers/M29-E24/k8s/espaces/chaos-mesh/30-politiques-reseau.yaml) (31767 depuis le contrôleur seulement, 31766 depuis Prometheus, sondes de l'hôte).

Commandes qui donnent les sorties du document :

```
admin@adm01:~$ kubectl -n chaos-experiences get networkchaos latence-e24 -o yaml | yq '.metadata.finalizers, .status'
admin@adm01:~$ kubectl -n wb-essais get podnetworkchaos client-e24 -o yaml
admin@adm01:~$ kubectl -n chaos-mesh logs deploy/chaos-controller-manager --since=5m | grep -i latence-e24
admin@adm01:~$ kubectl -n chaos-mesh logs <chaos-daemon-du-nœud> --since=5m | grep -Ei 'tc|ipset|iptables'
admin@k8s-w0N:~$ id=$(sudo crictl pods --namespace wb-essais --name '^client-e24$' -q); pid=$(sudo crictl inspectp "$id" | jq .info.pid)
admin@k8s-w0N:~$ sudo nsenter -t "$pid" -n tc qdisc show dev eth0
admin@k8s-w0N:~$ sudo nsenter -t "$pid" -n iptables-legacy -S
admin@adm01:~$ kubectl -n chaos-mesh exec <chaos-daemon-du-nœud> -- nsenter -t "$pid" -n ipset list   # si ipset absent du nœud
admin@k8s-w0N:~$ ps -eo pid,ppid,cgroup:90,cmd | grep -E '[s]tress-ng|[n]sexec'
```

**Explications** : voir le document ; les trois points qui surprennent : (1) pas de filtre `tc` pour une latence ciblée — le tri est fait par `iptables` (`CLASSIFY` vers la bande `netem`, `ipset` de la cible) ; (2) les règles sont posées avec `iptables-legacy` : invisibles avec l'`iptables` (nft) du nœud ; (3) `stress-ng` est rattaché au cgroup du conteneur : la limite CPU du conteneur s'applique au stress.

**Alternatives** : lire le code (`pkg/chaosdaemon/tc_server.go`, `iptables_server.go`, `stress_server_linux.go`, `pkg/bpm/`) à l'étiquette `v2.8.6` ; activer les journaux de débogage du daemon le temps de l'exercice (valeur du chart, par MR, retirée ensuite).

**Pièges classiques**
- `iptables -S` dans l'espace du pod avec la variante nft : « rien », conclusion fausse.
- Retirer une règle à la main pendant que l'expérience vit : le contrôleur et le daemon la reposent (ou se désynchronisent).
- Oublier de supprimer `cible-e24`/`client-e24` (le check du mini-projet les cherche).

**En production chez MédiSphère**
Le `chaos-daemon` ne tourne que parce que le chaos est pratiqué ; s'il ne l'est plus pendant six mois, on désinstalle Chaos Mesh (ADR-0290). Falco surveille les exécutions dans les espaces de noms des conteneurs par un processus étranger (règle d'exception écrite pour le daemon, au registre du M26).
