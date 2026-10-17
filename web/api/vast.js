// Event archive on VAST. Two ways in, matching how VAST is usually exposed:
//   S3:  VAST_S3_ENDPOINT, VAST_ACCESS_KEY, VAST_SECRET_KEY, VAST_BUCKET (path-style, SigV4)
//   NFS: VAST_DIR=/mnt/vast/shoo (a mounted VAST view)
// With neither set, events go to a local folder so the API still works in dev,
// and status reports that VAST isn't connected.
import { S3Client, PutObjectCommand, GetObjectCommand, ListObjectsV2Command } from '@aws-sdk/client-s3';
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';

const {
  VAST_S3_ENDPOINT, VAST_ACCESS_KEY, VAST_SECRET_KEY, VAST_BUCKET = 'shoo', VAST_REGION = 'us-east-1', VAST_DIR,
} = process.env;
const PREFIX = 'shoo/';

const s3 = VAST_S3_ENDPOINT && VAST_ACCESS_KEY && VAST_SECRET_KEY
  ? new S3Client({
    endpoint: VAST_S3_ENDPOINT,
    region: VAST_REGION,
    forcePathStyle: true,
    credentials: { accessKeyId: VAST_ACCESS_KEY, secretAccessKey: VAST_SECRET_KEY },
  })
  : null;
const root = VAST_DIR || join(import.meta.dirname, '..', 'data');

export const vastStatus = () => ({
  connected: !!(s3 || VAST_DIR),
  mode: s3 ? 's3' : VAST_DIR ? 'nfs' : 'local',
  where: s3 ? `${VAST_S3_ENDPOINT.replace(/^https?:\/\//, '')}/${VAST_BUCKET}` : VAST_DIR ?? 'local disk (not VAST)',
});

export async function put(key, body, contentType) {
  if (s3) {
    await s3.send(new PutObjectCommand({ Bucket: VAST_BUCKET, Key: PREFIX + key, Body: body, ContentType: contentType }));
    return;
  }
  const file = join(root, PREFIX, key);
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, body);
}

export async function get(key) {
  if (s3) {
    const r = await s3.send(new GetObjectCommand({ Bucket: VAST_BUCKET, Key: PREFIX + key }));
    return Buffer.from(await r.Body.transformToByteArray());
  }
  return readFile(join(root, PREFIX, key));
}

export async function list(prefix) {
  if (s3) {
    const keys = [];
    let token;
    do {
      const r = await s3.send(new ListObjectsV2Command({ Bucket: VAST_BUCKET, Prefix: PREFIX + prefix, ContinuationToken: token }));
      for (const o of r.Contents ?? []) keys.push(o.Key.slice(PREFIX.length));
      token = r.IsTruncated ? r.NextContinuationToken : undefined;
    } while (token);
    return keys;
  }
  const out = [];
  const walk = async (dir, rel) => {
    let entries = [];
    try { entries = await readdir(dir, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      if (e.isDirectory()) await walk(join(dir, e.name), `${rel}${e.name}/`);
      else out.push(rel + e.name);
    }
  };
  await walk(join(root, PREFIX, prefix), prefix);
  return out;
}

/// Layout, so other tools (VAST DataBase, Spark, notebooks) can read it directly:
///   shoo/events/<yyyy-mm-dd>/<device>/<iso-time>_<species>.json   metadata + NVIDIA results + embedding
///   shoo/events/<yyyy-mm-dd>/<device>/<iso-time>_<species>.jpg    snapshot
export function eventKey(e) {
  const day = e.at.slice(0, 10);
  const safe = (s) => String(s).toLowerCase().replace(/[^a-z0-9-]+/g, '-').slice(0, 40) || 'x';
  return `events/${day}/${safe(e.device)}/${e.at.replace(/[:.]/g, '-')}_${safe(e.species)}`;
}
