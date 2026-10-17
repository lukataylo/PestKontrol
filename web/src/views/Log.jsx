import { useEffect, useLayoutEffect, useRef, useState } from 'preact/hooks';
import { DotText, Pet, Glyph } from '../dot.jsx';
import { PESTS } from '../detector.js';
import { all, blobURL, clear, remove, revision } from '../store.js';
import { pal, rgba, stamp } from '../theme.js';
import { Caption, Card, Chip, Panel, Title } from '../ui.jsx';

export function Log() {
  const [items, setItems] = useState([]);
  const [open, setOpen] = useState(null);
  const rev = revision.value;
  useEffect(() => { all('sightings').then((s) => setItems(s.reverse())); }, [rev]);
  const hours = new Array(24).fill(0);
  items.forEach((s) => hours[s.at.getHours()]++);

  return (
    <div class="screen">
      <div class="stack">
        <div class="row" style={{ alignItems: 'flex-end' }}>
          <Title text="LOG" />
          <span class="spacer" />
          <Caption>{items.length} events</Caption>
        </div>

        <Card>
          <div class="row" style={{ justifyContent: 'space-between' }}>
            {PESTS.map((p) => {
              const n = items.filter((s) => s.species === p).length;
              return (
                <div key={p} class="stack" style={{ alignItems: 'center', gap: '10px' }} aria-label={`${n} ${p}`}>
                  <div style={{ height: '27px', display: 'flex', alignItems: 'flex-end' }}><Pet kind={p} pitch={2.4} dim={!n} /></div>
                  <DotText text={String(n)} pitch={3} color={n ? undefined : 'var(--ghost)'} />
                </div>
              );
            })}
          </div>
        </Card>

        <Card title="Activity by hour">
          <HourChart hours={hours} />
          <div class="row" style={{ justifyContent: 'space-between' }}>
            {['00', '06', '12', '18', '23'].map((h) => <Caption key={h}>{h}</Caption>)}
          </div>
        </Card>

        {items.length === 0 ? (
          <Card>
            <DotText text="NOTHING YET" pitch={3} />
            <Caption>Visits appear here with a snapshot</Caption>
          </Card>
        ) : (
          <>
            {items.map((s) => (
              <Panel key={s.id} class="listrow" radius="24px" style={{ padding: '10px' }} seed={s.id} onClick={() => setOpen(s)}>
                <div class="row" style={{ gap: '14px', width: '100%' }}>
                  <div class="thumb big">{s.snapshot ? <img src={blobURL(s.snapshot)} alt="" /> : <Pet kind={s.species} pitch={3} dim />}</div>
                  <div class="stack" style={{ gap: '9px', flex: 1 }}>
                    <DotText text={s.species} pitch={2.6} />
                    <Caption>{stamp(s.at)} · {Math.round(s.confidence * 100)}%</Caption>
                  </div>
                  <Outcome s={s} />
                </div>
              </Panel>
            ))}
            <button class="chip" style={{ alignSelf: 'center', borderColor: 'var(--red)' }}
              onClick={() => confirm('Delete every sighting and snapshot?') && clear('sightings')}>Clear log</button>
          </>
        )}
      </div>
      {open && <Detail s={open} close={() => setOpen(null)} />}
    </div>
  );
}

const Outcome = ({ s }) => (
  <div class="stack" style={{ gap: '6px', alignItems: 'flex-end' }}>
    {s.outcome === 'fired' ? <Chip kind="solid">{s.pattern}</Chip> : <Chip>{{ quiet: 'Quiet', vetoed: 'Held' }[s.outcome] ?? 'Logged'}</Chip>}
    {s.cloud && !s.cloud.error && <Chip>{s.cloud.present ? 'NVIDIA ✓' : 'NVIDIA ✗'}</Chip>}
  </div>
);

function HourChart({ hours }) {
  const ref = useRef();
  const p = pal();
  useLayoutEffect(() => {
    const c = ref.current, w = c.clientWidth, h = c.clientHeight, dpr = Math.min(2, devicePixelRatio || 1);
    c.width = w * dpr; c.height = h * dpr;
    const g = c.getContext('2d');
    g.scale(dpr, dpr);
    const rows = 7, pitch = w / 24, rp = h / rows, d = Math.min(pitch, rp) * 0.6;
    const peak = Math.max(1, ...hours), now = new Date().getHours();
    for (let x = 0; x < 24; x++) {
      const lit = hours[x] ? Math.max(1, Math.round((hours[x] / peak) * rows)) : 0;
      for (let r = 0; r < rows; r++) {
        g.fillStyle = r < lit ? (x === now ? p.red : p.ink) : rgba(p.ink, 0.08);
        g.beginPath();
        g.arc(x * pitch + pitch / 2, h - (r + 0.5) * rp, d / 2, 0, Math.PI * 2);
        g.fill();
      }
    }
  });
  return <canvas ref={ref} class="hourchart" aria-label="Visits by hour of day" />;
}

function Detail({ s, close }) {
  return (
    <div class="sheet" role="dialog" aria-label={`${s.species} visit`}>
      <div class="stack">
        <div class="row">
          <DotText text={s.species} pitch={6} />
          <span class="spacer" />
          <button class="close" onClick={close} aria-label="Close">✕</button>
        </div>
        {s.snapshot && <img class="full" src={blobURL(s.snapshot)} alt={`${s.species} snapshot`} />}
        <Card>
          {[['Time', stamp(s.at)], ['Confidence', `${Math.round(s.confidence * 100)}%`], ['Outcome', s.outcome], ['Sound', s.pattern ?? 'none'], ['Light', s.dark ? 'night' : 'day']].map(([k, v]) => (
            <div class="row" key={k}><Caption>{k}</Caption><span class="spacer" /><span class="text" style={{ textTransform: 'uppercase' }}>{v}</span></div>
          ))}
        </Card>
        {s.cloud && (
          <Card title="NVIDIA · VAST">
            {s.cloud.error ? <span class="blurb">Cloud check failed: {s.cloud.error}</span> : (
              <>
                <div class="row"><Caption>Verdict</Caption><span class="spacer" /><span class="text">{s.cloud.present ? `CONFIRMED ${s.species.toUpperCase()}` : `NOT A ${s.species.toUpperCase()} · SAW ${String(s.cloud.animal).toUpperCase()}`}</span></div>
                <p class="text" style={{ margin: 0 }}>{s.cloud.description}</p>
                <Caption>{s.cloud.model} · archived to {s.cloud.stored}</Caption>
              </>
            )}
          </Card>
        )}
        <button class="primary" style={{ background: 'none', border: '1px solid var(--red)' }} onClick={() => { remove('sightings', s.id); close(); }}>
          <Glyph name="trash" pitch={2.4} color="var(--red)" /><DotText text="DELETE" pitch={2.6} color={pal().red} />
        </button>
      </div>
    </div>
  );
}
