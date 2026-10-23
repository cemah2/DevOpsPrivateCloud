# Final F3 — Phase 6 : vendredi

Vendredi, dernier jour. Deux incidents qui mettent à l'épreuve autre chose que le diagnostic technique. Le premier est une alerte de **sécurité** : la bonne réaction n'est pas de « réparer » vite, mais de qualifier, de confiner sans détruire, de préserver les preuves et d'escalader — un pod supprimé trop tôt, c'est une enquête impossible. Le second touche la **production** et des messages que des patients attendent : la contrainte est qu'**aucune notification ne se perde**, même si purger la file « réglerait » le symptôme en une seconde.

> **Rappels de la semaine** (détail dans [`00-introduction.md`](00-introduction.md) et ta procédure de S02) : main courante (`- HH:MM INC-59XX [type] texte`), gravité, messages d'état au rythme de la procédure (courriel, objet avec `[INC-59XX]`), correction par le code et la CI, `lab/bin/check F3 <XX>` puis `lab/bin/break F3 <XX> --annuler` pour clore. Lance les incidents dans l'ordre, sans lire `corrige/`.

---

### F3-S12 — Vendredi : alerte Falco en production  `BF` `★★★`

> **Incident INC-5912** — *Alerte reçue sur `astreinte@`, vendredi 7 h 52*
> Courriels d'Alertmanager `AlerteFalco` : un shell interactif dans un conteneur applicatif, puis des connexions sortantes vers un port non prévu, répétées chaque minute. Personne n'a annoncé d'intervention. Nadia transfère avec pour objet « Falco : shell en production ?! ». *(L'espace concerné s'affiche à l'injection : vérifier si c'est vraiment la production fait partie de la qualification.)*

**Objectifs pédagogiques**
- **Qualifier** une alerte de sécurité (vrai ou faux positif) à partir de sources croisées : Falco, Tetragon, journal d'audit de l'API, Hubble, historique des changements.
- **Confiner** sans détruire : politique de quarantaine, pod sorti de son contrôleur, service rétabli par un pod sain.
- **Préserver** les preuves (du plus volatil au plus durable, empreintes, compartiment `preuves`) et **escalader** à la RSSI dans les délais de RB-262.

**Prérequis** : S01-S02, S11 close ; module 26 (Falco, falcosidekick, Tetragon, quarantaine, RB-262, compartiment `preuves`), module 22 (Loki, locataire `audit`), module 15 (Hubble), module 24 (identités dans le journal d'audit).
**Durée indicative** : 1 h 30 à 2 h (collecte comprise).

**Contexte technique**
- Politique de cluster `quarantaine` (CiliumClusterwideNetworkPolicy, M26-E33), posée à l'avance : elle s'applique à tout pod étiqueté `medisphere.internal/quarantaine=oui`. RB-262 décrit l'ordre des gestes.
- Compartiment `preuves` de `s3-01` : identité `preuves-depot` (écrire, lister, jamais supprimer), identité `preuves-lecture` ; versionné. Fichiers d'identité dans `~/.config/workbook/` (M26).
- ⚠️ **Ne supprime pas le pod suspect, ne redémarre pas son conteneur, ne lance rien dedans** avant la fin de la collecte. Ne désactive ni ne modifie Falco, ses règles ou falcosidekick pour faire taire l'alerte. Un silence Alertmanager **ciblé et daté** sur le pod une fois isolé est permis (consigne-le).
- Simulation : l'« attaque » est inoffensive (aucun binaire, aucune donnée lue ni envoyée, aucune sortie réelle) ; traite-la comme si elle ne l'était pas.

**Injection** : `lab/bin/break F3 12` (3 variantes). Temps cible : **60 min** jusqu'au confinement et à l'escalade ; la collecte peut déborder.

**Travail demandé**
1. Ouvre l'incident ; dans les **15 premières minutes**, qualifie : quel pod, quel espace, quel nœud, quelle image, depuis quand, qui a ouvert le shell (audit de l'API), vers où partent les connexions, un changement annoncé l'explique-t-il ? Écris ta décision (vrai ou faux positif) et sa justification.
2. Confine selon RB-262 : isolement réseau, pod sorti de son contrôleur, service de l'espace rétabli par un pod sain. Vérifie que l'isolement n'a pas redémarré le conteneur.
3. Collecte les preuves dans l'ordre de volatilité, calcule leurs empreintes, dépose-les dans `preuves/INC-5912/` ; recopie les empreintes dans la main courante.
4. Escalade à Sophie Laurent (RSSI) dans le délai de RB-262, avec ce qu'elle a besoin de savoir pour décider ; préviens Julien ou l'équipe propriétaire de l'espace.
5. Termine : éradication décidée avec Sophie (suppression du pod suspect **après** collecte), recherche d'une persistance ou d'un second pod touché, actions de suite (comptes à vérifier, règles, exceptions).

