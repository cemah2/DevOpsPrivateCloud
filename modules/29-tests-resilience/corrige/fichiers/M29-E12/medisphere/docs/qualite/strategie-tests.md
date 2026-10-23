# Stratégie de tests de la plateforme MédiSphère

> `plateforme/medisphere` — `docs/qualite/strategie-tests.md` (M29-E12, PLAT-3012). Propriétaire : équipe Plateforme (Karim Benali). Revue : à chaque fin de trimestre et à chaque nouvel outil de test.
> Décision d'outillage : ADR-0290 (M29-E17). Procédures : RB-290 (charge), RB-291 (Goss), RB-292 (chaos, arrêt d'urgence), RB-293 (VMs de test orphelines).

## 1. Pourquoi ce document

Avant le module 29, la plateforme était « testée » par le fait que les choses passaient. Ce document dit **ce qu'on teste, quand, avec quoi, ce que ça coûte et qui en répond**, pour que chaque MR reçoive la bonne quantité de vérification : assez pour arrêter une erreur avant la production, pas au point de rendre chaque fusion lente et chère. Il dit aussi ce qu'on **ne** teste **pas**, et pourquoi.

## 2. La pyramide de la plateforme

```
                       ▲ coût, durée, réalisme
                      ╱ ╲
                     ╱ 5 ╲        Chaos, journées de jeu (recette)            trimestriel, annoncé
                    ╱─────╲
                   ╱   4   ╲      Charge k6 / k6-operator (recette)           chaque nuit + avant mise en prod
                  ╱─────────╲
                 ╱     3     ╲    Terratest (vraie VM), Testinfra (parc réel) manuel / chaque nuit
                ╱─────────────╲
               ╱       2       ╲  Molecule (rôle sur VM jetable), tofu test   MR qui touche le rôle / module
              ╱─────────────────╲
             ╱         1         ╲ Statique : lint, kubeconform+CRD, conftest, chaque MR, < 2 min
            ╱─────────────────────╲  opa test, kyverno test, promtool, helm-unittest
           ▼ nombre de tests, vitesse
```

| Étage | Ce qu'il prouve | Ce qu'il ne prouve pas |
|---|---|---|
| 1. Statique | Le fichier est bien formé, conforme au schéma de l'API **du cluster** (CRD comprises), respecte nos règles (registres, limites, VMID, pool, étiquettes, destructions) | Que l'objet fonctionne une fois appliqué ; l'admission réelle (Kyverno, VAP, PSA) reste la vérité |
| 2. Unitaire d'infrastructure | Un rôle converge et est idempotent sur une VM neuve ; un module produit le plan attendu (fournisseur simulé) | Le comportement sur le parc réel (données, voisins, réseau) |
| 3. Intégration | Une VM créée par le module démarre, répond en SSH, a ses étiquettes et son adresse NetBox ; le parc est dans l'état promis par les rôles | La tenue en charge, la résilience |
| 4. Charge | MédiAgenda tient le débit attendu **dans ses SLO** (95 % < 250 ms, 99,5 % sans erreur) | Ce qui se passe quand un composant tombe |
| 5. Chaos | Une hypothèse de résilience écrite (le service survit à la perte de X) tient, ou pas | L'absence de défaut (« on n'a rien cassé » ne prouve rien) |

## 3. Ce qui tourne quand

