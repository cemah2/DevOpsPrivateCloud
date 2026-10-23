# Final F2 — Phase 2 : MédiVisio — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Validé hors du lab** (à la rédaction, 23/10/2026) :
- Le service de référence ([`src/app.py`](fichiers/S04/medivisio-consultation/src/app.py), bibliothèque standard de Python 3.13) a été lancé et interrogé : `/sante`, `/pret` (503 sans clé), `/api/v1/disponibilites`, `POST /api/v1/salles`, `/metrics` (compteur et histogramme cumulatif au format texte de Prometheus) ; ses tests `unittest` passent.
- Tous les fichiers YAML et JSON des corrigés se relisent ; le script de panne passe `bash -n` et `shellcheck -x`.

**Points non testés en conditions réelles** (signale tes retours) :
- le modèle `nouveau-service` v2 : expressions Nunjucks des étapes (`parameters.locataire or …`, `x if y else z`, `if:` des étapes) et la branche `oneOf` « équipe en code » (`not: enum`) dans le formulaire de Backstage 1.56 ;
- `kustomize build` des overlays (pas d'outil dans l'environnement de rédaction) et transformations `yq` (mikefarah v4) du script de panne ;
- fusion des `AlertmanagerConfig` (voir le corrigé de la phase 1), propagation des étiquettes `pyrra.dev/*` par Pyrra 0.10 dans un espace d'équipe, tableau Grafana (requêtes sur `pyrra_availability` et `pyrra_objective` des règles génériques) ;
- les horodatages de la mesure du délai : ceux d'un lab **imaginé** pour montrer la forme ; remplace-les par les tiens.

**Fichiers** : [`fichiers/S04/`](fichiers/S04/) (`medivisio-consultation/` = `medivisio/consultation`, `medivisio-consultation-deploiement/`, `medivisio-gitops/` = `medivisio/gitops`, `portail-modeles/`, `equipes/` = l'extrait du fichier d'équipe, `medisphere/`) ; [`fichiers/S05/`](fichiers/S05/) (overlays de recette et de production, runbook, tableau, tests de routage) ; [`fichiers/S06/`](fichiers/S06/) (RB-321, journal) ; panne : [`pannes/break-S06.sh`](pannes/break-S06.sh).

---

### F2-S04 — MédiVisio : du modèle au premier déploiement

**Solution de référence** (ADR : [ADR-0321](fichiers/S04/medisphere/docs/accueil/adr/ADR-0321-services-des-equipes-en-code.md)).

**1. Le modèle v2.** Le modèle du M28 suppose un espace par service. Pour une équipe en code, les espaces existent et l'AppProject est posé : il ne manque qu'une **Application par environnement**. La référence la fait naître d'un **ApplicationSet par équipe**, rendu en S02 ([`services.yaml`](fichiers/S02/rendu-exemple/gitops/equipes/medivisio/services.yaml)) : générateur `matrix` = fichiers `services/*.yaml` du dépôt **de l'équipe** `medivisio/gitops` × environnements de l'équipe ; projet, destinations et politique de synchronisation écrits dans le gabarit (jamais une donnée de l'équipe) ; `templatePatch` pour la synchronisation automatique sauf en production. Le modèle v2 ([`template.yaml`](fichiers/S04/portail-modeles/modeles/nouveau-service/template.yaml)) :
- garde les branches du M28 pour `mediagenda` et `medidoc` (étapes conditionnées par `if:`) ;
- pour une équipe en code : nom sans préfixe (`consultation`), composant et image préfixés (`medivisio-consultation`), deux projets dans le groupe de l'équipe, un dépôt de déploiement avec les overlays de **tous** ses environnements ([squelette](fichiers/S04/portail-modeles/modeles/nouveau-service/squelettes/LISEZMOI-deploiement-equipe.md)), et une MR **dans le dépôt de l'équipe** (`services/consultation.yaml`), qu'Inès fusionne elle-même.

**2. Le parcours d'Inès** (fenêtre privée, compte `ines.garnier`) :

```
Portail → Créer → « Nouveau service » : équipe medivisio, nom consultation, Python, description
  → medivisio/consultation, medivisio/consultation-deploiement, MR medivisio/gitops!1, Component medivisio-consultation
```

