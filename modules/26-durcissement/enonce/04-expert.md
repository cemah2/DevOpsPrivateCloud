# Module 26 — Palier 4 : Expert

Le durcissement de MédiSphère est en place : le parc est mesuré chaque semaine contre CIS et ANSSI, le rôle Ansible `durcissement` a durci les hôtes par vagues, Pod Security Admission impose `restricted`, Kyverno refuse ce qui n'est pas conforme, Falco et Tetragon regardent ce que font les processus, Cilium chiffre le trafic entre nœuds et filtre les hôtes, les kubelets ont des certificats vérifiés. Sophie Laurent pose la question de l'auditeur : « Et quand ça casse ? » Car le durcissement casse : une politique trop stricte bloque une livraison, une exception trop large laisse passer un pod privilégié, un agent de détection devient muet, `sudo` ne répond plus, un service confiné refuse de démarrer, deux nœuds ne se parlent plus, `kubectl logs` renvoie une erreur TLS. Puis un vrai incident : un conteneur se comporte comme s'il était compromis. Nadia Roussel a posé sa condition dès le début — **le durcissement ne doit pas casser l'astreinte** — et c'est maintenant qu'on la vérifie. Enfin tu ouvres le capot (eBPF, LSM, chaîne d'admission) et tu passes les questions d'entretien.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger **à la racine et par le code**, prévenir la récidive. Avec trois règles propres à la sécurité :
- **Ne désactive jamais le contrôle pour « voir ».** `setenforce 0`, retirer une politique Kyverno, mettre un webhook en `failurePolicy: Ignore`, désactiver AppArmor : ce sont des gestes qui masquent le symptôme et ouvrent un trou. On diagnostique **avec** le contrôle en place (mode audit, journaux de refus, `--dry-run=server`), on corrige la charge ou la règle, pas l'inverse.
- **Garde toujours un accès de secours.** Avant de toucher à `sudo`, à SSH, à l'admission ou au chiffrement entre nœuds : une session root ouverte, un compte de bris de glace testé, la console Proxmox et l'agent QEMU joignables. Les pannes de ce palier qui cassent `sudo` ou l'accès à un nœud s'annulent **par l'agent QEMU** (`qm guest exec`), jamais en dépendant de l'accès cassé.
- **Git fait foi, Argo CD réconcilie.** Les politiques (Kyverno, Falco, Tetragon), les étiquettes d'espaces et le pare-feu d'hôte vivent dans `plateforme/politiques` et `plateforme/k8s`. Une réparation à la main sur un objet géré par Argo CD est défaite en quelques secondes (`selfHeal`). Les corrections passent par une MR ; seuls les objets hors Git (un `PolicyException` posé en urgence, une étiquette de quarantaine) se réparent sur place, et la réparation se reporte dans le code.

> **Rappels** : tout se lance depuis `adm01`. Admission : `kubectl get validatingpolicies,imagevalidatingpolicies,mutatingpolicies,generatingpolicies.policies.kyverno.io`, `kubectl get policyreports -A`, `kubectl get clusterpolicyreports`. Détection : espace `falco` (falcosidekick → Alertmanager `kps-alertmanager.supervision:9093` et Loki locataire `audit`, `service="falco"`), espace `tetragon` (`service="tetragon"`). Conformité : `oscap`, Lynis, `ssh-audit` sur les hôtes ; métriques `medisphere_conformite_*` dans la vue globale (10.10.41.60). Nœuds : `cilium encrypt status`, `cilium-dbg status`, `hubble observe --verdict DROPPED|AUDIT`, `kubectl get csr`. Bris de glace : `admin.conf` (Vault `critique`), `admin` local des VMs, console Proxmox, agent QEMU.

## Règles du jeu des pannes (M26-E35 à M26-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 26 35
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab (ta configuration diffère du corrigé, ou **ta CI refuse la MR** : c'est alors elle qui a gagné), le script en essaie une autre.
- **Comment les pannes touchent ce qui est dans Git.** Comme une vraie erreur humaine : Lucas Martin ouvre une MR (jeton d'emprunt d'identité créé par ton jeton d'administration GitLab `WB_GITLAB_ADMIN_TOKEN_FILE`, puis révoqué), elle est fusionnée (fusion automatique au succès du pipeline, si ton projet l'exige), Argo CD synchronise. Le commit porte le marqueur `M26-EXX`. Une injection de ce type prend **5 à 20 minutes**. L'annulation passe par une seconde MR (`revert(...)`), jamais par une réécriture d'historique, et seulement si la marque de la panne est encore dans le fichier.
- **Ce que les pannes ne touchent jamais** (PLAN §4.12) : `kube-system`, `kyverno` lui-même, `argocd`, `cilium` ; jamais `adm01`, `gw01`/`gw02` pour `sudo` ; jamais `pbs01` ni le réseau de `pve01`. Les pannes d'hôte ne visent que des VMs non critiques (`nbx01`, `dns02`, `mon01`, un hôte Rocky non critique) ou **un seul** travailleur / nœud de contrôle à la fois. Aucune donnée n'est supprimée.
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 26 35`) : il doit être vert. Le script refuse de casser un cluster qui ne va pas bien (API muette, Applications `kyverno` ou `politiques` non synchronisées, jeton GitLab d'administration absent, `yq` absent) ou un hôte dont l'agent QEMU ne répond pas (le filet de sécurité d'annulation).
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les VMs, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause. L'historique Git et les rapports de politiques, eux, sont des outils de diagnostic légitimes.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 26 35 --annuler` remet l'état sain (filet de sécurité, pas un correctif). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne (sinon elle reste marquée active et bloque l'astreinte M26-E43 et le mini-projet) : l'annulation ne revient jamais sur ta réparation.
- **Tiens un journal de diagnostic** par panne dans `docs/kubernetes/journal/` (cluster) ou `docs/socle/journal/` (VMs) de `~/medisphere`, publié par MR : heure, hypothèse, commande, résultat, conclusion. Les runbooks du palier : **RB-260** (alerte Falco), **RB-262** (réponse à incident conteneur), **RB-263** (durcissement par vagues), **RB-264** (pare-feu d'hôte Cilium), **RB-265** (semaine avant l'audit), dans `docs/securite/durcissement/runbooks/`.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre, ou en désactivant un contrôle, en est un.

> ⚠️ **Les gestes interdits du palier**, sauf mention explicite dans ta démarche avec sa justification : `setenforce 0` ou désactiver AppArmor comme correctif ; retirer une politique Kyverno ou la passer en `Ignore`/`Audit` pour « débloquer » ; mettre un espace applicatif en PSA `privileged` ; désactiver le chiffrement WireGuard du cluster ; approuver une CSR de kubelet sans en comprendre l'origine ; corriger à la main un objet géré par Argo CD et en rester là. Toute exception se code (`durcissement_exceptions`, `PolicyException`, macro Falco) avec justification, valideur et date de revue.

> ⚠️ **Accès de secours** : avant M26-E38 (sudo) et M26-E41 (kubelets), ouvre une session root de secours sur la VM concernée et vérifie que `admin.conf` et la console Proxmox répondent. L'agent QEMU est le dernier recours d'annulation.

---

### M26-E35 — Panne : plus aucun déploiement ne passe en recette  `BF` `★★`

> **Ticket INC-5335** — *De : Julien Petit*
> Depuis cet après-midi, plus aucune MR de déploiement ne finit en recette : Argo CD montre `mediagenda-recette` en échec de synchronisation, ou les pods restent « non prêts ». La prod n'est pas touchée. *(Le détail s'affiche à l'injection.)* On doit livrer une correction avant ce soir.

**Objectifs pédagogiques**
- Lire un refus d'admission de bout en bout : message du webhook, `PolicyReport`/`ClusterPolicyReport`, `validationActions` (`Audit` contre `Deny`), `failurePolicy`, portée (`matchConstraints`, `namespaceSelector`).
- Distinguer « l'objet est **refusé** à l'admission » de « l'objet est admis mais les pods ne **démarrent** pas » (politique de génération qui pose un refus réseau sans DNS ni sondes).
- Corriger la politique au bon endroit (MR dans `plateforme/politiques`) sans ouvrir de trou, et écrire le test `kyverno test` qui l'aurait arrêtée.

**Prérequis** : M26-E07, M26-E15, M26-E16, M26-E18 ; `lab/bin/check 26 35` vert avant l'injection.
**Durée indicative** : 40 min (temps cible).

**Contexte technique** : les politiques CEL de MédiSphère vivent dans `plateforme/politiques` (`kyverno/validation/`, `kyverno/generation/`), rendues par l'Application Argo CD `politiques`. Une `ValidatingPolicy` en `validationActions: [Deny]` **refuse** l'objet ; en `[Audit]` elle ne fait que rapporter. `failurePolicy` décide de ce qui arrive quand la politique ne peut pas rendre de décision. Une `GeneratingPolicy` crée des objets (dont des politiques réseau) dans les espaces qu'elle vise.

**Injection** : `lab/bin/break 26 35` (3 variantes).

**Travail demandé**
1. Constate sans rien toucher : la synchronisation échoue-t-elle à l'**admission** (message `admission webhook … denied the request`) ou les pods sont-ils **non prêts** ? `kubectl -n mediagenda-recette get events`, `kubectl get policyreports -n mediagenda-recette -o wide`, `kubectl -n argocd get application <recette> -o jsonpath='{.status.conditions}'`.
2. Pour un refus : trouve la politique responsable et **pourquoi** elle refuse (lis son `validationActions`, ses `validations`, ses `matchConditions`, sa `failurePolicy`). Rejoue la décision avec `kyverno test` ou un `kubectl apply --dry-run=server` d'un manifeste conforme.
3. Pour des pods non prêts : `kubectl -n mediagenda-recette get ciliumnetworkpolicies` et `hubble observe --namespace mediagenda-recette --verdict DROPPED` ; la politique générée autorise-t-elle le DNS (port 53 vers `kube-dns`) et la collecte des sondes ?
4. Trouve l'origine (commit de `lucas.martin`, marqueur `M26-E35`, ou objet posé hors de Git), corrige à la racine par MR, sans retirer ni affaiblir le contrôle légitime ; nettoie ce qui a été posé à la main. Vérifie qu'une charge conforme passe de nouveau et que la prod n'a jamais bougé.
5. Préviens : un test `kyverno test` dans `plateforme/politiques/kyverno/tests/` qui vérifie qu'une charge conforme de recette est **admise** et qu'une charge non conforme est **refusée** ; complète le runbook concerné.

**Critères de réussite**
- [ ] Une charge conforme est admise **et devient prête** dans `mediagenda-recette` (synchronisation Argo CD réussie) ; l'espace reste en PSA `restricted` ; aucune politique n'a été retirée ni affaiblie pour y arriver.
- [ ] Les rapports de politiques de recette n'ont plus de résultat `error` ; le pipeline de `plateforme/politiques` est vert ; ton journal cite le commit en cause.

**Vérification** : `lab/bin/check 26 35`

<details><summary>Indice 1</summary>

Un échec de synchronisation Argo CD qui dit `denied the request` est un refus d'admission : lis le message, il nomme la politique et la règle. Des pods `Running` mais `0/1 Ready` ne sont pas un refus d'admission : regarde leurs sondes et le réseau.
</details>

<details><summary>Indice 2</summary>

`kubectl get validatingpolicy <nom> -o yaml` : `spec.validationActions`, `spec.failurePolicy`, `spec.matchConditions`. Une expression CEL peut ne pas **pouvoir** s'évaluer sur l'objet reçu : que fait alors la politique, selon sa `failurePolicy` ? Rejoue l'expression sur ton manifeste (`kyverno apply`).
</details>

<details><summary>Indice 3</summary>

`git log` de `plateforme/politiques` (ou l'historique des MR) montre le commit `M26-E35`. Pour le refus réseau : une `CiliumNetworkPolicy`/`NetworkPolicy` de refus par défaut doit toujours laisser sortir le DNS (`k8s:io.kubernetes.pod.namespace=kube-system`, port 53) et laisser entrer la collecte des sondes du kubelet.
</details>

**Pour aller plus loin** : compare le même refus exprimé par une `ValidatingPolicy` Kyverno et par une `ValidatingAdmissionPolicy` native (M26-E17). Laquelle donne le message le plus clair à l'auteur de la MR, laquelle se teste le mieux hors cluster ?

---

### M26-E36 — Panne : un pod privilégié est passé  `BF` `★★★`

> **Ticket SEC-5336** — *De : Sophie Laurent*
> Le rapport de politiques de ce matin montre une charge non conforme **admise** dans un espace applicatif : une image hors de notre registre, ou un pod privilégié. L'admission aurait dû la refuser. Je veux savoir par où c'est passé, et une preuve que le trou est refermé. Lucas a touché aux politiques « pour débloquer un essai » cette semaine.

**Objectifs pédagogiques**
- Comprendre comment une charge échappe à l'admission : `PolicyException` trop large, espace ré-étiqueté `privileged`, `matchConstraints` qui exclut l'espace, exemption d'un groupe d'utilisateurs.
- Lire les rapports (`PolicyReport`, `ClusterPolicyReport`) et distinguer « conforme », « en échec mais admis (audit) », « refusé ».
- Refermer le trou par le code, avec une exception **juste assez large** si le besoin est réel (date, justification, valideur).

**Prérequis** : M26-E06, M26-E07, M26-E17, M26-E18, M26-E23 ; `lab/bin/check 26 36` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : `registres-autorises` (`ValidatingPolicy`, `Deny`) n'admet que `registry.par1.medisphere.internal/*` ; PSA `restricted` refuse un pod privilégié. Une `PolicyException` (`policies.kyverno.io/v1`) exempte des charges **ciblées** d'une politique ; mal écrite, elle exempte tout un espace. Un `namespaceSelector` en `NotIn` retire un espace du périmètre. Une `matchCondition` qui exclut `request.userInfo.groups` d'un groupe (les administrateurs, un compte de service) laisse passer tout ce que ce groupe soumet.

**Injection** : `lab/bin/break 26 36` (4 variantes).

**Travail demandé**
1. Reproduis la détection : quelle charge non conforme a été **admise** ? `kubectl get policyreports -A`, cherche un résultat `fail` non bloquant, ou un pod privilégié vivant (`kubectl get pods -A -o json | jq '… .securityContext.privileged == true'`).
2. Remonte le « par où » : la politique responsable est-elle en `Deny` ? Son `matchConstraints` couvre-t-il l'espace (regarde `namespaceSelector`) ? Une `PolicyException` la vise-t-elle (`kubectl get policyexceptions -A`) ? Une `matchCondition` exempte-t-elle un groupe ? L'espace a-t-il été ré-étiqueté `privileged` (`kubectl get ns <espace> --show-labels`) ?
3. Trouve l'origine (commit `M26-E36` de `lucas.martin`, ou objet posé à la main) et referme **par le code** : retire l'exception trop large ou la réduit à la charge réelle ; remets l'espace en `restricted` ; retire l'exclusion de groupe ; corrige le `namespaceSelector`.
4. Prouve que le trou est refermé : une charge d'essai non conforme est **refusée** au bon endroit (`--dry-run=server`).
5. Préviens : un test `kyverno test` qui vérifie que la politique couvre bien cet espace et ce groupe ; si une exception est légitime, inscris-la au registre `exceptions.md` (règle, périmètre, justification, risque résiduel, valideur, date de revue).

**Critères de réussite**
- [ ] Aucune `PolicyException` n'exempte tout un espace applicatif ; aucun espace applicatif n'est en PSA `privileged` ; `registres-autorises` couvre `wb-pannes` sans exclusion `NotIn` ; aucune politique ne saute un groupe d'utilisateurs.
- [ ] Aucune violation « admise » ne subsiste dans les rapports des espaces applicatifs ; le pipeline de `plateforme/politiques` est vert.

**Vérification** : `lab/bin/check 26 36`

<details><summary>Indice 1</summary>

`kubectl get policyreports -A -o wide` donne le bilan par espace. Une ligne `fail` qui n'a **pas** empêché la création (la charge existe) est le signe d'une politique en `Audit`, d'une exception, ou d'un espace hors périmètre.
</details>

<details><summary>Indice 2</summary>

`kubectl get policyexceptions.policies.kyverno.io -A -o yaml` : une exception dont la `matchCondition` dit `object.metadata.namespace == 'wb-pannes'` exempte **tout** l'espace, pas un pod. `kubectl get ns <espace> -o jsonpath='{.metadata.labels}'` : cherche `pod-security.kubernetes.io/enforce: privileged`.
</details>

**Pour aller plus loin** : une exception bien écrite vise une charge par son nom, son compte de service ou une étiquette, et porte une date d'expiration (`spec.expiresAt`). Écris l'exception minimale pour le besoin réel, et explique pourquoi une exception qui n'expire jamais est une dette de sécurité.

---

### M26-E37 — Panne : Falco est muet  `BF` `★★`

> **Ticket SEC-5337** — *De : Sophie Laurent*
> Mon essai hebdomadaire : j'ouvre un shell dans un pod de `wb-essais`, je lis `/etc/shadow`. D'habitude Falco crie en quelques secondes (Alertmanager, Loki locataire `audit`). Là : rien. La détection à l'exécution, c'est ce qui me reste quand l'admission a laissé passer quelque chose.

**Objectifs pédagogiques**
- Suivre une détection de bout en bout : agent Falco sur **le bon nœud**, règle **chargée** et **non désactivée**, événement produit, falcosidekick, route vers Alertmanager et Loki.
- Lire l'état d'un DaemonSet (couverture des nœuds, `nodeSelector`, tolérances), la configuration chargée (`falco.yaml`, `priority`), les règles montées (`customRules`).
- Régler le bruit sans rendre Falco muet : exception par **macro/liste**, jamais par suppression de règle.

**Prérequis** : M26-E08, M26-E19, M26-E20 ; `lab/bin/check 26 37` vert avant l'injection.
**Durée indicative** : 40 min (temps cible).

**Contexte technique** : Falco 0.45 (pilote `modern_ebpf`) tourne en DaemonSet dans l'espace `falco`, piloté par les valeurs `valeurs/falco/values.yaml` de `plateforme/gitops` ; les règles MédiSphère sont dans `falco/regles-medisphere.yaml` de `plateforme/politiques` (clé `customRules`, troisième source de l'Application `falco`). falcosidekick 2.31 envoie vers Alertmanager (`http://kps-alertmanager.supervision:9093`) et Loki (locataire `audit`, `service="falco"`). La clé `priority` de `falco.yaml` fixe la **priorité minimale** des règles chargées.

**Injection** : `lab/bin/break 26 37` (4 variantes).

**Travail demandé**
1. Reproduis l'essai : ouvre un shell dans un pod de `wb-essais`, lis `/etc/shadow`. Observe où ça se perd : l'événement apparaît-il dans les journaux d'un pod Falco (`kubectl -n falco logs ds/falco`) ? Dans Loki (`{service="falco"}`, locataire `audit`) ? Dans Alertmanager ?
2. Vérifie la **couverture** : `kubectl -n falco get ds falco -o wide` ; `desiredNumberScheduled` vaut-il le nombre de nœuds ? Un `nodeSelector` exclut-il les travailleurs ?
3. Vérifie la **règle** : est-elle chargée (`kubectl -n falco get cm -o yaml | grep -A2 "Shell interactif"`) ? Désactivée par une surcharge (`enabled: false`) ? La priorité minimale (`falco.yaml: priority`) a-t-elle été remontée au-dessus de celle de la règle ?
4. Vérifie l'**acheminement** : falcosidekick pointe-t-il vers la bonne URL d'Alertmanager (port 9093) ?
5. Trouve l'origine (commit `M26-E37`), corrige par MR, rejoue l'essai jusqu'à voir l'alerte arriver. Si le vrai besoin était de réduire le bruit, fais-le par une **exception ciblée** (liste/macro), pas en coupant la règle. Complète **RB-260**.

**Critères de réussite**
- [ ] Le DaemonSet Falco couvre tous les nœuds ; la règle « shell interactif » est chargée et active ; la priorité minimale n'est pas remontée à `critical` ; falcosidekick vise le bon point d'entrée d'Alertmanager.
- [ ] Un essai (shell + lecture de `/etc/shadow`) remonte dans Loki (`service="falco"`) ; le pipeline de `plateforme/politiques` est vert ; RB-260 contient sa section.

**Vérification** : `lab/bin/check 26 37`

<details><summary>Indice 1</summary>

Si les journaux d'un pod Falco contiennent l'événement mais qu'Alertmanager ne reçoit rien, le problème est **en aval** (falcosidekick, route). Si **aucun** pod Falco ne tourne sur le nœud où tu as ouvert le shell, le problème est la **couverture** (DaemonSet, `nodeSelector`).
</details>

<details><summary>Indice 2</summary>

`kubectl -n falco get cm falco -o jsonpath='{.data.falco\.yaml}' | grep -i priority` : si `priority: critical`, les règles `notice`/`warning` ne sont plus chargées. Une surcharge de règle `- rule: … \n enabled: false` dans `customRules` désactive une règle sans la supprimer : cherche-la.
</details>

**Pour aller plus loin** : Falco expose son propre statut (`GET /reload`, métriques). Écris une alerte qui te prévient quand le **nombre d'agents Falco prêts** est inférieur au nombre de nœuds, et une autre quand Falco n'a produit **aucun** événement depuis N heures (un détecteur muet est pire qu'absent).

---

### M26-E38 — Panne : sudo cassé après le durcissement  `BF` `★★`

> **Ticket INC-5338** — *De : Nadia Roussel*
> Le playbook de nuit a échoué sur une VM : `sudo: a password is required` ou `sudo: a terminal is required`. Le compte `admin` ne peut plus rien faire en `sudo` non interactif. C'est arrivé après la vague de durcissement. *(La VM s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Diagnostiquer `sudo` sans se verrouiller : `sudo -l`, `visudo -c`, l'ordre des drop-ins de `/etc/sudoers.d/`, les exigences de **propriété et de mode** d'un fichier inclus, `requiretty`, `timestamp_timeout`, PAM (`pam_faillock`).
- Comprendre pourquoi `sudo` **ignore** un fichier inclus inscriptible par le groupe/les autres, et ce que change `error_recovery` (défaut depuis sudo 1.9.3) sur une erreur de syntaxe.
- Réparer par le code (rôle `durcissement`) en gardant un accès de secours.

**Prérequis** : M26-E10, M26-E11 ; M04 (Ansible, `become`) ; `lab/bin/check 26 38` vert avant l'injection.
**Durée indicative** : 40 min (temps cible).

**Contexte technique** : le compte local `admin` (Ansible, bris de glace) a un drop-in `NOPASSWD` posé par cloud-init (`/etc/sudoers.d/90-cloud-init-users`) ou par le rôle. Ansible et les checks utilisent `sudo -n` (non interactif, sans terminal). Le rôle `durcissement` pose `Defaults use_pty`, `logfile`, `timestamp_timeout=5` ; mal réglé, il casse `sudo -n`. **L'agent QEMU de la VM répond encore** (root dans l'invité, sans `sudo`) : c'est ton filet de sécurité, et c'est par lui que `lab/bin/break 26 38 --annuler` restaure.

> ⚠️ **Attention** : ne te verrouille pas. Ouvre d'abord une **session root de secours** (console Proxmox, ou `sudo -i` tant que ça marche) et garde-la. Teste tes correctifs sur un drop-in, jamais en éditant `/etc/sudoers` directement sans `visudo`.

**Injection** : `lab/bin/break 26 38` (3 variantes).

**Travail demandé**
1. Depuis `adm01`, reproduis l'échec : `ssh <vm> sudo -n true`. Lis le message exact (mot de passe requis ? terminal requis ?).
2. Avec ta session de secours (root), diagnostique : `visudo -c` (syntaxe), `sudo -l -U admin`, `ls -l /etc/sudoers.d/` (modes, propriétaire), `grep -R requiretty /etc/sudoers*`, `grep -R timestamp_timeout /etc/sudoers*`, `faillock --user admin`.
3. Classe la cause : `requiretty` (sudo exige un tty) ; drop-in **ignoré** parce qu'inscriptible par le groupe/les autres (mode) ; `NOPASSWD` retiré + `timestamp_timeout=0` (réauthentification à chaque appel). Explique pourquoi chacune casse précisément `sudo -n`.
4. Corrige **par le rôle `durcissement`** (variable ou gabarit), pas à la main : rejoue le rôle (ou, si l'accès est cassé, restaure par l'agent QEMU puis corrige le rôle). Vérifie `ssh <vm> sudo -n true`.
5. Préviens : un contrôle (molecule ou `--check`) qui vérifie que `sudo -n` d'`admin` marche après durcissement, et que les drop-ins sont en `0440` propriété `root`.

**Critères de réussite**
- [ ] `sudo -n true` du compte `admin` fonctionne sur la VM ; aucun `Defaults requiretty` ; aucun drop-in sudoers inscriptible par le groupe/les autres ; `visudo -c` passe.
- [ ] La correction est dans le rôle (pas seulement sur la VM) ; ton journal explique laquelle des trois causes et pourquoi.

**Vérification** : `lab/bin/check 26 38`

<details><summary>Indice 1</summary>

`sudo` **ignore silencieusement** un fichier de `/etc/sudoers.d/` qui est inscriptible par le groupe ou les autres, ou qui n'appartient pas à root. `ls -l` : un fichier en `0666` ne sera pas lu, donc la règle `NOPASSWD` qu'il contient disparaît. Le mode attendu est `0440`.
</details>

<details><summary>Indice 2</summary>

Depuis sudo 1.9.3, une **erreur de syntaxe** n'empêche plus sudo de tourner (l'entrée fautive est écartée, `error_recovery=true` par défaut) : ce n'est donc probablement pas une faute de frappe. `requiretty` fait échouer tout `sudo` sans terminal : Ansible en *pipelining* et `ssh host sudo -n` n'ont pas de tty. `timestamp_timeout=0` sans `NOPASSWD` force une saisie de mot de passe à chaque appel.
</details>

