# Module 19 — Palier 3 : Production — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- Pod Security `restricted` avec l'exécuteur Kubernetes de GitLab Runner 19.4/19.5 : conteneurs `init-permissions` et `helper` en UID 1000 avec `fs_group` (droits sur `/builds`), services PostgreSQL 18 et Valkey forcés en UID 999 par `service_container_security_context` ; motif `**` dans `allowed_images` (vérifié dans le code du runner 19.5 : `common/allowed_images.go` compare avec `doublestar.Match`, et une liste **vide** n'interdit rien) ; montage d'un Secret par `[[runners.kubernetes.volumes.secret]]` (le code du runner 19.5 le monte dans **tous** les conteneurs du pod : `init-permissions`, `build`, `helper` et services ; d'où `allowed_services` restreint à `plateforme/**` sur le runner protégé) ;
- CiliumNetworkPolicy `toFQDNs` vers `registry.par1.medisphere.internal` (CNAME vers `reg01`) et sortie Internet par `toCIDRSet` avec `except` ; entité `ingress` pour joindre la Gateway depuis un pod (exception SonarQube) ;
- rendu des charts `gitlab/gitlab-runner` 0.94.0 et `gitlab/gitlab-agent` 2.33.0 vérifié par `helm template` (Helm 4.3) et `kubeconform` (relecture : values de E24 et E27 rendues avec le chart 0.94.0, TOML relu par `tomllib`) ; arrêt gracieux du gestionnaire par `preStop` (SIGQUIT) en E27 : non essayé ; le chart 0.93.0 a été rendu avec les values de E24 des deux runners (`helm template`, TOML relu, `kubeconform`) ;
- variables de projet de portée `promotion/*` reçues par un job `environment: {action: prepare}` ; recréation d'une variable cachée par `DELETE` + `POST masked_and_hidden=true` ; `POST …/access_tokens/:id/rotate?expires_at=` ;
- adresse `grpcs://git01.par1.medisphere.internal` de l'agent 19.5 avec NGINX d'omnibus en HTTP/2 (documentation « Agent server », pas d'essai) ; changement de `CI_RUNNER_TAGS` : MR amont !256718 « Serialize CI_RUNNER_TAGS as valid JSON », fusionnée le 23/09/2026 avec le jalon 19.5 (chaque étiquette encodée en JSON, forme inchangée pour des étiquettes simples) ; `CI_JOB_TAGS` (19.3) est un tableau JSON depuis son introduction et n'est pas concernée ;
- réponse de `GET /projects/:id/ci/lint` (`includes[].type == "component"`, `location` avec `@version`) sur laquelle s'appuient l'outil de E32 et le check de E34 ; rôle minimal du compte technique pour lire `ci/lint` ;
- comportement de Harbor 2.15.3 avec les référents Cosign 3 : d'après son code (`src/server/middleware/subject/subject.go`), tout référent d'`artifactType` `application/vnd.dev.sigstore.bundle.v0.3+json` (signature **et** attestations) est classé en accessoire `signature.cosign` ; le check compte donc au moins trois accessoires de ce type (affichage de l'interface non vérifié) ;
- prédicat SLSA v1 de BuildKit 0.34 : seul `buildDefinition.buildType` est contrôlé par la porte ; lis le reste sur une de tes images ;
- `go test -race` de MédiDoc dans l'image `golang:1.26-trixie` en UID 1000 (`GOPATH`, `GOCACHE` déplacés) : non exécuté ici (Go 1.26 indisponible dans le bac à sable de rédaction) ;

**Numéros de version des composants** : à la suite du palier 2 (v2.0.0 en E10 … v2.6.0 en E23), une MR `feat:` par exercice donne **v2.7.0** en E24 et **v2.8.0** en E29 ; les projets consomment toujours l'étiquette exacte, préfixe compris (`@v2.7.0`, voir M19-E10). Les vérifications de E29, E33 et E34 exigent une version ≥ v2.8.0 : si ton historique a regroupé des fonctions (moins de mineures), publie une mineure de plus plutôt que de réécrire une étiquette.

**Rappel** : aucune nouvelle VM dans ce palier. Fichiers de solution : `corrige/fichiers/M19-E24/` à `M19-E30/`, `M19-E32/` à `M19-E34/`.

---

### M19-E24 — Cloisonner les runners : comptes, Pod Security, réseau, quotas

**Solution**

Fichiers : espaces [`ci-jobs/00-namespace.yaml`](fichiers/M19-E24/k8s/espaces/ci-jobs/00-namespace.yaml), [`ci-jobs/40-politiques-reseau.yaml`](fichiers/M19-E24/k8s/espaces/ci-jobs/40-politiques-reseau.yaml), [`ci-jobs-protege/`](fichiers/M19-E24/k8s/espaces/ci-jobs-protege/) (espace, quota, LimitRange, compte, politiques) ; values [`gitlab-runner`](fichiers/M19-E24/k8s/composants/gitlab-runner/values.yaml) et [`gitlab-runner-protege`](fichiers/M19-E24/k8s/composants/gitlab-runner-protege/values.yaml) ; [release](fichiers/M19-E24/k8s/releases/50-ci.yaml.gotmpl.extrait) ; modèles de Vault [`gitlab-runner-protege.yml`](fichiers/M19-E24/k8s/secrets/gitlab-runner-protege.yml.exemple) et [`cosign-ci.yml`](fichiers/M19-E24/k8s/secrets/cosign-ci.yml.exemple) ; [`outils/creer-runner-protege.sh`](fichiers/M19-E24/k8s/outils/creer-runner-protege.sh) ; composants v2.7.0 : [`securite`](fichiers/M19-E24/ci-templates/templates/securite/template.yml.extrait), [`promotion`](fichiers/M19-E24/ci-templates/templates/promotion/template.yml.extrait) ; documentation : [`cloisonnement.md`](fichiers/M19-E24/medisphere/docs/livraison/ci/cloisonnement.md), [matrice des flux du cluster](fichiers/M19-E24/medisphere/docs/kubernetes/reseau/matrice-flux-cluster.md.extrait).

*1. État des lieux.* Les sondes de la [ressource](../ressources/E24-sondes-cloison/.gitlab-ci.yml) n'ouvrent qu'une connexion TCP (`/dev/tcp` de bash) : rien d'authentifié, rien d'écrit. Avant les cloisons, le job tourne en root (`uid=0`), avec les capacités par défaut du moteur (`CapEff: 00000000a80425fb`, dont `CAP_NET_RAW`, `CAP_SETUID`, `CAP_CHOWN`…), sans seccomp (`Seccomp: 0`), et joint **tout** : l'API du cluster (la connexion TCP s'ouvre, même sans jeton), PostgreSQL de `mediagenda-dev`, NetBox, les SSH du socle, Mailpit. Le jeton n'est pas monté (compte `ci-job` du E04), mais rien dans la configuration du runner ne l'interdit si un job demandait un autre compte.

```
admin@adm01:~$ kubectl -n ci-jobs get pods -l medisphere.internal/ci=job -o yaml | yq '.items[0].spec | {"securityContext": .securityContext, "sa": .serviceAccountName, "automount": .automountServiceAccountToken, "conteneurs": [.initContainers[].name, .containers[].name]}'
```

(L'étiquette `medisphere.internal/ci: job` est posée par le runner depuis E04 ; lance la commande pendant le `sleep` d'une sonde.)

*2. Pod Security.* Niveau actuel posé en E02 (`enforce: baseline`, `warn`/`audit: restricted`). Essai à blanc :

```
admin@adm01:~$ kubectl label --dry-run=server --overwrite ns ci-jobs pod-security.kubernetes.io/enforce=restricted
Warning: existing pods in namespace "ci-jobs" violate the new PodSecurity enforce level "restricted:v1.36"
Warning: runner-…-concurrent-0-…: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/ci-jobs labeled (server dry run)
```

Les clés de `[runners.kubernetes]` qui répondent à chaque ligne de l'avertissement : `allow_privilege_escalation = false` ; `cap_drop = ["ALL"]` ; `pod_security_context` avec `run_as_non_root`, `run_as_user`/`run_as_group` 1000, `fs_group` 1000 (l'`emptyDir` des sources est inscriptible par le groupe) et `seccomp_profile.type = "RuntimeDefault"` (la sous-table existe dans la documentation 19.x pour le contexte du pod et ceux des conteneurs). Puis : `privileged = false`, `automount_service_account_token = false`, `allowed_images`/`allowed_services` limités à Harbor (déjà là depuis E04), `allowed_pull_policies`, aucune clé `*_overwrite_allowed` pour l'espace ni le compte (vides = surcharge interdite). `HOME=/tmp`, ajouté aux variables `environment` de E07-E08 (`SSL_CERT_DIR`, `BUILDKIT_HOST`, `BUILDKIT_TLS_DIR`, qu'il ne faut pas perdre), sauve les images qui supposent `/root`. Les Secrets (`gitlab-runner`, `gitlab-runner-certs`, `ci-cache-s3`), les volumes (`medisphere-racine`, `buildkit-client`) et l'étiquette de pod `medisphere.internal/ci: job` de E04-E08 restent : la politique d'entrée de buildkitd (E08) sélectionne les pods par cette étiquette. Application et contrôle :

```
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=gitlab-runner diff
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=gitlab-runner apply
admin@adm01:~$ kubectl -n gitlab-runner get configmap gitlab-runner -o jsonpath='{.data.config\.template\.toml}' | grep -E 'cap_drop|automount|run_as'
```

