# Phase 1 — Le cadre

Avant d'accueillir qui que ce soit, la Plateforme dit ce qu'elle offre, outille l'accueil d'une équipe pour qu'il tienne en un changement relu, et répond aux questions de fond qu'on lui posera : jusqu'où partager un cluster entre équipes, et avec un prestataire.

---

### F2-S01 — L'offre de service de la plateforme  `RED` `★★★`

> **Ticket PLAT-3201** — *De : Claire Morel*
> Inès m'a demandé hier ce qu'elle avait « le droit de demander ». Je n'ai pas su lui répondre en une page, et c'est un problème. Avant que les trois équipes arrivent, je veux un document qu'on puisse leur envoyer : ce que la plateforme fournit, ce qu'elle ne fournit pas, qui fait quoi, comment on nous joint, ce qu'on promet. Et une liste de contrôle d'arrivée et de départ d'une équipe, qu'on cochera pour de vrai.
> Sophie relira la partie responsabilités et exceptions, Nadia la partie support.

**Objectifs pédagogiques**
- Décrire une plateforme interne comme un produit : périmètre, promesses mesurables, limites.
- Partager clairement les responsabilités entre la plateforme et les équipes.
- Transformer un accueil d'équipe en liste de contrôle vérifiable, départ compris.

**Prérequis** : modules 19 à 28 (ce que la plateforme sait faire) ; M28-E12 (guide d'accueil d'une équipe, chemin balisé).
**Durée indicative** : 3 à 4 h.

**Contexte technique**
- Le guide d'accueil du M28 (`docs/plateforme-dev/guide-accueil-equipe.md`) décrit le chemin balisé côté développeur ; il ne dit ni ce qui est promis, ni qui est responsable de quoi, ni comment une équipe part.
- Les SLO de la plateforme n'existent pas encore : tu proposes des objectifs **mesurables avec ce qui existe** (Prometheus, sondes blackbox de `mon01`, Pyrra).
- Quotas par défaut : propose-les ici ; S02 les confrontera au bilan de capacité (et tu reviendras sur ce document si besoin).

**Travail demandé**
1. Écrire `docs/accueil/offre-de-service.md` dans `plateforme/medisphere`. Il contient au moins des sections sur : ce que la plateforme **fournit** ; ce qu'elle **ne fournit pas** ; les **responsabilités partagées** (un tableau plateforme / équipe) ; les **niveaux de service** de la plateforme (objectifs chiffrés et leur indicateur) ; les **canaux de support** (qui, comment, en combien de temps) ; les **quotas par défaut** ; le **chemin balisé** ; les **exceptions** (comment on en obtient une, ce qui n'en aura jamais).
2. Écrire `docs/accueil/parcours-accueil.md` : une liste de contrôle d'**arrivée** (avant, jour J, premiers jours, avant la production) et de **départ** (une personne, une équipe ou un prestataire), en cases à cocher, chaque ligne vérifiable.
3. Créer `docs/accueil/README.md` (index du dossier, à compléter au fil du final).
4. MR relue (Karim pour la technique ; Sophie et Nadia comme indiqué), fusion.

**Critères de réussite**
- [ ] `docs/accueil/offre-de-service.md` sur `main`, avec les huit sections demandées et au moins un objectif chiffré par service de plateforme cité.
- [ ] `docs/accueil/parcours-accueil.md` sur `main`, arrivée **et** départ, en cases à cocher.
- [ ] Rien n'y est promis que la plateforme ne sache mesurer ou faire aujourd'hui.

