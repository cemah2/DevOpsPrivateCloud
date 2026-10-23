### M25-E37 — Panne : un ExternalSecret en erreur

**Points non testés en conditions réelles (M25-E37)** — signale tes retours, ils corrigent le workbook :
- **Vérifié dans le code d'ESO v2.13.0** (dépôt `external-secrets/external-secrets`, étiquette `v2.13.0`) : cache des clients OpenBao indexé par nom, espace, type **et `resourceVersion` du magasin** (`providers/v1/vault/provider.go`) ; réutilisation du jeton tant que `auth/token/lookup-self` le dit valide, sinon nouvelle connexion (`auth.go`) ; message générique « could not get secret data from provider » dans la condition, erreur complète dans l'événement `UpdateFailed` ; refus « SecretStore "openbao" is not ready » quand le magasin n'est pas prêt (`assertStoreIsUsable`) ; synchronisation relancée par tout changement d'annotation ou d'étiquette (empreinte des métadonnées) ; messages `cannot request Kubernetes service account token for service account "…"` et `cannot read secret data from Vault` ; métriques `externalsecret_status_condition` et `secretstore_status_condition` (étiquettes `name`, `namespace`, `condition`, `status`) ; `serviceMonitor.honorLabels: false` par défaut dans le chart. Règles d'alerte passées à `promtool` 3.15 (`check rules`, `test rules`).
- **Script** : `break-E37.sh` exécuté avec des bouchons à la place de `kubectl` et d'OpenBao (enchaînement injection → constat → annulation de la variante 1) ; `bash -n` et `shellcheck -x` propres. Variantes 2 à 4 non jouées sur un cluster.
- **Non vérifié** : le texte exact du refus d'audience d'OpenBao 2.7 pour la méthode `kubernetes` (attendu : « invalid audience (aud) claim… ») et son code HTTP ; le fait qu'une connexion TCP **établie** survive à l'ajout d'un `egressDeny` Cilium (le script recrée le pod du contrôleur pour ne pas en dépendre) ; le libellé de Hubble pour un refus par politique de refus ; le délai de reprise du magasin après correction (nouvel essai à intervalle croissant de controller-runtime, plafonné vers 16 min).

**Démarche de diagnostic**

*Symptômes* : `harbor-pull` en `SecretSyncedError`, application Argo CD `mediagenda-recette` *Degraded* (contrôle de santé intégré des ExternalSecret), Secret figé sur sa dernière valeur.

*Hypothèses*, du plus proche au plus loin : (a) l'**ExternalSecret** lui-même (clé, propriété : exclu si l'overlay n'a pas changé — à vérifier dans l'historique Git et dans Argo CD) ; (b) le **chemin** que le magasin fait lire (moteur, version KV) ; (c) la **connexion** du magasin (compte de service, rôle, audience, liaison `auth-delegator`) ; (d) le **réseau** entre le contrôleur et la VIP ; (e) le **coffre** (scellé, sans leader : M25-E35, E39) ; (f) la **politique** `eso-mediagenda-recette`.

**Étape 1 — La portée**

```
admin@adm01:~$ kubectl -n mediagenda-recette get externalsecrets
NAME                      STORETYPE     STORE     REFRESH INTERVAL   STATUS              READY
harbor-pull               SecretStore   openbao   1h                 SecretSyncedError   False
mediagenda-db-api         …                       30m                SecretSynced        True
mediagenda-db-migrateur   …                       30m                SecretSynced        True
admin@adm01:~$ kubectl get secretstores -A ; kubectl get clustersecretstores
admin@adm01:~$ kubectl -n mediagenda-recette get externalsecret harbor-pull -o jsonpath='{.status.refreshTime}{"\n"}'
```

Les deux identifiants dynamiques passent par des **générateurs** (`VaultDynamicSecret`), qui ont leur propre configuration de fournisseur : ils ne dépendent pas du SecretStore. Qu'ils restent sains alors que `harbor-pull` échoue désigne le magasin (variantes 1 et 4) ; s'ils échouent à leur tour à leur rafraîchissement suivant, la cause est commune au rôle ou au réseau (variantes 2 et 3). **Tous** les magasins du cluster en erreur : réseau ou coffre (variante 3), jamais l'overlay.

