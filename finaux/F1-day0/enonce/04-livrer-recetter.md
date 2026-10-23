# Final F1 — Phase 4 : Livrer et recetter

Le cluster est revenu, les données aussi, et l'incident d'après-reconstruction est clos. Reste à prouver que la plateforme reconstruite n'est pas une vitrine : une **vraie livraison** doit traverser toute la chaîne (MR, CI, image signée, promotion, Argo CD, canary en production) sans que personne ne touche au cluster à la main. Puis la **recette** : tous les contrôles d'entrée des finaux au vert, sur un cluster qui a moins d'une semaine. Enfin, ce que Sophie Laurent montrera à l'auditeur HDS : un rapport chiffré, un runbook exécutable et une décision pour faire mieux la prochaine fois.

> **Rappels** : la fenêtre CHG-3107 est **fermée** à la réouverture du service (S11). À partir d'ici, les règles ordinaires de production s'appliquent : aucun `kubectl` d'écriture sur les espaces applicatifs (Argo CD seul), aucune expérience de chaos hors recette, toute modification par MR relue.

---

### F1-S13 — Première livraison en production  `LIBRE` `★★★`

> **Demande DEV-3113** — *De : Julien Petit*
> Les centres de santé nous demandent depuis des semaines d'afficher le **nombre** de créneaux libres à côté de la liste, sans avoir à les compter côté client. C'est une petite évolution de l'API (le champ `nombre` dans la réponse de `/api/v1/creneaux`), compatible avec les clients actuels. Elle était prête avant la fenêtre ; je veux qu'elle soit la première chose livrée sur la plateforme reconstruite, **par le chemin normal**, avec le canary en production. Si quelque chose casse dans la chaîne, c'est maintenant qu'on veut le savoir, pas un vendredi soir.

**Objectifs pédagogiques**
- Faire traverser toute la chaîne de livraison à une évolution réelle sur une plateforme reconstruite : MR, composants CI/CD, image signée et attestée, promotion par MR, Argo CD, canary piloté par Argo Rollouts et analysé par Prometheus.
- Repérer ce que la reconstruction a cassé dans la chaîne (identités, runners, signatures, webhooks, analyses) et le réparer par le code.
- Observer le SLO pendant et après la mise en production.

**Prérequis** : F1-S12 (panne close) ; modules 17 (chart, Kustomize), 19 (composants CI/CD, runners `k8s-par1` et `k8s-par1-protege`, signature, promotion par MR du compte `ci-promotion`), 20 (Argo CD, ApplicationSet `mediagenda`, Argo Rollouts et le plugin Gateway API), 21 (SLO, analyses Prometheus), 25 (signature par la clé `transit/cosign-medisphere`), 26 (Kyverno : signature et attestation SBOM exigées en recette et en production), 27 (migrations Flyway, hook Sync vague −1).
**Durée indicative** : 3 à 4 h.

**Contexte technique**
- L'évolution est fournie : [`ressources/S13/`](../ressources/S13/) contient la demande et le changement de code (modèle `Creneaux` et un test). Elle ne change ni le schéma de la base ni la configuration ; les réponses déjà en cache dans Valkey restent lisibles.
- Projets : `mediagenda/api` (code, CI, étiquettes `vX.Y.Z` par semantic-release), `mediagenda/deploiement` (overlays `dev`, `recette`, `prod`, image désignée par **condensé**) ; image `registry.par1.medisphere.internal/medisphere/mediagenda-api` ; production publiée sur `https://mediagenda.apps.par1.medisphere.internal` (`/sante` renvoie la version).
- Production : Rollout `mediagenda` (espace `mediagenda-prod`, canary par poids des HTTPRoute sur `gw-par1`, analyses Prometheus), Application `mediagenda-prod` synchronisée **à la main**, HPA ; SLO `mediagenda-latence` (95 % < 250 ms) et `mediagenda-disponibilite` (99,5 %).
- Le dépôt `apps/` du workbook n'est pas modifié : tu reportes l'évolution dans **ton** dépôt `mediagenda/api`.