**Vérification** : `lab/bin/check F2 01` (présence et contenu minimal ; le fond s'auto-évalue avec le corrigé).

<details><summary>Indice 1</summary>

Pars du point de vue de l'équipe qui arrive : « que puis-je obtenir seul, que dois-je demander, que n'aurai-je jamais, et que se passe-t-il quand ça casse ? ». Chaque réponse est une section.
</details>

<details><summary>Indice 2</summary>

Un niveau de service sans indicateur n'est qu'une intention. Pour chaque objectif, écris la mesure (quelle série, quelle sonde) et la fenêtre. Pense aussi aux délais : accueillir une équipe, livrer un premier service.
</details>

<details><summary>Indice 3</summary>

Le départ est la moitié oubliée de l'accueil : jetons, sessions, certificats SSH, données à garder ou détruire, preuve que tout a été retiré.
</details>

**Pour aller plus loin** (facultatif) : la notion de *Thinnest Viable Platform* (*Team Topologies*) ; comparer ton offre à un catalogue de services ITIL et à la page de statut d'un fournisseur de cloud public.

---

### F2-S02 — Une équipe en un changement  `LIBRE` `★★★★`

> **Ticket PLAT-3202** — *De : Claire Morel*
> RB-280 décrit onze étapes dans sept dépôts. Trois équipes arrivent, une repart dans trois mois. Je veux qu'une équipe se crée — et se modifie, et parte — **en un seul changement relu**. Karim propose un fichier par équipe dans un projet `plateforme/equipes` et un modèle Backstage `nouvelle-equipe` qui ouvre la MR ; je te laisse concevoir le reste, mais tout ce qu'une équipe reçoit doit en sortir. Commence par MédiVisio (DEV-3202, Inès) et Data (DEV-3207, Hugo) ; AxiomDev viendra plus tard. Et avant de promettre des quotas, fais le compte : les travailleurs ne grandiront pas.

**Objectifs pédagogiques**
- Décrire une équipe en code et la faire appliquer par les mécanismes existants (Ansible, OpenTofu, Argo CD, API GitLab), sans identité toute-puissante.
- Raisonner capacité : *requests*, allouable, budget, surengagement, réserve.
- Concevoir l'idempotence, l'ordre d'application et le retrait d'un ensemble de ressources réparties.

**Prérequis** : S01 ; M24 (annuaire `plateforme/identite`, synchronisation GitLab, OTP), M25 (politiques, groupes externes, ESO, rôles JWT), M28 (Capsule, locataires, PriorityClasses, Backstage), M20 (AppProjects, ApplicationSets), M21 (Grafana, Alertmanager), M26 (Kyverno), M19 (composants CI).
**Durée indicative** : 10 à 14 h.

**Contexte technique**
- Format du fichier d'équipe : **fixé** (introduction, « Format de référence ») ; noms fixés : `plateforme/equipes`, `equipes/<equipe>.yaml`, modèle `nouvelle-equipe`.
- Ce que chaque équipe doit recevoir (la liste de RB-280, à reprendre) : groupe et membres dans FreeIPA (`plateforme/identite/annuaire`) ; correspondances Keycloak si besoin (OTP) ; groupe GitLab et appartenances (outil `synchro-gitlab` du M24-E11 : responsable Maintainer, développeurs Developer) ; locataire Capsule avec ses espaces, `ResourceQuota`, `LimitRange`, classes de priorité et de stockage autorisées, budget global, libre-service ; entrée de chaque espace dans le coffre (`SecretStore`, rôle `eso-<espace>`) ; politique et groupe externe OpenBao de l'équipe (`kv/<equipe>/<env>/*`) ; AppProject Argo CD (dépôts du groupe, espaces de l'équipe, rien de cluster) et accès en lecture aux dépôts du groupe ; dossier et équipe Grafana (état `observabilite-grafana`) ; route d'alertes vers l'adresse de l'équipe ; espaces de recette et de production couverts par la politique de signature de Kyverno ; entité `Group` du catalogue Backstage.
- Ce qu'une équipe ne reçoit **pas** : règle HBAC ou sudo (aucun accès SSH aux VMs), droit d'écriture direct dans ses environnements, objet de cluster.
- État actuel : la `CapsuleConfiguration` liste ses utilisateurs dans `valeurs/capsule/values.yaml` ; la politique `exiger-signature-medisphere` vise des espaces **nommés** ; le portail découvre des groupes GitLab et des groupes LDAP **nommés** ; les routes d'équipe d'Alertmanager sont écrites dans `kps/values.yaml`. Chacun de ces points demande une adaptation unique, à faire dans ce scénario.
- Bilan de capacité : `kubectl describe nodes`, `kubectl top nodes`, `GlobalResourceQuota` des locataires existants ; travailleurs à 10 Go.

