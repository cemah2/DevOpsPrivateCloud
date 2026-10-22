# Chaîne de traces : capacité, rétention et sécurité (M23-E16)

> Document d'exemple du corrigé : les volumes sont ceux d'un lab de référence, remplace-les par tes mesures.

## Point d'entrée hors cluster

| Élément | Valeur |
|---|---|
| Nom, adresse | `otlp.apps.par1.medisphere.internal` → 10.10.41.63 (Service `otlp-externe`, `externalTrafficPolicy: Local`) |
| Ports publiés | 4317 (OTLP/gRPC) → 14317 de la passerelle ; 4318 (OTLP/HTTP) → 14318 |
| TLS | Certificat cert-manager `otlp-externe` (ClusterIssuer `step-ca-acme`, DNS-01), 24 h, renouvelé aux deux tiers ; la passerelle relit le fichier toutes les heures (`reload_interval: 1h`) ; TLS 1.2 minimum |
| Authentification | `bearertokenauth/externe` : un jeton par émetteur dans le Secret `otlp-jetons` (fichier relu à chaud) |
| Tailles | gRPC : 4 Mio par message ; HTTP : 4 Mio par requête (refus `400 request body too large`) |
| Réseaux autorisés | 10.10.0.0/16 (CiliumNetworkPolicy `traces-passerelle`) ; la bordure ne laisse entrer que les réseaux du lab |

Les agents du cluster parlent à l'entrée **interne** (4317/4318, sans TLS) que la CNP réserve aux pods `otel-agent` et `otel-passerelle`. Les données externes passent par le pipeline `traces/externe`, qui les renvoie par `loadbalancing` (clé `traceID`) aux réplicas avant l'échantillonnage en queue.

Ce qu'un émetteur voit quand il dépasse une limite :

| Situation | Réponse | Comportement d'un SDK ou d'un Collector émetteur |
|---|---|---|
| Pas de jeton / jeton inconnu | HTTP 401 (`Unauthenticated` en gRPC) | erreur permanente, données abandonnées, message dans les journaux de l'émetteur |
| Message trop gros | HTTP 400 / gRPC `ResourceExhausted` | abandon du lot : réduire la taille des lots de l'émetteur |
| Passerelle saturée (`memory_limiter`) | refus temporaire | nouvelle tentative avec attente, puis abandon |
| Tempo au-delà de `rate_limit_bytes` | `RATE_LIMITED` vers la passerelle | la passerelle réessaie (file d'attente de 50 000 spans), alerte `CollectorFileDAttentePleine` |

## Jetons

- Source de vérité : Ansible Vault `critique`, `secrets/otel.yml` (`otel_jetons_otlp`, une entrée par émetteur : nom, jeton, date de création, propriétaire). Matérialisés par `plateforme/k8s/outils/secrets-k8s.sh otel` en Secret `traces/otlp-jetons` (clé `jetons` : « `<jeton> <nom-de-l'émetteur>` » par ligne).
- Création : `openssl rand -hex 32`, ajout dans Vault, `secrets-k8s.sh otel`, remise du jeton à l'équipe émettrice par le coffre de l'équipe (jamais par ticket ni par courriel).
- Rotation (tous les 90 jours, ou immédiatement en cas de fuite) : ajouter le nouveau jeton **à côté** de l'ancien, `secrets-k8s.sh otel` ; la mise à jour du Secret monté arrive dans le pod en une à deux minutes (période de synchronisation du kubelet), puis l'extension relit le fichier ; l'émetteur bascule ; retirer l'ancien, relancer `secrets-k8s.sh`. Fenêtre d'acceptation de l'ancien jeton après révocation : le temps de propagation du Secret, quelques minutes au plus.
- Contrôle : `lab/bin/check 23 16` vérifie le refus sans jeton et avec un jeton inconnu.

## Rétention et dimensionnement de Tempo

| Mesure | Valeur |
|---|---|
| Octets reçus par Tempo (`sum(increase(tempo_distributor_bytes_received_total[1d]))`) | 2,1 Go/jour (après échantillonnage en queue) |
| Taille du compartiment après 5 jours (`radosgw-admin bucket stats --bucket tempo-k8s-par1`) | 7,4 Go, soit ≈ 1,5 Go/jour une fois compressé et compacté |
| Rétention | 14 jours (`tempo.retention: 336h` → `backend_worker.compaction.block_retention`) |
| Taille attendue à 14 jours | ≈ 21 Go, marge × 2 pour les incidents (erreurs et lentes gardées à 100 %) : **quota RGW de 50 Go** sur l'utilisateur `tempo` |
| Limites d'ingestion | `rate_limit_bytes` 15 Mo/s, `burst_size_bytes` 20 Mo, `max_traces_per_user` 20 000, `max_bytes_per_trace` 5 Mo |
| Ressources | Tempo : 500 m / 2 Gio demandés, 3 Gio max ; volume `ceph-rbd` de 10 Gio (WAL, live-store, metrics-generator) occupé à 2,3 Gio : pas d’agrandissement |
| Pyroscope | ≈ 300 Mo/jour, 14 jours, quota 10 Go |

Règle de pouce : un lot de la passerelle (`send_batch_max_size: 4096` spans) pèse moins de 4 Mo : il reste sous `burst_size_bytes`. Une requête plus grosse que la rafale ne peut **jamais** être acceptée.

## Flux de l'espace `traces` (entrées)

| Vers | Depuis | Port |
|---|---|---|
| `otel-agent` | pods de `mediagenda-*`, `medidoc-*`, `wb-essais` | 4317, 4318 |
| `otel-passerelle` | `otel-agent`, `otel-passerelle` (renvoi par `loadbalancing`) | 4317, 4318 |
| `otel-passerelle` | 10.10.0.0/16 par 10.10.41.63 | 14317, 14318 |
| `tempo` | `otel-passerelle` | 4317 |
| `tempo`, `pyroscope` | Grafana, Prometheus (`supervision`) | 3200, 4040 |
| `pyroscope` | MédiAgenda (SDK), Alloy (`journaux`) | 4040 |
| collectors | Prometheus | 8888 |

Sorties (non filtrées à ce stade, à fermer au M26) : Tempo et Pyroscope → RGW 10.10.30.200:443 par `eth1` ; Tempo → Prometheus 9090 (écriture distante) ; collectors → API Kubernetes (`k8sattributes`, `loadbalancing` résolveur `k8s`).

## Ce qui reste ouvert

- Flux internes en clair (agents → passerelle → Tempo) : à chiffrer (TLS mutuel) quand le maillage ou les identités de charge arriveront (M24-M26).
- Jetons statiques : à remplacer par OIDC (Keycloak, M24) pour les émetteurs qui le permettent.
- Un émetteur légitime peut encore envoyer des données de santé dans un attribut : le masquage de M23-E10 reste la dernière barrière, côté passerelle.
