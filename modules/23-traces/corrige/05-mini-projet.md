# Module 23 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

### M23-E25 — Mini-projet : l'observabilité de MédiSphère v1

**Solution**

Un exercice `LIBRE` n'a pas de solution unique : voici une démarche qui livre, dans l'ordre où elle réduit le risque, et les fichiers d'exemple dans [`fichiers/M23-E25/`](fichiers/M23-E25/).

*1. État des lieux (30 min).* Lance `lab/bin/check 23 25` une première fois : il liste ce qui manque. Fais l'inventaire de ce qui est provisoire :

```
admin@adm01:~$ kubectl get ns | grep -E 'jaeger|essai|pannes'
admin@adm01:~$ kubectl get instrumentations.opentelemetry.io -A
admin@adm01:~$ kubectl get pods -A -o json | jq -r '.items[] | select(.metadata.annotations // {} | keys | any(startswith("instrumentation.opentelemetry.io/inject-"))) | "\(.metadata.namespace)/\(.metadata.name)"'
admin@adm01:~$ kubectl -n traces get otelcol -o json | jq -r '.items[] | "\(.metadata.name): \(.spec.config.service.pipelines | [.[].exporters[]] | unique | join(","))"'
admin@adm01:~$ ls ~/.local/state/workbook/pannes-actives/ 2>/dev/null
```

*2. Production (1 h 30).* MédiAgenda de production reçoit les composants `telemetrie` et `profilage` dans `overlays/prod` (MR approuvée par Julien et Karim, CHG-2425) ; pour la production, un échantillonnage en tête **à 1.0** reste raisonnable au volume du lab (la passerelle réduit en queue) — si tu le baisses, écris pourquoi et ce que tu perds (M23-E18, question 1). La production étant synchronisée à la main (M20) : `argocd app diff mediagenda-prod`, fenêtre annoncée, `argocd app sync mediagenda-prod`, suivi du Rollout (`kubectl argo rollouts get rollout mediagenda -n mediagenda-prod --watch`), retour arrière = revert de la MR et nouvelle synchronisation. Vérifie les traces de production (TraceQL `{resource.service.name = "mediagenda-api" && resource.deployment.environment.name = "prod"}`) et les profils (`environnement="prod"`). MédiDoc reste en dev et recette (il n'a pas de production au lab).

*3. Tableau de démonstration (1 h).* [`tableaux/mediagenda-slo-traces.json`](fichiers/M23-E25/observabilite/tableaux/mediagenda-slo-traces.json) (UID `m23-slo-traces`) : SLI de disponibilité sur 1 h et budget restant sur 28 jours (même définition que le SLO Pyrra de M21-E26), part des requêtes sous le seuil de latence, latence p95 par route **avec exemplars** (`"exemplar": true` sur la requête), table des traces en erreur ou lentes (TraceQL), profil CPU (Pyroscope) ; trois variables de source (`datasource`, `tempo`, `profils`) et une d'environnement ; liens vers Pyrra et les runbooks. Les exemplars n'apparaissent sur ce panneau que si toute la chaîne de noms est cohérente : `trace_id` posé par MédiAgenda sur ses exemplars (M23-E08), `exemplarTraceIdDestinations.traceIdLabelName: trace_id` dans les values de kps, `trace_id_label_name: trace_id` dans les overrides de Tempo (M23-E13) pour les séries tirées des traces.

*4. Données sensibles (45 min).* Les requêtes de contrôle et leurs résultats datés : [`conformite.md`](fichiers/M23-E25/medisphere/docs/observabilite/traces/conformite.md). Elles s'appuient sur le masquage de M23-E10 dans l'agent (sondes filtrées, littéraux SQL et paramètres d'URL retirés, en-têtes supprimés, motifs NIR et courriel masqués) et le vérifient de l'extérieur. Un masquage par motif qui se déclenche (`redaction.masked.count > 0`) n'est pas un succès : il révèle un émetteur qui fuit, et donne lieu à un ticket à l'équipe concernée.

*5. Documentation (1 h).* Page d'accueil [`README.md`](fichiers/M23-E25/medisphere/docs/observabilite/traces/README.md) ; `conventions-telemetrie.md` de M23-E10 complété : noms de services (`mediagenda-api`, `medidoc`), attributs de ressource obligatoires (`service.namespace=medisphere`, `deployment.environment.name`), attributs métier autorisés (`mediagenda.rendez_vous.id`, tailles, statuts), **attributs interdits** (identité du patient, noms de fichier, contenu, paramètres SQL et d'URL, en-têtes d'authentification, baggage métier), nommage des spans (route, jamais d'identifiant) et protocoles d'export (gRPC 4317 vers l'agent du nœud) ; ADR-0230 (M23-E17), `capacite-securite.md` (M23-E16) remis à jour avec les volumes de la production ; RB-230 à RB-233 relus après les pannes.

