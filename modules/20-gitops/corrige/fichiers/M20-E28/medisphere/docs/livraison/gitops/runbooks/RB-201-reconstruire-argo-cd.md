# RB-201 — Reconstruire Argo CD

| | |
|---|---|
| Ticket d'origine | PLAT-2128 (M20-E28) |
| Propriétaire | Équipe Plateforme |
| Durée mesurée | <ex. 41 min> du début de la désinstallation au dernier `Synced` (compte rendu : `docs/livraison/gitops/tests/reconstruction-argo-cd.md`) |
| Dernière répétition | <DATE> |

## 1. Quand reconstruire, et quand ne pas le faire

**Reconstruire** : espace `argocd` détruit ou corrompu (CRD supprimées, `argocd-secret` perdu), montée de version ratée et irréparable, migration vers un autre cluster.

**Ne pas reconstruire** pour : une Application `OutOfSync` ou `Degraded` (RB-200), un dépôt illisible (identifiants, réseau : RB-200 §3), un pod en échec (redémarrage, journaux), une politique RBAC fausse (corriger `policy.csv` et `helmfile apply`). Pendant qu'Argo CD est absent, **les applications continuent de tourner** : rien ne presse au point de sauter une étape.

## 2. Ce qui fait Argo CD, et d'où chaque élément revient

