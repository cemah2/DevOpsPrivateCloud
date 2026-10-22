<!-- À INTÉGRER dans docs/kubernetes/reseau/matrice-flux-cluster.md (plateforme/medisphere) — M22-E02 -->

| Source | Destination | Port | Motif | Politique | Réf. |
|---|---|---|---|---|---|
| `journaux/alloy` (DaemonSet) | `journaux/loki` | TCP 3100 | écriture des journaux du cluster | CNP `journaux/loki-entree` | M22-E02/E03 |
| `supervision/grafana` | `journaux/loki` | TCP 3100 | lecture (sources par locataire) | CNP `loki-entree` | M22-E02 |
| `supervision/prometheus` | `journaux/loki` | TCP 3100, GET `/metrics` | métriques de Loki | CNP `loki-entree` (règle HTTP) | M22-E02 |
| `journaux/loki` | `journaux/loki` | TCP 7946, 9095 | memberlist, gRPC interne | CNP `loki-entree` | M22-E02 |
| MGMT 10.10.10.0/24 | `journaux/loki` par 10.10.41.62 | TCP 3100 | vérifications, `logcli`, agent de `adm01` | CNP `loki-entree` (`fromCIDR`) | M22-E02 |
| VLAN 20, VLAN 70, `gw01`/`gw02` | `journaux/loki` par 10.10.41.62 | TCP 3100, POST `/loki/api/v1/push` | agents Alloy des VMs | CNP `loki-entree` (`fromCIDR` + règle HTTP) | M22-E05 |
| `journaux/loki` | RGW 10.10.30.200 (par `eth1` des travailleurs) | TCP 443 | chunks et index | aucune politique de sortie (flux du M16) | M22-E02 |
