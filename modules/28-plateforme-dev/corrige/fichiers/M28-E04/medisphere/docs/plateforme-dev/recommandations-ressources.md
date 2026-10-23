# Recommandations de ressources (VPA)

> Plateforme développeurs — M28-E04 (PLAT-2904). Responsable : équipe Plateforme. À revoir à chaque trimestre et après chaque changement notable d'une application.

## Dispositif

- **VPA 1.7.1** (Application `vpa`, espace `vpa`) : *recommender*, *updater*, *admission-controller* (webhook en `failurePolicy: Ignore`).
- Un `VerticalPodAutoscaler` **en `Off`** par charge, nommé comme elle, déclaré dans le dépôt de déploiement de l'équipe :

| VPA | Espace | Cible |
|---|---|---|
| `mediagenda` | `mediagenda-recette`, `mediagenda-prod` | Rollout `mediagenda` (le Deployment n'est que le gabarit, à 0 réplica) |
| `medinotif` | `medinotif-recette`, `medinotif-prod` | Deployment `medinotif` |
| `medidoc` | `medidoc-recette` | Deployment `medidoc` |

- Les recommandations se lisent par `kubectl describe vpa` ou `kubectl get vpa <nom> -o jsonpath='{.status.recommendation}'` ; les `requests` se changent **par MR**, jamais par le VPA.

## Recommandations relevées

> Valeurs **représentatives** (corrigé) après ≈ 24 h de trafic de recette (`charge.sh` deux fois par jour) et le trafic réel de la production. Remplace-les par les tiennes, avec la durée d'observation.

| Application, environnement | Conteneur | `requests` actuelles | `target` | `lowerBound` – `upperBound` | Consommation mesurée (p95 sur 24 h) | Décision |
|---|---|---|---|---|---|---|
| MédiAgenda, recette | `api` | 200 m / 192 Mi | 163 m / 178 Mi | 25 m – 410 m / 150 – 260 Mi | 150 m / 175 Mi | **Garder** : l'HPA vise 70 % de 200 m ; descendre les `requests` ferait monter l'HPA plus tôt (plus de pods, même consommation totale) |
| MédiAgenda, prod | `api` | 200 m / 192 Mi | 35 m / 165 Mi | 15 m – 120 m / 150 – 210 Mi | 30 m / 160 Mi | **Garder le CPU** (l'HPA en dépend, la prod n'a pas encore connu de pic) ; mémoire inchangée |
| MédiNotif, recette | (unique) | 100 m / 128 Mi | 15 m / 100 Mi | 15 m – 60 m / 100 – 130 Mi | 12 m / 70 Mi | Descendre à **25 m / 96 Mi** (limite 192 Mi) |
| MédiNotif, prod | (unique) | 100 m / 128 Mi | 15 m / 100 Mi | 15 m – 40 m / 100 – 120 Mi | 10 m / 68 Mi | Idem après une campagne de rappels observée |
| MédiDoc, recette | (unique) | 50 m / 64 Mi | 15 m / 100 Mi | 15 m – 80 m / 100 – 180 Mi | 20 m / 85 Mi | **Monter la mémoire à 96 Mi** (la `request` actuelle est sous la consommation stable : pod en tête de liste d'éviction) |

`100 Mi` et `15 m` sont les **planchers** du *recommender* (`pod-recommendation-min-memory-mb`, `pod-recommendation-min-cpu-millicores`) : une recommandation égale au plancher veut dire « moins que ça ».

Ce qu'on ne fait pas : suivre une recommandation de moins de 24 h (`LowConfidence`), ni descendre le CPU d'une charge pilotée par un HPA sur le CPU sans refaire le calcul de l'HPA.

## Essai de redimensionnement en place (`wb-essais`)

| Étape | Observé |
|---|---|
| `essai-vpa` appliqué (1 pod, `requests` 20 m, consommation ≈ 100 m) | recommandation `target` ≈ 110 m après quelques minutes |
| Updater sans `updatePolicy.minReplicas` | rien : la charge a 1 pod, sous le seuil `--min-replicas` (2) de l'updater |
| `updatePolicy.minReplicas: 1` | le pod est **redimensionné en place** : même UID, `restartCount` 0, `spec.containers[0].resources.requests.cpu` et `status.containerStatuses[0].resources` passent à ≈ 110 m (limites ajustées en proportion : `controlledValues` par défaut `RequestsAndLimits`) |
| Redimensionnement à la main : `kubectl -n wb-essais patch pod <pod> --subresource resize --patch '{"spec":{"containers":[{"name":"calcul","resources":{"requests":{"cpu":"150m"}}}]}}'` | accepté, sans redémarrage (`resizePolicy` CPU `NotRequired`) ; le VPA le ramène ensuite à sa recommandation |
| Même chose sur la mémoire | le conteneur **redémarre** (`RestartContainer`), le pod reste le même |

Ce qui empêche le redimensionnement en place : un changement qui ferait changer la **classe de QoS** (ex. `requests` = `limits` partout → `Guaranteed`) ; un nœud sans la place nécessaire (le *resize* reste `Pending`, puis l'updater **évince** en mode `InPlaceOrRecreate`) ; une politique `RestartContainer` sur la mémoire (redémarrage du conteneur, pas du pod) ; une charge déclarant ses ressources au niveau du **pod** (non gérée par le VPA 1.7). L'essai a été supprimé (`kubectl delete -f`).

## Garde-fous

1. **Jamais un VPA actif et un HPA sur le même CPU (ou la même mémoire).** L'HPA de MédiAgenda mesure `consommation / requests` : si le VPA monte les `requests`, l'utilisation baisse, l'HPA retire des pods, la consommation par pod remonte, le VPA remonte les `requests`… Les deux boucles se répondent. Un HPA sur une métrique **externe** (KEDA) n'a pas ce couplage, mais un VPA actif sur MédiNotif évincerait des workers en plein traitement à chaque ajustement : recommandations seulement.
2. **Mode actif uniquement par décision écrite** (ADR) et sur une charge sans HPA sur la même ressource, avec des `minAllowed`/`maxAllowed` et un PDB.
3. **Le webhook reste en `Ignore`** : une panne de l'admission-controller ne doit jamais bloquer la création des pods du cluster.
