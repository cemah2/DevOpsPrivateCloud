# M25-E13 — Comparaison avant / après (modèle ; empreintes tronquées, AUCUNE valeur)

Méthode : `outils/secret-vers-openbao.sh comparer <espace> <secret> <chemin>` après la recopie (empreinte SHA-256 de chaque clé, Secret contre coffre), puis, après la synchronisation d'Argo CD, `outils/secrets-k8s.sh verifier <composant>` (Vault Ansible contre Secret : il lit toujours l'ancienne source) ; enfin l'adoption :

```
admin@adm01:~$ kubectl -n supervision get secret grafana-admin -o json \
    | jq '{proprietaire: .metadata.ownerReferences[0].kind, source: .metadata.labels["medisphere.internal/source"]}'
admin@adm01:~$ kubectl -n supervision get pods -l app.kubernetes.io/name=grafana -o jsonpath='{.items[*].metadata.uid}'   # avant / après : identiques
```

| Secret | Empreintes (recopie) | `verifier` après synchro | Propriétaire | Pods redémarrés ? |
|---|---|---|---|---|
| supervision/grafana-admin | [OK] admin-user 8c69…, [OK] admin-password 7e2b… | [OK] identique au Vault | ExternalSecret | non (UID identiques) |
| argocd/repo-creds-plateforme | [OK] ×4 | [OK] | ExternalSecret | non |
| … | | | | |
