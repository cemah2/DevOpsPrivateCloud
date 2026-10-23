<?php
/*
 * Purge des pièces jointes de plus de RETENTION_JOURS jours — version 2.4.0 (F4-S12, CHG-3412).
 * Lancée par le CronJob « legacy-rdv-purge » (plus de cron sur une machine), ligne de commande seulement.
 *
 * Corrige le défaut d'InfoGér (README de l'application, point 7) : la base est mise à jour EN MÊME
 * TEMPS que le disque. Pour chaque rendez-vous dont la pièce est plus vieille que la rétention :
 *   - le fichier est supprimé s'il existe ;
 *   - la colonne piece_jointe est remise à NULL (plus de lien « voir » qui mène à un 404).
 * Les références ORPHELINES héritées d'InfoGér (fichier déjà absent, rendez-vous plus vieux que la
 * rétention) sont remises à NULL de la même façon. Une référence récente dont le fichier manque n'est
 * PAS touchée : c'est une anomalie à examiner (journalisée), pas une purge.
 * Supprime aussi les sessions expirées (table « sessions »).
 * Options : --a-blanc (affiche, ne change rien).
 */

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    exit('Script réservé à la ligne de commande.');
}

require __DIR__ . '/../config.php';

$a_blanc = in_array('--a-blanc', $argv, true);
$journal = function (string $niveau, string $m): void {
    @file_put_contents(LOG_FILE, sprintf("[%s] %s cron purge : %s\n", date('Y-m-d H:i:s'), $niveau, $m), FILE_APPEND | LOCK_EX);
};

mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
$db = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME, DB_PORT);
$db->set_charset('utf8mb4');

$limite = date('Y-m-d H:i:s', time() - RETENTION_JOURS * 86400);
$req = $db->prepare('SELECT id, piece_jointe FROM rendez_vous WHERE piece_jointe IS NOT NULL AND cree_le < ?');
$req->bind_param('s', $limite);
$req->execute();
$lignes = $req->get_result()->fetch_all(MYSQLI_ASSOC);

$maj = $db->prepare('UPDATE rendez_vous SET piece_jointe = NULL WHERE id = ? AND piece_jointe = ?');
$fichiers = 0;
$references = 0;
foreach ($lignes as $l) {
    $chemin = UPLOAD_DIR . basename($l['piece_jointe']);
    if (is_file($chemin)) {
        if ($a_blanc) {
            $fichiers++;
        } elseif (unlink($chemin)) {
            $fichiers++;
        } else {
            $journal('ERREUR', "suppression impossible de $chemin (rendez-vous {$l['id']}) : base inchangée");
            continue;
        }
    }
    if (!$a_blanc) {
        $id = (int) $l['id'];
        $maj->bind_param('is', $id, $l['piece_jointe']);
        $maj->execute();
    }
    $references++;
}

// Références récentes sans fichier : anomalie, signalée seulement.
$req = $db->prepare('SELECT id, piece_jointe FROM rendez_vous WHERE piece_jointe IS NOT NULL AND cree_le >= ?');
$req->bind_param('s', $limite);
$req->execute();
foreach ($req->get_result()->fetch_all(MYSQLI_ASSOC) as $l) {
    if (!is_file(UPLOAD_DIR . basename($l['piece_jointe']))) {
        $journal('ALERTE', "pièce jointe récente absente pour le rendez-vous {$l['id']}");
    }
}

$sessions = 0;
if (!$a_blanc) {
    $req = $db->prepare('DELETE FROM sessions WHERE expire_le < ?');
    $maintenant = time();
    $req->bind_param('i', $maintenant);
    $req->execute();
    $sessions = $req->affected_rows;
}

$journal('INFO', sprintf('%s%d fichier(s) supprimé(s), %d référence(s) remise(s) à NULL, %d session(s) expirée(s)',
    $a_blanc ? '[à blanc] ' : '', $fichiers, $references, $sessions));
