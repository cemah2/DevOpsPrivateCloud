# Module 26 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. En sécurité, deux réflexes sont presque toujours faux : « je désactive le contrôle et je verrai » (on masque le symptôme et on ouvre un trou) et « je corrige à la main et c'est réglé » (Argo CD remet la version de Git en quelques secondes, et la MR fautive reste). On diagnostique **avec** le contrôle en place, on corrige **par le code**.

Les scripts d'injection sont dans `corrige/pannes/` : `_m26-commun.sh` contient les fonctions partagées (MR de Lucas par l'API GitLab avec fusion automatique et transformation inverse à l'annulation, attente des synchronisations d'Argo CD, sauvegarde/restauration d'objets Kubernetes, exécution sur les VMs par SSH **et par l'agent QEMU** pour l'annulation quand `sudo` est cassé, contrôles de santé). Les fichiers modifiés sur une VM sont journalisés dans `/var/lib/workbook/pannes.log` de la VM ; les objets Kubernetes d'origine et l'état des pannes sont gardés sur `adm01` dans `~/.local/state/workbook/M26-EXX/`.

> **Remarque sur l'historique Git** : les MR de panne sont ouvertes au nom de `lucas.martin` (jeton d'emprunt d'identité créé par ton jeton d'administration, puis révoqué) et **fusionnées avec ton jeton**. En production, ce serait Karim ou Julien : c'est précisément la question du post-mortem — pourquoi la relecture n'a-t-elle rien vu, et qu'est-ce que la CI aurait pu voir ?

Les sorties reproduites sont **représentatives** : noms de pods, adresses, horodatages et formulations exactes varient selon ton lab et les versions (Kyverno 1.19.2, Falco 0.45.1, Tetragon 1.7.1, Cilium 1.20.3, Kubernetes 1.36, kubelet-csr-approver 1.2.15, OpenSCAP 1.4, ComplianceAsCode 0.1.82).

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) :
- L'ensemble des scripts de panne a été vérifié par `shellcheck -x` et `bash -n`, et leurs transformations `yq`/`jq` relues ; **aucune injection n'a été jouée sur un lab réel**. Les points les plus sensibles :
  - l'emprunt d'identité de `lucas.martin` et la fusion automatique (API GitLab 19), comme au M21 ;
  - le nom et le schéma exacts des CRD Kyverno **CEL** `policies.kyverno.io/v1` (`ValidatingPolicy`, `ImageValidatingPolicy`, `MutatingPolicy`, `GeneratingPolicy`, `PolicyException`) : relevés dans le chart `kyverno-api` 3.9.2 (champs `validationActions`, `failurePolicy`, `matchConstraints.namespaceSelector`, `matchConditions`, `evaluation`, `webhookConfiguration.timeoutSeconds`), mais la **prise en charge des *bundles* Cosign 3** par `ImageValidatingPolicy` reste *à vérifier* (champs `ctlog`/`tsa`) — repli documenté en E36 et au mini-projet ;
  - le nom exact des ConfigMaps de Falco (chart `falco` 9.2.1) et le champ `falcosidekick.config.alertmanager.hostport` : à confirmer sur ton rendu ;
  - pour E41, le chemin `/var/lib/kubelet/pki/kubelet-server-current.pem` et la relecture du certificat de service par le kubelet après redémarrage ;
  - pour E39 v2, le contexte SELinux attendu de la clé TLS de node_exporter sur Rocky 10 ;
  - pour E40 v1, la variante exige le pare-feu d'hôte (`enable-host-firewall`, M26-E27) : elle retire l'étiquette `medisphere.internal/pare-feu-hote` du nœud et constate l'effet par `cilium-health status` d'un autre agent (texte de sortie à confirmer) ; sans pare-feu d'hôte, elle se déclare « sans effet » ;
  - pour E37 v3, la configuration de falcosidekick est lue dans son Secret (variables d'environnement) : nom et forme à confirmer sur le rendu du sous-chart 0.14.1 ;
  - pour E42, le nom de processus `kdevtmpfsi` repose sur `exec -a` de l'`ash` de busybox 1.37 (copie de busybox lancée avec `argv[0]` = `sleep`) ; si ton busybox ne l'accepte pas, le témoin dort sous le nom `sleep` et le signe « binaire exécuté depuis /tmp » manque.
- E44 : les identifiants et le nombre de programmes eBPF dépendent du noyau et des versions de Falco/Tetragon/Cilium ; le compte rendu relève **tes** chiffres.

---

### M26-E35 — Panne : plus aucun déploiement ne passe en recette

**Démarche de diagnostic**

*Symptômes* : les MR de déploiement en `mediagenda-recette` n'aboutissent plus ; Argo CD montre l'espace en échec de synchronisation, **ou** les pods démarrent puis restent `0/1 Ready`. La prod (synchronisée à la main) n'est pas touchée.

*Hypothèses* : l'objet est **refusé à l'admission** (politique Kyverno en `Deny`, PSA, `failurePolicy: Fail`) ; l'objet est **admis** mais les pods ne démarrent pas (refus réseau par défaut sans DNS ni sondes).

**Étape 1 — Refus d'admission ou pods non prêts ?**

```
admin@adm01:~$ kubectl -n argocd get application mediagenda-recette -o jsonpath='{.status.conditions}' | jq .
admin@adm01:~$ kubectl -n mediagenda-recette get events --sort-by=.lastTimestamp | tail
admin@adm01:~$ kubectl get policyreports -n mediagenda-recette -o wide
```

Un message `admission webhook "validate.kyverno.svc" denied the request` (ou une `ComparisonError`/`SyncFailed` qui le cite) classe la panne comme **refus**. Des pods `Running 0/1` sans refus classent comme **sondes** (variante GeneratingPolicy).

**Variante 1 — une validation de trop, trop large pour la recette.**

```
admin@adm01:~$ kubectl -n mediagenda-recette apply --dry-run=server -f charge-conforme.yaml
Error from server: admission webhook "…kyverno.svc…" denied the request: … SEC-2735 (Lucas) : toute charge de la recette doit citer son ticket de changement …
admin@adm01:~$ kubectl get validatingpolicy exiger-etiquettes -o yaml | yq '.spec.validationActions, .spec.validations'
```

Le message du refus nomme la politique et cite la validation ajoutée : `object.metadata.namespace != "mediagenda-recette" || <annotation medisphere.internal/change présente>`. La politique était déjà en `Deny` sur recette et prod ; Lucas lui a ajouté une exigence (annotation de ticket de changement) qu'aucune charge ne remplit, limitée à la recette. `git log` de `plateforme/politiques` montre le commit `M26-E35` de `lucas.martin` (« refuser les charges sans ticket de changement »). **Correctif** : MR (`revert`) qui retire la validation ; si l'intention est bonne, elle se réintroduit plus tard dans une politique **à part**, en `Audit` d'abord (lecture des `PolicyReport`), avec un test `kyverno test`. [`fichiers/M26-E35/politiques/kyverno/validation/exiger-etiquettes.yaml`](fichiers/M26-E35/politiques/kyverno/validation/exiger-etiquettes.yaml) montre l'état sain.

À ne pas confondre : une **`matchCondition`** fausse ne refuse rien, elle fait **ignorer** la politique pour l'objet (c'est un filtre de portée, comme dans une `ValidatingAdmissionPolicy`). Mettre l'exigence dans une `matchCondition` aurait donc… retiré la politique des charges sans annotation.

**Variante 2 — failurePolicy: Fail avec une condition CEL qui échoue.**

```
admin@adm01:~$ kubectl get validatingpolicy exiger-etiquettes -o yaml | yq '.spec.failurePolicy, .spec.matchConditions'
Fail
- name: garde-recette
  expression: object.metadata.namespace != "mediagenda-recette" || object.spec.template.metadata.labels.absent == "oui"
```

