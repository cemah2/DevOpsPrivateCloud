# Legacy-RDV — l'ancienne prise de rendez-vous (héritée d'InfoGér)

Application monolithique PHP 8.4 + MariaDB écrite et exploitée par InfoGér de 2014 à 2021, toujours utilisée par quelques cabinets. Elle tourne sur une VM unique (`legacy-rdv01`, importée au module 09) : Apache avec `mod_php`, MariaDB sur la même machine. Elle sera conteneurisée au module 12, puis migrée vers Kubernetes dans le final F4.

**Ce code est volontairement daté.** Il fonctionne, il échappe correctement le HTML et utilise des requêtes préparées, mais il accumule les choix qui rendent une migration pénible. Ne le prends pas pour modèle ; ne le « corrige » pas non plus avant l'exercice qui le demande.

Projet GitLab cible : `legacy/legacy-rdv`.

## Fichiers

| Fichier | Rôle |
|---|---|
| `index.php` | Liste des rendez-vous à venir, filtre par praticien |
| `prendre.php` | Formulaire de prise de rendez-vous avec pièce jointe facultative (PDF, JPEG, PNG, 5 Mo) |
| `piece.php?id=N` | Téléchargement de la pièce jointe d'un rendez-vous |
| `config.php` | Configuration… **avec les identifiants de base en dur** |
| `inc/commun.php` | Session, connexion MariaDB, journal, gabarit HTML |
| `cron/purge-uploads.php` | Purge nocturne des pièces jointes de plus d'un an (ligne de commande seulement) |
| `schema.sql` | Tables et jeu de données fictif |
| `uploads/` | Pièces jointes téléversées (vide dans le dépôt) |
| `vm/apache-legacy-rdv.conf` | Hôte virtuel Apache tel qu'installé sur la VM |
| `vm/cron.d-legacy-rdv` | Tâche planifiée de la VM (`/etc/cron.d/legacy-rdv`) |

## Installation sur la VM (procédure InfoGér, Debian 13)

```
admin@legacy-rdv01:~$ sudo apt-get install -y apache2 libapache2-mod-php8.4 php8.4-mysql mariadb-server
admin@legacy-rdv01:~$ sudo mkdir -p /var/www/legacy-rdv /var/log/legacy-rdv
admin@legacy-rdv01:~$ sudo cp -r ~/legacy-rdv/. /var/www/legacy-rdv/
admin@legacy-rdv01:~$ sudo chown -R www-data: /var/www/legacy-rdv/uploads /var/log/legacy-rdv
admin@legacy-rdv01:~$ sudo mariadb -e "CREATE DATABASE legacy_rdv CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; \
  CREATE USER 'legacy_rdv'@'localhost' IDENTIFIED BY 'InfoGer2014!'; \
  GRANT SELECT, INSERT, UPDATE, DELETE ON legacy_rdv.* TO 'legacy_rdv'@'localhost';"
admin@legacy-rdv01:~$ sudo mariadb legacy_rdv < /var/www/legacy-rdv/schema.sql
admin@legacy-rdv01:~$ sudo cp /var/www/legacy-rdv/vm/apache-legacy-rdv.conf /etc/apache2/sites-available/legacy-rdv.conf
admin@legacy-rdv01:~$ sudo a2dissite 000-default && sudo a2ensite legacy-rdv && sudo systemctl reload apache2
admin@legacy-rdv01:~$ sudo cp /var/www/legacy-rdv/vm/cron.d-legacy-rdv /etc/cron.d/legacy-rdv
```

Le mot de passe est celui de `config.php`, puisque c'est là qu'il est écrit. Extensions PHP utilisées : `mysqli`, `fileinfo` (`mime_content_type`), `mbstring`, `session`.

En développement, sans Apache : `php -S 127.0.0.1:8000` depuis ce répertoire (MariaDB locale nécessaire).

## Ce qui rend la migration difficile

