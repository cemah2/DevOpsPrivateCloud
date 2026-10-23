# Fiche réflexe — « permission denied » dans OpenBao

> M25-E40 (INC-5240). À suivre **avant** de toucher à une politique. On ne demande jamais son jeton à
> la personne, on ne se connecte pas à sa place : on travaille par **accesseur** et dans l'**audit**.

## 1. Quel jeton, quelles politiques ?

```
admin@adm01:~$ bao list -format=json auth/token/accessors | jq -r '.[]' | while read -r a; do
    bao token lookup -format=json -accessor "$a" | jq -r --arg a "$a" 'select(.data.display_name == "oidc-<IDENTIFIANT>")
      | [$a, .data.issue_time, (.data.policies | join(",")), ((.data.identity_policies // []) | join(","))] | @tsv'; done
```

- `policies` : celles du **rôle** de la méthode (pour une personne : `default`).
- `identity_policies` : celles des **groupes** (externes) de son entité, **recalculées à chaque requête**.
- Pas de `identity_policies` alors que la personne est dans le groupe de l'annuaire → l'**alias** du
  groupe externe ne correspond plus à la revendication `groups` (§ 4).

## 2. Que peut faire ce jeton sur ce chemin ?

```
admin@adm01:~$ bao write -format=json sys/capabilities-accessor accessor=<ACCESSEUR> paths=kv/data/<CHEMIN> | jq .data
```

Rappels : `bao kv get|put` → `kv/data/…` ; `bao kv list` et l'arbre de l'interface → `kv/metadata/…` ;
`bao kv delete` → `kv/data/…` (suppression douce), `undelete`/`destroy` → `kv/undelete|destroy/…`.

## 3. Ce que l'audit a vu

LogQL (Grafana, source Loki, locataire `audit`) :

```logql
{service="openbao"} | json qui="auth.display_name", chemin="request.path", op="request.operation", erreur="error"
  | qui="oidc-<IDENTIFIANT>" | erreur="permission denied" | line_format "{{.op}} {{.chemin}}"
```

Le chemin **exact** demandé est souvent la réponse (préfixe `data/`, sous-dossier imprévu).

## 4. Lire la chaîne

| Maillon | Commande | Piège |
|---|---|---|
| Politique | `bao policy read <nom>` | `+` = **un** segment ; `*` seulement en fin de motif ; `data/` et `metadata/` |
| Entre politiques | toutes les politiques du jeton | la règle au motif **le plus précis** s'applique seule ; deux motifs **identiques** : capacités réunies, `deny` l'emporte |
| Groupe externe | `bao read identity/group/name/<groupe>` | politiques du groupe (appliquées tout de suite aux jetons existants) |
| Alias du groupe | champ `alias` du groupe | nom **exact** de la revendication `groups`, sur l'accessor du montage `oidc/` ; effet à la **prochaine connexion** |
| Dérive | `tofu -chdir=tofu plan` dans `plateforme/secrets` | une modification à la main se voit au plan |

## 5. Corriger

Par `plateforme/secrets` (MR, test des politiques en CI, plan, apply) ; jamais en élargissant un motif
« pour débloquer ». Puis : capacités par accesseur, essai de la personne ; nouvelle connexion
**nécessaire** seulement si l'alias de groupe était en cause.
