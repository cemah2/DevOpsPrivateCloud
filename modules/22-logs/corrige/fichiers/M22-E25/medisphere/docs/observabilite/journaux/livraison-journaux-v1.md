# Livraison « journaux-v1 » — note de passage de relais

> Modèle de M22-E25. À compléter avec **tes** valeurs (versions exactes, volumes, dates) et à publier avec l'étiquette `journaux-v1` de `plateforme/medisphere`.

| | |
|---|---|
| Date de livraison | AAAA-MM-JJ |
| Recette | revue du comité (Claire Morel, Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit) |
| Contrôle global | `lab/bin/check 22 25` vert le AAAA-MM-JJ à HH:MM |
| Décision | ADR-0220 |

## 1. Ce qui est livré

| Brique | Version | Où | Piloté par |
|---|---|---|---|
| Loki | 3.7.x (chart 19.0.x) | `journaux`, `loki-0`, compartiment `loki-k8s-par1`, 10.10.41.62:3100 | Argo CD (`loki`), `plateforme/observabilite/loki/` |
| Alloy (cluster) | 1.21.x (chart 1.14.x) | DaemonSet `alloy` (`journaux`) | Argo CD (`alloy`), `plateforme/observabilite/alloy/` |
| Alloy (VMs) | 1.21.x | toutes les VMs du socle | rôle Ansible `alloy`, playbook `journaux-vms.yml` |
| Sources Grafana | — | organisation principale (3 sources), organisation Sécurité (audit) | `grafana/sources-loki.yaml`, OpenTofu `observabilite-grafana` |
| Alertes | — | *ruler* de Loki (3 locataires), PrometheusRule `loki-capacite` | `loki/regles/`, `regles/` |

## 2. Mesures de référence (à la livraison)

| Mesure | Valeur |
|---|---|
| Volume reçu par jour, par locataire | plateforme … Mo, mediagenda … Mo, medidoc … Mo, audit … Mo |
| Flux actifs par locataire | … |
| Mémoire / CPU de `loki-0` (moyenne, pic) | … |
| Mémoire d'Alloy par nœud | … |
| Taille du compartiment (et projection à l'équilibre des rétentions) | … |
| Temps de la requête de référence sur 7 jours (froid / chaud) | … |
| Délai de détection « Alloy absent d'un nœud » (démonstration de Nadia) | … |

## 3. Ce que le M23 (traces) trouve

- Les journaux de MédiAgenda portent `request_id` en **métadonnée structurée** : le M23 y ajoute `trace_id` (même mécanisme, pas d'étiquette) pour relier Loki et Tempo (champ dérivé de la source Grafana).
- Alloy est en place sur chaque nœud : le M23 peut lui ajouter une réception OTLP (ou déployer le Collector OpenTelemetry décidé par l'ADR-0230), sans toucher à la collecte des journaux.
- La liste fermée d'étiquettes s'applique aussi aux journaux reçus en OTLP (`otlp_config` de Loki, attributs de ressource indexés à réduire).

## 4. Ce qui reste à traiter (limites acceptées)

| Limite | Pourquoi acceptée | Traité par |
|---|---|---|
| En-tête `X-Scope-OrgID` non authentifié (MGMT, Grafana) | cercle réduit, politiques réseau, écriture seule depuis les VMs | M24 (passerelle authentifiante, SSO de Grafana) |
| HTTP en clair vers 10.10.41.62 | journaux masqués, réseaux du lab | M24 (TLS et identité des agents) |
| Un seul pod Loki | volume du lab ; Alloy réessaie quelques minutes | révision de l'ADR-0220 si l'astreinte le demande |
| Pas de copie hors site (audit d'un an compris) | versionnage contre l'erreur humaine, réplication de `ceph-par1` | F5 (PRA) |
| Droits d'`exec` dans les espaces d'équipe non contrôlés à l'admission (INC-4923) | correction faite, alerte en place | M26 (durcissement) |

## 5. Où trouver quoi

Politique : `politique-journaux.md` ; architecture et choix : ADR-0220, `loki.md`, `sous-le-capot.md` ; exploitation : RB-220 (chercher), RB-221 (effacement), RB-222 (journaux manquants), RB-223 (écritures refusées), RB-224 (requêtes) ; mesures : `performance.md` ; comparatifs : `comparatif-collecteurs.md`, `comparatif-opensearch.md` ; incidents : `docs/kubernetes/post-mortems/*INC-4923*`.
