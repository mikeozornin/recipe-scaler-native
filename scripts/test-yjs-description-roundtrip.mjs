#!/usr/bin/env node
/**
 * Companion Node.js script for YrsDescriptionRoundtripTests.
 * Verifies that yjs can decode the same `description` XmlFragment that yrs encoded.
 *
 * Usage:
 *   node scripts/test-yjs-description-roundtrip.mjs [file1.bin file2.bin ...]
 *
 * If no files given, verifies all known test fixtures from /tmp.
 */

import { readFileSync } from 'fs'
import { basename } from 'path'
import { execSync } from 'child_process'

// Resolve yjs from the web project
const Y = await importYjs()

async function importYjs() {
  const webRoot = new URL('../recipe-scaler-web/recipe-scaler', import.meta.url)
  const yjsPath = new URL('node_modules/yjs/src/index.js', webRoot).pathname
  try {
    return (await import('file://' + yjsPath)).default ?? (await import('file://' + yjsPath))
  } catch {
    // Fallback: try CJS
    return require(new URL('node_modules/yjs/dist/yjs.cjs', webRoot).pathname)
  }
}

const defaultFixtures = [
  '/tmp/yrs-test-simple.bin',
  '/tmp/yrs-test-with-nodes.bin',
  '/tmp/yrs-test-multi-edit.bin',
  '/tmp/yrs-test-yjs-roundtrip-simple.bin',
  '/tmp/yrs-test-yjs-roundtrip-multi.bin',
  '/tmp/yrs-test-real-api-reencoded.bin',
  '/tmp/cheesecake-yjs.bin',  // raw API state (may have all-deleted description)
]

const files = process.argv.length > 2
  ? process.argv.slice(2)
  : defaultFixtures

let passed = 0
let failed = 0
let skipped = 0

for (const filePath of files) {
  const label = basename(filePath)
  try {
    const data = readFileSync(filePath)
    const state = new Uint8Array(data)

    const doc = new Y.Doc()
    Y.applyUpdate(doc, state)

    const fragment = doc.getXmlFragment('description')
    const fragLen = fragment.length
    const fragText = fragment.toString()

    // Count alive vs deleted items
    let alive = 0
    let deleted = 0
    let child = fragment._start
    while (child) {
      if (child.deleted) deleted++
      else alive++
      child = child.right
    }

    const shareKeys = [...doc.share.keys()]
    const hasDescription = shareKeys.includes('description')

    // Determine pass/fail
    // For the real API state (cheesecake), the description may be all-deleted on server
    const isRealApi = filePath.includes('cheesecake') || filePath.includes('real-api')

    if (isRealApi) {
      // For real API state we just log diagnostics, don't fail
      console.log(`  ℹ️  ${label}: ${data.length} bytes, share=[${shareKeys}], desc.length=${fragLen}, alive=${alive}, deleted=${deleted}`)
      if (fragLen > 0) {
        console.log(`     ✅ description has ${fragLen} children, text: "${fragText.slice(0, 80)}"`)
        passed++
      } else {
        console.log(`     ⚠️  description is empty (all deleted by server/other clients)`)
        skipped++
      }
    } else {
      // For yrs-generated test fixtures, description MUST be readable
      if (!hasDescription) {
        console.log(`  ❌ ${label}: no 'description' key in share (keys: ${shareKeys})`)
        failed++
      } else if (fragLen === 0) {
        console.log(`  ❌ ${label}: description exists but fragment.length=0, alive=${alive}, deleted=${deleted}`)
        console.log(`     share=[${shareKeys}]`)
        failed++
      } else {
        console.log(`  ✅ ${label}: ${data.length} bytes, desc.length=${fragLen}, alive=${alive}, text: "${fragText.slice(0, 60)}..."`)
        passed++
      }
    }
  } catch (err) {
    if (err.code === 'ENOENT') {
      console.log(`  ⏭️  ${label}: file not found (run XCTest first)`)
      skipped++
    } else {
      console.log(`  ❌ ${label}: ${err.message}`)
      failed++
    }
  }
}

console.log(`\n${passed} passed, ${failed} failed, ${skipped} skipped`)
process.exit(failed > 0 ? 1 : 0)
