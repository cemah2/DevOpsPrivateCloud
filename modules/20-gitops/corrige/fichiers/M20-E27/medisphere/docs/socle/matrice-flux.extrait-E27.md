<!-- docs/socle/matrice-flux.md : ligne AJOUTÉE en M20-E27 (PLAT-2127). -->
| `git01` (10.10.20.12) | `gw-par1` (10.10.41.10) | TCP 443 | VLAN 20 → plage des services (annoncée en BGP par k8s-par1) | webhooks GitLab vers Argo CD (`argocd.apps.par1.medisphere.internal/api/webhook`) | `gw01`, `gw02` (`pare_feu.yml`) ; GitLab : liste d'autorisation des requêtes locales | M20-E27 |
