# M25-E11 — Pourquoi deux chemins (modèle de réponse)

Une politique OpenBao donne des capacités sur des **chemins** (`path "kv/data/…" { capabilities = ["read"] }`), jamais sur une clé à l'intérieur d'un secret KV : lire `kv/data/plateforme/ansible-vault` renvoie **toutes** ses clés (`lab` et `critique`) d'un coup. Avec un seul secret, la politique de Lucas (qui ne doit voir que `lab`) verrait aussi `critique`. D'où deux secrets, `kv/plateforme/ansible-vault/lab` et `…/critique`, chacun avec une clé `mot-de-passe`, et une politique par chemin. Même raisonnement pour l'historique : `kv/metadata/plateforme/ansible-vault/*` donnerait la liste et les versions des deux.

Contrôle fait : `bao token capabilities <jeton ansible-lab> kv/data/plateforme/ansible-vault/critique` → `deny`.
