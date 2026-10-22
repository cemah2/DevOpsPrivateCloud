# Post-mortem — INC-4923 — Rendez-vous de démonstration supprimés en recette par un compte de service d'outillage

> Exemple de livrable de M22-E23 (variante : panne enchaînée E20 variante 1, limite d'ingestion de
> MédiAgenda). Heures, identifiants et pods de **ton** incident différeront : la forme et la démarche
> comptent. Sans recherche de coupable.

| | |
|---|---|
| **Statut** | Relu |
| **Date de l'incident** | 2026-11-05 |
| **Rédacteur** | <MOI> (astreinte) |
| **Relecteurs** | Nadia Roussel, Sophie Laurent, Julien Petit |
| **Sévérité** | P2 — données de recette (démonstration client) perdues, aucun impact production, mais un accès non maîtrisé dans un espace applicatif |
| **Durée d'impact** | 10:14 → 10:15 (suppressions) ; outillage des journaux dégradé 10:31 → 11:22 |
| **Services touchés** | MédiAgenda recette ; collecte des journaux de MédiAgenda (Loki, locataire `mediagenda`) |

## 1. Résumé

Quatre rendez-vous de démonstration (praticien `dr-demo-recette`) ont été supprimés en recette à 10:15 par des requêtes `DELETE` émises **depuis l'intérieur** d'un pod MédiAgenda, au moyen d'un `kubectl exec` fait avec le compte de service `wb-pannes/outillage-recette`. Ce compte avait reçu la veille un droit d'`exec` dans `mediagenda-recette` pour un « outil de purge des données de test ». Pendant l'enquête, la collecte des journaux de MédiAgenda était presque bloquée par une limite d'ingestion erronée (commit du 05/11, 09:58), réparée à 11:22. Les droits du compte ont été retirés à 11:40 ; les rendez-vous ont été recréés par l'équipe.

## 2. Impact