Premier pipeline : **échec à la signature** — le rôle JWT `ci-medivisio-consultation` n'existe pas, et `ci-signature` n'accepte pas encore le groupe `medivisio`. Correction **par le code** : MR d'Inès sur `plateforme/equipes` ([extrait](fichiers/S04/equipes/equipes/medivisio.extrait-F2-S04.yaml) : `services: [consultation]`), relue par la Plateforme ; la propagation crée dans `plateforme/secrets` les rôles `ci-medivisio-consultation` et `-promotion` (liés au chemin du projet, références protégées) et ajoute `medivisio` aux groupes de `ci-signature` (`tofu:apply:equipes`, aucune destruction).

```
admin@adm01:~$ bao read auth/gitlab/role/ci-medivisio-consultation-promotion      # bound_claims : project_path, environment promotion/*
admin@adm01:~$ bao read -format=json auth/gitlab/role/ci-signature | jq .data.bound_claims.namespace_path
```

Pipeline relancé : construction (BuildKit), analyse, signature par `transit/cosign-medisphere`, SBOM, puis MR de promotion dans `medivisio/consultation-deploiement` (jeton de groupe `kv/medivisio/ci/promotion`, rangé en S02). Le secret du service en dev, écrit par Inès :

```
ines@poste$ bao login -method=oidc
ines@poste$ bao kv put kv/medivisio/dev/consultation cle_salles="$(openssl rand -hex 32)"
ines@poste$ bao kv get kv/mediagenda/dev/x        # refusé (403) : contrôle négatif
```

Inès fusionne la MR de promotion **puis** la MR de déclaration (`services/consultation.yaml`) ; l'ApplicationSet crée `medivisio-consultation-dev` (`-recette` et `-prod` aussi, qui restent `OutOfSync`/`Missing` tant que leurs overlays n'ont pas d'empreinte valide — ou que leur MR n'est pas faite : voir S05).

```
admin@adm01:~$ argocd app get medivisio-consultation-dev
admin@adm01:~$ kubectl -n medivisio-dev get deploy consultation -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
admin@adm01:~$ cosign verify --key docs/registre/cosign.pub --insecure-ignore-tlog=true registry.par1.medisphere.internal/medisphere/medivisio-consultation@sha256:<EMPREINTE>
admin@adm01:~$ curl -s https://consultation-dev.apps.par1.medisphere.internal/sante
```

Documentation : le job `techdocs:publication` attend `TECHDOCS_S3_CLE`/`TECHDOCS_S3_SECRET` en variables de groupe : posées par la Plateforme (seconde intervention, hors du chemin critique).

