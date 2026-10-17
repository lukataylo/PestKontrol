// Static server for the built PWA. Serves pre-compressed files when present
// and sets cross-origin isolation so the model can use WASM threads.
import { createServer } from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { extname, join, normalize } from 'node:path';
import { handleAPI } from './api/cloud.js';

const ROOT = join(import.meta.dirname, 'dist');
const PORT = Number(process.env.PORT) || 8080;

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css',
  '.json': 'application/json', '.webmanifest': 'application/manifest+json', '.png': 'image/png', '.svg': 'image/svg+xml',
  '.woff2': 'font/woff2', '.wasm': 'application/wasm', '.onnx': 'application/octet-stream', '.ico': 'image/x-icon',
};

function cacheControl(path) {
  if (path.startsWith('/assets/') || path.startsWith('/models/') || path.startsWith('/ort/')) return 'public, max-age=31536000, immutable';
  if (path === '/sw.js' || path.endsWith('.html')) return 'no-cache';
  return 'public, max-age=86400';
}

createServer(async (req, res) => {
  if (await handleAPI(req, res)) return;
  let path = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  path = normalize(path).replace(/^(\.\.[/\\])+/, '');
  let file = join(ROOT, path);
  if (!file.startsWith(ROOT)) { res.writeHead(403).end(); return; }
  if (!existsSync(file) || statSync(file).isDirectory()) {
    if (extname(path)) { res.writeHead(404).end('Not found'); return; }
    file = join(ROOT, 'index.html');
    path = '/index.html';
  }

  const headers = {
    'Content-Type': TYPES[extname(file)] ?? 'application/octet-stream',
    'Cache-Control': cacheControl(path),
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Cross-Origin-Embedder-Policy': 'credentialless',
    'Cross-Origin-Resource-Policy': 'same-origin',
    'X-Content-Type-Options': 'nosniff',
    'Permissions-Policy': 'camera=(self)',
  };
  if (path === '/sw.js') headers['Service-Worker-Allowed'] = '/';

  const gz = file + '.gz';
  if (/\bgzip\b/.test(req.headers['accept-encoding'] ?? '') && existsSync(gz)) {
    headers['Content-Encoding'] = 'gzip';
    headers['Vary'] = 'Accept-Encoding';
    file = gz;
  }
  headers['Content-Length'] = statSync(file).size;
  res.writeHead(200, headers);
  if (req.method === 'HEAD') return res.end();
  createReadStream(file).pipe(res);
}).listen(PORT, () => console.log(`SHOO on :${PORT}`));
