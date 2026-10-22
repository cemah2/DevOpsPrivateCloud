# RB-221 — Traiter une demande d'effacement dans les journaux

| | |
|---|---|
| Déclencheur | Ticket `SEC-` de la RSSI ou du DPO : donnée personnelle journalisée (fuite) ou droit à l'effacement |
| Exécutant | Équipe Plateforme (astreinte) — jamais seul : un second membre relit la demande avant création |
| Durée | 30 min de travail ; suppression physique sous 48 h |
| Références | `politique-journaux.md` § 2.3, documentation Loki « Log entry deletion », API `/loki/api/v1/delete` |

## 0. Ce que ce runbook ne fait pas

- Il n'efface **rien** dans le locataire `audit` (fermé par configuration : l'API répond `403 deletion is not available for this tenant`). Une donnée personnelle dans l'audit se traite par décision écrite de la RSSI.
- Il ne corrige pas la cause : ouvrir en parallèle le ticket de correction du masquage (Alloy, M22-E09) ou de l'application.

## 1. Qualifier la demande (avec le demandeur)

1. Locataire concerné (`mediagenda`, `medidoc` ou `essai`), espace, application.
2. Motif exact à effacer (identifiant, adresse…) — **dans le ticket, seulement sa forme** (« identifiant patient commençant par PAT- ») : on ne recopie pas la donnée.
3. Fenêtre de temps : première et dernière occurrence. La trouver par requête, sans afficher les lignes :
   ```
   admin@adm01:~$ export LOKI_ADDR=http://loki.apps.par1.medisphere.internal:3100
   admin@adm01:~$ read -rs MOTIF   # la valeur à effacer, jamais dans l'historique du shell
   admin@adm01:~$ logcli query --org-id=mediagenda --since=720h --step=1h --quiet \
       "sum(count_over_time({namespace=~\"mediagenda-.+\"} |= \"$MOTIF\" [1h]))"
   ```
   Retenir l'heure de début de la première tranche non nulle et la fin de la dernière.

## 2. Créer la demande (relue par un second membre)

```
admin@adm01:~$ logcli delete create --org-id=mediagenda \
    "{namespace=~\"mediagenda-.+\"} |= \"$MOTIF\"" \
    --from="<DÉBUT RFC 3339, UTC>" --to="<FIN RFC 3339, UTC, pas dans le futur>"
```

Règles : sélecteur **et** filtre de ligne (jamais un sélecteur seul : il effacerait tout le flux) ; fenêtre la plus courte possible ; fin ≤ maintenant (sinon `deletes in the future are not allowed`).

## 3. Relever l'identifiant et vérifier l'effet immédiat

```
admin@adm01:~$ curl -s -H 'X-Scope-OrgID: mediagenda' "$LOKI_ADDR/loki/api/v1/delete" | jq '.[] | {request_id, status, query, start_time, end_time}'
admin@adm01:~$ logcli query --org-id=mediagenda --from=… --to=… --quiet "{namespace=~\"mediagenda-.+\"} |= \"$MOTIF\""   # doit être vide
```

`logcli delete list` n'affiche pas l'identifiant ; l'API, si. Statut attendu : `received`. Les requêtes ne renvoient déjà plus les lignes visées (filtrage à la lecture).

## 4. Annuler si erreur (dans les 24 h)

```
admin@adm01:~$ logcli delete cancel --org-id=mediagenda --request-id=<ID>
```

Après 24 h (`delete_request_cancel_period`), la demande passe au compactor ; une annulation n'est plus possible que par `--force` et ne rend pas ce qui a déjà été supprimé.

## 5. Constater la suppression physique (J+1 à J+2)

- Statut `processed` dans la liste des demandes.
- Métriques : `loki_compactor_delete_requests_processed_total` a augmenté, `loki_compactor_deleted_lines` aussi ; `loki_compactor_pending_delete_requests_count` revient à 0.

## 6. Clore le ticket

Dans le ticket `SEC-` : identifiant de la demande, sélecteur (sans la valeur), fenêtre, dates de création et de traitement, résultat de la requête de vérification (nombre de lignes = 0), ticket de correction de la cause. Le motif effacé n'apparaît nulle part.

## Pièges

- Le compartiment est versionné (M22-E16) : les objets supprimés par le compactor restent **7 jours** en version non courante. Pour une fuite grave, la RSSI peut demander la purge immédiate des versions non courantes concernées : opération exceptionnelle, faite avec l'administrateur du RGW et tracée dans le ticket, hors de ce runbook.
- Les métriques tirées des journaux (règles du *ruler*, M22-E08) déjà enregistrées dans Prometheus ne sont pas recalculées.
- Loki invalide son cache des résultats à chaque nouvelle demande (numéro de génération du cache, service `cache-generation-loader`) ; si une vérification renvoie encore la ligne, relance-la sur une fenêtre close et note-le : c'est un écart à signaler, pas un état normal.
