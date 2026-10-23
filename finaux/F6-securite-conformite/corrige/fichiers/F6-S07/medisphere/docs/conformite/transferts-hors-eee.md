# Cartographie des transferts et accès hors EEE

> SEC-3607 / ECA-3606 (F6-S07). Établie par Thomas Renaud (DPO) avec la Plateforme et le support ; **validée par le DPO le 2026-11-25** ; revue annuelle et à chaque nouveau fournisseur ou accès. La synthèse (§ 4) est publiée sur le site de MédiSphère, comme l'exige le référentiel HDS ; le détail est communiqué aux clients dans le contrat d'hébergement.

## 1. Questions posées pour chaque ligne

1. Des données (de santé, ou personnelles) **quittent-elles** l'EEE (stockage, traitement, sauvegarde, support) ?
2. Quelqu'un **accède-t-il** aux données ou à la plateforme **depuis un pays tiers** (même sans copie) ?
3. Le fournisseur, ou sa société mère, est-il **soumis à une loi extra-européenne** qui pourrait l'obliger à communiquer des données (accès des autorités) ?

Une seule réponse « oui » suffit pour que la ligne figure, avec ses garanties et ses mesures.

## 2. Inventaire

| Fournisseur ou accès | Usage | Données | Pays (stockage / accès) | Loi extra-européenne | Q1 | Q2 | Q3 | Base et garanties | Mesures | Décision |
|---|---|---|---|---|---|---|---|---|---|---|
| DataCampus | colocation PAR1/PAR2 (activité 1) | aucune donnée lue ; accès physique aux baies fermées | France | non | non | non | non | contrat, certificat HDS activité 1 | baies fermées, liste d'accès tenue par MédiSphère | **hors cartographie** (aucun transfert) ; suivi fournisseur |
| HelpNow (SaaS de tickets) | support des clients | demandes des clients ; **captures d'écran de dossiers patients** jointes par certains cabinets ; noms et contacts des professionnels | Allemagne (Francfort) ; société mère aux États-Unis | **oui** (société mère américaine) | non (stockage UE) | possible (support de l'éditeur) | **oui** | contrat de sous-traitance RGPD de l'éditeur, clauses contractuelles types pour son support | **interdiction** des pièces jointes contenant des données de santé (consigne, filtre de pièces jointes de l'outil, message automatique aux cabinets) ; purge des pièces existantes ; journal des accès de l'éditeur demandé | **à réduire** : plus aucune donnée de santé dans l'outil ; données des professionnels seulement ; étude d'un outil hébergé en UE par une société européenne (décision de la direction, 2027-T1) |
| SMS-Express | envoi des rappels de MédiNotif | numéro de téléphone du patient, date et heure, nom du praticien (donnée de santé indirecte : le fait d'avoir rendez-vous chez un spécialiste) | Irlande ; rapports de remise traités par un sous-traitant aux États-Unis | **oui** (sous-traitant) | **oui** (rapports de remise : numéro et statut) | non | oui | contrat de sous-traitance, clauses contractuelles types avec le sous-traitant, à vérifier | texte du SMS **minimisé** (ni spécialité ni motif : « rappel de votre rendez-vous du … à … ») ; demande de désactivation des rapports détaillés hors UE | **accepté sous conditions**, information des clients |
| Registres publics (Docker Hub, ghcr.io, quay.io) | téléchargement d'images et de charts par les caches de Harbor | aucune donnée envoyée (requêtes de téléchargement, adresse IP de sortie de MédiSphère) | États-Unis | oui | non | non | sans objet (aucune donnée) | — | images recopiées et vérifiées (M13) ; aucune donnée de la plateforme ne sort par ce flux (bordure) | **hors cartographie** des transferts de données ; dépendance d'approvisionnement suivie (5.21) |
| Messagerie d'entreprise | SI interne (hors périmètre) | règle : aucune donnée de santé par courriel | UE ; éditeur américain | oui | non | non | oui | contrat de l'éditeur | règle rappelée dans la charte ; filtre de contenu sur les pièces jointes vers l'extérieur | **hors périmètre** ; risque de contournement suivi (une donnée de santé reçue par courriel est un incident à déclarer) |
| Astreinte depuis le Maroc | un ingénieur du support assure l'astreinte deux semaines par an depuis le Maroc, par le VPN | accès d'administration à la plateforme (donc, potentiellement, aux données de santé) | Maroc (pays tiers, sans décision d'adéquation) | non | non | **oui** | **non** | — | **suspendu** depuis le 2026-11-20 : l'astreinte se fait depuis l'EEE ; tout accès d'administration depuis un pays tiers est refusé (contrôle : géolocalisation des adresses VPN dans la revue mensuelle) | **refusé** ; s'il était maintenu, il faudrait l'écrire au contrat de chaque client et le publier |

## 3. Ce qui est dit aux clients

- Les données de santé sont hébergées **exclusivement en France** (PAR1, PAR2) ; aucune copie hors EEE.
- Deux prestataires peuvent être concernés par une loi extra-européenne : l'outil de tickets (aucune donnée de santé ne doit y figurer : règle et filtrage décrits) et le prestataire SMS (données minimisées, rapports de remise) ; risques et mesures décrits dans l'annexe « Sous-traitants » du contrat d'hébergement.
- Aucun accès d'administration depuis un pays tiers.

## 4. Synthèse publiée (site de MédiSphère)

> **Transferts de données hors de l'Espace économique européen** — MédiSphère héberge les données de santé de ses clients exclusivement dans ses deux sites en France. Aucune donnée de santé n'est transférée hors de l'EEE. Deux prestataires de MédiSphère appartiennent à des groupes soumis à une législation extra-européenne : notre outil de gestion des demandes du support (hébergé en Allemagne ; il ne doit contenir aucune donnée de santé) et notre prestataire d'envoi de SMS de rappel (hébergé en Irlande ; les messages ne contiennent ni spécialité ni motif). Aucun accès d'administration à la plateforme n'a lieu depuis un pays tiers. Mise à jour : 2026-11-27.

## 5. Révision

| Date | Changement | Validation |
|---|---|---|
| 2026-11-25 | première version (audit à blanc, ECA-3606) | Thomas Renaud |
