# plateforme/observabilite

Configuration de la supervision de MédiSphère (module 21, puis 22 et 23). Relu en MR, appliqué par Argo CD.

| Dossier | Contenu | Consommé par |
|---|---|---|
| `kps/` | `values.yaml` de kube-prometheus-stack (Prometheus, Alertmanager, Grafana) | Application `kube-prometheus-stack` (source `$values`) |
| `regles/` | `PrometheusRule` d'enregistrement et d'alerte de la plateforme | Application `observabilite` |
| `scrape/` | `ScrapeConfig` (VMs, exportateurs hors cluster), `Probe` | Application `observabilite` |
| `alertmanager/` | gabarits et essais de routage (`amtool config routes test`) | CI |
| `tableaux/` | tableaux de bord JSON (M21-E17) | Application `observabilite` |
| `requetes/` | requêtes PromQL de travail et d'exploration (`EXX.promql`) | CI (syntaxe), checks du workbook |
| `tests/` | tests unitaires de règles (`promtool test rules`, M21-E15) | CI |
| `outils/` | scripts de la CI | CI |

Règles :

- tout objet appliqué porte `medisphere.internal/supervision: "oui"` (posé par la `kustomization.yaml` racine) : c'est le sélecteur de Prometheus ;
- les **ServiceMonitor et PodMonitor des applications** ne sont pas ici : ils vivent dans les dépôts `…/deploiement` des équipes (`components/supervision`) ;
- aucun secret dans ce dépôt (Secrets créés par `plateforme/k8s/outils/secrets-k8s.sh`).

Format des fichiers `requetes/*.promql` : une requête par bloc, blocs séparés par une ligne vide, lignes de commentaire commençant par `#` (la question à laquelle la requête répond). Vérification locale : `outils/verifier-promql.sh requetes/*.promql`.
