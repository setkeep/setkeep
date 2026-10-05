const bucket = 'friend-avatars';
const pageSize = 100;
const maxPages = 10;

// Only the UUID verified by Auth reaches here. No client paths are accepted.
export async function cleanupAccountAvatars({ url, serviceKey, userId, tokenHash, rpc, fetcher }) {
  const attempt = crypto.randomUUID();
  const params = { p_user: userId, p_token_hash: tokenHash, p_attempt: attempt };
  let claimed = false;
  const release = async () => {
    if (!claimed) return;
    try { await rpc('account_avatar_cleanup_release', params); } catch (_) {}
  };
  const lease = async () => {
    const result = await rpc('account_avatar_cleanup_check', params);
    if (result?.ready !== true) throw Error('avatar_cleanup_lease_unavailable');
  };
  const storage = async (method, suffix, body) => {
    const response = await fetcher(`${url}/storage/v1/object/${suffix}/${bucket}`, {
      method,
      headers: {
        apikey: serviceKey, Authorization: `Bearer ${serviceKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body), signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) throw Error('avatar_storage_unavailable');
    return response;
  };
  try {
    const result = await rpc('account_avatar_cleanup_begin', params);
    if (result?.ready !== true) {
      const error = Error('avatar_cleanup_not_ready');
      if (result?.error === 'tenant_owner_requires_transfer') error.code = result.error;
      throw error;
    }
    claimed = true;
    // Re-list offset zero after each removal. Deleted pages must not shift past
    // an increasing offset. The last read is required even at the page limit.
    for (let page = 0; page <= maxPages; page++) {
      await lease();
      const response = await storage('POST', 'list', {
        prefix: `${userId}/`, limit: pageSize, offset: 0,
        sortBy: { column: 'name', order: 'asc' },
      });
      const objects = await response.json();
      if (!Array.isArray(objects) || objects.length > pageSize) throw Error('invalid_avatar_listing');
      if (objects.length === 0) {
        const confirmed = await rpc('account_avatar_cleanup_confirm', params);
        if (confirmed?.ready !== true) throw Error('avatar_cleanup_not_confirmed');
        return { release };
      }
      if (page === maxPages) throw Error('avatar_cleanup_page_limit');
      // A folder, a foreign path or an unexpected file requires manual review.
      // Refuse the entire page before deleting any object in that page.
      if (objects.some(item => !item || typeof item.id !== 'string' || !item.id
          || typeof item.name !== 'string' || !/^[0-9]+\.png$/.test(item.name))) {
        throw Error('unsupported_avatar_object');
      }
      const prefixes = objects.map(item => `${userId}/${item.name}`);
      if (new Set(prefixes).size !== prefixes.length) throw Error('invalid_avatar_listing');
      await lease();
      const removed = await fetcher(`${url}/storage/v1/object/${bucket}`, {
        method: 'DELETE',
        headers: {
          apikey: serviceKey, Authorization: `Bearer ${serviceKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ prefixes }), signal: AbortSignal.timeout(15000),
      });
      if (!removed.ok) throw Error('avatar_storage_unavailable');
    }
    throw Error('avatar_cleanup_not_confirmed');
  } catch (error) {
    // Keep the upload gate closed. A later verified request reclaims the lease.
    await release();
    throw error;
  }
}
