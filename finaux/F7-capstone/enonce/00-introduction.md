# Final F7 — Introduction : répondre au GHSV

## Lundi 26 octobre, 9 h 10

Le courriel est arrivé à 8 h 02, depuis le profil d'acheteur d'un groupement hospitalier que personne chez MédiSphère n'avait encore approché. Claire Morel l'a transféré à 8 h 05, avec trois lignes et une pièce jointe de trente pages.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel
> **Objet** : TR: Consultation GHSV-DSI-2026-014 — prise de rendez-vous en marque blanche
>
> Bonjour,
>
> Le Groupement hospitalier Seine-et-Vallées (douze établissements, 1,8 million de rendez-vous par an) cherche un hébergeur pour sa prise de rendez-vous en ligne, raccordée à son DPI et à son annuaire. Élodie Marchand, leur DSI, a publié le cahier des charges ce matin. Offres le 4 décembre, soutenance mi-décembre, démarrage le 1er mars 2027.
>
> La direction veut y aller avec MédiAgenda et **notre** plateforme. Je te confie la réponse technique, de bout en bout : comprendre leur besoin, concevoir ce qu'il faudrait vraiment en production, chiffrer, planifier, monter une preuve de concept dans le lab et la défendre devant un jury. Karim relit l'architecture, Sophie la sécurité et la conformité, Julien tout ce qui touche à l'API, Nadia le run. Je relis le chiffrage et le planning.
>
> Une seule règle, et je serai intraitable : **on ne promet rien qu'on ne sait pas mesurer**. Chaque chiffre de notre offre doit avoir une source (une mesure de notre plateforme, une hypothèse écrite, ou un devis), et chaque engagement doit avoir sa méthode de mesure. Si on ne sait pas tenir une exigence, on le dit, on propose autre chose, et on le chiffre.
>
> Claire

---

## Ce que tu construis dans ce final

À la fin de F7, MédiSphère a remis une offre défendable au GHSV et l'a soutenue, preuve de concept à l'appui. L'étiquette `capstone-v1` de `plateforme/medisphere` est posée en F7-S14.

| Phase | Fichier | Scénarios | Ce qui en sort | Durée indicative |
|---|---|---|---|---|
| 1. Comprendre le besoin | [`01-besoin.md`](01-besoin.md) | S01-S02 | analyse du cahier des charges, questions au client, exigences non fonctionnelles chiffrées et traçables | 7 à 9 h |
| 2. Concevoir | [`02-concevoir.md`](02-concevoir.md) | S03-S06 | architecture de production sur deux sites, ADR, chiffrage sur cinq ans, planning, risques, organisation du run | 17 à 22 h |
| 3. Livrer | [`03-livrer.md`](03-livrer.md) | S07-S11 | le client en code dans le lab (locataire `ghsv`), identité fédérée, contrats d'interface testés, engagements mesurés, démonstration sous incidents | 22 à 29 h |
| 4. Soutenir | [`04-soutenir.md`](04-soutenir.md) | S12-S14 | dossier et support de soutenance, questions du jury, recette `capstone-v1` | 7 à 10 h |

Les phases 1 et 2 sont des **rédactions** : elles ne touchent à rien de ce qui tourne. Elles produisent pourtant les décisions que la phase 3 met en œuvre et que la phase 4 défend. Ne les bâcle pas : un jury pardonne une démonstration qui hoquette, pas un chiffre qu'on ne sait pas justifier.

Un final ne réenseigne rien : il **combine** tout le workbook. Tu t'appuies sur ce que tu as construit et mesuré : SLO de MédiAgenda (M21), charge k6 et non-régression (M29), sonde de continuité (F4), reprise sur PAR2 et RTO/RPO mesurés (F5), audit, preuves et écarts (F6), équipe en code (F2).

---

## Les règles du capstone (valables pour chaque scénario)

