# Final F3 — Corrigé de la phase 6 : vendredi

> ⚠️ Corrigé : à n'ouvrir qu'après avoir cherché. Heures d'exemple : vendredi 2026-11-06.

**Validé hors du lab** : règles et tests `promtool` de [`notifications-astreinte`](fichiers/S13/observabilite/regles/notifications-astreinte.yaml) (Prometheus 3.5, `promtool test rules`) ; `shellcheck -x` et `bash -n` sur les scripts, dont [`collecte-pod.sh`](fichiers/S12/outils/incident/collecte-pod.sh).
**Non testé en conditions réelles** (à vérifier sur ton lab) : déclenchement exact de la règle « shell interactif » pour un conteneur éphémère (`kubectl debug -it`) selon la version des macros de Falco 0.45 ; comportement du Messaging Topology Operator 1.20 après un `rabbitmqctl clear_password` (il peut réconcilier l'utilisateur à sa prochaine resynchronisation et « réparer » seul la variante 1 de S13) ; débit réel de la campagne factice par l'API de gestion (dépend du poste `adm01` ; `WB_F3_S13_DEBIT` pour l'ajuster).

---

### F3-S12 — Vendredi : alerte Falco en production

#### Démarche de diagnostic (qualifier, confiner, préserver, escalader)

L'ordre est imposé par RB-262 : **qualifier** (15 min) → **isoler** (5 min) → **collecter** (du plus volatil au plus durable) → **escalader** (dans l'heure) → éradiquer **après** la collecte. La vitesse compte moins que l'irréversibilité : un pod supprimé ne se collecte plus.

**1. Qualifier (vrai ou faux positif).**

```
admin@adm01:~$ # Courriel : règle, espace, pod, conteneur, commande, destination (étiquettes de l'alerte)
admin@adm01:~$ amtool --alertmanager.url=http://alertmanager.apps.par1.medisphere.internal:9093 alert query alertname=AlerteFalco -o extended
admin@adm01:~$ kubectl -n <ESPACE> get pod <POD> -o wide; kubectl -n <ESPACE> get pod <POD> -o jsonpath='{.status.containerStatuses[*].imageID}{"\n"}'
```

Dans Grafana, source `loki-audit` (organisation Sécurité) :

```logql
{service="falco"} | json | k8s_pod_name="<POD>"
{job="kubernetes-audit"} | json | objectRef_subresource=~"exec|ephemeralcontainers" | objectRef_name="<POD>"
```

(Les noms de champs extraits par `| json` dépendent du format de la ligne : lis une ligne brute d'abord.)

```
admin@adm01:~$ hubble observe --pod <ESPACE>/<POD> --since 1h --verdict DROPPED
admin@adm01:~$ git -C ~/medisphere log --since=yesterday --oneline     # un changement annoncé l'explique-t-il ?
```

Ce que l'on trouve, selon la variante : un shell interactif ouvert par `kubectl exec -it` (v1, v3) dans l'API de **recette** de MédiAgenda, ou par `kubectl debug -it` (v2 : conteneur éphémère `diag`, image busybox, ciblant MédiDoc en **dev** — l'image distroless n'a pas de shell, l'« intrus » en a apporté un) ; ensuite une boucle qui tente toutes les minutes une connexion vers 203.0.113.50:4444 (v1 : adresse externe, port typique d'un canal de commande), 198.51.100.23:6667 (v2) ou le coffre 10.10.20.200:8200 et l'API Kubernetes 10.10.40.200:8443 (v3 : reconnaissance interne). Hubble montre ces flux **jetés** par la politique de l'espace : rien n'est sorti. Le journal d'audit donne l'identité qui a demandé l'`exec` (dans le lab : celle de l'injection, ton compte ou `kubernetes-admin`) et l'adresse source (`adm01`).

**Qualification : vrai positif**, jusqu'à preuve du contraire : aucun changement annoncé, aucune personne de l'équipe ne revendique l'action, comportement sans rapport avec l'application, connexions vers des destinations hors de la matrice. Le fait que l'identité soit celle d'un compte interne n'innocente rien : c'est la piste d'un **compte compromis** (ou d'un bris de glace utilisé hors procédure), à ajouter à l'escalade. Ce n'est **pas la production** (recette ou dev) : le titre du scénario et l'objet du transfert de Nadia (« Falco : shell en production ?! ») reprennent la façon dont l'alerte a été **perçue** ; établir l'environnement réel fait partie de la qualification, et le premier message d'état le rectifie. Gravité : SEV2 sécurité, pas SEV1 (aucune donnée de production exposée, rien n'est sorti), mais l'escalade à la RSSI reste obligatoire (RB-262), et un vrai positif en **production** aurait été SEV1 d'emblée (procédure S02).

**2. Isoler.**

```
admin@adm01:~$ export NS=<ESPACE> POD=<POD>; date -u +%FT%TZ
admin@adm01:~$ kubectl -n $NS get pod $POD -o jsonpath='{.status.containerStatuses[*].restartCount}{"\n"}'   # avant
admin@adm01:~$ kubectl -n $NS label pod $POD medisphere.internal/quarantaine=oui
admin@adm01:~$ kubectl -n $NS get rs -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.selector.matchLabels}{"\n"}{end}'
admin@adm01:~$ kubectl -n $NS label pod $POD app.kubernetes.io/instance-      # une étiquette DU SÉLECTEUR (lis-le avant)
admin@adm01:~$ kubectl -n $NS get pods -o wide                               # un pod neuf, le suspect orphelin
admin@adm01:~$ kubectl -n $NS get endpointslices -o yaml | grep -c "$POD"    # 0 : hors du Service
admin@adm01:~$ hubble observe --pod $NS/$POD --since 5m                      # tout est refusé, sauf les sondes de l'hôte
admin@adm01:~$ kubectl -n $NS get pod $POD -o jsonpath='{.status.containerStatuses[*].restartCount}{"\n"}'   # après : identique
```

Pour un Rollout (MédiAgenda en recette, M20), le sélecteur porte aussi `rollouts-pod-template-hash` : retirer une étiquette du sélecteur du ReplicaSet suffit, Argo Rollouts recrée un pod. Pour la variante 2, le pod de MédiDoc garde son conteneur applicatif sain : l'isoler coupe aussi MédiDoc dans ce pod, c'est le pod neuf qui rend le service.

Un **silence** Alertmanager ciblé (matchers `alertname=AlerteFalco`, `k8s_pod_name=<POD>`, fin à la clôture, commentaire « INC-5912, pod isolé ») est légitime une fois le pod en quarantaine : les tentatives continuent (et sont jetées), les notifications n'apprennent plus rien. Jamais de silence avant l'isolement, jamais sur toute la règle.

**3. Collecter** — script de référence [`collecte-pod.sh`](fichiers/S12/outils/incident/collecte-pod.sh) (à verser dans `plateforme/outils`, `incident/`) : état du pod et du nœud, processus et connexions vus d'un conteneur éphémère **sous le même utilisateur que la cible** (sinon `/proc/1/root` est illisible), `/tmp` archivé sans rien exécuter, journaux, export Loki (Falco, Tetragon, audit), Hubble, empreintes, dépôt par `preuves-depot`.

```
admin@adm01:~$ ~/src/outils/incident/collecte-pod.sh $NS $POD <CONTENEUR> INC-5912
Preuves déposées dans s3://preuves/INC-5912/20261106T081544Z/ — empreintes (à recopier dans la main courante) :
3f1c…  collecte.log
…
```

(Pour la variante 2, la cible du conteneur éphémère de collecte est le conteneur `medidoc`, et l'on archive aussi ce que montre `diag` : le shell de l'intrus est **dans** `diag`, ses fichiers sont dans le système de fichiers de `diag` — `kubectl exec -c diag -- ls -la /tmp` puis `tar` de la même façon.)

Ce que la collecte montre (v1, v3) : `python3 /tmp/.cache-maj.py` (ou `python3 -c …`) détaché du shell, un fichier texte `/tmp/.cache-maj.py` qui ouvre des connexions TCP en boucle **sans rien envoyer** et s'arrête seul au bout de 6 h. Inoffensif — mais c'est la collecte qui permet de l'affirmer.

**4. Escalader** — Sophie Laurent dans l'heure (RB-262 §1), par téléphone puis courriel : quoi (règles, pod, image, destinations), depuis quand, quelle identité dans l'audit, ce qui est établi (rien n'est sorti : flux jetés), ce qui ne l'est pas (comment l'identité a été utilisée), ce qui est fait (isolé, service rétabli, preuves et empreintes), décisions attendues d'elle (compte à suspendre ou jetons à révoquer, éradication, notification éventuelle). Prévenir aussi Julien (recette) ou l'équipe MédiDoc (dev).

**5. Éradiquer et rétablir** — après accord de Sophie : suppression du pod suspect (`kubectl -n $NS delete pod $POD`), vérification qu'aucun autre pod de la même image ne présente le même processus (`kubectl get pods -A -o json | jq …` par image, puis un `exec` non interactif de contrôle) ou qu'aucune persistance n'existe (CronJob, Job, conteneur éphémère ailleurs), revue des accès de l'identité vue dans l'audit (kubeconfigs, sessions OIDC, `admin.conf`), levée du silence, puis `lab/bin/check F3 12` et `lab/bin/break F3 12 --annuler`.

#### Messages d'état types

- **Début (08:02)** — *[INC-5912] SEV2 sécurité — activité suspecte dans un conteneur de recette (pas la production)* — « Alerte de détection reçue à 07:52 : shell ouvert dans un conteneur de MédiAgenda recette, tentatives de connexion vers une adresse externe, toutes bloquées par le réseau. Pod en cours d'isolement, RSSI prévenue. Ne pas intervenir sur l'espace. Prochain point : 08:30. »
- **Point d'étape (08:30)** — « Pod isolé à 08:09 (service de recette rétabli par un pod sain), preuves collectées et déposées avec leurs empreintes à 08:26. Aucune donnée sortie selon les flux réseau. L'action a été faite avec un compte interne : enquête en cours avec Sophie. Prochain point : 09:30. »
- **Fin** — « Clôture technique à 09:40 : pod suspect supprimé après collecte, aucune persistance trouvée, silence levé. Suite (accès, comptes) pilotée par la RSSI sous SEC-<NUMÉRO>. »

#### Main courante (extrait type)

```
- 07:58 INC-5912 [ouverture] AlerteFalco : shell interactif + connexions sortantes, mediagenda-recette/<POD>. Astreinte = responsable d'incident.
- 08:02 INC-5912 [état] Message 1 (SEV2 sécurité, recette, isolement en cours).
- 08:06 INC-5912 [action] Audit API : create pods/exec par <IDENTITÉ> depuis 10.10.10.10 à 07:51. Hubble : 203.0.113.50:4444 DROPPED.
- 08:07 INC-5912 [décision] Vrai positif (aucun changement annoncé, personne ne revendique, destination hors matrice). SEV2 sécurité.
- 08:09 INC-5912 [action] Quarantaine posée, pod sorti du contrôleur (étiquette du sélecteur retirée), restartCount inchangé (0), pod neuf prêt.
- 08:11 INC-5912 [action] Escalade : Sophie Laurent prévenue par téléphone (RSSI), courriel de synthèse envoyé.
- 08:12 INC-5912 [action] Silence ciblé AlerteFalco k8s_pod_name=<POD> jusqu'à 18:00.
- 08:26 INC-5912 [action] Collecte : s3://preuves/INC-5912/20261106T081544Z/ ; SHA256SUMS : 3f1c… collecte.log ; 9a07… processus.txt ; …
- 08:30 INC-5912 [état] Message 2.
- 09:35 INC-5912 [décision] Sophie : éradication autorisée ; suite sous SEC-<NUMÉRO> (revue de l'identité).
- 09:38 INC-5912 [action] Pod suspect supprimé ; aucun autre pod de l'image ne présente le processus ; silence levé.
- 09:40 INC-5912 [clôture] Clôture technique. Preuves conservées (ne pas purger preuves/INC-5912/).
```

#### Explications

Falco dit *quoi*, l'audit de l'API dit *qui*, Hubble dit *où* (et si c'est passé). La quarantaine par étiquette + politique de refus agit en secondes sans arrêter le processus : la mémoire, les fichiers et les connexions restent collectables. Sortir le pod de son contrôleur concilie préservation (le suspect vit) et rétablissement (un pod sain le remplace). Les empreintes et le dépôt dans un compartiment versionné, par une identité qui ne peut pas supprimer, font des pièces une **preuve** (intégrité, chaîne de détention).

#### Alternatives

- Supprimer le pod tout de suite : service rétabli plus vite, preuves perdues, persistance éventuelle non comprise. Non.
- Isoler le nœud (cordon, drain) : trop large, et le drain **supprime** le pod.
- Réponse automatique (falcosidekick qui supprime le pod) : refusée au M26 pour la même raison.

#### Pièges classiques

- Lancer des commandes **dans** le conteneur suspect (`kubectl exec … sh`) : on modifie la scène et on crée de nouvelles alertes.
- Une quarantaine qui bloque les sondes de vivacité (conteneur redémarré = preuves volatiles perdues) : la politique du M26 laisse passer l'hôte local exprès.
- Conclure « faux positif » parce que l'identité est interne.
- Silencer toute la règle Falco, ou modifier ses règles pour faire taire l'alerte.
- Recopier un jeton ou un secret dans les preuves (c'est un secret, pas une preuve).

#### En production chez MédiSphère

Exercice sur table RB-262 deux fois par an, outil de collecte versionné et testé sur `wb-essais`, verrouillage d'objet du compartiment `preuves` (à vérifier sur la version de SeaweedFS), alerte d'audit sur tout `exec` en production (`AuditExecProduction`, M26) et sur l'usage de `admin.conf`, et revue des identités autorisées à `exec`/`debug` (RBAC) dans les espaces applicatifs.

---

### F3-S13 — Vendredi : les notifications s'accumulent

#### Démarche de diagnostic

**Symptômes.** File `notifications` de `medinotif-prod` qui grossit ; rappels en retard ; une campagne exceptionnelle en cours (entrée plus forte que d'habitude).

**Raisonner en débits** (5 min) :

```
admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmqctl list_queues -p medinotif-prod \
  name type messages messages_unacknowledged consumers policy
admin@adm01:~$ kubectl -n medinotif-prod get hpa keda-hpa-medinotif
admin@adm01:~$ kubectl -n medinotif-prod get scaledobject medinotif -o yaml | yq '.spec | {minReplicaCount, maxReplicaCount}, .status.conditions'
admin@adm01:~$ kubectl -n medinotif-prod get pods -l app.kubernetes.io/name=medinotif
```

Dans l'interface de gestion (ou Grafana, tableau `m27-donnees`) : débit de publication ≈ 110/s, débit d'acquittement ≈ 40, 80 ou 0/s. Avec ≈ 20 messages/s par pod (M28-E13), 110/s exige au moins 6 pods : la question devient « pourquoi l'effectif ne monte-t-il pas, ou pourquoi les pods ne consomment-ils pas ? ».

**Variante 1 — KEDA en repli : le compte `keda-prod` est refusé par RabbitMQ.**

```
admin@adm01:~$ kubectl -n medinotif-prod describe scaledobject medinotif | tail -n 12
  Warning  KEDAScalerFailed  …  error inspecting rabbitMQ: … 401 Unauthorized
  Type: Fallback  Status: True                      # repli : 4 pods, insuffisant pour 110/s
admin@adm01:~$ kubectl -n keda logs deploy/keda-operator --since=30m | grep -i 'medinotif' | tail -n 3
admin@adm01:~$ kubectl -n messagerie get users.rabbitmq.com keda-prod -o yaml | yq '.status'
admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmqctl list_users | grep keda-prod
```

OpenBao, le Secret de l'espace (`medinotif-rabbitmq`) et celui de la topologie (`rabbitmq-utilisateur-keda-prod`) sont d'accord (dates de rafraîchissement des deux `ExternalSecret`) ; c'est **RabbitMQ** qui n'accepte plus le mot de passe : il a été changé ou effacé directement dans RabbitMQ (journaux des nœuds RabbitMQ dans Loki : `rabbitmqctl` / `clear_password`, ou l'API de gestion). Correctif par le chemin normal : **rotation** du compte (RB de rotation du M28 : nouvelle version de `kv/medinotif/prod/keda`, `force-sync` des deux `ExternalSecret`, le Messaging Topology Operator applique le mot de passe au `User`, contrôle `GET /api/whoami` avec le compte, condition `Fallback` qui repasse à `False`). Ne tape jamais un mot de passe à la main dans RabbitMQ.

**Variante 2 — le plafond a été abaissé en direct.**

```
admin@adm01:~$ kubectl -n medinotif-prod get hpa keda-hpa-medinotif
NAME                 REFERENCE              TARGETS            MINPODS  MAXPODS  REPLICAS
keda-hpa-medinotif   Deployment/medinotif   5500/100 (avg) …   2        2        2
admin@adm01:~$ argocd app diff medinotif-prod          # ou l'interface : ScaledObject, maxReplicaCount 8 → 2
admin@adm01:~$ # audit API : {job="kubernetes-audit"} |= "scaledobjects" |= "medinotif" (locataire audit) : qui, quand
```

La prod est synchronisée à la main : la modification directe reste, l'Application est `OutOfSync`. Correctif : **synchroniser** l'Application `medinotif-prod` après lecture du différentiel (le dépôt fait foi : maximum 8) — ou, si un plafond plus bas était voulu, MR dans `medinotif/deploiement` d'abord. L'HPA monte à 6-8 pods, la file redescend à ≈ 50 messages/s nets.

**Variante 3 — un message empoisonné, sans limite de livraison.**

```
admin@adm01:~$ kubectl -n medinotif-prod get pods -l app.kubernetes.io/name=medinotif     # CrashLoopBackOff, redémarrages
admin@adm01:~$ kubectl -n medinotif-prod logs <POD> --previous | tail -n 5                 # RecursionError dans json.loads
admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmqctl list_policies -p medinotif-prod
medinotif-prod  notifications-rebut        ^notifications$  quorum_queues  {…"delivery-limit":5…}   10
medinotif-prod  notifications-maintenance  ^notifications$  quorum_queues  {…"delivery-limit":-1…}  20
```

Une seule politique s'applique à une file : la plus prioritaire. `notifications-maintenance` (créée hors de `plateforme/donnees`, priorité 20) recopie le rebut mais **retire la limite de livraison** : le message qui fait planter MédiNotif revient indéfiniment. Correctif : supprimer la politique hors code (`rabbitmqctl clear_policy -p medinotif-prod notifications-maintenance`, geste consigné — elle n'existe pas dans Git, il n'y a pas de MR à faire, seulement une à **empêcher**), vérifier que `notifications-rebut` redevient la politique effective ; à la 5e livraison en échec, le message part au **rebut** ; MédiNotif repart, la file se vide. Ensuite seulement : regarder le message au rebut (`rabbitmq-queues peek`… ou l'interface, en-tête `x-death` : `delivery_limit`) et décider avec Julien (il ne se rejoue pas tel quel ; MédiNotif devrait traiter une erreur d'analyse inattendue comme un message invalide : ticket pour l'équipe).

**Non-perte** (toutes variantes) : aucune purge ; le rebut contient au plus le message empoisonné (variante 3) ; le compteur `medinotif_messages_total{resultat="envoye"}` progresse d'autant que les publications (campagne comprise) ; la file finit vide. Consigne-le avec les chiffres.

**Prévention.** Règles de symptôme et tests : [`notifications-astreinte.yaml`](fichiers/S13/observabilite/regles/notifications-astreinte.yaml), [tests](fichiers/S13/observabilite/tests/notifications-astreinte.test.yaml) (`MedinotifAuPlafondEnRetard` critique, `MedinotifRedemarreEnBoucle`, `ArgoCDProductionDerive`) ; contrôle des politiques RabbitMQ hors topologie (comparaison `list_policies` / `plateforme/donnees` en CI planifiée) ; rotation outillée du compte `keda-prod` ; runbook [RB-338](fichiers/S13/medisphere/docs/exploitation/runbooks/RB-338-notifications-en-retard.md).

#### Messages d'état types

- **Début (10:26)** — *[INC-5913] SEV2 — rappels SMS de production en retard* — « La file des notifications de production grossit depuis 10:00 environ pendant la campagne de rappels ; les SMS partent en retard, aucun n'est perdu. Diagnostic en cours. Support : répondre aux cabinets que les rappels arrivent avec retard. Prochain point : 10:50. »
- **Point d'étape** — « Cause trouvée : l'ajustement automatique du nombre d'envois ne monte plus ([identifiants refusés | plafond modifié | message bloquant]). Correction en cours par le chemin normal ; retour à la normale estimé vers 11:15. »
- **Fin** — « Rétabli à 10:38 (effectif complet) ; file vide à 11:12 ; ≈ 9 800 rappels partis en retard (retard maximal 38 min), aucun perdu (vérifié). Prévention : alerte sur le retard des notifications (PLAT-3313). »

#### Main courante (extrait type, variante 2)

```
- 10:22 INC-5913 [ouverture] Nadia : rappels non reçus, file notifications prod qui grossit. SEV2.
- 10:26 INC-5913 [état] Message 1 (retard, aucune perte, prochain point 10:50).
- 10:31 INC-5913 [action] Entrée ≈ 110/s, sortie ≈ 40/s ; HPA 2/2 (max 2) ; ScaledObject Ready, pas de repli.
- 10:35 INC-5913 [action] Argo CD : medinotif-prod OutOfSync, ScaledObject maxReplicaCount 8 → 2 ; audit API : patch par <IDENTITÉ> à 09:58.
- 10:37 INC-5913 [décision] Synchronisation de medinotif-prod (le dépôt fait foi, max 8), différentiel relu : seul le ScaledObject change.
- 10:38 INC-5913 [action] Sync Argo CD ; HPA 8/8 ; sortie ≈ 160/s.
- 10:45 INC-5913 [état] Message 2 (retour à la normale estimé 11:15).
- 11:12 INC-5913 [action] File vide. Non-perte : rebut inchangé (0 nouveau), envoyés = publiés sur la période (medinotif_messages_total).
- 11:14 INC-5913 [clôture] Actions : PLAT-3313 (alertes de symptôme, dérive de la prod).
```

#### Explications

L'autoscaling sur la longueur d'une file ne sert que si trois choses tiennent : KEDA **lit** la file (identité valide, sinon repli figé), l'HPA **peut** monter (plafond, quotas, capacité), les pods **consomment** (pas de message qui les fait tomber). Le repli (`fallback`) masque la panne de lecture en gardant un effectif fixe : mieux que rien, insuffisant pour une campagne. La limite de livraison et le rebut transforment un message empoisonné en **un** message écarté au lieu d'un service arrêté ; les retirer, c'est retirer le fusible.

#### Alternatives

- Monter l'effectif à la main (`kubectl scale`) : KEDA/HPA le ramène ; au mieux un palliatif de quelques minutes, consigné.
- Variante 1 : remettre l'ancien mot de passe directement dans RabbitMQ (depuis le Secret) : rapide, mais contourne la rotation et masque l'origine.
- Variante 3 : rejeter le message empoisonné à la main depuis l'interface (« Reject requeue false ») : utile si les consommateurs sont tous arrêtés ; jamais sans avoir remis le rebut.

#### Pièges classiques

- Purger la file « pour soulager » : perte définitive de rappels de patients.
- Synchroniser la prod sans lire le différentiel (d'autres écarts peuvent attendre une décision).
- Supprimer le message empoisonné au lieu de l'envoyer au rebut.
- Conclure à un manque de capacité sans regarder les conditions du ScaledObject.

#### En production chez MédiSphère

Alerte de **symptôme** (retard d'envoi) routée à l'astreinte, en plus des alertes de cause ; contrôle de dérive de la prod (alerte Argo CD au-delà de la fenêtre de changement) ; rotation des comptes de service planifiée et testée ; politique RabbitMQ gérée **uniquement** par la topologie déclarative, avec une alerte sur toute politique inconnue ; MédiNotif idempotent (ADR-0270) pour pouvoir rejouer sans doublon.
