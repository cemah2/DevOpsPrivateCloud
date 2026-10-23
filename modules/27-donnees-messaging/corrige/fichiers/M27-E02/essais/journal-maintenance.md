# Journal de maintenance — mediagenda-db (recette) — M27-E02

> Modèle à remplir pendant la section D. Une ligne par mesure ; les durées viennent de la sonde
> `/pret` (une requête par seconde) et de `kubectl cnpg status`. Valeurs ci-dessous : FORME
> attendue, pas résultats de référence (non mesurés en conditions réelles).

| Date | Opération | Commande | Primaire avant → après | Durée sans écriture (sonde) | Réponses ≠ 200 | Remarques |
|---|---|---|---|---|---|---|
| AAAA-MM-JJ hh:mm | Bascule planifiée | `kubectl cnpg promote mediagenda-db mediagenda-db-2 -n mediagenda-recette` | `-1` → `-2` | … s | … (503 de `/pret`) | clients du pooler : erreurs « server conn crashed » pendant … s, puis reprise sans redémarrage de l'API |
| | Drainage d'un nœud de réplique | `kubectl drain <NOEUD-REPLIQUE> --ignore-daemonsets --delete-emptydir-data` | inchangé | 0 s | 0 | l'instance évincée reste `Pending` : trois travailleurs, anti-affinité **requise**, les deux autres portent déjà une instance ; elle revient sur son nœud après `uncordon` (même PVC) et rattrape par la réplication. Le PDB des réplicas n'autorise qu'une réplique arrêtée à la fois |
| | Drainage du nœud du primaire | même commande | `-2` → `-x` | … s | … | « a switchover happens ahead of the drain » (doc CNPG 1.30) : le PDB du primaire retient l'éviction, l'opérateur bascule, puis l'ancien primaire, devenu réplique, est évincé |
| | Image reconstruite (18.6, par empreinte) | MR `plateforme/k8s`, `task appliquer` | `-x` → `-y` | … s | … | réplicas d'abord, puis bascule (primaryUpdateMethod: switchover), ancien primaire en dernier |
| | Montée 18.4 → 18.6 (`wb-essais/essai-maj`) | `kubectl patch cluster essai-maj --type merge -p '{"spec":{"imageName":"…18.6…"}}'` | | — | — | `SELECT version()` avant/après |
