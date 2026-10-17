// SHOO Cloud Boost API — opt-in. Devices send confirmed visits (a snapshot,
// never live video); NVIDIA verifies, describes and embeds them; VAST keeps them.
import { timingSafeEqual } from 'node:crypto';
import { vastStatus, put, get, list, eventKey } from './vast.js';
import { nvidiaStatus, verify, embedImage, embedQuery, answer } from './nvidia.js';

const TOKEN = process.env.SHOO_CLOUD_TOKEN;
const MAX_BODY = 3 * 1024 * 1024;
const index = new Map(); // key → event metadata (incl. embedding), warm cache of the archive
let loaded = null;

const json = (res, code, body) => {
  res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(body));
};

function authorised(req) {
  if (!TOKEN) return false;
  const given = Buffer.from(String(req.headers.authorization ?? '').replace(/^Bearer /, ''));
  const want = Buffer.from(TOKEN);
  return given.length === want.length && timingSafeEqual(given, want);
}

async function body(req) {
  const chunks = [];
  let size = 0;
  for await (const c of req) {
    size += c.length;
    if (size > MAX_BODY) throw Object.assign(new Error('too large'), { status: 413 });
    chunks.push(c);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
}

/// Warm the index from VAST: the last 14 days of event metadata.
function loadIndex() {
  loaded ??= (async () => {
    const days = [...Array(14)].map((_, i) => new Date(Date.now() - i * 86400_000).toISOString().slice(0, 10));
    for (const day of days) {
      for (const key of (await list(`events/${day}/`).catch(() => [])).filter((k) => k.endsWith('.json'))) {
        try { index.set(key.slice(0, -5), JSON.parse((await get(key)).toString('utf8'))); } catch { /* skip bad */ }
      }
    }
  })();
  return loaded;
}

const cosine = (a, b) => {
  let s = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) { s += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]; }
  return s / (Math.sqrt(na * nb) || 1);
};

const publicEvent = ({ embedding, ...e }) => e;

async function ingest(req, res) {
  const b = await body(req);
  if (!b.jpeg || !b.species || !b.at) return json(res, 400, { error: 'jpeg, species and at are required' });
  const e = {
    device: String(b.device || 'camera').slice(0, 40),
    at: new Date(b.at).toISOString(),
    species: String(b.species).slice(0, 20),
    confidence: Number(b.confidence) || 0,
    outcome: String(b.outcome || 'logged').slice(0, 12),
    pattern: b.pattern ? String(b.pattern).slice(0, 12) : null,
  };
  const key = eventKey(e);
  const [check, embedding] = await Promise.allSettled([verify(b.jpeg, e.species), embedImage(b.jpeg)]);
  e.nvidia = check.status === 'fulfilled' ? check.value : { error: String(check.reason?.message ?? check.reason).slice(0, 200) };
  e.embedding = embedding.status === 'fulfilled' ? embedding.value : null;
  e.image = `${key}.jpg`;
  await put(e.image, Buffer.from(b.jpeg, 'base64'), 'image/jpeg');
  await put(`${key}.json`, JSON.stringify(e), 'application/json');
  index.set(key, e);
  json(res, 200, { key, stored: vastStatus().where, ...publicEvent(e) });
}

async function search(req, res) {
  const { query, limit = 12 } = await body(req);
  if (!query) return json(res, 400, { error: 'query required' });
  await loadIndex();
  const q = await embedQuery(String(query).slice(0, 300));
  const hits = [...index.entries()]
    .filter(([, e]) => e.embedding)
    .map(([key, e]) => ({ key, score: cosine(q, e.embedding), ...publicEvent(e) }))
    .sort((a, b) => b.score - a.score)
    .slice(0, Math.min(40, limit));
  json(res, 200, { results: hits });
}

async function ask(req, res) {
  const { question, deviceLog = '' } = await body(req);
  if (!question) return json(res, 400, { error: 'question required' });
  await loadIndex();
  const events = [...index.values()].sort((a, b) => a.at.localeCompare(b.at)).slice(-60);
  const log = events.map((e) => `${e.at.slice(0, 16).replace('T', ' ')} [${e.device}] ${e.species} ${e.outcome}` +
    `${e.nvidia?.description ? ` — ${e.nvidia.description}` : ''}${e.nvidia && !e.nvidia.error && !e.nvidia.present ? ' (NVIDIA: not confirmed)' : ''}`)
    .join('\n');
  const r = await answer(String(question).slice(0, 500), `${log || 'No archived events.'}\n\nThis device:\n${String(deviceLog).slice(0, 4000)}`);
  json(res, 200, r);
}

async function image(req, res, url) {
  const key = url.searchParams.get('key') ?? '';
  if (!/^events\/[\w\-/.]+\.jpg$/.test(key) || key.includes('..')) return json(res, 400, { error: 'bad key' });
  const buf = await get(key);
  res.writeHead(200, { 'Content-Type': 'image/jpeg', 'Cache-Control': 'private, max-age=86400', 'Cross-Origin-Resource-Policy': 'same-origin' });
  res.end(buf);
}

/// Returns true if it handled the request.
export async function handleAPI(req, res) {
  const url = new URL(req.url, 'http://x');
  if (!url.pathname.startsWith('/api/')) return false;
  try {
    if (url.pathname === '/api/cloud/status') {
      json(res, 200, { enabled: !!TOKEN, authorised: authorised(req), vast: vastStatus(), nvidia: nvidiaStatus() });
    } else if (!TOKEN) {
      json(res, 503, { error: 'Cloud Boost is off on this server (SHOO_CLOUD_TOKEN not set).' });
    } else if (!authorised(req)) {
      json(res, 401, { error: 'Wrong cloud key.' });
    } else if (req.method === 'POST' && url.pathname === '/api/events') {
      await ingest(req, res);
    } else if (req.method === 'POST' && url.pathname === '/api/search') {
      await search(req, res);
    } else if (req.method === 'POST' && url.pathname === '/api/ask') {
      await ask(req, res);
    } else if (req.method === 'GET' && url.pathname === '/api/image') {
      await image(req, res, url);
    } else {
      json(res, 404, { error: 'not found' });
    }
  } catch (e) {
    json(res, e.status ?? 500, { error: String(e.message ?? e).slice(0, 300) });
  }
  return true;
}