**Travail demandé** (objectifs, contraintes, livrables)
1. **Bilan de capacité** des travailleurs, écrit dans `docs/accueil/capacite.md`, avec ta règle d'engagement (combien de *requests* promettre au-delà de la marge, par ressource) et les budgets que tu accordes à MédiVisio et à Data.
2. **Concevoir** le mécanisme : un fichier `equipes/<equipe>.yaml` relu en MR produit tout ce que l'équipe reçoit. Décide comment chaque brique est appliquée (par quel dépôt, quelle identité, quel ordre), ce qui est validé avant la fusion (schéma, cohérence, **capacité**), ce que le relecteur voit avant de fusionner, et ce qui se passe quand une équipe change ou part. Écris la décision dans **`docs/accueil/adr/ADR-0320-…`**.
3. **Livrer** `plateforme/equipes` (code, CI, tests) et les adaptations uniques des dépôts existants ; le modèle Backstage `nouvelle-equipe` ouvre une MR sur ce projet.
4. **Appliquer** `equipes/medivisio.yaml` (dev, recette, production) et `equipes/data.yaml` (un environnement `traitements`) par ce mécanisme, sans geste à la main dans les systèmes cibles.
5. **Runbook** `docs/accueil/runbooks/RB-320-…` : accueillir, modifier, retirer une équipe.
6. Mesurer et noter : durée entre la fusion de la MR d'une équipe et le moment où tout est appliqué.

Contraintes :
- aucune identité de CI ne peut à la fois écrire l'annuaire, le coffre et le cluster ; aucun secret en variable de CI ;
- relancer le mécanisme sans changement ne change rien (idempotence) ; une modification à la main d'un objet produit est corrigée ou signalée ;
- un retrait d'équipe retire des droits mais **ne supprime jamais** un espace, un volume ou une base sans geste explicite ;
- les quotas cumulés tiennent dans le bilan de capacité : une MR qui le dépasse est refusée par la CI ;
- les équipes historiques (`mediagenda`, `medidoc`, `medinotif`) ne perdent rien.

**Critères de réussite**
- [ ] `plateforme/equipes` existe, avec `equipes/medivisio.yaml` et `equipes/data.yaml` sur `main` ; sa CI valide et refuse un fichier invalide ou un budget qui dépasse la capacité (montré par une MR de test rouge).
- [ ] Groupes `medivisio` et `data` dans FreeIPA avec leurs membres, personnes actives ; **aucune** règle HBAC ne les cite.
- [ ] Locataires Capsule `medivisio` et `data` actifs ; espaces `medivisio-dev`, `-recette`, `-prod` et `data-traitements` rattachés, Pod Security `restricted`, chacun avec quota et `LimitRange` ; budget global et classes de priorité posés sur chaque locataire (Data : `medisphere-lot` autorisée ; MédiVisio : `medisphere-critique`).
- [ ] AppProjects `medivisio` et `data` : dépôts de leur groupe seulement, leurs espaces seulement, aucun objet de cluster.
- [ ] Coffre : groupe externe et politique de chaque équipe limitée à `kv/<equipe>/` ; rôle `eso-<espace>` pour chaque espace.
- [ ] Groupes GitLab `medivisio` et `data` : responsable Maintainer, développeur Developer.
- [ ] Entités `Group` `medivisio` et `data` au catalogue, avec leurs membres ; dossiers Grafana ; route d'alertes de MédiVisio vers `medivisio@medisphere.internal`.
- [ ] `capacite.md`, ADR-0320 et RB-320 publiés.

**Vérification** : `lab/bin/check F2 02`

<details><summary>Indice 1</summary>

Chaque brique a déjà un dépôt qui sait l'appliquer, avec ses contrôles et son identité. La question n'est pas « comment tout appliquer d'ici » mais « comment faire parvenir à chacun ce qui le concerne, de façon relisible ». Compare : appliquer depuis un pipeline central, faire lire le fichier par chaque dépôt, ou *rendre* des fichiers et les proposer par MR.
</details>

<details><summary>Indice 2</summary>

Repère les listes écrites en dur qui empêchent une nouvelle équipe d'apparaître sans toucher à un fichier partagé (utilisateurs Capsule, espaces de la politique de signature, filtre LDAP et groupes découverts du portail, routes d'Alertmanager). Les remplacer par une étiquette, un fichier rendu ou un sélecteur est le travail « une fois pour toutes ». Attention : Helm **remplace** les listes d'un fichier de valeurs à l'autre.
</details>

<details><summary>Indice 3</summary>

Pense à l'ordre et aux références : un espace rattaché à un locataire qui n'existe pas encore, un groupe GitLab absent quand la synchronisation tourne, un groupe Keycloak pas encore importé de l'annuaire quand OpenTofu le cherche, une politique OpenBao qui doit exister avant le rôle qui l'utilise. Et à la propriété : Capsule rattache un espace par une **référence de propriétaire** vers le `Tenant` (M28-E05).
</details>

