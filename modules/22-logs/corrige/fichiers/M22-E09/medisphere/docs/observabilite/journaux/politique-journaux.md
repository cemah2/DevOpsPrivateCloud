# Politique des journaux de MédiSphère

> Propriétaire : équipe Plateforme. Validée par Sophie Laurent (RSSI). Version 1 : M22-E09 (SEC-2309).
> Les sections 2 (rétentions et effacement), 3 (accès) et 4 (sauvegarde) sont ajoutées par M22-E13 et M22-E16.

## 1. Données de santé et données personnelles

### 1.1 La règle

**Aucune donnée personnelle de patient n'entre dans Loki.** Ni nom, ni prénom, ni date de naissance,
ni NIR, ni adresse de courriel ou de téléphone d'un patient, ni contenu de document. Un journal sert à
comprendre ce que fait un système, pas qui est soigné.

Deux lignes de défense, dans cet ordre :

1. **Les applications ne journalisent pas de données personnelles** (contrat des applications,
   `apps/README.md`) : on journalise des **identifiants techniques** (`rdv_id`, `request_id`, plus tard
   `trace_id`), jamais la donnée. C'est la seule défense complète : elle est vérifiée en revue de code
   et par des tests (« pas de donnée patient dans le journal », `tests/test_api.py` de MédiAgenda).
2. **La collecte masque ce qui passe quand même** (exception non rattrapée, bibliothèque bavarde,
   erreur humaine) : étape `loki.process "masquage"` d'Alloy, **dernière** étape avant l'envoi, sur
   toutes les sources (pods, journald des nœuds et des VMs, audit, événements).

### 1.2 Ce que la collecte masque (Alloy, M22-E09)

| Motif | Remplacé par | Remarque |
|---|---|---|
| NIR (13 chiffres + clé, espaces ou points facultatifs, Corse 2A/2B) | `[NIR-MASQUE]` | bornes de mot : un nombre plus long (horodatage en ns) n'est pas touché |
| adresse de courriel **hors** `medisphere.internal` | `[COURRIEL-MASQUE]` | les adresses de service (`astreinte@`, `plateforme@`…) restent lisibles |
| valeur des champs JSON `patient`, `nom`, `prenom`, `nom_patient`, `nom_naissance`, `date_naissance`, `telephone` | `[MASQUE]` | liste convenue avec les équipes : un nouveau champ nominatif se déclare ici d'abord |

Limites assumées, écrites pour ne tromper personne :

- un **nom en texte libre** (« patient Jeanne Martin ») n'est pas reconnaissable par une expression
  régulière : seule la ligne de défense n° 1 le traite ;
- un faux positif (un numéro de 15 chiffres qui ressemble à un NIR) est masqué : on préfère perdre une
  information technique que garder une donnée de santé ;
- le masquage s'applique à la **ligne** ; les métadonnées structurées posées par Alloy ne contiennent
  que des identifiants techniques (liste fermée : `pod`, `stream`, `niveau`, `request_id`, `unite`,
  champs de l'audit).

### 1.3 Vérification

- en continu : le contrôle `lab/bin/check 22 09` (motifs recherchés dans tous les locataires sur 1 h) ;
- à chaque changement de la configuration d'Alloy : le pod témoin `wb-essais/temoin-donnees`
  (`ressources/E09-temoin`) écrit des valeurs **factices** ; ses lignes doivent arriver masquées ;
- en revue de code des applications : refus de toute ligne de journal qui contient une donnée patient.

### 1.4 Si une donnée personnelle est trouvée dans Loki

C'est un **incident de sécurité** (ticket `SEC-`, Sophie Laurent prévenue le jour même) :
1. corriger la source (application ou masquage) et le vérifier avec le témoin ;
2. demander la suppression des lignes concernées par l'API de suppression de Loki (M22-E13), dans le
   locataire touché, sur la plage de temps exacte ;
3. consigner dans le registre des incidents : quoi, depuis quand, qui a pu le lire (journal d'audit de
   Grafana et de l'API Kubernetes).

## 2. Rétentions et effacement

*(M22-E13)*

## 3. Accès aux journaux

*(M22-E16)*

## 4. Sauvegarde

*(M22-E16)*
