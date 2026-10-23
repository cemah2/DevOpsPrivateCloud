# Recette Day 1 — accueil des équipes

*Ticket : PLAT-3213. Date : <DATE>. Recette menée par : <MOI>. Témoins : Claire Morel, Sophie Laurent. Étiquette : `day1-v1` sur `plateforme/medisphere`.*

## Ce qui est recetté

L'engagement de l'offre de service (`offre-de-service.md`) : **une équipe se crée en un changement relu, reçoit ses droits par ses groupes, ses quotas, un chemin balisé jusqu'à la production, et repart sans laisser de traces**. Trois arrivées le prouvent : MédiVisio (équipe produit), Data (bases et lots en libre-service), AxiomDev (prestataire, parti en fin de final).

## Conformité des équipes (`ms-verif-equipe`)

Outil : `plateforme/outils`, `bin/ms-verif-equipe` (tests : `tests/ms-verif-equipe/lancer.sh`, job `test:ms-verif-equipe` ; contrôle quotidien : pipeline planifié `conformite-equipes`).

```
admin@adm01:~/src/outils$ bin/ms-verif-equipe medivisio
<COLLER LA SORTIE>
admin@adm01:~/src/outils$ bin/ms-verif-equipe data
<COLLER LA SORTIE>
admin@adm01:~/src/outils$ bin/ms-verif-equipe ext-axiomdev
<COLLER LA SORTIE : après le départ, « annuaire KO : groupe vide » est ATTENDU>
```

| Équipe | Annuaire | Keycloak | GitLab | Locataire | Argo CD | OpenBao | Grafana | Alertes | Catalogue | SLO |
|---|---|---|---|---|---|---|---|---|---|---|
| medivisio | OK | OK | OK | OK | OK | OK | OK | OK | OK | OK (service en prod) |
| data | OK | OK | OK | OK | OK | OK | OK | OK | OK | non exigé (pas de service en prod) |

## Délais mesurés

| Mesure | Valeur | Source |
|---|---|---|
| Création d'une équipe (MR ouverte → tout appliqué) | <DURÉE> | pipelines de `plateforme/equipes` (S02) |
| MédiVisio : du modèle `nouveau-service` au premier déploiement en dev | <DURÉE> | S04, horodatages du projet et d'Argo CD |
| MédiVisio : premier déploiement en dev → production | <DURÉE> | S05 |
| Data : demande → base sauvegardée et première extraction chargée | <DURÉE> | S07 |
| AxiomDev : arrivée (MR) → premier commit sur `mediagenda/api` | <DURÉE> | S10 |
| AxiomDev : départ (MR) → contrôle final vert | <DURÉE> | S12, `departs/axiomdev.md` |
| Interventions manuelles de la plateforme pendant ces parcours | <NOMBRE> (liste en annexe) | journal des scénarios |

## Vérifications du workbook

`lab/bin/check F2 13` (relance S02, S04, S05, S07, S08, S11, S12) : vert le <DATE>.

## Réserves et suites

- <RÉSERVE> (ex. le dossier Grafana de l'équipe n'est pas visible du compte de vérification : droit ajouté par l'équipe en code, MR !<N>).
- Feuille de route : `retour-experience.md` (S14).
