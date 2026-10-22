# Accès à la supervision de `k8s-par1`

| Service | Adresse | Qui | Authentification |
|---|---|---|---|
| Prometheus (API, interface) | `http://prometheus.apps.par1.medisphere.internal:9090` (10.10.41.60) | MGMT (10.10.10.0/24), `mon01` ; dans le cluster : espace `supervision` | aucune : filtrage réseau (CiliumNetworkPolicy `prometheus-entree`) |
| Alertmanager (API, interface) | `http://alertmanager.apps.par1.medisphere.internal:9093` (10.10.41.61) | MGMT, `mon01` ; espace `supervision` | aucune : filtrage réseau (`alertmanager-entree`) ; silences signés par `author` (amtool) |
| Grafana | `https://grafana.apps.par1.medisphere.internal` (Gateway `gw-par1`) | tout le lab (réseaux autorisés par la bordure) | comptes nominatifs (SSO au M24) |

## Comptes de Grafana

- `admin` : **bris de glace** seulement. Mot de passe dans le Secret `supervision/grafana-admin`, source Ansible Vault `critique` (`plateforme/k8s`, `secrets/grafana.yml`). Chaque usage est noté dans `docs/kubernetes/journal/` (date, motif, durée).
- Comptes nominatifs : l'équipe Plateforme (Admin de l'organisation) ; les personnages et les équipes `plateforme`, `mediagenda`, `medidoc` par OpenTofu (M21-E17).
- Compte de service `wb-checks` : rôle **Viewer**, jeton de 90 jours dans `~/.config/workbook/grafana-checks.token` (600) sur `adm01` ; rotation par `grafana-jeton-checks.sh`, échéance au registre des secrets ; l'ancien jeton est révoqué après la rotation.

## Ce qui n'est pas permis

- Exposer Prometheus ou Alertmanager par la Gateway, ou ouvrir leur politique d'entrée à d'autres réseaux, sans authentification devant (mandataire OAuth2, M24).
- Créer des tableaux de bord « de production » à la main : ils se perdent avec le volume de Grafana ; les tableaux de référence sont *as code* (M21-E17).