**Pour aller plus loin** (facultatif) : comparer ton mécanisme à Crossplane (fiche `annexes/decouverte/crossplane.md`) et au *Capsule Proxy* ; écrire le contrôle de dérive nocturne (un objet produit modifié à la main).

---

### F2-S03 — Questions de conception : jusqu'où partager ?  `Q` `★★★`

> **Ticket PLAT-3203** — *De : Sophie Laurent*
> Avant qu'un prestataire et une équipe qui manipule des statistiques issues de données de santé entrent dans le même cluster que la production, je veux comprendre ce qui les sépare vraiment. Réponds par écrit, avec tes arguments ; on en discutera en revue d'architecture.

**Objectifs pédagogiques**
- Distinguer isolation douce et isolation forte, et situer Capsule, vCluster et le cluster dédié.
- Raisonner sur le voisin bruyant, le stockage, le coût et la conformité HDS.
- Connaître les limites d'un modèle multi-locataire par espaces.

**Prérequis** : S02 ; M28-E09, E15, E18 (vCluster, isolation des locataires) ; M26 (politiques d'admission, Falco).
**Durée indicative** : 2 à 3 h.

**Travail demandé** — réponses argumentées dans `docs/accueil/reponses/F2-S03-conception-multi-locataire.md` :

1. Qu'est-ce qui sépare **aujourd'hui**, concrètement, un pod de `data-traitements` d'un pod de `mediagenda-prod` ? Liste les barrières (identité, API, réseau, nœud, noyau, stockage) et dis lesquelles sont « douces ».
2. Un traitement de Data sature le CPU d'un travailleur la nuit. Qu'est-ce qui protège MédiAgenda en production, et qu'est-ce qui ne la protège pas ? Même question pour la mémoire, puis pour les entrées-sorties disque sur Ceph.
3. AxiomDev : locataire Capsule partagé (un espace dans `mediagenda`), vCluster, ou cluster dédié ? Donne ton choix et ses conditions.
4. Même question pour une hypothétique équipe qui traiterait des **données de santé identifiantes** pour la recherche : qu'exige HDS, et lequel des trois modèles retiens-tu ?
5. Les quotas de stockage : que limite `requests.storage` d'un `ResourceQuota`, que ne limite-t-il pas (instantanés, sauvegardes, objets S3) ? Comment borner la consommation de Ceph par équipe ?
6. Pourquoi un locataire Capsule ne peut-il pas installer sa propre CRD, son propre opérateur ou son propre webhook d'admission ? Que répondrais-tu à Inès qui veut « juste installer un opérateur Redis » ?
7. Un budget de locataire est un plafond de *requests*. Pourquoi peut-on, ou non, promettre plus que la capacité ? Quel lien avec les classes de priorité ?
8. Qui « possède » quoi dans ton mécanisme de S02 : le fichier d'équipe, le locataire, les espaces, les objets déployés dans les espaces, les secrets ? Qui peut modifier quoi, et comment le voit-on ?
9. Coût : comment répartirais-tu le coût de la plateforme entre équipes (*showback*) ? Sur les *requests*, l'utilisation, les quotas ? Quels effets pervers chaque choix encourage-t-il ?
10. Une équipe demande un `ClusterRole` pour lister les nœuds « pour son tableau de bord ». Que réponds-tu, et quelle alternative proposes-tu ?
11. Les webhooks de Capsule tombent. Que se passe-t-il pour chaque équipe, pour la production, pour la plateforme ? Est-ce acceptable ?

**Vérification** : pas de script (auto-évaluation avec le corrigé).

<details><summary>Indice 1</summary>

Classe chaque barrière selon ce qu'un attaquant **dans** un pod du locataire peut tenter : parler à l'API, parler au réseau, s'échapper sur le nœud, lire le disque d'un autre. Le noyau partagé est la limite de tout modèle « un cluster, plusieurs espaces ».
</details>

<details><summary>Indice 2</summary>

Pour le voisin bruyant : *requests* (ordonnancement), *limits* (CPU étranglé, mémoire tuée), classes de QoS, priorités et préemption ne protègent pas de la même chose. Les entrées-sorties Ceph ne sont bornées par aucun de ces mécanismes.
</details>

**Pour aller plus loin** (facultatif) : Kubernetes, *Multi-tenancy* (<https://kubernetes.io/docs/concepts/security/multi-tenancy/>) ; gVisor et Kata Containers ; référentiel HDS (activités 1 à 6) et ce qu'il dit de la séparation des environnements.
