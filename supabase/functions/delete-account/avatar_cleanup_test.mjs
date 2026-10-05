import test from 'node:test';
import assert from 'node:assert/strict';
import { cleanupAccountAvatars } from './avatar_cleanup.mjs';
import { createDeleteAccountHandler } from './handler.mjs';

const userId = '11111111-1111-4111-8111-111111111111';
const config = { url: 'https://example.test', serviceKey: 'test-service', anonKey: 'test-public' };
function fixture({ files = ['1.png'], malicious, deleteStatus = 200, confirm = true,
  lease = true, begin = { ready: true }, adminStatus = 200, stuck = false, ownerAfterCleanup = false } = {}) {
  let stored = files.map((name, i) => ({ name, id: `synthetic-${i}` }));
  const calls = [];
  const rpc = async (name, params) => {
    calls.push({ name, params });
    if (name === 'account_deletion_prepare') {
      if (ownerAfterCleanup && calls.filter(c => c.name === name).length > 1) {
        return { ready: false, error: 'tenant_owner_requires_transfer' };
      }
      return { ready: true, avatar_cleanup_required: true };
    }
    if (name === 'account_deletion_receipt') return false;
    assert.equal(params.p_user, userId);
    assert.match(params.p_attempt, /^[0-9a-f-]{36}$/);
    if (name === 'account_avatar_cleanup_begin') return begin;
    if (name === 'account_avatar_cleanup_check') return { ready: lease };
    if (name === 'account_avatar_cleanup_confirm') return { ready: confirm && stored.length === 0 };
    assert.equal(name, 'account_avatar_cleanup_release');
    return true;
  };
  const fetcher = async (url, options) => {
    if (url.endsWith('/auth/v1/user')) return Response.json({ id: userId });
    if (url.includes('/rest/v1/rpc/')) return Response.json(await rpc(url.split('/').at(-1), JSON.parse(options.body)));
    const body = JSON.parse(options.body);
    assert.equal(options.headers.Authorization, `Bearer ${config.serviceKey}`);
    calls.push({ url, method: options.method, body });
    if (url.endsWith('/storage/v1/object/list/friend-avatars')) {
      assert.equal(body.prefix, `${userId}/`);
      assert.equal(body.offset, 0);
      return Response.json(malicious ?? stored.slice(0, body.limit));
    }
    if (url.endsWith('/storage/v1/object/friend-avatars')) {
      assert.equal(options.method, 'DELETE');
      for (const path of body.prefixes) assert.match(path, new RegExp(`^${userId}/[0-9]+\\.png$`));
      if (deleteStatus === 200 && !stuck) stored = stored.filter(item => !body.prefixes.includes(`${userId}/${item.name}`));
      return Response.json({}, { status: deleteStatus });
    }
    assert.equal(url, `${config.url}/auth/v1/admin/users/${userId}`);
    assert.equal(options.method, 'DELETE');
    assert.deepEqual(body, { should_soft_delete: false });
    return Response.json({}, { status: adminStatus });
  };
  return { rpc, fetcher, calls, get stored() { return stored; } };
}
const run = (f) => cleanupAccountAvatars({ ...config, userId, tokenHash: 'test-hash', rpc: f.rpc, fetcher: f.fetcher });
const request = () => new Request(config.url, {
  method: 'POST', headers: { Authorization: 'Bearer synthetic-user-token' },
  body: JSON.stringify({ user_id: 'forged-other-owner', prefixes: ['other-user/1.png'] }),
});

