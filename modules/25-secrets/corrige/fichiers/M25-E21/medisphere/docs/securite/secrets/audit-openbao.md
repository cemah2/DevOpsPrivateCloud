# Audit d'OpenBao : qui a lu quel secret

> Propriétaire : équipe Plateforme · Lecteurs : Sophie Laurent (RSSI), astreinte · Ticket : SEC-2621 (M25-E21)

## 1. La chaîne

```
requête → OpenBao (nœud actif) → dispositif « fichier » : /var/log/openbao/audit.log (JSON, une ligne par requête et une par réponse)
        → logrotate (quotidien, 14 jours, SIGHUP) → Alloy (rôle alloy, groupe openbao) → Loki, locataire « audit » (1 an), {service="openbao"}
        → ruler de Loki (loki/regles/audit/openbao.yaml) → Alertmanager → plateforme@ / astreinte@
```

- Dispositif **déclaré** dans `openbao.hcl` (rôle `openbao`, variable `openbao_audit`) : l'API ne crée plus de dispositif (OpenBao ≥ 2.4), un dispositif déclaré est **immuable** (nouveau chemin pour changer une option) et identique sur tous les nœuds.
- **Si aucun dispositif ne peut écrire, OpenBao refuse toutes les requêtes** (HTTP 500, « no audit backend succeeded in logging the response »). Un audit qui casse = un coffre qui s'arrête : c'est voulu (rien ne passe sans trace). Surveillance : alerte `OpenBaoAuditImpossible` (journal du service, locataire `plateforme`) et, au M25-E27, la métrique d'échec d'audit. Second dispositif (`syslog` ou `socket`) étudié et non retenu pour l'instant : il doublerait la trace vers journald, donc vers le locataire `plateforme` (rétention 14 jours, lecteurs plus nombreux) ; à revoir avec un filtre d'Alloy dédié.
- Valeurs sensibles en **HMAC-SHA256** (sel propre au dispositif) ; chemins, identités, adresses, politiques en clair ; **accessors en clair** (`hmac_accessor = "false"`) pour pouvoir révoquer un jeton vu dans l'audit.
- Chemins **non audités** par conception : `sys/init`, `sys/seal-status`, `sys/seal`, `sys/unseal`, `sys/leader`, `sys/health`, `sys/storage/raft/bootstrap`, `sys/storage/raft/join` (et `sys/metrics` si non authentifié).

## 2. Requêtes LogQL (Grafana → Explore, source Loki, en-tête `X-Scope-OrgID: audit`)

Champs utiles d'une ligne (`| json` aplatit `request.path` en `request_path`…) : `type` (`request`/`response`), `time`, `request.id`, `request.operation` (`read`, `create`, `update`, `delete`, `list`), `request.path`, `request.remote_address`, `auth.display_name` (`oidc-<identifiant>`, `approle`, `gitlab-<projet>`, `k8s-par1-<compte>`…), `auth.policies`, `auth.metadata` (rôle, projet, espace…), `auth.accessor`, `error`.

**Qui a lu un secret de production de MédiAgenda (7 derniers jours)** :
```logql
{service="openbao"} | json type="type", chemin="request.path", operation="request.operation", qui="auth.display_name", ip="request.remote_address"
  | type="response" | operation="read" | chemin=~"kv/data/mediagenda/prod/.*"
  | line_format "{{.qui}} {{.ip}} {{.chemin}}"
```
(Attendu : l'identité d'ESO de `mediagenda-prod` toutes les `refreshInterval` ; toute autre identité est à expliquer.)

**Quels secrets une identité a-t-elle lus** (remplacer `<QUI>`) :
```logql
{service="openbao"} | json type="type", chemin="request.path", qui="auth.display_name" | type="response" | qui="<QUI>"
```

**Refus** (politique trop stricte ou tentative) :
```logql
{service="openbao"} | json type="type", erreur="error", chemin="request.path", qui="auth.display_name" | type="response" | erreur=~".*permission denied.*"
```

**Politiques** (création, modification, suppression) :
```logql
{service="openbao"} | json type="type", chemin="request.path", operation="request.operation", qui="auth.display_name" | type="response" | chemin=~"sys/(policies/acl|policy)/.+" | operation=~"create|update|delete"
```

**Signatures Cosign** (M25-E20) : projet, référence et pipeline viennent des `claim_mappings` du rôle `ci-signature` :
```logql
{service="openbao"} | json type="type", chemin="request.path", projet="auth.metadata.projet", ref="auth.metadata.reference", pipeline="auth.metadata.pipeline"
  | type="response" | chemin="transit/sign/cosign-medisphere/sha2-256"
```

**Un jeton précis** (accessor en clair) :
```logql
{service="openbao"} |= "<ACCESSOR>"
```

## 3. Retrouver qui a vu une valeur précise

Les valeurs sont en HMAC : on calcule le HMAC de la valeur **avec le sel du dispositif**, puis on le cherche (droit `sys/audit-hash/fichier`, `securite-audit` et `plateforme-admin`) :
```
admin@adm01:~$ read -rs v; printf '%s' "$v" | jq -Rs '{input: .}' | bao write -field=hash sys/audit-hash/fichier - ; unset v
hmac-sha256:3a5f…
```
```logql
{service="openbao"} |= "hmac-sha256:3a5f…" | json qui="auth.display_name", chemin="request.path" | line_format "{{.qui}} {{.chemin}}"
```
Le HMAC change si le dispositif change (nouveau chemin = nouveau sel) : refaire le calcul pour chaque dispositif de la période.

## 4. Alertes

| Alerte | Locataire | Gravité | Ce qui la déclenche |
|---|---|---|---|
| `OpenBaoJetonRacineUtilise` | audit | critique | toute réponse à une requête faite avec un jeton `root` |
| `OpenBaoPolitiqueModifiee` | audit | avertissement | création, modification ou suppression de politique |
| `OpenBaoCleTransitModifiee` | audit | avertissement | création, réglage, rotation, découpage, import ou suppression d'une clé de transit |
| `OpenBaoAuditImpossible` | plateforme | critique | « failed to audit » dans le journal du service (le coffre refuse les requêtes) |

## 5. Panne de l'audit

Symptôme : toutes les requêtes en 500 « internal error », `bao status` normal (non audité). Diagnostic sur le nœud actif : `journalctl -u openbao -n 50` (« failed to audit »), `df -h /var/log`, `ls -l /var/log/openbao/`, `findmnt /var/log`. Correctif : libérer de la place ou rétablir le fichier et ses droits, puis `systemctl reload openbao`. Jamais : supprimer le dispositif pour « débloquer » (il est déclaré : on ne peut pas, et ce serait couper la trace).