**Critères de réussite**
- [ ] Falco tourne sur tous les nœuds ; la politique de quarantaine est intacte.
- [ ] Au moins trois pièces et leurs empreintes (`SHA256SUMS` ou `*.sha256`) sont dans `s3://preuves/INC-5912/`.
- [ ] Le pod suspect est en quarantaine, sorti de son contrôleur et derrière aucun Service — ou supprimé **après** le dépôt des preuves ; le service de l'espace est rétabli.
- [ ] La main courante d'INC-5912 contient la qualification (entrée `[décision]`), l'isolement et l'escalade à la RSSI ; l'incident est ouvert, suivi et clos ; un courriel d'état au moins est parti.

**Vérification** : `lab/bin/check F3 12`

<details><summary>Indice 1</summary>

Falco dit **ce qui** a été lancé, le journal d'audit de l'API dit **qui** l'a demandé (`verb="create"`, sous-ressource `exec` ou `ephemeralcontainers`, utilisateur, adresse source, heure) : locataire `audit` de Loki. Hubble dit **où** les paquets ont voulu aller et s'ils ont été jetés.
</details>

<details><summary>Indice 2</summary>

Ce que tu cherches dans le pod (processus, connexions, fichiers déposés) se lit **de l'extérieur** : conteneur éphémère avec `--target` (même espace de processus), `/proc/1/root/…` pour les fichiers, sous le même utilisateur que la cible. Rien n'est lancé dans le conteneur suspect lui-même.
</details>

<details><summary>Indice 3</summary>

