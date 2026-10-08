<?php
/*
 * Configuration de Legacy-RDV.
 *
 * ⚠️ ANTI-PATRON VOLONTAIRE, hérité d'InfoGér : identifiants de base de données
 * écrits en dur dans le code source, versionnés avec lui, identiques sur tous
 * les environnements. Ne reproduis jamais ça dans une nouvelle application.
 * Ces valeurs sont fictives (lab de formation) ; la migration (modules 12 et F4)
 * consiste justement à les sortir d'ici (variables d'environnement, Secret).
 */

// Connexion MariaDB : la base tourne sur la même VM (socket local).
define('DB_HOST', 'localhost');
define('DB_NAME', 'legacy_rdv');
define('DB_USER', 'legacy_rdv');
define('DB_PASS', 'InfoGer2014!'); // mot de passe fictif, jamais changé depuis 2014

// Stockage des pièces jointes : répertoire local du serveur web.
define('UPLOAD_DIR', __DIR__ . '/uploads/');
define('UPLOAD_MAX', 5 * 1024 * 1024); // 5 Mo
define('UPLOAD_TYPES', ['application/pdf' => 'pdf', 'image/jpeg' => 'jpg', 'image/png' => 'png']);

// Journal applicatif : fichier local, rotation confiée à logrotate sur la VM.
define('LOG_FILE', '/var/log/legacy-rdv/app.log');

// Rétention des pièces jointes (script cron/purge-uploads.php).
define('RETENTION_JOURS', 365);

// Fuseau imposé ici plutôt que dans l'environnement.
date_default_timezone_set('Europe/Paris');

// Affichage des erreurs à l'écran : laissé « temporairement » par InfoGér en 2019.
ini_set('display_errors', '1');
error_reporting(E_ALL);
