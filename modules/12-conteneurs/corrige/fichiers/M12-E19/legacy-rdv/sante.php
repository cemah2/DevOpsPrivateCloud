<?php
/*
 * Sonde de vivacité de Legacy-RDV (M12-E19) : répond « ok » si Apache et PHP fonctionnent,
 * SANS ouvrir de session ni contacter MariaDB (une panne de la base ne doit pas faire
 * redémarrer le serveur web ; README de l'application, point 8). Ajout, pas modification.
 */
header('Content-Type: text/plain; charset=utf-8');
header('Cache-Control: no-store');
echo "ok\n";
