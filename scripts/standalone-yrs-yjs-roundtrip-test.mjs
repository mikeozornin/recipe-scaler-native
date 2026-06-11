#!/usr/bin/env node
/**
 * standalone-yrs-yjs-roundtrip-test.mjs
 *
 * Standalone test that reproduces the "yjs sees empty description" bug
 * WITHOUT needing XCTest. Simulates what yrs does:
 *   1. Create description with content from "client A"
 *   2. Delete all of it from "client B"
 *   3. Re-create description from "client A" again
 *   4. Encode state → decode in fresh yjs doc → check fragment.length
 *
 * Run: node scripts/standalone-yrs-yjs-roundtrip-test.mjs
 */

import { fileURLToPath } from 'url'
import { join, dirname } from 'path'

const __dirname = dirname(fileURLToPath(import.meta.url))
const webRoot = join(__dirname, '..', '..', 'recipe-scaler-web', 'recipe-scaler')

let Y
try {
  const yjsPath = join(webRoot, 'node_modules', 'yjs')
  Y = await import('file://' + yjsPath + '/src/index.js')
} catch {
  // Try CJS
  Y = require(join(webRoot, 'node_modules', 'yjs', 'dist', 'yjs.cjs'))
}

if (!Y.Doc) {
  console.error('Failed to load yjs')
  process.exit(1)
}

let passed = 0
let failed = 0

function assert(condition, message) {
  if (condition) {
    console.log(`  ✅ ${message}`)
    passed++
  } else {
    console.log(`  ❌ ${message}`)
    failed++
  }
}

// ─── Test 1: Simple write → encode → decode roundtrip ───
console.log('\nTest 1: Simple single-client roundtrip')
{
  const doc1 = new Y.Doc()
  const desc1 = doc1.getXmlFragment('description')
  const p = new Y.XmlElement('paragraph')
  const t = new Y.XmlText()
  t.insert(0, 'Hello from yrs!')
  p.insert(0, [t])
  desc1.insert(0, [p])

  assert(desc1.length === 1, `doc1 fragment.length = ${desc1.length} (expected 1)`)
  assert(desc1.toString().includes('Hello from yrs!'), 'doc1 has text content')

  // Encode → decode
  const state = Y.encodeStateAsUpdate(doc1)
  const doc2 = new Y.Doc()
  Y.applyUpdate(doc2, state)

  const desc2 = doc2.getXmlFragment('description')
  assert(desc2.length === 1, `doc2 fragment.length = ${desc2.length} (expected 1)`)
  assert(desc2.toString().includes('Hello from yrs!'), 'doc2 has text content after roundtrip')
}

// ─── Test 2: Two-client edit (write → delete → rewrite) ───
// This simulates what the Basque Cheesecake recipe went through:
// client A wrote content, client B deleted it, client A wrote new content.
console.log('\nTest 2: Two-client write-delete-rewrite')
{
  // Client A writes initial content
  const docA = new Y.Doc()
  const descA = docA.getXmlFragment('description')
  const p1 = new Y.XmlElement('paragraph')
  const t1 = new Y.XmlText()
  t1.insert(0, 'Initial content from client A')
  p1.insert(0, [t1])
  descA.insert(0, [p1])

  const stateAfterA1 = Y.encodeStateAsUpdate(docA)

  // Client B receives state, deletes all content
  const docB = new Y.Doc()
  Y.applyUpdate(docB, stateAfterA1)

  const descB = docB.getXmlFragment('description')
  assert(descB.length === 1, `docB after sync: fragment.length = ${descB.length}`)

  // Client B deletes everything
  descB.delete(0, descB.length)
  assert(descB.length === 0, `docB after delete: fragment.length = ${descB.length}`)

  const stateAfterB = Y.encodeStateAsUpdate(docB)

  // Client A receives B's delete
  Y.applyUpdate(docA, stateAfterB)
  assert(descA.length === 0, `docA after receiving delete: fragment.length = ${descA.length}`)

  // Client A writes new content
  const p2 = new Y.XmlElement('paragraph')
  const t2 = new Y.XmlText()
  t2.insert(0, 'New content from client A')
  p2.insert(0, [t2])
  descA.insert(0, [p2])

  assert(descA.length === 1, `docA after rewrite: fragment.length = ${descA.length}`)

  // Now encode A's state and decode in fresh doc
  const stateFinal = Y.encodeStateAsUpdate(docA)
  const docFresh = new Y.Doc()
  Y.applyUpdate(docFresh, stateFinal)

  const descFresh = docFresh.getXmlFragment('description')
  assert(descFresh.length === 1, `fresh doc: fragment.length = ${descFresh.length} (THIS IS THE BUG if 0)`)
  assert(descFresh.toString().includes('New content from client A'),
    'fresh doc has new content')
}

