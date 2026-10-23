# Final F7 — Phase 4 : Soutenir — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. Le dossier de référence est **un** dossier défendable ; le jury juge la cohérence entre ce qui est écrit, ce qui est mesuré et ce qui est montré.

**Validé hors du lab** (à la rédaction, 23/10/2026) : documents de référence rejoués contre les motifs de `check-S12.sh` (synthèse : 747 mots ; script : 13 repères de temps) ; chiffres repris du corrigé de la phase 2 (`chiffrage.md` : 1 864 265 € sur cinq ans, 530 568 € la première année) ; `check-S14.sh` exécuté sans lab (KO attendus, aucun arrêt intempestif).

**Fichiers** : [`fichiers/F7-S12/`](fichiers/F7-S12/) (`medisphere/docs/capstone/soutenance/…`), [`fichiers/F7-S14/`](fichiers/F7-S14/) (`recette.md`, component `donnees-demo`).

---

### F7-S12 — Le dossier de soutenance

**Solution**

Documents de référence : [`document-architecture.md`](fichiers/F7-S12/medisphere/docs/capstone/soutenance/document-architecture.md), [`synthese-direction.md`](fichiers/F7-S12/medisphere/docs/capstone/soutenance/synthese-direction.md), [`script-demonstration.md`](fichiers/F7-S12/medisphere/docs/capstone/soutenance/script-demonstration.md), [`annexes-preuves.md`](fichiers/F7-S12/medisphere/docs/capstone/soutenance/annexes-preuves.md).

Ce qui fait un bon dossier :
1. **La traçabilité d'abord** : une ligne par exigence (ce que dit le GHSV, ce que nous faisons, la décision, la preuve, le statut). La colonne « statut » distingue *confirmé*, *à confirmer* (capacité réelle), *ouvert* (identité à PAR2, ENF-07) : un jury technique cherche exactement ces lignes ; les écrire soi-même désarme la question.
2. **Ce que le lab ne montre pas**, dit sans détour, avec la condition de l'engagement (campagne de charge en préproduction, Keycloak de repli à PAR2 avant la mise en service).
3. **La synthèse se lit seule** : des conséquences pour le groupement (« au plus 40 à 45 minutes par mois, selon sa longueur »), pas des mécanismes ; le coût en ordre de grandeur avec ses hypothèses et « à confirmer par devis » ; trois risques et leur traitement ; ce que le GHSV doit fournir, daté.
4. **Le script prévoit l'échec** : liste de contrôle à T−30 min, un plan B par étape (enregistrement de la veille, captures, document), et la règle « pas plus de 60 secondes de réparation en direct ».
5. **Les annexes renvoient à des objets réels** : objets de `preuves-conformite` (collectés par `ms-preuves`), MR, rapports, comptes rendus — pas des captures sans date.

**Explications**
Le dossier n'est pas un résumé des phases 1 à 3 : c'est une **argumentation**. Chaque affirmation se rattache à une preuve, chaque chiffre à une source (mesure, hypothèse `H-nn`, devis). Ce qui n'a pas de preuve devient un risque ou une réserve, ou disparaît.

**Alternatives**
Un document unique au lieu de quatre : plus court à produire, mais la direction ne lit pas un document d'architecture, et le RSSI ne se contente pas d'une synthèse. Un support en diapositives généré depuis le dépôt (Pandoc, Marp) garde une seule source.

**Pièges classiques**
- Recopier `architecture.md` au lieu de dire ce que la preuve de concept a confirmé ou non.
- Un « 99,99 % » glissé dans la synthèse pour « faire mieux » que le cahier des charges : non mesuré, non chiffré.
- Des prix présentés comme des devis.
- Une démonstration sans plan B, ou dont le plan B est « on improvise ».
- Une annexe de preuves qui cite des captures d'écran au lieu d'objets datés et signés.

**En production chez MédiSphère**
Le dossier est produit par la CI (PDF numéroté, empreinte), versionné avec l'offre, et les preuves gardent leur identifiant de `preuves-conformite` jusqu'à la fin du marché.

---

### F7-S13 — La soutenance : questions du jury

Réponses de référence : courtes, chiffrées, honnêtes. Chaque piège est signalé.

