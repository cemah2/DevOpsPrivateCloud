# Final F5 — Phase 1 : Analyser — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. Les livrables de cette phase sont des documents : ceux de référence sont **des** réponses défendables, pas **la** réponse. Ils se jugent sur la justification des chiffres, la complétude des dépendances et la cohérence avec ce que `hp01` peut porter.

**Fichiers** : [`fichiers/F5-S01/`](fichiers/F5-S01/) et [`fichiers/F5-S02/`](fichiers/F5-S02/), sous `medisphere/…` = dépôt `plateforme/medisphere`.

---

### F5-S01 — Analyse d'impact et objectifs de reprise

**Solution**

Documents de référence : [`bia.md`](fichiers/F5-S01/medisphere/docs/pra/bia.md) et [`objectifs.md`](fichiers/F5-S01/medisphere/docs/pra/objectifs.md).

Démarche :

1. **Une échelle d'impact commune** (patients, cabinets, conformité, réputation ; quatre niveaux) : sans elle, « grave » n'a pas le même sens pour Julien et pour Sophie.
2. **Les impacts dans le temps**, service par service, à 1 h, 4 h, 1 jour, 3 jours, chiffrés à partir de la volumétrie donnée (≈ 9 000 rendez-vous par jour, 30 % en deux heures : ≈ 22 prises par minute en pointe). Le chiffre utile n'est pas « combien de rendez-vous par heure » mais **à partir de quand le contournement manuel ne tient plus** : pour MédiAgenda, la saturation des standards à la demi-journée.
3. **DMIA et PDMA** (durée d'interruption et perte de données maximales admissibles) déduites des impacts ; puis **RTO et RPO** posés **sous** elles, avec une marge, et rattachés à une capacité technique qui les rend tenables.
4. **Le RPO de MédiAgenda se calcule** sur le chemin d'une écriture : validation → segment de WAL archivé au plus `archive_timeout` (5 min, valeur de CloudNativePG) après → objet dans `s3-01` (secondes) → copié par `filer.sync` (secondes à une minute, à mesurer en S04) → rejoué. Pire cas ≈ 7 min ; l'objectif de 15 min garde une marge. Le RPO de référence est donc **justifié**, pas seulement accepté.
5. **Le périmètre** : MédiVisio et Data sont tranchés **par écrit** (hors v1, avec la condition qui les ferait entrer). La CI, l'observabilité et l'identité sont traitées comme des services avec leur propre mode dégradé (gel des livraisons ; supervision **minimale** de PAR2 : la sonde en permanence, Prometheus, Alertmanager et Mailpit de secours sur `adm02` mis en service pendant un PRA ; bris de glace).
6. **La définition de la reprise** : une création de rendez-vous réussie par le **nom global**, portant `X-MediSphere-Site: par2`, observée par la sonde **et** par un utilisateur hors du lab. On distingue trois horloges (T0, T décision, T reprise) : l'exercice mesurera les deux durées.

**Explications**

- Une BIA sert à **arbitrer** : elle dit où mettre l'argent et les heures. Ici, elle justifie que MédiAgenda passe en premier (seul service dont la DMIA est inférieure à une journée), que Legacy-RDV garde son RPO de 24 h (une journée se ressaisit), et que MédiNotif n'a rien à protéger (tout se recalcule).
- Le RTO n'est pas un temps technique : il contient la **détection** et la **décision**. Si la reprise technique prend 2 h 30 et que le RTO est de 4 h, la décision doit tomber dans l'heure : c'est ce que fixera RB-350 (S07).
- Écrire ce qu'on ne sait **pas** tenir (RTO < 1 h, haute disponibilité à PAR2) est une information pour Claire, pas un aveu d'échec.

**Alternatives**
- BIA par **processus métier** (« prendre un rendez-vous », « consulter un document ») plutôt que par application : plus juste quand une application sert plusieurs processus ; ici, la correspondance est presque une pour une.
- Objectifs **par niveau de service** (or, argent, bronze) appliqués aux applications : plus simple à gouverner quand il y a beaucoup d'applications ; prématuré avec quatre.
- RPO de MédiAgenda à quelques secondes (réplication en flux à travers `wg0`) : possible, au prix d'une base de production exposée à un second site ; écarté en v1, cité dans l'ADR-0350.

**Pièges classiques**
- Copier les objectifs de référence sans les relier à la BIA ni aux capacités : un RPO de 15 min sans calcul du chemin des WAL est un vœu.
- Confondre RTO et DMIA (« on accepte 4 h, donc le RTO est de 4 h ») : aucune marge pour la décision.
- Oublier la **perte** de données dans la BIA (seulement l'arrêt) : c'est elle qui fixe le RPO.
- Une fin de reprise non mesurable (« les applications sont reparties »).
- Mettre « tout » dans le périmètre : `hp01` ne le porte pas, et le jour J on ne sait plus par quoi commencer. À l'inverse, exclure **toute** supervision : le site de repli tourne alors à l'aveugle, et le premier incident pendant le PRA est signalé par un patient.
- Laisser MédiVisio et Data sans réponse écrite : les équipes le découvriront le jour du sinistre.

**En production chez MédiSphère**
La BIA est revue chaque année avec les responsables métier et signée par la direction ; les objectifs entrent dans les contrats des cabinets (annexe HDS) et dans le registre des risques ; chaque nouveau service passe par une mini-BIA à sa mise en production (modèle `nouveau-service` de Backstage, M28).

---

### F5-S02 — Les dépendances de la reprise et l'architecture de PAR2

**Solution**

Documents de référence : [`dependances.md`](fichiers/F5-S02/medisphere/docs/pra/dependances.md) et [`ADR-0350-site-de-repli-par2.md`](fichiers/F5-S02/medisphere/docs/pra/adr/ADR-0350-site-de-repli-par2.md).

1. **L'inventaire** (26 dépendances dans la référence) se construit en remontant deux chemins : celui d'une requête de patient (nom → DNS → Gateway → certificat → image → Secret → base) et celui de l'opérateur (VPN → SSH → mots de passe → jetons → kubeconfig). Pour chaque dépendance, la colonne qui compte le plus est la dernière : **ce qu'il faut avoir en main pour s'en servir**. C'est elle qui remplit l'enveloppe de reprise (S05).
2. **Les boucles** : la référence en traite huit, dont trois incontournables :
   - le coffre et son descellement (OpenBao → `kms01` → parts Shamir → personnes) ;
   - l'état OpenTofu de PAR2 sur une machine qu'il décrit (amorçage par un état local, puis migration) ;
   - les mots de passe d'Ansible Vault **dans OpenBao** depuis le M25 : le jour où il n'y a plus d'OpenBao, plus d'Ansible Vault, donc plus de clé `age` pour déchiffrer l'instantané du coffre… Seule une copie hors du coffre (enveloppe) casse la boucle.
   Les cinq autres (confiance ACME, ESO et coffre de secours, Argo CD et ses identifiants, délégation `par1`, clé de chiffrement de PBS) sont moins visibles et tout aussi bloquantes.
3. **L'ordre de redémarrage** par vagues avec conditions de passage observables, et un chemin critique estimé (≈ 2 h 30) qui sera remplacé par les mesures de l'exercice.
4. **Le dégradé** : ce qui ne marche plus sans PAR1 et **combien de temps on tient** (15 jours de certificats ACME, deux semaines de DNSSEC, gel des livraisons).
5. **L'ADR-0350** compare quatre options sur les mêmes axes (RTO, RPO, coût, entretien, risque pour les sauvegardes, retour, conformité), décide B (tiède sur `hp01`), écrit ce qu'on refuse et ce qu'on accepte, et fixe des conditions de révision mesurables.

**Explications**

- Une reprise échoue rarement sur ce qui est dans le schéma (la base, le cluster) : elle échoue sur ce qui n'y est pas — une clé, un mot de passe, une délégation DNS, un certificat qui expire, un outil qui va chercher son module sur un serveur mort. D'où la règle : **toute dépendance a une forme à PAR2 et un contrôle**.
- La **topologie distribuée** de CloudNativePG est retenue parce qu'elle seule permet un retour **contrôlé** : rétrogradation de PAR2 avec un jeton, promotion de PAR1 qui attend d'avoir rejoué jusqu'au jeton (documentation 1.30, « Distributed Topology »). Le réplica autonome du M27 ne se promeut que sans retour : l'ancien primaire est à reconstruire.
- Le choix des **L2 announcements** à PAR2 n'est pas cosmétique : il n'y a pas de routeur BGP à PAR2 ; `hp01` est sur le même segment (`vmbr2`) que le nœud et apprend l'adresse de la Gateway par ARP.

**Alternatives**
- Cartographier par un outil (NetBox, graphe Backstage) plutôt qu'à la main : utile pour garder la carte à jour ; insuffisant pour les dépendances humaines (gardiens, mots de passe).
- Garder les secrets de reprise dans un **coffre externe** (gestionnaire de mots de passe d'entreprise hébergé ailleurs) plutôt qu'une enveloppe physique : plus pratique ; ajoute une dépendance (compte, MFA, éditeur) qu'il faut elle-même mettre dans l'enveloppe.
- Faire de `dns03` le **primaire** de `par2.medisphere.internal` dès la veille : le site serait autonome pour ses propres noms ; écarté pour garder un seul chemin d'écriture DNS (OpenTofu → `dns01`) en temps normal.

**Pièges classiques**
- S'arrêter aux dépendances techniques visibles et oublier le temps, la confiance, l'outillage (modules OpenTofu téléchargés depuis `git01`, fournisseur NetBox, mots de passe d'Ansible Vault).
- Un ordre de redémarrage sans conditions de passage : chacun « avance » sans savoir si la vague précédente a vraiment fini.
- Ne pas voir que les **sauvegardes PBS sont chiffrées** et que la clé est sur `pve01`.
- Une option « chaud » écartée sans dire ce qu'elle coûterait : Claire ne peut pas arbitrer.
- Un ADR sans conséquences acceptées (« nœud unique », « pas de supervision ») : le jour de l'exercice, chacun les découvre comme des défauts.

**En production chez MédiSphère**
La carte des dépendances vit à côté de la matrice des flux et est relue à chaque ADR ; les dépendances « pour s'en servir » alimentent le registre des secrets de bris de glace (Sophie) ; l'ADR-0350 est présenté au comité de direction avec le chiffrage de l'option D, base du budget de l'année suivante.

---

## Points non testés en conditions réelles

- Les volumes de MédiAgenda et de MédiDoc (rendez-vous par jour, dépôts) sont ceux du scénario, pas des mesures du lab ; ta BIA peut s'appuyer sur les compteurs réels de `mediagenda_http_requests_total` si ton lab a de la charge (k6, M29).
- La durée de validité des signatures DNSSEC dépend de la configuration de PowerDNS (rotation des signatures, `SOA-EDIT` `INCEPTION-INCREMENT` du M06) : mesure-la sur ton `dns01` (`dig +dnssec`, champ d'expiration des RRSIG) avant de reprendre « ≈ 2 à 3 semaines ».
- Les temps de référence des vagues (≈ 2 h 30) sont estimés ; seuls la répétition (S08) et l'exercice (S09) les établissent.
- Les ordres de grandeur de coût de l'ADR-0350 (serveur, IaaS HDS) sont indicatifs (octobre 2026) et **à vérifier** : ce ne sont pas des devis.
