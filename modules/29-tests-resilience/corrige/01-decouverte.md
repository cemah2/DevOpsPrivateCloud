# Module 29 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les fichiers complets sont dans [`fichiers/`](fichiers/) : `M29-E02/k8s/` reproduit `plateforme/k8s`, `M29-E02/gitops/` `plateforme/gitops`, `M29-E03/politiques/` `plateforme/politiques`, `M29-E04/ansible/` `plateforme/ansible`, `M29-E05/resilience/` `plateforme/resilience`, `*/medisphere/` la documentation.

**Ce qui a été vérifié à la rédaction** (outils aux versions du bloc, binaires téléchargés depuis les publications officielles et contrôlés par empreinte) :
- kubeconform 0.8.0 : 32 CRD réelles (Argo CD, CNPG, cert-manager, Chaos Mesh 2.8.6…) converties par `openapi2jsonschema.py` v0.8.0 (empreinte `d145babf…81881f3`) ; un champ inconnu dans un `PodChaos` et dans une `Application` **accepté** avec le schéma brut (`jq .schema.openAPIV3Schema`), **refusé** (`additional properties … not allowed`) avec le schéma converti ; `-ignore-missing-schemas` → objet compté « Skipped », code 0 ; archive `tar` reproductible (deux générations, même empreinte) ; `rendre-charts.sh` sur l'Application `chaos-mesh` (26 objets rendus, tous valides).
- OPA 1.21.3 et conftest 0.71.1 : les règles de `rego/tofu/` (24 tests `opa test` réussis), `opa check --strict`, `opa fmt` sans différence ; les trois plans d'exemple construits à partir d'un vrai plan d'OpenTofu 1.13.0 avec le fournisseur `bpg/proxmox` 0.116.1 ; les contrôles du check (15 sur 15 sur ce corrigé, rouges sur la version de Lucas d'E11).
- pytest-testinfra 10.2.2 : 48 tests collectés (`--collect-only`, aucun hôte contacté), exécution par le connecteur `ansible://` sur un inventaire local.
- k6 1.8.2 : `premier-test.js` dans les deux modèles contre MédiAgenda (code de `apps/mediagenda`) servi localement avec les doublures en mémoire de ses tests ; `k6 inspect` refuse l'URL de production.

**Non testé en conditions réelles** (à vérifier sur ton lab, et à signaler s'il diffère) : la publication du paquet générique dans **ton** GitLab (API standard, non rejouée sur `git01`) ; la liste exacte des CRD de **ton** cluster (dépend des modules faits) ; les valeurs exactes attendues par `test_durcissement.py` sur tes VMs (elles reprennent le corrigé du M26) ; les chiffres de latence de la recette (le serveur local n'a ni réseau, ni PostgreSQL, ni Valkey réels).

---

### M29-E01 — Test de positionnement : tests et résilience

**Barème** : chaque question vaut 2 points (2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc). Total sur 24. Sous 12, lis l'introduction du module de près avant E02 ; les numéros d'exercice à côté de chaque réponse indiquent où la notion est travaillée.

**1. La pyramide** (E10, E12). (a) statique, chaque MR (secondes) ; (f) statique sur le plan, chaque MR **dans le job de plan** ; (c) unitaire, chaque MR de `plateforme/politiques` ; (d) intégration réelle, chaque nuit et à la demande (elle lit le parc, ne crée rien) ; (b) intégration réelle, **manuel** avant la fusion d'une MR qui touche le module (≈ 10 min, une VM, un quota de VMID) ; (e) charge, à la demande avant une campagne ou une version, en recette, annoncée ; (g) résilience, planifiée et annoncée, en heures ouvrées. Critères en plus du coût : la **fréquence de changement** de ce qui est testé (un module modifié deux fois par an n'a pas besoin d'un test à chaque MR d'un autre dossier) ; le **délai de retour** acceptable (un relecteur attend la CI) ; la **fiabilité** du test (un test instable placé à chaque MR finit ignoré) ; le **risque** qu'il fait courir (charge sur la recette, VM créée) ; et surtout ce qu'il détecte que les étages inférieurs **ne voient pas** : s'il ne détecte rien de plus, il ne mérite pas son coût.

