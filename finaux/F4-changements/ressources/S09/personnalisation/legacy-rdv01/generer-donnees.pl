#!/usr/bin/perl
# generer-donnees.pl — jeu de données FICTIF de Legacy-RDV « tel qu'en production chez InfoGér » (F4-S09).
#
# Lancé par fabriquer-export-vmware.sh sur pve01 (Perl est toujours présent sur Proxmox VE).
# Déterministe : même date de référence => mêmes lignes, mêmes noms de fichiers, mêmes contenus.
#
# Usage : generer-donnees.pl DOSSIER_SORTIE [AAAA-MM-JJ]   (date de référence, défaut : aujourd'hui)
# Produit dans DOSSIER_SORTIE :
#   donnees.sql        INSERT des rendez-vous (identifiants 101 et suivants, plus les témoins 9001-9003)
#   pieces/            pièces jointes encore présentes sur le disque (PDF fictifs)
#   pieces-dates.txt   « fichier<TAB>AAAA-MM-JJ HH:MM:SS » : date de modification à poser dans l'invité
#   temoins.csv        rendez-vous témoins (vérifications de F4-S13) : id;patient;praticien;date_rdv;affichage;piece
#   resume.txt         nombres de lignes, de références de pièces, de fichiers présents
#
# Aucune personne réelle : prénoms et noms tirés de listes courantes, combinés au hasard.
use strict;
use warnings;
use utf8;
use POSIX qw(strftime mktime floor);

my ($sortie, $ref) = @ARGV;
die "usage : $0 DOSSIER_SORTIE [AAAA-MM-JJ]\n" unless defined $sortie;
$ref //= strftime('%Y-%m-%d', localtime);
die "date de référence invalide : $ref\n" unless $ref =~ /^(\d{4})-(\d{2})-(\d{2})$/;
my ($ra, $rm, $rj) = ($1, $2, $3);

$ENV{TZ} = 'Europe/Paris';
POSIX::tzset();
# Midi le jour de référence : aucun changement d'heure ne déplace le jour.
my $t_ref = mktime(0, 0, 12, $rj, $rm - 1, $ra - 1900, 0, 0, -1);
srand(2014);    # graine fixe : fabrication reproductible
binmode(STDOUT, ":utf8");

mkdir $sortie unless -d $sortie;
mkdir "$sortie/pieces" unless -d "$sortie/pieces";

my @prenoms = qw(Camille Louise Léa Manon Chloé Inès Jade Emma Alice Lina Hugo Lucas Louis Gabriel Arthur
  Jules Raphaël Adam Paul Nathan Martine Monique Michel Bernard Christine Philippe Sylvie Patrick
  Nathalie Isabelle Françoise Jean Marie Pierre Anne Thierry Céline Sandrine Yves Odile);
my @noms = qw(Martin Bernard Thomas Petit Robert Richard Durand Dubois Moreau Laurent Simon Michel
  Lefebvre Leroy Roux David Bertrand Morel Fournier Girard Bonnet Dupont Lambert Fontaine Rousseau
  Vincent Muller Lefèvre Faure André Mercier Blanc Guérin Boyer Garnier Chevalier François Legrand
  Gauthier Garcia Perrin Robin Clément Morin Nicolas Henry Roussel Mathieu Gautier Masson);
my @praticiens = qw(dr-morel dr-benali dr-laurent dr-petit dr-roussel dr-garnier dr-vidal dr-martin);
my @motifs = ('Consultation de suivi', "Renouvellement d'ordonnance", "Résultats d'analyses",
  'Première consultation', 'Certificat de sport', 'Vaccination', 'Contrôle tension',
  'Suivi diabète', 'Douleurs dorsales', 'Bilan annuel', 'Téléconsultation impossible', '');

