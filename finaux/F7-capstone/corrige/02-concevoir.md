# Final F7 — Phase 2 : Concevoir — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. Les documents de référence sont **une** conception défendable ; une autre, argumentée à partir des mêmes exigences et de tes mesures, vaut autant. Le jury (S13) juge la cohérence entre exigences, architecture, décisions, chiffres et démonstration, pas la conformité au corrigé.

**Validé hors du lab** (à la rédaction, 23/10/2026) :
- `chiffrage.csv` produit par un script à partir des hypothèses H-C01 à H-C12 ; totaux, sous-totaux et sensibilités de `chiffrage.md` recalculés depuis le tableur ;
- checks `check-S03.sh` à `check-S06.sh` rejoués sur les documents de référence (GitLab simulé), et contre des documents dégradés (section manquante, total faux, scénario manquant) ;
- prix publics relevés en octobre 2026 (voir « Points non testés ») ; dates du planning vérifiées au calendrier 2027 (1er mars et 12 avril : lundis ; 26 février : vendredi ; 5 juin : samedi ; vague 3 le mardi 18 mai, le 17 étant le lundi de Pentecôte) ; RACI : un seul A par activité.

**Fichiers** : [`fichiers/F7-S03/`](fichiers/F7-S03/) à [`fichiers/F7-S06/`](fichiers/F7-S06/), arborescence de `plateforme/medisphere` (`medisphere/docs/capstone/…`).

---

### F7-S03 — L'architecture cible de production

**Solution**

Document de référence : [`architecture.md`](fichiers/F7-S03/medisphere/docs/capstone/architecture.md). Ce qui fait une bonne réponse :

1. **Une mesure, pas un abaque.** Deux paliers stables sur la recette (le TestRun du M29 à 20 puis 40 itérations/s), CPU **consommé** par composant (`rate(container_cpu_usage_seconds_total[5m])`, jamais les `requests`), débit servi, nombre de pods. Deux paliers séparent la part fixe de la part proportionnelle. Résultat de référence : ≈ 0,72 vCPU d'API et 0,23 vCPU de PostgreSQL pour 100 req/s.
2. **Une chaîne de facteurs écrite** : capacité NF-07 (300 req/s) × coût mesuré × mélange (×1,0 : le parcours du M29, qui écrit à 40 % (2 requêtes sur 5), sert de borne haute pour un GHSV à 15 % d'écritures) × processeur (×1,3, prudence) ÷ utilisation cible (0,5). Le GHSV réserve ≈ 23 vCPU à PAR1 et ≈ 17 à PAR2.
3. **La conclusion qui en sort** : la charge du GHSV pèse ≈ 6 % du calcul d'une grappe de production de six hyperviseurs. **Ce qui dimensionne, c'est la redondance** : PAR2 à pleine capacité (trois hyperviseurs, minimum d'une grappe Proxmox et Ceph à trois répliques), Keycloak en grappe, un accès Internet propre à PAR2. Une architecture qui ajoute des serveurs à PAR1 « pour le GHSV » n'a pas fait le calcul.
4. **L'exposition à Internet**, que le lab n'a jamais eue : CNAME du nom du GHSV vers **notre** zone publique (la bascule se fait chez nous, TTL 60 s), deux fournisseurs DNS, AC publique en ACME (le défi HTTP-01 fonctionne sur le nom du GHSV puisque le CNAME pointe chez nous), protection volumétrique des opérateurs, limites de débit, routes publiées réduites au contrat.
5. **Le tableau « ce qui change par rapport au lab »** (douze lignes de référence) et les **points uniques de défaillance** assumés ou traités, dont deux que le lab cache : l'**IdP du GHSV** (hors de notre contrôle : exclusion contractuelle et sonde pour le prouver) et `kms01` (seulement au redémarrage d'OpenBao : accepté avec procédure).
6. **Un accès Internet à PAR2** : sans lui, le PRA du F5 bascule des noms internes, mais aucun patient ne joint PAR2. C'est l'oubli le plus fréquent.

**Grille d'auto-évaluation** (sur 20)
- Mesure du coût par requête (méthode, deux paliers, sources) : 4
- Chaîne de dimensionnement écrite et conclusion « la redondance dimensionne » : 4
- Deux sites décrits couche par couche, PAR2 à pleine capacité et joignable d'Internet : 4
- Exposition Internet (noms, certificats, DDoS, filtrage) : 3
- Écarts avec le lab et points uniques de défaillance (IdP du GHSV, Keycloak, `kms01`) : 3
- Schéma lisible, hypothèses identifiées : 2

**Explications**

Le lab du workbook est une maquette **d'architecture** : mêmes logiciels, mêmes flux, mêmes procédures. Il n'est une maquette ni de **capacité** (virtualisation imbriquée, un seul hyperviseur, des disques partagés), ni d'**exposition** (aucun trafic d'Internet), ni de **défaillance matérielle** (tout tombe avec `pve01`). Transposer une mesure du lab, c'est transposer un **coût unitaire** (vCPU par requête), pas un débit ; et le refaire sur le matériel livré (première revue de capacité).

