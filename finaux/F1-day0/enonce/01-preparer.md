# Final F1 — Phase 1 : Préparer

Personne ne détruit un cluster de production sur une intuition. Avant la fenêtre, l'équipe doit savoir **quoi** reconstruire et dans quel ordre, être sûre que le code décrit **vraiment** ce qui tourne, et pouvoir **revenir en arrière** si la reconstruction échoue. Cette phase ne casse rien : elle rend la destruction possible.

---

### F1-S01 — La carte d'amorçage de MédiSphère  `RED` `★★★`

> **Ticket PLAT-3101** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent*
> Avant de toucher à quoi que ce soit, je veux une carte : tout ce qu'il faut pour remonter la plateforme depuis rien, dans quel ordre, combien de temps chaque étape, et surtout ce qui **n'est pas** dans le code. Sophie veut voir noir sur blanc où sont les secrets qui permettent de tout rouvrir. Karim veut qu'on ait réfléchi aux poules et aux œufs : le jour où GitLab est par terre, où est le code de GitLab ?

**Objectifs pédagogiques**
- Reconstituer le graphe de dépendances d'une plateforme complète, du réseau aux applications.
- Identifier les dépendances circulaires et la façon de les casser (amorçage, chemins de secours).
- Recenser les secrets d'amorçage, ceux qui ne peuvent pas être dans le code, et où ils vivent.
- Estimer une durée de reconstruction défendable, étape par étape.

**Prérequis** : état d'entrée du final ([`00-introduction.md`](00-introduction.md)) ; modules 00 à 29.
**Durée indicative** : 3 à 4 h.

