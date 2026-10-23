# Final F3 — Phase 3 : mardi

Deux incidents de jour qui touchent la plateforme elle-même (la PKI, un nœud), puis un appel le soir, chronométré. Même discipline que lundi : main courante, gravité, messages d'état, correction par le code, contrôle, clôture (`lab/bin/break F3 <XX> --annuler`). Rappel : [`00-introduction.md`](00-introduction.md).

---

### F3-S05 — Mardi : les certificats ne se renouvellent plus  `BF` `★★★`

> **Ticket INC-5905** — *De : Sophie Laurent*
> *(Le détail s'affiche à l'injection : la répétition hebdomadaire du renouvellement du joker reste à `False`.)*

**Objectifs pédagogiques**
- Suivre une émission ACME de bout en bout dans cert-manager (`Certificate` → `CertificateRequest` → `Order` → `Challenge`) et lire l'erreur au bon étage.
- Situer la rupture entre le cluster, la bordure, l'autoritaire DNS (RFC 2136, TSIG) et l'autorité ACME de `ca01`.
- Mesurer l'urgence réelle (échéance des certificats en service) avant de décider de la gravité.

**Prérequis** : M06 (step-ca, PowerDNS), M07 (pare-feu de la bordure), M15 (cert-manager, `step-ca-acme`, DNS-01 RFC 2136, RB-151) ; F3-S04 clos.
**Durée indicative** : 1 h (temps cible).

**Contexte technique**
- ClusterIssuer `step-ca-acme` : répertoire `https://ca01.par1.medisphere.internal/acme/acme/directory` ; DNS-01 par RFC 2136 vers l'autoritaire `10.10.20.10:5300`, clé TSIG `certmanager-k8s` (Secret `cert-manager/tsig-certmanager-k8s`) pour la zone `apps.par1.medisphere.internal` ; HTTP-01 par `gw-par1` pour les autres noms.
- Témoin : le `Certificate` `wb-pannes/repetition-joker` (`*.apps.par1.medisphere.internal`, donc DNS-01), créé par l'injection. Le joker réel `passerelles/apps-joker` est valide et n'est pas touché ; il est renouvelé 10 jours avant son échéance.
- ⚠️ **Interdit** : toucher à la racine « MédiSphère Root CA » ou à l'intermédiaire de `ca01`, ou désactiver la vérification TLS pour « débloquer ».

**Injection** : `lab/bin/break F3 5` (3 variantes ; 5 à 15 min : l'injection attend de constater que le témoin n'est pas délivré).

**Travail demandé**
1. Ouvre INC-5905 ; évalue l'urgence (quels certificats en service échoient quand ?) et fixe la gravité en conséquence.
2. Trouve l'étage qui échoue et la cause racine, preuve à l'appui (événements, journaux de cert-manager, journal de l'autoritaire ou de la bordure, compteurs).
3. Répare par le code qui décrit la chose (rôle Ansible, `plateforme/k8s`, matrice des flux) ou, si la dérive est hors du code, en rejouant ce que dit le code ; explique dans la main courante pourquoi le code n'avait rien vu.
4. Vérifie que la répétition est délivrée et qu'aucun défi ne reste bloqué ; écris **RB-332** « Certificats ACME non délivrés » (ou complète RB-151 et pointe-le depuis RB-332).

**Critères de réussite**
- [ ] `step-ca-acme` est prêt et interroge le répertoire ACME de `ca01`.
- [ ] Tous les certificats du cluster sont prêts, la répétition du joker comprise ; aucun défi ACME n'est bloqué depuis plus de 15 min.
- [ ] La zone `apps.par1.medisphere.internal` accepte les mises à jour signées de cert-manager ; le contrôle de santé est vert.
- [ ] INC-5905 est ouvert et clos, avec au moins un message d'état consigné et envoyé ; RB-332 est publié.

**Vérification** : `lab/bin/check F3 5`

<details><summary>Indice 1</summary>

`kubectl describe` sur chaque objet de la chaîne, dans l'ordre, jusqu'au premier qui dit pourquoi il n'avance pas. `cmctl status certificate` résume. Une erreur d'enregistrement de compte ACME se lit sur l'émetteur, pas sur le certificat.
</details>

<details><summary>Indice 2</summary>

Rejoue chaque dialogue depuis l'endroit d'où il part : un pod de `wb-essais` sur un travailleur vers `ca01:443` ; `nsupdate` signé avec la même clé et le même nom vers `10.10.20.10:5300` (le M15 l'a fait) ; regarde les métadonnées de la zone sur `dns01` et les compteurs des règles de la bordure (`nft -a list chain inet filter forward`). Ce que tu vois dans la configuration écrite n'est pas forcément ce qui tourne.
</details>

**Pour aller plus loin** (facultatif) : transforme la répétition hebdomadaire en `CronJob` qui renouvelle un certificat de répétition et alerte (règle Prometheus sur `certmanager_certificate_ready_status`) s'il n'est pas délivré en 30 min.

---

### F3-S06 — Mardi : un nœud tombe malade  `BF` `★★★`

> **Ticket INC-5906** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection : un travailleur de `k8s-par1` est signalé en mauvaise santé et des pods en sont chassés.)*

**Objectifs pédagogiques**
- Lire l'état d'un nœud (conditions, *taints*, événements, éviction) et choisir entre réparer le nœud et le vider.
- Diagnostiquer sur le nœud lui-même (services, journaux systemd, disque, configuration) sans le redémarrer à l'aveugle.
- Vérifier l'impact sur les charges (StatefulSets, bases, réplicas) et la capacité restante du cluster.

**Prérequis** : M14 (nœuds, kubelet, containerd, éviction, RB-14x), M16, M27 (bases et caches sur les nœuds) ; F3-S05 clos.
**Durée indicative** : 1 h (temps cible).

**Contexte technique**
- Un seul travailleur est touché ; jamais un nœud de contrôle. L'injection choisit un travailleur qui ne porte ni le primaire de la base de production ni le Valkey de production, et vérifie qu'une sauvegarde récente de la base de production existe.
- Accès aux nœuds : SSH `admin` + `sudo` (ou ton certificat SSH du M24) ; console `qm terminal` depuis `pve01` en dernier recours.
- Configuration des nœuds : rôles `containerd`, `k8s_noeud`, `k8s_travailleur` de `plateforme/ansible`.
- ⚠️ Ne redémarre pas la VM avant d'avoir trouvé la cause : un redémarrage efface des preuves et ne répare pas forcément.

**Injection** : `lab/bin/break F3 6` (3 variantes).

**Travail demandé**
1. Ouvre INC-5906 ; mesure l'impact (quels pods sont partis où, qu'est-ce qui tourne à capacité réduite, la production est-elle à risque si un deuxième nœud tombe ?).
2. Diagnostique depuis le cluster puis sur le nœud ; décide (main courante) entre réparer en place et vider le nœud.
3. Répare ; si la cause est une dérive de configuration, ramène le nœud dans l'état décrit par Ansible et explique pourquoi Ansible ne l'avait pas vue.
4. Vérifie que le nœud reprend des pods et que la production est au complet ; écris **RB-333** « Nœud travailleur malade ».

