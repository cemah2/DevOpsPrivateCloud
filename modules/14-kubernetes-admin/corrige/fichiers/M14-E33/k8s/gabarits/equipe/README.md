# Gabarit d'accueil d'une équipe (plateforme/k8s, M14-E33)

```
admin@adm01:~/src/k8s$ outils/nouvelle-equipe.sh <EQUIPE> <ENV>
```

Génère `espaces/<EQUIPE>-<ENV>/` (`00-namespace.yaml` étiqueté pour Pod Security et l'admission, `10-quota.yaml`, `20-limites.yaml`, `30-comptes-service.yaml`) et `rbac/40-<EQUIPE>-<ENV>.yaml` (liaisons du groupe `medisphere:<EQUIPE>-devs` aux ClusterRoles `medisphere-developpeur` et `medisphere-secrets-edition` de M14-E11). À ajuster dans la MR : l'enveloppe (valeur accordée par écrit dans le ticket), le responsable. Le reste ne se modifie pas. Procédure : `docs/kubernetes/accueil-equipe.md` de `plateforme/medisphere`.
