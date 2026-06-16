const TIME_24H = /\b([01]?\d|2[0-3]):([0-5]\d)\b/g;
const TIME_12H = /\b(1[0-2]|0?[1-9])\s*:\s*([0-5]\d)\s*(am|pm)\b/gi;
const TIME_12H_SHORT = /\b(1[0-2]|0?[1-9])\s*(am|pm)\b/gi;

function to24h(hour, minute, period) {
  let h = hour;
  if (period) {
    const p = period.toLowerCase();
    if (p === 'pm' && h < 12) h += 12;
    if (p === 'am' && h === 12) h = 0;
  }
  return `${String(h).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
}

function extractTimes(text) {
  const found = new Set();

  for (const match of text.matchAll(TIME_12H)) {
    found.add(to24h(Number(match[1]), Number(match[2]), match[3]));
  }

  for (const match of text.matchAll(TIME_12H_SHORT)) {
    const period = match[2];
    let hour = Number(match[1]);
    if (period.toLowerCase() === 'pm' && hour < 12) hour += 12;
    if (period.toLowerCase() === 'am' && hour === 12) hour = 0;
    found.add(to24h(hour, 0));
  }

  for (const match of text.matchAll(TIME_24H)) {
    found.add(to24h(Number(match[1]), Number(match[2])));
  }

  const lower = text.toLowerCase();
  if (found.size === 0) {
    if (/morning|ertalab|sabah/.test(lower)) found.add('08:00');
    if (/noon|lunch|tushlik|afternoon/.test(lower)) found.add('13:00');
    if (/evening|kech|shom/.test(lower)) found.add('20:00');
    if (/night|tun|before\s*bed|uyqu/.test(lower)) found.add('22:00');
  }

  if (found.size === 0 && /twice|2\s*x|ikki\s*marta|2\s*marta/.test(lower)) {
    found.add('08:00');
    found.add('20:00');
  } else if (found.size === 0 && /three|3\s*x|uch\s*marta|3\s*marta/.test(lower)) {
    found.add('08:00');
    found.add('13:00');
    found.add('20:00');
  } else if (found.size === 0 && /once|daily|kunlik|har\s*kun|1\s*marta/.test(lower)) {
    found.add('09:00');
  }

  return [...found].sort();
}

function parseLine(line) {
  const trimmed = line.trim();
  if (!trimmed || trimmed.length < 2) return null;

  const times = extractTimes(trimmed);
  let remainder = trimmed
    .replace(TIME_12H, '')
    .replace(TIME_12H_SHORT, '')
    .replace(TIME_24H, '')
    .replace(/\b(twice|three|once|daily|morning|evening|ertalab|kech|kunlik)\b/gi, '')
    .replace(/[-–—|•]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  if (!remainder) return null;

  const doseMatch = remainder.match(/(\d+\s*(?:mg|mcg|g|ml|IU|iu|tablet|tab|kapsula|kap)?)/i);
  const dose = doseMatch?.[1] ?? '';
  const name = remainder.replace(dose, '').trim() || remainder;

  return {
    name: name.slice(0, 80),
    dose,
    instructions: trimmed,
    times: times.length > 0 ? times : ['09:00'],
  };
}

function parseMedicineText(text) {
  const lines = text
    .split(/\n+/)
    .map((line) => line.trim())
    .filter(Boolean);

  const parsed = lines.map(parseLine).filter(Boolean);
  if (parsed.length > 0) return parsed;

  const times = extractTimes(text);
  if (text.trim()) {
    return [{
      name: text.trim().slice(0, 80),
      dose: '',
      instructions: text.trim(),
      times: times.length > 0 ? times : ['09:00'],
    }];
  }

  return [];
}

async function parseWithOpenAIVision(imageDataUrl, hintText) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error('AI_NOT_CONFIGURED');

  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'system',
          content:
            'Extract medicines from prescription. Return ONLY valid JSON array: [{"name":"","dose":"","instructions":"","times":["08:00"]}]. Times must be 24h HH:MM format.',
        },
        {
          role: 'user',
          content: [
            {
              type: 'text',
              text: hintText
                ? `Prescription notes: ${hintText}\nExtract all medicines and daily times.`
                : 'Extract all medicines and daily reminder times from this prescription image.',
            },
            { type: 'image_url', image_url: { url: imageDataUrl } },
          ],
        },
      ],
      max_tokens: 1200,
    }),
  });

  if (!response.ok) throw new Error('AI_PARSE_FAILED');

  const json = await response.json();
  const content = json.choices?.[0]?.message?.content;
  if (!content) throw new Error('AI_PARSE_FAILED');

  const match = content.match(/\[[\s\S]*\]/);
  if (!match) throw new Error('AI_PARSE_FAILED');

  const items = JSON.parse(match[0]);
  return items
    .filter((item) => item?.name)
    .map((item) => ({
      name: String(item.name).trim(),
      dose: String(item.dose ?? '').trim(),
      instructions: String(item.instructions ?? '').trim(),
      times: Array.isArray(item.times) && item.times.length > 0
        ? item.times.map((t) => String(t).trim())
        : ['09:00'],
    }));
}

export async function parsePrescriptionWithAI({ text, imageDataUrl }) {
  if (text?.trim()) {
    const fromText = parseMedicineText(text);
    if (fromText.length > 0) return fromText;
  }

  if (imageDataUrl && process.env.OPENAI_API_KEY) {
    return parseWithOpenAIVision(imageDataUrl, text);
  }

  if (text?.trim()) return parseMedicineText(text);

  throw new Error('AI_NOT_CONFIGURED');
}
