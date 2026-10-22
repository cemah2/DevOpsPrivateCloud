# RB-220 — Chercher dans les journaux pendant un incident

> Runbook de référence des journaux (M22-E12). Public : astreinte (Nadia Roussel et l'équipe Plateforme),
> équipes MédiAgenda et MédiDoc. Cité par les alertes du ruler de Loki (`runbook_url`).
> Outils : Grafana « Explore » (`https://grafana.apps.par1.medisphere.internal`) ou `logcli` sur `adm01`.

## 0. En 30 secondes

1. **Quel locataire ?** Une équipe = un locataire : `mediagenda`, `medidoc` ; tout le reste (cluster,
   nœuds, VMs, Argo CD, Loki…) = `plateforme` ; qui a fait quoi sur l'API Kubernetes = `audit`.
   Dans Grafana : la source `Loki — <locataire>`. Avec logcli : `--org-id=<locataire>`.
2. **Quelle fenêtre ?** Commence **étroit** (15 min autour de l'heure du symptôme), élargis ensuite.
3. **Quel flux ?** Toujours un sélecteur d'étiquettes précis **avant** tout filtre :
   `{namespace="mediagenda-prod", container="api"}` — jamais `{job=~".+"}` sur 7 jours.

## 1. Préparer son poste (une fois)

```
admin@adm01:~$ export LOKI_ADDR=http://loki.apps.par1.medisphere.internal:3100
admin@adm01:~$ logcli --org-id=plateforme labels                    # la connexion marche ?
admin@adm01:~$ logcli --org-id=mediagenda labels namespace          # quels espaces dans ce locataire ?
```

Les étiquettes indexées (les seules utilisables dans `{…}`) : `cluster`, `namespace`, `app`,
`container`, `node`, `job` (`pods`, `journald`, `kubernetes-audit`, `kubernetes-events`), et pour les
VMs `host`, `role`, `site`. Tout le reste se filtre **après** le sélecteur : métadonnées structurées
(`pod`, `stream`, `niveau`, `request_id`, `unite`, et pour l'audit `verb`, `user`, `code`,
`resource`, `object_ns`, `object_name`) ou champs de la ligne (`| json`, `| logfmt`).

## 2. Requêtes types

| Question | Locataire | Requête |
|---|---|---|
| Les erreurs de l'API MédiAgenda en prod | mediagenda | `{namespace="mediagenda-prod", container="api"} \| json \| code >= 500` |
| Tout ce qu'a fait UNE requête | mediagenda | `{namespace="mediagenda-prod", container="api"} \| request_id="<ID>"` (l'ID est dans l'en-tête `X-Request-ID` de la réponse) |
| Les erreurs par route, minute par minute | mediagenda | `sum by (route) (count_over_time({namespace="mediagenda-prod", container="api"} \| json \| code >= 500 [1m]))` |
| Un pod qui redémarre : ses dernières lignes | mediagenda | `{namespace="mediagenda-prod", container="api"} \| pod="<pod>"` (le pod n'existe plus ? les lignes, si) |
| Les événements Kubernetes d'un espace | équipe ou plateforme | `{job="kubernetes-events", namespace="mediagenda-prod"} \| logfmt \| type="Warning"` |
| Un nœud : kubelet et containerd | plateforme | `{job="journald", node="k8s-w02"} \| unite=~"kubelet.service\|containerd.service"` |
| Une VM du socle | plateforme | `{job="journald", host="git01"} \| niveau=~"error\|crit\|alert\|emerg"` |
| Qui a supprimé un objet ? | audit | `{job="kubernetes-audit"} \| verb="delete" \| object_ns="mediagenda-prod" \| object_name="<nom>"` |
| Qui a ouvert un shell dans un pod ? | audit | `{job="kubernetes-audit"} \| resource="pods" \| json \| objectRef_subresource="exec"` |
| Échecs d'authentification sur l'API : d'où ? | audit | `{job="kubernetes-audit"} \| code="401" \| json ip="sourceIPs[0]", qui="user.username" \| line_format "{{.ip}} {{.qui}}"` (l'analyseur `json` sans expression ignore les tableaux) |
| Loki ou Alloy eux-mêmes | plateforme | `{namespace="journaux"} \| logfmt \| level=~"warn\|error"` |

Avec logcli, mêmes requêtes :

```
admin@adm01:~$ logcli --org-id=mediagenda query --since=30m --limit=200 '{namespace="mediagenda-prod", container="api"} | json | code >= 500'
admin@adm01:~$ logcli --org-id=audit query --from=2026-10-22T08:00:00Z --to=2026-10-22T09:00:00Z '{job="kubernetes-audit"} | verb="delete"'
admin@adm01:~$ logcli --org-id=mediagenda query --tail '{namespace="mediagenda-recette", container="api"}'     # suivre en direct
```

## 3. Droits : qui voit quoi

- Grafana : chaque équipe voit **sa** source (dossiers et équipes du M21) ; l'astreinte et la
  Plateforme voient les quatre. Grafana OSS ne restreint pas une source par équipe : voir M22-E16 et
  `politique-journaux.md` §3.
- `logcli` depuis `adm01` : réservé à l'équipe Plateforme (le Service 10.10.41.62 n'est lisible que
  depuis MGMT, CNP `loki-entree`).
- Locataire `audit` : Plateforme et RSSI seulement. Toute recherche dans l'audit pendant un incident
  se note dans le journal de diagnostic (`docs/kubernetes/journal/`).

## 4. Pièges

| Piège | Ce qui se passe | Parade |
|---|---|---|
| Mauvais locataire | « aucun résultat » alors que les lignes existent | vérifie la source / `--org-id` avant de conclure |
| Fenêtre trop large, sélecteur trop vague | requête lente, `max_query_series` ou délai dépassé | sélecteur précis, fenêtre de 15 min, puis élargir |
| Heure locale / UTC | Grafana affiche l'heure du navigateur, logcli et Loki parlent UTC | `--from/--to` en `Z`, et l'écrire dans le journal de diagnostic |
| `kubectl logs` d'un pod remplacé | « not found » | Loki garde les lignes : sélecteur + `\| pod="…"` |
| Absence de lignes = absence d'événement ? | pas forcément : collecte arrêtée, niveau `debug` filtré, sondes écartées, masquage | regarde l'alerte `CollecteJournauxArretee`, et `loki_process_dropped_lines_total` dans Prometheus |
| Rétention | au-delà de 14 j (plateforme) ou 30 j (équipes), plus rien | l'audit est gardé 1 an ; ailleurs, les métriques (Thanos) restent |
| Données masquées | `[NIR-MASQUE]`, `[COURRIEL-MASQUE]` : voulu | ne jamais chercher une donnée de patient dans les journaux : elle n'y est pas, par politique |
| Requête copiée dans un ticket | elle peut contenir un identifiant sensible | n'y mettre que des identifiants techniques (`request_id`, `rdv_id`) |

## 5. Après la recherche

Note dans le journal de diagnostic : la question, le locataire, la requête exacte, la fenêtre (UTC),
ce que tu en conclus. Une requête utile deux fois mérite un panneau de tableau de bord ou une règle
d'alerte (`plateforme/observabilite/loki/regles/<locataire>/`).
