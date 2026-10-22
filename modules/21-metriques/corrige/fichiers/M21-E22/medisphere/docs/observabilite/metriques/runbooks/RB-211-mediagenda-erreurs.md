# RB-211 — MediagendaTauxErreurEleve : l'API MédiAgenda renvoie des erreurs

**Alerte** : `MediagendaTauxErreurEleve` (critique en prod au-delà de 5 %, avertissement de 2 à 5 % et hors prod ; équipe `mediagenda`) · **Tableau** : [RED MédiAgenda](https://grafana.apps.par1.medisphere.internal/d/mediagenda-red?var-environnement=prod) · **Dernière vérification** : à la création (M21-E22)

## Que signifie cette alerte
Plus de 5 % (critique) ou de 2 % (avertissement) des requêtes de l'API de MédiAgenda se terminent
par une erreur **5xx** depuis 10 minutes, avec un trafic d'au moins 6 requêtes par minute. Les
routes de sonde (`/sante`, `/pret`, `/metrics`) ne comptent pas.

## Impact pour les utilisateurs
Des centres de santé ne peuvent pas **prendre, consulter ou annuler** un rendez-vous ; certains
réessaient, d'autres appellent le support. En prod, c'est un incident dès que l'alerte est critique.

## Premières vérifications (5 minutes)
1. Vu de l'extérieur : la sonde du témoin répond-elle ? `probe_success{instance=~".*mediagenda.apps.*"}`
   sur `http://mon01.par1.medisphere.internal:9090` (hors cluster).
2. Étendue, sur le Prometheus du cluster (`http://prometheus.apps.par1.medisphere.internal:9090`) :
   ```
   sum by (route, code) (rate(mediagenda_http_requests_total{environnement="prod", code=~"5.."}[5m]))
   sum by (pod) (rate(mediagenda_http_requests_total{environnement="prod", code=~"5.."}[5m]))
   ```
   Une route ? un pod ? tous ?
3. Changement récent : `admin@adm01:~$ kubectl argo rollouts get rollout mediagenda -n mediagenda-prod`
   (révision, canary en cours ?) et l'historique de l'Application `mediagenda-prod` dans Argo CD.
4. Dépendances : `admin@adm01:~$ kubectl get cluster mediagenda-db -n mediagenda-prod` (CNPG :
   `Cluster in healthy state` ?), pods `valkey` prêts ? Journaux de l'API :
   `kubectl logs -n mediagenda-prod -l app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api -c api --since=15m --prefix | grep -i erreur`.

## Causes connues et actions
| Ce que tu observes | Cause probable | Action |
|---|---|---|
| Erreurs sur le seul canary, depuis le début d'une mise en production | nouvelle version défectueuse | l'analyse d'Argo Rollouts doit avorter ; sinon `kubectl argo rollouts abort mediagenda -n mediagenda-prod`, puis prévenir Julien Petit |
| Erreurs sur tous les pods, `/pret` en 503 | PostgreSQL (CNPG) ou Valkey indisponible | suivre l'état du cluster CNPG ; bascule automatique en cours ? ne rien forcer sans Karim |
| Erreurs sur une seule route, avec une requête particulière | entrée inattendue non traitée (bogue) | relever un exemple dans les journaux (sans donnée patient), ticket `DEV-` à Julien ; en heures ouvrées |
| Erreurs et latence ensemble, CPU bridé | saturation (voir INC-4823) | augmenter les réplicas par une MR dans `mediagenda/deploiement` (overlay prod) |

## Escalade
- **Critique en prod** : astreinte (Nadia Roussel) ; Julien Petit (application) si une version
  récente est en cause ; Karim Benali (plateforme) si la base, le réseau ou le cluster sont en
  cause. Ouvre un incident `INC-48xx` si l'impact dépasse 15 minutes.
- Avertissement : ticket à l'équipe MédiAgenda, traité aux heures ouvrées.

## Retour à la normale
`environnement:mediagenda_requetes_5xx:ratio_taux5m{environnement="prod"}` sous 1 % pendant
15 minutes (l'alerte reste active 10 minutes après le retour sous le seuil : `keep_firing_for`).

## Après l'incident
Post-mortem si plus de 15 minutes d'impact en prod (`docs/kubernetes/post-mortems/`) ; le seuil de
l'analyse du canary (`taux-erreur-mediagenda`) aurait-il dû l'arrêter ?