**3. La mesure** ([`medivisio-premier-deploiement.md`](fichiers/S04/medisphere/docs/accueil/mesures/medivisio-premier-deploiement.md)) : chronologie horodatée (scaffolder, pipelines, MR, historique d'Argo CD, audit du coffre), délai total, attente de la Plateforme, liste des interventions avec leur cause et le correctif proposé.

**Explications**

- Le chemin balisé se mesure du point de vue de l'équipe : « je clique » → « ça répond ». Ce qui compte n'est pas le temps machine (minutes) mais les **attentes humaines** : ici, la relecture d'une MR de la Plateforme pour les rôles CI. La mesure les rend visibles, la feuille de route (S14) les supprime.
- L'ApplicationSet est sûr parce que le **cadre** (projet, destinations, synchronisation) est dans le gabarit de la plateforme, et la **donnée** de l'équipe (`service`) n'entre que dans un nom et un chemin de dépôt, eux-mêmes bornés par l'AppProject (dépôts du groupe, espaces de l'équipe).
- La signature reste réservée au runner protégé et aux groupes déclarés : une équipe qui n'a pas déclaré son service ne peut pas faire signer d'image par la clé MédiSphère.

**Alternatives**

- Garder le modèle du M28 (espace par service, deux MR à la Plateforme) : plus d'isolation entre services d'une équipe, deux tickets par service.
- Générateur **SCM Provider** (GitLab) de l'ApplicationSet : découvre seul les projets `*-deploiement` du groupe, sans index ; exige un jeton d'API pour Argo CD et rend l'apparition d'un service implicite (un projet créé suffit).
- Rôle CI **par groupe** (`namespace_path = medivisio`) : plus de MR pour un nouveau service, mais tout projet du groupe obtient le jeton de promotion et la signature.
- Faire ouvrir par le modèle la MR de `plateforme/equipes` (déclaration du service) : supprime l'oubli, garde la relecture ; c'est la prochaine étape (feuille de route).

**Pièges classiques**

- Fusionner la MR de déclaration avant la première image signée : `-recette`/`-prod` (et `-dev` sans empreinte) apparaissent en erreur dans Argo CD ; sans gravité, mais trompeur pour l'équipe.
- Une image désignée par étiquette dans un overlay : refusée en recette et en production (`verifyDigest`), acceptée en dev — la surprise arrive au pire moment (S06, variante 2).
- Oublier que `/pret` dépend du secret : pods jamais prêts tant que `kv/medivisio/dev/consultation` n'existe pas.
- Nom de composant non préfixé (`consultation`) : collision au catalogue avec un futur service d'une autre équipe.
- Corriger l'échec de signature en ajoutant le rôle à la main dans OpenBao : la prochaine propagation (ou le contrôle de dérive) l'efface, et rien n'est tracé.

**En production chez MédiSphère**

Le délai jusqu'au premier déploiement devient un indicateur suivi (médiane par trimestre) ; le modèle ouvre lui-même la MR de déclaration ; l'identité d'écriture TechDocs est rendue par équipe ; un test de bout en bout du modèle (création d'un service jetable, déploiement en dev, suppression) tourne chaque nuit.

---

### F2-S05 — MédiVisio en production, avec ses alertes et son SLO

**Solution de référence**

**1. Secrets en libre-service.** Inès écrit `kv/medivisio/recette/consultation` et `kv/medivisio/prod/consultation` (politique `medivisio-equipe`, S02) ; chaque overlay porte son [`ExternalSecret`](fichiers/S04/medivisio-consultation-deploiement/overlays/prod/secret.yaml), lu par le `SecretStore` `openbao` de l'espace (rôle `eso-medivisio-<env>` : `kv/medivisio/<env>/*` en lecture seulement).

```
ines@poste$ bao kv put kv/medivisio/prod/consultation cle_salles="$(openssl rand -hex 32)"
ines@poste$ bao kv list kv/medivisio/                         # dev/ prod/ recette/ — pas ci/
ines@poste$ bao kv get kv/medivisio/ci/promotion              # refusé : jeton de la CI
admin@adm01:~$ kubectl -n medivisio-prod get externalsecret consultation   # STATUS SecretSynced, READY True
```

**2. Promotion.** MR « recette » dans `medivisio/consultation-deploiement` : l'empreinte de dev recopiée dans `overlays/recette/kustomization.yaml` ([état](fichiers/S04/medivisio-consultation-deploiement/overlays/recette/kustomization.yaml), plus [`slo.yaml`](fichiers/S05/medivisio-consultation-deploiement/overlays/recette/slo.yaml)) ; synchronisation automatique ; vérification de la recette. MR « production » : même empreinte dans [`overlays/prod/kustomization.yaml`](fichiers/S05/medivisio-consultation-deploiement/overlays/prod/kustomization.yaml) (2 réplicas, `medisphere-critique`, répartition sur les nœuds, [`PodDisruptionBudget`](fichiers/S05/medivisio-consultation-deploiement/overlays/prod/production.yaml), [SLO](fichiers/S05/medivisio-consultation-deploiement/overlays/prod/slo.yaml)), relue par Léo, fusionnée par Inès ; **Sync** manuel dans Argo CD un mardi à 10 h (fenêtre `deny` du vendredi 16 h au lundi 8 h, `manualSync: false`).

```
admin@adm01:~$ argocd app diff medivisio-consultation-prod
ines@poste$ argocd app sync medivisio-consultation-prod          # rôle proj:medivisio:equipe
admin@adm01:~$ kubectl -n medivisio-prod get deploy,pdb -l app.kubernetes.io/instance=consultation
admin@adm01:~$ curl -s https://consultation.apps.par1.medisphere.internal/sante
```

**3. SLO et alertes.** Le SLO est **dans l'espace de production**, porté par le dépôt de l'équipe : Pyrra écrit la `PrometheusRule` du même nom dans `medivisio-prod` (lue parce que l'espace porte `supervision-regles=oui`, sélecteurs forcés sur l'espace par `enforcedNamespaceLabel`) ; `pyrra.dev/equipe: medivisio` devient l'étiquette `equipe` des alertes ; la `severity` posée par Pyrra est recopiée dans `gravite` (M21-E27). Routage : la route `equipe="medivisio"` de l'`AlertmanagerConfig` `alertes-medivisio` de l'espace (rendue en S02, filtre `namespace="medivisio-prod"` ajouté par l'opérateur, `continue` en premier niveau) part à `medivisio@` ; une critique continue vers `astreinte@` (route globale du M21).

