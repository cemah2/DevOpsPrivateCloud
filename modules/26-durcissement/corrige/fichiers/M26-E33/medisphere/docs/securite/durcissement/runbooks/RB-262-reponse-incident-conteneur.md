# RB-262 — Réponse à incident : conteneur compromis

| | |
|---|---|
| Ticket | SEC-2733 (M26-E33) ; éprouvé en M26-E42 |
| Propriétaire | RSSI (Sophie Laurent) ; exécution : astreinte Plateforme |
| Dernier exercice | <DATE> (exercice sur table + essai sur `wb-essais/suspect`, compte rendu dans `rapports/`) |

## 0. Principes

1. **Isoler sans détruire** : un pod supprimé, c'est la mémoire, les fichiers temporaires et les connexions perdus. On isole d'abord, on supprime en dernier.
2. **Tracer chaque geste** : journal d'incident horodaté (`docs/kubernetes/journal/<AAAA-MM-JJ>-INC-NNNN.md`, post-mortem dans `docs/kubernetes/post-mortems/`), qui a fait quoi, quand, avec quelle commande.
3. **Ne rien installer dans le conteneur suspect** : on regarde de l'extérieur (kubelet, API, conteneur éphémère, nœud, journaux centraux).
4. **Une preuve = un fichier + une empreinte SHA-256 + qui l'a collectée et quand**, déposée dans le compartiment `preuves` (versionné, identité sans suppression).

## 1. Rôles