**Critères de réussite**
- [ ] Tous les nœuds sont `Ready`, sans pression, planifiables ; kubelet et containerd sont actifs sur chaque travailleur ; aucun système de fichiers de `/var/lib/kubelet` n'est rempli à plus de 85 %.
- [ ] Le Rollout de production est `Healthy`, la base de production a toutes ses instances prêtes, Valkey de production est prêt ; le contrôle de santé est vert.
- [ ] INC-5906 est ouvert et clos, avec au moins un message d'état consigné et envoyé ; RB-333 est publié.

**Vérification** : `lab/bin/check F3 6`

<details><summary>Indice 1</summary>

`kubectl describe node` : conditions, *taints*, événements, et la date du dernier battement de cœur (`Lease` dans `kube-node-lease`). Un nœud `Ready` avec une pression n'a pas le même problème qu'un nœud `NotReady` ; dans le second cas, ce n'est pas Kubernetes qui te dira pourquoi, c'est le nœud.
</details>

<details><summary>Indice 2</summary>

Sur le nœud : `systemctl status` et `journalctl -u … -b` des deux services dont dépend un nœud Kubernetes ; `df -h` et `du -xh --max-depth=2 /var | sort -h` ; les dates de modification des fichiers de configuration (`ls -la --time-style=full-iso`). Le rôle Ansible concerné en `--check --diff` sur ce seul nœud te dit si la configuration a dérivé.
</details>

**Pour aller plus loin** (facultatif) : écris la variante que l'injection a refusé de faire, l'**horloge** du nœud qui dérive : quels composants de `k8s-par1` (TLS, WireGuard de Cilium, cephx, jetons) en souffriraient, dans quel ordre, et comment on le verrait avant que ça casse (règle sur `node_timex_offset_seconds`).

---

### F3-S07 — Mardi soir : incident chronométré  `CHRONO` `★★★★`

> **Ticket INC-5907** — *Téléphone d'astreinte, 21 h 04*
> *(Le symptôme s'affiche à l'injection, tel qu'il arrive.)*

**Objectifs pédagogiques**
- Tenir un incident inconnu, seul, le soir, en temps limité : trier, rétablir, communiquer.
- Réutiliser ses runbooks et son index (S01) au lieu de sa mémoire.
- Garder un rythme de messages d'état réguliers sous pression.

**Prérequis** : F3-S01 à F3-S06 ; les modules du réservoir (M15, M16, M27, M28).
**Durée** : **45 min**, chronométrées, **sans ouvrir aucun corrigé** (ni du final ni des modules). Tes runbooks, ta trousse, la documentation officielle et le dépôt sont autorisés.

**Contexte technique**
- L'injection tire **une** panne au hasard dans un réservoir de pannes déjà rencontrées dans les modules (elles visent la recette ou des objets d'essai, jamais la production). Elle te montre le message tel qu'il arrive.
- Le chrono part à l'affichage du symptôme : note cette heure comme heure d'`[ouverture]` de INC-5907.
- Messages d'état **toutes les 15 min au plus** (courriel + entrée `[état]`), quelle que soit la gravité que tu retiens.

**Injection** : `lab/bin/break F3 7` (5 possibilités).

**Travail demandé**
1. Ouvre INC-5907 à l'heure de l'appel ; message d'état n° 1 dans les 15 min.
2. Rétablis le service touché ; corrige par le code si la cause est dans le code.
3. Clôture dans les 45 min ; consigne ce que tu as laissé pour le lendemain (tickets `PLAT-3307`).

**Critères de réussite**
- [ ] Le service touché est rétabli ; le contrôle de santé est vert.
- [ ] Entre `[ouverture]` et `[clôture]` de INC-5907 : 45 min au plus, et un message d'état consigné au moins toutes les 15 min ; au moins un message d'état envoyé par courriel.

**Vérification** : `lab/bin/check F3 7`

*(Pas d'indice : c'est un chronométré.)*

**Pour aller plus loin** (facultatif) : relance un second tirage un autre soir (`lab/bin/break F3 7`, une fois le premier clos), sous l'identifiant `INC-5907b` pour ne pas mélanger les deux dans les contrôles, et compare tes deux mains courantes : qu'as-tu fait plus vite la seconde fois, et grâce à quoi ?
