// MyManager: статичний сайт + обмін токенами Google (етап 23).
//
// Браузер сам не може тихо поновлювати доступ до Google Drive, тому:
// 1) сайт отримує від Google одноразовий код і передає його сюди;
// 2) Worker обмінює код на ключ поновлення (потрібен секрет клієнта —
//    він лише в налаштуваннях Worker: `wrangler secret put GOOGLE_CLIENT_SECRET`);
// 3) ключ лежить у cookie, яке не бачить скрипт сторінки;
// 4) сайт просить тут свіжий доступ, коли старий закінчився.

const COOKIE = 'mm_rt';
const COOKIE_PATH = '/api/auth';
// Найдовший строк, який дозволяють браузери (400 днів).
const COOKIE_MAX_AGE = 400 * 24 * 60 * 60;
const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const REVOKE_URL = 'https://oauth2.googleapis.com/revoke';

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (!url.pathname.startsWith('/api/')) return env.ASSETS.fetch(request);
    try {
      return await handleApi(request, env, url);
    } catch (e) {
      return json({ error: 'server_error' }, 500);
    }
  },
};

async function handleApi(request, env, url) {
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  // Лише запити з самого сайту (захист від чужих сторінок).
  if (request.headers.get('Origin') !== url.origin) {
    return json({ error: 'forbidden_origin' }, 403);
  }
  if (!env.GOOGLE_CLIENT_ID || !env.GOOGLE_CLIENT_SECRET) {
    return json({ error: 'not_configured' }, 500);
  }
  switch (url.pathname) {
    case '/api/auth/exchange':
      return exchange(request, env);
    case '/api/auth/token':
      return refresh(request, env);
    case '/api/auth/signout':
      return signout(request, env);
    default:
      return json({ error: 'not_found' }, 404);
  }
}

/** Одноразовий код → доступ + ключ поновлення в cookie. */
async function exchange(request, env) {
  let code;
  try {
    ({ code } = await request.json());
  } catch {
    return json({ error: 'bad_request' }, 400);
  }
  if (typeof code !== 'string' || code.length === 0) {
    return json({ error: 'bad_request' }, 400);
  }
  const res = await google(TOKEN_URL, {
    code,
    client_id: env.GOOGLE_CLIENT_ID,
    client_secret: env.GOOGLE_CLIENT_SECRET,
    // Код отримано у спливному вікні Google (GIS, ux_mode: popup).
    redirect_uri: 'postmessage',
    grant_type: 'authorization_code',
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    return json({ error: 'exchange_failed', detail: data.error ?? null }, 400);
  }
  if (!data.refresh_token) {
    // Google видає ключ лише при першій згоді. Доступ на годину все одно є.
    return json(
      { error: 'no_refresh_token', access_token: data.access_token, expires_in: data.expires_in },
      409,
    );
  }
  return json(
    { access_token: data.access_token, expires_in: data.expires_in },
    200,
    setCookie(data.refresh_token),
  );
}

/** Свіжий доступ за ключем із cookie. */
async function refresh(request, env) {
  const rt = readCookie(request);
  if (!rt) return json({ error: 'no_session' }, 401);
  const res = await google(TOKEN_URL, {
    refresh_token: rt,
    client_id: env.GOOGLE_CLIENT_ID,
    client_secret: env.GOOGLE_CLIENT_SECRET,
    grant_type: 'refresh_token',
  });
  const data = await res.json().catch(() => ({}));
  if (res.ok && data.access_token) {
    return json({ access_token: data.access_token, expires_in: data.expires_in });
  }
  if (data.error === 'invalid_grant') {
    // Ключ відкликано або минув строк (режим Testing — 7 днів).
    return json({ error: 'session_expired' }, 401, clearCookie());
  }
  return json({ error: 'google_unavailable' }, 502);
}

/** Вихід: відкликати ключ у Google і стерти cookie. */
async function signout(request) {
  const rt = readCookie(request);
  if (rt) {
    try {
      await google(REVOKE_URL, { token: rt });
    } catch {
      // Стерти cookie важливіше за відповідь Google.
    }
  }
  return json({ ok: true }, 200, clearCookie());
}

function google(url, params) {
  return fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(params),
  });
}

function readCookie(request) {
  const header = request.headers.get('Cookie') ?? '';
  for (const part of header.split(';')) {
    const [name, ...rest] = part.trim().split('=');
    if (name === COOKIE) return decodeURIComponent(rest.join('='));
  }
  return null;
}

function setCookie(value) {
  return `${COOKIE}=${encodeURIComponent(value)}; Path=${COOKIE_PATH}; Max-Age=${COOKIE_MAX_AGE}; HttpOnly; Secure; SameSite=Strict`;
}

function clearCookie() {
  return `${COOKIE}=; Path=${COOKIE_PATH}; Max-Age=0; HttpOnly; Secure; SameSite=Strict`;
}

function json(body, status = 200, cookie) {
  const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' };
  if (cookie) headers['Set-Cookie'] = cookie;
  return new Response(JSON.stringify(body), { status, headers });
}
