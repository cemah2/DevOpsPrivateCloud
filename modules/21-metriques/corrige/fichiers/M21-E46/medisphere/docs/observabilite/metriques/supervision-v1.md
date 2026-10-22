# Supervision MédiSphère v1 (`metriques-v1`)

> Fiche de livraison du module 21 (PLAT-2246), à jour au <DATE>. Elle dit ce que la supervision couvre, comment, ce qu'elle ne couvre pas, et ce que les modules suivants trouveront. Les détails sont dans les documents cités ; ne recopie ici ni secret ni valeur de configuration sensible.

## Architecture

| Brique | Où | Rôle | Référence |
|---|---|---|---|
| kube-prometheus-stack 92.x | Application Argo CD `kube-prometheus-stack`, espace `supervision` | Prometheus `kps` (2 réplicas, 15 j, `ceph-rbd`), Alertmanager `kps`, Grafana 13.2, kube-state-metrics, node-exporter | ADR-0210 |
| Thanos 0.42 | `plateforme/observabilite/thanos/` | Query (10.10.41.60, vue globale), Store Gateway, Compactor ; compartiment `thanos-k8s-par1` (30 j brut, 180 j à 5 min, 2 ans à 1 h) | RB-214, RB-219 |
| Configuration | `plateforme/observabilite` (Application `observabilite`) | règles, ScrapeConfig, routes, tableaux, SLO, tests en CI | README du dépôt |
| Applications | dépôts `…/deploiement`, composant `components/supervision` | ServiceMonitor, PodMonitor, règles d'équipe | RB-217 |
| VMs | rôle `node_exporter` (TLS step-ca), ScrapeConfig `vms` générée depuis NetBox | toutes les VMs du socle et des environnements | M21-E08 |
| Témoin | `mon01` (rôle `supervision_temoin`) | Prometheus 3.13 LTS, Alertmanager, blackbox, pve-exporter ; *dead man's switch* ; relais des alertes de transport | RB-215, RB-218 |
| SLO | Pyrra 0.10 | `mediagenda-disponibilite`, `mediagenda-latence`, `medidoc-disponibilite` | politique-budget-erreur.md |

## Ce qui est couvert

Pour chaque domaine : cibles (jobs), alertes principales (nom, gravité, destinataire), tableau de référence, runbook.
- Kubernetes (plan de contrôle, etcd, kubelet, Cilium, CoreDNS) : …
- Socle (VMs, HAProxy, PowerDNS, GitLab, Harbor, Ceph, Proxmox, PBS) : …
- Applications (MédiAgenda dev/recette/prod, MédiDoc) : …
- Supervision elle-même (cibles disparues, règles non chargées, transport des alertes, Thanos, cardinalité, témoin) : …

## Ce qui n'est pas couvert (limites assumées)

- Un seul hyperviseur, une seule salle : si `pve01` tombe, le cluster **et** le témoin tombent ; seul un service externe le verrait (non retenu : lab hors ligne).
- Le témoin partage Mailpit (`mon01`) avec la messagerie du lab : une panne de `mon01` coupe le témoin et ses courriels ; le cluster le détecte (sonde réciproque) mais ne peut prévenir que par… Mailpit.
- Pas de SSO (comptes locaux de Grafana) : M24 ; secrets hors Git par `secrets-k8s.sh` : External Secrets au M25.
- Pas de journaux ni de traces : M22 (Loki, `plateforme/observabilite/loki/`, `alloy/`), M23 (OpenTelemetry, Tempo ; c'est le M23 qui active `enableRemoteWriteReceiver` pour le *metrics-generator*).
- Alertes par courriel seulement (pas de SMS, pas de téléphone) : l'astreinte lit ses courriels ; escalade humaine (politique d'alerte).

## Ce que les modules suivants trouvent

- Alertmanager : récepteurs `plateforme-mail`, `astreinte-mail`, `mediagenda-mail`, `medidoc-mail`, routage par `equipe` et `gravite`, essais de routage et d'inhibition en CI.
- Grafana : sources par le code, dossiers par équipe, tableaux *as code*, compte de service `wb-checks`.
- RGW : un utilisateur par composant (`thanos` ; `loki` et `tempo` à créer).
- Pour ajouter une brique : un ServiceMonitor étiqueté `medisphere.internal/supervision: "oui"`, une alerte de disparition, un runbook.

## Preuves de la recette

- `lab/bin/check 21 46` vert le <DATE>.
- Démonstrations : coupure de l'Alertmanager du cluster → courriel du témoin en N min ; canary de MédiAgenda en recette interrompu par l'analyse Prometheus ; inventaire du compartiment.
