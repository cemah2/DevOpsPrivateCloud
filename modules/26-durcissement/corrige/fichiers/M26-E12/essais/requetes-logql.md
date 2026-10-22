# Requêtes LogQL d'investigation (M26-E12) — locataire « audit », source Grafana `loki-audit`

Toutes les requêtes portent sur `{job="audit"}` ; ajuste `host` et la période. Les champs viennent du
format ENRICHED d'auditd (`auid=` numérique suivi de `AUID="nom"` en fin de ligne).

| Question | Requête |
|---|---|
| Qui a lancé des commandes sur `git01` cette nuit ? | `{job="audit", service="auditd", host="git01"} \|= "key=\"exec-humain\"" \|~ "type=EXECVE"` |
| Commandes d'une personne, partout | `{job="audit", service="auditd"} \|= "key=\"exec-humain\"" \|= "AUID=\"karim.benali\""` |
| Modifications de sudoers | `{job="audit", service="auditd"} \|= "key=\"sudoers\""` |
| Lecture de la configuration d'OpenBao | `{job="audit", service="auditd", host=~"vault0[1-3]"} \|= "key=\"openbao\""` |
| Accès refusés (EACCES/EPERM) par hôte, sur 24 h | `sum by (host) (count_over_time({job="audit", service="auditd"} \|= "key=\"acces-refuse\"" [24h]))` |
| Volume d'événements par hôte et par clé (coût) | `sum by (host) (count_over_time({job="audit", service="auditd"} [1h]))` |
| Élévations par sudo (journald, locataire `plateforme`) | `{job="journald"} \|= "sudo" \|~ "COMMAND="` |
| Écarts AIDE signalés | `{job="journald"} \| unite = "aide-verification.service"` (locataire `plateforme` ; `unite` est une métadonnée structurée, M22) |

Lecture d'un événement d'exécution : il arrive en plusieurs lignes (SYSCALL, EXECVE, CWD, PATH,
PROCTITLE) liées par le même identifiant `msg=audit(<horodatage>:<numéro>)`. Pour reconstituer la
commande : filtre sur ce numéro (`|= "audit(1792712345.123:4567)"`).
