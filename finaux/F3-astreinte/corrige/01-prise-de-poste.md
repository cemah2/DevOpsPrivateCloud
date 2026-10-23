# Final F3 — Corrigé de la phase 1 : prise de poste

> ⚠️ Corrigé. À n'ouvrir qu'après avoir cherché.

**Validé hors du lab** : règles et tests `promtool` des fichiers de ce final (Prometheus 3.5, `promtool test rules`), arbre de routage et injection de route rejoués avec `amtool` 0.28 sur la configuration du corrigé de M21-E16, garde-fou `verifier-routes-null.sh` et générateur d'index rejoués sur des dépôts de test, `shellcheck -x` et `bash -n` sur tous les scripts, YAML validés.
**Points non testés en conditions réelles** (signale tes retours) : le contrôle de santé complet sur un lab réel (noms des Applications Argo CD qui seraient légitimement `OutOfSync` : `WB_F3_APPS_IGNOREES`) ; la recherche Mailpit `to:… subject:…` (syntaxe de recherche de Mailpit 1.31) ; la lecture de `sys/auth` par l'AppRole `wb-checks` d'OpenBao.

---

### F3-S01 — Prendre l'astreinte

**Solution de référence** (il en existe d'autres ; ce qui compte, ce sont les preuves)

Fichiers : [`index-runbooks.md`](fichiers/S01/medisphere/docs/exploitation/index-runbooks.md), [`trousse-astreinte.md`](fichiers/S01/medisphere/docs/exploitation/trousse-astreinte.md), [`outils/generer-index-runbooks.sh`](fichiers/S01/medisphere/outils/generer-index-runbooks.sh), main courante d'exemple [`journal/2026-11-02.md`](fichiers/S01/medisphere/docs/exploitation/journal/2026-11-02.md).

1. **Santé.** `lab/bin/check F3 1` : la première partie est le contrôle de santé. Ce qui est rouge au départ se traite comme un incident (main courante, sans identifiant `INC-` s'il est mineur). Cas fréquents en sortie de F2 : une Application `OutOfSync` parce qu'une promotion de production attend sa synchronisation manuelle (synchronise-la ou, si c'est voulu, exclus-la par `WB_F3_APPS_IGNOREES` et écris pourquoi dans la trousse) ; `RECENT_CRASH` dans Ceph après un redémarrage (lis le rapport, `ceph crash archive-all`).

2. **Accès, voie normale.**
   ```
   admin@adm01:~$ kubectl config get-contexts ; kubectl auth whoami          # oidc:<MOI>, groupes oidc:plateforme-admins
   admin@adm01:~$ bao login -method=oidc && bao token lookup -format=json | jq '.data.policies'
   admin@adm01:~$ step ssh login <MOI> --provisioner keycloak && ssh mon01 true
   ```
   Chaque connexion demande le SSO et l'OTP **sur le téléphone d'astreinte** ; enrôle un second facteur de secours (WebAuthn) si ce n'est pas fait.

3. **Bris de glace en lecture** (RB-240), avec une seconde personne (Claire) : `admin.conf` (copie temporaire en 600, `kubectl --kubeconfig … get nodes`, copie effacée), `root@pam` (lecture de `/cluster/resources`), `root` de GitLab (liste des projets), `kc-secours` (console de Keycloak, royaume `master`, lecture). Constate dans Loki (locataire `audit`) l'entrée de chaque usage et la réception de l'alerte d'usage du bris de glace (M24-E28). Rien n'est modifié ; la date de l'essai va dans la trousse (format `AAAA-MM-JJ`, lu par le check).

4. **Chaîne d'alerte.**
   ```
   admin@adm01:~$ export AM=--alertmanager.url=http://alertmanager.apps.par1.medisphere.internal:9093
   admin@adm01:~$ curl -s http://alertmanager.apps.par1.medisphere.internal:9093/api/v2/status | jq -r .config.original > /tmp/am.yml
   admin@adm01:~$ amtool config routes test --config.file=/tmp/am.yml alertname=EssaiPriseDePoste gravite=critique equipe=plateforme
   astreinte-mail,plateforme-mail
   admin@adm01:~$ amtool $AM alert add EssaiPriseDePoste gravite=critique equipe=plateforme \
       --annotation=resume="Essai de prise d'astreinte" --end=$(date -d '+10 min' -Iseconds)
   ```
   Le courriel arrive à `astreinte@` après `group_wait` (30 s) : vérifie-le dans Mailpit. L'essai passe par **la vraie** route (`gravite=critique`), pas par une route d'essai : c'est la seule preuve qui vaille.

5. **Dead man's switch.** Sur le témoin de `mon01` : `probe_success{job="watchdog-cluster"}` vaut 1 ; la règle `SupervisionClusterMuette` (`probe_success == 0` pendant 5 min, critique) existe et son Alertmanager témoin route vers `astreinte@`. La preuve **se lit** : la sonde exige `Watchdog` dans la réponse de Thanos Query ; si Watchdog disparaissait, la sonde échouerait. On ne coupe pas Prometheus pour le prouver un lundi matin (c'était l'exercice M21-E28).

6. **Index et trousse.** L'index est **généré** pour la partie « par domaine » (`outils/generer-index-runbooks.sh`, qui lit `docs/**/runbooks/RB-NNN-*.md` et garde la partie manuelle) ; la partie « par symptôme » est écrite à la main, c'est celle qui sert à 3 h du matin. Le script a un mode `--verifier` pour un job de CI. La trousse suit le gabarit fourni : ce qu'on vérifie en prenant le téléphone, les accès et leur date de vérification, le bris de glace daté, les outils, l'escalade.

7. **Main courante** : `docs/exploitation/journal/<AAAA-MM-JJ>.md` avec la prise de poste et les résultats ; MR.

**Explications**

Une astreinte qui n'a pas vérifié ses accès découvre ses problèmes au pire moment, quand le SSO est lui-même en panne ou que l'OTP est sur un autre téléphone. L'essai d'alerte doit emprunter le chemin réel (règle de gravité, route, récepteur, SMTP, boîte) : un test qui contourne la route prouve seulement que Mailpit marche. Le *dead man's switch* répond à la question que l'astreinte ne peut pas se poser elle-même : « et si c'est la supervision qui est en panne ? ». L'index généré règle le problème de l'éparpillement (160 runbooks dans 23 dossiers) ; la table par symptôme règle celui du stress.

**Alternatives**

- Index entièrement manuel : plus lisible, mais il dérive en quelques semaines ; le générateur + `--verifier` en CI l'empêche.
- Catalogue de Backstage (TechDocs, M28) comme point d'entrée : valable, mais il dépend du cluster ; l'astreinte garde un index dans le dépôt, lisible même cluster arrêté (clone local).
- Sonde de bout en bout automatique (une alerte d'essai par heure, vérifiée dans Mailpit par le témoin) : voir « Pour aller plus loin » de S04.

**Pièges classiques**

- Tester le bris de glace « en écriture » (changer un mot de passe, créer un objet) : c'est une modification non tracée de la configuration ; RB-240 dit **lecture**.
- Laisser traîner la copie de `admin.conf` dans `/tmp`.
- Poser l'alerte d'essai sans `--end` : sa durée dépend alors d'un réglage global (`resolve_timeout`, 5 min) au lieu d'être choisie et consignée. (Le contrôle de santé ignore les alertes dont le nom commence par `Essai`.)
- Envoyer l'alerte d'essai avec `severity=critical` au lieu de `gravite=critique` : elle passe par la route de compatibilité du chart, pas par celle de MédiSphère.
- Écrire l'index à la main sans les runbooks des modules anciens (RB-001 à RB-085) : ce sont eux qui servent quand le socle tombe.

**En production chez MédiSphère**

La prise d'astreinte est une liste signée à chaque relève (date, heure, résultats), conservée dans la main courante ; l'essai des comptes de bris de glace est trimestriel et fait l'objet d'un audit ISO 27001 (A.5.18, A.8.2) ; l'outil d'astreinte (PagerDuty, Grafana OnCall) porte un « heartbeat » de l'Alertmanager en plus du témoin interne.

---

### F3-S02 — La procédure de gestion d'incident

**Solution de référence**

Fichiers : [`gestion-incidents.md`](fichiers/S02/medisphere/docs/exploitation/gestion-incidents.md) et son annexe [`modeles-messages.md`](fichiers/S02/medisphere/docs/exploitation/modeles-messages.md).

Points qu'une bonne procédure doit avoir (grille d'auto-évaluation) :

1. **Gravité par l'impact**, avec des exemples MédiSphère pour chaque niveau, et deux règles d'élévation : le temps (un SEV3 qui atteint son échéance devient SEV2) et les données de santé (tout soupçon d'exposition = SEV1 jusqu'à preuve du contraire, HDS et RGPD : notification possible à la CNIL sous 72 h, décision de Sophie). Classement des deux cas de l'énoncé : « la recette est lente » = SEV3 (aucun utilisateur réel touché ; SEV4 si personne n'en dépend aujourd'hui) ; « un dossier patient visible par un autre cabinet » = **SEV1**, quel que soit le nombre de dossiers et même si c'est « réparé ».
2. **Trois rôles** distincts, même tenus par une seule personne (séparés dans le temps), et la passation de rôle écrite.
3. **Canaux** : un canal de diffusion (courriel `incidents@`), un canal d'urgence (téléphone), une source de vérité (main courante), des tickets pour les suites ; règle « pas de donnée de santé ni de secret dans les messages ».
4. **Rythme chiffré** par gravité, et la promesse du « prochain message à HH:MM ».
5. **Modèles** courts et toujours dans le même ordre (impact, ce qu'on sait, ce qu'on fait, ce qu'on demande, prochain message).
6. **Main courante** au format de l'équipe, heure de l'événement, publiée par MR.
7. **Clôture** mesurée (le symptôme est revenu à la normale), message de fin, tickets de suite, et **post-mortem** obligatoire pour SEV1, SEV2 et toute alerte défaillante, sous 5 jours, sans recherche de coupable.

**Explications**

Une procédure d'incident sert surtout à **ne pas avoir à décider** de la forme pendant l'incident : qui parle, quand, où on écrit. Le rythme des messages rassure plus que leur contenu (Claire sait quand elle aura des nouvelles et n'appelle pas la personne technique). Séparer les rôles, même seul, évite le piège classique de l'ingénieur absorbé par son diagnostic qui oublie de communiquer pendant une heure.

**Alternatives**

- Gravités à trois niveaux (P1-P3) : plus simple ; quatre niveaux permettent de distinguer « production dégradée » de « outillage dégradé », utile chez MédiSphère où la plateforme a ses propres clients internes.
- Canal de messagerie instantanée (Mattermost auto-hébergé) à la place du courriel : plus vif, mais rien dans le lab ; le courriel vers Mailpit tient lieu de canal tracé.
- Cadre « Incident Command System » complet (commandant, scribe, liaison) : surdimensionné pour une équipe de cinq.

**Pièges classiques**

- Gravité définie par la technique (« Ceph en HEALTH_WARN = SEV2 ») : on surclasse des non-événements et on sous-classe des fuites de données.
- Pas de rythme pour SEV3 : les incidents « mineurs » durent trois jours sans que personne ne le sache.
- Clôture « quand ça a l'air d'aller » : sans mesure, on clôt avant le rétablissement réel.
- Post-mortem réservé aux SEV1 : on rate les leçons des incidents moyens, qui sont les plus nombreux.

**En production chez MédiSphère**

La procédure est intégrée au SMSI (ISO 27001 A.5.24 à A.5.28 : planification, appréciation, réponse, enseignements, collecte des preuves) ; les incidents de sécurité suivent en plus la procédure de Sophie (F6) ; un exercice d'incident (« jour de jeu ») vérifie la procédure deux fois par an (M29).
