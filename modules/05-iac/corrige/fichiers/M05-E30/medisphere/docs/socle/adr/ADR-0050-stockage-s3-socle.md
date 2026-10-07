# ADR-0050 — Garder SeaweedFS comme stockage S3 du socle, avec une sortie préparée

- Statut : accepté
- Date : 2026-10-XX
- Décideurs : Claire Morel (responsable infrastructure), équipe Plateforme
- Consultés : Karim Benali (standards), Sophie Laurent (RSSI), Nadia Roussel (exploitation)
- Remplace : le choix implicite de MinIO (PLAN, conception du bloc A)

## Contexte et problème

Le socle a besoin d'un stockage objet S3 : aujourd'hui pour l'état OpenTofu (`tofu-state`, verrou
natif `use_lockfile`, M05-E11/E12), demain pour MédiDoc, les sauvegardes Velero (module 16) et,
peut-être, un datastore S3 de PBS. MinIO, prévu à l'origine, a cessé d'être une option libre :
plus de binaires ni d'images de l'édition communautaire depuis octobre 2025, console retirée de
l'édition libre, dépôt archivé en février 2026 ; seule l'offre commerciale (AIStor) continue. Un
fork communautaire (`pgsty/minio`, février 2026) republie des binaires.

SeaweedFS a été installé en urgence sur `s3-01` (M05-E10). Avant que d'autres projets en
dépendent, il faut confirmer ce choix contre les alternatives, dire à quelles conditions on le
reverrait, et préparer la sortie : l'abandon de MinIO a montré qu'un composant libre peut
disparaître en quelques mois.

## Facteurs de décision (pondération)

