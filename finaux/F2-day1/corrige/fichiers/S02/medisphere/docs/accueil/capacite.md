# Capacité des travailleurs et budgets des équipes (Day 1)

> Relevé du `<AAAA-MM-JJ>` (F2-S02, PLAT-3202). Mis à jour à chaque arrivée d'équipe et à chaque relevé trimestriel. Les valeurs entre `<…>` sont **tes** mesures : l'exemple ci-dessous est celui de la solution de référence et doit être remplacé.

## Méthode

```
admin@adm01:~$ kubectl describe nodes -l '!node-role.kubernetes.io/control-plane' | grep -A8 'Allocated resources'
admin@adm01:~$ kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o custom-columns=NOM:.metadata.name,CPU:.status.allocatable.cpu,MEM:.status.allocatable.memory
admin@adm01:~$ kubectl top nodes
admin@adm01:~$ kubectl get globalresourcequotas -o custom-columns=NOM:.metadata.name,DEMANDE:.status.total.used
admin@adm01:~$ ssh root@pve01 'free -g | head -2'
```

On compare ce qui est **réservé** (somme des *requests* des pods posés sur les travailleurs) à ce qui est **allouable** (capacité moins ce que le kubelet et le système se gardent). L'utilisation réelle (`kubectl top`) dit si les *requests* sont réalistes ; elle ne sert pas au calcul (l'ordonnanceur ne regarde que les *requests*).

## Relevé (exemple de la solution de référence)

| Travailleur | Allouable CPU | Allouable mémoire | *Requests* CPU | *Requests* mémoire | Marge CPU | Marge mémoire |
|---|---|---|---|---|---|---|
| `k8s-w01` | `<3800m>` | `<9.1Gi>` | `<2650m>` | `<6.4Gi>` | `<1150m>` | `<2.7Gi>` |
| `k8s-w02` | `<3800m>` | `<9.1Gi>` | `<2550m>` | `<6.2Gi>` | `<1250m>` | `<2.9Gi>` |
| `k8s-w03` | `<3800m>` | `<9.1Gi>` | `<2600m>` | `<6.4Gi>` | `<1200m>` | `<2.7Gi>` |
| **Total** | `<11400m>` | `<27Gi>` | `<7800m>` | `<19Gi>` | `<3600m>` | `<8Gi>` |

`k8s-w03` porte la marque `dedie=bdd:NoSchedule` (M14) : les pods des équipes n'y vont que s'ils la tolèrent (bases CNPG). Sa marge mémoire ne sert donc qu'aux bases (Data, F2-S07).

Hôte : `pve01` a `<N>` Go libres avec le profil de travail (≈ 111 Go engagés sur 128) ; **aucune** VM ne peut être ajoutée pour les équipes (PLAN §4.14 : F2 n'ajoute rien), d'où des budgets prélevés sur la marge des travailleurs.

## Règle d'engagement (ADR-0320)

- Un **budget** (GlobalResourceQuota du locataire) est un plafond de *requests* : une promesse, pas une réservation.
- **CPU** : on promet jusqu'à **1,5 ×** la marge (le CPU est compressible : en cas de contention, les conteneurs ralentissent, la production en `medisphere-critique` passe devant).
- **Mémoire** : jamais plus que la marge (**1,0 ×**) : une promesse mémoire non tenue, c'est un pod `Pending` ou un OOM.
- **N-1** : perdre un travailleur sur trois n'est pas absorbable dans le lab (il faudrait garder un tiers de l'allouable libre) ; c'est écrit comme risque, accepté par Claire Morel pour le lab, et devrait être une réserve explicite en production réelle.

## Budgets accordés

| Équipe | CPU | Mémoire | Pods | Détail |
|---|---|---|---|---|
| `medivisio` | 2,5 | 3 Gi | 45 | dev 0,5 / 768 Mi ; recette 0,5 / 768 Mi ; prod 1 / 1 Gi ; libre-service 0,5 / 512 Mi |
| `data` | 2 | 3,5 Gi | 30 | traitements 1,5 / 3 Gi (base CNPG + lots) ; libre-service 0,25 / 512 Mi |
| **Total** | **4,5** (plafond 5,4) | **6,5 Gi** (plafond 8 Gi) | | AxiomDev (F2-S10) n'a pas de locataire : son espace est pris sur le budget de `mediagenda` |

`outils/capacite.py` de `plateforme/equipes` refait ce calcul à chaque MR (bloquant) à partir de `config/plateforme.yaml`, qui recopie ce relevé.

## Risques et suivi

- Les *requests* réelles de MédiVisio sont des estimations : relire les recommandations du VPA (`Off`) après une semaine de trafic de recette, et ajuster le budget par MR.
- Un budget non consommé est de la capacité gelée : revue trimestrielle (consommation par locataire, F2-S08).
- Alerte à poser (plateforme) : somme des *requests* > 85 % de l'allouable sur un travailleur pendant 30 min.