**Pour aller plus loin** : la variante PAM (`pam_faillock`) verrouille un compte après N échecs. Qu'est-ce qui, dans le durcissement, pourrait verrouiller le compte d'automatisation par accident (un test de mot de passe, un scan) ? Comment exclure les comptes de service du verrouillage sans affaiblir celui des personnes ?

---

### M26-E39 — Panne : un service confiné ne démarre plus  `BF` `★★★`

> **Ticket INC-5339** — *De : Nadia Roussel*
> Sur une VM du socle, un service refuse de démarrer depuis la vague de durcissement : `systemctl status` le montre en échec, le journal parle de permission refusée alors que les droits du fichier ont l'air bons. On a posé du MAC (AppArmor/SELinux) et durci des unités systemd cette semaine.

**Objectifs pédagogiques**
- Lire un refus de MAC : AppArmor (`aa-status`, `dmesg`/`journalctl` `apparmor="DENIED"`, mode *complain* contre *enforce*), SELinux (`getenforce`, `ausearch -m AVC`, `sealert`, contextes de fichiers), durcissement systemd (`ProtectSystem`, `ReadWritePaths`, `systemd-analyze security`).
- Comprendre pourquoi « les droits Unix sont bons » ne suffit pas quand un LSM ou une unité durcie interdit l'accès.
- Corriger en **gardant le confinement** : ajouter le chemin manquant au profil / au contexte / aux `ReadWritePaths`, jamais `setenforce 0` ni `aa-disable`.

