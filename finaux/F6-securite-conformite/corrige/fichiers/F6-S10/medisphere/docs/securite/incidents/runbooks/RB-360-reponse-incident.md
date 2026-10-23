# RB-360 — Réponse à incident de sécurité

| | |
|---|---|
| Ticket | SEC-3610 (F6-S10) ; ferme ECA-3605 |
| Propriétaire | RSSI (Sophie Laurent) |
| Niveau | Procédure générale de réponse à incident de sécurité (au-dessus de RB-262) |
| Voir aussi | RB-262 (conteneur compromis, M26), RB-361 (forensique conteneur), RB-240 (bris de glace) |
| Dernier exercice | voir `exercices/` |

## 0. Objet et principes

Répondre à tout incident de sécurité (pas seulement un conteneur) : détecter, qualifier, confiner sans
détruire les preuves, investiguer, éradiquer, rétablir, décider des obligations réglementaires, apprendre.

1. **Isoler sans détruire** : une preuve perdue ne se recrée pas. On isole d'abord, on supprime en dernier.
2. **Tracer chaque geste** : dossier d'incident `docs/securite/incidents/INC-NNNN/` (chronologie
   horodatée UTC, preuves, décisions). Une ligne par entrée : `- HH:MM INC-NNNN [type] texte`.
3. **Décider sur preuves** : les obligations (CNIL, clients, signalement) se tranchent sur ce qui est
   **établi**, pas sur l'émotion de l'alerte.
4. **Sans recherche de coupable** : le post-mortem cherche des mécanismes.

## 1. Déclenchement

Déclenché par : une alerte de sécurité (Falco/Tetragon → Alertmanager, M26), un signalement humain, une
anomalie d'audit, une alerte d'un tiers. Toute personne qui constate déclenche ; en cas de doute, on
déclenche (un incident clos en faux positif ne coûte rien, un incident ignoré coûte cher).

## 2. Gravités

| Gravité | Définition | Points | RSSI/DPO |
|---|---|---|---|
| G1 critique | Données de santé **réelles** touchées ou accès production confirmé | toutes les 30 min | RSSI + DPO immédiatement |
| G2 majeur | Compromission confirmée sans accès établi aux données réelles | toutes les heures | RSSI immédiatement, DPO informé |
| G3 mineur | Activité anormale confinée (recette, bac à sable), portée limitée | à l'ouverture et à la clôture | RSSI informée |

La gravité peut monter ou descendre quand la portée se précise ; on l'écrit.

## 3. Rôles

| Rôle | Qui | Responsabilités |
|---|---|---|
| Responsable d'incident | astreinte Plateforme (hors heures), sinon Karim Benali | décide l'isolement, coordonne, tient la chronologie |
| Collecte | second membre Plateforme | preuves, empreintes, dépôt `preuves-conformite` (RB-361) |
| RSSI | Sophie Laurent | qualification, décision de violation, autorités |
| DPO | Thomas Renaud | décision CNIL / personnes, registre des violations (art. 33.5) |
| Communication | Claire Morel | direction, équipes, clients |
| Support | Nadia Roussel | impact client, tickets |

Contacts : annuaire d'astreinte (hors dépôt).

## 4. Déroulé

1. **Qualifier** (15 min) : vrai ou faux positif, quoi, où, depuis quand, quelle portée. Faux positif
   démontré → clôture motivée. Sinon → incident ouvert (`INC-NNNN`), gravité, RSSI (et DPO si G1/G2).
2. **Confiner sans détruire** : selon la nature. Conteneur → RB-262 (quarantaine, sortie du contrôleur).
   Hôte → isolement réseau. Compte → révocation. **Ne rien supprimer avant la collecte.**
3. **Collecter** : RB-361 pour un conteneur (ordre de volatilité, empreintes, dépôt verrouillé).
4. **Investiguer** : chronologie à partir des sources inaltérables (audit, Falco, Tetragon, Hubble) ;
   établir la portée (ce qui est prouvé / ce qui ne l'est pas).
5. **Éradiquer** : la cause, pas le symptôme (rotation des secrets exposés, correction par MR).
6. **Rétablir** : service propre, aucune nouvelle alerte pendant 24 h.
7. **Décider des obligations** (§5) et **apprendre** (§6).

## 5. Obligations réglementaires (décision RSSI + DPO)

On se pose la question **dès** qu'une donnée à caractère personnel a pu être touchée (confidentialité,
intégrité, disponibilité), et on tranche **sur preuves** :

- **Registre des violations (RGPD art. 33.5)** : dans **tous** les cas où une violation est constatée
  (et, en pratique, pour les événements analysés et écartés) — c'est la trace de la décision.
- **CNIL (art. 33)** : notification sous **72 heures** après en avoir pris connaissance, **sauf** si la
  violation n'engendre pas de risque pour les droits et libertés.
- **Personnes concernées (art. 34)** : information si **risque élevé**.
- **Clients responsables de traitement (contrat HDS)** : information pour qu'ils fassent leurs propres
  déclarations ; distinguer une **notification de violation** d'une **information « pour mémoire »**.
- **Signalement d'incident grave de sécurité d'un SI de santé (CERT Santé, art. L.1111-8-2)** : sans
  délai pour les incidents graves — **périmètre et circuit à vérifier sur Légifrance** à chaque revue.

Détail et rédaction : procédure de notification (F6-S13), modèles dans `docs/conformite/`.

## 6. Retour d'expérience

Post-mortem **sans recherche de coupable** sous 5 jours ouvrés (`post-mortems/` ou le dossier de
l'incident), cause racine en mécanisme, actions avec responsable et date, mise à jour des règles de
détection et de ce runbook. Présenté à la revue de suivi (F6-S14) et à l'auditeur HDS.