// ─── Test 3: Full merge from multiple clients (simulates real sync) ───
console.log('\nTest 3: Multi-client merge (simulates real sync scenario)')
{
  // Server has accumulated state from many clients
  const serverDoc = new Y.Doc()

  // Client A creates initial description
  const clientA = new Y.Doc()
  const descA = clientA.getXmlFragment('description')
  for (let i = 0; i < 5; i++) {
    const p = new Y.XmlElement('paragraph')
    const t = new Y.XmlText()
    t.insert(0, `Paragraph ${i + 1} from client A`)
    p.insert(0, [t])
    descA.insert(i, [p])
  }

  // Sync A → server
  Y.applyUpdate(serverDoc, Y.encodeStateAsUpdate(clientA))
  // Sync server → A
  Y.applyUpdate(clientA, Y.encodeStateAsUpdate(serverDoc))

  // Client B reads, deletes everything, writes new content
  const clientB = new Y.Doc()
  Y.applyUpdate(clientB, Y.encodeStateAsUpdate(serverDoc))

  const descB = clientB.getXmlFragment('description')
  assert(descB.length === 5, `clientB sees ${descB.length} paragraphs`)

  descB.delete(0, descB.length)

  // Client B writes 4 new paragraphs
  for (let i = 0; i < 4; i++) {
    const p = new Y.XmlElement('paragraph')
    const t = new Y.XmlText()
    t.insert(0, `New paragraph ${i + 1} from client B`)
    p.insert(0, [t])
    descB.insert(i, [p])
  }

  // Sync B → server
  Y.applyUpdate(serverDoc, Y.encodeStateAsUpdate(clientB))
  // Sync server → all
  const serverState = Y.encodeStateAsUpdate(serverDoc)
  Y.applyUpdate(clientA, serverState)
  Y.applyUpdate(clientB, serverState)

  // Verify all docs agree
  const descServer = serverDoc.getXmlFragment('description')
  assert(descServer.length === 4, `server: fragment.length = ${descServer.length}`)

  // THE KEY TEST: fresh doc from server state
  const freshDoc = new Y.Doc()
  Y.applyUpdate(freshDoc, serverState)
  const descFresh = freshDoc.getXmlFragment('description')
  assert(descFresh.length === 4,
    `fresh doc from server state: fragment.length = ${descFresh.length} (BUG if 0)`)
  assert(descFresh.toString().includes('New paragraph 1 from client B'),
    'fresh doc has client B content')
}

// ─── Test 4: Check the real API state ───
console.log('\nTest 4: Real API state (cheesecake-yjs.bin)')
{
  const fs = await import('fs')
  const path = '/tmp/cheesecake-yjs.bin'

  if (!fs.existsSync(path)) {
    console.log('  ⏭️  No cheesecake-yjs.bin found, skipping')
  } else {
    const state = new Uint8Array(fs.readFileSync(path))
    const doc = new Y.Doc()
    Y.applyUpdate(doc, state)

    const desc = doc.getXmlFragment('description')

    // Count alive vs deleted
    let alive = 0, deleted = 0
    let child = desc._start
    while (child) {
      if (child.deleted) deleted++
      else alive++
      child = child.right
    }

    // Diagnose WHY fragment is empty
    const decoded = Y.decodeUpdate(state)
    const descClient = 4045812770
    const allStructs = decoded.structs.filter(s => s.id.client === descClient)
    const ds = decoded.ds.clients.get(descClient)
    const gcStruct = allStructs.find(s => s.id.clock === 1580)

    console.log(`  📊 API state: ${state.length} bytes, share=[${[...doc.share.keys()]}]`)
    console.log(`  📊 description: length=${desc.length}, alive=${alive}, deleted=${deleted}`)
    console.log(`  📊 decoded structs for desc client: ${allStructs.length}`)

    if (gcStruct) {
      const gcEnd = gcStruct.id.clock + gcStruct.length
      console.log(`  📊 GC/Skip struct: [${gcStruct.id.clock}, ${gcEnd}) len=${gcStruct.length}`)
    }

    // Check: do content items reference a clock inside the GC range?
    const contentStructs = allStructs.filter(s => s.id.clock >= 4747)
    const unresolvedRight = contentStructs.filter(s =>
      s.rightOrigin &&
      s.rightOrigin.client === descClient &&
      gcStruct &&
      s.rightOrigin.clock >= gcStruct.id.clock &&
      s.rightOrigin.clock < gcStruct.id.clock + gcStruct.length
    )

    if (unresolvedRight.length > 0) {
      console.log(`  🔍 ROOT CAUSE: ${unresolvedRight.length} content items have rightOrigin inside GC range`)
      console.log(`     These items can never integrate → fragment stays empty in yjs`)
      console.log(`     (yrs resolves them differently using the Skip struct)`)
      failed++
    } else if (desc.length === 0) {
      console.log('  ⚠️  description empty but no unresolved rightOrigin found')
      failed++
    } else {
      assert(desc.length > 0, `real API state has ${desc.length} fragment children`)
    }
  }
}

// ─── Summary ───
console.log(`\n${passed} passed, ${failed} failed`)
process.exit(failed > 0 ? 1 : 0)
