# Module 22 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

### M22-E25 — Mini-projet : les journaux de MédiSphère v1

Il n'y a pas de solution unique : ce corrigé donne un **plan de travail** éprouvé, la préparation des quatre démonstrations et la **grille de revue**. Les fichiers de référence sont ceux des exercices du module ; le seul nouveau est le modèle de note de livraison [`livraison-journaux-v1.md`](fichiers/M22-E25/medisphere/docs/observabilite/journaux/livraison-journaux-v1.md).

**Solution**

*Plan de travail recommandé* (on prouve d'abord, on nettoie ensuite, on documente à la fin)

1. **État des lieux** (30 min) : `lab/bin/check 22 25`, puis les contrôles détaillés rouges (`lab/bin/check 22 XX`) ; inventaire des restes :
   ```
   admin@adm01:~$ kubectl get ns | grep -E 'essai|pannes'
   admin@adm01:~$ kubectl -n argocd get applications | grep -Ei 'essai|fluent|opensearch'
   admin@adm01:~$ kubectl get pv | grep -E 'essai'
   admin@adm01:~$ ls ~/.local/state/workbook/pannes-actives/ | grep M22
   admin@adm01:~$ kubectl -n mediagenda-recette get rolebindings -o wide
   ```
2. **Rien de provisoire** (1 h) : clore les pannes (`lab/bin/break 22 XX --annuler`, qui ne défait pas tes réparations), supprimer le déploiement `journal-temoin` s'il reste, le témoin de données de E09 (`wb-essais/temoin-donnees`) **après** l'essai du point 4, les Applications et espaces d'essai (E10, E15) avec leurs volumes, les entrées `fluent-bit` et `opensearch` du miroir des charts (aucune Application ne s'en sert ; le contrôle global le vérifie).
3. **Couverture** (1 h) : pour chaque nœud et chaque VM du socle, une ligne récente ; pour chaque espace applicatif, des lignes dans le bon locataire ; `logcli series --analyze-labels` sur chaque locataire.
   ```
   admin@adm01:~$ for n in k8s-cp01 k8s-cp02 k8s-cp03 k8s-w01 k8s-w02 k8s-w03; do printf '%-9s ' $n; logcli query --org-id=plateforme --since=10m --quiet --limit=1 "{node=\"$n\"}" | wc -l; done
   admin@adm01:~$ for h in ${WB_M22_VMS_SOCLE:-gw01 gw02 adm01 dns01 dns02 ca01 git01 runner01 runner02 nbx01 s3-01 reg01 mon01 lb01 lb02}; do printf '%-9s ' $h; logcli query --org-id=plateforme --since=15m --quiet --limit=1 "{host=\"$h\"}" | wc -l; done
   ```
