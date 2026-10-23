# Cellule de crise — PRA

| | |
|---|---|
| Ticket | PLAT-3507 |
| Propriétaire | Nadia Roussel |
| Runbook technique | RB-350 (bascule), RB-351 (retour) |
| Version | <AAAA-MM-JJ> — imprimée dans l'enveloppe (E12) |

## 1. Rôles

| Rôle | Titulaire | Suppléant | Fait | Ne fait pas |
|---|---|---|---|---|
| **Décision** | Claire Morel | Nadia Roussel | déclenche le PRA (critère de RB-350), décide du retour, arbitre les écarts au runbook, parle à la direction générale | ne tape aucune commande |
| **Pilotage** | Nadia Roussel | Karim Benali | tient le rythme (points de situation), répartit le travail, valide les conditions de passage, tient la main courante (ou la délègue au scribe) | n'exécute pas de vague elle-même |
| **Technique** (A et B) | <MOI> (clavier), Karim Benali (lecteur, revue technique) | Lucas Martin (B), Julien Petit (A pour MédiAgenda) | exécutent RB-350 à deux, relèvent les preuves | ne décident pas d'un écart au runbook seuls |
| **Validation métier** | Julien Petit | <dev MédiAgenda de garde> | confirme la reprise de MédiAgenda depuis un poste extérieur ; rejeu des rappels | — |
| **Communication** | Nadia Roussel (support) | Claire Morel | messages aux cabinets, bandeau, message vocal | ne promet pas d'heure non validée par le pilotage |
| **Observation** | Sophie Laurent | Thomas Renaud (DPO) en appui | relève heures et preuves (indépendante), évalue la notification (données de santé) | **n'agit pas** et n'aide pas |
| **Scribe** | Lucas Martin | — | main courante | — |

Une personne peut cumuler pilotage et communication, jamais **décision et clavier**.

## 2. Canaux (indépendants de PAR1)

| Usage | Canal principal | Secours |
|---|---|---|
| Cellule (voix) | pont téléphonique (numéro dans l'annuaire de crise, E11) | appels individuels |
| Cellule (écrit) | groupe de messagerie hors MédiSphère (application grand public chiffrée, groupe « PRA », membres de l'annuaire) | SMS |
| Main courante | `docs/pra/journal/<AAAA-MM-JJ>.md` sur `adm02` (miroir de `plateforme/medisphere`, commit toutes les 30 min) | papier, ressaisi ensuite |
| Cabinets | message vocal du standard, bandeau du site public (hébergé hors de PAR1), courriel depuis la messagerie d'entreprise externe | appels aux 20 plus gros cabinets (E11) |
| Direction | téléphone de Claire | SMS |

La messagerie de MédiSphère (Mailpit, `incidents@`) et la supervision sont **à PAR1** : elles n'existent plus pendant un PRA. Aucun canal ci-dessus ne dépend de PAR1.

## 3. Rythme

- **T+0** (décision) : ouverture de la cellule, rôles nommés, premier message aux cabinets dans les **30 min**.
- **Points de situation** toutes les **30 min** (10 min au plus) : où en est la vague, prochaine condition de passage, obstacles, prochaine communication.
- **Message d'état** aux cabinets toutes les **heures** tant que la reprise n'est pas faite, puis à la reprise, puis deux fois par jour en mode dégradé.
- **Direction** : à la décision, à la reprise, puis toutes les 2 h.

## 4. Main courante

Une ligne par entrée, horodatée en heure locale :

```
- HH:MM INC-6109 [type] texte
```

Types : `ouverture`, `décision`, `action`, `état`, `mesure`, `clôture`. Sont **obligatoirement** tracés : T0 ; la décision de déclencher (critère) ; chaque condition de passage franchie (avec la preuve) ; le point de non-retour (promotion de la base) ; toute dérogation au runbook ; T reprise (RTO) ; le RPO mesuré (témoin) ; chaque message envoyé (qui, à qui) ; la clôture.

## 5. Modèles de messages

**Cabinets — n° 1 (dans les 30 min)**
> MédiSphère — incident majeur en cours. La prise de rendez-vous en ligne (MédiAgenda) et l'accès aux documents (MédiDoc) sont indisponibles depuis HH:MM. Nos équipes activent notre site de secours. Merci de prendre les rendez-vous par téléphone et de noter ceux reçus depuis HH:MM. Prochain point : HH:MM.

**Cabinets — reprise**
> MédiAgenda est de nouveau disponible depuis HH:MM, en mode secours (temps de réponse plus longs possibles). Les rendez-vous pris en ligne entre HH:MM et HH:MM ont pu être perdus : nous vous transmettrons la liste des patients concernés dès qu'elle sera établie. Les rappels SMS de ce soir partiront avec du retard.

**Direction — point**
> Situation HH:MM : vague N/6, prochaine étape …, reprise de MédiAgenda estimée à HH:MM (RTO engagé : 4 h, soit HH:MM). Impact : … Décision attendue de vous : aucune / ….

**Autorités et clients (données de santé)** : si le RPO mesuré fait perdre des données de santé (rendez-vous, documents), Sophie et Thomas Renaud évaluent la notification de violation (RGPD art. 33 : 72 h) et l'information des établissements clients (obligation contractuelle HDS) ; le modèle est celui de la procédure d'incident de sécurité (F6). La cellule ne l'envoie pas d'elle-même.

## 6. Fin de crise

La crise se termine quand **toutes** les conditions sont réunies : services du périmètre repris à PAR2 (vague 4 faite pour les quatre services), communication de reprise envoyée, mode dégradé stable depuis 2 h, plan de retour (RB-351) daté. Claire prononce la fin (`[clôture]`) ; la cellule passe la main à l'équipe qui prépare le retour ; le rapport d'exercice ou d'incident est lancé (S13).