**Contraintes**
- Aucun `kubectl` d'écriture, aucune synchronisation forcée d'Argo CD qui contourne l'analyse, aucune étiquette d'image mobile : la production reçoit l'image par **condensé**, par une MR de promotion approuvée (Julien ou Karim).
- L'image livrée en production est **signée** par la clé de la plateforme et porte son attestation SBOM ; Kyverno l'admet sans exception ajoutée.
- Le canary va jusqu'au bout **sans** intervention manuelle autre que celles que prévoit le Rollout (pause à lever, s'il y en a une, notée).
- Le SLO est observé pendant le canary et une heure après ; s'il se dégrade, le retour arrière est celui du Rollout, pas un `kubectl`.
- Toute réparation de la chaîne découverte en route (runner, identité, analyse…) est une MR et une ligne de la chronologie (c'est encore de la dette de reconstruction).

**Livrables**
- MR fusionnée dans `mediagenda/api`, étiquette `vX.Y.Z` publiée, pipeline de l'étiquette réussi.
- MR de promotion de la recette puis de la production dans `mediagenda/deploiement`.
- Une ligne de `chronologie.md` par étape de la livraison (durée de bout en bout, de la fusion à 100 % du trafic), et la mention de ce qui a cassé dans la chaîne.

**Critères de réussite**
- [ ] `/sante` de la production renvoie la version de la **dernière** étiquette de `mediagenda/api`, publiée après la reconstruction du cluster, et `/api/v1/creneaux` renvoie le champ `nombre`.
- [ ] Les pods de l'API en production tournent sur une image désignée par condensé, signée (signature attachée dans Harbor) ; le Rollout est `Healthy` et une analyse du canary a réussi après la reconstruction.
- [ ] L'Application `mediagenda-prod` est `Synced` et `Healthy` ; aucun champ du Deployment ni du Rollout de production n'est géré par un `kubectl` (gestionnaires de champs).
- [ ] Une MR de promotion vers la production a été fusionnée après la reconstruction.

**Vérification** : `lab/bin/check F1 13`

<details><summary>Indice 1</summary>

Avant de fusionner, lance un pipeline sur la branche et regarde **où** il s'arrête. Une chaîne de livraison a besoin de plus de choses qu'on ne le croit : un runner protégé et son jeton, une identité OpenBao pour signer (jeton d'identité de GitLab, rôle `ci-signature`), le compte `ci-promotion`, l'accès du cluster à Harbor, et des analyses qui interrogent un Prometheus qui a des métriques.
</details>

<details><summary>Indice 2</summary>

L'analyse du canary compare des taux d'erreurs et des latences sur une fenêtre de temps. Sur une production qui vient de rouvrir, avec un Prometheus neuf, les séries existent-elles déjà ? Une analyse « sans données » peut être `Inconclusive` : lis comment ton `AnalysisTemplate` traite ce cas avant d'accuser l'application.
</details>

**Pour aller plus loin** (facultatif) : mesure le délai de bout en bout (fusion → 100 % du trafic) et compare-le au délai avant la reconstruction (historique des pipelines et des Rollouts) : la reconstruction a-t-elle ralenti la livraison (caches vides, images à retirer) ?

---

### F1-S14 — Recette Day 0  `LIBRE` `★★★`

> **Ticket PLAT-3114** — *De : Claire Morel*
> Je signe la fin du Day 0 quand **tous** les contrôles qui servent d'entrée aux finaux sont verts sur le cluster reconstruit, sans exception négociée, et quand les sondes du socle disent la même chose. Pose l'étiquette `day0-v1` sur `plateforme/medisphere` après, pas avant. S'il faut corriger un contrôle parce que la reconstruction a changé un nom ou une valeur légitimement, c'est une décision écrite, pas un contournement.

**Objectifs pédagogiques**
- Recetter une reconstruction contre l'ensemble des exigences accumulées (modules 24 à 29 et phases du final).
- Distinguer une régression de la reconstruction d'un écart légitime (nouvelle autorité, nouveau `serverName`, nouvelle date de création) et traiter chacun par écrit.
- Clore une opération : rien de provisoire, rien d'ouvert.

**Prérequis** : F1-S13 ; tous les contrôles d'entrée des finaux (PLAN §4.14, `annexes/prerequis.md` §7).
**Durée indicative** : 3 à 6 h (selon ce que la recette trouve).

**Contexte technique**
- Contrôles d'entrée des finaux : `lab/bin/check 29 25`, `28 25`, `27 25`, `26 46`, `25 46`, `24 46` ; contrôles du final : `lab/bin/check F1 2`, `F1 5`, `F1 6` et `F1 7` à `F1 13` (liste réglable par `WB_F1_S14_CONTROLES`, avec une raison écrite).
- `lab/bin/check F1 6` relit les journaux d'accès de `pxe01` : allume-la le temps de la recette. La rotation de Debian garde ces journaux 14 jours ; au-delà, retirer `F1 6` de la liste est une décision écrite dans `recette-day0.md`.
- Sondes du socle sur `adm01` : `ms-verif-services` (M06-E29) et `ms-verif-sauvegardes` (M02).
- Les contrôles des modules lisent parfois des éléments qui, légitimement, ont changé avec la reconstruction (dates de création, `serverName`, identifiants de ressources). Leurs variables `WB_*` de `lab/lab.env` permettent de les adapter, avec une raison écrite.

**Contraintes**
- Aucune panne active (modules ni final), aucune VM d'essai restante (3100-3199), aucun Secret d'amorçage restant, aucune exception Kyverno ajoutée pendant le final sans date de fin.
- Les gestes manuels de la reconstruction ne sont pas « réparés » par d'autres gestes manuels : soit ils sont devenus du code, soit ils sont inscrits comme dette au rapport de S15.
- Toute variable `WB_*` modifiée pour la recette est listée avec sa raison dans le compte rendu.
- L'étiquette est posée **en dernier**, sur un `main` dont le pipeline est vert.

**Livrables**
- `docs/day0/recette-day0.md` : tableau des contrôles (commande, résultat, date), écarts légitimes et leur traitement, variables adaptées, réserves éventuelles et leur échéance, signature de Claire (la MR qu'elle approuve).
- Étiquette **`day0-v1`** sur `plateforme/medisphere`.

**Critères de réussite**
- [ ] Les contrôles d'entrée des finaux et ceux du final F1 (S02, S05, S06, S07 à S13) sont verts.
- [ ] `ms-verif-services` et `ms-verif-sauvegardes` réussissent sur `adm01`.
- [ ] Aucune panne marquée active ; `recette-day0.md` est publié ; l'étiquette `day0-v1` existe sur `plateforme/medisphere`.

**Vérification** : `lab/bin/check F1 14` (rejoue tous les contrôles listés : compte 20 à 40 minutes).

<details><summary>Indice 1</summary>

Lance d'abord chaque contrôle séparément et range les rouges en trois tas : ce que la reconstruction a vraiment perdu (à réparer), ce qu'elle a légitimement changé (à décider par écrit), ce qui était déjà rouge avant (à vérifier dans les comptes rendus des modules). Ne commence à réparer qu'après ce tri.
</details>

<details><summary>Indice 2</summary>

Les contrôles qui datent quelque chose (« sauvegarde de moins de 24 h », « pipeline planifié réussi cette semaine ») passent au vert en laissant tourner la plateforme une nuit : la recette d'une reconstruction se fait le lendemain, pas dans la foulée.
</details>

**Pour aller plus loin** (facultatif) : transforme la liste de contrôles de la recette en un pipeline planifié de `plateforme/medisphere` (compte de lecture, sur `runner01`) qui la rejoue chaque semaine : une recette qu'on ne refait jamais redevient une hypothèse.

---

### F1-S15 — Rapport de reconstruction et runbook Day 0  `RED` `★★★`

> **Ticket PLAT-3115** — *De : Sophie Laurent*
> L'auditeur HDS vient dans trois semaines. Je veux trois documents que je peux lui tendre sans les relire avec toi : ce qui s'est passé (avec les chiffres), comment on le referait demain à 4 heures du matin, et ce qu'on change pour que ce soit plus court. Pas de « environ », pas de « ça devrait marcher ».

**Objectifs pédagogiques**
- Écrire un rapport de reconstruction factuel, chiffré et sans recherche de coupable.
- Transformer une opération vécue en runbook exécutable par quelqu'un d'autre.
- Décider, par un ADR, de ce qui réduit le temps de reconstruction et de ce qu'on accepte de garder.

**Prérequis** : F1-S01 (estimations de la carte d'amorçage) et F1-S07 à F1-S14 (chronologie, comparaison des données, post-mortem, recette).
**Durée indicative** : 4 à 6 h.

**Travail demandé**
1. **Rapport** `docs/day0/rapport-reconstruction.md` :
   - résumé (une demi-page : ce qui a été fait, durée totale de coupure, données perdues : aucune ou combien, incidents) ;
   - durées **mesurées** par phase et par étape (depuis `chronologie.md`), comparées à l'estimation de la carte d'amorçage de S01, avec l'écart en pourcentage et son explication ;
   - les **gestes manuels** de la reconstruction, chacun avec sa raison et son statut : devenu code (MR citée) ou **dette** (avec un responsable et une date) ;
   - les dépendances circulaires réellement rencontrées (et comment elles ont été cassées), comparées à celles prévues en S01 ;
   - ce qui a cassé, ce qui a surpris (incident INC-5712 compris), ce qui a bien marché ;
   - les **actions** datées (format `AAAA-MM-JJ`), avec responsable et ticket.
2. **Runbook RB-310** `docs/day0/runbooks/RB-310-reconstruire-k8s-par1.md` : quand l'utiliser (et quand utiliser plutôt RB-141, la restauration PBS ou le secours de RB-275), qui décide, prérequis vérifiables, ordre exact (VMID, playbooks, fichiers de Helmfile, amorçage, OpenBao, Argo CD, données), points de contrôle à chaque étape (la commande et le résultat attendu), points de non-retour, retour arrière, durées de référence mesurées.
3. **ADR-0310** `docs/day0/adr/ADR-0310-<titre>.md` : ce qu'on change pour réduire le temps de reconstruction (au moins deux options comparées, chiffrées avec tes mesures), décision, conséquences, ce qu'on accepte de ne pas faire.

**Critères de réussite**
- [ ] Les trois documents sont publiés sur `main` de `plateforme/medisphere` par une MR relue.
- [ ] Le rapport chiffre chaque phase, compare à l'estimation de S01, liste les gestes manuels et les actions datées.
- [ ] RB-310 cite les VMID 2141 à 2146, la VIP, les playbooks, Helmfile, OpenBao, Argo CD, la récupération CNPG et ses points de contrôle, et renvoie au retour arrière.
- [ ] ADR-0310 compare au moins deux options et décide.

**Vérification** : `lab/bin/check F1 15` (présence et contenu minimal : le fond s'auto-évalue avec le corrigé).

<details><summary>Indice 1</summary>

Un rapport chiffré se construit à partir de la chronologie, pas de mémoire : fais d'abord le tableau des durées (étape, début, fin, durée, dont attente, estimation de S01, écart), puis écris autour. Les écarts importants sont rarement « on a été lents » : ce sont des étapes oubliées dans l'estimation.
</details>

<details><summary>Indice 2</summary>

Un runbook se teste en le faisant lire par quelqu'un qui n'a pas fait l'opération : chaque étape doit dire **où** lancer la commande, ce qu'on doit voir, et quoi faire si on ne le voit pas. Les durées de référence permettent à l'astreinte de savoir si « c'est long » ou si « c'est cassé ».
</details>

**Pour aller plus loin** (facultatif) : propose à Claire un exercice annuel de reconstruction (fréquence, périmètre tournant, critères de succès) inscrit au plan de continuité, et ce qu'il coûterait en mémoire et en temps sur le lab.
