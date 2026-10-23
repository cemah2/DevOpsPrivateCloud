# Script de la démonstration — soutenance GHSV (45 min)

> Présentation et démonstration : 45 min ; questions : 30 min (S13). Démonstration attendue par le CCTP §12 : prise de rendez-vous par l'API sur la recette, connexion d'un agent par l'IdP du GHSV, tableau de bord des engagements. Orateurs : `<MOI>` (technique), Claire Morel (ouverture, coûts), Sophie Laurent (sécurité), Julien Petit (API).

## État de départ — liste de contrôle à T−30 min

| Contrôle | Commande ou écran | Attendu |
|---|---|---|
| Vérifications de la phase 3 | `lab/bin/check F7 7` à `F7 11` | tout vert |
| Aucune panne active | `ls ~/.local/state/workbook/pannes-actives/` | vide |
| Recette du client | `https://ghsv-recette.apps.par1.medisphere.internal/pret` | 200 |
| Jeton du DPI de démonstration | script `demo/jeton.sh` (client `ghsv-dpi-demo`) | jeton obtenu |
| Compte agent de test (`agent.demo1`) | connexion à blanc, OTP sur le téléphone de démonstration | accès |
| Tableaux ouverts | Pyrra (`ghsv-*`), Grafana « Client GHSV », rapport du mois | chargés |
| Plan B | captures et enregistrement vidéo du parcours complet de la veille, sur le portable de secours | présents, lus une fois |
| Charge de fond | `TestRun` `demo-ghsv` à 2 itérations/s | `started` |

## Déroulé

| Minute | Qui | Ce qu'on montre | Commande ou écran | Ce que le jury doit retenir | Plan B |
|---|---|---|---|---|---|
| 0:00-5:00 | Claire | le besoin du GHSV en trois chiffres, notre réponse en une phrase | diapositives 1-3 | nous avons compris le besoin | — |
| 5:00-12:00 | `<MOI>` | l'architecture : deux salles, un locataire isolé, l'API, l'identité, les clés | diapositives 4-8 (schéma de `architecture.md`) | chaque exigence a une décision et une preuve | — |
| 12:00-17:00 | Julien | **prise de rendez-vous par l'API** (recette) : jeton, créneaux, création, déplacement, liste du DPI | `demo/parcours-dpi.sh` (curl lisible, une étape par touche) | l'API v1 du GHSV est tenue, testée à chaque changement | vidéo du parcours (2 min) ; dire « voici l'enregistrement d'hier, même recette » |
| 17:00-20:00 | Julien | une MR qui casse le contrat est refusée | page de la MR fermée, job `contrat:ghsv` rouge | le DPI n'apprend jamais une rupture en production | capture de la MR |
| 20:00-25:00 | Sophie | **connexion d'un agent par l'IdP du GHSV** (MFA), refus d'un cadre, refus de nos outils internes | navigateur privé : `ghsv-agents-recette…` ; puis `grafana…` | aucun compte chez nous, aucun accès à nos outils | captures des trois écrans |
| 25:00-30:00 | `<MOI>` | **tableau de bord des engagements** : SLO, sonde, rapport du mois | Pyrra, rapport `ghsv-<AAAA-MM>.md` | chaque chiffre a sa requête | rapport en PDF |
| 30:00-35:00 | `<MOI>` | la journée de jeu : trois incidents, détection, réparation, minutes comptées | compte rendu S11 (chronologie, graphe de la sonde) | nous savons réagir, et nous le mesurons | — (document) |
| 35:00-39:00 | Sophie | clés dédiées et réversibilité : export, relecture, destruction de clé d'essai | compte rendu d'essai, procès-verbal d'essai | vos données vous reviennent, la destruction se prouve | — (document) |
| 39:00-43:00 | Claire | coût, planning, risques et ce que le GHSV fournit | `synthese-direction.md` | coût réaliste, risques dits | — |
| 43:00-45:00 | Claire | conclusion | — | « on ne promet rien qu'on ne sait pas mesurer » | — |

Transition vers les questions : « Tout ce que nous avons montré est dans le dossier, avec la preuve à côté. Nous avons aussi écrit ce que nous ne savons pas encore prouver. Nous vous écoutons. »

## Si un incident survient pendant la démonstration

1. Ne pas réparer en direct au-delà de 60 secondes : annoncer ce qu'on voit (« la sonde passe au rouge à 14 h 32 »), passer au plan B de l'étape.
2. Garder le tableau de la sonde ouvert : l'incident devient une démonstration de la détection.
3. Après la soutenance : compte rendu comme une journée de jeu (`docs/qualite/journees-de-jeu/`).

## Si le réseau ou l'identité tombent

- Réseau du lieu de soutenance : partage de connexion 4G préparé, VPN `wg1` testé la veille.
- IdP de démonstration indisponible : captures de la connexion d'agent, et le compte rendu de la révocation chronométrée.
