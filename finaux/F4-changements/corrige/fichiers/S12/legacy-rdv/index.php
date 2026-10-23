<?php
/* Liste des rendez-vous à venir.
 * F4-S12 : « maintenant » est calculé par PHP dans le fuseau des cabinets (config.php) et passé à la
 * requête : la comparaison avec les DATETIME sans fuseau ne dépend plus du fuseau du serveur MariaDB. */
require __DIR__ . '/inc/commun.php';

$praticien = $_GET['praticien'] ?? '';
$maintenant = date('Y-m-d H:i:s');
if ($praticien !== '') {
    $req = db()->prepare(
        'SELECT id, patient, praticien, date_rdv, motif, piece_jointe FROM rendez_vous
         WHERE date_rdv >= ? AND praticien = ? ORDER BY date_rdv LIMIT 200'
    );
    $req->bind_param('ss', $maintenant, $praticien);
} else {
    $req = db()->prepare(
        'SELECT id, patient, praticien, date_rdv, motif, piece_jointe FROM rendez_vous
         WHERE date_rdv >= ? ORDER BY date_rdv LIMIT 200'
    );
    $req->bind_param('s', $maintenant);
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
