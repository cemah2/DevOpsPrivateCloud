# Module 19 — Palier 3 : Production

Les paliers 1 et 2 ont donné à MédiSphère une vraie chaîne d'intégration continue : un runner `k8s-par1` dont les jobs tournent dans `ci-jobs`, un démon BuildKit *rootless* partagé, un cache S3, des composants CI/CD publiés au catalogue (**v2.0.0** en E10, **v2.6.0** à la fin du palier 2), des analyses de sécurité, une promotion des images par MR dans `mediagenda/deploiement` (jeton `ci-promotion`) et un déploiement en dev par l'agent `k8s-par1`. Mais tout cela tourne encore comme un banc d'essai : n'importe quel job de n'importe quelle branche partage le même runner, le même espace, le même réseau que les jobs qui signent les images et qui ouvrent les MR de promotion ; personne ne sait quels secrets traînent dans les variables de CI ni quand expirent les jetons ; GitLab est en 19.4, qui n'est plus qu'en maintenance ; un pic de pipelines le lundi matin fait la queue ; et la porte d'entrée de la production — la MR de promotion — accepte n'importe quelle image pourvu qu'elle soit écrite par digest. Sophie Laurent veut des cloisons et une chaîne d'approvisionnement vérifiée ; Claire Morel veut une plateforme montée de version, dimensionnée, mesurée et une décision écrite ; Julien Petit veut que ses équipes (MédiDoc, MédiAnnuaire) entrent dans la chaîne sans attendre. Ce palier fait passer la CI en production.

> ⚠️ **Rappel** : la CI est désormais le chemin de **toute** livraison. Avant toute intervention qui touche les runners, GitLab ou l'agent : (1) aucun pipeline de `main` ou d'étiquette en cours sur les projets applicatifs (`mediagenda/*`, `medidoc/*`) — sinon attends ou mets le runner en pause ; (2) l'ancienne configuration est dans Git (Helmfile de `plateforme/k8s`) et `helmfile -e par1 diff` est relu avant chaque `apply` ; (3) un seul runner touché à la fois : `runner02` (étiquette `docker`) reste le filet de secours des constructions tant que `k8s-par1` n'est pas revenu ; (4) les jobs qui **signent** ou **promeuvent** ne tournent jamais pendant un changement de leur runner.

**Chemin imposé** (introduction du module) : la configuration des runners, de l'agent, des espaces et des politiques vit dans `plateforme/k8s` (Helmfile, `espaces/`, `composants/`), les composants CI/CD dans `plateforme/ci-templates` (versions `vX.Y.Z` publiées par release), les outils dans `plateforme/outils`, la documentation dans `docs/livraison/ci/` de `plateforme/medisphere` ; tout passe par une MR relue. Les secrets ne sont **jamais** dans Git : Ansible Vault `critique` (`secrets/<composant>.yml` de `plateforme/k8s`) puis `outils/secrets-k8s.sh` pour les Secrets Kubernetes ; variables de CI créées par l'API ou l'interface, inscrites au **registre des secrets**.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| GitLab | `git01` (10.10.20.12), `https://git01.par1.medisphere.internal`, **19.4.x** au début du palier, **19.5.x** à partir de E26 |
| Runner `k8s-par1` (E04) | instance, étiquettes `k8s`, `kubernetes`, `run_untagged: false` ; release Helmfile `gitlab-runner` (espace `gitlab-runner`, fichier `releases/50-ci.yaml.gotmpl`), values `composants/gitlab-runner/values.yaml` ; Secrets `gitlab-runner` (jeton), `gitlab-runner-certs` (racine), `ci-cache-s3` (cache, E07) ; jobs dans `ci-jobs` (étiquette de pod `medisphere.internal/ci: job`, racine par la ConfigMap `medisphere-racine`, certificat client `buildkit-client`), compte de service `ci-job` |
| Runner `k8s-par1-protege` (E24) | instance, `access_level: ref_protected`, étiquette **`protege`**, `run_untagged: false` ; release Helmfile **`gitlab-runner-protege`** (espace `gitlab-runner`), values `composants/gitlab-runner-protege/values.yaml`, Secret de jeton **`gitlab-runner-protege-jeton`** (`secrets/gitlab-runner-protege.yml`, une ligne de plus dans la table `outils/secrets-k8s.conf` de E04), racine MédiSphère par le Secret `gitlab-runner-certs` de E04 ; jobs dans **`ci-jobs-protege`**, compte de service `ci-job` |
| Clé de signature (E24) | Secret **`cosign-medisphere`** de `ci-jobs-protege` (clés `cosign.key`, `cosign.password`), depuis `secrets/cosign-ci.yml` (Vault `critique`) ; monté **par le seul runner protégé** dans les jobs sous `/run/secrets/medisphere/cosign/` |
| BuildKit (E08) | Service `buildkitd.buildkit:1234`, TLS mutuel, pods étiquetés `app.kubernetes.io/name: buildkitd` |
| Composants | `plateforme/ci-templates`, `templates/<composant>/template.yml` ; **v2.6.0** à l'entrée (fin du palier 2 : v2.0.0 en E10, puis une mineure par exercice jusqu'à E23), **v2.7.0** après E24 (signature et promotion sur `protege`), **v2.8.0** après E29 (attestations et porte de vérification) |
| Promotion (E17) | jeton de projet `ci-promotion` de `mediagenda/deploiement`, variable `DEPLOIEMENT_TOKEN` de `mediagenda/api` ; branches `promotion/<env>-vX.Y.Z` ; seuls Julien Petit et Karim Benali fusionnent sur `main` |
| Agent (E18) | `k8s-par1`, espace `gitlab-agent`, release `gitlab-agent`, `config.kasAddress` en `wss://git01.par1.medisphere.internal/-/kubernetes-agent/` jusqu'à E26 |
| Documentation | `docs/livraison/ci/` : `cloisonnement.md` (E24), `secrets-ci.md` (E25), `capacite-runners.md` (E27), `indicateurs-dora.md` (E28), `chaine-approvisionnement.md` (E29), `adr/ADR-0190-chaine-ci.md` (E30), `conformite.md` (E32) ; runbooks dans `docs/livraison/ci/runbooks/` (à côté de RB-190, E22) : RB-191 « faire tourner les secrets de CI » (E25), RB-192 « monter GitLab, les runners et l'agent » (E26), RB-193 « saturation des runners » (E27) |

**Ordre conseillé** : E24 → E25 → E26 → E27 → E29 → E28 → E30 → E31 → E32 → E33 → E34. Le cloisonnement (E24) précède tout : les exercices suivants supposent le runner protégé. La montée de version (E26) vient avant la capacité (E27), qui change la configuration des mêmes releases. La chaîne d'approvisionnement (E29) précède la rédaction (E28, E30) et l'accueil des nouvelles équipes (E33, E34), qui en héritent. **Durée totale indicative** : 22 à 27 h.

Les vérifications se lancent **depuis `adm01`** (`lab/bin/check 19 XX`).

---

### M19-E24 — Cloisonner les runners : comptes, Pod Security, réseau, quotas  `LAB` `★★★`

> **Ticket SEC-2024** — *De : Sophie Laurent* — *Copie : Karim Benali, Claire Morel*
> J'ai lu le pipeline de la branche `essai-lucas` de `formation/ci-labo`. Une ligne de script suffirait à ce job pour lire la clé de signature Cosign (elle est dans une variable de groupe), parler à la base PostgreSQL de `mediagenda-dev`, interroger l'API de NetBox ou ouvrir une session vers n'importe quelle VM du VLAN 20. Un job de **branche** de stagiaire tourne au même endroit, avec le même réseau, que le job qui **signe** nos images de production.
> Je veux deux mondes : les jobs ordinaires, enfermés (pas de compte, pas de privilège, un réseau réduit au strict nécessaire) ; et un runner **protégé**, seul à recevoir la clé de signature et le jeton de promotion, qui n'exécute que des jobs de références protégées. Chaque exception écrite et justifiée.

**Objectifs pédagogiques**
- Mesurer ce qu'un job peut atteindre (API Kubernetes, autres espaces, VMs, Internet) avant et après les cloisons.
- Appliquer le niveau Pod Security `restricted` à des pods de job : contexte de sécurité du runner, images qui ne tournent pas en root, exceptions écrites.
- Réduire les droits du gestionnaire du runner sur l'API Kubernetes (Role dans l'espace des jobs, aucun droit ailleurs) et ceux des pods de job (aucun jeton).
- Écrire la politique réseau de sortie des jobs (CiliumNetworkPolicy) et la reporter dans la matrice des flux du cluster.
- Séparer les jobs sensibles sur un runner `ref_protected` : création par l'API, espace dédié, secrets montés par le runner et non plus portés par GitLab.

