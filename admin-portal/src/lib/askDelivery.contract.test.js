import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

import {
  ASK_AGAIN_TAIL,
  ASK_BODY,
  ASK_NAME_FALLBACK,
  ASK_PUSH_FUNCTION,
  ASK_PUSH_SCREEN,
  CLOSING_NOTICE,
  DECLINE_QUOTE,
  NOTICE_CHANNELS,
  SELLER_NOTICE_TYPE,
  TEAM_QUOTE,
} from './askDelivery.js'

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

// ─── 4. The push says what the bell says ───────────────────────────
//
// A notice row is not a push. Both rows can land, correctly, in the same
// transaction as the close, and the seller's phone can still stay silent — which
// is the report that made `askPush.js` exist. So the portal now asks for the
// OS-level copy too, and this section is what keeps it from becoming a second,
// drifting version of the news: the words are the RPC's, and the two guards
// below are that claim in the only form a browser can test.

test('the push quotes the RPC bodies rather than paraphrasing them', () => {
  const fulfil = functionBody('fulfil_shoe_model_request')
  const decline = functionBody('decline_shoe_model_request')

  // The middle of each sentence, the name fallback, and the way each ending
  // appends the admin's words — all lifted from the SQL above, so a copy change
  // on either side fails here instead of on a seller's lock screen.
  assert.ok(
    fulfil.includes(ASK_BODY.FULFILLED),
    `the fulfil notice no longer says "${ASK_BODY.FULFILLED}" — repoint askDelivery.js`,
  )
  assert.ok(decline.includes(ASK_BODY.DECLINED))
  // ⚠️ Compared in the SQL's own spelling: plpgsql escapes the apostrophe in
  // "product's" by doubling it, so the literal in the migration is
  // `product''s` — the sentence is the same one, and this says so rather than
  // leaving a one-character difference to be discovered by a failing seller.
  assert.ok(
    decline.includes(ASK_AGAIN_TAIL.replace(/'/g, "''")),
    'the ask-again sentence moved — repoint askDelivery.js',
  )
  assert.ok(fulfil.includes(TEAM_QUOTE))
  assert.ok(decline.includes(DECLINE_QUOTE))

  // `COALESCE(…, 'Your product')`: the fallback is the bell's own, not a second
  // invented one, because the push and the bell are read by the same person.
  assert.ok(fulfil.includes(`'${ASK_NAME_FALLBACK}'`))
  assert.ok(decline.includes(`'${ASK_NAME_FALLBACK}'`))
})

test("the push's screen key is one the app actually navigates for", () => {
  // The portal cannot click a phone, so the key is checked against the app's own
  // switch: `seller_shell.dart` handles a push's `screen` and silently ignores
  // anything it does not recognise, so a key invented here would swallow the tap.
  const shell = readFileSync(
    new URL('../../../lib/screens/seller/seller_shell.dart', import.meta.url),
    'utf8',
  )
  assert.match(
    shell,
    new RegExp(`case '${ASK_PUSH_SCREEN}':`),
    `${ASK_PUSH_SCREEN} is pushed but the app has no case for it — the tap would land nowhere`,
  )
})

test('both closing RPCs are followed by a push request, in the hook that calls them', () => {
  // Without this the whole feature can be deleted and every other test still
  // passes: the notice rows are the RPC's (guarded above), the copy is tested,
  // and the sender is tested — but nothing would call it.
  const hook = sources.find(({ path }) => path.endsWith('useModelRequests.js'))
  assert.ok(hook, 'the closing hooks moved — repoint this guard')

  for (const [rpc, kind] of [
    ['fulfil_shoe_model_request', 'FULFILLED'],
    ['decline_shoe_model_request', 'DECLINED'],
  ]) {
    const at = hook.text.indexOf(`'${rpc}'`)
    assert.ok(at > -1, `${rpc} is no longer called from ${hook.path}`)

    // Bounded to the same statement region rather than the whole file, so a call
    // that moved to an unrelated mutation cannot satisfy this by accident.
    const window = hook.text.slice(at, at + 900)
    assert.ok(
      window.includes('sendAskEndingPush'),
      `${rpc} closes an ask and asks for no push — the seller's phone stays quiet`,
    )
    assert.ok(window.includes(`ASK_ENDING.${kind}`), `${rpc} must push the ending it closed as`)
  }

  // And it is fire-and-forget: awaited into the outcome, a failed push would
  // report as a failed close (the ask is already closed by then).
  assert.ok(!/await\s+sendAskEndingPush/.test(hook.text))
  assert.match(hook.text, /void\s+sendAskEndingPush/)
})

test('the push service name is the deployed Edge Function, spelled once', () => {
  assert.equal(ASK_PUSH_FUNCTION, 'send-notification-push')

  const sender = sources.find(({ path }) => path.endsWith('askPush.js'))
  assert.ok(sender, 'askPush.js moved — repoint this guard')

  // The name is imported, never re-typed at the call site: a second spelling is
  // how a push starts 404-ing quietly (the invoke's error is swallowed by design).
  assert.ok(sender.text.includes(`invoke(ASK_PUSH_FUNCTION`))
  assert.ok(!sender.text.includes(`'send-notification-push'`))
})