sub q_sql { my $s = shift; $s =~ s/\\/\\\\/g; $s =~ s/'/''/g; return "'$s'"; }
sub dt { return strftime('%Y-%m-%d %H:%M:%S', localtime(shift)); }
sub hex16 { return join('', map { sprintf('%x', int(rand(16))) } 1 .. 16); }

# PDF minimal mais bien formé (table xref aux bons décalages).
sub pdf {
  my ($texte) = @_;
  $texte =~ s/([\\()])/\\$1/g;
  my $flux = "BT /F1 12 Tf 72 720 Td ($texte) Tj ET";
  my @obj = (
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    "<< /Length " . length($flux) . " >>\nstream\n$flux\nendstream",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
  );
  my $out = "%PDF-1.4\n";
  my @pos;
  for my $i (0 .. $#obj) {
    push @pos, length($out);
    $out .= ($i + 1) . " 0 obj\n$obj[$i]\nendobj\n";
  }
  my $xref = length($out);
  $out .= "xref\n0 " . (@obj + 1) . "\n0000000000 65535 f \n";
  $out .= sprintf("%010d 00000 n \n", $_) for @pos;
  $out .= "trailer\n<< /Size " . (@obj + 1) . " /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n";
  return $out;
}

open(my $sql, '>', "$sortie/donnees.sql") or die "$sortie/donnees.sql : $!\n";
open(my $dates, '>', "$sortie/pieces-dates.txt") or die "$!\n";
binmode($sql, ':utf8');
print $sql "-- Données de production simulées de Legacy-RDV (F4-S09), référence $ref. FICTIVES.\n";
print $sql "SET NAMES utf8mb4;\nSTART TRANSACTION;\n";

my %pris;    # (praticien, date) déjà utilisé : clé unique rendez_vous_praticien_date
my ($n, $nb_ref, $nb_fichiers, $nb_purges) = (0, 0, 0, 0);
my $id = 101;
my @lot;

sub ecrire_pieces {
  my ($nom, $t_cree, $texte, $forcer) = @_;
  # Pièce de plus d'un an : déjà purgée par la tâche nocturne d'InfoGér (fichier absent, référence
  # restée en base : défaut connu, README de l'application, point 7).
  if (!$forcer && $t_cree < $t_ref - 365 * 86400) { $nb_purges++; return; }
  open(my $f, '>:raw', "$sortie/pieces/$nom") or die "$nom : $!\n";
  print $f pdf($texte);
  close $f;
  print $dates "$nom\t" . dt($t_cree) . "\n";
  $nb_fichiers++;
}

sub vider_lot {
  return unless @lot;
  print $sql "INSERT INTO rendez_vous (id, patient, praticien, date_rdv, motif, piece_jointe, cree_le) VALUES\n  "
    . join(",\n  ", @lot) . ";\n";
  @lot = ();
}

while ($n < 2600) {
  my $jour = int(rand(1180)) - 1000;                      # de J-1000 à J+179
  my $t_jour = $t_ref + $jour * 86400;
  my @l = localtime($t_jour);
  next if $l[6] == 0;                                       # pas de rendez-vous le dimanche
  my $quart = int(rand(44));                                # 08:00 à 18:45, par quarts d'heure
  my $t_rdv = mktime(0, ($quart % 4) * 15, 8 + int($quart / 4), $l[3], $l[4], $l[5], 0, 0, -1);
  my $prat = $praticiens[int(rand(@praticiens))];
  my $cle = "$prat|" . dt($t_rdv);
  next if $pris{$cle}++;
  my $patient = $prenoms[int(rand(@prenoms))] . ' ' . $noms[int(rand(@noms))];
  my $motif = $motifs[int(rand(@motifs))];
  # Création : entre 1 et 40 jours avant le rendez-vous, jamais après la date de référence.
  my $t_cree = $t_rdv - (1 + int(rand(40))) * 86400 - int(rand(36000));
  $t_cree = $t_ref - int(rand(30 * 86400)) if $t_cree > $t_ref;
  my $piece = 'NULL';
  if (rand() < 0.12) {
    my $nom = strftime('%Y%m%d', localtime($t_cree)) . '_' . hex16() . '.pdf';
    $piece = q_sql($nom);
    $nb_ref++;
    ecrire_pieces($nom, $t_cree, "Piece jointe fictive - rendez-vous $id - $prat", 0);
  }
  push @lot, "($id, " . q_sql($patient) . ", '$prat', '" . dt($t_rdv) . "', "
    . ($motif eq '' ? 'NULL' : q_sql($motif)) . ", $piece, '" . dt($t_cree) . "')";
  vider_lot() if @lot >= 200;
  $id++;
  $n++;
}
vider_lot();

# --- Témoins (F4-S13) : heures de Paris, une en heure d'hiver, une en heure d'été, une avec pièce -----
# Loin dans le futur (plus d'un an) : ils restent « à venir » quelle que soit la date de la bascule.
my $t_min = $t_ref + 400 * 86400;
sub prochain {    # prochain JJ/MM à HH:MM strictement après $t_min
  my ($jj, $mm, $hh, $mi) = @_;
  my $a = (localtime($t_min))[5] + 1900;
  for my $ann ($a, $a + 1) {
    my $t = mktime(0, $mi, $hh, $jj, $mm - 1, $ann - 1900, 0, 0, -1);
    return $t if $t > $t_min;
  }
  die "date témoin introuvable\n";
}
my $t_pj = $t_ref + 500 * 86400;
my @lpj = localtime($t_pj);
my @temoins = (
  [9001, 'Témoin Hiver', prochain(15, 1, 9, 0), undef],
  [9002, 'Témoin Été', prochain(15, 7, 14, 30), undef],
  [9003, 'Témoin Pièce-Jointe', mktime(0, 15, 10, $lpj[3], $lpj[4], $lpj[5], 0, 0, -1),
    strftime('%Y%m%d', localtime($t_ref - 10 * 86400)) . '_temoin0000000003.pdf'],
);
open(my $tm, '>:utf8', "$sortie/temoins.csv") or die "$!\n";
print $tm "id;patient;praticien;date_rdv;affichage;piece\n";
for my $w (@temoins) {
  my ($wid, $pat, $t, $pj) = @$w;
  my $t_cree = $t_ref - 10 * 86400;
  if ($pj) {
    ecrire_pieces($pj, $t_cree, "Piece jointe temoin - rendez-vous $wid - ne pas supprimer", 1);
    $nb_ref++;
  }
  push @lot, "($wid, " . q_sql($pat) . ", 'dr-temoin', '" . dt($t) . "', 'Témoin de migration (F4)', "
    . ($pj ? q_sql($pj) : 'NULL') . ", '" . dt($t_cree) . "')";
  print $tm join(';', $wid, $pat, 'dr-temoin', dt($t), strftime('%d/%m/%Y %H:%M', localtime($t)), $pj // '') . "\n";
  $n++;
}
vider_lot();
print $sql "COMMIT;\n";
close $sql;
close $dates;
close $tm;

open(my $r, '>', "$sortie/resume.txt") or die "$!\n";
# + 3 lignes d'exemple de schema.sql (identifiants 1 à 3)
printf $r "rendez_vous=%d\nreferences_pieces=%d\nfichiers_presents=%d\nfichiers_deja_purges=%d\n",
  $n + 3, $nb_ref, $nb_fichiers, $nb_purges;
close $r;
print "données générées : ", $n + 3, " rendez-vous, $nb_ref références de pièces, $nb_fichiers fichiers présents\n";
