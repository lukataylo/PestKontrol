import { useEffect, useState } from 'preact/hooks';
import { signal } from '@preact/signals';
import { BotFace, BotSpeech } from '../bot.jsx';
import { DotText, Glyph, Pet } from '../dot.jsx';
import { loadModel, model, PESTS } from '../detector.js';
import * as S from '../sentry.js';
import { PetGrid, Friends, ModePicker } from './Config.jsx';
import { Caption, Panel, Title } from '../ui.jsx';
import { EngineCard } from './Engine.jsx';
import { slasher } from '../theme.js';

/// Chrome/Android/desktop hand us an install prompt we can trigger from a button.
export const installPrompt = signal(null);
window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault();
  installPrompt.value = e;
});
window.addEventListener('appinstalled', () => (installPrompt.value = null));

const platform = () => {
  const ua = navigator.userAgent;
  const standalone = matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  if (standalone) return 'installed';
  if (/iPhone|iPad|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)) {
    return /CriOS|FxiOS|EdgiOS/.test(ua) ? 'ios-other' : 'ios';
  }
  if (/Android/.test(ua)) return 'android';
  return 'desktop';
};

const FEATURES = [
  ['eye', 'SPOTS PESTS', 'Pigeons, gulls, foxes, rats and squirrels — recognised by AI running on this device.'],
  ['speaker', 'SCARES THEM OFF', 'A different sound for each pest, randomised so they never get used to it.'],
  ['search', 'REMEMBERS', 'Ask “what happened last night?” and jump straight to the clip.'],
  ['lock', 'STAYS PRIVATE', 'No account, no uploads. Video never leaves this phone.'],
];

function Step({ n, children }) {
  return (
    <div class="row" style={{ gap: '12px', alignItems: 'flex-start' }}>
      <span class="stepnum">{n}</span>
      <span class="text" style={{ paddingTop: '2px' }}>{children}</span>
    </div>
  );
}

const Inline = ({ name }) => (
  <span class="inlineglyph"><Glyph name={name} pitch={1.9} /></span>
);

function Install() {
  const p = platform();
  const prompt = installPrompt.value;
  if (p === 'installed') {
    return (
      <div class="row" style={{ gap: '10px' }}>
        <Glyph name="check" pitch={2.4} color="var(--red)" />
        <span class="text">Installed — you're running SHOO from your home screen.</span>
      </div>
    );
  }
  return (
    <div class="stack" style={{ gap: '12px' }}>
      <p class="body" style={{ fontSize: '13px' }}>
        Install SHOO so it opens full screen, stays awake and works offline.
      </p>
      {prompt && (
        <button class="chip ink press" style={{ alignSelf: 'flex-start', padding: '9px 14px' }}
          onClick={async () => { prompt.prompt(); await prompt.userChoice; installPrompt.value = null; }}>
          <Glyph name="plus" pitch={1.8} color="#000000" /> Install SHOO
        </button>
      )}
      {p === 'ios' && (
        <>
          <Step n="1">Tap Share <Inline name="share" /> in Safari's toolbar.</Step>
          <Step n="2">Scroll down and tap <b>Add to Home Screen</b>.</Step>
          <Step n="3">Tap <b>Add</b>, then open SHOO from your home screen.</Step>
        </>
      )}
      {p === 'ios-other' && (
        <>
          <Step n="1">Open this page in <b>Safari</b> (or tap Share <Inline name="share" /> here if available).</Step>
          <Step n="2">Choose <b>Add to Home Screen</b>.</Step>
          <Step n="3">Open SHOO from your home screen.</Step>
        </>
      )}
      {p === 'android' && !prompt && (
        <>
          <Step n="1">Tap the browser menu <Inline name="menu" /> (top right).</Step>
          <Step n="2">Tap <b>Install app</b> or <b>Add to Home screen</b>.</Step>
          <Step n="3">Open SHOO from your home screen.</Step>
        </>
      )}
      {p === 'desktop' && !prompt && (
        <Step n="1">Use the install icon in the address bar, or your browser menu → <b>Install SHOO</b>. Best on a spare phone, though.</Step>
      )}
    </div>
  );
}

