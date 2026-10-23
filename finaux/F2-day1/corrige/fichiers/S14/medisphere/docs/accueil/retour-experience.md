# Retour d'expérience Day 1 et feuille de route de l'accueil

*Ticket : PLAT-3214. Rédigé par : <MOI>, avec Claire Morel. Personnes interrogées : Inès Garnier (MédiVisio), Hugo Bernard (Data), Marc Vidal (AxiomDev), Julien Petit, Sophie Laurent, Nadia Roussel. Date : <DATE>. Revue : dans un trimestre.*

## 1. Ce que nous voulions prouver

Qu'une équipe arrive, livre et repart **par la plateforme** et non par des tickets à la main : un changement relu pour créer l'équipe, un chemin balisé jusqu'à la production, des données utiles sans exposer la production, un tiers aux accès bornés et retirés sans trace.

## 2. Délais mesurés

| Parcours | Cible (offre de service) | Mesuré | Écart et cause principale |
|---|---|---|---|
| Création d'une équipe (MR → appliqué) | 1 jour ouvré | <DURÉE> | <CAUSE> (ex. synchronisation de la fédération Keycloak manuelle) |
| Premier déploiement en dev (MédiVisio) | 1 jour | <DURÉE> | <CAUSE> |
| Premier déploiement en prod (MédiVisio) | 1 semaine | <DURÉE> | <CAUSE> (fenêtre de synchronisation, quota de recette) |
| Base en libre-service + données (Data) | 2 jours | <DURÉE> | <CAUSE> (migration V5 à faire porter par MédiAgenda) |
| Arrivée d'un prestataire | 2 jours | <DURÉE> | <CAUSE> (première connexion SSO nécessaire avant GitLab) |
| Départ d'un prestataire (MR → contrôle vert) | 4 h | <DURÉE> | <CAUSE> |

## 3. Frictions et tickets

| Ticket | Équipe | Friction | Cause racine | Corrigé ? |
|---|---|---|---|---|
| DEV-3206 | MédiVisio | déploiement de recette bloqué (S06) | quota / image non signée / chemin OpenBao | oui : message d'erreur et doc du chemin balisé |
| DEV-3209 | Data | « accès en lecture à la prod » | besoin réel = données à jour dans une base à soi | oui : extraction pseudonymisée (ADR-0327) |
| SEC-3211 | AxiomDev | le prestataire voyait trop (S11) | <VARIANTE RENCONTRÉE> | oui : politique `rbac-prestataires`, revue d'accès |
| <PLAT-32XX> | <ÉQUIPE> | <FRICTION> | <CAUSE> | <ÉTAT> |

Interventions manuelles de la plateforme pendant l'accueil : <NOMBRE> ; les trois plus coûteuses : <LISTE>.

## 4. Satisfaction recueillie

Questionnaire de 5 questions (note de 1 à 5 + un commentaire libre), envoyé à chaque responsable une semaine après l'arrivée :

| Question | Inès (MédiVisio) | Hugo (Data) | Marc (AxiomDev) |
|---|---|---|---|
| Savais-tu à qui t'adresser et par quel canal ? | <N> | <N> | <N> |
| La documentation (offre de service, parcours, TechDocs) suffisait-elle ? | <N> | <N> | <N> |
| Délai jusqu'à ta première livraison / tes premières données | <N> | <N> | <N> |
| Les refus étaient-ils expliqués (quota, signature, accès prod) ? | <N> | <N> | <N> |
| Recommanderais-tu la plateforme à une autre équipe ? | <N> | <N> | <N> |
| Commentaire marquant | « <CITATION> » | « <CITATION> » | « <CITATION> » |

## 5. Ce qui a marché, ce qui n'a pas marché

- **Marché** : <POINTS> (ex. l'équipe en code : une MR, tout le reste suit ; le refus motivé de DEV-3209 a été accepté parce qu'une alternative existait le jour même).
- **N'a pas marché** : <POINTS> (ex. dépendance à la première connexion SSO ; messages de Kyverno peu lisibles pour une équipe ; capacité des travailleurs au plus juste).

## 6. Feuille de route trimestrielle (priorisée)

Priorité = valeur pour les équipes × fréquence ÷ effort ; P1 ce trimestre, P2 si la capacité le permet, P3 noté.

| Priorité | Action | Gain attendu | Effort | Responsable | Indicateur de réussite |
|---|---|---|---|---|---|
| P1 | Modèle Backstage `nouvelle-equipe` qui ouvre la MR sur `plateforme/equipes` (formulaire guidé) | création d'équipe sans connaître le format | 3 j | Plateforme | 100 % des créations par le modèle |
| P1 | Messages d'admission réécrits pour les équipes (Kyverno, Capsule, quotas) + page « pourquoi mon pod est refusé » | moins de tickets du type DEV-3206 | 2 j | Plateforme | tickets « déploiement bloqué » ÷ 2 |
| P1 | `ms-verif-equipe` dans la CI de `plateforme/equipes` (après application) et revue d'accès qui lit le modèle des prestataires | dérive vue le jour même | 1 j | Plateforme + Sophie | 0 écart `ext-*` à la revue |
| P2 | Ajout d'un travailleur (`k8s-w04` permanent) ou baisse des requests (VPA) avant la prochaine arrivée | marge de capacité > 20 % | 2 j | Claire (arbitrage) | bilan de capacité |
| P2 | Catalogue de données (extraction : dictionnaire des colonnes, règles d'usage) dans TechDocs | moins d'allers-retours avec Data | 1 j | Data + Julien | — |
| P2 | Showback envoyé automatiquement aux responsables (MR + message) | équipes conscientes de leurs requests | 1 j | Plateforme | efficacité réservé/utilisé > 40 % |
| P3 | Base Data à deux instances si elle porte des résultats non reconstructibles | RTO | 1 j | Data | — |
| P3 | Évaluer vCluster pour un futur prestataire qui demanderait des CRD | isolation plus forte | 3 j | Plateforme | ADR |

## 7. Décisions demandées

- À Claire : arbitrage capacité (P2 travailleur) ; passage du showback au chargeback ou non.
- À Sophie : validation de la règle « un prestataire = un groupe `ext-*` daté, aucune appartenance héritée » comme standard (RB-329).
