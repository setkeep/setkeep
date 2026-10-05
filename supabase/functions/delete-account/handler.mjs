import { cleanupAccountAvatars } from './avatar_cleanup.mjs';

// No client-supplied user ID is accepted. Secrets exist only in the Edge runtime.
export function createDeleteAccountHandler({ url, anonKey, serviceKey }, fetcher = fetch) {
  const json = (status, body) => Response.json(body, {
    status, headers: { 'Cache-Control': 'no-store' },
  });
  return async (request) => {
    if (request.method !== 'POST') return json(405, { error: 'method_not_allowed' });
    const authorization = request.headers.get('Authorization');
    if (!/^Bearer \S+$/i.test(authorization ?? '')) {
      return json(401, { error: 'unauthorized' });
    }
    if (!url || !anonKey || !serviceKey) {
      return json(503, { error: 'not_configured' });
    }
    let tokenHash;
    let avatarCleanup;
    let avatarCleanupRequired = false;
    let authDeletionStarted = false;
    const rpc = async (name, body) => {
      const response = await fetcher(`${url}/rest/v1/rpc/${name}`, {
        method: 'POST',
        headers: {
          apikey: serviceKey, Authorization: `Bearer ${serviceKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body), signal: AbortSignal.timeout(15000),
      });
      if (!response.ok) throw Error('rpc_unavailable');
      return response.json();
    };
    const completed = () => rpc('account_deletion_receipt', { p_token_hash: tokenHash });
    try {
      // Only a hash is persisted. It lets the SAME credential confirm a lost
      // success response after Auth no longer recognizes the deleted user.
      tokenHash = Array.from(new Uint8Array(await crypto.subtle.digest(
        'SHA-256', new TextEncoder().encode(authorization.replace(/^Bearer /i, '')),
      )), (byte) => byte.toString(16).padStart(2, '0')).join('');
      // Auth verifies the token and checks that the user still exists.
      const verified = await fetcher(`${url}/auth/v1/user`, {
        headers: { apikey: anonKey, Authorization: authorization },
        signal: AbortSignal.timeout(15000),
      });
      if (!verified.ok) {
        if ((verified.status === 401 || verified.status === 403 || verified.status === 404)
            && await completed() === true) return json(200, { deleted: true });
        return json(verified.status >= 500 ? 503 : 401, { error: 'verification_failed' });
      }
      const user = await verified.json();
      if (typeof user.id !== 'string' ||
          !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(user.id)) {
        return json(401, { error: 'unauthorized' });
      }
      user.id = user.id.toLowerCase();
      const preparation = await rpc('account_deletion_prepare', {
        p_user: user.id, p_token_hash: tokenHash,
      });
      if (preparation?.ready !== true) {
        if (preparation?.error === 'tenant_owner_requires_transfer') {
          return json(409, { error: 'tenant_owner_requires_transfer' });
        }
        if (await completed() === true) return json(200, { deleted: true });
        return json(503, { error: 'preparation_failed' });
      }
      // The new DB contract opts into media cleanup. Old DB deployments keep
      // their existing no-Storage flow until the explicit migration is applied.
      if (preparation.avatar_cleanup_required === true) {
        avatarCleanupRequired = true;
        avatarCleanup = await cleanupAccountAvatars({
          url, serviceKey, userId: user.id, tokenHash, rpc, fetcher,
        });
      }
      // Shared records still change only INSIDE the Auth transaction. Storage
      // media is removed first under its upload gate and cannot be rolled back.
      authDeletionStarted = true;
      const deleted = await fetcher(`${url}/auth/v1/admin/users/${user.id}`, {
        method: 'DELETE',
        headers: {
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ should_soft_delete: false }),
        signal: AbortSignal.timeout(15000),
      });
      if (!deleted.ok) {
        await avatarCleanup?.release();
        avatarCleanup = undefined;
        // Concurrent duplicate requests can observe a 404 after the first
        // succeeds. Only the transaction's completion receipt counts as proof.
        if (await completed() === true) return json(200, { deleted: true });
        // Ownership may change between preflight and DELETE.
        const retry = await rpc('account_deletion_prepare', {
          p_user: user.id, p_token_hash: tokenHash,
        });
        if (retry?.error === 'tenant_owner_requires_transfer') {
          return json(409, {
            error: avatarCleanupRequired
              ? 'tenant_owner_requires_transfer_after_avatar_cleanup'
              : 'tenant_owner_requires_transfer',
          });
        }
        return json(502, {
          error: avatarCleanupRequired ? 'deletion_unconfirmed_after_avatar_cleanup' : 'deletion_failed',
        });
      }
      return json(200, { deleted: true });
    } catch (_) {
      await avatarCleanup?.release();
      // Do not leak tokens, upstream responses, or configuration in errors/logs.
      if (_?.code === 'tenant_owner_requires_transfer') {
        return json(409, { error: 'tenant_owner_requires_transfer' });
      }
      return json(503, {
        error: avatarCleanupRequired
          ? authDeletionStarted ? 'deletion_unconfirmed_after_avatar_cleanup' : 'avatar_cleanup_unavailable'
          : 'unavailable',
      });
    }
  };
}
