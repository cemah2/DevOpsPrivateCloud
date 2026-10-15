# Politiques réseau de MédiAgenda (M15-E17, SEC-1617 ; réduites en M17-E04, PLAT-1804)

Manifestes **sans espace de noms** : les mêmes fichiers s'appliquent à `mediagenda-dev` et à
`mediagenda-recette` (`task reseau:politiques`, ou à la main) :

    kubectl apply --server-side -n mediagenda-dev     -f espaces/politiques-mediagenda/
    kubectl apply --server-side -n mediagenda-recette -f espaces/politiques-mediagenda/

Ce qui reste à la plateforme, parce que cela vaut pour tout l'espace ou pour les données :

| Fichier | Politique | Rôle |
|---|---|---|
| `00-refus-par-defaut.yaml` | `refus-par-defaut` | rien n'entre, rien ne sort, sauf autorisation explicite |
| `10-sortie-dns.yaml` | `sortie-dns` | résolution de noms vers CoreDNS, pour tous les pods |
| `30-valkey-replication.yaml` | `valkey-replication` | réplication entre les instances de Valkey |

Ce qui est parti en M17-E04, quand le chart `mediagenda` a remplacé le MédiAgenda du M14 (pods
`app.kubernetes.io/name: mediagenda` au lieu de `mediagenda-api`) :

| Ancienne politique | Remplacée par |
|---|---|
| `api-entree` (CiliumNetworkPolicy L7) | `mediagenda-depuis-gateway`, rendue par le chart, même filtrage L7 |
| `api-vers-donnees` | NetworkPolicy `mediagenda`, rendue par le chart (sorties DNS, base, Valkey) |
| `taches-vers-postgresql` | `mediagenda-vers-postgresql` (`espaces/mediagenda-recette/`, M16) pour le Job de migration ; plus de CronJob de sauvegarde en dev depuis M17-E03 |
| `postgresql-depuis-api`, `valkey-depuis-api` | `mediagenda-acces-base` et `mediagenda-acces-valkey` de `mediagenda/deploiement` (recette) ; politiques du chart (dev) |

Les objets retirés du dépôt ont été supprimés à la main des deux espaces (`kubectl apply` ne
supprime rien). Matrice des flux : `docs/kubernetes/reseau/flux-mediagenda.md` (plateforme/medisphere),
à mettre à jour avec les nouveaux noms.