| Élément | Source de reconstruction |
|---|---|
| Release Helmfile `argocd` (valeurs, CRD, politique RBAC `policy.csv`) | `plateforme/k8s` : `helmfile -e par1 -l composant=argocd apply` |
| Espace `argocd` (étiquettes PSA, exposition) | `plateforme/k8s` `espaces/argocd.yaml` : `task espaces` |
| Politiques réseau | `plateforme/k8s` `composants/reseau/politiques/argocd.yaml`, `argocd-sauvegarde.yaml` |
| Identifiants des dépôts (jetons de déploiement), dépôt OCI, cluster `lyo-k3s01`, secret des webhooks, identité S3 des sauvegardes | Vault `critique` `secrets/argocd.yml` : `outils/secrets-k8s.sh appliquer argocd` |
| AppProjects, ApplicationSets, Applications | `plateforme/gitops`, par l'application racine |
| Application racine | `plateforme/gitops` `racine/racine.yaml` (appliquée **une fois** à la main, M20-E06) |
| CronJob de sauvegarde | `plateforme/k8s` `composants/argocd-sauvegarde/` : `task argocd-sauvegarde` |
| **`server.secretkey`** (signature des sessions **et des jetons d'API**) | **nulle part ailleurs que dans l'export** |
| **Mots de passe et jetons des comptes locaux** (`accounts.*` d'`argocd-secret`) | **nulle part ailleurs que dans l'export** |

Sans l'export : un nouveau `server.secretkey` est généré au démarrage, tous les jetons existants (dont `ci-lecture` → `~/.config/workbook/argocd-checks.token`) sont refusés, et les comptes locaux n'ont plus de mot de passe (l'administrateur `admin` est désactivé : il faut le réactiver le temps de les redéfinir, ou passer par `argocd account bcrypt` et le Vault). Avec l'export, `outils/argocd-restaurer-secret.sh` remet ces seules clés.

## 3. Préalables (ne pas commencer sans)

1. Instantané etcd vérifié de moins d'une heure (`outils/etcd-instantane.sh`, RB-141).
2. Sauvegarde Velero des espaces applicatifs (`velero backup create avant-rb201-<date> --include-namespaces 'mediagenda-*','medidoc-*'`), `Completed`.
3. Export d'Argo CD de moins d'une heure (`task argocd-sauvegarde-maintenant`), téléchargé, **déchiffré et relu** sur `adm01` :
   ```
   admin@adm01:~$ install -d -m 700 /dev/shm/rb201
   admin@adm01:~$ ( set -a; . ~/.config/workbook/s3-argocd-sauvegardes.env; set +a
   >   aws s3 cp s3://argocd-sauvegardes/quotidien/<OBJET>.yaml.gpg /dev/shm/rb201/ )
   admin@adm01:~$ cd ~/src/k8s && uv run --project ~/src/ansible ansible-vault view \
   >   --vault-id critique@$HOME/src/ansible/outils/vault-pass-client.sh secrets/argocd-sauvegarde-gpg.cle \
   >   | GNUPGHOME=/dev/shm/rb201/gnupg gpg --batch --import
   admin@adm01:~$ GNUPGHOME=/dev/shm/rb201/gnupg gpg --batch --decrypt --output /dev/shm/rb201/export.yaml /dev/shm/rb201/<OBJET>.yaml.gpg
   admin@adm01:~/src/k8s$ outils/argocd-restaurer-secret.sh /dev/shm/rb201/export.yaml     # essai : liste les clés
   ```
   (`GNUPGHOME` créé en 700 par `gpg` dans `/dev/shm` : la clé privée ne touche jamais le disque.)
4. Relevé des UID et dates de création des Deployments, StatefulSets et pods applicatifs (compte rendu, §« Avant »).
5. `mediagenda-prod` synchronisée à la main (pas d'`automated`) ; aucune synchronisation en cours (`argocd app list`).
6. Une session `kubectl` avec ton kubeconfig personnel : pendant la reconstruction, il n'y a plus d'interface.

## 4. Désinstallation contrôlée

> ⚠️ Ordre impératif. Une Application qui porte `resources-finalizer.argocd.argoproj.io` et qui est supprimée **pendant que le contrôleur tourne** fait supprimer toutes ses ressources. Retour arrière à chaque étape : §6.

4.1. **Arrêter la réconciliation** (plus rien ne réécrit les finaliseurs depuis Git, plus rien ne supprime) :
```
admin@adm01:~$ kubectl --context k8s-par1 -n argocd scale statefulset/argocd-application-controller --replicas=0
admin@adm01:~$ kubectl --context k8s-par1 -n argocd scale deployment/argocd-applicationset-controller --replicas=0
admin@adm01:~$ kubectl --context k8s-par1 -n argocd get pods -l 'app.kubernetes.io/name in (argocd-application-controller,argocd-applicationset-controller)'
No resources found in argocd namespace.
```
4.2. **Retirer les finaliseurs** de toutes les Applications et vérifier qu'il n'en reste aucun :
```
admin@adm01:~$ kubectl --context k8s-par1 -n argocd get applications.argoproj.io -o json \
>   | jq -r '.items[] | select(.metadata.finalizers) | .metadata.name'          # inventaire (compte rendu)
admin@adm01:~$ kubectl --context k8s-par1 -n argocd get applications.argoproj.io -o name \
>   | xargs -r -I{} kubectl --context k8s-par1 -n argocd patch {} --type merge -p '{"metadata":{"finalizers":null}}'
admin@adm01:~$ kubectl --context k8s-par1 -n argocd get applications.argoproj.io -o json | jq '[.items[] | select(.metadata.finalizers)] | length'
0
```
4.3. **Orpheliner les ApplicationSets** (les Applications générées restent, sans propriétaire) :
```
admin@adm01:~$ kubectl --context k8s-par1 -n argocd delete applicationsets.argoproj.io --all --cascade=orphan
```
4.4. **Supprimer les Applications puis les AppProjects** (aucun finaliseur : rien ne touche les charges) :
```
admin@adm01:~$ kubectl --context k8s-par1 -n argocd delete applications.argoproj.io --all
admin@adm01:~$ kubectl --context k8s-par1 -n argocd get appprojects.argoproj.io -o name \
>   | xargs -r -I{} kubectl --context k8s-par1 -n argocd patch {} --type merge -p '{"metadata":{"finalizers":null}}'
admin@adm01:~$ kubectl --context k8s-par1 -n argocd delete appprojects.argoproj.io --all
```
Contrôle : les pods applicatifs n'ont pas bougé (mêmes UID).

4.5. **Supprimer la release, le CronJob, les CRD, l'espace** :
```
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd destroy
admin@adm01:~$ kubectl --context k8s-par1 delete -k ~/src/k8s/composants/argocd-sauvegarde
admin@adm01:~$ kubectl --context k8s-par1 get crd -o name | grep 'argoproj.io' | grep -v 'rollouts\|analysis\|experiments'
customresourcedefinition.apiextensions.k8s.io/applications.argoproj.io
customresourcedefinition.apiextensions.k8s.io/applicationsets.argoproj.io
customresourcedefinition.apiextensions.k8s.io/appprojects.argoproj.io
admin@adm01:~$ kubectl --context k8s-par1 delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io
admin@adm01:~$ kubectl --context k8s-par1 delete namespace argocd
```
Les CRD d'Argo **Rollouts** (`rollouts`, `analysistemplates`, `analysisruns`, `experiments`, `clusteranalysistemplates`) ne sont **pas** à supprimer : elles portent les Rollouts de MédiAgenda. Les CRD d'Argo CD survivent à `helmfile destroy` (`helm.sh/resource-policy: keep`) : d'où leur suppression explicite, **après** qu'il ne reste plus aucun objet.

## 5. Reconstruction

5.1. Espace et politiques : `task espaces`, puis les politiques de `composants/reseau/politiques/argocd*.yaml` (même commande que M20-E25).
5.2. `helmfile -e par1 -l composant=argocd apply` : pods prêts, `argocd-redis-secret-init` réussi.
5.3. `outils/secrets-k8s.sh appliquer argocd` : dépôts, dépôt OCI, cluster `lyo-k3s01`, `argocd-webhook-gitlab`, `argocd-sauvegardes-s3`.
5.4. `outils/argocd-restaurer-secret.sh /dev/shm/rb201/export.yaml --appliquer` : `server.secretkey` et comptes locaux ; redémarrage du serveur.
5.5. Application racine : `kubectl --context k8s-par1 apply --server-side -f ~/src/gitops/racine/racine.yaml`. Elle recrée AppProjects, ApplicationSets, Applications.
5.6. `task argocd-sauvegarde`, puis une exécution manuelle (`task argocd-sauvegarde-maintenant`).
5.7. Suivre : `argocd app list` (avec ton compte, mot de passe d'avant), `argocd app diff <app>` pour chaque Application qui n'est pas `Synced`. **Ne synchronise pas** une Application `OutOfSync` sans avoir compris le diff ; `mediagenda-prod` se synchronise à la main de toute façon.
5.8. Nettoyage : `rm -rf /dev/shm/rb201`.

## 6. Retour arrière

| Étape | Si ça tourne mal | Retour |
|---|---|---|
| 4.1 | — | `scale --replicas=2` (contrôleur) et `--replicas=2` (ApplicationSets) |
| 4.2 | un finaliseur réapparaît | un contrôleur tourne encore : revenir à 4.1 |
| 4.3-4.4 | une charge disparaît | **arrêt** ; restauration Velero de l'espace concerné (préalable 2) ; post-mortem |
| 4.5 | espace `argocd` bloqué en `Terminating` | un objet porte encore un finaliseur : `kubectl get applications.argoproj.io,appprojects.argoproj.io -n argocd`, retirer, attendre |
| 5.x | Application `OutOfSync` inattendue | `argocd app diff` ; si c'est une étiquette ou annotation de suivi absente (`argocd.argoproj.io/tracking-id`), vérifier `application.resourceTrackingMethod` et le nom de l'Application |
| 5.4 | jetons toujours refusés | export plus ancien que le jeton : régénérer le jeton de `ci-lecture` (`argocd account generate-token --account ci-lecture`) et le reporter dans `~/.config/workbook/argocd-checks.token` |

## 7. Vérifications finales

- `lab/bin/check 20 28` (âges des charges, racine `Synced`, ancien jeton accepté, sauvegarde du jour).
- `argocd cluster list` : `lyo-k3s01` `Successful` (s'il existe encore).
- Un *push* trivial sur `formation/gitops-labo` : événement de webhook en 200 et rafraîchissement immédiat.
- Compte rendu complété (durées par étape, RTO, écarts).