**1. Pourquoi nous plutôt qu'un grand hébergeur certifié ?** Parce que nous hébergeons **et** développons l'application : l'équipe qui corrige un défaut est celle qui est d'astreinte, sans ticket entre deux sociétés (EXP-02 : 15 min de prise en compte). Notre plateforme a été reconstruite depuis son code (F1), a basculé sur son site de secours avec des mesures (F5 : RTO et RPO mesurés), a passé un audit à blanc HDS/ISO (F6), et tout cela est **dans le dossier**. Ce qu'un grand hébergeur fait mieux : la capacité brute, la redondance d'équipes. Notre réponse : la charge du GHSV pèse ≈ 6 % d'une grappe (architecture §5), et notre limite est humaine, d'où une astreinte chiffrée. Si le GHSV veut l'infrastructure d'un grand hébergeur, l'option infogérance est chiffrée (`chiffrage.md` §3) — elle laisse l'application chez nous.

**2. Un serveur de maquette, et 150 req/s le lundi ?** La maquette ne prouve pas la capacité ; elle prouve la **méthode** : coût mesuré par requête (CPU de l'API et de PostgreSQL à deux paliers de charge), multiplié par des facteurs écrits (mélange, processeur, utilisation cible 50 %). Résultat : ≈ 23 vCPU réservés pour le GHSV à PAR1 sur des serveurs dimensionnés (architecture §5). Engagement conditionné à une campagne de charge en préproduction (avril 2027) à 300 req/s (deux fois la pointe) ; si elle échoue, nous ajoutons de la capacité à nos frais avant le premier établissement. C'est écrit dans l'offre.

**3. Fin de contrat : combien de temps, combien d'argent, quel état ?** Export complet sous 30 jours (ERV-02) : rendez-vous en JSON Lines et CSV aux champs de l'API v1, comptes patients sans secret, pièces jointes avec leur index, journaux du locataire, manifeste d'empreintes signé ; relisible sans aucun outil de MédiSphère (essai : base vierge d'une autre version de PostgreSQL). Prix : le forfait P7 du bordereau (export final et destruction, 15 000 € proposés, ordre de grandeur à confirmer), plus l'accompagnement P6 au jour ; les essais annuels sont compris dans la redevance (≈ 11 000 € de coût pour nous sur le marché, essais et export final compris : `chiffrage.md`). Puis destruction prouvée sous 30 jours : procès-verbal, effacement cryptographique des clés.

**4. *(Piège)* « 100 % souveraine ? »** Non, et il faut le dire. Les données sont en France, dans deux salles d'hébergeurs certifiés HDS (activité 1), sur des logiciels libres que nous exploitons nous-mêmes ; aucun service d'un fournisseur extra-européen ne traite les données de santé. Mais : des composants viennent de projets étrangers (logiciels libres), nos images passent par des caches de registres publics, le prestataire du DPI à Tunis demande à lire des journaux (ESC-12, question 19), et les SMS passent par un opérateur. La cartographie des transferts (F6, ESC-03) dit tout cela ; « souverain » sans définition n'est pas un engagement.

**5. 99,93 % dans le rapport, mais une heure sans connexion des agents mardi.** Les deux peuvent être vrais. ENF-03 mesure la **prise de rendez-vous** (web et API) ; une panne de **connexion des agents** (IdP du GHSV injoignable, courtier, mandataire) ne l'interrompt pas pour les patients ni pour le DPI. Si la panne venait de chez nous, c'est un incident P1 ou P2 avec sa fiche, qui figure au rapport (section incidents) ; si elle venait de l'IdP du GHSV, notre sonde de connexion d'agent le montre. Ce que je propose : un indicateur séparé « disponibilité de l'accès des agents », publié au rapport — sans le confondre avec ENF-03. Et si la sonde du GHSV (R-09) voit autre chose que la nôtre, on compare en comité de suivi.