1. **Tout ce qui est promis est mesurable.** Un engagement (« 99,9 % », « RPO 15 min », « 95 % sous 300 ms ») est écrit avec : sa définition exacte, son point de mesure, sa méthode de calcul (requête ou outil), sa fréquence, et l'endroit où on lira le résultat. Sans méthode de mesure, ce n'est pas un engagement, c'est un vœu.
2. **Chaque chiffre a une source.** Trois sources possibles, et une seule à la fois : une **mesure** de ta plateforme (cite-la : fichier, `testid`, rapport, date), une **hypothèse** écrite et identifiée (`H-nn`), ou un **devis** (que tu n'as pas : dans ce final, les prix sont des ordres de grandeur d'octobre 2026, marqués « à vérifier »).
3. **On distingue le lab et la production.** Le lab est une maquette fidèle de l'architecture, pas de la capacité ni de l'exposition. Chaque fois que tu transposes une mesure du lab à la production, écris le facteur et sa justification.
4. **On dit non quand il faut.** Une exigence intenable, contradictoire ou mal posée se signale (question au client, réserve dans la réponse), elle ne se promet pas en silence. Une réserve argumentée fait gagner des points ; une promesse intenable fait perdre le marché, ou pire, le gagner.
5. **Tout par le code et par MR**, comme dans le reste du workbook : documents dans `plateforme/medisphere`, relus par MR (Karim pour l'architecture, Sophie pour la sécurité, Claire pour le chiffrage et le planning).
6. **Le GHSV est un client, pas une équipe interne.** Ses données de santé, ses clés, ses journaux et ses agents sont **isolés** de ceux de MédiSphère et des autres clients, et cette isolation se démontre.

> ⚠️ **Attention** : la phase 3 crée un nouveau locataire dans le cluster de **production** du lab (`k8s-par1`), un royaume dans Keycloak et des clés dans OpenBao. Rien de ce que fait ce final ne doit toucher aux données, aux clés ou aux accès de MédiAgenda, MédiDoc, MédiVisio ou Data. Sauvegardes vérifiées avant chaque changement (même règle qu'au F4), aucune panne active d'un autre final.

---

## État d'entrée

| Élément | État attendu | Contrôle |
|---|---|---|
| Plateforme | Finaux F1 à F6 terminés : étiquettes `day0-v1`, `day1-v1`, `astreinte-v1` (si fait), `changements-v1`, `pra-v1`, `conformite-v1` sur `plateforme/medisphere` | `lab/bin/check F6 14` |
| PAR2 | Site de repli du F5 en veille : `hp01` (Proxmox VE à côté de PBS), `adm02`, `dns03`, `s3-02`, `reg02`, `k8s-par2` (applications à 0 réplica), `mediagenda-db-par2` en réplica continu | `lab/bin/check F5 14` |
| Mesures disponibles | Référence de charge de MédiAgenda (`plateforme/resilience`, `charge/references/mediagenda-recette.json`, M29-E14) ; SLO Pyrra `mediagenda-disponibilite` et `mediagenda-latence` (M21) ; sonde de continuité et mesures des changements (F4, `docs/changements/`) ; rapport de l'exercice de PRA (F5, `docs/pra/exercices/2026-exercice-1/rapport.md`) ; rapport d'écarts et plan de remédiation (F6, `docs/conformite/`) | lecture |
| Pannes | Aucune panne active (`ls ~/.local/state/workbook/pannes-actives/` vide), aucune expérience de chaos en cours | — |
| Mémoire | Profil de travail des blocs F et G (≈ 111 Go) ; PAR2 en veille sur `hp01` | — |

**Ce qu'est MédiAgenda dans le lab.** L'application du dépôt (`apps/mediagenda`) est une **API** : créneaux, rendez-vous (création, lecture, liste, annulation), choix de rappel (M27). Dans la fiction, MédiSphère vend aussi l'interface web des patients et celle des secrétariats ; elles **n'existent pas dans le lab**. La preuve de concept de la phase 3 porte donc sur l'API, l'identité, l'isolation, les clés, les engagements mesurés et la reprise, pas sur des écrans. Ton analyse doit le savoir : lis le code de `apps/mediagenda` (et les évolutions des modules : `rappel` au M27) avant de dire ce que la solution sait faire.

**Les certifications de MédiSphère, hypothèses du final.** Pour ce final, on pose : MédiSphère est certifiée HDS v2 pour les **activités 2 à 6** ; ses deux salles (PAR1, PAR2) sont dans des centres de données d'hébergeurs eux-mêmes certifiés HDS pour l'**activité 1** ; l'audit de certification ISO/IEC 27001:2022, qui suit l'audit à blanc du F6, est programmé en **janvier 2027**. Ces faits viennent de Sophie Laurent ; tu peux les utiliser, mais pas les embellir.

---

## Le calendrier et ses contraintes

| Date | Événement |
|---|---|
| lundi 26 octobre 2026 | publication de la consultation (cahier des charges : [`ressources/S01/`](../ressources/S01/)) |
| vendredi 13 novembre 2026, 12 h | date limite des questions écrites au GHSV (S01) |
| vendredi 20 novembre 2026 | réponses du GHSV, publiées à tous les candidats ([`ressources/S02/reponses-aux-candidats.md`](../ressources/S02/reponses-aux-candidats.md) : à lire **après** avoir terminé S01) |
| vendredi 4 décembre 2026, 12 h | remise des offres (fin des phases 1 et 2, preuve de concept démontrable) |
| 14 au 16 décembre 2026 | soutenance : 45 min de présentation, 30 min de questions (S12, S13) |
| fin janvier 2027 | notification prévisionnelle |
| lundi 1er mars 2027 | début du marché |

Ces dates sont celles de la fiction : tu feras le final à ton rythme. Garde-les pourtant comme contrainte de raisonnement : le planning (S06) doit tenir entre la notification et le 1er mars 2027, et ce qui ne tient pas doit être dit.

---

## Conventions du final

**Documentation** (dépôt `plateforme/medisphere`, par MR) :

| Chemin | Contenu | Scénario |
|---|---|---|
| `docs/capstone/analyse-cdc.md` | analyse du cahier des charges : périmètre, hors périmètre, hypothèses, écarts entre le besoin et ce que fait la solution, incohérences | S01 |
| `docs/capstone/questions-client.md` | questions écrites au GHSV | S01 |
| `docs/capstone/exigences.md` | exigences non fonctionnelles chiffrées, mesurables et traçables | S02 |
| `docs/capstone/architecture.md` | architecture cible de production et dimensionnement | S03 |
| `docs/capstone/adr/ADR-0370-<sujet>.md`, `ADR-0371-…` | décisions d'architecture du final | S04 |
| `docs/capstone/chiffrage.md` et `docs/capstone/chiffrage.csv` | chiffrage et coût complet sur cinq ans, comparaisons | S05 |
| `docs/capstone/planning.md`, `risques.md`, `run.md` | planning de la notification au déploiement, registre des risques, organisation du run | S06 |
| `docs/capstone/soutenance/` | dossier et support de soutenance | S12 |

**Identifiants** (les checks les comptent) :

| Objet | Format | Exemple |
|---|---|---|
| Exigence du cahier des charges | celle du GHSV : `EF-nn`, `ENF-nn`, `ESC-nn`, `ERV-nn`, `EXP-nn`, `MES-nn` | `ENF-03` |
| Question au client | `Q-nn` | `Q-07` |
| Hypothèse | `H-nn` | `H-04` |
| Exigence non fonctionnelle de MédiSphère (ta reformulation mesurable) | `NF-nn` | `NF-01` |
| Risque (registre de S06) | `RSQ-nn` | `RSQ-12` |
| Réponse du GHSV aux candidats (S02) | `R-nn`, fixé par le GHSV | `R-11` |
| Décision d'architecture | `ADR-037x` (`ADR-0370` à `ADR-0379`) | `ADR-0372` |
| Runbook du final | `RB-370…` | — |

**Tickets** : `PLAT-37xx` (plateforme) et `DEV-37xx` (développement), `xx` = numéro du scénario.

**Objets du lab** (phase 3, détaillés dans [`03-livrer.md`](03-livrer.md)) : locataire `ghsv` déclaré dans `plateforme/equipes` (`equipes/ghsv.yaml`), espaces `ghsv-recette` et `ghsv-prod`, `https://ghsv.apps.par1.medisphere.internal` et `https://ghsv-recette.apps.par1.medisphere.internal`, clés `transit/ghsv-*` d'OpenBao, royaume Keycloak `ghsv-idp` sur `idp01` (le fournisseur d'identité **simulé** du GHSV), déclaré comme fournisseur d'identité (alias `ghsv-idp`) dans le royaume `medisphere`. VMID 3700-3799 réservés à tes essais ; aucune VM n'est imposée.

**Jury** (S13) : Claire Morel, Sophie Laurent, Karim Benali et Élodie Marchand, DSI du GHSV (personnage fictif, comme tout le groupement).

---

## Variables de `lab/lab.env`

Toutes facultatives : les défauts conviennent au lab.

| Variable | Défaut | Utilisée par |
|---|---|---|
| `WB_F7_DOC` | `docs/capstone` | tous les checks |
| `WB_F7_PROJET_DOC` | `plateforme/medisphere` | tous les checks |
| `WB_F7_MIN_QUESTIONS` | `10` | S01 (questions au client) |
| `WB_F7_MIN_EXIGENCES` | `15` | S02 (exigences `NF-nn`) |
| `WB_F7_TRACABILITE_MIN` | `0.8` | S02 (part des exigences ENF et ESC du cahier des charges reprises) |
| `WB_F7_MIN_ADR` | `4` | S04 |
| `WB_F7_MIN_RISQUES` | `10` | S06 |

Les scénarios de la phase 3 en ajoutent (voir leurs énoncés). Les checks relisent aussi `WB_GITLAB_*` et `WB_TIMEOUT`. Les checks des phases 1, 2 et 4 vérifient la **présence et le contenu minimal** des documents (sections, identifiants, cohérence de quelques chiffres) ; leur **qualité** se juge avec le corrigé. Outils sur `adm01` : `curl`, `jq`.

---

## Pour commencer

Lis le cahier des charges en entier, une première fois sans prendre de notes, comme le ferait Élodie Marchand en le relisant avant publication. Puis ouvre [`01-besoin.md`](01-besoin.md).
