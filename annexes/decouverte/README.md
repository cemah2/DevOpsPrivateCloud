# Fiches « découverte »

Outils étudiés sans être déployés dans le lab : chaque fiche dit ce que fait l'outil, comment il se compare à ce que le workbook a retenu, et pourquoi il a été écarté (ou dans quel cas il le serait). Elles se lisent au moment de l'ADR du module d'origine.

| Fiche | En une phrase | Module d'origine |
|---|---|---|
| [`nats.md`](nats.md) | NATS et sa persistance JetStream, messagerie légère comparée à RabbitMQ et à Kafka ; non retenue (ADR-0270). | [M27 — Données et messagerie](../../modules/27-donnees-messaging/README.md) |
| [`crossplane.md`](crossplane.md) | Crossplane 2, plan de contrôle d'infrastructure dans Kubernetes ; rien à piloter dans un cloud privé sans API de services managés (ADR-0280). | [M28 — Plateforme développeurs](../../modules/28-plateforme-dev/README.md) |
| [`tilt-skaffold.md`](tilt-skaffold.md) | Tilt et Skaffold, outils de la boucle de développement interne (reconstruire, déployer, synchroniser en continu) ; non installés (ADR-0280). | [M28 — Plateforme développeurs](../../modules/28-plateforme-dev/README.md) |
| [`litmuschaos.md`](litmuschaos.md) | LitmusChaos 3, plateforme de chaos concurrente de Chaos Mesh ; écartée parce que son ChaosCenter exige MongoDB par un sous-chart Bitnami (ADR-0290). | [M29 — Tests et résilience](../../modules/29-tests-resilience/README.md) |