**6. Un agent licencié vendredi soir : quand perd-il l'accès ?** Dès que le GHSV le désactive dans son annuaire : au plus **15 minutes** plus tard, à l'expiration de sa session chez nous (session du client et cookie du mandataire de 15 min, sans rafraîchissement ; le flux n'accepte jamais une session MédiSphère seule, il repasse par l'IdP du GHSV, qui refuse). Ce qui pourrait prolonger : une désactivation tardive **chez le GHSV** (c'est son processus), une session de l'IdP du GHSV qui ne vérifie pas l'état du compte, un jeton déjà émis (≤ 15 min). Mesure faite : `identite-federee.md` §4 (P-15).

**7. Keycloak compromis : quoi pour l'attaquant ?** Il peut émettre des jetons pour n'importe quel client de notre royaume : se faire passer pour un agent du GHSV auprès de l'API (lecture et annulation des rendez-vous du GHSV), ou pour le DPI. Il n'obtient pas : les mots de passe des agents (ils sont chez le GHSV), les clés `transit/ghsv-*` (OpenBao, autre système, aucune personne n'a `decrypt`), les sauvegardes. Détection : événements d'administration de Keycloak, alertes sur les connexions anormales ; réponse : rotation des clés de signature, invalidation des sessions, RB-360 (F6). Keycloak est un actif de niveau 0 (M24) ; en production, grappe dédiée et administration réservée au compte d'OpenTofu.

**8. « Clés dédiées » : qui peut déchiffrer ?** Les clés `transit/ghsv-*` ne sortent jamais d'OpenBao (non exportables). **Aucune personne** ne détient le droit de déchiffrer : il faut un jeton d'opération créé par un administrateur, limité à 15 minutes et à quelques usages, pour une raison écrite (essai de relecture, remise) — et chaque création et chaque usage sont dans le journal d'audit d'OpenBao, conservé un an, relu dans le rapport mensuel (section accès). Vous le sauriez par le rapport et, sur demande, par l'extrait du journal (ESC-08 : sous 5 jours ouvrés). Limite honnête : aujourd'hui ces clés protègent les exports ; leur application à la base et aux archives est au lot de construction (écart écrit, ADR-0371).

**9. *(Piège)* « Le chiffrement au repos de vos disques suffit contre vos administrateurs ? »** Non. Le chiffrement au repos protège d'un disque volé ou mis au rebut ; un administrateur qui accède au système en marche lit des données déchiffrées. Contre les administrateurs : moindre privilège et accès nominatifs revus chaque trimestre (ESC-11), journaux inaltérables, séparation des rôles (celui qui administre le stockage ne détient pas les clés), chiffrement **applicatif** des champs identifiants par une clé du client (cible de l'ADR-0371), et pour les sauvegardes, des clés que l'administrateur du stockage n'a pas.

**10. Incident de sécurité sans atteinte connue à vos données : vous prévenez ?** Oui, si l'incident touche la plateforme qui héberge vos données : information **sans délai, et au plus tard 24 heures** après détection (ESC-10), même avec « pas d'atteinte connue à ce stade », car c'est vous qui déclarez au CERT Santé et, le cas échéant, à la CNIL (72 h). Nous fournissons la chronologie, le périmètre, les preuves (exercice INC-6211 du F6 : modèle de notification). Ce qui ne déclenche pas de message : un événement de sécurité sans lien avec votre locataire ni avec la plateforme commune — il figure au rapport mensuel.

**11. Une instance par client plutôt que multi-locataire ?** Isolation simple à **prouver** (espace, base, clés, journaux, réseau : chaque frontière est un objet de la plateforme, ADR-0370), destruction simple, versions synchronisées par la même promotion, et MédiAgenda n'a pas de modèle multi-locataire aujourd'hui. Coût : une base, un cache et deux mandataires par client (≈ 1,5 vCPU et 3 Gio réservés dans le lab, une fraction d'une grappe en production). Je changerais d'avis vers une dizaine de clients **petits** (le coût fixe par instance domine), ou si le produit devient multi-locataire avec isolation par ligne prouvée (politiques de sécurité au niveau des lignes, clés par locataire) ; le seuil se mesure avec le showback (F2-S08).

**12. SLO glissant, contrat calendaire, 15 jours de rétention : prouvez que le chiffre du mois est juste.** Le chiffre du contrat ne vient pas de Pyrra : `ms-rapport-client` l'évalue sur le **mois de Paris**, à la fin de chaque intervalle hors maintenances conformes, sur les **données brutes de Thanos** (30 jours de brut, stockage objet), en comptant les échantillons de sonde réussis. Les requêtes sont en annexe du rapport : on peut les rejouer. D'où une contrainte : le rapport est produit le 1er et au plus tard avant le 30 du mois suivant. Pyrra (30 j glissants, sans exclusion des maintenances) sert au pilotage, et les deux chiffres sont différents par construction.

**13. Un champ mal typé dans l'API v1 : les six prochains mois.** Un champ mal typé ne se corrige pas en place : c'est une rupture. Mois 0 : ticket, décision (si le contrat dit le bon type et que nous le servons mal, c'est **nous** qui sommes hors contrat : correctif conforme au contrat, testé, annoncé comme correction) ; sinon : ajout d'un nouveau champ correct à côté (compatible, version 1.1), ancien champ marqué déprécié dans la documentation. Mois 0-1 : recette du GHSV au moins 10 jours ouvrés avant la production (EXP-06), tests de contrat des deux formes. Mois 1-6 : trafic suivi par champ et par version dans le rapport ; le retrait de l'ancien champ n'arrive qu'avec une v2, coexistence ≥ 12 mois (EF-05). Jamais : changer le type en production sans version.

**14. *(Piège)* « Réplication continue, donc RPO nul ? »** Non. La réplication vers PAR2 est **asynchrone** (archivage des WAL au moins chaque minute, puis copie vers le stockage de PAR2) : le RPO mesuré est de quelques minutes (essai isolé : `<MIN>`), sous les 15 min promises. Un RPO nul exigerait une réplication **synchrone** entre sites : chaque écriture attend PAR2, la latence et la disponibilité de PAR1 dépendent de la liaison ; non proposé. Et une réplication propage aussi les erreurs (une suppression par erreur arrive à PAR2) : elle ne remplace pas les sauvegardes.

**15. Cinq clients comme le GHSV : qu'est-ce qui casse en premier ?** Pas le calcul (6 % d'une grappe par client) : d'abord **les personnes** (astreinte, revues d'accès, rapports mensuels, comités : chaque client ajoute du travail fixe), puis **Keycloak** (un royaume pour tous, cinq fournisseurs, refus à maintenir : passer à un royaume par client), puis la **mémoire de PAR2** (une réplique par client), puis le budget d'erreur partagé de la plateforme (une maintenance commune consomme le budget de cinq contrats). Mesures pour le voir venir : showback, charge de l'astreinte, rapport de capacité de PAR2.

**16. Combien de personnes pour tenir 24 h/24, et les avons-nous ?** Le chiffrage retient 1,2 ETP d'exploitation dédiés au GHSV (dont la part d'astreinte) et 0,3 ETP de maintenance applicative, dans une rotation d'astreinte d'au moins cinq personnes qualifiées (une semaine sur cinq). Aujourd'hui l'équipe Plateforme est de cinq personnes, dont un stagiaire : la rotation tient **juste**, sans marge pour congés et départs. C'est un risque écrit ; traitement : un recrutement à la notification (dans le chiffrage) et l'astreinte applicative partagée avec l'équipe MédiAgenda.