**Alternatives**
- Kubernetes directement sur les serveurs (sans Proxmox) : moins de couches, meilleures performances, mais on perd les VMs du socle sur le même matériel et la cohérence avec tout ce que l'équipe exploite ; défendable pour une plateforme plus grande.
- Ceph séparé du calcul (grappe de stockage dédiée) : isolation des pannes et des montées de version ; plus de serveurs ; pertinent au-delà de quelques centaines de To.
- Actif/actif sur deux sites : voir ADR-0373 (écarté).
- Pare-feu applicatif (WAF) en façade dès la v1 : défendable ; le corrigé le laisse « à décider » après le test d'intrusion, ce qui est une décision écrite, pas un oubli.

**Pièges classiques**
- Dimensionner sur les `requests` des pods, ou sur le débit brut du lab.
- Oublier N+1 (les hyperviseurs) **et** PAR2 à pleine capacité (deux marges différentes).
- PAR2 sans accès Internet, sans DNS public, sans certificat valide pour le nom du GHSV.
- Garder `idp01` seul en production pour un service à 99,9 % dont la connexion des agents dépend.
- Compter sur le DNS du GHSV pour basculer (TTL et délais de modification hors de notre contrôle).
- Oublier la troisième copie des sauvegardes (rançongiciel atteignant PAR1 et PAR2 par le lien inter-sites).

**En production chez MédiSphère**
Le modèle de capacité est un tableur versionné (débit → pods → nœuds → serveurs) mis à jour à chaque essai de capacité trimestriel ; la revue de capacité mensuelle compare la pointe réelle au modèle et déclenche un achat quand la marge N+1 passe sous 30 %.

---

### F7-S04 — Les décisions d'architecture

**Solution**

ADR de référence : [`ADR-0370`](fichiers/F7-S04/medisphere/docs/capstone/adr/ADR-0370-isolation-client-ghsv.md) (isolation), [`ADR-0371`](fichiers/F7-S04/medisphere/docs/capstone/adr/ADR-0371-cles-dediees-ghsv.md) (clés), [`ADR-0372`](fichiers/F7-S04/medisphere/docs/capstone/adr/ADR-0372-federation-identite-ghsv.md) (identité), [`ADR-0373`](fichiers/F7-S04/medisphere/docs/capstone/adr/ADR-0373-pra-client-ghsv.md) (PRA), [`ADR-0374`](fichiers/F7-S04/medisphere/docs/capstone/adr/ADR-0374-reversibilite-ghsv.md) (réversibilité).

