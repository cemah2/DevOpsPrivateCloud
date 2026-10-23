# GHSV-DSI-2026-014 — Questions des candidats et réponses du GHSV

> Publié le vendredi 20 novembre 2026 sur le profil d'acheteur, à l'attention de **tous** les candidats. Les questions sont reformulées et anonymisées par le GHSV. Ces réponses complètent le CCTP et s'imposent à toutes les offres.
>
> Document fictif (workbook MédiSphère). **À lire seulement après avoir terminé F7-S01** : il contient des réponses à des questions que tu dois d'abord trouver toi-même.

---

## Volumétrie et charge

**R-01 — Sur quoi repose la pointe de 150 requêtes par seconde (ENF-02) ?**
Elle a été mesurée en mars 2026 sur l'outil actuel (cinq établissements, pages web et API confondues, au point d'entrée du fournisseur actuel), puis multipliée par 2,5 pour l'ensemble du groupement. Le GHSV ne dispose pas d'une mesure plus fine ni de la répartition entre lectures et écritures. Le DPI interrogera l'opération `listerRendezVous` toutes les 5 minutes pour chaque praticien en consultation (environ 600 au plus fort de la matinée).

**R-02 — Le facteur 3 des campagnes de vaccination (ENF-09) s'applique-t-il à la pointe du lundi ?**
Non. Il s'applique au nombre quotidien de rendez-vous des **centres de vaccination**, qui représentent environ 20 % des rendez-vous du groupement en octobre. La pointe du lundi matin reste la référence ; les candidats en déduisent la pointe d'octobre.

**R-03 — Les données de l'établissement GHSV-12 (EHPAD Les Tilleuls) sont-elles exactes ?**
Non, erreur de saisie : **12 900** consultations externes en 2025 (et non 129 000). Le total réel de 2025 est donc de 1 683 900. Le GHSV **maintient** néanmoins la volumétrie de dimensionnement de 1,8 million de rendez-vous par an (ENF-01), qui intègre la croissance de 2026. Le nombre de praticiens (1 050 dans l'annexe A2, 1 150 au §1.1) : 1 150 est l'effectif total, 1 050 celui des praticiens qui ont des consultations externes.

**R-04 — Comment sont comptés les rendez-vous pour les lignes P2 et P3 du bordereau ?**
Rendez-vous **créés** au cours de l'année du marché (1er mars au 28 ou 29 février), annulations comprises, reprises de données exclues.

**R-05 — Combien de rappels par SMS faut-il prévoir (EF-06) ?**
Hypothèse du GHSV : 55 % des patients consentent au rappel par SMS ; un SMS par rendez-vous. Les courriels ne sont pas limités.

## Fonctionnel et interfaces

**R-06 — Les pièces jointes (EF-07) sont-elles transmises au DPI par l'API v1 ? Combien de temps sont-elles conservées ?**
L'API v1 de l'annexe A1 ne les transmet pas. Une version **1.1** de l'API (ajout d'opérations, sans modification des opérations existantes) sera définie avec le titulaire dans les six premiers mois du marché. D'ici là, les agents les consultent dans l'interface des agents. Durée de conservation chez le titulaire : **12 mois** après la date du rendez-vous (et non toute la durée du marché).

**R-07 — Quels identifiants de praticiens le DPI utilise-t-il ?**
L'identifiant interne du DPI, unique dans le groupement : `P` suivi de six chiffres (exemple : `P004217`). Les spécialités et les établissements d'un praticien sont fournis par un export quotidien du DPI (format CSV, décrit à la notification).

**R-08 — L'API FHIR (option 1) est-elle attendue dès la remise des offres ?**
Non. Les candidats chiffrent l'option ; une réponse « non proposée » est acceptée et n'est pas éliminatoire.

## Engagements de service

**R-09 — Comment la disponibilité est-elle mesurée en cas de désaccord (ENF-03, EXP-07) ?**
Le GHSV installera une sonde depuis son réseau. En cas d'écart, les parties analysent ensemble les deux mesures en comité de suivi. À défaut d'accord, la mesure du titulaire fait foi **si sa méthode a été présentée et validée en comité de suivi** avant le mois concerné.

**R-10 — L'exigence « aucune requête ne doit dépasser 1 seconde » (ENF-05) peut-elle être reformulée ?**
Oui. Le GHSV accepte une proposition du candidat portant sur un centile, à condition qu'elle soit mesurée et figure dans le rapport mensuel.

**R-11 — Comment concilier le RPO de 15 minutes (ENF-06) et l'exigence qu'aucun rendez-vous confirmé ne soit perdu (ENF-07) ?**
Les deux exigences sont **maintenues**. Le candidat décrit comment, en cas de sinistre, aucun rendez-vous confirmé à un patient n'est finalement perdu.

**R-12 — Les maintenances programmées peuvent-elles avoir lieu le samedi ?**
Oui, entre 22 h et 6 h, comme les autres jours. Les consultations du samedi matin (trois établissements) imposent qu'aucune maintenance ne déborde après 6 h.

## Sécurité et conformité

**R-13 — Le titulaire peut-il s'appuyer sur un hébergeur certifié pour l'activité 1 du référentiel HDS (ESC-01) ?**
Oui, s'il fournit les certificats de ses sous-traitants et la répartition des activités.

**R-14 — Que signifie « le GHSV doit pouvoir demander la révocation de ses clés » (ESC-06) ?**
Le GHSV veut pouvoir rendre ses données **définitivement illisibles** en cas de litige grave ou de compromission du titulaire, et obtenir la preuve de la destruction des clés. Il ne demande pas à détenir lui-même les clés (le GHSV n'a pas de module matériel de sécurité). Il sait qu'une révocation arrête le service.

**R-15 — Le prestataire de maintenance du DPI, à Tunis (ESC-12), doit-il accéder directement aux journaux ?**
Selon le GHSV, les journaux techniques de l'API ne contiennent pas de données de santé. Le candidat décrit les conditions dans lesquelles il peut donner cet accès, ou propose une alternative qui permette le même diagnostic.

**R-16 — Comment l'authentification multifacteur des agents (ESC-04) est-elle garantie ?**
Le fournisseur d'identité du GHSV impose la MFA à tous les agents ; c'est une responsabilité du GHSV. Le titulaire n'a pas à la vérifier, mais ne doit proposer aucun autre moyen d'authentification aux agents.

## Réversibilité

**R-17 — Les journaux doivent-ils être détruits sous 30 jours en fin de marché (ERV-04) alors qu'ils doivent être conservés un an (ESC-08) ?**
Les journaux sont inclus dans l'export de réversibilité. Le candidat précise dans son plan de réversibilité les données qu'il doit conserver au-delà de 30 jours pour ses propres obligations légales, leur durée et leur protection ; tout le reste est détruit sous 30 jours.

## Calendrier

**R-18 — Comment concilier la mise en service de tous les établissements au 1er mars 2027 (MES-01) et le déploiement par vagues (MES-02) ?**
**MES-01 est modifiée** : au 1er mars 2027, les cinq établissements qui utilisent l'outil actuel (GHSV-01 à GHSV-05) sont en service, avec la reprise de leurs données ; les sept autres sont déployés par vagues jusqu'au **30 juin 2027**.

## Questions sans réponse

Le GHSV ne répond pas aux questions portant sur les offres des autres candidats, sur le budget prévisionnel du groupement, ni sur l'architecture que les candidats devraient retenir.
