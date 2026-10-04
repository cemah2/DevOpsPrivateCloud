# RB-012 — Superviser et diagnostiquer la forge (premiers gestes)

| | |
|---|---|
| Service | GitLab `git01` (10.10.20.12), runner `runner01` (10.10.20.15) |
| Rédigé | M01-E30 (PLAT-257) |
| Sonde | `~/lab-scripts/sonde-forge.sh` sur `adm01` (code 0/1/2, une ligne par contrôle) |

## 1. Lancer la sonde

```
admin@adm01:~$ ~/lab-scripts/sonde-forge.sh ; echo "code=$?"
```

| Ligne en échec | Premier geste | Aller plus loin |
|---|---|---|
| `readiness` HTTP 503 | lire la dépendance en échec dans le JSON (`db_check`, `redis_check`, `gitaly_check`…) | §3 |
| `readiness` HTTP 404/403 | `adm01` n'est plus dans `monitoring_whitelist` (réinstallation ? `gitlab.rb` restauré ancien ?) | `gitlab.rb` |
| `liveness` en échec | Puma bloqué ou arrêté : `sudo gitlab-ctl status puma`, `sudo gitlab-ctl tail puma` | redémarrage de Puma seulement |
| `certificat` < 30 j | renouveler (PKI provisoire jusqu'au M06, puis ACME) | M06 |
| `runner …` contact ancien | `ssh runner01 systemctl status gitlab-runner`, `journalctl -u gitlab-runner -n 50` | M01-E38 |
| `disque` ≥ 80 % | `sudo du -xh --max-depth=2 /var/opt/gitlab \| sort -h \| tail` : sauvegardes locales ? artefacts ? journaux ? | rétention (`backup_keep_time`, expiration des artefacts) |
| `mémoire` < 500 Mo | `ps -eo rss,comm --sort=-rss \| head` ; swap (`free -m`) | profil mémoire (E04, E30) |
| `services GitLab` | `sudo gitlab-ctl status` : quel service est `down:` ? | §3 |
| `sauvegarde applicative` | `journalctl -u wb-backup-gitlab.service -n 100` | RB-010, M00 RB-004 |

## 2. Carte des composants (Linux package)

| Composant | Rôle | Journal (`/var/log/gitlab/…`) |
|---|---|---|
| nginx | TLS, frontal HTTP | `nginx/gitlab_access.log`, `nginx/gitlab_error.log` |
| gitlab-workhorse | proxy intelligent (git HTTP, envois de fichiers) | `gitlab-workhorse/current` |
| puma | application Rails (web, API) | `puma/current`, `gitlab-rails/production_json.log`, `api_json.log` |
| sidekiq | tâches de fond (e-mails, pipelines, nettoyage) | `sidekiq/current` |
| gitaly | tout accès aux dépôts Git (+ hooks globaux) | `gitaly/current` |
| postgresql | base | `postgresql/current` |
| redis | cache, files de Sidekiq, sessions | `redis/current` |
| gitlab-shell / sshd | Git en SSH (sshd du système, port 22) | `gitlab-shell/gitlab-shell.log`, `journalctl -u ssh` |

`sudo gitlab-ctl tail <service>` suit un journal ; `sudo gitlab-ctl status` donne l'état et la durée depuis le dernier démarrage (un service qui redémarre en boucle a une durée de quelques secondes).

## 3. Arbre de décision « la forge ne répond pas »

1. `ping 10.10.20.12`, `ssh git01` : la VM vit-elle ? Sinon : `qm status 1004`, console (`qm terminal 1004`).
2. `sudo gitlab-ctl status` : un service `down:` → `sudo gitlab-ctl tail <service>` avant de redémarrer quoi que ce soit (on garde la cause).
3. HTTP 502 : nginx répond mais pas Puma/Workhorse (démarrage en cours ? mémoire ? → M01-E37).
4. Lenteur : `uptime`, `free -m`, `vmstat 1 5` (swap, iowait), `sudo gitlab-rake gitlab:check SANITIZE=true`.
5. Après correction : sonde verte, un `git ls-remote` en SSH et en HTTPS, un pipeline.

## 4. Métriques exposées

- `http://10.10.20.12:9100/metrics` : exporteur système (CPU, mémoire, disques, réseau) — sera collecté par Prometheus au module 21.
- `https://git01.par1.medisphere.internal/-/metrics` (liste d'adresses autorisées) : métriques de l'application, si « Enable Prometheus Metrics » est actif dans *Admin → Settings → Metrics and profiling*.
- Non activés (coût mémoire mesuré en M01-E30) : serveur Prometheus embarqué, gitlab-exporter, exporteurs Redis/PostgreSQL.
