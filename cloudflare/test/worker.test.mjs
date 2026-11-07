// Тести Worker без справжнього Google: node --test test/
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/worker.js';

const SITE = 'https://mm.example.workers.dev';
const env = {
  GOOGLE_CLIENT_ID: 'cid',
  GOOGLE_CLIENT_SECRET: 'secret',
  ASSETS: { fetch: async () => new Response('site', { status: 200 }) },
};

let calls;
let googleReply;
beforeEach(() => {
  calls = [];
  googleReply = () => Response.json({ access_token: 'at', expires_in: 3599, refresh_token: 'rt' });
  globalThis.fetch = async (url, init) => {
    calls.push({ url, params: Object.fromEntries(new URLSearchParams(init.body)) });
    return googleReply(url);
  };
});

function api(path, { body, cookie, origin = SITE, method = 'POST' } = {}) {
  const headers = { Origin: origin, 'Content-Type': 'application/json' };
  if (cookie) headers.Cookie = cookie;
  return worker.fetch(
    new Request(SITE + path, { method, headers, body: body && JSON.stringify(body) }),
    env,
  );
}

test('сайт віддається без участі Google', async () => {
  const res = await worker.fetch(new Request(SITE + '/'), env);
  assert.equal(await res.text(), 'site');
  assert.equal(calls.length, 0);
});

test('обмін коду: доступ у відповіді, ключ — лише в HttpOnly cookie', async () => {
  const res = await api('/api/auth/exchange', { body: { code: 'c1' } });
  assert.equal(res.status, 200);
  const data = await res.json();
  assert.deepEqual(data, { access_token: 'at', expires_in: 3599 });
  const cookie = res.headers.get('Set-Cookie');
  assert.match(cookie, /^mm_rt=rt;/);
  for (const flag of ['HttpOnly', 'Secure', 'SameSite=Strict', 'Path=/api/auth']) {
    assert.ok(cookie.includes(flag), flag);
  }
  assert.equal(calls[0].url, 'https://oauth2.googleapis.com/token');
  assert.deepEqual(calls[0].params, {
    code: 'c1',
    client_id: 'cid',
    client_secret: 'secret',
    redirect_uri: 'postmessage',
    grant_type: 'authorization_code',
  });
});

test('Google не дав ключ поновлення — 409, cookie немає', async () => {
  googleReply = () => Response.json({ access_token: 'at', expires_in: 3599 });
  const res = await api('/api/auth/exchange', { body: { code: 'c1' } });
  assert.equal(res.status, 409);
  assert.equal((await res.json()).error, 'no_refresh_token');
  assert.equal(res.headers.get('Set-Cookie'), null);
});

test('невдалий обмін — 400', async () => {
  googleReply = () => Response.json({ error: 'invalid_grant' }, { status: 400 });
  const res = await api('/api/auth/exchange', { body: { code: 'bad' } });
  assert.equal(res.status, 400);
});

test('поновлення за cookie', async () => {
  googleReply = () => Response.json({ access_token: 'at2', expires_in: 3599 });
  const res = await api('/api/auth/token', { cookie: 'x=1; mm_rt=rt' });
  assert.equal(res.status, 200);
  assert.equal((await res.json()).access_token, 'at2');
  assert.deepEqual(calls[0].params, {
    refresh_token: 'rt',
    client_id: 'cid',
    client_secret: 'secret',
    grant_type: 'refresh_token',
  });
});

test('без cookie — 401 і без запиту до Google', async () => {
  const res = await api('/api/auth/token');
  assert.equal(res.status, 401);
  assert.equal(calls.length, 0);
});

test('ключ відкликано / минув строк — 401 і cookie стерто', async () => {
  googleReply = () => Response.json({ error: 'invalid_grant' }, { status: 400 });
  const res = await api('/api/auth/token', { cookie: 'mm_rt=rt' });
  assert.equal(res.status, 401);
  assert.match(res.headers.get('Set-Cookie'), /Max-Age=0/);
});

test('Google недоступний — 502, cookie лишається', async () => {
  googleReply = () => new Response('oops', { status: 503 });
  const res = await api('/api/auth/token', { cookie: 'mm_rt=rt' });
  assert.equal(res.status, 502);
  assert.equal(res.headers.get('Set-Cookie'), null);
});

test('вихід відкликає ключ і стирає cookie', async () => {
  googleReply = () => new Response('', { status: 200 });
  const res = await api('/api/auth/signout', { cookie: 'mm_rt=rt' });
  assert.equal(res.status, 200);
  assert.equal(calls[0].url, 'https://oauth2.googleapis.com/revoke');
  assert.deepEqual(calls[0].params, { token: 'rt' });
  assert.match(res.headers.get('Set-Cookie'), /Max-Age=0/);
});

test('чужий сайт — 403', async () => {
  const res = await api('/api/auth/token', { cookie: 'mm_rt=rt', origin: 'https://evil.example' });
  assert.equal(res.status, 403);
  assert.equal(calls.length, 0);
});

test('лише POST', async () => {
  const res = await api('/api/auth/token', { method: 'GET' });
  assert.equal(res.status, 405);
});

test('без секрету — зрозуміла помилка', async () => {
  const res = await worker.fetch(
    new Request(SITE + '/api/auth/token', { method: 'POST', headers: { Origin: SITE } }),
    { ...env, GOOGLE_CLIENT_SECRET: undefined },
  );
  assert.equal(res.status, 500);
  assert.equal((await res.json()).error, 'not_configured');
});
