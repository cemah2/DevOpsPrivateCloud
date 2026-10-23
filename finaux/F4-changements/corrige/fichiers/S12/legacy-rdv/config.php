<?php
/*
 * Configuration de Legacy-RDV 2.4.0 — projet legacy/legacy-rdv (F4-S12, CHG-3412).
 * Reprend config.php de M12-E19 (tout par l'environnement, mot de passe sans valeur par défaut, lu
 * dans un fichier de secret) et ajoute ce qu'exige l'exécution en plusieurs réplicas :
 *   LEGACY_RDV_SESSIONS    « fichiers » (défaut historique, une seule instance) ou « base » (sessions
 *                          dans la table « sessions » de MariaDB : partagées entre les réplicas) ;
 *   LEGACY_RDV_DB_PORT     port de MariaDB (3306) ;
 *   LEGACY_RDV_VERSION     version affichée dans les journaux.
 * Sans aucune variable, l'application se comporte comme sur la VM d'InfoGér (au mot de passe près).
 */

/** Valeur d'une variable d'environnement, ou la valeur par défaut si elle est absente ou vide. */
function legacy_env(string $nom, string $defaut = ''): string
{
    $valeur = getenv($nom);
    return ($valeur === false || $valeur === '') ? $defaut : $valeur;
}

/** Secret lu dans le fichier désigné par <NOM>_FILE, sinon dans <NOM>, sinon chaîne vide. */
function legacy_secret(string $nom): string
{
    $fichier = legacy_env($nom . '_FILE');
    if ($fichier !== '' && is_readable($fichier)) {
        return rtrim((string) file_get_contents($fichier), "\r\n");
    }
    return legacy_env($nom);
}

define('LEGACY_RDV_VERSION', legacy_env('LEGACY_RDV_VERSION', '2.4.0'));

// Connexion MariaDB (facteur IV) : service attaché, désigné par son nom.
define('DB_HOST', legacy_env('LEGACY_RDV_DB_HOST', 'localhost'));
define('DB_PORT', (int) legacy_env('LEGACY_RDV_DB_PORT', '3306'));
define('DB_NAME', legacy_env('LEGACY_RDV_DB_NAME', 'legacy_rdv'));
define('DB_USER', legacy_env('LEGACY_RDV_DB_USER', 'legacy_rdv'));
define('DB_PASS', legacy_secret('LEGACY_RDV_DB_PASS'));

// Sessions (facteur VI) : « base » dès qu'il y a plus d'une instance.
define('SESSIONS', legacy_env('LEGACY_RDV_SESSIONS', 'fichiers'));
define('SESSION_DUREE', (int) legacy_env('LEGACY_RDV_SESSION_DUREE', '1440'));

// Pièces jointes : répertoire désigné par la configuration (volume partagé RWX sur Kubernetes).
define('UPLOAD_DIR', rtrim(legacy_env('LEGACY_RDV_UPLOAD_DIR', __DIR__ . '/uploads'), '/') . '/');
define('UPLOAD_MAX', 5 * 1024 * 1024); // 5 Mo (règle métier, pas de la configuration)
define('UPLOAD_TYPES', ['application/pdf' => 'pdf', 'image/jpeg' => 'jpg', 'image/png' => 'png']);

// Journal applicatif (facteur XI) : php://stderr dans le conteneur.
define('LOG_FILE', legacy_env('LEGACY_RDV_LOG_FILE', '/var/log/legacy-rdv/app.log'));

// Rétention des pièces jointes (cron/purge-uploads.php).
define('RETENTION_JOURS', (int) legacy_env('LEGACY_RDV_RETENTION_JOURS', '365'));

// Fuseau des rendez-vous : celui des cabinets. Les DATETIME de la base sont des heures de Paris SANS
// fuseau : PHP calcule « maintenant » dans ce fuseau et le passe aux requêtes (index.php), il ne
// dépend donc plus du fuseau du serveur MariaDB.
date_default_timezone_set(legacy_env('LEGACY_RDV_FUSEAU', 'Europe/Paris'));

// Affichage des erreurs : activé par défaut (comportement historique), désactivé dans l'image.
ini_set('display_errors', legacy_env('LEGACY_RDV_AFFICHER_ERREURS', '1'));
error_reporting(E_ALL);
