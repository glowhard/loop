// The window loads its files one after another into a single shared scope.
// Two files declaring the same name is not a warning there: the second file
// stops dead, and everything after it never runs, so the window comes up with
// pieces missing. Cheap to check here, miserable to find by hand.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const DIR = path.join(__dirname, '..', 'src', 'renderer');
const page = fs.readFileSync(path.join(DIR, 'index.html'), 'utf8');

// The files the window loads, in the order it loads them.
const loaded = [...page.matchAll(/<script src="([^"]+\.js)"><\/script>/g)]
  .map((m) => m[1])
  .filter((f) => !f.startsWith('../'));

test('the window loads the files it is meant to', () => {
  assert.ok(loaded.includes('app.js'), 'app.js is loaded');
  assert.ok(loaded.includes('voice.js'), 'voice.js is loaded');
  for (const f of loaded) assert.ok(fs.existsSync(path.join(DIR, f)), `${f} is there`);
});

test('no two renderer files declare the same name', () => {
  const seen = new Map(); // name -> file that declared it first
  const clashes = [];
  for (const file of loaded) {
    const src = fs.readFileSync(path.join(DIR, file), 'utf8');
    for (const m of src.matchAll(/^(?:const|let|var|function|class)\s+([A-Za-z_$][\w$]*)/gm)) {
      const name = m[1];
      if (seen.has(name)) clashes.push(`${name}: ${seen.get(name)} and ${file}`);
      else seen.set(name, file);
    }
  }
  assert.deepStrictEqual(clashes, [], 'these names are declared twice, and the second file will not load');
});

test('every renderer file parses on its own', () => {
  const vm = require('node:vm');
  for (const file of loaded) {
    const src = fs.readFileSync(path.join(DIR, file), 'utf8');
    assert.doesNotThrow(() => new vm.Script(src, { filename: file }), `${file} does not parse`);
  }
});