- Recette : 4 rendez-vous de démonstration perdus (recréés à la main par l'équipe, 15 min). Production non concernée.
- Données : aucune donnée réelle de patient (données de démonstration). Aucune exposition : les journaux ne contiennent pas le contenu des rendez-vous (politique § 1).
- Journaux : entre 10:31 et 11:22, ≈ 2 300 lignes de MédiAgenda (tous environnements) abandonnées par Alloy après refus de Loki (`loki_write_dropped_entries_total`) ; les preuves de l'incident (10:14-10:15) étaient déjà enregistrées.
- Conformité : l'accès a été tracé de bout en bout par le journal d'audit de l'API (exigence ISO 27001 A.8.15 tenue) ; la faiblesse est dans l'attribution du droit.

## 3. Chronologie

| Heure | Événement | Source |
|---|---|---|
| 04/11 17:42 | Création du compte `wb-pannes/outillage-recette`, du Role et du RoleBinding `outillage-recette` dans `mediagenda-recette` (`pods` get/list, `pods/exec` get/create) | audit, `{job="kubernetes-audit"} \| user=~"…" \| resource="rolebindings"` |
| 10:13 | 4 rendez-vous `dr-demo-recette` créés (ids 412-415) par un `exec` dans `mediagenda-7c9d…-x2k4p` | `mediagenda` : `"rendez-vous créé"`, `client` 127.0.0.1 ; audit : `pods/exec` |
| 10:14:52 | `exec` dans le même pod par `system:serviceaccount:wb-pannes:outillage-recette` | audit, `{job="kubernetes-audit"} \|= "outillage-recette" \|= "exec"` |
| 10:14:53-55 | 4 × `DELETE /api/v1/rendez-vous/{412..415}` → 204, `client` 127.0.0.1 ; 4 × `"rendez-vous supprimé"` | `mediagenda`, `{namespace="mediagenda-recette"} \|= "supprimé" \| json` |
| 09:58 (antérieur) | Commit « plafond d'ingestion de MédiAgenda » sur `plateforme/observabilite` | GitLab, Argo CD |
| 10:31 | Surcharge rechargée par Loki : 429 pour `mediagenda` | `loki_discarded_samples_total{reason="rate_limited"}` |
| 10:45 | Appel de Julien ; ticket INC-4923 | téléphone |
| 10:58 | Grafana « Loki — mediagenda » presque vide : hypothèse « collecte » ; journaux d'Alloy : `status=429` | `kubectl logs ds/alloy` |
| 11:12 | Cause trouvée (`git log -p -- loki/values.yaml`) ; MR de revert | GitLab |
| 11:22 | Synchronisation d'Argo CD ; plus de rejets | Prometheus |
| 11:25-11:36 | Enquête dans `mediagenda` puis `audit` (requêtes ci-dessous) | Loki |
| 11:40 | RoleBinding et Role `outillage-recette` supprimés (MR `plateforme/k8s` pour tracer) | audit |
| 11:55 | Julien prévenu ; démonstration rétablie | ticket |

## 4. Causes

### 4.1 Causes racines

1. **Incident** : un compte de service d'outillage disposait d'un droit d'`exec` dans un espace applicatif ; l'outil de purge l'a utilisé pour appeler l'API de MédiAgenda **depuis le pod** (`127.0.0.1`), contournant les politiques réseau et le chemin normal (Gateway). Preuves :
   ```
   logcli query --org-id=mediagenda --from=2026-11-05T09:10:00Z --to=2026-11-05T09:20:00Z \
     '{namespace="mediagenda-recette"} |= "supprimé" | json | line_format "{{.horodatage}} rdv={{.rdv_id}}"'
   logcli query --org-id=audit --from=2026-11-05T09:10:00Z --to=2026-11-05T09:20:00Z \
     '{job="kubernetes-audit"} |= "exec" | user=~"system:serviceaccount:.*"'
   ```
2. **Outillage** : commit qui a fixé `ingestion_rate_mb: 0.0001` (104 octets/s) pour `mediagenda` en croyant convertir « 100 Mo par jour » ; aucune revue n'a relu l'unité (Mo/s).

### 4.2 Facteurs contributifs

- Aucun contrôle d'admission ni règle de RBAC n'interdit un droit d'`exec` à un compte hors de l'équipe dans `mediagenda-*`.
- Aucune alerte sur un `exec` dans un espace applicatif.
- L'alerte `LokiEchantillonsRejetes` (M22-E14) attend 10 minutes : elle a sonné à 10:41, après le début de la perte.

## 5. Détection et diagnostic

- Détection par l'utilisateur (Julien), 30 min après les suppressions : trop tard.
- Ce qui a ralenti : la source Grafana vide laissait croire à une perte de données ; l'audit était sain, mais il fallait d'abord rétablir la collecte de MédiAgenda pour croiser.
- Ce qui a accéléré : l'adresse `127.0.0.1` dans les journaux d'accès (geste né dans le pod) ; les métadonnées structurées de l'audit (`user`, `resource`, `object_name`).

## 6. Ce qui a bien fonctionné

- Les preuves étaient dans Loki **avant** la panne d'ingestion ; aucun ticket ne contenait de donnée.
- Les limites par locataire ont contenu le problème d'ingestion à MédiAgenda.

## 7. Actions

| # | Action | Type | Responsable | Échéance | Ticket |
|---|---|---|---|---|---|
| 1 | Retirer les droits d'`exec` des comptes de service hors équipe dans `mediagenda-*` et `medidoc-*` ; revue des RoleBindings | prévenir | Plateforme | fait | SEC-2323 |
| 2 | ValidatingAdmissionPolicy : refuser un RoleBinding donnant `pods/exec` dans un espace d'équipe à un sujet hors de l'équipe | prévenir | Karim | M26 | SEC-2324 |
| 3 | Règle du *ruler* (locataire `audit`) : `exec` dans `mediagenda-*` par une identité hors `medisphere:mediagenda-devs` → `equipe=plateforme`, `gravite=avertissement` | détecter | <MOI> | +1 semaine | PLAT-2323 |
| 4 | Commentaire d'unité et test CI (valeur minimale) pour les limites d'ingestion dans `loki/values.yaml` | prévenir | <MOI> | +1 semaine | PLAT-2320 |
| 5 | `LokiEchantillonsRejetes` : `for: 2m` pour `rate_limited` sur les locataires applicatifs | détecter | <MOI> | +1 semaine | PLAT-2314 |
| 6 | RB-220 : section « enquête » (requêtes ci-dessus) | documenter | <MOI> | fait | — |