Relance des sondes et du pipeline de `main` de `mediagenda/api` **avant** l'étiquette d'espace : ce qui casse se voit dans les journaux sans rien bloquer (les avertissements `warn` s'affichent dans les événements). Cas rencontrés : services PostgreSQL et Valkey (E14) qui démarrent en root → `service_container_security_context` 999:999 ; un job qui faisait `apt-get install jq` → image outillée de `plateforme/` ; `uv` et `pip` qui écrivent dans `$HOME` → `HOME=/tmp` ; Go qui écrit dans `/go` → `GOPATH` dans le projet (E33). Puis seulement l'espace, par le code (`espaces/ci-jobs/00-namespace.yaml`, `task appliquer` ou `kubectl apply --server-side -f`).

*3. Droits du gestionnaire.* `rbac.create: true`, `clusterWideAccess: false`, `runners.jobNamespace: ci-jobs` : le chart crée la Role **dans `ci-jobs`** et la lie au compte `gitlab-runner` de l'espace `gitlab-runner` (`templates/role.yaml` et `role-binding.yaml` du chart). `rbac.rules` remplace la règle par défaut du chart (`apiGroups: [""]`, `resources: ["*"]`, `verbs: ["*"]`, c'est-à-dire **tout le cœur**, Secrets compris, de l'espace). La liste retenue est celle de la documentation pour les fonctions utilisées (tableau du fichier de values). Preuves :

```
admin@adm01:~$ kubectl auth can-i get secrets -n mediagenda-dev --as=system:serviceaccount:gitlab-runner:gitlab-runner
no
admin@adm01:~$ kubectl auth can-i create pods -n kube-system --as=system:serviceaccount:gitlab-runner:gitlab-runner
no
admin@adm01:~$ kubectl auth can-i create pods/attach -n ci-jobs --as=system:serviceaccount:gitlab-runner:gitlab-runner
yes
admin@adm01:~$ kubectl auth can-i --list -n ci-jobs --as=system:serviceaccount:ci-jobs:ci-job | grep -v selfsubject
```

(Ton identité `<MOI>` a le droit d'emprunter : c'est un essai d'administrateur. Le check fait la même chose par des `SubjectAccessReview`.)

*4. Réseau.* Fichier `40-politiques-reseau.yaml` : le refus par défaut est une `NetworkPolicy` standard (lisible par tous les outils), les autorisations une `CiliumNetworkPolicy` (FQDN, entités, `toCIDRSet`). Observation :

```
admin@adm01:~$ hubble observe -n ci-jobs --verdict DROPPED -f
admin@adm01:~$ hubble observe -n ci-jobs --to-fqdn s3-01.par1.medisphere.internal
```

Ce qu'on découvre en général au premier essai : la règle DNS oubliée (tous les `toFQDNs` tombent), `reg01.par1…` à ajouter à côté de `registry.par1…` (le mandataire DNS voit les deux noms de la chaîne CNAME selon le client), l'Internet en 80 (un `apt` caché dans une image) qu'on **ne** rouvre **pas**. Les adresses de la bordure ne changent pas : `K8S_TRAV → git01:443`, `→ reg01:443`, `→ s3-01:8333` existent déjà.

*5. Espace protégé.* Mêmes fichiers, quota de 6 pods, LimitRange plus serré, sortie limitée à DNS, `git01` et Harbor. Vérifié en fin d'exercice : signature, attestations et MR de promotion passent sans Internet ni `s3-01` (pas de cache sur ce runner).

*6. Runner protégé.*

```
admin@adm01:~/src/k8s$ outils/creer-runner-protege.sh
runner k8s-par1-protege créé (id 7)
jeton chiffré dans secrets/gitlab-runner-protege.yml (à committer, puis : outils/secrets-k8s.sh appliquer gitlab-runner-protege)
admin@adm01:~/src/k8s$ outils/secrets-k8s.sh appliquer gitlab-runner-protege && outils/secrets-k8s.sh appliquer cosign-ci
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=gitlab-runner-protege apply
admin@adm01:~$ curl -s -H "PRIVATE-TOKEN: $(<~/.config/workbook/gitlab-checks.token)" \
    https://git01.par1.medisphere.internal/api/v4/runners/7 | jq '{description, access_level, tag_list, run_untagged, status}'
```

Le script crée le runner par `POST /user/runners` (`runner_type=instance_type`, `access_level=ref_protected`, `tag_list=protege`, `run_untagged=false`, `maximum_timeout=3600`) et envoie le jeton directement dans `ansible-vault encrypt` (variable `gitlab_runner_protege_jeton`) : il ne passe ni par le terminal, ni par un fichier en clair, ni par un argument. Les deux nouvelles lignes de la table `outils/secrets-k8s.conf` ([extrait](fichiers/M19-E24/k8s/outils/secrets-k8s.conf.extrait)) suffisent : le script de E04 n'est pas modifié. Le gestionnaire protégé réutilise le Secret `gitlab-runner-certs` (même espace `gitlab-runner`) ; ses jobs reçoivent la racine par une ConfigMap `medisphere-racine` de `ci-jobs-protege` ([`40-racine-ca.yaml`](fichiers/M19-E24/k8s/espaces/ci-jobs-protege/40-racine-ca.yaml)), indispensable à `git` et `curl` du composant `promotion`. Avec un jeton `glrt-`, les options `runners.protected`/`runners.tags` du chart n'ont aucun effet : c'est GitLab qui porte ces attributs.

Le Secret `cosign-medisphere` n'existe que dans `ci-jobs-protege` et seule la configuration du runner protégé le monte (`[[runners.kubernetes.volumes.secret]]`) : un job de `k8s-par1` ne peut ni le monter (pas d'option côté `.gitlab-ci.yml`), ni le lire par l'API (pas de jeton, autre espace). Le runner monte ce volume dans **tous** les conteneurs du pod, services compris : sur le runner protégé, `allowed_services` est donc restreint aux images de `plateforme/` (une liste vide n'interdirait rien).

*7. Jobs sensibles.* Composant `securite` v2.7.0 : le job `securite:signature` prend l'étiquette `protege` et lit `/run/secrets/medisphere/cosign/cosign.key` et `cosign.password` ; composant `promotion` v2.7.0 : le job `promouvoir-<overlay>` aussi (entrée `runner`, défaut `protege`). Release `v2.7.0` de `plateforme/ci-templates` (semantic-release : commit `feat(securite): signature sur le runner protégé`), `mediagenda/api` passe en `@v2.7.0`, étiquette de version. Contrôle :

```
admin@adm01:~$ curl -s -H "PRIVATE-TOKEN: $(<~/.config/workbook/gitlab-checks.token)" \
    "https://git01.par1.medisphere.internal/api/v4/projects/mediagenda%2Fapi/pipelines/<ID>/jobs?per_page=100" \
  | jq -r '.[] | [.name, .status, .runner.description] | @tsv'
```

Variables : `DELETE` des variables Cosign **de projet** de `mediagenda/api` s'il y en a ; inventaire des consommateurs de la variable de groupe (recherche de `COSIGN_PRIVATE_KEY` dans les projets, pipelines v1 sur `runner02`) : `mediagenda/chart`, `medidoc/medidoc`, `medinotif/worker` (gabarit `supply-chain.yml` de M13-E12) → exception n° 1 de `cloisonnement.md` (fin : E33 pour MédiDoc, mini-projet pour le chart et le worker). Le groupe `legacy` reçoit aussi ces variables (M13-E07) sans les consommer : supprime-les tout de suite (`DELETE /groups/legacy/variables/COSIGN_PRIVATE_KEY`, puis `COSIGN_PASSWORD`).

*8. Essai inverse.* Sur une branche non protégée, le job `protege` reste `pending` avec « This job is stuck because you don't have any active runners online or available with any of these tags assigned to them: protege » (le message de GitLab ne distingue pas « aucun runner » de « runner protégé, référence non protégée » : RB-190). Annule-le : un job bloqué occupe la file.

**Explications**

Le pod d'un job réunit des conteneurs de confiance différente : `helper` (code de GitLab Runner) et `build`/services (code et images choisis par le projet). La Pod Security agit sur **tous** au moment de la création du pod : c'est une barrière que le `.gitlab-ci.yml` ne peut pas contourner, contrairement à une convention. La politique réseau, elle, agit sur le pod entier : le helper a besoin de `git01` et de `s3-01`, le build de buildkitd et d'Internet ; on ne peut pas séparer les deux à l'intérieur d'un pod, d'où une liste qui couvre l'union. Le runner protégé change le **modèle de menace** : la clé ne vit plus dans GitLab (où toute référence protégée la recevait) mais dans Kubernetes, remise par le seul gestionnaire qui ne prend que des références protégées. La sécurité de la clé devient celle de la revue de code sur `main` et sur les étiquettes (règles de protection, M01), plus celle de l'espace `ci-jobs-protege`.

