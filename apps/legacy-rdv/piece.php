<?php
/* Téléchargement de la pièce jointe d'un rendez-vous (lue sur le disque local). */
require __DIR__ . '/inc/commun.php';

$id = (int) ($_GET['id'] ?? 0);
$req = db()->prepare('SELECT piece_jointe FROM rendez_vous WHERE id = ?');
$req->bind_param('i', $id);
$req->execute();
$nom = $req->get_result()->fetch_row()[0] ?? null;

// basename() : le nom vient de la base, mais on ne sort jamais de uploads/.
$chemin = $nom ? UPLOAD_DIR . basename($nom) : null;
if ($chemin === null || !is_file($chemin)) {
    // Fichier absent : la base référence un fichier resté sur un autre serveur,
    // ou perdu lors d'une réinstallation (cas réel chez InfoGér en 2020).
    journal('ERREUR', "pièce jointe introuvable pour le rendez-vous $id");
    http_response_code(404);
    exit('Pièce jointe introuvable.');
}

header('Content-Type: ' . (mime_content_type($chemin) ?: 'application/octet-stream'));
header('Content-Length: ' . filesize($chemin));
header('Content-Disposition: attachment; filename="' . basename($chemin) . '"');
header('X-Content-Type-Options: nosniff');
readfile($chemin);
