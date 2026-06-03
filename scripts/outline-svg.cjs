#!/usr/bin/env node
/** Read SVG from stdin, write outlined (filled) SVG to stdout. Requires `npm install` in scripts/. */
const outlineStroke = require('svg-outline-stroke');

let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  input += chunk;
});
process.stdin.on('end', async () => {
  try {
    const outlined = await outlineStroke(input);
    process.stdout.write(outlined);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
});