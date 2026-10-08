<?php
/* Liste des rendez-vous à venir. */
require __DIR__ . '/inc/commun.php';

$praticien = $_GET['praticien'] ?? '';
if ($praticien !== '') {
    $req = db()->prepare(
        'SELECT id, patient, praticien, date_rdv, motif, piece_jointe FROM rendez_vous
         WHERE date_rdv >= NOW() AND praticien = ? ORDER BY date_rdv LIMIT 200'
    );
    $req->bind_param('s', $praticien);
} else {
    $req = db()->prepare(
        'SELECT id, patient, praticien, date_rdv, motif, piece_jointe FROM rendez_vous
         WHERE date_rdv >= NOW() ORDER BY date_rdv LIMIT 200'
    );
}
$req->execute();
$rdvs = $req->get_result()->fetch_all(MYSQLI_ASSOC);

entete('Rendez-vous à venir');
?>
<form method="get">
  <label>Praticien <input name="praticien" value="<?= h($praticien) ?>"></label>
  <button>Filtrer</button>
</form>
<?php if (!$rdvs) { ?>
<p>Aucun rendez-vous à venir.</p>
<?php } else { ?>
<table>
  <tr><th>Date</th><th>Patient</th><th>Praticien</th><th>Motif</th><th>Pièce jointe</th></tr>
  <?php foreach ($rdvs as $r) { ?>
  <tr>
    <td><?= h(date('d/m/Y H:i', strtotime($r['date_rdv']))) ?></td>
    <td><?= h($r['patient']) ?></td>
    <td><?= h($r['praticien']) ?></td>
    <td><?= h($r['motif']) ?></td>
    <td><?php if ($r['piece_jointe']) { ?><a href="piece.php?id=<?= (int) $r['id'] ?>">voir</a><?php } ?></td>
  </tr>
  <?php } ?>
</table>
<?php } ?>
<?php
pied();