| Moment | Où | Tests | Durée cible | Bloquant |
|---|---|---|---|---|
| **Chaque MR** | dépôts concernés (composant `validation` v2.11.0 et jobs propres) | pre-commit, Gitleaks (`qualite`) ; `kubeconform -strict` avec le paquet `schemas-crd` ; `conftest` `rego/kubernetes` sur les rendus ; dans `plateforme/infra` : `conftest` `rego/tofu` sur chaque plan ; dans `plateforme/politiques` : `opa check --strict`, `opa fmt`, `opa test`, `conftest verify`, `kyverno test` ; `promtool test rules` ; `ansible-lint` ; `tofu test` des modules | < 3 min | **oui** |
| MR qui touche un rôle Ansible | `plateforme/ansible` | Molecule (scénario du rôle, VM 2045-2049) | 10-20 min | oui |
| MR qui touche `vm-debian` | `plateforme/tofu-modules` | compilation du test (`go vet`) ; **Terratest** manuel, lancé avant fusion par le relecteur | 8-12 min | job manuel obligatoire par règle d'équipe |
| **Chaque nuit** | `plateforme/ansible` (planifié `testinfra`) | Testinfra sur le socle (`ansible://socle`, `-n 4`) | 5 min | ticket si rouge |
| Chaque nuit | `plateforme/resilience` (k6-operator, palier 3) | non-régression de performance de MédiAgenda en recette | 10 min | ticket si un seuil est franchi |
| En continu | `mon01` | sondes Goss (essai), sondes blackbox | — | alerte (avertissement) |
| Avant une mise en production de MédiAgenda | recette | test de charge complet (`parcours-recette.js`), RB-290 | 20 min | oui (Go/No-Go de Julien) |
| Chaque trimestre | recette | journée de jeu (chaos), rapport dans `journees-de-jeu/` | ½ journée | — |
| Chaque montée de version d'un composant à CRD | `plateforme/k8s` | régénérer et publier `schemas-crd`, puis relever la version dans les consommateurs | 10 min | — |

## 4. Coûts

| Test | Coût d'une exécution | Coût de possession |
|---|---|---|
| Statique | secondes de CPU dans `ci-jobs` | faible : tenir les politiques à jour, régénérer `schemas-crd` |
| Molecule | une VM 1 Go 10-20 min | moyen : scénarios à maintenir avec les rôles |
| Terratest | une VM 1 Go, une adresse NetBox, 10 min, un VMID de la plage 2290-2299 | moyen : identité Proxmox dédiée, ménage des orphelines (RB-293) |
| Testinfra | quelques minutes de SSH sur le socle | faible à moyen : les tests suivent les rôles (une valeur change → un test change) |
| Charge | la recette est chargée 10 à 20 min ; MédiAgenda peut monter en réplicas (HPA) | moyen : scénarios, références, données factices |
| Chaos | une demi-journée de deux personnes ; un risque de vraie panne de recette | élevé : préparation, annonce, rapport, actions |

Règle : un test qui coûte plus qu'il n'attrape est supprimé ou déplacé d'étage (relu à la revue trimestrielle).

## 5. Ce qu'on ne teste pas (et pourquoi)

- **La production**, ni en charge ni en chaos : données de santé réelles, contrat HDS, aucun bénéfice que la recette ne donne pas à un coût acceptable. La recette doit donc **ressembler** à la production (mêmes versions, même topologie à l'échelle près).
- **Les composants amont eux-mêmes** (Cilium, CNPG, Argo CD…) : on teste **notre configuration** et **notre usage**, pas leur code.
- **L'exhaustivité** : on ne vise pas 100 % de couverture des rôles par Testinfra ; on teste ce qui casse ou ce qui coûte cher quand ça casse (accès, temps, supervision, sécurité).
- **Les performances des VMs du socle** : pas d'enjeu de charge mesuré aujourd'hui.

## 6. Propriétaires

| Ensemble | Propriétaire | Suppléant |
|---|---|---|
| Composant `validation`, `schemas-crd`, politiques Rego | Karim Benali | <MOI> |
| Testinfra, Molecule, rôles | <MOI> | Karim Benali |
| Terratest, modules OpenTofu | <MOI> | Karim Benali |
| Scénarios de charge, seuils | Julien Petit (MédiAgenda) avec la Plateforme | <MOI> |
| Chaos Mesh, journées de jeu | Karim Benali | Nadia Roussel (rapport, astreinte) |
| Revue trimestrielle de ce document | Claire Morel | — |

## 7. Quand un test est rouge

- **Bloquant de MR** : on ne force pas la fusion ; on corrige le code ou, si la règle est fausse, on corrige la règle **dans sa propre MR** (avec son test).
- **Nocturne** : le pipeline planifié échoue et ouvre un ticket ; le propriétaire le traite le jour ouvré suivant.
- **Faux positif** : une exception écrite (registre du M26 pour la sécurité ; commentaire daté dans la règle sinon), jamais une désactivation silencieuse.
