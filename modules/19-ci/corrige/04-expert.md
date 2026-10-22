# Module 19 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. En CI, « j'ai relancé et ça passe » est presque toujours faux : la relance passe sur un autre runner, après l'expiration d'un cache, ou simplement parce que la panne est intermittente, et la preuve (journal du job, pod supprimé, événements expirés au bout d'une heure) part avec elle.

Les scripts d'injection sont dans `corrige/pannes/` : `_m19-commun.sh` contient les fonctions partagées (API GitLab avec ton jeton d'administration, commits « de Lucas » par l'API des commits avec `author_name`/`author_email`, publication d'une version du composant `canari`, modification du gabarit TOML du runner, sauvegarde et restauration d'objets Kubernetes en JSON nettoyé, création du projet témoin à partir de `_m19-temoin/`, lancement et suivi des pipelines du canari, contrôles de santé). Les états d'origine sont gardés sur `adm01` dans `~/.local/state/workbook/M19-EXX/`, et sur `s3-01` dans `/var/lib/workbook/` (M19-E38).

> **Remarque sur les traces** : les commits des pannes ont pour **auteur** Lucas Martin mais pour **committeur** ton compte d'administration (c'est ce que fait l'API des commits quand on lui passe `author_name`) ; les changements de runner, de variables et de projet faits par l'API apparaissent sous ton nom dans les événements d'audit. En production, ce serait celui de Lucas : c'est exactement pour cela qu'on ne partage pas un jeton d'administration et qu'on garde les *audit events*. `git log --format=fuller` montre les deux identités.

