// plateforme/portail — packages/backend/src/instrumentation.js (M28-E16, PLAT-2916)
// Tutoriel « Setup OpenTelemetry » de Backstage : le SDK Node d'OpenTelemetry est démarré AVANT
// le backend (option --require du Dockerfile), avec un exportateur Prometheus (port 9464, /metrics).
// Pas d'exportateur de traces pour l'instant : à brancher sur otel-passerelle (espace traces, OTLP
// HTTP 4318, M23) quand on voudra suivre une requête du portail vers GitLab.
// Dépendances (packages/backend) : @opentelemetry/sdk-node, @opentelemetry/auto-instrumentations-node,
// @opentelemetry/exporter-prometheus — versions épinglées par yarn.lock.

// Une seule fois : le backend lance des threads de travail qui rechargeraient ce fichier.
const { isMainThread } = require('node:worker_threads');

if (isMainThread) {
  const { NodeSDK } = require('@opentelemetry/sdk-node');
  const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
  const { PrometheusExporter } = require('@opentelemetry/exporter-prometheus');

  // Port et chemin par défaut de l'exportateur : 9464, /metrics (exposés par le chart : extraPorts).
  const prometheus = new PrometheusExporter();

  const sdk = new NodeSDK({
    metricReader: prometheus,
    instrumentations: [
      getNodeAutoInstrumentations({
        // Le système de fichiers produit des spans à chaque lecture : inutile et coûteux ici.
        '@opentelemetry/instrumentation-fs': { enabled: false },
      }),
    ],
  });
  sdk.start();
}
