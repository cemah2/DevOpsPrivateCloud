// plateforme/resilience — charge/parcours-recette.js (M29-E06, PLAT-3006)
//
// Charge réaliste de MédiAgenda en RECETTE, alignée sur les SLO (M21) :
//   - lecture des créneaux : taux d'arrivée CONSTANT (modèle ouvert), LECTURE_RPS par seconde ;
//   - réservation puis annulation : taux d'arrivée en RAMPE jusqu'à RESERVATION_RPS par seconde.
// Seuils = SLO : 95 % des requêtes en moins de 250 ms (métrique sous_250ms, même définition que le
// SLO « mediagenda-latence » : part des requêtes sous le seau le="0.25"), 99,5 % sans échec ; arrêt
// automatique si les erreurs dépassent 5 % (on ne casse pas la recette pour rien).
// Résumé JSON écrit par handleSummary dans charge/resultats/ (versionné : c'est la référence d'après).
// Chemin relatif au dossier COURANT : lancer k6 depuis la racine du dépôt (~/src/resilience).
//
// Variables (-e) : BASE_URL (recette par défaut), LECTURE_RPS (20), RESERVATION_RPS (5),
// DUREE (5m), VARIETE (200 couples praticien/jour lus : effet du cache Valkey), RESULTAT (fichier).
//   k6 run charge/parcours-recette.js
//   k6 run -e VARIETE=1 -e RESULTAT=charge/resultats/2026-10-23-cache-chaud.json charge/parcours-recette.js
import http from 'k6/http';
import { check, group } from 'k6';
import exec from 'k6/execution';
import { Rate } from 'k6/metrics';
import { BASE_URL, ENTETES_JSON, PRATICIEN_PREFIXE, corpsRendezVous, lectureAleatoire } from './lib/commun.js';

const LECTURE_RPS = parseInt(__ENV.LECTURE_RPS || '20', 10);
const RESERVATION_RPS = parseInt(__ENV.RESERVATION_RPS || '5', 10);
const DUREE = __ENV.DUREE || '5m';
const VARIETE = parseInt(__ENV.VARIETE || '200', 10);
const RESULTAT = __ENV.RESULTAT || `charge/resultats/${new Date().toISOString().slice(0, 10)}-parcours-recette.json`;

// Part des requêtes servies en moins de 250 ms : la définition du SLO, pas une moyenne.
const sous250 = new Rate('sous_250ms');

