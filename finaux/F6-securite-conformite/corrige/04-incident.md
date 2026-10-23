# Final F6 — Phase 4 : L'incident — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. F6-S11 est un `BF` : la section est une **démarche de
> diagnostic** (symptômes → hypothèses → commandes → cause → correctif → prévention), **chaque variante
> traitée**. Les `LIBRE` (S10, S12) donnent une solution de référence ; le `RED` (S13) est argumenté.

**Validé hors du lab** (à la rédaction, 23/10/2026) :
- `break-S11.sh`, `verifier-kit-forensique.sh` : `bash -n` et `shellcheck -x` ;
- logique de l'injection relue contre les règles Falco du M26 (shell interactif, lecture du jeton,
  connexion sortante non prévue) et la politique de quarantaine (M26-E33) ;
- manifestes (NetworkPolicy injectée, runbooks) : YAML/Markdown valides.

**Points non testés en conditions réelles** : voir la fin de l'énoncé (point de contrôle de conteneur,
`exec` sur la recette, signalement CERT Santé). La création/destruction de `c2-simule01` par l'injection
et le minutage des alertes n'ont pas été rejoués sur une plateforme F6 complète.

**Fichiers** : [`fichiers/F6-S10/`](fichiers/F6-S10/), [`fichiers/F6-S12/`](fichiers/F6-S12/),
[`fichiers/F6-S13/`](fichiers/F6-S13/). Panne : [`pannes/break-S11.sh`](pannes/break-S11.sh).

---

### F6-S10 — Prêts pour l'incident

**Solution** (solution de référence)

Fichiers : [`RB-360-reponse-incident.md`](fichiers/F6-S10/medisphere/docs/securite/incidents/runbooks/RB-360-reponse-incident.md), [`RB-361-forensique-conteneur.md`](fichiers/F6-S10/medisphere/docs/securite/incidents/runbooks/RB-361-forensique-conteneur.md), [`verifier-kit-forensique.sh`](fichiers/F6-S10/outils/bin/verifier-kit-forensique.sh), [`2026-exercice-table.md`](fichiers/F6-S10/medisphere/docs/securite/incidents/exercices/2026-exercice-table.md), [`ECA-3605.md`](fichiers/F6-S10/medisphere/docs/conformite/ecarts/ECA-3605.md).

1. **Trois niveaux de runbook, pas un de plus** : RB-262 (M26) reste le détail « conteneur compromis »
   (isolement, collecte, escalade). RB-360 est le niveau **au-dessus** : quand déclencher, gravités,
   rôles (responsable, collecte, RSSI, DPO, communication, support), rythme des points, et le volet
   réglementaire (quand on se pose la question CNIL/clients/CERT Santé, qui décide). RB-361 est le
   niveau **en dessous** : le détail de la collecte forensique d'un conteneur (reprise et généralisation
   de la section 4 de RB-262). Les trois se citent ; on ne duplique rien.
2. **Le kit se vérifie, il ne se déclare pas** : `verifier-kit-forensique.sh` contrôle que l'image
   d'outils (`netshoot`/`busybox` de la bibliothèque) existe et que sa signature Cosign est valide, que
   l'identité de dépôt `preuves-conformite` **écrit** un fichier d'essai et **échoue** à le supprimer
   (verrouillage), que les modèles (chronologie, manifeste) sont présents, et que chaque compte de bris
   de glace **répond en lecture** (jamais en écriture). Lancé à froid, il doit pouvoir passer au rouge.