**Alternatives**
- `namespace_per_job` : un espace par job (créé et détruit par le gestionnaire, qui a alors besoin de `namespaces create/delete` au niveau du cluster) ; isolement réseau et quotas par job, mais RBAC du gestionnaire beaucoup plus large.
- `RuntimeClass` à isolation forte (gVisor, Kata) pour les jobs non fiables : pas de nœud adapté dans le lab (virtualisation imbriquée pour Kata).
- *User namespaces* (`hostUsers: false`) : root du conteneur ≠ root du nœud ; à suivre (option de l'exécuteur et du runtime), complémentaire de `restricted`.
- Clé de signature dans un KMS (OpenBao transit au M25) : la clé ne quitte plus jamais le coffre, le job demande une signature avec un jeton d'identité (E25). C'est la cible.

**Pièges classiques**
- Passer l'espace en `restricted` **avant** de changer le runner : tous les pipelines échouent d'un coup.
- Oublier `seccomp_profile` (le niveau `restricted` l'exige depuis Kubernetes 1.25) ou un des quatre contextes (le `init-permissions` est souvent oublié : il hérite du contexte du pod).
- Garder `rbac.rules: []` en croyant n'avoir « rien » : le chart pose alors **tout** sur l'espace.
- `toFQDNs` sans règle DNS : tout est refusé, sans message clair dans le job (« Could not resolve host »).
- Poser les étiquettes `protege` sans `rules` sur les références protégées : jobs bloqués sur les branches de fonctionnalité, pipelines jamais verts.
- Laisser la variable Cosign au niveau du projet « au cas où » : elle est remise à tous les jobs de `main`.

**En production chez MédiSphère**
Un contrôle continu (M26 : Kyverno ou Pod Security en `audit` sur tout le cluster) qui alerte sur toute création de pod refusée dans `ci-jobs` ; la clé de signature dans OpenBao (M25) ; un runner dédié par niveau de confiance pour une équipe externe ; revue trimestrielle des exceptions de `cloisonnement.md`.

---

### M19-E25 — Secrets en CI : variables protégées, `CI_JOB_TOKEN`, jetons d'identité

**Solution**

Fichiers : [`bin/ci-inventaire-variables.sh`](fichiers/M19-E25/outils/bin/ci-inventaire-variables.sh), [job `jeton-identite`](fichiers/M19-E25/ci-labo/jeton-identite.gitlab-ci.yml), [`secrets-ci.md`](fichiers/M19-E25/medisphere/docs/livraison/ci/secrets-ci.md), [RB-191](fichiers/M19-E25/medisphere/docs/livraison/ci/runbooks/RB-191-rotation-secrets-ci.md) ; composant `promotion` (environnement `promotion/<cible>`) : [extrait v2.7.0](fichiers/M19-E24/ci-templates/templates/promotion/template.yml.extrait).

*1. Inventaire.* Le script retire `.value` dans le même `jq` qui reçoit la réponse : la valeur n'existe à aucun moment dans une variable du shell, un fichier ou le terminal. Pagination par l'en-tête `x-next-page`.

```
admin@adm01:~/src/outils$ bin/ci-inventaire-variables.sh > /tmp/inventaire.tsv
ANOMALIE : projet mediagenda/api SONAR_TOKEN (protégée=false, masquée=true)
37 variables inventoriées
admin@adm01:~/src/outils$ column -t -s $'\t' /tmp/inventaire.tsv | less -S
```

Le classement « secret » est une heuristique sur la clé (`TOKEN`, `PASSWORD`, `KEY`…) : il donne des faux positifs (`CACHE_KEY`), et **aucune** heuristique ne remplace la lecture humaine de la liste. Classement attendu : voir `secrets-ci.md` §1.

*2. Durcir.* Une variable existante ne devient pas cachée : on la supprime et on la recrée (RB-191 §2 montre la commande, avec la valeur qui ne passe que par un tuyau). Pour `DEPLOIEMENT_TOKEN` : `protected=true`, `masked_and_hidden=true`, `environment_scope=promotion/*`, `raw=true`. Le composant `promotion` déclare `environment: {name: promotion/$CIBLE, action: prepare}` : la variable est remise aux seuls jobs de promotion, `prepare` n'enregistre pas de déploiement (l'environnement `promotion/dev` apparaît dans la liste, sans déploiement). Essai : un job de `main` qui fait `echo "${DEPLOIEMENT_TOKEN:+présente}"` n'affiche rien.

Ce que le masquage protège : la valeur **exacte** dans le journal. Ce qu'il ne protège pas : `echo "$T" | base64`, `echo "${T:0:5}"; echo "${T:5}"`, un `curl -v` qui affiche un en-tête dérivé, un fichier mis en artefact, `env > debug.txt`, l'envoi par le réseau. `set -x` : la commande développée s'affiche, le masquage la rattrape **si** la valeur y apparaît telle quelle ; `CI_DEBUG_TRACE` affiche tout l'environnement développé (le masquage s'applique, mais c'est le premier réglage à interdire — panne de E40).

*3. `CI_JOB_TOKEN`.*

```
admin@adm01:~$ for p in $(curl -s -H "PRIVATE-TOKEN: $(<~/.config/workbook/gitlab-checks.token)" \
    "https://git01.par1.medisphere.internal/api/v4/groups/mediagenda/projects?per_page=100&include_subgroups=true" | jq -r '.[].id'); do
  curl -s -H "PRIVATE-TOKEN: $(<~/.config/workbook/gitlab-checks.token)" \
    "https://git01.par1.medisphere.internal/api/v4/projects/$p/job_token_scope" | jq -c --arg p "$p" '{p: $p, inbound_enabled}'; done
```

Activation par projet (`PATCH /projects/:id/job_token_scope` avec `enabled=true`, jeton `api`), autorisations par `POST /projects/:id/job_token_scope/allowlist` (`target_project_id`) ou `…/groups_allowlist` ; puis *Admin → Paramètres → CI/CD → Enforce job token allowlist*. Dans quel sens lire la liste : elle se règle sur le projet **cible** (« qui a le droit de venir chez moi avec son jeton de job »). Le pipeline multi-projets de E12 (`trigger:project`) ne s'en sert pas (droits de l'utilisateur qui lance le pipeline) ; un job aval qui **clone** `mediagenda/deploiement` avec `CI_JOB_TOKEN` en a besoin ; la promotion utilise `DEPLOIEMENT_TOKEN`. Essai inverse depuis `formation/ci-labo` : `git clone https://gitlab-ci-token:${CI_JOB_TOKEN}@git01…/mediagenda/deploiement.git` → refus.

*4. Jetons d'identité.* Le job ne laisse jamais sortir le jeton : il n'imprime que l'en-tête et la charge utile décodés, puis vérifie la signature contre le JWKS de l'instance avec PyJWT (versions exactes), audience et émetteur compris. Résultats et revendications à exiger pour le M25 : `secrets-ci.md` §4. Points notables : `ref_protected` est une **chaîne** (`"true"`) dans le jeton ; `sub` vaut par défaut `project_path:<groupe>/<projet>:ref_type:<type>:ref:<réf>` ; la durée de vie suit le délai du job ; `runner_id` permet de n'accepter que le runner protégé.

*5. Rotation.* RB-191 §2 et §3, une rotation après l'autre avec un pipeline témoin. Contrôle :

```
admin@adm01:~$ curl -s -H "PRIVATE-TOKEN: $(<~/.config/workbook/gitlab-checks.token)" \
    https://git01.par1.medisphere.internal/api/v4/projects/mediagenda%2Fdeploiement/access_tokens | jq '.[] | {name, active, revoked, created_at, expires_at, scopes}'
```

La rotation crée un **nouveau** jeton (nouvel identifiant, `created_at` du jour) et révoque l'ancien : c'est ce `created_at` que regarde le check.

*6. Livrable.* `secrets-ci.md` (modèle complet dans les fichiers).

**Explications**

Les quatre attributs d'une variable répondent à quatre questions différentes : **qui la reçoit** (protégée : références protégées ; portée : environnement), **qui la voit dans un journal** (masquée), **qui la relit** (cachée : plus personne, pas même un Maintainer), **comment elle arrive** (type fichier : pas dans l'environnement du processus). Aucune ne répond à « quel runner » : GitLab Free ne sait pas lier une variable à un runner, d'où le secret monté par le runner protégé (E24). Le jeton d'identité inverse le modèle : plus de secret stocké, le job prouve **qui il est** (projet, référence, protection, runner, environnement) par une signature de GitLab, et c'est le coffre (M25) qui décide.

