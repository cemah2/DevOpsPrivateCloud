// plateforme/resilience — charge/lib/commun.js (M29-E05, PLAT-3005 ; repris en M29-E06)
//
// Ce que TOUS les scénarios de charge de MédiAgenda partagent :
//   1. le garde-fou de cible : la production n'est JAMAIS visée (liste d'autorisation, pas de liste
//      d'interdiction : une adresse inconnue est refusée, y compris une faute de frappe) ;
//   2. des données FACTICES : praticiens « dr-k6-<n> » qui n'existent pas, patients « Patient
//      Charge <n> », motif marqué, dates loin dans le futur. Aucune donnée réelle, jamais.
//
// Code d'initialisation : exécuté une fois par VU au chargement (et par « k6 inspect »).

// Cibles autorisées : recette (et dev) de MédiAgenda, et un MédiAgenda local pour essayer le script.
const CIBLES_AUTORISEES = [
  /^https:\/\/mediagenda-recette\.apps\.par1\.medisphere\.internal$/,
  /^https:\/\/mediagenda-dev\.apps\.par1\.medisphere\.internal$/,
  /^http:\/\/127\.0\.0\.1:[0-9]+$/,
];

export const BASE_URL = (__ENV.BASE_URL || 'https://mediagenda-recette.apps.par1.medisphere.internal').replace(/\/+$/, '');

if (!CIBLES_AUTORISEES.some((motif) => motif.test(BASE_URL))) {
  // Une exception dans le code d'initialisation arrête k6 avant la première requête.
  throw new Error(`cible refusée : ${BASE_URL} (seules la recette, la dev et 127.0.0.1 sont autorisées)`);
}

export const MOTIF = 'test de charge k6 (M29)';
export const PRATICIEN_PREFIXE = 'dr-k6-';
export const FUSEAU = '+01:00'; // les dates de novembre à mars sont en heure d'hiver à Paris

// Premier jour utilisé : J+60 par défaut (jamais un jour où de vrais rendez-vous de recette existent).
const DECALAGE_JOURS = parseInt(__ENV.DECALAGE_JOURS || '60', 10);

function jourDecale(n) {
  const d = new Date(Date.now() + (DECALAGE_JOURS + n) * 86400000);
  return d.toISOString().slice(0, 10); // AAAA-MM-JJ
}

// Les 16 créneaux de 30 min d'une journée (8 h-12 h, 14 h-18 h, MédiAgenda README).
const HEURES = ['08:00', '08:30', '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
  '14:00', '14:30', '15:00', '15:30', '16:00', '16:30', '17:00', '17:30'];

// Créneau propre à un couple (VU, itération) : un praticien par VU, 16 créneaux par jour, puis le
// jour suivant. Deux VUs ne réservent donc jamais le même créneau (pas de 409 fabriqué par le test).
export function creneauUnique(vu, iteration) {
  return {
    praticien: `${PRATICIEN_PREFIXE}${vu}`,
    debut: `${jourDecale(Math.floor(iteration / HEURES.length))}T${HEURES[iteration % HEURES.length]}:00${FUSEAU}`,
  };
}

// Corps de création : données factices, reconnaissables (nettoyage, lecture des journaux).
export function corpsRendezVous(vu, iteration) {
  const c = creneauUnique(vu, iteration);
  return JSON.stringify({
    patient: `Patient Charge ${vu}-${iteration}`,
    praticien: c.praticien,
    debut: c.debut,
    duree_minutes: 30,
    motif: MOTIF,
  });
}

// Jour et praticien de lecture des créneaux : « variete » couples différents (effet du cache Valkey,
// M29-E06 : 1 couple = presque tout en cache ; 500 couples = presque tout calculé en base).
export function lectureAleatoire(variete) {
  const n = Math.floor(Math.random() * variete);
  return { praticien: `${PRATICIEN_PREFIXE}${n % 50}`, jour: jourDecale(Math.floor(n / 50)) };
}

export const ENTETES_JSON = { headers: { 'Content-Type': 'application/json' } };
