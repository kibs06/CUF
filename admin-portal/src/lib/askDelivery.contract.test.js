import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import { CLOSING_NOTICE, NOTICE_CHANNELS, SELLER_NOTICE_TYPE } from './askDelivery.js'

// ─── The claim this portal makes about SQL it does not own ─────────
//
// The queue says "the seller has been told". That is a statement about two
// INSERTs inside two `SECURITY DEFINER` functions in
// `supabase/migrations/20260928140000_add_shoe_model_requests.sql` — code no
// browser runs and no front-end test can exercise. So the guard is the same
// shape the app uses for its own cross-language claim
// (`test/services/notification_category_contract_test.dart`): read the SQL, and
// fail if it stops backing the sentence.
//
// There are three ways the promise could break, and one test each:
//
//   1. the SQL stops writing the notice (or writes it on one channel, which is
//      V2.14's bug — a row the seller's shell never renders);
//   2. the notice moves out of the transaction that closes the ask, so "closed"
//      no longer implies "told";
//   3. **this portal** starts sending the notice itself, or closes an ask by
//      writing the row — both of which would make delivery a client's courtesy
//      rather than the database's fact, and both of which are guarded by
//      reading the portal's own source below.

const MIGRATION = '20260928140000_add_shoe_model_requests.sql'
const sql = readFileSync(
  new URL(`../../../supabase/migrations/${MIGRATION}`, import.meta.url),
  'utf8',
)

const SRC = fileURLToPath(new URL('../', import.meta.url))

/** Every `.js`/`.jsx` file under `src/`, tests excluded: a test's own text is
 *  full of the strings these guards look for, and a guard that trips on itself
 *  guards nothing. */
function sourceFiles(dir = SRC) {
  const found = []
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = `${dir}/${entry.name}`
    if (entry.isDirectory()) found.push(...sourceFiles(path))
    else if (/\.(js|jsx)$/.test(entry.name) && !/\.test\.js$/.test(entry.name)) found.push(path)
  }
  return found
}

const sources = sourceFiles().map((path) => ({ path, text: readFileSync(path, 'utf8') }))

/** One `CREATE OR REPLACE FUNCTION public.<name>` body: from the header to the
 *  first `$$;`, which is the only place that terminator appears. */
function functionBody(name) {
  const body = new RegExp(
    String.raw`CREATE OR REPLACE FUNCTION public\.${name}\([\s\S]*?\n\$\$;`,
  ).exec(sql)
  assert.ok(body, `${name} is no longer defined in ${MIGRATION} — repoint this guard`)
  return body[0]
}

function indexOfOrFail(haystack, pattern, label) {
  const match = new RegExp(pattern).exec(haystack)
  assert.ok(match, `${label} is gone from the migration: expecting ${pattern}`)
  return match.index
}

