<!-- À INTÉGRER dans docs/socle/matrice-flux.md (plateforme/medisphere), section « Observabilité » — M22-E05 -->

| Source | Destination | Proto/port | Motif | Où c'est appliqué | Réf. |
|---|---|---|---|---|---|
| VLAN 20 INFRA (10.10.20.0/24) | Loki 10.10.41.62 | TCP 3100 | agents Alloy des VMs : journal systemd → Loki (locataire `plateforme`) | `gw01`/`gw02` (`pare_feu.yml`, transit `V_INFRA` → `V_K8S`) ; CNP `journaux/loki-entree` (POST `/loki/api/v1/push` seulement) | M22-E05 |
| VLAN 70 DMZ (10.10.70.0/24) | Loki 10.10.41.62 | TCP 3100 | agents Alloy de `lb01`/`lb02` | idem (transit `V_DMZ` → `V_K8S`) ; CNP `loki-entree` | M22-E05 |
| `gw01`/`gw02` (10.10.40.2/.3) | Loki 10.10.41.62 | TCP 3100 | agents Alloy des passerelles (trafic propre, chaîne `output`) | CNP `loki-entree` (deux /32) | M22-E05 |
| MGMT 10.10.10.0/24 | Loki 10.10.41.62 | TCP 3100 | `adm01` : agent Alloy (écriture), vérifications `lab/bin/check 22 …` et `logcli` (lecture) | existant côté bordure (MGMT joint tout) ; CNP `loki-entree` (tout le port) | M22-E02, E04, E05 |