`failurePolicy: Fail` et une condition (`garde-recette`) qui, pour la seule recette (ailleurs, la partie gauche du `||` est vraie et CEL ne va pas plus loin), lit un champ qui n'existe pas : pour un pod, `object.spec.template` n'existe même pas, pour un Deployment la clé `absent` non plus. L'évaluation **échoue** ; en `Fail`, un échec d'évaluation d'une `matchCondition` vaut refus. **Correctif** : MR (`revert`) qui retire la condition et remet la `failurePolicy` d'origine (`Ignore` pour cette politique d'étiquettes). La leçon : `failurePolicy: Fail` est réservé aux politiques de **refus mûres et testées** (signature en prod), jamais à une politique dont l'expression peut échouer ; une expression défensive s'écrit avec `has()`.

**Variante 3 — GeneratingPolicy qui pose un refus réseau total.**

```
admin@adm01:~$ kubectl -n mediagenda-recette get pods
NAME                          READY   STATUS    RESTARTS
mediagenda-api-…              0/1     Running   0
admin@adm01:~$ hubble observe --namespace mediagenda-recette --verdict DROPPED --last 20
… mediagenda-recette/mediagenda-api-… → kube-system/coredns-… :53 policy-verdict DENIED
admin@adm01:~$ kubectl -n mediagenda-recette get ciliumnetworkpolicies
NAME          AGE
refus-total   8m
```

Une `CiliumNetworkPolicy` `refus-total` (posée à la main, annotation `medisphere.internal/auteur: lucas.martin` ; une `GeneratingPolicy` mal réglée produirait la même chose) a des règles **vides** (`ingress: [{}]`, `egress: [{}]`) : une règle vide active le refus par défaut dans son sens sans rien autoriser. Toute sortie est refusée, DNS compris : les pods démarrent mais leurs `readinessProbe` échouent (pas de résolution, pas de base). Les sondes du kubelet, elles, viennent de l'hôte local, que Cilium laisse passer par défaut : c'est bien la **dépendance** qui manque, pas la sonde. **Correctif** : retirer la politique manuelle (`kubectl delete cnp refus-total -n mediagenda-recette`) **et** traiter l'intention par le code — la `GeneratingPolicy` `networkpolicy-par-defaut` doit poser un refus par défaut qui **laisse sortir le DNS** (port 53 vers `kube-system`) et **entrer la collecte des sondes** et de `supervision`. Voir [`fichiers/M26-E35/politiques/kyverno/generation/networkpolicy-par-defaut.yaml`](fichiers/M26-E35/politiques/kyverno/generation/networkpolicy-par-defaut.yaml).

**Clôture commune** : charge conforme admise, pods `Ready`, `lab/bin/check 26 35`, puis `lab/bin/break 26 35 --annuler`.

**Prévention.** Des tests `kyverno test` dans `plateforme/politiques/kyverno/tests/` : une charge conforme de recette **admise**, une charge non conforme **refusée** ([`fichiers/M26-E35/politiques/kyverno/tests/etiquettes.test.yaml`](fichiers/M26-E35/politiques/kyverno/tests/etiquettes.test.yaml)). Un passage obligatoire en `Audit` avant `Deny` (lire les `PolicyReport` quelques jours). `failurePolicy: Fail` seulement sur les politiques de refus mûres.

**Explications.** Une `ValidatingPolicy` CEL s'exécute dans le contrôleur d'admission de Kyverno : `validationActions` décide (refuser, auditer, avertir), `matchConstraints` et `matchConditions` décident **de quoi** elle s'occupe, `failurePolicy` décide **en cas d'échec d'évaluation ou d'indisponibilité**. Une politique de génération, elle, crée des objets (ici une NetworkPolicy par espace) : une politique réseau de refus par défaut est saine **à condition** d'autoriser explicitement le DNS et les sondes, sinon elle rend les pods non prêts.

**Alternatives.** Exprimer la même règle par une `ValidatingAdmissionPolicy` native (M26-E17) : elle survit à une panne du contrôleur Kyverno, mais se teste moins bien hors cluster et ne génère pas de rapport `PolicyReport`.

**Pièges classiques.**
- Chercher un pod `CrashLoopBackOff` alors qu'il est `Running 0/1` : le problème est la sonde, pas le conteneur.
- Passer une politique en `Ignore` pour « débloquer » : on perd la garantie exactement quand on en a besoin.
- Corriger la politique avec `kubectl edit` : Argo CD remet Git en quelques secondes.

**En production chez MédiSphère.** Toute politique de refus arrive après une fenêtre d'audit documentée ; les tests `kyverno test` sont bloquants en CI ; une alerte prévient quand un `PolicyReport` passe du vert au rouge sur un espace applicatif.

---

### M26-E36 — Panne : un pod privilégié est passé

**Démarche de diagnostic**

*Symptômes* : le rapport de politiques montre une charge non conforme **admise** (image hors registre, ou pod privilégié).

*Hypothèses* : une `PolicyException` trop large ; l'espace ré-étiqueté `privileged` ; la politique ne couvre plus l'espace (`namespaceSelector NotIn`) ; une exemption de groupe (`request.userInfo.groups`).

**Étape 1 — Qu'est-ce qui est passé, et où ?**

```
admin@adm01:~$ kubectl get policyreports -A -o wide | grep -i fail
admin@adm01:~$ kubectl get pods -A -o json | jq -r '.items[] | select(.spec.containers[]?.securityContext.privileged == true) | "\(.metadata.namespace)/\(.metadata.name)"'
```

**Variante 1 — PolicyException trop large.**

```
admin@adm01:~$ kubectl get policyexceptions.policies.kyverno.io -A -o yaml | yq '.items[].spec'
```

Une exception `essai-lucas-wb-pannes` dont la `matchCondition` dit `object.metadata.namespace == 'wb-pannes'` exempte **tout** l'espace de `registres-autorises`. **Correctif** : la supprimer, ou la réduire à la charge réelle (par nom ou étiquette) avec une `expiresAt`. Voir [`fichiers/M26-E36/politiques/kyverno/exceptions/essai-outil-interne.yaml`](fichiers/M26-E36/politiques/kyverno/exceptions/essai-outil-interne.yaml) (exception **ciblée** et datée, au format d'E18), à ajouter à `kyverno/exceptions/kustomization.yaml` (espace `kyverno-exceptions`, E18), et sa ligne au registre d'E23 [`exceptions.extrait-M26-E36.md`](fichiers/M26-E36/medisphere/docs/securite/durcissement/exceptions.extrait-M26-E36.md).

**Variante 2 — espace ré-étiqueté privileged.**

```
admin@adm01:~$ kubectl get ns mediagenda-recette --show-labels | tr , '\n' | grep pod-security
pod-security.kubernetes.io/enforce=privileged
```

`git log` de `plateforme/k8s` montre le commit `M26-E36` sur `espaces/mediagenda-recette/00-namespace.yaml`. **Correctif** : MR qui remet `enforce: restricted` (et `enforce-version: v1.36`).

**Variante 3 — matchConstraints qui exclut l'espace.**

```
admin@adm01:~$ kubectl get validatingpolicy registres-autorises -o yaml | yq '.spec.matchConstraints.namespaceSelector'
```

Un `matchExpressions` `kubernetes.io/metadata.name NotIn [wb-pannes]` retire l'espace du périmètre. **Correctif** : MR qui retire l'exclusion.

**Variante 4 — exemption d'un groupe d'administrateurs.**

```
admin@adm01:~$ kubectl get validatingpolicy registres-autorises -o yaml | yq '.spec.matchConditions'
- name: sauf-admins
  expression: '!("oidc:plateforme-admins" in request.userInfo.groups)'     # ton groupe d'administration
```