3. **Capture éprouvée** : sur un pod d'essai (`wb-essais`), tentative de point de contrôle du kubelet
   (`POST /checkpoint/<ns>/<pod>/<conteneur>`) ; si le runtime l'implémente (containerd + CRIU), on
   obtient l'archive dans `/var/lib/kubelet/checkpoints/` ; sinon `500`, et on **replie** sur la copie du
   système de fichiers (conteneur éphémère, `/proc/1/root`) et des journaux. Le résultat (dans un sens ou
   l'autre) est écrit dans RB-361 — l'« à confirmer » du M26 est tranché.
4. **Exercice de table** : un scénario (« un shell inattendu dans un conteneur de prod ») joué sur table,
   chronométré, qui révèle les trous (qui appelle le DPO la nuit ? où est l'identité de dépôt des
   preuves ? qui décide de la quarantaine ?). Les trous deviennent des actions datées.
5. **ECA-3605 clos** avec preuve `ms-preuves` (runbooks sur `main`, rapport vert du contrôle du kit,
   résultat de la capture, compte rendu de l'exercice).

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
Courriels d'Alertmanager (source `falco`) toutes les minutes pour `mediagenda-recette` : « shell
interactif dans un conteneur applicatif », « lecture du jeton de compte de service », « connexion
sortante vers un port non prévu » vers une adresse inconnue (`10.10.99.66:4444`). Aucune intervention
annoncée.

**Hypothèses** (dans l'ordre où on les écarte)
1. Faux positif — un développeur débogue en recette (un `exec` humain déclenche « shell interactif »).
2. Vrai positif, entrée par une **identité de l'API** (jeton de compte de service fuité).
3. Vrai positif, une **règle réseau trop large** laisse sortir le trafic vers une destination interdite.

**Commandes de diagnostic** (dans l'ordre ; lecture seule, rien n'est supprimé)

*Qualifier (15 min).* Quel pod, quel nœud, quelle image, depuis quand :
```
admin@adm01:~$ kubectl -n mediagenda-recette get pods -o wide
admin@adm01:~$ kubectl -n mediagenda-recette get pod <POD> -o jsonpath='{.status.containerStatuses[*].image}{"\n"}{.status.containerStatuses[*].restartCount}{"\n"}'
```
*Qui a ouvert le shell* — journal d'audit de l'API (locataire `audit` de Loki) :
```logql
{job="kubernetes-audit"} | json | objectRef_subresource="exec" | objectRef_name="<POD>"
```
- Si l'identité est un **humain** (`kubernetes-admin`, un compte FreeIPA) avec un ticket `CHG-`/`INC-` :
  piste du faux positif. Ici, aucun ticket → vrai positif.
- Si l'identité est un **compte de service** (`system:serviceaccount:mediagenda-recette:…`) faisant en
  plus `auth can-i --list` et `get pods` : **vecteur 1** (jeton fuité).
*Ce qui a été lancé* — Falco et Tetragon :
```logql
{service="falco", k8s_pod_name="<POD>"} | json
{service="tetragon"} | json | process_exec_process_pod_name="<POD>"
```
Tetragon donne l'arbre : le `sh` a lu `/var/run/secrets/kubernetes.io/serviceaccount/token`, puis lancé
une boucle `python3`.
*Où va la connexion, aboutit-elle* — Hubble (c'est ici que les deux vecteurs se séparent) :
```
admin@adm01:~$ hubble observe --pod mediagenda-recette/<POD> --to-ip 10.10.99.66 --last 50
```
- **Vecteur 1** : verdict `DROPPED` (le refus par défaut de l'espace tient) → la connexion **n'aboutit
  pas** ; le C2 ne journalise rien.
- **Vecteur 2** : verdict `FORWARDED` → une politique autorise la sortie. La trouver :
  ```
  admin@adm01:~$ kubectl -n mediagenda-recette get networkpolicy
  admin@adm01:~$ kubectl -n mediagenda-recette get networkpolicy legacy-sortie-large -o yaml
  ```
  L'annotation montre une vieille MR (`MR !218 (2026-03)`, « sortie temporaire, jamais retirée ») :
  **vecteur 2** (politique réseau trop large).

**Cause racine** (par variante)
- **Variante 1 — jeton de compte de service fuité** : un jeton du compte de service de recette a été
  lu dans le pod puis utilisé contre l'API (reconnaissance). La connexion sortante vers le C2 a été
  jetée par le refus réseau par défaut. Portée : ce que le jeton ouvre (droits du compte de service),
  **pas** de donnée sortie.
- **Variante 2 — politique réseau trop large** : une NetworkPolicy oubliée (`legacy-sortie-large`)
  autorisait la sortie vers `10.10.99.0/24` ; la connexion vers le C2 a abouti (le C2 l'a journalisée).
  Rien n'a été envoyé (inoffensif), mais le canal était ouvert. Portée : exfiltration **possible** par
  ce canal.

**Correctif** (confinement en S11 ; éradication en S12)
Confiner sans détruire, identique pour les deux variantes (RB-262) :
```
admin@adm01:~$ kubectl -n mediagenda-recette label pod <POD> medisphere.internal/quarantaine=oui
admin@adm01:~$ kubectl -n mediagenda-recette get pod <POD> -o jsonpath='{.status.containerStatuses[0].restartCount}'   # inchangé
admin@adm01:~$ kubectl -n mediagenda-recette get rs -l app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api -o jsonpath='{.items[*].spec.selector}'
admin@adm01:~$ kubectl -n mediagenda-recette label pod <POD> app.kubernetes.io/component-   # sort le pod du ReplicaSet
```
Le contrôleur recrée un pod sain ; le suspect reste orphelin, isolé, hors du Service. Ouvrir INC-6211,
qualifier (`[décision]`), escalader à Sophie (RSSI) et Thomas (DPO), un courriel d'état.

**Prévention**
- Variante 1 : retirer la capacité d'`exec` humain hors bris de glace **aussi** sur la recette
  (`prod-gestes-interactifs` du F3 étendu) ; jeton de compte de service non monté quand inutile
  (norme « charge sûre » C6, M26) ; alerte sur l'usage d'un jeton de compte de service contre l'API
  depuis une adresse inhabituelle.
- Variante 2 : contrôle de dérive des NetworkPolicy (une règle de sortie large = une alerte) ; revue
  des politiques réseau à chaque MR ; refus par défaut vérifié par un test Hubble périodique.

**Chaque variante traitée** : voir ci-dessus (portée et prévention diffèrent ; confinement identique).

---

### F6-S12 — Investigation et éradication

**Solution** (solution de référence)

Fichiers : [`chronologie.md`](fichiers/F6-S12/medisphere/docs/securite/incidents/INC-6211/chronologie.md).

1. **Chronologie** reconstruite avec des sources inaltérables (F6-S08) : première trace Falco → `exec`
   dans l'audit de l'API (identité) → lecture du jeton (Tetragon) → boucle de connexion (Tetragon,
   Hubble) → verdict réseau (Hubble) → journaux du C2 (`c2-simule01:/var/log/c2-simule.log`, relevés
   **avant** l'annulation) → isolement. Chaque ligne datée (UTC), sourcée, avec l'empreinte de la pièce
   dans `preuves-conformite/INC-6211/`.
2. **Portée** : *établi* — un shell a été ouvert, le jeton a été lu, une connexion vers `10.10.99.66`
   a été tentée. *Selon la variante* — vecteur 1 : usage du jeton contre l'API (audit), connexion
   **jetée** (Hubble `DROPPED`, C2 muet) → pas de sortie de données ; vecteur 2 : connexion **aboutie**
   (Hubble `FORWARDED`, C2 journalise) → canal ouvert, mais *non établi* qu'une donnée soit sortie
   (le C2 n'a reçu aucun octet utile ; l'injection n'envoie rien). *Non établi* dans les deux cas :
   aucune donnée de patient réelle (recette fictive/pseudonymisée), aucun accès à la production.
3. **Éradication de la cause** :
   - vecteur 1 : renouveler le compte de service (nouveau jeton), révoquer ce qu'il ouvrait dans OpenBao
     (nouveaux identifiants, révocation des baux du moteur `database`) ;
   - vecteur 2 : retirer `legacy-sortie-large` par MR (`plateforme/k8s` ou le dépôt de l'équipe de
     recette), vérifier le retour au refus par défaut (Hubble : la connexion repasse `DROPPED`).
   Dans les deux cas : supprimer le pod suspect **après** la collecte et l'accord de la RSSI.
4. **Rotation des secrets exposés** : jeton de compte de service, Secrets montés dans le pod,
   identifiants OpenBao lisibles depuis le pod — tournés ; trace dans la chronologie.
5. **Retour** : pod sain en service, plus de connexion vers le C2 (détruit à l'annulation), aucune alerte
   Falco active sur l'espace. Relever les journaux du C2 **puis** `lab/bin/break F6 11 --annuler`.

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

**La décision, sur preuves de F6-S12.** Les données de `mediagenda-recette` sont fictives ou
pseudonymisées (vérifié) ; aucun accès à la production n'est établi ; la connexion sortante n'a emporté
aucune donnée (vecteur 1 : jetée ; vecteur 2 : aboutie mais aucun octet utile). Conclusion :
- **Violation de données à caractère personnel** (RGPD art. 4.12) : **non** — aucune donnée personnelle
  réelle n'a été touchée (confidentialité, intégrité, disponibilité). La démonstration s'appuie sur la
  portée établie en F6-S12 (recette fictive, pas de prod, rien de sorti).
- **CNIL (art. 33)** : pas de notification — pas de violation de données personnelles. Mais l'analyse et
  la décision sont **inscrites au registre** (art. 33.5), car on a pris connaissance d'un événement et
  on doit pouvoir montrer qu'on a tranché.
- **Personnes (art. 34)** : sans objet (pas de violation, pas de risque élevé).
- **Clients HDS** : information **pour mémoire** au titre de la transparence contractuelle (un incident
  de sécurité a eu lieu en recette, sans impact sur leurs données), selon le contrat ; ce n'est pas une
  notification de violation.
- **Signalement d'incident grave (CERT Santé, art. L.1111-8-2)** : a priori **non** (pas d'impact sur un
  système d'information de santé en production) — **à vérifier sur Légifrance** (périmètre exact du
  signalement, arrêté du 30 octobre 2017 et textes postérieurs).

Si les faits avaient différé (données réelles, accès prod, données sorties), la décision basculerait :
le document contient donc aussi les **projets** de notification CNIL (champs du téléservice) et de
notification client « pour mémoire », pour montrer qu'on sait les rédiger.

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
- Création/destruction de `c2-simule01` par l'injection et minutage des alertes Falco → Alertmanager →
  Mailpit : relus en logique, non rejoués sur une plateforme F6 complète.
- Signalement CERT Santé (art. L.1111-8-2) : **à vérifier sur Légifrance** (périmètre et circuit exacts).
