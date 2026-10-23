// plateforme/resilience — charge/distribue/mediagenda-recette.js (M29-E14, PLAT-3014)
// Parcours d'un patient sur MédiAgenda (recette), pour k6-operator (TestRun distribué) comme pour un
// essai depuis adm01. Même parcours que M29-E06 : créneaux d'un jour, création d'un rendez-vous,
// lecture, annulation (on ne laisse rien derrière soi), liste.
//
// Paramètres (variables d'environnement, -e ou spec.runner.env) :
//   BASE_URL      défaut https://mediagenda-recette.apps.par1.medisphere.internal
//   TAUX_CIBLE    itérations par seconde visées (total, réparti entre exécuteurs), défaut 20
//   PALIER        durée du palier au taux cible, défaut 5m
// L'étiquette testid est posée par la ligne de commande (--tag testid=…) : elle accompagne chaque
// métrique jusque dans Prometheus.
//
// Seuils alignés sur le SLO de latence (250 ms à 95 %, M21) et de disponibilité. En distribué, chaque
// exécuteur évalue ses seuils sur SA part : le verdict global se lit dans Prometheus (RB-295).
//
// Fichier AUTONOME : le TestRun ne reçoit qu'un fichier (une clé de ConfigMap, sans sous-dossier), il ne
// peut donc pas importer ../lib/commun.js. Il en reprend les deux règles du module (M29-E05) : liste
// d'autorisation des cibles (jamais la prod) et données FACTICES (praticiens « dr-k6-<n> », patients
// « Patient Charge … », motif marqué, jours à partir de J+60). Toute évolution de commun.js se reporte ici.
import http from 'k6/http';
import { check, group } from 'k6';

const CIBLES_AUTORISEES = [
  /^https:\/\/mediagenda-recette\.apps\.par1\.medisphere\.internal$/,
  /^https:\/\/mediagenda-dev\.apps\.par1\.medisphere\.internal$/,
  /^http:\/\/127\.0\.0\.1:[0-9]+$/,
];
const BASE = (__ENV.BASE_URL || 'https://mediagenda-recette.apps.par1.medisphere.internal').replace(/\/+$/, '');
if (!CIBLES_AUTORISEES.some((motif) => motif.test(BASE))) {
  // Exception dans le code d'initialisation : l'initialiseur du TestRun échoue avant toute requête.
  throw new Error(`cible refusée : ${BASE} (seules la recette, la dev et 127.0.0.1 sont autorisées)`);
}
const TAUX = parseInt(__ENV.TAUX_CIBLE || '20', 10);
const PALIER = __ENV.PALIER || '5m';
const PRATICIEN_PREFIXE = 'dr-k6-';
const MOTIF = 'test de charge k6 (M29)';

export const options = {
  scenarios: {
    parcours: {
      executor: 'ramping-arrival-rate',
      startRate: 1,
      timeUnit: '1s',
      preAllocatedVUs: 20,
      maxVUs: 200,
      stages: [
        { target: TAUX, duration: '1m' },   // montée
        { target: TAUX, duration: PALIER }, // palier mesuré
        { target: 0, duration: '30s' },     // descente
      ],
    },
  },
  thresholds: {
    'http_req_duration{type:metier}': ['p(95)<250', 'p(99)<1000'],
    'http_req_failed{type:metier}': ['rate<0.01'],
    checks: ['rate>0.99'],
  },
  // Jauges envoyées par l'écriture distante (voir TestRun) ; ici pour le résumé local.
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

// Un créneau futur, entre J+60 et J+89 (jamais un jour où de vrais rendez-vous de recette existent,
// comme commun.js), parmi les 16 créneaux d'ouverture (8 h-12 h, 14 h-18 h) : les conflits (409) restent
// rares et sont acceptés comme une réponse normale. Fuseau fixe +01:00 (heure d'hiver), comme commun.js.
const HEURES = ['08:00', '08:30', '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
  '14:00', '14:30', '15:00', '15:30', '16:00', '16:30', '17:00', '17:30'];
function creneau() {
  const j = new Date(Date.now() + (60 + Math.floor(Math.random() * 30)) * 86400000);
  const jour = j.toISOString().slice(0, 10);
  return { jour, debut: `${jour}T${HEURES[Math.floor(Math.random() * HEURES.length)]}:00+01:00` };
}

const metier = (nom) => ({ tags: { type: 'metier', name: nom } });
// 409 (créneau déjà pris) est une réponse normale de l'API, pas une erreur.
const metier201ou409 = (nom) => ({ tags: { type: 'metier', name: nom }, responseCallback: http.expectedStatuses(201, 409) });

export default function () {
  const praticien = `${PRATICIEN_PREFIXE}${Math.floor(Math.random() * 50)}`;
  const { jour, debut } = creneau();

  group('creneaux', () => {
    const r = http.get(`${BASE}/api/v1/creneaux?date=${jour}&praticien=${praticien}`, metier('GET /api/v1/creneaux'));
    check(r, { 'créneaux : 200': (x) => x.status === 200 });
  });

  group('rendez-vous', () => {
    const corps = JSON.stringify({ patient: 'Patient Charge distribuée', praticien, debut, duree_minutes: 30, motif: MOTIF });
    const c = http.post(`${BASE}/api/v1/rendez-vous`, corps,
      Object.assign(metier201ou409('POST /api/v1/rendez-vous'), { headers: { 'Content-Type': 'application/json' } }));
    check(c, { 'création : 201 ou 409': (x) => x.status === 201 || x.status === 409 });
    if (c.status === 201) {
      const id = c.json('id');
      const g = http.get(`${BASE}/api/v1/rendez-vous/${id}`, metier('GET /api/v1/rendez-vous/{id}'));
      check(g, { 'lecture : 200': (x) => x.status === 200 });
      const d = http.del(`${BASE}/api/v1/rendez-vous/${id}`, null, metier('DELETE /api/v1/rendez-vous/{id}'));
      check(d, { 'annulation : 204': (x) => x.status === 204 });
    }
  });

  group('liste', () => {
    const l = http.get(`${BASE}/api/v1/rendez-vous?limite=20`, metier('GET /api/v1/rendez-vous'));
    check(l, { 'liste : 200': (x) => x.status === 200 });
  });
}
