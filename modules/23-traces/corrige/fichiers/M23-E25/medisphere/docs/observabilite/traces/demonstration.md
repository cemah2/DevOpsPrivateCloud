# Démonstration : de l'alerte à la ligne de code (M23-E25)

> Exemple du corrigé, déroulé en recette le 2026-11-12 avec l'outil de charge de M21-E23 et une erreur provoquée
> (MédiDoc de recette arrêté une minute). Identifiants réels de l'essai, aucune donnée de santé.

1. **Alerte** : `ErrorBudgetBurn` de Pyrra (`slo="mediagenda-disponibilite"`, fenêtre courte) à 14 h 02 ; tableau `m23-slo-traces`, variable `env=recette` : SLI 1 h à 98,7 %, budget 28 j à 61 %.
2. **Exemplar** : sur le panneau « Latence p95 par route, avec exemplars », un point de `POST /api/v1/rendez-vous/{rdv_id}/pieces-jointes` à 14 h 01 m 37 s, latence 5,02 s, exemplar `trace_id=4bf92f3577b34da6a3ce929d0e0e4736`.
3. **Trace** : « Voir la trace » ouvre la trace `4bf92f3577b34da6a3ce929d0e0e4736` : span serveur de `mediagenda-api` (502), span `mediagenda.piece_jointe.deposer` en erreur, span client `POST` vers MédiDoc en erreur après 5 s (*connect timeout*), aucune span `medidoc` : MédiDoc n'a jamais reçu la requête.
4. **Journaux** : « Logs for this span » ouvre `Loki — mediagenda` filtré sur le `trace_id` : ligne `pièce jointe refusée par MédiDoc` (`erreur: ConnectTimeout`), même `trace_id`, `rdv_id` seul (pas de donnée patient).
5. **Profil** : depuis la span racine, « Profiles for this span » (Pyroscope, même service et même période) : rien d'anormal sur le CPU, ce qui confirme une attente réseau et non un calcul.
6. **Cause** : `kubectl -n medidoc-recette get deploy medidoc` : 0 réplica (arrêt volontaire de l'essai) ; retour à 1 réplica à 14 h 04, SLI rétabli à 14 h 06.

Durée du parcours, de l'alerte à la cause : 3 min 40 s.
