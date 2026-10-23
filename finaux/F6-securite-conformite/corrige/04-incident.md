# Final F6 — Phase 4 : L'incident — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. F6-S11 est un `BF` : la section est une **démarche de
> diagnostic** (symptômes → hypothèses → commandes → cause → correctif → prévention), **chaque variante
> traitée**. Les `LIBRE` (S10, S12) donnent une solution de référence ; le `RED` (S13) est argumenté.

**Validé hors du lab** (à la rédaction, 23/10/2026) :
- `break-S11.sh`, `ms-verifier-kit-forensique` : `bash -n` et `shellcheck -x` ;
- logique de l'injection relue contre les règles Falco du M26 (shell interactif, connexion sortante non
  prévue), les macros des règles par défaut de Falco (`open_read` exige une ouverture **réussie**,
  `fd.num>=0` : une lecture d'un jeton absent ne déclenche rien ; `container_entrypoint`, `shell_procs`),
  le code de falcosidekick (étiquettes `source="falco"`, `alertname` = nom de la règle, `k8s_ns_name`…)
  et la politique de quarantaine (M26-E33) ;
- pseudo-terminal de l'injection (`script -qec … </dev/null` sous `timeout`) et commande passée au
  conteneur : rejoués localement avec un faux `kubectl` (util-linux 2.39) ;
- manifestes (NetworkPolicy injectée, runbooks) : YAML/Markdown valides.

**Points non testés en conditions réelles** : en fin de corrigé. Signale tes retours.

**Fichiers** : [`fichiers/F6-S10/`](fichiers/F6-S10/), [`fichiers/F6-S12/`](fichiers/F6-S12/),
[`fichiers/F6-S13/`](fichiers/F6-S13/). Panne : [`pannes/break-S11.sh`](pannes/break-S11.sh).

---

### F6-S10 — Prêts pour l'incident

**Solution** (solution de référence)

Fichiers : [`RB-360-reponse-incident.md`](fichiers/F6-S10/medisphere/docs/securite/incidents/runbooks/RB-360-reponse-incident.md), [`RB-361-forensique-conteneur.md`](fichiers/F6-S10/medisphere/docs/securite/incidents/runbooks/RB-361-forensique-conteneur.md), [`ms-verifier-kit-forensique`](fichiers/F6-S10/outils/bin/ms-verifier-kit-forensique), [`2027-01-exercice-table.md`](fichiers/F6-S10/medisphere/docs/securite/incidents/exercices/2027-01-exercice-table.md), [`ECA-3605-reponse-incident.md`](fichiers/F6-S10/medisphere/docs/conformite/ecarts/ECA-3605-reponse-incident.md).

1. **Trois niveaux de runbook, pas un de plus** : RB-262 (M26) reste le détail « conteneur compromis »
   (isolement, collecte, escalade). RB-360 est le niveau **au-dessus** : quand déclencher, gravités,
   rôles (responsable, collecte, RSSI, DPO, communication, support), rythme des points, et le volet
   réglementaire (quand on se pose la question CNIL/clients/CERT Santé, qui décide). RB-361 est le
   niveau **en dessous** : le détail de la collecte forensique d'un conteneur (reprise et généralisation
   de la section 4 de RB-262). Les trois se citent ; on ne duplique rien.
2. **Le kit se vérifie, il ne se déclare pas** : `bin/ms-verifier-kit-forensique` (`plateforme/outils`,
   pipeline planifié `kit:verifier` sur `runner01`) contrôle que l'image d'outils
   `plateforme/outils-forensique:v1.0.0` (netshoot recopié par empreinte dans Harbor et signé par la CI
   avec `transit/cosign-medisphere`) existe et que sa signature est valide, que l'identité de dépôt
   (`preuves`) **écrit** un objet d'essai et **échoue** à en supprimer la **version** (une suppression
   sans version ne ferait que poser un marqueur de suppression dans un compartiment versionné : le test
   serait faux), et que les modèles (chronologie, manifeste) sont présents. Le bris de glace ne s'éprouve
   **pas** dans le pipeline (son usage fait sonner `AuditBrisDeGlace`, M24) : option `--bris-de-glace`, à
   la main, annoncée, en lecture (RB-240). Lancé à froid, le contrôle doit pouvoir passer au rouge.