```
admin@adm01:~$ curl -s http://alertmanager.apps.par1.medisphere.internal:9093/api/v2/status | jq -r .config.original > /tmp/am.yaml
admin@adm01:~$ amtool config routes show --config.file=/tmp/am.yaml | grep -A3 medivisio
admin@adm01:~$ amtool config routes test --config.file=/tmp/am.yaml --verify.receivers=medivisio-prod/alertes-medivisio/equipe-courriel \
                 alertname=ErrorBudgetBurn gravite=avertissement equipe=medivisio namespace=medivisio-prod
admin@adm01:~$ amtool alert add EssaiRoutageF2S05 gravite=avertissement equipe=medivisio namespace=medivisio-prod \
                 --annotation=summary="Essai de routage F2-S05" --alertmanager.url=http://alertmanager.apps.par1.medisphere.internal:9093
```

L'alerte d'essai arrive dans Mailpit (destinataire `medivisio@medisphere.internal`) après `group_wait` (30 s) ; elle expire seule (sans `--end`, 1 h par défaut côté `amtool` : vérifie `amtool alert add --help` sur ta version). Ajoute les cas de [`routes-tests.extrait`](fichiers/S05/observabilite/alertmanager/routes-tests.extrait-F2-S05.txt) à `alertmanager/routes-tests.txt` de `plateforme/observabilite`.

**4. Tableau de bord.** MR d'Inès sur `plateforme/observabilite` : [`tableaux/medivisio/medivisio-consultation.json`](fichiers/S05/observabilite/tableaux/medivisio/medivisio-consultation.json) et sa ligne de [`kustomization`](fichiers/S05/observabilite/tableaux/kustomization.extrait-F2-S05.yaml) (`grafana_folder: MédiVisio`, dossier créé en S02) — intervention de la Plateforme (relecture), notée dans la mesure.

**5. Runbook.** [`docs/runbook.md`](fichiers/S05/medivisio-consultation/docs/runbook.md) du projet du code, publié par TechDocs, lié par `pyrra.dev/runbook_url` : alerte de budget, absence de mesure, retour arrière par MR (jamais `rollout undo`), rotation de la clé, contacts.

```
admin@adm01:~$ lab/bin/check F2 05
```

**Explications**