Lucas a exempté le groupe des administrateurs (celui que `kubectl auth whoami` te montre : `oidc:plateforme-admins` après le M24 ; `kubeadm:cluster-admins` pour `admin.conf` ; `system:masters` n'est plus porté que par `super-admin.conf`) « pour ne pas être bloqué en urgence ». Conséquence : tout ce qu'un administrateur soumet (y compris une image hors registre) passe. **Correctif** : MR qui retire la condition. La bonne réponse à « je suis bloqué en urgence » est une `PolicyException` ciblée et datée, pas une exemption de tout un groupe puissant.

**Clôture** : charge d'essai non conforme **refusée** (`--dry-run=server`), `lab/bin/check 26 36`, `--annuler`.

**Prévention.** Tests `kyverno test` qui vérifient le périmètre (l'espace est couvert) et l'absence d'exemption de groupe ; le registre `exceptions.md` relu à chaque audit ; une `ValidatingAdmissionPolicy` native qui interdit à une équipe de ré-étiqueter son espace en `privileged` (M26-E17).

**Explications.** Une charge échappe à l'admission par l'un des quatre leviers : exception, étiquette d'espace, périmètre de la politique, identité de l'appelant. Un `PolicyReport` `fail` sur une charge **qui existe** est le signe qu'une de ces quatre a joué.

**Alternatives.** Gatekeeper exprimerait les mêmes exceptions par des `Config`/`Assign` ; l'avantage de Kyverno `PolicyException` est qu'elle est un objet daté, versionné et relu.

**Pièges classiques.** Retirer la politique au lieu de l'exception ; laisser une exception sans date d'expiration ; exempter un groupe entier.

**En production chez MédiSphère.** Chaque exception a un propriétaire, une justification, un risque résiduel, une compensation et une date de revue (RB-261) ; une revue mensuelle alerte sur les exceptions périmées.

---

### M26-E37 — Panne : Falco est muet

**Démarche de diagnostic**

*Symptômes* : un essai (shell dans un pod, lecture de `/etc/shadow`) ne remonte ni dans Alertmanager ni dans Loki.

*Hypothèses* : Falco ne tourne pas sur le nœud (couverture) ; la règle est désactivée ou non chargée ; la priorité minimale est trop haute ; l'acheminement (falcosidekick → Alertmanager) est cassé.

**Étape 1 — Où le signal se perd-il ?**

```
admin@adm01:~$ kubectl -n falco get ds falco -o wide
admin@adm01:~$ kubectl -n falco logs ds/falco --since=10m | grep -i "shell\|shadow"   # l'événement est-il produit ?
admin@adm01:~$ loki_requete '{service="falco"}' audit 15m | jq '.data.result | length'   # arrive-t-il dans Loki ?
```

**Variante 1 — nodeSelector qui exclut les travailleurs.**

```
admin@adm01:~$ kubectl -n falco get ds falco -o jsonpath='{.spec.template.spec.nodeSelector}'
{"node-role.kubernetes.io/control-plane":""}
admin@adm01:~$ kubectl -n falco get pods -o wide   # aucun pod sur k8s-w0x
```

Falco ne tourne plus que sur les nœuds de contrôle : rien ne voit les charges applicatives. **Correctif** : MR qui retire le `nodeSelector` de `valeurs/falco/values.yaml` (`plateforme/gitops`).

**Variante 2 — règle désactivée par une surcharge.**

```
admin@adm01:~$ kubectl -n falco get cm -o yaml | grep -i -A1 "shell interactif"
    - rule: MédiSphère — shell interactif dans un conteneur applicatif
      enabled: false
```

Une surcharge `enabled: false` en fin de `regles-medisphere.yaml`. **Correctif** : MR qui la retire. Si le bruit était réel, la bonne réponse est une **exception par liste/macro** (exclure un conteneur légitime qui ouvre un shell), pas la désactivation de la règle.

**Variante 3 — falcosidekick vers une mauvaise URL.**

```
admin@adm01:~/src/gitops$ yq '.falcosidekick.config.alertmanager.hostport' valeurs/falco/values.yaml
http://kps-alertmanager.supervision.svc:9095
admin@adm01:~$ kubectl -n falco logs deploy/falco-falcosidekick --since=15m | grep -i alertmanager   # erreurs de connexion
```

Port 9095 au lieu de 9093 : les détections sont produites mais n'arrivent pas à Alertmanager. **Correctif** : MR qui remet `:9093`.

**Variante 4 — priorité minimale relevée.**

```
admin@adm01:~$ kubectl -n falco get cm falco -o jsonpath='{.data.falco\.yaml}' | grep -i priority
priority: critical
```

Les règles `notice`/`warning` (dont « shell interactif ») ne sont plus chargées. **Correctif** : MR qui remet `priority: notice` (ou le niveau de la politique).

**Clôture** : rejoue l'essai, l'alerte arrive dans Loki (`service="falco"`) et dans `astreinte@`, `lab/bin/check 26 37`, `--annuler`.

**Prévention.** Deux alertes « méta » ([`fichiers/M26-E37/observabilite/regles/falco.yaml`](fichiers/M26-E37/observabilite/regles/falco.yaml)) : `FalcoCouvertureIncomplete` (agents prêts < nœuds) et `FalcoMuet` (aucun événement depuis N heures). RB-260 complété.

**Explications.** Une détection passe par quatre maillons : l'agent sur le bon nœud, la règle chargée et active, la priorité qui la retient, l'acheminement. Un détecteur muet est pire qu'absent : il donne un faux sentiment de sécurité.

**Alternatives.** Tetragon couvre certains cas que Falco manque (et peut bloquer) ; les deux sont complémentaires (M26-E20, E44).

**Pièges classiques.** Désactiver une règle au lieu de l'excepter ; oublier que `priority` est un **seuil** ; ne pas vérifier la couverture des nœuds.

**En production chez MédiSphère.** Un essai hebdomadaire automatisé de la chaîne de détection ; une alerte si Falco ne couvre pas tous les nœuds ou se tait.

---

### M26-E38 — Panne : sudo cassé après le durcissement

**Démarche de diagnostic**

*Symptômes* : sur une VM, `sudo -n` du compte `admin` échoue (`a password is required` ou `a terminal is required`) ; Ansible et les checks tombent.

*Hypothèses* : `requiretty` ; drop-in `NOPASSWD` ignoré (mode/propriété) ; `NOPASSWD` retiré + `timestamp_timeout=0`.

> ⚠️ Ouvre d'abord une session root de secours (console Proxmox). L'agent QEMU reste le recours ultime (`lab/bin/break 26 38 --annuler` l'utilise).

**Étape 1 — Lire le message, puis sudoers (avec la session de secours).**

```
admin@adm01:~$ ssh nbx01 sudo -n true; echo $?
sudo: a terminal is required to read the password…        # variante 1
root@nbx01:~# visudo -c
root@nbx01:~# sudo -l -U admin
root@nbx01:~# ls -l /etc/sudoers.d/
```

**Variante 1 — Defaults requiretty.**

```
root@nbx01:~# grep -R requiretty /etc/sudoers /etc/sudoers.d/
/etc/sudoers.d/90-durcissement-requiretty:Defaults requiretty
```

`requiretty` fait échouer tout `sudo` sans terminal : Ansible en *pipelining* et `ssh host sudo -n` n'en ont pas. **Correctif** : par le rôle `durcissement`, ne pas poser `requiretty` (Debian ne l'active pas ; il casse l'automatisation). Retirer le drop-in, rejouer le rôle.

**Variante 2 — drop-in ignoré (0666).**

```
root@nbx01:~# ls -l /etc/sudoers.d/90-cloud-init-users
-rw-rw-rw- 1 root root … 90-cloud-init-users
root@nbx01:~# sudo -l -U admin        # plus de NOPASSWD : sudo ignore le fichier inscriptible
```

sudo **ignore** un fichier inclus inscriptible par le groupe/les autres : la règle `NOPASSWD` disparaît. **Correctif** : `chmod 0440`, et le rôle `durcissement` doit poser tous ses drop-ins en `0440` propriété `root:root`.

**Variante 3 — NOPASSWD retiré + timestamp_timeout=0.**

```
root@nbx01:~# grep -R timestamp_timeout /etc/sudoers.d/
/etc/sudoers.d/10-durcissement-timeout:Defaults timestamp_timeout=0
```

`admin` doit s'authentifier à chaque appel (pas de cache), et `NOPASSWD` a été retiré : `sudo -n` échoue. **Correctif** : conserver `NOPASSWD` pour le **compte d'automatisation** (et seulement lui), ou un `timestamp_timeout` raisonnable (5) pour les personnes ; distinguer les deux dans le rôle.

**Clôture** : `ssh <vm> sudo -n true` revient, `lab/bin/check 26 38`, `--annuler` (par l'agent QEMU).

**Prévention.** Un contrôle Molecule/`--check` du rôle `durcissement` qui vérifie `sudo -n` d'`admin` après durcissement et le mode `0440` des drop-ins. Jamais `requiretty` sur un parc automatisé.

**Explications.** `sudo -n` (non interactif) est le mode d'Ansible et des checks : il faut `NOPASSWD` pour le compte d'automatisation **et** pas d'obstacle (`requiretty`, fichier ignoré, `timestamp_timeout=0`). Depuis sudo 1.9.3, une erreur de **syntaxe** n'est plus fatale (`error_recovery=true` par défaut) : ce n'est donc pas la piste.

**Alternatives.** Séparer le compte d'automatisation (NOPASSWD, commandes ciblées) du compte des personnes (mot de passe, `use_pty`, `logfile`) : moindre privilège et traçabilité.

**Pièges classiques.** Éditer `/etc/sudoers` sans `visudo` ; se verrouiller sans session de secours ; poser `requiretty` « par durcissement ».

**En production chez MédiSphère.** Le compte d'automatisation a un `sudoers` minimal (commandes nécessaires), les personnes passent par `use_pty` et `logfile`, et tout changement de `sudoers` est validé par `visudo -cf` en CI.

---

### M26-E39 — Panne : un service confiné ne démarre plus

**Démarche de diagnostic**

*Symptômes* : un service `failed`, journal « permission denied » alors que les droits Unix sont bons.

*Hypothèses* : AppArmor en *enforce* sans un chemin ; contexte SELinux faux sur un fichier qu'un domaine confiné doit utiliser ; unité systemd durcie dont les exceptions ont été retirées.

**Étape 1 — Quel service, quel refus ?**

```
admin@adm01:~$ ssh mon01 systemctl --failed ; ssh ceph01 systemctl --failed
admin@adm01:~$ ssh mon01 'journalctl -u mailpit --since -20min | tail'
```

**Variante 1 — AppArmor (Mailpit, mon01).**

```
admin@adm01:~$ ssh mon01 'journalctl -k | grep -i apparmor | tail'
… apparmor="DENIED" operation="open" profile="mailpit" name="/var/lib/mailpit/mailpit.db" … requested_mask="wrc"
admin@adm01:~$ ssh mon01 'diff <(sudo cat /etc/apparmor.d/usr.local.bin.mailpit) <(…profil rendu par le rôle…)'
```

Le profil en *enforce* n'autorise plus le répertoire de données (les lignes `/var/lib/mailpit/` ont disparu du fichier déployé). **Correctif** : rejouer le rôle `durcissement` (tag du domaine `mac`), qui redépose le profil versionné et le recharge ; si la règle manquait **dans le gabarit**, l'ajouter au gabarit (`/var/lib/mailpit/** rwk,`), au besoin après une observation en *complain* (`aa-logprof`). Jamais `aa-disable`.

**Variante 2 — SELinux (AIDE, hôte Rocky).**

```
admin@adm01:~$ ssh ceph01 'getenforce; systemctl status aide-verification --no-pager | tail -3'
Enforcing
… aide-verification.service: Main process exited, code=exited, status=17/n/a
admin@adm01:~$ ssh ceph01 'sudo ausearch -m AVC -ts recent | tail -2'
… avc: denied { write } for comm="aide" name="aide" … scontext=system_u:system_r:aide_t:s0 tcontext=unconfined_u:object_r:user_tmp_t:s0 tclass=dir
admin@adm01:~$ ssh ceph01 'ls -dZ /var/log/aide; matchpathcon /var/log/aide'
unconfined_u:object_r:user_tmp_t:s0 /var/log/aide
/var/log/aide	system_u:object_r:aide_log_t:s0
```

Le dossier de journal d'AIDE a pris un contexte de fichier temporaire (copie, `mv` depuis `/tmp`, `chcon` manuel) : le domaine `aide_t` n'a pas le droit d'y écrire son rapport, la vérification échoue. Les droits Unix n'y sont pour rien. **Correctif** : `restorecon -Rv /var/log/aide` remet le contexte **de la politique** (`matchpathcon`) ; rien à ajouter au rôle si le chemin est standard (sinon : `semanage fcontext` par le rôle, puis `restorecon`) ; relancer `aide-verification.service` et vérifier qu'il se termine avec un code de 0 à 7. Jamais `setenforce 0`. Note : node_exporter, installé dans `/usr/local/bin`, tourne en `unconfined_service_t` (E13) : un contexte faux sur ses fichiers ne le gênerait pas — c'est pour cela que la panne vise un programme **confiné**.

**Variante 3 — unité durcie dont les exceptions ont disparu (Mailpit, mon01).**

```
admin@adm01:~$ ssh mon01 'journalctl -u mailpit -n 5 --no-pager'
… open /var/lib/mailpit/mailpit.db: read-only file system
admin@adm01:~$ ssh mon01 'systemctl cat mailpit | grep -E "^# /|ProtectSystem|ReadWritePaths"'
# /etc/systemd/system/mailpit.service
ProtectSystem=strict
ReadWritePaths=/var/lib/mailpit
# /etc/systemd/system/mailpit.service.d/90-durcissement.conf
ProtectSystem=strict
ReadWritePaths=
```

« Read-only file system » et non « permission denied » : c'est l'espace de noms de montage de l'unité, pas le MAC. Le drop-in `90-durcissement.conf` contient `ReadWritePaths=` **vide**, ce qui **remet à zéro** la liste de l'unité : `/var/lib/mailpit` n'est plus inscriptible. **Correctif** : retirer le drop-in (il ne vient d'aucun rôle) ou, si un drop-in de durcissement est voulu, y redéclarer `ReadWritePaths=/var/lib/mailpit` ; `daemon-reload`, redémarrage ; le coder dans le rôle `mailpit` (M19) et vérifier avec `systemd-analyze security mailpit` que l'exposition n'a pas augmenté.

**Clôture** : service `active`, MAC toujours en place, `lab/bin/check 26 39`, `--annuler`.

**Prévention.** Élaborer les profils/contextes/unités en mode observation d'abord (AppArmor *complain*, SELinux `permissive` sur un booléen ciblé, `systemd-analyze security`) ; les coder (profil versionné, `semanage fcontext` idempotent, drop-ins dans le rôle).

**Explications.** Le MAC et le durcissement systemd ajoutent une couche **au-dessus** des droits Unix : « rwxr-xr-x root » ne dit rien si un LSM ou `ProtectSystem` interdit l'accès. La bonne lecture est le journal du refus, pas `ls -l`.

**Alternatives.** BPF-LSM (M26-E44) comme troisième LSM ; mais AppArmor (Debian) et SELinux (Rocky) restent les LSM majeurs du lab.

**Pièges classiques.** `setenforce 0`/`aa-disable` « pour voir » ; corriger à la main un contexte qui repart au prochain `restorecon` ; oublier `ReadWritePaths`.

**En production chez MédiSphère.** Chaque service exposé a un profil/contexte versionné ; `systemd-analyze security` entre dans la revue ; aucun refus de MAC n'est « résolu » en désactivant le MAC.

---

### M26-E40 — Panne : des nœuds ne se parlent plus

**Démarche de diagnostic**

*Symptômes* : connexions inter-nœuds qui tombent, sondes intermittentes, Hubble `DROPPED` ; un seul travailleur concerné.

*Hypothèses* : pare-feu d'hôte qui oublie un flux ; nftables local qui filtre WireGuard ; MTU incohérente.

**Étape 1 — Lire l'état Cilium et Hubble.**

```
admin@adm01:~$ kubectl get nodes
admin@adm01:~$ hubble observe --verdict DROPPED --last 50
admin@adm01:~$ kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status | grep -i -A2 encryption
admin@adm01:~$ kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg encrypt status
```

**Variante 1 — pare-feu d'hôte qui oublie la santé 4240.**

```
admin@adm01:~$ kubectl get ciliumclusterwidenetworkpolicies
NAME                       AGE
wb-pare-feu-hote-essai     6m
```

```
admin@adm01:~$ kubectl get nodes -L medisphere.internal/pare-feu-hote
NAME       STATUS   …   PARE-FEU-HOTE
k8s-w03    Ready    …                      # les autres nœuds : oui
```

Lucas a voulu « essayer une version resserrée » sur `k8s-w03` : il a retiré l'étiquette `medisphere.internal/pare-feu-hote` (les politiques `hote-*` d'E27 ne sélectionnent plus ce nœud) et posé à la main une `CiliumClusterwideNetworkPolicy` à `nodeSelector` `kubernetes.io/hostname: k8s-w03` qui reprend leurs flux… **sauf** la santé Cilium (4240/TCP et l'écho ICMP depuis `remote-node`/`health`). Dès qu'une politique d'hôte sélectionne un nœud, tout ce qu'elle n'autorise pas est refusé : les sondes de santé des autres agents échouent, le nœud devient « injoignable » (`cilium-health status`, `cilium_unreachable_nodes`) — vu depuis les **nœuds de contrôle** : entre travailleurs, le trafic d'hôte passe par `cilium_wg0` (chiffrement nœud à nœud, E26), où les politiques d'hôte ne s'appliquent pas (limite connue, RB-264) ; regarde donc `cilium-health status` dans l'agent de `k8s-cp01`. **Démarche** : `kubectl get ccnp` et `-L medisphere.internal/pare-feu-hote` montrent l'écart avec `plateforme/k8s` ; `hubble observe --verdict DROPPED --node k8s-w03 --port 4240` le confirme. **Correctif** : retirer la politique d'essai (hors Git) et remettre l'étiquette par `cluster/noeuds.yaml` (`task` d'E27, ou `kubectl label node k8s-w03 medisphere.internal/pare-feu-hote=oui` puis vérifier que Git dit la même chose) ; les flux de référence sont ceux de [`hote-commun.yaml`](fichiers/M26-E27/k8s/composants/cilium/hote/hote-commun.yaml) et [`hote-travailleurs.yaml`](fichiers/M26-E27/k8s/composants/cilium/hote/hote-travailleurs.yaml). Toute variante d'une politique d'hôte s'essaie d'abord avec le point de terminaison d'hôte du nœud **en audit** (`outils/pare-feu-hote.sh audit k8s-w03`, RB-264 ; jamais l'option globale `policyAuditMode`) ; retirer l'étiquette est un geste de **retour arrière** (étape 2 de RB-264 : le nœud n'est alors plus filtré du tout), pas un moyen d'essayer une autre politique.

**Variante 2 — nftables local qui filtre WireGuard.**

```
admin@adm01:~$ ssh k8s-w03 'sudo nft list ruleset | grep -A2 51871'
… udp dport 51871 counter packets 318 … drop comment "PLAT-2740 (Lucas) : fermer WireGuard"
```

Le compteur grimpe : le chiffrement ne s'établit plus avec ce nœud. **Correctif** : retirer la table (`sudo nft delete table inet wb_e40`) et vérifier que le rôle du pare-feu local autorise 51871/UDP ; le prochain passage d'Ansible ne doit pas réintroduire la table.

**Variante 3 — MTU incohérente.**

```
admin@adm01:~$ ssh k8s-w03 'ip link show eth0 | grep mtu'
… mtu 1400 …     # les autres nœuds sont à 1500 (ou 9000)
```

Les gros paquets tombent (symptôme intermittent). **Correctif** : rétablir la MTU cohérente (`ip link set eth0 mtu <valeur>`), reportée dans le code ; un changement de MTU est coordonné (M07-E15).

**Clôture** : nœuds `Ready`, `cilium encrypt status` cohérent, `cilium_unreachable_nodes == 0`, `lab/bin/check 26 40`, `--annuler`.

**Prévention.** Toujours appliquer un pare-feu d'hôte après une phase d'audit du point de terminaison d'hôte, nœud par nœud (RB-264) ; une alerte `cilium_unreachable_nodes > 0` ; les règles nftables des nœuds uniquement par Ansible, avec une alerte si une table inconnue apparaît.

**Explications.** Un refus de **politique** apparaît dans Hubble (avec le nom de la politique) ; un paquet jeté par le **pare-feu local** du nœud n'y apparaît pas (il n'a pas atteint l'eBPF de Cilium). Une MTU incohérente ne « refuse » rien : elle fait disparaître les gros paquets.

**Alternatives.** IPsec plutôt que WireGuard (clés à gérer, plus d'en-têtes) : écarté au M26-E26.

**Pièges classiques.** Appliquer un pare-feu d'hôte partout d'un coup en `enforce` ; chercher dans Hubble un drop nftables local ; oublier que la MTU est de bout en bout.

**En production chez MédiSphère.** Le pare-feu d'hôte est versionné, appliqué par vagues, et chaque flux autorisé est dans la matrice `docs/kubernetes/reseau/matrice-flux-cluster.md`.

---

### M26-E41 — Panne : `kubectl logs` et `exec` refusés

**Démarche de diagnostic**

*Symptômes* : `kubectl logs/exec` en erreur TLS, constant (un nœud) ou intermittent (un apiserver sur trois).

*Hypothèses* : le kubelet n'a plus de certificat de service (CSR refusée par l'approbateur, ou jamais traitée parce que l'approbateur est arrêté) ; un serveur d'API vérifie les kubelets avec une mauvaise CA.

Rappel : kubeadm ne pose pas `--kubelet-certificate-authority` ; dans ce lab, le serveur d'API ne vérifie donc **pas** le certificat des kubelets (dette notée en M14 et en E25). Sans certificat de service, en revanche, le kubelet ne peut **rien** présenter : la poignée de main échoue côté kubelet.

**Étape 1 — Lire l'erreur, puis les CSR.**

```
admin@adm01:~$ kubectl logs -n mediagenda-recette deploy/mediagenda-api
Error from server: Get "https://10.10.40.63:10250/containerLogs/…": remote error: tls: internal error
admin@adm01:~$ kubectl get csr --sort-by=.metadata.creationTimestamp | grep kubelet-serving | tail -3
csr-abc…  3m  kubernetes.io/kubelet-serving  system:node:k8s-w03  <none>  Denied        # variante 1
csr-def…  3m  kubernetes.io/kubelet-serving  system:node:k8s-w03  <none>  Pending       # variante 2
admin@k8s-w03:~$ ls -l /var/lib/kubelet/pki/ ; sudo journalctl -u kubelet --since -10min | grep -i 'serving\|certificate' | tail -3
```

**Variante 1 — regex de l'approbateur + certificat renouvelé.**

```
admin@adm01:~$ kubectl get csr csr-abc… -o jsonpath='{.spec.username} {.status.conditions[0].type} {.status.conditions[0].message}{"\n"}'
system:node:k8s-w03 Denied …
admin@adm01:~/src/gitops$ git log -p -S providerRegex -- valeurs/kubelet-csr-approver/values.yaml | head -20   # commit M26-E41 de lucas.martin
-providerRegex: '^k8s-(cp|w)0[1-9]$'
+providerRegex: '^k8s-(cp|w)0[1-2]$' # PLAT-2741 (Lucas) : restreindre l approbation
```

La regex exclut `k8s-w03` (et `k8s-cp03` à son prochain renouvellement) ; la nouvelle CSR est **refusée** (`skipDenyStep: false`), le kubelet n'a plus de certificat. **Correctif** : MR (`revert`) qui rétablit `providerRegex: '^k8s-(cp|w)0[1-9]$'` dans `plateforme/gitops`, synchronisation d'Argo CD. Une CSR refusée ne se rattrape pas : le kubelet en soumet une nouvelle à sa prochaine tentative (quelques minutes) ou au redémarrage du kubelet ; l'approbateur réparé l'approuve.

**Variante 2 — approbateur arrêté + certificat renouvelé.**

```
admin@adm01:~$ kubectl -n kubelet-csr-approver get deploy
NAME                   READY   UP-TO-DATE   AVAILABLE
kubelet-csr-approver   0/0     0            0
admin@adm01:~/src/gitops$ git log -p -- valeurs/kubelet-csr-approver/values.yaml | head -12   # replicas: 0, commit M26-E41
```

Personne ne traite la CSR : elle reste `Pending`. **Correctif** : MR (`revert`) qui remet `replicas: 2` ; l'approbateur, relancé, approuve la CSR en attente (vérifie dans ses journaux qu'il l'a bien examinée). Approuver à la main est possible en urgence (RB-143 §5) **après** avoir lu la demande (`openssl req -noout -text` du champ `spec.request` : nom et adresse du nœud) — jamais en aveugle.

**Variante 3 — CA fausse sur un nœud de contrôle.**

```
admin@adm01:~$ ssh k8s-cp03 'sudo grep kubelet-certificate-authority /etc/kubernetes/manifests/kube-apiserver.yaml'
- --kubelet-certificate-authority=/etc/kubernetes/pki/front-proxy-ca.crt
```

Cet apiserver est le seul à vérifier les kubelets, et avec la **mauvaise** CA (`x509: certificate signed by unknown authority`) : une requête sur trois (celles qu'il sert) échoue. **Correctif** : remettre le manifeste du **seul** nœud touché dans l'état des deux autres (option retirée), le pod statique redémarre ; le manifeste est produit par kubeadm (`cluster/kubeadm-config.yaml`) : vérifie qu'aucune `extraArgs` du dépôt ne l'y remettrait. Poser `--kubelet-certificate-authority=/etc/kubernetes/pki/ca.crt` sur **les trois** (par `apiServer.extraArgs` et `outils/reconfigurer-apiserver.sh`, un nœud à la fois) est la vraie amélioration, une fois tous les kubelets dotés d'un certificat signé : à proposer par MR, pas pendant l'incident.

**Clôture** : plus de CSR `Pending`, approbateur prêt, `kubectl logs/exec` partout, `lab/bin/check 26 41`, `--annuler`.

**Prévention.** Alerte sur une CSR `kubelet-serving` `Pending` depuis plus de N minutes ([`fichiers/M26-E41/observabilite/regles/kubelets.yaml`](fichiers/M26-E41/observabilite/regles/kubelets.yaml)) ; alerte sur l'expiration des certificats de service ; un seul nœud de contrôle modifié à la fois.

**Explications.** `kubectl logs/exec` ouvre une connexion TLS apiserver → kubelet 10250. Avec `serverTLSBootstrap: true`, le kubelet ne sert qu'un certificat **signé** : CSR refusée ou jamais traitée → aucun certificat → `tls: internal error`. L'apiserver ne vérifie ce certificat que si `--kubelet-certificate-authority` est posé ; posé avec une mauvaise CA sur un seul des trois, il produit une panne intermittente.

**Alternatives.** Approuver les CSR à la main (sans l'approbateur) : possible mais fragile ; l'approbateur avec une regex stricte est plus sûr qu'une approbation automatique de tout.

**Pièges classiques.** Approuver une CSR sans en vérifier l'origine ; toucher aux trois nœuds de contrôle à la fois ; corriger les valeurs de l'approbateur dans le cluster au lieu de `plateforme/gitops` (Argo CD les défait) ; supprimer à la main le certificat d'autres nœuds « pour tester ».

**En production chez MédiSphère.** metrics-server et Prometheus vérifient les certificats des kubelets (pas de `--kubelet-insecure-tls`) ; l'approbateur a une regex stricte et une alerte sur les CSR en attente.

---

### M26-E42 — Incident : un conteneur compromis

> Rappel : le témoin est **strictement inoffensif** (il dort, lit son jeton, tente une connexion qui échoue, dépose un fichier dans `/tmp` — aucun calcul, aucune exfiltration). L'exercice porte sur la **réponse**, pas sur l'attaque.

**Démarche de réponse à incident**

*Symptômes* : Falco/Tetragon remontent un processus `kdevtmpfsi`, la lecture d'un jeton de SA, une tentative de sortie, un binaire dans `/tmp`, dans un pod de `wb-pannes`.

**1. Détecter / qualifier.**

```
admin@adm01:~$ loki_requete '{service="falco"}' audit 30m | jq -r '.data.result[].values[][1]' | grep -i kdevtmpfsi
admin@adm01:~$ kubectl -n wb-pannes get pods -l app.kubernetes.io/name=wb-mineur -o wide
admin@adm01:~$ kubectl -n wb-pannes describe pod <pod> | sed -n '/Containers/,/Events/p'
```

**2. Isoler (sans tuer).**

```
admin@adm01:~$ kubectl -n wb-pannes label pod <pod> medisphere.internal/quarantaine=oui
admin@adm01:~$ hubble observe --namespace wb-pannes --pod <pod> --last 10   # plus de sortie
```

La `CiliumClusterwideNetworkPolicy` `quarantaine` (posée en M26-E33, [`fichiers/M26-E33/k8s/composants/reseau/politiques/quarantaine.yaml`](fichiers/M26-E33/k8s/composants/reseau/politiques/quarantaine.yaml)) sélectionne `medisphere.internal/quarantaine: "oui"` et coupe entrée et sortie. On isole **avant** d'éradiquer, sinon une persistance relance le pod sur un autre.

**3. Collecter (avant de supprimer).**

```
admin@adm01:~$ kubectl -n wb-pannes get pod <pod> -o yaml > ~/m26/e42/pod.yaml
admin@adm01:~$ kubectl debug -n wb-pannes <pod> --profile=restricted --image=registry.par1.medisphere.internal/dockerhub/library/busybox:1.37 --target=app -- sh -c 'ps aux; ls -la /tmp; cat /tmp/.wb-depot-incident 2>/dev/null' | tee ~/m26/e42/preuves.txt
admin@adm01:~$ loki_requete '{service=~"falco|tetragon"}' audit 1h > ~/m26/e42/detections.json
admin@adm01:~$ sha256sum ~/m26/e42/* > ~/m26/e42/empreintes.txt
admin@adm01:~$ aws --endpoint-url https://s3-01.par1.medisphere.internal:8333 s3 cp ~/m26/e42/ s3://preuves/INC-5342/ --recursive   # compartiment preuves
```

(Le *checkpoint* de conteneur par l'API du kubelet, `ContainerCheckpoint` — bêta, activée par défaut depuis 1.30, toujours bêta en 1.36 —, fige la mémoire du conteneur sans l'arrêter, si le runtime le permet (containerd avec CRIU, sinon réponse `500`) : archive dans `/var/lib/kubelet/checkpoints/` du nœud, à copier dans `preuves` avec son empreinte.)

**4. Éradiquer.**

```
admin@adm01:~$ kubectl -n wb-pannes delete deployment wb-mineur
admin@adm01:~$ kubectl -n wb-pannes get cronjob    # variante 3 : persistance
admin@adm01:~$ kubectl -n wb-pannes delete cronjob wb-persistance
admin@adm01:~$ kubectl -n wb-pannes get pods        # plus aucun pod de l'incident
```

Les trois variantes : un mineur factice (processus qui dort) ; + une « exfiltration » factice (écriture locale jamais envoyée) ; + une persistance par `CronJob`. La persistance exige de supprimer **aussi** le CronJob, sinon le pod revient chaque minute.

**5. Rétablir et rédiger.** Retire la quarantaine une fois l'espace sain ; complète **RB-262** (celui d'E33 : [`fichiers/M26-E33/…/RB-262-reponse-incident-conteneur.md`](fichiers/M26-E33/medisphere/docs/securite/durcissement/runbooks/RB-262-reponse-incident-conteneur.md)) avec les ajouts de l'incident ([`RB-262-reponse-incident-conteneur.extrait-M26-E42.md`](fichiers/M26-E42/medisphere/docs/securite/durcissement/runbooks/RB-262-reponse-incident-conteneur.extrait-M26-E42.md)) ; journal `docs/kubernetes/journal/AAAA-MM-JJ-INC-5342.md` et post-mortem `docs/kubernetes/post-mortems/AAAA-MM-JJ-INC-5342.md`.

**Clôture** : `lab/bin/check 26 42`, `--annuler`.

**Explications.** L'ordre est le cœur de l'exercice : **isoler avant d'éradiquer** (la persistance), **collecter avant de supprimer** (les preuves). La quarantaine par étiquette + `CiliumClusterwideNetworkPolicy` agit en secondes et n'éteint pas le pod (on garde la mémoire pour l'analyse).

**Alternatives.** Isoler par `kubectl cordon`/`drain` du nœud (trop large) ; supprimer le pod tout de suite (on perd les preuves et la persistance le ramène). La quarantaine ciblée est le bon compromis.

**Pièges classiques.** Supprimer le pod en premier ; oublier le `CronJob` de persistance ; recopier le jeton de SA dans les preuves (c'est un secret).

**En production chez MédiSphère.** La quarantaine est posée **à l'avance** ; les preuves vont dans un compartiment à verrouillage d'objet si SeaweedFS le permet (à vérifier) ; l'incident déclenche une rotation du jeton de SA lu et une revue des accès du pod compromis.

---

### M26-E43 — Astreinte : la semaine avant l'audit

**Démarche** : deux pannes de M26-E35 à E42 (jamais E40+E41, jamais E38+E39) et une dérive de conformité, injectées ensemble.

**1. Triage (15 min).** Liste les symptômes et classe par risque :
- une **détection muette** (E37) ou un **trou d'admission** (E36) : priorité absolue — tant qu'ils durent, une vraie attaque passe inaperçue ou une charge non conforme entre ;
- un **blocage** (E35 déploiements, E38 sudo, E40/E41 nœuds) : gêne le travail, pas la sécurité immédiate ;
- la **dérive de conformité** : à réparer, mais le parc ne devient pas vulnérable en une nuit.

Vérifie tes instruments : l'admission refuse-t-elle encore (`kubectl apply --dry-run=server` d'une charge non conforme) ? Falco crie-t-il à un essai ? La conformité d'une VM (`ssh-audit`, `oscap xccdf eval`) a-t-elle baissé ? Première communication à Nadia.

**2. Diagnostic et rétablissement.** Traite chaque panne par sa démarche (E35-E42 ci-dessus), **par le code**, sans désactiver de contrôle. Pour la dérive : `ssh <vm> sudo sshd -T | grep -i permitrootlogin` montre `yes`, `oscap`/Lynis montrent un score en baisse ; la cause est un drop-in `sshd_config.d/99-wb-derive.conf` et un `sysctl` défait — **correctif par le rôle `durcissement`** (rejeu), pas à la main. Après chaque correction, relance `lab/bin/check 26 <xx>`.

**3. Clôture.** `lab/bin/break 26 43 --annuler`, puis post-mortem `docs/kubernetes/post-mortems/AAAA-MM-JJ-INC-5343.md` (chronologie, causes racines, extraits de diagnostic, section **Détection** : pour chaque cause, ce qui aurait dû la signaler et pourquoi ça n'a pas marché), et **RB-265** ([`fichiers/M26-E43/medisphere/docs/securite/durcissement/runbooks/RB-265-semaine-avant-audit.md`](fichiers/M26-E43/medisphere/docs/securite/durcissement/runbooks/RB-265-semaine-avant-audit.md)).

**Prévention.** RB-265 : la checklist de la semaine avant l'audit (ordre de priorité, ce qu'on ne touche pas, qui valide un changement en gel). Aucune correction la nuit avant l'audit qui ne passe par Git.

**Pièges classiques.** Désactiver un contrôle pour « gagner du temps » (exactement ce que l'auditeur cherche) ; traiter un blocage avant une détection muette ; oublier la dérive de conformité.

---

### M26-E44 — Sous le capot : eBPF, LSM et chaîne d'admission

**Solution** (le compte rendu est personnel ; voici la trame et les commandes).

**1. eBPF.**
```
root@k8s-w01:~# bpftool prog show | awk '{print $2}' | sort | uniq -c   # par type
root@k8s-w01:~# bpftool prog show --json | jq -r '.[] | "\(.id)\t\(.type)\t\(.name)\t\(.tag)"' | sort -k2
root@k8s-w01:~# ls -l /sys/fs/bpf/ /sys/fs/bpf/cilium/ 2>/dev/null
```
On relie les programmes à leur produit : Cilium (`tc`/`sched_cls`, `cgroup_*`, pinned dans `/sys/fs/bpf/cilium`), Falco et Tetragon (`tracepoint`/`kprobe`/`lsm`, chargés par leurs agents). On note un `id` réel.

**2. LSM.**
```
root@k8s-w01:~# cat /sys/kernel/security/lsm
lockdown,capability,landlock,yama,apparmor,bpf      # Debian : apparmor majeur + bpf (BPF-LSM)
root@ceph01:~# cat /sys/kernel/security/lsm         # Rocky : …,selinux,bpf
```
On explique un hook `security_bprm_check` (déclenché à `execve`, d'où « binaire exécuté depuis /tmp ») et le lien avec seccomp (`seccompDefault: true` filtre les appels système au niveau du conteneur).

**3. Chaîne d'admission.** Ordre : **authentification** (`AuthenticationConfiguration`, M24) → **autorisation** (RBAC) → **mutation** (webhooks Kyverno `MutatingPolicy`, `MutatingAdmissionPolicy` native) → **validation** (PSA, webhooks Kyverno `ValidatingPolicy`, `ValidatingAdmissionPolicy` native CEL) → **persistance** (etcd). On montre où une création non conforme est arrêtée :
```
admin@adm01:~$ kubectl apply --dry-run=server -f pod-non-conforme.yaml
Error … admission webhook "validate.kyverno.svc" denied … / pods "…" is forbidden: violates PodSecurity "restricted:v1.36"
```

**4. auditID de bout en bout.**
```
admin@adm01:~$ loki_requete '{service="kube-apiserver-audit"}' audit 10m | jq -r '.data.result[].values[][1]' | jq -r 'select(.objectRef.resource=="pods") | "\(.auditID) \(.stage) \(.responseStatus.code // "")"' | head
```
Le même `auditID` relie `RequestReceived` et `ResponseComplete` ; `responseStatus` porte le verdict (par ex. 403 et la raison).

**Réponses aux questions** (résumé argumenté — le compte rendu développe) :
1. Un programme eBPF est du code vérifié chargé dans le noyau ; le vérificateur garantit terminaison et sûreté mémoire, d'où plus besoin de module. 2. `kprobe`/`tracepoint` **observent**, un hook BPF-LSM peut **refuser** (il renvoie un verdict sur `security_*`). 3. Tetragon s'accroche à des hooks qui peuvent agir (`Sigkill`/`Override`) ; le risque est de tuer un processus légitime (faux positif) — d'où l'application d'abord dans `wb-essais`, puis une règle sûre en recette (M26-E29). 4. Deux LSM sur le même hook : chacun peut refuser (le plus restrictif gagne) ; AppArmor et SELinux ne coexistent pas comme majeurs car leurs modèles (chemins vs contextes) et leur gestion des hooks sont incompatibles. 5. La mutation avant la validation permet à une mutation (ex. `seccomp-par-defaut`) de rendre une charge **conforme** avant le contrôle ; l'inverse refuserait des charges qu'on aurait pu corriger. 6. VAP native dans l'apiserver = survit à une panne du contrôleur Kyverno ; le webhook suit sa `failurePolicy`. 7. `auditID` identifie une requête de bout en bout ; Secrets en `Metadata` (ne pas journaliser les valeurs), `exec`/`attach` en `RequestResponse` (traçabilité d'un accès interactif). 8. seccomp filtre les **appels système** du conteneur ; BPF-LSM filtre des **opérations** de haut niveau (ouverture de fichier sensible) : complémentaires.

**Explications.** La défense en profondeur de MédiSphère empile des couches indépendantes : admission (avant exécution), seccomp + capacités + MAC (pendant), détection eBPF (observation), réponse (quarantaine). Ouvrir le capot montre que ces couches sont réelles et mesurables, pas des cases à cocher.

---

### M26-E45 — Questions expert : sécurité

Réponses argumentées (l'apprenant développe ; voici les points clés et, pour les QCM, la bonne réponse **et** pourquoi les autres sont fausses).

1. Espaces de noms partagés (un conteneur avec `hostPID`/`hostNetwork` voit les processus/le réseau de l'hôte), capacités (`SYS_ADMIN` ≈ racine), montage de `/` ou du socket du runtime (`/var/run/docker.sock`, `containerd.sock` → création de conteneurs privilégiés sur l'hôte). Le conteneur partage le **noyau** de l'hôte : une faille noyau ou une mauvaise configuration suffit.
2. **c**. `readOnlyRootFilesystem` seul n'empêche pas une évasion (un pod privilégié ou avec `SYS_ADMIN` s'évade quand même) ; a, b et d ferment des voies distinctes et se combinent. `readOnlyRootFilesystem` limite la **persistance**, pas l'évasion.
3. `NET_ADMIN` (config réseau), `SYS_ADMIN` (montages, namespaces — quasi racine), `SYS_PTRACE` (inspection d'autres processus), `DAC_OVERRIDE` (ignorer les droits de fichiers). `SYS_ADMIN` est la plus dangereuse. `drop: [ALL]` puis `add:` ciblé = moindre privilège, et on sait exactement ce qu'on accorde.
4. `RuntimeDefault` applique le profil seccomp par défaut du runtime (bloque les appels système dangereux) ; un profil personnalisé restreint davantage ; `Unconfined` = aucun filtre seccomp → drapeau rouge (on a retiré une protection par défaut).
5. Espace exclu du périmètre (une politique dont le `namespaceSelector` ne couvre pas l'espace) ; webhook en `failurePolicy: Ignore` pendant que le contrôleur est indisponible (la requête passe). Parades : périmètre explicite et testé, `failurePolicy: Fail` sur les politiques critiques en prod, contrôleur en 3 réplicas, VAP natives qui ne dépendent pas d'un webhook.
6. **b**. La VAP native s'exécute dans l'apiserver (survit à la panne du contrôleur) ; le webhook Kyverno suit sa `failurePolicy` (Fail = refus, Ignore = passage). a/c/d sont faux : l'apiserver démarre, et au moins la VAP valide.
7. La signature prouve que l'image a été **signée par la clé MédiSphère** (origine), pas qu'elle est exempte de vulnérabilités ni à jour. Registre compromis mais clé privée saine : l'attaquant ne peut pas produire une image signée acceptée → la vérification tient (c'est l'intérêt).
8. Agir avant la lecture de la règle (course) → parade : règles sur `execve` et ouverture, pas seulement sur la lecture tardive ; appel système non couvert → parade : jeu de règles maintenu, Tetragon en complément ; désactiver l'agent sur un nœud → parade : alerte de couverture (M26-E37).
9. Falco **observe** (alerte), Tetragon peut **bloquer** (`Sigkill`) ; un blocage sur faux positif tue un processus légitime en prod → on applique d'abord en observation, puis une règle sûre et ciblée.
10. Maillons : code (SAST Semgrep), build (reproductible, BuildKit sans privilège), image (scan Trivy, SBOM), signature (Cosign), registre (immuabilité `v*`, Harbor), promotion (MR, digest), admission (`exiger-signature-medisphere`, `exiger-digest`, `registres-autorises`), exécution (Falco). Chaque maillon a son contrôle.
11. WireGuard chiffre **pod → pod d'un autre nœud** ; il ne chiffre pas le trafic entre pods du **même** nœud (voulu) ni l'intérieur du pod ; ce n'est pas un mTLS applicatif (pas d'identité de charge, pas d'autorisation applicative) → mTLS (M25 PKI de services) reste nécessaire pour l'authentification mutuelle des applications.
12. CIS (consensus, niveaux 1/2), ANSSI-BP-028 (France, minimal→élevé), STIG (DoD US). MédiSphère retient CIS (reconnu HDS) **et** ANSSI (souveraineté, exigences françaises). 100 % n'est ni atteignable (règles qui cassent un environnement cloud, ex. montage `/tmp noexec` vs outils qui exécutent dans `/tmp`) ni souhaitable (coût > bénéfice) : d'où les exceptions documentées.
13. Conforme mais vulnérable : un parc 100 % CIS avec une application exposée et vulnérable (CIS ne regarde pas l'applicatif). Écart justifié et sûr : `ip_forward=1` sur les passerelles et les nœuds K8s (nécessaire au routage, compensé par le pare-feu).
14. **b**. `hostPath: /` en lecture seule expose les secrets du nœud (`/etc/kubernetes`, clés, tokens) et des chemins de pivot ; c'est dangereux même en lecture seule. a/c/d sont faux.
15. Isoler avant d'éradiquer (une persistance relancerait le conteneur ailleurs) ; collecter avant de supprimer (les preuves disparaissent avec le pod). Un `checkpoint` préserve la mémoire et l'état des processus qu'une suppression détruit.
16. L'attaquant tente : lire le jeton de SA (parade : `automountServiceAccountToken: false`), appeler l'API (parade : RBAC minimal du SA), bouger latéralement (parade : NetworkPolicy refus par défaut), monter en privilège (parade : PSA `restricted`, seccomp, capacités `drop ALL`), persister (parade : Falco détecte, quarantaine isole). La défense en profondeur fait que chaque étape rencontre un contrôle.
