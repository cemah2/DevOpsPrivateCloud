# Journal de travail — confinement (M26-E13)

## AppArmor : Mailpit sur mon01

| Étape | Commande | Constat |
|---|---|---|
| Profil chargé ? | `sudo aa-status \| grep -A1 mailpit` | « mailpit » en complain, processus listé sous le profil |
| Le lien ne compte pas | `readlink -f /usr/local/bin/mailpit` | `/opt/mailpit/1.31.6/mailpit` : c'est ce chemin que le profil vise |
| Ce qui aurait été refusé | `sudo journalctl -k --since -7d \| grep 'apparmor="ALLOWED"' \| grep mailpit` | <à remplir : chemins et opérations> |
| Ajouts proposés | `sudo aa-logprof -f /var/log/kern.log` (ou le journal) | <règles acceptées, refusées, pourquoi> |
| Enforce | `sudo aa-status --json \| jq '.profiles.mailpit'` | `"enforce"` |
| Essais | courriel de test, `curl` sur 8025 (API des checks), interface par 8443 | <résultats> |
| Ce que le profil empêche | `sudo -u mailpit` impossible ; essai d'exécution depuis le profil : `aa-exec -p mailpit -- /bin/sh` | refusé (`Permission denied`) |

## SELinux : hôtes Rocky (ipa01, ceph01-03, durci-rocky)

| Question | Commande | Constat |
|---|---|---|
| Mode | `getenforce ; sestatus` | Enforcing, targeted |
| Services confinés / non confinés | `ps -eZ \| awk '{print $1}' \| sort \| uniq -c \| sort -rn \| head` | `unconfined_service_t` = services installés hors paquets (node_exporter, alloy) |
| Domaine d'AIDE pendant la vérification | `sudo systemctl start aide-verification ; ps -eZ \| grep aide` | `aide_t` (init_daemon_domain) |
| Booléens modifiés localement (ipa01) | `sudo semanage boolean -l -C` | <liste posée par ipa-server-install> |
| Règles de contexte locales | `sudo semanage fcontext -l -C` | <liste> |
| Refus récents | `sudo ausearch -m AVC,USER_AVC -ts recent ; sudo ausearch -m AVC -ts today \| audit2why` | <refus, cause, décision> |