**Prérequis** : M19-E04 et E05 (runner, anatomie d'un pod de job), E07 (cache S3), E08 (buildkitd), E10 et E17 (composants, promotion) ; M14-E18 (Pod Security Admission), M15-E17 et E34 (politiques Cilium, `toFQDNs`), M13-E09 (signature Cosign).
**Durée indicative** : 4 h 30.

**Contexte technique**
- Ce dont un job ordinaire a besoin : DNS du cluster ; `git01` en 443 (clone, artefacts, API) ; `registry.par1.medisphere.internal` (`reg01`) en 443 (images, cache BuildKit) ; `s3-01` en 8333 (cache) ; `buildkitd.buildkit` en 1234 ; Internet en 443 pour les dépendances (PyPI, proxy Go). Rien d'autre : ni l'API Kubernetes, ni les autres espaces, ni les autres VMs du lab.
- Les images sont tirées par le **kubelet** (pas par le pod) : la politique réseau des pods n'a pas à ouvrir Harbor pour cela ; les conteneurs *helper* (clone, cache, artefacts) et *build* (dépendances, client BuildKit) partagent, eux, le réseau du pod.
- Pod Security `restricted` exige, pour **chaque** conteneur (y compris `init-permissions`, `helper` et les services) : utilisateur non root, `allowPrivilegeEscalation: false`, toutes les capacités retirées, profil seccomp `RuntimeDefault` (ou `Localhost`). Les options correspondantes de l'exécuteur Kubernetes sont décrites dans la documentation de GitLab Runner (*Kubernetes executor*, sections *security context* et *capabilities*). Une image qui suppose root (installation de paquets par `apt-get`, écriture dans `/root`) ne tournera plus dans `ci-jobs` : c'est voulu.
- Le runner protégé : jeton `glrt-` créé par l'API (`POST /user/runners`, comme en E04), **jamais** de jeton d'enregistrement. Le niveau d'accès d'un runner créé par un jeton `glrt-` se règle **côté GitLab** (à la création ou par `PUT /runners/:id`), pas par les options du chart.
- La clé Cosign est aujourd'hui une variable **de groupe** (M13 : `COSIGN_PRIVATE_KEY`, `COSIGN_PASSWORD`) : une variable protégée est remise à **tous** les jobs des références protégées, sur **tous** les runners. Seul un secret monté par le runner protégé lui-même ne quitte jamais son espace. Les projets encore sur les gabarits v1 et `runner02` (signature du chart, MédiDoc avant E33) gardent la variable de groupe jusqu'à leur migration : c'est une **exception écrite**, avec sa date de fin — au plus tard le mini-projet (M19-E46), qui supprime ces variables de groupe.
- Mémoire : le second gestionnaire coûte ≈ 128 Mio ; ses jobs consomment le quota de `ci-jobs-protege`, pas celui de `ci-jobs`.

> ⚠️ **Attention** : passer `ci-jobs` en `restricted` fait échouer **à la création du pod** tout job dont un conteneur ne respecte pas le niveau (message `violates PodSecurity "restricted:…"` dans le journal du job). Fais d'abord l'essai à blanc (`kubectl label --dry-run=server … --overwrite`) et relève les avertissements ; applique la configuration du runner **avant** l'étiquette de l'espace ; garde la MR de retour arrière prête (étiquette `baseline`). De même, une politique réseau de sortie trop serrée casse silencieusement le clone ou le cache : observe avec Hubble (`hubble observe -n ci-jobs --verdict DROPPED`) pendant un pipeline complet avant de déclarer la cloison finie.

**Travail demandé**
1. **État des lieux.** Copie le pipeline de sondes fourni ([`ressources/E24-sondes-cloison/.gitlab-ci.yml`](../ressources/E24-sondes-cloison/.gitlab-ci.yml)) dans une branche `sondes-cloison` de `formation/ci-labo` et lance-le. Pour chaque sonde (API Kubernetes, PostgreSQL de `mediagenda-dev`, NetBox, SSH vers `dns01`, `git01`, Harbor, `s3-01`, buildkitd, Internet en 443 et en 80, identité du processus, jeton de compte de service monté), note le résultat dans `docs/livraison/ci/cloisonnement.md` (tableau « avant »). Lis aussi le spec d'un pod de job (`kubectl -n ci-jobs get pod … -o yaml`) : utilisateur, capacités, seccomp, jeton.
2. **Pod Security.** Relève le niveau actuel de `ci-jobs` (E02), puis l'avertissement que donnerait `restricted` (essai à blanc). Dans `composants/gitlab-runner/values.yaml`, complète `[runners.kubernetes]` : contexte de sécurité du pod (non root, utilisateur et groupe fixes, `fs_group`, seccomp `RuntimeDefault`), retrait de toutes les capacités, pas d'élévation de privilège, pas de mode privilégié, jeton du compte de service non monté **par le runner** (en plus du compte `ci-job`), aucune surcharge du compte de service ni de l'espace par les variables `KUBERNETES_*`, images et services autorisés limités à Harbor. Applique (`helmfile … apply`), relance le pipeline de sondes **et** le pipeline de `main` de `mediagenda/api`, puis seulement passe `ci-jobs` en `enforce: restricted` par le code (`espaces/ci-jobs/`). Chaque job qui casse : corrige le job (image non root, `HOME` inscriptible) ou écris l'exception (qui, pourquoi, jusqu'à quand) dans `cloisonnement.md`.
3. **Droits du gestionnaire.** Remplace les droits du gestionnaire par une **Role dans `ci-jobs`** réduite à la liste de la documentation de GitLab Runner (*Configure runner API permissions*) pour les fonctions que tu utilises, sans joker ni `ClusterRole`. Prouve par des `SubjectAccessReview` (ou `kubectl auth can-i --as=system:serviceaccount:…`) que le compte du gestionnaire ne peut ni lire les Secrets de `mediagenda-dev`, ni créer de pod dans `kube-system`, et que `ci-job` ne peut rien.
4. **Réseau.** Dans `espaces/ci-jobs/40-politiques-reseau.yaml` : refus par défaut en entrée et en sortie de l'espace, puis une CiliumNetworkPolicy de sortie qui n'autorise que la liste du contexte (noms du lab par `toFQDNs`, buildkitd par sélecteur d'espace et d'étiquette, Internet en 443 **sans** les réseaux privés). Observe un pipeline complet avec Hubble, ajuste, puis relance les sondes : tableau « après ». Reporte les flux dans `docs/kubernetes/reseau/matrice-flux-cluster.md`. Si une analyse SonarQube (E16) ou un job Jenkins (E20) passe encore par la Gateway, écris-le comme exception temporaire (retirée au mini-projet).
5. **Espace protégé.** Crée `espaces/ci-jobs-protege/` sur le modèle de `ci-jobs` : PSA `restricted`, quota et LimitRange (plus petits), compte `ci-job` sans jeton, politiques réseau (mêmes sorties, **sans** Internet : les jobs qui signent et promeuvent n'en ont pas besoin — vérifie-le).
6. **Runner protégé.** Crée le runner d'instance `k8s-par1-protege` par l'API (niveau `ref_protected`, étiquette `protege`, pas de jobs sans étiquette, délai maximal), range le jeton en Vault (`secrets/gitlab-runner-protege.yml`), crée le Secret par `outils/secrets-k8s.sh`, et ajoute la release `gitlab-runner-protege` (mêmes durcissements, `ci-jobs-protege`, `concurrent` faible). Ajoute le Secret `cosign-medisphere` (depuis `secrets/cosign-ci.yml`) et monte-le, en lecture seule, **par la configuration de ce runner seulement**.
7. **Déplacer les jobs sensibles.** Publie la version **v2.7.0** de `plateforme/ci-templates` : le job de signature du composant `securite` lit la clé dans le fichier monté (plus de variable `COSIGN_PRIVATE_KEY`) et tourne sur l'étiquette `protege` ; le job de promotion du composant `promotion` aussi. Passe `mediagenda/api` sur `@v2.7.0`, pose une étiquette de version et vérifie quel runner a signé et promu. Supprime les variables Cosign **de projet** qui traîneraient ; inventorie les consommateurs restants de la variable **de groupe** et écris l'exception.
8. **Essai inverse.** Sur une branche **non protégée** de `formation/ci-labo`, un job étiqueté `protege` : que se passe-t-il ? Note le message, et pourquoi c'est le comportement voulu.

**Critères de réussite**
- [ ] `ci-jobs` et `ci-jobs-protege` appliquent `restricted` (`enforce`) ; les comptes `ci-job` des deux espaces ne montent pas de jeton ; la configuration des deux runners interdit le jeton, le privilège, l'élévation de privilège et retire toutes les capacités.
- [ ] Le gestionnaire de chaque runner n'a de droits que par une Role de son espace de jobs, sans joker ; aucun lien de `ClusterRole` vers ses comptes de service.
- [ ] Les deux espaces ont un refus par défaut et une politique de sortie Cilium ; la sortie Internet de `ci-jobs-protege` est fermée.
- [ ] Le runner `k8s-par1-protege` est en ligne, `ref_protected`, étiqueté `protege`, sans jobs non étiquetés ; le Secret `cosign-medisphere` est monté par lui seul.
- [ ] Sur la dernière étiquette `vX.Y.Z` de `mediagenda/api`, les jobs de signature et de promotion ont tourné sur `k8s-par1-protege` ; `mediagenda/api` n'a plus de variable Cosign de projet ; `DEPLOIEMENT_TOKEN` est protégée et masquée.
- [ ] `docs/livraison/ci/cloisonnement.md` (sondes avant et après, exceptions avec date de fin) est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 19 24`

<details><summary>Indice 1</summary>

Le chart crée la Role et son lien dans l'espace donné par `runners.jobNamespace` (sinon dans celui de la release) quand `rbac.create` est vrai ; `rbac.rules` remplace la règle par défaut (tout, partout dans l'espace). Lis `templates/role.yaml` du chart avant d'écrire tes règles : les groupes d'API vides valent le groupe du cœur. Côté TOML, `namespace` et `runners.jobNamespace` doivent désigner le même espace.
</details>

<details><summary>Indice 2</summary>

`[runners.kubernetes.pod_security_context]` couvre `run_as_non_root`, `run_as_user`, `run_as_group`, `fs_group` et une sous-table `seccomp_profile` ; `cap_drop`, `allow_privilege_escalation`, `privileged` et `automount_service_account_token` sont des clés directes de `[runners.kubernetes]`. Un volume de type Secret se déclare dans `[[runners.kubernetes.volumes.secret]]` (nom, chemin de montage, lecture seule) : il est monté dans **tous** les conteneurs du pod de job (`build`, `helper`, services) — pense à ce que cela implique pour les images de services admises sur le runner protégé.
</details>

<details><summary>Indice 3</summary>

Une politique `toFQDNs` ne fonctionne que si la règle DNS de la même politique (ou d'une politique de base) fait passer les requêtes par le mandataire DNS de Cilium. Pour Internet, `toCIDRSet` accepte un `cidr` et une liste `except`. Un job `ref_protected` mal étiqueté ne tombe pas en erreur : il reste **en attente** d'un runner qui n'arrivera jamais (RB-190).
</details>

**Pour aller plus loin** (facultatif) : `namespace_per_job` (un espace par job) et ses coûts ; une `RuntimeClass` gVisor ou Kata pour les jobs non fiables ; *user namespaces* des pods (`hostUsers: false`, Kubernetes 1.33+) avec l'exécuteur ; [Kubernetes executor](https://docs.gitlab.com/runner/executors/kubernetes/), [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/), [Protected runners](https://docs.gitlab.com/ci/runners/configure_runners/#prevent-runners-from-revealing-sensitive-information).

---

### M19-E25 — Secrets en CI : variables protégées, `CI_JOB_TOKEN`, jetons d'identité  `LAB` `★★★`

> **Ticket SEC-2025** — *De : Sophie Laurent* — *Copie : Nadia Roussel*
> L'auditeur HDS passe dans six semaines. Il demandera la liste de tous les secrets que manipule la CI, où ils vivent, qui peut les lire, quand ils expirent, et la preuve qu'on sait les faire tourner. Aujourd'hui je n'ai rien de tout ça.
> Et pour la suite (OpenBao au module 25), je veux que la CI s'authentifie **sans** secret stocké : les jetons d'identité OIDC de GitLab. Décode-les, dis-moi ce qu'on pourra vérifier dedans.

**Objectifs pédagogiques**
- Inventorier toutes les variables de CI (instance, groupes, projets) par l'API, avec leurs attributs (protégée, masquée, cachée, type, portée d'environnement), sans jamais afficher une valeur.
- Choisir pour chaque secret la bonne combinaison : protégée, masquée et **cachée**, type fichier, portée d'environnement (projet), et savoir ce que chaque attribut protège ou non.
- Fermer le `CI_JOB_TOKEN` : liste d'autorisation entrante de chaque projet, réglage d'instance.
- Comprendre les jetons d'identité (`id_tokens`) : émission, audience, revendications, signature vérifiable par les clés publiques de GitLab.
- Faire tourner les jetons longue durée (jeton de projet `ci-promotion`, robot Harbor de CI) et écrire RB-191.

**Prérequis** : M19-E24 (runner protégé), E17 (jeton `ci-promotion`), M13-E05 (robots Harbor), M01-E20 (jetons GitLab, registre des secrets).
**Durée indicative** : 3 h 30.

**Contexte technique**
- API des variables : `GET /admin/ci/variables`, `GET /groups/:id/variables`, `GET /projects/:id/variables` (attributs `protected`, `masked`, `hidden`, `raw`, `variable_type`, `environment_scope`). Une variable **cachée** (*Masked and hidden*) ne se crée qu'à la création (`masked_and_hidden=true`) : on ne rend pas cachée une variable existante, on la recrée. En **Free**, la portée d'environnement existe pour les variables **de projet**, pas pour celles de groupe (Premium).
- Le jeton du compte de vérification (`gitlab-checks.token`, `read_api` + `admin_mode`) lit les variables **avec leur valeur** : ton script d'inventaire ne doit jamais l'afficher ni l'écrire.
- `CI_JOB_TOKEN` : `GET|PATCH /projects/:id/job_token_scope` (`inbound_enabled`), listes d'autorisation par projet et par groupe ; réglage d'instance *Enforce job token allowlist* (Admin → Paramètres → CI/CD).
- Jetons d'identité : mot-clé `id_tokens` d'un job, audience `aud` libre ; clés publiques de vérification : `https://git01.par1.medisphere.internal/oauth/discovery/keys`. Audience retenue pour le futur OpenBao (M25) : `openbao.medisphere.internal` (le M25 la reprendra).
- Jetons longue durée connus : `DEPLOIEMENT_TOKEN` (jeton de projet `ci-promotion`, E17), robot Harbor `robot$medisphere+ci` (variables de groupe `HARBOR_ROBOT_USER`/`HARBOR_ROBOT_TOKEN`, M13), jeton de SonarQube (E16), jeton `GITLAB_TOKEN` de semantic-release (M01), jetons des runners (`glrt-`).

> ⚠️ **Attention** : recréer une variable (pour la rendre cachée) ouvre une fenêtre où les pipelines qui en dépendent échouent ; fais-le hors des pipelines de `main` et d'étiquette, une variable à la fois, et relance un pipeline témoin après chaque. Une rotation de jeton **invalide immédiatement** l'ancien : mets la nouvelle valeur en place (variable, Vault) dans la même minute. N'affiche jamais un jeton d'identité complet dans un journal : c'est un secret valable plusieurs minutes.

**Travail demandé**
1. **Inventaire.** Écris `bin/ci-inventaire-variables.sh` (`plateforme/outils`) : pour l'instance, les groupes `plateforme`, `mediagenda`, `medidoc`, `medinotif`, `legacy`, `formation` et chacun de leurs projets, une ligne par variable (niveau, propriétaire, clé, type, protégée, masquée, cachée, portée, `raw`) — **jamais** la valeur. Lance-le, et classe chaque variable : secret ou non, qui la consomme, sur quel runner, à quelle fréquence elle tourne.
2. **Durcir les variables.** Pour chaque secret : protégée ; masquée et **cachée** quand la valeur s'y prête ; type fichier pour les clés et certificats ; `raw` pour les valeurs qui contiennent `$`. Recrée `DEPLOIEMENT_TOKEN` en masquée et cachée, protégée, avec la portée d'environnement `promotion/*`, et adapte le job de promotion du composant (environnement `promotion/<cible>` sans déploiement). Montre qu'un job de `main` **sans** cet environnement ne la reçoit plus. Que protège exactement le masquage, et que ne protège-t-il pas (pense à `base64`, à un fichier d'artefact, à `set -x`) ?
3. **`CI_JOB_TOKEN`.** Pour chaque projet des groupes ci-dessus, relève `inbound_enabled` et la liste d'autorisation. Active la liste pour tous, n'autorise que les accès réellement utilisés (lequel des pipelines de E12 en a besoin ? et la promotion ?), puis active le réglage d'instance qui l'impose. Prouve qu'un job de `formation/ci-labo` ne peut plus cloner `mediagenda/deploiement` avec son `CI_JOB_TOKEN`.
4. **Jetons d'identité.** Dans `formation/ci-labo`, un job `jeton-identite` qui demande un jeton d'audience `openbao.medisphere.internal`, en décode l'en-tête et la charge utile (pas la signature) et vérifie la signature contre les clés publiques de GitLab, sans jamais écrire le jeton. Lance-le sur une branche non protégée **et** sur `main` : compare `sub`, `ref`, `ref_protected`, `project_path`, `namespace_path`, `runner_id`, `environment`, `exp - iat`. Écris dans `secrets-ci.md` quelles revendications la politique d'OpenBao devra exiger (M25) et pourquoi `sub` seul ne suffit pas.
5. **Échéances et rotation.** Liste les jetons longue durée avec leur date d'expiration (API GitLab des jetons de projet, robots Harbor). Fais tourner `ci-promotion` (API `rotate`, nouvelle valeur dans la variable, ancienne révoquée) et le secret du robot `medisphere+ci`, avec un pipeline témoin après chacun. Écris RB-191 « faire tourner les secrets de CI » (une section par secret : où il vit, qui le consomme, geste de rotation, vérification, retour arrière) et le calendrier.
6. **Livrable.** `docs/livraison/ci/secrets-ci.md` : inventaire classé (sans valeurs), règles retenues (quel attribut pour quel cas), exceptions (variable Cosign de groupe, E24), `CI_JOB_TOKEN`, revendications OIDC pour le M25, calendrier de rotation.

**Critères de réussite**
- [ ] Aucune variable dont la clé désigne un secret (`*TOKEN*`, `*PASSWORD*`, `*KEY*`, `*SECRET*`) n'est non masquée dans les groupes `plateforme`, `mediagenda`, `medidoc` et leurs projets, ni non protégée — seules exceptions admises : les identités de **lecture** (`*_RO_*`), masquées, et la variable de groupe `COSIGN_PRIVATE_KEY` (type fichier, protégée, non masquable, exception écrite de E24 jusqu'au mini-projet) ; `DEPLOIEMENT_TOKEN` est cachée et limitée à la portée `promotion/*`.
- [ ] La liste d'autorisation entrante du `CI_JOB_TOKEN` est active sur chaque projet des groupes `mediagenda`, `medidoc` et `plateforme`.
- [ ] Le jeton de projet `ci-promotion` est actif, expire dans moins de 1 an et a été tourné il y a moins de 60 jours ; le dernier pipeline d'étiquette de `mediagenda/api` a réussi après la rotation.
- [ ] Le dernier pipeline de `formation/ci-labo` contient un job `jeton-identite` réussi.
- [ ] `secrets-ci.md` et RB-191 sont sur `main` de `plateforme/medisphere`, `bin/ci-inventaire-variables.sh` sur `main` de `plateforme/outils`.

**Vérification** : `lab/bin/check 19 25`

<details><summary>Indice 1</summary>

L'API pagine : `per_page=100` et l'en-tête `x-next-page` (ou `--paginate` de `glab api`). Pour ne jamais afficher une valeur, ne garde que les champs utiles avec `jq` **dans le même tuyau**, sans fichier intermédiaire : `del(.value)` avant tout affichage.
</details>

<details><summary>Indice 2</summary>

Une variable de portée `promotion/*` n'est remise qu'aux jobs qui déclarent un environnement dont le nom correspond. Un job qui ne déploie rien peut déclarer `environment:` avec `action: prepare` : il reçoit les variables de l'environnement sans créer de déploiement.
</details>

<details><summary>Indice 3</summary>

Un JWT, c'est trois morceaux en base64url séparés par des points ; la charge utile se décode avec `cut -d. -f2 | tr '_-' '/+'` et un remplissage `=` jusqu'à un multiple de 4. Pour la signature, `python3` et la bibliothèque `PyJWT` (avec `cryptography`) ou `step crypto jwt verify --jwks` lisent directement le JWKS.
</details>

**Pour aller plus loin** (facultatif) : *fine-grained permissions* du `CI_JOB_TOKEN` (portées par point d'accès) ; personnaliser `sub` (`ci_id_token_sub_claim_components`) ; Secure Files pour les fichiers sensibles ; [CI/CD variables](https://docs.gitlab.com/ci/variables/), [CI/CD job token](https://docs.gitlab.com/ci/jobs/ci_job_token/), [ID tokens](https://docs.gitlab.com/ci/secrets/id_token_authentication/).

---

### M19-E26 — Monter GitLab, les runners et l'agent en 19.5  `LAB` `★★★`

> **Ticket CHG-2026** — *De : Claire Morel* — *Copie : Nadia Roussel, Julien Petit*
> La 19.5 est sortie le 15 octobre ; la 19.4 n'a plus que des correctifs de maintenance. La 19.5 est aussi un **arrêt obligatoire** du chemin de montée : on ne la saute pas. Cette fois, ce n'est plus seulement GitLab : les deux runners de `k8s-par1`, `runner01`, `runner02` et l'agent doivent suivre, et l'agent change de protocole par défaut.
> Fenêtre : un mardi entre 7 h et 8 h, avant l'arrivée des équipes. Je veux le plan, la sauvegarde **vérifiée**, le retour arrière écrit **avant**, et un compte rendu.

**Objectifs pédagogiques**
- Préparer une montée de version de la forge comme un changement : notes de version de chaque version traversée, arrêts obligatoires, migrations d'arrière-plan, compatibilité des runners et de l'agent, effets sur les pipelines (`CI_RUNNER_TAGS`, `CI_JOB_TAGS`).
- Sauvegarder de deux façons (PBS de la VM, `gitlab-backup` + secrets) et savoir laquelle sert à quoi.
- Monter dans l'ordre : GitLab, puis les runners (charts et paquets), puis l'agent, en vérifiant chaque étape.
- Changer l'adresse de l'agent de WebSocket (`wss://`) à gRPC natif (`grpcs://`) et comprendre ce qui change sur le chemin réseau.

**Prérequis** : M01-E29 (RB-011, première montée de GitLab), M19-E04, E18, E24 ; M17-E10 (Helmfile).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Versions : GitLab **19.5.z** (dernier correctif) ; chart `gitlab/gitlab-runner` **0.94.x** (Runner 19.5) pour les releases `gitlab-runner` et `gitlab-runner-protege` ; chart `gitlab/gitlab-agent` de la mineure 19.5 (lis `appVersion` dans l'index du dépôt de charts) ; paquets `gitlab-runner` 19.5 sur `runner01` (exécuteur `shell`) et `runner02` (exécuteur `docker`, rôle `gitlab_runner`).
- `CI_RUNNER_TAGS` est documentée comme un tableau JSON, mais GitLab la rendait jusqu'ici à la manière d'un tableau Ruby ; un changement amont (MR « Serialize CI_RUNNER_TAGS as valid JSON ») la rend en JSON strict : vérifie dans les notes de version s'il est dans ta 19.5 (`annexes/versions-bloc-DE.md` le donne pour acquis). `CI_JOB_TAGS` (apparue en 19.3) est un tableau JSON dès l'origine. Cherche **dans tous tes projets et composants** ce qui découpe ces variables à la main.
- Agent 19.5 : adresse de KAS par défaut en `grpcs://<hôte de GitLab>` quand NGINX d'omnibus termine TLS en HTTP/2 ; `wss://…/-/kubernetes-agent/` reste accepté. Les travailleurs joignent `git01` directement en 443 (flux `K8S_TRAV → git01` du M19).
- Sauvegarde : tâche PBS de `git01` (M01, `wb-backup-gitlab.service`) **et** `gitlab-backup create` + copie de `/etc/gitlab/gitlab-secrets.json` et `gitlab.rb` (Vault `critique`), RB-010.

> ⚠️ **Attention** : on ne **redescend jamais** un paquet GitLab après des migrations. Le retour arrière d'une montée qui échoue avant réouverture, c'est l'instantané de VM (`qm rollback`) ; après réouverture, c'est la restauration (RB-010) avec perte des écritures. Écris-le dans le plan **avant** de commencer, avec le critère « point de non-retour ». Mets les **quatre** runners en pause avant d'arrêter GitLab, et ne lance la montée qu'avec **zéro** migration d'arrière-plan en cours. Pour l'agent, garde la valeur `wss://` dans l'historique du dépôt : si `grpcs://` ne se connecte pas, c'est le retour arrière immédiat.

**Travail demandé**
1. **Préparation (J-7).** Lis l'article de version 19.5 et les notes de montée (19.4 → 19.5) : liste ce qui touche **ce** lab (CI, runners, agent, omnibus, dépréciations). Vérifie le chemin de montée avec l'outil officiel. Relève les versions actuelles de tout (GitLab, quatre runners et leurs gestionnaires, agent) **par l'API** et sur les hôtes. Cherche les usages de `CI_JOB_TAGS`/`CI_RUNNER_TAGS` dans `plateforme/ci-templates` et les projets ; corrige-les par une version corrective des composants si besoin.
2. **Plan de changement.** `docs/livraison/ci/changements/CHG-2026-montee-19.5.md` : périmètre, ordre, durée estimée de chaque étape, critères de passage, point de non-retour, retour arrière à chaque étape, communication (annonce par courriel via Mailpit à `plateforme@`, M19-E03), contrôles après.
3. **Sauvegardes (J0).** Sauvegarde PBS de `git01` vérifiée, `gitlab-backup create` (relève la durée et la taille) avec copie des secrets, instantané de VM sans mémoire. Note à quoi sert chacune.
4. **GitLab.** Runners en pause, migrations d'arrière-plan à zéro, montée du paquet en version exacte, lecture de la sortie. Contrôles : services, `readiness`, version par l'API, `gitlab:check`, `doctor:secrets`, migrations de la 19.5 en cours ou terminées, connexion et clone.
5. **Runners.** Montée des releases `gitlab-runner` puis `gitlab-runner-protege` (chart 0.94, un à la fois, `helmfile diff` relu, PDB respecté si E27 est déjà fait), puis des paquets de `runner01` et `runner02` par Ansible. Réactive chaque runner et vérifie la version de **chaque gestionnaire** par l'API, l'image *helper* utilisée par un job (elle doit suivre la version du runner).
6. **Agent.** Montée de la release `gitlab-agent` sur la mineure 19.5, puis passage de `config.kasAddress` en `grpcs://git01.par1.medisphere.internal` (certificat de la racine MédiSphère toujours fourni). Vérifie la connexion (API des agents, journaux d'`agentk`) et le job `deployer-dev` de `mediagenda/deploiement`.
7. **Après.** Pipelines témoins (une MR et une étiquette de `mediagenda/api`, un pipeline de `mediagenda/deploiement`), job qui affiche `CI_RUNNER_TAGS` et `CI_JOB_TAGS` (format constaté avant et après). RB-192 « monter GitLab, les runners et l'agent » (généralise RB-011 au périmètre CI) et compte rendu dans le plan de changement (durées réelles, écarts). Supprime l'instantané de VM après 24 à 48 h.

**Critères de réussite**
- [ ] GitLab répond en 19.5.x ; le paquet `gitlab-ce` est figé (`hold`) ; aucune migration d'arrière-plan n'est en échec ni en attente.
- [ ] Chaque gestionnaire en ligne des runners `k8s-par1`, `k8s-par1-protege`, de `runner01` et de `runner02` est en 19.5.x ; les releases `gitlab-runner` et `gitlab-runner-protege` utilisent le chart 0.94.x.
- [ ] L'agent `k8s-par1` tourne en 19.5.x, est connecté, et sa release déclare une adresse `grpcs://`.
- [ ] Le dernier pipeline d'étiquette de `mediagenda/api` et le dernier pipeline de `main` de `mediagenda/deploiement` ont réussi après la montée.
- [ ] Le plan de changement (avec compte rendu) et RB-192 sont sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 19 26`

<details><summary>Indice 1</summary>

Les arrêts obligatoires de GitLab tombent sur les mineures `x.2`, `x.5`, `x.8`, `x.11` (RB-011) ; l'outil *Upgrade Path* le confirme pour ta version de départ. Les migrations d'arrière-plan d'une version doivent être **terminées** avant de monter à la suivante : `gitlab-rake gitlab:background_migrations:list` ou la requête de RB-011.
</details>

<details><summary>Indice 2</summary>

`GET /runners/:id/managers` donne la version, la plateforme et l'état de **chaque** gestionnaire d'un runner : un runner « en ligne » peut cacher un vieux gestionnaire qui ne contacte plus GitLab. Si ton `helper_image` contient `${CI_RUNNER_VERSION}`, il suit seul la montée ; sinon, c'est une ligne de plus à changer.
</details>

<details><summary>Indice 3</summary>

Le chart de l'agent lit `config.kasAddress` et `config.kasCaCert` ; en gRPC, le certificat présenté est celui de NGINX de `git01`, et HTTP/2 doit y être actif. Les journaux d'`agentk` disent à quelle adresse il se connecte et pourquoi il échoue.
</details>

**Pour aller plus loin** (facultatif) : répéter la montée sur une VM restaurée depuis PBS (M01-E28) avant la production ; préparer la 19.6 (non obligatoire) et la prochaine majeure ; [Upgrade paths](https://docs.gitlab.com/update/upgrade_paths/), [GitLab Runner chart](https://docs.gitlab.com/runner/install/kubernetes/), [Agent server (KAS)](https://docs.gitlab.com/administration/clusters/kas/).

---

### M19-E27 — Capacité et disponibilité des runners  `LAB` `★★★`

> **Ticket PLAT-2027** — *De : Julien Petit* — *Copie : Claire Morel*
> Lundi, 9 h 15 : six développeurs poussent en même temps, vingt-trois jobs attendent, la MR la plus urgente a mis 14 minutes à **démarrer**. Et la semaine dernière, pendant le drainage d'un nœud, le runner a disparu deux minutes : tous les jobs en cours ont été perdus.
> Je ne demande pas des runners infinis. Je demande qu'on sache combien de jobs on tient, ce qui se passe au-delà, et que le runner survive à la maintenance d'un nœud.

**Objectifs pédagogiques**
- Distinguer les trois réglages de débit d'un gestionnaire (`concurrent`, `limit`, `request_concurrency`) et ce qui borne réellement la capacité (quota de l'espace, mémoire des nœuds, buildkitd).
- Rendre le gestionnaire disponible : plusieurs réplicas d'un même runner (plusieurs *runner managers*), répartition sur les nœuds, PodDisruptionBudget, arrêt gracieux.
- Placer les pods de job sous une PriorityClass basse et préemptible, avec des demandes et limites par défaut et des maximums surchargeables.
- Mesurer : temps d'attente (`queued_duration`), durée, saturation ; fixer un seuil et écrire RB-193.

**Prérequis** : M19-E04, E05, E24, E26 ; M14-E14 (PriorityClasses `medisphere-*`), M14-E16 (PDB), M14-E10 (quotas).
**Durée indicative** : 3 h.

**Contexte technique**
- PriorityClasses existantes (M14-E14) : `medisphere-critique` (100000), `medisphere-standard` (10000), `medisphere-essai` (100, `preemptionPolicy: Never`). La nouvelle classe s'appelle **`medisphere-ci`**.
- Le chart du runner expose `replicas`, `podDisruptionBudget`, `topologySpreadConstraints`, `affinity`, `terminationGracePeriodSeconds`, `concurrent` et `checkInterval` ; `limit` et `request_concurrency` se règlent dans `[[runners]]` du TOML. Avec un jeton `glrt-`, chaque réplica s'annonce comme un **gestionnaire** (*runner manager*) distinct du même runner.
- Quota de `ci-jobs` (E02) et mémoire des travailleurs (3 × 10 Go) : calcule la capacité réelle avant de régler `concurrent`.
- Mesure : API des jobs d'un pipeline (`queued_duration`, `duration`, `started_at`, `runner`).

> ⚠️ **Attention** : l'essai de charge (`parallel: 20`) charge les trois travailleurs ; ne le lance pas pendant qu'un composant temporaire (SonarQube ou Jenkins) tourne, ni pendant un pipeline d'étiquette. Garde `kubectl top nodes` ouvert et arrête l'essai (annulation du pipeline) si un nœud dépasse 90 % de mémoire. Un PDB `minAvailable: 2` avec deux réplicas **bloque** tout drainage : préfère `maxUnavailable: 1`.

**Travail demandé**
1. **Comprendre.** Dans la documentation de GitLab Runner, explique dans `capacite-runners.md` : `concurrent` (global au processus), `limit` (par `[[runners]]`), `request_concurrency` (requêtes simultanées de *long polling*) ; comment deux réplicas d'un même runner se partagent les jobs ; pourquoi `concurrent` × réplicas peut dépasser le quota de l'espace ou la place des nœuds, et ce qui se passe dans chaque cas (création du pod refusée par le quota, ou pod `Pending` jusqu'à `poll_timeout`).
2. **Calcul.** À partir du quota de `ci-jobs`, des demandes par défaut d'un pod de job (build + helper + services), de la mémoire libre des travailleurs et de la capacité de buildkitd, calcule le nombre de jobs simultanés soutenable. Règle `concurrent`, `limit` et `request_concurrency` en conséquence, ainsi que les demandes, limites et maximums surchargeables du TOML.
3. **Disponibilité.** Deux réplicas du gestionnaire `gitlab-runner`, répartis sur deux nœuds différents, PDB `maxUnavailable: 1`, arrêt gracieux suffisant pour finir un job. Vérifie par l'API que le runner a **deux** gestionnaires en ligne. Draine le nœud d'un réplica pendant qu'un job long tourne : le job survit-il ? Explique.
4. **Priorité.** Crée `medisphere-ci` (valeur inférieure à `medisphere-standard`, sans préemption des autres pods) dans `ordonnancement/` de `plateforme/k8s`, appliquée aux pods de job par la configuration du runner. Le quota de `ci-jobs` doit-il en tenir compte ?
5. **Essai de charge.** Dans `formation/ci-labo`, un job `charge` en `parallel: 20` (une minute de travail chacun, demandes réalistes). Mesure par l'API, pour chaque job : attente, durée, gestionnaire qui l'a pris. Fais l'essai avec l'ancienne configuration (une valeur de `concurrent`) et la nouvelle, compare (médiane et 95e centile de l'attente).
6. **Seuil et runbook.** Fixe un seuil d'attente acceptable (écrit dans `capacite-runners.md`) et ce qu'on fait quand il est dépassé : RB-193 « saturation des runners » (diagnostic, réglages, quand ajouter de la capacité, quand refuser). Le module 21 en fera une alerte.

**Critères de réussite**
- [ ] Le Deployment `gitlab-runner` a 2 réplicas prêts sur 2 nœuds différents ; un PDB couvre ses pods et autorise au moins une interruption ; le runner `k8s-par1` a 2 gestionnaires en ligne.
- [ ] La PriorityClass `medisphere-ci` existe (valeur < 10000, `preemptionPolicy: Never`) et la configuration du runner l'applique ; `concurrent`, `limit` et `request_concurrency` > 1 sont posés explicitement, avec des maximums de surcharge.
- [ ] Un pipeline de `formation/ci-labo` contient au moins 20 jobs `charge` réussis, pris par les deux gestionnaires.
- [ ] `capacite-runners.md` (calcul, mesures avant et après, seuil) et RB-193 sont sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 19 27`

<details><summary>Indice 1</summary>

Les jobs d'un pipeline `parallel` s'appellent `charge 1/20`, `charge 2/20`… ; `GET /projects/:id/pipelines/:pid/jobs?per_page=100` donne pour chacun `queued_duration` (en secondes) et l'objet `runner` ; le gestionnaire précis se lit dans le journal du job (première ligne : « Running with gitlab-runner … on k8s-par1 <système> »).
</details>

<details><summary>Indice 2</summary>

`request_concurrency = 1` (défaut) fait qu'un gestionnaire n'a qu'une requête de *long polling* à la fois : même avec des places libres, il ne prend qu'un job par cycle. La documentation détaille l'interaction avec `limit` et le drapeau `FF_USE_ADAPTIVE_REQUEST_CONCURRENCY`.
</details>

<details><summary>Indice 3</summary>

Un pod de job n'appartient à aucun contrôleur : le drainage l'**expulse** comme un pod nu (`--force` exigé), et le job échoue. C'est le gestionnaire qui doit survivre, pas le job ; pour les jobs, l'exécuteur sait créer un PDB par pod (`pod_disruption_budget`), au prix de drainages bloqués.
</details>

**Pour aller plus loin** (facultatif) : la capacité de réserve de l'exécuteur (*pause pods*, `[runners.kubernetes.autoscaler]`) ; un HPA du gestionnaire sur des métriques personnalisées ; [Advanced configuration](https://docs.gitlab.com/runner/configuration/advanced-configuration/), [Runner concurrency tuning](https://docs.gitlab.com/runner/configuration/advanced-configuration/#the-runners-section).

---

### M19-E28 — Indicateurs de livraison (DORA)  `RED` `★★`

> **Ticket PLAT-2028** — *De : Claire Morel*
> Le comité de direction veut savoir si la nouvelle chaîne « change quelque chose ». Je ne veux pas d'impressions : les quatre indicateurs DORA, calculés à partir de nos données, avec leurs limites honnêtement écrites. Les tableaux de bord DORA de GitLab sont en Ultimate : on les calcule nous-mêmes.

**Objectifs pédagogiques**
- Définir les quatre indicateurs DORA (fréquence de déploiement, délai de mise en production, taux d'échec des changements, temps de rétablissement) et ce qu'ils mesurent **chez MédiSphère** (qu'est-ce qu'un « déploiement », un « changement », un « échec » ?).
- Les calculer à partir de l'API GitLab (déploiements des environnements, MR, commits, tickets d'incident).
- Écrire leurs limites et ce qu'il ne faut pas en faire (objectifs individuels, comparaison entre équipes).

**Prérequis** : M19-E17, E18 (promotion par MR, déploiements de l'environnement `dev`), E26.
**Durée indicative** : 2 h.

**Contexte technique**
- Déploiements : environnements `dev`, `recette`, `prod` des projets `mediagenda/deploiement` (job `deployer-dev`, E18) ; API `GET /projects/:id/deployments` (filtres `environment`, `status`, `updated_after` — ce dernier exige `order_by=updated_at`, sinon `400`), `GET /projects/:id/environments`.
- Changements : MR de promotion (`promotion/<env>-vX.Y.Z`) et MR applicatives de `mediagenda/api` (`merged_at`, commits).
- Incidents : tickets étiquetés `incident` dans `mediagenda/api` (ou ceux de Nadia, `INC-…`). S'il n'y en a pas, la méthode suffit : écris-le.
- Le point d'accès `…/dora/metrics` de l'API n'est pas disponible en Free.

**Travail demandé**
1. Écris `docs/livraison/ci/indicateurs-dora.md` sur le modèle fourni ([`ressources/E28-dora/modele-indicateurs-dora.md`](../ressources/E28-dora/modele-indicateurs-dora.md)) : pour chaque indicateur, la définition retenue chez MédiSphère, la source de données (point d'accès, champs, filtres), le calcul, la fenêtre (30 jours glissants), le niveau de confiance et ses biais.
2. Écris un script (`bin/dora.py` de `plateforme/outils`, bibliothèque standard ou `requests`) qui calcule les quatre valeurs pour un projet de déploiement et un environnement, en lecture seule (jeton `read_api`), et sort un tableau Markdown. Lance-le sur `mediagenda/deploiement` / `dev` et colle le résultat (daté) dans le document.
3. Ajoute la section « Ce que ces chiffres ne disent pas » et « Ce que nous en ferons » (revue mensuelle de l'équipe Plateforme, jamais d'objectif individuel), et la façon de rendre le calcul plus juste en M20 (déploiements par Argo CD).

**Critères de réussite**
- [ ] `indicateurs-dora.md` définit les quatre indicateurs pour MédiSphère avec source, calcul, fenêtre et limites, et contient un résultat daté.
- [ ] `bin/dora.py` est sur `main` de `plateforme/outils`, lit l'API sans écrire, et ne contient aucun jeton.

<details><summary>Indice 1</summary>

Le délai de mise en production se mesure du **commit** du changement au déploiement réussi qui le contient. Chez nous, un déploiement en `dev` contient une image ; l'image vient d'une étiquette de `mediagenda/api` ; l'étiquette pointe sur un commit. Remonte la chaîne par la branche `promotion/dev-vX.Y.Z` de la MR qui a provoqué le déploiement.
</details>

<details><summary>Indice 2</summary>

Un « échec de changement » peut être un déploiement en échec, un retour arrière (déploiement d'une version antérieure), ou un incident ouvert dans les heures qui suivent : choisis, écris-le, et tiens-toi à ta définition dans le temps.
</details>

**Pour aller plus loin** (facultatif) : les quatre indicateurs plus la « fiabilité » (cinquième indicateur du rapport DORA récent) ; [DORA metrics](https://dora.dev/guides/dora-metrics-four-keys/), [Deployments API](https://docs.gitlab.com/api/deployments/).

---

### M19-E29 — Chaîne d'approvisionnement : SBOM, provenance, signature, vérification  `LAB` `★★★`

> **Ticket SEC-2029** — *De : Sophie Laurent* — *Copie : Julien Petit, Karim Benali*
> On signe nos images depuis le module 13. Mais **personne ne vérifie** au moment où ça compte : la MR de promotion dans `mediagenda/deploiement` accepte n'importe quel digest. Hier, Lucas a ouvert une MR de promotion avec une image construite sur son poste et poussée à la main dans `medisphere` ; elle aurait été fusionnée si Karim ne l'avait pas lue de près.
> Je veux que la porte d'entrée vérifie elle-même : signée par notre clé, avec son SBOM et sa provenance, construite par **notre** chaîne. Sinon la MR ne peut pas être fusionnée.

**Objectifs pédagogiques**
- Porter dans les composants la chaîne complète du M13 : SBOM SPDX attaché, provenance SLSA v1 de BuildKit attestée par Cosign (`slsaprovenance1`), signature par le runner protégé.
- Écrire une **porte de vérification** côté consommateur : pour chaque image de l'overlay modifié, refus si elle n'est pas par digest, pas signée par la clé MédiSphère, sans SBOM ni provenance, ou construite ailleurs que par la chaîne.
- Rendre la porte **bloquante** (job non facultatif, « pipelines must succeed ») et la tester par l'essai inverse.

**Prérequis** : M13-E09 et E14 (supply-chain, vérification), M19-E10, E17, E24 (runner protégé), E25.
**Durée indicative** : 3 h 30.

**Contexte technique**
- Le composant `construction-image` (E08, E10) construit par buildkitd distant avec `attest:provenance=mode=max` et produit l'archive OCI (index + manifeste d'attestation de BuildKit) ; la publication exporte `IMAGE_REF` = `registry.par1.medisphere.internal/<projet>/<dépôt>@sha256:…` (rapport `dotenv`). Les jobs de la chaîne travaillent **sur ce digest**, jamais sur une étiquette.
- Cosign 3, configuration de signature **sans service** (`/etc/medisphere/signing-config.json` de l'image `plateforme/outils-supply-chain`), vérification avec `--insecure-ignore-tlog=true` et la clé publique `docs/registre/cosign.pub` (empreinte épinglée, M13-E14). Types d'attestation : `spdxjson`, `slsaprovenance1`.
- Harbor 2.15.3 exige la signature au tirage et refuse de servir un manifeste avant la fin de l'analyse (M13-E14) : l'ordre des jobs compte.
- Le pipeline de MR de `mediagenda/deploiement` inclut le composant `deploiement` (validation `kustomize build` + `kubeconform`) : c'est là que va la porte. Il tourne sur l'étiquette `k8s` (lecture seule de Harbor par le robot de lecture).

> ⚠️ **Attention** : une porte trop stricte bloque **toutes** les promotions, y compris un correctif urgent. Avant de rendre le job bloquant : fais-le tourner en `allow_failure: true` sur les MR existantes, vérifie qu'il accepte les images légitimes **déjà en production** (les images antérieures à E29 n'ont peut-être pas de provenance attestée : décide et écris), puis seulement passe-le en bloquant. Écris dans RB-190 (ou un runbook dédié) comment passer outre en urgence — et pourquoi ce n'est pas « désactiver le job ».

**Travail demandé**
1. **État des lieux.** Pour la dernière version de `mediagenda/api` dans Harbor : liste les référents (signature, attestations) avec `cosign tree` et dans l'interface de Harbor. Que manque-t-il par rapport au M13 depuis que la construction est passée par les composants ?
2. **Côté producteur (composant `securite`).** Publie la version **v2.8.0** de `plateforme/ci-templates` : SBOM SPDX (Syft) sur l'archive ; après publication, sur le runner `protege`, signature de l'index **et** des manifestes de plateforme, attestation SBOM (`spdxjson`) et attestation de provenance (`slsaprovenance1`, prédicat extrait du manifeste d'attestation de BuildKit), puis vérification. Passe `mediagenda/api` sur `@v2.8.0` et publie une version : `cosign tree` doit montrer signature et deux attestations.
3. **Côté consommateur (composant `deploiement`).** Ajoute à la v2.8.0 un job `verifier-images` qui, dans les pipelines de MR : détermine les overlays modifiés, rend chacun (`kustomize build`), en extrait **toutes** les images (conteneurs, conteneurs d'initialisation, CronJobs), refuse toute image sans digest, puis pour chaque image vérifie la signature et les deux attestations avec la clé MédiSphère, et contrôle dans la provenance qu'elle a été construite par BuildKit à partir d'un dépôt de `git01`. Le job écrit un rapport (artefact) image par image.
4. **Bloquant.** Fais-le tourner en `allow_failure: true` sur une MR de promotion légitime (doit passer), décide du sort des images antérieures, puis passe-le en bloquant et active « Pipelines must succeed » sur `mediagenda/deploiement` (si ce n'est pas déjà fait en E13).
5. **Essai inverse.** Reproduis la MR de Lucas : une image construite sur `adm01`, poussée **sans signature** dans un dépôt de test de `medisphere` (ou signée par une autre clé), référencée par digest dans `overlays/dev`. La MR doit être bloquée, avec un message clair. Puis une image signée mais **sans provenance** : bloquée aussi. Supprime ensuite l'image et la branche de test.
6. **Documentation.** `docs/livraison/ci/chaine-approvisionnement.md` : ce qui est produit, par qui (quel runner, quelle clé), où c'est stocké, ce que la porte vérifie et ce qu'elle ne vérifie pas (contenu de la provenance, révocation de clé, Harbor lui-même), la procédure d'urgence.

**Critères de réussite**
- [ ] La dernière version `vX.Y.Z` de `mediagenda-api` dans Harbor porte une signature Cosign et au moins deux attestations (SBOM et provenance), produites par un job du runner `k8s-par1-protege`.
- [ ] Le composant `deploiement` v2.8.0 contient le job `verifier-images` ; `mediagenda/deploiement` l'inclut, le job a tourné, sans `allow_failure`, dans le dernier pipeline de MR, et le projet exige des pipelines réussis pour fusionner.
- [ ] Une MR de `mediagenda/deploiement` avec une image non signée a un pipeline en échec sur `verifier-images`.
- [ ] `chaine-approvisionnement.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 19 29`

<details><summary>Indice 1</summary>

`kustomize build overlays/dev | yq -r '.. | select(has("image")) | .image'` attrape les images de tous les types d'objets, sans liste de chemins à tenir à jour. Les overlays modifiés par une MR : `git diff --name-only "$CI_MERGE_REQUEST_DIFF_BASE_SHA" HEAD -- overlays/`, avec une profondeur de clone suffisante (`GIT_DEPTH`).
</details>

<details><summary>Indice 2</summary>

`cosign verify-attestation --type slsaprovenance1 … | jq -r '.payload | @base64d | fromjson | .predicate'` donne le prédicat. Dans la provenance SLSA v1 de BuildKit, regarde `buildDefinition.buildType` et `buildDefinition.externalParameters` (dont la source du contexte de construction). Lis le prédicat d'une image légitime **avant** d'écrire tes règles.
</details>

<details><summary>Indice 3</summary>

Harbor refuse de servir une image non signée (politique du projet `medisphere`) : pour l'essai inverse, le refus de Harbor **et** celui de la porte se cumulent. Pour tester la porte seule, pousse l'image de test dans un projet sans cette politique (un dépôt de test de `plateforme`), ou signe-la avec une clé jetable : Harbor l'acceptera, la porte non.
</details>

**Pour aller plus loin** (facultatif) : une politique d'admission dans le cluster (Kyverno `verifyImages`, module 26) qui fait la même vérification au moment du déploiement ; `cosign verify-attestation --policy` (CUE ou Rego) ; les niveaux SLSA de la construction ; [SLSA provenance v1](https://slsa.dev/spec/v1.0/provenance), [BuildKit attestations](https://docs.docker.com/build/metadata/attestations/slsa-provenance/), [Cosign](https://docs.sigstore.dev/cosign/verifying/attestation/).

---

### M19-E30 — ADR : la chaîne de CI de MédiSphère  `RED` `★★`

> **Ticket PLAT-2030** — *De : Karim Benali* — *Copie : Claire Morel, Sophie Laurent*
> On a essayé beaucoup de choses en un module : Jenkins, SonarQube, Kaniko qu'on a écarté avant de le toucher, BuildKit, deux runners. Dans six mois, quelqu'un demandera « pourquoi pas Jenkins ? », « pourquoi pas SonarQube, tout le monde l'a ? ». Je veux l'ADR qui répond, avant le mini-projet qui démonte ce qu'on ne garde pas.

**Objectifs pédagogiques**
- Écrire une décision d'architecture argumentée par des **mesures** du module (E20, E16, E23, E27) et des contraintes MédiSphère (HDS, souveraineté, édition Free, mémoire du lab).
- Présenter les options écartées honnêtement (ce qu'elles font mieux) et les conséquences de la décision (dettes, points de révision).

**Prérequis** : M19-E16, E19, E20, E23, E24, E27, E29 ; ADR précédents (format de M01, ADR-0010).
**Durée indicative** : 1 h 30.

**Travail demandé**
Écris `docs/livraison/ci/adr/ADR-0190-chaine-ci.md` (format des ADR de MédiSphère : contexte, décision, options, conséquences, statut, date, relecteurs). La décision couvre au moins :
1. **Moteur de CI** : GitLab CI avec des runners Kubernetes (`k8s-par1`, `k8s-par1-protege`) et `runner02` gardé pour l'étiquette `docker` ; Jenkins **non retenu** (comparatif chiffré de E20 : lignes, durée, maintenance des plugins, surface d'attaque, identité).
2. **Analyse de qualité** : SonarQube Community Build **non retenu** (pas d'analyse de MR ni de branches en édition communautaire, coût mémoire, une base de plus) ; ce qui le remplace (ruff, couverture dans GitLab, Semgrep CE) et ce qu'on perd.
3. **Construction d'images** : BuildKit *rootless* partagé avec TLS mutuel ; Kaniko **écarté** (archivé par Google en juin 2025, fork de maintenance) ; Buildah sur `runner02` en secours ; pas de Docker-in-Docker (privilège).
4. **Sécurité** : runner protégé, secrets montés par le runner, porte de vérification ; ce qui reste exposé (variable de groupe Cosign jusqu'à la fin des migrations, `CI_JOB_TOKEN`), ce qui viendra au M25 (OpenBao, jetons d'identité) et au M26 (admission).
5. **Partage** : composants CI/CD versionnés, catalogue de l'instance, socle imposé par contrôle (E32) faute de politiques d'exécution de pipelines (Ultimate).
6. **Conséquences et révision** : ce qu'on démonte au mini-projet (Jenkins, SonarQube et leurs données), ce qui déclencherait une révision (passage en Premium, besoin d'analyse de MR, charge > capacité mesurée en E27).

**Critères de réussite**
- [ ] ADR-0190 sur `main` de `plateforme/medisphere`, statut « acceptée », relue par Karim Benali (MR approuvée) ; chaque option écartée a au moins un argument chiffré ou daté.

<details><summary>Indice 1</summary>

Une bonne section « Options » dit pour chaque option **ce qu'elle fait mieux** que la solution retenue : un ADR qui ne trouve aucune qualité aux options écartées ne convaincra personne dans six mois.
</details>

<details><summary>Indice 2</summary>

Distingue ce qui est une **contrainte** (édition Free, mémoire de 100 Go, HDS) de ce qui est une **préférence** (une seule interface pour les développeurs). Les contraintes peuvent changer : écris lesquelles rendraient la décision caduque.
</details>

**Pour aller plus loin** (facultatif) : un tableau de critères pondérés en annexe ; [ADR de Michael Nygard](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions).

---

### M19-E31 — Questions de production : intégration continue  `Q` `★★★`

> **Ticket PLAT-2031** — *De : Karim Benali*
> Avant le mini-projet, je te fais passer la revue que je fais à chaque nouvel ingénieur Plateforme. Réponds par écrit, argumente, et dis ce que tu ferais **chez nous**.

**Prérequis** : paliers 1 à 3 du module.
**Durée indicative** : 1 h 30.

**Questions**
1. Un runner `ref_protected` garantit-il que seul du code relu s'exécute avec la clé de signature ? Cite au moins deux façons de faire tourner du code non relu sur une référence protégée, et ce qui les ferme.
2. Les jobs de deux projets différents tournent dans le même espace `ci-jobs`. Qu'est-ce qui les sépare réellement (réseau, système de fichiers, nœud, cache), et qu'est-ce qui ne les sépare pas ? Quand faudrait-il un espace par projet ou par job ?
3. Un développeur demande une exception PSA « juste pour `apt-get install` dans son job ». Que réponds-tu, et que proposes-tu à la place ?
4. buildkitd est partagé par tous les jobs. Quels risques cela crée-t-il (cache empoisonné, secrets de construction, déni de service) et comment les limites-tu ?
5. Le cache S3 de `ci-cache` est partagé par toutes les branches d'un projet. Montre comment une branche non protégée pourrait influencer un job de `main`, et comment l'éviter.
6. Une variable masquée apparaît en clair dans un journal de job. Donne trois façons dont c'est arrivé et l'ordre de tes gestes (avant même de chercher la cause).
7. Combien de temps garder les artefacts, les journaux de jobs, les SBOM et les images ? Distingue obligations (HDS, preuve d'audit) et coûts (`s3-01`, Harbor, base de GitLab).
8. GitLab est en panne pendant une heure. Que ne peut plus faire MédiSphère, qu'est-ce qui continue de tourner en production, et que changerait le module 20 ?
9. Combien coûte une minute de pipeline chez MédiSphère (mémoire, CPU, temps humain) ? Quels sont les trois réglages qui ont le plus d'effet sur ce coût d'après tes mesures (E23, E27) ?
10. La montée 19.4 → 19.5 a été faite. Qu'est-ce qui garantit que la suivante (19.8, arrêt obligatoire) ne sera pas oubliée ? Où est le calendrier, qui est prévenu, que surveille-t-on ?
11. Pourquoi la porte de vérification (E29) est-elle dans le pipeline du **consommateur** et pas seulement dans celui du producteur ? Que faudra-t-il en plus au moment du déploiement (module 26) ?
12. Les composants sont épinglés (`@v2.8.0`). Comment une faille corrigée dans un composant arrive-t-elle dans tous les projets ? Compare épinglage exact, version partielle (`@2`) et `@~latest`.
13. Un auditeur demande la liste des personnes qui pouvaient faire signer une image de production le 3 du mois dernier. Comment la reconstitues-tu ?
14. Jenkins a été retiré. Une équipe d'un éditeur racheté arrive avec 40 `Jenkinsfile`. Quelle stratégie de migration, et quelles erreurs éviter ?

**Critères de réussite**
- [ ] Chaque réponse est argumentée, dit ce qui est fait **chez MédiSphère** et cite au moins un exercice du module ou une documentation officielle (auto-évaluation par le corrigé).

---

### M19-E32 — Imposer le socle de sécurité à tous les projets  `LIBRE` `★★★`

> **Ticket SEC-2032** — *De : Sophie Laurent* — *Copie : Claire Morel*
> Le composant `securite` existe, il est bon. Mais rien n'oblige un projet à l'inclure, ni à le garder, ni à rester sur une version maintenue, ni à exiger un pipeline vert avant fusion. GitLab sait l'imposer… en Ultimate. Nous sommes en Free.
> Je veux un contrôle automatique, chaque nuit, de tous les projets applicatifs : conforme ou pas, et quand ça ne l'est pas, un ticket dans le projet, adressé à l'équipe, qui se ferme tout seul quand c'est corrigé.

**Objectifs pédagogiques**
- Lire la configuration **fusionnée** d'un projet (includes résolus) par l'API et en tirer des faits vérifiables.
- Concevoir un contrôle idempotent qui ouvre, met à jour et ferme des tickets sans bruit.
- Faire tourner un outil de plateforme par un pipeline planifié, avec une identité dédiée aux droits minimaux.

**Prérequis** : M19-E10, E15, E24, E25 ; M02 (outils de `plateforme/outils`, `medictl`), M01 (pipelines planifiés).
**Durée indicative** : 4 h.

**Contexte technique**
- Périmètre : projets non archivés des groupes `mediagenda`, `medidoc`, `medinotif`, `legacy` (et leurs sous-groupes).
- Configuration fusionnée : `GET /projects/:id/ci/lint` (réponse `valid`, `merged_yaml`, `includes`) ; réglage « Pipelines must succeed » : attribut de projet `only_allow_merge_if_pipeline_succeeds`.
- Version minimale supportée du composant `securite` : **v2.7.0** (signature sur le runner protégé, E24) ; la liste des versions supportées fait partie de la configuration de l'outil, pas du code.
- Identité : aucun jeton personnel. Un compte de service ou un compte technique dédié, droits minimaux sur les seuls groupes du périmètre, jeton à expiration, variable protégée, masquée et cachée du projet qui porte le contrôle.

**Contraintes**
- L'outil vit dans `plateforme/outils` (sous-commande `medictl ci conformite` ou script `bin/ms-ci-conformite`), testé (tests unitaires sur des réponses d'API enregistrées), sans dépendance non épinglée.
- Règles minimales : le composant `securite` est inclus (par `include: component`, pas recopié), à une version supportée ; le projet exige des pipelines réussis pour fusionner ; la configuration CI est valide. Une règle de plus de ton choix, argumentée.
- Idempotence : un seul ticket ouvert par projet non conforme (étiquette `conformite-ci`), mis à jour s'il existe, **fermé** automatiquement avec un commentaire quand le projet redevient conforme ; aucun ticket pour un projet conforme.
- Sortie : rapport lisible (Markdown) et machine (JSON) en artefact ; code de sortie non nul si un projet est non conforme **seulement** sur demande (option), pour ne pas rendre le pipeline planifié rouge chaque nuit à cause des équipes.
- Exécution : pipeline planifié chaque nuit sur l'étiquette `k8s`, jamais sur le runner protégé ; documenté dans `docs/livraison/ci/conformite.md` (règles, exceptions, propriétaire, comment demander une dérogation).

**Critères de réussite**
- [ ] `plateforme/outils` a un pipeline planifié actif du contrôle, dont la dernière exécution planifiée a réussi il y a moins de 48 h et a produit son rapport.
- [ ] Un projet non conforme du périmètre (au moins `legacy/legacy-rdv`, qui n'inclut pas le composant) a un ticket ouvert étiqueté `conformite-ci` ; aucun projet conforme n'en a.
- [ ] Le jeton utilisé n'est pas un jeton personnel d'un humain, expire, et sa variable est protégée et masquée.
- [ ] `conformite.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 19 32`

**Pour aller plus loin** (facultatif) : un tableau de conformité publié (GitLab Pages) ; les *pipeline execution policies* et *security policies* d'Ultimate, ce qu'elles feraient de plus ; [CI Lint API](https://docs.gitlab.com/api/lint/).

---

### M19-E33 — Accueillir l'équipe MédiDoc dans la CI  `LIBRE` `★★★`

> **Ticket DEV-2033** — *De : Julien Petit* — *Copie : l'équipe MédiDoc*
> L'équipe MédiDoc construit encore sur `runner02` avec les gabarits v1, et son déploiement en dev est un dossier de `plateforme/k8s` qu'elle ne peut pas modifier. Elle veut la même chose que MédiAgenda : un pipeline standard, une image signée, une promotion par MR dans **son** dépôt de déploiement. Le module 20 branchera Argo CD dessus : il faut que la forme soit la bonne dès maintenant.

**Objectifs pédagogiques**
- Adapter le pipeline standard à une application Go (vet, tests avec le détecteur de concurrence, couverture lisible par GitLab) sans recopier les composants.
- Créer un dépôt de déploiement Kustomize (base + overlay `dev`) en reprenant l'existant sans interruption.
- Étendre la promotion par MR à un second couple application / déploiement, avec son propre jeton.

**Prérequis** : M19-E10, E11, E17, E24, E25, E29 ; M15-E34 et M16-E46 (MédiDoc dans `medidoc-dev`), M17 (Kustomize, `mediagenda/deploiement`).
**Durée indicative** : 4 h.

**Contexte technique**
- Code : `medidoc/medidoc` (Go 1.26, `go vet ./...`, `go test ./...`, port 8080). Image `registry.par1.medisphere.internal/medisphere/medidoc`.
- Existant à reprendre : `applications/medidoc-dev/` de `plateforme/k8s` (Deployment `medidoc`, Service, HTTPRoute `medidoc-dev.apps.par1.medisphere.internal`, politiques réseau, M15-E34 et M16-E46), appliqué depuis `adm01`. Les Secrets (`medidoc-s3`, `harbor-pull`) et la ConfigMap `racine-medisphere` restent hors du dépôt.
- Le déploiement en `medidoc-dev` reste fait depuis `adm01` (`kubectl apply --server-side -k`) jusqu'au module 20 : l'agent `k8s-par1` n'a pas d'accès à `medidoc-dev` et n'en recevra pas.

**Contraintes**
- `.gitlab-ci.yml` de `medidoc/medidoc` : composants `@v2.8.0` uniquement pour tout ce qui existe en composant ; jobs locaux pour ce qui est propre à Go (et dis pourquoi ce n'est pas un composant… ou fais-en un) ; aucun job sur `docker`, aucun privilège ; tests avec `-race` ; couverture visible dans la MR (rapport de couverture et pourcentage).
- Image construite par buildkitd, analysée, SBOM et provenance attestés, signée sur `protege`, promue par MR dans **`medidoc/deploiement`** (branche `promotion/dev-vX.Y.Z`, image par digest), jeton de projet `ci-promotion` propre à ce dépôt, variable protégée, masquée, cachée, de portée `promotion/*`.
- `medidoc/deploiement` : `base/` (objets de l'application sans espace de noms ni image figée), `overlays/dev/` (espace `medidoc-dev`, image par digest), pipeline de MR par le composant `deploiement` (porte E29 comprise) ; `main` protégée, fusion par les Maintainers de MédiDoc et de la Plateforme.
- Reprise sans coupure : le premier `apply` du dépôt prend la main sur les objets existants (gestionnaire de champs) ; `applications/medidoc-dev/` est retiré de `plateforme/k8s` **après**, par MR qui renvoie vers le nouveau dépôt.
- Les anciens consommateurs de la variable de groupe Cosign diminuent : mets à jour l'exception de E24.

**Critères de réussite**
- [ ] Le dernier pipeline de `main` et celui de la dernière étiquette `vX.Y.Z` de `medidoc/medidoc` ont réussi, n'incluent que des composants (et des jobs locaux) et aucun job n'a tourné sur `runner02`.
- [ ] La dernière version de `medidoc` dans Harbor est signée et attestée ; une MR de promotion existe dans `medidoc/deploiement` avec l'image par digest.
- [ ] `medidoc/deploiement` a `base/` et `overlays/dev/` sur `main` ; le Deployment `medidoc-dev/medidoc` tourne avec l'image par digest de l'overlay.

**Vérification** : `lab/bin/check 19 33`

**Pour aller plus loin** (facultatif) : un composant `qualite-go` publié au catalogue ; la couverture en Cobertura sans outil tiers ; [Go test coverage](https://go.dev/doc/build-cover), [Code coverage in GitLab](https://docs.gitlab.com/ci/testing/code_coverage/).

---

### M19-E34 — Un pipeline en temps limité  `CHRONO` `★★★`

> **Ticket DEV-2034** — *De : Julien Petit* — *Copie : Claire Morel*
> MédiAnnuaire tourne toujours avec le pipeline écrit en urgence au module 12, sur `runner02`, gabarits v1. Claire veut savoir combien de temps il faut à la Plateforme pour faire entrer **une** application existante dans la chaîne standard. Chrono en main.

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé, pas d'autres notes que **ta** documentation (`docs/livraison/ci/`), ton code (`plateforme/ci-templates`, les pipelines de `mediagenda/api` et `medidoc/medidoc`) et la documentation officielle.
- Durée cible : **1 h 30** entre l'ouverture du dossier (T0) et la livraison vérifiée (T4).
- Tout passe par Git et la CI ; une commande manuelle est permise pour essayer et constater, notée dans la feuille de temps.

**Prérequis** : M19-E24, E29, E33 ; M12-E34 (MédiAnnuaire, projet `mediagenda/annuaire`).
**Durée** : 1 h 30 chronométrées + 30 minutes de retour d'expérience.

**Dossier** : [`ressources/E34-dossier-chrono.md`](../ressources/E34-dossier-chrono.md) (besoin, exigences, feuille de temps). Lis-le à T0, pas avant.

**Critères de réussite**
- [ ] Toutes les exigences du dossier sont satisfaites à T4 (vérification ci-dessous).
- [ ] La feuille de temps est remplie (T0 à T4) et le temps total est inférieur à 1 h 30 ; le retour d'expérience (une demi-page) est rédigé, et ta documentation mise à jour par MR si l'exercice en a montré un manque.

**Vérification** : `lab/bin/check 19 34` (à lancer à T4).

**Pour aller plus loin** (facultatif) : un **modèle de projet** (gabarit `.gitlab-ci.yml` d'une ligne d'include par composant, `CODEOWNERS`, réglages de projet) appliqué par l'outil de E32 ; c'est l'idée du module 28.
