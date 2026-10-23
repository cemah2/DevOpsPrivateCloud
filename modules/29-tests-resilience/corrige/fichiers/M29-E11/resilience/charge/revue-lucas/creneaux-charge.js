// plateforme/resilience — charge/revue-lucas/creneaux-charge.js (M29-E11, version corrigée de la MR !37)
// Question du ticket : MédiAgenda tient-il 500 requêtes/s ? Réponse mesurable : un taux d'arrivée
// fixé en ITÉRATIONS par seconde (une itération = 3 requêtes), des seuils = SLO, la recette seulement,
// des données factices, et rien qui reste en base. Les numéros renvoient à REVUE.md.
//   k6 run charge/revue-lucas/creneaux-charge.js                          (défaut prudent : 20 it/s, RB-290)
//   k6 run -e ITERATIONS_PAR_S=167 charge/revue-lucas/creneaux-charge.js  (≈ 500 req/s, annoncé, après la montée)
import http from 'k6/http';
import { check } from 'k6';
import exec from 'k6/execution';

// (13) Cible : la recette par défaut ; la production est refusée (liste d'autorisation).
const BASE = (__ENV.BASE_URL || 'https://mediagenda-recette.apps.par1.medisphere.internal').replace(/\/+$/, '');
if (!/^https:\/\/mediagenda-(recette|dev)\.apps\.par1\.medisphere\.internal$|^http:\/\/127\.0\.0\.1:[0-9]+$/.test(BASE)) {
  throw new Error(`cible refusée : ${BASE}`);
}

// (11) 500 requêtes/s = ~167 itérations/s de 3 requêtes. Assez de VUs : débit × durée d'itération
// (167 × 0,3 s ≈ 50) avec de la marge ; sinon k6 PERD des itérations (dropped_iterations).
// Défaut volontairement bas (RB-290 : paramètres prudents d'abord) ; le débit cible se demande
// explicitement, une fois la montée faite et le test annoncé.
const RYTHME = parseInt(__ENV.ITERATIONS_PAR_S || '20', 10);

export const options = {
  // (13) Vérification TLS conservée : la racine MédiSphère est dans le magasin de adm01.
  scenarios: {
    creneaux: {
      executor: 'constant-arrival-rate',
      rate: RYTHME,
      timeUnit: '1s',
      duration: __ENV.DUREE || '5m',
      preAllocatedVUs: Math.ceil(RYTHME / 2),
      maxVUs: RYTHME * 2,
    },
  },
  // (10) Les seuils décident du résultat : les checks seuls n'ont jamais fait échouer un test.
  thresholds: {
    http_req_duration: ['p(95)<250'],
    http_req_failed: ['rate<0.005', { threshold: 'rate<0.05', abortOnFail: true, delayAbortEval: '30s' }],
    checks: ['rate>0.99'],
    dropped_iterations: ['count<10'],
  },
};

// (13) Créneaux distincts par VU et itération, dates avec fuseau, loin dans le futur.
function creneau() {
  const vu = exec.vu.idInTest;
  const i = exec.vu.iterationInScenario;
  const jour = new Date(Date.now() + (60 + Math.floor(i / 16)) * 86400000).toISOString().slice(0, 10);
  const heure = 8 + Math.floor((i % 16) / 2) + ((i % 16) >= 8 ? 2 : 0);
  return { praticien: `dr-k6-${vu}`, debut: `${jour}T${String(heure).padStart(2, '0')}:${i % 2 ? '30' : '00'}:00+01:00`, jour };
}

export default function () {
  const c = creneau();
  const lus = http.get(`${BASE}/api/v1/creneaux?date=${c.jour}&praticien=${c.praticien}`, { tags: { name: 'GET /api/v1/creneaux' } });
  check(lus, { 'créneaux : 200': (r) => r.status === 200 });

  // (12) Données FACTICES générées ici : aucun export de la production, aucun identifiant réel.
  const cree = http.post(`${BASE}/api/v1/rendez-vous`, JSON.stringify({
    patient: `Patient Charge ${exec.vu.idInTest}-${exec.vu.iterationInScenario}`,
    praticien: c.praticien,
    debut: c.debut,
    duree_minutes: 30,
    motif: 'test de charge k6 (M29)',
  }), { headers: { 'Content-Type': 'application/json' }, tags: { name: 'POST /api/v1/rendez-vous' } });
  // (10) 201 attendu : « < 500 » laissait passer les 422 (date sans fuseau) et les 409.
  if (!check(cree, { 'création : 201': (r) => r.status === 201 })) {
    return;
  }
  // (13) Une URL par identifiant = une série par identifiant : on nomme la requête.
  // (13) Et on annule : la base de recette ne garde rien du test.
  const annule = http.del(`${BASE}/api/v1/rendez-vous/${cree.json('id')}`, null, { tags: { name: 'DELETE /api/v1/rendez-vous/{id}' } });
  check(annule, { 'annulation : 204': (r) => r.status === 204 });
  // (11) Pas de sleep : dans un modèle ouvert, le rythme vient de l'exécuteur.
}
