# Final F3 — Phase 1 : prise de poste (lundi matin)

Avant le premier appel, deux choses : savoir que tout fonctionne **et que tu le sais** (tes accès, tes alertes, tes runbooks), puis écrire la règle du jeu des incidents. Rien n'est injecté dans cette phase ; le contrôle de S01 devient le contrôle de santé que chaque incident exigera ensuite.

---

### F3-S01 — Prendre l'astreinte  `LIBRE` `★★★`

> **Ticket PLAT-3301** — *De : Nadia Roussel*
> L'an dernier, une astreinte a découvert à 2 h du matin que son OTP était sur l'ancien téléphone et que les alertes partaient vers une adresse que personne ne lisait. Avant de prendre le téléphone, tu vérifies **tout** : que tu peux entrer partout (y compris si le SSO tombe), que les alertes arrivent vraiment, que le témoin de `mon01` surveille bien la supervision, et que tu sais où est chaque runbook. Tu me laisses une trousse d'astreinte que la personne suivante pourra reprendre telle quelle.

**Objectifs pédagogiques**
- Vérifier ses accès de bout en bout, par la voie normale (SSO + OTP) et par la voie de secours (bris de glace), sans rien casser.
- Prouver la chaîne d'alerte réelle (règle → Alertmanager → route → courriel) et le *dead man's switch* qui la surveille.
- Rassembler une documentation éparpillée dans vingt-neuf modules en un point d'entrée utilisable sous stress.

**Prérequis** : F2 terminé (`day1-v1`, `lab/bin/check F2 13` vert) ; M21 (routes, Mailpit, témoin `mon01`), M24 (SSO, OTP, kubelogin, RB-240), M25 (OpenBao OIDC).
**Durée indicative** : 3 à 4 h.

**Contexte technique**
- Le contrôle de santé du lab (celui qu'exige chaque injection) est la première partie de `lab/bin/check F3 1` : nœuds de `k8s-par1` `Ready` et planifiables, toutes les Applications Argo CD `Synced`/`Healthy`, Ceph `HEALTH_OK`, aucune alerte critique active dans l'Alertmanager du cluster, et sur le témoin de `mon01` : sonde `watchdog-cluster` réussie, aucune sonde en échec, aucune alerte critique.
- Adresse de la boîte d'astreinte dans Mailpit : `astreinte@medisphere.internal`. L'alerte d'essai de la prise de poste s'appelle **`EssaiPriseDePoste`** (gravité `critique`, équipe `plateforme`) ; elle doit traverser la **vraie** route d'astreinte, pas une route d'essai.
- Comptes de bris de glace : ceux de RB-240 (M24-E28). « Tester en lecture » veut dire : prouver que le compte s'ouvre et lit, **sans rien modifier**, en suivant RB-240 (deux personnes, coffre, traces), et constater que l'usage est bien vu (journal d'audit, alerte).
- Livrables, dans `plateforme/medisphere` par MR :
  - `docs/exploitation/index-runbooks.md` : **tous** les runbooks `RB-NNN` du dépôt (le check compare avec les fichiers `docs/**/runbooks/RB-NNN-*.md`), rangés par symptôme ou par domaine, avec pour chacun une ligne « quand l'ouvrir » ;
  - `docs/exploitation/trousse-astreinte.md` : accès (SSO, kubelogin, OpenBao, SSH), bris de glace (RB-240, date du dernier essai en lecture au format `AAAA-MM-JJ`), contrôle de santé de début de journée, vérification du *dead man's switch*, adresses des outils, personnes et escalade ;
  - la première main courante de la semaine : `docs/exploitation/journal/<AAAA-MM-JJ>.md` (prise de poste, résultat des vérifications).

**Travail demandé**
1. Établis que le lab est sain (le contrôle de santé de ce scénario) ; ce qui ne l'est pas se répare maintenant, et se note.
2. Vérifie chacun de tes accès par la voie normale, puis les comptes de bris de glace en lecture seule, en traçant ce que tu fais.
3. Prouve la chaîne d'alerte avec `EssaiPriseDePoste`, et prouve que le témoin de `mon01` verrait une supervision muette (sans la rendre muette).
4. Écris l'index des runbooks et la trousse d'astreinte ; ouvre la main courante.

**Critères de réussite**
- [ ] Le contrôle de santé est entièrement vert.
- [ ] `~/.kube/config` accède au cluster par kubelogin (OIDC) ; la méthode `oidc` d'OpenBao répond.
- [ ] La configuration chargée de l'Alertmanager route une alerte critique de la plateforme vers `astreinte-mail`, et `astreinte@medisphere.internal` a reçu `EssaiPriseDePoste`.
- [ ] L'index cite tous les runbooks `RB-NNN` du dépôt, dont celui du bris de glace ; la trousse couvre les accès, le bris de glace daté, le contrôle de santé et le *dead man's switch*.
- [ ] La main courante du jour est publiée sur `main`.

**Vérification** : `lab/bin/check F3 1`

<details><summary>Indice 1</summary>

Une alerte d'essai se pose directement dans l'Alertmanager du cluster, avec les étiquettes qui la feront router comme une vraie alerte et une fin proche ; `amtool` sait faire les deux (tester l'arbre, poser l'alerte). Pour le témoin, regarde ce que mesure le job `watchdog-cluster` et ce que deviendrait cette mesure si l'alerte `Watchdog` disparaissait : la preuve se lit, elle ne se provoque pas.
</details>

<details><summary>Indice 2</summary>

La liste des runbooks se fabrique depuis le dépôt lui-même (arbre de `docs/`), pas de mémoire : un script de quelques lignes, gardé dans `docs/exploitation/` ou `plateforme/outils`, refait l'index à chaque ajout. Pour le bris de glace, relis RB-240 jusqu'au bout : la partie « après usage » compte autant que l'ouverture.
</details>

**Pour aller plus loin** (facultatif) : fais de l'index un fichier **généré** par la CI de `plateforme/medisphere` (job qui échoue si un runbook n'y figure pas), et ajoute à la trousse une fiche d'une page imprimable « les dix premières minutes ».

---

### F3-S02 — La procédure de gestion d'incident  `RED` `★★`

> **Ticket PLAT-3302** — *De : Claire Morel*
> Pendant l'incident d'InfoGér du printemps, j'ai reçu des nouvelles par trois personnes différentes, contradictoires, et aucune pendant une heure. Je veux une procédure écrite, courte, que tout le monde suit : à partir de quand c'est grave, qui fait quoi, qui me parle et à quel rythme, où on écrit ce qui se passe, et quand on considère que c'est fini. Je la relirai ce soir et on l'appliquera dès aujourd'hui.

**Objectifs pédagogiques**
- Définir des niveaux de gravité fondés sur l'impact (utilisateurs, données, conformité HDS) plutôt que sur la technique.
- Séparer les rôles d'un incident (responsable, communication, technique), même quand une seule personne les tient.
- Rendre la communication prévisible : canaux, rythme, modèles, critères de clôture, déclenchement du post-mortem.

**Prérequis** : F3-S01 ; l'introduction de ce final (convention de main courante et de messages d'état).
**Durée indicative** : 2 h.

