<?php
/*
 * Fonctions communes à toutes les pages : session, base, journal, gabarit.
 * Inclus en tête de chaque page par « require __DIR__ . '/inc/commun.php'; ».
 */

require_once __DIR__ . '/../config.php';

// Sessions PHP « fichiers » (session.save_handler = files) : elles sont écrites
// sur le disque de CE serveur (/var/lib/php/sessions sous Debian). Une seconde
// instance derrière un répartiteur ne les voit pas.
session_name('LEGACYRDV');
session_start();

/** Écrit une ligne dans le journal applicatif (fichier local). */
function journal(string $niveau, string $message): void
{
    $ligne = sprintf("[%s] %s %s %s\n", date('Y-m-d H:i:s'), $niveau, $_SERVER['REMOTE_ADDR'] ?? 'cli', $message);
    // Si le répertoire n'existe pas ou n'est pas accessible en écriture, le
    // message est perdu sans bruit (le @ masque l'avertissement) : typique.
    @file_put_contents(LOG_FILE, $ligne, FILE_APPEND | LOCK_EX);
}

/** Connexion MariaDB unique pour la requête en cours. */
function db(): mysqli
{
    static $cnx = null;
    if ($cnx === null) {
        mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
        try {
            $cnx = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);
            $cnx->set_charset('utf8mb4');
        } catch (mysqli_sql_exception $e) {
            journal('ERREUR', 'connexion MariaDB impossible : ' . $e->getMessage());
            http_response_code(500);
            exit('Service momentanément indisponible.');
        }
    }
    return $cnx;
}

/** Échappement HTML. */
function h(?string $texte): string
{
    return htmlspecialchars($texte ?? '', ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

/** Jeton anti-CSRF stocké… dans la session (donc sur le disque local). */
function jeton_csrf(): string
{
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(16));
    }
    return $_SESSION['csrf'];
}

function verifier_csrf(): bool
{
    return isset($_POST['csrf'], $_SESSION['csrf']) && hash_equals($_SESSION['csrf'], (string) $_POST['csrf']);
}

/** Message affiché une fois, à la page suivante. */
function flash(?string $message = null): ?string
{
    if ($message !== null) {
        $_SESSION['flash'] = $message;
        return null;
    }
    $m = $_SESSION['flash'] ?? null;
    unset($_SESSION['flash']);
    return $m;
}

function entete(string $titre): void
{
    ?><!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<title><?= h($titre) ?> - MédiSphère RDV</title>
<style>
body { font-family: sans-serif; margin: 2em; color: #222; }
table { border-collapse: collapse; } td, th { border: 1px solid #999; padding: .3em .6em; }
.flash { background: #e6f4e6; padding: .5em; border: 1px solid #7a7; }
.erreur { background: #fbe9e9; padding: .5em; border: 1px solid #c77; }
</style>
</head>
<body>
<h1><?= h($titre) ?></h1>
<p><a href="index.php">Rendez-vous</a> | <a href="prendre.php">Prendre rendez-vous</a></p>
<?php if ($m = flash()) { ?><p class="flash"><?= h($m) ?></p><?php } ?>
<?php
}

function pied(): void
{
    ?>
<hr><small>MédiSphère - prise de rendez-vous (version 2.3.1, InfoGér 2014-2021)</small>
</body>
</html>
<?php
}
