// Rolling recording into the browser's private file system (OPFS):
// 5-minute segments named by start time, pruned past the retention window.

const SEGMENT_MS = 5 * 60 * 1000;
const TYPES = ['video/mp4;codecs=avc1', 'video/mp4', 'video/webm;codecs=vp9', 'video/webm'];

export class Recorder {
  constructor() {
    this.enabled = true;
    this.keepHours = 6;
    this.rec = null;
  }

  static supported() {
    return !!(window.MediaRecorder && navigator.storage?.getDirectory);
  }

  async dir() {
    const root = await navigator.storage.getDirectory();
    return root.getDirectoryHandle('video', { create: true });
  }

  start(stream) {
    this.stream = stream;
    if (this.enabled && Recorder.supported()) this.begin();
  }

  setEnabled(on) {
    this.enabled = on;
    if (!on) this.finish();
    else if (this.stream && !this.rec) this.begin();
  }

  begin() {
    const type = TYPES.find((t) => MediaRecorder.isTypeSupported(t));
    if (!type) return;
    const chunks = [];
    const started = Date.now();
    this.started = started;
    const rec = new MediaRecorder(this.stream, { mimeType: type, videoBitsPerSecond: 1_000_000 });
    rec.ondataavailable = (e) => e.data.size && chunks.push(e.data);
    rec.onstop = () => this.write(started, type, chunks).then(() => rec.resolveStop?.());
    rec.start(10_000);
    this.rec = rec;
    clearTimeout(this.rotate);
    this.rotate = setTimeout(() => this.roll(), SEGMENT_MS);
  }

  /// Close the current segment so it can be played, start the next.
  async roll() {
    const old = this.rec;
    if (!old) return;
    this.rec = null;
    await new Promise((res) => { old.resolveStop = res; old.stop(); });
    if (this.enabled && this.stream?.active) this.begin();
  }

  finish() {
    clearTimeout(this.rotate);
    if (this.rec?.state === 'recording') this.rec.stop();
    this.rec = null;
  }

  async write(started, type, chunks) {
    if (!chunks.length) return;
    const ext = type.includes('mp4') ? 'mp4' : 'webm';
    const dir = await this.dir();
    const file = await dir.getFileHandle(`seg_${started}.${ext}`, { create: true });
    const w = await file.createWritable();
    await w.write(new Blob(chunks, { type }));
    await w.close();
    await this.prune();
  }

  async segments() {
    const out = [];
    try {
      for await (const [name, handle] of (await this.dir()).entries()) {
        const m = /^seg_(\d+)\./.exec(name);
        if (m) out.push({ start: Number(m[1]), name, handle });
      }
    } catch { /* no OPFS */ }
    return out.sort((a, b) => a.start - b.start);
  }

  async prune() {
    const cutoff = Date.now() - this.keepHours * 3600_000 - SEGMENT_MS;
    const dir = await this.dir();
    for (const s of await this.segments()) if (s.start < cutoff) await dir.removeEntry(s.name);
  }

  async bytes() {
    let total = 0;
    for (const s of await this.segments()) total += (await s.handle.getFile()).size;
    return total;
  }

  /// URL + offset (seconds) for the footage around `at`.
  async locate(at) {
    const t = at.getTime();
    // The segment being written isn't playable until it's closed.
    if (this.rec && t >= this.started - 1000) await this.roll();
    const seg = (await this.segments()).filter((s) => s.start <= t + 1000).at(-1);
    if (!seg || t - seg.start > SEGMENT_MS + 30_000) return null;
    return { url: URL.createObjectURL(await seg.handle.getFile()), offset: Math.max(0, (t - seg.start) / 1000) };
  }
}
