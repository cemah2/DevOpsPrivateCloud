# Legacy-RDV en conteneur : écarts aux « 12 facteurs »

> M12-E19 (DEV-1319). Image `legacy/legacy-rdv` 2.3.1 (`ctr01.par1.medisphere.internal:5000/legacy/legacy-rdv:2.3.1` après publication), pile de recette `compose.yaml` du projet. Point de départ : la VM `legacy01` (installation InfoGér reproduite en M12-E02).

## Ce qui a changé, et ce qui n'a pas changé

Le **comportement** de l'application est identique (mêmes pages, mêmes règles, même base) : seuls `config.php` (valeurs lues dans l'environnement, valeurs par défaut d'InfoGér) et une page de sonde `sante.php` (ajout) touchent au code. Sans aucune variable, l'application se comporte comme sur la VM, sauf sur un point volontaire : **le mot de passe de la base n'a plus de valeur par défaut**.

| # (README) | Facteur | Sur la VM | Dans le conteneur | Statut |
|---|---|---|---|---|
| 1 | III configuration | identifiants en dur dans `config.php` | `LEGACY_RDV_DB_*` ; mot de passe par fichier de secret (`LEGACY_RDV_DB_PASS_FILE`) ; ancien mot de passe changé sur la base conteneurisée | corrigé (le mot de passe reste dans l'historique Git : exception Gitleaks documentée) |
| 2 | IV services attachés | MariaDB sur `localhost` | service `mariadb` de la pile, désigné par son nom | corrigé |
| 3 | VI sans état | pièces jointes sur le disque local | volume nommé sur `/var/www/legacy-rdv/uploads` | **écart assumé** : une seule instance ; stockage partagé ou objet au final F4 |
| 4 | VI sans état | sessions en fichiers | volume nommé sur `/var/lib/php/sessions` | **écart assumé** : une seule instance, sessions perdues si le volume l'est ; Valkey au F4 |
| 5 | XI journaux | `/var/log/legacy-rdv/app.log` | `LEGACY_RDV_LOG_FILE=php://stderr`, journaux Apache sur stdout/stderr | corrigé (format texte, pas JSON : écart mineur) |
| 6 | droits système | dossiers appartenant à `www-data` | Apache entier sous l'UID 33, port 8080 ; code en lecture seule (root), seuls les volumes appartiennent à 33 | corrigé |
| 7 | XII processus d'administration | `/etc/cron.d` sur la VM | service ponctuel `purge` (profil `admin`), lancé par `legacy-rdv-purge.timer` sur l'hôte | corrigé (la purge ne met toujours pas la base à jour : défaut applicatif signalé à l'équipe) |
| 8 | sonde | aucune | `sante.php` (sans session ni base) | corrigé |
| 9 | migrations | `schema.sql` à la main | inchangé : schéma joué au premier démarrage d'un volume vide ; données migrées par `mysqldump` | **écart** |
| 10 | fuseau | implicite, Paris | `LEGACY_RDV_FUSEAU` et `TZ` du conteneur MariaDB à `Europe/Paris` | conservé tel quel (sinon décalage des rendez-vous existants) |
| 11 | `display_errors` | activé | `LEGACY_RDV_AFFICHER_ERREURS=0` dans l'image, `display_errors=Off` | corrigé |
| 12 | configuration PHP dans Apache | `php_value` dans l'hôte virtuel | `conteneur/php-legacy-rdv.ini` | corrigé (sinon 2 Mo au lieu de 6 : téléversements refusés) |
| 13 | `mod_php`, prefork | idem | idem (image `php:8.4-apache`) | **écart** : passage à php-fpm au F4 |

## Migration des données de `legacy01`

```
admin@legacy01:~$ sudo mariadb-dump --single-transaction legacy_rdv | gzip > /tmp/legacy_rdv.sql.gz
admin@legacy01:~$ sudo tar -C /var/www/legacy-rdv -czf /tmp/uploads.tgz uploads
```

Transfert par `adm01` (scp), import dans la pile (`docker compose exec -T mariadb mariadb -u root -p… legacy_rdv`), pièces jointes copiées dans le volume par un conteneur jetable qui monte le volume (`--user 33`). Les fichiers temporaires sont supprimés des deux côtés : ce sont des données de santé.