**Contexte technique**
- Périmètre de la carte : **toute** la plateforme (socle v5, `ceph-par1`, `k8s-par1` et ce qu'il porte), même si le final ne reconstruit que `k8s-par1`, `lb02` et `dns02`. Le final F5 (PRA) partira de cette carte.
- Sources : `lab/topologie.md` (« Qui gère quoi »), les `docs/*/` de `plateforme/medisphere` (en particulier `docs/kubernetes/reconstruction.md` du M14 et `docs/kubernetes/reseau/reconstruction.md` du M15), les runbooks de bris de glace (RB-240) et de restauration (RB-141 etcd, RB-051 états OpenTofu), les fichiers `secrets/` et `outils/` des projets.
- Les durées peuvent venir de tes mesures passées (mini-projets, tests de restauration chronométrés) ; une estimation sans source est signalée comme telle. S15 comparera tes estimations aux durées réelles.

**Travail demandé**
1. Écris `docs/day0/carte-amorcage.md` dans `plateforme/medisphere` (MR relue).
2. **Ordre de construction** : chaque brique (VM ou service), ce dont elle dépend, l'outil et le dépôt qui la construisent, la preuve qu'elle est prête avant de passer à la suite. Un graphe (Mermaid accepté) et une liste ordonnée.
3. **Dépendances circulaires** : au moins celles de la forge, du registre, du coffre et d'Ansible, d'External Secrets et de la méthode d'authentification du cluster dans OpenBao, de l'identité (Keycloak) et des sauvegardes. Pour chacune : le cycle, la façon de le casser aujourd'hui, et ce qu'il faudrait pour le casser mieux.
4. **Secrets hors du code** : chaque secret sans lequel on ne peut pas redémarrer la chaîne (parts du coffre, racines de PKI, mots de passe des identités Ansible Vault, clés de chiffrement des sauvegardes et des états, comptes de bris de glace, accès d'administration du cluster…) : où il est, qui y a accès, comment on vérifie qu'il est encore lisible, ce qui se passe s'il est perdu. **Jamais la valeur.**
5. **Durées** estimées par étape, la durée totale, et le chemin critique.
6. Ce que la carte ne couvre pas encore (lien vers les tickets ou les finaux suivants).

**Contraintes**
- Aucune valeur secrète, aucun extrait de fichier chiffré, aucun jeton, même expiré.
- Les noms d'hôtes, VMID, dépôts, rôles, états et espaces sont ceux du lab : pas de nom générique.

**Critères de réussite**
- [ ] `docs/day0/carte-amorcage.md` est sur `main`, avec un ordre explicite, une section sur les dépendances circulaires et une section sur les secrets hors du code.
- [ ] Chaque cycle cité a une façon de le casser qui fonctionne **aujourd'hui** sur le lab (pas seulement une intention).
- [ ] Chaque secret hors du code a un emplacement, un responsable et une procédure de vérification.
- [ ] Les durées ont une source (mesure ou estimation justifiée) et un total.

**Vérification** : `lab/bin/check F1 1` (présence et contenu minimal ; le fond s'évalue avec la grille du corrigé).

<details><summary>Indice 1</summary>

Pars de la fin : pour que MédiAgenda serve un patient, qu'est-ce qui doit tourner ? Puis, pour chacune de ces choses, recommence. Tu tomberas vite sur des briques qui dépendent d'elles-mêmes, directement ou par un détour.
</details>

<details><summary>Indice 2</summary>

Pour chaque brique, pose trois questions : où est son **code** ? où sont ses **images ou paquets** ? qui lui donne ses **secrets** ? Si la réponse est « dans une brique qui n'existe pas encore », tu as trouvé un cycle. Regarde ensuite ce que les modules ont prévu comme voie de secours : copies de travail sur `adm01`, runner `shell` hors du cluster, caches et sources publiques, identités locales, fichiers de `~/.config/workbook/`.
</details>

<details><summary>Indice 3</summary>

Pour les secrets, relis les registres de secrets (`docs/socle/registre-secrets.md` et ses extraits par module) et la liste de ce qui reste dans le script d'amorçage de `plateforme/k8s` depuis le M25. Demande-toi, pour chacun, comment tu le **testes** sans l'exposer.
</details>

**Pour aller plus loin** (facultatif) : ajoute à la carte une colonne « niveau de confiance » (reconstruit au moins une fois de bout en bout depuis le code, ou jamais) et classe les briques jamais reconstruites par risque.

---

### F1-S02 — Chasse à la dérive  `LIBRE` `★★★`

> **Ticket PLAT-3102** — *De : Karim Benali*
> Je ne veux pas découvrir pendant la fenêtre que le code ne décrit pas ce qui tourne. Fais l'inventaire de toutes les dérives, couche par couche : infrastructure, configuration, cluster, identité, coffre, registre, inventaire. Pour chaque écart, une décision : soit on remet la réalité au niveau du code, soit le code adopte la réalité. Les deux passent par une MR. Et je veux que ce contrôle soit reproductible : la prochaine fois, ce sera la nuit, pas toi.

**Objectifs pédagogiques**
- Détecter la dérive à chaque couche avec l'outil propre à la couche, sans rien appliquer.
- Distinguer la dérive (on a touché à la réalité) de l'écart de code (le code a changé, pas la réalité).
- Décider, pour chaque écart, entre retour au code et codification, et le tracer.
- Rendre la détection reproductible et périodique.

**Prérequis** : F1-S01 ; M05 (détection de dérive de `plateforme/infra`), M04 (dérive Ansible), M17 (`helmfile diff`), M20 (Argo CD), M24, M25 (états `identite`, `secrets`), M13 (état `registre`), M06 (NetBox).
**Durée indicative** : 4 à 6 h.

**Contexte technique**

| Couche | Ce qui fait foi | Où |
|---|---|---|
| VMs | états OpenTofu `socle`, `envs/k8s`, `envs/ceph`, `envs/provisioning` et les autres environnements encore vivants | `plateforme/infra` (détection de dérive planifiée depuis le M05) |
| Configuration des VMs | rôles et playbooks, mode vérification | `plateforme/ansible` (détection planifiée depuis le M04) |
| Couche de base du cluster | Helmfile | `plateforme/k8s` |
| Plateforme et applications | Argo CD | `plateforme/gitops`, dépôts de déploiement |
| Identité | état `identite` (royaume Keycloak), annuaire FreeIPA (`annuaire/`) | `plateforme/identite` |
| Coffre | état `secrets` | `plateforme/secrets` |
| Registre | état `registre` (projets, robots, caches, politiques de Harbor) | `plateforme/infra`, dossier `registre/` (M13) |
| Inventaire | NetBox face à Proxmox | `nbx01`, `medictl`, inventaires Ansible |

- `helmfile diff` ne montre une modification faite à la main sur un objet que dans certaines conditions : relis ce que tu as noté au M17 avant de conclure qu'une release est conforme.
- Les plans d'`identite` et de `secrets` ne tournent aujourd'hui que lors d'une poussée sur `main` : ils ne voient rien de ce qui change entre deux poussées.
- Toute action d'écriture passe par MR et pipeline ; un `apply` lancé depuis `adm01` n'est permis que pour un état dont le pipeline ne sait pas le faire, et se note comme dette.

**Travail demandé**
1. Lance la détection sur chaque couche du tableau. Rien n'est appliqué pendant la détection.
2. Pour chaque écart : la couche, l'objet, ce qui diffère (noms d'attributs, jamais de valeur secrète), la cause probable, la décision (**corrigé** : la réalité revient au code ; **codifié** : le code adopte la réalité) et la MR qui l'applique.
3. Applique les décisions par MR, puis relance la détection jusqu'à ce qu'elle soit vide partout.
4. Rends la détection **reproductible** : chaque couche a un contrôle qui tourne sans toi (planifié), dont le résultat se lit dans GitLab. Les couches qui n'en avaient pas en reçoivent un (au minimum `identite` et `secrets`) ; la détection de `plateforme/infra` couvre aussi l'état `envs/k8s`.
5. Écris le compte rendu `docs/day0/derive-<AAAA-MM-JJ>.md` : méthode par couche, tableau des écarts et décisions, ce que tu n'as pas pu contrôler et pourquoi.

**Contraintes**
- Aucun écart n'est « laissé pour après la fenêtre » sans décision écrite et datée de Karim (ou de toi, en le signalant).
- Aucune valeur secrète dans le compte rendu, les tickets ou les journaux de CI.
- Pas d'`apply` partiel « pour voir » sur un état partagé.

**Critères de réussite**
- [ ] Toutes les Applications d'Argo CD sont `Synced` et `Healthy`.
- [ ] La dernière détection planifiée de `plateforme/infra` (dont `envs/k8s`) et de `plateforme/ansible` est verte et date de moins de 7 jours.
- [ ] Les derniers plans d'`identite` et de `secrets` sont vides (« No changes ») et datent de moins de 7 jours.
- [ ] `helmfile diff` de `plateforme/k8s` est vide, NetBox et Proxmox concordent, l'état `registre` est vide (preuves dans le compte rendu).
- [ ] Le compte rendu est sur `main`, chaque écart a sa décision et sa MR.

**Vérification** : `lab/bin/check F1 2`

<details><summary>Indice 1</summary>

Deux plans différents répondent à deux questions différentes : « la réalité a-t-elle bougé depuis le dernier apply ? » et « le code a-t-il bougé depuis le dernier apply ? ». Le M05 a écrit un outil qui pose les deux.
</details>

<details><summary>Indice 2</summary>

Pour `identite` et `secrets`, le plus simple est souvent d'ajouter au pipeline existant une règle qui laisse le plan tourner dans un pipeline **planifié** (et à la demande), sans job d'application. Pense au verrou de l'état et aux identités dont le job a besoin.
</details>

<details><summary>Indice 3</summary>

Pour Helmfile, compare ce que montre un diff ordinaire et un diff qui tient compte de l'état réel des objets ; pour NetBox face à Proxmox, l'inventaire Proxmox d'Ansible est resté le contrôle de cohérence depuis le M06.
</details>

**Pour aller plus loin** (facultatif) : exporte une métrique « écarts par couche » vers Prometheus et une alerte quand une dérive dure plus de deux jours ouvrés.

---

### F1-S03 — Panne : les mains de quelqu'un sont passées par là  `BF` `★★★`

> **Incident INC-5703** — *De : Karim Benali*
> Je relisais le plan de la reconstruction et j'ai relancé les contrôles de dérive par acquit de conscience : le diff n'est pas vide quelque part. Je n'ai pas eu le temps de creuser. J'ai un doute sur `lb02`, quelqu'un y a travaillé pendant l'astreinte du week-end dernier, mais je ne suis sûr de rien et ce n'est peut-être pas le seul endroit. On ne détruit rien tant que le code et la réalité ne disent pas la même chose.

**Objectifs pédagogiques**
- Retrouver plusieurs dérives simultanées, sur des couches différentes, sans se laisser guider par une seule piste.
- Choisir pour chacune entre retour au code et codification, et justifier.
- Mesurer ce que vaut la détection mise en place en S02 (qu'a-t-elle vu, que n'a-t-elle pas vu ?).

**Prérequis** : F1-S02 terminé (code et réalité alignés, détection reproductible).
**Durée indicative** : 1 h 30 (temps cible) ; jusqu'à 3 h avec le compte rendu.

**Injection** : `lab/bin/break F1 3` (depuis `adm01`). Le script vérifie d'abord que le lab est sain ; il refuse sinon.

**Contexte technique**
- La panne ne coupe aucun service.
- Une décision de **codification** doit rester conforme aux standards (une valeur adoptée par le code doit avoir une raison écrite).

**Travail demandé**
1. Retrouve **toutes** les dérives, par les outils de S02, sans te limiter à `lb02`.
2. Pour chacune : décision, MR, contrôle que la dérive a disparu.
3. Ajoute l'incident au compte rendu de dérive (`docs/day0/derive-*.md`) : ce qui a été trouvé, par quel contrôle, en combien de temps, et ce que la détection planifiée aurait vu ou non (et quand).

**Critères de réussite**
- [ ] Plus aucune dérive sur aucune couche (contrôles de S02 relancés, tous vides).
- [ ] Chaque dérive a sa décision tracée dans le compte rendu, sous la référence INC-5703.
- [ ] Une faiblesse de la détection, s'il y en a une, a son ticket ou sa correction.

**Vérification** : `lab/bin/check F1 3`

<details><summary>Indice 1</summary>

Trois couches, trois outils. Une dérive par couche n'est pas exclue.
</details>

<details><summary>Indice 2</summary>

Une couche dont le contrôle est vide n'est pas forcément conforme : relis la remarque sur `helmfile diff` du contexte technique de S02, et pense à ce qu'un fichier modifié à la main produit (ou ne produit pas) dans un mode vérification.
</details>

<details><summary>Indice 3</summary>

Une modification faite dans l'interface de Proxmox se voit dans un plan qui rafraîchit l'état ; une modification de fichier sur une VM se voit dans le `--diff` du rôle qui gère ce fichier ; une modification d'objet du cluster géré par Helmfile ne se voit qu'en comparant aussi l'état réel. Pour chaque couche, vérifie que ton contrôle sait voir ce genre de changement avant de conclure.
</details>

**Pour aller plus loin** (facultatif) : retrouve **qui** a fait chaque modification et quand (journal des tâches de Proxmox, `journald` de la VM, journal d'audit de l'API Kubernetes dans Loki, locataire `audit`).

---

### F1-S04 — Le filet : sauvegardes prouvées, go/no-go et retour arrière  `LIBRE` `★★★`

> **Changement CHG-3104** — *De : Claire Morel* — *Copie : Sophie Laurent, Nadia Roussel, Julien Petit*
> La veille de la fenêtre, je veux une seule page qui me permette de dire « go » ou « no-go » en cinq minutes, sur des preuves. Des sauvegardes vues réussies et relues, pas des tâches planifiées supposées tourner. Une photographie des données pour vérifier qu'on retrouve tout après. Et un retour arrière que Nadia saurait jouer seule à 3 h du matin si la reconstruction tourne mal : remettre les six nœuds tels qu'ils étaient.

**Objectifs pédagogiques**
- Prouver une sauvegarde : réussite constatée, âge connu, lisibilité vérifiée.
- Photographier l'état des données pour comparer avant et après.
- Écrire des critères de go/no-go mesurables et un plan de retour arrière exécutable.

**Prérequis** : F1-S02 et F1-S03 ; M14 (instantanés etcd, PBS `par1/k8s`, RB-141), M16 (Velero, CNPG), M20 (sauvegarde d'Argo CD), M27 (export des définitions RabbitMQ), M00 (PBS).
**Durée indicative** : 4 à 6 h (dont des attentes de sauvegarde).

**Contexte technique**

| Filet | Où | Rappel |
|---|---|---|
| VMs des six nœuds | PBS `pbs01`, datastore `ds-lab`, espace de noms `par1/k8s` | sert au **retour arrière** (remettre l'ancien cluster), pas à la reconstruction |
| etcd | `s3-01`, compartiment `etcd-k8s-par1` (instantanés chiffrés `age`) | horaire, sur les nœuds de contrôle |
| Objets du cluster | Velero, `s3-01` compartiment `velero-k8s-par1` | en appoint de la reconstruction GitOps |
| PostgreSQL | CNPG, `s3-01` compartiment `cnpg-k8s-par1` (plugin Barman Cloud) | `mediagenda-db` (recette, prod), `portail-db` |
| RabbitMQ | CronJob `messagerie/export-definitions` → `messagerie-definitions` | définitions seulement ; les messages en file n'y sont pas |
| Argo CD | CronJob `argocd/argocd-export` → `argocd-sauvegardes` | export chiffré |

- Restauration de test d'un nœud : VMID **5310-5319**, sans jamais remettre en ligne une carte qui porte l'adresse ou la MAC d'un nœud en service. Une vérification PBS (*verify*) est l'autre preuve admise ; une restauration vaut mieux.
- Mémoire : une seule VM restaurée à la fois, de préférence un nœud de contrôle (4 Go).
- Les messages en file de RabbitMQ ne sont pas sauvegardés : la fiche dit ce qu'on en fait (vider la file avant la fenêtre, accepter la perte, ou autre) et Julien doit l'avoir validé.

**Travail demandé**
1. **Sauvegardes** : déclenche ou constate, juste avant la fenêtre, chaque filet du tableau, et prouve sa réussite (état, date, taille). Sauvegarde Velero **complète** (tous les espaces).
2. **Lisibilité** : restaure un nœud depuis PBS en VM jetable et vérifie qu'il démarre (ou fais vérifier ses instantanés par PBS) ; vérifie qu'un instantané etcd se télécharge et se déchiffre ; vérifie qu'une sauvegarde CNPG est utilisable (catalogue, WAL archivés jusqu'à maintenant).
3. **Photographie** : `docs/day0/reference-avant.md` : nombre de rendez-vous en production, messages en file par vhost et par file, nombre d'`ExternalSecret` et leur état, certificats et leurs échéances, Applications Argo CD, PVC et leur taille, versions des composants. Uniquement des comptes et des noms, aucune donnée de patient.
4. **Retour arrière** : `docs/day0/retour-arriere.md` : quand on le déclenche (critères, heure limite), comment (restaurer les six VMs depuis PBS, ordre de démarrage, état de `ceph-par1`), quoi vérifier ensuite, combien de temps, et ce qu'on perd (RPO).
5. **Fiche de changement** `docs/day0/changements/CHG-3104-filet-et-go.md` : périmètre de CHG-3107, critères de go/no-go mesurables (chacun avec sa commande ou son check), preuves jointes, qui décide, communication (Nadia, Julien), décision prise et heure.

**Contraintes**
- Aucune donnée de patient dans les documents ; pas d'extrait de base.
- Aucune VM restaurée n'est démarrée avec une carte active sur un VLAN de production.
- Les preuves ont **moins de 24 h** au moment du go : si la fenêtre glisse, S04 se rejoue.

**Critères de réussite**
- [ ] Les six nœuds ont une sauvegarde PBS de moins de 24 h dans `par1/k8s`, et la lisibilité d'au moins un nœud est prouvée.
- [ ] Un instantané etcd récent a été téléchargé et déchiffré avec succès.
- [ ] Sauvegarde Velero complète `Completed`, sauvegardes CNPG `completed` de `mediagenda-db` (recette, prod) et de `portail-db`, exports RabbitMQ et Argo CD réussis : tous de moins de 24 h.
- [ ] `reference-avant.md`, `retour-arriere.md` et la fiche CHG-3104 sont sur `main`, avec la décision go ou no-go.

**Vérification** : `lab/bin/check F1 4` (à lancer juste avant le go : les âges comptent).

<details><summary>Indice 1</summary>

Pour chaque filet, demande-toi : « comment je sais qu'il a réussi, et comment je sais que je saurai le relire ? ». Si la seule réponse est « la tâche est planifiée », ce n'est pas une preuve.
</details>

<details><summary>Indice 2</summary>

Une restauration de test d'une VM qui partage la MAC et l'adresse d'une machine en service peut casser ce que tu voulais protéger. Regarde les options de restauration de Proxmox qui rendent une VM restaurée unique, et la façon de la démarrer sans réseau.
</details>

<details><summary>Indice 3</summary>

Un bon critère de go/no-go se vérifie par une commande et donne vert ou rouge : « `lab/bin/check F1 4` vert », « `lab/bin/check 29 25` vert », « Argo CD : 0 Application hors `Synced/Healthy` », « dernière archive WAL de `mediagenda-db` (prod) de moins de 10 minutes »… Un critère qui demande un jugement (« le cluster a l'air sain ») n'en est pas un.
</details>

**Pour aller plus loin** (facultatif) : chronomètre une restauration complète d'un nœud depuis PBS et reporte le temps dans le retour arrière ; tu sauras ce que coûte l'abandon à mi-fenêtre.
