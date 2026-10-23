# Fiche réflexe — ExternalSecret en erreur (ESO 2.13 et OpenBao)

> M25-E37 (INC-5237). Un ExternalSecret en erreur **ne supprime pas** son Secret : il garde sa dernière
> valeur. On a donc le temps de diagnostiquer, sauf pour les identifiants dynamiques (bail d'une heure).
> On ne lit **jamais** les données du Secret pour diagnostiquer : statuts, événements et audit suffisent.

## 1. Portée : un objet, un espace, ou tout le cluster ?

```
admin@adm01:~$ kubectl get externalsecrets -A | grep -v SecretSynced
admin@adm01:~$ kubectl get secretstores -A ; kubectl get clustersecretstores
```

- Un seul ExternalSecret en erreur, magasin `Valid` → **sa** clé (`remoteRef`/`extract`) ou le chemin
  calculé par le magasin (§ 3).
- Tous les ExternalSecret d'un espace, magasin `InvalidProviderConfig` → **le magasin** ou **son rôle** (§ 4).
- Tous les magasins du cluster en erreur → **cause commune** : contrôleur d'ESO, réseau, coffre (§ 5).

## 2. Lire le vrai message

ESO 2.13 ne met dans la condition qu'un message générique (« could not get secret data from
provider » : une erreur de fournisseur peut contenir des données). Le détail est dans les **événements** :

```
admin@adm01:~$ kubectl -n <ESPACE> describe externalsecret <NOM>      # événements UpdateFailed
admin@adm01:~$ kubectl -n <ESPACE> describe secretstore openbao       # InvalidProviderConfig, Valid
admin@adm01:~$ kubectl -n external-secrets logs deploy/external-secrets --since=30m | grep -i <ESPACE>
```

« SecretStore "openbao" is not ready » sur l'ExternalSecret renvoie aux événements **du magasin**.

## 3. Le chemin lu dans le coffre

Le message d'un refus (403) contient l'URL demandée : `GET …/v1/kv/data/<application>/<env>/<clé>`
attendu. Sans `data/` → magasin en `version: v1` ; `kv/data/data/…` → `path: kv/data` dans le magasin.
Côté OpenBao, l'audit (Loki, locataire `audit`) :

```logql
{service="openbao"} | json role="auth.metadata.role", chemin="request.path", erreur="error"
  | role="eso-<ESPACE>" | erreur!="" | line_format "{{.chemin}} {{.erreur}}"
```

## 4. La connexion d'ESO (méthode `k8s-par1`)

| Message (événements du magasin ou de l'ExternalSecret) | Cause |
|---|---|
| `cannot request Kubernetes service account token for service account "<X>"` … `not found` | `serviceAccountRef.name` faux, ou compte supprimé |
| `invalid audience (aud) claim` | `audiences` du magasin ≠ `audience` du rôle OpenBao |
| `service account name not authorized` / `namespace not authorized` | `bound_service_account_*` du rôle |
| `invalid role name` | rôle du magasin absent du coffre (faute de frappe, rôle non créé par `plateforme/secrets`) |
| refus de la revue de jeton (TokenReview) dans le message de connexion | liaison `openbao-auth-delegator` du compte manquante (M25-E12) |
| `i/o timeout`, `context deadline exceeded` vers `10.10.20.200:8200` | flux coupé (§ 5) ou coffre arrêté |

```
admin@adm01:~$ bao read -format=json auth/k8s-par1/role/eso-<ESPACE> | jq '.data | {audience, bound_service_account_names, bound_service_account_namespaces, token_policies}'
admin@adm01:~/src/secrets$ tofu -chdir=tofu plan        # la dérive du rôle apparaît
admin@adm01:~/src/k8s$ task diff                         # la dérive du magasin apparaît
```

Jetons en cache : ESO réutilise son jeton OpenBao jusqu'à son expiration (15 min) ou jusqu'à une
modification du magasin. Un changement du rôle dans le coffre peut donc ne se voir qu'**un quart d'heure
plus tard**.

## 5. Le chemin réseau

```
admin@adm01:~$ kubectl -n external-secrets get ciliumnetworkpolicies ; kubectl get ciliumclusterwidenetworkpolicies
admin@adm01:~$ hubble observe -n external-secrets --to-ip 10.10.20.200 --last 20
```

Un `egressDeny` l'emporte sur toute autorisation, quel que soit le nom de la politique. Toute CNP de
`external-secrets` absente de `plateforme/gitops` (`manifestes/external-secrets/`) est suspecte : Argo CD
ne montre pas les objets qu'il ne gère pas.

## 6. Après la correction

ESO réessaie seul (intervalle croissant, jusqu'à un quart d'heure). Pour ne pas attendre, une
**métadonnée** suffit (ce n'est pas une modification de configuration : Argo CD ne la voit pas) :

```
admin@adm01:~$ kubectl -n <ESPACE> annotate externalsecret <NOM> force-sync="$(date +%s)" --overwrite
```

Vérifier `SecretSynced`, puis l'alerte `ExternalSecretEnErreur` résolue. Identifiants dynamiques :
vérifier que Reloader a bien redémarré les pods (M25-E15).
