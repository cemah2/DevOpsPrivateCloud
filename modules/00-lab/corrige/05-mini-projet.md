# Module 00 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

---

### M00-E50 — Mini-projet : livrer le socle MédiSphère v0

**Solution**

Il n'y a pas « une » solution : il y a un socle sain et un dossier qui permet à quelqu'un d'autre de l'exploiter. Un exemple de dossier complet est fourni dans [`fichiers/M00-E50/docs/socle/`](fichiers/M00-E50/docs/socle/) :

| Fichier | Ce qu'il illustre |
|---|---|
| [`README.md`](fichiers/M00-E50/docs/socle/README.md) | index, périmètre, état, **risques connus** (points uniques de défaillance) |
| [`architecture.md`](fichiers/M00-E50/docs/socle/architecture.md) | schéma Mermaid + ASCII, composants, chemins critiques |
| [`inventaire.md`](fichiers/M00-E50/docs/socle/inventaire.md) | hôtes, VMs, stockages, comptes avec **emplacement** des secrets, clés publiques WireGuard |
| [`matrice-flux.md`](fichiers/M00-E50/docs/socle/matrice-flux.md) | matrice **exemplaire** : chaque flux relié à sa règle, refus notables, dettes (règles de transition) |
| [`capacite.md`](fichiers/M00-E50/docs/socle/capacite.md) | calcul de la mémoire disponible, projection par profil, mécanismes, règles d'exploitation, disque PBS |
| [`runbooks/`](fichiers/M00-E50/docs/socle/runbooks/) | RB-003 et RB-004 complets (issus des pannes), RB-001/002 à reprendre de M00-E25 |
| [`adr/`](fichiers/M00-E50/docs/socle/adr/) | ADR-0003 (SDN) ; ADR-0001/0002 : ceux de M00-E33 ([`fichiers/M00-E33/`](fichiers/M00-E33/)) |
| [`tests/restauration.md`](fichiers/M00-E50/docs/socle/tests/restauration.md) | feuille de temps, RTO mesuré, RPO constaté, écarts |
| [`gitignore-exemple`](fichiers/M00-E50/gitignore-exemple) | filet de sécurité contre la publication de secrets |

Le post-mortem d'exemple est celui de M00-E46 ([`fichiers/M00-E46/post-mortem-exemple.md`](fichiers/M00-E46/post-mortem-exemple.md)).

**Démarche recommandée** (8 à 12 h) :

1. **Assainir d'abord** (1 à 2 h) : `lab/bin/check 00 50`, puis traiter chaque KO à la racine. Les KO typiques à ce stade : une VM sandbox oubliée (5044, 5048, 509x), une panne d'exercice encore marquée active, `startup: order` absent, l'agent QEMU non démarré dans une VM, une sauvegarde de plus de 48 h, des règles de transition jamais retirées (ce n'est pas un KO du contrôle, mais Sophie les trouvera).
2. **Inventaire à partir de la réalité** (1 h) : sorties de `pvesh get /cluster/resources --type vm --output-format json`, `qm config`, `pvesm status`, `pveum user list`, `proxmox-backup-manager acl list`. Un inventaire écrit de mémoire diverge dès la première ligne.
3. **Matrice des flux à partir des règles** (1 à 2 h) : `nft list ruleset` sur `gw01`, une ligne par règle d'acceptation, plus les refus notables. Chaque écart entre ta matrice idéale et tes règles est soit une règle à corriger, soit une dette à documenter.
4. **Schéma** (1 h), **capacité** (1 h, mesures comprises), **test de restauration** (1 h), **runbooks et ADR** (2 h, en réutilisant M00-E25, M00-E33 et tes journaux du palier 4).
5. **Relecture croisée** (30 min) : lis le dossier comme un nouvel arrivant. Chaque fois que tu dois deviner quelque chose, il manque une phrase.
6. **Livraison** : `git status` propre, recherche de secrets, `git tag -a socle-v0 -m "Socle MédiSphère v0"`.

```
admin@adm01:~/medisphere$ git grep -nIE 'PrivateKey|BEGIN .*PRIVATE|password|secret' -- docs/ || echo "rien de suspect"
admin@adm01:~/medisphere$ git status --short && git tag -a socle-v0 -m "Socle MédiSphère v0 — recette AAAA-MM-JJ"
```

> ⚠️ **Attention** : si un secret a été commité, le supprimer dans un nouveau commit ne suffit pas, il reste dans l'historique. Avant le module 01 (où le dépôt sera poussé sur GitLab), réécris l'historique **et** considère le secret comme compromis : rotation obligatoire (jeton, clé WireGuard, clé SSH).

**Grille d'évaluation de la revue** (Claire Morel ; à utiliser en auto-évaluation si tu travailles seul)

Barème sur 100. Seuil de recette : 70, **et** aucun critère éliminatoire.

