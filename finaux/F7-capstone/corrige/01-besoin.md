# Final F7 — Phase 1 : Comprendre le besoin — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. Les deux scénarios sont des rédactions : les documents de référence sont **des** réponses possibles, jugées sur les critères ci-dessous. Une analyse différente, argumentée et appuyée sur le code et les mesures, vaut autant.

**Validé hors du lab** (à la rédaction, 23/10/2026) :
- annexe A1 : OpenAPI 3.1 valide (`openapi-spec-validator`, et `redocly lint` 1.34 : seul avertissement, l'absence de licence) ; chaque écart avec MédiAgenda relevé ci-dessous a été vérifié dans `apps/mediagenda` (`app.py`, `modeles.py`) et dans le correctif `rappel` du M27-E06 ;
- annexe A2 : totaux recalculés (somme des consultations 1 800 000, dont 129 000 pour GHSV-12 ; total corrigé par R-03 : 1 683 900 ; patients 462 300 contre 400 000 déclarés ; 2 000 Go de pièces jointes pour 176 600 rendez-vous en ligne) ; chiffres de S02 recalculés (budgets d'erreur, 1,06⁵ = 1,338, capacité, volumes) ;
- checks `check-S01.sh` et `check-S02.sh` rejoués sur les documents de référence (GitLab simulé).

**Fichiers** : [`fichiers/F7-S01/`](fichiers/F7-S01/) et [`fichiers/F7-S02/`](fichiers/F7-S02/), arborescence de `plateforme/medisphere` (`medisphere/docs/capstone/…`).

---

### F7-S01 — Lire le cahier des charges

**Solution**

Documents de référence : [`analyse-cdc.md`](fichiers/F7-S01/medisphere/docs/capstone/analyse-cdc.md) et [`questions-client.md`](fichiers/F7-S01/medisphere/docs/capstone/questions-client.md).

Ce qu'il fallait trouver, par ordre d'importance pour l'offre :

1. **Les deux contradictions volontaires du CCTP** :
   - **ENF-06 ↔ ENF-07** : un RPO de 15 minutes et « aucun rendez-vous confirmé perdu » ne tiennent pas ensemble techniquement. La bonne réponse n'est ni de promettre un RPO nul (réplication synchrone entre sites : chaque écriture paie l'aller-retour, et le site de repli devient une dépendance de la disponibilité du site principal), ni d'ignorer ENF-07, mais de tenir ENF-07 **par un processus** : le DPI a reçu le `201`, MédiNotif a envoyé une confirmation, les journaux d'accès gardent l'horodatage : on réconcilie après la bascule. Le GHSV maintient les deux exigences (R-11) : c'est la réponse d'un client qui veut voir comment le candidat s'y prend.
   - **ESC-08 ↔ ERV-04** : journaux conservés un an, mais tout détruit sous 30 jours, journaux compris. S'y ajoutent les sauvegardes (rétention PBS, verrouillage d'objets du F6) qu'on ne sait pas « détruire » sélectivement. Réponse : restitution des journaux dans l'export, conservation justifiée de ce que nos obligations exigent, et **destruction cryptographique** (les clés dédiées rendent sauvegardes et copies illisibles) : l'ESC-06 devient la solution de l'ERV-04.
