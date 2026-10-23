# RB-340 — Lancer la sonde de continuité et relever la mesure

| | |
|---|---|
| Quand | avant, pendant et après chaque changement normal ou standard du trimestre |
| Durée | 5 min avant, 5 min après |
| Prérequis | `k6-operator` sain (espace `k6`), sondes `continuite-*` vertes sur `mon01`, tableau `f4-changement-en-cours` |

## 1. Avant la fenêtre (T - 40 min)

```
admin@adm01:~/src/resilience$ outils/sonde-continuite.sh demarrer CHG-34XX 4h   # testid sonde-continuite-CHG-34XX
admin@adm01:~/src/resilience$ outils/sonde-continuite.sh etat          # ETAPE : started
```

- Ouvre le tableau « Changement en cours » sur les 30 dernières minutes : 0 seconde d'erreur, toutes les sondes vertes, charge active ≈ 3 req/s.
- Note dans la fiche : heure de début de la ligne de base (30 min de calme).
- Si la ligne de base n'est pas à 0 : **no-go** tant que la cause n'est pas comprise (on ne mesure pas un changement sur un fond d'erreurs).

## 2. Pendant

- Le tableau reste ouvert sur l'écran de l'exécutant ; le relecteur surveille les critères d'abandon de la fiche.
- Chaque étape est notée avec son heure dans le journal de la fiche : la courbe se lit ensuite étape par étape.

## 3. Après (T fin + 30 min)

```
admin@adm01:~/src/observabilite$ outils/mesurer-interruption.sh <MESURE-DEBUT> <MESURE-FIN>
admin@adm01:~/src/observabilite$ outils/mesurer-interruption.sh <FIN> <FIN+30min>     # « après »
admin@adm01:~/src/resilience$ outils/sonde-continuite.sh arreter
```

Reporte dans l'en-tête de la fiche `mesure-debut`, `mesure-fin`, `mesure-interruption-s` (la valeur « secondes d'erreur cumulées ») et remplis le tableau §10 (avant, pendant, après).

## 4. Sans le cluster (k8s-par1 arrêté, F4-S08)

Pas de charge k6 ni de Prometheus du cluster : source `temoin`, et seulement les groupes de sondes pertinents (`mesure-groupes`) :

```
admin@adm01:~/src/observabilite$ outils/mesurer-interruption.sh <DEBUT> <FIN> temoin 'continuite-openstack.*'
```

## 5. Si la sonde elle-même tombe

- TestRun en `error` ou disparu : `outils/sonde-continuite.sh etat`, événements des Jobs dans `k6` (quota, image, admission) ; relance avec le même `CHG-34XX` (les compteurs repartent de zéro : `rate` et `increase` le gèrent).
- Sondes de `mon01` muettes : alerte `CibleTemoinInjoignable` (M21) ; la mesure de la fenêtre perd sa couverture : la fiche le dit (la couverture est affichée par l'outil et contrôlée par les checks).
