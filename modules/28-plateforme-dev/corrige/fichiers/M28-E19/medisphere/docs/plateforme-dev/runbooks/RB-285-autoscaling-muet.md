# RB-285 — L'autoscaling ne suit plus la charge (KEDA)

> Alertes `KedaScalerEnErreur`, `KedaScaledObjectEnPause`, `KedaAbsent` ; ou file qui grossit sans que l'effectif bouge. Rédigé en M28-E19. Propriétaire : équipe Plateforme.

## Impact
Les messages ne sont **pas perdus** (files quorum) : ils sont traités en retard. En prod, le minimum (2) et le repli (`fallback`) limitent le retard ; en recette, MédiNotif peut rester à 0.

## Arbre de décision

| Question | Commande | Si oui |
|---|---|---|
| 1. KEDA tourne-t-il ? | `kubectl -n keda get pods` ; `kubectl get apiservice v1beta1.external.metrics.k8s.io` | sinon : pods, événements, CNP de `keda` (`20-reseau.yaml`) |
| 2. Le `ScaledObject` est-il en pause ? | `kubectl -n <ns> get scaledobject medinotif` (colonne `PAUSED`) ; annotations `autoscaling.keda.sh/paused*` | `git log -p` de l'overlay ; retirer par MR (jamais `kubectl annotate`) |
| 3. Le scaler est-il en erreur ? | `kubectl -n keda logs deploy/keda-operator --since=15m \| grep <ns>` ; `keda_scaler_detail_errors_total` | lire le code : **401** → identifiants (ExternalSecret `medinotif-rabbitmq`, compte `keda-<env>`) ; **404** → chemin (`vhostName`, `queueName`) ; **délai** → réseau (`hubble observe --from-namespace keda --to-namespace messagerie`) |
| 4. La métrique arrive-t-elle à l'HPA ? | `kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1/namespaces/<ns>/<métrique>?labelSelector=scaledobject.keda.sh%2Fname%3Dmedinotif"` ; `kubectl describe hpa keda-hpa-medinotif` | sinon : adaptateur (`keda-operator-metrics-apiserver`), APIService |
| 5. L'HPA décide-t-il mais rien ne bouge ? | `kubectl describe hpa` (conditions `ScalingLimited`, `AbleToScale`) ; quotas, budget du locataire | `maxReplicaCount`, quota d'espace, budget (`kubectl get globalresourcequotas`) |

## Correctifs
- Toujours par MR dans `medinotif/deploiement` (overlay de l'environnement) ; un secret faux se corrige dans OpenBao puis `kubectl -n <ns> annotate externalsecret medinotif-rabbitmq force-sync=$(date +%s) --overwrite`.
- Ne pas redémarrer KEDA « pour voir » : il sert aussi la production.

## Vérification
`campagne.sh 300` (recette) : MédiNotif sort de 0 en moins d'une minute, la file se vide ; `lab/bin/check 28 19`.