**Contexte technique**
- Livrable : `docs/exploitation/gestion-incidents.md` dans `plateforme/medisphere`, par MR (relue par Claire : approbation ou commentaire de `claire.morel`).
- La procédure reprend la convention de l'introduction (identifiants `INC-59XX`, lignes `- HH:MM INC-59XX [type] …`, messages d'état par courriel avec `[INC-59XX]` en tête d'objet, tickets `PLAT-33XX`) et la complète.
- Contraintes MédiSphère : données de santé (HDS) — une exposition de données est grave quelle que soit sa durée ; les cabinets prennent rendez-vous de 7 h à 20 h ; l'astreinte est seule la nuit et le week-end ; Sophie Laurent (RSSI) est prévenue de tout incident de sécurité.

**Travail demandé**
Rédige la procédure. Elle contient au moins :
1. **Quatre niveaux de gravité** SEV1 à SEV4, chacun avec sa définition, deux exemples MédiSphère, qui est prévenu et en combien de temps.
2. **Les rôles** : responsable d'incident, communication, technique ; qui les tient quand l'astreinte est seule ; comment on passe la main.
3. **Les canaux** (courriel `incidents@`, téléphone, ticket) et ce qui va dans chacun.
4. **Le rythme des messages d'état** par gravité (« toutes les N min ») et les **modèles** de message (début, point d'étape, fin).
5. **La main courante** : format, ce qu'on y écrit, quand on la publie.
6. **Les critères de clôture** et le **déclenchement du post-mortem** (quels incidents, sous quel délai, sans recherche de coupable).

**Critères de réussite**
- [ ] `docs/exploitation/gestion-incidents.md` est sur `main` et contient les quatre niveaux, les trois rôles, les canaux, un rythme chiffré, des modèles, la main courante et son format, la clôture et le post-mortem.
- [ ] Un lecteur qui ne connaît pas MédiSphère sait classer « la recette est lente » et « un dossier patient visible par un autre cabinet » sans hésiter.

**Vérification** : `lab/bin/check F3 2` (présence et contenu minimal ; la qualité s'évalue avec le corrigé).

<details><summary>Indice 1</summary>

Classe par **impact**, pas par cause : combien d'utilisateurs, quelle fonction, quelles données, depuis combien de temps, contournement possible ou non. « Ceph `HEALTH_WARN` » n'est pas une gravité ; « les cabinets ne peuvent plus prendre de rendez-vous » en est une.
</details>

<details><summary>Indice 2</summary>

Un message d'état utile répond toujours aux mêmes questions dans le même ordre : quel impact maintenant, ce qu'on sait, ce qu'on fait, prochain message à quelle heure. Le « prochain message à » est la promesse qui rassure le plus, et celle qu'on oublie le plus.
</details>

**Pour aller plus loin** (facultatif) : ajoute un tableau « qui réveiller la nuit » (escalade par gravité et par domaine), et une règle de **gel des changements** pendant un SEV1.
