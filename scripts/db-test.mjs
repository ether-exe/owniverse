#!/usr/bin/env node
/**
 * Owniverse — M0 security suite.
 *
 * Black-box: every assertion goes through the same HTTP surface an attacker
 * uses. No local Postgres required. SPEC §7.1 (matrix), §7.3 (threats) and the
 * registry invariant of §6.3 are proven here as observed behaviour.
 *
 * What this does NOT prove: policy text, or anything below the wire.
 *
 * Required environment:
 *   SUPABASE_URL                 https://<ref>.supabase.co
 *   SUPABASE_PUBLISHABLE_KEY     sb_publishable_...   (client-safe)
 *   SUPABASE_ACCESS_TOKEN        sbp_...              (management, admin + cleanup)
 *   SUPABASE_PROJECT_REF         <ref>
 *
 * Nothing is written to disk. The service key is fetched at runtime and only
 * ever held in memory.
 */

const URL_BASE = required('SUPABASE_URL').replace(/\/+$/, '');
const MGMT_BASE = process.env.SUPABASE_MGMT_URL || 'https://api.supabase.com';
const ANON = required('SUPABASE_PUBLISHABLE_KEY');
const PAT = required('SUPABASE_ACCESS_TOKEN');
const REF = required('SUPABASE_PROJECT_REF');

const RUN = Date.now().toString(36);
const PASSWORD = 'owniverse-suite-password';
const results = [];
let clientKey; // anon/publishable
let adminKey; // service_role — memory only, never printed

function required(name) {
  const v = process.env[name];
  if (!v) {
    console.error(`missing env: ${name}`);
    process.exit(2);
  }
  return v;
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

async function call(path, { method = 'GET', token, key, body, headers = {}, base = URL_BASE } = {}) {
  const h = { ...headers };
  if (key) h['apikey'] = key;
  if (token) h['Authorization'] = `Bearer ${token}`;
  if (body !== undefined) h['Content-Type'] = 'application/json';

  const res = await fetch(`${base}${path}`, {
    method,
    headers: h,
    body: body === undefined ? undefined : JSON.stringify(body),
  });

  const text = await res.text();
  let json;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = null;
  }
  return { status: res.status, json, text };
}

const rpc = (name, args, opts = {}) =>
  call(`/rest/v1/rpc/${name}`, { method: 'POST', body: args, ...opts });

// ---------------------------------------------------------------------------
// Assertions
// ---------------------------------------------------------------------------

function record(ok, name, detail) {
  results.push({ ok, name, detail });
  const mark = ok ? 'ok  ' : 'FAIL';
  const line = `${mark} ${String(results.length).padStart(2)}. ${name}`;
  console.log(ok ? line : `${line}\n         ${detail}`);
}

function expect(name, cond, detail = '') {
  record(Boolean(cond), name, detail);
}

function expectError(name, res, needle) {
  const msg = res.json?.message ?? res.text ?? '';
  const ok = res.status >= 400 && String(msg).includes(needle);
  record(ok, name, `expected "${needle}", got ${res.status} ${msg}`.slice(0, 300));
}

