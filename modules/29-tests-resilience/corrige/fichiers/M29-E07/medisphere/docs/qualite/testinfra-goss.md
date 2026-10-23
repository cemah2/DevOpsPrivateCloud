# Testinfra ou Goss : tester l'état des VMs du socle

> `plateforme/medisphere` — `docs/qualite/testinfra-goss.md` (M29-E07, PLAT-3007). Essai sur `dns02` et `nbx01`, mêmes vérifications que `tests/infra` (node_exporter, alloy, chrony).

| Critère | Testinfra 10.2 (pytest) | Goss 0.4.10 |
|---|---|---|
| Où s'exécute la logique | sur le **contrôleur** (`runner01`, `adm01`), commandes envoyées en SSH | **sur l'hôte**, binaire Go autonome (aucun interpréteur) |
| Langage des tests | Python (boucles, fixtures, lecture du registre JSON des exceptions, conditions par groupe d'inventaire) | YAML déclaratif (+ gabarits) ; pas de logique au-delà des gabarits |
| Inventaire | celui d'Ansible (`ansible://socle`), NetBox | aucun : un fichier par hôte, rendu par Ansible |
| Vue extérieure | oui (contrôle HTTPS depuis le contrôleur, comme Prometheus) | non (tout est vu de l'hôte ; HTTPS vers lui-même) |
| Privilèges | `sudo` au cas par cas (`sshd -T`, fichiers 0640) | ici sans privilège (utilisateur dynamique) : pas de lecture de `web.yml` ni de `/etc/alloy`, pas de `sshd -T` |
| Résultat | rapport JUnit dans la CI, ponctuel ou nocturne | **en continu** : `goss serve` → `/healthz` (200/503) sondé par `mon01`, alerté |
| Vitesse | ~2 s par hôte et par fichier de tests (SSH) | < 0,1 s par hôte (local), résultats en cache 30 s |
| Coût de possession | un dépôt, une CI, des tests qui suivent les rôles | un binaire et un service par VM, un fichier par VM, un port ouvert, une sonde et deux alertes |
| Ce qui a manqué | — | les tests conditionnels (exceptions du durcissement, groupes) ; la vue de l'extérieur |

**Décision proposée** (à confirmer dans l'ADR-0290, M29-E17) : Testinfra reste l'outil des tests d'infrastructure (CI nocturne, logique riche, une seule source de vérité : l'inventaire). Goss n'est pas déployé sur le parc : sa force (vérification continue sur l'hôte) recouvre ce que font déjà node_exporter et les alertes de supervision, et la **dérive** de configuration est déjà détectée chaque jour par le pipeline `derive` de `plateforme/ansible` (M04-E29). On le garde en tête pour des images ou des conteneurs à valider sans Python (dgoss), et on retire l'essai (`playbooks/goss-retrait.yml`).
