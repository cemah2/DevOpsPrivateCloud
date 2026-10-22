# RB-251 — Descellement et redémarrage du coffre

> `docs/securite/secrets/runbooks/RB-251-descellement-et-redemarrage.md` — M25-E25 (PLAT-2625). Propriétaire : équipe Plateforme. Relu par : Sophie Laurent (RSSI), Nadia Roussel (astreinte).
> Alertes liées : `OpenBaoScelle`, `OpenBaoSansLeader` (M25-E27).

## 1. Ce qu'il faut savoir avant d'agir

- La grappe `vault01-03` est **auto-descellée** par le seal `transit` de `kms01` (clé `autodescellement-par1`). Un nœud qui démarre demande à `kms01` de déchiffrer sa clé racine. **Sans `kms01`, aucun nœud ne peut démarrer** ; ceux qui tournent continuent.
- `kms01` est scellé par **Shamir** (5 parts, seuil 3 ; `secrets/kms01-init.yml`, Vault `critique`, dépositaires : `garde-des-parts.md`). Un redémarrage de `kms01` exige **trois dépositaires**.
- Les parts de la grappe (`secrets/openbao-init.yml`) sont devenues des **clés de récupération** : elles ne descellent rien ; elles servent à `generate-root` (procédure `procedure-jeton-racine.md`) et à une migration inverse.
- Jeton du seal : orphelin, périodique (7 jours), politique `kms-autodescellement`, dans `/etc/openbao/kms.env` (root, 600) de chaque nœud, source : `vault_openbao_kms_jeton` (Vault `critique`). Le serveur le renouvelle tant qu'il tourne. **Si toute la grappe reste arrêtée plus de 7 jours, le jeton a expiré** : voir §6.
- On ne supprime **jamais** `/var/lib/openbao` d'un nœud sans avoir lu §7.

## 2. Redémarrage normal (mise à jour du système, maintenance)

