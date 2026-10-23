# ADR-0374 — Réversibilité : export ouvert, vérifié par un tiers, destruction prouvée

| | |
|---|---|
| Statut | **Accepté** (<DATE>) |
| Décideurs | Claire Morel, Thomas Renaud (DPO), Sophie Laurent (RSSI), Julien Petit |
| Ticket | PLAT-3704 (F7-S04) |
| Exigences | ERV-01 à ERV-05, ESC-08, ESC-06 ; réponse R-17 |
| Complète | ADR-0371 (clés dédiées) |

## Contexte

En fin de marché (ou à la demande du GHSV), MédiSphère doit livrer sous 30 jours un export complet en format ouvert et documenté, utilisable par un tiers sans nos outils (ERV-02), l'avoir essayé en année 3 (ERV-03), puis tout détruire sous 30 jours, sauvegardes et copies de PAR2 comprises (ERV-04), en conservant ce que nos obligations exigent (R-17). Un export « qu'on fera le moment venu » est un export qui ne marche pas le moment venu.

## Décision

1. **Format** : une archive par export, chiffrée (`transit/ghsv-exports`, clé remise au GHSV par un canal séparé), manifeste signé (`transit/ghsv-signature`), déposée dans le compartiment dédié `ghsv-reversibilite`, contenant :
   - `rendez-vous.jsonl` (un rendez-vous par ligne, schéma JSON fourni, **mêmes champs que l'API v1**, annulés compris avec leur statut et leur date) et `rendez-vous.csv` (même contenu, UTF-8, séparateur virgule, RFC 4180) ;
   - `patients.jsonl` (comptes sans mot de passe ni secret OTP, consentements, dates) ;
   - `pieces-jointes/` (fichiers d'origine, noms = identifiant + extension) et `pieces-jointes.csv` (rattachement, type, taille, SHA-256) ;
   - `journaux/` (journaux d'accès et d'administration du locataire `ghsv`, format JSON Lines, sur la période conservée) ;
   - `MANIFESTE.sha256` (empreinte de chaque fichier), `LISEZMOI.md` (description, schémas, correspondance avec l'API A1 et la spécification OpenAPI) ;
   - **pas** de sauvegarde PostgreSQL : un dump n'est pas un format ouvert utilisable sans PostgreSQL et sans connaître notre schéma.
2. **Outil** : `ms-reversibilite` dans `plateforme/outils` (construit en F7-S07, procédure RB-371 « Réversibilité et fin de contrat d'un client ») (même conventions que les outils `ms-*`), lancé par un pipeline protégé, qui lit la base par un rôle en lecture et les objets du locataire, déchiffre les champs (`transit/ghsv-donnees`), écrit l'archive et son manifeste. Il ne s'exécute jamais sur la production pendant les heures de pointe.
3. **Vérification par un tiers** : chaque essai (annuel, pas seulement en année 3) est rechargé par l'équipe Data (qui ne connaît pas le schéma) dans une base vide avec la **seule** documentation de l'archive ; écarts corrigés dans l'outil ou la documentation. Mesures : durée de l'export, volumes, nombre d'enregistrements comparé à la base, nombre de questions posées par le tiers.
4. **Destruction** (ERV-04) : après validation de l'export par le GHSV : suppression des espaces, bases, compartiments et du royaume `ghsv-patients` à PAR1 et PAR2 ; **destruction des clés** `transit/ghsv-*` (ADR-0371), qui rend illisibles les sauvegardes, WAL archivés et copies hors site qu'on ne peut pas effacer sélectivement ; procès-verbal daté (actions, horodatages des journaux d'audit, empreintes des preuves).
5. **Conservé au-delà de 30 jours** (R-17), écrit dans le plan de réversibilité : journaux de sécurité et d'administration de **notre** plateforme qui mentionnent le GHSV, pseudonymisés (aucune donnée de patient), jusqu'à leur échéance d'un an (traçabilité HDS, preuves d'audit) ; documents contractuels et rapports mensuels (sans donnée de santé), selon les durées légales.

**Preuve de concept du lab** (F7-S07) : `ms-reversibilite` est lancé depuis `adm01` par une personne du groupe `ghsv` (politique `ghsv-reversibilite`, sans `decrypt`), pas encore par un pipeline protégé (rôle JWT et runner qui joint la base : cible de production) ; aucun champ chiffré à déchiffrer (pas de `transit/ghsv-donnees` dans le lab) ; ni comptes de patients, ni pièces jointes, ni journaux dans l'archive (`patients.jsonl`, `pieces-jointes/` et `journaux/` sont déclarés absents dans son manifeste : le lab n'a ni royaume `ghsv-patients` ni pièces jointes) ; la relecture est faite par toi dans une VM jetable (VMID 3701), pas par l'équipe Data.

## Options étudiées

| Option | Pour | Contre | Décision |
|---|---|---|---|
| Dump PostgreSQL + copie du compartiment | rapide à produire | non « ouvert » pour un tiers sans PostgreSQL ni notre schéma ; champs chiffrés illisibles | **écartée** |
| Format FHIR (Bundle d'`Appointment`) | standard de santé | l'option FHIR n'est pas dans la tranche ferme ; un repreneur n'a pas forcément d'outil FHIR ; à ajouter si l'option 1 est retenue | **écartée en v1** |
| **JSON Lines + CSV + fichiers + manifeste** | lisible par n'importe quel outil, vérifiable, aligné sur l'API v1 | outil à développer et à maintenir avec le schéma | **retenue** |
| Destruction « une copie à la fois » (sans destruction de clés) | pas de dépendance aux clés | impossible à prouver pour les sauvegardes dédupliquées (PBS), les WAL archivés et les copies verrouillées (F6) | **écartée** |

## Conséquences

- Développement : `ms-reversibilite` (≈ 8 jours en production, au-delà de la preuve de concept) et son test de rechargement ; maintenance à chaque migration de schéma de MédiAgenda (le test d'export entre dans la CI).
- Les essais annuels coûtent ≈ 3 jours (export, rechargement par un tiers, rapport) : inclus dans le prix (S05).
- Dépendance assumée de la destruction aux clés : la gestion des clés (ADR-0371) devient une exigence de réversibilité.

## Révision

Si l'option FHIR est retenue (ajout d'un export FHIR) ; après chaque essai ; à la demande du repreneur désigné par le GHSV.
