# Politique de budget d'erreur

| | |
|---|---|
| Ticket | PLAT-2227 (M21-E27) |
| Rédaction | Équipe Plateforme |
| Validée par | Claire Morel (infrastructure), Julien Petit (MédiAgenda), Nadia Roussel (support et astreinte) |
| S'applique à | les SLO de [`slo.md`](slo.md) : `mediagenda-disponibilite`, `mediagenda-latence`, `medidoc-disponibilite` |
| Révision | trimestrielle, et après tout incident qui consomme plus de 20 % d'un budget |

## 1. Principe

Un objectif de 99,5 % accepte 0,5 % d'échecs sur 28 jours : c'est le **budget d'erreur**. Tant qu'il en reste, l'équipe produit livre à son rythme ; quand il est épuisé, la fiabilité passe avant les nouveautés. Ce n'est pas une sanction : c'est la règle de décision dont on convient **avant** l'incident, pour ne pas la négocier pendant.

## 2. Qui est prévenu, quand

| Consommation (fenêtres courte ET longue) | Signification | Gravité | Qui |
|---|---|---|---|
| 2 % du budget en 1 h (facteur 14 ; 5 min et 1 h) | à ce rythme, budget épuisé en 2 jours | **critique** (disponibilité prod) | astreinte (Nadia), 24 h/24 |
| 5 % du budget en 6 h (facteur 7 ; 30 min et 6 h) | épuisé en 4 jours | **critique** (disponibilité prod) ; avertissement (latence) | astreinte / équipe |
| 10 % du budget en 1 j (facteur 2 ; 2 h et 1 j) | épuisé en 2 semaines | avertissement | équipe MédiAgenda, heures ouvrées |
| 100 % du budget sur la fenêtre (facteur 1 ; 6 h et 4 j) | épuisé à la fin de la fenêtre | avertissement | équipe MédiAgenda, revue hebdomadaire |
| plus de mesure (`SLOMetricAbsent`) | on ne sait plus | critique (prod) | astreinte |

La lenteur seule ne réveille personne, sauf si elle rend le service inutilisable (facteur 14). Les environnements hors production (`medidoc-recette`) ne réveillent jamais.

## 3. Ce qui se passe selon le budget restant (sur 28 jours)

| Budget restant | Décision | Décideur |
|---|---|---|
| > 50 % | livraisons normales (canary, analyses automatiques) | équipe produit |
| 25 à 50 % | livraisons normales ; le prochain sprint inclut au moins une action de fiabilité issue des incidents du mois | Julien Petit |
| < 25 % | **gel des fonctionnalités** en production : seuls les correctifs de fiabilité ou de sécurité partent, après revue de Karim Benali | Julien Petit + Karim Benali |
| épuisé | gel complet hors correctifs ; post-mortem obligatoire de chaque incident qui a consommé plus de 20 % ; point avec Claire Morel | Claire Morel |

Exceptions : un correctif de **sécurité** part toujours ; un incident d'un **fournisseur** hors de notre périmètre (réseau des centres de santé) reste compté (le patient ne fait pas la différence), mais n'ouvre pas de gel s'il est seul en cause : décision écrite de Claire Morel.

## 4. Limites connues

- SLI mesuré par l'application : la Gateway, le DNS ou le réseau en panne ne consomment pas le budget. La sonde blackbox de `mon01` couvre ce point de vue.
- La disponibilité « 28 jours » affichée par Pyrra porte au plus sur la rétention locale de Prometheus (voir `slo.md` et `dimensionnement.md`).
- Faible trafic la nuit : quelques erreurs suffisent à dépasser le facteur 14 sur 5 min ; la fenêtre d'1 h (et le `for` de 2 min) filtrent la plupart des faux positifs. Si une alerte nocturne se révèle injustifiée deux fois dans le mois, la revue d'alertes (politique d'alerte) la reprend.

## 5. Revue

Chaque lundi, l'équipe MédiAgenda lit l'interface `https://slo.apps.par1.medisphere.internal` (budget restant, tendance) ; le compte rendu mensuel des SLO est joint au comité HDS (Claire Morel).
