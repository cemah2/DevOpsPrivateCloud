# Capacité du cloud OpenStack — octobre 2026

> Pour Claire Morel. Chiffres collectés le 2026-10-24 par `ms-capacite-openstack` (`plateforme/outils`) ; données brutes archivées. Valeurs du lab de référence, **indicatives**. Relance : `ms-capacite-openstack -d ~/capacite/2026-11 > brut.md`, puis mise à jour de ce modèle.

## En une phrase

Le calcul est la ressource rare : **6 Go de mémoire allouable restent libres** (6 instances `m1.petit` ou 3 `m1.moyen`), au rythme actuel il sera plein **mi-décembre** ; le stockage a de la marge (moins de 15 % du brut utilisé). Recommandation : réserver dès maintenant la mémoire d'un troisième calcul (8 Go) dans le budget du premier trimestre, ou plafonner les quotas de `mediagenda-dev`.

## 1. Calcul

Trois notions à ne pas confondre :
- **capacité allouable** (Placement) : ce que Nova peut promettre = (total − réservé) × ratio d'allocation ;
- **allocations** : ce qui est promis aux instances existantes (gabarits) ;
- **consommation réelle** : ce que les instances utilisent vraiment sur les hyperviseurs.

| Hôte | vCPU alloués / allouables (ratio 4.0) | Mémoire allouée / allouable (ratio 1.0, 1 Go réservé à l'hôte) | Mémoire réellement utilisée par la VM |
|---|---|---|---|
| `oscmp01` | 6 / 16 | 4 096 / 7 168 Mo | 5,1 Go / 7,8 Go |
| `oscmp02` | 4 / 16 | 4 096 / 7 168 Mo | 4,6 Go / 7,8 Go |
| **Total** | **10 / 32** | **8 192 / 14 336 Mo** | — |

Lecture : les vCPU ne limitent pas (ratio 4, charges peu actives) ; la **mémoire** limite (ratio 1 : on ne promet jamais plus que la mémoire physique, sinon la VM imbriquée de 8 Go échange et tout ralentit). Marge : 6 144 Mo allouables = **6 `m1.petit`** (1 Go) ou **3 `m1.moyen`** (2 Go) ou **1 `m1.grand`** (4 Go), à condition de rester en dessous de ~85 % de la mémoire réelle des VMs de calcul (chaque instance consomme ~10 % de plus que son gabarit : QEMU, tables de pages).

## 2. Projets

| Projet | Instances | vCPU utilisés / quota | Mémoire utilisée / quota | Volumes utilisés / quota | Heures vCPU (1-24 oct.) |
|---|---|---|---|---|---|
| `plateforme` | 2 | 2 / 8 | 2 048 / 8 192 Mo | 2 / 50 Go | 410 |
| `mediagenda-dev` | 3 | 3 / 8 | 3 072 / 8 192 Mo | 5 / 100 Go | 290 |
| `mediagenda-prod` | 2 | 4 / 8 | 4 096 / 8 192 Mo | 0 / 100 Go | 180 |
| **Somme des quotas** | | **24** vCPU | **24 576 Mo** | 250 Go | |

Les quotas additionnés (24 Go) dépassent la capacité allouable (14 Go) : c'est **voulu** (tous les projets n'utilisent pas leur quota en même temps), mais c'est le premier projet qui atteindra son quota… ou la capacité. Une équipe peut recevoir « No valid host » sans avoir atteint son quota.

## 3. Stockage (`ceph-par1`, 3 copies)

| Pool | Stocké | Brut utilisé (× 3) | Disponible |
|---|---|---|---|
| `images` | 3,1 Gio | 9,3 Gio | 119 Gio |
| `volumes` | 1,8 Gio | 5,4 Gio | 119 Gio |
| `vms` | 6,7 Gio | 20,1 Gio | 119 Gio |
| `backups` | 0,9 Gio | 2,7 Gio | 119 Gio |

Brut : 52 Gio utilisés sur 576 Gio (9 %), dont 37 Gio pour OpenStack. Seuil `nearfull` de Ceph à 85 % : marge ≈ 430 Gio bruts ≈ 140 Gio de données nouvelles. Volumes : **7 Go provisionnés** dans Cinder, **1,8 Gio réellement écrits** (allocation fine) — la marge réelle dépend de ce que les équipes écriront, pas de ce qu'elles ont demandé : surveiller l'écrit, pas le provisionné.

## 4. Tendance et projection

Deux mesures (2026-10-10 et 2026-10-24) : +3 072 Mo alloués en 14 jours (instances de recette de MédiAgenda). À ce rythme : capacité mémoire allouable atteinte vers le **2026-12-12**. Le stockage n'est pas un sujet avant 2027.

## 5. Recommandation

1. **Court terme** (gratuit) : quota de mémoire de `mediagenda-dev` ramené à 6 Go ; destruction automatique des environnements de recette inutilisés (pipeline `detruire` planifié le vendredi soir).
2. **Premier trimestre 2027** : troisième nœud de calcul (8 Go de RAM et 4 vCPU sur `pve01`, à arbitrer avec les autres profils du lab — sur du matériel réel : un serveur de calcul supplémentaire).
3. Mesure mensuelle avec `ms-capacite-openstack`, seuil d'alerte à 80 % de la mémoire allouable (module 21).

## 6. Ce que ce rapport ne mesure pas

- La surcharge de la **virtualisation imbriquée** (les calculs sont des VMs de `pve01`) : performances et mémoire réelle différentes d'un serveur physique.
- `pve01` est partagé avec le socle et les autres profils du lab : la capacité « réelle » du cloud dépend de ce qui tourne à côté.
- Les pics (mesure ponctuelle, pas de séries temporelles avant le module 21).
- Le réseau (débit des IP flottantes, passerelle unique sur `osctl01`).