function Welcome() {
  const m = model.value;
  const sl = slasher();
  return (
    <div class="stack welcome" style={{ gap: '16px' }}>
      <Panel seed={3} splat={sl ? 'br' : null} radius="28px">
        <div class="stack" style={{ gap: '16px' }}>
          <div class="face"><BotFace mood="happy" /></div>
          <BotSpeech text="Hi. I'm Shoo." pitch={3.2} max={18} />
        </div>
      </Panel>

      <div class="stack" style={{ gap: '8px' }}>
        {sl ? <Title text="SHOO" /> : <DotText text="SHOO" pitch={7} label="SHOO" />}
        <p class="lede">Turn a spare phone into a pest sentry.</p>
        <div class="row" style={{ gap: '14px', marginTop: '4px' }}>
          {PESTS.map((p) => <Pet key={p} kind={p} pitch={2.2} />)}
        </div>
      </div>

      <div class="stack" style={{ gap: '14px' }}>
        {FEATURES.map(([icon, title, text]) => (
          <div class="row" key={title} style={{ gap: '14px', alignItems: 'flex-start' }}>
            <div class="round" style={{ width: '44px', height: '44px' }}><Glyph name={icon} pitch={2.3} /></div>
            <div class="stack" style={{ gap: '6px', paddingTop: '4px' }}>
              <DotText text={title} pitch={2.2} />
              <span class="blurb">{text}</span>
            </div>
          </div>
        ))}
      </div>

      <Panel seed={9}>
        <div class="stack" style={{ gap: '12px' }}>
          <div class="row" style={{ gap: '10px' }}>
            <Glyph name="plus" pitch={2.2} color="var(--red)" />
            <DotText text="ADD TO HOME SCREEN" pitch={2.2} />
          </div>
          <Install />
        </div>
      </Panel>

      <Panel seed={12}><EngineCard compact /></Panel>
    </div>
  );
}

const PAGES = 5;

export function Onboarding() {
  const [page, setPage] = useState(0);
  const last = page === PAGES - 1;
  // Start the ~70 MB model download straight away so it's ready by the camera step.
  useEffect(() => loadModel(), []);
  const next = async () => {
    if (!last) return setPage(page + 1);
    await S.start();
    S.onboarded.value = true;
  };
  const tip = (icon, title, detail) => (
    <div class="row" style={{ gap: '16px' }}>
      <div class="round" style={{ width: '52px', height: '52px' }}><Glyph name={icon} pitch={2.8} /></div>
      <div class="stack" style={{ gap: '8px' }}>
        <DotText text={title} pitch={2.6} />
        <span class="blurb">{detail}</span>
      </div>
    </div>
  );

  return (
    <div class="onboard">
      <div class="dotsbar" aria-label={`Step ${page + 1} of ${PAGES}`}>
        {Array.from({ length: PAGES }, (_, i) => (
          <i key={i} class={i === page ? 'on' : i < page ? 'done' : ''} onClick={() => i < page && setPage(i)} />
        ))}
      </div>
      <div class={`pages ${page === 0 ? 'top' : ''}`} key={page}>
        {page === 0 && <Welcome />}
        {page === 1 && (
          <div class="stack" style={{ gap: '18px', justifyContent: 'flex-start' }}>
            <DotText text="WHO BUGS YOU?" pitch={3.6} />
            <p class="body">Tap to pick. I'll ignore the rest.</p>
            <PetGrid showSound={false} />
            <Caption>I never scare these</Caption>
            <Friends />
          </div>
        )}
        {page === 2 && (
          <div class="stack" style={{ gap: '18px' }}>
            <DotText text="HOW HARD?" pitch={4} />
            <p class="body">You can change this any time in Config.</p>
            <ModePicker />
          </div>
        )}
        {page === 3 && (
          <div class="stack" style={{ gap: '22px' }}>
            <DotText text="SET ME UP" pitch={4} />
            {tip('bolt', 'PLUG IN', 'I run all day. Keep me on power.')}
            {tip('speaker', 'VOLUME UP', 'Turn the device volume up before arming.')}
            {tip('eye', 'AIM', 'Point me at the spot they visit.')}
            {tip('moon', 'STAY OPEN', 'Keep this tab in front. Tap the moon to dim instead of locking.')}
            {tip('eye', 'BEFORE THEY ARRIVE', 'Start me while the spot is empty — I learn what normal looks like.')}
          </div>
        )}
        {page === 4 && (
          <>
            <BotFace mood="surprised" />
            <DotText text="LET ME SEE" pitch={4.4} />
            <p class="body">The camera never leaves this device. Footage and snapshots are stored in this browser only.</p>
          </>
        )}
      </div>
      <button class="primary press" onClick={next}>
        <DotText text={last ? 'ALLOW CAMERA' : page === 0 ? 'GET STARTED' : 'NEXT'} pitch={3.2} color="#000000" />
        <Glyph name="arrow" pitch={3.2} color="#000000" />
      </button>
    </div>
  );
}