**Alternatives**
- *Secure Files* (fichiers chiffrés par projet, téléchargés par le job) : pratique pour des certificats, mêmes limites qu'une variable fichier.
- *Fine-grained permissions* du `CI_JOB_TOKEN` (portées par point d'accès) : réduit encore ce que peut faire un jeton de job autorisé ; à activer projet par projet quand la fonction est disponible sur ta version.
- Secrets externes (`secrets:` + OpenBao/Vault) : c'est le M25 ; en Free, l'intégration native `secrets:vault` est Premium, l'authentification par `id_tokens` + `bao`/`vault` CLI dans le job fonctionne partout.

**Pièges classiques**
- Afficher l'inventaire avec les valeurs (`jq .` sur la réponse brute) : la commande de vérification devient la fuite.
- Rendre « cachée » une variable sans noter sa valeur ailleurs (Vault) : plus personne ne peut la relire, il faut la régénérer à la source.
- Portée d'environnement au niveau du **groupe** : refusée en Free (Premium).
- Décoder un JWT avec `base64 -d` sans corriger l'alphabet base64url ni le remplissage : erreurs aléatoires.
- Faire tourner un jeton sans mettre à jour la variable dans la même minute : promotion cassée jusqu'au prochain passage.

**En production chez MédiSphère**
Inventaire mensuel automatique (le script en pipeline planifié, rapport à `securite@`), rappels d'échéance par courriel (jetons qui expirent à 14 jours), jetons longue durée remplacés par OpenBao au M25 (secrets dynamiques à durée de vie courte, authentification par `id_tokens`), journal d'audit de GitLab exporté vers Loki (M22) pour tracer les lectures et modifications de variables.

---

### M19-E26 — Monter GitLab, les runners et l'agent en 19.5

**Solution**

Fichiers : [plan de changement](fichiers/M19-E26/medisphere/docs/livraison/ci/changements/CHG-2026-montee-19.5.md), [RB-192](fichiers/M19-E26/medisphere/docs/livraison/ci/runbooks/RB-192-monter-gitlab-runners-agent.md), [versions des releases](fichiers/M19-E26/k8s/releases/50-ci.yaml.gotmpl.extrait), [values du chart 0.94](fichiers/M19-E26/k8s/composants/values-runner-0.94.diff), [agent](fichiers/M19-E26/k8s/composants/gitlab-agent/values.yaml.extrait), [runners du socle (Ansible)](fichiers/M19-E26/ansible/inventories/lab/group_vars/role_runner/gitlab_runner.yml.extrait), [job `etiquettes-job`](fichiers/M19-E26/ci-labo/etiquettes-job.gitlab-ci.yml).

*1. Préparation.* Lecture de l'article de version 19.5 et des notes de montée ; points qui touchent ce lab : 19.5 est un arrêt obligatoire ; `CI_RUNNER_TAGS` (documentée comme tableau JSON, rendue jusqu'ici à la manière d'un tableau Ruby) rendue en JSON strict, si le changement amont est bien dans la 19.5 ; agent 19.5 en `grpcs://` par défaut ; exécuteur Kubernetes (message clair quand le *helper* est tué par manque de mémoire). Versions des charts lues dans l'index :

```
admin@adm01:~$ helm repo update gitlab && helm search repo gitlab/gitlab-runner --versions | head -3
NAME                  CHART VERSION  APP VERSION  DESCRIPTION
gitlab/gitlab-runner  0.94.0         19.5.0       GitLab Runner
gitlab/gitlab-runner  0.93.0         19.4.0       GitLab Runner
admin@adm01:~$ helm search repo gitlab/gitlab-agent --versions | head -3
gitlab/gitlab-agent   2.33.0         v19.5.0      GitLab Agent
gitlab/gitlab-agent   2.32.0         v19.4.0      GitLab Agent
```

Inventaire des versions : RB-192 §2.3 (API `/version`, `/runners/:id/managers` pour **chaque** gestionnaire, image d'`agentk`). Recherche de `CI_JOB_TAGS`/`CI_RUNNER_TAGS` : aucun usage dans les composants (seul le job témoin). Différence du chart 0.94 : `image.repository` remplace `image.image` (encore lue) ; on migre dans la même MR.

*2. Plan.* Voir le fichier : le point de non-retour est la réouverture de GitLab ; le retour arrière avant, c'est l'instantané de VM ; après, la restauration RB-010 avec perte annoncée.

*3. Sauvegardes.*

```
root@pve01:~# vzdump 1004 --storage pbs-par2 --mode snapshot --notes-template 'CHG-2026 avant 19.5'
admin@git01:~$ sudo gitlab-backup create STRATEGY=copy
admin@git01:~$ sudo ls -lh /var/opt/gitlab/backups/ | tail -1
root@pve01:~# qm snapshot 1004 avant-19-5 --description "CHG-2026"
```

(La sauvegarde PBS se fait aussi par `wb-backup-gitlab.service` si c'est ainsi que M01 l'a outillée.) Ce que sert chacune : PBS = la VM entière, retour rapide si l'hôte ou le disque est en cause ; `gitlab-backup` + secrets = restauration sur une **autre** machine ou version identique, et extraction d'un projet ; instantané = retour arrière en minutes pendant la fenêtre, à jeter ensuite.

*4. GitLab.*

```
admin@adm01:~$ for id in <IDS-DES-4-RUNNERS>; do curl -sSf -X PUT -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(<~/.config/workbook/gitlab-admin.token)") \
    "https://git01.par1.medisphere.internal/api/v4/runners/$id" -d paused=true > /dev/null; done
admin@git01:~$ sudo gitlab-rake gitlab:background_migrations:list | grep -v finished
admin@git01:~$ sudo apt-mark unhold gitlab-ce && sudo apt-get update && sudo apt-get install gitlab-ce=19.5.Z-ce.0 && sudo apt-mark hold gitlab-ce
admin@git01:~$ sudo gitlab-ctl status && sudo gitlab-rake gitlab:check SANITIZE=true && sudo gitlab-rake gitlab:doctor:secrets
```

*5. Runners.* MR sur `plateforme/k8s` (versions + `image.repository`), `helmfile -e par1 -l composant=gitlab-runner diff` puis `apply`, réactivation, contrôle du gestionnaire :

```
admin@adm01:~$ curl -s -H "PRIVATE-TOKEN: $(<~/.config/workbook/gitlab-checks.token)" \
    https://git01.par1.medisphere.internal/api/v4/runners/<ID>/managers | jq -r '.[] | [.system_id, .version, .status, .contacted_at] | @tsv'
```

Les anciens gestionnaires (pods remplacés) restent listés quelque temps en `offline`/`stale` : c'est normal avec un jeton `glrt-` (un `system_id` par pod) ; ils disparaissent seuls, ou se suppriment. Puis `gitlab-runner-protege`, puis `runner01` et `runner02` par Ansible (variable de version du rôle `gitlab_runner`). L'image *helper* change dans la même MR (étiquette `x86_64-v19.5.0` et nouvelle empreinte, relevée par `skopeo` à travers Harbor, comme celle du gestionnaire) : vérifie-la sur un pod de job. L'autre choix, `x86_64-v${CI_RUNNER_VERSION}`, suit seul la montée mais renonce à l'empreinte.

*6. Agent.* Chart 2.33.0, puis `kasAddress: grpcs://git01.par1.medisphere.internal`. Contrôles : `kubectl -n gitlab-agent logs deploy/gitlab-agent --tail=50` (connexion établie, aucune erreur TLS), page *Clusters Kubernetes* du projet `plateforme/k8s` (« Connecté », version de l'agent), relance de `deployer-dev`. Si la connexion échoue (NGINX qui ne parle pas HTTP/2, proxy sur le chemin) : retour immédiat à `wss://…/-/kubernetes-agent/`, analyse ensuite.

*7. Après.* Pipelines témoins ; le job `etiquettes-job` montre `CI_RUNNER_TAGS = ["k8s", "kubernetes"]` (format inchangé pour des étiquettes simples) ; RB-192 et compte rendu.

**Explications**

Les arrêts obligatoires existent parce que certaines migrations de base (dont les migrations d'arrière-plan par lots) doivent être **terminées** avant que la version suivante supprime le code qui les gère : sauter un arrêt, c'est arriver avec une base dans un état que la nouvelle version ne sait plus traiter. Les runners et l'agent dialoguent avec GitLab par des API versionnées : une mineure de retard fonctionne, une avance non garantie, d'où l'ordre GitLab → runners → agent. Le gRPC natif de l'agent supprime la couche WebSocket (moins d'en-têtes, de délais, de relais à configurer) quand NGINX termine TLS en HTTP/2 ; derrière un répartiteur qui ne relaie pas HTTP/2 (HAProxy en mode HTTP/1.1, par exemple), `wss://` reste la bonne valeur.

**Alternatives**
- Monter d'abord une copie (VM restaurée depuis PBS, M01-E28) et y jouer la montée : la vraie répétition générale ; coûte une VM de 8 Go le temps de l'essai.
- Laisser les runners une mineure en retard pendant quelques jours : acceptable, mais à ne pas laisser dériver (le check de E26 l'interdit).
- Paquet GitLab en suivant toujours la dernière mineure dès sa sortie : moins de dette, plus de risque de régressions des versions `.0` (on attend le premier correctif).

**Pièges classiques**
- Lancer la montée avec des migrations d'arrière-plan en cours (« pending », « paused ») : échec des migrations ou attente interminable.
- Oublier `apt-mark hold` après l'installation : une mise à jour automatique emporte GitLab à la mineure suivante, sans fenêtre.
- Ne monter que les runners de `k8s-par1` et oublier `runner01`/`runner02`.
- Croire un runner « en ligne » alors qu'un de ses gestionnaires a encore l'ancienne version (lire `/managers`).
- Passer l'agent en `grpcs://…/-/kubernetes-agent/` (chemin du WebSocket) : en gRPC, pas de chemin.
- Supprimer l'instantané de VM tout de suite… ou l'oublier pendant des semaines (il alourdit le stockage, M01).

**En production chez MédiSphère**
Un calendrier des montées (arrêts obligatoires, correctifs de sécurité sous 7 jours) suivi par Nadia Roussel ; une plateforme de pré-production (copie de GitLab) pour les mineures ; la montée des runners par Renovate (versions de charts dans `plateforme/k8s`) ; supervision (M21) de la version de chaque gestionnaire et de l'état de connexion de l'agent.

---

### M19-E27 — Capacité et disponibilité des runners

**Solution**

Fichiers : [values (extrait)](fichiers/M19-E27/k8s/composants/gitlab-runner/values.yaml.extrait), [PriorityClass `medisphere-ci`](fichiers/M19-E27/k8s/ordonnancement/priorite-ci.yaml), [essai de charge](fichiers/M19-E27/ci-labo/charge.gitlab-ci.yml), [`bin/ci-mesurer-pipeline.sh`](fichiers/M19-E27/outils/bin/ci-mesurer-pipeline.sh), [`capacite-runners.md`](fichiers/M19-E27/medisphere/docs/livraison/ci/capacite-runners.md), [RB-193](fichiers/M19-E27/medisphere/docs/livraison/ci/runbooks/RB-193-saturation-runners.md).

*1. Comprendre.* Voir `capacite-runners.md` §1. L'essentiel : `concurrent` borne le **processus**, `limit` l'entrée `[[runners]]`, `request_concurrency` le nombre de demandes de jobs en vol. Avec un seul `[[runners]]` par gestionnaire, `limit = concurrent` est explicite et sans surprise. Deux réplicas = deux gestionnaires du même runner ; la capacité s'additionne.

*2. Calcul.* `capacite-runners.md` §2 : le plus petit de (quota de l'espace, mémoire libre des nœuds, capacité utile de buildkitd) ; dans le lab, ≈ 16 jobs. On commence par **mesurer** la mémoire libre réelle (`kubectl describe nodes`, section *Allocated resources*) plutôt que de se fier à la mémoire totale.

*3. Disponibilité.*

```
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=gitlab-runner apply
admin@adm01:~$ kubectl -n gitlab-runner get pods -o wide -l app=gitlab-runner
admin@adm01:~$ kubectl -n gitlab-runner get pdb gitlab-runner
NAME            MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
gitlab-runner   N/A             1                 1                     2m
admin@adm01:~$ curl -s -H "PRIVATE-TOKEN: $(<~/.config/workbook/gitlab-checks.token)" \
    https://git01.par1.medisphere.internal/api/v4/runners/<ID>/managers | jq '[.[] | select(.status == "online")] | length'
2
```

Le chart 0.94 a une clé `podDisruptionBudget` (rendue telle quelle sous `spec`) : `maxUnavailable: 1`. Arrêt gracieux : Kubernetes envoie `SIGTERM`, que GitLab Runner traite comme un arrêt **forcé** (jobs en cours abandonnés) ; seul `SIGQUIT` est gracieux. Le chart ne réécrit pas le signal (`dumb-init` le relaie tel quel) : `deploymentLifecycle.preStop` envoie `SIGQUIT` et attend la fin du processus, dans la limite de `terminationGracePeriodSeconds` (À vérifier sur ton lab : supprime un réplica pendant un job long et lis le journal du gestionnaire). Essai de drainage : le gestionnaire est expulsé et recréé ailleurs, l'autre continue ; le **job** du nœud drainé meurt (pod nu, `--force` exigé). Conclusion écrite dans `capacite-runners.md` §3 et RB-193 §4 : on cordonne et on attend la fin des jobs.

*4. Priorité.* `priorite-ci.yaml` dans `ordonnancement/` ; `priority_class_name = "medisphere-ci"` dans le TOML. Vérification :

```
admin@adm01:~$ kubectl -n ci-jobs get pods -o custom-columns=NOM:.metadata.name,PRIO:.spec.priorityClassName,VAL:.spec.priority
```

Le quota : pas de `scopeSelector` par priorité nécessaire, tous les pods de l'espace ont la même classe ; si un jour `ci-jobs` accueille deux classes, un quota par classe (`scopeSelector` `PriorityClass`) permet de réserver de la place.

*5. Essai de charge.* Pipeline web de `formation/ci-labo` avec `ESSAI_CHARGE=oui` :

```
admin@adm01:~/src/outils$ MESURER_GESTIONNAIRE=1 bin/ci-mesurer-pipeline.sh formation/ci-labo <ID> '^charge '
job           statut   attente_s duree_s runner   gestionnaire
charge 1/20   success  2         62      k8s-par1 s_1a2b3c…
…
jobs=20  attente médiane=4 s  p95=63 s  max=66 s
```

Avant (un réplica, `request_concurrency = 1`), les jobs démarrent un par un à quelques secondes d'intervalle et la seconde moitié attend une minute ; après, 16 démarrent presque ensemble. Les chiffres exacts dépendent de ton lab : remplis le tableau de `capacite-runners.md` §5.

*6. Seuil et runbook.* `capacite-runners.md` §6 et RB-193.

**Explications**

La file d'attente de GitLab est **tirée** par les runners (*long polling* sur `/api/v4/jobs/request`) : un gestionnaire ne demande un job que s'il a une place (`concurrent`, `limit`) et une requête disponible (`request_concurrency`). Au-delà, les jobs restent `pending` côté GitLab — ce qui est sain. Régler `concurrent` au-dessus de ce que l'espace peut accueillir déplace le problème vers Kubernetes, où il est moins visible et finit en échec : au-delà du **quota**, l'API refuse de créer le pod (`exceeded quota`) et le job échoue aussitôt à la préparation (sauf réessais `retry_limits`) ; au-delà de la **place des nœuds**, le pod reste `Pending` et le job échoue après `poll_timeout`. La priorité basse et non préemptive fait des jobs des « locataires polis » : ils prennent la place libre, la rendent à une application qui en a besoin, et n'en délogent jamais une.

**Alternatives**
- Capacité de réserve de l'exécuteur (*pause pods* de `[runners.kubernetes.autoscaler]`, documentation 19.x) : des pods de faible priorité gardent des places chaudes, préemptés quand un job arrive ; utile avec un autoscaler de nœuds, peu d'intérêt sur un cluster fixe.
- HPA du gestionnaire sur métriques personnalisées (`hpa` du chart) : la capacité est bornée par les nœuds, pas par les gestionnaires.
- Un runner par équipe avec son quota : équité garantie, capacité morcelée.

**Pièges classiques**
- `minAvailable: 2` avec deux réplicas : drainage impossible.
- Deux réplicas sur le même nœud (pas de contrainte de répartition) : aucune disponibilité gagnée.
- Augmenter `concurrent` sans le quota : création des pods refusée (`exceeded quota`), jobs en échec dès la préparation ; sans la mémoire des nœuds : pods `Pending` puis jobs en échec « timed out waiting for pod to start ».
- `request_concurrency` élevé avec un `limit` à 0 : un gestionnaire peut prendre plus de jobs que prévu (lis l'interaction dans la documentation).
- Mesurer l'attente avec la durée du pipeline : c'est `queued_duration` de chaque job qui dit la vérité.

**En production chez MédiSphère**
Métriques du gestionnaire (`/metrics`, M21) : jobs en cours, places libres, erreurs de requête ; alerte sur l'attente p95 ; tableau de bord de la CI ; révision trimestrielle du calcul avec la croissance des équipes.

---

### M19-E28 — Indicateurs de livraison (DORA)

**Solution**

Fichiers : [`indicateurs-dora.md`](fichiers/M19-E28/medisphere/docs/livraison/ci/indicateurs-dora.md), [`bin/dora.py`](fichiers/M19-E28/outils/bin/dora.py) et [ses tests](fichiers/M19-E28/outils/tests/test_dora.py) (réponses d'API simulées, `pytest`).

Le document modèle répond aux trois points : vocabulaire **propre à MédiSphère** (§1 : qu'est-ce qu'un déploiement chez nous), sources et calculs (§2), limites (§4), usage (§5). Le script remonte la chaîne déploiement → commit du dépôt de déploiement → MR de promotion (`promotion/dev-vX.Y.Z`) → étiquette du projet applicatif → date du commit. Lancement :

```
admin@adm01:~/src/outils$ bin/dora.py --deploiement mediagenda/deploiement --application mediagenda/api --environnement dev
admin@adm01:~/src/outils$ uv run pytest tests/test_dora.py
```

**Explications**

DORA mesure le **flux** (fréquence, délai) et la **stabilité** (taux d'échec, rétablissement) ensemble, parce que l'un sans l'autre se triche : déployer souvent en cassant, ou ne rien casser en ne déployant jamais. Les définitions comptent plus que les chiffres : un indicateur dont la définition change chaque mois n'a pas de tendance. Le délai mesuré depuis le **dernier** commit d'une version sous-estime le délai réel (premier commit en attente) : c'est écrit, et c'est le même biais chaque mois.

**Alternatives**
- Tableaux DORA de GitLab (Ultimate) : mêmes indicateurs, calculés à partir des déploiements et des incidents de GitLab.
- *Four Keys* (outil open source de calcul à partir d'événements de forge) : plus complet, une base et un service de plus.
- Indicateurs SPACE (satisfaction, activité, communication…) : complètent DORA sur la dimension humaine.

**Pièges classiques**
- Compter les pipelines comme des déploiements.
- Comparer des équipes ou fixer des objectifs individuels (Goodhart).
- Une fenêtre trop courte : chiffres qui sautent d'un mois à l'autre.
- Mettre un jeton dans le script ou dans la sortie collée dans la documentation.

**En production chez MédiSphère**
Calcul mensuel en pipeline planifié, résultat versionné dans `docs/livraison/` ; à partir du M20, les déploiements viennent d'Argo CD ; au M21, un tableau de bord Grafana alimenté par une métrique de déploiement.

---

### M19-E29 — Chaîne d'approvisionnement : SBOM, provenance, signature, vérification

**Solution**

Fichiers : composants v2.8.0 [`securite`](fichiers/M19-E29/ci-templates/templates/securite/template.yml.extrait) (SBOM et prédicat de provenance, signature et attestations sur `protege`, vérification) et [`deploiement`](fichiers/M19-E29/ci-templates/templates/deploiement/template.yml.extrait) (jobs `deploiement:images` et `verifier-images`) ; [`images-tierces.txt`](fichiers/M19-E29/deploiement/images-tierces.txt) de `mediagenda/deploiement` ; [`chaine-approvisionnement.md`](fichiers/M19-E29/medisphere/docs/livraison/ci/chaine-approvisionnement.md).

*1. État des lieux.*

```
admin@adm01:~$ cosign login registry.par1.medisphere.internal -u "$HARBOR_USER" --password-stdin <<<"$HARBOR_PASSWORD"   # identité de lecture (harbor-moi.env)
admin@adm01:~$ cosign tree registry.par1.medisphere.internal/medisphere/mediagenda-api@sha256:<EMPREINTE>
📦 Supply Chain Security Related artifacts for an image: …
└── 🔐 Signatures for an image tag: …
```

Avec la v2.0.0 à v2.7.0 des composants : la signature seule. La provenance de BuildKit est dans l'index (manifeste d'attestation), mais **pas** attestée par Cosign ; le SBOM est un artefact du pipeline, pas un référent de l'image. On a perdu ce que faisait `sc:signature` au M13.

*2. Producteur.* `securite:sbom` extrait aussi le prédicat SLSA v1 de l'archive (couche `in-toto.io/predicate-type: https://slsa.dev/provenance/v1` du manifeste d'attestation de l'index) ; `securite:signature` (runner protégé) signe l'index et les manifestes de plateforme puis attache deux attestations (`spdxjson`, `slsaprovenance1`) ; `securite:verification` vérifie les trois. Après une version :

```
admin@adm01:~$ cosign tree registry.par1.medisphere.internal/medisphere/mediagenda-api@sha256:<EMPREINTE>
└── 🔐 Signatures for an image tag: …
└── 💾 Attestations for an image tag: …
   ├── 🍒 sha256:…   (spdxjson)
   └── 🍒 sha256:…   (slsaprovenance1)
admin@adm01:~$ cosign verify-attestation --key ~/src/medisphere/docs/registre/cosign.pub --insecure-ignore-tlog=true \
    --type slsaprovenance1 registry.par1.medisphere.internal/medisphere/mediagenda-api@sha256:<EMPREINTE> \
  | jq -r '.payload | @base64d | fromjson | .predicate.buildDefinition.buildType'
https://github.com/moby/buildkit/blob/master/docs/attestations/slsa-definitions.md
```

(La présentation exacte de `cosign tree` varie selon la version de Cosign et le stockage des référents ; l'important : une signature et deux attestations.)

*3. Consommateur.* Deux jobs, pour ne mélanger ni les images ni les droits : `deploiement:images` (image du composant `deploiement`, qui a `kustomize` et `yq`) rend les overlays touchés et extrait **toute** clé `image` (`yq '.. | select(tag == "!!map" and has("image")) | .image'`, vérifié sur le rendu de `medidoc/deploiement`) ; `verifier-images` (image outillée : Cosign, skopeo, clé publique dont l'empreinte est contrôlée) refuse, dans l'ordre : pas de digest ; image tierce absente de la liste revue ; signature ; attestation SBOM ; attestation de provenance ; constructeur BuildKit ; label `org.opencontainers.image.source` sous `https://git01…/`. Le rapport `rapport-images.tsv` est conservé un an (preuve d'audit). Attention à la forme rendue par kustomize avec `newTag` **et** `digest` (`…/mediagenda-api:vX.Y.Z@sha256:…`) : Cosign l'accepte (l'étiquette est ignorée), mais `skopeo` (bibliothèque `containers/image`) refuse une référence qui porte à la fois une étiquette et une empreinte (« Docker references with both a tag and digest are currently not supported ») ; le job retire donc l'étiquette avant `skopeo inspect`. Identité : un robot de **lecture** `robot$medisphere+verification` en variables non protégées (les pipelines de MR tournent sur des branches non protégées : une variable protégée n'y existerait pas).

*4. Bloquant.* D'abord `allow_failure: true` sur une MR de promotion légitime ; décision pour les images antérieures (reconstruction par une version corrective, voir le document) ; puis `allow_failure: false` (valeur par défaut, écrite explicitement dans le composant) et, sur `mediagenda/deploiement`, *Paramètres → Merge requests → Pipelines must succeed* (ou `PUT /projects/:id only_allow_merge_if_pipeline_succeeds=true`).

*5. Essai inverse.*

```
admin@adm01:~/essai-porte$ printf 'FROM registry.par1.medisphere.internal/bibliotheque/debian:trixie\n' > Dockerfile
admin@adm01:~/essai-porte$ buildctl … --output type=image,name=registry.par1.medisphere.internal/plateforme/essai-porte:1,push=true   # ou buildah/podman
admin@adm01:~/src/mediagenda-deploiement$ git switch -c essai/porte-lucas
admin@adm01:~/src/mediagenda-deploiement$ (cd overlays/dev && kustomize edit set image registry.par1.medisphere.internal/medisphere/mediagenda-api=registry.par1.medisphere.internal/plateforme/essai-porte@sha256:<EMPREINTE>)
admin@adm01:~/src/mediagenda-deploiement$ git commit -am "test(dev): essai de la porte (SEC-2029)" && git push -u origin HEAD   # puis MR
```

Résultat : `verifier-images` en échec, « signature MédiSphère absente ou invalide », bouton de fusion grisé. Même essai avec une image signée par la chaîne v2.7.0 (sans provenance) : « attestation de provenance (slsaprovenance1) absente ». Nettoyage : MR fermée, branche et dépôt de test supprimés.

*6. Documentation.* Voir le fichier : §3 (ce qu'elle ne vérifie pas) et §5 (urgence) sont les sections que Sophie Laurent lira en premier.

**Explications**

Le producteur **affirme** (signature, attestations), le consommateur **vérifie** : tant que la vérification n'a lieu que dans le pipeline du producteur, une image qui n'est pas passée par ce pipeline (construite sur un poste, poussée à la main) n'est jamais contrôlée. La porte est placée là où se décide l'entrée en environnement : la MR du dépôt de déploiement. Elle travaille par digest, ce qui rend inutile toute confiance dans les étiquettes de Harbor. La provenance SLSA dit **comment** l'image a été construite (constructeur, paramètres, matériaux) ; signée par la clé de la chaîne, elle prouve que c'est **notre** chaîne qui l'affirme.

**Alternatives**
- `cosign verify-attestation --policy` (CUE ou Rego) : règles riches sur le prédicat (source exacte, paramètres de construction).
- Politique d'admission dans le cluster (Kyverno `verifyImages`, Sigstore *policy-controller*) : la vérification au **déploiement**, indépendante de la CI ; c'est le complément (M26), pas un remplaçant (le refus arrive plus tard et plus brutalement).
- Ratify, Notation (signatures Notary v2) : autres écosystèmes de signature.

**Pièges classiques**
- Vérifier une image par **étiquette** : l'étiquette peut changer entre la vérification et le déploiement.
- Oublier les `initContainers`, les CronJobs, les images d'un sous-chart (Valkey) : d'où l'extraction générique de toutes les clés `image`.
- Variables du robot de lecture **protégées** : vides dans les pipelines de MR, la porte échoue pour toutes les MR.
- Désactiver la porte « le temps du correctif » : la MR suivante passe aussi.
- Rendre la porte bloquante avant d'avoir re-signé les images en service.

**En production chez MédiSphère**
Admission par signature dans le cluster (M26), clé de signature dans OpenBao transit (M25), provenance avec la source Git et la révision (options `vcs:` de BuildKit), revue mensuelle de `images-tierces.txt`, alerte sur toute MR fusionnée malgré un échec (journal d'audit).

---

### M19-E30 — ADR : la chaîne de CI de MédiSphère

**Solution**

Modèle : [ADR-0190](fichiers/M19-E30/medisphere/docs/livraison/ci/adr/ADR-0190-chaine-ci.md). Ce qui fait un bon ADR ici :
- des **mesures du module** (lignes, durées, mémoire) plutôt que des opinions ; les cases « … » du modèle se remplissent avec tes chiffres de E20, E23, E27 ;
- pour chaque option écartée, **ce qu'elle fait mieux** (Jenkins : programmabilité, écosystème ; SonarQube : dette consolidée) ;
- la distinction entre contraintes (Free, mémoire, HDS) et préférences, et les **conditions de révision** ;
- les **conséquences concrètes** : ce que le mini-projet démonte, les dettes acceptées et leur échéance.

**Explications**

Un ADR sert à la personne qui, dans six mois, voudra rouvrir la question : il doit lui donner le contexte d'alors (ce qui pouvait changer), pas seulement la conclusion. Kaniko est le cas typique d'une option écartée **sans essai** : l'ADR dit pourquoi l'essai n'en valait pas la peine (projet archivé).

**Pièges classiques**
- Un ADR qui raconte l'historique des exercices au lieu de décider.
- Aucune condition de révision : l'ADR devient un dogme.
- Oublier les conséquences négatives (dettes) : elles reviendront sans explication.

**En production chez MédiSphère**
ADR relu en MR par Karim Benali (architecture) et Sophie Laurent (sécurité), lié depuis `docs/livraison/ci/README` ; révision planifiée au passage éventuel en Premium.

---

### M19-E31 — Questions de production : intégration continue

1. **Non.** `ref_protected` garantit que le job vient d'une référence protégée, pas que son code a été relu. Chemins : (a) un Maintainer qui pousse directement sur `main` si la branche autorise le *push* (règle de protection « Allowed to push » ≠ « No one ») ; (b) une étiquette protégée créée sur un commit non relu (qui peut créer des étiquettes `v*` ?) ; (c) un `include:` distant ou un composant en `@~latest` dont le contenu change sans revue ; (d) un pipeline planifié dont le propriétaire peut modifier les variables. Fermetures : `main` sans *push* direct (fusion par MR approuvée seulement), étiquettes protégées créables par les Maintainers seulement (ou par semantic-release), composants épinglés en version exacte, revue des pipelines planifiés ; en dernier ressort, la signature par un KMS qui exige des revendications (`ref_protected`, `project_path`, M25).
2. **Ce qui sépare** : espace de noms des processus et système de fichiers (un pod par job), politiques réseau (identiques pour tous les jobs de l'espace, donc pas d'isolement **entre** jobs : un job peut joindre un autre pod de `ci-jobs`… sauf que l'entrée est refusée par défaut), comptes sans jeton. **Ce qui ne sépare pas** : le noyau du nœud (une évasion de conteneur donne le nœud), le démon buildkitd, le cache S3 si les clés coïncident, les quotas (un projet peut prendre toute la place). Un espace par projet ou par job quand une équipe **externe** ou moins fiable arrive (prestataire, éditeur racheté), ou quand un projet manipule des données sensibles dans ses tests.
3. **Non**, pas d'exception PSA pour installer un paquet : l'installation en root est exactement ce que `restricted` empêche. Proposer : une image outillée qui contient déjà l'outil (`bibliotheque/` ou `plateforme/`, construite par la chaîne, signée) ; si l'outil change souvent, une image par projet construite par son propre pipeline ; pour des outils Python, `uv`/`pip --user` sans root. L'exception reste possible pour un besoin **non contournable**, écrite avec une date de fin (`cloisonnement.md`).
4. Risques de buildkitd partagé : **cache empoisonné** (une construction malveillante écrit une couche que réutilise une autre construction : clés de cache différentes par projet, cache distant en écriture seulement sur les références protégées — E08) ; **secrets de construction** (`--secret`) en mémoire du démon le temps de la construction, visibles d'un démon compromis ; **déni de service** (une construction gigantesque bloque les autres : limites du pod buildkitd, parallélisme du démon, quota) ; **démon lui-même** (rootless, pas de privilège, TLS mutuel, politique d'entrée). Alternative si le risque monte : un démon par niveau de confiance (un pour `protege`, un pour le reste).
5. Le cache est indexé par **clé** ; une branche non protégée qui calcule la même clé que `main` (même `uv.lock`) peut **écrire** un cache que `main` relira (dépendance trafiquée dans `.venv`). GitLab sépare par défaut les caches des références protégées et non protégées (suffixe ajouté à la clé), sauf si l'option du projet qui partage les caches est activée : la laisser désactivée ; ne jamais mettre en cache des **exécutables** produits par le job lui-même ; vérifier les dépendances par empreintes (`uv sync --locked` vérifie les hachages du verrou). Le runner protégé n'a pas de cache (E24).
6. Causes : variable démasquée (case décochée, recréée sans masque), `set -x` ou `CI_DEBUG_TRACE` avec une valeur transformée, outil qui affiche ses identifiants (`curl -v`, `env`), valeur trop courte ou avec des caractères non masquables (refusée au masquage → stockée non masquée). Gestes **avant** la cause : (1) révoquer/tourner le secret à la source (c'est lui qui compte, pas le journal) ; (2) effacer le journal du job (*Erase job* : journal et artefacts) et vérifier les artefacts téléchargés ; (3) chercher les autres journaux exposés (pipelines du même jour) ; (4) puis la cause et la prévention ; (5) incident de sécurité déclaré à Sophie Laurent (HDS : traçabilité).
7. Proposition : **artefacts** de jobs ordinaires 1 à 30 jours (`expire_in`), rapports de sécurité 1 an (preuve), SBOM et provenance **avec l'image** (référents dans Harbor, durée de vie de l'image) ; **journaux de jobs** 1 an pour les pipelines de `main` et d'étiquettes (preuve de ce qui a été livré), moins pour les branches (réglage d'instance d'expiration des pipelines) ; **images** : versions en service + N versions précédentes, `main-<sha>` 30 jours (rétention de Harbor). Coûts : stockage des artefacts dans `s3-01`/GitLab, base de GitLab (journaux), Harbor (images). HDS demande la traçabilité de **qui a déployé quoi**, pas de garder chaque binaire intermédiaire.
8. Sans GitLab : plus de push, de MR, de pipeline, de promotion, de déploiement en dev par l'agent (KAS est dans GitLab) ; ce qui tourne en production continue (Kubernetes ne dépend pas de GitLab pour faire tourner des pods ; les images sont dans Harbor). Au M20, Argo CD lit les dépôts : une panne de GitLab gèle les synchronisations (pas de dérive, pas de changement) mais n'arrête rien ; un correctif d'urgence passe alors par une procédure de bris de glace documentée.
9. Coût : mémoire réservée × durée (demandes des pods de job), CPU consommé, et surtout **temps humain d'attente** (un développeur qui attend une MR). Réglages les plus efficaces mesurés : `needs` (DAG) et caches par fichier de verrou (E23), cache BuildKit en registre (E08/E23), `interruptible` + `auto_cancel` (E06), `request_concurrency` et réplicas (E27).
10. Calendrier des montées dans `docs/livraison/ci/` (prochain arrêt obligatoire : 19.8), rappel mensuel (courriel de Nadia Roussel, ou contrôle planifié qui compare la version de `/api/v4/version` à la dernière publiée), supervision (M21) de l'âge de la version ; RB-192 à jour.
11. Parce que le consommateur ne peut pas faire confiance au pipeline du producteur : une image peut arriver par un autre chemin (poussée à la main, autre projet, registre compromis), et seul le consommateur sait **ce qu'il va déployer**. Au déploiement (M26), l'admission du cluster revérifie : protection contre un `kubectl apply` manuel ou une erreur de configuration d'Argo CD.
12. **Épinglage exact** (`@v2.8.0`) : reproductible, chaque changement est une MR relue, mais une faille corrigée en `v2.8.1` n'arrive que par une MR par projet (Renovate peut les ouvrir). **Partiel** (`@2`, `@2.8`) : correctifs automatiques, mais le pipeline change sans revue du projet. **`@~latest`** : dernier publié, y compris une majeure incompatible : jamais en production. Chez MédiSphère : exact + Renovate + contrôle de version minimale (E32) qui force la mise à jour après une faille (`versions_retirees`).
13. Reconstitution : qui pouvait **déclencher** un job de signature ce jour-là = qui pouvait pousser sur `main` ou créer une étiquette protégée de chaque projet signé (membres Maintainers et règles de protection, à l'état de ce jour : journal d'audit des membres et des réglages de protection), plus les administrateurs de GitLab, plus qui pouvait lire le Secret `cosign-medisphere` (RBAC du cluster, journal d'audit de l'API, M14-E27) et le Vault `critique`. Sans journal d'audit conservé, la réponse est « on ne sait pas » : d'où la rétention des journaux (M22).
14. Stratégie : inventaire et classement (ce qui est standard → composants ; ce qui est spécifique → jobs locaux ; ce qui n'a plus lieu d'être → supprimé), migration **par lots** en commençant par les pipelines les plus simples, période où l'ancien Jenkins tourne en lecture seule ou n'est plus alimenté, outils d'aide (assistant de migration de GitLab, réécriture guidée). Erreurs : traduire ligne à ligne (on garde les mauvaises pratiques), réinstaller Jenkins « temporairement » (ADR-0190), migrer les identifiants Jenkins en variables non protégées, oublier les déclencheurs (cron, webhooks, dépendances entre jobs).

---

### M19-E32 — Imposer le socle de sécurité à tous les projets

**Solution**

Fichiers : [`bin/ms-ci-conformite`](fichiers/M19-E32/outils/bin/ms-ci-conformite), [règles `etc/ci-conformite.toml`](fichiers/M19-E32/outils/etc/ci-conformite.toml), [tests et réponses enregistrées](fichiers/M19-E32/outils/tests/), [pipeline (extrait)](fichiers/M19-E32/outils/gitlab-ci.yml.extrait), [`conformite.md`](fichiers/M19-E32/medisphere/docs/livraison/ci/conformite.md).

Conception :
- **Faits** lus par l'API : `GET /projects/:id/ci/lint` (configuration fusionnée, `includes` résolus avec leur type et leur emplacement `…/securite@X.Y.Z`), attribut `only_allow_merge_if_pipeline_succeeds`. La fonction `evaluer()` est **pure** (projet + réponse de lint + règles → liste d'écarts) : elle se teste sans réseau sur des réponses enregistrées (`tests/donnees/*.json`).
- **Règles** hors du code (`etc/ci-conformite.toml`, `tomllib` de la bibliothèque standard) : version minimale, versions retirées, dérogations datées, projets sans image (seules R1 et R4).
- **Idempotence** : un seul ticket ouvert par projet (étiquette `conformite-ci`), mis à jour seulement si la liste des écarts change, fermé avec un commentaire quand le projet redevient conforme ; `--sans-tickets` pour un essai.
- **Identité** : un **compte de service** d'instance `ci-conformite` (disponibles en Free depuis GitLab 18.11, API `POST /service_accounts` ; pas de connexion par l'interface, pas de siège) — à défaut, un compte technique ordinaire sans connexion interactive ; Developer sur les quatre groupes, et membre de `plateforme/outils` avec le droit de lancer un pipeline sur `main` protégée (sinon la planification qu'il possède ne démarre pas : un pipeline planifié s'exécute avec les droits de son propriétaire), jeton `api` de 90 jours en variable fichier protégée, masquée, cachée de `plateforme/outils` ; le pipeline planifié appartient à ce compte (il s'exécute avec les droits de son propriétaire, et ne casse pas le jour où un humain part).
- **Exécution** : job `ci-conformite` sur `k8s`, rapports en artefacts, code de sortie 0 (option `--strict` pour un usage ponctuel).

```
admin@adm01:~/src/outils$ uv run pytest tests/test_ci_conformite.py
admin@adm01:~/src/outils$ GITLAB_TOKEN_FILE=~/.config/workbook/gitlab-checks.token bin/ms-ci-conformite --sans-tickets && cat conformite.md
```

(L'essai avec le jeton des checks est en **lecture** : `--sans-tickets`.) Planification par l'interface (*Build → Pipeline schedules*) connecté en `ci-conformite`, ou par l'API avec son jeton.

**Explications**

Sans *pipeline execution policies* (Ultimate), on ne peut pas **imposer** un job à l'exécution ; on peut en revanche **constater** chaque nuit, et rendre la non-conformité visible là où l'équipe travaille (un ticket dans son projet). La configuration **fusionnée** est la seule vérité : un projet peut inclure le composant et en neutraliser un job (`allow_failure: true`, `rules: when: never`), d'où R5 (et l'idée d'étendre R5 à `when: never`).

**Alternatives**
- `medictl ci conformite` (sous-commande du CLI de M02) au lieu d'un script : même cœur `evaluer()`, intégration au paquet ; plus propre si `medictl` est déjà installé dans l'image du job.
- *Compliance frameworks* et *security policies* de GitLab Ultimate : imposent au lieu de constater.
- Modèle de projet (*project templates*) : bon point de départ, mais rien n'empêche de s'en écarter ensuite.

**Pièges classiques**
- Ouvrir un nouveau ticket chaque nuit (pas d'idempotence) : les équipes coupent les notifications.
- Lire `.gitlab-ci.yml` brut au lieu de la configuration fusionnée : les includes et les composants n'y sont pas résolus.
- Jeton personnel d'un humain, sans expiration, sur tous les groupes.
- Pipeline planifié rouge chaque nuit : plus personne ne le regarde.

**En production chez MédiSphère**
Tableau de conformité publié, indicateur mensuel (projets conformes / total) dans la revue de Sophie Laurent, passage aux politiques d'Ultimate si la licence change (ADR-0190 §Révision).

---

### M19-E33 — Accueillir l'équipe MédiDoc dans la CI

**Solution**

Fichiers : [`medidoc/.gitlab-ci.yml`](fichiers/M19-E33/medidoc/.gitlab-ci.yml) ; dépôt `medidoc/deploiement` : [`base/`](fichiers/M19-E33/medidoc-deploiement/base/) (Deployment, Service, HTTPRoute, politiques), [`overlays/dev/kustomization.yaml`](fichiers/M19-E33/medidoc-deploiement/overlays/dev/kustomization.yaml), [`overlays/dev/livraison.yaml`](fichiers/M19-E33/medidoc-deploiement/overlays/dev/livraison.yaml), [`outils/verifier-livraison.sh`](fichiers/M19-E33/medidoc-deploiement/outils/verifier-livraison.sh), [`.gitlab-ci.yml`](fichiers/M19-E33/medidoc-deploiement/.gitlab-ci.yml), [`images-tierces.txt`](fichiers/M19-E33/medidoc-deploiement/images-tierces.txt), [`CODEOWNERS`](fichiers/M19-E33/medidoc-deploiement/CODEOWNERS).

Étapes :
1. **Pipeline de `medidoc/medidoc`** : composants `qualite` (Go : `go vet`, tests JUnit), `construction-image`, `securite`, `promotion` en v2.8.0, et un job local `go:race-couverture` : `go test -race` (cgo, gcc de l'image `golang:1.26-trixie`), couverture en mode `atomic` (obligatoire avec `-race`), pourcentage lu par `coverage:` (regex sur la ligne `total:` de `go tool cover -func`), Cobertura par `gocover-cobertura` épinglé (`@v1.4.0`, par le proxy Go). `GOPATH`/`GOCACHE` dans le projet : l'UID 1000 (E24) ne peut pas écrire dans `/go`. Pourquoi un job local : le composant `qualite` ne fait pas `-race` ; la bonne suite est une entrée `race: true` dans `qualite` v2.9.0 (MR proposée), pas un composant de plus.
2. **`medidoc/deploiement`** : projet créé (branche `main` protégée, fusion par les Maintainers, « Pipelines must succeed »), `base/` = les objets de `plateforme/k8s/applications/medidoc-dev/` **sans** espace ni image figée (`kustomize build overlays/dev` vérifié, `kubeconform` propre), HTTPRoute au nom de production en base et remplacé en `dev` par un patch. Le composant `promotion` attend, dans le dépôt de déploiement, un `livraison.yaml` par overlay (ConfigMap `livraison`, `data.version`) et un garde-fou `outils/verifier-livraison.sh` (M17-E21, M19-E17) : `medidoc/deploiement` a les deux (garde-fou réduit à l'image de MédiDoc), et l'overlay `dev` porte `images:` avec `newTag` **et** `digest`. La validation n'inclut que l'overlay `dev` (entrée `overlays: [dev]` du composant `deploiement`).
3. **Reprise sans coupure** :
   ```
   admin@adm01:~/src/medidoc-deploiement$ kubectl diff --server-side --field-manager=medidoc-deploiement -k overlays/dev
   admin@adm01:~/src/medidoc-deploiement$ kubectl apply --server-side --field-manager=medidoc-deploiement --force-conflicts -k overlays/dev
   admin@adm01:~$ kubectl -n medidoc-dev rollout status deploy/medidoc
   ```
   `--force-conflicts` transfère la propriété des champs de l'ancien gestionnaire (`kubectl` des applications de `plateforme/k8s`) au nouveau ; sans lui, l'apply échoue sur les champs déjà possédés. Le `diff` avant : seule l'image (digest au lieu d'étiquette) et les étiquettes ajoutées changent → un redéploiement progressif (`maxUnavailable: 0`). Puis MR sur `plateforme/k8s` qui retire `applications/medidoc-dev/` et laisse un `README` qui renvoie vers `medidoc/deploiement`.
4. **Promotion** : inclusion du composant `promotion` avec `overlay: dev`, `declenchement: on_success`, `projet_deploiement: medidoc/deploiement`, `nom_image: registry.par1.medisphere.internal/medisphere/medidoc` ; jeton de projet `ci-promotion` de `medidoc/deploiement` (Developer, `api` + `write_repository`, 90 jours), variable `DEPLOIEMENT_TOKEN` de `medidoc/medidoc` (protégée, masquée et cachée, portée `promotion/*`), liste d'autorisation du `CI_JOB_TOKEN` active sur les deux projets. Étiquette `vX.Y.Z` → image signée et attestée sur `protege` → MR `promotion/dev-vX.Y.Z` dans `medidoc/deploiement` → porte E29 verte → fusion par un Maintainer → `kubectl apply` depuis `adm01` (jusqu'au M20).
5. **Exception de E24** : `medidoc/medidoc` ne lit plus `COSIGN_PRIVATE_KEY` ; `cloisonnement.md` mis à jour (restent `mediagenda/chart` et `medinotif/worker`, jusqu'au mini-projet).

**Explications**

Un dépôt de déploiement par application (ou par équipe) donne à l'équipe la propriété de **sa** configuration sans lui donner de droits sur la plateforme ; la porte et les règles de branche gardent la qualité. La base sans espace ni image figée est ce qui permet au M20 de brancher Argo CD (ApplicationSet par overlay) sans rien réécrire.

**Alternatives**
- Garder MédiDoc dans `plateforme/k8s` : moins de dépôts, mais l'équipe dépend de la Plateforme pour chaque changement.
- Un chart Helm pour MédiDoc (comme MédiAgenda au M17) : utile s'il y a beaucoup d'environnements ou de variantes ; Kustomize suffit pour un service sans dépendance.
- Donner à l'agent `k8s-par1` l'accès à `medidoc-dev` : refusé, le M20 retire justement ces accès.

**Pièges classiques**
- `-race` sans cgo (`CGO_ENABLED=0` hérité d'une image *distroless* ou d'une variable globale) : « -race requires cgo ».
- Couverture en mode `set` avec `-race` : refusé par Go (`atomic` imposé).
- Apply sans `--force-conflicts` : conflits de gestionnaire ; ou avec un autre `--field-manager` à chaque fois : propriété éclatée.
- Supprimer `applications/medidoc-dev/` **avant** la reprise : `task appliquer` avec `--prune` supprimerait MédiDoc.
- Réutiliser le jeton `ci-promotion` de `mediagenda/deploiement` : un jeton de projet ne vaut que pour son projet (et c'est voulu).

**En production chez MédiSphère**
Argo CD (M20) synchronise `overlays/dev` automatiquement ; overlays `recette` et `prod` ajoutés quand MédiDoc y arrivera ; `qualite` v2.9.0 avec `race: true` ; tableau de bord de l'équipe MédiDoc (M21).

---

### M19-E34 — Un pipeline en temps limité

**Solution** (à lire **après** la tentative chronométrée)

Fichiers : [`.gitlab-ci.yml`](fichiers/M19-E34/annuaire/.gitlab-ci.yml), [`pyproject.toml` (extrait)](fichiers/M19-E34/annuaire/pyproject.toml.extrait).

Déroulé type en 1 h 30 :
- **T0 → T1 (30 min)** : branche, `.gitlab-ci.yml` réduit à trois composants (`qualite` Python, `construction-image` avec `image_nom: medisphere/annuaire`, `securite`), `workflow:rules` sans doublons ; `pyproject.toml` : groupe `dev` avec `pytest` et `ruff` épinglés, `uv lock` ; `uv run ruff check . && uv run ruff format --check . && uv run pytest` en local d'abord (pytest exécute les tests `unittest` sans modification). Le `Dockerfile` du M12 reste : il doit seulement partir d'une image de `bibliotheque/` épinglée par digest, ce qu'il fait déjà. MR, pipeline de MR vert.
- **T1 → T2 (15 min)** : fusion, pipeline de `main` : publication `main-<sha>`, signature sur `protege`.
- **T2 → T3 (15 min)** : étiquette `v1.1.0` (protégée), publication, signature et attestations ; `cosign tree` montre signature + 2 attestations.
- **T3 → T4 (20 min)** : réglage « Pipelines must succeed », lancement manuel du pipeline planifié de conformité (`CONFORMITE=oui`), ticket fermé ; `lab/bin/check 19 34`.

Pièges vécus : ruff qui signale le formatage de `src/` ou `tests/`, que l'on n'a pas le droit de modifier (réponse : régler ruff dans `pyproject.toml` — longueur de ligne, règles sélectionnées — et noter l'écart pour l'équipe de Julien, plutôt que `ruff format` sur leur code) ; l'ancien job `images-autorisees` (gabarit v1) oublié dans un `include` ; l'étiquette `v1.1.0` posée **avant** la fusion : elle est bien protégée (motif `v*`), mais elle pointe sur un commit qui a encore l'ancien pipeline ; `latest` dans une image de job copiée du M12.

**Explications**

L'exercice mesure l'**outillage** plus que la personne : si la migration d'une application simple prend plus d'une heure et demie, c'est que les composants, leur documentation ou les modèles manquent de quelque chose. Le retour d'expérience doit produire des MR (README d'un composant, exemple pour Python sans dépendances).

**En production chez MédiSphère**
Un modèle de projet (`.gitlab-ci.yml` de trois lignes, réglages, `CODEOWNERS`) appliqué à la création d'un projet, et le contrôle de E32 qui vérifie qu'il n'a pas dérivé ; c'est l'amorce de la plateforme développeurs du module 28.
