# Journal de diagnostic — INC-5237 « ExternalSecret en erreur » (Julien Petit, recette)

> Modèle de journal (M25-E37), rempli ici pour la variante « politique réseau ». Une ligne par geste :
> heure, hypothèse, commande (sans valeur de secret), résultat, conclusion. Aucun jeton, aucune donnée
> du Secret (`kubectl get secret … -o yaml` est proscrit : seules les métadonnées comptent).

| Heure | Hypothèse | Commande | Résultat | Conclusion |
|---|---|---|---|---|
| 10:02 | — | `kubectl -n mediagenda-recette get externalsecrets` | `harbor-pull` `SecretSyncedError`, les deux `mediagenda-db-*` encore `SecretSynced` (rafraîchis il y a 20 min) | une seule ES visible en erreur pour l'instant |
| 10:03 | portée | `kubectl get externalsecrets,secretstores -A` ; `kubectl get clustersecretstores` | tous les magasins `Ready=False` (recette, dev, prod, MédiDoc, `openbao` de cluster) | cause **commune** : pas l'overlay de recette |
| 10:05 | coffre indisponible | `curl -s https://openbao.par1.medisphere.internal:8200/v1/sys/health` (depuis `adm01`) | 200, actif | le coffre répond aux autres |
| 10:06 | — | `kubectl -n mediagenda-recette describe secretstore openbao` (événements) | `InvalidProviderConfig` … `dial tcp 10.10.20.200:8200: i/o timeout` | ESO ne joint pas la VIP |
| 10:08 | flux réseau | `hubble observe -n external-secrets --to-ip 10.10.20.200 --last 20` | `DROPPED` (refus par politique) | le refus est dans le cluster, pas sur le routeur |
| 10:10 | — | `kubectl -n external-secrets get cnp` | `external-secrets-sorties` (Git) **et** `external-secrets-telemetrie` (inconnue d'Argo CD) | objet hors Git |
| 10:11 | — | `kubectl -n external-secrets get cnp external-secrets-telemetrie -o yaml` | `egressDeny` vers `10.10.20.192/26` port 8200 | /26 couvre .192 à .255 : la VIP .200 en fait partie ; un refus l'emporte sur toute autorisation |
| 10:14 | — | `kubectl -n external-secrets delete cnp external-secrets-telemetrie` (accord de Karim, CHG en urgence) | supprimée | — |
| 10:19 | — | `kubectl get secretstores -A` ; `kubectl -n mediagenda-recette get es` | magasins `Valid` ; `harbor-pull` `SecretSynced` après `force-sync` | réparé |

**Cause** : CiliumNetworkPolicy ajoutée à la main dans `external-secrets` (« télémétrie », ticket
OBS-2637), dont un `egressDeny` couvrait la VIP du coffre. **Correctif** : suppression ; si une règle de
télémétrie est voulue, elle passe par une MR de `plateforme/gitops` (`manifestes/external-secrets/`) et
n'utilise pas de refus large. **Prévention** : alertes `MagasinSecretsEnErreur` et
`MagasinsSecretsTousEnErreur` ; recherche hebdomadaire des objets hors Git dans les espaces de plateforme.