test('current and orphaned photos are paginated and removed only within the verified user namespace', async () => {
  const f = fixture({ files: Array.from({ length: 101 }, (_, i) => `${i + 1}.png`) });
  await run(f);
  assert.equal(f.stored.length, 0);
  assert.equal(f.calls.filter(c => c.method === 'DELETE').length, 2);
  assert.equal(f.calls.filter(c => c.url?.includes('/object/list/')).length, 3);
  assert.equal(f.calls.at(-1).name, 'account_avatar_cleanup_confirm');
});
test('unexpected names, paths, folders and malformed listing fail before deletion', async () => {
  for (const malicious of [[{ id: 'x', name: '../other.png' }], [{ id: 'x', name: 'other-user/1.png' }],
    [{ id: null, name: 'folder' }], [{ id: 'x', name: 'notes.txt' }], {}]) {
    const f = fixture({ malicious });
    await assert.rejects(run(f));
    assert.equal(f.calls.filter(c => c.method === 'DELETE').length, 0);
    assert.equal(f.calls.at(-1).name, 'account_avatar_cleanup_release');
  }
});
test('failed removal releases only the lease and is safely retried', async () => {
  const failed = fixture({ deleteStatus: 503 });
  await assert.rejects(run(failed));
  assert.equal(failed.stored.length, 1);
  assert.equal(failed.calls.at(-1).name, 'account_avatar_cleanup_release');
  const retry = fixture({ files: failed.stored.map(x => x.name) });
  await run(retry);
  assert.equal(retry.stored.length, 0);
});
test('confirmation failure and a lost lease never allow Auth deletion', async () => {
  for (const flags of [{ confirm: false }, { lease: false }]) {
    const f = fixture(flags);
    const response = await createDeleteAccountHandler(config, f.fetcher)(request());
    assert.equal(response.status, 503);
    assert.equal(f.calls.some(c => c.url?.includes('/auth/v1/admin/')), false);
    assert.equal(f.calls.at(-1).name, 'account_avatar_cleanup_release');
    assert.equal(JSON.stringify(await response.json()).includes(config.serviceKey), false);
  }
});
test('a concurrent lease cannot be stolen or released by a second attempt', async () => {
  const f = fixture({ begin: { ready: false, error: 'avatar_cleanup_in_progress' } });
  await assert.rejects(run(f));
  assert.equal(f.calls.length, 1);
});
test('bounded removal stops a non-progressing backend and keeps Auth intact', async () => {
  const f = fixture({ stuck: true });
  const response = await createDeleteAccountHandler(config, f.fetcher)(request());
  assert.equal(response.status, 503);
  assert.equal(f.calls.filter(c => c.method === 'DELETE').length, 10);
  assert.equal(f.calls.some(c => c.url?.includes('/auth/v1/admin/')), false);
});
test('Auth delete follows confirmed media cleanup and forged IDs cannot change the owner', async () => {
  const f = fixture();
  const response = await createDeleteAccountHandler(config, f.fetcher)(request());
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { deleted: true });
  const confirmAt = f.calls.findIndex(c => c.name === 'account_avatar_cleanup_confirm');
  const authAt = f.calls.findIndex(c => c.url?.includes('/auth/v1/admin/'));
  assert.ok(confirmAt >= 0 && authAt > confirmAt);
});
test('failed Auth deletion releases media lease without reporting account deletion success', async () => {
  const f = fixture({ adminStatus: 502 });
  const response = await createDeleteAccountHandler(config, f.fetcher)(request());
  assert.equal(response.status, 502);
  assert.equal(f.calls.some(c => c.name === 'account_avatar_cleanup_release'), true);
  assert.equal((await response.json()).deleted, undefined);
});
test('owner race before media claim returns transfer requirement without Storage calls', async () => {
  const f = fixture({ begin: { ready: false, error: 'tenant_owner_requires_transfer' } });
  const response = await createDeleteAccountHandler(config, f.fetcher)(request());
  assert.equal(response.status, 409);
  assert.equal(f.calls.some(c => c.url?.includes('/storage/')), false);
});
test('owner race after media removal never claims that every shared item is unchanged', async () => {
  const f = fixture({ adminStatus: 502, ownerAfterCleanup: true });
  const response = await createDeleteAccountHandler(config, f.fetcher)(request());
  assert.equal(response.status, 409);
  assert.equal((await response.json()).error, 'tenant_owner_requires_transfer_after_avatar_cleanup');
});