Sortir un pod de son contrôleur : retirer une étiquette du **sélecteur** du ReplicaSet (lis-le d'abord). Le contrôleur recrée un pod sain ; le suspect continue de tourner, orphelin, isolé, hors des EndpointSlices du Service.
</details>

**Pour aller plus loin** (facultatif) : un *checkpoint* du conteneur par l'API du kubelet (`ContainerCheckpoint`, RB-262 pièce 7) et un instantané PBS du nœud (pièce 8) ; puis rédige pour Sophie une note d'une page : ce qui est établi, ce qui ne l'est pas, ce qui reste à vérifier (comptes, jetons, autres pods de la même image).

---

### F3-S13 — Vendredi : les notifications s'accumulent  `BF` `★★★`

> **Incident INC-5913** — *De : Nadia Roussel, vendredi 10 h 20*
> « Trois cabinets appellent : leurs patients n'ont pas reçu les SMS de rappel de ce matin. Dans l'interface de RabbitMQ, la file `notifications` de la prod grossit à vue d'œil. On a pourtant mis KEDA pour ça, non ? » (une campagne de rappels exceptionnelle est en cours)

**Objectifs pédagogiques**
- Raisonner en **débits** : entrée, sortie, capacité par consommateur, effectif possible ; savoir dire si la file se videra et quand.
- Diagnostiquer l'autoscaling piloté par les événements (ScaledObject, TriggerAuthentication, repli, HPA `keda-hpa-*`) et la consommation (consommateurs, politique effective de la file, rebut, limite de livraison).
- Rétablir la production **sans perdre un seul message**, par le chemin normal (dépôt, rotation, Argo CD).

**Prérequis** : S01-S02, S12 close ; modules 27 (RabbitMQ, topologie déclarative, rebut, RB-277), 28 (KEDA, comptes `keda-prod`, ScaledObject de prod), 25 (ESO, OpenBao), 20 (synchronisation manuelle de la prod).
**Durée indicative** : 1 h à 1 h 30.

**Contexte technique**
- File quorum `notifications` du vhost `medinotif-prod` (grappe `messagerie/rabbitmq`), politique `notifications-rebut` (rebut `notifications.rebut`, limite de livraison 5, `at-least-once`) déclarée dans `plateforme/donnees` ; MédiNotif dans `medinotif-prod`, ScaledObject `medinotif` (minimum 2, maximum du dépôt `medinotif/deploiement`, repli à 4 pods), compte `keda-prod` (mot de passe dans `kv/medinotif/prod/keda`). Capacité mesurée au M28-E13 : ≈ 20 messages/s par pod.
- La « campagne » est simulée par un éditeur borné (45 min au plus) ; ses messages sont valides : MédiNotif les « envoie » (une ligne de journal, rien ne part).
- ⚠️ **Interdit** : purger ou supprimer la file, supprimer un message, retirer la limite de livraison ou le rebut, synchroniser la production sans avoir lu le différentiel d'Argo CD.

**Injection** : `lab/bin/break F3 13` (3 variantes). Temps cible : **45 min**.

**Travail demandé**
1. Ouvre et qualifie l'incident (impact patients : notifications en retard) ; communique, y compris au support (Nadia) avec une estimation de retour à la normale.
2. Mesure : débit d'entrée, débit de sortie, nombre de consommateurs, effectif demandé et obtenu, état du ScaledObject ; déduis-en si l'autoscaling, la consommation ou la capacité est en cause.
3. Corrige la cause par le chemin normal (dépôt et Argo CD, rotation d'identifiants par OpenBao, topologie déclarative) ; consigne tout écart trouvé hors du code et son auteur s'il est connu (journaux d'audit).
4. Vérifie que la file redescend et estime l'heure à laquelle les rappels en retard seront tous partis ; vérifie qu'aucun message n'est perdu (rebut, compteurs de MédiNotif) et écris-le.
5. **Prévention** : une alerte de symptôme (le client attend) plutôt que de cause, et ce qui aurait empêché l'écart (contrôle de dérive, procédure de rotation, politique).

**Critères de réussite**
- [ ] La file `notifications` (prod) a au moins deux consommateurs, sa politique effective est `notifications-rebut` (rebut et limite de livraison positifs) et elle se vide (moins de 2 000 messages, ou consommée plus vite qu'alimentée).
- [ ] Le ScaledObject `medinotif` (prod) est prêt, hors repli, avec le maximum du dépôt ; MédiNotif a au moins deux pods disponibles, aucun en `CrashLoopBackOff`.
- [ ] La main courante d'INC-5913 dit comment la non-perte des messages a été vérifiée ; l'incident est ouvert, suivi et clos ; un courriel d'état au moins est parti.

**Vérification** : `lab/bin/check F3 13`

<details><summary>Indice 1</summary>

`kubectl describe scaledobject` montre les conditions (`Ready`, `Active`, `Fallback`) et les événements du scaler ; `kubectl get hpa keda-hpa-medinotif` l'effectif demandé, obtenu et le maximum. Si KEDA est en repli, c'est qu'il ne lit plus la file : demande-toi avec quelle identité il la lit.
</details>

<details><summary>Indice 2</summary>

`rabbitmqctl list_queues -p medinotif-prod name messages messages_unacknowledged consumers policy` et `rabbitmqctl list_policies -p medinotif-prod` : une seule politique s'applique à une file, celle de plus haute priorité. Des consommateurs qui redémarrent en boucle avec un message non acquitté qui revient, c'est le scénario de RB-277.
</details>

<details><summary>Indice 3</summary>

La production est synchronisée **à la main** par Argo CD : une modification directe d'un objet y reste et rend l'Application `OutOfSync`. Le différentiel d'Argo CD te dit quoi, le journal d'audit de l'API qui et quand.
</details>

**Pour aller plus loin** (facultatif) : calcule le maximum de pods nécessaire pour absorber une campagne de 120 messages/s en moins de 10 minutes de retard, et vérifie que les quotas de `medinotif-prod` et la capacité des travailleurs le permettent (MR si besoin).