Les décisions qui comptent et leur raison :
- **Isolation par les données, les clés, les journaux et les accès, pas par le matériel** : locataire Capsule `ghsv` déclaré par l'équipe en code (type `client`), `Cluster` CloudNativePG, Valkey et compartiments **dédiés**, nœuds mutualisés. Un cluster dédié coûterait deux plans de contrôle et deux chaînes de montée de version de plus pour une exigence qui ne le demande pas ; les options sont **placées sur une échelle** avec ce que chacune isole vraiment.
- **Clés : la question est « qu'est-ce qui devient illisible si on détruit la clé ? »**. Un chiffrement de volume ne protège pas les sauvegardes logiques, les WAL, le réplica de PAR2 ni les exports ; un chiffrement **applicatif** par `transit` (chiffrement d'enveloppe) suit la donnée partout et rend la **destruction cryptographique** possible : c'est elle qui tient ERV-04 pour les copies qu'on ne sait pas effacer une à une (PBS dédupliqué, objets verrouillés). Conséquence assumée : OpenBao devient une dépendance de chaque écriture (cache des clés de données, supervision, ordre de reprise du PRA). Et un piège : les **instantanés Raft** d'OpenBao contiennent encore la clé détruite.
- **Identité : trois populations, trois solutions.** Agents fédérés par courtage OIDC dans `medisphere` (structure figée du lab ; un royaume par client à partir du deuxième client), sans aucun moyen d'authentification local ; patients dans un royaume **dédié** `ghsv-patients` (inscription libre, bourrage d'identifiants : jamais à côté des administrateurs) ; DPI en compte de service *client credentials*, de préférence avec `private_key_jwt`.
- **PRA : asynchrone + réconciliation.** La réplication synchrone entre sites ferait dépendre la disponibilité de PAR1 de celle de PAR2 ; ENF-07 est tenue en **résultat** (principe éprouvé en F7-S10, procédure dans RB-370, le runbook d'exploitation du service : DPI, accusés des fournisseurs de SMS et de courriel, journaux d'accès). `archive_timeout` ramené à 1 min pour viser un RPO technique de quelques minutes.
- **Réversibilité : un format qu'un tiers recharge sans nous**, essayé chaque année par l'équipe Data avec la seule documentation ; jamais un dump PostgreSQL.