1. Un nœud à la fois, **en attente d'abord** (`curl -s -o /dev/null -w '%{http_code}' https://<nœud>.par1.medisphere.internal:8200/v1/sys/health` → `429`), le nœud actif en dernier après `bao operator step-down`.
2. `sudo systemctl reboot` (ou `qm reboot <VMID>`).
3. Attendre `429` (en attente, descellé) ou `200`. Contrôles : `bao operator raft list-peers` (trois électeurs), `bao operator raft autopilot state` (`Healthy: true`, tolérance 1), `ip -br addr` (VIP sur l'actif seulement).
4. Seulement alors, le nœud suivant.

## 3. Un nœud ne démarre pas : `kms01` injoignable

Symptômes : `systemctl status openbao` en `failed` ; journal : `Error configuring seal "transit": … connection refused` (ou `context deadline exceeded`, `x509`) ; après trois échecs en une minute, systemd abandonne (`start-limit-hit`) et **ne réessaiera plus** même quand `kms01` reviendra.

1. Depuis le nœud : `curl -sS https://kms01.par1.medisphere.internal:8200/v1/sys/health` → `200` attendu. Sinon : §4 (kms01 scellé : `503`), réseau (pare-feu local de `kms01`, DNS), certificat.
2. Jeton : `bao token lookup -accessor <vault_openbao_kms_accesseur>` sur `kms01` (jeton de génération, voir §5) ; s'il a expiré ou été révoqué : §6.
3. Une fois `kms01` sain : `sudo systemctl reset-failed openbao && sudo systemctl start openbao` sur chaque nœud concerné, un par un.

## 4. `kms01` a redémarré (il est scellé)

Tant qu'il est scellé, la grappe **tourne** mais aucun nœud ne peut redémarrer : ne touche à aucun nœud de la grappe.

1. Réunir trois dépositaires de `kms01` (astreinte : appeler dans l'ordre de `garde-des-parts.md`).
2. Chacun, depuis `adm01`, dans `~/src/ansible` :
   `PARTS_FICHIER=secrets/kms01-init.yml PARTS_CLE=kms01_init BAO_ADDR=https://kms01.par1.medisphere.internal:8200 outils/openbao-parts.sh desceller <N> <SON-IDENTITÉ-AGE>`
3. Contrôle : `sys/health` de `kms01` → `200`. Puis §3 point 3 pour les nœuds restés en échec.

Délai cible : 30 min (heures ouvrées), 1 h (nuit).

## 5. Administrer `kms01` (rotation de la clé, nouveau jeton)

Aucune méthode d'authentification humaine sur `kms01`. On régénère un jeton racine (procédure `procedure-jeton-racine.md`, avec les **parts de kms01** et le jeton `vault_kms01_jeton_generation`), on fait l'action, on révoque. Actions possibles : nouveau jeton de seal (puis rôle `openbao` sur la grappe : `kms.env`, redémarrage un nœud à la fois), `transit/keys/autodescellement-par1/rotate` (les anciennes versions de la clé restent utilisables pour déchiffrer : la clé racine chiffrée par une ancienne version reste lisible ; ne **jamais** relever `min_decryption_version` de cette clé sans avoir vérifié qu'aucune donnée ne dépend plus des anciennes versions — non vérifié dans le lab : laisse-le à sa valeur).

## 6. Jeton du seal expiré ou révoqué

Les nœuds qui tournent ne voient rien jusqu'au prochain renouvellement (erreurs de renouvellement du jeton dans le journal) ; un nœud qui redémarre échoue. Créer un nouveau jeton (§5), mettre à jour `vault_openbao_kms_jeton`, appliquer le rôle `openbao` (écrit `kms.env`), redémarrer les nœuds **en attente** un par un, puis l'actif après `step-down`. Révoquer l'ancien par son accesseur s'il vit encore.

## 7. Perte définitive de `kms01`

Ce qui est perdu : la clé `autodescellement-par1`. Sans elle, **aucun** nœud arrêté ne redémarrera, et aucun instantané ne pourra être relu ailleurs. Ce qui reste : la grappe **en marche**.

1. **N'arrête plus aucun nœud.** Prévenir Claire Morel et Sophie Laurent.
2. Restaurer `kms01` depuis PBS (`par1/secrets`) si une sauvegarde existe : la clé est dans ses données Raft ; descellement Shamir (§4). C'est le cas normal.
3. Sinon, il n'y a **pas** de migration possible : migrer le seal exige de redémarrer chaque nœud, donc de déchiffrer la clé racine par l'ancien seal, donc `kms01`. Il reste à reconstruire : exporter par l'API ce qui peut l'être tant que la grappe tourne (secrets KV avec un jeton `plateforme-admin` ; politiques, méthodes et rôles sont dans `plateforme/secrets`), monter une grappe neuve (Shamir, puis un nouveau `kms01`), réinjecter, refaire émettre la PKI de services et les identifiants dynamiques. C'est pour éviter ce cas que `kms01` est sauvegardé par PBS **et** que sa restauration est essayée (RB-252).

## 8. Migration inverse vers Shamir (décision, pas une panne)

Procédure officielle « auto → Shamir » : sur chaque nœud en attente l'un après l'autre, ajouter `disabled = "true"` au bloc `seal "transit"` (le reste inchangé, `kms01` joignable), redémarrer, `bao operator unseal -migrate` avec trois **clés de récupération** (`outils/openbao-parts-p3.sh migrer`) ; puis `step-down` de l'actif, migration par le nouvel actif ; enfin l'ancien actif. Les clés de récupération redeviennent des parts Shamir. Retirer ensuite le bloc `seal` et `kms.env`.

## 9. Retirer ou remplacer un nœud

`bao operator raft remove-peer <node_id>` (depuis un nœud sain, jeton `plateforme-admin`) avant de détruire une VM ; un nœud recréé vide rejoint seul (`retry_join`) et se descelle par `kms01`. Ne jamais copier `/var/lib/openbao` d'un nœud à l'autre.

## Contacts

Astreinte Plateforme (Nadia Roussel), dépositaires (`garde-des-parts.md`), RSSI (Sophie Laurent) pour toute génération de jeton racine.
