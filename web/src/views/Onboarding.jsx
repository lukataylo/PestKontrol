import { useState } from 'preact/hooks';
import { BotFace, BotSpeech } from '../bot.jsx';
import { DotText, Glyph } from '../dot.jsx';
import { loadModel } from '../detector.js';
import * as S from '../sentry.js';
import { PetGrid, Friends, ModePicker } from './Config.jsx';
import { Caption } from '../ui.jsx';

const PAGES = 5;

export function Onboarding() {
  const [page, setPage] = useState(0);
  const last = page === PAGES - 1;
  const next = async () => {
    if (page === 0) loadModel(); // start the ~70 MB model download while they read
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
      <div class="pages" key={page}>
        {page === 0 && (
          <>
            <BotFace mood="happy" />
            <BotSpeech text="Hi. I'm Shoo." pitch={4.4} max={13} />
            <p class="body">I watch for pests and scare them off with sound. Everything I see stays on this device — the AI runs right here in your browser.</p>
          </>
        )}
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
            {tip('arrow', 'ADD TO HOME SCREEN', 'Share → Add to Home Screen for full screen and offline use.')}
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
        <DotText text={last ? 'ALLOW CAMERA' : 'NEXT'} pitch={3.2} color="#000000" />
        <Glyph name="arrow" pitch={3.2} color="#000000" />
      </button>
    </div>
  );
}