**2. Réponse B.** Sans schéma, kubeconform signale normalement « could not find schema » et échoue ; avec `-ignore-missing-schemas`, il **saute** l'objet (compté *skipped* dans le résumé) et le code de sortie reste 0. `-strict` ne joue que quand un schéma existe (champs supplémentaires, clés dupliquées). A serait vrai **sans** l'option (erreur, mais pas pour la bonne raison : pour l'absence de schéma, pas pour la faute). C est faux : `-strict` ne transforme pas un saut en erreur. D est faux : kubeconform n'a pas de schéma générique de repli. Morale : l'option fait dire « vert » à une CI qui n'a rien lu.

**3. Schéma brut et `-strict`** (E02). Pour les objets standard, kubeconform en mode `-strict` prend la variante « stricte » des schémas de `kubernetes-json-schema`, générés avec `additionalProperties: false`. Pour un schéma fourni par toi, il l'utilise **tel quel**. Or l'`openAPIV3Schema` d'une CRD ne dit rien des propriétés supplémentaires ; en JSON Schema, l'absence de `additionalProperties` veut dire « tout est permis ». Le champ mal orthographié passe. Le convertisseur officiel de kubeconform (`scripts/openapi2jsonschema.py`) ajoute `additionalProperties: false` à chaque objet **imbriqué** qui déclare ses propriétés, et à la racine si la variable `DENY_ROOT_ADDITIONAL_PROPERTIES` est posée (sans elle, un `specc:` au premier niveau passerait encore) : c'est ce qui rend `-strict` utile sur les CRD. Côté cluster, la validation de champs côté serveur (`--validate=strict`, défaut de `kubectl` depuis 1.27) refuserait aussi le champ, mais trop tard : à l'application, pas en revue.

**4. Rego v1** (E03, E11). OPA 1.0 a fait de Rego v1 le langage par défaut : `if` obligatoire avant le corps d'une règle, `contains` obligatoire pour les règles à valeurs multiples (`deny contains msg if { … }`), mots-clés `in`, `every`, `if`, `contains` disponibles sans `import future.keywords` (et `import rego.v1` devenu inutile), quelques fonctions dépréciées retirées, vérifications plus strictes. Un fichier `deny[msg] { … }` **ne se charge pas** : ``rego_parse_error: `if` keyword is required before rule body`` (et `` `contains` keyword is required for partial set rules ``). Migration : (1) `opa fmt --v0-v1 --write` réécrit les fichiers dans une syntaxe compatible v0 **et** v1 (`if`, `contains`, avec un `import rego.v1` ajouté, que `opa fmt --drop-v0-imports` retire une fois la migration terminée) ; relire le diff, relancer les tests ; (2) en transition, faire tourner l'ancien code en mode compatible (`opa … --v0-compatible`, `conftest … --rego-version v0`). Pour 40 fichiers : une MR de migration avec `opa fmt --v0-v1`, tests passés **avant** (en mode v0) et **après** (en v1), puis version d'OPA épinglée dans la CI pour que personne ne revienne en arrière ; le mode compatible ne sert qu'à découpler la montée de version d'OPA de la migration.

**5. Le plan JSON** (E03, E10). `tofu show -json` écrit **toutes** les valeurs connues, y compris celles marquées sensibles (`after_sensitive` ne fait que les signaler) : jetons, mots de passe cloud-init, clés. Publier le fichier comme artefact, c'est le rendre lisible par toute personne qui a accès aux artefacts du projet, pendant leur durée de rétention. Conftest tourne **dans le job qui produit le plan**, sur un fichier temporaire supprimé à la fin du script ; les messages des règles ne citent que des champs non sensibles (adresse, VMID, étiquettes). Le plan binaire (`plan.tfplan`) que le job d'apply réutilise contient les mêmes valeurs : artefact à durée courte, sur branche protégée, jamais téléchargeable par des rôles qui n'en ont pas besoin (M05). Les valeurs **éphémères** (OpenTofu ≥ 1.11) ne sont, elles, écrites ni dans le plan ni dans l'état.

**6. Testinfra, Goss, Molecule** (E04, E07). *Testinfra* : bibliothèque pytest (Python), s'exécute sur le **contrôleur** et interroge les hôtes par SSH, Ansible, `docker`…, sur n'importe quel parc. *Goss* : binaire unique, tests en YAML, s'exécute **sur** l'hôte (rapide, peu de dépendances), sait publier son résultat en HTTP (`goss serve`). *Molecule* : cadre de test de **rôles** sur des instances **jetables** (création, convergence, idempotence, vérification, destruction) ; son vérificateur peut être Ansible ou Testinfra. Sur le parc réel, Testinfra voit ce que Molecule ne peut pas voir : les **dérives** (modification à la main, autre rôle qui écrase un réglage, mise à jour de paquet), les combinaisons de rôles réellement appliquées à un hôte, le réseau et le pare-feu réels, les données d'inventaire réelles. Risque : exécuter des commandes sur des machines de production avec un compte qui peut `sudo`. Limites : tests **en lecture seule** (aucune commande qui change l'état), parallélisme borné, clé de CI restreinte (`from=` du runner), `become` seulement là où c'est nécessaire, et revue des tests comme du code de production.

**7. Terratest coupé** (E08). Le job coupé tue `go test` : ni `defer` ni `t.Cleanup` ne s'exécutent, la VM reste, et son état local reste dans un dossier temporaire du runner que plus rien n'utilise (VM orpheline, RB-293). Il faut : (1) enregistrer la destruction **avant** `InitAndApply` (`t.Cleanup` ou `defer`), pour qu'elle s'exécute même si la création échoue à moitié ou si une assertion `require` arrête le test ; (2) emboîter les délais : les attentes du test (SSH, cloud-init, agent) bornées par une échéance **plus courte** que celle de `go test`, avec une marge pour la destruction ; puis `go test -timeout` ; puis le délai du job, plus long encore. Point essentiel, vérifié : quand `go test -timeout` expire, le binaire **panique** (« test timed out ») **sans** exécuter `t.Cleanup` ni `defer` ; c'est donc l'échéance interne du test, lue avec `t.Deadline()`, qui protège. Sans `-timeout`, `go test` applique son défaut de **10 minutes** : un test d'intégration qui dure 12 minutes panique à chaque fois et laisse sa VM. (3) Un nettoyage de rattrapage (runbook, puis pipeline planifié) pour ce qui échappe malgré tout.

**8. Réponse B.** Un VU fait une requête à la fois : 50 VUs × (1 / 2 s) = 25 requêtes/s (au début : 50 × 10 = 500 requêtes/s). Le modèle fermé **ralentit avec le serveur** et sous-estime le problème (omission coordonnée). A est faux : le nombre de VUs est constant, pas le débit. C est faux (calcul). D est faux : `constant-vus` ne crée pas de VUs ; c'est le rôle des exécuteurs à taux d'arrivée, dans la limite de `maxVUs`. Une campagne de vaccination est un modèle **ouvert** : `constant-arrival-rate` ou `ramping-arrival-rate`. Si k6 manque de VUs pour tenir le taux, il compte les itérations non lancées dans **`dropped_iterations`**.