4. **Données de santé** (30 min) : rejouer le témoin de E09 (`ressources/E09-temoin`), vérifier que ses lignes arrivent masquées, retirer le témoin ; `lab/bin/check 22 09` sur 24 h.
5. **Règles appliquées** (30 min, puis attente) : une demande d'effacement sur `essai` **au début** du mini-projet (elle sera `processed` après 24 h et un passage du compactor) ; vérifier rétentions et limites (`/config/tenant/v1/limits`, ConfigMap `loki-runtime`), le compactor (`/services`, métriques).
6. **Alertes** (1 h) : une alerte par locataire, déclenchée par un moyen réversible et noté :
   - `audit` : quelques échecs d'authentification sur l'API (`kubectl --token=invalide get pods` répété) ;
   - `mediagenda` : une rafale de 5xx sur `mediagenda-dev` (par exemple en coupant Valkey de dev quelques minutes avec l'accord de Julien, ou par le scénario prévu en E08) ;
   - `plateforme` : la règle de E08 de ce locataire selon son déclencheur ;
   - « Alloy absent d'un nœud » (`AlloyAbsentDUnNoeud`, règle Prometheus écrite en E19 : [`regles/alloy-collecte.yaml`](fichiers/M22-E19/observabilite/regles/alloy-collecte.yaml), `for: 5m`) : taint de test sur un travailleur + suppression du pod Alloy (comme en E19), chronométré, puis retour.
   Vérifier la réception dans Mailpit par la bonne adresse (`equipe`).
7. **Accès et sauvegarde** (30 min) : `lab/bin/check 22 16` ; essai depuis un compte d'équipe dans Grafana ; `aws s3api get-bucket-versioning`.
8. **Documentation** (1 h 30) : compléter les documents de l'état livré, la note de livraison (modèle fourni), la matrice des flux (socle : VMs → 10.10.41.62:3100 ; cluster : section `journaux`).
9. **Livraison** (30 min) : MR, pipelines verts, `lab/bin/check 22 25` vert, étiquette `journaux-v1` sur `plateforme/medisphere`.

*Les quatre démonstrations* (à répéter **avant** la revue)

| Démonstration | Préparation | Ce qu'on montre | Attendu |
|---|---|---|---|
| Sophie : « qui a fait quoi à telle heure ? » | Un tableau Grafana « Audit » dans l'organisation Sécurité : gestes d'écriture par utilisateur (`sum by (user, verb) (count_over_time({job="kubernetes-audit"} | verb=~"create|update|patch|delete" [5m]))`) et une table des lignes | Réponse en < 5 min, avec la ligne d'audit (identité, ressource, objet) ; un compte d'équipe ne voit pas la source ; `lab/bin/check 22 09` vert | Montrer aussi ce que l'audit **ne** contient pas (corps des Secrets : niveau `Metadata`) |
| Nadia : arrêt d'Alloy sur un travailleur | Taint de test + suppression du pod (ou `kubectl -n journaux delete pod` répété), chronomètre lancé | Alerte en < 10 min ; après le retour : fichiers des pods rattrapés depuis les positions, journald rattrapé (dans `max_age`) | Expliquer pourquoi rien n'est perdu sur un arrêt court, et ce qui le serait (rotation des fichiers du kubelet) |
| Julien : une requête par son identifiant | Récupérer un `request_id` dans l'en-tête de réponse de MédiAgenda (E06) | `{namespace="mediagenda-recette"} | request_id="…"` dans Grafana ou `logcli` | Pas d'étiquette `request_id` (liste fermée), réponse rapide grâce au sélecteur |
| Karim : une rétention plus courte pour un flux d'essai | MR prête : une règle `retention_stream` de 24 h sur un flux d'essai du locataire `plateforme` (par exemple `{namespace="wb-essais", app="…"}`) ; 24 h est le minimum du compactor | MR, diff d'Argo CD, rechargement (`loki_runtime_config_hash`), `/config/tenant/v1/limits`, prochain passage du compactor, `retention_delete_delay` | Savoir dire à chaque étape ce qui est encore réversible |

*Grille de revue*

| Critère | Attendu | Poids |
|---|---|---|
| Contrôle global | `lab/bin/check 22 25` vert, sans exception non justifiée | élevé |
| Rien de provisoire | essais, témoins, pannes, droits de panne retirés ; volumes d'essai supprimés | élevé |
| Collecte | six nœuds, toutes les VMs du socle, audit, événements ; liste fermée respectée | élevé |
| Données de santé | masquage prouvé par le témoin, aucun motif sur 24 h | élevé |
| Rétention et effacement | durées conformes, effacement d'essai `processed`, compactor actif, versionnage | élevé |
| Alertes | une alerte par locataire éprouvée et reçue par la bonne équipe ; alerte de collecte | moyen |
| Accès | politiques réseau, audit dans l'organisation Sécurité, décisions écrites (transport, sauvegarde) | moyen |
| Documentation | état livré complet, runbooks testés pendant les pannes, ADR et note de livraison | moyen |
| Démonstrations | les quatre réussies dans le temps, explications justes | élevé |

**Explications**

Le mini-projet ne demande rien de nouveau : il oblige à rendre **cohérent** ce que les exercices ont posé un par un, et à prouver ce qui ne se voit pas dans un fichier (une alerte qui part vraiment, un masquage qui masque vraiment, une rétention qui s'applique vraiment). Les démonstrations sont choisies pour cela : chacune exerce une propriété de la brique (traçabilité, résilience de la collecte, cardinalité maîtrisée, réversibilité d'un changement dangereux).

**Pièges classiques**
- Supprimer `wb-pannes` ou des objets de journald « pour faire propre » : les témoins et pannes se retirent par `--annuler` ; aucune donnée ne se supprime.
- Faire la demande d'effacement d'essai la veille de la revue : elle sera encore `received` (délai d'annulation de 24 h).
- Éprouver l'alerte de MédiAgenda en prod ou sans prévenir Julien.
- Oublier les volumes des essais (`opensearch-essai`) : la classe `ceph-rbd` les supprime avec le PVC, pas avec l'Application.
- Démontrer une réduction de rétention sur un flux réel « parce que c'est plus parlant » : c'est exactement le geste que la politique interdit sans ticket.

**En production chez MédiSphère**
La note de livraison est relue au comité et archivée avec l'étiquette ; la grille sert à la recette annuelle de la brique ; les mesures de référence alimentent le dimensionnement des workbooks finaux (F2, F7).
