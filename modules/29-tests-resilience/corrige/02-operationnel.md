# Module 29 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les fichiers complets sont dans [`fichiers/`](fichiers/) (`M29-E06` à `M29-E12`), rangés comme les dépôts : `resilience/` (`plateforme/resilience`), `ansible/`, `tofu-modules/`, `infra/`, `gitops/`, `k8s/`, `charts-miroir/`, `politiques/`, `ci-templates/`, `medisphere/` (documentation). Les fichiers `*.extrait*` sont des **morceaux** à insérer dans un fichier existant du dépôt, pas des fichiers complets.

**Ce qui a été vérifié à la rédaction**
- E06 : `parcours-recette.js` lancé avec k6 1.8.2 contre MédiAgenda (code de `apps/mediagenda`) servi localement avec les doublures en mémoire de ses tests (latence simulée) ; `k6 inspect` (2 scénarios, 6 métriques à seuils) ; résumé JSON écrit dans `charge/resultats/` quand k6 est lancé depuis la racine du dépôt.
- E07 : rôle `goss` passé à `ansible-lint` (profil `production`) ; fichier de tests rendu et validé par `goss render` (Goss 0.4.10, archive vérifiée par empreinte) ; règles `goss.yml` vérifiées et testées par `promtool check rules` et `promtool test rules` (Prometheus 3.13.5, `SUCCESS`).
- E08 : `go vet` et compilation du test avec l'étiquette `integration` (Go 1.26, Terratest 1.0.1, `go.sum` produit par le proxy Go) ; `tofu validate` de la configuration de test (OpenTofu 1.13.0, `bpg/proxmox` 0.116.x) ; comportement de `go test -timeout` (panique **sans** `t.Cleanup` ni `defer`) rejoué ; suppression des ACL `/vms/<vmid>` à la destruction d'une VM lue dans le code de `qemu-server` (`remove_vm_access`).
- E09 : valeurs relues dans l'archive du chart 2.8.6 (`helm show values`, empreinte `1a394742…59b1`) ; rendu `helm template` (26 objets) et tous les manifestes validés par kubeconform avec les schémas convertis des CRD de Chaos Mesh 2.8.6 et de cert-manager ; annotation aléatoire `rollme` constatée dans le rendu.
- E10 : image d'outils : empreintes de kubeconform, conftest, OPA, kustomize, helm, yq relevées dans les fichiers de sommes publiés ; règles `rego/kubernetes/` (13 tests `opa test` réussis) ; syntaxe YAML du composant et des extraits.
- E11 : la version de Lucas rejouée (OPA 1.21 : erreurs d'analyse ; une fois la syntaxe corrigée, conftest `--namespace tofu` : « 0 tests » et code 0 ; son test k6, 10 s contre le MédiAgenda local : 100 % de checks verts, 50 % de requêtes en échec, 1 627 itérations perdues, code 0) ; versions corrigées : `opa check --strict` et 7 tests réussis, script k6 corrigé sans échec.

**Non testé en conditions réelles** (à vérifier sur ton lab et à signaler s'il diffère) : l'installation de Chaos Mesh 2.8.6 sur Kubernetes 1.36 (compatibilité non annoncée par le projet à la rédaction) et l'injection elle-même ; la ValidatingAdmissionPolicy `medisphere-chaos-espaces` (d'où le passage obligatoire par `[Warn, Audit]`) ; les noms exacts des règles Falco déclenchées par le `chaos-daemon` ; les sous-pools Proxmox (`lab/terratest`) avec ton jeton et ta version de PVE ; le test Terratest de bout en bout sur `pve01` ; le composant `validation` dans **ton** GitLab (droits des jetons de job, `CI_MERGE_REQUEST_LABELS`) ; les sondes `goss` vues par **ton** `mon01`.

---

### M29-E06 — k6 en profondeur : scénarios, seuils des SLO, métriques

**Solution**

Script : [`fichiers/M29-E06/resilience/charge/parcours-recette.js`](fichiers/M29-E06/resilience/charge/parcours-recette.js) (il importe `lib/commun.js` d'E05) ; mode d'emploi des résultats : [`charge/resultats/LISEZMOI.md`](fichiers/M29-E06/resilience/charge/resultats/LISEZMOI.md).

- Scénario `lecture` : `constant-arrival-rate`, `LECTURE_RPS` (20) par seconde, `preAllocatedVUs` ≈ débit, `maxVUs` = 5 × débit, étiquette `parcours: lecture` ; il tire un couple (praticien, jour) parmi `VARIETE` (200 par défaut).
- Scénario `reservation` : `ramping-arrival-rate` de 1 à `RESERVATION_RPS` (5) en 1 min, palier `DUREE`, descente 30 s ; groupe « réserver puis annuler » ; étiquette `parcours: reservation`.
- Seuils : `sous_250ms: rate>0.95` (métrique `Rate` alimentée par `durée < 250` à chaque réponse : la définition du SLO), `http_req_duration{parcours:lecture}: p(95)<250`, `http_req_duration{parcours:reservation}: p(95)<250, p(99)<1000`, `http_req_failed: rate<0.005` et `rate<0.05` avec `abortOnFail` (après 30 s), `dropped_iterations: count<10`, `checks: rate>0.999`.
- `setup()` : `GET /pret`, sinon `exec.test.abort()` ; `teardown()` : liste des rendez-vous, suppression des seuls `dr-k6-*`.
- `handleSummary()` : texte sur la sortie standard, JSON `{ "resume": …, "k6": … }` dans `charge/resultats/<date>-parcours-recette.json` (ou `-e RESULTAT=…`).

```
admin@adm01:~/src/resilience$ k6 inspect charge/parcours-recette.js | jq '{scenarios: (.scenarios|keys), seuils: (.thresholds|keys)}'
admin@adm01:~/src/resilience$ k6 run -e RESULTAT=charge/resultats/2026-10-23-cache-froid.json charge/parcours-recette.js
admin@adm01:~/src/resilience$ k6 run -e VARIETE=1 -e RESULTAT=charge/resultats/2026-10-23-cache-chaud.json charge/parcours-recette.js
parcours-recette sur https://mediagenda-recette.apps.par1.medisphere.internal : seuils respectés
  sous 250 ms : 99.31 %   p95 : 41.2 ms   p99 : 187.0 ms
  …
```
(Chiffres d'exemple : les tiens dépendent de la recette.)

Corrélation, sur la fenêtre exacte du test (Grafana, ou API de Prometheus avec `start`/`end`) :
```
sum(rate(mediagenda_http_request_duration_seconds_bucket{namespace="mediagenda-recette",le="0.25"}[1m]))
  / sum(rate(mediagenda_http_request_duration_seconds_count{namespace="mediagenda-recette"}[1m]))
sum by (route) (rate(mediagenda_http_requests_total{namespace="mediagenda-recette"}[1m]))
sum by (resultat) (rate(mediagenda_cache_total{namespace="mediagenda-recette"}[1m]))
kube_horizontalpodautoscaler_status_current_replicas{namespace="mediagenda-recette", horizontalpodautoscaler="mediagenda"}
```

L'analyse suit le plan du `LISEZMOI` : conditions, client, serveur, écart, cache, HPA, conclusion.

**Explications**

Deux parcours n'ont ni le même volume ni le même coût : les mélanger dans un seul p95 cache le parcours qui casse. Les sous-métriques filtrées par étiquette (`{parcours:lecture}`) donnent un verdict par parcours sans dupliquer le script. La part sous 250 ms est la définition **exacte** du SLO (M21), alors qu'un p95 < 250 ms n'en est qu'une approximation (équivalente sur un échantillon, mais pas agrégeable). L'écart attendu entre k6 et Prometheus : k6 mesure TLS, passerelle, réseau et file d'attente côté serveur web, Prometheus le traitement dans l'application ; un écart de quelques millisecondes est normal, un écart qui grandit avec la charge dit que la file d'attente est **avant** l'application (passerelle, connexions, CPU du nœud). En cache froid, chaque lecture d'un couple nouveau fait une requête PostgreSQL (via le pooler) ; en cache chaud, presque tout est servi par Valkey : la différence de p95 mesure ce que le cache rapporte. L'HPA (M28) réagit sur l'utilisation CPU moyenne avec un délai (fenêtre de métriques, `behavior`) : sur un test de 5 minutes, le réplica supplémentaire peut arriver après le pic ; c'est une information pour la campagne (préchauffer, ou abaisser la cible).

**Alternatives**

- Un seul scénario `ramping-arrival-rate` avec une itération qui tire au sort lecture ou réservation : plus simple, mais un seul débit et pas de seuil par parcours.
- `--summary-export` (option historique) au lieu de `handleSummary` : écrit le résumé JSON standard sans le bloc de synthèse ni le contrôle du chemin ; `handleSummary` remplace l'affichage par défaut et permet d'écrire plusieurs fichiers.
- Envoyer les métriques de k6 dans Prometheus (`-o experimental-prometheus-rw`) : corrélation dans un seul outil ; c'est l'objet du palier 3 (k6-operator), avec la politique réseau qui va avec.

**Pièges classiques**

- `maxVUs` trop bas : k6 perd des itérations en silence (sauf seuil sur `dropped_iterations`) et le débit annoncé est faux.
- Un `sleep()` dans un scénario à taux d'arrivée : il n'abaisse pas le débit, il consomme des VUs.
- Comparer cache froid et cache chaud sans redémarrer ni attendre l'expiration du cache : le « froid » est tiède.
- Lancer k6 depuis `charge/` : le résumé part dans `charge/charge/resultats/`.
- Conclure sur un seul passage : rejouer au moins deux fois les mesures qui fondent une décision.

**En production chez MédiSphère**

Les résumés JSON versionnés deviennent la référence de non-régression (E14) ; la campagne réelle est précédée d'un test au débit prévu × 1,5 en recette ; les tests de charge sont annoncés selon RB-290 ; la production n'est observée que par ses SLO (Pyrra), jamais chargée.

---

### M29-E07 — Goss : la comparaison et les sondes de santé

**Solution**

- Rôle : [`fichiers/M29-E07/ansible/roles/goss/`](fichiers/M29-E07/ansible/roles/goss/) — `defaults/main.yml` (0.4.10, empreinte de `goss_0.4.10_linux_x86_64.tar.gz` relevée dans `goss_0.4.10_SHA256SUMS`, écoute `<adresse de service>:8099`, cache 30 s, versions attendues de node_exporter 1.12.1 et Alloy 1.21.1, sources NTP `.2`/`.3`) ; `tasks/main.yml` (téléchargement **sur le contrôleur** avec `checksum: sha256:…`, extraction, copie, gabarit validé par `validate: goss --gossfile %s render`, unité, service) ; `templates/goss-serve.service.j2` (`DynamicUser=yes`, `ExecStart=… serve --listen-addr … --format json --cache 30s`, durcissement systemd) ; `templates/goss.yaml.j2` ; `handlers/main.yml`.
- Playbooks : [`goss-essai.yml`](fichiers/M29-E07/ansible/playbooks/goss-essai.yml) (`hosts: dns02:nbx01`) et [`goss-retrait.yml`](fichiers/M29-E07/ansible/playbooks/goss-retrait.yml).
- Flux : extraits `host_vars/dns02|nbx01/pare_feu_local.yml.extrait` (source 10.10.20.19, TCP 8099).
- `mon01` : groupe de sondes `goss` ([extrait](fichiers/M29-E07/ansible/inventories/lab/host_vars/mon01/supervision_temoin.yml.extrait)), module `goss_sante` ([extrait](fichiers/M29-E07/ansible/roles/supervision_temoin/templates/blackbox-module-goss.extrait.yml)), règles [`goss.yml`](fichiers/M29-E07/ansible/roles/supervision_temoin/files/regles/goss.yml) et leurs tests [`goss.test.yml`](fichiers/M29-E07/ansible/roles/supervision_temoin/files/regles/goss.test.yml) ; `SondeEnEchec` modifiée ([extrait](fichiers/M29-E07/ansible/roles/supervision_temoin/templates/regles-temoin.extrait-M29.yml.j2)) : `probe_success{job="blackbox", groupe!="goss"} == 0`.
- Documents : [`testinfra-goss.md`](fichiers/M29-E07/medisphere/docs/qualite/testinfra-goss.md), [`RB-291`](fichiers/M29-E07/medisphere/docs/qualite/runbooks/RB-291-sonde-goss.md).

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/goss-essai.yml
admin@adm01:~$ ssh admin@mon01 'curl -s -o /dev/null -w "%{http_code}\n" http://nbx01.par1.medisphere.internal:8099/healthz'
200
admin@adm01:~$ ssh admin@nbx01 'sudo systemctl stop alloy'; sleep 35
admin@adm01:~$ ssh admin@mon01 'curl -s http://nbx01.par1.medisphere.internal:8099/healthz | jq ".summary"'
{ "failed-count": 2, "summary-line": "Count: 14, Failed: 2, Skipped: 0, Duration: …", … }
admin@adm01:~$ ssh admin@nbx01 'sudo systemctl start alloy'
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/supervision-temoin.yml
```

**Explications**

`goss serve` exécute les tests à la demande (avec un cache, pour qu'une sonde toutes les 30 s ne relance pas tout) et répond 200 ou 503 : le blackbox en fait une sonde comme une autre. Une sonde qui reçoit 503 a `probe_success == 0`, exactement comme une VM injoignable ; sans précaution, un test de conformité rouge déclencherait l'alerte **critique** `SondeEnEchec` et réveillerait l'astreinte. D'où le groupe `goss` exclu de `SondeEnEchec` et deux alertes dédiées, d'importance « avertissement » : `TestsGossEnEchec` (`probe_http_status_code == 503` pendant 15 min : la VM répond, des tests sont rouges) et `SondeGossMuette` (pas de réponse HTTP du tout : service arrêté, pare-feu). `DynamicUser=yes` fait tourner Goss sans privilège, au prix de tests impossibles (fichiers de root, `sshd -T`) : c'est une des lignes de la comparaison.

**Alternatives**

- Goss lancé par une minuterie systemd qui écrit un fichier lu par le *textfile collector* de node_exporter : pas de port supplémentaire, résultats en métriques (une par test) ; plus d'entretien.
- `goss serve --format prometheus` : expose des métriques par test plutôt qu'un 200/503 ; nécessite une cible de collecte (`scrape`) plutôt qu'une sonde.
- Testinfra seul, plus souvent (toutes les heures) : pas de nouveau composant, mais pas de vue continue.

**Pièges classiques**

- Chercher un binaire `goss-linux-amd64` dans la publication 0.4.10 : ce sont désormais des archives.
- `goss serve -l` : selon les versions, l'option courte collisionne ; utiliser `--listen-addr`.
- Écouter sur toutes les adresses (`:8099`) : le port s'ouvre sur toutes les interfaces ; l'adresse de service et le pare-feu local limitent l'exposition à `mon01`.
- Des tests Goss qui recopient les valeurs du rôle à la main : ils divergent ; les valeurs viennent des mêmes variables.

**En production chez MédiSphère**

La décision proposée (testinfra-goss.md) garde Testinfra et retire l'essai Goss (`goss-retrait.yml`), faute de valeur ajoutée suffisante par rapport à la supervision existante (node_exporter, Alloy, OpenSCAP hebdomadaire) ; l'ADR-0290 (E17) la confirme ou non. Si Goss était retenu : un fichier de tests par rôle, rendu par le rôle lui-même, et la sonde dans le tableau de bord de conformité.

---

### M29-E08 — Terratest : tester le module `vm-debian`

**Solution**

1. Go sur `adm01` (même principe sur `runner01`, par le rôle `gitlab_runner`) :
   ```
   admin@adm01:~$ V=1.26.10; cd "$(mktemp -d)"
   admin@adm01:/tmp/tmp.G$ curl -fsSLO "https://go.dev/dl/go$V.linux-amd64.tar.gz"
   admin@adm01:/tmp/tmp.G$ curl -fsS 'https://go.dev/dl/?mode=json&include=all' \
       | jq -r --arg f "go$V.linux-amd64.tar.gz" '.[].files[] | select(.filename == $f) | "\(.sha256)  \(.filename)"' | sha256sum --check
   admin@adm01:/tmp/tmp.G$ sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf "go$V.linux-amd64.tar.gz" && /usr/local/go/bin/go version
   ```
   (Prends la dernière corrective de la 1.26 au moment où tu le fais.)
2. Identité : [`fichiers/M29-E08/infra/outils/proxmox/pve-terratest-compte.sh`](fichiers/M29-E08/infra/outils/proxmox/pve-terratest-compte.sh), en root sur `pve01`. Il crée le sous-pool `lab/terratest`, le rôle `WBTerratest` (création, configuration, alimentation, agent, destruction) posé sur `/pool/lab/terratest`, le rôle `WBTerratestModele` (`VM.Audit`, `VM.Clone`) posé sur `/vms/<id>` des **seuls** modèles dorés 9010-9029, `PVEDatastoreUser` sur `local-nvme`, `PVESDNUser` sur le VNet `vsandbox`, et un jeton à séparation de privilèges valable 90 jours. Contrôle :
   ```
   root@pve01:~# pveum user token permissions wb-terratest@pve terratest --path /pool/lab/terratest
   root@pve01:~# pveum user token permissions wb-terratest@pve terratest --path /pool/lab
   root@pve01:~# pveum user token permissions wb-terratest@pve terratest --path /vms/1008
   ```
   Le deuxième et le troisième ne doivent montrer aucun privilège d'écriture. Exemple du fichier d'environnement : [`adm01-pve-terratest.env.exemple`](fichiers/M29-E08/adm01-pve-terratest.env.exemple).
3. Test : [`tofu-modules/vm-debian/test/`](fichiers/M29-E08/tofu-modules/vm-debian/test/) — `go.mod`, `go.sum`, `doc.go`, `vm_debian_test.go` (`//go:build integration`, `TestVmDebian`), `apis_test.go` (petits clients de l'API Proxmox et de NetBox : VMID libre, ressource de la VM, adresses de l'agent, nombre d'adresses dans NetBox), configuration [`fixtures/vm/`](fichiers/M29-E08/tofu-modules/vm-debian/test/fixtures/vm/) (module `../../..`, sous-pool, `vsandbox`, étiquettes, variables validées, sans *backend*).
4. Lancement :
   ```
   admin@adm01:~/src/tofu-modules/vm-debian/test$ set -a; . ~/.config/workbook/pve-terratest.env; . ~/.config/workbook/netbox-tofu.env; set +a
   admin@adm01:~/src/tofu-modules/vm-debian/test$ go test -tags integration -run TestVmDebian -timeout 35m -count=1 -v ./...
   ```
5. Échec provoqué (par exemple `assert.Equal(t, "lab", vm.Pool)`) : le sous-test échoue, `t.Cleanup` détruit la VM puis vérifie qu'elle n'existe plus et que NetBox a rendu l'adresse.
6. CI : [`tofu-modules/gitlab-ci.extrait-M29.yml`](fichiers/M29-E08/tofu-modules/gitlab-ci.extrait-M29.yml) — `terratest:vm-debian` (manuel, `resource_group: terratest`, `timeout: 40m`, `go test … -timeout 35m`, journal en artefact, variables protégées) et `terratest:compiler` (`gofmt`, `go vet -tags integration`, à chaque MR, ne crée rien).
7. [`RB-293`](fichiers/M29-E08/medisphere/docs/qualite/runbooks/RB-293-vms-de-test-orphelines.md).

**Explications**

- *Isolation* : nom `tt-` + `random.UniqueID()` en minuscules (6 caractères), premier VMID libre de 2290-2299 lu dans `/cluster/resources`, copie du module dans un dossier temporaire (`test_structure.CopyTerraformFolderToTemp`) : deux lancements ne partagent ni nom, ni VMID, ni état.
- *`TerraformBinary: "tofu"`* : sans lui, Terratest prend `terraform` s'il est dans le `PATH` (un poste où les deux cohabitent testerait autre chose).
- *Destruction garantie* : `t.Cleanup` enregistré **avant** `InitAndApply` ; les fonctions de nettoyage s'exécutent dans l'ordre inverse de leur enregistrement : d'abord `Destroy`, ensuite la vérification que rien ne reste.
- *Les délais* : quand `go test -timeout` expire, le binaire **panique** et s'arrête **sans** exécuter `t.Cleanup` ni `defer` (vérifié). Le test borne donc ses attentes par une échéance interne, `t.Deadline()` moins 8 minutes (`margeDestruction`), et `cloud-init status --wait` par `timeout 600` ; `go test -timeout 35m` ; job `timeout: 40m` (le journal et le message de Go sont conservés). L'emboîtement protège des attentes sans fin ; il ne protège pas d'une création de VM qui bloque elle-même au-delà de l'échéance (fournisseur), d'où RB-293 et le nettoyage du palier 4.
- *L'identité* : Proxmox **supprime les ACL** posées sur `/vms/<vmid>` quand la VM est détruite (`remove_vm_access` dans `qemu-server`) ; des ACL par VMID disparaîtraient après le premier test. Un pool survit aux VMs, et une VM créée dans le pool hérite de ses droits ; le clonage vers un pool exige `VM.Allocate` sur ce pool et `VM.Clone` sur le modèle. Le sous-pool `lab/terratest` (pools imbriqués, PVE ≥ 8.1) reste dans le pool `lab`, donc dans le périmètre des droits de `wb-tofu` et des inventaires.
- *Étiquette de construction* : sans `-tags integration`, `go test ./...` (ou un `go vet` d'outillage) ne compile même pas le test : aucune VM n'est créée par accident.

**Alternatives**

- `tofu test` avec un vrai fournisseur (`command = apply` dans un bloc `run`) : crée de vraies ressources sans Go ; les vérifications « dans » la VM (SSH, cloud-init, agent) sont alors à faire par des sources de données ou des `check`, moins naturellement qu'en Go.
- Kitchen-Terraform (Ruby, InSpec) : approche proche, écosystème en déclin.
- Tester le module **dans** une VM imbriquée jetable : isolation parfaite, coût et durée bien supérieurs.

**Pièges classiques**

- ACL posées par VMID : le test passe une fois, puis plus jamais (403 au clonage suivant).
- `VM.Clone` donné sur `/pool/lab` : le jeton peut copier le disque de n'importe quelle VM du lab.
- `defer terraform.Destroy` placé **après** `InitAndApply` : si la création échoue à moitié (`require` arrête le test), rien n'est détruit.
- Compter sur `go test -timeout` pour déclencher le nettoyage.
- Un DHCP supposé : le module `vm-debian` v2 alloue l'adresse dans NetBox (M06) ; le test le vérifie et vérifie qu'elle est rendue.
- Lancer deux tests en parallèle sans `resource_group` : deux VMs peuvent prendre le même VMID libre.

**En production chez MédiSphère**

Le test est lancé avant toute fusion qui change la création des VMs (règle d'équipe, rappelée dans la MR) ; un pipeline planifié de nettoyage (palier 4) applique RB-293 aux VMs du sous-pool de plus de 2 heures ; le jeton expire et se renouvelle à la revue trimestrielle des accès ; le coût (≈ 10 minutes, 1 Go) est noté dans la stratégie de tests (E12).

---

### M29-E09 — Chaos Mesh : installer avec des garde-fous

**Solution**

1. Chart et valeurs :
   ```
   admin@adm01:~$ helm show values oci://registry.par1.medisphere.internal/charts/chaos-mesh --version 2.8.6 > /tmp/cm-values.yaml
   admin@adm01:~$ yq '.controllerManager.enableFilterNamespace, .chaosDaemon.runtime, .chaosDaemon.socketPath, .dashboard.create, .dashboard.securityMode, .dnsServer.create, .webhook.certManager.enabled' /tmp/cm-values.yaml
   ```
   Entrée du miroir : [`charts.yaml.extrait`](fichiers/M29-E09/charts-miroir/charts.yaml.extrait).
2. Espaces et droits : [`k8s/espaces/chaos-mesh.yaml`](fichiers/M29-E09/k8s/espaces/chaos-mesh.yaml) (PSA `enforce: privileged`, `audit` et `warn` en `restricted` pour garder la trace) ; [`k8s/espaces/chaos-experiences/`](fichiers/M29-E09/k8s/espaces/chaos-experiences/) (`restricted`, `ResourceQuota` sur `count/podchaos.chaos-mesh.org`… et `pods: "0"`, ClusterRoles `chaos-experimentateur` et `chaos-lecteur` liées dans `chaos-experiences` **et** dans les trois espaces visables) ; [`k8s/rbac/wb-checks-services-m29.yaml`](fichiers/M29-E09/k8s/rbac/wb-checks-services-m29.yaml) (lecture de `chaos-mesh.org`, de `k6.io` et des politiques d'admission, agrégée à `wb-checks-services`).
3. Politique : [`k8s/admission/50-chaos-espaces.yaml`](fichiers/M29-E09/k8s/admission/50-chaos-espaces.yaml) — `ValidatingAdmissionPolicy` en CEL : (1) annotation `chaos-mesh.org/inject=enabled` refusée sur tout espace hors de la liste ; (2) objet `chaos-mesh.org` refusé hors de `chaos-experiences` ; (3) `spec.selector.namespaces` (et celui des modèles de `Schedule`/`Workflow`) inclus dans la liste. `matchConditions` exclut le compte de service du contrôleur (`system:serviceaccount:chaos-mesh:chaos-controller-manager`), qui crée lui-même des objets internes (`PodNetworkChaos`…) dans les espaces visés. Liaison d'abord en `[Warn, Audit]`, puis `[Deny]`.
4. `hostPath` : [extrait](fichiers/M29-E09/k8s/admission/20-interdire-hostpath.extrait-M29.yaml) (`chaos-mesh: "/run/containerd,/sys,/lib/modules"`). Falco : [extrait](fichiers/M29-E09/politiques/falco/regles-medisphere.extrait-M29.yaml) (exception ajoutée aux règles observées, limitée à l'espace `chaos-mesh` et à l'image du cache Harbor). Registre : [extrait](fichiers/M29-E09/medisphere/docs/securite/durcissement/exceptions.extrait-M29.md) (EXC-K-005, EXC-K-006, EXC-D-002).
5. Valeurs et Application : [`valeurs/chaos-mesh/values.yaml`](fichiers/M29-E09/gitops/valeurs/chaos-mesh/values.yaml), [`plateforme/chaos-mesh.yaml`](fichiers/M29-E09/gitops/plateforme/chaos-mesh.yaml) — filtre d'espaces, runtime `containerd` et son socket, images et image `pause` par Harbor, pas de tableau de bord (mais `securityMode: true`, qui garde le webhook de vérification des droits), pas de DNS, certificats des webhooks par cert-manager, `chaosdSecurityMode: false` ; dans l'Application : `ServerSideApply=true`, `CreateNamespace=false`, `ignoreDifferences` sur l'annotation `rollme` avec `RespectIgnoreDifferences=true`.
   ```
   admin@adm01:~/src/gitops$ SCHEMAS=~/schemas-crd outils/rendre-charts.sh /tmp/rendu && kubeconform -strict -summary -schema-location default \
       -schema-location "$HOME/schemas-crd/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" /tmp/rendu/chaos-mesh.yaml
   admin@adm01:~$ kubectl -n chaos-mesh get deploy chaos-controller-manager -o json | jq -r '.spec.template.spec.containers[0].env[] | select(.name|test("FILTER_NAMESPACE|SECURITY_MODE")) | "\(.name)=\(.value)"'
   ENABLE_FILTER_NAMESPACE=true
   SECURITY_MODE=true
   admin@adm01:~/src/k8s$ outils/schemas-crd.sh generer && outils/schemas-crd.sh publier 2026.10.23-1
   ```
6. Annotations : extraits pour [`mediagenda-recette`](fichiers/M29-E09/k8s/espaces/mediagenda-recette/00-namespace.extrait-M29.yaml), [`medinotif-recette`](fichiers/M29-E09/k8s/espaces/medinotif-recette/00-namespace.extrait-M29.yaml), [`wb-essais`](fichiers/M29-E09/k8s/espaces/wb-essais.extrait-M29.yaml). Contrôle du refus :
   ```
   admin@adm01:~$ kubectl annotate ns mediagenda-prod chaos-mesh.org/inject=enabled --dry-run=server
   Error from server (Forbidden): … ValidatingAdmissionPolicy 'medisphere-chaos-espaces' … denied request: …
   ```
7. Filtre : [`00-temoin-wb-essais.yaml`](fichiers/M29-E09/resilience/chaos/e09/00-temoin-wb-essais.yaml) puis [`02-temoin-filtre.yaml`](fichiers/M29-E09/resilience/chaos/e09/02-temoin-filtre.yaml) **avant** l'annotation : l'objet est créé, `kubectl -n chaos-experiences describe podchaos e09-temoin-filtre` montre `Selected: False` et un événement « no pod is selected » ; après l'annotation (MR fusionnée), le même objet recréé tue le pod témoin.
8. [`RB-292`](fichiers/M29-E09/medisphere/docs/qualite/runbooks/RB-292-arret-chaos.md) et première expérience [`01-pod-failure-api.yaml`](fichiers/M29-E09/resilience/chaos/e09/01-pod-failure-api.yaml) :
   ```
   admin@adm01:~/src/resilience$ kubectl apply -f chaos/e09/01-pod-failure-api.yaml
   admin@adm01:~$ kubectl -n mediagenda-recette get pods -l app.kubernetes.io/component=api -w
   admin@adm01:~$ kubectl -n chaos-experiences annotate podchaos e09-pod-failure-api experiment.chaos-mesh.org/pause=true
   admin@adm01:~$ kubectl -n chaos-experiences delete podchaos e09-pod-failure-api
   ```
   Documentation d'exploitation : [`docs/qualite/chaos-mesh.md`](fichiers/M29-E09/medisphere/docs/qualite/chaos-mesh.md).

**Explications**

Les garde-fous sont **empilés** et indépendants : (1) le filtre d'espaces du contrôleur ne sélectionne que des pods d'espaces annotés ; (2) la VAP rend la liste des espaces annotés immuable hors MR et refuse les cibles hors liste avant même que l'objet existe ; (3) le webhook `validate-auth` (mode de sécurité) vérifie par `SubjectAccessReview` que l'auteur a le droit de créer ce type d'expérience **dans chaque espace visé** : d'où les RoleBindings dans les trois espaces ; (4) le quota borne le nombre d'objets ; (5) la règle Rego d'E10 refuse une expérience sans durée dans les MR. Aucun ne dépend de la prudence de la personne. `pod-failure` remplace l'image des conteneurs du pod par l'image `pause` pendant la durée : le pod reste, non prêt, et le Service le retire ; à la fin, l'image d'origine est remise (le conteneur redémarre). Le `chaos-daemon` doit être privilégié (il entre dans les espaces de noms des conteneurs par le socket du runtime) : l'exception PSA et les chemins `hostPath` sont écrits et compensés, pas cachés.

**Alternatives**

- **LitmusChaos 3** : expériences en hub, ChaosCenter (interface, MongoDB, sous-chart Bitnami interdit chez nous) : voir la fiche.
- Des pannes « à la main » (`kubectl delete pod`, `tc` dans un conteneur de débogage) : suffisant pour un essai, sans durée garantie, sans retour arrière automatique, sans trace.
- Le tableau de bord de Chaos Mesh derrière OIDC : pratique pour les équipes, mais une interface qui crée des expériences avec **ses** droits ; refusé ici.

**Pièges classiques**

- Oublier `ServerSideApply` : la synchronisation échoue sur la taille des CRD.
- Laisser l'annotation `rollme` sans `ignoreDifferences` : Argo CD voit l'Application désynchronisée en permanence et redémarre le contrôleur et les démons à chaque synchronisation.
- `dashboard.create: false` en croyant que `securityMode` ne sert qu'au tableau de bord : c'est lui qui garde le webhook de vérification des droits.
- Lier `chaos-experimentateur` dans `chaos-experiences` seulement : le webhook refuse les expériences (le demandeur n'a pas de droit dans l'espace visé).
- Exclure **tous** les comptes de service de la VAP : un pipeline compromis pourrait annoter n'importe quel espace.
- Croire qu'une expérience qui ne sélectionne rien a été refusée : elle existe, elle attend.
- Supprimer un objet de chaos et ne pas vérifier que la panne est retirée (finaliseur `chaos-mesh/records`, RB-292).

**En production chez MédiSphère**

Ajout d'un espace visable = MR sur la VAP et sur l'espace, relue par Sophie ; journées de jeu planifiées (palier 3) ; alerte si un objet de chaos existe depuis plus que sa durée ; Chaos Mesh mis à jour avec ses CRD (application côté serveur) et le paquet `schemas-crd` republié dans la foulée.

---

### M29-E10 — Le composant `validation` : une pyramide de tests en CI

**Une solution possible** (exercice libre : d'autres découpages sont valables s'ils remplissent les critères).

- Composant : [`ci-templates/templates/validation/template.yml`](fichiers/M29-E10/ci-templates/templates/validation/template.yml), publié en `v2.11.0`. Entrées : `stage`, `runner` (`k8s`), `image` (étiquette **et** empreinte, contrôlées par une expression rationnelle), `version_kubernetes`, `schemas_crd_version` (format `AAAA.MM.JJ[-N]`), `politiques_ref` (étiquette `vX.Y.Z` seulement), `manifestes`, `overlays` (tableaux), `charts_argocd`, `regles_kubernetes`, `tests_rego`, `testinfra` (booléens), `testinfra_hotes`.
  - `validation:manifestes` : télécharge le paquet `schemas-crd` avec `CI_JOB_TOKEN` et contrôle son empreinte ; récupère `rego/kubernetes` de `plateforme/politiques` à l'étiquette donnée ; rend les overlays (`kustomize build`) et, si demandé, les charts (`outils/rendre-charts.sh`) ; `kubeconform -strict` avec les schémas `default` et ceux du paquet (sortie JUnit) ; `conftest test --namespace kubernetes`.
  - `validation:rego` (dans `plateforme/politiques`) : `opa check --strict`, `opa fmt --fail --list`, `opa test` sur des racines explicites, `conftest verify`, et les plans d'exemple.
  - `.validation:conftest-plan` (modèle caché) : un script à appeler **dans** le job de plan, qui écrit `contexte.json` (dossier de la configuration, étiquettes de MR découpées), produit le JSON dans un dossier temporaire, lance conftest et le supprime.
  - `validation:testinfra` : n'étend **pas** `.socle` (le composant ne connaît pas les modèles du consommateur) ; `plateforme/ansible` complète le job (`extends: .socle`) dans son `.gitlab-ci.yml`.
- Image : [`ci-templates/images/outils-validation/Dockerfile`](fichiers/M29-E10/ci-templates/images/outils-validation/Dockerfile) (versions et empreintes en `ARG`, `sha256sum --check` pour chaque binaire, utilisateur non root), construite, signée et poussée par la CI de `plateforme/ci-templates` comme les autres images d'outils.
- Règles Kubernetes : [`rego/kubernetes/`](fichiers/M29-E10/politiques/rego/kubernetes/) — `chaos.rego` (annotation hors liste, expérience sans durée, cible hors liste), `charges.rego` (conteneur sans limite de mémoire), `kubernetes_test.rego` (13 tests).
- Consommateurs : extraits pour [`k8s`](fichiers/M29-E10/k8s/gitlab-ci.extrait-M29.yml), [`gitops`](fichiers/M29-E10/gitops/gitlab-ci.extrait-M29.yml), [`infra`](fichiers/M29-E10/infra/gitlab-ci.extrait-M29.yml) (le job `.plan` existant reçoit `!reference [.validation:conftest-plan, script]` après `tofu plan`), [`ansible`](fichiers/M29-E10/ansible/gitlab-ci.extrait-M29.yml) (remplace le job `testinfra` d'E04), [`politiques`](fichiers/M29-E10/politiques/gitlab-ci.extrait-M29.yml) (`tests_rego: true`).
- Préalable : *Settings → CI/CD → Job token permissions* de `plateforme/k8s` et `plateforme/politiques` : autoriser les projets consommateurs.

**Explications**

Le composant porte la **mécanique** ; les **données** (schémas, politiques) sont versionnées à part et épinglées par chaque consommateur : monter de version de schémas ou de politiques est une MR visible, pas un changement silencieux. Le plan reste dans le job qui le produit : le seul artefact qui en sort est le verdict. La pyramide en CI : chaque MR fait tourner le statique et l'unitaire (secondes) ; Testinfra tourne la nuit ; Terratest reste manuel (E08) ; la charge et le chaos ne sont pas dans la CI.

**Alternatives**

- Un modèle `include: project:` au lieu d'un composant : pas d'entrées typées ni de catalogue ; c'était l'état d'avant le M19.
- Un job par outil dans chaque dépôt : duplication, versions divergentes.
- Des politiques vendues dans chaque dépôt (copie) : chacun dérive.

**Pièges classiques**

- `-ignore-missing-schemas` remis « pour faire passer » une MR : la règle d'équipe est de régénérer le paquet.
- Une image d'outils référencée par étiquette seule : elle peut changer sous le composant.
- Publier le plan JSON en artefact « pour déboguer ».
- `CI_MERGE_REQUEST_LABELS` lu dans un pipeline de branche : vide ; le contexte doit avoir un comportement défini (aucune étiquette = aucune destruction autorisée).
- Un composant qui référence `.socle` : erreur de configuration dans tout projet qui ne le définit pas.
- Jetons de job non autorisés : téléchargement du paquet en 404/403 dans les consommateurs.

**En production chez MédiSphère**

Les règles de protection de branche exigent un pipeline vert ; le composant suit le versionnement sémantique (changement d'entrée = version majeure) ; une montée de version des politiques passe d'abord en avertissement (`warn`) une semaine, puis en refus ; tableau de suivi des refus par règle pour repérer les règles mal comprises.

---

### M29-E11 — Revue : les politiques Rego et le test k6 du stagiaire

**Solution**

La revue complète : [`politiques/rego/revue-lucas/REVUE.md`](fichiers/M29-E11/politiques/rego/revue-lucas/REVUE.md) (13 défauts). Versions corrigées : [`garde-fous.rego`](fichiers/M29-E11/politiques/rego/revue-lucas/garde-fous.rego), [`garde-fous_test.rego`](fichiers/M29-E11/politiques/rego/revue-lucas/garde-fous_test.rego), [`creneaux-charge.js`](fichiers/M29-E11/resilience/charge/revue-lucas/creneaux-charge.js).

Preuves rejouées :
```
admin@adm01:~/src/politiques$ opa test rego/revue-lucas
… rego_parse_error: `if` keyword is required before rule body
admin@adm01:~/src/politiques$ conftest test --namespace tofu -p /tmp/lucas-v1 --data /tmp/ctx.json rego/exemples/plan-socle-remplacement.json; echo rc=$?
0 tests, 0 passed, 0 warnings, 0 failures, 0 exceptions
rc=0
admin@adm01:~/src/resilience$ k6 run -e BASE_URL=http://127.0.0.1:8000 /tmp/lucas-10s.js; echo rc=$?
     ✓ créneaux ok
     ✓ rdv ok
     checks.........................: 100.00% …
     http_req_failed................: 50.00% …
     dropped_iterations.............: 1627 …
rc=0
admin@adm01:~/src/politiques$ opa check --strict rego/revue-lucas && opa test -v rego/revue-lucas
PASS: 7/7
```
(`/tmp/lucas-v1` : les règles de Lucas passées en syntaxe v1 par `opa fmt --v0-v1`, sans autre changement ; `/tmp/lucas-10s.js` : son script avec `duration: '10s'`.)

Les défauts majeurs, en bref (détail, preuves et corrections dans `REVUE.md`) :

| # | Défaut | Gravité |
|---|---|---|
| 1 | Rego v0 : ne se charge pas avec OPA ≥ 1.0 (« vert chez moi » = OPA 0.68) | B |
| 2 | `package main.infra` hors de `--namespace tofu` : aucune règle évaluée, « 0 tests », code 0 | B |
| 3 | `rc.after` au lieu de `rc.change.after` | B |
| 4 | Plage 2000-2999 unique pour tous les états | M |
| 5 | Règle `refuser_destruction` ignorée par conftest | B |
| 6 | `actions[0] == "delete"` rate les remplacements `create_before_destroy` | M |
| 7 | Pool en `warn`, et champ absent = silence | M |
| 8 | Exigence d'étiquette fausse et mal écrite | M |
| 9 | Un seul test, qui ne vérifie que le cas conforme | M |
| 10 | Aucun seuil ; checks crus bloquants ; `status < 500` accepte 422 et 409 | B |
| 11 | `sleep` dans un taux d'arrivée, 50 VUs pour 500 it/s (= 1 500 req/s) : itérations perdues | M |
| 12 | Données de santé présentées comme réelles (export de production, NIR) | B |
| 13 | Production par défaut (et lancée), TLS non vérifié, créneau unique sans fuseau, rien annulé, URL non nommées, dépendance téléchargée à l'exécution | B |

**Explications**

Les deux MR ont le même défaut de fond : des tests **qui ne peuvent pas échouer**. Une politique dont aucune règle n'est lue, une règle sur un chemin qui n'existe pas, un test qui ne vérifie que le cas conforme, un test de charge sans seuil : tout est vert, et rien n'est vérifié. La méthode de revue est de construire, pour chaque règle et chaque affirmation, le cas qui **devrait** échouer, et de le faire tourner. Le défaut 12 n'est pas un défaut de code : un fichier qui se présente comme un export de patients, poussé dans un dépôt et envoyé vers la recette, est un **incident de données** (signalement à Sophie Laurent, ticket SEC-, purge de l'historique de la branche, vérification des accès à l'export), même si, dans le lab, les données sont inventées. Le défaut 13 « lancé hier à 18 h sur la production » appelle aussi une vérification côté production (Julien, Nadia).

**Alternatives**

Refuser les MR avec une liste de commentaires, sans version corrigée : plus rapide, moins formateur ; la version corrigée sur une branche séparée permet à Lucas de comparer ligne à ligne. Pour un stagiaire, une séance de relecture commune vaut mieux qu'un long commentaire.

**Pièges classiques**

- Croire « les tests passent » sans compter les tests exécutés.
- Rejouer le script de Lucas sur la recette (ou pire, sans changer sa cible).
- Supprimer `patients.csv` dans un nouveau commit et considérer l'affaire close : il reste dans l'historique et dans la MR.
- Corriger en silence : Lucas refera les mêmes erreurs.

**En production chez MédiSphère**

Détection de secrets et de données sensibles dans les MR (règles Gitleaks du M01 étendues aux formats de NIR) ; la commande conftest de la CI échoue si aucun test n'est exécuté (`opa test` avec un nombre minimal attendu, ou vérification du nombre de règles chargées) ; RB-290 pour tout test de charge.

---

### M29-E12 — Stratégie de tests de la plateforme

**Solution**

[`docs/qualite/strategie-tests.md`](fichiers/M29-E12/medisphere/docs/qualite/strategie-tests.md) et [`RB-290-test-de-charge.md`](fichiers/M29-E12/medisphere/docs/qualite/runbooks/RB-290-test-de-charge.md).

**Grille d'auto-évaluation**

| Critère | Attendu |
|---|---|
| Pyramide | les étages réellement en place, avec leurs outils et versions, du statique au chaos |
| Tableau des tests | chaque test : déclencheur (MR, nuit, manuel, planifié), durée, coût (temps, ressources, risque), propriétaire, où lire le résultat ; chaque ligne vérifiable dans GitLab |
| Règles | un test doit pouvoir échouer (cas rouge connu) ; rouge = blocage ou alerte, qui agit ; pas de désactivation sans ticket |
| Angles morts | ce qu'on ne teste pas, pourquoi, et quand on réexamine (ex. : la production n'est jamais chargée ni soumise au chaos ; le matériel et `pve01` lui-même ; la restauration hors site testée par d'autres exercices ; les dépendances externes) |
| Données | factices, préfixes `dr-k6-`, `tt-`, nettoyage, aucune donnée réelle |
| RB-290 | utilisable par Julien seul : annonce, cible recette, montée prudente, surveillance, critères d'arrêt, arrêt, nettoyage, rangement des résultats |

**Explications**

Une stratégie de tests sert d'abord à **décider** (où mettre l'effort suivant) et à **prouver** (à un auditeur que les risques sont connus). La partie la plus utile est souvent la liste de ce qu'on ne teste pas : elle transforme des angles morts en risques acceptés et datés.

**Pièges classiques**

- Un inventaire d'outils au lieu d'une stratégie (rien sur les déclencheurs, les coûts ni les propriétaires).
- Des promesses que la CI ne tient pas (« tests à chaque MR » pour un test manuel).
- Un runbook écrit pour soi : Julien doit pouvoir l'appliquer sans connaître k6 en détail.

**En production chez MédiSphère**

La stratégie est relue à chaque revue trimestrielle de la plateforme, avec l'indicateur proposé (défauts réels bloqués par la CI) ; elle est citée par l'ADR-0290 (E17) et par le dossier d'audit HDS.