**9. Percentiles.** (a) Oui : avec 93 % des requêtes autour de 50 ms, 3 % autour de 150 ms, 3 % autour de 500 ms et 1 % à 2 s, la moyenne est d'environ 0,93 × 50 + 0,03 × 150 + 0,03 × 500 + 0,01 × 2 000 ≈ 86 ms. (b) Part sous 250 ms : (9 300 + 300) / 10 000 = **96 %** ≥ 95 % : le SLO est tenu, de peu. (c) 100 requêtes (1 %) dépassent 1 s : le p99 est à la frontière ; le 99ᵉ centile tombe sur la 9 900ᵉ requête triée, qui est dans la tranche 250 ms-1 s : p99 < 1 s, mais tout juste (et le p99,5 est au-delà de 1 s). (d) Un percentile ne se moyenne pas : le pod à 900 ms peut porter 10 % ou 60 % du trafic, et le p95 global dépend de la **distribution** complète. On l'obtient en agrégeant les **seaux** de l'histogramme avant de calculer le quantile : `histogram_quantile(0.95, sum by (le) (rate(mediagenda_http_request_duration_seconds_bucket[5m])))` ; et pour le SLO, la part sous 250 ms : `sum(rate(…_bucket{le="0.25"}[5m])) / sum(rate(…_count[5m]))`.

