# RB-292 — Arrêter le chaos, tout de suite

| | |
|---|---|
| Déclencheurs | Une expérience fait plus de dégâts que prévu ; une alerte de recette pendant une expérience ; une expérience qui « ne s'arrête plus » ; demande de l'équipe MédiAgenda ou de l'astreinte |
| Durée | 2 min pour arrêter, 15 min pour vérifier |
| Références | Chaos Mesh 2.8 (`docs/qualite/chaos-mesh.md`), expériences `plateforme/resilience/chaos/`, garde-fous : filtre d'espaces, VAP `medisphere-chaos-espaces` |

**Toutes** les expériences vivent dans l'espace `chaos-experiences` : c'est là qu'on agit, jamais dans l'espace visé.

## 1. Mettre en pause (réversible, 30 s)

```
admin@adm01:~$ kubectl -n chaos-experiences get podchaos,networkchaos,stresschaos,iochaos,timechaos,httpchaos,schedules,workflows
admin@adm01:~$ for t in podchaos networkchaos stresschaos iochaos timechaos httpchaos schedules workflows; do
    kubectl -n chaos-experiences annotate "$t" --all experiment.chaos-mesh.org/pause=true --overwrite
  done
```

La pause fait **retirer** la panne par le contrôleur (le `chaos-daemon` du nœud défait ce qu'il a posé : règles `tc`, `iptables`, processus de stress ; les conteneurs remplacés par `pause` retrouvent leur image). Un `Schedule` en pause ne crée plus d'expérience.

## 2. Supprimer (définitif)

```
admin@adm01:~$ kubectl -n chaos-experiences delete podchaos,networkchaos,stresschaos,iochaos,timechaos,httpchaos,schedules,workflows --all
```

La suppression déclenche la même récupération (*finalizer* `chaos-mesh/records`) **avant** que l'objet disparaisse. Un objet qui reste en `Terminating` = la récupération n'a pas abouti → § 3. **Ne retire jamais le finalizer à la main** sans avoir vérifié l'état des pods visés : la panne resterait posée, sans plus personne pour la retirer.

## 3. Vérifier que rien ne reste

| Quoi | Commande | Attendu |
|---|---|---|
| Objets | `kubectl -n chaos-experiences get podchaos,networkchaos,stresschaos,schedules,workflows` | aucun, ou tous en pause avec la condition `AllRecovered=True` |
| Objets internes | `kubectl get podnetworkchaos,podiochaos,podhttpchaos -A` | aucun |
| Pods visés | `kubectl -n mediagenda-recette get pods` ; `kubectl -n mediagenda-recette describe pod <pod>` | images d'origine (pas `pause`), prêts |
| Contrôleur | `kubectl -n chaos-mesh logs deploy/chaos-controller-manager --since=15m \| grep -i error` | pas d'erreur de récupération |
| Service | sonde `/pret` de la recette, SLO de recette (Pyrra) | revenus à la normale |

Si un pod garde une panne réseau (latence, perte) malgré l'absence d'objet : supprimer le **pod** (son contrôleur le recrée, propre) ; consigner l'incident.

## 4. Couper Chaos Mesh entièrement (dernier recours)

```
admin@adm01:~$ kubectl -n chaos-mesh scale deploy/chaos-controller-manager --replicas=0
```

Plus aucune expérience n'est appliquée **ni retirée** : fais d'abord les § 1 à 3. Argo CD remettra le réplica (auto-réparation) : désactive l'auto-synchronisation de l'Application `chaos-mesh` le temps de l'incident, et note-le dans le ticket.