**17. L'hypothèse la plus chère si elle est fausse ?** Celle sur les **personnes** : l'exploitation et l'astreinte pèsent ≈ 48 % du coût complet ; si 1,2 ETP devient 2 ETP (incidents plus nombreux, exigences de reporting sous-estimées), le coût sur cinq ans augmente de plusieurs centaines de milliers d'euros (ordre de grandeur `chiffrage.md` §4). Le matériel (± 50 %) est négligeable sur le total. Les SMS (14 %) dépendent du taux de consentement (R-05 : 55 %) : sensibilité écrite.

**18. *(Piège)* « 99,99 % pour 10 % de plus ? »** Non. 99,99 % c'est **4 minutes** par mois au lieu de 43 : une seule bascule de PAR1 vers PAR2 (RTO mesuré en heures) consomme le budget de plusieurs années. Il faudrait un actif-actif entre sites (réplication synchrone ou base multi-sites, Keycloak et stockage actifs des deux côtés), une astreinte avec intervention en minutes, des maintenances sans interruption : une autre architecture, à un autre prix — et nous ne savons pas encore le **mesurer** à ce niveau (sonde toutes les 30 s : une résolution trop grossière). Réponse honnête : nous chiffrons un 99,95 % si le groupement le souhaite, avec ses conditions.

