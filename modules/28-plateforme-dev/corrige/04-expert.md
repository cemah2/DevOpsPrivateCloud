# Module 28 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. Deux réflexes évitent la moitié des fausses pistes dans ce module : **demander à l'objet son état** (conditions du `ScaledObject`, de l'HPA, du `Tenant`, journal de la tâche du *scaffolder*) avant de chercher ailleurs, et **chercher qui a écrit en dernier** (`managedFields`, historique d'Argo CD, `git log`).

Les scripts d'injection sont dans `corrige/pannes/` : `_m28-commun.sh` contient les fonctions partagées — état local (`~/.local/state/workbook/M28-EXX/`), lecture de la source Git d'une Application Argo CD à partir de l'annotation de suivi d'un objet, et surtout les **commits de Lucas** : fichier lu sur `main`, transformé (`yq` de mikefarah, `sed`), poussé par l'API de GitLab avec l'auteur « Lucas Martin » et le marqueur `M28-EXX` (directement sur `main` si la branche l'accepte, sinon par une MR fusionnée après son pipeline), Argo CD invité à relire Git. L'annulation remet le contenu d'origine par un nouveau commit, **seulement** si le fichier est encore exactement dans l'état injecté (empreinte SHA-256) : ta réparation n'est jamais défaite. **Aucune panne ne modifie un secret ni ne redémarre ou ne coupe un composant partagé avec la production** (opérateur KEDA, webhooks de Capsule sans accord explicite).

**Vérifié hors du lab** : transformations `yq` et `sed` rejouées sur les fichiers de référence des corrigés (overlays de M28-E03/E04, ApplicationSet de M28-E03, Tenant de M28-E05, modèle `nouveau-service` de M28-E08) ; les correctifs Kustomize ajoutés par les pannes construits par `kustomize build` 5.8.1 ; `shellcheck -x` et `bash -n` sur tous les scripts.

**Non testé en conditions réelles** (signale tes retours) : délai entre un commit, la synchronisation d'Argo CD et l'effet (les scripts attendent jusqu'à 8 à 12 minutes) ; déclenchement effectif des évictions par l'updater du VPA (E20, variantes 1 et 3 : selon les recommandations du moment, la variante peut être sans effet et le script en essaie une autre) ; message exact des webhooks de Capsule 0.15 et de l'API d'impersonation ; délai de relecture d'un modèle par le catalogue.

> **Remarque sur les traces** : le commit porte l'auteur « Lucas Martin », mais c'est **ton** jeton d'administration qui l'a poussé (le *committer* et le journal d'audit de GitLab le montrent). En production, ce serait l'identité de Lucas.

---

### M28-E19 — Panne : MédiNotif ne monte plus en charge

**Démarche de diagnostic**

*Symptômes* : en recette, la file `notifications` grossit, MédiNotif reste à 0 ou 1 pod ; la prod va bien.

*Hypothèses* : (a) KEDA ne regarde plus (pause) ; (b) KEDA regarde mais l'interrogation échoue (identifiants, chemin, réseau) ; (c) la métrique arrive mais l'HPA ne peut pas agir (bornes, quota) ; (d) KEDA lui-même ne tourne pas (exclu vite : la prod va bien).

*Commandes, dans l'ordre*
```
admin@adm01:~$ kubectl -n medinotif-recette get scaledobject medinotif
NAME        SCALETARGETKIND      SCALETARGETNAME   MIN   MAX   READY   ACTIVE   FALLBACK   PAUSED   …
medinotif   apps/v1.Deployment   medinotif         0     5     True    False    False      True     …
admin@adm01:~$ kubectl -n medinotif-recette get scaledobject medinotif -o jsonpath='{.metadata.annotations}{"\n"}'
admin@adm01:~$ kubectl -n keda logs deploy/keda-operator --since=15m | grep medinotif-recette | tail -5
admin@adm01:~$ kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1/namespaces/medinotif-recette/s0-rabbitmq-notifications?labelSelector=scaledobject.keda.sh%2Fname%3Dmedinotif"
admin@adm01:~$ argocd app history medinotif-recette | tail -3
admin@adm01:~/src/medinotif-deploiement$ git log -p -3 -- overlays/recette/
```

*Cause racine, par variante*

| Variante | Cause | Ce qui le prouve |
|---|---|---|
| 1 | Commit de Lucas : correctif Kustomize qui pose `autoscaling.keda.sh/paused: "true"` sur le `ScaledObject` (« pendant mes essais ») ; KEDA n'interroge plus rien, l'effectif est figé | colonne `PAUSED` à `True`, condition `Paused`, métrique `keda_scaled_object_paused` à 1, alerte `KedaScaledObjectEnPause` au bout de 2 h, `git log` |
| 2 | Commit de Lucas : correctif JSON qui force `vhostName: medinotif` (vhost inexistant) ; l'API de gestion répond 404, le scaler est en erreur, la métrique n'est plus servie | journaux de l'opérateur (`404`, `Object Not Found`), `keda_scaler_detail_errors_total`, `kubectl get scaledobject … -o yaml` (`vhostName`) |

*Correctif* : revert par MR dans `medinotif/deploiement` (overlay de recette) ; synchronisation automatique de la recette ; constat par `campagne.sh 300` : MédiNotif sort de 0 en moins d'une minute, la file se vide. Puis `lab/bin/break 28 19 --annuler` pour clore.

*Prévention* : [`RB-285`](fichiers/M28-E19/medisphere/docs/plateforme-dev/runbooks/RB-285-autoscaling-muet.md) ; `CODEOWNERS` sur `overlays/*/keda/` (approbation de la Plateforme) ; l'alerte de pause existe (E13) mais arrive tard : une alerte « file qui grossit sans que l'effectif bouge » (RabbitMQ + kube-state-metrics, *pour aller plus loin*) détecte en minutes.

*Autres causes possibles, non injectées* (le runbook les couvre) : identifiants faux (401 : ExternalSecret `medinotif-rabbitmq`, version du secret `kv/medinotif/recette/keda`), réseau coupé entre `keda` et `messagerie` (délai dépassé : `hubble observe`). Elles ne sont pas injectées parce qu'elles exigeraient de toucher un secret réel ou un composant partagé avec la production.

---

### M28-E20 — Panne : des pods redémarrent en boucle depuis l'autoscaling

**Démarche de diagnostic**

*Symptômes* : pods de MédiAgenda remplacés ou redémarrés en boucle (variantes 1 et 3) ; pods de MédiNotif qui naissent et meurent toutes les quelques secondes (variante 2).

*Hypothèses* : (a) un VPA actif évince ; (b) un conteneur meurt (OOM, sonde) ; (c) deux pilotes écrivent `replicas` (Argo CD et l'HPA/KEDA).

*Commandes, dans l'ordre*
```
admin@adm01:~$ kubectl -n mediagenda-recette get pods -l app.kubernetes.io/name=mediagenda -o wide
admin@adm01:~$ kubectl -n mediagenda-recette get events --sort-by=.lastTimestamp | tail -20
… Normal  EvictedByVPA  pod/mediagenda-7c9…  Pod was evicted by VPA Updater to apply resource recommendation.
admin@adm01:~$ kubectl -n mediagenda-recette get vpa mediagenda -o jsonpath='{.spec.updatePolicy}{"\n"}{.spec.resourcePolicy}{"\n"}'
admin@adm01:~$ kubectl -n mediagenda-recette get pod <pod> -o jsonpath='{.spec.containers[0].resources}{"\n"}{.status.containerStatuses[0].lastState}{"\n"}'
admin@adm01:~$ kubectl -n medinotif-recette get deploy medinotif --show-managed-fields -o yaml | yq '.metadata.managedFields[] | [.manager, .operation]'
admin@adm01:~$ argocd app history medinotif-recette | tail -5
```

*Cause racine, par variante*

| Variante | Cause | Ce qui le prouve |
|---|---|---|
| 1 | Commit de Lucas dans l'overlay de recette de `mediagenda/deploiement` : VPA `mediagenda` en `Recreate` sur le Rollout que l'HPA pilote **sur le CPU**. L'updater évince pour changer les requests ; l'utilisation vue par l'HPA (en % des requests) change ; l'HPA rajoute ou retire des pods ; nouvelles recommandations… | événements `EvictedByVPA`, `updateMode: Recreate`, requests des pods ≠ gabarit, `git log` |
| 2 | Deux commits de Lucas : `add /spec/replicas: 2` sur le Deployment `medinotif` (overlay de recette) **et** retrait de l'`ignoreDifferences` correspondant dans le modèle de l'ApplicationSet `medinotif` (`plateforme/gitops`). Argo CD (selfHeal) remet 2, KEDA (aucune activité, minimum 0) remet 0, en boucle | `managedFields` (`argocd-controller` propriétaire de `spec.replicas`), événements `ScalingReplicaSet` en rafale, historique de synchronisation |
| 3 | Commit de Lucas : VPA `mediagenda` en `Recreate`, `minReplicas: 1`, mémoire seule, `maxAllowed.memory: 40Mi`. La combinaison VPA mémoire + HPA CPU est admissible, mais la borne est absurde : l'admission réécrit requests **et limites** (proportionnelles, `RequestsAndLimits` par défaut) → OOMKilled | `lastState.terminated.reason: OOMKilled`, limites mémoire des pods ≪ gabarit, `resourcePolicy` |

*Correctif* : revert par MR (les deux commits pour la variante 2) ; puis renouveler les pods de MédiAgenda créés pendant la panne (`kubectl argo rollouts restart mediagenda -n mediagenda-recette`) : le contrôleur d'admission ne corrige pas les pods existants. 15 minutes sans redémarrage ; `lab/bin/break 28 20 --annuler`.

*Prévention* : [`RB-286`](fichiers/M28-E20/medisphere/docs/plateforme-dev/runbooks/RB-286-pods-oscillent.md) ; `CODEOWNERS` sur les VPA, les `ignoreDifferences` et les `replicas` ; ValidatingPolicy Kyverno qui refuse un VPA hors `Off` hors de `wb-essais` (*pour aller plus loin*).

---

### M28-E21 — Panne : une équipe ne peut plus créer d'espace

**Démarche de diagnostic**

*Symptômes* : `kubectl create namespace medidoc-revue-<n>` refusé pour l'équipe MédiDoc.

*Commandes, dans l'ordre*
```
admin@adm01:~$ kubectl --kubeconfig <ADMIN.CONF> --as=essai --as-group=oidc:medidoc --as-group=system:authenticated \
    create ns medidoc-revue-essai --dry-run=server
admin@adm01:~$ kubectl get tenant medidoc
admin@adm01:~$ kubectl get tenant medidoc -o jsonpath='{.spec.owners}{"\n"}{.spec.namespaceOptions.quota}{" / "}{.status.size}{"\n"}'
admin@adm01:~$ kubectl get capsuleconfiguration default -o jsonpath='{.spec.protectedNamespaceRegex}{"\n"}{.spec.users}{"\n"}'
admin@adm01:~$ kubectl -n capsule-system get pods,svc,ciliumnetworkpolicies
admin@adm01:~/src/k8s$ git log -p -3 -- locataires/
admin@adm01:~/src/gitops$ git log -p -3 -- valeurs/capsule/
```

*Cause racine, par variante*

| Variante | Cause | Message (forme) |
|---|---|---|
| 1 | Commit de Lucas : `namespaceOptions.quota` ramené au nombre d'espaces existants | refus du webhook de Capsule : quota d'espaces atteint |
| 2 | Commit de Lucas : propriétaire `oidc:medidoc` renommé `oidc:medi-doc` (owners seulement) : le groupe ne possède plus de locataire | refus du webhook : l'utilisateur ne possède aucun locataire |
| 3 | Commit de Lucas : `manager.options.protectedNamespaceRegex` trop large (`…medi[a-z]*-`) dans les valeurs du chart | refus du webhook : nom d'espace protégé |
| 4 (sur accord) | CiliumNetworkPolicy `capsule-durcissement` posée à la main dans `capsule-system` : seuls les pods de l'espace entrent ; l'apiserver ne joint plus les webhooks | `failed calling webhook … context deadline exceeded` ; ⚠️ plus aucun pod ne démarre dans les espaces des locataires |

*Correctif* : revert par MR (variantes 1 à 3) ; suppression de la politique et signalement (variante 4 : « rien à la main », et un webhook en `Fail` est une dépendance critique). Contrôle : le même `--dry-run=server` passe. Ni `oidc:plateforme-admins` ni Argo CD n'ont besoin de droits supplémentaires pour réparer.

*Prévention* : [`RB-287`](fichiers/M28-E21/medisphere/docs/plateforme-dev/runbooks/RB-287-locataire-bloque.md) ; alerte sur `apiserver_admission_webhook_rejection_count` et les échecs d'appel des webhooks de Capsule ; `CODEOWNERS` sur `locataires/` et `valeurs/capsule/`.

---

### M28-E22 — Panne : le portail ne crée plus de services

**Démarche de diagnostic**

*Commandes, dans l'ordre* : relancer le modèle sur `medidoc-essai-inc5522`, lire le journal de la tâche ; puis
```
admin@adm01:~$ logcli query --org-id=plateforme --since=30m '{namespace="portail"} |= "<taskId>"'
admin@adm01:~$ curl -s -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(cat ~/.config/workbook/gitlab-admin.token)") \
    "https://git01.par1.medisphere.internal/api/v4/groups/medidoc/members/all?query=svc-portail" | jq '.[] | {username, access_level}'
admin@adm01:~/src/portail-modeles$ git log -p -3 -- modeles/nouveau-service/template.yaml
```

| Variante | Cause | Ce qui le prouve |
|---|---|---|
| 1 | Droits de `svc-portail` réduits à Reporter (20) dans le groupe `medidoc` | étape `publish:gitlab` en **403** ; `access_level: 20` |
| 2 | Commit de Lucas : première action `publish:gitlab` renommée `publish:gitlab:projet` | échec avant la première étape : *Template action with ID 'publish:gitlab:projet' is not registered* ; entité `Template` du catalogue |
| 3 | Commit de Lucas : `repoUrl` vers `gitlab.par1.medisphere.internal` | *No matching integration configuration for host gitlab.par1…* |

*Correctif* : rétablir le rôle de `svc-portail` (Developer ou celui que le modèle exige, décidé en E08) dans le groupe ; revert par MR dans `plateforme/portail-modeles` (le catalogue relit le modèle à l'intervalle de rafraîchissement, ou tout de suite par « Refresh » sur l'entité). Supprimer les projets et MR d'essai. `lab/bin/break 28 22 --annuler`.

*Prévention* : [`RB-288`](fichiers/M28-E22/medisphere/docs/plateforme-dev/runbooks/RB-288-portail-ne-cree-plus.md) (dont la rotation du jeton) ; CI du dépôt des modèles qui vérifie les actions utilisées ; alerte sur le taux d'échec des tâches du *scaffolder* (métriques de E16) ; appartenances de `svc-portail` déclarées en code (OpenTofu ou script de `plateforme/identite`) plutôt qu'à la main.

---

### M28-E23 — Astreinte : un locataire sature le cluster

**Démarche de diagnostic**

*Symptômes* : recette lente pour plusieurs équipes, un travailleur à 100 % de CPU, pods de `medidoc-dev` tués par manque de mémoire en boucle, alertes de capacité.

*Commandes, dans l'ordre*
```
admin@adm01:~$ kubectl top nodes
admin@adm01:~$ kubectl top pods -A --sort-by=cpu | head
admin@adm01:~$ kubectl -n medidoc-dev get pods -o custom-columns=NOM:.metadata.name,PRIO:.spec.priorityClassName,REQ:.spec.containers[0].resources.requests,LIM:.spec.containers[0].resources.limits,RESTARTS:.status.containerStatuses[0].restartCount
admin@adm01:~$ kubectl -n medidoc-dev get limitrange,resourcequota
admin@adm01:~$ kubectl get tenant medidoc -o jsonpath='{.spec.priorityClasses}{"\n"}'
admin@adm01:~$ kubectl get events -A --field-selector reason=OOMKilling --sort-by=.lastTimestamp | tail
admin@adm01:~/src/k8s$ git log -p -5 -- espaces/medidoc-dev/ locataires/
```

*Cause racine* : un traitement par lots de MédiDoc lancé à la main, **sans requests** (l'ordonnanceur le croit gratuit et l'empile sur un nœud) ; il consomme tout le CPU que ses limites permettent et dépasse sa mémoire ; il a pu passer parce que les garde-fous de l'espace (LimitRange, quota) avaient été retirés ou relevés la veille par un commit dans `plateforme/k8s`. Lis l'historique : c'est l'auteur et la date de ce commit qui expliquent l'incident.

*Endiguement* : après accord (Karim, équipe), `kubectl -n medidoc-dev scale deploy/<charge> --replicas=0`, noté dans le journal.

*Correction durable* : revert des garde-fous par MR (LimitRange, quota de `medidoc-dev`) ; locataire `medidoc` sans `medisphere-critique`, budget global en place (E14) ; la charge relancée par l'équipe, dans son dépôt, avec requests et limites justes et la classe `medisphere-lot`.

*Retour à la normale* : nœud revenu, plus aucun pod tué depuis 15 minutes, recette dans son SLO ; `lab/bin/check 28 23` ; `--annuler`.

*Post-mortem et runbook* : [`INC-5523`](fichiers/M28-E23/medisphere/docs/kubernetes/post-mortems/AAAA-MM-JJ-INC-5523.md) (modèle), [`RB-289`](fichiers/M28-E23/medisphere/docs/plateforme-dev/runbooks/RB-289-locataire-sature.md).

*Prévention* : `CODEOWNERS` sur `espaces/` et `locataires/` ; ValidatingPolicy Kyverno qui exige des requests dans les espaces des locataires ; alerte « part de CPU d'un locataire sur un nœud ».

---

### M28-E24 — Sous le capot : la boucle de l'HPA, les métriques externes et les webhooks de Capsule

**Solution** : [`sous-le-capot.md`](fichiers/M28-E24/medisphere/docs/plateforme-dev/sous-le-capot.md) (calculs chiffrés, chemin de la métrique, tableau des webhooks).
```
root@k8s-cp01:~# grep -E 'horizontal-pod-autoscaler' /etc/kubernetes/manifests/kube-controller-manager.yaml || echo "valeurs par défaut"
admin@adm01:~$ kubectl get hpa mediagenda -n mediagenda-recette -o yaml | yq '.status'
admin@adm01:~$ kubectl get apiservice v1beta1.external.metrics.k8s.io -o yaml | yq '.spec.service, .status.conditions'
admin@adm01:~$ kubectl -v=8 --kubeconfig <ADMIN.CONF> --as=essai --as-group=oidc:medidoc --as-group=system:authenticated \
    create ns medidoc-sous-le-capot --dry-run=server 2>&1 | grep -E 'POST|Response Status'
```

**Explications** : l'HPA ne connaît que l'API de métriques ; tout le reste (KEDA, scalers, RabbitMQ) est derrière l'agrégateur de l'API. D'où l'unicité du fournisseur `external.metrics.k8s.io` et l'importance de l'`APIService` dans le diagnostic. Les webhooks en `Fail` sont des **dépendances** de l'API : leur disponibilité conditionne celle des créations qu'ils interceptent.

**Pièges classiques** : oublier la tolérance (« le CPU est à 76 %, cible 70 %, pourquoi ne monte-t-il pas ? ») ; oublier la fenêtre de stabilisation en descente ; laisser la verbosité des journaux de KEDA élevée après l'enquête.

**En production chez MédiSphère** : ce document est lié depuis RB-285, RB-286 et RB-287 et relu à chaque montée de KEDA, de Capsule ou de Kubernetes.
