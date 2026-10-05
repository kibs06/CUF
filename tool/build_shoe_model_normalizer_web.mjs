#!/usr/bin/env node
// tool/build_shoe_model_normalizer_web.mjs
//
// Compiles the reference shoe-model normalizer to JavaScript for the admin
// portal's "Compress it" step, and stamps the artifact with the digest of the
// Dart it was built from.
//
//   node tool/build_shoe_model_normalizer_web.mjs
//
// **Why the output is checked in.** `admin-portal/` is its own app with its own
// lockfile and its own CI job (`.github/workflows/admin-portal.yml`), which
// installs Node and nothing else. Making every portal build depend on a Dart
// SDK would mean the portal could not be built by somebody who only has the
// folder. So the artifact is committed and this script is run by whoever
// changes the normalizer — the same shape as any other generated file that
// ships, with one difference: the stamp below is checked by
// `modelCompress.contract.test.js`, so forgetting to re-run this fails a test
// with the command in the message rather than shipping a stale normalizer.
//
// Exit codes: `0` built · `1` the compile failed · `2` the command could not
// run (no Dart on PATH, wrong working directory).

import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')

/** The entry point, and every Dart file it can pull in. Listed explicitly
 *  rather than walked: the stamp has to change when the *rules* change, and a
 *  walk would make it change for a comment in an unrelated file. */
const SOURCES = ['tool/shoe_model_normalizer_web.dart', 'lib/utils/glb_normalizer.dart']

/** Where the portal imports it from. */
const OUTPUT = 'admin-portal/src/lib/glb_normalizer.gen.js'

/** The digest of the Dart sources, in the listed order. */
function sourceDigest() {
  const hash = createHash('sha256')
  for (const relative of SOURCES) {
    hash.update(`${relative}\n`)
    hash.update(readFileSync(join(repoRoot, relative)))
  }
  return hash.digest('hex')
}

function main() {
  const digest = sourceDigest()

  let sdk
  try {
    const probe = execFileSync(
      process.platform === 'win32' ? 'dart.bat' : 'dart',
      ['--version'],
      { encoding: 'utf8', shell: process.platform === 'win32' },
    )
    sdk = /Dart SDK version: ([^\s]+)/.exec(probe)?.[1] ?? 'unknown'
  } catch (error) {
    console.error('error: could not run `dart --version`. Is the Dart SDK on PATH?')
    console.error(`  ${error.message}`)
    process.exit(2)
  }

  const staging = mkdtempSync(join(tmpdir(), 'shoe-normalizer-web-'))
  const compiled = join(staging, 'normalizer.js')

  try {
    execFileSync(
      process.platform === 'win32' ? 'dart.bat' : 'dart',
      ['compile', 'js', '-O2', SOURCES[0], '-o', compiled],
      { cwd: repoRoot, stdio: ['ignore', 'inherit', 'inherit'], shell: process.platform === 'win32' },
    )
  } catch (error) {
    console.error('error: `dart compile js` failed — the artifact was not written.')
    console.error(`  ${error.message}`)
    process.exit(1)
  }

  // dart2js emits an IIFE, not a module. The portal imports this file, so the
  // entry point is re-exported at the bottom — by then `main()` has run and the
  // function is on `globalThis`. The sourceMappingURL is dropped because the
  // `.map` is not shipped and a comment pointing at a missing file only makes
  // a browser devtools request 404.
  const compiledCode = readFileSync(compiled, 'utf8')
    .replace(/^\/\/# sourceMappingURL=.*$/m, '')
    .trimEnd()

  const banner = [
    '// ⚠️ GENERATED FILE — do not edit, and do not hand-fix.',
    '//',
    '// The reference shoe-model normalizer (`lib/utils/glb_normalizer.dart`),',
    '// compiled from `tool/shoe_model_normalizer_web.dart` by:',
    '//',
    '//   node tool/build_shoe_model_normalizer_web.mjs',
    '//',
    '// It is the same `normalizeShoeModel` the CLI runs, not a port of it: the',
    '// eleven-check contract has exactly two implementations (the Dart reference',
    '// and the TypeScript mirror in `validate-shoe-model`, parity-checked over 22',
    '// fixtures) and the portal adds no third. See the Dart entry point for why.',
    '//',
    '// The stamp below is verified by `modelCompress.contract.test.js`, which',
    '// fails with the rebuild command if the Dart has moved on without this file.',
    '//',
    `// dart-source-sha256: ${digest}`,
    `// dart-sdk: ${sdk}`,
    '',
  ].join('\n')

  const exportLine = [
    '',
    '// The portal imports this name. `main()` above has already assigned it.',
    'export const soleVisionNormalize = globalThis.soleVisionNormalize',
    '',
  ].join('\n')

  const output = `${banner}${compiledCode}${exportLine}`
  writeFileSync(join(repoRoot, OUTPUT), output)
  rmSync(staging, { recursive: true, force: true })

  const kilobytes = (Buffer.byteLength(output) / 1024).toFixed(0)
  console.log(`Wrote ${OUTPUT} (${kilobytes} KB)`)
  console.log(`  dart-source-sha256: ${digest}`)
  console.log(`  dart-sdk: ${sdk}`)
}

main()