2. **Les exigences irréalistes** : **ENF-05** « aucune requête ne doit dépasser 1 seconde » (un 100e centile, que n'importe quel ramasse-miettes viole) et **MES-01** dans sa version initiale (douze établissements un mois après la notification, alors que MES-02 parle de quatre mois de vagues). ENF-09 lu littéralement (×3 sur la pointe) en est un troisième, levé par R-02.
3. **La tension ESC-03 ↔ ESC-12** (centre de services à Tunis) : ce n'est pas une contradiction absolue (le référentiel HDS v2 admet un accès depuis un pays tiers s'il est déclaré et cartographié publiquement, et le RGPD l'encadre), mais c'est un risque de non-conformité et de réputation. Une extraction filtrée remise au GHSV, sous sa responsabilité, permet le même diagnostic sans transfert de notre fait.
4. **L'annexe A1 contre le code** : `deplacerRendezVous` n'existe pas (`405`) ; `listerRendezVous` **ignore** `praticien`, `du` et `au` (FastAPI ne rejette pas les paramètres de requête inconnus : réponse `200` avec les 100 premiers rendez-vous de tous les praticiens — le DPI rapprocherait ses agendas avec des données fausses, sans erreur) ; `annulerRendezVous` supprime physiquement la ligne (plus de trace pour les statistiques, les journaux ou la réconciliation) ; aucune authentification. C'est le cœur du contrat d'interface que F7-S09 testera.
5. **Les trous du produit** : aucune notion d'établissement, de spécialité ni de plages ouvertes (plages codées en dur), pas de déplacement, pas de pièces jointes, pas de comptes patients, pas de rappel planifié à J-2. Un capstone honnête chiffre ce travail (≈ 155 jours selon Julien) et le met au planning.
6. **Les données douteuses** : la ligne GHSV-12 (129 000 consultations pour 7 praticiens), le total des patients (dédoublonné), le volume de pièces jointes rapporté aux rendez-vous en ligne.
7. **La recevabilité** : HDS « activités 1 à 6 » alors que MédiSphère est certifiée 2 à 6 (Q-08, R-13), ISO 27001 en cours (non éliminatoire), ESC-04 démontrable.

Les **questions** de référence ont trois qualités qu'on vérifie une par une : chacune cite une exigence, chacune dit ce qu'elle change dans l'offre, chacune a une hypothèse de repli. Aucune ne révèle notre architecture (« utilisez-vous CloudNativePG ? » n'a rien à faire là) ni nos faiblesses (« acceptez-vous un PRA sans capacité complète avant avril ? » apprendrait à nos concurrents ce que nous ne savons pas faire). Q-05, Q-09 et Q-14 restent sans réponse : les hypothèses H-07 et H-10, et la date d'export final retenue pour Q-09, entrent dans l'offre comme réserves écrites.

La **recommandation** de référence est « répondre avec réserves », avec des conditions de *no-go* explicites. Une recommandation « ne pas répondre » est défendable si elle est argumentée (charge de développement, calendrier) ; « répondre sans réserve » ne l'est pas.

**Grille d'auto-évaluation** (sur 20)
- Contradictions ENF-06/ENF-07 et ESC-08/ERV-04 trouvées et traitées (proposition, pas seulement constat) : 4
- ENF-05 (100e centile) et MES-01/MES-02 relevées : 2
- Annexe A1 comparée opération par opération, y compris les paramètres ignorés et la suppression physique : 4
- Trous fonctionnels identifiés et chiffrés, même grossièrement : 2
- Annexe A2 recalculée (GHSV-12, patients, pièces jointes) : 2
- Questions : précises, liées à une décision, avec hypothèse de repli, sans fuite : 4
- Recommandation argumentée avec conditions de *no-go* : 2

**Explications**

Un cahier des charges public est écrit par des personnes qui n'ont pas le temps de tout relire ensemble : la section « PRA » est rédigée par l'infrastructure, la section « intégrité » par les directions médicales, la section « réversibilité » par les juristes, la section « journaux » par le RSSI. Les contradictions naissent aux frontières. La phase de questions écrites est le **seul** moment où on peut les faire lever pour tous les candidats ; après la remise des offres, une réserve non posée devient un engagement.

Comparer le contrat d'interface au code, paramètre par paramètre, est le réflexe le plus rentable de ce scénario : un contrat d'API engage sur cinq ans (EF-05 : rétrocompatibilité et 12 mois de recouvrement). Signer un contrat qu'on ne respecte pas aujourd'hui sans l'avoir vu, c'est découvrir l'écart en recette avec l'éditeur du DPI, sous pénalités.

**Alternatives**
- Matrice de conformité exhaustive (une ligne par exigence, *conforme / avec réserve / non conforme*, §11.2) dès S01 plutôt qu'une analyse thématique : c'est le format qu'attend l'acheteur ; elle se construit naturellement depuis le tableau besoin ↔ solution.
- Analyse de risques dès S01 (registre préliminaire) : utile, mais S06 la fait ; ici, une liste des conditions de *no-go* suffit.
- Poser les questions sous forme de QCM (« A, B ou C ? ») : excellente pratique quand les options sont connues ; elle force une réponse exploitable.

**Pièges classiques**
- Poser des questions dont la réponse est dans le CCTP : l'acheteur répond « voir §5 » et l'offre perd en crédibilité.
- Révéler son architecture ou ses faiblesses dans une question publiée à tous les candidats.
- Comparer les **chemins** de l'API et conclure « conforme » : le diable est dans les paramètres (`du`, `au` ignorés), les codes (`405`), la sémantique (suppression physique) et la sécurité.
- Reprendre l'annexe A2 telle quelle dans un dimensionnement, ligne aberrante comprise.
- Traiter ENF-07 en promettant un RPO nul « parce que le client le veut » : c'est une promesse qui coûte une architecture et qu'on ne tiendra pas.
- Oublier que MédiAgenda, dans le lab, n'est qu'une API : promettre des écrans qu'on ne peut pas démontrer.