*Critères éliminatoires* (recette refusée quel que soit le total) : contrôle global non vert ; secret présent dans le dépôt (même dans l'historique) ; aucune preuve de restauration ; adresse, VMID ou nom contraire à PLAN.md sans ADR.

| # | Axe | Points | Insuffisant (0-40 %) | Attendu (60-80 %) | Excellent (100 %) |
|---|---|---|---|---|---|
| 1 | Socle sain et hygiène | 10 | KO corrigés à chaud, sans cause | contrôle vert, causes des KO expliquées | idem + dettes recensées (règles de transition, VMs sandbox) avec plan de résorption |
| 2 | Architecture | 10 | schéma image seul, incomplet | schéma texte complet (deux sites, VNets, tunnels, chemin de sauvegarde) | idem + chemins critiques et points uniques de défaillance argumentés |
| 3 | Inventaire | 10 | liste de VMs | toutes les colonnes, cohérent avec `qm config` | idem + comptes/jetons avec emplacement et rotation, clés publiques, généré ou vérifiable par script |
| 4 | Matrice des flux | 15 | liste de ports | chaque flux justifié et relié à une règle ; politique par défaut ; ICMP traité | idem + refus notables, dettes, autres pare-feu (`pve01`, `pbs01`), vérification ligne à ligne démontrée |
| 5 | Runbooks | 15 | procédures narratives non testées | 4 runbooks au format standard (déclencheur, étapes, vérification, retour arrière, escalade) | idem + runbooks issus d'incidents réels, testés par quelqu'un d'autre ou rejoués en revue |
| 6 | ADR | 10 | descriptions sans alternatives | 3 ADR avec options, décision, conséquences | idem + révision honnête d'un ADR de M00-E33 à la lumière de l'expérience |
| 7 | Restauration | 10 | « ça marche » sans mesure | feuille de temps, RTO, RPO, comparaison à l'objectif | idem + écarts et actions, test réalisé avec un observateur |
| 8 | Capacité | 10 | reprise des chiffres de PLAN | mesures réelles, calcul de la mémoire disponible, 4 profils | idem + mécanismes de récupération chiffrés, règles d'exploitation, projection disque PBS |
| 9 | Présentation et défense | 10 | lecture du dossier | 10 min structurées, démonstration réussie | idem + réponses précises aux questions, limites et risques assumés |

**Démonstrations que Claire peut demander** (une seule, tirée sur place) :
- restaurer un fichier de `/etc` de `dns01` depuis PBS (M00-E23) ;
- montrer, pour une ligne de la matrice choisie par Sophie, la règle nftables correspondante et son compteur ;
- injecter une panne (`lab/bin/break 00 3X`, variante tirée) et appliquer le runbook correspondant ;
- créer une VM sandbox avec RB-001, puis la supprimer proprement ;
- prouver que la sauvegarde de cette nuit est chiffrée et vérifiée.

**Questions de revue typiques et éléments de réponse attendus**

| Question | Ce qu'une bonne réponse contient |
|---|---|
| « Si `gw01` tombe maintenant, qu'est-ce qui s'arrête ? » | tout l'accès au lab, DNS récursif (pas la résolution locale depuis INFRA), NTP, VPN, tunnel donc sauvegardes ; PRA : restauration de `gw01` depuis PBS… qui passe par `gw01` → accès à PBS par le LAN maison (SSH de secours, interface PBS à rouvrir temporairement) ; d'où la priorité VRRP du module 07 |
| « Combien de temps pour reconstruire `dns01` si PBS est perdu aussi ? » | template + cloud-init + configuration dnsmasq versionnée dans le dépôt : temps estimé et, idéalement, mesuré ; c'est l'argument pour l'IaC des modules 04-05 |
| « Pourquoi ces deux règles de transition sont-elles encore là ? » | réponse honnête (dette), date de retrait, ticket |
| « Qui a accès à la clé de chiffrement des sauvegardes ? » | emplacement, droits, copie papier, procédure de perte (M00-E36) |
| « Le profil plateforme tient-il vraiment ? » | marge de ~1 Gio : conditions (ARC réduit, pas d'autre VM), alerte à 90 %, plan B (réduction des nœuds) |

**Explications**

Le dossier n'est pas un rapport de stage sur ce que tu as appris : c'est un outil d'exploitation. Chaque document répond à une question qu'un collègue se posera un jour, souvent sous pression : « par où passe ce flux ? », « où est le secret ? », « comment je restaure ? », « est-ce que je peux lancer ce profil ? », « pourquoi a-t-on fait ce choix ? ». Le contrôle automatique vérifie la **présence** et quelques marqueurs de complétude ; la revue vérifie la **justesse** et l'**utilité**.

La matrice des flux est le document le plus important pour Sophie : c'est la preuve, exigée par ISO 27001 et HDS, que chaque ouverture réseau est voulue et justifiée. Une matrice déconnectée des règles réelles ne prouve rien ; d'où le rapprochement ligne à ligne et l'intérêt des `comment` systématiques dans nftables.

**Alternatives**
- Schéma : draw.io (fichier `.drawio` versionnable) ou diagrams-as-code (Mermaid, D2, PlantUML). Le format texte gagne pour les revues de MR (diff lisible).
- Inventaire : généré par script depuis l'API Proxmox (module 02), puis remplacé par NetBox comme source de vérité (module 06).
- Matrice des flux : tableur pour la revue sécurité, mais la source de vérité doit rester versionnée avec la configuration ; à terme, la matrice **génère** les règles (module 04) plutôt que l'inverse.
- ADR : format MADR, ou outil `adr-tools`.

**Pièges classiques**
- Documenter l'architecture **voulue** au lieu de l'architecture **réelle** (les règles de transition « oubliées » de la matrice).
- Recopier PLAN.md au lieu de mesurer (capacité).
- Un test de restauration ancien ou non daté présenté comme preuve.
- Des secrets dans les exemples de configuration (clé WireGuard copiée « pour mémoire »).
- Des runbooks jamais exécutés par quelqu'un d'autre : à la première utilisation réelle, une étape manque toujours.
- Un dépôt non commité ou une étiquette posée avant les dernières corrections.

**En production chez MédiSphère**

Le dossier de socle est le premier élément de la documentation d'exploitation exigée par l'audit HDS. Au module 01, il est poussé sur GitLab, protégé par revue de MR (Claire approuve l'architecture, Sophie la matrice des flux), et ses contrôles (liens, secrets, cohérence matrice/règles) entrent en CI. Chaque module suivant ajoute sa brique au dossier, et le contrôle global grandit avec lui : le « socle v1 » de fin de bloc A intégrera PKI, GitLab, NetBox, MinIO et l'IaC.
