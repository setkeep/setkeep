import test from 'node:test';
import assert from 'node:assert/strict';
import { createDeleteAccountHandler } from './handler.mjs';

const config = { url: 'https://example.test', anonKey: 'public-test', serviceKey: 'secret-test' };
const userId = '11111111-1111-4111-8111-111111111111';
const request = (body = {}, token = 'user-token') => new Request('https://example.test/delete-account', {
  method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: JSON.stringify(body),
});
const hash = async (value) => Array.from(new Uint8Array(await crypto.subtle.digest(
  'SHA-256', new TextEncoder().encode(value))), b => b.toString(16).padStart(2, '0')).join('');

function backend({ verify = 200, preparation = { ready: true }, deletion = 200,
  receipt = false, throwDelete = false, throwPrepare = false } = {}) {
  const calls = [];
  let stored = receipt;
  const fetcher = async (url, options) => {
    calls.push({ url, options });
    if (url.endsWith('/auth/v1/user')) return Response.json({ id: userId }, { status: verify });
    assert.equal(options.headers.Authorization, 'Bearer secret-test');
    const body = JSON.parse(options.body);
    if (url.endsWith('/account_deletion_prepare')) {
      assert.deepEqual(Object.keys(body).sort(), ['p_token_hash', 'p_user']);
      assert.equal(body.p_user, userId);
      assert.equal(body.p_token_hash, await hash('user-token'));
      if (throwPrepare) throw Error('secret-test');
      return Response.json(preparation);
    }
    if (url.endsWith('/account_deletion_receipt')) {
      assert.deepEqual(body, { p_token_hash: await hash('user-token') });
      return Response.json(stored);
    }
    assert.equal(url, `${config.url}/auth/v1/admin/users/${userId}`);
    assert.equal(options.method, 'DELETE');
    assert.deepEqual(body, { should_soft_delete: false });
    if (throwDelete) throw Error('secret-test');
    if (deletion === 200) stored = true;
    return Response.json({ error: 'secret-test' }, { status: deletion });
  };
  return { calls, fetcher, markCompleted: () => { stored = true; } };
}

test('rejects absent credentials, non POST and missing configuration without upstream calls', async () => {
  const fail = () => assert.fail('unexpected fetch');
  assert.equal((await createDeleteAccountHandler(config, fail)(new Request(config.url, { method: 'POST' }))).status, 401);
  assert.equal((await createDeleteAccountHandler(config, fail)(new Request(config.url))).status, 405);
  assert.equal((await createDeleteAccountHandler({}, fail)(request())).status, 503);
});

test('ignores forged user ID, receipt and Premium claims; persists only token hash', async () => {
  const b = backend();
  const response = await createDeleteAccountHandler(config, b.fetcher)(request({ user_id: 'other', deleted: true, token_hash: 'forged', premium: false }));
  assert.deepEqual(await response.json(), { deleted: true });
  assert.equal(b.calls.length, 3);
  assert.equal(b.calls[0].options.headers.Authorization, 'Bearer user-token');
  assert.ok(!b.calls[1].options.body.includes('user-token'));
});

test('owner has explicit 409 and Auth DELETE never starts', async () => {
  const b = backend({ preparation: { ready: false, error: 'tenant_owner_requires_transfer' } });
  const response = await createDeleteAccountHandler(config, b.fetcher)(request());
  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { error: 'tenant_owner_requires_transfer' });
  assert.equal(b.calls.length, 2);
});

test('unrecognized credentials cannot delete or use an uncompleted receipt', async () => {
  for (const verify of [401, 403, 404, 500]) {
    const b = backend({ verify });
    const response = await createDeleteAccountHandler(config, b.fetcher)(request());
    assert.equal(response.status, verify === 500 ? 503 : 401);
    assert.ok(!b.calls.some(c => c.options.method === 'DELETE'));
  }
});

test('malformed verified user fails closed', async () => {
  let calls = 0;
  const response = await createDeleteAccountHandler(config, async () => {
    calls++; return Response.json({ id: '../other' });
  })(request());
  assert.equal(response.status, 401);
  assert.equal(calls, 1);
});

test('lost response is confirmed only by this credential completion receipt', async () => {
  const b = backend({ verify: 401, receipt: true });
  assert.equal((await createDeleteAccountHandler(config, b.fetcher)(request())).status, 200);
  assert.equal(b.calls.length, 2);
  assert.ok(!b.calls.some(c => c.options.method === 'DELETE'));
});

test('duplicate concurrent request with Auth 404 succeeds only after receipt', async () => {
  const b = backend({ deletion: 404, receipt: true });
  assert.equal((await createDeleteAccountHandler(config, b.fetcher)(request())).status, 200);
});

test('transient delete failure can retry; no premature success or secret exposure', async () => {
  const first = backend({ deletion: 500 });
  const response = await createDeleteAccountHandler(config, first.fetcher)(request());
  assert.equal(response.status, 502);
  assert.ok(!(await response.text()).includes('secret-test'));
  const retry = backend();
  assert.equal((await createDeleteAccountHandler(config, retry.fetcher)(request())).status, 200);
});

test('transport and preparation failure never start destructive fallback', async () => {
  for (const options of [{ throwPrepare: true }, { throwDelete: true }]) {
    const b = backend(options);
    const response = await createDeleteAccountHandler(config, b.fetcher)(request());
    assert.equal(response.status, 503);
    assert.ok(!(await response.text()).includes('secret-test'));
    if (options.throwPrepare) assert.equal(b.calls.length, 2);
  }
});

test('timeout after committed delete is safely retried against the receipt', async () => {
  const b = backend({ throwDelete: true });
  const handler = createDeleteAccountHandler(config, b.fetcher);
  assert.equal((await handler(request())).status, 503);
  b.markCompleted();
  const retry = backend({ verify: 401, receipt: true });
  assert.deepEqual(await (await createDeleteAccountHandler(config, retry.fetcher)(request())).json(), { deleted: true });
});

test('ownership race between preflight and Auth delete returns block reason', async () => {
  const b = backend({ deletion: 500 });
  const fetcher = async (url, options) => {
    if (url.endsWith('/account_deletion_prepare') && b.calls.some(c => c.options.method === 'DELETE')) {
      return Response.json({ ready: false, error: 'tenant_owner_requires_transfer' });
    }
    return b.fetcher(url, options);
  };
  assert.equal((await createDeleteAccountHandler(config, fetcher)(request())).status, 409);
});
