# Comparatif des collecteurs de journaux : Grafana Alloy et Fluent Bit

> M22-E10 (PLAT-2310). Essai du 2026-10-.. sur `k8s-par1` : Fluent Bit **5.1.3** (chart `fluent/fluent-bit`
> 0.58.3) dans `journaux-essai`, à côté d'Alloy **1.21.1** (chart `grafana/alloy` 1.14.1) dans `journaux`.
> Même périmètre pour les deux : conteneurs de `mediagenda-recette` et de `journaux`, pendant 2 h, avec
> `ressources/E04-trafic/trafic.sh`. Fluent Bit écrivait dans le locataire `essai`. **Essai retiré.**
>
> ⚠️ Les mesures ci-dessous sont un **exemple de forme** : remplace-les par les tiennes (méthode en fin
> de document). Ce qui compte : la même charge pour les deux, et des chiffres sourcés.

## 1. Ressources (moyenne sur 2 h, par pod, mesures `kubectl top` et métriques cAdvisor)

| | Alloy (DaemonSet complet) | Fluent Bit (périmètre réduit) |
|---|---|---|
| Mémoire de travail | ~ 95 Mi (pods + journald + audit + événements) | ~ 18 Mi |
| CPU | ~ 15 m | ~ 5 m |
| Image | ~ 150 Mo (binaire Go, nombreux composants) | ~ 30 Mo (C) |
| Lignes envoyées (2 h, même périmètre) | identiques à ± 0,5 % | identiques à ± 0,5 % |

Lecture : Fluent Bit est nettement plus léger ; à périmètre égal (Alloy ne lisant que les mêmes
fichiers), l'écart se réduit mais reste à l'avantage de Fluent Bit. Sur trois travailleurs de 10 Go,
la différence (de l'ordre de 50 à 80 Mi par nœud) n'est pas décisive.

## 2. Configuration

| Critère | Alloy | Fluent Bit |
|---|---|---|
| Langage | syntaxe Alloy : composants reliés (`forward_to`), expressions, `alloy fmt` / `alloy validate` en CI | fichiers « classiques » à sections `[INPUT]` / `[FILTER]` / `[OUTPUT]` ou YAML ; `--dry-run` |
| Découverte Kubernetes | `discovery.kubernetes` + règles de *relabel* (même modèle que Prometheus) | filtre `kubernetes` (enrichit chaque enregistrement par l'API) |
| Étiquettes Loki | liste fermée construite par relabel, contrôle fin | `labels` avec accesseurs `$kubernetes['…']` ; `auto_kubernetes_labels` dangereux (toutes les étiquettes) |
| Métadonnées structurées | `stage.structured_metadata` | option `structured_metadata` de la sortie Loki |
| Locataire par entrée | `stage.tenant` (étiquette, champ extrait ou valeur) | `tenant_id` fixe, ou `tenant_id_key` (champ de l'enregistrement) |
| Masquage | `stage.replace` (expressions RE2, gabarits) | filtre `modify`/`lua` (script Lua pour un vrai masquage) |
| Positions de lecture | fichier sous `--storage.path` | base SQLite `DB` |
| Rechargement | à chaud (`/-/reload`, config-reloader du chart) | à chaud depuis 2.x (`hot_reload`), redémarrage dans le chart |
| Journal d'audit, événements | `loki.source.file`, `loki.source.kubernetes_events` (clustering) | `tail` ; événements par l'entrée `kubernetes_events` |
| Au-delà des journaux | métriques, traces OTLP, profils : **un seul agent** pour M21-M23 | journaux surtout (métriques et traces possibles, moins intégrées) |

## 3. Fonctionnement constaté pendant l'essai

- Les deux lisent le format CRI et recollent les lignes partielles.
- Fluent Bit : sans `drop_single_key raw`, la ligne envoyée à Loki est un JSON qui **enveloppe** la ligne
  d'origine (`{"log":"…"}`) ; les requêtes `| json` de MédiAgenda deviennent `| json | line_format "{{.log}}" | json`.
- Fluent Bit : `app=$kubernetes['labels']['app.kubernetes.io/name']` vide pour les pods sans cette
  étiquette : il faut une valeur de repli (Lua), là où Alloy la gère par une règle de relabel.
- Fluent Bit : aucune notion de locataire par espace sans `tenant_id_key` et un filtre qui écrit le champ.

## 4. Décision

**Recommandation : Alloy reste le collecteur de la plateforme** (dans le cluster et sur les VMs) ;
Fluent Bit n'est pas retenu. Raisons, par ordre de poids :

1. un seul agent pour les journaux (M22), les traces OTLP et le profilage (M23) ;
2. le même modèle de découverte et de relabel que Prometheus (M21), déjà connu de l'équipe ;
3. le locataire et le masquage s'écrivent simplement, et la configuration se valide en CI ;
4. l'écart de mémoire (quelques dizaines de Mi par nœud) est acceptable chez nous.

Fluent Bit redeviendrait un candidat pour un environnement très contraint (agence LYO1 sur k3s, 2 Go)
ou s'il fallait alimenter OpenSearch (M22-E15). Décision consignée dans l'ADR-0220 (M22-E17).

## 5. Méthode de mesure (pour refaire l'essai)

```
admin@adm01:~$ kubectl --context k8s-par1 top pods -n journaux -l app.kubernetes.io/name=alloy
admin@adm01:~$ kubectl --context k8s-par1 top pods -n journaux-essai
admin@adm01:~$ # même chose sur 2 h dans Prometheus :
#   avg_over_time(container_memory_working_set_bytes{namespace=~"journaux|journaux-essai", container=~"alloy|fluent-bit"}[2h])
#   rate(container_cpu_usage_seconds_total{namespace=~"journaux|journaux-essai", container=~"alloy|fluent-bit"}[2h])
admin@adm01:~$ # lignes reçues des mêmes pods, dans les deux locataires :
admin@adm01:~$ LOKI_ADDR=http://loki.apps.par1.medisphere.internal:3100 logcli --org-id=mediagenda instant-query \
    'sum(count_over_time({namespace="mediagenda-recette", container="api"}[2h]))'
admin@adm01:~$ LOKI_ADDR=http://loki.apps.par1.medisphere.internal:3100 logcli --org-id=essai instant-query \
    'sum(count_over_time({job="fluent-bit", namespace="mediagenda-recette", container="api"}[2h]))'
```

## 6. Retrait (fait)

Fichier `plateforme/gitops/plateforme/fluent-bit-essai.yaml` retiré (le finaliseur supprime les
objets), espace `journaux-essai` supprimé à la main, règle temporaire retirée de la CNP
`loki-entree`, chart `fluent-bit` retiré de `plateforme/charts-miroir`. Les lignes du locataire
`essai` restent dans Loki jusqu'à leur rétention (M22-E13).
