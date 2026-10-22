# M25-E13 — Inventaire des Secrets hors Git (modèle ; AUCUNE valeur)

Sources : `kubectl get secrets -A -l medisphere.internal/source=ansible-vault -o custom-columns=…` (noms et clés seulement : `-o json | jq '.items[] | {ns: .metadata.namespace, nom: .metadata.name, cles: (.data | keys)}'`), registre des secrets (M16-E23, M17-E15), inventaire E02.

| Espace | Secret | Clés | Consommateur (comment) | À chaud ? | Chemin KV | Migré le |
|---|---|---|---|---|---|---|
| argocd | repo-creds-plateforme, -mediagenda, -medidoc, -formation | type, url, username, password | repo-server (lu à chaque accès au dépôt) | oui | kv/plateforme/argocd/depot-<groupe> | AAAA-MM-JJ |
| argocd | depot-harbor-charts | name, type, url, enableOCI, username, password | repo-server | oui | kv/plateforme/argocd/depot-harbor-charts | |
| argocd | argocd-webhook-gitlab | secret | argocd-server (référence `$argocd-webhook-gitlab:secret`) | oui | kv/plateforme/argocd/webhook-gitlab | |
| argocd | argocd-sauvegardes-s3 | AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY | CronJob argocd-export (variables, à chaque exécution) | oui | kv/plateforme/argocd/sauvegardes-s3 | |
| argocd | argocd-oidc | clientSecret | argocd-server (référence `$argocd-oidc:clientSecret`) | oui | kv/plateforme/argocd/oidc | |
| supervision | grafana-admin | admin-user, admin-password | Grafana, à la création de la base seulement | n/a | kv/plateforme/grafana/admin | |
| supervision | grafana-oidc | GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET | Grafana (variable, au démarrage) | non | kv/plateforme/grafana/oidc | |
| supervision | thanos-objstore | objstore.yml | sidecar, Store, Compactor (fichier, au démarrage) | non | kv/plateforme/thanos/objstore | |
| journaux | loki-objstore | (clés S3) | Loki (variables) | non | kv/plateforme/loki/objstore | |
| traces | tempo-objstore, pyroscope-objstore | (clés S3) | Tempo, Pyroscope (variables) | non | kv/plateforme/tempo/objstore, …/pyroscope/objstore | |
| traces | otlp-jetons | jetons | passerelle OTLP (fichier monté, relu) | oui | kv/plateforme/otel/jetons | |
| gitlab-runner | gitlab-runner, gitlab-runner-protege-jeton | runner-token, runner-registration-token | gestionnaire du runner (au démarrage) | non | kv/plateforme/gitlab-runner/jeton, …/protege-jeton | |
| gitlab-runner | ci-cache-s3 | accesskey, secretkey | gestionnaire (URL présignées) | non | kv/plateforme/gitlab-runner/cache-s3 | |
| gitlab-agent | gitlab-agent-jeton | token | agentk (au démarrage) | non | kv/plateforme/gitlab-agent/jeton | |
| oauth2-proxy | oauth2-proxy-oidc | client-id, client-secret, cookie-secret | OAuth2 Proxy (variables) | non | kv/plateforme/oauth2-proxy/oidc | |
| mediagenda-dev/-recette/-prod | harbor-pull | .dockerconfigjson | kubelet (tirage d'image) | oui | kv/mediagenda/<env>/harbor-pull | |
| medidoc-dev/-recette | harbor-pull, medidoc-s3 | .dockerconfigjson ; AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY | kubelet ; MédiDoc (variables) | oui ; non | kv/medidoc/<env>/harbor-pull, …/s3 | |
| gitlab-runner | gitlab-runner-certs | (racine publique) | gestionnaire | — | **reste** (amorçage) | — |
| ci-jobs-protege | cosign-medisphere | cosign.key, cosign.password | jobs de signature | — | **E20** (transit) | — |
| velero, cnpg-system, cert-manager, external-dns, ceph-csi | (scripts du M15-M16 : TSIG, S3, cephx) | — | — | — | **mini-projet** (même méthode ; base Helmfile) | — |