Chaque point s'oppose à un des « 12 facteurs » (entre parenthèses) et casse quelque chose dès qu'on lance deux instances ou qu'on passe en conteneur.

1. **Identifiants de base en dur dans `config.php`** (III, configuration). Le mot de passe est versionné avec le code, identique partout, jamais changé depuis 2014 ; changer de base ou de mot de passe impose de modifier le code et de redéployer. Un analyseur de secrets (Gitleaks, module 01) le signalera dès le premier `git push` : c'est attendu.
2. **Base « localhost »** (IV, services externes). L'application suppose MariaDB sur la même machine (socket Unix local). Dans un conteneur, `localhost` est le conteneur lui-même : il n'y a pas de MariaDB.
3. **Pièces jointes écrites dans `uploads/`, sur le disque local** (VI, processus sans état). Une seconde instance ne voit pas les fichiers de la première ; un conteneur recréé les perd ; la base continue de les référencer (`piece.php` répond 404). Il faut un volume partagé (l'export NFS `/legacy-rdv` de CephFS préparé au module 08, un PVC) ou, mieux, un stockage objet.
4. **Sessions PHP en fichiers sur le disque** (VI). Le jeton anti-CSRF et le message de confirmation vivent dans `/var/lib/php/sessions` du serveur qui a servi le formulaire. Derrière un répartiteur à deux instances, un POST arrivé sur l'autre instance échoue avec « Votre session a expiré » (journal : `jeton CSRF invalide`). Contournement : affinité de session ; solution : sessions dans un stockage partagé (Valkey, base).
5. **Journal dans un fichier, `/var/log/legacy-rdv/app.log`** (XI, journaux comme flux). Format libre, rotation confiée à logrotate, rien sur stdout : `kubectl logs` et le collecteur de la plateforme ne voient rien. Pire : si le répertoire n'existe pas ou n'est pas accessible en écriture, `@file_put_contents` échoue **sans bruit** et le journal est perdu.
6. **Chemin absolu et droits système** : `/var/log/legacy-rdv/` et `uploads/` doivent appartenir à `www-data`, ce qui suppose un système de fichiers modifiable et un utilisateur précis ; un conteneur en lecture seule ou sous un autre UID ne peut pas écrire.
7. **Tâche cron sur la VM** (XII, processus d'administration). La purge vit dans `/etc/cron.d`, hors du code déployé. Avec plusieurs instances, elle tourne autant de fois qu'il y a de machines ; en conteneur, elle ne tourne plus du tout (devient un CronJob, qui doit voir les mêmes fichiers). Elle supprime les fichiers sans mettre la base à jour.
8. **Pas de point de santé** : aucune URL ne dit si l'application est vivante ou prête. `index.php` interroge la base : l'utiliser comme sonde fait redémarrer l'application à chaque panne de MariaDB.
9. **Pas de migrations versionnées** : `schema.sql` est rejoué à la main ; ce qui tourne en production peut différer du fichier, et rien ne le dit.
10. **Dates sans fuseau** (`DATETIME`, `date_default_timezone_set` en dur) : l'heure « de Paris » est implicite. Une base ou un conteneur en UTC décale les rendez-vous si l'on n'y prend pas garde lors de la migration des données.
11. **`display_errors` activé** : une erreur affiche chemins et requêtes à l'utilisateur. Acceptable sur un poste de développement, pas en production.
12. **Configuration PHP dans l'hôte virtuel Apache** (`php_value upload_max_filesize`) : changer de serveur (php-fpm, image officielle `php`) fait silencieusement revenir aux valeurs par défaut (2 Mo).
13. **Dépendance à `mod_php` et au modèle prefork** : un seul processus Apache par requête, mémoire non bornée ; passer à php-fpm + nginx change les journaux, les limites et la façon de transmettre la configuration.

## Vérification

```
admin@adm01:~/src/legacy-rdv$ for f in $(find . -name '*.php'); do php -l "$f"; done
```
