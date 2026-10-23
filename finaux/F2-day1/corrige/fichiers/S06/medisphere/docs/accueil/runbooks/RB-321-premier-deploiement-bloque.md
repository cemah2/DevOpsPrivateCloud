# RB-321 — Un déploiement d'équipe « synchronisé » qui ne démarre pas

| | |
|---|---|
| Déclencheur | une équipe signale qu'une nouvelle version n'arrive pas : Argo CD affiche `Synced` (ou `Progressing` qui dure), ou `OutOfSync` avec une synchronisation en échec |
| Exécutant | la Plateforme (lecture), l'équipe (correction par MR dans son dépôt) |
| Durée | 15 à 45 min |
| Références | F2-S06, ADR-0320, M20 (Argo CD), M25 (ESO), M26 (Kyverno), M28 (Capsule) |

Variables : `NS=<equipe>-<env>`, `D=<deployment>`.

## 1. Où en est le déploiement ?

```
admin@adm01:~$ kubectl -n $NS get deploy $D -o wide
admin@adm01:~$ kubectl -n $NS rollout status deploy/$D --timeout=10s
admin@adm01:~$ kubectl -n $NS get rs -l app.kubernetes.io/instance=$D -o wide
```

```
admin@adm01:~$ argocd app get <application>            # Sync Status ; Phase et Message de la dernière opération
```

**Opération `Failed`** (`OutOfSync`, santé souvent encore `Healthy`) : un objet de Git a été refusé à l'admission. Le message le dit, par exemple `admission webhook "…kyverno…" denied the request: … exiger-signature-medisphere …` : la politique de signature est autogénérée pour les Deployments, une image désignée par **étiquette** (ou non signée) fait refuser le Deployment lui-même. Correction par MR (empreinte `images[].digest` dans l'overlay), puis la synchronisation repart au commit suivant.

« Synchronisé » = Argo CD a écrit ce que dit Git. Les pods, eux, sont créés par le **ReplicaSet** : c'est lui qu'on lit ensuite.

## 2. Le ReplicaSet n'arrive pas à créer ses pods (pods absents)

```
admin@adm01:~$ kubectl -n $NS describe rs <nouveau-rs> | sed -n '/Conditions/,$p'
admin@adm01:~$ kubectl -n $NS get events --field-selector reason=FailedCreate --sort-by=.lastTimestamp | tail
```

| Message | Cause | Correction (par MR) |
|---|---|---|
| `exceeded quota: quota, requested: requests.memory=…, used: …, limited: …` | quota de l'espace dépassé (`kubectl -n $NS describe resourcequota`) | réduire réplicas ou *requests* dans l'overlay ; ou, si le besoin est réel, MR sur `equipes/<equipe>.yaml` (quota, bilan de capacité) |
| `exceeded quota: capsule-…` | budget global du locataire (`kubectl get globalresourcequotas`) | idem, budget |
| `maximum memory usage per Container is …` | `LimitRange` de l'espace | *requests*/*limits* sous le plafond |
| `admission webhook "…kyverno…" denied the request: …` | politique Kyverno sur les pods (sans autogénération) ; pour `exiger-signature-medisphere`, le refus arrive d'abord sur le Deployment (voir § 1) | selon le message ; pour la signature : `images[].digest: sha256:…` de l'image validée, jamais `newTag` |
| `violates PodSecurity "restricted:latest"` | contexte de sécurité incomplet | `securityContext` du pod et du conteneur |
| `forbidden: … priorityclass …` (Capsule) | classe de priorité non autorisée au locataire | classe autorisée, ou MR sur le fichier d'équipe |

Rapports Kyverno de l'espace : `kubectl -n $NS get policyreports -o wide`.

## 3. Les pods existent mais ne démarrent pas

```
admin@adm01:~$ kubectl -n $NS get pods -l app.kubernetes.io/instance=$D
admin@adm01:~$ kubectl -n $NS describe pod <pod> | sed -n '/Events/,$p'
admin@adm01:~$ kubectl -n $NS get externalsecrets
admin@adm01:~$ kubectl -n $NS describe externalsecret <nom> | sed -n '/Status/,$p'
```

| Symptôme | Cause | Correction |
|---|---|---|
| `CreateContainerConfigError` : `secret "…" not found` | le Secret attendu n'est pas créé | lire l'`ExternalSecret` qui doit le produire |
| `ExternalSecret` `SecretSyncedError`, message `permission denied` / `403` | chemin du coffre **hors** de la politique `eso-$NS` (lecture de `kv/<equipe>/<env>/*` seulement) | ranger le secret sous `kv/<equipe>/<env>/…` (l'équipe l'écrit elle-même) ; un secret « commun » se recopie dans chaque environnement, il ne se partage pas |
| `SecretSyncedError`, `secret not found` / `404` | chemin ou propriété absents du coffre | `bao kv get kv/<equipe>/<env>/<secret>` (personne de l'équipe, OIDC) |
| `ImagePullBackOff` | image absente, ou droit de tirage | Harbor ; Secret de tirage de l'espace |
| `CrashLoopBackOff`, `Readiness probe failed` | l'application | journaux (Loki), équipe |

## 4. Après la correction

- La MR fusionnée, Argo CD resynchronise (`dev`, `recette` : automatique ; `prod` : à la main, dans la fenêtre).
- Vérifier : `kubectl -n $NS rollout status deploy/$D`, Application `Synced` et `Healthy`, URL du service.
- Dire à l'équipe la cause et la prévention ; noter l'incident dans `docs/accueil/journal/`.

## Prévention

- CI du dépôt de déploiement : rendre chaque overlay (`kustomize build`), refuser une image sans empreinte, un chemin de secret hors `<equipe>/<env>/`, et une somme `réplicas × requests` au-delà du quota déclaré dans le fichier d'équipe (composant `validation`, politiques Rego, M29).
- Le modèle « Nouveau service » v2 livre déjà des overlays par empreinte et un `ExternalSecret` par environnement.