**Étape 2 — Le message**

```
admin@adm01:~$ kubectl -n mediagenda-recette describe externalsecret harbor-pull | sed -n '/^Events:/,$p'
admin@adm01:~$ kubectl -n mediagenda-recette describe secretstore openbao | sed -n '/^Status:/,$p'
admin@adm01:~$ kubectl -n external-secrets logs deploy/external-secrets --since=30m | grep mediagenda-recette | tail -5
```

La condition `Ready` dit seulement « could not get secret data from provider » : ESO 2.13 ne recopie pas une erreur de fournisseur dans le statut (elle pourrait contenir une valeur). L'événement `UpdateFailed` porte l'erreur complète. « SecretStore "openbao" is not ready » renvoie aux événements **du magasin** (`InvalidProviderConfig`).

**Étape 3 — Les écarts aux dépôts**

```
admin@adm01:~/src/k8s$ git switch main && git pull && task diff            # magasin et compte (plateforme/k8s)
admin@adm01:~/src/secrets$ tofu -chdir=tofu plan                             # rôle (lecture seule)
admin@adm01:~$ kubectl -n external-secrets get ciliumnetworkpolicies         # face à manifestes/external-secrets/
admin@adm01:~$ bao read -format=json auth/k8s-par1/role/eso-mediagenda-recette | jq '.data | {audience, bound_service_account_names, bound_service_account_namespaces, token_policies}'
```

**Variante 1 — `version: v1` dans le magasin.**

```
Warning  UpdateFailed  …  cannot read secret data from Vault: Error making API request.
URL: GET https://openbao.par1.medisphere.internal:8200/v1/kv/mediagenda/recette/harbor-pull
Code: 403. Errors:
* 1 error occurred:
	* permission denied
```

Le magasin est `Valid` : la connexion réussit, c'est la **lecture** qui est refusée. L'URL n'a pas de `data/` : en `v1`, ESO lit `<path>/<clé>` ; en `v2`, `<path>/data/<clé>`. La politique `eso-mediagenda-recette` n'ouvre que `kv/data/mediagenda/recette/*` : OpenBao refuse avant même de router la requête vers le moteur. L'audit le confirme :

```logql
{service="openbao"} | json role="auth.metadata.role", chemin="request.path", erreur="error"
  | role="eso-mediagenda-recette" | erreur="permission denied" | line_format "{{.chemin}}"
```

`task diff` montre `version: v1` → `v2`. Correctif : `task appliquer` depuis `main` (le dépôt a raison ; `--force-conflicts` reprend le champ posé par un autre gestionnaire). Le changement de `resourceVersion` du magasin vide l'entrée du cache : la correction prend effet dès la synchronisation suivante. Le piège voisin, `path: kv/data` (ESO ajoute `data/` : `kv/data/data/…`), donne le même 403 (M25-E12).

**Variante 2 — audience du rôle changée dans le coffre.**

```
Warning  InvalidProviderConfig  …  … auth/k8s-par1/login … invalid audience (aud) claim …
```

Le magasin envoie un jeton projeté d'audience `openbao.medisphere.internal` (`serviceAccountRef.audiences`) ; le rôle attend désormais `openbao.par1.medisphere.internal` (une « harmonisation avec le nom du service »). `tofu plan` : `vault_kubernetes_auth_backend_role.eso_espace["mediagenda-recette"]` à mettre à jour, `audience`. L'audit donne l'heure et l'auteur de l'écriture sur `auth/k8s-par1/role/eso-mediagenda-recette` (ici ton jeton : l'injection l'utilise), et la révocation des jetons d'ESO de ce rôle juste après. **Sans** cette révocation, rien ne se serait vu pendant au plus 15 min : ESO garde son jeton tant qu'il est valide (cache), et l'erreur serait apparue « toute seule », loin du changement. Correctif : relancer le pipeline de `main` de `plateforme/secrets` (apply) ; ESO se reconnecte au premier essai suivant. Les générateurs de recette, qui utilisent le même rôle, échouaient aussi à leur rafraîchissement : vérifier qu'ils ont repris avant la fin des baux en cours.