**10. Réponse B.** Les `check()` alimentent la métrique `checks` mais ne font **jamais** échouer un test par eux-mêmes. Sans seuil, `k6 run` sort avec 0 (si le script ne lève pas d'exception). A : le code 99 est celui des **seuils** franchis, il en faut au moins un. C : aucune règle implicite de ce genre. D : 107 est une erreur de script (exception non rattrapée), pas un check raté. Pour qu'un check compte : `thresholds: { checks: ['rate>0.99'] }`.

**11. Une expérience complète** (E09, palier 3). *État stable* : part des requêtes de MédiAgenda (recette) servies sous 250 ms ≥ 95 % et taux d'erreurs 5xx < 0,5 %, sur 5 minutes glissantes : `sum(rate(mediagenda_http_request_duration_seconds_bucket{namespace="mediagenda-recette",le="0.25"}[5m])) / sum(rate(mediagenda_http_request_duration_seconds_count{namespace="mediagenda-recette"}[5m]))`. *Hypothèse* : « avec une charge de 20 lectures/s, la perte d'un pod de l'API pendant 60 s ne fait pas passer la part sous 250 ms sous 95 % ni les erreurs au-dessus de 0,5 % ». *Injection* : `PodChaos` `pod-failure`, `mode: one`, `duration: 60s`, sur `mediagenda-recette` seulement. *Rayon d'action* : un pod sur trois, une minute, la recette. *Arrêt* : si les erreurs dépassent 5 % ou si la recette ne revient pas à l'état stable en 2 minutes → pause par annotation, suppression, RB-292. *Si l'hypothèse tombe* : c'est un résultat ; on cherche pourquoi (sonde de disponibilité trop lente à retirer le pod, connexions gardées par la passerelle, `PodDisruptionBudget` absent, HPA à 1 réplica la nuit), on ouvre un ticket, on rejoue après correction. *Garde-fous indépendants de la bonne volonté* : filtre d'espaces de Chaos Mesh (seuls les espaces annotés sont visables) ; politique d'admission qui refuse l'annotation hors de la liste, les objets hors de `chaos-experiences` et les cibles hors de la liste ; RBAC (seul le groupe autorisé crée des expériences, le webhook en mode de sécurité vérifie les droits du demandeur sur les espaces visés) ; quota d'objets ; règle Rego qui refuse une expérience sans `duration` (E10).

**12. Architecture de Chaos Mesh** (E09, E24). Le **`chaos-daemon`** du nœud qui héberge le pod visé injecte la panne : le contrôleur reçoit l'expérience, sélectionne les pods, et demande (gRPC, mTLS) au démon du bon nœud d'agir ; le démon retrouve le conteneur par le **socket de containerd**, obtient son PID, **entre dans ses espaces de noms** (réseau pour `tc`/`iptables`/`ipset`, PID pour tuer ou figer un processus) et y exécute les outils. D'où : `privileged`, `hostPID`, montage du socket du runtime, de `/sys` (et parfois `/lib/modules`). Côté PSA, l'espace `chaos-mesh` doit être en `privileged` (exception écrite au registre, EXC-K-005, et chemins `hostPath` déclarés dans la VAP du M26) ; côté Falco, le démon déclenche des règles (entrée dans les espaces de noms, outils réseau, accès au socket du runtime) : exceptions **ciblées** sur ces conteneurs et cette image, au registre, sans désactiver les règles. Si une expérience vise un espace non annoté alors que le filtre est actif, elle **n'est pas refusée à la création** : elle existe, mais ne sélectionne aucun pod (condition `Selected` à `False`, événement « Failed … no pod is selected ») ; c'est la VAP (E09) qui refuse en amont une cible hors de la liste.

---

### M29-E02 — kubeconform : valider les manifestes avec leurs CRD

**Solution**

1. Installation vérifiée :
   ```
   admin@adm01:~$ V=0.8.0; cd "$(mktemp -d)"
   admin@adm01:/tmp/tmp.X$ curl -fsSLO https://github.com/yannh/kubeconform/releases/download/v$V/kubeconform-linux-amd64.tar.gz
   admin@adm01:/tmp/tmp.X$ curl -fsSLO https://github.com/yannh/kubeconform/releases/download/v$V/CHECKSUMS
   admin@adm01:/tmp/tmp.X$ grep ' kubeconform-linux-amd64.tar.gz$' CHECKSUMS | sha256sum --check
   kubeconform-linux-amd64.tar.gz: OK
   admin@adm01:/tmp/tmp.X$ tar -xzf kubeconform-linux-amd64.tar.gz kubeconform && sudo install -m 0755 kubeconform /usr/local/bin/ && kubeconform -v
   v0.8.0
   ```
2. Constat sans schémas de CRD, puis avec l'option interdite :
   ```
   admin@adm01:~/src/k8s$ K="-strict -summary -kubernetes-version 1.36.5 -ignore-filename-pattern kustomization\.yaml$"
   admin@adm01:~/src/k8s$ kubeconform $K espaces/ rbac/ admission/
   … could not find schema for CiliumNetworkPolicy …
   Summary: 212 resources found in 96 files - Valid: 180, Invalid: 0, Errors: 32, Skipped: 0
   admin@adm01:~/src/k8s$ kubeconform $K -ignore-missing-schemas espaces/ rbac/ admission/; echo "rc=$?"
   Summary: 212 resources found in 96 files - Valid: 180, Invalid: 0, Errors: 0, Skipped: 32
   rc=0
   ```
   (Les nombres et les dossiers dépendent de ton dépôt ; les dossiers Kustomize se valident sur leur rendu, `kustomize build`.) 32 objets n'ont pas été lus, et la CI dirait vert.
3. Le script : [`fichiers/M29-E02/k8s/outils/schemas-crd.sh`](fichiers/M29-E02/k8s/outils/schemas-crd.sh) et le convertisseur recopié [`openapi2jsonschema.py`](fichiers/M29-E02/k8s/outils/openapi2jsonschema.py) (étiquette v0.8.0, empreinte vérifiée par le script avant chaque usage). Points clés : lecture de **toutes** les CRD servies (`kubectl get customresourcedefinitions -o json`, lecture seule) ; une CRD par fichier, rangée par groupe ; le convertisseur écrit dans le **dossier courant** et nomme ses fichiers selon `FILENAME_FORMAT` (`{kind}_{version}`, en minuscules) : un appel par groupe depuis le dossier du groupe, avec `DENY_ROOT_ADDITIONAL_PROPERTIES=1` pour que la racine soit stricte elle aussi ; `api-versions.txt` par `kubectl api-versions` ; archive reproductible (`tar --sort=name --mtime=… --owner=0 --group=0 --numeric-owner`) ; téléversement par `PUT` (`curl --upload-file`) sur l'API des paquets génériques, jeton passé par un en-tête lu dans une substitution de processus (jamais dans la ligne de commande visible par `ps`).
4. La démonstration (extrait réel, avec un `PodChaos` ; le principe est le même avec un `Cluster` CNPG) :
   ```
   admin@adm01:~$ kubeconform -strict -schema-location default -schema-location 'brut/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' faute.yaml; echo rc=$?
   rc=0
   admin@adm01:~$ kubeconform -strict -schema-location default -schema-location 'schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' faute.yaml; echo rc=$?
   faute.yaml - PodChaos essai is invalid: problem validating schema. Check JSON formatting: jsonschema validation failed with 'schemas/chaos-mesh.org/podchaos_v1alpha1.json#' - at '/spec': additional properties 'durration' not allowed
   rc=1
   ```
5. Publication et relecture :
   ```
   admin@adm01:~/src/k8s$ outils/schemas-crd.sh generer && outils/schemas-crd.sh verifier
   admin@adm01:~/src/k8s$ outils/schemas-crd.sh publier "$(date +%Y.%m.%d)"
   admin@adm01:~$ cd "$(mktemp -d)" && V=2026.10.23
   admin@adm01:/tmp/tmp.Y$ for f in schemas-crd.tar.gz schemas-crd.tar.gz.sha256; do
       curl -fsS -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<~/.config/workbook/gitlab-admin.token)") -o "$f" \
         "https://git01.par1.medisphere.internal/api/v4/projects/plateforme%2Fk8s/packages/generic/schemas-crd/$V/$f"; done
   admin@adm01:/tmp/tmp.Y$ sha256sum --check schemas-crd.tar.gz.sha256 && mkdir ~/schemas-crd && tar -xzf schemas-crd.tar.gz -C ~/schemas-crd
   ```
6. Rendu des charts : [`fichiers/M29-E02/gitops/outils/rendre-charts.sh`](fichiers/M29-E02/gitops/outils/rendre-charts.sh). Il lit chaque Application de `plateforme/`, prend la source dont `repoURL` est le miroir Harbor (et **refuse** un chart d'ailleurs), résout `$values/…` dans le dépôt courant et `$<ref>/…` par une variable `REF_<ref>` ; une valeur introuvable est signalée et le script finit en code 3 (rendu incomplet). `helm template` reçoit `--kube-version 1.36.5` et un `--api-versions` par ligne de `api-versions.txt` : sans eux, on valide autre chose que ce qu'Argo CD appliquera (lui passe les API du cluster). Exemple vérifié : le chart de Chaos Mesh 2.8.6 choisit la version de ses `Issuer` et `Certificate` par `.Capabilities.APIVersions.Has "cert-manager.io/v1"` ; rendu sans `--api-versions`, il produit du `cert-manager.io/v1alpha2`, que plus aucun cert-manager ne sert (6 erreurs « could not find schema ») ; avec, 26 objets valides.
   ```
   admin@adm01:~/src/gitops$ SCHEMAS=~/schemas-crd outils/rendre-charts.sh /tmp/rendu-gitops
   admin@adm01:~/src/gitops$ kubeconform -strict -summary -kubernetes-version 1.36.5 -schema-location default \
       -schema-location "$HOME/schemas-crd/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" /tmp/rendu-gitops plateforme/
   ```
7. Dans les `.gitlab-ci.yml` des quatre projets, l'option disparaît ; le job télécharge le paquet (E10 le généralisera par le composant).
8. Documentation : [`fichiers/M29-E02/medisphere/docs/qualite/schemas-crd.md`](fichiers/M29-E02/medisphere/docs/qualite/schemas-crd.md).

**Explications**

kubeconform résout un schéma par objet à partir de gabarits (`{{.Group}}`, `{{.ResourceKind}}` en minuscules, `{{.ResourceAPIVersion}}`) ; `default` désigne les schémas des objets standard, générés depuis l'OpenAPI de Kubernetes pour chaque version (d'où `-kubernetes-version`). Pour les CRD, la source de vérité est **le cluster** : ce sont les versions installées (et leurs schémas) qui comptent, pas celles de la documentation du projet. Le paquet versionné par date sépare la production des schémas (une fois, par quelqu'un qui a le droit de lire les CRD) de leur consommation (toutes les CI, sans accès au cluster). L'empreinte publiée à côté permet à chaque consommateur de vérifier ce qu'il télécharge.

**Alternatives**

- Le catalogue communautaire `datreeio/CRDs-catalog` (schémas déjà convertis pour des centaines de CRD) : pratique, mais ce ne sont pas **nos** versions, et c'est une source externe de plus dans la chaîne.
- Valider contre le cluster (`kubectl apply --dry-run=server`) : exact, mais exige un accès au cluster depuis chaque CI et rend la validation dépendante de sa disponibilité ; à garder pour l'étage d'après (Argo CD le fait à la synchronisation).
- `kubectl-validate` (projet SIG CLI) : valide avec les schémas OpenAPI et les règles CEL des CRD (`x-kubernetes-validations`), ce que kubeconform ne fait pas ; plus lent, moins répandu en CI.

**Pièges classiques**

- `-ignore-missing-schemas` « en attendant » : il reste pour toujours, et masque précisément les objets qu'on voulait valider.
- Schémas extraits au `jq` : `-strict` ne sert à rien sur les CRD (E01, question 3).
- Oublier `--api-versions` dans `helm template` : rendu différent de celui d'Argo CD (qui connaît les API du cluster).
- Valider les fichiers `values.yaml`, `kustomization.yaml` ou les extraits comme des objets : erreurs absurdes ; on les ignore par motif de nom.
- Ne pas régénérer le paquet après une installation (Chaos Mesh en E09, k6-operator en E14) : les nouveaux objets échouent faute de schéma — c'est le bon comportement, à condition de savoir pourquoi.

**En production chez MédiSphère**

Pipeline hebdomadaire de `plateforme/k8s` qui régénère les schémas, compare au dernier paquet et ouvre une MR de montée de version dans les consommateurs ; vérification d'empreinte systématique ; paquet signé (Cosign, comme les images) pour aller au-delà de l'intégrité ; conservation des anciennes versions tant qu'une branche les référence.

---

### M29-E03 — conftest et Rego v1 : des règles sur les plans OpenTofu

**Solution**

1. Installation (empreintes publiées par les projets) :
   ```
   admin@adm01:~$ cd "$(mktemp -d)"
   admin@adm01:/tmp/tmp.Z$ curl -fsSLO https://github.com/open-policy-agent/opa/releases/download/v1.21.3/opa_linux_amd64_static
   admin@adm01:/tmp/tmp.Z$ curl -fsSLO https://github.com/open-policy-agent/opa/releases/download/v1.21.3/opa_linux_amd64_static.sha256
   admin@adm01:/tmp/tmp.Z$ sha256sum --check opa_linux_amd64_static.sha256 && sudo install -m 0755 opa_linux_amd64_static /usr/local/bin/opa
   admin@adm01:/tmp/tmp.Z$ curl -fsSLO https://github.com/open-policy-agent/conftest/releases/download/v0.71.1/conftest_0.71.1_Linux_x86_64.tar.gz
   admin@adm01:/tmp/tmp.Z$ curl -fsSLO https://github.com/open-policy-agent/conftest/releases/download/v0.71.1/checksums.txt
   admin@adm01:/tmp/tmp.Z$ grep ' conftest_0.71.1_Linux_x86_64.tar.gz$' checksums.txt | sha256sum --check
   admin@adm01:/tmp/tmp.Z$ tar -xzf conftest_0.71.1_Linux_x86_64.tar.gz conftest && sudo install -m 0755 conftest /usr/local/bin/
   ```
2. Exploration d'un plan (dans un dossier temporaire, supprimé après) :
   ```
   admin@adm01:~/src/infra/envs/m20$ T="$(mktemp -d)"; tofu plan -out="$T/p.tfplan" && tofu show -json "$T/p.tfplan" > "$T/p.json"
   admin@adm01:~/src/infra/envs/m20$ jq -r '.resource_changes[] | [.address, (.change.actions|join(","))] | @tsv' "$T/p.json"
   admin@adm01:~/src/infra/envs/m20$ jq '.resource_changes[] | select(.type=="proxmox_virtual_environment_vm") | .change.after | {vm_id, pool_id, tags}' "$T/p.json"
   admin@adm01:~/src/infra/envs/m20$ rm -rf "$T"
   ```
   Un remplacement apparaît comme `["delete","create"]`, ou `["create","delete"]` quand la ressource a `create_before_destroy` ; `before` est l'état actuel, `after` l'état visé (valeurs inconnues à l'apply dans `after_unknown`).
3. Règles : [`fichiers/M29-E03/politiques/rego/tofu/`](fichiers/M29-E03/politiques/rego/tofu/) — `commun.rego` (ressources visées, aides, refus quand `data.contexte` manque), `vmid.rego` (plage selon l'état : `data.plages_vmid[etat]`, sinon règle `envs/mNN` ; état inconnu refusé ; VMID non numérique refusé), `pool.rego` (`object.get(…, "pool_id", null) != pool_attendu`, « lab » sauf convention d'état déclarée), `etiquettes.rego`, `destruction.rego` (`"delete" in rc.change.actions` et VM du socle : `"socle"` dans les étiquettes **d'avant**, ou plan de l'état `socle` — une VM du socle qui aurait perdu son étiquette reste protégée ; `warn` quand l'étiquette de MR l'autorise).
4. Données : [`rego/donnees/plages-vmid.yaml`](fichiers/M29-E03/politiques/rego/donnees/plages-vmid.yaml) (à aligner sur les dossiers de **ton** `envs/`). Tous les états des modules précédents y sont, y compris ceux que la règle générale `envs/mNN` ne couvre pas : `lab-m05`, `recette-m05`, `lab-m06`, `m15-essai`, `m18` (banc 2181-2188 **et** k3s HA 5191-5193), `openstack-projets` (liste vide : aucune VM Proxmox) et `hv-invites`. Ce dernier vise le cluster imbriqué `hv-par1` du M09 (pool `recette`, étiquettes `tofu`/`recette`) : ses conventions sont déclarées sous `conventions_etat` plutôt que codées en dur dans les règles. Sans ces entrées, le job de plan de chacun de ces états serait refusé dès E10 (« état sans plage »), ce que l'échec fermé veut justement : on déclare, on ne devine pas.
5. Tests : [`rego/tofu/tofu_test.rego`](fichiers/M29-E03/politiques/rego/tofu/tofu_test.rego), 24 tests, un cas accepté et un cas refusé par règle, dont les remplacements dans les deux ordres (`["delete","create"]` et `["create","delete"]`) :
   ```
   admin@adm01:~/src/politiques$ opa test -v rego/tofu rego/donnees
   …
   PASS: 24/24
   ```
6. Plans d'exemple : [`rego/exemples/`](fichiers/M29-E03/politiques/rego/exemples/) ; par exemple :
   ```
   admin@adm01:~/src/politiques$ echo '{"contexte":{"etat":"socle","etiquettes_mr":[]}}' > /tmp/ctx.json
   admin@adm01:~/src/politiques$ conftest test --namespace tofu -p rego/tofu --data rego/donnees --data /tmp/ctx.json rego/exemples/plan-socle-remplacement.json
   FAIL - rego/exemples/plan-socle-remplacement.json - tofu - module.dns02.proxmox_virtual_environment_vm.vm : le plan remplace une VM du socle (dns02) ; étiquette de MR « destruction-autorisee » requise

   14 tests, 13 passed, 0 warnings, 1 failure, 0 exceptions
   ```
7. `opa check --strict rego/tofu rego/donnees`, `opa fmt --list rego/` (aucune sortie), MR, fusion.

**Explications**

Le JSON d'un plan est stable et documenté : `resource_changes[]` liste chaque ressource avec ses actions et ses valeurs avant/après ; on n'analyse jamais la sortie texte. Toutes les règles partagent le paquet `tofu`, celui que conftest lit avec `--namespace tofu` ; conftest n'évalue que les règles nommées `deny`, `violation`, `warn` (ou préfixées ainsi). Les données arrivent par `--data` : `plages-vmid.yaml` sous `data.plages_vmid`, le contexte du job sous `data.contexte`. Les règles **échouent fermées** : un contexte absent, un état inconnu, un pool absent, un VMID non numérique sont des refus. En Rego, une expression sur un champ absent est **indéfinie**, et une règle dont le corps est indéfini ne produit rien : `input.x.pool_id != "lab"` ne refuse pas un pool absent ; `object.get` donne une valeur par défaut qui, elle, se compare.

**Alternatives**

- Les **tests d'OpenTofu** (`tofu test`, M05) : vérifient un module, pas un plan d'un état réel avec ses données.
- **Checkov** / **Trivy** (M24-M26) : règles génériques de sécurité sur le code, utiles en complément, mais pas nos conventions (plages, étiquettes, socle).
- **Sentinel** (HashiCorp, payant) ou les politiques d'un orchestrateur de plans (Spacelift, env0) : même idée, hors de notre outillage libre.
- Une protection côté Proxmox (`protection: 1` sur les VMs du socle) : complémentaire et indispensable, car conftest ne protège que ce qui passe par la CI.

**Pièges classiques**

- `rc.after` au lieu de `rc.change.after` : la règle ne voit jamais rien (E11).
- `actions[0] == "delete"` : rate les remplacements `create_before_destroy`.
- Tester seulement le cas conforme : le test reste vert quand la règle ne se déclenche jamais.
- Mettre les plans d'exemple JSON **sous** un dossier chargé par `opa test` : OPA les charge comme données et peut échouer (« merge error ») ou les mélanger aux vraies données ; on les range à part et on charge des racines explicites.
- Citer dans un message une valeur sensible du plan : elle part dans le journal du job.

**En production chez MédiSphère**

Le job de plan écrit le contexte à partir de `$DOSSIER` et des étiquettes de MR, lance conftest et supprime le JSON (E10) ; l'étiquette `destruction-autorisee` n'est posable que par les mainteneurs (étiquette protégée de GitLab, ou règle d'approbation qui la conditionne) ; les avertissements (`warn`) remontent dans la MR ; chaque nouveau module ajoute sa plage à `plages-vmid.yaml` dans la même MR que son état.

---

### M29-E04 — Testinfra : tester les rôles Ansible sur les VMs

**Solution**

1. Dépendances : groupe `tests` du `pyproject.toml` ([extrait](fichiers/M29-E04/ansible/pyproject.toml.extrait)) puis :
   ```
   admin@adm01:~/src/ansible$ uv add --group tests 'pytest-testinfra==10.2.2' pytest-xdist
   admin@adm01:~/src/ansible$ uv run pytest tests/infra --collect-only -q | tail -1
   48 tests collected in 0.03s
   ```
2. Fixtures : [`tests/infra/conftest.py`](fichiers/M29-E04/ansible/tests/infra/conftest.py) — variables Ansible de l'hôte, groupes, famille, passerelle ou non, adresse de service, et **registre des exceptions** lu sur l'hôte (`/etc/medisphere/conformite/exceptions.json`, avec `sudo`) : une règle en exception fait sauter (`pytest.skip`) le test correspondant, avec l'identifiant de l'exception dans la raison.
3. Tests : [`test_durcissement.py`](fichiers/M29-E04/ansible/tests/infra/test_durcissement.py) (paramètres du noyau avec leur règle XCCDF, modules non chargeables, paquets interdits, `/tmp`, `sshd -T`, `auditd`, journal persistant, minuterie AIDE, verrouillage après 5 échecs), [`test_node_exporter.py`](fichiers/M29-E04/ansible/tests/infra/test_node_exporter.py) (version 1.12.1, compte sans shell, service durci, écoute sur l'adresse de service, TLS, et deux tests **depuis le contrôleur** : HTTPS vérifié, HTTP clair refusé), [`test_alloy.py`](fichiers/M29-E04/ansible/tests/infra/test_alloy.py), [`test_chrony.py`](fichiers/M29-E04/ansible/tests/infra/test_chrony.py) (sources `.2`/`.3` de la passerelle du VLAN en NTS, synchronisation, écart, NTS négocié). Marqueurs déclarés dans [`pytest.ini`](fichiers/M29-E04/ansible/tests/infra/pytest.ini) avec `--strict-markers` et le rapport JUnit.
4. Exécution :
   ```
   admin@adm01:~/src/ansible$ set -a; . ~/.config/workbook/netbox-ansible.env; set +a
   admin@adm01:~/src/ansible$ uv run pytest tests/infra --hosts='ansible://socle' -n 4
   admin@adm01:~/src/ansible$ uv run pytest tests/infra --hosts='ansible://dns01' -m chrony -v
   ```
5. et 6. Job : [`gitlab-ci.extrait-M29-E04.yml`](fichiers/M29-E04/ansible/gitlab-ci.extrait-M29-E04.yml) (modèle `.socle`, clé passée par `--ssh-identity-file="$ANSIBLE_PRIVATE_KEY_FILE"`, JUnit, planifié avec `PLANIF=testinfra`, manuel sur `main`). Pipeline planifié : *Build → Pipeline schedules*, `main`, chaque nuit à 2 h 17, variable `PLANIF=testinfra`. Mode d'emploi : [`tests/infra/README.md`](fichiers/M29-E04/ansible/tests/infra/README.md).

**Explications**

Le connecteur `ansible://` construit les hôtes depuis l'inventaire (NetBox) et ses variables de connexion : un seul inventaire pour configurer et pour tester. Les tests contrôlent l'**état** (le service tourne, le port écoute, le noyau applique la valeur) plutôt que la présence d'un fichier que le rôle vient d'écrire : c'est la différence entre « le rôle a été appliqué » et « l'hôte est conforme ». Lire le registre des exceptions sur l'hôte évite la double vérité (une exception ajoutée au registre ne casse pas les tests, une exception retirée les réactive). Les tests « depuis le contrôleur » voient ce que voit Prometheus : pare-feu, certificat, refus du HTTP clair.

**Alternatives**

- **Goss** (E07) : tests sur l'hôte, en continu, mais un binaire et un port de plus par VM.
- **InSpec** (Chef, licence commerciale depuis 2019 ; fork libre **cinc-auditor**) : langage dédié très riche pour la conformité, Ruby.
- Le mode `--check --diff` d'Ansible lancé la nuit : détecte les dérives **par rapport aux rôles**, sans test écrit ; utile en complément, mais muet sur ce que les rôles ne gèrent pas.
- OpenSCAP (M26) : la conformité au référentiel, hebdomadaire ; Testinfra couvre nos promesses à nous.

**Pièges classiques**

- Croire que `ANSIBLE_PRIVATE_KEY_FILE` suffit : Testinfra ne le lit pas.
- Des tests qui écrivent (un `host.run("systemctl restart …")` « pour vérifier ») : un test du parc réel est en **lecture seule**.
- Recopier les exceptions dans les tests : elles divergent du registre au premier changement.
- Lancer `-n 32` sur tout le parc : 32 connexions SSH simultanées et des `sudo` en rafale ; borner le parallélisme.
- Un test rouge « corrigé » en assouplissant le test alors que le parc avait vraiment dérivé.

**En production chez MédiSphère**

Résultat de la nuit envoyé dans le canal de l'équipe (rouge seulement) ; tableau hôte × rôle dans la MR ; un test rouge ouvre un ticket et ne se désactive pas sans exception au registre ; les tests évoluent dans la même MR que le rôle qu'ils testent (relecture commune).

---

### M29-E05 — k6 : premier test de charge de MédiAgenda

**Solution**

1. Installation :
   ```
   admin@adm01:~$ V=1.8.2; cd "$(mktemp -d)"
   admin@adm01:/tmp/tmp.K$ curl -fsSLO https://github.com/grafana/k6/releases/download/v$V/k6-v$V-linux-amd64.tar.gz
   admin@adm01:/tmp/tmp.K$ curl -fsSLO https://github.com/grafana/k6/releases/download/v$V/k6-v$V-checksums.txt
   admin@adm01:/tmp/tmp.K$ grep " k6-v$V-linux-amd64.tar.gz\$" k6-v$V-checksums.txt | sha256sum --check
   admin@adm01:/tmp/tmp.K$ tar -xzf k6-v$V-linux-amd64.tar.gz && sudo install -m 0755 k6-v$V-linux-amd64/k6 /usr/local/bin/ && k6 version
   ```
   Projet `plateforme/resilience` créé dans le groupe `plateforme` (branche `main` protégée, MR obligatoire, comme les autres projets de plateforme), cloné dans `~/src/resilience`.
2. [`charge/lib/commun.js`](fichiers/M29-E05/resilience/charge/lib/commun.js) : cible par défaut la recette ; **liste d'autorisation** (recette, dev, `127.0.0.1`) testée dans le code d'initialisation, qui lève une exception sinon ; praticiens `dr-k6-<VU>`, patients « Patient Charge … », motif marqué, jours à J+60, 16 créneaux par jour, **fuseau** dans chaque date ; `creneauUnique(vu, iteration)` qui ne donne jamais deux fois le même couple (praticien, heure).
3. et 4. [`charge/premier-test.js`](fichiers/M29-E05/resilience/charge/premier-test.js) : `MODELE=ferme` (5 VUs, 2 min) ou `MODELE=ouvert` (3 itérations/s, 2 min) ; lire, réserver (201 attendu), relire, annuler (204) ; requêtes nommées (`DELETE /api/v1/rendez-vous/{id}`) ; seuils `p(95)<250`, `http_req_failed: rate<0.005`, `checks: rate==1`.
5. Garde-fou :
   ```
   admin@adm01:~/src/resilience$ k6 inspect charge/premier-test.js | jq '.thresholds'
   admin@adm01:~/src/resilience$ k6 inspect -e BASE_URL=https://mediagenda.apps.par1.medisphere.internal charge/premier-test.js
   ERRO[0000] Error: cible refusée : https://mediagenda.apps.par1.medisphere.internal (seules la recette, la dev et 127.0.0.1 sont autorisées)
   ```
6. Exécution, après l'annonce dans `docs/qualite/journal/` :
   ```
   admin@adm01:~/src/resilience$ k6 run -e MODELE=ferme charge/premier-test.js
   admin@adm01:~/src/resilience$ k6 run -e MODELE=ouvert charge/premier-test.js
   ```
   Pendant le test : `sum(rate(mediagenda_http_requests_total{namespace="mediagenda-recette"}[1m]))`, la part sous 250 ms (question 9 d'E01) et `kube_horizontalpodautoscaler_status_current_replicas{namespace="mediagenda-recette"}`.
7. `curl -fsS "$URL/api/v1/rendez-vous?limite=1000" | jq '[.[] | select(.praticien | startswith("dr-k6-"))] | length'` → 0.

**Explications**

Le modèle fermé donne un débit qui **dépend** de la latence : à 5 VUs et une itération de ≈ 0,3 s, ≈ 16 itérations/s, qui baissent si le serveur ralentit. Le modèle ouvert impose 3 itérations/s quoi qu'il arrive : c'est lui qui répond à la question de Julien. Le garde-fou est dans le code d'initialisation, exécuté avant la moindre requête (et par `k6 inspect`), et c'est une liste d'**autorisation** : une URL inconnue est refusée. Les requêtes nommées évitent une série de métriques par rendez-vous (cardinalité) et rendent le résumé lisible. L'annulation garde la base de recette propre : sans elle, chaque test remplit les agendas de Julien et change les résultats du test suivant (créneaux déjà pris).

**Alternatives**

- **Locust** (Python) : modèle fermé par défaut, interface web ; **Gatling** (Scala/Java) : modèle ouvert natif, rapports riches ; **JMeter** : historique, lourd ; **vegeta** : très simple, taux constant, une URL. k6 l'emporte ici par le scripting JS, les seuils, k6-operator (palier 3) et l'intégration Prometheus.
- Un modèle hybride (VUs avec `sleep` de réflexion) : réaliste pour un parcours d'utilisateur humain, mais il faut alors raisonner en sessions, pas en requêtes.

**Pièges classiques**

- Une date sans fuseau : MédiAgenda répond 422 ; un check « `< 500` » ne le voit pas.
- Un créneau unique partagé : 409 en série, et l'on mesure la gestion des conflits, pas la réservation.
- Pas d'annulation : la base de recette se remplit.
- `insecureSkipTLSVerify` « parce que ça ne marchait pas » : la racine MédiSphère doit être dans le magasin de `adm01` (M06).
- Lire la moyenne du résumé au lieu de la p95 et du verdict des seuils.

**En production chez MédiSphère**

RB-290 (E12) encadre chaque test : annonce, paramètres prudents d'abord, surveillance, arrêt, nettoyage. Les tests de charge passent en k6-operator dans le cluster au palier 3 (charge générée au plus près, résultats dans Prometheus), et leurs résumés deviennent des références de non-régression.
