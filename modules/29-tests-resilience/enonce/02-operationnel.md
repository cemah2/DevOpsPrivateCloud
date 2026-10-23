# Module 29 — Palier 2 : Opérationnel

Le palier 1 a posé un outil par étage. Le palier 2 les rend **utiles** : un test de charge qui répond à la question de Julien avec les SLO et les métriques du serveur, une comparaison honnête entre Testinfra et Goss, un vrai test du module `vm-debian` qui crée et détruit une VM sans pouvoir toucher au reste du lab, Chaos Mesh installé avec des garde-fous qui ne dépendent pas de la prudence de chacun, et le tout assemblé dans un composant CI/CD que les quatre dépôts de plateforme consomment. Lucas a ouvert deux MR à relire, et Claire attend la stratégie de tests écrite.

Prérequis : palier 1 terminé (`lab/bin/check 29 02` à `29 05` verts). Rappels des [règles du module](00-introduction.md#règles-du-module) : jamais la production, données factices, un test laisse le lab propre, un test de charge ou une expérience s'annonce.

**Ce que le palier 2 trouve en place** (modules précédents)

| Élément | Valeur |
|---|---|
| MédiAgenda recette | espace `mediagenda-recette`, Rollout `mediagenda` (pods `app.kubernetes.io/name: mediagenda`, `app.kubernetes.io/component: api`), HPA `mediagenda` (M28-E02), Pooler `mediagenda-db-pooler-rw` (M27-E02), cache StatefulSet `valkey` (M27-E07) |
| Métriques | `mediagenda_http_request_duration_seconds_bucket`, `mediagenda_http_requests_total`, `mediagenda_cache_total` (étiquette `resultat` : `hit`, `miss`, `erreur`) ; SLO Pyrra `mediagenda-latence` (95 % < 250 ms) ; HPA : `kube_horizontalpodautoscaler_status_current_replicas` |
| Supervision témoin (M21) | `mon01` (10.10.20.19) : Prometheus témoin (`:9090`), blackbox_exporter ; sondes déclarées par groupes (`supervision_temoin_sondes` dans `host_vars/mon01/`, étiquette `groupe` = nom du groupe, job `blackbox`) ; alerte critique `SondeEnEchec` sur `probe_success == 0` |
| Proxmox (M05, M06) | pool `lab`, VNet `vsandbox` (10.10.99.0/24) de la zone SDN `lab`, stockage `local-nvme` ; identité OpenTofu `wb-tofu@pve!tofu` (rôle `WBTofu` sur `/pool/lab`) ; modèles Debian dorés 9010-9029 ; module `vm-debian` v2 (`plateforme/tofu-modules`, adresse allouée par NetBox) |
| Admission (M26) | VAP du préfixe `medisphere-` dans `plateforme/k8s/admission/`, dont `medisphere-interdire-hostpath` (exceptions par espace) ; PSA `restricted` partout sauf exceptions du registre `docs/securite/durcissement/exceptions.md` ; Falco (règles `plateforme/politiques/falco/`) |
| CI (M19) | `plateforme/ci-templates` : composants publiés par étiquette `vX.Y.Z` ; `runner01` (exécuteur shell) ; modèle `.socle` de `plateforme/ansible` (clé SSH de la CI) |

---

### M29-E06 — k6 en profondeur : scénarios, seuils des SLO, métriques  `LAB` `★★★`

> **Ticket PLAT-3006** — *De : Julien Petit* — *Copie : Claire Morel*
> Merci pour le premier chiffre. Pour la décision de la campagne, il me faut mieux : la vraie forme de la charge (beaucoup de lectures de créneaux, moins de réservations, qui montent le matin), un verdict par parcours aligné sur nos SLO, et la preuve que ce que mesure k6 est ce que voit le serveur. Dites-moi aussi si le cache Valkey sert à quelque chose sous charge, et si l'HPA réagit assez vite. Je veux pouvoir comparer avec la prochaine version : gardez les résultats.

**Objectifs pédagogiques**
- Modéliser une charge réaliste avec plusieurs scénarios k6 (exécuteurs à taux d'arrivée, constants et en rampe), des groupes et des étiquettes.
- Écrire des seuils qui **sont** les SLO (part des requêtes sous 250 ms, disponibilité), par parcours, avec arrêt automatique.
- Exploiter `setup`, `teardown` et `handleSummary` : précondition, nettoyage, résumé versionné.
- Corréler la mesure client (k6) et la mesure serveur (Prometheus), et interpréter l'effet du cache et de l'HPA.

**Prérequis** : M29-E05 (`charge/lib/commun.js`), M21 (SLO), M27-E07 (cache Valkey), M28-E02 (HPA).
**Durée indicative** : 2 h.

**Contexte technique**
- Charge cible de la campagne : **20 lectures de créneaux par seconde** en continu ; réservations (création puis annulation) qui **montent** jusqu'à **5 par seconde** puis se maintiennent.
- Le SLO de latence est la **part** des requêtes servies en moins de 250 ms (95 %), celui de disponibilité 99,5 % de requêtes sans erreur.
- Le cache des créneaux de MédiAgenda est indexé par (praticien, jour) : lire toujours le même couple ne sollicite qu'une entrée.
- Le script s'appelle **`charge/parcours-recette.js`** ; ses résumés vont dans **`charge/resultats/`** (versionnés), avec une analyse écrite par campagne (`charge/resultats/<date>-analyse.md`).

**Travail demandé**
1. Écris `charge/parcours-recette.js` (il réutilise `lib/commun.js`) : un scénario **lecture** à taux constant et un scénario **réservation** à taux en rampe, chacun étiqueté par parcours (`parcours: lecture`, `parcours: reservation`). Rends paramétrables (`-e`) les deux débits, la durée et la **variété** des couples (praticien, jour) lus.
2. Seuils : la part des requêtes sous 250 ms, mesurée par une métrique personnalisée qui reprend la définition du SLO ; p95 par parcours (sous-métriques filtrées par étiquette) ; taux d'échec sous 0,5 %, **arrêt** du test au-delà de 5 % ; itérations perdues ; checks.
3. `setup()` vérifie que la recette est prête et **annule** le test sinon ; `teardown()` supprime tout rendez-vous factice resté en base (seulement les praticiens `dr-k6-…`).
4. `handleSummary()` écrit un résumé lisible sur la sortie standard et un JSON dans `charge/resultats/` : un bloc de synthèse (cible, paramètres, verdict, seuils franchis, part sous 250 ms, p95, p99, erreurs, débit, itérations perdues) suivi du résumé complet de k6.
5. Vérifie le script avec `k6 inspect`, annonce la campagne, puis lance deux tests de 5 minutes : un en **cache froid** (grande variété), un en **cache chaud** (un seul couple). Garde les deux résumés.
6. Pendant chaque test, relève dans Prometheus, sur la même fenêtre : la part sous 250 ms et le débit **vus par le serveur**, le taux de succès du cache, le nombre de réplicas de l'HPA. Regarde aussi `kubectl top nodes`.
7. Écris l'analyse : conditions, résultat client, résultat serveur et écart expliqué, effet du cache, réaction de l'HPA (délai, effet visible ou non), conclusion pour la campagne et campagne suivante proposée.

**Critères de réussite**
- [ ] `charge/parcours-recette.js` est sur `main` : deux scénarios à taux d'arrivée (constant et rampe), seuils par parcours, seuil aligné sur le SLO, `abortOnFail`, `dropped_iterations`, `handleSummary`.
- [ ] `k6 inspect` lit deux scénarios et au moins quatre seuils.
- [ ] `charge/resultats/` contient au moins deux résumés JSON mesurés sur la **recette** et une analyse `*analyse*.md`.
- [ ] Les métriques de la recette montrent des succès de cache et au moins un réplica ajouté par l'HPA pendant les 7 derniers jours.

**Vérification** : `lab/bin/check 29 06`

<details><summary>Indice 1</summary>

Une métrique personnalisée de type `Rate` à laquelle tu ajoutes, pour chaque réponse, « durée < 250 » donne exactement la part des requêtes sous 250 ms. Un seuil sur une sous-métrique s'écrit avec le filtre entre accolades dans le nom de la métrique.
</details>

<details><summary>Indice 2</summary>

Un exécuteur à taux d'arrivée a besoin de VUs disponibles : environ débit × durée d'une itération, plus une marge. Si `maxVUs` est trop bas, k6 ne lance pas les itérations et les compte dans `dropped_iterations`.
</details>

<details><summary>Indice 3</summary>

Le fichier écrit par `handleSummary` est relatif au dossier **courant** de k6, pas au script. Côté Prometheus, la part sous 250 ms se calcule comme dans la règle de SLO du M21 : seau `le="0.25"` divisé par le total, sur la fenêtre du test.
</details>

**Pour aller plus loin** (facultatif) : ajoute un troisième scénario en `ramping-arrival-rate` qui cherche le point de rupture (débit auquel la part sous 250 ms passe sous 95 %), avec un seuil `abortOnFail` pour ne pas aller au-delà.

---

### M29-E07 — Goss : la comparaison et les sondes de santé  `LAB` `★★`

> **Ticket PLAT-3007** — *De : Karim Benali* — *Copie : Nadia Roussel*
> Testinfra tourne la nuit depuis le contrôleur. Nadia aimerait autre chose : que chaque VM dise **elle-même**, en continu, si elle est conforme, et que la supervision le voie. Goss fait ça (`goss serve`). Essaie-le sur deux VMs, branche-le sur le blackbox de `mon01`, et dis-moi par écrit si on garde Testinfra, Goss, ou les deux. Attention à ne pas réveiller l'astreinte pour un test de conformité.

**Objectifs pédagogiques**
- Écrire des tests Goss 0.4 (YAML, gabarits) qui reprennent les contrôles Testinfra d'E04.
- Publier l'état de conformité par `goss serve` et le superviser par une sonde HTTP du blackbox.
- Distinguer, dans les alertes, une machine injoignable d'un test de conformité rouge.
- Comparer deux outils sur des critères écrits et décider.

**Prérequis** : M29-E04, M21 (supervision témoin de `mon01`, rôle `supervision_temoin`), M06 (pare-feu local des VMs, rôle `pare_feu_local`).
**Durée indicative** : 1 h 45.

**Contexte technique**
- VMs de l'essai : **`dns02`** et **`nbx01`** (Debian 13). `goss serve` écoute sur l'adresse de service de la VM, port **8099**, chemin `/healthz` : réponse **200** si tous les tests passent, **503** sinon.
- Rôle **`goss`** de `plateforme/ansible` : `defaults/main.yml` (version **0.4.10**, empreinte de l'archive), `templates/goss.yaml.j2` (les tests), `templates/goss-serve.service.j2` (unité systemd) ; playbooks `playbooks/goss-essai.yml` (installation sur les deux VMs) et `playbooks/goss-retrait.yml` (retrait complet).
- Sur `mon01`, nouveau groupe de sondes **`goss`** (module blackbox `goss_sante`) ; alertes **`TestsGossEnEchec`** (la sonde répond, mais des tests sont rouges) et **`SondeGossMuette`** (la sonde ne répond plus) dans un fichier de règles `goss.yml` du rôle `supervision_temoin`, testé par `promtool test rules`.
- Flux à ouvrir : `mon01` (10.10.20.19) → `dns02`, `nbx01` en TCP 8099, par le pare-feu local des deux VMs.
- Documents : `docs/qualite/testinfra-goss.md` (comparaison, décision) et runbook **RB-291** (« sonde Goss rouge ») dans `docs/qualite/runbooks/` de `plateforme/medisphere`.

**Travail demandé**
1. Écris le rôle `goss` : téléchargement de l'archive sur le contrôleur, vérification de l'empreinte, installation sur la VM ; fichier de tests rendu depuis le gabarit et **validé** avant d'être installé ; service `goss serve` **sans privilège** (pas root), sortie JSON, résultats gardés en cache quelques secondes, redémarré quand les tests changent.
2. Dans le gabarit, reprends au moins les contrôles d'E04 pour `node_exporter`, Alloy et chrony (service, version, port, sources de temps), avec les valeurs attendues en variables du rôle.
3. Applique sur `dns02` et `nbx01`, ouvre le flux depuis `mon01`, et vérifie `/healthz` depuis `mon01`. Fais échouer **un** test exprès (arrête Alloy sur `nbx01`, par exemple) : que renvoie `/healthz`, que dit le corps de la réponse ? Remets en état.
4. Ajoute le groupe de sondes et le module blackbox sur `mon01`. Écris les deux alertes et leurs tests unitaires `promtool`. Fais en sorte qu'une sonde Goss qui répond 503 ne déclenche **pas** l'alerte critique existante `SondeEnEchec`.
5. Écris RB-291 : que faire quand `TestsGossEnEchec` ou `SondeGossMuette` se déclenche.
6. Écris `docs/qualite/testinfra-goss.md` : tableau comparatif (où le test s'exécute, langage, accès nécessaires, ce qu'on voit en continu, coût d'entretien, double emploi avec le rôle Ansible, sécurité du port ouvert), décision argumentée, et ce que devient l'essai (garder, étendre ou retirer avec `goss-retrait.yml`).

**Critères de réussite**
- [ ] Le rôle `goss` est sur `main` : version 0.4.10 et son empreinte, service sur le port 8099 sans privilège.
- [ ] Les sondes `goss` de `dns02` et `nbx01` réussissent sur le Prometheus témoin (200).
- [ ] Les alertes `TestsGossEnEchec` et `SondeGossMuette` sont chargées ; `SondeEnEchec` exclut le groupe `goss`.
- [ ] `docs/qualite/testinfra-goss.md` (avec une décision) et RB-291 sont sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 29 07`

<details><summary>Indice 1</summary>

Depuis la version 0.4.10, la publication de Goss fournit des **archives** et un fichier de sommes, et non plus un binaire nu : regarde la liste des fichiers de la publication avant d'écrire l'URL. `goss render` affiche le fichier de tests après inclusion des gabarits : c'est un bon validateur pour le module `template`.
</details>

<details><summary>Indice 2</summary>

Le blackbox expose `probe_http_status_code` en plus de `probe_success`. Une sonde HTTP qui reçoit 503 a `probe_success == 0` : il faut distinguer « répond 503 » de « ne répond pas ».
</details>

<details><summary>Indice 3</summary>

Un service systemd peut tourner sous un utilisateur créé à la volée (`DynamicUser=`) ; certains tests Goss (lecture de fichiers de root) deviennent alors impossibles. Choisis tes tests en conséquence, ou dis-le dans la comparaison.
</details>

**Pour aller plus loin** (facultatif) : génère un premier fichier Goss avec `goss autoadd` sur une VM et compare-le à ton gabarit : qu'est-ce qui est utile, qu'est-ce qui est du bruit ?

---

### M29-E08 — Terratest : tester le module `vm-debian`  `LAB` `★★★`

> **Ticket PLAT-3008** — *De : Karim Benali* — *Copie : Sophie Laurent*
> `vm-debian` est le module le plus utilisé du dépôt et ses tests (`tofu test`, M05) tournent avec un fournisseur simulé : ils prouvent la logique, pas qu'une VM **marche**. Je veux un test qui crée une vraie VM, vérifie qu'on s'y connecte, que cloud-init a fait son travail, que l'agent QEMU répond, que les étiquettes et l'adresse sont justes, puis la détruit **quoi qu'il arrive**. Sophie pose une condition : l'identité Proxmox de ce test ne doit pouvoir toucher **que** les VMs de test, pas le socle, même si le test se trompe de VMID.

**Objectifs pédagogiques**
- Écrire un test Terratest 1.0 (Go 1.26) : copie du module, `InitAndApply`, sorties, vérifications avec tentatives, destruction garantie.
- Isoler un test d'intégration : nom unique, VMID libre d'une plage réservée, étiquette de construction, délais cohérents entre `go test` et le job.
- Concevoir une identité Proxmox au moindre privilège, et comprendre ce que Proxmox fait des ACL quand une VM est détruite.
- Intégrer un test long et coûteux en CI : manuel, un seul à la fois.

**Prérequis** : M05 (module `vm-debian`, identité `wb-tofu`, `tofu test`), M06 (NetBox, allocation d'adresses), M03 (modèles dorés), M19 (CI).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Le test vit dans **`plateforme/tofu-modules/vm-debian/test/`** : `go.mod` (Go **1.26**, `github.com/gruntwork-io/terratest` **v1.0.x**), `go.sum`, le test `vm_debian_test.go` (fonction `TestVmDebian`) et une configuration d'appel du module dans `test/fixtures/vm/` (sans *backend* : l'état est local au test).
- VMs de test : nom **`tt-<suffixe>`** (6 caractères en minuscules), VMID **2290-2299** (le premier libre), VNet **`vsandbox`**, étiquettes **`env-m29`** et **`terratest`**, sous-pool Proxmox **`lab/terratest`** (pools imbriqués). Une seule VM à la fois.
- Identité dédiée : **`wb-terratest@pve`**, jeton **`terratest`**, créée par un script `plateforme/infra/outils/proxmox/pve-terratest-compte.sh` à lancer en root sur `pve01` (modèle : `pve-tofu-compte.sh` du M05). Le jeton est rangé dans `~/.config/workbook/pve-terratest.env` (`PROXMOX_VE_ENDPOINT`, `PROXMOX_VE_API_TOKEN`) et dans les variables protégées et masquées de `plateforme/tofu-modules`. Le jeton NetBox d'automatisation (`netbox-tofu.env`, M06) sert à l'allocation d'adresse.
- Le test est compilé seulement avec l'étiquette de construction **`integration`** (`go test ./...` sans elle ne crée rien).
- CI : job **`terratest:vm-debian`**, **manuel**, sur `runner01` (Go 1.26 à ajouter par le rôle `gitlab_runner` ; `tofu` y est depuis le M05), un seul à la fois dans toute l'instance.
- Runbook **RB-293** (« VMs de test orphelines ») dans `docs/qualite/runbooks/` ; le palier 4 (M29-E21) le complétera.

**Travail demandé**
1. Installe Go 1.26.x sur `adm01` (archive officielle, empreinte vérifiée) et ajoute Go 1.26.x à `runner01` par son rôle `gitlab_runner` (vérifie que `tofu version` y répond aussi).
2. Conçois l'identité de test : quels privilèges, sur quels chemins d'ACL, pour cloner un modèle doré, créer, configurer, démarrer, lire l'agent et détruire une VM du sous-pool, et **rien d'autre**. Écris le script de création (rejouable), lance-le, et prouve avec `pveum user token permissions` que le jeton n'a **aucun** droit d'écriture sur le reste du pool `lab`.
3. Écris la configuration de test `fixtures/vm/` (appel du module, variables validées : nom au bon format, VMID dans la plage) et le test `TestVmDebian` :
   - nom unique et premier VMID libre de la plage (lu dans l'API de Proxmox) ;
   - copie du module dans un dossier temporaire, binaire **`tofu`** imposé ;
   - destruction enregistrée **avant** la création, puis vérification qu'aucune VM ni adresse NetBox ne reste ;
   - sous-tests : sorties du module, étiquettes et sous-pool (API Proxmox), connexion SSH et fin de cloud-init (avec tentatives), réponse de l'agent QEMU.
4. Lance le test depuis `adm01` et lis son journal : combien de temps chaque étape ? Pendant le test, observe la VM dans Proxmox et dans NetBox.
5. Provoque un échec (une vérification volontairement fausse) et constate que la VM est quand même détruite. Rétablis.
6. Ajoute le job manuel (et un job rapide qui compile et analyse le test à chaque MR, sans rien créer). Règle les délais (attentes du test, `-timeout` de `go test`, `timeout` du job) pour que la VM soit détruite même quand une attente n'aboutit jamais : vérifie par un essai ce qui se passe **réellement** quand `go test -timeout` expire. Fais réussir le job une fois.
7. Écris RB-293 : comment retrouver et supprimer, sans risque pour le reste du lab, une VM de test restée après un test interrompu.

**Critères de réussite**
- [ ] `go version` sur `adm01` répond go1.26.x ; `go.mod` déclare Go 1.26 et Terratest 1.0 ; `go.sum` est versionné.
- [ ] Le test impose `tofu`, détruit dans tous les cas, nomme `tt-…` en 2290-2299, vérifie SSH, étiquettes et agent QEMU ; il porte l'étiquette de construction `integration`.
- [ ] Le job Terratest est manuel et exclusif, et a réussi dans les 30 derniers jours.
- [ ] Le sous-pool `lab/terratest` existe ; le jeton `wb-terratest@pve!terratest` peut allouer dans ce sous-pool et n'a aucun droit d'écriture sur `/pool/lab`.
- [ ] Aucune VM de test ne reste dans Proxmox ni dans NetBox (hors test en cours) ; RB-293 est publié.

**Vérification** : `lab/bin/check 29 08`

<details><summary>Indice 1</summary>

Terratest choisit `terraform` s'il le trouve dans le `PATH`, sauf si les options disent le contraire. `t.Cleanup` (ou `defer`) enregistré **avant** `InitAndApply` s'exécute même si la création échoue à moitié ou si une assertion `require` arrête le test.
</details>

<details><summary>Indice 2</summary>

Avant de poser des ACL sur `/vms/<vmid>`, lis ce que fait Proxmox des ACL d'une VM quand on la **détruit** (code de `qemu-server`, ou essaie : crée une VM, pose une ACL, détruis, relis les ACL). Un chemin qui survit aux VMs, c'est un pool.
</details>

<details><summary>Indice 3</summary>

Le clonage avec un pool cible demande `VM.Allocate` sur ce pool et `VM.Clone` sur le modèle. La connexion SSH arrive avant la fin de cloud-init : attends que `cloud-init status --wait` réussisse dans une boucle de tentatives.
</details>

**Pour aller plus loin** (facultatif) : ajoute un second test qui vérifie la **mise à jour en place** (changer la taille mémoire ne doit pas recréer la VM : compare le VMID et l'UUID SMBIOS avant et après).

---

### M29-E09 — Chaos Mesh : installer avec des garde-fous  `LAB` `★★★`

> **Ticket PLAT-3009** — *De : Sophie Laurent* — *Copie : Karim Benali, Claire Morel*
> J'accepte qu'on installe un outil qui tue des pods et coupe le réseau, à condition que **la production soit hors d'atteinte par construction**, pas par discipline. Je veux : une liste fermée d'espaces visables (recette et `wb-essais`), une barrière qui refuse tout le reste même à un administrateur pressé, l'exception PSA écrite au registre, Falco ajusté sans devenir aveugle, aucun tableau de bord publié, et une procédure d'arrêt d'urgence que Nadia peut appliquer seule. Première expérience : un pod de l'API de recette, une minute.

**Objectifs pédagogiques**
- Installer Chaos Mesh 2.8 par Argo CD avec un chart recopié, des valeurs **vérifiées dans le chart** et des images du cache Harbor.
- Comprendre l'architecture (contrôleur, `chaos-daemon` privilégié, webhooks) et ce qu'elle impose côté PSA, admission et Falco.
- Empiler les garde-fous : filtre d'espaces, politique d'admission, RBAC, quota, durée obligatoire, runbook d'arrêt.
- Lancer, observer et arrêter une première expérience.

**Prérequis** : M20 (Argo CD, `charts-miroir`), M26 (PSA, VAP, Falco, registre des exceptions), M28-E05 (locataires Capsule : un propriétaire de locataire peut annoter ses espaces), M15 (cert-manager).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Chart **`chaos-mesh/chaos-mesh` 2.8.x** (dépôt `https://charts.chaos-mesh.org`), recopié par `plateforme/charts-miroir` ; Application Argo CD **`chaos-mesh`** (projet `plateforme`), valeurs dans **`plateforme/gitops/valeurs/chaos-mesh/values.yaml`**, espace **`chaos-mesh`** (créé par `plateforme/k8s`, pas par Argo CD). Images par le cache `ghcr` de Harbor.
- Runtime du cluster : containerd, socket `/run/containerd/containerd.sock`.
- Les CRD de Chaos Mesh dépassent la taille d'annotation que permet l'application côté client.
- Espaces **visables** (annotation `chaos-mesh.org/inject=enabled`) : **`mediagenda-recette`**, **`medinotif-recette`**, **`wb-essais`**, et eux seuls. Jamais `*-prod`, jamais `messagerie`, jamais un espace de plateforme.
- Les objets de chaos se créent **depuis `adm01`** dans l'espace **`chaos-experiences`** (exception écrite à « tout par Argo CD ») et sont rangés dans **`plateforme/resilience/chaos/`** (ici `chaos/e09/`).
- Politique d'admission **`medisphere-chaos-espaces`** (`plateforme/k8s/admission/`) ; exceptions au registre : **EXC-K-005** (PSA `privileged` de `chaos-mesh`), et les suivantes libres selon ce que tu trouves.
- Lecture des objets de Chaos Mesh (et de k6-operator, palier 3) par les checks : ClusterRole **`wb-checks-services-m29`**, agrégée à `wb-checks-services` (M27), dans `plateforme/k8s/rbac/`.
- Première expérience : **PodChaos `e09-pod-failure-api`**, action `pod-failure`, **un** pod de l'API de `mediagenda-recette`, **60 s**.
- Runbook **RB-292** (« arrêt d'urgence du chaos ») et `docs/qualite/chaos-mesh.md` dans `plateforme/medisphere`.

> ⚠️ **Attention** : l'annotation `chaos-mesh.org/inject=enabled` ne se pose **jamais** à la main, ni « pour l'essai », ni sur un espace hors de la liste. Elle se pose par MR dans `plateforme/k8s`, après que la politique d'admission est en place.

**Travail demandé**
1. Recopie le chart et **lis ses valeurs** (`helm show values`) : relève les clés qui activent le filtre d'espaces, le runtime et son socket, le tableau de bord, le serveur DNS, le mode de sécurité, les certificats des webhooks, les images. Note leurs valeurs par défaut.
2. Écris l'espace `chaos-mesh` (PSA et exception écrite) et l'espace `chaos-experiences` (PSA `restricted`, quota d'objets de chaos, aucun pod), les rôles (qui peut créer des expériences, qui peut les lire) et la ClusterRole des checks.
3. Écris la politique d'admission : refuser l'annotation hors de la liste, tout objet de chaos hors de `chaos-experiences`, toute expérience qui vise un espace hors de la liste. Pense au contrôleur de Chaos Mesh, qui crée lui-même des objets dans les espaces visés. Passe-la d'abord en **avertissement et audit**, vérifie, puis en refus.
4. Adapte la politique `medisphere-interdire-hostpath` pour les chemins dont le `chaos-daemon` a besoin, et ajuste Falco selon ce qu'il remonte pendant l'installation (exceptions **ciblées** sur les conteneurs de Chaos Mesh, au registre).
5. Écris les valeurs et l'Application. Pas de tableau de bord, pas de serveur DNS, filtre d'espaces actif, mode de sécurité actif. Relis le rendu (`helm template`) avant la MR et valide-le avec le paquet de schémas d'E02. Synchronise et vérifie que tout est sain, puis régénère et republie le paquet `schemas-crd` (nouvelles CRD).
6. Pose l'annotation sur les trois espaces par MR. Vérifie que la politique refuse de la poser sur `mediagenda-prod`.
7. Prouve le filtre : déploie un témoin dans `wb-essais` et une expérience qui le vise **avant** que `wb-essais` soit annoté ; lis l'état de l'expérience et ses événements. Recommence après l'annotation.
8. Écris RB-292 (pause, suppression, que faire si l'objet ne part pas, vérifier que la panne est **retirée**), puis lance `e09-pod-failure-api` en recette pendant que tu observes les pods, le Service et la latence ; arrête-la une fois par le runbook avant sa fin, relance-la et laisse-la finir.

**Critères de réussite**
- [ ] Application `chaos-mesh` : chart 2.8.x de Harbor, synchronisée, saine, appliquée côté serveur.
- [ ] Contrôleur avec filtre d'espaces et mode de sécurité actifs, images du cache Harbor ; `chaos-daemon` prêt sur chaque nœud, runtime containerd ; ni tableau de bord ni DNS de Chaos Mesh.
- [ ] `chaos-mesh` en `privileged` (EXC-K-005 au registre), `chaos-experiences` en `restricted` avec un quota.
- [ ] Seuls les trois espaces de la liste sont annotés ; aucun `*-prod` ni `messagerie`.
- [ ] La politique `medisphere-chaos-espaces` est liée en refus ; les chemins `hostPath` du `chaos-daemon` sont déclarés.
- [ ] `e09-pod-failure-api` a visé un pod et l'a rétabli ; aucun objet de chaos n'existe hors de `chaos-experiences` ; RB-292 est publié.

**Vérification** : `lab/bin/check 29 09`

<details><summary>Indice 1</summary>

Le contrôleur de Chaos Mesh lit ses réglages dans des variables d'environnement générées par le chart : `kubectl -n chaos-mesh get deploy chaos-controller-manager -o yaml` montre ce que les valeurs ont vraiment produit. Certaines ressources du chart portent une annotation aléatoire régénérée à chaque rendu : Argo CD les verra toujours « désynchronisées » si tu ne lui dis pas de l'ignorer.
</details>

<details><summary>Indice 2</summary>

Une ValidatingAdmissionPolicy peut exclure des demandeurs par `matchConditions` (`request.userInfo.username`). Le webhook de Chaos Mesh, en mode de sécurité, vérifie aussi que le **demandeur** a le droit d'agir sur les espaces visés : les rôles doivent exister dans ces espaces, pas seulement dans `chaos-experiences`.
</details>

<details><summary>Indice 3</summary>

Une expérience qui ne trouve aucun pod n'est pas refusée à la création : elle existe, et c'est son **statut** (conditions, événements) qui dit qu'elle n'a rien sélectionné. Pour l'arrêt d'urgence, cherche l'annotation de pause dans la documentation de Chaos Mesh.
</details>

**Pour aller plus loin** (facultatif) : lis la fiche [`litmuschaos.md`](../../../annexes/decouverte/litmuschaos.md) et liste ce qui, dans LitmusChaos 3, remplacerait chacun de tes garde-fous.

---

### M29-E10 — Le composant `validation` : une pyramide de tests en CI  `LIBRE` `★★★`

> **Ticket PLAT-3010** — *De : Claire Morel* — *Copie : Karim Benali*
> Nous avons maintenant des tests à chaque étage, mais chacun dans son coin, lancé à la main ou recopié d'un dépôt à l'autre. Je veux **un** composant CI/CD, versionné comme les autres, que chaque dépôt de plateforme inclut en trois lignes, et qui fasse tourner ce qui convient à ce dépôt : schémas, politiques, tests des politiques, tests d'infrastructure. Une MR qui casse une règle ne doit plus pouvoir être fusionnée. Et rien de ce composant ne doit pouvoir faire fuir un secret de plan.

**Objectifs pédagogiques**
- Concevoir un composant CI/CD réutilisable (entrées typées, valeurs par défaut, jobs activables) qui assemble les étages bas de la pyramide.
- Fournir une image d'outils reproductible et vérifiée.
- Brancher des politiques et des schémas **versionnés** dans plusieurs dépôts sans les recopier.
- Placer chaque test au bon moment du pipeline (MR, branche principale, planifié) et au bon endroit (le plan ne sort pas du job).

**Prérequis** : M29-E02, E03, E04 ; M19 (composants CI/CD de `plateforme/ci-templates`, publication par étiquette, registre Harbor, signature).
**Durée indicative** : 2 h.

**Contexte technique**
- Composant **`validation`** de `plateforme/ci-templates` (`templates/validation/template.yml`), publié dans la version mineure qui suit la dernière étiquette du projet (`v2.11.0` si la dernière est `v2.10.0` ; sinon règle `WB_M29_VERSION_VALIDATION`). Les consommateurs l'incluent **par étiquette**, jamais par branche.
- Consommateurs : `plateforme/k8s`, `plateforme/gitops`, `plateforme/infra`, `plateforme/ansible`. Les règles Rego elles-mêmes sont testées dans la CI de `plateforme/politiques`.
- Noms des jobs (les vérifications s'en servent) : préfixe **`validation:`** (par exemple `validation:manifestes`, `validation:rego`, `validation:testinfra`). La vérification des plans est un modèle caché **`.validation:conftest-plan`** que le job de plan de `plateforme/infra` étend.
- Les entrées comprennent au moins : la version du paquet `schemas-crd`, la version des politiques (une **étiquette** `vX.Y.Z` de `plateforme/politiques`, que tu commences à publier ici), la version de Kubernetes, et l'activation (booléenne) de Testinfra.
- Les outils (kubeconform, conftest, OPA, kustomize, helm, yq) viennent d'une image construite par `plateforme/ci-templates`, poussée dans Harbor et référencée **par empreinte**. Exception : le job de plan de `plateforme/infra` tourne sur `runner01` (exécuteur `shell`, M05) et y lance conftest lui-même ; conftest 0.71 et OPA 1.21 s'installent sur `runner01` par le rôle `gitlab_runner` (binaires vérifiés par empreinte).

**Travail demandé**
1. Conçois et publie le composant : validation des manifestes rendus (Kustomize et charts des Applications) avec les schémas du paquet et les politiques Kubernetes, sans jamais ignorer un schéma manquant ; tests et vérifications de format des politiques Rego ; vérification des plans **dans** le job qui les produit ; Testinfra facultatif.
2. Construis l'image d'outils : versions épinglées, binaires vérifiés par empreinte, image signée comme les autres images de la plateforme. Ajoute conftest et OPA au rôle `gitlab_runner` et applique-le sur `runner01`.
3. Ajoute dans `plateforme/politiques` au moins deux règles Kubernetes utiles aux manifestes rendus (par exemple : une expérience de chaos sans durée, une charge de travail sans limites de mémoire), avec leurs tests.
4. Branche le composant dans les quatre dépôts consommateurs et dans la CI de `plateforme/politiques`. Remplace ce que le composant rend inutile (le job Testinfra d'E04, les validations ad hoc).
5. Prouve que la CI **bloque** : une MR de démonstration par étage (une `Application` avec un champ inconnu, un plan qui remplace une VM du socle, une règle Rego cassée) doit échouer, puis être fermée.
6. Vérifie qu'aucun job ne publie le plan JSON ni un fichier qui en dérive.
7. Documente le composant (entrées, exemples d'inclusion, ce que fait chaque job, comment monter de version) dans son `README`.

**Critères de réussite**
- [ ] L'étiquette du composant est publiée ; `validation` a des entrées typées, dont la version des schémas et la référence des politiques.
- [ ] Le composant lance kubeconform en mode strict avec le paquet `schemas-crd`, sans `-ignore-missing-schemas` ; il lance conftest (manifestes et plans) et `opa test` ; Testinfra est activable par une entrée.
- [ ] Les quatre dépôts incluent `validation@vX.Y.Z` par étiquette ; le job de plan de `plateforme/infra` étend `.validation:conftest-plan` ; conftest 0.71 répond sur `runner01`.
- [ ] Les derniers pipelines de `main` de `plateforme/k8s` et `plateforme/gitops` ont réussi avec un job `validation:…` ; ceux de `plateforme/infra` et de `plateforme/politiques` ont réussi, les règles Rego testées.
- [ ] Les trois MR de démonstration ont échoué pour la bonne raison.

**Vérification** : `lab/bin/check 29 10`

<details><summary>Indice 1</summary>

Un composant ne connaît pas les modèles cachés du projet qui l'inclut. Si un job du composant doit tourner avec des réglages propres à un consommateur (clé SSH, variables protégées), laisse le consommateur **compléter** ce job plutôt que d'y faire référence dans le composant.
</details>

<details><summary>Indice 2</summary>

Le paquet générique d'un autre projet se télécharge dans un job avec le jeton du job, à condition que ce projet autorise les jetons de job des projets consommateurs. Les politiques d'un autre dépôt peuvent se récupérer à une référence précise de la même façon.
</details>

<details><summary>Indice 3</summary>

Les étiquettes de la MR (`CI_MERGE_REQUEST_LABELS`) n'existent que dans un pipeline de MR. Le contexte que la règle de destruction lit doit donc être écrit par le job de plan lui-même, et un plan de la branche principale doit avoir un comportement défini.
</details>

**Pour aller plus loin** (facultatif) : ajoute au composant une entrée qui publie un rapport JUnit de conftest, pour que les refus apparaissent dans l'onglet *Tests* de la MR.

---

### M29-E11 — Revue : les politiques Rego et le test k6 du stagiaire  `REV` `★★`

> **Ticket PLAT-3011** — *De : Karim Benali* — *Copie : Lucas Martin*
> Lucas a ouvert deux MR le même jour : des garde-fous pour les plans (`plateforme/politiques`, !214) et un test de charge pour le ticket de Julien sur les 500 requêtes/s (`plateforme/resilience`, !37). Il dit que tout est vert chez lui. Relis-les sérieusement : je veux la liste des défauts, leur gravité, la preuve pour chacun, et une version corrigée qu'il pourra comparer à la sienne. Explique-lui, ne réécris pas en silence.

**Objectifs pédagogiques**
- Relire du Rego et un script k6 en cherchant ce qui rend un test **faussement vert**.
- Prouver un défaut par une exécution, pas par une opinion.
- Reconnaître un incident de données dans une MR et le traiter comme tel.

**Prérequis** : M29-E03, E05, E06.
**Durée indicative** : 1 h 15.

**Contexte technique**
- Les fichiers de Lucas sont dans [`ressources/E11-lucas/`](../ressources/E11-lucas/) (son `README.md` reprend la description de chaque MR).
- Travaille sur une branche **`revue-lucas`** dans `plateforme/politiques` et dans `plateforme/resilience`. Les versions corrigées vont dans **`rego/revue-lucas/`** (`garde-fous.rego`, `garde-fous_test.rego`) et **`charge/revue-lucas/`** (`creneaux-charge.js`) ; ta revue dans **`rego/revue-lucas/REVUE.md`** (un tableau : numéro, défaut, gravité, preuve, correction).
- Les règles des plans d'E03 (`rego/tofu/`) restent la référence ; la version corrigée de Lucas sert à **lui montrer** chaque correction.
- Pour rejouer le test k6 sans toucher la recette, un MédiAgenda local suffit (section « Lancer en local » du `README.md` de MédiAgenda : un PostgreSQL et un Valkey jetables en conteneurs sur `adm01`), servi sur `127.0.0.1:8000`. Avant de lancer un script que tu n'as pas écrit, lis quelle cible il vise par défaut, donne-lui toujours `-e BASE_URL=http://127.0.0.1:8000`, et raccourcis sa durée dans une copie de travail (l'option `--duration` de la ligne de commande remplacerait ses scénarios, donc ce que tu veux observer).

**Travail demandé**
1. Lis les deux MR et leurs descriptions. Avant de pousser quoi que ce soit, lis **tout** ce que tu t'apprêtes à versionner.
2. Rejoue les politiques de Lucas avec les outils de l'équipe (OPA 1.21, conftest 0.71, commande du job de plan) sur les plans d'exemple d'E03. Rejoue son test k6 contre un MédiAgenda local, quelques secondes, avec son code de sortie.
3. Écris `REVUE.md` : **au moins 10 défauts**, avec gravité (bloquant, majeur, mineur), preuve (commande et résultat) et correction. Signale à part ce qui relève de la sécurité ou de la protection des données, et ce qu'il faut faire au-delà du code.
4. Écris les versions corrigées et leurs tests (pour chaque règle, un cas accepté et un cas refusé). Elles doivent compiler en Rego v1 et passer leurs tests ; le script k6 corrigé doit respecter les règles du module.
5. Pousse les branches `revue-lucas` et rédige le commentaire de revue des deux MR (ton : pédagogique, précis, sans condescendance).

**Critères de réussite**
- [ ] Branches `revue-lucas` dans les deux projets ; `REVUE.md` liste au moins 10 défauts.
- [ ] `rego/revue-lucas/` : paquet lu par la commande de conftest de l'équipe, Rego v1, `opa check --strict` et `opa test` réussis, au moins un test qui exige un refus.
- [ ] `charge/revue-lucas/creneaux-charge.js` : pas de cible de production, des seuils dont le taux d'échec, aucune donnée réelle, TLS vérifié, création attendue en 201.
- [ ] Aucun fichier de patients sur la branche `revue-lucas` de `plateforme/resilience`.

**Vérification** : `lab/bin/check 29 11`

<details><summary>Indice 1</summary>

« Les tests passent » ne veut rien dire si **aucune** règle n'est évaluée. Compte les tests et les règles que conftest dit avoir lus, et compare à ce que tu attends.
</details>

<details><summary>Indice 2</summary>

Pour chaque règle de Lucas, construis le plan le plus simple qui **devrait** être refusé et regarde s'il l'est. Pour le test k6, compare le taux de checks réussis au taux de requêtes en échec, et regarde ce que vaut le code de sortie.
</details>

<details><summary>Indice 3</summary>

Un fichier supprimé dans un nouveau commit reste dans l'historique de la branche et dans la MR. Demande-toi ce que le fichier **prétend** contenir, qui doit être prévenu, et ce qu'il faut faire de l'historique.
</details>

**Pour aller plus loin** (facultatif) : écris pour l'équipe une page « Relire un test » de dix lignes : les questions qui révèlent un test qui ne peut pas échouer.

---

### M29-E12 — Stratégie de tests de la plateforme  `RED` `★★`

> **Ticket PLAT-3012** — *De : Claire Morel* — *Copie : Sophie Laurent, Julien Petit, Nadia Roussel*
> Pour l'audit, je dois pouvoir montrer **une** page qui dit comment nous testons la plateforme : quoi, à quel moment, ce que ça coûte, qui en est responsable, et ce que nous avons décidé de ne pas tester (et pourquoi). Et Julien veut une procédure courte pour lancer un test de charge sans gêner son équipe : il l'appliquera lui-même.

**Objectifs pédagogiques**
- Écrire une stratégie de tests lisible par un auditeur et par l'équipe : pyramide, déclencheurs, coûts, propriétaires, angles morts assumés.
- Écrire un runbook utilisable par une autre équipe.

**Prérequis** : M29-E02 à E10.
**Durée indicative** : 1 h 15.

**Contexte technique**
- Documents dans `plateforme/medisphere` : **`docs/qualite/strategie-tests.md`** et **`docs/qualite/runbooks/RB-290-test-de-charge.md`**.
- Lecteurs : l'auditeur HDS (preuves, responsabilités), l'équipe Plateforme (quoi lancer quand), les équipes de développement (ce qui les concerne).

**Travail demandé**
1. Rédige la stratégie (2 à 3 pages) :
   - la **pyramide** de la plateforme, du statique au chaos, avec les outils réellement en place ;
   - un tableau : test, étage, déclencheur (**chaque MR**, **chaque nuit**, **manuel**/à la demande, planifié), durée, **coût** (temps, ressources, risque pour la recette), **propriétaire**, où lire le résultat ;
   - les règles : un test doit pouvoir échouer (comment on le vérifie), un test rouge bloque ou alerte (lequel, qui), on ne désactive pas un test sans ticket ;
   - ce qu'on **ne teste pas** (et pourquoi : coût, risque, couvert ailleurs), avec la date de la prochaine revue de cette liste ;
   - les données de test (factices, préfixes, nettoyage) et l'interdiction de la production.
2. Rédige RB-290 « lancer un test de charge sans nuire » : prérequis, annonce, cible (la recette, jamais la production), paramètres prudents d'abord, surveillance pendant le test, critères d'arrêt et comment arrêter, nettoyage et vérification après, où ranger le résultat.
3. Fais relire la stratégie par quelqu'un qui n'a pas fait le module (ou relis-la à froid le lendemain) : chaque ligne du tableau doit pouvoir être vérifiée dans GitLab.

**Critères de réussite**
- [ ] `docs/qualite/strategie-tests.md` est sur `main` : pyramide, déclencheurs (MR, nuit, manuel), coûts, propriétaires, ce qu'on ne teste pas, et les outils du module.
- [ ] `RB-290-test-de-charge.md` est publié : production exclue, recette comme cible, annonce, arrêt, nettoyage.

**Vérification** : `lab/bin/check 29 12` (présence des parties ; la qualité s'auto-évalue avec le corrigé)

<details><summary>Indice 1</summary>

Pour chaque ligne du tableau, demande-toi : « si ce test disparaissait demain, qui s'en apercevrait, et quand ? ». S'il n'y a pas de réponse, il manque un propriétaire ou une alerte.
</details>

<details><summary>Indice 2</summary>

La liste de ce qu'on ne teste pas est la partie la plus utile pour un auditeur : elle montre que les angles morts sont **connus**. Pense au matériel, à `pve01` lui-même, aux sauvegardes hors site, à la production, aux dépendances externes.
</details>

**Pour aller plus loin** (facultatif) : ajoute à la stratégie un indicateur mensuel (par exemple : part des MR de plateforme bloquées par la CI et confirmées comme de vrais défauts) et sa source.