function expectDenied(name, res) {
  const ok = res.status === 401 || res.status === 403;
  record(ok, name, `expected 401/403, got ${res.status} ${res.text}`.slice(0, 300));
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

async function fetchKeys() {
  const res = await call(`/v1/projects/${REF}/api-keys`, { token: PAT, base: MGMT_BASE });
  if (res.status !== 200) throw new Error(`api-keys: ${res.status} ${res.text}`);

  const keys = res.json;
  // Legacy service_role is a JWT, which the auth admin API accepts as a bearer.
  const service = keys.find((k) => k.name === 'service_role' && k.type === 'legacy');
  const anon = keys.find((k) => k.type === 'publishable') ?? keys.find((k) => k.name === 'anon');
  if (!service) throw new Error('no service_role key on this project');
  if (!anon) throw new Error('no publishable/anon key on this project');

  // The publishable key from env is the intended client credential; fall back
  // to the project's own if it was not supplied.
  adminKey = service.api_key;
  clientKey = ANON || anon.api_key;
}

async function createUser(label) {
  const email = `suite-${RUN}-${label}@owniverse.test`;
  const res = await call('/auth/v1/admin/users', {
    method: 'POST',
    key: adminKey,
    token: adminKey,
    body: { email, password: PASSWORD, email_confirm: true },
  });
  if (res.status >= 300) throw new Error(`create ${label}: ${res.status} ${res.text}`);

  const signIn = await call('/auth/v1/token?grant_type=password', {
    method: 'POST',
    key: clientKey,
    body: { email, password: PASSWORD },
  });
  if (signIn.status !== 200) throw new Error(`sign in ${label}: ${signIn.status} ${signIn.text}`);

  return { id: res.json.id, email, token: signIn.json.access_token };
}

async function deleteUser(id) {
  await call(`/auth/v1/admin/users/${id}`, {
    method: 'DELETE',
    key: adminKey,
    token: adminKey,
  });
}

// ---------------------------------------------------------------------------
// Suite
// ---------------------------------------------------------------------------

async function run() {
  await fetchKeys();

  const alice = await createUser('alice');
  const bob = await createUser('bob');
  const carol = await createUser('carol');
  const dave = await createUser('dave'); // never completes onboarding

  const nameAlice = `alice-${RUN}`;
  const nameBob = `bob-${RUN}`;
  const users = [alice, bob, carol, dave];

  try {
    // --- profile / onboarding -------------------------------------------
    const free = await rpc('username_available', { p_username: nameAlice }, { key: clientKey });
    expect('anon can ask whether a username is free', free.status === 200 && free.json === true, free.text);

    const setAlice = await rpc(
      'update_profile',
      { p_name: 'Alice', p_username: nameAlice, p_avatar_path: null, p_email_public: false, p_social: {} },
      { key: clientKey, token: alice.token },
    );
    expect('owner completes their profile', setAlice.status === 200 && setAlice.json?.username === nameAlice, setAlice.text);

    const taken = await rpc('username_available', { p_username: nameAlice }, { key: clientKey });
    expect('a claimed username is no longer available', taken.json === false, taken.text);

    await rpc(
      'update_profile',
      { p_name: 'Bob', p_username: nameBob, p_avatar_path: null, p_email_public: false, p_social: {} },
      { key: clientKey, token: bob.token },
    );

    const incomplete = await rpc(
      'create_space',
      { p_title: 'Nope', p_slug: 'nope' },
      { key: clientKey, token: dave.token },
    );
    expectError('a half-built profile cannot create content', incomplete, 'profile_incomplete');

    // --- §7.1 direct table access ---------------------------------------
    const anonSpaces = await call('/rest/v1/spaces', { key: clientKey });
    expect('anon reads no rows from spaces', anonSpaces.status === 200 && Array.isArray(anonSpaces.json) && anonSpaces.json.length === 0, anonSpaces.text);

    const anonGlobal = await call('/rest/v1/global', { key: clientKey });
    expect('anon reads no rows from global', anonGlobal.status === 200 && Array.isArray(anonGlobal.json) && anonGlobal.json.length === 0, anonGlobal.text);

    const anonInsert = await call('/rest/v1/spaces', {
      method: 'POST',
      key: clientKey,
      body: { owner_id: alice.id, title: 'Forged', slug: 'forged' },
    });
    expectDenied('anon cannot insert into spaces', anonInsert);

    const ownerInsert = await call('/rest/v1/spaces', {
      method: 'POST',
      key: clientKey,
      token: alice.token,
      body: { owner_id: alice.id, title: 'Forged', slug: 'forged' },
    });
    expectDenied('owner cannot insert into spaces directly (D35)', ownerInsert);

    // --- create / registry ----------------------------------------------
    const created = await rpc(
      'create_space',
      { p_title: 'My Journey', p_slug: 'my-journey' },
      { key: clientKey, token: alice.token },
    );
    expect('owner creates a Space', created.status === 200 && created.json?.id, created.text);
    const spaceId = created.json?.id;

    const sameSlugBob = await rpc(
      'create_space',
      { p_title: 'My Journey', p_slug: 'my-journey' },
      { key: clientKey, token: bob.token },
    );
    expect('titles are per-user, not platform-wide (D18)', sameSlugBob.status === 200, sameSlugBob.text);

    const duplicate = await rpc(
      'create_space',
      { p_title: 'Another', p_slug: 'my-journey' },
      { key: clientKey, token: alice.token },
    );
    expectError('the same owner cannot claim a slug twice', duplicate, 'slug_taken');

    const bobSees = await call('/rest/v1/spaces?select=id', { key: clientKey, token: bob.token });
    const bobIds = (bobSees.json ?? []).map((r) => r.id);
    expect("an owner cannot see another owner's Space", !bobIds.includes(spaceId) && bobIds.length === 1, bobSees.text);

    // --- blocks / autosave ----------------------------------------------
    const blocks = [
      { id: 'a', type: 'text', v: 1, data: { text: 'above the threshold' } },
      { id: 'd', type: 'door', v: 1, data: {} },
      { id: 'b', type: 'text', v: 1, data: { text: 'SECRET BELOW THE DOOR' } },
    ];

    const saved = await rpc(
      'save_blocks',
      { p_space_id: spaceId, p_blocks: blocks, p_version: 1 },
      { key: clientKey, token: alice.token },
    );
    expect('autosave writes and bumps the version', saved.json?.status === 'saved' && saved.json?.version === 2, saved.text);

    const stale = await rpc(
      'save_blocks',
      { p_space_id: spaceId, p_blocks: blocks, p_version: 1 },
      { key: clientKey, token: alice.token },
    );
    expect('a stale write returns conflict, not a silent loss', stale.json?.status === 'conflict' && stale.json?.version === 2, stale.text);

    const noAlt = await rpc(
      'save_blocks',
      {
        p_space_id: spaceId,
        p_blocks: [{ id: 'i', type: 'image', v: 1, data: { media_id: '00000000-0000-0000-0000-000000000000', alt: '' } }],
        p_version: 2,
      },
      { key: clientKey, token: alice.token },
    );
    expectError('an image without alt text is refused', noAlt, 'image_alt_required');

    // --- publish and the gate -------------------------------------------
    const beforePublish = await rpc('space_head', { p_handle: nameAlice, p_slug: 'my-journey' }, { key: clientKey });
    expect('an unpublished Space is not public', beforePublish.json?.found === false, beforePublish.text);

    const published = await rpc('publish_space', { p_space_id: spaceId }, { key: clientKey, token: alice.token });
    // Door + everything at or below it is the gated slice: 1 public, 2 gated.
    expect('publish succeeds and splits at the door', published.json?.status === 'published' && published.json?.has_door === true && published.json?.public_blocks === 1 && published.json?.gated_blocks === 2, published.text);

    const head = await rpc('space_head', { p_handle: nameAlice, p_slug: 'my-journey' }, { key: clientKey });
    const headText = JSON.stringify(head.json);
    expect('anon reaches the published page', head.json?.found === true && head.json?.title === 'My Journey', head.text);
    expect('THE GATE: gated block is absent from the anon payload', !headText.includes('SECRET BELOW THE DOOR'), headText.slice(0, 300));
    expect('the block above the door is present for anon', headText.includes('above the threshold'), headText.slice(0, 300));
    expect('counters start at zero', head.json?.readers === 0 && head.json?.likes === 0, head.text);

    // space_enter is not granted to anon at all, so the refusal happens before
    // the function body. The internal `auth_required` guard is the second lock.
    const anonEnter = await rpc('space_enter', { p_handle: nameAlice, p_slug: 'my-journey' }, { key: clientKey });
    expectDenied('anon cannot call space_enter', anonEnter);

    const bobEnter1 = await rpc('space_enter', { p_handle: nameAlice, p_slug: 'my-journey' }, { key: clientKey, token: bob.token });
    expect('a signed-in reader passes the door', JSON.stringify(bobEnter1.json).includes('SECRET BELOW THE DOOR'), bobEnter1.text.slice(0, 300));
    expect('the first read counts as one reader', bobEnter1.json?.readers === 1, bobEnter1.text);

    const bobEnter2 = await rpc('space_enter', { p_handle: nameAlice, p_slug: 'my-journey' }, { key: clientKey, token: bob.token });
    expect('a refresh does not inflate readers', bobEnter2.json?.readers === 1, bobEnter2.text);

    const carolEnter = await rpc('space_enter', { p_handle: nameAlice, p_slug: 'my-journey' }, { key: clientKey, token: carol.token });
    expect('a second person counts as two', carolEnter.json?.readers === 2, carolEnter.text);

    // --- likes ------------------------------------------------------------
    const like1 = await rpc('toggle_like', { p_handle: nameAlice, p_slug: 'my-journey' }, { key: clientKey, token: carol.token });
    expect('a reader can like', like1.json?.liked === true && like1.json?.likes === 1, like1.text);

    const like2 = await rpc('toggle_like', { p_handle: nameAlice, p_slug: 'my-journey' }, { key: clientKey, token: carol.token });
    expect('liking again removes the like', like2.json?.liked === false && like2.json?.likes === 0, like2.text);

    const selfLike = await rpc('toggle_like', { p_handle: nameAlice, p_slug: 'my-journey' }, { key: clientKey, token: alice.token });
    expectError('the author cannot like their own Space', selfLike, 'cannot_like_own');

    // --- rename and D9 ---------------------------------------------------
    const renamed = await rpc(
      'rename_space',
      { p_space_id: spaceId, p_title: 'My Journey', p_slug: 'my-journey-renamed' },
      { key: clientKey, token: alice.token },
    );
    expect('rename changes the draft slug only', renamed.json?.slug === 'my-journey-renamed' && renamed.json?.published_slug === 'my-journey', renamed.text);

    const oldStillLive = await rpc('space_head', { p_handle: nameAlice, p_slug: 'my-journey' }, { key: clientKey });
    expect('the published URL still answers after a rename (D8, D9)', oldStillLive.json?.found === true, oldStillLive.text);

    const newNotLive = await rpc('space_head', { p_handle: nameAlice, p_slug: 'my-journey-renamed' }, { key: clientKey });
    expect('the new slug is not live until publish', newNotLive.json?.found === false, newNotLive.text);

    await rpc('publish_space', { p_space_id: spaceId }, { key: clientKey, token: alice.token });

    const newLive = await rpc('space_head', { p_handle: nameAlice, p_slug: 'my-journey-renamed' }, { key: clientKey });
    expect('republish moves the URL', newLive.json?.found === true, newLive.text);

    const oldDead = await rpc('space_head', { p_handle: nameAlice, p_slug: 'my-journey' }, { key: clientKey });
    expect('the old slug 404s after republish', oldDead.json?.found === false, oldDead.text);

    // --- visibility / trash ----------------------------------------------
    await rpc('set_visibility', { p_space_id: spaceId, p_visibility: 'private' }, { key: clientKey, token: alice.token });
    const isPrivate = await rpc('space_head', { p_handle: nameAlice, p_slug: 'my-journey-renamed' }, { key: clientKey });
    expect('a private Space 404s for anon', isPrivate.json?.found === false, isPrivate.text);

    await rpc('set_visibility', { p_space_id: spaceId, p_visibility: 'public' }, { key: clientKey, token: alice.token });

    await rpc('trash_space', { p_space_id: spaceId }, { key: clientKey, token: alice.token });
    const trashed = await rpc('space_head', { p_handle: nameAlice, p_slug: 'my-journey-renamed' }, { key: clientKey });
    expect('a trashed Space 404s immediately', trashed.json?.found === false, trashed.text);

    const trashVisible = await call('/rest/v1/spaces?select=id,deleted_at&deleted_at=not.is.null', {
      key: clientKey,
      token: alice.token,
    });
    expect('the owner can still see it in Trash (D34)', Array.isArray(trashVisible.json) && trashVisible.json.some((r) => r.id === spaceId), trashVisible.text);

    await rpc('restore_space', { p_space_id: spaceId }, { key: clientKey, token: alice.token });
    const restored = await rpc('space_head', { p_handle: nameAlice, p_slug: 'my-journey-renamed' }, { key: clientKey });
    expect('restore brings it back', restored.json?.found === true, restored.text);

    await rpc('delete_forever', { p_space_id: spaceId }, { key: clientKey, token: alice.token });
    const purged = await rpc('space_head', { p_handle: nameAlice, p_slug: 'my-journey-renamed' }, { key: clientKey });
    expect('delete forever removes it', purged.json?.found === false, purged.text);

    const reclaim = await rpc(
      'create_space',
      { p_title: 'Same Title Again', p_slug: 'my-journey-renamed' },
      { key: clientKey, token: alice.token },
    );
    expect('purging releases the title claim (D19)', reclaim.status === 200, reclaim.text);

    // --- storage ----------------------------------------------------------
    const anonStorage = await call('/storage/v1/object/list/media', {
      method: 'POST',
      key: clientKey,
      body: { prefix: '', limit: 10 },
    });
    const leaked = Array.isArray(anonStorage.json) && anonStorage.json.length > 0;
    expect('anon cannot list the private media bucket', !leaked, anonStorage.text.slice(0, 300));

    const anonAvatar = await call('/storage/v1/object/list/avatars', {
      method: 'POST',
      key: clientKey,
      body: { prefix: '', limit: 10 },
    });
    expect('avatars bucket answers without error', anonAvatar.status < 500, anonAvatar.text.slice(0, 200));
  } finally {
    for (const u of users) {
      await deleteUser(u.id).catch(() => {});
    }
  }

  const failed = results.filter((r) => !r.ok);
  console.log(`\n${results.length - failed.length}/${results.length} passed`);
  if (failed.length) {
    console.log('\nFailures:');
    for (const f of failed) console.log(`  - ${f.name}`);
    process.exit(1);
  }
}

run().catch((err) => {
  console.error('\nsuite crashed:', err.message);
  process.exit(2);
});