| # | Facteur | Poids | Pourquoi |
|---|---|---|---|
| F1 | Écritures conditionnelles (`If-None-Match: *` sur PutObject) | éliminatoire | Sans elles, le verrou `use_lockfile` ne protège rien, sans erreur visible |
| F2 | Versionnage des objets | éliminatoire | Seul retour arrière rapide d'un état écrasé ou supprimé (M05-E29) |
| F3 | Licence libre et gouvernance | 3 | Ne pas revivre MinIO : qui décide, qui peut changer la licence (CLA ?) |
| F4 | Maintenance active, délai de correction des failles | 3 | Composant exposé au lab entier, porteur des états de toute l'infrastructure |
| F5 | Empreinte (2 vCPU, 2 Go, une VM) | 2 | Budget mémoire du socle (PLAN §3.3) |
| F6 | Simplicité d'exploitation (installation par rôle Ansible, mise à jour, sauvegarde) | 2 | Équipe de quatre, astreinte de premier niveau |
| F7 | Compatibilité S3 pour les usages à venir (multipart, cycle de vie, politiques) | 2 | MédiDoc, Velero |
| F8 | Réversibilité (sortie en moins d'une journée) | 2 | Leçon de MinIO |

## Options envisagées

1. **SeaweedFS** (Apache 2.0), mode serveur unique sur `s3-01`.
2. **Garage** (AGPL 3.0, association Deuxfleurs).
3. **Versity Gateway** (`versitygw`, Apache 2.0) : passerelle S3 devant un système de fichiers POSIX.
4. **RustFS** (Apache 2.0) : réécriture en Rust, version 1.0 en septembre 2026.
5. **Ceph RGW** (LGPL) : la passerelle objet de Ceph, qui arrive au module 08.
6. **Fork communautaire de MinIO** (`pgsty/minio`, AGPL 3.0).
7. **État OpenTofu géré par GitLab** (backend `http` de la forge), sans stockage S3 pour l'état.

## Comparaison

Légende de vérification : **T** = vérifié par test (date, version) ; **D** = documentation
officielle (lien) ; **?** = non vérifié.

| Critère | SeaweedFS 4.48 | Garage | Versity GW | RustFS 1.0 | Ceph RGW | Fork MinIO | État GitLab |
|---|---|---|---|---|---|---|---|
| F1 If-None-Match | ✅ **T** (412 au second PUT, script E12, 2026-10) | ❌ <résultat de ton essai, VM 2057> ; aucune mention dans la matrice de compatibilité S3 **D** | <résultat de ton essai> ou **?** | <résultat de ton essai> ou **?** | à tester sur la version du M08 ⇒ **?** | hérité de MinIO **D**, non testé | sans objet (verrou HTTP de GitLab **D**) |
| F2 Versionnage | ✅ **T** (`get-bucket-versioning` Enabled, restauration E29) | ❌ **D** (« Garage does not (yet) support object versioning ») | annoncé (POSIX, attributs étendus) **?** | annoncé **?** | ✅ **D** | ✅ **D** | historique des versions d'état **D** |
| F3 Licence / gouvernance | Apache 2.0 ; un mainteneur principal + une société (édition entreprise) | AGPL ; association, financements publics | Apache 2.0 ; une société | Apache 2.0 ; une société, très jeune | LGPL ; fondation (Linux Foundation), nombreux contributeurs | AGPL ; une petite équipe tierce, sans lien avec MinIO Inc. | (CE MIT) ; dépend de la forge |
| F4 Maintenance | versions fréquentes (4.4x en 2026) | active | active | 1.0 depuis trois semaines | très active, cycle long | incertaine (rétroportages ?) | suit GitLab |
| F5 Empreinte | <mémoire mesurée sur `s3-01` : `ps -o rss= -C weed`> | faible | faible (passerelle) | faible | lourde (MON, MGR, OSD : plusieurs Go, 3 nœuds pour la redondance) | faible | nulle (déjà là) |
| F6 Exploitation | un binaire, rôle Ansible (M05-E10) | un binaire, simple | un binaire + un FS | un binaire | cephadm, compétences dédiées (M08) | un binaire, paquets tiers | rien à exploiter |
| F7 Usages à venir | bon (multipart, politiques) | bon, sans versionnage | partiel | annoncé large | complet | complet | **aucun** (état seulement) |
| F8 Réversibilité | objets S3 standard | — | — | — | — | — | export par API, autre format de backend |

Les cellules **?** ne pèsent pas dans la décision : un critère non vérifié n'est pas un argument.
Les cellules `<…>` sont à remplir avec tes propres mesures et essais (version testée, date) : un
ADR exemplaire ne recopie pas un résultat qu'il n'a pas obtenu. Garage n'a pas de versionnage
(documentation), ce qui l'élimine de toute façon (F2), quel que soit le résultat de F1.

## Décision

Option retenue : **1, SeaweedFS**, en serveur unique sur `s3-01`, parce que c'est la seule option
qui satisfait **aujourd'hui et par test** les deux critères éliminatoires (F1, F2), avec une
licence permissive, une empreinte compatible avec le socle et une exploitation à la portée de
l'équipe. Ceph RGW est la cible naturelle quand le besoin de redondance apparaîtra (module 08) ;
l'état géré par GitLab est écarté parce qu'il lierait l'état à la disponibilité de la forge et ne
servirait aucun autre usage.

Mesures qui accompagnent la décision :
- **Le test des écritures conditionnelles** (`outils/s3-tester-ecriture-conditionnelle.sh`, E12) est
  rejoué **après chaque montée de version** de SeaweedFS, avant de rendre la main.
- **Versionnage, sauvegarde nocturne PBS de `s3-01` et copie externe des états** (E29) : la perte du
  stockage n'emporte pas l'état.
- **Identités par usage** : `tofu-etat` (compartiment `tofu-state` seul), une identité par futur
  consommateur ; `admin-s3` en bris de glace.
- Version figée dans le rôle Ansible `seaweedfs`, montée de version par MR (même procédure que les
  providers, `docs/socle/iac.md`).

## Conditions de révision (indicateurs observables)

La décision est revue, par un nouvel ADR, si **l'un** de ces événements survient :
1. aucune version publiée de SeaweedFS depuis 6 mois, ou un avis de sécurité critique non corrigé
   sous 30 jours ;
2. changement de licence ou de modèle (fonction dont nous dépendons déplacée vers l'édition
   entreprise) ;
3. le test des écritures conditionnelles échoue après une mise à jour ;
4. un besoin de haute disponibilité du stockage objet (MédiDoc en production, PRA du module F5) ;
5. revue annuelle de routine : octobre 2027.

## Stratégie de sortie

Ce qui est portable : les états (objets S3, chiffrés par OpenTofu, indépendants du stockage) et
les données des futurs consommateurs. Ce qui ne l'est pas : les identités, les politiques, et
l'adresse `https://s3-01.par1.medisphere.internal:8333` écrite dans les blocs `backend` et dans
`terragrunt/live/root.hcl`.

Procédure (cible : moins d'une demi-journée pour les états) :
1. Nouveau stockage installé à côté, compartiment `tofu-state` versionné, test E12 vert.
2. Gel des applys (planifications suspendues, annonce), puis copie des états : `outils/sauvegarder-etats.sh`
   depuis l'ancien, `outils/restaurer-etat.sh --fichier` (ou `aws s3 sync`) vers le nouveau ;
   comparaison des `serial`/`lineage` du manifeste.
3. MR qui change l'adresse dans les backends et `root.hcl` ; `tofu init -reconfigure` partout
   (mêmes compartiment et clés : rien à migrer dans l'état lui-même) ; plans vides partout.
4. Ancien stockage en lecture seule un mois, puis retiré.

Test de la stratégie : la répétition d'E29 (restauration sous `_restauration/` et plan vide) en
est la moitié ; l'autre moitié (backend pointé vers un autre stockage) est rejouée lors du
module 08 avec Ceph RGW.

## Conséquences

Positives : un stockage libre, léger, testé sur les fonctions dont l'état dépend ; une sortie
écrite et en partie répétée ; un critère de révision qu'on peut constater sans débat.

Négatives, et leur traitement :
- **Point unique de défaillance** : `s3-01` est une VM seule. Traitement : sauvegarde PBS nocturne,
  copie externe des états (E29), RTO mesuré ; haute disponibilité au module 08 si un consommateur
  l'exige.
- **Dépendance à un petit nombre de mainteneurs** (gouvernance moins solide que Ceph). Traitement :
  conditions de révision 1 et 2, veille mensuelle (journal des versions), sortie préparée.
- **Fonctions S3 inégalement couvertes** (cycle de vie des versions non courantes, verrouillage
  d'objets) : à tester avant chaque nouvel usage, jamais supposées.
- **Coût de la veille** : une demi-heure par mois, inscrite au calendrier de l'équipe.