export const options = {
  scenarios: {
    lecture: {
      executor: 'constant-arrival-rate',
      exec: 'lecture',
      rate: LECTURE_RPS,
      timeUnit: '1s',
      duration: DUREE,
      // VUs nécessaires ≈ débit × durée d'une itération (20/s × 0,2 s = 4) ; marge pour les ralentissements.
      preAllocatedVUs: Math.max(5, LECTURE_RPS),
      maxVUs: LECTURE_RPS * 5,
      tags: { parcours: 'lecture' },
    },
    reservation: {
      executor: 'ramping-arrival-rate',
      exec: 'reservation',
      startRate: 1,
      timeUnit: '1s',
      stages: [
        { target: RESERVATION_RPS, duration: '1m' },
        { target: RESERVATION_RPS, duration: DUREE },
        { target: 0, duration: '30s' },
      ],
      preAllocatedVUs: Math.max(5, RESERVATION_RPS * 2),
      maxVUs: RESERVATION_RPS * 10,
      tags: { parcours: 'reservation' },
    },
  },
  thresholds: {
    // SLO de latence (M21) sur l'ensemble des requêtes du test.
    sous_250ms: ['rate>0.95'],
    // Mêmes exigences vues par parcours : le diagnostic dit QUEL parcours casse le SLO.
    'http_req_duration{parcours:lecture}': ['p(95)<250'],
    'http_req_duration{parcours:reservation}': ['p(95)<250', 'p(99)<1000'],
    // Disponibilité (M21, 99,5 %) ; au-delà de 5 % d'erreurs, k6 ARRÊTE le test (après 30 s).
    http_req_failed: [
      'rate<0.005',
      { threshold: 'rate<0.05', abortOnFail: true, delayAbortEval: '30s' },
    ],
    // Itérations non lancées faute de VU : le débit demandé n'a pas été tenu, le test ne prouve rien.
    dropped_iterations: ['count<10'],
    checks: ['rate>0.999'],
  },
  // Résumé : percentiles utiles au SLO.
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

function mesurer(reponse) {
  sous250.add(reponse.timings.duration < 250);
  return reponse;
}

// Une recette malade ne se teste pas en charge : on vérifie /pret avant de commencer.
export function setup() {
  const r = http.get(`${BASE_URL}/pret`, { tags: { name: 'GET /pret' } });
  if (r.status !== 200) {
    exec.test.abort(`MédiAgenda n'est pas prêt (${BASE_URL}/pret : HTTP ${r.status}) : test annulé`);
  }
  return { debut: new Date().toISOString() };
}

export function lecture() {
  group('lire les créneaux', () => {
    const { praticien, jour } = lectureAleatoire(VARIETE);
    const r = mesurer(http.get(`${BASE_URL}/api/v1/creneaux?date=${jour}&praticien=${praticien}`, {
      tags: { name: 'GET /api/v1/creneaux' },
    }));
    check(r, { 'créneaux : 200': (x) => x.status === 200 });
  });
}

export function reservation() {
  const vu = exec.vu.idInTest;
  const iteration = exec.vu.iterationInScenario;
  group('réserver puis annuler', () => {
    const cree = mesurer(http.post(`${BASE_URL}/api/v1/rendez-vous`, corpsRendezVous(vu, iteration), {
      ...ENTETES_JSON,
      tags: { name: 'POST /api/v1/rendez-vous' },
    }));
    if (!check(cree, { 'création : 201': (x) => x.status === 201 })) {
      return;
    }
    const id = cree.json('id');
    const annule = mesurer(http.del(`${BASE_URL}/api/v1/rendez-vous/${id}`, null, {
      tags: { name: 'DELETE /api/v1/rendez-vous/{id}' },
    }));
    check(annule, { 'annulation : 204': (x) => x.status === 204 });
  });
}

// Filet de sécurité : supprime les rendez-vous factices restés en base (test interrompu entre la
// création et l'annulation). Ne touche QUE les praticiens « dr-k6-… ».
export function teardown() {
  const r = http.get(`${BASE_URL}/api/v1/rendez-vous?limite=1000`, { tags: { name: 'GET /api/v1/rendez-vous' } });
  if (r.status !== 200) {
    return;
  }
  for (const rdv of r.json()) {
    if (rdv.praticien.startsWith(PRATICIEN_PREFIXE)) {
      http.del(`${BASE_URL}/api/v1/rendez-vous/${rdv.id}`, null, { tags: { name: 'DELETE /api/v1/rendez-vous/{id}' } });
    }
  }
}

// --- Résumé ---------------------------------------------------------------------------------------
function valeur(data, metrique, cle) {
  const m = data.metrics[metrique];
  return m && m.values[cle] !== undefined ? m.values[cle] : null;
}

function seuilsFranchis(data) {
  const franchis = [];
  for (const [nom, m] of Object.entries(data.metrics)) {
    for (const [expr, etat] of Object.entries(m.thresholds || {})) {
      if (!etat.ok) {
        franchis.push(`${nom} ${expr}`);
      }
    }
  }
  return franchis;
}

export function handleSummary(data) {
  const franchis = seuilsFranchis(data);
  const resume = {
    scenario: 'parcours-recette',
    cible: BASE_URL,
    date: new Date().toISOString(),
    parametres: { LECTURE_RPS, RESERVATION_RPS, DUREE, VARIETE },
    resultat: franchis.length === 0 ? 'seuils respectés' : 'SEUILS FRANCHIS',
    seuils_franchis: franchis,
    sous_250ms: valeur(data, 'sous_250ms', 'rate'),
    p95_ms: valeur(data, 'http_req_duration', 'p(95)'),
    p99_ms: valeur(data, 'http_req_duration', 'p(99)'),
    erreurs: valeur(data, 'http_req_failed', 'rate'),
    debit_rps: valeur(data, 'http_reqs', 'rate'),
    iterations_perdues: valeur(data, 'dropped_iterations', 'count') || 0,
    vus_max: valeur(data, 'vus_max', 'max'),
  };
  const texte = [
    `parcours-recette sur ${BASE_URL} : ${resume.resultat}`,
    `  sous 250 ms : ${(100 * (resume.sous_250ms || 0)).toFixed(2)} %   p95 : ${(resume.p95_ms || 0).toFixed(1)} ms   p99 : ${(resume.p99_ms || 0).toFixed(1)} ms`,
    `  erreurs : ${(100 * (resume.erreurs || 0)).toFixed(3)} %   débit : ${(resume.debit_rps || 0).toFixed(1)} req/s   itérations perdues : ${resume.iterations_perdues}`,
    ...franchis.map((f) => `  ✗ ${f}`),
    `  résumé complet : ${RESULTAT}`,
    '',
  ].join('\n');
  // Le JSON complet de k6 (data) contient tout ; on y ajoute notre résumé lisible en tête.
  return {
    stdout: texte,
    [RESULTAT]: JSON.stringify({ resume, k6: data }, null, 2),
  };
}