*6. Démonstration (45 min).* En recette, provoque une vraie dégradation sans risque (MédiDoc de recette à 0 réplica une minute pendant une charge) et déroule le parcours : [`demonstration.md`](fichiers/M23-E25/medisphere/docs/observabilite/traces/demonstration.md). Mesure le temps de l'alerte à la cause : c'est l'indicateur que Claire présentera.

*7. Retraits et livraison (30 min).* Jaeger (si M23-E15 n'a pas tout retiré), `Instrumentation python-essai` et la copie de MédiAgenda de `wb-essais` (M23-E07), exportateurs `debug`, pannes closes (`lab/bin/break 23 XX --annuler` pour chacune), témoin de trafic supprimé une fois les contrôles du palier 4 refaits :

```
admin@adm01:~$ kubectl -n wb-pannes delete deploy trafic-agenda && kubectl -n wb-pannes delete cm trafic-agenda racine-medisphere
admin@adm01:~$ lab/bin/check 23 25
admin@adm01:~/medisphere$ git tag -a traces-v1 -m "M23 : traces et profils, MédiSphère v1" && git push origin traces-v1
```

**Explications**

Le mini-projet ne demande pas de technique nouvelle : il demande que les morceaux tiennent **ensemble** et qu'on puisse le prouver. La démonstration de Claire est une chaîne de cinq liens (alerte, exemplar, trace, journaux, profil) qui repose sur une demi-douzaine de conventions de noms (`service.name` = `service_name`, `trace_id` partout, environnement dans les attributs de ressource et les étiquettes de profil) : la moindre divergence casse le parcours. C'est pourquoi la convention est écrite (`conventions-telemetrie.md`) et vérifiée (checks).

**Alternatives**

- Un tableau par équipe (MédiAgenda, MédiDoc) plutôt qu'un tableau unique : mieux pour les équipes, moins lisible pour une démonstration.
- Contrôle de conformité automatisé (règle Loki ou job planifié qui rejoue les requêtes TraceQL et ouvre un ticket) au lieu d'un document daté : à faire dès que le volume d'émetteurs grandit (M28, plateforme pour les développeurs).

**Pièges classiques**
- Poser `traces-v1` avant que `check 23 25` soit vert : l'étiquette ment.
- Laisser le témoin de trafic de `wb-pannes` : il remplit le compartiment de MédiDoc de dev de documents factices.
- Oublier l'étiquette `environnement` des profils de production : le panneau Pyroscope reste vide pour `env=prod`.
- Faire la démonstration en production en arrêtant MédiDoc : c'est précisément ce qu'on ne fait pas ; la recette existe pour ça.

**En production chez MédiSphère**

L'étiquette `traces-v1` ferme le bloc E (observabilité). Ce qui en dépend : F3 (astreinte) s'appuie sur le parcours de la démonstration ; M24 remplace les comptes locaux de Grafana par le SSO et peut porter l'authentification OIDC du point d'entrée OTLP ; M26 chiffre les flux internes, filtre les sorties de l'espace `traces`, branche Falco et Tetragon sur Loki et réévalue OBI ; M29 éprouve les limites de la chaîne (M23-E16) sous charge et sous chaos.