test('the guards are reading the portal and the SQL, not an empty set', () => {
  // A guard that scans the wrong directory passes for the wrong reason — the
  // bug the app's own contract test was rewritten for (a moved anchor passing on
  // an empty set). These three assertions are that lesson, in the only form a
  // source scan can have: prove there was something to scan, and that the
  // patterns the negative guards look for are actually present.
  assert.ok(sources.length >= 20, `expected the whole portal, saw ${sources.length} files`)
  assert.ok(
    sources.some(({ text }) => /\.from\(\s*['"]shoe_model_requests['"]\s*\)/.test(text)),
    'nothing reads the queue — the write guard below would pass on nothing',
  )
  assert.ok(
    sources.some(({ text }) => /\.rpc\(\s*['"]/.test(text)),
    'nothing calls an RPC — the call-site guard below would pass on nothing',
  )
  assert.ok(sql.includes('CREATE OR REPLACE FUNCTION public.fulfil_shoe_model_request('))
})

// ─── 1. The SQL still writes the notice, on both channels ──────────

test('the close writes the seller a notice, on both of the two channels', () => {
  const body = functionBody('fulfil_shoe_model_request')

  assert.match(body, /INSERT INTO public\.notifications \(user_id, category, title, message, metadata\)/)
  assert.match(body, /'models'/)
  assert.ok(body.includes(`'${CLOSING_NOTICE.FULFILLED}'`), 'the title the portal quotes')

  // ⚠️ Two rows. The per-user one alone was correct and unreadable at the same
  // time, because the seller's shell reads the store-scoped bell instead — the
  // finding the portal's own sentence now names, so both must stay.
  assert.match(body, /INSERT INTO public\.seller_notifications/)
  assert.ok(body.includes(`'${SELLER_NOTICE_TYPE}'`))
  assert.equal(NOTICE_CHANNELS.length, 2)
})

test('the decline writes the same two rows, under the other title', () => {
  const body = functionBody('decline_shoe_model_request')

  assert.match(body, /INSERT INTO public\.notifications \(user_id, category, title, message, metadata\)/)
  assert.match(body, /'models'/)
  assert.ok(body.includes(`'${CLOSING_NOTICE.DECLINED}'`))

  assert.match(body, /INSERT INTO public\.seller_notifications/)
  assert.ok(body.includes(`'${SELLER_NOTICE_TYPE}'`))

  // The reason the page insists on travels with the notice — from the ARGUMENT,
  // which is what this call carried, not from a stale snapshot of the row.
  const notice = body.slice(indexOfOrFail(body, 'INSERT INTO public\\.notifications', 'the notice'))
  assert.match(notice, /p_reason/)
})

// ─── 2. …inside the transaction that closes the ask ────────────────

test('neither notice can outlive or precede the close: same function, after the UPDATE', () => {
  for (const [name, title] of [
    ['fulfil_shoe_model_request', CLOSING_NOTICE.FULFILLED],
    ['decline_shoe_model_request', CLOSING_NOTICE.DECLINED],
  ]) {
    const body = functionBody(name)

    const closed = indexOfOrFail(body, 'UPDATE public\\.shoe_model_requests', `${name}'s close`)
    const perUser = indexOfOrFail(
      body,
      'INSERT INTO public\\.notifications',
      `${name}'s per-user notice`,
    )
    const perStore = indexOfOrFail(
      body,
      'INSERT INTO public\\.seller_notifications',
      `${name}'s store notice`,
    )

    // One plpgsql body is one transaction, so "after the UPDATE and inside the
    // body" is the mechanical form of "the seller cannot be told about a close
    // that rolled back".
    assert.ok(closed < perUser, `${name}: the notice must follow the status change`)
    assert.ok(closed < perStore, `${name}: the bell row must follow the status change`)
    assert.ok(perUser < body.length && perStore < body.length)

    // And the fulfil's note is the argument, not `v_request.admin_note`, which is
    // the snapshot read BEFORE the UPDATE — the seller reads this sentence, and
    // stale would be worse than absent.
    if (name === 'fulfil_shoe_model_request') {
      const notice = body.slice(perUser, perStore)
      assert.match(notice, /p_admin_note/)
      assert.ok(!notice.includes('v_request.admin_note'))
    }

    assert.ok(body.includes(title))
  }
})

// ─── 3. This portal does not do the telling ────────────────────────

test('the portal never writes a notice itself, on either channel', () => {
  // An app-side send is skippable — the next client, the next outage, the next
  // forgotten `await` — which is exactly why the RPC writes it. If this portal
  // ever inserts one, two notices would arrive and neither would be the fact.
  for (const { path, text } of sources) {
    assert.ok(
      !/\.from\(\s*['"](notifications|seller_notifications)['"]\s*\)/.test(text),
      `${path} touches a notice table directly; the closing RPC is the writer`,
    )
  }
})

test('the portal closes an ask only through the RPCs, never by writing the row', () => {
  for (const { path, text } of sources) {
    for (const match of text.matchAll(/\.from\(\s*['"]shoe_model_requests['"]\s*\)/g)) {
      const statement = text.slice(match.index, text.indexOf(';', match.index) + 1)
      assert.ok(
        !/\.(insert|upsert|update|delete)\(/.test(statement),
        `${path} closes an ask by writing the row; only the RPCs may, because they notify`,
      )
    }
  }
})

test('every request RPC the portal calls exists in the migration that owns it', () => {
  const called = new Set()
  for (const { text } of sources) {
    for (const match of text.matchAll(/\.rpc\(\s*['"](\w+)['"]/g)) called.add(match[1])
  }

  const requestRpcs = [...called].filter((name) => name.endsWith('_shoe_model_request'))
  assert.ok(
    requestRpcs.length >= 3,
    `expected the three closing/claiming RPCs, saw ${requestRpcs.join(', ') || 'none'}`,
  )

  for (const name of requestRpcs) {
    assert.match(
      sql,
      new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\(`),
      `${name} is called but not defined in ${MIGRATION}`,
    )
  }

  // The two closing ones are the ones whose bodies carry the notice — asserted
  // above — so a rename that lost the insert cannot pass by being found once.
  assert.ok(requestRpcs.includes('fulfil_shoe_model_request'))
  assert.ok(requestRpcs.includes('decline_shoe_model_request'))
})