**Prérequis** : M26-E13 ; `lab/bin/check 26 39` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : sur `mon01` (Debian), Mailpit est confiné deux fois : par un profil AppArmor (`/etc/apparmor.d/usr.local.bin.mailpit`, E13) et par son unité systemd durcie (M19 : `ProtectSystem=strict` et ses exceptions). Sur les hôtes Rocky (SELinux *enforcing*), seuls les programmes qui ont un **domaine** sont confinés (la vérification AIDE tourne en `aide_t` ; ce qui est installé dans `/usr/local/bin` tourne en `unconfined_service_t`, E13) ; un domaine n'accède qu'aux fichiers dont le **contexte** le permet. Un `ProtectSystem=strict` rend tout le système de fichiers en lecture seule pour le service, sauf ce que l'unité excepte.

> ⚠️ **Attention** : ne désactive pas le MAC pour « voir ». Un refus AppArmor/SELinux se lit dans les journaux ; la correction consiste à **autoriser le chemin légitime**, pas à retirer le confinement.

**Injection** : `lab/bin/break 26 39` (3 variantes).

**Travail demandé**
1. Identifie le service en échec : `systemctl --failed`, `systemctl status <unité>`, `journalctl -u <unité> --since -20min`.
2. Cherche le refus : AppArmor (`journalctl -k | grep apparmor` ou `dmesg | grep DENIED`), SELinux (`ausearch -m AVC -ts recent`, `sealert`), ou unité durcie (`systemd-analyze security <unité>`, `systemctl cat <unité>`).
3. Trouve ce que le refus désigne : un chemin absent du profil (compare au profil du rôle), un contexte SELinux différent de celui que la politique attend (`ls -Z` contre `matchpathcon`), une restriction d'unité ajoutée (`systemctl cat <unité>` : quels drop-ins, dans quel ordre ?).
4. Corrige en gardant le confinement : ajoute la règle au profil (`aa-logprof` en *complain* puis *enforce*), remets le bon contexte (`restorecon`, ou un `semanage fcontext` pour le rendre durable), ajoute le `ReadWritePaths`. Rejoue par le rôle `durcissement`. Redémarre le service, vérifie qu'il est `active`.
5. Préviens : explique dans le runbook comment lire un refus de MAC, et pourquoi la correction se code (profil, contexte durable, drop-in d'unité) et non à la main.

**Critères de réussite**
- [ ] Le service est `active` ; AppArmor reste en *enforce* / SELinux reste *enforcing* ; aucun refus AVC récent sur le service.
- [ ] La correction est dans le code (rôle `durcissement`) ; ton journal cite le refus exact (ligne `DENIED`/`AVC`).

**Vérification** : `lab/bin/check 26 39`

<details><summary>Indice 1</summary>

Un service qui ne démarre pas « alors que les droits sont bons » : regarde **au-dessus** des droits Unix. `journalctl -k | grep -i apparmor` montre `operation="open" … name="/var/lib/mailpit/…" … denied_mask="wr"`. `ausearch -m AVC -ts recent` montre un `avc: denied { read } for … scontext=… tcontext=unconfined_u:object_r:user_tmp_t`.
</details>

<details><summary>Indice 2</summary>

`systemd-analyze security <unité>` note l'exposition d'une unité et liste ce qui est restreint. `ProtectSystem=strict` rend `/usr`, `/boot` et `/etc` en lecture seule, et **tout le reste** sauf ce que `ReadWritePaths` autorise : un service qui écrit dans `/var/lib/…` a besoin que ce chemin y soit.
</details>

**Pour aller plus loin** : élabore un profil AppArmor en mode *complain*, laisse tourner le service un moment, puis génère les règles avec `aa-logprof` et passe en *enforce*. Qu'est-ce que cette méthode (observer puis durcir) a de commun avec le mode `Audit` de Kyverno et le mode audit du pare-feu d'hôte de Cilium (E27) ?

---

### M26-E40 — Panne : des nœuds ne se parlent plus  `BF` `★★★`

> **Ticket INC-5340** — *De : Nadia Roussel*
> Depuis la vague « réseau » du durcissement (pare-feu d'hôte, chiffrement WireGuard), des pods d'un nœud n'arrivent plus à joindre ceux des autres : des connexions tombent, des sondes échouent par intermittence, Hubble montre des paquets perdus. Un seul travailleur semble concerné.

**Objectifs pédagogiques**
- Diagnostiquer la connectivité inter-nœuds de Cilium : `cilium-dbg status`, `cilium encrypt status`, `hubble observe --verdict DROPPED` et `--verdict AUDIT`, `cilium_unreachable_nodes`, la santé Cilium (port 4240), WireGuard (`cilium_wg0`, UDP 51871).
- Distinguer un refus du **pare-feu d'hôte Cilium** (politique qui oublie un flux), un filtrage **nftables local** du nœud, et une **MTU** incohérente.
- Corriger un seul nœud à la fois, avec un retour arrière écrit (RB-264).

**Prérequis** : M26-E26, M26-E27 ; M15 (Cilium, Hubble) ; `lab/bin/check 26 40` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : le pare-feu d'hôte Cilium s'exprime par des `CiliumClusterwideNetworkPolicy` avec `nodeSelector` (`plateforme/k8s/composants/cilium/hote/` : `hote-commun`, `hote-plan-controle`, `hote-travailleurs`, qui sélectionnent les nœuds étiquetés `medisphere.internal/pare-feu-hote: "oui"`, M26-E27), posées **un nœud à la fois** après une phase d'audit **du point de terminaison d'hôte** du nœud (`outils/pare-feu-hote.sh audit <nœud>`, RB-264 ; jamais l'option globale `policyAuditMode` du chart, qui mettrait aussi en audit toutes les politiques des pods). Les flux à autoriser entre nœuds : kubelet 10250, santé Cilium 4240, WireGuard 51871/UDP, VXLAN 8472 (si tunnel), API 6443/8443, BGP 179.

> ⚠️ **Attention** : un seul nœud à la fois. Si tu repasses une politique de pare-feu d'hôte, remets d'abord le point de terminaison d'hôte du nœud en audit (`outils/pare-feu-hote.sh audit <nœud>`, observe les verdicts `AUDIT`) avant d'appliquer. L'accès console Proxmox et l'agent QEMU restent ton recours.

**Injection** : `lab/bin/break 26 40` (3 variantes).

**Travail demandé**
1. Identifie le nœud et le symptôme : `kubectl get nodes`, `hubble observe --verdict DROPPED --last 50`, `cilium-dbg status` (sur l'agent du nœud), `cilium encrypt status`.
2. Classe : un refus **vu par Cilium** (Hubble le montre, avec la politique en cause ; le mode audit du point de terminaison d'hôte le confirme sans couper), une perte **hors de Cilium** (Hubble ne voit rien : compare ce qui sort d'un nœud et ce qui arrive sur l'autre, `tcpdump`, ce qui filtre localement sur le nœud), ou une perte qui dépend de la **taille** des paquets (petits paquets qui passent, gros qui disparaissent).
3. Trouve l'origine en comparant le nœud touché à un nœud sain et au code (`plateforme/k8s/composants/cilium/hote/`, `cluster/noeuds.yaml`, rôles Ansible des nœuds), et corrige à la racine : ce qui vit dans Git par MR, ce qui a été posé à la main sur le nœud retiré (et vérifie que rien ne le reposera).
4. Vérifie : tous les nœuds `Ready`, `cilium encrypt status` cohérent, `cilium_unreachable_nodes == 0`, Hubble sans refus inattendu.
5. Préviens : complète **RB-264** (pare-feu d'hôte : toujours passer par le mode audit, un nœud à la fois, flux à autoriser listés) ; une alerte sur `cilium_unreachable_nodes > 0`.

**Critères de réussite**
- [ ] Tous les nœuds `Ready` ; aucune `CiliumClusterwideNetworkPolicy` d'essai ne reste ; aucune table nftables d'essai sur le nœud ; MTU cohérente (≥ 1450) ; `cilium_unreachable_nodes == 0`.
- [ ] Ton journal cite le flux/la règle/la MTU en cause ; RB-264 contient la procédure.

**Vérification** : `lab/bin/check 26 40`

<details><summary>Indice 1</summary>

`hubble observe --verdict DROPPED` montre un refus de **politique** (avec le nom de la politique) ; un paquet jeté par un **pare-feu local** du nœud (nftables) n'apparaît pas dans Hubble. Si Hubble ne montre rien mais que ça tombe quand même, regarde `nft list ruleset` sur le nœud et la MTU.
</details>

<details><summary>Indice 2</summary>

`cilium encrypt status` doit montrer des paires chiffrées cohérentes entre nœuds ; si un nœud ne chiffre plus, soupçonne le port WireGuard (51871/UDP) filtré localement. Une MTU incohérente se voit en comparant `ip link show eth0` entre nœuds : seuls les gros transferts tombent.
</details>

**Pour aller plus loin** : le mode audit du point de terminaison d'hôte (`PolicyAuditMode`, réglé par nœud dans l'agent) laisse passer le trafic tout en journalisant ce qui **serait** refusé (`hubble observe --verdict AUDIT`). Explique pourquoi on applique toujours un pare-feu d'hôte en audit d'abord, nœud par nœud, et ce qui se passerait si on l'appliquait partout d'un coup en `enforce`.

---

### M26-E41 — Panne : `kubectl logs` et `exec` refusés  `BF` `★★`

> **Ticket INC-5341** — *De : Julien Petit*
> Je n'arrive plus à voir les journaux d'un pod : `kubectl logs` renvoie une erreur TLS (x509) ou reste bloqué ; `kubectl exec` aussi. Parfois ça marche, parfois non. C'est arrivé après la sécurisation des kubelets (certificats de service, approbation des CSR).

**Objectifs pédagogiques**
- Comprendre le chemin de `kubectl logs/exec` : apiserver → kubelet 10250 en TLS, **certificat de service** du kubelet, et ce que change `--kubelet-certificate-authority` côté apiserver.
- Diagnostiquer `serverTLSBootstrap` et kubelet-csr-approver : CSR `kubernetes.io/kubelet-serving` en attente ou refusée, configuration et état de l'approbateur, CA côté apiserver.
- Réparer un seul nœud (de contrôle) à la fois, sans ouvrir de faille (ne jamais approuver une CSR sans comprendre).

**Prérequis** : M26-E25 ; M14 (kubeadm, manifestes statiques) ; `lab/bin/check 26 41` vert avant l'injection.
**Durée indicative** : 40 min (temps cible).

**Contexte technique** : les kubelets ont `serverTLSBootstrap: true` : sans certificat de service **signé**, un kubelet n'en présente aucun sur 10250. Ce certificat est signé après approbation d'une CSR `kubernetes.io/kubelet-serving` par **kubelet-csr-approver** (M26-E25 : Application Argo CD, valeurs dans `plateforme/gitops`). Côté serveur d'API, l'option `--kubelet-certificate-authority` (que kubeadm ne pose pas) lui fait **vérifier** ce certificat ; sans elle, il ne le vérifie pas. La poignée de main TLS de `logs`/`exec` dépend donc des deux bouts.

> ⚠️ **Attention** : si tu touches à un manifeste statique du plan de contrôle, **un seul nœud à la fois**, et garde `admin.conf` (bris de glace) de côté. L'annulation du workbook passe par l'agent QEMU.

**Injection** : `lab/bin/break 26 41` (3 variantes).

**Travail demandé**
1. Reproduis : `kubectl logs <pod>` ; lis l'erreur exacte (`x509: certificate signed by unknown authority`, `x509: certificate has expired or is not yet valid`, timeout). Note si c'est **constant** (un nœud) ou **intermittent** (un apiserver sur trois).
2. Remonte : `kubectl get csr` (une CSR `kubelet-serving` récente : quelle condition ?), `kubectl get csr <nom> -o yaml` (signer, username, condition et message), l'état et les journaux de l'approbateur, ses valeurs et leur historique dans `plateforme/gitops`, ce que présente le kubelet du nœud (`openssl s_client -connect <ip>:10250`), et sur chaque nœud de contrôle les options `--kubelet-*` du manifeste du serveur d'API.
3. Classe le symptôme : **un nœud** touché en permanence (côté kubelet), ou **une requête sur trois** (côté serveur d'API) ; puis le maillon exact, preuve à l'appui.
4. Corrige au bon endroit (MR pour ce qui vit dans Git ; un seul nœud de contrôle à la fois pour un manifeste statique) ; une CSR ne s'approuve à la main que si son origine et son contenu sont vérifiés. Vérifie que `kubectl logs/exec` marche sur tous les pods.
5. Préviens : une alerte sur une CSR `kubelet-serving` en attente depuis plus de N minutes ; une alerte sur l'expiration des certificats de service des kubelets.

**Critères de réussite**
- [ ] Aucune CSR `kubelet-serving` en attente ; l'approbateur tourne et sa configuration couvre tous les nœuds ; la configuration des nœuds de contrôle vis-à-vis des kubelets est cohérente ; chaque kubelet présente un certificat de service ; `kubectl logs` d'un pod du nœud touché fonctionne.
- [ ] Ton journal cite l'erreur TLS exacte et la cause.

**Vérification** : `lab/bin/check 26 41`

<details><summary>Indice 1</summary>

`kubectl get csr` : une ligne `kubelet-serving` récente d'un `Requestor` `system:node:<nœud>` signifie que le kubelet a redemandé un certificat. `Pending` : personne ne l'a traitée (l'approbateur tourne-t-il ?) ; `Denied` : l'approbateur l'a refusée (lis le message, puis sa configuration). `remote error: tls: internal error` côté client : le kubelet n'a **aucun** certificat à présenter.
</details>

<details><summary>Indice 2</summary>

Une erreur **intermittente** (une fois sur trois) pointe vers **un** des trois kube-apiserver : compare leurs manifestes (`diff` des trois). `x509: certificate signed by unknown authority` vient du côté qui **vérifie**.
</details>

**Pour aller plus loin** : `bypassDnsResolution` de kubelet-csr-approver. Pourquoi le résoudre (ou non) change-t-il la robustesse de l'approbation quand le DNS du cluster est perturbé ? Quel est le risque de sécurité d'une approbation automatique trop permissive ?

---

### M26-E42 — Incident : un conteneur compromis  `BF` `★★★`

> **Ticket INC-5342** — *De : Sophie Laurent* — priorité P1
> Falco (ou Tetragon) remonte un comportement anormal dans un pod de `wb-pannes` : un processus `kdevtmpfsi`, la lecture du jeton de compte de service par un processus inattendu, une tentative de sortie vers une adresse inconnue, un binaire exécuté depuis `/tmp`. Traite-le comme une compromission.

> **Note du workbook** : le pod est un **témoin strictement inoffensif**. Il ne mine rien, ne calcule rien, n'exfiltre rien : il **imite les signes** d'une compromission pour que tu t'entraînes à la réponse. Aucun vrai code malveillant n'est exécuté.

**Objectifs pédagogiques**
- Mener une réponse à incident sur un conteneur : **détecter** (Falco/Tetragon, journal d'audit), **isoler** (étiquette de quarantaine + `CiliumClusterwideNetworkPolicy`), **collecter** les preuves (conteneur éphémère `kubectl debug`, journaux, `checkpoint` si disponible, instantané), **éradiquer**, **rétablir**, **rédiger**.
- Travailler sans détruire les preuves (ne pas supprimer le pod avant d'avoir collecté).
- Éprouver un runbook écrit à l'avance (RB-262, E33), le compléter, et rédiger un post-mortem.

**Prérequis** : M26-E08, M26-E19, M26-E20, M26-E29, M26-E33 ; `lab/bin/check 26 42` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : la quarantaine est préparée **à l'avance** (M26-E33) : une étiquette `medisphere.internal/quarantaine: "oui"` et une `CiliumClusterwideNetworkPolicy` `quarantaine` qui coupe toute entrée/sortie du pod étiqueté. Les preuves vont dans `s3-01` compartiment `preuves`. Falco et Tetragon acheminent vers Loki (`audit`). Le témoin vit dans `wb-pannes` (PSA `restricted`, non-root).

**Injection** : `lab/bin/break 26 42` (3 variantes : mineur factice ; + « exfiltration » factice ; + persistance par CronJob).

**Travail demandé**
1. **Détecte** : qu'a vu Falco (`{service="falco"}`, `audit`) et Tetragon (`{service="tetragon"}`) ? Identifie le pod, le processus, le comportement (`kubectl -n wb-pannes get pods`, `kubectl -n wb-pannes describe pod <pod>`).
2. **Isole** sans tuer : étiquette le pod `medisphere.internal/quarantaine=oui` (la `CiliumClusterwideNetworkPolicy` `quarantaine` coupe son réseau) ; vérifie avec Hubble qu'il ne sort plus.
3. **Collecte** : `kubectl debug` (conteneur éphémère) pour inspecter les processus et `/tmp` ; copie les journaux Falco/Tetragon/audit pertinents ; prends un instantané (description du pod, `kubectl get pod -o yaml`, liste des processus) ; dépose les preuves dans `s3-01/preuves` (empreintes `sha256`). **Ne supprime rien avant d'avoir collecté.**
4. **Éradique** : supprime le Deployment `wb-mineur` **et** la persistance (CronJob `wb-persistance` s'il existe). Vérifie qu'aucun pod de l'incident ne subsiste.
5. **Rétablis** et **rédige** : retire la quarantaine une fois l'espace sain ; **complète RB-262** (écrit en E33) de ce que l'incident t'a appris (écarts entre le runbook et la réalité, retour d'expérience) ; rédige le journal et le post-mortem de `INC-5342`.

**Critères de réussite**
- [ ] Le Deployment `wb-mineur` et le CronJob `wb-persistance` sont supprimés ; aucun pod de l'incident ne subsiste ; la politique `quarantaine` existe (posée en E33).
- [ ] RB-262 couvre les cinq étapes (détection → isolement → collecte → éradication → rétablissement) et porte le retour d'expérience de `INC-5342` ; le journal et le post-mortem `INC-5342` sont commités ; des preuves sont consignées (empreintes dans `s3-01/preuves`, référencées dans le journal).

**Vérification** : `lab/bin/check 26 42`

<details><summary>Indice 1</summary>

L'ordre compte : **isoler avant d'éradiquer** (sinon une persistance relance le pod), **collecter avant de supprimer** (sinon tu perds les preuves). L'étiquette de quarantaine agit immédiatement si la `CiliumClusterwideNetworkPolicy` `quarantaine` sélectionne `medisphere.internal/quarantaine: "oui"`.
</details>

<details><summary>Indice 2</summary>

`kubectl debug -n wb-pannes <pod> --image=… --target=<conteneur>` attache un conteneur éphémère pour inspecter sans redémarrer. Une persistance par `CronJob` relance le pod chaque minute : `kubectl -n wb-pannes get cronjob` ; tant qu'il existe, l'éradication ne tient pas.
</details>

**Pour aller plus loin** : la fonction `ContainerCheckpoint` du kubelet (statut en 1.36 à vérifier) permet de figer un conteneur pour analyse hors ligne sans l'arrêter. Compare avec un instantané du disque du nœud (PBS). Qu'est-ce que chacun préserve, et qu'est-ce qu'un attaquant pourrait faire disparaître entre la détection et la collecte ?

---

### M26-E43 — Astreinte : la semaine avant l'audit  `BF` `★★★★`

> **Ticket INC-5343** — *De : Nadia Roussel (responsable astreinte)* — priorité P2
> Tu es d'astreinte, la semaine avant l'audit HDS. Plusieurs remontées à la fois (le détail s'affiche à l'injection), et la conformité d'une VM a baissé. L'auditeur vient dans quelques jours : à la fin, le parc doit être mesuré et conforme, l'admission doit refuser ce qui ne l'est pas, la détection doit fonctionner, et tu dois pouvoir montrer une réponse à incident.

**Objectifs pédagogiques**
- Gérer un incident à causes multiples **sur les contrôles de sécurité eux-mêmes** sans ouvrir de trou ni casser l'astreinte.
- Prioriser : d'abord ce qui laisse passer une vraie attaque (admission trouée, détection muette), puis ce qui bloque le travail (déploiements, `sudo`, nœuds), puis la dérive de conformité.
- Communiquer pendant l'incident, rédiger un post-mortem centré sur la **détection** et la **prévention**, et un runbook de la semaine avant l'audit (RB-265).

**Prérequis** : M26-E35 à M26-E42 (au moins une variante de chacun).
**Durée indicative** : 2 h de rétablissement + 45 min de post-mortem.

**Contexte technique** : le script tire **deux** pannes distinctes parmi M26-E35 à M26-E42 (jamais E40 avec E41, jamais E38 avec E39), avec une variante au hasard, **plus** une dérive de conformité sur une VM non critique (un réglage de durcissement défait : SSH `PermitRootLogin yes`, un sysctl). `--variante N` force le couple, pas les variantes. `--annuler` retire tout. Modèle de post-mortem : [`modules/00-lab/ressources/M00-E46/modele-post-mortem.md`](../../00-lab/ressources/M00-E46/modele-post-mortem.md).

**Injection** : `lab/bin/break 26 43`

**Travail demandé**
1. **Triage (15 min max)** : liste les symptômes et leur impact (qui pourrait attaquer quoi sans être vu ? qui est bloqué ?). Vérifie tes instruments de sécurité : l'admission refuse-t-elle encore une charge non conforme ? Falco crie-t-il à un essai ? La conformité remonte-t-elle encore ? Envoie la première communication.
2. **Diagnostic** : traite dans un ordre que tu justifies (priorité au trou d'admission et à la détection muette) ; tiens ton journal horodaté ; garde les sorties qui prouvent chaque cause.
3. **Rétablissement** : corrige chaque cause racine par le chemin normal (MR, rôle Ansible), **sans désactiver de contrôle** ; répare la dérive de conformité par le rôle `durcissement` ; après chaque correction, relance tes tests.
4. **Clôture** : communication de fin, `--annuler` pour clore, puis post-mortem `docs/kubernetes/post-mortems/AAAA-MM-JJ-INC-5343.md` (publié par MR) avec une section **Détection** (pour chaque cause, ce qui aurait dû la signaler), et **RB-265** (la semaine avant l'audit : checklist, ordre de priorité, ce qu'on ne touche pas).

**Critères de réussite**
- [ ] Toutes les vérifications de M26-E35 à M26-E42 sont vertes (le contrôle les rejoue) et aucune panne n'est encore active ; la dérive de conformité est réparée (aucune VM ne ré-autorise `PermitRootLogin yes`).
- [ ] Le post-mortem existe (chronologie, causes racines, extraits de diagnostic, analyse de détection), sans aucun secret ; RB-265 est rédigé et commité.

**Vérification** : `lab/bin/check 26 43`

<details><summary>Indice 1</summary>

Ordre de confiance : les API brutes (`kubectl get policyreports`, `kubectl get csr`, `hubble observe`) et les journaux `audit` de Loki avant tout tableau. Une **détection muette** (Falco) et un **trou d'admission** sont les deux pannes à traiter en premier : tant qu'elles durent, une vraie attaque passerait inaperçue.
</details>

<details><summary>Indice 2</summary>

Ne cède pas à la tentation de désactiver un contrôle pour « gagner du temps » : un `setenforce 0` ou un webhook en `Ignore` la nuit avant l'audit est exactement ce que l'auditeur cherche. Chaque correction passe par Git (traçable, relue, défaite par `revert`).
</details>

**Pour aller plus loin** : prépare la **revue de l'auditeur** (M26-E46) à partir de cet incident : pour chaque panne, quelle preuve montrerais-tu à Sophie que le contrôle est revenu et qu'il détecterait la prochaine fois ?

---

### M26-E44 — Sous le capot : eBPF, LSM et chaîne d'admission  `LAB` `★★★★`

> **Ticket PLAT-2744** — *De : Karim Benali*
> On a parlé d'« eBPF », de « hooks LSM », de « chaîne d'admission » comme de boîtes noires. Je veux que tu ouvres le capot et que tu **montres** : quels programmes eBPF Falco, Tetragon et Cilium chargent, où s'accrochent les LSM, dans quel ordre l'API passe une requête par authentification → autorisation → mutation → validation → persistance, et comment un `auditID` relie tout. Sur le lab, en lecture. Compte rendu pour les prochains arrivants.

**Objectifs pédagogiques**
- Lister et lire les programmes eBPF chargés (`bpftool prog show`, `bpftool prog`, types `kprobe`/`tracepoint`/`lsm`/`tc`/`cgroup`), et relier chacun à son produit (Falco, Tetragon, Cilium).
- Situer les LSM (ordre d'empilement `/sys/kernel/security/lsm`, AppArmor/SELinux/BPF-LSM, hook `security_*`), et le lien avec seccomp.
- Décrire la chaîne d'admission de kube-apiserver (authentification, autorisation, webhooks de mutation, webhooks et politiques CEL de validation, persistance) et suivre une requête par son `auditID` dans le journal d'audit.

**Prérequis** : M26-E05, M26-E06, M26-E07, M26-E17, M26-E20, M26-E28 ; M22 (journal d'audit dans Loki).
**Durée indicative** : 3 h.

**Contexte technique**
- Sur un nœud (en lecture) : `bpftool` (paquet `linux-tools`/`bpftool`), `/sys/kernel/security/lsm`, `/sys/fs/bpf`. Falco en `modern_ebpf`, Tetragon et Cilium chargent leurs propres programmes.
- Chaîne d'admission : `AuthenticationConfiguration` (M24), autorisation RBAC, webhooks de mutation (Kyverno `MutatingPolicy`, `MutatingAdmissionPolicy` native), validation (Kyverno `ValidatingPolicy`, `ValidatingAdmissionPolicy` native, PSA), puis persistance dans etcd. Journal d'audit (M14/M28) acheminé vers Loki (`audit`).
- Travaille sur `adm01` dans `~/m26/e44/` (700). Compte rendu : [`ressources/E44-sous-le-capot/compte-rendu-squelette.md`](../ressources/E44-sous-le-capot/compte-rendu-squelette.md).

> ⚠️ **Attention** : tout en **lecture**. `bpftool prog show`, `kubectl get`, lecture de journaux. Ne décharge aucun programme eBPF, ne modifie aucun hook LSM, ne touche à aucune politique.

**Travail demandé**
1. **eBPF** : sur un nœud, `sudo bpftool prog show` ; compte les programmes par type, repère ceux de Falco, Tetragon, Cilium (par `name`/`tag`/pinned path dans `/sys/fs/bpf`). Relève un identifiant réel. Explique ce que chacun observe (appels système, fonctions noyau, trafic).
2. **LSM** : `cat /sys/kernel/security/lsm` (ordre d'empilement) ; l'hôte est-il en AppArmor (Debian) ou SELinux (Rocky) ? BPF-LSM est-il actif ? Explique un hook `security_bprm_check` (exec) et son rapport avec seccomp (`seccompDefault`).
3. **Chaîne d'admission** : décris l'ordre exact (authentification → autorisation → mutation → validation → persistance) ; pour une création de pod non conforme, montre **où** elle est arrêtée (PSA ? Kyverno ? VAP native ?) et **pourquoi** l'ordre mutation-avant-validation compte.
4. **auditID de bout en bout** : prends une requête (par ex. une création refusée), retrouve son `auditID` dans le journal d'audit (Loki `audit`), et montre les étapes `RequestReceived` → `ResponseComplete` et le verdict.
5. **Compte rendu** : `docs/securite/durcissement/analyses/sous-le-capot-ebpf-lsm-admission.md` avec `## Les programmes eBPF`, `## Les LSM`, `## La chaîne d'admission`, `## L'auditID de bout en bout`, `## Réponses aux questions` ; chiffres relevés (un identifiant de programme eBPF, l'ordre réel, un `auditID`) ; aucun secret. Publie par MR.

**Questions d'analyse** (à traiter dans le compte rendu)
1. Qu'est-ce qu'un programme eBPF, et pourquoi Falco en `modern_ebpf` n'a-t-il plus besoin d'un module noyau ? Qu'est-ce que le vérificateur eBPF garantit ?
2. Différence entre un `kprobe`, un `tracepoint` et un hook `lsm` (BPF-LSM) ? Lequel peut **bloquer** une action, lequel ne fait qu'**observer** ?
3. Comment Tetragon peut-il **appliquer** (`Sigkill`, `Override`) là où Falco ne fait qu'alerter ? Qu'est-ce que cela change pour le risque (faux positif qui tue un processus) ?
4. Ordre des LSM : que se passe-t-il si deux LSM donnent un verdict différent sur le même hook ? Pourquoi AppArmor et SELinux ne coexistent-ils pas comme LSM « majeurs » sur le même hôte ?
5. Chaîne d'admission : pourquoi la **mutation** vient-elle avant la **validation** ? Donne un cas où l'inverse casserait (une mutation qui rend une charge conforme).
6. `ValidatingAdmissionPolicy` native (CEL dans l'apiserver) contre webhook Kyverno : qui s'exécute en premier, lequel survit à une panne du contrôleur d'admission, lequel donne le message le plus clair ?
7. Que contient un `auditID`, et pourquoi la politique d'audit met-elle les Secrets en `Metadata` mais `exec`/`attach` en `RequestResponse` ?
8. seccomp (`RuntimeDefault`) contre un hook BPF-LSM : qu'est-ce que chacun filtre, et pourquoi les deux sont-ils complémentaires ?

**Critères de réussite**
- [ ] Le compte rendu existe, est commité, contient les sections demandées, cite `bpftool prog`, un hook LSM, CEL, webhook, `auditID` et seccomp, avec un identifiant de programme eBPF réel et l'ordre relevé de la chaîne.
- [ ] Les 8 questions sont traitées ; aucun secret dans le compte rendu.

**Vérification** : `lab/bin/check 26 44`

<details><summary>Indice 1</summary>

`sudo bpftool prog show` liste chaque programme avec son `id`, son `type` (`kprobe`, `tracepoint`, `lsm`, `sched_cls`/`tc`, `cgroup_*`), son `name` et son `tag`. `sudo bpftool prog show --json | jq` facilite le comptage par type. `/sys/fs/bpf` montre les programmes « épinglés » (Cilium y range les siens).
</details>

<details><summary>Indice 2</summary>

Le journal d'audit de l'API (M14/M28, acheminé vers Loki `audit`) contient un objet par étape ; filtre par `objectRef` et retrouve le même `auditID` sur `RequestReceived` et `ResponseComplete`. Le `responseStatus` porte le code et la raison du refus.
</details>

**Pour aller plus loin** : charge (en lecture) la documentation de Tetragon sur les `TracingPolicy` et montre, pour une de tes règles, à quel point de hook eBPF elle s'accroche et quelle donnée elle lit. Compare avec la règle Falco équivalente.

---

### M26-E45 — Questions expert : sécurité  `Q` `★★★`

> **Ticket SEC-2745** — *De : Sophie Laurent*
> Dernière étape avant la recette du durcissement. Ces questions, je les pose à l'auditeur et il me les pose. Réponds par écrit, en argumentant. Pas de recherche à la première passe ; vérifie ensuite dans la documentation et corrige-toi en couleur.

**Objectifs pédagogiques**
- Consolider la compréhension de l'évasion de conteneur, de l'admission, de la détection et de la chaîne d'approvisionnement manipulées dans le module.
- S'entraîner à argumenter une réponse de sécurité comme en audit ou en entretien.

**Prérequis** : paliers 1 à 3, M26-E44.
**Durée indicative** : 2 h 30.

**Questions**
1. « Un conteneur n'est pas une frontière de sécurité. » Explique avec trois mécanismes précis (espaces de noms partagés, capacités, montage de `/`, socket du runtime) comment un conteneur mal configuré donne la racine du nœud.
2. QCM — Lequel **ne** suffit **pas** à empêcher une évasion depuis un conteneur applicatif ?
   a) `runAsNonRoot` + `drop: [ALL]` ; b) `seccompProfile: RuntimeDefault` ; c) `readOnlyRootFilesystem: true` **seul** ; d) PSA `restricted`. (Explique chacun.)
3. Capacités Linux : à quoi servent `NET_ADMIN`, `SYS_ADMIN`, `SYS_PTRACE`, `DAC_OVERRIDE` ? Laquelle est quasi équivalente à la racine, et pourquoi `drop: [ALL]` puis `add:` ciblé est la bonne pratique ?
4. seccomp : que fait `RuntimeDefault`, qu'est-ce qu'un profil personnalisé, et pourquoi un `Unconfined` sur un pod applicatif est-il un drapeau rouge à l'audit ?
5. Admission : décris deux façons de **contourner** une politique d'admission (un espace exclu du périmètre, un webhook en `failurePolicy: Ignore` pendant que le contrôleur est indisponible). Comment MédiSphère s'en protège ?
6. QCM — Une `ValidatingAdmissionPolicy` native (CEL) et un webhook Kyverno valident tous deux. Si le contrôleur Kyverno est **en panne** :
   a) les deux laissent tout passer ; b) la VAP native continue de valider (elle s'exécute dans l'apiserver), le webhook suit sa `failurePolicy` ; c) l'apiserver refuse de démarrer ; d) rien n'est validé. (Explique.)
7. Vérification de signature d'images (Cosign) à l'admission : qu'est-ce que `exiger-signature-medisphere` prouve, qu'est-ce qu'elle **ne** prouve **pas** (image non vulnérable ? image à jour ?), et que se passe-t-il si le registre est compromis mais la clé privée non ?
8. Détection : donne trois façons de **contourner** Falco (agir trop vite avant la lecture, utiliser un appel système non couvert par une règle, désactiver l'agent sur un nœud) et la parade pour chacune.
9. Falco contre Tetragon : lequel observe, lequel peut bloquer, et quel est le risque d'un blocage (`Sigkill`) sur un faux positif en production ?
10. Chaîne d'approvisionnement : de l'`git push` au pod en production, liste les maillons où une image peut être altérée et le contrôle MédiSphère à chaque maillon (SAST, build reproductible, signature, scan Trivy, admission, digest).
11. Chiffrement entre nœuds (WireGuard) : qu'est-ce qu'il protège, qu'est-ce qu'il **ne** protège **pas** (trafic d'un pod vers un pod du **même** nœud, trafic en clair dans le pod), et pourquoi ce n'est pas un substitut au mTLS applicatif ?
12. CIS contre ANSSI-BP-028 contre STIG : qu'est-ce qui distingue ces référentiels, pourquoi MédiSphère retient CIS **et** ANSSI, et pourquoi « 100 % de conformité » n'est ni atteignable ni souhaitable (règles qui cassent un environnement cloud) ?
13. Conformité n'est pas sécurité : donne un exemple d'un parc 100 % conforme CIS mais vulnérable, et un exemple d'un écart CIS justifié et sûr.
14. QCM — Un pod monte `hostPath: /` en lecture seule. Est-ce sûr ?
   a) oui, c'est en lecture seule ; b) non, la lecture de `/` du nœud expose des secrets (clés, `/etc/kubernetes`, tokens) et des chemins par lesquels pivoter ; c) seulement si le pod est privilégié ; d) seulement en écriture. (Explique.)
15. Réponse à incident : pourquoi **isoler avant d'éradiquer** et **collecter avant de supprimer** ? Qu'est-ce qu'un `checkpoint` de conteneur préserve qu'une simple suppression détruit ?
16. Un attaquant a obtenu l'exécution dans un pod applicatif de `mediagenda-prod`. Déroule ce qu'il peut tenter (jeton de compte de service, API, réseau, montée de privilèges) et ce que chaque contrôle MédiSphère (PSA, NetworkPolicy, `automountServiceAccountToken: false`, RBAC, Falco, quarantaine) lui oppose.

**Critères de réussite**
- [ ] Les 16 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses).
- [ ] Après correction, tu as identifié tes trois points les plus faibles et noté un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour 1 à 9 : documentation Kubernetes (Pod Security Standards, Security Context, Admission Controllers, ValidatingAdmissionPolicy), Falco et Tetragon, ton travail de M26-E06, E07, E17, E20, E42, E44.
</details>

<details><summary>Indice 2</summary>

Pour 10 à 16 : ADR-0260, la documentation Cosign/Kyverno `verifyImages`, Cilium (chiffrement), ComplianceAsCode et les guides CIS/ANSSI, et le SRE/Security workbook sur la réponse à incident.
</details>

**Pour aller plus loin** : choisis trois questions et transforme chacune en mini-démonstration sur le lab (5 minutes, reproductible, dans `wb-essais` ou `wb-pannes`), à présenter à Sophie.