| Rôle | Qui | Responsabilités |
|---|---|---|
| Responsable de l'incident | astreinte Plateforme (heures non ouvrées), sinon Karim Benali | décide l'isolement, coordonne, tient le journal |
| Collecte | un second membre de la Plateforme | collecte et dépôt des preuves, empreintes |
| RSSI | Sophie Laurent (prévenue **dans l'heure**, de jour comme de nuit) | qualification, décision de violation de données, autorités |
| Communication | Claire Morel | direction, équipes (Julien Petit pour MédiAgenda), clients si besoin |
| Support | Nadia Roussel | astreinte, impact client, tickets |

Contacts et numéros : annuaire d'astreinte (hors de ce dépôt).

## 2. Détection et qualification (15 min)

Sources : alertes Falco (Alertmanager, Loki `{service="falco"}`), `TetragonProcessusTue` et événements Tetragon (`{service="tetragon"}`), audit de l'API (`AuditExecProduction`, `AuditLectureSecretParPersonne`…), Hubble (`hubble observe --pod <espace>/<pod> --verdict DROPPED`).

Questions : quel pod, quel espace, quel nœud, quelle image (digest), depuis quand ? Un processus inattendu, une connexion vers l'extérieur, une lecture de jeton ? **Faux positif** démontré (déploiement en cours, test annoncé) → clôture motivée. Sinon : incident ouvert (`INC-…`), RSSI prévenue.

## 3. Isolement (5 min)

```
admin@adm01:~$ export NS=<ESPACE> POD=<POD> ; date -u +%FT%TZ          # T_isolement, dans le journal
admin@adm01:~$ kubectl -n $NS label pod $POD medisphere.internal/quarantaine=oui
admin@adm01:~$ kubectl -n $NS get pod $POD -o yaml > /dev/null && hubble observe --pod $NS/$POD --last 20
```

La politique de cluster `quarantaine` (posée à l'avance, `composants/reseau/politiques/quarantaine.yaml`) refuse toute entrée (sauf les sondes de l'hôte local) et toute sortie, quelles que soient les politiques de l'équipe.

**Sortir le pod de son contrôleur** (sinon il reste dans le Service, et un `rollout` ou une mise à l'échelle le tuerait) : retirer une étiquette du sélecteur du ReplicaSet. Le contrôleur recrée un pod sain ; le suspect devient orphelin et continue de tourner, isolé.

```
admin@adm01:~$ kubectl -n $NS get rs -l app.kubernetes.io/name=<APPLI> -o jsonpath='{.items[*].spec.selector}'
admin@adm01:~$ kubectl -n $NS label pod $POD app.kubernetes.io/name-        # ou l'étiquette du sélecteur
admin@adm01:~$ kubectl -n $NS get pods -o wide                              # un nouveau pod, le suspect toujours là
```

Argo CD : l'Application de l'équipe passe « OutOfSync » (pod hors gestion) : ne pas synchroniser en élagage (`prune`) avant la fin de la collecte. Si le pod porte une étiquette de Rollout (Argo Rollouts), même geste sur l'étiquette du sélecteur.

Vérifier que l'isolement n'a **pas** redémarré le conteneur : `kubectl -n $NS get pod $POD -o jsonpath='{.status.containerStatuses[*].restartCount}'` (identique à avant).

## 4. Collecte (30 à 60 min, dans cet ordre : du plus volatil au plus durable)

Dossier de travail en mémoire sur `adm01` : `D=$(mktemp -d "$XDG_RUNTIME_DIR/inc.XXXXXX")`.

| # | Pièce | Commande |
|---|---|---|
| 1 | État du pod et du nœud | `kubectl -n $NS get pod $POD -o yaml > $D/pod.yaml` ; `kubectl get node <NŒUD> -o yaml > $D/noeud.yaml` |
| 2 | Processus et connexions, vus d'un conteneur éphémère (même espace de processus que la cible) | `kubectl -n $NS debug -it pod/$POD --image=registry.par1.medisphere.internal/dockerhub/nicolaka/netshoot:v0.16 --target=<CONTENEUR> --profile=restricted -- sh -c 'ps -ef; ls -l /proc/1/exe /proc/1/cwd; cat /proc/1/cmdline \| tr "\0" " "; ss -tnap' > $D/processus.txt` |
| 3 | Fichiers déposés (sans les exécuter) | depuis le conteneur éphémère : `ls -la /proc/1/root/tmp` ; copie par `kubectl cp` **depuis le conteneur éphémère** (`/proc/1/root/tmp/<FICHIER>`) |
| 4 | Journaux du conteneur | `kubectl -n $NS logs $POD --all-containers --timestamps > $D/logs.txt` (et `--previous` s'il a redémarré) |
| 5 | Événements de sécurité | export Loki (locataire `audit`) : `{service=~"falco\|tetragon"} \|= "<POD>"` et `{job="kubernetes-audit"} \|= "<POD>"` sur la période, en JSON (Grafana « Inspecter → Données » ou `logcli`) |
| 6 | Flux réseau | `hubble observe --pod $NS/$POD --since 24h -o json > $D/hubble.json` (tampon limité : le faire tôt) |
| 7 | *Checkpoint* du conteneur (si disponible) | API du kubelet `POST /checkpoint/<ns>/<pod>/<conteneur>` (fonction `ContainerCheckpoint` : statut en 1.36 et CRIU sur les nœuds **à vérifier** ; sinon sauter, et le noter) |
| 8 | Instantané du disque du nœud | sur `pve01` : `vzdump <VMID> --storage pbs-par2 --mode snapshot --notes-template "INC-NNNN preuve"` (namespace PBS `par1/k8s`) ; noter l'identifiant de la sauvegarde |

Empreintes et dépôt :

```
admin@adm01:~$ (cd $D && sha256sum * > SHA256SUMS && cat SHA256SUMS)       # recopiées dans le journal d'incident
admin@adm01:~$ (set -a; . ~/.config/workbook/s3-preuves-depot.env; set +a; \
                aws s3 cp --recursive $D s3://preuves/INC-NNNN/$(date -u +%FT%TZ)/ \
                --endpoint-url https://s3-01.par1.medisphere.internal:8333)
admin@adm01:~$ rm -rf "$D"
```

## 5. Analyse

Chronologie (premier signe, accès initial probable, actions, sorties), image en cause (digest, signature Kyverno vérifiée ?, CVE connues : `outils/cve-en-service.sh`), étendue (autres pods de la même image, même compte de service, mêmes secrets montés ?), données touchées (le pod avait-il accès à des données de santé ? à quel Secret ?).

## 6. Éradication et rétablissement

- Supprimer le pod suspect **après** la collecte et l'accord de la RSSI ; révoquer ce qu'il a pu voir : rotation des secrets montés ou lus (OpenBao : nouveaux identifiants, révocation des baux du moteur `database`), jeton de compte de service (supprimer le compte de service et le recréer si un jeton long a pu fuiter).
- Corriger la cause (image reconstruite, dépendance corrigée, politique Kyverno/Falco/Tetragon renforcée), par MR.
- Rétablir : le contrôleur a déjà recréé un pod sain (étape 3) ; vérifier ses sondes, ses journaux, l'absence de nouvelle alerte pendant 24 h.

## 7. Communication et obligations

- Interne : point toutes les heures pendant la phase active (Claire, Sophie, Nadia).
- **Violation de données personnelles** (données de santé consultées, copiées ou altérées, ou impossibilité de l'exclure) : décision de la RSSI et du DPO. RGPD, article 33 : notification à la CNIL dans les **72 heures** après en avoir pris connaissance ; article 34 : information des personnes si risque élevé. Hébergement de données de santé : information des clients (responsables de traitement) selon le contrat HDS ; signalement des incidents graves de sécurité des systèmes d'information de santé (article L.1111-8-2 du code de la santé publique, portail de signalement, CERT Santé) **sans délai**. Délais et circuits **à confirmer avec le DPO** à chaque revue de ce runbook.
- Tout est consigné dans le journal d'incident.

## 8. Retour d'expérience

Post-mortem sans recherche de coupable sous 5 jours ouvrés (`docs/kubernetes/post-mortems/`), actions avec responsable et date, mise à jour de ce runbook et des règles de détection.

## Annexe — essai de la quarantaine (pod de test `wb-essais/suspect`)

```
admin@adm01:~$ kubectl -n wb-essais apply -f pod-suspect.yaml && kubectl -n wb-essais rollout status deploy/suspect
admin@adm01:~$ P=$(kubectl -n wb-essais get pod -l app.kubernetes.io/name=suspect -o name | head -1)
admin@adm01:~$ kubectl -n wb-essais label $P medisphere.internal/quarantaine=oui
admin@adm01:~$ kubectl -n wb-essais apply -f pod-essai-tetragon.yaml     # pod d'outils conforme à restricted (M26-E29)
admin@adm01:~$ kubectl -n wb-essais exec essai-tetragon -- curl -m 3 -s http://<IP-DU-POD>:8080/hostname   # échoue
admin@adm01:~$ kubectl -n wb-essais exec ${P#pod/} -- /agnhost connect 10.10.20.10:53 --timeout 3s   # échoue (sortie refusée)
admin@adm01:~$ sleep 60; kubectl -n wb-essais get $P -o jsonpath='{.status.containerStatuses[0].restartCount}'   # 0 : pas de redémarrage
admin@adm01:~$ kubectl -n wb-essais label $P app.kubernetes.io/name-     # sorti du ReplicaSet : un nouveau pod apparaît
admin@adm01:~$ kubectl -n wb-essais delete $P ; kubectl -n wb-essais delete deploy/suspect   # fin de l'essai
```