- La recette et la production ne reconstruisent jamais l'image : la même **empreinte** traverse les environnements, ce qui a été validé est ce qui tourne.
- L'autonomie de l'équipe repose sur des objets **qu'elle possède** (ExternalSecret, SLO, ServiceMonitor, runbook) dans un cadre **qu'elle ne possède pas** (SecretStore, route d'alertes, quotas, fenêtre de synchronisation), tous deux en Git. L'AppProject interdit à l'équipe d'écrire le cadre.
- Une alerte n'a de valeur que si elle arrive : le test de routage sur la configuration **générée** (et non sur `kps/values.yaml`) vérifie ce qu'Alertmanager fait vraiment.

**Alternatives**

- SLO dans `plateforme/observabilite/slo/` (comme MédiAgenda au M21) : relu par la Plateforme, moins autonome ; utile tant qu'une équipe découvre les SLO.
- Routes d'équipe écrites par l'équipe elle-même (`AlertmanagerConfig` autorisé dans son AppProject) : plus d'autonomie (horaires, regroupements) ; risque de destinataires externes au lab.
- Tableau de bord par ConfigMap dans l'espace de l'équipe (le *sidecar* de Grafana chercherait dans tous les espaces) : plus de libre-service, moins de relecture ; la référence garde la relecture tant que les dossiers sont en lecture seule.
- Argo Rollouts (canary par la Gateway, analyse Prometheus) comme MédiAgenda : plus sûr pour la production, à faire quand la consultation aura du trafic réel.

**Pièges classiques**

- Un SLO dont les métriques n'existent pas encore (ServiceMonitor oublié, sélecteur sans `medisphere.internal/supervision: "oui"`) : Pyrra crée des règles, l'alerte `absent` sonne, mais le budget n'est jamais calculé.
- `pyrra.dev/equipe` oublié : l'alerte n'a pas d'étiquette `equipe`, la route de l'équipe ne la voit pas, elle part à la plateforme.
- Tester le routage sur le fichier de valeurs : les `AlertmanagerConfig` n'y sont pas.
- Synchroniser la production le vendredi à 17 h : refusé par la fenêtre (et c'est le but) ; prévoir la démonstration en conséquence.
- Écrire la clé de production dans une variable de CI pour « aller vite » : interdit (offre de service, § exceptions).

**En production chez MédiSphère**

Revue de mise en production (parcours d'accueil, § avant la production) signée par Inès et la Plateforme ; contact d'astreinte de MédiVisio connu de Nadia ; SLO de latence ajouté après un mois de mesures ; *game day* sur la recette (M29) avant la première campagne réelle.

---

### F2-S06 — Panne : les premiers pas qui coincent

Le script ([`pannes/break-S06.sh`](pannes/break-S06.sh)) fait **un commit de Lucas Martin** (marqueur `F2-S06`) dans l'overlay de recette de `medivisio/consultation-deploiement`, choisi parmi trois variantes, puis constate la panne sur place. Argo CD synchronise : l'Application reste `Synced`, la santé passe à `Progressing` ou `Degraded`.

**Démarche de diagnostic**

*Symptômes* : « synchronisé, mais la nouvelle version n'arrive jamais » ; la recette répond peut-être encore (anciens pods).

*Hypothèses*, dans l'ordre où on les élimine : (a) Argo CD n'a pas appliqué (non : `Synced`) ; (b) les pods ne sont pas **créés** (quota, admission) ; (c) ils sont créés mais ne **démarrent** pas (Secret, image, sondes) ; (d) l'application elle-même.

*Commandes, dans l'ordre* (RB-321) :

```
admin@adm01:~$ argocd app get medivisio-consultation-recette                         # Synced ; santé ?
admin@adm01:~$ kubectl -n medivisio-recette rollout status deploy/consultation --timeout=10s
admin@adm01:~$ kubectl -n medivisio-recette get rs,pods -l app.kubernetes.io/instance=consultation
admin@adm01:~$ kubectl -n medivisio-recette describe rs <nouveau-rs> | sed -n '/Conditions/,$p'
admin@adm01:~$ kubectl -n medivisio-recette get events --sort-by=.lastTimestamp | tail -20
admin@adm01:~$ kubectl -n medivisio-recette get externalsecrets
admin@adm01:~$ git -C ~/src/consultation-deploiement pull && git -C ~/src/consultation-deploiement log -p -3 -- overlays/recette/
```

**Variante 1 — quota de l'espace atteint.**
- *Constat* : nouveau ReplicaSet à 1 pod sur 3 (ou 2), condition `ReplicaFailure` : `pods "consultation-…" is forbidden: exceeded quota: quota, requested: requests.memory=…, used: …, limited: requests.memory=768Mi`. Les anciens pods servent encore.
- *Cause racine* : le commit relève les réplicas à 3 et les *requests* mémoire à (quota / 2 + 64 Mi) par pod : la somme dépasse le `ResourceQuota` de `medivisio-recette` (et peut-être le budget du locataire, `kubectl get globalresourcequotas`).
- *Correctif* : revert du commit (MR), ou réglage raisonnable ; si le besoin est réel, MR sur `equipes/medivisio.yaml` (quota de recette, bilan de capacité refait par la CI).
- *Prévention* : contrôle en CI du dépôt de déploiement (réplicas × *requests* ≤ quota déclaré), panneau « quota utilisé » dans le tableau de l'équipe.

**Variante 2 — image désignée par étiquette, refusée par Kyverno.**
- *Constat* : le nouveau ReplicaSet ne crée **aucun** pod ; condition `ReplicaFailure` : `admission webhook "…kyverno…" denied the request: … exiger-signature-medisphere …` (exigence d'empreinte) ; `kubectl -n medivisio-recette get policyreports` pour le détail. En dev, la même modification passerait (la politique n'y est pas appliquée) : d'où « ça marchait en dev ».
- *Cause racine* : le commit remplace `digest: sha256:…` par `newTag: v…` dans `images:` de l'overlay ; la politique exige `verifyDigest` dans les espaces étiquetés `signature-exigee`.
- *Correctif* : remettre l'empreinte (revert, ou `kustomize edit set image registry.par1.medisphere.internal/medisphere/medivisio-consultation@sha256:<EMPREINTE>` dans `overlays/recette`), MR.
- *Prévention* : la CI du dépôt de déploiement refuse un `newTag` sur une image `medisphere/*` ; expliquer à l'équipe pourquoi une étiquette n'est pas une identité (elle peut être déplacée ; l'empreinte, non).

**Variante 3 — secret hors de la politique du coffre.**
- *Constat* : un nouveau pod en `CreateContainerConfigError` (`secret "consultation-visio" not found`) ; `ExternalSecret` `consultation-visio` en `SecretSyncedError` ; `kubectl describe externalsecret consultation-visio` : `permission denied` (403) sur `kv/data/medivisio/commun/visio`. Les anciens pods servent encore.
- *Cause racine* : le commit ajoute un `ExternalSecret` vers `kv/medivisio/commun/visio` et une variable obligatoire ; le rôle `eso-medivisio-recette` ne lit que `kv/medivisio/recette/*`. Ce n'est **pas** un défaut du coffre : c'est la cloison voulue entre environnements.
- *Correctif* : ranger la clé sous `kv/medivisio/recette/visio` (Inès l'écrit, OIDC) et pointer l'`ExternalSecret` dessus (MR) ; ou retirer la modification (revert). Jamais élargir la politique `eso-medivisio-recette` à `kv/medivisio/*` : la recette lirait la production.
- *Prévention* : la CI du dépôt de déploiement vérifie que chaque `remoteRef.key` commence par `medivisio/<env-de-l-overlay>/` ; documenter « un secret commun se recopie, il ne se partage pas » (RB-321).

*Pour toutes les variantes* : la correction est un commit (la panne est un commit, la réparation aussi) ; `lab/bin/check F2 06` vérifie l'état de la recette, l'empreinte dans le Deployment **et** dans Git, les `ExternalSecret` et les livrables ([journal](fichiers/S06/medisphere/docs/accueil/journal/AAAA-MM-JJ-F2-S06-recette-medivisio-bloquee.md), [RB-321](fichiers/S06/medisphere/docs/accueil/runbooks/RB-321-premier-deploiement-bloque.md)). `lab/bin/break F2 06 --annuler` fait un commit inverse **seulement** si l'overlay est encore exactement dans l'état injecté.

**Explications**

Argo CD dit si l'état **déclaré** est appliqué, pas si l'état **voulu** est atteint : entre les deux, le contrôleur de Deployment, le ReplicaSet, l'admission (quota, Pod Security, Kyverno, Capsule) et le kubelet (Secrets, image) peuvent tous refuser. Chaque refus laisse sa trace à un endroit précis : condition du ReplicaSet et événement `FailedCreate` pour ce qui empêche la **création** ; événements du pod et statut de l'`ExternalSecret` pour ce qui empêche le **démarrage**. Dans un cadre multi-locataire, les trois causes sont des **protections qui fonctionnent** : le diagnostic se conclut par une explication à l'équipe, pas par un assouplissement.

**Alternatives**

- Corriger en relevant le quota (variante 1) par une MR sur `equipes/medivisio.yaml` : légitime **si** le besoin est réel et que le bilan de capacité le permet (la CI le recalcule) ; jamais pour faire passer un réglage arbitraire.
- Laisser la signature non exigée en recette (variante 2) et ne contrôler qu'en production : la surprise arrive alors le jour de la mise en production, au pire moment.
- Un secret « commun » réellement partagé (variante 3) : un chemin `kv/medivisio/commun/*` ajouté aux rôles `eso-medivisio-<env>` par l'équipe en code ; à décider explicitement (ADR), car il casse la cloison entre recette et production.

**Pièges classiques**

- S'arrêter à `Synced` et chercher côté Argo CD.
- « Corriger » par `kubectl edit` dans la recette : Argo CD (selfHeal) le défait ; et l'équipe n'a pas ce droit.
- Agrandir le quota, désactiver la politique Kyverno pour l'espace ou élargir la politique du coffre : on supprime la protection au lieu de corriger la demande.
- Oublier que l'ancien ReplicaSet sert encore : la recette « marche » et masque le problème jusqu'au prochain redémarrage.

**En production chez MédiSphère**

Alerte sur `kube_deployment_status_condition{condition="Progressing", status="false"}` et sur les `ReplicaFailure` des espaces d'équipe, routée vers l'équipe ; contrôles de la CI des dépôts de déploiement (composant `validation`) qui rendent ces trois erreurs impossibles à fusionner.
