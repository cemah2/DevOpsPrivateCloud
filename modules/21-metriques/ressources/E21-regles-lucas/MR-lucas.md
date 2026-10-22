# MR !14 — plateforme/observabilite : « Alertes pour tout couvrir »

**Auteur** : Lucas Martin · **Branche** : `lucas/alertes` · **Cible** : `main`

Salut,

Comme on n'avait pas grand-chose côté alertes, j'en ai écrit pour couvrir le plus de cas possible :
erreurs et lenteur de l'API, redémarrages de pods, mémoire et disques des VMs, et une alerte si
MédiAgenda disparaît. J'ai aussi ajouté des règles d'enregistrement pour aller plus vite dans
Grafana.

- J'ai mis `severity: page` sur ce qui doit réveiller, comme dans le chart.
- Pour les erreurs, j'ai pris `irate` sur 1 minute, c'est plus réactif que `rate`.
- J'ai mis la valeur dans une étiquette pour qu'on la voie directement dans le sujet du courriel.
- Les liens de runbook pointent vers le wiki d'InfoGér, c'est là qu'étaient les procédures avant.

Je n'ai pas écrit de tests, `promtool check rules` passe. Je peux fusionner ?