**19. Le prestataire du DPI à Tunis et les journaux de l'API.** Les journaux d'accès de MédiAgenda ne contiennent pas de donnée de patient (règle de l'application : pas de corps, pas de nom ; vérifié par un test), mais ils contiennent des identifiants de praticiens et de rendez-vous, des adresses IP et des horaires : ce sont des données **personnelles**, et un accès depuis la Tunisie est un **transfert hors EEE** (RGPD chapitre V, et information des clients au titre de HDS v2). Proposition : (a) une vue **pseudonymisée** des journaux techniques des échanges avec le DPI (identifiants hachés avec une clé que nous gardons, codes, durées, horaires), exposée en lecture dans une organisation Grafana dédiée, accès nominatif et journalisé ; (b) pas d'accès aux journaux bruts ; (c) le GHSV, responsable de traitement, encadre le transfert (clauses contractuelles types avec son prestataire) ; (d) nous l'inscrivons dans la cartographie des transferts publiée (F6). Alternative sans transfert : nous faisons le diagnostic de niveau 2 et transmettons des extraits pseudonymisés à la demande.

---

### F7-S14 — Recette `capstone-v1`

**Solution**

Document de référence : [`recette.md`](fichiers/F7-S14/medisphere/docs/capstone/recette.md).

1. **Idempotence** : rendu de `plateforme/equipes` sans MR à ouvrir, `tofu plan` vides (`medisphere`, `ghsv-idp`, `plateforme/secrets`), Applications `Synced`/`Healthy`, pipelines verts.
2. **Reconstruction de `ghsv-recette`** : ⚠️ données fictives uniquement ; vérifier avant et après que `ghsv-prod` et MédiAgenda ne bougent pas.
   ```
   admin@adm01:~$ kubectl -n argocd get applicationset client-ghsv -o jsonpath='{.spec.syncPolicy.preserveResourcesOnDeletion}'   # true attendu
   admin@adm01:~$ argocd app delete ghsv-recette --cascade=false --yes      # l'ApplicationSet la recrée
   admin@adm01:~$ kubectl delete namespace ghsv-recette --wait=true         # RB-320 § Départ, un seul environnement
   admin@adm01:~$ argocd app sync equipes-k8s                               # ou attendre la synchronisation automatique
   admin@adm01:~$ kubectl -n ghsv-recette get pods -w
   ```
   La base renaît **vide** : les migrations (hook) recréent le schéma, et le component [`donnees-demo`](fichiers/F7-S14/mediagenda-deploiement/components/donnees-demo/job.yaml) (hook `PostSync`, overlay de recette seulement) recharge 400 rendez-vous fictifs — sans lui, la recette reconstruite est vide et la démonstration du DPI échoue : c'est l'écart que la reconstruction révèle le plus souvent. Chronométrer chaque étape, noter chaque geste manuel.
3. **Preuves** : ajouter au catalogue de `ms-preuves` (F6) les éléments de la capstone (rapport mensuel, essai de réversibilité, compte rendu de journée de jeu, essai de reprise, constat de cloisonnement, rapport JUnit du contrat, métadonnées des clés), lancer sa collecte (pipeline planifié ou exécution manuelle du même pipeline), reporter les identifiants dans `annexes-preuves.md`.
4. **Recette et étiquette** : `recette.md` (contrôles, durées, écarts E-1 à E-4 au moins, suite), MR, puis `capstone-v1` :
   ```
   admin@adm01:~/medisphere$ git tag -a capstone-v1 -m "Capstone GHSV : preuve de concept et dossier (F7-S14)" && git push origin capstone-v1
   ```

**Explications**
Un plan vide prouve que le code décrit l'existant ; une reconstruction prouve que le code **suffit**. Les deux ensemble ferment les deux doutes : la dérive silencieuse et le geste manuel oublié. La recette n'est qu'un environnement, mais c'est celui que le DPI du GHSV utilise en permanence (EXP-06) : savoir le reconstruire en quelques minutes est un argument de soutenance.

**Alternatives**
Reconstruire tout le locataire dans un cluster jetable (vCluster, M28) : prouve aussi le rendu de `plateforme/equipes` de bout en bout, sans toucher à `ghsv-recette` ; plus long à monter. Reconstruction hebdomadaire planifiée : transforme la preuve ponctuelle en contrôle continu.

**Pièges classiques**
- Supprimer l'Application avec cascade : Argo CD supprime aussi les objets… y compris ce qui n'a pas `Prune=false`.
- Supprimer l'espace pendant qu'un Job de migration tourne : finaliseurs, espace bloqué en `Terminating`.
- Déposer les preuves à la main dans le compartiment : elles ne sont ni horodatées ni signées par `ms-preuves` (et le verrouillage d'objets empêche de corriger une erreur).
- Poser l'étiquette avant que tous les contrôles soient verts.

**En production chez MédiSphère**
La reconstruction de la recette de chaque client est un pipeline hebdomadaire qui publie sa durée ; la recette `capstone-v1` devient le modèle de recette de toute arrivée de client.

---

## Points non testés en conditions réelles

- Commandes de reconstruction de `ghsv-recette` (`argocd app delete --cascade=false`, recréation de l'espace par l'Application `equipes-k8s` sans `Prune` ni `selfHeal` sur les espaces ? vérifie la politique de synchronisation de **ton** Application `equipes-k8s` : si l'espace ne revient pas tout seul, une synchronisation manuelle suffit).
- Job `donnees-demo` en hook `PostSync` : ordre d'exécution après le Job de migrations (vague −1, hook `Sync`) à confirmer ; politique réseau de la base à ouvrir à ce Job.
- Catalogue et mode d'emploi de `ms-preuves` : définis au F6 (S02) ; le corrigé ne présume pas de leur forme exacte.
- Chiffres cités dans les réponses du jury (coûts, ETP, part des personnes) : ceux du corrigé de la phase 2 ; tes chiffres font foi.
- Seuil de mots de la synthèse dans le check (300 à 1 400) : une approximation de « deux pages ».
