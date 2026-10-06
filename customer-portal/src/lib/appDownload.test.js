import assert from 'node:assert/strict'
import { test } from 'node:test'

import {
  APP_DOWNLOAD_URL,
  modelRequestAppPrompt,
  tryOnAppPrompt,
} from './appDownload.js'

test('the download is the app repo\'s latest release, not a pinned version', () => {
  /*
    The one property worth guarding. The app installs from a versioned APK URL in
    `releases/version.json`, and copying that version into the portal would work
    exactly once — every later release would leave the website handing out the
    build it shipped with. `releases/latest` resolves to whatever is newest.
  */
  assert.equal(APP_DOWNLOAD_URL, 'https://github.com/kibs06/CUF/releases/latest')
  assert.ok(APP_DOWNLOAD_URL.endsWith('/releases/latest'), APP_DOWNLOAD_URL)
  assert.ok(/^https:\/\//.test(APP_DOWNLOAD_URL), 'must be https')

  // A versioned APK path is the mistake this guards: `…/releases/download/v1.2.3/…`.
  assert.ok(!APP_DOWNLOAD_URL.includes('/releases/download/'), APP_DOWNLOAD_URL)
})

test('the prompt names what was asked for and where it actually lives', () => {
  const prompt = tryOnAppPrompt()

  // The button says "Try On in AR"; a prompt that answered a different question
  // would read as a non-sequitur the moment it opened.
  assert.match(prompt.title, /Try On in AR/)
  // And it has to say the app, rather than implying the website failed.
  assert.match(prompt.title, /CUFMAI app/)

  assert.ok(prompt.description.length > 0)
  assert.match(prompt.description, /app/)
  // It is an APK for a phone, not a desktop download: saying so is the honest
  // half of "download the app".
  assert.match(prompt.description, /Android/)

  // The action asks for the download; the escape does not read like a cancelled
  // job (nobody is losing work by not downloading something).
  assert.equal(prompt.confirmLabel, 'Download the app')
  assert.equal(prompt.cancelLabel, 'Not now')
})

test('the model-request prompt says the app is where a request is filed', () => {
  const prompt = modelRequestAppPrompt()

  // The menu item says "Request a 3D model"; a prompt answering a different
  // question would read as a non-sequitur the moment it opened.
  assert.match(prompt.title, /3D model/)
  assert.match(prompt.title, /CUFMAI app/)

  /*
    It says what the seller will be asked for. A model is not a file they hand
    over — it is built from figures measured with a tape against the shoe — and
    that is the part of the ask nobody expects, so the prompt says it before they
    go looking for a ruler.
  */
  assert.match(prompt.description, /measur/i)
  assert.match(prompt.description, /Android/)

  assert.equal(prompt.confirmLabel, 'Download the app')
  assert.equal(prompt.cancelLabel, 'Not now')
})

test('both app pointers make the same offer in the same words', () => {
  /*
    Two answers to "where is the app" on one site is how a download prompt ends
    up disagreeing with itself. The action and the escape are the same two, and
    both call sites open `APP_DOWNLOAD_URL` — the constant above is the only URL
    either of them can reach.
  */
  const ar = tryOnAppPrompt()
  const model = modelRequestAppPrompt()
  assert.equal(model.confirmLabel, ar.confirmLabel)
  assert.equal(model.cancelLabel, ar.cancelLabel)

  /*
    And neither may read as "this page will do it for you". The portal files no
    model request (there is no INSERT policy for a browser session) and performs
    no fitting, so copy pointing at the portal is the one kind of sentence that
    promises something the click cannot deliver.
  */
  const said = `${model.title} ${model.description}`.toLowerCase()
  assert.ok(!/portal|this page/.test(said), said)
})

test('no prompt claims the browser can do the AR itself', () => {
  const prompt = tryOnAppPrompt()
  const said = `${prompt.title} ${prompt.description}`.toLowerCase()

  assert.ok(said.includes('app'), said)
  // The page draws the model and nothing else — see `Product3DViewer`. Copy that
  // offered "try on here" would be a promise no browser can keep.
  assert.ok(!said.includes('here in the browser'), said)
  assert.ok(!/try it on (now|here)/.test(said), said)
})