3. **Capture éprouvée** : sur un pod d'essai (`wb-essais`), tentative de point de contrôle du kubelet
   (`POST /checkpoint/<ns>/<pod>/<conteneur>`) ; si le runtime l'implémente (containerd + CRIU), on
   obtient l'archive dans `/var/lib/kubelet/checkpoints/` ; sinon `500`, et on **replie** sur la copie du
   système de fichiers (conteneur éphémère, `/proc/1/root`) et des journaux. Le résultat (dans un sens ou
   l'autre) est écrit dans RB-361 — l'« à confirmer » du M26 est tranché.
4. **Exercice de table** : un scénario (« un shell inattendu dans un conteneur de prod ») joué sur table,
   chronométré, qui révèle les trous (qui appelle le DPO la nuit ? où est l'identité de dépôt des
   preuves ? qui décide de la quarantaine ?). Les trous deviennent des actions datées.
5. **ECA-3605 clos** : fiche [`ECA-3605-reponse-incident.md`](fichiers/F6-S10/medisphere/docs/conformite/ecarts/ECA-3605-reponse-incident.md),
   en-tête `statut: clos`, `clos-le`, `preuve:` = le lot `ms-preuves` qui contient P-CTL-01 (dernier
   `kit:verifier` réussi) ; runbooks, résultat de la capture et compte rendu de l'exercice cités.

**Explications**
- Un incident ne se prépare pas pendant qu'il a lieu. La valeur de RB-262 était restée théorique
  (une seule exécution sur un pod d'essai) : l'écart ECA-3605 n'est pas « pas de runbook » mais « pas de
  **capacité** éprouvée ». D'où un contrôle qui prouve que le kit marche, et un exercice qui prouve que
  l'équipe sait l'utiliser.
- **La capture avant la suppression.** La raison d'être de RB-361 est de figer l'état vivant (mémoire,
  processus, connexions, fichiers temporaires) avant toute éradication. Un pod supprimé trop tôt est une
  enquête impossible : c'est exactement ce que F6-S11 et F6-S12 mettent à l'épreuve.

**Alternatives**
- Un seul runbook géant au lieu de trois : illisible à 3 h du matin ; la séparation déclenchement /
  conteneur / capture suit les trois moments de l'incident.
- Capture systématique par instantané PBS du nœud : lourd et tardif ; le point de contrôle (ou la copie
  ciblée) est plus rapide et suffisant pour un conteneur. L'instantané du nœud reste la pièce de dernier
  recours.

**Pièges classiques**
- Déclarer le kit « prêt » sans contrôle automatisé : le jour J, l'identité de dépôt a expiré.
- Éprouver les comptes de bris de glace **en écriture** : c'est une modification non tracée (RB-240 dit
  lecture).
- Oublier que le point de contrôle dépend du runtime : sans repli écrit, l'équipe est bloquée si `500`.
- Un exercice joué par celui qui a écrit la procédure : il ne révèle aucun trou (le faire jouer par
  quelqu'un d'autre).

**En production chez MédiSphère**
L'exercice de table est annuel, avant l'audit ; une trousse d'astreinte sécurité (dérivée du F3) est à
jour ; le contrôle du kit tourne en CI et alerte si une image d'outils ou une identité expire.

---

### F6-S11 — Panne : un conteneur compromis

> `BF` — démarche de diagnostic. Deux vecteurs (variantes) ; les gestes de confinement sont les mêmes,
> la **portée** diffère. Injection : [`pannes/break-S11.sh`](pannes/break-S11.sh).

**Symptômes**
Courriels d'Alertmanager (source `falco`) pour `mediagenda-recette` : « MédiSphère — shell interactif
dans un conteneur applicatif » (et la règle par défaut « Terminal shell in container », priorité
`NOTICE`, si le seuil de falcosidekick la laisse passer), puis « MédiSphère — connexion sortante vers
un port non prévu » vers une adresse inconnue (`10.10.99.66:4444`), répétée chaque minute (l'alerte
reste active ; Alertmanager ne renvoie pas un courriel par connexion). Aucune intervention annoncée.
**Pas** d'alerte « lecture du jeton de compte de service » : le shell a bien lancé
`cat /var/run/secrets/kubernetes.io/serviceaccount/token`, mais l'API de MédiAgenda ne monte pas de
jeton (norme « charge sûre » C6, `automountToken: false` du chart) ; l'ouverture échoue, et la macro
`open_read` de Falco (comme la politique Tetragon `fichiers-sensibles`) ne voit que les lectures réussies.
Seul l'événement `process_exec` de Tetragon (`cat` et son argument) trahit la tentative : la norme C6 a
tenu, c'est un point « ce qui a marché » du post-mortem.

**Hypothèses** (dans l'ordre où on les écarte)
1. Faux positif — un développeur débogue en recette (un `exec` humain déclenche « shell interactif »).
2. Vrai positif, entrée par une **identité de l'API** (jeton de compte de service fuité).
3. Vrai positif, des **règles de sortie trop larges** laissent le trafic atteindre une destination interdite.

**Commandes de diagnostic** (dans l'ordre ; lecture seule, rien n'est supprimé)

*Qualifier (15 min).* Quel pod, quel nœud, quelle image, depuis quand :
```
admin@adm01:~$ kubectl -n mediagenda-recette get pods -o wide
admin@adm01:~$ kubectl -n mediagenda-recette get pod <POD> -o jsonpath='{.status.containerStatuses[*].image}{"\n"}{.status.containerStatuses[*].restartCount}{"\n"}'
```
*Qui a ouvert le shell, qui a appelé l'API* — journal d'audit de l'API (locataire `audit` de Loki) :
```logql
{job="kubernetes-audit"} | json | objectRef_subresource="exec" | objectRef_name="<POD>"
{job="kubernetes-audit"} | json qui="user.username", verbe="verb", ressource="objectRef.resource", sous="objectRef.subresource", outil="userAgent", ip="sourceIPs[0]", code="responseStatus.code" | qui=~"system:serviceaccount:mediagenda-recette:.*" | line_format "{{.verbe}} {{.ressource}} {{.code}} {{.outil}} {{.ip}}"
{job="kubernetes-audit"} | json | objectRef_resource="serviceaccounts" | objectRef_subresource="token" | objectRef_namespace="mediagenda-recette"
```
(`| json` sans paramètre ignore les tableaux : `sourceIPs` s'extrait par `sourceIPs[0]`.)
> Dans le lab, l'`exec` (et, en variante 1, l'émission du jeton `create serviceaccounts/token`) apparaît
> au nom de l'identité d'administration qui a lancé `lab/bin/break` (comme en F6-S04) : elle joue
> l'attaquant. En vrai, ce serait l'identité de l'attaquant ou celle qu'il a volée — et la question
> suivante de l'enquête. Aucun ticket `CHG-` ni `INC-` ne l'annonce → ce n'est pas une intervention
> légitime : vrai positif.
- Si le **compte de service** de l'API (`system:serviceaccount:mediagenda-recette:…`) fait des requêtes
  de reconnaissance (`selfsubjectrulesreviews` de `auth can-i --list`, `list pods` refusé en `403`) avec
  un `userAgent` **`kubectl/…`** (MédiAgenda n'utilise pas `kubectl`, et son pod ne monte même pas de
  jeton) et depuis une adresse qui n'est pas celle d'un pod (`sourceIPs` : un nœud de contrôle, appel
  entré par la VIP de l'API, venu de l'extérieur du cluster), précédées d'un `create serviceaccounts/token`
  pour ce compte : un jeton a été **émis** pour le compte de l'application et utilisé hors du cluster →
  **vecteur 1** (jeton fuité).
*Ce qui a été lancé* — Falco et Tetragon :
```logql
{service="falco"} | json | output_fields_k8s_pod_name="<POD>"
{service="tetragon"} | json | process_exec_process_pod_name="<POD>"
```
(`k8s_pod_name` n'est pas une étiquette de flux — liste fermée du M22 — mais un champ du JSON de Falco,
sous `output_fields`.) Tetragon donne l'arbre : le `sh` a lancé `cat
/var/run/secrets/kubernetes.io/serviceaccount/token` (en échec : pas de jeton monté), `base64`, puis une
boucle `python3` détachée. (Un ou plusieurs `python3 -c` courts, sans terminal, juste après : c'est le
script d'injection qui vérifie que la boucle tourne — artefact du lab, à noter comme tel.)
*Où va la connexion, aboutit-elle* — Hubble (c'est ici que les deux vecteurs se séparent) :
```
admin@adm01:~$ hubble observe --pod mediagenda-recette/<POD> --to-ip 10.10.99.66 --last 50
```
- **Vecteur 1** : verdict `DROPPED` (le refus par défaut de l'espace tient) → la connexion **n'aboutit
  pas** ; le C2 ne journalise rien.
- **Vecteur 2** : verdict `FORWARDED` → une politique autorise la sortie. La trouver, puis chercher ce
  qui la laisse passer **après** le cluster (la bordure refuse par défaut VLAN 40 → VLAN 99) :
  ```
  admin@adm01:~$ kubectl -n mediagenda-recette get networkpolicy
  admin@adm01:~$ kubectl -n mediagenda-recette get networkpolicy legacy-sortie-large -o yaml
  admin@gw01:~$ sudo nft -a list chain inet filter forward | grep -n 10.10.99.66
      ip saddr { 10.10.40.0/24, 10.240.0.0/16 } ip daddr 10.10.99.66 tcp dport 4444 counter packets 12 bytes 720 accept comment "legacy-sortie-recette" # handle 91
  admin@gw01:~$ sudo grep -c legacy-sortie-recette /etc/nftables.conf
  0
  ```
  L'annotation de la politique montre une vieille MR (`MR !218 (2026-03)`, « sortie temporaire, jamais
  retirée ») ; la règle jumelle de la bordure est active sur `gw01` **et** `gw02`, absente de la
  configuration persistée et du code : **vecteur 2** (règles de sortie trop larges, à deux couches).

**Cause racine** (par variante)
- **Variante 1 — jeton de compte de service fuité** : la tentative de lecture du jeton dans le pod a
  échoué (aucun jeton monté, C6), mais un jeton du compte de service de recette a été **émis**
  (TokenRequest) puis utilisé depuis l'extérieur contre l'API (reconnaissance). La connexion sortante
  vers le C2 a été jetée par le refus réseau par défaut. Portée : ce que le jeton ouvre (droits du compte
  de service : ici presque rien, `get pods` refusé), **pas** de donnée sortie ; et l'identité qui a
  émis le jeton, à instruire.
- **Variante 2 — règles de sortie trop larges** : une NetworkPolicy oubliée (`legacy-sortie-large`)
  autorisait les pods d'API à sortir vers `10.10.99.0/24`, et une règle posée à chaud sur la bordure
  (`legacy-sortie-recette`) laissait passer jusqu'à `10.10.99.66:4444` ; la connexion vers le C2 a abouti
  (le C2 l'a journalisée). Rien n'a été envoyé (inoffensif), mais le canal était ouvert. Portée :
  exfiltration **possible** par ce canal.

**Correctif** (confinement en S11 ; éradication en S12)
Confiner sans détruire, identique pour les deux variantes (RB-262) :
```
admin@adm01:~$ kubectl -n mediagenda-recette label pod <POD> medisphere.internal/quarantaine=oui
admin@adm01:~$ kubectl -n mediagenda-recette get pod <POD> -o jsonpath='{.status.containerStatuses[0].restartCount}'   # inchangé
admin@adm01:~$ kubectl -n mediagenda-recette get rs -l app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api -o jsonpath='{.items[*].spec.selector}'
admin@adm01:~$ kubectl -n mediagenda-recette label pod <POD> app.kubernetes.io/component-   # sort le pod du ReplicaSet
admin@adm01:~$ kubectl -n mediagenda-recette get rollout mediagenda   # (kubectl argo rollouts get rollout mediagenda)
```
Le ReplicaSet du Rollout `mediagenda` (M20) recrée un pod sain ; le suspect reste orphelin, isolé, hors
des Services (stable et canary sélectionnent `component: api`). Le conteneur n'a pas redémarré
(`restartCount` inchangé : le check le compare à la valeur notée à l'injection). Ouvrir INC-6211,
qualifier (`[décision]`), escalader à Sophie (RSSI) et Thomas (DPO), un courriel d'état.

**Prévention**
- Variante 1 : retirer la capacité d'`exec` humain hors bris de glace **aussi** sur la recette
  (`prod-gestes-interactifs` du F3 étendu) ; restreindre qui peut émettre un jeton
  (`create serviceaccounts/token`) pour les comptes applicatifs ; alertes d'audit sur l'émission d'un
  jeton pour un compte applicatif et sur l'usage d'un jeton de compte de service avec un `userAgent`
  `kubectl` ou depuis une adresse hors des pods. La norme C6 (jeton non monté) a tenu : la garder.
- Variante 2 : contrôle de dérive des NetworkPolicy (une règle de sortie large = une alerte) et de la
  bordure (ruleset actif ↔ configuration persistée : P-RES-01 et la métrique proposée en F6-S04) ; revue
  des politiques réseau à chaque MR ; refus par défaut vérifié par un test Hubble périodique.

**Chaque variante traitée** : voir ci-dessus (portée et prévention diffèrent ; confinement identique).

---

### F6-S12 — Investigation et éradication

**Solution** (solution de référence)

Fichiers : [`chronologie.md`](fichiers/F6-S12/medisphere/docs/securite/incidents/INC-6211/chronologie.md).

1. **Chronologie** reconstruite avec des sources inaltérables (F6-S08) : première trace Falco → `exec`
   dans l'audit de l'API (identité) → tentative de lecture du jeton (Tetragon `process_exec`) → boucle de connexion (Tetragon,
   Hubble) → verdict réseau (Hubble) → journaux du C2 (`c2-simule01:/var/log/c2-simule.log`, relevés
   **avant** l'annulation) → isolement. Chaque ligne datée (UTC), sourcée, avec l'empreinte de la pièce
   dans `preuves-conformite/INC-6211/`.
2. **Portée** : *établi* — un shell a été ouvert, la lecture du jeton a été **tentée** (échec : aucun
   jeton monté), une connexion vers `10.10.99.66` a été tentée. *Selon la variante* — vecteur 1 : un
   jeton du compte a été émis puis utilisé contre l'API (audit), connexion
   **jetée** (Hubble `DROPPED`, C2 muet) → pas de sortie de données ; vecteur 2 : connexion **aboutie**
   (Hubble `FORWARDED`, C2 journalise) → canal ouvert, mais *non établi* qu'une donnée soit sortie
   (le C2 n'a reçu aucun octet utile ; l'injection n'envoie rien). *Non établi* dans les deux cas :
   aucune donnée de patient réelle (recette fictive/pseudonymisée), aucun accès à la production.
3. **Éradication de la cause** :
   - vecteur 1 : renouveler le compte de service (voir ci-dessous), révoquer ce qu'il ouvrait dans
     OpenBao (nouveaux identifiants, révocation des baux du moteur `database` émis pour la recette) ;
   - vecteur 2 : retirer `legacy-sortie-large` (et la ligne de la vieille MR qui l'a créée, si elle
     est encore dans un dépôt), retirer la règle `legacy-sortie-recette` des **deux** passerelles par son
     *handle* (`nft delete rule inet filter forward handle <H>`, comme en F6-S04), vérifier le retour au
     refus par défaut (Hubble : la connexion repasse `DROPPED` ; compteurs de la bordure figés).
   - vecteur 1 : un jeton lié ne se révoque pas individuellement ; supprimer et recréer le compte de
     service invalide **tous** ses jetons (nouvel UID : le check le compare à celui noté à
     l'injection), puis redémarrer proprement l'API de recette ; instruire l'identité qui a émis le
     jeton (dans le lab : celle qui a lancé l'injection).
   Dans les deux cas : supprimer le pod suspect **après** la collecte et l'accord de la RSSI.
4. **Rotation des secrets exposés** : jeton de compte de service, Secrets montés dans le pod,
   identifiants OpenBao lisibles depuis le pod — tournés ; trace dans la chronologie.
5. **Retour** : Rollout `mediagenda` complet, plus de connexion vers le C2, aucune alerte Falco active
   sur l'espace (les alertes de falcosidekick sans échéance se résolvent d'elles-mêmes quelques minutes
   après le dernier événement : `resolve_timeout` d'Alertmanager). Relever les journaux du C2
   (`qm guest exec 3601 -- cat /var/log/c2-simule.log` depuis `pve01`, empreinte dans la chronologie)
   **puis** `lab/bin/break F6 11 --annuler` (destruction du C2 ; retrait de ce que l'injection a posé et
   que tu n'aurais pas déjà retiré ; l'état local garde le pod et le compte de service pour le check).

**Explications**
- L'archive d'audit inaltérable (F6-S08) est faite pour ce moment : la chronologie tient parce que ses
  sources ne peuvent pas avoir été retouchées.
- **Éradiquer la cause, pas le symptôme** : supprimer le pod suspect règle le symptôme ; si le vecteur
  (jeton réutilisable, politique trop large) reste, l'incident revient. D'où la rotation et la MR.
- **Établi vs non établi** : la valeur de l'enquête est de dire ce qu'on sait **prouver**. Hubble et les
  journaux du C2 tranchent l'aboutissement ; c'est cette distinction qui nourrit la décision de F6-S13.

**Alternatives**
- Instantané PBS du nœud comme preuve principale : lourd ; la chronologie des journaux centraux +
  capture du conteneur suffit ici.
- Garder le pod suspect en quarantaine plusieurs jours pour analyse approfondie : possible (il est
  isolé), au prix d'une ressource à surveiller ; à décider avec la RSSI.

**Pièges classiques**
- Supprimer le pod avant d'avoir relevé les journaux du C2 et déposé les preuves.
- Annuler l'injection (`--annuler`) avant d'avoir relevé les journaux du C2 : la VM est détruite, la
  preuve de l'aboutissement disparaît.
- Conclure « rien de grave » sans Hubble : en variante 2, la connexion a abouti, ce n'est pas rien.
- Ne tourner que le jeton sans révoquer les baux OpenBao qu'il ouvrait.

**En production chez MédiSphère**
L'incident alimente une nouvelle règle de détection et un contrôle de dérive des NetworkPolicy ; la
recette passe sous `prod-gestes-interactifs` (plus d'`exec` humain hors bris de glace).

---

### F6-S13 — Notifications, communication et post-mortem

**Solution** (argumentée ; `RED` publié)

Fichiers : [`decision-notification.md`](fichiers/F6-S13/medisphere/docs/securite/incidents/INC-6211/decision-notification.md), [`registre-violations.md`](fichiers/F6-S13/medisphere/docs/securite/incidents/INC-6211/registre-violations.md), [`message-etat.md`](fichiers/F6-S13/medisphere/docs/securite/incidents/INC-6211/message-etat.md), [`post-mortem.md`](fichiers/F6-S13/medisphere/docs/securite/incidents/INC-6211/post-mortem.md).

**D'abord le rôle.** Pour ses propres données (comptes du personnel, journaux d'administration, données
fictives de sa recette), MédiSphère est **responsable de traitement** ; pour les données de patients
qu'elle héberge et traite pour ses clients (production de MédiAgenda), elle est **sous-traitant**
(art. 28). Le sous-traitant ne notifie pas la CNIL à la place de son client : il **notifie le
responsable de traitement dans les meilleurs délais** après avoir pris connaissance de la violation
(art. 33.2), et c'est le client qui décide de la notification CNIL (art. 33.1, 72 h) et de l'information
des personnes (art. 34). La répartition exacte se lit dans les contrats (clause de sous-traitance,
contrat HDS) : **à vérifier dans les contrats**, pas à supposer.

**La décision, sur preuves de F6-S12.** Les données de `mediagenda-recette` sont fictives ou
pseudonymisées (vérifié) ; aucun accès à la production n'est établi ; la connexion sortante n'a emporté
aucune donnée (vecteur 1 : jetée ; vecteur 2 : aboutie mais aucun octet utile). Conclusion :
- **Violation de données à caractère personnel** (RGPD art. 4.12) : **non** — aucune donnée personnelle
  réelle n'a été touchée (confidentialité, intégrité, disponibilité). La démonstration s'appuie sur la
  portée établie en F6-S12 (recette fictive, pas de prod, rien de sorti).
- **CNIL (art. 33)** : pas de notification — pas de violation de données personnelles. L'art. 33.5
  impose de documenter toute **violation** ; ici il n'y en a pas, mais l'analyse et la décision sont
  inscrites au même registre (bonne pratique, recommandée par la CNIL) : on doit pouvoir montrer qu'on a
  analysé et tranché.
- **Personnes (art. 34)** : sans objet (pas de violation, pas de risque élevé).
- **Clients HDS** : information **pour mémoire** au titre de la transparence contractuelle (un incident
  de sécurité a eu lieu en recette, sans impact sur leurs données), selon le contrat ; ce n'est pas une
  notification de violation.
- **Signalement d'incident grave (CERT Santé, art. L.1111-8-2)** : a priori **non** (pas d'impact sur un
  système d'information de santé en production) — **à vérifier sur Légifrance** (périmètre exact du
  signalement, arrêté du 30 octobre 2017 et textes postérieurs).

Si les faits avaient différé (données réelles, accès prod, données sorties), la décision basculerait :
données de patients des clients → **notification aux clients** sans délai (art. 33.2), qui notifient la
CNIL ; données dont MédiSphère est responsable → notification CNIL dans les 72 h. Le document contient
donc aussi les **projets** de ces notifications, construits sur le contenu minimal de l'art. 33.3
(nature, catégories et nombre approximatif de personnes et d'enregistrements, contact du DPO,
conséquences probables, mesures prises ou proposées), pour montrer qu'on sait les rédiger.

**Registre des violations (art. 33.5)** : entrée datée — nature de l'incident, catégories et nombre
approximatif de personnes et d'enregistrements concernés (ici : aucun réel), conséquences probables
(aucune établie), mesures prises (confinement, éradication, rotation), décision de non-notification et sa
justification.

**Message d'état** : factuel, sans jargon, au rythme de RB-360 (Claire, équipes) : ce qui s'est passé,
ce qui est fait, l'impact (nul sur la production et sur les données réelles), la suite.

**Post-mortem** sans recherche de coupable : chronologie, impact, **cause racine formulée en mécanisme**
(« une politique réseau de sortie temporaire n'a jamais été retirée et aucun contrôle ne la voyait » /
« un jeton de compte de service monté sans besoin pouvait servir à la reconnaissance »), ce qui a marché
(détection Falco/Tetragon, quarantaine, preuves inaltérables), ce qui a coûté (temps de qualification),
actions datées (contrôle de dérive, `exec` hors bris de glace sur la recette, jetons non montés).

**Explications**
- **Décider sur preuves.** Une notification CNIL envoyée « par prudence » sur une recette fictive est une
  fausse alerte réglementaire (qui use la relation avec l'autorité) ; une non-notification d'une vraie
  violation est une faute. La compétence évaluée est de **justifier** la décision avec les preuves, pas
  de choisir par réflexe.
- **Le registre dans tous les cas.** L'art. 33.5 impose de documenter **toute** violation (et, en
  pratique, l'analyse des événements écartés) : c'est la trace qui prouve la décision à l'auditeur.
- **Sans coupable.** Nommer une personne (« untel a laissé la règle ») arrête l'apprentissage ; nommer
  un mécanisme (« aucun contrôle ne voyait les règles de sortie larges ») produit une action.

**Pièges classiques**
- Confondre « alerte de sécurité » et « violation de données personnelles » : la première ne déclenche
  pas mécaniquement les secondes obligations.
- Raisonner comme responsable de traitement pour des données dont MédiSphère est sous-traitant (et
  « notifier la CNIL » à la place du client) : l'obligation du sous-traitant est d'alerter son client
  sans délai (art. 33.2).
- Oublier le registre quand on ne notifie pas (l'absence de trace = on ne peut pas prouver qu'on a
  décidé).
- Affirmer sans démontrer (« pas de données touchées ») sans citer la portée de F6-S12.
- Un post-mortem qui nomme des personnes.
- Présenter le projet de notification client comme une notification de violation alors que c'en est une
  information « pour mémoire ».

**En production chez MédiSphère**
Un arbre de décision « faut-il notifier ? » est versionné ; le modèle de notification CNIL est prêt ; le
DPO et la RSSI co-signent la décision ; le post-mortem est présenté à la revue de suivi (F6-S14).

---

## Points non testés en conditions réelles (phase 4)

- `ContainerCheckpoint` (point de contrôle de conteneur) : dépend du runtime (containerd + CRIU) ;
  tranché par F6-S10 sur le lab, dans un sens ou l'autre.
- `ms-verifier-kit-forensique` : image `plateforme/outils-forensique:v1.0.0` à construire (netshoot
  recopié par empreinte et signé par la CI) ; refus de `delete-object --version-id` par le verrou du RGW.
- Interception de l'`exec` humain sur la recette (`prod-gestes-interactifs` du F3 étendu) : proposée,
  non écrite.
- Création/destruction de `c2-simule01` par l'injection (clone du template 9000 sur le VNet `vsandbox`,
  écouteur posé par l'agent QEMU) et minutage des alertes Falco → Alertmanager → Mailpit : relus en
  logique, non rejoués sur une plateforme F6 complète.
- Variante 2 : adresse source vue par la bordure (adresse du pod ou du nœud selon le masquage de Cilium :
  la règle injectée accepte les deux) ; règle insérée à chaud sur la passerelle passive.
- Variante 1 : `sourceIPs` de l'audit pour un appel fait depuis `adm01` à travers la VIP de l'API
  (HAProxy en mode TCP, sans protocole PROXY : l'adresse du nœud de contrôle qui relaie est attendue, à
  vérifier) ; le `userAgent` `kubectl/…` reste l'indice le plus net.
- Signalement CERT Santé (art. L.1111-8-2) : **à vérifier sur Légifrance** (périmètre et circuit exacts ;
  l'ARS des Hauts-de-France le décrit comme un signalement « sans délai » des incidents significatifs ou
  graves par les établissements, sur le portail national, transmis au CERT Santé et à l'ARS).
- Répartition responsable / sous-traitant de MédiSphère selon ses contrats : à vérifier dans les
  contrats (le corrigé suppose : sous-traitant pour les données de patients des clients).
- Variante 1 : émission du jeton (`kubectl create token`) par le kubeconfig d'administration, et
  `kubeconfig` à `tokenFile` utilisé pour les deux requêtes : relus, non rejoués sur le lab.
