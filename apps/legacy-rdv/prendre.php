<?php
/* Prise de rendez-vous, avec pièce jointe facultative (ordonnance, courrier). */
require __DIR__ . '/inc/commun.php';

$erreurs = [];
$saisie = ['patient' => '', 'praticien' => $_SESSION['dernier_praticien'] ?? '', 'date_rdv' => '', 'motif' => ''];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    foreach (array_keys($saisie) as $champ) {
        $saisie[$champ] = trim((string) ($_POST[$champ] ?? ''));
    }

    // Le jeton est en session : si le formulaire a été servi par un autre
    // serveur que celui qui reçoit le POST, il est introuvable ici.
    if (!verifier_csrf()) {
        $erreurs[] = 'Votre session a expiré, merci de recommencer.';
        journal('ALERTE', 'jeton CSRF invalide ou session absente');
    }
    if ($saisie['patient'] === '' || mb_strlen($saisie['patient']) > 200) {
        $erreurs[] = 'Nom du patient obligatoire (200 caractères au plus).';
    }
    if ($saisie['praticien'] === '' || mb_strlen($saisie['praticien']) > 100) {
        $erreurs[] = 'Praticien obligatoire.';
    }
    // Date « locale » sans fuseau : stockée telle quelle en DATETIME.
    $date = DateTime::createFromFormat('Y-m-d\TH:i', $saisie['date_rdv']);
    if ($date === false) {
        $erreurs[] = 'Date invalide.';
    }

    // Pièce jointe : écrite dans le répertoire uploads/ du serveur web.
    $piece = null;
    if (!$erreurs && isset($_FILES['piece']) && $_FILES['piece']['error'] !== UPLOAD_ERR_NO_FILE) {
        $f = $_FILES['piece'];
        $type = $f['error'] === UPLOAD_ERR_OK ? mime_content_type($f['tmp_name']) : false;
        if ($f['error'] !== UPLOAD_ERR_OK || $f['size'] > UPLOAD_MAX) {
            $erreurs[] = 'Pièce jointe refusée (5 Mo au plus).';
        } elseif (!isset(UPLOAD_TYPES[$type])) {
            $erreurs[] = 'Type de fichier refusé (PDF, JPEG ou PNG).';
        } else {
            $piece = date('Ymd') . '_' . bin2hex(random_bytes(8)) . '.' . UPLOAD_TYPES[$type];
            if (!move_uploaded_file($f['tmp_name'], UPLOAD_DIR . $piece)) {
                $erreurs[] = 'Impossible d\'enregistrer la pièce jointe.';
                journal('ERREUR', 'écriture impossible dans ' . UPLOAD_DIR);
                $piece = null;
            }
        }
    }

    if (!$erreurs) {
        $req = db()->prepare(
            'INSERT INTO rendez_vous (patient, praticien, date_rdv, motif, piece_jointe) VALUES (?, ?, ?, ?, ?)'
        );
        $quand = $date->format('Y-m-d H:i:00');
        $req->bind_param('sssss', $saisie['patient'], $saisie['praticien'], $quand, $saisie['motif'], $piece);
        try {
            $req->execute();
        } catch (mysqli_sql_exception $e) {
            if ($e->getCode() === 1062) { // clé unique (praticien, date_rdv)
                $erreurs[] = 'Ce créneau est déjà pris.';
            } else {
                throw $e;
            }
        }
        if (!$erreurs) {
            $_SESSION['dernier_praticien'] = $saisie['praticien'];
            journal('INFO', 'rendez-vous ' . db()->insert_id . ' créé pour ' . $saisie['praticien']);
            flash('Rendez-vous enregistré.');
            header('Location: index.php');
            exit;
        }
    }
}

entete('Prendre rendez-vous');
foreach ($erreurs as $e) {
    echo '<p class="erreur">' . h($e) . "</p>\n";
}
?>
<form method="post" enctype="multipart/form-data">
  <input type="hidden" name="csrf" value="<?= h(jeton_csrf()) ?>">
  <p><label>Patient <input name="patient" required maxlength="200" value="<?= h($saisie['patient']) ?>"></label></p>
  <p><label>Praticien <input name="praticien" required maxlength="100" value="<?= h($saisie['praticien']) ?>"></label></p>
  <p><label>Date et heure <input type="datetime-local" name="date_rdv" required value="<?= h($saisie['date_rdv']) ?>"></label></p>
  <p><label>Motif <input name="motif" maxlength="500" value="<?= h($saisie['motif']) ?>"></label></p>
  <p><label>Pièce jointe (PDF, JPEG, PNG, 5 Mo) <input type="file" name="piece"></label></p>
  <p><button>Enregistrer</button></p>
</form>
<?php
pied();
