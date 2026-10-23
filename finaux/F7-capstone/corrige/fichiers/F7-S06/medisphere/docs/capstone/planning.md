# Planning de la mise en service du GHSV

> PLAT-3706 (F7-S06). Auteur : équipe Plateforme. Relu par Nadia Roussel et Claire Morel.
> Hypothèse de notification : **vendredi 29 janvier 2027** (« fin janvier », §11.1 du CCTP). Si elle glisse, tout ce qui suit la notification glisse d'autant, **sauf** le 1er mars (fin de l'outil actuel) : voir R-01.
> **Engagé** = contractuel, annoncé au GHSV ; **interne** = notre organisation.

## 1. Jalons

| Date | Jalon | Nature | Dépend de |
|---|---|---|---|
| ven. 4 déc. 2026 | Remise de l'offre | engagé | phases 1 et 2 |
| 14-16 déc. 2026 | Soutenance et démonstration | engagé | phase 3 |
| lun. 4 janv. 2027 | **Début des travaux à nos risques** (développement lot 1, outil de reprise) | interne | accord de la direction (risque R-02) |
| déc. 2026 - janv. 2027 | Devis de matériel à validité courte, réservation du test d'intrusion et de la baie de PAR2 | interne | — |
| ven. 29 janv. 2027 | Notification (hypothèse) ; commande du matériel de PAR2 et de l'accès Internet de PAR2 ; lancement du recrutement | engagé / interne | GHSV |
| lun. 1er févr. | Réunion de lancement avec le GHSV ; demande des fournitures (nom de domaine, client OIDC, export d'essai, export des praticiens, DPI en recette) | engagé | — |
| ven. 5 févr. | Client OIDC enregistré chez le GHSV ; CNAME `rendez-vous(-recette).ghsv.example` posés | engagé (fourniture du GHSV) | GHSV (R-03) |
| ven. 12 févr. | **Recette ouverte au GHSV** (EXP-06 : 10 jours ouvrés avant la production) : API v1 complète (déplacement, filtres, annulation logique), fédération des agents, tests de contrat verts | engagé | lot 1, fédération |
| 8-19 févr. | Test d'intrusion PASSI sur la recette ; correction des critiques avant le 26 | interne | réservation de décembre |
| lun. 15 févr. | Reprise à blanc n° 1 (export d'essai du GHSV) | interne | export d'essai (R-04) |
| lun. 22 févr. | Reprise à blanc n° 2, chronométrée ; répétition de la bascule de la vague 1 | interne | — |
| ven. 26 févr., 14 h | **Go/no-go de la vague 1** (MédiSphère et GHSV) | engagé | critères §4 |
| sam. 27 févr., 20 h | Outil actuel en lecture seule, export final, reprise (≈ 4 h mesurées à blanc) | engagé | fournisseur actuel |
| dim. 28 févr. | Vérifications (comptes, rendez-vous futurs, échantillon par établissement), sondes vertes | interne | — |
| **lun. 1er mars 2027, 7 h** | **Vague 1 en service** : GHSV-01 à GHSV-05 (R-18) ; hypercare deux semaines (astreinte renforcée, point quotidien) | engagé | — |
| ven. 9 avr. | Premier rapport mensuel (mars) | engagé | NF-21 |
| lun. 12 avr. | Vague 2 : GHSV-06, 07, 08 | engagé | lot 2 (établissements, spécialités, plages) |
| avril (8 à 12 semaines après commande) | Livraison du matériel de PAR2 | interne | fournisseur (R-05) |
| ven. 30 avr. | PAR2 à pleine capacité (NF-08), essai de capacité à 300 req/s | engagé (réserve levée) | matériel |
| lun. 17 mai | Vague 3 : GHSV-09, 10 | engagé | — |
| sam. 5 juin, 22 h | **Premier test de PRA** en présence du GHSV (ENF-08) ; rapport avant le 21 juin | engagé | PAR2 complet |
| lun. 14 juin | Vague 4 : GHSV-11, 12 (EHPAD Les Tilleuls hors DPI : agendas tenus dans l'interface des agents) | engagé | — |
| mer. 30 juin 2027 | **Fin du déploiement** ; comité de pilotage de clôture du projet | engagé | — |

## 2. Lots de travail et chemin critique

| Lot | Contenu | Charge | Responsable |
|---|---|---|---|
| L1 API v1 conforme | filtres de `listerRendezVous`, `deplacerRendezVous`, annulation logique, authentification du DPI, tests de contrat | 20 j | Julien Petit |
| L2 Modèle hospitalier | établissements, spécialités, plages ouvertes, import quotidien du DPI (R-07) | 35 j | Julien Petit |
| L3 Reprise | outil de reprise, reprises à blanc, reprise finale | 15 j | Julien Petit + toi |
| L4 Identité | fédération des agents (`ghsv`), client `ghsv-dpi`, royaume `ghsv-patients`, reprise des comptes | 25 j | Karim Benali |
| L5 Locataire et plateforme | `equipes/ghsv.yaml`, overlay, clés, journaux, sondes, rapport mensuel, exposition Internet | 30 j | toi |
| L6 PAR2 | matériel, réseau, accès Internet, `k8s-par2`, capacité | 25 j | Karim Benali |
| L7 Fonctions complémentaires | rappels J-2, pièces jointes, règle des 24 h, statistiques, chiffrement applicatif, export de réversibilité | 60 j | Julien Petit |
| L8 Run | runbook d'exploitation RB-370, relecture de RB-371 à RB-374 (phase 3), astreinte, formation, recrutement | 15 j | Nadia Roussel |

**Chemin critique de la vague 1** : L1 (avant le 12 février) → recette ouverte → test d'intrusion et reprises à blanc → go/no-go du 26 février. Il passe par le **développement** et par trois **fournitures du GHSV** (client OIDC, export d'essai, DPI en recette), pas par l'infrastructure. L1 ne tient que si le travail commence le 4 janvier, avant la notification (R-02).

**Chemin critique des vagues 2 à 4** : L2 (modèle hospitalier) avant le 12 avril ; L6 (PAR2) avant le premier test de PRA.

**Ce qui ne sera pas prêt au 1er mars** (écrit dans l'offre comme plan de transition, pas découvert après) :
- PAR2 à pleine capacité : du 1er mars au 30 avril, le PRA du GHSV tient le RTO et le RPO mais avec une capacité réduite (≈ 100 req/s sur le nœud de repli actuel, H-A5) ; mesure transitoire : priorité au DPI et aux patients, interface des agents en mode dégradé.
- Pièces jointes et rappels J-2 (L7) : vague 2 ; d'ici là, rappels gérés par l'outil du GHSV pour les cinq établissements (à négocier) ou confirmation immédiate seulement.
- Statistiques mensuelles (EF-10) : premier export en avril.

## 3. RACI

R : réalise · A : approuve, rend compte · C : consulté · I : informé.

| Activité | Claire Morel | Toi (architecte, chef de projet technique) | Karim Benali | Julien Petit | Nadia Roussel | Sophie Laurent | Thomas Renaud | GHSV (Élodie Marchand) | Centre de services du GHSV |
|---|---|---|---|---|---|---|---|---|---|
| Pilotage du projet, comités | A | R | C | C | C | I | I | C | I |
| Développements L1, L2, L7 | I | C | C | A/R | I | C | C | C | I |
| Locataire, clés, journaux (L5) | I | R | A | C | I | C | I | I | — |
| Identité et fédération (L4) | I | C | A/R | C | I | C | C | R (son IdP) | — |
| PAR2 (L6) | A | C | R | — | I | I | — | I | — |
| Reprise des données (L3) | I | R | C | R | I | C | C | A (export, validation) | I |
| Test d'intrusion, correction | I | R | C | R | I | A | I | I | — |
| Go/no-go de chaque vague | A | R | C | C | C | C | I | A | I |
| Run : incidents P1-P3 | I | C | C | C | A/R | C | I | I | R (niveau 1) |
| Rapport mensuel | A | R | C | C | R | C | I | I (destinataire) | — |
| Test de PRA annuel | A | R | R | C | R | C | I | C (présent) | I |
| Incident de sécurité, information du GHSV | I | C | C | C | R | A | C | I (puis A de ses déclarations) | I |
| Réversibilité, destruction | A | R | C | C | I | C | C | A | — |

## 4. Critères du go/no-go de la vague 1 (26 février)

1. Tests de contrat de l'API v1 verts sur la recette ; DPI du GHSV en recette : création, déplacement, annulation et rapprochement réussis.
2. Agents de test du GHSV connectés par leur IdP, droits par groupe vérifiés, désactivation ≤ 15 min mesurée.
3. Reprise à blanc n° 2 : 100 % des rendez-vous futurs repris, écarts de l'historique < 0,1 % et expliqués, durée < 6 h.
4. Aucune vulnérabilité critique ouverte du test d'intrusion.
5. Sondes de disponibilité de production vertes depuis les deux points de mesure ; tableau du rapport mensuel alimenté.
6. Sauvegarde de la base du GHSV restaurée à blanc ; bascule vers PAR2 répétée (capacité transitoire).
7. Astreinte de l'hypercare constituée ; runbooks RB-370 (exploitation), RB-372 (identité fédérée) et RB-373 (contrat d'API) relus.

Un critère rouge = **no-go** : la vague 1 reste sur l'outil actuel si le fournisseur accepte une prolongation (à demander par le GHSV dès janvier, R-01) ; sinon, décision de la direction du GHSV sur une mise en service partielle.
