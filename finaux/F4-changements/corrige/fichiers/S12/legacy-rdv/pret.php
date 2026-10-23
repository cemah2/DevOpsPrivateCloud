<?php
/*
 * Sonde de DISPONIBILITÉ de Legacy-RDV (F4-S12) : 200 si la base répond, 503 sinon. Ajout.
 * N'ouvre PAS de session (n'inclut pas inc/commun.php) : la sonde de Kubernetes passe toutes les
 * 10 s, elle ne doit ni créer de lignes dans « sessions » ni dépendre d'elles.
 * Rend aussi le nombre de rendez-vous : aucune donnée personnelle, utile aux contrôles de la bascule
 * (F4-S13). Jamais publié hors du lab : les répartiteurs refusent /pret.php sur rdv.par1… (F4-S10).
 * La vivacité, elle, reste sante.php (M12-E19) : elle ne touche pas la base.
 */
require __DIR__ . '/config.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
try {
    $db = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME, DB_PORT);
    $n = (int) $db->query('SELECT COUNT(*) FROM rendez_vous')->fetch_row()[0];
    echo json_encode(['pret' => true, 'version' => LEGACY_RDV_VERSION, 'rendez_vous' => $n]), "\n";
} catch (mysqli_sql_exception $e) {
    http_response_code(503);
    @file_put_contents(LOG_FILE, sprintf("[%s] ERREUR sonde pret : %s\n", date('Y-m-d H:i:s'), $e->getMessage()), FILE_APPEND);
    echo json_encode(['pret' => false]), "\n";
}
