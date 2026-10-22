# Module 23 — Palier 5 : Mini-projet

Le module a instrumenté MédiAgenda et MédiDoc, monté la chaîne OpenTelemetry, Tempo et Pyroscope, relié les quatre signaux, sécurisé le point d'entrée, comparé Jaeger, cassé et réparé la chaîne. Il reste à la **livrer** comme une brique de la plateforme : les trois environnements tracés et profilés, des données sensibles absentes, des tableaux qui partent d'un SLO pour arriver à la ligne de code, une documentation que l'astreinte peut suivre, et rien de provisoire. C'est ce que Claire Morel présentera au comité comme « l'observabilité de MédiSphère v1 » : métriques (M21), journaux (M22), traces et profils (M23).

---

### M23-E25 — Mini-projet : l'observabilité de MédiSphère v1  `LIBRE` `★★★`

> **Ticket PLAT-2425** — *De : Claire Morel*
> Jeudi, je présente au comité d'architecture et à l'auditrice HDS notre observabilité complète. Je veux pouvoir dérouler en direct, en production : une alerte de SLO sur MédiAgenda → le point du graphique → la trace de la requête fautive → ses journaux → le profil du service à ce moment-là. Sophie veut la preuve qu'aucune donnée de santé ne traîne dans les traces. Nadia veut des runbooks à jour. Et je ne veux plus voir un seul essai qui traîne. Livre-moi ça avec l'étiquette `traces-v1`.

**Objectifs pédagogiques**
- Intégrer la brique de traces et de profils dans MédiSphère : trois environnements, trois signaux corrélés, documentation et exploitation.
- Démontrer la conformité (données sensibles, rétention, accès) par des contrôles reproductibles, pas par des affirmations.
- Préparer les modules suivants : astreinte (F3), sécurité d'exécution (M26), tests de charge et de chaos (M29).

**Prérequis** : tous les exercices du module ; `lab/bin/check 23 13`, `14`, `16` et `19` à `22` verts.
**Durée indicative** : 4 à 6 h.

**Contraintes**
- Tout passe par le code et la relecture : dépôts des applications et leurs `…/deploiement` (MR, promotion GitOps de dev vers recette puis production), `plateforme/observabilite`, `plateforme/gitops`, `plateforme/medisphere`. Aucune ressource posée à la main ne doit rester dans le cluster.
- La production de MédiAgenda (`mediagenda-prod`) se synchronise **à la main** (M20) : la mise en production de la télémétrie suit la procédure de changement de l'équipe (MR approuvée, fenêtre, retour arrière décrit).
- Aucune donnée de santé dans les traces, les profils ni leurs étiquettes : ni identifiant de patient, ni nom de fichier, ni paramètre de requête SQL ou d'URL, ni en-tête d'authentification.
- Échantillonnage : en production, les erreurs et les requêtes lentes sont toujours gardées ; le volume reste dans le dimensionnement de M23-E16.
- Les essais du module sont retirés : Jaeger, l'auto-instrumentation de M23-E07 (et son annotation), les exportateurs `debug`, le témoin de trafic du palier 4 une fois les contrôles faits.
- Rétention, quotas et accès conformes à `capacite-securite.md` et à l'ADR-0230.

**Livrables**
1. **Trois environnements tracés et profilés** : MédiAgenda en dev, recette et production, MédiDoc en dev et recette, chacun avec le composant de télémétrie, des traces distribuées entre les deux applications en recette, des profils pour les deux applications.
2. **Tableau « MédiAgenda — SLO, traces et profils »** (UID `m23-slo-traces`, dans `tableaux/`, sources en variables) : les SLO de M21 (disponibilité, latence) et le budget restant, la latence par route **avec exemplars** vers Tempo, les traces en erreur ou lentes, le profil CPU du service ; liens vers Pyrra et les runbooks. C'est le support de la démonstration de Claire.
3. **Données sensibles** : une preuve reproductible (requêtes TraceQL et LogQL écrites dans `docs/observabilite/traces/conformite.md`, avec leur résultat daté) qu'aucune span ne porte de sonde, d'identifiant de patient, de paramètre SQL ou d'en-tête d'authentification sur 24 h dans les trois environnements.
4. **Documentation** dans `docs/observabilite/traces/` : `conventions-telemetrie.md` finalisé (noms de services, attributs de ressource obligatoires, attributs métier autorisés, section « attributs interdits », nommage des spans), ADR-0230, `capacite-securite.md` à jour, runbooks RB-235 à RB-238 relus après le palier 4, et une page d'accueil `README.md` qui dit où trouver quoi (architecture, adresses, comptes, procédures).
5. **Démonstration écrite** : le parcours « alerte → exemplar → trace → journaux → profil » réalisé en recette, capturé pas à pas (requêtes, identifiants de trace, captures d'écran sans donnée de santé) dans `docs/observabilite/traces/demonstration.md`.
6. **Rien de provisoire** : essais retirés (voir contraintes), aucune panne M23 active, pipeline de `plateforme/observabilite` vert.
7. **Étiquette `traces-v1`** sur `plateforme/medisphere`, posée quand tout le reste est livré.

**Critères de réussite**
- [ ] Des traces récentes de `mediagenda-api` en dev, recette et production, et de `medidoc` en dev et recette ; des traces distribuées en recette ; des profils des deux applications.
- [ ] Aucune span de sonde ni attribut d'identité de patient ou d'en-tête d'authentification sur 1 h ; échantillonnage en queue actif ; aucun exportateur `debug` en service.
- [ ] Les contrôles de M23-E13, M23-E14 et M23-E16 (et ceux des paliers 1 et 2 rejoués) sont verts.
- [ ] Le tableau `m23-slo-traces` est provisionné depuis `tableaux/` et relie SLO, exemplars, traces et profils.
- [ ] Jaeger, l'`Instrumentation` d'essai et toute injection automatique hors `wb-essais` ont disparu ; aucune panne active.
- [ ] ADR-0230, `conventions-telemetrie.md` (avec ses attributs interdits), RB-235 à RB-238 publiés ; pipeline vert ; étiquette `traces-v1` posée.

**Vérification** : `lab/bin/check 23 25` (3 à 6 minutes ; il rejoue les contrôles clés du module).

<details><summary>Indice 1</summary>

Fais d'abord la liste de ce qui est encore provisoire dans le cluster et dans les dépôts (espaces d'essai, Applications, annotations, exportateurs, variables de `lab/lab.env` qui ne servent plus) : c'est souvent ce qui fait échouer une recette.
</details>

<details><summary>Indice 2</summary>

La démonstration de Claire part d'un point de la courbe de latence : sans exemplar sur ce point, le parcours s'arrête là. Vérifie la chaîne des noms : l'étiquette d'exemplar posée par l'application, celle que Grafana attend, celle qu'écrit le *metrics-generator* de Tempo.
</details>

**Pour aller plus loin** : prépare pour F3 (astreinte) un scénario où l'API de production ralentit à cause d'une dépendance (MédiDoc, PostgreSQL), et vérifie que l'astreinte peut, en dix minutes et sans aide, aller de l'alerte à la span fautive.
