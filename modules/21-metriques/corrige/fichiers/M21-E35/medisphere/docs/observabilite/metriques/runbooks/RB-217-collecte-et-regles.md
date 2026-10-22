# RB-217 — Une cible, une règle ou un tableau a disparu

| | |
|---|---|
| **Alertes liées** | `CibleDisparue`, `ApplicationCibleEnEchec`, `CibleInjoignable` (VMs), alertes de règles non évaluées |
| **Gravité** | critique pour une disparition (on ne voit plus rien) ; avertissement pour une cible en échec |
| **Propriétaire** | Équipe Plateforme |
| **Dernière revue** | 2026-10-27 (pannes M21-E35, E37, E41) |

Principe : une donnée de supervision traverse une **chaîne**. Une absence de donnée n'est presque jamais signalée par une erreur : il faut remonter la chaîne maillon par maillon et **prouver** chaque maillon avec la commande indiquée. Ne corrige rien à la main sur un objet géré par Argo CD : la correction passe par une MR.

Variables utilisées ci-dessous (sur `adm01`) :

```
P=http://prometheus.apps.par1.medisphere.internal:9090      # vue globale (Thanos Query)
kubectl -n supervision port-forward pod/prometheus-kps-0 9091:9090 &   # un Prometheus en direct (cibles écartées, TSDB Status)
```

## Une cible a disparu ou est muette

1. **Disparue ou en échec ?** `count by (job, namespace) (up)` maintenant et `offset 1h`. Plus de série : *disparue* (étape 2). Série à 0 : *en échec* (étape 3).
2. **Disparue — la découverte.**
   - ServiceMonitor/PodMonitor retenu ? `kubectl -n supervision get prometheus kps -o jsonpath='{.spec.serviceMonitorSelector}'` contre `kubectl -n <espace> get servicemonitor --show-labels` ; espace retenu (`serviceMonitorNamespaceSelector`) contre `kubectl get ns <espace> --show-labels`. Un objet non retenu n'apparaît **nulle part**.
   - Découvert mais écarté ? `curl -s localhost:9091/api/v1/targets?state=dropped | jq '.data.droppedTargets[] | select(.discoveredLabels.__meta_kubernetes_namespace == "<espace>") | .discoveredLabels'` : port nommé (`__meta_kubernetes_endpoint_port_name`) ou étiquettes du Service qui ne correspondent plus.
   - ScrapeConfig (`vms`, exportateurs natifs) : cibles générées par `supervision-cibles.yml` depuis NetBox (M21-E08) ; comparer avec NetBox.
   - Origine : `git log -p` du dépôt concerné (`mediagenda/deploiement` `components/supervision`, `plateforme/observabilite` `scrape/`).
3. **En échec — l'erreur exacte.** `curl -s $P/api/v1/targets | jq -r '.data.activeTargets[] | select(.health != "up") | "\(.labels.job) \(.scrapeUrl) \(.lastError)"'`.
   - `context deadline exceeded` sans réponse → réseau. Cluster : `hubble observe --namespace <espace> --verdict DROPPED`, puis `kubectl get cnp,netpol -n <espace>` (une politique **non versionnée** est suspecte). VM : `sudo nft list ruleset` et compteurs (`counter packets`) sur la VM, matrice des flux (`K8S_TRAV → 9100`).
   - `x509` → certificat : `openssl s_client -connect <vm>:9100 -CAfile /usr/local/share/ca-certificates/medisphere-root-ca.crt` **depuis un nœud** ; émetteur, dates ; rôle `node_exporter` en `--check --diff`.
   - `connection refused` → service arrêté ou port changé.
   - Toujours tester **depuis le chemin de Prometheus** (un pod de `supervision`, un nœud), jamais seulement depuis `adm01`.
4. **Corriger** : MR (ServiceMonitor, ScrapeConfig, politique de la plateforme), ou rejeu du rôle Ansible ; retirer ce qui n'a rien à faire là après avoir retrouvé son auteur et son intention.
5. **Vérifier** : cibles `up == 1`, trou dans les courbes (il ne se comble pas) consigné.
6. **Prévenir** : `CibleDisparue` couvre-t-elle ce job ? Sinon, l'ajouter (une expression par job attendu).

## Un tableau est vide

1. Panneau → **Inspect → Query** : requête **interpolée**, source, réponse brute.
2. Variable vide (`=~""`) ? *Dashboard settings → Variables* : aperçu des valeurs ; `curl -s "$P/api/v1/label/<étiquette>/values" -G --data-urlencode 'match[]=<sélecteur>'`.
3. Source introuvable ? `curl -s https://grafana.apps.par1.medisphere.internal/api/frontend/settings -H "Authorization: Bearer $(cat ~/.config/workbook/grafana-checks.token)" | jq '.datasources'` (UID, défaut) ; URL : `kubectl -n supervision get cm -l grafana_datasource=1 -o yaml | grep url` (doit viser Thanos Query).
4. Règle d'enregistrement absente ? *Status → Rules* ; `count(<règle>)`.
5. Données absentes sur la période ? Requête sur 30 j : s'arrête à 15 j → la requête ne passe pas par Thanos, ou le Store ne sert pas (RB-219).
6. Corriger par MR dans `tableaux/`, `regles/` ou `kps/values.yaml` ; jamais dans l'interface. Un UID (tableau, source) et un nom de règle d'enregistrement sont des **identifiants stables** : on ne les renomme pas sans période de transition.
7. Prévenir : `outils/verifier-tableaux.sh` en CI (règles citées existantes, variables, sources par variable).

## Une règle ne se charge pas

1. L'objet existe ? `kubectl -n <espace> get prometheusrules --show-labels`.
2. Argo CD l'a synchronisé ? `argocd app get <app>` : message de la dernière opération ; un refus du webhook `prometheusrulevalidate.monitoring.coreos.com` contient l'erreur PromQL exacte. Reproduire : `kustomize build overlays/<env> | kubectl apply --dry-run=server -f -`.
3. L'opérateur le retient ? `ruleSelector` contre les étiquettes de l'objet ; `ruleNamespaceSelector` contre les étiquettes de l'espace. Les règles retenues sont dans les ConfigMaps `prometheus-kps-rulefiles-*` de `supervision`.
4. Prometheus l'évalue ? *Status → Rules* (dernière évaluation, erreur), `prometheus_rule_evaluation_failures_total`.
5. Corriger par MR dans le dépôt qui porte la règle ; l'étiquette d'un espace se corrige dans `plateforme/k8s`.
6. Prévenir : `promtool check rules` sur les règles **rendues** dans le pipeline de chaque dépôt qui en contient (`outils/extraire-regles-rendues.sh` puis `promtool check rules`, M21-E41).