**Grille d'auto-évaluation** (sur 20, pour quatre ADR ; cinq pour la note maximale)
- Chaque ADR décide (pas de « on pourrait ») et cite ses exigences : 4
- Options placées et écartées pour des raisons vérifiables : 4
- Conséquences honnêtes (ce qu'on perd, travail de la phase 3, coût) : 4
- Clés : destruction cryptographique et ce qui n'est **pas** couvert : 3
- PRA : position argumentée sur ENF-07 : 3
- Conditions de révision : 2

**Explications**

Une ADR sert surtout à celui qui la relira dans deux ans (ou au jury dans une heure) : pourquoi pas l'autre option ? Les options écartées et leurs raisons sont la partie la plus utile du document. Une option écartée « par goût » ou « parce que c'est plus complexe » sans dire de combien ne résiste pas à la première question.

**Alternatives**
- Une seule ADR « architecture du client GHSV » : plus courte, mais chaque décision a ses propres déclencheurs de révision ; les séparer permet de réviser l'identité au deuxième client sans rouvrir les clés.
- BYOK (clés fournies par le GHSV) : écartée sur la réponse R-14, à rouvrir si un client l'exige.

**Pièges classiques**
- Confondre « clés dédiées » et « disques chiffrés ».
- Oublier les copies de la donnée (sauvegardes, PAR2, exports, journaux) quand on raisonne sur la destruction.
- Mettre les patients dans le royaume des personnels.
- Promettre un RPO nul sans en payer le prix, ou ignorer ENF-07.
- Une réversibilité qui repose sur nos outils (le repreneur ne les a pas).
- Des ADR qui ne disent pas ce que le lab ne montrera pas (royaume `ghsv-patients`, capacité de PAR2).

**En production chez MédiSphère**
Les ADR du client sont jointes à l'offre sous une forme résumée (« nos engagements de conception ») ; les versions complètes restent internes. Elles sont relues à chaque comité de pilotage annuel et à chaque changement de version majeure de la plateforme.

---

### F7-S05 — Chiffrage et coût complet sur cinq ans

**Solution**

Documents de référence : [`chiffrage.md`](fichiers/F7-S05/medisphere/docs/capstone/chiffrage.md) et [`chiffrage.csv`](fichiers/F7-S05/medisphere/docs/capstone/chiffrage.csv) (47 lignes de postes, trois scénarios).

| Scénario | Total 5 ans (HT, ordres de grandeur) |
|---|---|
| Plateforme MédiSphère | ≈ 1,86 M€ (coût marginal ≈ 1,58 M€) |
| Nuage public HDS | ≈ 1,59 M€ |
| Infogérance HDS | ≈ 1,51 M€ |

Les enseignements que le chiffrage devait faire apparaître :
1. **Le matériel ne pèse rien** (≈ 4 % du coût complet) ; **les personnes pèsent la moitié** (≈ 48 %), les SMS ≈ 14 %, la quote-part de l'existant ≈ 13 %. Une variation de ± 50 % du prix des serveurs (le marché de la mémoire de 2026) change le total de ± 46 000 € ; ce qui compte pour ce matériel, c'est le **délai** de livraison (S06).
2. **Coût complet et coût marginal** sont deux chiffres différents pour deux décisions différentes : le marginal décide d'y aller, le complet fixe le prix. Oublier la quote-part, c'est vendre à perte en le découvrant dans trois ans.
3. **Sur le seul GHSV, les alternatives sont moins chères**, mais l'écart (≈ 270 000 à 350 000 € sur cinq ans) est à l'intérieur des incertitudes (personnes ± 30 %, clé de répartition, prix des tiers) et se resserre fortement au deuxième client (la plateforme rejoint le nuage et passe à moins de 6 % de l'infogérance, sensibilité du §5). La recommandation s'appuie alors sur ce que les chiffres ne disent pas : investissement de PAR2 utile à tous, PRA et preuves démontrables, pas de tiers sur le chemin d'un P1. **Une recommandation qui contredit le classement par le coût doit le dire et dire pourquoi.**
4. **Le SMS est un risque de marge** : inclus dans le prix (CCTP §11.3), il divise la marge par deux si son prix passe de 0,045 à 0,07 € : clause de révision.
5. Le **prix** (P1 165 000 €, P2 32 500 €/mois, P3 250 €/mois par tranche, P7 15 000 €) donne ≈ 2,16 M€ au sens du critère de prix du GHSV, pour une marge d'environ 14 %.

**Grille d'auto-évaluation** (sur 20)
- Hypothèses identifiées, prix datés et sourcés, « à vérifier » : 4
- Coût complet avec personnes chargées, astreinte, SMS, certifications, quote-part : 4
- Comparaisons sur le même périmètre, ce qui reste à notre charge, ce qui n'est pas comparable : 4
- Prix proposé cohérent avec le bordereau et le critère de jugement : 3
- Sensibilité qui identifie les variables décisives : 3
- Tableur cohérent avec le document : 2

**Explications**

Un coût complet (TCO) se construit **par les usages** (ce qu'il faut pour tenir chaque engagement) et non par les factures connues. Les postes oubliés sont toujours les mêmes : personnes au coût complet employeur (et non au salaire brut), astreinte, audits et certifications, coûts de sortie, coordination d'un tiers, quote-part de l'existant. Les prix publics sont des **ordres de grandeur** : un capstone qui affiche « 34 712 € » pour un serveur sans devis prétend à une précision qu'il n'a pas.

**Alternatives**
- Amortir le matériel sur sa durée de vie technique (6 à 7 ans) plutôt que sur le marché (5 ans) : baisse du prix, risque si le GHSV ne renouvelle pas.
- Facturer les SMS au réel (refacturation) : supprime le risque, mais le CCTP exige qu'ils soient compris dans le prix : à proposer en variante.
- Valeur actuelle nette avec un taux d'actualisation : utile pour comparer des scénarios aux profils de dépenses différents (CAPEX l'année 1 contre OPEX lissé).

**Pièges classiques**
- Comparer une plateforme complète sur deux sites à « quelques VMs » dans le nuage.
- Compter les salaires bruts, oublier l'astreinte et le samedi.
- Oublier la quote-part de l'existant, ou au contraire l'imputer en totalité au premier client.
- Prix sans date ni source, présentés comme des devis.
- Totaux du tableur qui ne correspondent pas au document.
- Recommander le moins cher sans regarder ce qui reste à notre charge (l'exploitation de Kubernetes dans le nuage, le pilotage d'un infogérant).

**En production chez MédiSphère**
Le modèle de coût est un script versionné (hypothèses en YAML → tableur), relu par la direction financière ; le coût réel du locataire est suivi chaque mois par `ms-showback` (F2) et comparé au modèle en comité interne.

---

### F7-S06 — Planning, risques et organisation du run

**Solution**

Documents de référence : [`planning.md`](fichiers/F7-S06/medisphere/docs/capstone/planning.md), [`risques.md`](fichiers/F7-S06/medisphere/docs/capstone/risques.md), [`run.md`](fichiers/F7-S06/medisphere/docs/capstone/run.md).

Les points qui font la différence :
1. **Le chemin critique passe par le développement et par le GHSV**, pas par l'infrastructure : API v1 conforme avant l'ouverture de la recette au GHSV (vendredi 12 février, dix jours ouvrés avant la production : EXP-06), trois fournitures du client (client OIDC, export d'essai, DPI en recette). Il ne tient que si le travail commence **avant la notification** (dès le lundi 4 janvier, notification attendue le 29) : décision de la direction, écrite comme risque (RSQ-02).
2. **Le planning se construit à rebours depuis le 1er mars** : go/no-go le vendredi 26 février avec des critères écrits, reprise finale le samedi 27 au soir, vérifications le dimanche.
3. **Ce qui ne sera pas prêt est écrit dans l'offre** : PAR2 à pleine capacité fin avril (matériel commandé à la notification), d'où une capacité de PRA transitoire réduite de mars à avril ; rappels et pièces jointes en vague 2. Un écart annoncé est une condition ; un écart découvert est une pénalité.
4. **Le RACI distingue A et R** et implique le GHSV (validation de la reprise, go/no-go, fourniture de son IdP).
5. **Les risques ont une racine commune** (calendrier court, peu de personnes) et des **indicateurs de déclenchement** datés ou mesurables, pas seulement une cotation.
6. **L'astreinte** : quatre personnes formées, c'est une semaine sur quatre sans marge ; le stagiaire n'est jamais seul ; recrutement d'un ingénieur à la notification ; support du samedi par rotation et **+0,5 ETP** ; hypercare de deux semaines après chaque vague.

**Grille d'auto-évaluation** (sur 20)
- Jalons datés réalistes, à rebours depuis le 1er mars, EXP-06 respectée : 4
- Chemin critique identifié (développement et fournitures du GHSV) et travaux avant notification : 4
- Écarts au 1er mars écrits et traités (PAR2, fonctions) : 3
- RACI cohérent (un seul A par activité) incluant le GHSV : 2
- Registre des risques : propriétaires nommés, réponses, indicateurs : 4
- Run : samedi, astreinte soutenable, P1-P3, rapport, montée en compétences : 3

**Explications**

Un planning imposé par une date se lit à l'envers : qu'est-ce qui doit être vrai la veille ? Ici, quatre semaines entre la notification et le 1er mars ne suffisent qu'à la condition d'avoir commencé avant : c'est un **pari** que la direction prend en connaissance de cause, avec un périmètre limité à ce qui sert le produit quoi qu'il arrive (l'API conforme, le modèle hospitalier). L'organisation du run est la partie que les jurys techniques négligent et que les clients regardent le plus : qui décroche à 3 h du matin, et sait-il quoi faire ?

**Alternatives**
- Proposer au GHSV un démarrage au 1er avril avec prolongation de l'outil actuel : plus sûr, mais dépend d'un tiers (le fournisseur sortant) ; à présenter comme plan B dans l'offre.
- Astreinte partagée avec un prestataire de supervision 24/7 (premier niveau de nuit) : réduit la charge de l'équipe, ajoute un intermédiaire sur le délai de 15 min.

**Pièges classiques**
- Un planning qui commence à la notification sans dire ce qui se passe avant.
- Oublier les dix jours ouvrés de recette du GHSV, ou le test d'intrusion avant l'ouverture.
- Une astreinte « de l'équipe » sans effectif ni rotation, un stagiaire seul la nuit.
- Des risques sans propriétaire nommé, ou cotés sans réponse.
- Des fournitures du client absentes du planning : le retard du GHSV devient le nôtre.

**En production chez MédiSphère**
Le planning vit dans l'outil de gestion de projet, mais ses jalons contractuels sont dans le dépôt (comme ici) pour que le rapport mensuel les reprenne. Le registre des risques est revu en comité de suivi et alimente le registre des risques de sécurité (F6) pour ceux qui le concernent.

---

## Points non testés en conditions réelles

- **Mesures de coût par requête** du lab de référence (0,72 et 0,23 vCPU pour 100 req/s, pods, latences des paliers) : imaginées, cohérentes avec la référence du M29 (158 req/s, p95 112 ms) ; remplace-les par les tiennes.
- **Ceph RGW avec OpenBao comme KMS** (SSE-KMS, moteur `transit`) : RGW documente Vault comme KMS (moteurs `kv` et `transit`) ; la compatibilité avec OpenBao 2.7 n'a pas été essayée (ADR-0371 la marque « à confirmer »).
- **`auto_rotate_period` et `rewrap`** du moteur `transit` : présents dans l'API documentée d'OpenBao ; non rejoués.
- **Défi ACME HTTP-01 sur un nom en CNAME** vers notre zone : comportement standard des AC ACME (la validation suit la résolution DNS) ; non essayé dans le lab (aucune exposition publique).
- **Prix** (octobre 2026, à vérifier) : tarifs publics de Proxmox (Basic 370 €, Standard 550 €, Premium 1 100 € par socket et par an) ; baie en centre de données d'un grand opérateur de l'ordre de 2 700 à 5 500 €/mois selon la puissance ; test d'intrusion de 6 000 à 15 000 € ; certification HDS initiale de 25 000 à 60 000 € ; salaires d'ingénieur DevOps confirmé à Paris de l'ordre de 55 000 à 72 000 € bruts ; hausse des prix contractuels de la mémoire des serveurs d'environ 90 % au premier trimestre 2026 (TrendForce, prévision révisée de février 2026 ; + 60 % dans celle de janvier). Le prix du SMS (0,045 €), du nuage public HDS (5 000 €/mois) et de l'infogérance (9 000 €/mois) sont des **ordres de grandeur supposés** pour ce périmètre, sans devis. Tarifs de Proxmox relus sur la page officielle `proxmox.com/proxmox-ve/pricing` (Community 120 €, Basic 370 €, Standard 550 €, Premium 1 100 € par socket et par an).
- **Effectifs** (1,2 ETP d'exploitation, 0,5 ETP de support le samedi) et **charge de développement** (≈ 173 jours) : estimations de la fiction, à confronter à ton équipe.
- **Délais de livraison** du matériel (8 à 12 semaines) : ordre de grandeur supposé pour un marché tendu, non vérifié auprès d'un constructeur.
