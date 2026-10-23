# Sous le capot : HPA, métriques externes, webhooks de Capsule

> Rédigé en M28-E24 (PLAT-2924). La page que l'astreinte lit à 3 h du matin. Chiffres du lab de référence.

## 1. Les trois commandes d'abord
```
kubectl -n <ns> describe hpa <hpa>                                  # ce que voit et décide l'HPA
kubectl get apiservice v1beta1.external.metrics.k8s.io              # Available ? (KEDA)
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations | grep -i capsule
```

## 2. Le calcul de l'HPA
`desiredReplicas = ceil[currentReplicas × (currentMetricValue / desiredMetricValue)]` ; rien ne bouge si le rapport est dans la **tolérance** (0,1 par défaut, réglable par règle de comportement depuis Kubernetes 1.34 : champ `tolerance`) ; boucle toutes les 15 s (`--horizontal-pod-autoscaler-sync-period`).

Exemple relevé (MédiAgenda recette, cible 70 % du CPU demandé, requests 100m) :
| Pods | CPU (m) | Utilisation moyenne | Rapport | Calcul | Décision |
|---|---|---|---|---|---|
| 2 | 72 + 80 | 76 % | 1,086 | dans la tolérance (< 1,1) | 2 |
| 2 | 95 + 101 | 98 % | 1,40 | ⌈2 × 1,40⌉ = 3 | 3 |
| 3 | 30 + 28 + 35 | 31 % | 0,44 | ⌈3 × 0,44⌉ = 2 | 3 pendant 300 s (fenêtre de stabilisation : la plus haute recommandation de la fenêtre), puis 2 |

Pods non prêts ou sans métrique : comptés à 0 % en montée et à 100 % en descente (décision prudente). Plusieurs métriques : un calcul par métrique, on garde le **maximum**.

Comportement de MédiNotif (E13) : en montée, `selectPolicy: Max` entre +100 % et +2 pods par 15 s — à 3 pods, +3 (100 %) l'emporte sur +2 ; en descente, `Min` avec une seule politique (1 pod par 60 s). `selectPolicy: Disabled` interdit le sens concerné : c'est ce que KEDA pose pour les annotations `paused-scale-in` / `paused-scale-out`.

## 3. Le chemin d'une métrique externe
```
HPA (kube-controller-manager)
  → GET /apis/external.metrics.k8s.io/v1beta1/namespaces/<ns>/s0-rabbitmq-notifications?labelSelector=scaledobject.keda.sh/name=medinotif
  → kube-apiserver (agrégateur) → APIService v1beta1.external.metrics.k8s.io → Service keda/keda-operator-metrics-apiserver
  → adaptateur KEDA → gRPC (9666) → keda-operator (cache des scalers)
  → scaler rabbitmq → HTTPS 15671 rabbitmq.messagerie.svc : GET /api/queues/medinotif-recette/notifications
```
Nom de la métrique : `s<index du déclencheur>-<scaler>-<détail>`. Un seul `APIService` peut servir `external.metrics.k8s.io` : KEDA occupe la place, aucun autre adaptateur de métriques externes ne peut coexister.

## 4. Webhooks de Capsule
Tableau tiré de `kubectl get validatingwebhookconfigurations -o json | jq …` (relevé du lab ; noms et liste à relire à chaque montée) :

| Webhook (ressources) | Opérations | Politique d'échec | Portée | Bloque la prod s'il tombe ? |
|---|---|---|---|---|
| espaces (`namespaces`) | CREATE, UPDATE, DELETE | Fail | tout le cluster | **oui** : aucune création d'espace |
| pods (`pods`) | CREATE, UPDATE | Fail | espaces avec `capsule.clastix.io/tenant` | **oui** : aucun pod dans les espaces des locataires |
| services, PVC, ingress, gateways | CREATE, UPDATE | Fail | espaces des locataires | oui pour ces objets |
| tenants, configuration | CREATE, UPDATE, DELETE | Fail / Ignore | cluster | non pour les applications |
| métadonnées | CREATE, UPDATE | Ignore | espaces des locataires | non |

Latence ajoutée (p99 de `apiserver_admission_webhook_admission_duration_seconds`, webhooks de Capsule) : ≈ 15 ms.
