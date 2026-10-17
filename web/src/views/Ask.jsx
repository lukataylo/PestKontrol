import { useEffect, useState } from 'preact/hooks';
import { BotFace, BotSpeech } from '../bot.jsx';
import { DotText, Glyph, Pet, PETS } from '../dot.jsx';
import { search, ask, spot, parseRule, ruleWhen, range2, aiStatus } from '../recall.js';
import * as S from '../sentry.js';
import { all, blobURL } from '../store.js';
import { clock, stamp } from '../theme.js';
import { Card, Caption, Chip, Panel, Title, Toggle, Stepper, RoundButton } from '../ui.jsx';

const SUGGESTIONS = [
  'What happened overnight?',
  'Show me every pigeon today',
  'Was anyone here this morning?',
  'Any movement in the last hour?',
  'a bird on the railing',
];

const isQuestion = (q) => /\?$/.test(q.trim()) || /^(what|when|was|were|did|how|who|why|is|are|any|has|tell)\b/i.test(q.trim());

export function Ask({ play }) {
  const [q, setQ] = useState('');
  const [asked, setAsked] = useState('');
  const [busy, setBusy] = useState(false);
  const [answer, setAnswer] = useState(null);
  const [spotted, setSpotted] = useState([]);
  const [ai, setAI] = useState(false);

  useEffect(() => {
    aiStatus().then(setAI);
    const refresh = () => spot(new Date(Date.now() - 86_400_000), new Date(), S.tuning.value.threshold).then(setSpotted);
    refresh();
    const id = setInterval(refresh, 30_000);
    return () => clearInterval(id);
  }, []);

  async function run(text = q) {
    const t = text.trim();
    if (!t || busy) return;
    setQ(t);
    setAsked(t);
    setBusy(true);
    document.activeElement?.blur();
    try {
      const horizon = Math.max(S.recall.value.keepHours, 48);
      if (isQuestion(t)) {
        setAnswer(await ask(t, { horizonHours: horizon, threshold: S.tuning.value.threshold, sightings: await all('sightings') }));
      } else {
        const { clips } = await search(t, { horizonHours: horizon });
        setAnswer({ text: clips.length ? `${clips.length} moment${clips.length === 1 ? '' : 's'} matched.` : `Nothing matched “${t}”.`, clips, usedAI: false });
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <div class="screen">
      <div class="stack">
        <div class="row" style={{ alignItems: 'flex-end' }}>
          <Title text="ASK" />
          <span class="spacer" />
          <Caption>{ai ? 'On-device AI' : 'On-device search'}</Caption>
        </div>

        <Panel class="field" seed={71} radius="28px" style={{ padding: '0 9px 0 18px' }}>
          <div class="row" style={{ width: '100%', height: '100%' }}>
            <Glyph name="search" pitch={2.4} color="var(--dim)" />
            <input
              value={q}
              placeholder="Search or ask about your footage"
              aria-label="Search or ask about your footage"
              enterkeyhint="search"
              onInput={(e) => setQ(e.currentTarget.value)}
              onKeyDown={(e) => e.key === 'Enter' && run()}
            />
            {q && <RoundButton icon="arrow" label="Ask" on onClick={() => run()} />}
          </div>
        </Panel>

        <div class="hscroll">
          {SUGGESTIONS.map((s) => <button class="chip" key={s} onClick={() => run(s)}>{s}</button>)}
        </div>

        {busy && (
          <Panel seed={72}>
            <div class="row" style={{ gap: '16px' }}>
              <div style={{ width: '96px' }}><BotFace mood="suspicious" /></div>
              <BotSpeech text="Searching footage..." pitch={2.2} max={16} />
            </div>
          </Panel>
        )}

        {!busy && answer && (
          <Panel seed={73} splat="tr">
            <div class="stack">
              <div class="row" style={{ alignItems: 'flex-start', gap: '14px' }}>
                <div style={{ width: '72px', flex: 'none' }}><BotFace mood={answer.clips.length ? 'surprised' : 'idle'} /></div>
                <div class="stack" style={{ gap: '8px' }}>
                  <Caption>{asked}</Caption>
                  <div class="text" style={{ fontSize: '14px' }}>{answer.text}</div>
                </div>
              </div>
              {answer.clips.length > 0 && (
                <div class="clipgrid">
                  {answer.clips.map((c) => <Tile key={c.start} clip={c} onClick={() => play(c)} />)}
                </div>
              )}
              <Caption>{answer.usedAI ? 'Answered by the on-device model' : 'Matched on this device'}</Caption>
            </div>
          </Panel>
        )}

        <Caption style={{ marginTop: '8px' }}>Spotted · last 24h</Caption>
        {spotted.length === 0 ? (
          <Card><p class="body" style={{ fontSize: '12px' }}>Nothing spotted yet. Events appear here as the camera sees them.</p></Card>
        ) : (
          <div class="stack" style={{ gap: '8px' }}>
            {spotted.slice(0, 20).map((c) => (
              <Panel key={c.kind + c.start} class="listrow" radius="18px" style={{ padding: '10px' }} seed={c.start % 991} onClick={() => play(c)}>
                <div class="row" style={{ gap: '14px', width: '100%' }}>
                  <div style={{ width: '34px', display: 'grid', placeItems: 'center' }}><KindIcon kind={c.kind} /></div>
                  <div class="stack" style={{ gap: '6px', flex: 1, minWidth: 0 }}>
                    <DotText text={c.kind} pitch={2.2} />
                    <Caption>{range2(c)}</Caption>
                  </div>
                  <div class="thumb">{c.thumb && <img src={blobURL(c.thumb)} alt="" />}</div>
                </div>
              </Panel>
            ))}
          </div>
        )}

        <Caption style={{ marginTop: '8px' }}>When · then</Caption>
        <Rules />

        <Caption style={{ marginTop: '8px' }}>Footage</Caption>
        <Footage />
      </div>
    </div>
  );
}

export function KindIcon({ kind }) {
  if (PETS[kind]) return <Pet kind={kind} pitch={2.2} />;
  return <Glyph name={kind === 'lights down' ? 'moon' : kind === 'lights up' ? 'bulb' : 'eye'} pitch={2.4} />;
}

function Tile({ clip, onClick }) {
  return (
    <div class="tile" onClick={onClick} role="button" aria-label={`${clip.kind} at ${range2(clip)}`}>
      {clip.thumb && <img src={blobURL(clip.thumb)} alt="" />}
      <div style={{ position: 'absolute', top: '10px', right: '10px' }}><Glyph name="play" pitch={1.8} color="#fff" /></div>
      <div class="meta">
        <DotText text={clip.kind} pitch={1.9} color="#ffffff" />
        <span style={{ color: 'rgba(255,255,255,0.8)' }}>{range2(clip)}</span>
      </div>
    </div>
  );
}

function RuleChips({ rule }) {
  return (
    <div class="row" style={{ flexWrap: 'wrap', gap: '6px' }}>
      <Chip>When {ruleWhen(rule)}</Chip>
      {rule.actions.map((a) => <Chip key={a} kind="solid">{a}</Chip>)}
    </div>
  );
}

function Rules() {
  const [text, setText] = useState('');
  const [draft, setDraft] = useState(null);
  const list = S.rules.value;
  const update = (id, patch) => (S.rules.value = list.map((r) => (r.id === id ? { ...r, ...patch } : r)));

  return (
    <div class="stack" style={{ gap: '10px' }}>
      {list.map((r) => (
        <Panel key={r.id} seed={r.text.length}>
          <div class="row" style={{ alignItems: 'flex-start' }}>
            <div class="stack" style={{ gap: '10px', flex: 1 }}>
              <div class="text" style={{ color: r.enabled ? 'var(--ink)' : 'var(--dim)' }}>{r.text}</div>
              <RuleChips rule={r} />
            </div>
            <div class="stack" style={{ alignItems: 'flex-end', gap: '10px' }}>
              <Toggle on={r.enabled} label="Rule on" onChange={(on) => update(r.id, { enabled: on })} />
              <button class="caption" onClick={() => (S.rules.value = list.filter((x) => x.id !== r.id))} aria-label="Delete rule">Delete</button>
            </div>
          </div>
        </Panel>
      ))}

      {draft ? (
        <Panel seed={75}>
          <div class="stack">
            <Caption>New rule · check it</Caption>
            <RuleChips rule={draft} />
            {draft.actions.includes('webhook') && (
              <input class="hook" placeholder="https://… webhook URL" value={draft.webhook ?? ''} inputMode="url" autoCapitalize="off"
                onInput={(e) => setDraft({ ...draft, webhook: e.currentTarget.value || null })} />
            )}
            <div class="row" style={{ gap: '10px' }}>
              <button class="chip solid" onClick={() => {
                S.rules.value = [...list, draft];
                if (draft.actions.includes('notify')) S.askNotifications();
                setDraft(null);
                setText('');
              }}>Save rule</button>
              <button class="chip" onClick={() => setDraft(null)}>Edit</button>
            </div>
          </div>
        </Panel>
      ) : (
        <Panel seed={74} style={{ padding: '14px' }}>
          <div class="row">
            <textarea class="rule" rows={2} value={text} aria-label="New rule"
              placeholder="If a fox comes at night, flash the lamp and tell me"
              onInput={(e) => setText(e.currentTarget.value)}
              onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); text.trim() && setDraft(parseRule(text.trim())); } }} />
            {text.trim() && <RoundButton icon="arrow" label="Make rule" on onClick={() => setDraft(parseRule(text.trim()))} />}
          </div>
        </Panel>
      )}

      {S.firings.value.length > 0 && (
        <div class="stack" style={{ gap: '6px', padding: '0 6px' }}>
          {S.firings.value.slice(0, 5).map((f) => <Caption key={f.at}>{clock(f.at)} · {f.what}</Caption>)}
        </div>
      )}
    </div>
  );
}

