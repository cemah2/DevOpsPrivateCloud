<!-- docs/conteneurs/legacy-rdv-12-facteurs.md : EXTRAIT à intégrer (F4-S12). Colonne « Statut F4 ». -->
| Point du README | Statut M12 | Statut F4 (2.4.0 sur Kubernetes) |
|---|---|---|
| 1. Identifiants en dur | corrigé (environnement, fichier de secret) | corrigé ; mot de passe généré par OpenBao, livré par ESO |
| 2. Base « localhost » | corrigé | corrigé (Service `legacy-rdv-db` de l'opérateur) |
| 3. Pièces jointes locales | écart assumé (volume, une instance) | **corrigé** : PVC CephFS RWX partagé |
| 4. Sessions en fichiers | écart assumé (une instance) | **corrigé** : sessions dans MariaDB |
| 5. Journal en fichier | corrigé (`php://stderr`) | corrigé ; collecté par Alloy (M22) |
| 6. Droits système | corrigé (www-data, 8080) | corrigé ; racine en lecture seule, PSA `restricted` |
| 7. Cron sur la VM | corrigé (minuterie de l'hôte) | **corrigé** : CronJob, base mise à jour avec le disque |
| 8. Pas de point de santé | corrigé (`sante.php`) | corrigé ; + `pret.php` (disponibilité, base) |
| 9. Pas de migrations | défaut | partiel : `sql/V2__sessions.sql` par SqlJob ; pas d'outil de migrations (ADR-0340) |
| 10. Dates sans fuseau | écart (fuseau imposé) | **corrigé** côté application (« maintenant » calculé par PHP) ; données inchangées (`DATETIME`) |
| 11. `display_errors` | corrigé (image) | corrigé |
| 12. Réglages PHP dans Apache | corrigé (`php.ini` de l'image) | corrigé |
| 13. mod_php prefork | écart assumé | écart assumé (deux réplicas de 256 Mio suffisent) |
