import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {decode, encode} from '../src/lib/content/markdown';
import {activitySchema, parseMeta} from '../src/lib/content/schema';

const [nativeFile, contentDir] = process.argv.slice(2);
if (!nativeFile || !contentDir) throw new Error('Usage: npx tsx scripts/check-native-compat.ts <native-entry.md> <content-directory>');
const activities = await Promise.all((await fs.readdir(path.join(contentDir, 'activities'))).filter(name => name.endsWith('.md')).map(async name => {
  const parsed = decode(await fs.readFile(path.join(contentDir, 'activities', name), 'utf8'));
  return {...activitySchema.parse(parsed.data), body: parsed.content};
}));
const native = decode(await fs.readFile(nativeFile, 'utf8'));
const meta = parseMeta(native.data, activities);
assert.equal(meta.title, '晨跑');
assert.equal(meta.metrics?.duration_min, 32);
assert.equal(meta.metrics?.distance_km, 5.2);
assert.ok(native.content.includes('第二段 **正文**'));
await fs.writeFile(path.join(path.dirname(nativeFile), 'web-roundtrip.md'), encode(meta, native.content));
let count = 0;
for (const name of (await fs.readdir(path.join(contentDir, 'entries'))).filter(name => name.endsWith('.md'))) {
  const parsed = decode(await fs.readFile(path.join(contentDir, 'entries', name), 'utf8'));
  const entry = parseMeta(parsed.data, activities);
  assert.equal(name, `${entry.id}.md`);
  count++;
}
console.log(`PASS: web schema reads native output and ${count} library records; web-roundtrip.md written for native verification.`);
