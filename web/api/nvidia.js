// NVIDIA NIM (build.nvidia.com, OpenAI-compatible). Follows the Video Search &
// Summarization pattern: a vision model verifies and captions each event,
// a multimodal embedding makes it searchable, an LLM summarises.
const BASE = process.env.NVIDIA_BASE_URL || 'https://integrate.api.nvidia.com/v1';
const KEY = process.env.NVIDIA_API_KEY;
export const MODELS = {
  vision: [process.env.NVIDIA_VISION_MODEL || 'nvidia/cosmos-reason2-8b', 'meta/llama-3.2-11b-vision-instruct'],
  embed: process.env.NVIDIA_EMBED_MODEL || 'nvidia/llama-nemotron-embed-vl-1b-v2',
  llm: [process.env.NVIDIA_LLM_MODEL || 'nvidia/nemotron-3.5-super-vl-120b-a12b', 'nvidia/llama-3.1-nemotron-70b-instruct'],
};

export const nvidiaStatus = () => ({ connected: !!KEY, models: { vision: MODELS.vision[0], embed: MODELS.embed, llm: MODELS.llm[0] } });

async function post(path, body, timeoutMs = 30_000) {
  if (!KEY) throw new Error('NVIDIA_API_KEY is not set');
  const r = await fetch(BASE + path, {
    method: 'POST',
    headers: { Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json', Accept: 'application/json' },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!r.ok) throw new Error(`NVIDIA ${path} ${r.status}: ${(await r.text()).slice(0, 300)}`);
  return r.json();
}

/// Tries each model in order; returns the first answer.
async function chat(models, messages, { maxTokens = 400, temperature = 0.2 } = {}) {
  let last;
  for (const model of models) {
    try {
      const j = await post('/chat/completions', { model, messages, max_tokens: maxTokens, temperature });
      return { model, text: j.choices?.[0]?.message?.content ?? '' };
    } catch (e) {
      last = e;
    }
  }
  throw last;
}

/// Pulls the last {...} JSON object out of a reply (reasoning models think out loud first).
function lastJSON(text) {
  const clean = text.replace(/<think>[\s\S]*?<\/think>/g, '');
  const matches = clean.match(/\{[\s\S]*?\}/g) ?? [];
  for (let i = matches.length - 1; i >= 0; i--) {
    try { return JSON.parse(matches[i]); } catch { /* keep looking */ }
  }
  return null;
}

/// Second opinion from Cosmos Reason: is the claimed pest really there?
export async function verify(jpegBase64, species) {
  const { model, text } = await chat(MODELS.vision, [
    {
      role: 'system',
      content: 'You check frames from a home pest camera. Be strict and literal about what is visible.',
    },
    {
      role: 'user',
      content: [
        { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${jpegBase64}` } },
        {
          type: 'text',
          text: `A detector says this frame shows a ${species}. Look carefully. Reply with only JSON: ` +
            '{"present": true|false, "animal": "<what animal or person you actually see, or none>", ' +
            '"count": <number>, "description": "<one short sentence describing the scene>"}',
        },
      ],
    },
  ]);
  const j = lastJSON(text) ?? {};
  return {
    model,
    present: j.present === true || j.present === 'true',
    animal: String(j.animal ?? 'unknown').toLowerCase(),
    count: Number(j.count) || 0,
    description: String(j.description ?? text.replace(/<think>[\s\S]*?<\/think>/g, '').trim()).slice(0, 300),
  };
}

/// Multimodal embedding: snapshots as passages, text queries as queries, same space.
export async function embedImage(jpegBase64) {
  const j = await post('/embeddings', {
    model: MODELS.embed, input: [`data:image/jpeg;base64,${jpegBase64}`], input_type: 'passage', modality: 'image', encoding_format: 'float',
  });
  return j.data[0].embedding;
}

export async function embedQuery(text) {
  const j = await post('/embeddings', { model: MODELS.embed, input: [text], input_type: 'query', modality: 'text', encoding_format: 'float' });
  return j.data[0].embedding;
}

/// Nemotron answers "what happened?" from the archive + device log.
export async function answer(question, log) {
  const { model, text } = await chat(MODELS.llm, [
    {
      role: 'system',
      content: 'You are SHOO, a pest-watching camera network. Answer using only the activity log. ' +
        'Two to four short sentences. Mention times and which camera. If nothing relevant, say so.',
    },
    { role: 'user', content: `Activity log:\n${log}\n\nQuestion: ${question}` },
  ], { maxTokens: 300 });
  return { model, text: text.replace(/<think>[\s\S]*?<\/think>/g, '').trim() };
}