**Variante 3 — une politique de refus en sortie d'ESO.**

```
Warning  InvalidProviderConfig  …  dial tcp 10.10.20.200:8200: i/o timeout
admin@adm01:~$ kubectl -n external-secrets get cnp
NAME                         AGE
external-secrets-sorties     41d
external-secrets-telemetrie  12m
admin@adm01:~$ kubectl -n external-secrets get cnp external-secrets-telemetrie -o yaml | yq '.spec'
admin@adm01:~$ hubble observe -n external-secrets --to-ip 10.10.20.200 --last 20
```

Tous les magasins sont en erreur (y compris le ClusterSecretStore), le coffre répond aux autres clients, le pod du contrôleur a été recréé récemment. `external-secrets-telemetrie` n'existe pas dans `plateforme/gitops` : Argo CD ne l'affiche pas, faute de la gérer (le nom anodin et l'annotation `OBS-2637` n'en font pas un objet légitime). Son `egressDeny` vise `10.10.20.192/26`, soit `.192` à `.255` : la VIP `.200` en fait partie. Un refus l'emporte sur l'autorisation explicite d'`external-secrets-sorties`, **quelle que soit** la politique qui la porte. Correctif : supprimer l'objet (espace de plateforme, changement d'urgence tracé) ; si une règle de télémétrie est voulue, elle passe par une MR de `plateforme/gitops` et s'écrit en autorisation, sans refus large. Les ExternalSecret de **tout** le cluster sont touchés : après correction, vérifier `kubectl get es -A`.

**Variante 4 — compte de service inexistant.**

```
Warning  InvalidProviderConfig  …  cannot request Kubernetes service account token for service account "external-secrets": …
  serviceaccounts "external-secrets" not found
```

Le magasin demande à l'API un jeton projeté pour `external-secrets` (le compte du **contrôleur**, dans **son** espace, celui du ClusterSecretStore) ; un SecretStore ne peut demander qu'un compte de **son** espace, et seul `eso` y existe (et lui seul est lié à `system:auth-delegator` et au rôle). `task diff` montre `serviceAccountRef.name`. Correctif : `task appliquer`. Créer un compte `external-secrets` dans l'espace « pour que ça marche » serait faux deux fois : le rôle ne l'accepte pas (`bound_service_account_names = ["eso"]`) et l'objet sortirait du dépôt.

**Clôture commune**

```
admin@adm01:~$ kubectl -n mediagenda-recette annotate externalsecret harbor-pull force-sync="$(date +%s)" --overwrite
admin@adm01:~$ kubectl -n mediagenda-recette get secretstore openbao ; kubectl -n mediagenda-recette get es
admin@adm01:~$ argocd app get mediagenda-recette --refresh | sed -n '1,12p'
```

L'annotation est une métadonnée : elle change l'empreinte des métadonnées et déclenche une synchronisation, sans toucher la spec (Argo CD ne la compte pas comme une dérive). Un magasin resté `InvalidProviderConfig` après la correction (variantes 2 et 3) se revalide au prochain essai du contrôleur ; une modification de métadonnée du magasin le fait tout de suite. Puis `lab/bin/check 25 37` ; `lab/bin/break 25 37 --annuler` ; journal ([modèle, variante 3](fichiers/M25-E37/medisphere/docs/socle/journal/AAAA-MM-JJ-INC-5237.md)) ; Julien relance sa rotation.

**Prévention**
- [Alertes](fichiers/M25-E37/observabilite/regles/external-secrets.yaml) `ExternalSecretEnErreur` (15 min), `MagasinSecretsEnErreur` (10 min) et `MagasinsSecretsTousEnErreur` (cause commune), avec leurs [tests](fichiers/M25-E37/observabilite/tests/external-secrets.test.yaml) (`yq '.spec' regles/external-secrets.yaml > build/regles/external-secrets.yml && cd tests && promtool test rules external-secrets.test.yaml`) et l'[ajout à la kustomization](fichiers/M25-E37/observabilite/regles/kustomization.yaml.extrait). L'espace de l'objet est lu dans `exported_namespace` **ou** `namespace` : avec le ServiceMonitor du chart (`honorLabels: false`), `namespace` vaut `external-secrets` pour toutes les séries.
- `task derive` de `plateforme/k8s` planifiée (dérive du magasin), plan nocturne de `plateforme/secrets` (dérive du rôle, comme au M25-E40), et recherche des objets **hors Git** dans les espaces de plateforme (une CNP qu'aucune Application ne suit).
- [Fiche réflexe](fichiers/M25-E37/medisphere/docs/securite/secrets/fiche-externalsecret-en-erreur.md) « ExternalSecret en erreur » pour l'astreinte.

**Explications**

ESO ne parle au coffre que par le **magasin** : à chaque synchronisation, il prend (ou réutilise) un client OpenBao pour ce magasin, se connecte par la méthode `k8s-par1` avec un jeton projeté du compte désigné, puis lit le chemin construit à partir de `path`, `version` et de la clé de l'ExternalSecret. Le cache de clients est indexé par la `resourceVersion` du magasin : modifier le magasin crée un nouveau client (effet immédiat), modifier le **rôle** dans le coffre ne se voit qu'à la reconnexion suivante (jeton expiré). Un magasin est revalidé par son propre contrôleur (statut `Ready`) ; tant qu'il n'est pas prêt, les ExternalSecret qui l'utilisent ne tentent même plus de lire. Un ExternalSecret en échec garde son Secret intact et réessaie à intervalle croissant : la panne est silencieuse jusqu'à ce qu'une **nouvelle** valeur doive passer, d'où l'intérêt de l'alerte.

**Alternatives**
- Lire la valeur du Secret et la comparer au coffre pour « voir si c'est à jour » : expose un secret pour rien ; `refreshTime`, `syncedResourceVersion` et l'annotation d'empreinte des données du Secret (`reconcile.external-secrets.io/data-hash`) suffisent.
- Désactiver le cache de jetons pour des erreurs immédiates : une connexion par synchronisation et un audit bien plus bruyant ; on garde le cache et on connaît le délai.
- Redémarrer ESO « pour voir » : vide le cache et masque la chronologie ; utile seulement pour prouver qu'une connexion établie survivait à une politique réseau.

**Pièges classiques**
- S'arrêter à la condition (« could not get secret data from provider ») sans lire les événements.
- Élargir la politique `eso-mediagenda-recette` (`kv/mediagenda/*`) parce que le message dit « permission denied » : la cause était le chemin (variante 1), et l'espace lirait autre chose que sa recette.
- Corriger le magasin par `kubectl edit` : marche, mais le dépôt et `task diff` ne disent plus rien ; ou modifier l'ExternalSecret à la main : Argo CD le remet.
- Chercher la politique réseau dans Argo CD : il ne montre que ce qu'il gère.
- Conclure trop vite qu'un changement de rôle est « sans effet » : le cache de jetons retarde l'erreur d'un quart d'heure.
- Oublier les identifiants dynamiques : `harbor-pull` peut attendre, pas un bail d'une heure qui n'est plus renouvelé.

**En production chez MédiSphère**

Alertes sur les ExternalSecret et les magasins routées vers l'équipe propriétaire de l'espace **et** la plateforme ; Kyverno (M26) interdit aux équipes `SecretStore`, `ClusterSecretStore`, générateurs et CiliumNetworkPolicy dans les espaces de plateforme ; toute écriture sur `auth/*/role/*` hors du jeton du pipeline de `plateforme/secrets` remonte comme `OpenBaoPolitiqueModifiee` (M25-E21) ; dérive Kubernetes et OpenBao vérifiée chaque nuit, objets hors Git listés chaque semaine.

---
