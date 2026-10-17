// Pre-gzip compressible build output (the WASM runtime shrinks ~4×).
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';

const walk = (d) => readdirSync(d).flatMap((f) => (statSync(join(d, f)).isDirectory() ? walk(join(d, f)) : [join(d, f)]));
let saved = 0;
for (const f of walk('dist')) {
  if (!/\.(js|mjs|css|html|json|wasm|webmanifest|svg)$/.test(f)) continue;
  const raw = readFileSync(f);
  const gz = gzipSync(raw, { level: 9 });
  if (gz.length < raw.length * 0.9) { writeFileSync(f + '.gz', gz); saved += raw.length - gz.length; }
}
console.log(`gzip saved ${(saved / 1e6).toFixed(1)} MB`);