Les sorties reproduites sont **représentatives** : identifiants, noms de pods, formulations exactes varient selon ta version (GitLab 19.4 ou 19.5, Runner et chart 0.93 ou 0.94, Kubernetes 1.36, Cilium 1.20, BuildKit 0.34, SeaweedFS du M05).

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) :
- Le témoin (`_m19-temoin/`) a été validé par `yq` et `python -m py_compile`, pas exécuté sur un GitLab 19.x : la référence d'un composant de son propre projet par une étiquette sans `v` (`canari@1.0.0`), l'entrée `type: number` interpolée dans une variable entre guillemets, et l'accès HTTPS au dépôt par en-tête `Basic` avec un jeton d'accès de projet (nom d'utilisateur quelconque) sont conformes à la documentation, **à vérifier sur ton lab**.
- E35 v3 : comportement du runner face à `exceeded quota` (échec immédiat à la préparation par défaut ; nouvelles tentatives si `retry_limits` le prévoit dans ton gabarit).
- E36 v2 : le gestionnaire redémarré avec un Secret de certificats vide doit échouer à son enregistrement (`x509`) et redémarrer en boucle ; selon la version du chart, l'échec peut apparaître dans `register-the-runner` ou dans la sonde `check-live`.
- E37 v1 : réémission immédiate du certificat client par cert-manager quand `issuerRef` change (raison `IncorrectIssuer`) ; message exact de `buildctl` face à un certificat client d'une autre autorité. E37 v3 : PUT d'un robot Harbor 2.15 avec le corps complet renvoyé par `GET /robots/{id}`. E37 v4 : présence de `fallocate` dans l'image `moby/buildkit:*-rootless` (sinon la variante est sautée).
- E40 v2/v3 : le masquage de GitLab ne reconnaît pas la forme base64 d'une valeur (comportement attendu, mais les versions récentes du runner masquent aussi certaines formes encodées : vérifie ce que tu observes et note-le dans RB-198).
- E41 v4 : un pipeline planifié dont le propriétaire est bloqué n'est plus exécuté (documenté) ; l'affichage exact dans la page *Schedules* varie.
- E42 v2 : `MutatingAdmissionPolicy` en `admissionregistration.k8s.io/v1` (GA en 1.36) avec une mutation `ApplyConfiguration` sur `spec.activeDeadlineSeconds` ; si ton API refuse l'objet, la variante est sautée. E42 v4 : choix des victimes par l'ordonnanceur. Il épargne d'abord les pods les plus prioritaires : un pod sans PriorityClass (priorité 0) ou en `medisphere-essai` sur le même nœud serait préempté **avant** le job ; le script saute donc la variante si le nœud du job porte un tel pod (garde-fou : jamais une application touchée par une panne de CI).
- E44 : noms exacts des classes Sidekiq de création du pipeline. Vérifié dans le code : la clé `gitlab_workhorse['api_ci_long_polling_duration']` existe dans `gitlab.rb` mais vaut `nil` par défaut (omnibus), et le drapeau `-apiCiLongPollingDuration` de Workhorse a pour défaut 50 **nanosecondes** : sans réglage, pas de *long polling* (documentation *Long polling* : « you should enable long polling », exemple `"50s"`).

---

## Méthode commune aux pannes de CI

1. **Lire tout ce que GitLab dit.** Journal du job **depuis le haut** (runner, exécuteur, image, étapes `prepare`, `get_sources`, `restore_cache`, script, `archive_cache`, `upload_artifacts`), page du job (message *stuck*), page du pipeline (erreurs de création, configuration fusionnée), API des runners (`status`, `contacted_at`, `paused`, `tag_list`, `access_level`, `maintenance_note`).
2. **Situer l'étage.** Création → file → gestionnaire → API Kubernetes (admission, quotas) → ordonnanceur et kubelet → pod (helper, image, script) → services joints (Harbor, `s3-01`, `buildkitd`, KAS) → déploiement.
3. **Chercher ce qui a bougé.** `git log` des dépôts de code (`plateforme/k8s`, `plateforme/ci-templates`, projet concerné), versions de composants consommées, `helmfile -e par1 diff`, *audit events* de GitLab (Admin), journal d'audit de l'API Kubernetes (M14-E27), notes de maintenance des runners, annotations laissées sur les objets.
4. **Protéger avant d'agir.** Pas de relance en boucle (on écrase la preuve et on charge le cluster) ; pas de suppression de pods de job « pour voir » ; un secret exposé est **compromis**, il se remplace.
5. **Corriger à la racine, puis faire converger le code.** Values Helmfile, Vault puis `outils/secrets-k8s.sh`, manifestes de `plateforme/k8s`, nouvelle version de composant (jamais la réécriture d'une étiquette publiée).
6. **Prévenir** : quel contrôle (canari planifié, alerte sur le temps d'attente des jobs au M21, règle de revue de MR, test de composant) aurait vu la panne avant l'utilisateur ?

Commandes de base utilisées partout (à garder dans un fichier de fonctions de ton dépôt d'outils) :

```
admin@adm01:~$ GITLAB=https://git01.par1.medisphere.internal
admin@adm01:~$ gl() { curl -sS -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<~/.config/workbook/gitlab-admin.token)") "$GITLAB/api/v4/$1" "${@:2}"; }
admin@adm01:~$ P=$(jq -rn --arg s formation/ci-pannes '$s|@uri')
admin@adm01:~$ gl "projects/$P/pipelines?per_page=5" | jq -r '.[] | [.id, .status, .source, .ref, .sha[0:8]] | @tsv'
admin@adm01:~$ gl "projects/$P/jobs?per_page=5" | jq -r '.[] | [.id, .name, .status, (.runner.description // "-"), .failure_reason // ""] | @tsv'
admin@adm01:~$ gl "projects/$P/jobs/<id>/trace" | less -R
```

La fonction lit le jeton par un descripteur (jamais sur la ligne de commande, donc absent de `ps` et de l'historique).

---

### M19-E35 — Panne : les jobs restent en attente

**Démarche de diagnostic**

*Symptômes* : variantes 1 et 2, tous les jobs `k8s` restent `pending` ; variante 3, le job du canari passe en `running` puis échoue à la préparation (ou réessaie) ; variante 4, seul le job `signer-essai` de la branche de Lucas attend.

*Hypothèses* : aucun runner ne porte les étiquettes demandées ; runner suspendu ou hors ligne ; runner protégé et référence non protégée ; job pris mais pod refusé (quota, admission) ; gestionnaire saturé (`concurrent`, `limit`).

**Étape 1 — Pending ou running ?**

```
admin@adm01:~$ gl "projects/$P/jobs?scope[]=pending&scope[]=running" | jq -r '.[] | [.id, .name, .status, .ref, (.tag_list | join(","))] | @tsv'
4812    canari         pending   main                      k8s
```

Un job `pending` n'a **pas** de pod : rien à chercher dans Kubernetes. La page du job affiche un message du type « This job is stuck because you don't have any active runners online or available with any of these tags assigned to them: k8s ».

**Étape 2 — Les runners.**

```
admin@adm01:~$ gl "runners/all?type=instance_type&per_page=100" | jq -r '.[] | [.id, .description, .status, .paused] | @tsv'
3   runner02-docker    online   false
11  k8s-par1           online   false
12  k8s-par1-protege   online   false
admin@adm01:~$ gl runners/11 | jq '{tag_list, run_untagged, access_level, maintenance_note, contacted_at}'
```

**Variante 1 — étiquettes « harmonisées ».**

```
{
  "tag_list": ["k8s-par1", "kubernetes"],
  "run_untagged": false,
  "access_level": "not_protected",
  "maintenance_note": "Lucas (stage) : étiquettes harmonisées avec le nom du cluster (M19-E35)",
  …
}
```

Le runner est en ligne, il interroge GitLab en continu (*long polling*, `check_interval`)… et ne reçoit rien : aucun job ne demande `k8s-par1`, et plus aucun runner ne porte `k8s`. Un job est attribué à un runner qui porte **toutes** ses étiquettes. Correctif : remettre `k8s,kubernetes`. Où ? Depuis 16.x, les étiquettes d'un runner créé par jeton `glrt-` sont des **attributs du runner dans GitLab** (posés à la création par `POST /user/runners`, modifiables dans l'interface ou par `PUT /runners/:id`), et non plus des options de `register` : c'est donc une source de vérité **hors Git**. MédiSphère les trace dans le code qui crée le runner (le script de M19-E04 qui appelle l'API, rejoué à l'identique) et les contrôle (check du module, puis alerte au M21).

```
admin@adm01:~$ gl runners/11 -X PUT --data-urlencode 'tag_list=k8s,kubernetes' --data-urlencode 'maintenance_note=' | jq .tag_list
```

**Variante 2 — runner suspendu.** `"paused": true` et la note « pause pendant la maintenance de k8s-w02 ». Le gestionnaire continue à interroger GitLab (statut `online`), GitLab ne lui donne rien. Correctif : `--data-urlencode paused=false`, effacer la note. Prévention : une pause se pose avec une échéance (dans la note et dans le ticket de changement) et le contrôle quotidien signale tout runner suspendu depuis plus de 4 h.

**Variante 3 — quota en Mi.** Le job est `running` puis échoue :

```
Preparing the "kubernetes" executor
Using Kubernetes namespace: ci-jobs
…
ERROR: Job failed (system failure): prepare environment: setting up build pod: pods "runner-…-project-58-concurrent-0-…" is forbidden: exceeded quota: quota-ci, requested: limits.memory=…,requests.memory=…, used: limits.memory=0,requests.memory=0, limited: limits.memory=24Mi,requests.memory=12Mi
admin@adm01:~$ kubectl -n ci-jobs describe resourcequota
Name:            quota-ci
Resource         Used  Hard
--------         ----  ----
limits.memory    0     24Mi
requests.memory  0     12Mi
…
admin@adm01:~$ kubectl -n ci-jobs get resourcequota quota-ci -o jsonpath='{.metadata.annotations}'
{"medisphere.internal/modifie-par":"lucas.martin"}
```

Un refus de quota n'apparaît jamais comme un pod `Pending` : l'API refuse de **créer** l'objet. Si ton gabarit contient `[runners.kubernetes.retry_limits] "exceeded quota" = N`, le runner réessaie et le job reste `running` plus longtemps avant d'échouer : c'est voulu pour un quota **temporairement** plein (charge), pas pour un quota faux. Correctif : rétablir les valeurs du code (`plateforme/k8s/espaces/ci-jobs/…`, appliqué par `task appliquer`), après avoir vérifié avec `kubectl diff -f` que la seule différence est celle-là.

**Variante 4 — runner protégé et branche non protégée.**

```
admin@adm01:~$ gl "projects/$P/jobs?scope[]=pending" | jq -r '.[] | [.id, .name, .ref, (.tag_list|join(","))] | @tsv'
4830   signer-essai   lucas/essai-signature   protege
admin@adm01:~$ gl runners/12 | jq '{tag_list, access_level}'
{ "tag_list": ["protege"], "access_level": "ref_protected" }
admin@adm01:~$ gl "projects/$P/protected_branches" | jq -r '.[].name'
main
```

Le seul runner qui porte `protege` est en `ref_protected` : il ne prend que les jobs des branches et étiquettes protégées, et c'est **voulu** (M19-E24 : lui seul reçoit la clé Cosign et `DEPLOIEMENT_TOKEN`). Le job attend indéfiniment. Il n'y a rien à « réparer » côté plateforme : la réponse à Lucas est l'explication, et le correctif est sur sa branche (essayer la signature sur une référence protégée prévue pour cela, ou retirer `protege` et signer avec une clé d'essai sur le runner `k8s`). Ce qu'il ne faut **pas** faire : protéger `lucas/*` (la branche obtiendrait les secrets de signature), ou passer le runner protégé en `not_protected`. Supprime la branche (ou laisse Lucas la supprimer) : le contrôle exige qu'aucun job n'attende plus de 10 minutes.

**Vérification** : un pipeline du canari (`gl "projects/$P/pipeline?ref=main" -X POST`) réussit sur `k8s-par1` ; `lab/bin/check 19 35`, puis `lab/bin/break 19 35 --annuler`.

**Explications** : GitLab n'« envoie » rien aux runners ; chaque gestionnaire demande un job (`POST /api/v4/jobs/request`, toutes les `check_interval` secondes, ou en *long polling* maintenu par Workhorse si `api_ci_long_polling_duration` est posé dans `gitlab.rb`) en présentant son jeton ; GitLab choisit dans la file le premier job compatible (étiquettes, protection, pause, accès du projet). Un runner peut donc être `online` (il a contacté GitLab récemment) et ne jamais recevoir de job. Le statut `online` ne dit **rien** de sa capacité à prendre un job donné.

**Alternatives** : pour « voir » ce que demande un job sans le lancer, l'API `ci/lint` donne les étiquettes résolues ; pour les runners, une vue « runners × étiquettes » générée chaque jour (script de `plateforme/outils`) rend visible un changement d'étiquettes.

**Pièges classiques**
- Redémarrer le gestionnaire : il revient `online`, rien ne change, et on a perdu ses journaux.
- Ajouter `run_untagged: true` « pour débloquer » : tous les jobs sans étiquette du lab arrivent dans `ci-jobs`, y compris ceux prévus pour `runner02`.
- Chercher un pod `Pending` pour un refus de quota.

**En production chez MédiSphère** : alerte sur l'âge du plus vieux job en attente par étiquette (métriques de GitLab, M21) ; tout changement d'attribut de runner passe par un ticket CHG et par le script versionné ; le runner protégé est documenté dans RB-190 avec la règle « références protégées seulement ».

---

### M19-E36 — Panne : le job échoue avant le script

**Démarche de diagnostic**

*Symptômes* : variantes 1, 3, 4 : le job échoue en quelques secondes avec `ERROR: Job failed (system failure)` (ou `prepare environment`), sans aucune ligne du script ; variante 2 : plus aucun job pris, pods du gestionnaire qui redémarrent.

*Hypothèses* : image (job, *helper*, service) introuvable ou refusée ; pod refusé par l'API (compte de service, admission, quota) ; gestionnaire incapable de parler à GitLab (certificats, jeton) ; configuration du runner invalide.

**Étape 1 — Le journal du job, depuis le haut.**

```
Running with gitlab-runner 19.5.x (…)
  on k8s-par1 …
Preparing the "kubernetes" executor
Using Kubernetes namespace: ci-jobs
Using Kubernetes executor with image registry.par1.medisphere.internal/dockerhub/library/python:3.13-slim-trixie …
Using attach strategy to execute scripts...
Preparing environment
Waiting for pod ci-jobs/runner-…-project-58-concurrent-0-… to be running, status is Pending
…
ERROR: Job failed (system failure): prepare environment: …
```

La dernière ligne avant `ERROR` dit l'étape. Rien après `Preparing environment` : on n'est jamais arrivé à `Getting source from Git repository`.

**Étape 2 — Le message source.**

```
admin@adm01:~$ kubectl -n ci-jobs get events --sort-by=.lastTimestamp | tail -n 15
admin@adm01:~$ kubectl -n gitlab-runner get pods
admin@adm01:~$ kubectl -n gitlab-runner logs deploy/<gestionnaire> --tail=50
```

**Variante 1 — image *helper* introuvable.**

```
Warning  Failed   pod/runner-…   Failed to pull image "registry.par1.medisphere.internal/gitlab-registry/gitlab-org/gitlab-runner/gitlab-runner-helper:x86_64-v19.5.0": … not found
ERROR: Job failed (system failure): prepare environment: waiting for pod running: pulling image "registry.par1.medisphere.internal/gitlab-registry/…": image pull failed: …
admin@adm01:~$ kubectl -n gitlab-runner get configmap <cm> -o jsonpath='{.data.config\.template\.toml}' | grep helper_image
    helper_image = "registry.par1.medisphere.internal/gitlab-registry/gitlab-org/gitlab-runner/gitlab-runner-helper:…"
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=gitlab-runner diff | grep -n helper_image
-    helper_image = "registry.par1.medisphere.internal/gitlab-registry/…"
+    helper_image = "registry.par1.medisphere.internal/gitlab/…"
```

Le cache Harbor s'appelle `gitlab` (M19-E04, état OpenTofu `registre`) ; Harbor ne sait pas renommer un projet, et le gabarit du cluster pointe vers un projet qui n'existe pas. C'est une **dérive** : le code est juste, le cluster ne l'est plus. Correctif : `helmfile -e par1 -l composant=gitlab-runner apply` (le Deployment redémarre grâce à l'annotation `checksum/configmap` du chart). Prévention : `helmfile diff` dans le pipeline planifié de `plateforme/k8s` (dérive signalée chaque nuit).

**Variante 2 — Secret des certificats vide.**

```
admin@adm01:~$ kubectl -n gitlab-runner get pods
NAME                          READY   STATUS             RESTARTS      AGE
gitlab-runner-…-7x2kq         0/1     CrashLoopBackOff   4 (30s ago)   6m
gitlab-runner-…-p9d4m         0/1     CrashLoopBackOff   4 (41s ago)   6m
admin@adm01:~$ kubectl -n gitlab-runner logs <pod> --previous | tail -n 4
Registration attempt 30 of 30
ERROR: Verifying runner... failed  runner=… status=couldn't execute POST against https://git01.par1.medisphere.internal/api/v4/runners/verify: … tls: failed to verify certificate: x509: certificate signed by unknown authority
admin@adm01:~$ kubectl -n gitlab-runner get secret <certs> -o json | jq '{annotations: .metadata.annotations, tailles: (.data | map_values(length))}'
{ "annotations": {"medisphere.internal/restaure-depuis": "sauvegarde-vide-lucas"}, "tailles": {"git01.par1.medisphere.internal.crt": 0} }
```

Le chart monte le Secret `certsSecretName` dans `/home/gitlab-runner/.gitlab-runner/certs/` ; le runner y lit la chaîne de confiance de `git01` (fichier nommé d'après le nom d'hôte). Vide, la racine MédiSphère manque : l'enregistrement par jeton `glrt-` (revérifié à chaque démarrage par `register-the-runner`) échoue, le conteneur sort, redémarre. Les pods qui tournaient avant n'avaient rien vu (le fichier est lu au démarrage) : la panne ne se révèle qu'au premier redémarrage, ici celui de la nuit. C'est pour cela qu'un Secret « nettoyé » en journée peut casser la CI le lendemain. Correctif par le code : `outils/secrets-k8s.sh appliquer gitlab-runner` (qui reconstruit le Secret depuis Vault `secrets/gitlab-runner.yml`), puis suppression des pods en échec. Vérifie avant que le contenu de Vault est le bon (`openssl x509 -noout -subject -issuer` sur la racine).

**Variante 3 — compte de service absent.**

```
ERROR: Job failed (system failure): prepare environment: setting up build pod: pods "runner-…" is forbidden: error looking up service account ci-jobs/ci-job: serviceaccount "ci-job" not found
```

L'admission `ServiceAccount` refuse un pod qui désigne un compte inexistant. Correctif : réappliquer `plateforme/k8s/espaces/ci-jobs/` (le compte y est décrit, avec `automountServiceAccountToken: false`) ; `kubectl get sa -n ci-jobs ci-job -o yaml` pour vérifier. Retrouver qui l'a supprimé : journal d'audit de l'API (M14-E27), filtre `.objectRef.resource == "serviceaccounts" and .verb == "delete"`.

**Variante 4 — image hors de Harbor, refusée avant même le pod.**

```
ERROR: The "docker.io/library/python:3.13-slim-trixie" image is not present on list of allowed images:
- registry.par1.medisphere.internal/**
Please check runner's allowed_images configuration: …
ERROR: Job failed (system failure): prepare environment: … disallowed image
admin@adm01:~$ git -C ~/src/ci-pannes log --format='%h %an %s' -3 -- .gitlab-ci.yml
a41c9e2 Lucas Martin ci: image Python officielle pour le canari, plus simple (M19-E36)
```

Deux barrières se suivent. La première est celle du **runner** : `allowed_images` (M19-E04, E24) n'admet que `registry.par1.medisphere.internal/**` (motifs `doublestar`) ; le gestionnaire refuse le job **avant** de créer le pod, d'où l'absence d'événement dans `ci-jobs`. La seconde, si la première manquait (runner mal configuré), est l'**admission** : la politique `medisphere-images` (M14-E18) refuserait le pod (`ValidatingAdmissionPolicy 'medisphere-images' … denied request`). `docker.io/library/python` aurait été tirée par le cache de toute façon (miroir `hosts.toml`), mais runner et admission jugent la **référence** écrite, pas le chemin réel du tirage : c'est voulu (on veut voir partout d'où vient l'image). Correctif : revert du commit de Lucas (MR) ; réponse à Lucas : la bonne référence est `registry.par1.medisphere.internal/dockerhub/library/python:…`. Vérifie au passage que `ci-jobs` est bien couvert par la politique (étiquette `medisphere.internal/equipe` de l'espace) : sinon, c'est une exception à justifier dans l'ADR-0190 ou à corriger.

**RB-195 — modèle** : [`fichiers/M19-E36/medisphere/docs/livraison/ci/runbooks/RB-195-job-echoue-ou-tue.md`](fichiers/M19-E36/medisphere/docs/livraison/ci/runbooks/RB-195-job-echoue-ou-tue.md) (sections `Avant le script` et `Job tué`, cette dernière complétée en M19-E42).

**Explications** : avant le script, l'exécuteur Kubernetes enchaîne : lecture de la configuration (au démarrage du gestionnaire), demande du job, construction de la spécification du pod (images, ressources, compte de service, volumes, sécurité), création par l'API (authentification du gestionnaire, autorisation, admission : `ServiceAccount`, LimitRange, ResourceQuota, Pod Security, VAP), ordonnancement, tirage des images (*helper* et build en premier), démarrage, attachement. Chaque refus remonte dans le journal du job sous la forme `prepare environment: …`, souvent tronqué : l'événement Kubernetes ou le journal du gestionnaire donne la phrase complète.

**Alternatives** : l'option `print_pod_warning_events` de `[runners.kubernetes]` (activée par défaut en 19.x ; l'ancien drapeau `FF_RETRIEVE_POD_WARNING_EVENTS` n'existe plus) recopie les événements d'avertissement du pod dans le journal du job, au démarrage et après un échec ; elle exige le droit `events: list` du gestionnaire dans `ci-jobs` (Role de E24). Utile pour les équipes qui n'ont pas accès à `ci-jobs`.

**Pièges classiques**
- Corriger la ConfigMap à la main (`kubectl edit`) : le gestionnaire ne relit pas le gabarit sans redémarrage, et le prochain `helmfile apply` écrase la correction si les values ne sont pas justes.
- Recréer le compte de service à la main **avec** jeton monté (le défaut) : les pods de job auraient de nouveau un jeton d'API.
- Croire que « l'image est dans le cache donc l'admission devrait passer ».

**En production chez MédiSphère** : `helmfile diff` nocturne sur `plateforme/k8s` (dérive), alerte sur les redémarrages du gestionnaire (M21), Secrets toujours reconstruits depuis Vault, jamais édités.

---

### M19-E37 — Panne : la construction d'image échoue

**Démarche de diagnostic**

*Symptômes* : le job de construction de `mediagenda/api` échoue ; les autres jobs passent.

*Hypothèses* par maillon : TLS mutuel (certificat client, CA, nom du serveur), réseau (politique Cilium, Service), registre (identifiants, droits, robot), démon (stockage, mémoire, redémarrage).

**Étape 1 — Lire l'erreur de `buildctl`.** Relance le pipeline de `main` et lis le job de construction :

| Message (représentatif) | Maillon |
|---|---|
| `remote error: tls: bad certificate`, `tls: unknown certificate authority`, `certificate signed by unknown authority` | TLS mutuel (variante 1) |
| `context deadline exceeded`, `connection timed out` vers `buildkitd.buildkit:1234` | réseau (variante 2) |
| `401 Unauthorized` / `unauthorized: …` sur `plateforme/cache-buildkit` à l'export du cache | registre, robot (variante 3) |
| `no space left on device` (export, décompression des couches) | stockage du démon (variante 4) |

**Étape 2 — Reproduire hors pipeline**, avec un pod jetable qui respecte le profil `restricted` de `ci-jobs` et monte le Secret client (fichier d'exemple : [`fichiers/M19-E37/essais/sonde-buildctl.yaml`](fichiers/M19-E37/essais/sonde-buildctl.yaml), qui monte le Secret `buildkit-client` de M19-E08) :

```
admin@adm01:~$ kubectl -n ci-jobs apply -f sonde-buildctl.yaml
admin@adm01:~$ kubectl -n ci-jobs logs -f sonde-buildctl
ID                              PLATFORMS
k3v…                            linux/amd64,linux/amd64/v2,linux/amd64/v3,linux/386
admin@adm01:~$ kubectl -n ci-jobs delete pod sonde-buildctl
```

**Variante 1 — certificat client réémis par une autre autorité.**

```
admin@adm01:~$ kubectl get certificates -A -o custom-columns=NS:.metadata.namespace,NOM:.metadata.name,TYPE:.spec.issuerRef.kind,EMETTEUR:.spec.issuerRef.name,PRET:.status.conditions[0].status
NS         NOM                     TYPE            EMETTEUR                 PRET
cert-manager buildkit-ca           ClusterIssuer   buildkit-amorce          True
buildkit   buildkitd-serveur       ClusterIssuer   buildkit-ca              True
ci-jobs    buildkit-client         Issuer          buildkit-ca-2026         True
ci-jobs    buildkit-ca-2026        Issuer          buildkit-ca-2026-racine  True
admin@adm01:~$ kubectl -n ci-jobs get secret buildkit-client -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -issuer -dates
issuer=CN = buildkit-ca-2026
```

Tout est « vert » pour cert-manager : le certificat est valide… mais signé par une autorité que `buildkitd` ne connaît pas (il n'accepte que les clients signés par `buildkit-ca`). La poignée de main TLS échoue côté serveur. Correctif : le `Certificate` `buildkit-client` est rendu par le chart local `charts/buildkitd` (M19-E08 : `issuerRef` de type **ClusterIssuer** `buildkit-ca`, autorité amorcée par la ClusterIssuer `buildkit-amorce`) ; on le rend au code par `helmfile -e par1 -l composant=buildkitd diff` puis `apply` (le diff montre l'`issuerRef` modifié à la main), on laisse cert-manager réémettre (`cmctl renew -n ci-jobs buildkit-client` pour accélérer), retirer les objets parasites (`buildkit-ca-2026*`). Les jobs suivants montent le nouveau Secret.

**Variante 2 — refus explicite dans Cilium.**

```
admin@adm01:~$ kubectl -n buildkit get ciliumnetworkpolicies
NAME                     AGE   VALID
buildkitd                9d    True
buildkitd-durcissement   1h    True
admin@adm01:~$ hubble observe --namespace buildkit --verdict DROPPED --last 5
… ci-jobs/sonde-buildctl:41822 (ID:…) <> buildkit/buildkitd-…:1234 (ID:…) Policy denied by denylist DROPPED (TCP Flags: SYN)
```

Une règle `ingressDeny` l'emporte sur **toutes** les autorisations, y compris celle du M19-E08 qui ouvre justement ce flux. Correctif : retirer la politique, et la proposition de Lucas passe en revue : s'il voulait « durcir », la bonne demande est de restreindre la politique d'autorisation (sélecteur d'espace et port), pas d'empiler un refus contradictoire. Prévention : les politiques de `buildkit` ne vivent que dans `plateforme/k8s` (une politique hors du code est une dérive détectable par `kubectl diff`).

**Variante 3 — robot du cache désactivé.**

```
error: failed to solve: failed to push registry.par1.medisphere.internal/plateforme/cache-buildkit:mediagenda-api: unexpected status from PUT request to …: 401 Unauthorized
admin@adm01:~$ set -a; . ~/.config/workbook/harbor-moi.env; set +a
admin@adm01:~$ curl -sS -K <(printf 'user = "%s:%s"\n' "$HARBOR_USER" "$HARBOR_PASSWORD") "https://registry.par1.medisphere.internal/api/v2.0/robots?page_size=100" \
    | jq -r '.[] | [.id, .name, .disable, (.expires_at|tostring), .description] | @tsv' | grep -i cache
14  robot$plateforme+cache-buildkit  true  -1  … [désactivé par Lucas, M19-E37]
```

Le cache de construction est poussé par le **client** (le job, avec ses identifiants), pas par le démon : un robot désactivé fait échouer l'export du cache, donc la construction (sauf `ignore-error=true` sur `--export-cache`, à discuter). Correctif : réactiver le robot **par l'état OpenTofu `registre`** si le robot y est décrit (`disable = false`, `tofu apply`), sinon par l'interface puis report dans le code. Profite de l'incident pour vérifier la date d'expiration du robot et la présence de son secret dans Vault.

**Variante 4 — volume du démon plein.**

```
error: failed to solve: … write /home/user/.local/share/buildkit/runc-native/snapshots/…: no space left on device
admin@adm01:~$ kubectl -n buildkit exec deploy/buildkitd -- df -h /home/user/.local/share/buildkit
Filesystem      Size  Used Avail Use% Mounted on
/dev/rbd1        20G   20G   20M 100% /home/user/.local/share/buildkit
admin@adm01:~$ kubectl -n buildkit exec deploy/buildkitd -- sh -c 'du -sh /home/user/.local/share/buildkit/* | sort -h | tail -n 3'
1.2G  /home/user/.local/share/buildkit/runc-native
18.6G /home/user/.local/share/buildkit/wb-remplissage-M19-E37
```

Le chemin exact dépend de ton chart (`--root` du démon). Ce qui occupe la place n'est pas du cache : un fichier posé à la main. On le retire, en notant ce que c'est ; le cache, lui, se gère par `buildctl prune` (avec `--keep-storage`) et par la politique de ramasse-miettes du démon (`buildkitd.toml`). Si c'était du cache : `buildctl … prune --keep-storage 10GB` depuis un pod client, jamais `rm -rf` dans le dossier du démon (il perdrait son état et refuserait de redémarrer).

**Fichiers** : [`fichiers/M19-E37/medisphere/docs/livraison/ci/runbooks/RB-196-construction-et-cache.md`](fichiers/M19-E37/medisphere/docs/livraison/ci/runbooks/RB-196-construction-et-cache.md) (sections `buildkitd` et `Cache`, complétée en M19-E38).

**Explications** : la construction distante sépare trois identités : le **client** (pod de job, certificat client pour le démon, identifiants de registre pour pousser), le **démon** (certificat serveur, aucun identifiant de registre), le **registre** (Harbor). Les identifiants de registre voyagent du client vers le démon par la session BuildKit, à la demande : c'est pourquoi un robot désactivé échoue « dans le démon » alors qu'il appartient au job.

**Alternatives** : `--export-cache …,ignore-error=true` rend le cache facultatif (la construction réussit sans cache) ; c'est défendable pour le cache, pas pour la poussée de l'image.

**Pièges classiques**
- « Réparer » en passant `buildkitd` en privilégié ou en désactivant TLS : interdit par l'ADR-0120 et l'ADR-0190.
- Supprimer le dossier de données du démon pour « faire de la place ».
- Oublier que cert-manager dit `Ready` pour un certificat **valide** qui n'est pas celui que le serveur attend.

**En production chez MédiSphère** : supervision du volume du démon et de ses certificats (M21), sonde de disponibilité qui interroge le démon, robots de CI décrits par OpenTofu avec expiration et rotation (RB-131 du M13).

---

### M19-E38 — Panne : le cache ne sert plus

**Démarche de diagnostic**

*Symptômes* : jobs verts mais lents ; `CANARI cache restauré : non` à chaque pipeline.

**Étape 1 — Deux journaux successifs du canari, côte à côte.**

```
Restoring cache
Checking cache for 1-a3f1…-non_protected…              ← clé
WARNING: Retrying...  error=… 403 Forbidden              ← variante 1
Failed to extract cache
…
Saving cache for successful job
Creating cache 1-a3f1…...
.cache/canari/: found 2 matching artifact files and directories
WARNING: Retrying... error=… 403 Forbidden
Failed to create cache
```

Trois familles de lignes à repérer : la **clé** (`Checking cache for …`, `Creating cache …`), ce qui est **archivé** (`found N matching …`, ou `no matching files`), le **transport** (`Uploading cache.zip to …`, `Downloading cache from …`, `WARNING: Retrying…`, `403`, `404`).

**Variante 1 — identité S3 sans droits.** Lignes `403 Forbidden` au téléchargement et au téléversement. Les URL sont **présignées par le gestionnaire** avec l'identité `ci-cache` : le *helper* ne fait que les suivre. Preuve directe depuis `adm01` :

```
admin@adm01:~$ set -a; . ~/.config/workbook/s3-ci-cache.env; set +a
admin@adm01:~$ aws --endpoint-url https://s3-01.par1.medisphere.internal:8333 s3 ls s3://ci-cache/ | head -n 3
An error occurred (AccessDenied) when calling the ListObjectsV2 operation: Access Denied
admin@s3-01:~$ sudo jq '.identities[] | select(.name == "ci-cache") | .actions' <FICHIER-IDENTITÉS>
[]
```

`<FICHIER-IDENTITÉS>` est le fichier passé à `-s3.config` du processus `weed` (M05-E10). Correctif : rejouer le rôle Ansible `seaweedfs` (le gabarit `s3.json.j2` contient les droits de `ci-cache`, posés en M19-E07), qui restaure le fichier et redémarre la passerelle. La modification à la main du fichier sur `s3-01` est la dérive à expliquer.

**Variante 2 — compartiment renommé dans le gabarit.**

```
WARNING: Retrying... error=… 404 Not Found … NoSuchBucket
admin@adm01:~$ kubectl -n gitlab-runner get cm <cm> -o jsonpath='{.data.config\.template\.toml}' | grep -A6 'runners.cache.s3'
      BucketName = "ci-caches"
```

Correctif : `helmfile … apply` (le code dit `ci-cache`). Ne crée **pas** un compartiment `ci-caches` « pour que ça marche » : on aurait deux caches, des droits à dupliquer, et la dérive resterait.

**Variante 3 — clé par pipeline.**

```
Checking cache for canari-48231-…
…                                   (pipeline suivant)
Checking cache for canari-48236-…
admin@adm01:~/src/ci-pannes$ git diff 1.0.0 1.1.0 -- templates/canari/template.yml
-    key:
-      files:
-        - $[[ inputs.fichier_verrou ]]
+    key: canari-$CI_PIPELINE_ID
```

Le transport fonctionne, l'archive est créée… sous une clé que personne ne redemandera jamais. Le cache se remplit d'archives mortes (attention à `s3-01` : prévois une règle de cycle de vie sur `ci-cache` dans le rôle). Correctif : publier `1.2.0` (clé par fichier de verrou, plus éventuellement `fallback_keys`) ou revenir à `1.0.0` dans `.gitlab-ci.yml` ; jamais déplacer l'étiquette `1.1.0`. Réponse à Lucas : la crainte des « caches périmés » se traite par `key:files` (la clé change quand le verrou change), pas par une clé qui change toujours.

**Variante 4 — chemins hors du projet.**

```
Saving cache for successful job
Creating cache 1-a3f1…...
WARNING: /tmp/cache-canari/: no matching files. Ensure that the artifact path is relative to the working directory (/builds/formation/ci-pannes)
Archive is up to date!
```

Le runner n'archive que des chemins **sous** `$CI_PROJECT_DIR`. Correctif : nouvelle version du composant avec `.cache/canari/`. Pour les outils qui écrivent dans `$HOME` (pip, npm, Go), on redirige leur cache dans le projet (`PIP_CACHE_DIR: $CI_PROJECT_DIR/.cache/pip`), on ne cache pas `$HOME`.

**Explications** : avec un cache distribué S3, le gestionnaire calcule pour chaque job une URL présignée de lecture et une d'écriture (clé, préfixe du projet, protection de la référence), les passe au *helper*, qui télécharge `cache.zip`, l'extrait, puis, à la fin, archive les chemins et téléverse. Aucun échec de cache ne fait échouer un job (sauf `cache:policy` et options particulières) : c'est une **optimisation**, et sa panne est silencieuse. D'où l'indicateur explicite du canari.

**Alternatives** : `cache:fallback_keys` pour réutiliser le cache de la branche principale ; `cache:unprotect` (à éviter : le cache des références protégées est séparé de celui des branches quelconques précisément pour qu'une branche ne puisse pas empoisonner le cache d'une construction de production).

**Pièges classiques**
- Ne lire que le statut vert du job.
- Comparer les clés sans voir le suffixe `-protected` / `-non_protected` (les caches des références protégées et non protégées sont séparés).
- Corriger le composant en déplaçant une étiquette : tous les projets qui l'ont épinglée changent de comportement sans le savoir.

**En production chez MédiSphère** : indicateur « taux de cache restauré » calculé sur les journaux du canari (M22) ; règle de cycle de vie sur `ci-cache` ; tests des composants dans `plateforme/ci-templates` (un pipeline qui consomme deux fois le composant et vérifie le cache).

---

### M19-E39 — Panne : le déploiement en dev est refusé

**Démarche de diagnostic**

*Symptômes* : `deployer-dev` échoue ; rien n'arrive dans `mediagenda-dev`.

**Étape 1 — L'erreur du job, et son étage.**

| Erreur (représentative) | Étage |
|---|---|
| `error: no context exists with the name: "plateforme/k8s:k8s-par1"` | autorisation GitLab (`ci_access`) : GitLab n'a pas injecté le contexte (variante 3) |
| `Unable to connect to the server: … agent … not connected` / délai | connexion `agentk` ↔ KAS (variantes 1 et 4) |
| `Error from server (Forbidden): … User "system:serviceaccount:gitlab-agent:…" cannot patch resource "deployments" … in the namespace "mediagenda-dev"` | RBAC du compte de service de l'agent (variante 2) |

Dans le job, `kubectl config get-contexts` dit ce que GitLab a fourni ; le reste se lit dans le cluster et dans GitLab.

**Étape 2 — L'agent.**

```
admin@adm01:~$ kubectl -n gitlab-agent get pods
admin@adm01:~$ kubectl -n gitlab-agent logs deploy/<agent> --tail=30
admin@adm01:~$ kubectl -n gitlab-agent get deploy <agent> -o jsonpath='{.spec.template.spec.containers[0].args}'; echo
admin@adm01:~$ AK=$(jq -rn --arg s plateforme/k8s '$s|@uri')
admin@adm01:~$ gl "projects/$AK/cluster_agents" | jq '.[] | {id, name}'
admin@adm01:~$ gl "projects/$AK/cluster_agents/<id>/tokens" | jq '.[] | {id, name, status, last_used_at, created_at}'
```

**Variante 1 — jeton révoqué dans le Secret.**

```
{"level":"error","msg":"…","error":"rpc error: code = Unauthenticated desc = unauthenticated"}
admin@adm01:~$ gl "projects/$AK/cluster_agents/<id>/tokens" | jq -r '.[] | [.id, .name, .status, .last_used_at] | @tsv'
21   k8s-par1-initial   active    2026-10-29T06:12:44Z       ← plus utilisé depuis l'incident
admin@adm01:~$ gl "projects/$AK/cluster_agents/<id>/tokens/34"     ← le jeton « rotation-lucas » : révoqué
```

Le Secret contient le jeton « rotation-lucas » (créé puis révoqué) ; le bon jeton est toujours actif dans GitLab et dans Vault. Correctif : `outils/secrets-k8s.sh appliquer gitlab-agent` (reconstruit le Secret depuis `secrets/gitlab-agent.yml`), puis redémarrage des pods de l'agent. Si tu doutes de l'intégrité du jeton de Vault (a-t-il pu être exposé ?), fais une vraie rotation : nouveau jeton par l'API, Vault, `secrets-k8s.sh`, contrôle de connexion, **puis** révocation de l'ancien (un agent accepte deux jetons actifs, ce qui permet de tourner sans coupure).

**Variante 2 — RoleBinding supprimé.** `kubectl auth can-i patch deployments -n mediagenda-dev --as=system:serviceaccount:gitlab-agent:<sa>` répond `no`. Le RoleBinding est décrit dans `plateforme/k8s` (M19-E18) : `task appliquer`. Le journal d'audit dit qui l'a supprimé.

**Variante 3 — `ci_access` retiré.**

```
admin@adm01:~/src/k8s$ git log --format='%h %an %s' -3 -- .gitlab/agents/k8s-par1/config.yaml
7c1e0aa <MOI> Merge branch 'lucas/agent-ci-access' into 'main'
19b2f3d Lucas Martin fix(agent): ci_access limité aux projets qui en ont besoin (M19-E39)
admin@adm01:~/src/k8s$ git show 19b2f3d
```

La MR a été fusionnée (par toi, dans le lab : le script agit avec ton jeton). Correctif : MR de retour arrière (`git revert`), relue ; l'agent relit sa configuration depuis le dépôt en moins d'une minute. Prévention : `CODEOWNERS` sur `.gitlab/agents/` (fonction Free : la protection de branche peut exiger l'approbation des *code owners* seulement en Premium ; en Free, CODEOWNERS sert au moins à désigner les relecteurs, et la règle est écrite dans l'ADR).

**Variante 4 — `--kas-address` faux.**

```
{"level":"error","msg":"Error handling a connection", … "dial tcp: lookup gitlab.par1.medisphere.internal … no such host"}
```

Modification à chaud du Deployment : `helmfile -e par1 -l composant=gitlab-agent diff` la montre et `apply` la défait. Rappel du M19-E26 : en 19.5 l'adresse peut être en `grpcs://` ; vérifie que tes values sont cohérentes avec la version de l'agent.

**Fichiers** : [`fichiers/M19-E39/medisphere/docs/livraison/ci/runbooks/RB-197-deploiement-agent.md`](fichiers/M19-E39/medisphere/docs/livraison/ci/runbooks/RB-197-deploiement-agent.md).

**Explications** : dans le *CI/CD workflow*, GitLab injecte dans chaque job autorisé par `ci_access` un kubeconfig (`KUBECONFIG`) dont les contextes `<projet de l'agent>:<agent>` passent par KAS ; KAS relaie chaque requête à `agentk` par la connexion que celui-ci a ouverte (sortante, authentifiée par son jeton) ; `agentk` appelle l'API Kubernetes **avec son propre compte de service** (sans usurpation d'identité en Free). Trois autorisations successives : GitLab (`ci_access`), connexion (`agentk` authentifié), Kubernetes (RBAC du compte de l'agent).

**Pièges classiques**
- Donner `cluster-admin` à l'agent « le temps de débloquer ».
- Révoquer l'ancien jeton avant d'avoir vérifié que le nouveau est en place.
- Corriger le Deployment à la main et oublier les values.

**En production chez MédiSphère** : alerte si l'agent n'est plus connecté (métriques de `agentk`, M21) ; rotation planifiée du jeton (RB-197) ; au M20, plus aucun accès CI aux espaces applicatifs : Argo CD prend le relais.

---

### M19-E40 — Panne : un secret apparaît dans un journal de job

**Démarche de diagnostic**

*Symptômes* : la valeur de `CANARI_JETON` (variante 1) ou une valeur dérivée (variantes 2 et 3 : `CANARI_AUTH=Y2FuYXJpOmds…`) apparaît dans le journal du canari.

**Étape 1 — Confiner : trouver toutes les expositions.** Sans afficher la valeur, on cherche ses formes dans les journaux récents :

```
admin@adm01:~$ read -rs V < <(gl "projects/$P/variables/CANARI_JETON" | jq -r .value)
admin@adm01:~$ B=$(printf 'canari:%s' "$V" | base64 | tr -d '\n')
admin@adm01:~$ for j in $(gl "projects/$P/jobs?per_page=50" | jq -r '.[].id'); do
>   gl "projects/$P/jobs/$j/trace" | grep -qF -e "$V" -e "$B" && echo "exposé : job $j"
> done; unset V B
exposé : job 4911
exposé : job 4913
```

Note les identifiants (jamais la valeur) dans le journal de diagnostic. Pense aussi aux artefacts (un job qui écrit son environnement dans un fichier) et aux pipelines planifiés de la nuit.

**Étape 2 — Ce qui a contourné le masquage.**

```
admin@adm01:~$ gl "projects/$P/variables/CANARI_JETON" | jq '{masked, hidden, protected, description}'
admin@adm01:~$ gl "projects/$P/variables?per_page=100" | jq -r '.[].key'
admin@adm01:~$ gl "groups/formation/variables?per_page=100" | jq -r '.[].key'
admin@adm01:~$ git -C ~/src/ci-pannes diff 1.0.0 "$(git -C ~/src/ci-pannes describe --tags --abbrev=0)" -- templates/
```

- **Variante 1** : `"masked": false`, description « démasquée pour vérifier la valeur ». La ligne `env | grep "^CANARI_"` du job (débogage laissé par l'équipe, pas fautif tant que le masquage tient) affiche la valeur. Leçon : on ne démasque jamais une variable pour la « vérifier » ; on vérifie un effet (le canari accède-t-il au dépôt ?).
- **Variante 2** : la version `1.x.0` ajoute `before_script: [set -x]`. La trace du shell affiche les **affectations après expansion** : `+ CANARI_AUTH=Y2FuYXJpOmdscGF0LT…` ; le masquage ne remplace que la valeur exacte, pas son encodage base64 (et pas non plus une valeur coupée en deux, ou passée par `tr`, `rev`…).
- **Variante 3** : variable `CI_DEBUG_TRACE=true` au niveau du projet. La trace de débogage du runner affiche chaque commande exécutée avec ses expansions, plus l'environnement : même fuite que la variante 2, sur **tous** les jobs du projet.

**Étape 3 — Remplacer le secret.** Le jeton est compromis : il se remplace, il ne se « remasque » pas.

```
admin@adm01:~$ TID=$(gl "projects/$P/access_tokens?state=active" | jq -r '.[] | select(.name == "canari-lecture") | .id')
admin@adm01:~$ R=$(gl "projects/$P/access_tokens/$TID/rotate" -X POST --data-urlencode "expires_at=$(date -d '+90 days' +%F)")
admin@adm01:~$ jq -j .token <<<"$R" | gl "projects/$P/variables/CANARI_JETON" -X PUT --data-urlencode "value@-" \
    --data-urlencode masked=true --data-urlencode protected=true --data-urlencode description= | jq '{masked, protected}'
admin@adm01:~$ unset R
admin@adm01:~$ gl "projects/$P/access_tokens/$TID" | jq '{active, revoked}'
{ "active": false, "revoked": true }
```

La rotation crée un nouveau jeton et révoque l'ancien dans la même opération ; la nouvelle valeur passe par l'entrée standard de `curl` (`value@-`), jamais par ses arguments (visibles dans `ps`). Le script [`fichiers/M19-E40/outils/rotation-canari.sh`](fichiers/M19-E40/outils/rotation-canari.sh) enchaîne rotation, mise à jour de la variable et effacement des journaux, sans jamais afficher la valeur.

**Étape 4 — Effacer les journaux exposés.**

```
admin@adm01:~$ for j in 4911 4913; do gl "projects/$P/jobs/$j/erase" -X POST | jq '{id, erased_at}'; done
```

L'effacement retire journal **et** artefacts ; le job reste listé (traçabilité). Vérifie que `…/trace` est vide.

**Étape 5 — Corriger la cause** : variante 1, remasquer (et passer en « masquée et cachée » si l'équipe n'a jamais besoin de relire la valeur : elle ne pourra plus être démasquée) ; variante 2, publier une version sans `set -x` et y consommer (ou revenir à `1.0.0`) ; variante 3, supprimer `CI_DEBUG_TRACE`. Rejoue le canari : `CANARI_JETON=[MASKED]`.

**Fichiers** : [`fichiers/M19-E40/medisphere/docs/livraison/ci/runbooks/RB-198-fuite-secret-ci.md`](fichiers/M19-E40/medisphere/docs/livraison/ci/runbooks/RB-198-fuite-secret-ci.md).

*Réponse à Sophie (exemple)* : « Cause : [variante]. Exposition : jobs 4911 et 4913 du projet formation/ci-pannes, entre 06:12 et 07:40, journaux lisibles par les membres du projet (8 personnes, `internal` : tout compte connecté). Valeur : jeton de projet en lecture du seul dépôt formation/ci-pannes. Actions : jeton remplacé par rotation à 08:02 (ancien révoqué), journaux et artefacts effacés à 08:05, cause corrigée par la MR !12, canari vérifié à 08:10. Aucune autre exposition trouvée dans les 50 derniers jobs ni dans les artefacts. Prévention : interdiction de `set -x` et de `CI_DEBUG_TRACE` dans les composants (règle Semgrep de `securite`), variables sensibles en « masquée et cachée ». »

**Explications** : le masquage est un **filtre de sortie** du runner (remplacement de chaînes exactes dans le flux du journal), pas une protection du secret dans le job : tout ce que le job peut lire, il peut l'écrire sous une autre forme. Les protections fortes sont ailleurs : variables protégées (le secret n'arrive pas dans les jobs des branches quelconques), jetons à portée minimale et courte durée, `id_tokens` (pas de secret longue durée du tout, M19-E25 et M25).

**Pièges classiques**
- Se contenter de remasquer.
- Coller la valeur dans le ticket ou le journal de diagnostic « pour référence ».
- Oublier les artefacts et les journaux des autres pipelines (planifiés, MR).
- Effacer les journaux avant d'avoir noté les identifiants des jobs (on perd la mesure de l'exposition).

**En production chez MédiSphère** : règle Semgrep (composant `securite`) qui refuse `set -x`, `set -o xtrace` et `CI_DEBUG_TRACE` dans les configurations ; recherche périodique de motifs de jetons dans les journaux récents ; registre des secrets avec propriétaire et procédure de rotation pour chacun.

---

### M19-E41 — Panne : les pipelines ne se déclenchent plus

**Démarche de diagnostic**

*Symptômes* : un commit sur `main` ne crée aucun pipeline (variantes 1 à 3) ; le pipeline planifié n'a pas tourné (variante 4).

**Étape 1 — Prouver l'absence.**

```
admin@adm01:~$ SHA=$(gl "projects/$P/repository/branches/main" | jq -r .commit.id)
admin@adm01:~$ gl "projects/$P/pipelines?sha=$SHA" | jq length
0
admin@adm01:~$ gl "projects/$P/pipelines?source=schedule&per_page=3" | jq -r '.[] | [.id, .created_at] | @tsv'
```

**Étape 2 — Les réglages du projet.**

```
admin@adm01:~$ gl "projects/$P" | jq '{builds_access_level, ci_config_path}'
```

- **Variante 2** : `"ci_config_path": ".gitlab/ci/pipeline.yml"`, fichier inexistant : GitLab ne trouve pas de configuration et ne crée rien, sans erreur. Correctif : remettre la valeur par défaut (vide) ; la pose de ce réglage par Lucas est une demande de changement à refaire proprement (déplacer le fichier **et** changer le réglage dans la même MR, documentée).
- **Variante 3** : `"builds_access_level": "disabled"` : la fonction CI/CD est désactivée (l'onglet disparaît de l'interface). Correctif : `enabled`. Qui l'a fait ? *Audit events* du projet (selon édition et version) ou l'historique de l'équipe : à défaut de trace, c'est la prévention à écrire (droits Maintainer limités).

**Étape 3 — Faire évaluer la configuration sans pousser.**

```
admin@adm01:~$ gl "projects/$P/ci/lint?dry_run=true&dry_run_ref=main&include_jobs=true" | jq '{valid, errors, warnings, jobs: [.jobs[]?.name]}'
admin@adm01:~$ gl "projects/$P/pipeline?ref=main" -X POST | jq '{id, message}'
{ "message": { "base": ["Pipeline filtered out by workflow rules."] } }
```

(`GET …/ci/lint` lit le fichier du dépôt (`content_ref`, par défaut la tête de la branche par défaut) et le simule sur `dry_run_ref` ; `POST …/ci/lint` exige le contenu à valider dans `content`, utile pour essayer une modification avant de la pousser.)

- **Variante 1** : la version `1.x.0` du composant ne garde que `merge_request_event` et `CI_COMMIT_TAG` dans `workflow:rules` : plus de pipeline de branche, donc rien sur `main` (ni pour les pipelines planifiés, qui sont des pipelines de branche). La création manuelle répond « filtered out by workflow rules » : c'est la seule fois où GitLab le dit. Correctif : nouvelle version qui garde les pipelines de branche **et** évite les doublons (la règle du M19-E06 : `$CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS` → `never`), ou retour à `1.0.0`. Leçon pour Lucas : un composant qui porte `workflow` impose sa politique à tous ses consommateurs ; c'est une décision de plateforme, pas une optimisation locale.

**Étape 4 — Variante 4, le propriétaire du pipeline planifié.**

```
admin@adm01:~$ gl "projects/$P/pipeline_schedules" | jq '.[] | {id, description, active, owner: .owner.username, etat: .owner.state, next_run_at}'
{ "id": 3, "description": "canari-quotidien", "active": true, "owner": "lucas.martin", "etat": "blocked", … }
```

Un pipeline planifié s'exécute **au nom de son propriétaire** (ses droits, ses accès aux variables protégées). Compte bloqué : plus de pipeline, et la planification passe en **Inactive** à sa première exécution manquée (documentation *Scheduled pipelines*, « Scheduled pipeline becomes inactive ») ; débloquer le compte ne la réactive pas. Correctif : un Maintainer reprend la propriété (`POST /projects/:id/pipeline_schedules/:id/take_ownership`, ou bouton *Take ownership*). Qui doit être propriétaire ? Un compte nominatif d'un membre permanent de l'équipe, ou un compte de service dédié (`svc-ci-plateforme`) dont la vie ne dépend pas d'un contrat de stage. La règle va dans RB-194 et dans le contrôle de M19-E32.

> `--annuler` réactive le compte de Lucas : il sert aux pannes des modules suivants. Dans la réalité, on ne réactive pas un compte pour réparer un pipeline : on change de propriétaire.

**Fichiers** : [`fichiers/M19-E41/medisphere/docs/livraison/ci/runbooks/RB-194-pipeline-non-declenche.md`](fichiers/M19-E41/medisphere/docs/livraison/ci/runbooks/RB-194-pipeline-non-declenche.md).

**Explications** : avant de créer un pipeline, GitLab vérifie que la fonction est active, trouve la configuration (chemin, projet externe éventuel), la fusionne (includes, composants), évalue `workflow:rules`, puis les `rules` de chaque job ; s'il ne reste aucun job, il n'y a pas de pipeline. La plupart de ces refus sont **silencieux** pour un `push` (aucun pipeline en échec n'est créé), ce qui rend le diagnostic contre-intuitif : on cherche une erreur là où il n'y a qu'une absence.

**Pièges classiques**
- Chercher dans les runners (il n'y a pas de job).
- Pousser des commits vides en boucle « pour relancer ».
- Corriger le composant en déplaçant l'étiquette publiée.

**En production chez MédiSphère** : le canari planifié (et l'alerte « pas de pipeline du canari depuis 26 h ») ; contrôle des propriétaires des pipelines planifiés (M19-E32) ; tests des composants qui vérifient qu'un pipeline de branche **et** un pipeline de MR sont créés (avec `ci/lint` en `dry_run`).

---

### M19-E42 — Panne : le job est tué en cours de route

**Démarche de diagnostic**

*Symptômes* : le journal s'arrête après `CANARI accès au dépôt : HTTP 200` (ou après `CANARI mémoire occupée`), le job échoue sans erreur du script.

**Étape 1 — Attraper la preuve.** Le pod est supprimé à la fin du job : surveille **avant** de lancer.

```
admin@adm01:~$ kubectl -n ci-jobs get pods -w -o custom-columns=NOM:.metadata.name,PHASE:.status.phase,RAISON:.status.reason,NOEUD:.spec.nodeName
admin@adm01:~$ kubectl -n ci-jobs get events -w
admin@adm01:~$ gl "projects/$P/pipeline?ref=main" -X POST | jq .id
```

Le script [`fichiers/M19-E42/essais/surveiller-ci-jobs.sh`](fichiers/M19-E42/essais/surveiller-ci-jobs.sh) enregistre l'état complet de chaque pod de job qui se termine (`-o json`) dans un dossier, ce qui laisse le temps de l'analyse.

**Variante 1 — OOMKilled.**

```
"lastState"/"state": {"terminated": {"reason": "OOMKilled", "exitCode": 137, …}}
admin@adm01:~$ kubectl -n ci-jobs get pod <pod> -o jsonpath='{.spec.containers[?(@.name=="build")].resources}'
{"limits":{"memory":"96Mi"},"requests":{"memory":"96Mi",…}}
admin@adm01:~$ kubectl -n gitlab-runner get cm <cm> -o jsonpath='{.data.config\.template\.toml}' | grep -E 'memory_(request|limit) '
    memory_request = "96Mi"
    memory_limit = "96Mi"
```

Correctif : `helmfile … apply` (valeurs du code, M19-E27). La demande a été baissée avec la limite : une demande supérieure à la limite rendrait le pod invalide (refusé par l'API, un tout autre symptôme). Le noyau tue le processus qui dépasse `memory.max` de son cgroup ; le runner ne voit qu'une sortie 137 (ou un pod en échec).

**Variante 2 — délai actif imposé par une politique de mutation.**

```
admin@adm01:~$ kubectl -n ci-jobs get pod <pod> -o jsonpath='{.status.reason} {.spec.activeDeadlineSeconds}{"\n"}'
DeadlineExceeded 30
admin@adm01:~$ kubectl get mutatingadmissionpolicies,mutatingadmissionpolicybindings
NAME                                                                      AGE
mutatingadmissionpolicy.admissionregistration.k8s.io/ci-jobs-delai-maximal   2h
…
admin@adm01:~$ kubectl get mutatingadmissionpolicy ci-jobs-delai-maximal -o yaml | yq '.spec.mutations'
```

Le runner pose lui-même `activeDeadlineSeconds` = délai du job + 1 s (`FF_USE_POD_ACTIVE_DEADLINE_SECONDS`, actif par défaut) : une valeur de **30** ne peut pas venir de lui (le délai du projet est d'au moins 10 minutes et le job du canari ne fixe pas de `timeout`). Une politique de mutation (`MutatingAdmissionPolicy`, GA en 1.36) la réécrit à l'admission. Correctif : supprimer la politique et sa liaison (et poser la question à Lucas : les « jobs zombies » se traitent par les délais de job et du runner, `maximum_timeout`, pas par l'admission). Prévention : les politiques d'admission ne vivent que dans `plateforme/k8s/admission/` (revue obligatoire).

**Variante 3 — éviction pour stockage éphémère.**

```
admin@adm01:~$ kubectl -n ci-jobs get events --field-selector reason=Evicted
… Container build exceeded its local ephemeral storage limit "50Mi".
admin@adm01:~$ kubectl -n gitlab-runner get cm <cm> -o jsonpath='{.data.config\.template\.toml}' | grep -E 'ephemeral_storage_(request|limit) '
    ephemeral_storage_limit = "50Mi"
    ephemeral_storage_request = "50Mi"
```

Le kubelet mesure périodiquement la couche inscriptible et les journaux de chaque conteneur ; au-delà de la limite, il **évince** le pod (phase `Failed`, raison `Evicted`). Correctif : valeur du code. Note : `/builds` est un `emptyDir`, compté au niveau du pod ; `/tmp` est dans la couche du conteneur.

**Variante 4 — préemption.**

```
admin@adm01:~$ kubectl -n ci-jobs get events --field-selector reason=Preempted
… Preempted by pod 5f0c… on node k8s-w02
admin@adm01:~$ kubectl get pods -A --field-selector spec.nodeName=k8s-w02 \
    -o custom-columns=NS:.metadata.namespace,NOM:.metadata.name,CLASSE:.spec.priorityClassName,PRIO:.spec.priority | sort -k4 -n | tail -n 3
wb-pannes-ci   reindexation-nocturne-…   medisphere-critique   100000
admin@adm01:~$ kubectl -n wb-pannes-ci get deploy reindexation-nocturne -o jsonpath='{.spec.template.spec.containers[0].resources}'
```

Un pod de priorité haute demande plus de mémoire que le nœud n'en a de libre : l'ordonnanceur cherche des victimes de priorité **plus basse** et choisit le pod de job (`medisphere-ci`, valeur 1000, la plus basse des pods présents ; elle a `preemptionPolicy: Never`, ce qui l'empêche de préempter les autres, pas d'être préemptée : voulue en M19-E27 pour que la CI cède la place aux applications). Le comportement est correct ; la faute est d'avoir donné `medisphere-critique` à un traitement par lots. Correctif : supprimer la charge (et la refaire, si elle est utile, avec une priorité `medisphere-standard` et des demandes réalistes) ; prévention : `ResourceQuota` avec `scopeSelector` sur `PriorityClass` qui réserve `medisphere-critique` aux espaces de production.

**Fichiers** : la section `Job tué` de [`RB-195`](fichiers/M19-E36/medisphere/docs/livraison/ci/runbooks/RB-195-job-echoue-ou-tue.md).

**Explications** : quatre « tueurs » qui ne sont pas le script : le **noyau** (OOM, au niveau du cgroup du conteneur, immédiat), le **kubelet** (éviction par pression ou limite de stockage, sondes, délai actif : il arrête le pod avec un délai de grâce), l'**ordonnanceur** (préemption : il supprime des pods moins prioritaires pour en placer un plus prioritaire), et le **runner** (délai du job, annulation). Le journal du job ne montre que la conséquence (flux coupé) : la cause est dans `status` du pod et dans les événements, qui disparaissent avec le pod (une heure pour les événements).

**Alternatives** : `pod_disruption_budget = true` (Runner 18.10 et plus) protège les pods de job des **évictions volontaires** (drain), pas des préemptions ni des OOM ; une PriorityClass plus haute pour les jobs de production (signature, promotion) sur le runner protégé.

**Pièges classiques**
- Augmenter toutes les limites « pour être tranquille » : on déplace le problème vers la capacité du cluster (M19-E27).
- Chercher l'erreur dans le script.
- Laisser passer l'heure de rétention des événements avant de regarder.

**En production chez MédiSphère** : alertes sur `kube_pod_container_status_last_terminated_reason{reason="OOMKilled",namespace="ci-jobs"}` et sur les préemptions (M21) ; journalisation des événements de `ci-jobs` dans Loki (M22) pour garder la preuve.

---

### M19-E43 — Astreinte : la chaîne de livraison en détresse

**Démarche** (il n'y a pas de solution unique : le trio est tiré au hasard)

1. **Triage, 10 minutes.** Instruments d'abord : jeton d'administration (`gl version`), `kubectl get nodes`, accès aux journaux de `git01`, état des runners (`gl runners/all`). Puis cartographie : `for e in 35 36 37 38 39 40 41 42; do lab/bin/check 19 $e; done 2>&1 | grep -E '==|KO'`. Première communication : « Incident en cours sur la chaîne de livraison : [symptômes]. Impact : [qui ne peut plus livrer quoi]. Prochaine communication à 8 h 15. »
2. **Ordre de traitement**, par dépendances : existence des pipelines (E41) → prise des jobs (E35, gestionnaire) → démarrage (E36) → durée de vie (E42) → services joints (E37, E38, E40) → déploiement (E39). Une fuite de secret (E40) se **confine** dès qu'elle est vue, quel que soit l'ordre : effacement des journaux et rotation n'attendent pas.
3. **Après chaque correction**, rejouer le canari et les contrôles : une panne peut en masquer une autre (le cache cassé n'apparaît qu'une fois les jobs repartis).
4. **Communication** toutes les 30 minutes : état, ce qui est rétabli, prochaine étape, heure de la prochaine communication. Contournement possible pour la mise en production : aucun ne doit contourner la signature ni la promotion par MR ; un report est une option à proposer à Claire.
5. **Clôture** : `lab/bin/break 19 43 --annuler`, `lab/bin/check 19 43` vert, post-mortem.

**Post-mortem** : exemple complet dans [`fichiers/M19-E43/medisphere/docs/kubernetes/post-mortems/2026-11-03-INC-4643.md`](fichiers/M19-E43/medisphere/docs/kubernetes/post-mortems/2026-11-03-INC-4643.md) (trio E35 v1, E37 v2, E40 v2). Points que la grille regarde : chronologie horodatée avec la **détection** (Julien, pas une alerte) ; les trois causes racines et leur facteur commun (changements faits hors du code, sans revue, par une même personne en apprentissage : ce n'est pas la faute de Lucas, c'est l'absence de garde-fous) ; ce qui a bien marché (canari, runbooks) ; actions avec responsable et échéance (dérive nocturne de `plateforme/k8s`, alerte sur l'âge des jobs en attente, règle Semgrep contre `set -x`, revue obligatoire des politiques Cilium).

**Pièges classiques** : traiter les trois pannes en parallèle (on ne sait plus quelle action a réparé quoi) ; oublier une communication ; écrire le post-mortem avec des noms comme causes.

---

### M19-E44 — Sous le capot : du `git push` au pod de job

**Solution**

*Préparation* : branche `capot` de `formation/ci-labo` avec le job de [`fichiers/M19-E44/ci-labo/gitlab-ci.capot.yml`](fichiers/M19-E44/ci-labo/gitlab-ci.capot.yml) (à fusionner dans le `.gitlab-ci.yml` de la branche : composants du projet + job `capot`). `logLevel: debug` dans les values du runner, `helmfile … apply`. Trois terminaux : `git01` (journaux), `adm01` (`kubectl -n ci-jobs get pods -w`), `adm01` (gestionnaire : `kubectl -n gitlab-runner logs -f deploy/<gestionnaire>`). Le script [`fichiers/M19-E44/outils/capot-journaux.sh`](fichiers/M19-E44/outils/capot-journaux.sh) (à lancer sur `git01` avec `sudo`) extrait les lignes utiles des journaux de GitLab pour une fenêtre de temps et un projet, sans les jetons.

*1. Le push.*

```
admin@git01:~$ sudo jq -c 'select(.time >= "2026-11-04T09:12") | {time, msg, command, gl_project_path, status}' /var/log/gitlab/gitlab-shell/gitlab-shell.log | tail -n 3
admin@git01:~$ sudo jq -c 'select(.route | test("internal/(allowed|post_receive)")) | {time, route, status, duration_s, correlation_id}' /var/log/gitlab/gitlab-rails/api_json.log | tail -n 2
{"time":"…09:12:41.2Z","route":"/api/:version/internal/allowed","status":200,"duration_s":0.08,"correlation_id":"01J…"}
{"time":"…09:12:41.9Z","route":"/api/:version/internal/post_receive","status":200,"duration_s":0.05,"correlation_id":"01J…"}
admin@git01:~$ sudo jq -c 'select(.correlation_id == "01J…") | {time, class, job_status, duration_s}' /var/log/gitlab/sidekiq/current
{"class":"PostReceive","job_status":"done",…}
```

gitlab-shell demande à Rails si la poussée est permise (`/internal/allowed`), Gitaly écrit les objets, le *hook* `post-receive` de Gitaly appelle `/internal/post_receive`, qui met en file le travail Sidekiq `PostReceive` : la poussée rend la main au développeur **avant** que quoi que ce soit ne concerne la CI.

*2. Le pipeline.* `PostReceive` traite la poussée de branche (événements, MR liées) et demande la création du pipeline ; selon la version, la création est faite dans le travail ou dans un travail dédié (`CreatePipelineWorker`) ; puis `Ci::InitialPipelineProcessWorker` (ou `PipelineProcessWorker`) calcule les jobs prêts et les passe en `pending`. Recherche par `correlation_id`, puis par `meta.pipeline_id` / l'identifiant du pipeline. Durée typique poussée → `pending` sur le lab : 1 à 3 secondes (davantage si Sidekiq est chargé : c'est ce que voit le développeur, un pipeline qui « n'apparaît pas tout de suite »).

*3. La file et le runner.*

```
admin@git01:~$ sudo jq -c 'select(.route == "/api/:version/jobs/request") | {time, status, duration_s}' /var/log/gitlab/gitlab-rails/api_json.log | tail -n 4
admin@git01:~$ sudo grep -h '"uri":"/api/v4/jobs/request"' /var/log/gitlab/gitlab-workhorse/current | jq -c '{time, status, duration_ms}' | tail -n 4
{"status":204,"duration_ms":50012}
{"status":204,"duration_ms":50008}
{"status":201,"duration_ms":1873}
```

(Sorties après activation du *long polling* : `gitlab_workhorse['api_ci_long_polling_duration'] = "50s"` posé par le rôle Ansible de `git01`, puis `gitlab-ctl reconfigure`. Avant, sur un omnibus par défaut, chaque requête répond `204` en quelques millisecondes et le gestionnaire rappelle toutes les `check_interval` secondes : c'est la première chose à constater.) Workhorse retient alors la requête du runner jusqu'à `api_ci_long_polling_duration` et ne la transmet à Rails que si une notification Redis signale du nouveau pour ce runner : sans job, `204` au bout du délai ; avec un job, Rails exécute la sélection (`Ci::RegisterJobService` : étiquettes, protection, file), passe le job en `running`, répond `201` avec la charge utile (étapes du script, images, variables, jeton de job, informations de cache et d'artefacts). Dans le journal du gestionnaire : `Checking for jobs... received job=… repo_url=… runner=…`, puis `Using Kubernetes executor…`, `Waiting for pod…`.

*4. Le pod.*

```
admin@adm01:~$ kubectl -n ci-jobs get pod <pod> -o yaml | yq '{"init": [.spec.initContainers[].name], "conteneurs": [.spec.containers[].name], "sa": .spec.serviceAccountName, "jeton": .spec.automountServiceAccountToken, "delai": .spec.activeDeadlineSeconds, "prio": .spec.priorityClassName, "volumes": [.spec.volumes[].name]}'
admin@k8s-cp01:~$ sudo jq -c 'select(.user.username | startswith("system:serviceaccount:gitlab-runner:")) | select(.objectRef.namespace == "ci-jobs") | {t: .requestReceivedTimestamp, verb, res: .objectRef.resource, sub: .objectRef.subresource, nom: .objectRef.name, code: .responseStatus.code}' /var/log/kubernetes/audit/audit.log | tail -n 20
```

Séquence représentative (stratégie *attach*) : `create secrets` (identifiants de registre du job, selon la configuration), `create pods`, plusieurs `get pods` (attente de `Running`), `create pods/attach` sur `build` puis `helper` (chaque étape du job est un script envoyé au shell qui attend dans le conteneur), `get pods/log`, puis `delete pods` et `delete secrets`. Conteneurs : `init-permissions` (init, droits sur `/builds`), `build` (image du job), `helper` (clone, cache, artefacts), plus un conteneur par service. Le pod n'a **aucun** jeton d'API (`automountServiceAccountToken: false`, compte `ci-job`) : seul le gestionnaire parle à l'API.

*5. Journal et artefacts.*

```
admin@git01:~$ sudo jq -c 'select(.route | test("jobs/:id(/trace|/artifacts.*)?$")) | {time, method, route, status}' /var/log/gitlab/gitlab-rails/api_json.log | tail -n 8
{"method":"PATCH","route":"/api/:version/jobs/:id/trace","status":202}
…
{"method":"POST","route":"/api/:version/jobs/:id/artifacts/authorize","status":200}
{"method":"POST","route":"/api/:version/jobs/:id/artifacts","status":201}
{"method":"PUT","route":"/api/:version/jobs/:id","status":200}
```

Le journal part par morceaux (`PATCH …/trace` avec `Content-Range`), rangés d'abord dans Redis (*live trace*, `ci_build_trace_chunks`), puis consolidés en fin de job. Les artefacts : le *helper* demande une autorisation (`authorize`, Rails répond où écrire), Workhorse reçoit le flux, l'écrit sur disque ou dans le stockage objet, puis prévient Rails (`POST …/artifacts`). Sur omnibus sans stockage objet, ils sont sous `/var/opt/gitlab/gitlab-rails/shared/artifacts/` (arborescence par empreinte du projet). `PUT /jobs/:id` envoie l'état final (`success`) : c'est lui qui fait avancer le pipeline.

*6. Compte rendu* : modèle complet [`fichiers/M19-E44/medisphere/docs/livraison/ci/sous-le-capot.md`](fichiers/M19-E44/medisphere/docs/livraison/ci/sous-le-capot.md) (le squelette fourni est dans `ressources/E44-sous-le-capot/`).

**Réponses aux questions d'analyse**

1. La poussée doit être rapide et ne jamais échouer à cause de la CI : la création du pipeline (lecture de la configuration, includes, composants, évaluation des règles) peut prendre des secondes et appeler d'autres projets ; elle est donc différée dans Sidekiq. Sidekiq saturé : le développeur voit son commit **sans pipeline** pendant de longues secondes ou minutes, puis le pipeline apparaît (rien n'est perdu, la file Redis garde les travaux).
2. Interroger toutes les secondes ferait des milliers de requêtes Rails par minute pour rien ; le *long polling* garde une requête ouverte par gestionnaire et ne réveille Rails que quand une notification (Redis, clé de file du runner) arrive. Workhorse la maintient (`api_ci_long_polling_duration`, **à activer** : non posé par défaut dans omnibus, le runner se contente alors d'interroger toutes les `check_interval` secondes) ; l'arrivée d'un job compatible publie la notification qui libère la requête.
3. La réponse contient l'identifiant du job, le jeton du job, les étapes (scripts), les images et services, les variables (dont les secrets qui lui reviennent), les informations Git (dépôt, référence, profondeur), cache et artefacts à télécharger. Le jeton de job est valable tant que le job tourne (et jusqu'à son délai) ; il permet de cloner le dépôt, de télécharger les artefacts des dépendances, d'envoyer le journal et les artefacts, et d'accéder aux projets qui l'autorisent (liste d'autorisation entrante, M19-E25).
4. Le gestionnaire crée et pilote des pods (création, attachement ou `exec` pour envoyer les scripts, lecture des journaux, suppression) : il lui faut ces verbes dans `ci-jobs`, et rien d'autre (Role du M19-E24). Le pod de job exécute du code venu des projets : s'il avait un jeton d'API, n'importe quel développeur pourrait agir sur le cluster depuis un job.
5. Dans Redis (morceaux de journal en direct), puis en base ou en stockage objet à la fin. Si le gestionnaire meurt, il n'envoie plus rien : GitLab ne sait pas que le job est fini ; le job reste `running` jusqu'à son délai, puis passe en échec (« job has not been triggered by a runner… » / *stuck* selon le cas) ; le pod, lui, peut rester orphelin dans `ci-jobs` jusqu'à son `activeDeadlineSeconds` : d'où l'intérêt de ce champ.
6. Workhorse est un mandataire en Go conçu pour les transferts longs : Rails (Puma) n'a pas à garder un processus occupé pendant le téléversement d'un fichier de plusieurs centaines de Mo. La taille maximale des artefacts se règle dans *Admin > Settings > CI/CD* (et par projet ou groupe) ; elle vaut 100 Mo par défaut (à vérifier sur ta version).
7. Non redondants dans le lab : `git01` (Rails, Sidekiq, Workhorse, Gitaly, Redis, PostgreSQL sur une seule VM) : s'il tombe, plus de création de pipelines ni d'attribution, les jobs en cours ne peuvent plus envoyer leur journal ni finir (ils échouent au retour de GitLab) ; `s3-01` (cache : jobs plus lents, pas d'échec) ; `reg01` (images : les pods ne démarrent plus) ; `buildkitd` (une réplique : constructions en échec) ; l'API Kubernetes est redondante (trois nœuds de contrôle, VIP) ; le gestionnaire du runner l'est si `replicas: 2` (M19-E27).

**Pièges classiques** : recopier des lignes de journal en entier (URL présignées, identifiants) ; oublier de remettre `logLevel` ; chercher les classes Sidekiq par leur nom d'une ancienne version au lieu de suivre le `correlation_id`.

**En production chez MédiSphère** : ce compte rendu devient la page d'accueil de RB-190 à RB-198 ; les journaux de `git01` partent dans Loki au M22, avec des requêtes enregistrées pour chaque étape.

---

### M19-E45 — Questions expert : intégration continue

1. **Chemin d'un push.** Synchrone : client Git → sshd + gitlab-shell (ou nginx + Workhorse en HTTPS) → contrôle d'accès par Rails (`/internal/allowed`) → Gitaly écrit les objets et met à jour la référence → *hook* `post-receive` → Rails (`/internal/post_receive`) met en file `PostReceive` → la poussée se termine. Asynchrone : Sidekiq crée le pipeline (lecture de la configuration, includes et composants, règles), le traite (jobs `pending`) ; une notification réveille les requêtes de *long polling* des gestionnaires ; le premier gestionnaire compatible reçoit le job (`201`), crée le pod, attend `Running`, attache le shell ; le *helper* clone ; la première sortie du script part par `PATCH …/trace`. Tout ce qui suit la poussée est asynchrone, d'où les secondes « sans pipeline ».
2. **c).** Un job n'est pris que par un runner qui porte **toutes** ses étiquettes ; A n'a pas `protege`, B n'a pas `k8s`. Et même avec les bonnes étiquettes, B ne prendrait pas une référence non protégée. a) faux : une étiquette commune ne suffit pas ; b) faux : il n'y a pas de « précision » ; d) faux : un job est attribué à un seul runner.
3. Branche nouvelle : pas de base de comparaison fiable (GitLab compare au commit précédent de la poussée, ou considère que tout a changé selon le cas et la version) → `changes` vaut souvent vrai, jobs inattendus. Pipeline planifié (et API, déclencheurs) : `changes` vaut **toujours** vrai. MR : comparaison avec la branche cible (`compare_to` permet de fixer la référence). Piège : des jobs « conditionnés aux changements » qui tournent toujours dans les pipelines planifiés, ou un job de déploiement qui tourne sur une branche neuve.
4. Les entrées sont **typées**, validées et interpolées à la **création** du pipeline (avant l'évaluation des variables) : une valeur ne peut pas injecter de nouvelles clés YAML ni changer la structure, une entrée obligatoire absente fait échouer la création avec un message clair, et le composant est **versionné** (référence immuable). Les variables, elles, sont évaluées à l'exécution, peuvent venir de n'importe où (projet, groupe, déclencheur) et ne valident rien.
5. **b).** `~latest` suit la dernière version publiée : tous les consommateurs prennent la version cassée au pipeline suivant. a) faux : le catalogue ne « vérifie » pas les versions ; c) faux ; d) faux. D'où l'épinglage à une version complète (ou au moins majeure) et les tests du composant avant publication.
6. Garantit : la valeur exacte est remplacée par `[MASKED]` dans le journal. Ne garantit pas : une forme transformée (base64, URL-encodée selon les versions, coupée, inversée), la trace de débogage (`CI_DEBUG_TRACE`) qui affiche les expansions, les **artefacts** et fichiers écrits par le job, une variable **démasquée** par un Maintainer. « Masquée et cachée » : la valeur n'est plus lisible dans l'interface ni par l'API après création et la variable ne peut plus être démasquée.
7. Il authentifie le job auprès de GitLab (clone, artefacts, registre de paquets, API limitée) pendant la durée du job seulement. La liste d'autorisation entrante (*Job token permissions*) dit quels projets peuvent utiliser **leur** jeton de job pour accéder à **ce** projet : par défaut fermée. Préférable à un jeton de projet : pas de secret longue durée à stocker, à protéger et à tourner, portée limitée au job, révocation automatique.
8. Le job ne reçoit plus un secret durable mais une **preuve d'identité** de courte durée, signée par GitLab : le consommateur (OpenBao au M25) vérifie la signature (clés publiées par GitLab), `aud` (le jeton lui est destiné), `iss`, l'expiration, et décide selon les revendications (`project_path`, `ref`, `ref_protected`, `environment`). Ce qui doit être vérifié côté consommateur : **toutes** ces revendications ; un rôle qui n'exige pas `ref_protected: true` donne le secret de production à n'importe quelle branche.
9. **a).** Le délai effectif d'un job est le plus petit du délai du job et du `maximum_timeout` du runner. c) est la conséquence (le runner pose `activeDeadlineSeconds` = délai effectif + 1 s) mais pas la cause ; b) `poll_timeout` concerne l'attente du démarrage du pod ; d) le cache n'expire pas en cours de job.
10. DinD exige un conteneur privilégié (interdit, accès quasi root au nœud) ; Kaniko est archivé ; BuildKit sans démon dans chaque job exige des exceptions seccomp/AppArmor dans `ci-jobs` et perd le cache entre jobs. Le démon partagé *rootless* concentre les exceptions dans un seul espace surveillé et garde un cache chaud. Risques : un projet qui lit ou empoisonne le cache d'un autre (cache partagé par contenu), un démon compromis qui voit les constructions de tous, une indisponibilité commune. Réductions : TLS mutuel et politique réseau (seuls les jobs), cache en registre par projet (référence distincte), images de base par empreinte, signature et provenance qui lient l'image au job, démon distinct pour le runner protégé si l'analyse de risque l'exige.
11. Cache : optimisation **sans garantie** (peut manquer, être ancien, partagé entre jobs et pipelines, séparé par protection), stocké dans `ci-cache`. Artefacts : résultat **garanti** d'un job, transmis aux jobs suivants du même pipeline (`needs`, `dependencies`), conservé selon `expire_in`, stocké par GitLab. Transmettre un résultat par le cache : un job suivant peut tourner sur un autre runner, avant la fin de l'écriture, ou ne pas trouver l'archive.
12. PriorityClass basse : en cas de saturation, les applications (et les jobs prioritaires) préemptent les jobs de CI plutôt que l'inverse ; la file de CI s'allonge (les jobs attendent `poll_timeout` puis échouent, ou restent en attente côté GitLab si `limit`/`concurrent` sont atteints). Le PDB par job (`pod_disruption_budget`) ne protège que contre les **évictions** par l'API (drain) ; la préemption par l'ordonnanceur respecte les PDB « au mieux » mais peut les violer s'il n'y a pas d'autre choix, et l'OOM l'ignore complètement.
13. Le pipeline planifié ne tourne plus (le propriétaire n'a plus de droits) et la planification devient *Inactive* ; *Take ownership* la réactive. Règle : propriétaire = membre permanent ou compte de service dédié par équipe ; *take ownership* lors de chaque départ (procédure RH) ; contrôle hebdomadaire des propriétaires (M19-E32).
14. Free : branches et étiquettes protégées (seuls les Maintainers fusionnent ou étiquettent), runner protégé (seul à recevoir les secrets de signature et de promotion), variables protégées, jobs manuels, `resource_group` (un déploiement à la fois), MR obligatoire et relue sur `mediagenda/deploiement` (et Argo CD au M20). Moins bien qu'en Premium : pas d'approbation **obligatoire** d'un tiers imposée par GitLab (la règle tient par l'organisation et les Maintainers), pas de liste nominative de qui peut déployer dans tel environnement, pas de règle de *code owners* bloquante.
15. GitLab d'abord (dans le chemin de montée officiel, une mineure à la fois, migrations d'arrière-plan **terminées** avant la suivante), puis runners et agent (même mineure ; un runner peut avoir une mineure de retard ou d'avance limitée selon la politique de compatibilité, à vérifier). Retour arrière : restauration de la sauvegarde **applicative** (`gitlab-backup` + `gitlab-secrets.json` + `gitlab.rb`) cohérente avec la version, ou de la VM entière. PBS seul ne suffit pas : instantané pris pendant que les migrations écrivent (incohérence), restauration de toute la VM pour un problème partiel, et pas de restauration croisée vers une autre version.
16. Preuves : signature Cosign de l'image par la clé MédiSphère (vérifiable), attestation de provenance SLSA qui nomme le pipeline, le job, le commit et le runner ; SBOM attaché ; MR relue et fusionnée qui contient le commit ; journaux du pipeline ; promotion par MR dans `mediagenda/deploiement` ; événements d'audit de GitLab. Falsifiables par un administrateur de la plateforme : à peu près tout ce qui vit dans GitLab (un administrateur peut lancer un pipeline, accéder aux variables protégées, donc à la clé de signature) ; d'où la séparation des rôles (clé dans un HSM ou OpenBao au M25, signature sans clé exportable), les journaux exportés hors de GitLab (Loki, M22), et la vérification par un tiers.

**Pièges classiques** : répondre « c'est le runner qui choisit » (c'est GitLab qui attribue) ; confondre masquage et protection ; croire qu'un PDB protège de tout.

**En production chez MédiSphère** : ces réponses alimentent l'ADR-0190 (section « limites assumées ») et la page d'accueil des runbooks.