function Footage() {
  const r = S.recall.value;
  const [bytes, setBytes] = useState(0);
  useEffect(() => { S.recorder.bytes().then(setBytes).catch(() => {}); }, [r.keepHours, r.record]);
  const set = (patch) => (S.recall.value = { ...r, ...patch });
  return (
    <Card seed={76}>
      <div class="row">
        <span class="text" style={{ fontSize: '12px' }}>Record footage</span>
        <span class="spacer" />
        <Toggle on={r.record} label="Record footage" onChange={(on) => set({ record: on })} />
      </div>
      <Stepper label="Keep" value={`${r.keepHours}H`}
        dec={() => set({ keepHours: Math.max(1, r.keepHours - (r.keepHours > 6 ? 6 : 1)) })}
        inc={() => set({ keepHours: Math.min(48, r.keepHours + (r.keepHours >= 6 ? 6 : 1)) })} />
      <Caption>{(bytes / 1e9).toFixed(2)} GB in this browser · ~0.45 GB per hour · never uploaded</Caption>
    </Card>
  );
}

/// Plays stored footage from a few seconds before the moment.
export function Player({ clip, close }) {
  const [src, setSrc] = useState(undefined);
  useEffect(() => {
    let url;
    S.recorder.locate(new Date(clip.start)).then((r) => {
      setSrc(r);
      url = r?.url;
    });
    return () => url && URL.revokeObjectURL(url);
  }, [clip]);
  return (
    <div class="sheet" role="dialog" aria-label={`${clip.kind} footage`}>
      <div class="stack">
        <div class="row">
          <DotText text={clip.kind} pitch={4} />
          <span class="spacer" />
          <button class="close" onClick={close} aria-label="Close">✕</button>
        </div>
        <Caption>{stamp(new Date(clip.start))}</Caption>
        {src === undefined && <Caption>Finding footage…</Caption>}
        {src && (
          <video src={src.url} controls autoplay playsInline
            onLoadedMetadata={(e) => { e.currentTarget.currentTime = Math.max(0, src.offset - 3); }} />
        )}
        {src === null && (
          <div class="stack">
            {clip.thumb && <img class="full" src={blobURL(clip.thumb)} alt="" />}
            <Chip>No footage kept for this moment</Chip>
          </div>
        )}
      </div>
    </div>
  );
}
