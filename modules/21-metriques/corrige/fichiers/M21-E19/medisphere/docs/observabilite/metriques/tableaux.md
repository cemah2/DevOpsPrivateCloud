# Tableaux de bord de référence (M21-E19, PLAT-2219)

Cinq tableaux, construits de la même façon : une ligne de synthèse lisible en deux secondes, puis
une section par lettre de la méthode. Ils vivent dans `plateforme/observabilite/tableaux/`
(provisionnés, non modifiables dans Grafana), utilisent la variable `${datasource}` et, pour les
applications, les séries enregistrées d'E14. Chacun pointe vers son runbook.

| Tableau (UID) | Méthode | Ce qu'il montre | Ce qu'il ne montre pas |
|---|---|---|---|
| `plateforme-use-noeuds` | USE | CPU, mémoire, disques (utilisation) ; charge par cœur, PSI, échange (saturation) ; erreurs réseau, systèmes de fichiers en lecture seule, cibles injoignables (erreurs) — nœuds du cluster (`job=node-exporter`) ou VMs (`job=vms`) | les conteneurs (tableaux du chart), `pve01` et `pbs01` (job `hyperviseurs`, fédéré), le réseau du VLAN 31 |
| `plateforme-use-ceph` | USE | capacité de la grappe et des pools, opérations (utilisation) ; latence des OSD, PG non actifs (saturation) ; santé, OSD hors service (erreurs) | les disques sous-jacents (node_exporter des nœuds Ceph), le RGW vu des clients |
| `mediagenda-red` | RED | débit total et par route ; part des 5xx et codes ; centiles p50/p95/p99 et p95 par route — par environnement | les ressources des pods (USE des nœuds), l'expérience vue de l'extérieur (sondes du témoin), les dépendances (PostgreSQL : `cnpg_*`, Valkey) |
| `medidoc-red` | RED | même construction pour MédiDoc | le stockage objet (RGW) qui porte les documents |
| `plateforme-red-passerelle` | RED | requêtes, octets (débit) ; classes de réponses, paquets refusés par Hubble (erreurs) ; temps amont et total au 95e centile (durée) — Envoy de Cilium | les noms d'hôtes (les statistiques d'Envoy sont par écouteur et par cluster amont), le chemin bordure → répartiteurs |

**Lecture.** USE pour une **ressource** (« ce nœud est-il à bout ? »), RED pour un **service**
(« les utilisateurs sont-ils bien servis ? »). En astreinte, on part du RED du service touché, puis
on descend vers l'USE des ressources qu'il utilise.

**Limites connues.** Les séries d'Envoy de la passerelle suivent le schéma de statistiques
d'Envoy : leurs noms et étiquettes sont à revérifier à chaque montée de version de Cilium. Les
tableaux s'ouvrent en moins de 3 secondes sur 24 heures parce qu'ils lisent des séries
enregistrées ; sur 30 jours, utiliser Thanos (palier 3).
