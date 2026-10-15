<?php
/*
 * Configuration de Legacy-RDV — version conteneurisable (M12-E19, ticket DEV-1319).
 *
 * Toutes les valeurs viennent de l'environnement (facteur III). Les valeurs par défaut sont
 * celles de l'installation d'InfoGér, pour que l'application se comporte EXACTEMENT comme avant
 * quand rien n'est défini, avec une exception volontaire : le mot de passe de la base n'a plus
 * de valeur par défaut. Il vient de LEGACY_RDV_DB_PASS_FILE (fichier de secret, recommandé) ou de
 * LEGACY_RDV_DB_PASS ; sans l'un ni l'autre, la connexion échoue avec un message clair.
 * L'ancien mot de passe ne figure plus dans le code (il reste dans l'historique Git : il a été
 * changé sur la base conteneurisée, voir docs/conteneurs/legacy-rdv-12-facteurs.md).
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

// Connexion MariaDB (facteur IV : la base est un service attaché, désigné par son nom).
define('DB_HOST', legacy_env('LEGACY_RDV_DB_HOST', 'localhost'));
define('DB_NAME', legacy_env('LEGACY_RDV_DB_NAME', 'legacy_rdv'));
define('DB_USER', legacy_env('LEGACY_RDV_DB_USER', 'legacy_rdv'));
define('DB_PASS', legacy_secret('LEGACY_RDV_DB_PASS'));

// Pièces jointes : toujours un répertoire local, mais désigné par la configuration
// (dans le conteneur : un volume ; plus tard : un stockage partagé ou objet, F4).
define('UPLOAD_DIR', rtrim(legacy_env('LEGACY_RDV_UPLOAD_DIR', __DIR__ . '/uploads'), '/') . '/');
define('UPLOAD_MAX', 5 * 1024 * 1024); // 5 Mo (règle métier, pas de la configuration)
define('UPLOAD_TYPES', ['application/pdf' => 'pdf', 'image/jpeg' => 'jpg', 'image/png' => 'png']);

// Journal applicatif (facteur XI) : un fichier sur la VM, la sortie d'erreur dans le conteneur
// (LEGACY_RDV_LOG_FILE=php://stderr ; « /dev/stderr » échoue sans bruit : PHP résout le lien
// /proc/self/fd/2 vers « pipe:[…] », qui n'existe pas comme fichier, voir le corrigé).
define('LOG_FILE', legacy_env('LEGACY_RDV_LOG_FILE', '/var/log/legacy-rdv/app.log'));

// Rétention des pièces jointes (script cron/purge-uploads.php).
define('RETENTION_JOURS', (int) legacy_env('LEGACY_RDV_RETENTION_JOURS', '365'));

// Fuseau : celui de l'environnement s'il est donné, sinon Paris comme avant.
date_default_timezone_set(legacy_env('LEGACY_RDV_FUSEAU', 'Europe/Paris'));

// Affichage des erreurs : activé par défaut (comportement historique), désactivé dans l'image.
ini_set('display_errors', legacy_env('LEGACY_RDV_AFFICHER_ERREURS', '1'));
error_reporting(E_ALL);