**En production chez MédiSphère**
L'avant-vente a une procédure de lecture des appels d'offres : un « *bid / no-bid* » en 48 h sur une grille (adéquation au produit, capacité de l'équipe, calendrier, rentabilité, risque juridique), puis une revue des réserves par la direction juridique avant envoi des questions. Les réponses du client sont versionnées avec l'offre : en cas de litige, ce sont elles qui interprètent le contrat.

---

### F7-S02 — Les exigences non fonctionnelles, chiffrées

**Solution**

Document de référence : [`exigences.md`](fichiers/F7-S02/medisphere/docs/capstone/exigences.md). Les points qui font la différence :

1. **Disponibilité contractuelle en minutes, mesurée de l'extérieur.** 99,9 % sur un mois civil, c'est **44,6 min** sur 31 jours, 43,2 sur 30, 40,3 sur 28. Le point de mesure contractuel est **externe** (sondes synthétiques depuis deux points, dont un hors de nos sites) : une métrique de l'application ne voit ni une Gateway en panne, ni une coupure de l'accès Internet de PAR1. Le SLO **interne** en requêtes (Gateway, 99,95 % sur 28 jours glissants, Pyrra comme au M21) est plus strict, et il est assorti d'une **politique de budget d'erreur** (gel des changements du locataire quand il est consommé).
2. **Latence** : 95 % < 300 ms au contrat ; 95 % < 250 ms en interne (l'histogramme de MédiAgenda n'a pas de seau à 0,3 s : le seau 0,25 s est plus strict, donc sûr — c'est déjà la logique du M21) ; « aucune requête > 1 s » reformulée en **p99 < 1 s** (R-10), avec ses exclusions écrites.
3. **Capacité**, chaîne de calcul écrite : 150 req/s × 1,06⁵ (≈ 201 req/s en année 5) × 1,5 (octobre, R-02 arrondi) ≈ **300 req/s**, tenus **avec un nœud en moins**, testés à 400 req/s (utilisation ≤ 75 %). PAR2 : 300 req/s au contrat (pas d'objectif interne ni de N+1 pendant un PRA, et c'est écrit). La mesure du M29 (≈ 158 req/s, p95 112 ms en recette) prouve l'architecture, pas la capacité : la transposition se fait par le **coût par requête**, en S03.
4. **Volumes à cinq ans** : base ≈ 20 Go, comptes ≈ 3 Go, pièces jointes ≈ 3 To utiles (12 mois de conservation, R-06 ; l'hypothèse initiale « toute la durée du marché » donnait ≈ 13 To), journaux ≈ 40 à 60 Go/an. Conclusion qui servira en S05 : le GHSV est petit en calcul et en base, moyen en stockage objet, lourd en exigences.
5. **RTO et RPO définis précisément** : le RTO commence à la **première minute indisponible**, pas à la décision de basculer (le temps de décision est le poste le plus variable, le F5 l'a montré) ; le RPO se mesure par un **témoin** (celui du F5) et se borne par `archive_timeout` (5 min par défaut dans CloudNativePG) plus la réplication vers PAR2. ENF-07 devient **NF-12**, un engagement de **résultat** mesuré par un rapport de réconciliation.
6. **Sécurité chiffrée** : désactivation d'un agent ≤ 15 min (jetons de 5 min, H-08), journaux 365 j inaltérables et restitués en 5 jours ouvrés (remédiation de ECA-3601 du F6), vulnérabilités 15/30 j (processus de ECA-3602), information d'incident ≤ 24 h (RB-360), rotation des clés ≤ 12 mois, TLS partout.
7. **Matrice de traçabilité** : chaque `ENF-nn` et `ESC-nn` retombe sur un `NF-nn`, ou « non reprise » avec sa raison (ESC-01 : un certificat, pas une mesure). Les exigences « non reprises » ne sont pas oubliées : elles ont une autre forme de preuve.

**Grille d'auto-évaluation** (sur 20)
- Disponibilité : définition (bon/valide), point de mesure externe, budget en minutes selon la longueur du mois, maintenances : 4
- SLO interne plus strict et politique de budget d'erreur : 2
- Latence : p95 justifié, 100e centile reformulé : 2
- Capacité : chaîne de calcul (croissance, saisonnalité, N+1), distinction lab/production : 4
- Volumes à cinq ans, y compris l'effet de R-06 : 2
- RTO/RPO : définitions, décomposition, mesure du F5, position sur ENF-07 : 3
- Sécurité chiffrée et traçabilité complète : 3

**Explications**

Une exigence contractuelle n'existe que par sa **mesure**, et la mesure n'existe que par sa **définition**. « 99,9 % » ne veut rien dire tant qu'on n'a pas fixé : de quoi (prise de rendez-vous, donc écritures comprises, et pas seulement une page d'accueil), vu d'où (de l'extérieur), sur quelle fenêtre (le mois civil, puisque c'est la pénalité), avec quelles exclusions (les maintenances conformes, et rien d'autre). Le GHSV l'a compris (R-09) : la méthode est validée en comité avant le premier mois, sinon c'est un litige.

Les objectifs internes plus stricts que le contrat donnent une **marge d'alerte** : on agit quand le SLO interne se dégrade, avant que la pénalité tombe. L'inverse (un SLO interne plus lâche) garantit qu'on découvrira les pénalités dans le rapport mensuel.

Le calcul de capacité montre que le dimensionnement **n'est pas** dicté par la charge du GHSV (300 req/s, c'est peu pour un cluster) mais par la **redondance** : N+1 à PAR1, capacité complète à PAR2, et les exigences de sécurité. C'est la conclusion que le chiffrage (S05) doit retrouver.

**Alternatives**
- Mesure contractuelle par les seules métriques serveur (taux de 5xx) : précise et peu coûteuse, mais aveugle aux pannes en amont de l'application ; acceptable en SLO interne, pas en contrat.
- Disponibilité en **requêtes** plutôt qu'en minutes : plus juste pour l'utilisateur (une panne la nuit pèse moins), mais incompréhensible pour un acheteur qui raisonne en minutes, et instable avec un trafic faible la nuit. Le contrat en minutes et le SLO interne en requêtes combinent les deux.
- RPO nul par réplication synchrone inter-sites (`synchronous` de CloudNativePG vers un réplica de PAR2) : possible techniquement si la latence entre sites est faible, mais l'écriture dépend alors de PAR2 ; c'est un choix d'architecture à défendre en ADR (S04), pas une conséquence automatique d'ENF-07.

**Pièges classiques**
- 99,9 % = « 43 minutes » sans préciser la longueur du mois (40 à 45 min selon le mois).
- Mesurer la disponibilité sur `/sante` (vivacité) : elle répond même quand la base est tombée.
- Dimensionner sur la mesure du lab sans facteur (« le lab tient 158 req/s, la pointe est de 150 : c'est bon »).
- Appliquer la croissance en intérêts simples (+30 % sur 5 ans) au lieu de composés (+34 %), ou oublier l'année de référence.
- Faire commencer le RTO à la décision de bascule.
- Laisser des exigences ESC sans trace dans la matrice : le jury demandera « et ESC-12 ? ».
- Écrire des objectifs internes plus lâches que le contrat.

**En production chez MédiSphère**
Les `NF-nn` vivent dans un fichier versionné (YAML) d'où sont générés : les `ServiceLevelObjective` de Pyrra, les règles d'enregistrement, la matrice de traçabilité de l'offre et le gabarit du rapport mensuel. Une modification d'engagement passe par une MR relue par le responsable du compte client et la RSSI, et par un avenant au contrat.

---

## Points non testés en conditions réelles

- **Comportement de FastAPI face aux paramètres de requête inconnus** (ignorés, réponse `200`) et `405` sur `PATCH` : comportement documenté de FastAPI/Starlette, relu dans le code de MédiAgenda ; à constater sur ta recette (`curl -s -o /dev/null -w '%{http_code}' -X PATCH …`).
- **Sondes synthétiques en écriture en production** (praticien fictif `P999002`) : le principe est celui du témoin de RPO du F5 ; leur effet sur les statistiques du GHSV (EF-10) doit être filtré (praticiens fictifs exclus) : à vérifier en F7-S10.
- **`archive_timeout`** : 5 min par défaut dans CloudNativePG (documentation « WAL archiving »), modifiable ; effet d'une valeur plus courte sur le nombre d'objets archivés non mesuré.
- **Volumes de journaux** (≈ 450 octets par requête, compression ≈ 1/8 dans Loki) et **profil horaire** (moyenne journalière ≈ 15 % de la pointe) : ordres de grandeur supposés, à remplacer par ceux de ton Loki et de ton Prometheus.
- **Chiffrement transparent de Cilium** (NF-19) : cité comme piste, non évalué dans le workbook.
- Les éléments juridiques (procédure avec négociation, publicité des questions, recevabilité) sont simplifiés : ce final n'enseigne pas le droit de la commande publique.
