// IndexedDB for the searchable timeline (moments) and the visit log (sightings).
// Everything stays in this browser.
import { signal } from '@preact/signals';

/// Bumped whenever the log changes, so views re-query.
export const revision = signal(0);

const dbp = new Promise((resolve, reject) => {
  const req = indexedDB.open('shoo', 1);
  req.onupgradeneeded = () => {
    const db = req.result;
    for (const name of ['moments', 'sightings']) {
      const s = db.createObjectStore(name, { keyPath: 'id', autoIncrement: true });
      s.createIndex('at', 'at');
    }
  };
  req.onsuccess = () => resolve(req.result);
  req.onerror = () => reject(req.error);
});

const done = (req) => new Promise((res, rej) => { req.onsuccess = () => res(req.result); req.onerror = () => rej(req.error); });

export async function add(store, value) {
  const db = await dbp;
  const id = await done(db.transaction(store, 'readwrite').objectStore(store).add(value));
  if (store === 'sightings') revision.value++;
  return id;
}

export async function put(store, value) {
  const db = await dbp;
  return done(db.transaction(store, 'readwrite').objectStore(store).put(value));
}

/// Records with `at` in [from, to], oldest first.
export async function range(store, from, to) {
  const db = await dbp;
  const idx = db.transaction(store).objectStore(store).index('at');
  return done(idx.getAll(IDBKeyRange.bound(from, to)));
}

export async function all(store) {
  const db = await dbp;
  return done(db.transaction(store).objectStore(store).index('at').getAll());
}

export async function remove(store, id) {
  const db = await dbp;
  await done(db.transaction(store, 'readwrite').objectStore(store).delete(id));
  revision.value++;
}

export async function clear(store) {
  const db = await dbp;
  await done(db.transaction(store, 'readwrite').objectStore(store).clear());
  revision.value++;
}

export async function pruneBefore(store, date) {
  const db = await dbp;
  const tx = db.transaction(store, 'readwrite');
  const idx = tx.objectStore(store).index('at');
  return new Promise((res) => {
    const req = idx.openCursor(IDBKeyRange.upperBound(date, true));
    req.onsuccess = () => {
      const c = req.result;
      if (!c) return res();
      c.delete();
      c.continue();
    };
  });
}

/// Object URLs for stored image blobs, cached so lists don't leak.
const urls = new WeakMap();
export function blobURL(blob) {
  if (!blob) return null;
  if (!urls.has(blob)) urls.set(blob, URL.createObjectURL(blob));
  return urls.get(blob);
}

export async function persist() {
  try {
    await navigator.storage?.persist?.();
  } catch { /* best effort */ }
}
