# Final F2 — Phase 1 : le cadre — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Validé hors du lab** (à la rédaction, 23/10/2026) :
- Le générateur de `plateforme/equipes` (`outils/rendre.py`, `capacite.py`) a été exécuté sur les deux fichiers d'équipe de référence : validation par le schéma JSON (draft 2020-12, `jsonschema` 4.26), contrôles de cohérence, rendu des 21 fichiers de [`rendu-exemple/`](fichiers/S02/rendu-exemple/) (tous relus comme YAML ou JSON), bilan de capacité ; 8 tests `pytest` verts ; `ruff check` et `ruff format --check` propres. Le CronJob de rattachement (script POSIX) passe `shellcheck -s sh`.
- `freeipa.ansible_freeipa.ipauser` : paramètre `principalexpiration`, formats `AAAA-MM-JJ HH:MM:SSZ` (documentation du module).
- Champs du `Tenant` Capsule 0.15 (`priorityClasses`, `storageClasses`, `rules[].quota`, `rules[].enforce`, `preventDeletion`, `forceTenantPrefix`, `additionalMetadataList`) et `GlobalTenantResource` : repris tels quels du M28 (vérifiés sur la CRD du chart 0.15.1 à la rédaction du module) ; ApplicationSet : `goTemplate`, `goTemplateOptions`, générateurs `matrix`, `git` (`files`), `list`, `templatePatch`, `syncPolicy.preserveResourcesOnDeletion` (documentation d'Argo CD) ; `applicationsSync` exige `--enable-policy-override` du contrôleur, d'où son absence.

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- la propagation de bout en bout (`propager.py` contre GitLab 19.5 : commits à actions multiples, `auto_merge` sur les MR de `svc-equipes`, fermeture des MR remplacées), les jetons de groupe (`/groups/:id/access_tokens`, `/groups/:id/deploy_tokens`) créés par un **compte de service** ;
- la fusion par l'opérateur de prometheus-operator 0.94 des `AlertmanagerConfig` rendus (stratégie `OnNamespace` par défaut, `continue` forcé au premier niveau, noms de récepteurs préfixés `<espace>/<objet>/<récepteur>`) : à confirmer par `GET /api/v2/status` après la première synchronisation ;
- la découverte GitLab de Backstage 1.56 **sans** `group` (toute l'instance) et le filtre LDAP par exclusion ; l'image `clastix/kubectl` du CronJob de rattachement (présence de `/bin/sh`) ;
- les règles `rules:changes:` + `$CI_COMMIT_MESSAGE` des pipelines cibles sur un commit de fusion (modèle de message de fusion par défaut).

**Fichiers** : [`fichiers/S01/`](fichiers/S01/) (documentation) ; [`fichiers/S02/equipes/`](fichiers/S02/equipes/) = le projet `plateforme/equipes` complet ; [`fichiers/S02/cibles/`](fichiers/S02/cibles/) = les changements faits **une fois** dans les dépôts existants (`identite/`, `secrets/`, `infra/`, `k8s/`, `gitops/`, `observabilite/`, `politiques/`, `portail/` ; les `*.extrait*` se fusionnent dans le fichier existant, l'emplacement est dit en tête) ; [`fichiers/S02/portail-modeles/`](fichiers/S02/portail-modeles/) = le modèle `nouvelle-equipe` ; [`fichiers/S02/rendu-exemple/`](fichiers/S02/rendu-exemple/) = ce que le générateur produit pour `medivisio` et `data` ; [`fichiers/S02/medisphere/`](fichiers/S02/medisphere/) = ADR-0320, RB-320, `capacite.md`.

---

### F2-S01 — L'offre de service de la plateforme

**Solution**

Documents de référence : [`offre-de-service.md`](fichiers/S01/medisphere/docs/accueil/offre-de-service.md) et [`parcours-accueil.md`](fichiers/S01/medisphere/docs/accueil/parcours-accueil.md). Leur construction :

1. **Partir de l'équipe qui arrive**, pas du catalogue des outils : « que puis-je faire seul, que dois-je demander, que n'aurai-je jamais, que se passe-t-il quand ça casse, comment je pars ». Chaque question donne une section.
2. **Ce qui est fourni** : par domaine (identité, code, images, exécution, déploiement, exposition, secrets, observabilité, portail, sauvegarde, sécurité), avec le **comment** (fichier d'équipe, composant, dépôt). Un service qu'on ne sait pas obtenir n'est pas fourni.
3. **Ce qui ne l'est pas** est aussi important : pas de cluster dédié, pas de base en libre-service pour les équipes produit, pas d'accès aux données de production pour qui ne l'exploite pas, pas de SSH, pas d'astreinte applicative. Cela coupe court aux demandes qui finissent en exceptions.
4. **Responsabilités partagées** en tableau, ligne par sujet. Les lignes qui comptent : vulnérabilités de l'image (la plateforme alerte, l'équipe corrige), données applicatives (la plateforme sauvegarde l'infrastructure, l'équipe gère schéma et purge RGPD), incident applicatif (l'équipe d'abord), accès des personnes (le responsable déclare, la plateforme applique).
5. **Niveaux de service** chiffrés et **mesurables aujourd'hui** : chaque objectif a son indicateur (série Prometheus, sonde blackbox de `mon01`) et sa fenêtre (28 j comme les SLO du M21). Deux délais d'accueil : équipe prête en un jour ouvré, premier déploiement en un jour ouvré (mesuré en S04).
6. **Support** : par type de besoin (question, changement, incident plateforme, incident applicatif, sécurité), canal et délai.
7. **Quotas par défaut** : les valeurs que S02 confronte au bilan de capacité (et qui changent si le bilan l'impose : la cohérence entre les deux documents fait partie de la relecture).
8. **Exceptions** : demandées, justifiées, bornées dans le temps, validées, inscrites ; et la liste de ce qui n'en aura **jamais** (données de santé hors production, secrets dans Git, prestataire sans date de fin…).

Le parcours d'accueil est une **liste de contrôle cochée pour de vrai** dans le ticket d'arrivée : avant (J-5), jour J (Plateforme), premiers jours (équipe + parrain), avant la production (revue), après un mois ; et le départ (personne, équipe, prestataire) avec preuves.

```
admin@adm01:~/medisphere$ git switch -c conf/f2-s01-offre-de-service
admin@adm01:~/medisphere$ mkdir -p docs/accueil && $EDITOR docs/accueil/{README,offre-de-service,parcours-accueil}.md
admin@adm01:~/medisphere$ git add docs/accueil && git commit -m "docs(accueil): offre de service et parcours d'accueil (PLAT-3201)"
admin@adm01:~/medisphere$ git push -u origin conf/f2-s01-offre-de-service    # MR, relecture Karim, Sophie, Nadia
admin@adm01:~$ lab/bin/check F2 01
```

**Explications**

Une plateforme interne est un **produit** dont les clients ne peuvent pas partir (*Team Topologies*, « X-as-a-Service ») : sans offre écrite, chaque équipe négocie au cas par cas, la plateforme devient un guichet et ses promesses implicites (« c'est sauvegardé ») sont fausses à moitié. L'offre fixe aussi ce que la plateforme **mesure** : un niveau de service non mesuré se discute, un niveau mesuré se constate.

**Alternatives**

- Un catalogue de services ITIL complet (fiches par service, OLA/SLA) : plus formel, adapté à une DSI de grande taille ; lourd pour quatre équipes.
- Mettre l'offre dans le portail (TechDocs de `plateforme/medisphere`) : souhaitable, en plus du fichier ; le document reste la référence relue.
- Des niveaux de service **par environnement** (production seulement) : plus honnête pour la recette, qui peut être interrompue sans préavis ; à ajouter en v2.

**Pièges classiques**

- Promettre ce qu'on ne mesure pas (« disponibilité 99,9 % » sans sonde) ou ce qu'on ne fait pas (« sauvegarde de tout », alors que le libre-service n'est pas sauvegardé).
- Oublier ce qui n'est **pas** fourni : la première exception devient la règle.
- Un parcours d'arrivée sans départ : les comptes de prestataires restent actifs après le contrat.
- Des quotas par défaut écrits avant le bilan de capacité, jamais revus.

**En production chez MédiSphère**

Revue trimestrielle de l'offre avec les responsables d'équipe, rapport mensuel des niveaux de service publié dans le portail, enquête de satisfaction après chaque arrivée (S14). Les engagements de la plateforme envers la production (MédiAgenda, MédiVisio) remontent dans le PAS HDS et le registre des risques.

---

### F2-S02 — Une équipe en un changement

**Solution de référence** (il en existe d'autres : voir Alternatives). Décision : [ADR-0320](fichiers/S02/medisphere/docs/accueil/adr/ADR-0320-equipe-en-code.md). Procédure : [RB-320](fichiers/S02/medisphere/docs/accueil/runbooks/RB-320-accueillir-une-equipe.md).

**1. Bilan de capacité** ([`capacite.md`](fichiers/S02/medisphere/docs/accueil/capacite.md)).

```
admin@adm01:~$ kubectl describe nodes -l '!node-role.kubernetes.io/control-plane' | grep -A8 'Allocated resources'
admin@adm01:~$ kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o custom-columns=NOM:.metadata.name,CPU:.status.allocatable.cpu,MEM:.status.allocatable.memory
admin@adm01:~$ kubectl get globalresourcequotas
admin@adm01:~$ kubectl top nodes
```

Règle retenue : un budget est une **promesse** ; CPU engagé jusqu'à 1,5 × la marge (compressible), mémoire 1,0 × (non compressible), pas de réserve N-1 dans le lab (risque écrit). Avec l'exemple du corrigé (marge 3,6 CPU et 8 Gi), MédiVisio reçoit 2,5 CPU / 3 Gi et Data 2 CPU / 3,5 Gi : 4,5 CPU ≤ 5,4 et 6,5 Gi ≤ 8 Gi. **Tes** chiffres remplacent ceux-ci dans `config/plateforme.yaml`.

**2. Le mécanisme : fichier, rendu, propagation.**

```
plateforme/equipes (MR relue)
  ├─ valider    schéma JSON + cohérence (rendre.py --valider), tests
  ├─ capacite   budgets contre le relevé (bloquant)
  ├─ rendre     rendu complet et déterministe → rendu/<cible>/…
  ├─ apercu     (MR) diff par dépôt cible + ce qui sera créé dans GitLab
  └─ main : gitlab:equipes (groupe, <equipe>/gitops, jetons → OpenBao) → propager (une MR par dépôt cible)
                    │
     ┌──────────────┼──────────────┬───────────────┬────────────────┐
  identite        secrets        infra (Grafana)    k8s             gitops
  annuaire:       tofu:apply:    tofu apply         Argo CD          Argo CD
  appliquer +     equipes        (même règle)       equipes-k8s      equipes-gitops, capsule
  synchro:gitlab  (sans destruction)
```

Les pièces (toutes dans [`fichiers/S02/equipes/`](fichiers/S02/equipes/)) :

| Fichier | Rôle |
|---|---|
| [`schema/equipe.schema.json`](fichiers/S02/equipes/schema/equipe.schema.json) | le contrat (format v1 de l'introduction), règles prestataire comprises (`expiration`, OTP, compte externe) ; étendu ensuite par S07 (`base_openbao`) et S10 (`hebergement`), voir [README](fichiers/S02/equipes/README.md) § Évolutions du format |
| [`config/plateforme.yaml`](fichiers/S02/equipes/config/plateforme.yaml) | noms réservés, relevé de capacité et ratios, cibles et **chemins possédés**, comptes de service des groupes |
| [`outils/rendre.py`](fichiers/S02/equipes/outils/rendre.py) | validation, contrôles (budget ≥ quotas, responsable, préfixes, `ci` réservé…), rendu |
| [`gabarits/`](fichiers/S02/equipes/gabarits/) | `Tenant`, espace (Namespace + `ResourceQuota` + `LimitRange` + `SecretStore` + lecture de supervision + `AlertmanagerConfig`), cloison Cilium, AppProject, ApplicationSet, identifiants de dépôt, utilisateurs Capsule |
| [`outils/capacite.py`](fichiers/S02/equipes/outils/capacite.py) | bilan des budgets (tableau Markdown, artefact de la MR) |
| [`outils/gitlab_equipes.py`](fichiers/S02/equipes/outils/gitlab_equipes.py) | groupe, projet `<equipe>/gitops`, `svc-portail` membre, jetons de groupe rangés dans le coffre, révocation au départ |
| [`outils/propager.py`](fichiers/S02/equipes/outils/propager.py) | diff (aperçu) ou commit + MR + `auto_merge` par dépôt cible |
| [`.gitlab-ci.yml`](fichiers/S02/equipes/.gitlab-ci.yml) | étapes ci-dessus ; identité : rôle JWT `ci-plateforme-equipes` |
| [`tests/test_rendre.py`](fichiers/S02/equipes/tests/test_rendre.py) | budget dépassé, nom réservé, responsable absent, rendu complet, équipe retirée |

**3. Les adaptations uniques** ([`fichiers/S02/cibles/`](fichiers/S02/cibles/)), une MR par dépôt, avant la première équipe :

| Dépôt | Changement | Pourquoi |
|---|---|---|
| `plateforme/identite` | `annuaire.yml` lit `annuaire/equipes/*.yml` (listes fusionnées, expiration des principaux) ; `synchro-gitlab.py` lit `synchro-gitlab.d/` et accepte des lignes **par personne** ; `flux.tf` : `groupes_otp_equipes` ; règles CI d'application automatique des rendus, avec garde-fou (auteur, chemins) | l'annuaire et GitLab restent appliqués par leur dépôt |
| `plateforme/secrets` | [`tofu/equipes.tf`](fichiers/S02/cibles/secrets/tofu/equipes.tf) + gabarits de politiques ; rôle `ci-plateforme-equipes` ; `ci-signature` accepte les groupes d'équipe qui ont des services ; `tofu:apply:equipes` automatique **sauf destruction** | le coffre reste appliqué par son état OpenTofu |
| `plateforme/infra` | [`observabilite-grafana/equipes.tf`](fichiers/S02/cibles/infra/observabilite-grafana/equipes.tf) : `local.toutes_equipes` | dossiers et équipes Grafana du M21-E17 |
| `plateforme/k8s` | [`locataires/rattachement.yaml`](fichiers/S02/cibles/k8s/locataires/rattachement.yaml) : CronJob qui pose la référence de propriétaire des espaces d'équipe | généralise `rattacher-locataires.sh` (M28-E05) |
| `plateforme/gitops` | [`plateforme/equipes.yaml`](fichiers/S02/cibles/gitops/plateforme/equipes.yaml) : Applications `equipes-k8s` et `equipes-gitops` ; second fichier de valeurs de Capsule ; `manager.options.users` retiré de `values.yaml` | Helm remplace les listes : une seule source pour les utilisateurs Capsule |
| `plateforme/observabilite` | [`kps/values`](fichiers/S02/cibles/observabilite/kps/values.extrait-F2-S02.yaml) : `alertmanagerConfigSelector` et `alertmanagerConfigNamespaceSelector` | routes d'équipe sans toucher `alertmanager.config` |
| `plateforme/politiques` | [`exiger-signature-medisphere`](fichiers/S02/cibles/politiques/kyverno/images/exiger-signature-medisphere.extrait-F2-S02.yaml) : sélection par étiquette `medisphere.internal/signature-exigee=oui` (migration sans trou décrite dans le fichier) | une nouvelle équipe est couverte dès sa création |
| `plateforme/portail` | [`app-config`](fichiers/S02/cibles/portail/app-config.production.extrait-F2-S02.yaml) : découverte de toute l'instance, groupes LDAP par exclusion | une équipe apparaît au catalogue sans toucher au portail |
| `plateforme/portail-modeles` | modèle [`nouvelle-equipe`](fichiers/S02/portail-modeles/modeles/nouvelle-equipe/template.yaml) | interface : écrit le fichier et ouvre la MR |

Identités : compte de service GitLab `svc-equipes` (droit de créer des groupes, Developer des cinq dépôts cibles, autorisé à fusionner dans `main` par MR) ; son jeton dans `kv/plateforme/equipes/gitlab` ; politique [`ci-plateforme-equipes`](fichiers/S02/cibles/secrets/politiques/ci-plateforme-equipes.hcl).

```
admin@adm01:~$ bao login -method=oidc                                     # toi, plateforme-admins
admin@adm01:~$ bao kv put kv/plateforme/equipes/gitlab jeton=-            # jeton de svc-equipes, collé sur l'entrée standard
```

**4. Appliquer MédiVisio et Data.**

```
admin@adm01:~/src/equipes$ git switch -c conf/equipes-medivisio-data
admin@adm01:~/src/equipes$ uv run outils/rendre.py --valider && uv run outils/capacite.py && uv run pytest -q
admin@adm01:~/src/equipes$ git add equipes/ && git commit -m "feat(equipes): medivisio et data (DEV-3202, DEV-3207)" && git push -u origin HEAD
#   MR : lire capacite.md et apercu.diff ; relecture Karim ; fusion
#   main : gitlab:equipes, puis propager (artefact propagation.txt : 5 MR)
admin@adm01:~$ for p in identite secrets infra k8s gitops; do glab mr list -R plateforme/$p --label equipe-en-code; done
admin@adm01:~$ kubectl get tenants medivisio data && kubectl get ns -l medisphere.internal/origine=plateforme-equipes
[admin@ipa01 ~]$ kinit admin && ipa passwd ines.garnier && kdestroy   # premier mot de passe expiré d'office (RB-241), canal séparé ; idem pour les trois autres
admin@adm01:~$ lab/bin/check F2 02
```

Mesure (exemple) : fusion → tout appliqué en ≈ 20 min, dont 5 à 15 min d'attente du CronJob de rattachement et de la synchronisation du catalogue (30 min au pire pour l'entité `Group`).

**Explications**

- **Un fichier, plusieurs appliqueurs.** Chaque brique garde le dépôt, l'identité et les contrôles qui l'appliquent déjà (plans OpenTofu enregistrés, `--check --diff` d'Ansible, Argo CD). Le projet `plateforme/equipes` n'a **aucun** droit sur l'annuaire, le coffre (hors jetons de groupe) ni le cluster : il écrit dans GitLab. Le rayon d'action d'une erreur est celui d'une MR.
- **Rendu complet, chemins possédés.** Le générateur produit toujours l'ensemble des équipes ; `propager.py` compare ce rendu à ce qui est dans les chemins qu'il possède et en déduit créations, modifications **et suppressions** : une équipe retirée disparaît des fichiers sans liste à tenir. Le reste des dépôts lui est interdit (contrôle dans `propager.py`, et garde-fou des pipelines cibles).
- **Relu une fois, appliqué sans clic, sauf destruction.** La MR d'équipe est le changement relu ; les MR de propagation sont un changement standard pré-approuvé, appliqué automatiquement si son auteur et ses chemins sont les bons et si aucun plan ne détruit. Une destruction (départ) attend une lecture humaine.
- **Ordre.** Le groupe GitLab est créé avant la propagation (la synchronisation des appartenances l'exige) ; le `Tenant` a une vague Argo CD avant les espaces ; le rattachement (référence de propriétaire, qui contient l'UID du `Tenant`) se fait **après**, par le CronJob, seulement si le `Tenant` est protégé ; un groupe Keycloak n'existe qu'après sa synchronisation depuis l'annuaire (OTP des prestataires, RB-320 étape 8).
- **Les listes en dur deviennent des sélecteurs** : utilisateurs Capsule (fichier rendu complet), politique de signature (étiquette), portail (instance entière, exclusion), routes d'alertes (`AlertmanagerConfig` dans l'espace, filtre `namespace` imposé par l'opérateur : une équipe ne reçoit que ses alertes).
- **Données jamais détruites par un automate** : `Tenant` `preventDeletion` + `Prune=false,Delete=false`, espaces `Prune=false,Delete=false`, ApplicationSet `preserveResourcesOnDeletion`.

**Alternatives**

- **Pipeline central qui applique tout** (Ansible + OpenTofu + `kubectl` + API GitLab) : plus rapide, mais une identité capable de tout, deux chemins d'application pour les mêmes objets et deux états OpenTofu. Écarté (ADR-0320).
- **Les dépôts cibles lisent le fichier d'équipe eux-mêmes** (sous-module Git, `yamldecode(file())` sur une copie) : pas de MR de propagation, mais aucun diff relu dans le dépôt qui applique, et une dépendance de chaque pipeline au format.
- **Opérateur maison** (une CRD `Equipe` dans le cluster) ou **Crossplane** : élégant pour la partie Kubernetes, mais l'annuaire, le coffre et GitLab restent hors du cluster ; aucun fournisseur Crossplane maintenu pour FreeIPA ou OpenBao.
- **Groupe de l'annuaire par rôle** (`medivisio-responsables`) au lieu de lignes par personne dans la synchronisation : sans modification de l'outil, mais deux fois plus de groupes dans le coffre, le portail et la revendication `groups`.
- **Un espace par service** (modèle du M28) plutôt qu'un espace par environnement d'équipe : isolation plus fine, mais quotas, coffre et alertes à poser à chaque service (ADR-0321, S04).
- **Rôles CI par projet** (`project_id`, comme au M25) : plus robustes au renommage, mais l'identifiant n'existe qu'après la création du projet par l'équipe ; la solution lie le rôle au chemin (`project_path`), risque accepté.

**Pièges classiques**

- Laisser `manager.options.users` dans `values.yaml` **et** le fichier rendu : Helm prend la dernière liste ; selon l'ordre des fichiers, `oidc:mediagenda` disparaît et l'équipe ne peut plus créer d'espace de libre-service.
- Supprimer le `Tenant` d'une équipe (ou l'Application qui le porte, avec finaliseur) : **suppression en cascade** de ses espaces, production comprise.
- Un espace avec l'étiquette `capsule.clastix.io/tenant` mais sans référence de propriétaire : Capsule ne le compte pas dans le locataire (`status.namespaces`), ni ses règles, ni son budget.
- `blockOwnerDeletion: true` posé par un compte sans `update` sur `tenants/finalizers` : refus de l'apiserver.
- Une destination d'AppProject en `<equipe>-*` : une future équipe `<equipe>-xxx` y aurait accès.
- Politique d'équipe qui couvre `kv/<equipe>/*` : l'équipe lit `kv/<equipe>/ci/promotion` (jeton d'API de groupe).
- `data "keycloak_group"` sur un groupe pas encore importé de l'annuaire : le plan échoue (RB-320).
- Oublier les contrôles négatifs : une équipe qui « voit tout » passe tous les contrôles positifs.
- Promettre des quotas sans bilan : la première montée en charge d'une équipe met en `Pending` les pods d'une autre.

**En production chez MédiSphère**

Contrôle de dérive nocturne (rendu de `main` contre l'état des dépôts cibles et du cluster) ; revue d'accès trimestrielle alimentée par les fichiers d'équipe (le modèle de l'outil `revue-acces` du M24-E30 lirait les groupes d'équipe) ; quotas relus contre les recommandations du VPA ; réserve N-1 réelle (un quatrième travailleur) avant d'engager plus de 70 % de la mémoire ; le modèle `nouvelle-equipe` réservé aux responsables d'équipe, la MR restant relue par la Plateforme.

---

### F2-S03 — Questions de conception : jusqu'où partager ?

Réponses de référence (à rédiger dans `docs/accueil/reponses/F2-S03-conception-multi-locataire.md`).

**1. Ce qui sépare `data-traitements` de `mediagenda-prod`.**
- *Identité et API* : RBAC (l'équipe Data n'a que `view` sur ses espaces et `admin` sur son libre-service ; aucun droit sur `mediagenda-*`), Capsule (création d'espaces préfixés), AppProject (destinations) : barrière **forte pour l'API**, tant que le RBAC est juste.
- *Réseau* : cloison `isolement-locataire-data` (refus Cilium entre locataires) et politiques par défaut : forte au niveau L3/L4, **douce** au sens où une erreur de politique l'ouvre.
- *Admission* : Pod Security `restricted`, Kyverno : empêche les pods privilégiés, `hostPath`, `hostNetwork`.
- *Nœud et noyau* : **partagés** (même noyau, même kubelet, même runtime). Une faille d'évasion de conteneur franchit tout le reste : c'est la barrière la plus faible, et la raison de parler d'isolation **douce**.
- *Stockage* : volumes RBD distincts par PVC, mais même grappe Ceph ; les entrées-sorties sont partagées.
Les autres réponses sont fausses si elles présentent l'espace de noms comme une frontière de sécurité en soi : c'est un nom, les barrières sont les politiques qui s'y appuient.

**2. Voisin bruyant.**
- *CPU* : les *requests* garantissent une part (poids `cpu.weight` du cgroup) ; un pod de Data sans *limit* peut consommer le CPU libre, mais quand MédiAgenda le réclame, il retrouve sa part. La classe `medisphere-critique` permet en plus de **préempter** des pods moins prioritaires si la production ne peut pas être ordonnancée. Ne protège pas : la latence de l'ordonnanceur CFS en cas de forte contention, ni le CPU du nœud consommé hors des cgroups des pods.
- *Mémoire* : non compressible ; un pod qui dépasse sa *limit* est tué (OOM) ; si le nœud manque de mémoire, le kubelet évince d'abord les pods `BestEffort` puis `Burstable` qui dépassent leurs *requests*. Une production avec *requests* = *limits* (`Guaranteed`) est évincée en dernier. D'où la règle « mémoire jamais surengagée ».
- *E/S Ceph* : **aucun** mécanisme de Kubernetes ne les borne ; une requête massive de Data sur sa base peut ralentir les OSD partagés. Leviers : pool ou classe de stockage séparés, QoS RBD (`rbd_qos_*` par image), horaires de traitements, réplica de lecture.

**3. AxiomDev.** Choix de référence : **un espace dans le locataire `mediagenda`** (`mediagenda-axiomdev`), parce que le prestataire travaille sur le code de MédiAgenda, sans données réelles, en développement seulement, et pour trois mois. Conditions : comptes datés et OTP, RBAC limité à cet espace, aucun accès à `*-recette`/`*-prod` ni au coffre, cloison réseau vers le reste, revue d'accès, départ outillé (S10 à S12). Un vCluster se justifierait si AxiomDev devait installer des CRD ou des opérateurs ; un cluster dédié, s'il manipulait des données réelles ou si le contrat exigeait une isolation forte.

**4. Données de santé identifiantes pour la recherche.** HDS impose de maîtriser l'accès, la traçabilité, la séparation des environnements et le chiffrement ; l'isolation douce (noyau partagé avec des équipes moins sensibles) est difficile à justifier à l'audit. Choix : **cluster dédié** (ou au minimum des nœuds dédiés avec marques et affinités, et un pool Ceph dédié chiffré), accès nominatifs avec OTP, journalisation dans le locataire Loki `audit`, sauvegardes séparées. Un vCluster ne règle rien : ses pods tournent sur les nœuds partagés de l'hôte.

**5. Quotas de stockage.** `requests.storage` borne la somme des **demandes** des PVC d'un espace ; `persistentvolumeclaims` leur nombre ; `<classe>.storageclass.storage.k8s.io/requests.storage` par classe. Ne sont pas comptés : les instantanés de volumes, les sauvegardes Velero et CNPG sur `s3-01`, les objets S3 du RGW, l'espace réellement écrit (*thin provisioning* : un PVC de 40 Gi peut n'en occuper que 2). Borner Ceph par équipe : quotas de pool (`ceph osd pool set-quota`) si chaque équipe a son pool, quotas d'utilisateur ou de compartiment RGW (`radosgw-admin quota set`), et supervision de l'occupation réelle par PVC (kubelet `volume_stats`).

**6. CRD, opérateur, webhook.** Les CRD, ClusterRoles, webhooks d'admission et APIService sont des objets **de cluster** : ils s'appliquent à tous les locataires (une CRD est globale, un webhook peut intercepter les objets de tout le monde). Les donner à un locataire, c'est lui donner la plateforme. À Inès : un Redis géré par la plateforme (offre de service : sur demande), ou Valkey en StatefulSet simple dans ses espaces (chart ou manifestes, sans opérateur) ; si un opérateur est vraiment nécessaire, la plateforme l'installe pour tous et en assure le cycle de vie, ou l'équipe prend un vCluster.

**7. Promettre plus que la capacité.** Le budget borne les *requests* : il ne réserve rien. Promettre plus que la marge (surengagement) parie que toutes les équipes n'atteindront pas leur plafond en même temps. Raisonnable pour le CPU (compressible), dangereux pour la mémoire (pods `Pending` ou évictions). Les classes de priorité disent **qui perd** quand le pari échoue : la production (`medisphere-critique`) préempte le reste, les lots (`medisphere-lot`, `Never`) attendent.

**8. Qui possède quoi.** Le fichier d'équipe : la Plateforme (relit, fusionne) ; l'équipe propose. Le locataire et les espaces d'environnement : la Plateforme (rendus, livrés par Argo CD, `Prune=false`). Les objets déployés dans les environnements : l'équipe, par son dépôt de déploiement et Argo CD. Le libre-service : l'équipe (administratrice, peut supprimer). Les secrets : l'équipe écrit ses valeurs, la Plateforme fixe les chemins et les droits. On le voit : `medisphere.internal/origine` et l'annotation de suivi d'Argo CD sur chaque objet, l'historique Git, l'audit d'OpenBao.

**9. Coût (*showback*).** Sur les **requests** : simple, incite à demander juste ; mais pénalise une équipe prudente. Sur l'**utilisation** : juste en apparence, mais pousse à sous-déclarer les *requests* (et à dégrader l'ordonnancement). Sur les **quotas** : reflète la capacité gelée par la promesse, pousse à demander petit puis à revenir. Pratique courante : `max(requests, utilisation)` par heure, plus le stockage provisionné ; montré (*showback*) avant d'être facturé (*chargeback*). F2-S08 le met en œuvre.

**10. `ClusterRole` pour lister les nœuds.** Refus : la liste des nœuds révèle la topologie, les adresses, les marques, et n'est pas nécessaire à une équipe. Alternative : un tableau Grafana de la plateforme (nœuds, capacité, par locataire) en lecture, ou les métriques de kube-state-metrics filtrées par espace ; si le besoin persiste, une vue agrégée sans détail.

**11. Webhooks de Capsule indisponibles.** Avec `failurePolicy: Fail` (M28) : plus aucune création ni modification d'espace dans tout le cluster, et, pour les objets des espaces rattachés interceptés par les webhooks (pods, PVC…), refus de création — production comprise si elle redémarre un pod. Les pods déjà en marche continuent. C'est acceptable seulement parce que Capsule est surveillé (alerte sur la disponibilité de son webhook), redondant (deux réplicas) et que le runbook de M28-E21 sait le rétablir ; l'alternative `Ignore` ouvrirait une fenêtre où les règles des locataires ne s'appliquent plus.
