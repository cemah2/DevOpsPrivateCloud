<?php
/*
 * Purge des pièces jointes de plus de RETENTION_JOURS jours.
 * Lancé chaque nuit par la crontab de la VM (fichier /etc/cron.d/legacy-rdv) :
 *
 *   30 3 * * * www-data /usr/bin/php /var/www/legacy-rdv/cron/purge-uploads.php
 *
 * Il supprime les fichiers du disque local SANS mettre à jour la base : la
 * colonne piece_jointe pointe ensuite vers un fichier absent (404 dans piece.php).
 */

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit('Script réservé à la ligne de commande.');
}

require __DIR__ . '/../config.php';

$limite = time() - RETENTION_JOURS * 86400;
$supprimes = 0;
foreach (glob(UPLOAD_DIR . '*') ?: [] as $fichier) {
    if (!in_array(pathinfo($fichier, PATHINFO_EXTENSION), UPLOAD_TYPES, true)) {
        continue; // ne touche qu'aux pièces jointes (pdf, jpg, png)
    }
    if (filemtime($fichier) < $limite && unlink($fichier)) {
        $supprimes++;
    }
}
@file_put_contents(
    LOG_FILE,
    sprintf("[%s] INFO cron purge : %d fichier(s) supprimé(s)\n", date('Y-m-d H:i:s'), $supprimes),
    FILE_APPEND | LOCK_EX
);
