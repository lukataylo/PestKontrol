// Self-host the ONNX Runtime WASM binaries so nothing loads from a CDN at runtime.
import { cpSync, mkdirSync, readdirSync } from 'node:fs';
const src = 'node_modules/onnxruntime-web/dist/';
mkdirSync('public/ort', { recursive: true });
for (const f of readdirSync(src)) {
  if (/^ort-wasm-simd-threaded(\.(jsep|asyncify|jspi))?\.(wasm|mjs)$/.test(f)) cpSync(src + f, 'public/ort/' + f);
}
