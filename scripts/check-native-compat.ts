import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {decode, encode} from '../src/lib/content/markdown';
import {activitySchema, parseMeta, settingsSchema} from '../src/lib/content/schema';

const [nativeFile, contentDir, managedDir] = process.argv.slice(2);
if (!nativeFile || !contentDir || !managedDir) throw new Error('Usage: npx tsx scripts/check-native-compat.ts <native-entry.md> <content-directory> <native-management-directory>');
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

settingsSchema.parse(JSON.parse(await fs.readFile(path.join(managedDir, 'settings.json'), 'utf8')));
const managedActivities = await Promise.all((await fs.readdir(path.join(managedDir, 'activities'))).filter(name => name.endsWith('.md')).map(async name => {
  const parsed = decode(await fs.readFile(path.join(managedDir, 'activities', name), 'utf8'));
  const activity = activitySchema.parse(parsed.data);
  assert.equal(name, `${activity.id}.md`);
  return {...activity, body: parsed.content};
}));
assert.equal(managedActivities.find(activity => activity.id === 'swimming')?.name, '泳池训练');
assert.deepEqual(managedActivities.find(activity => activity.id === 'empty-activity')?.metrics, []);
const managedEntries = await Promise.all((await fs.readdir(path.join(managedDir, 'entries'))).filter(name => name.endsWith('.md')).map(async name => {
  const parsed = decode(await fs.readFile(path.join(managedDir, 'entries', name), 'utf8'));
  const entry = parseMeta(parsed.data, managedActivities);
  assert.equal(name, `${entry.id}.md`);
  return entry;
}));
assert.ok(managedEntries.some(entry => entry.activity_id === 'swimming' && entry.metrics?.distance_km === 0.75 && entry.title === '泳池训练'));
console.log(`PASS: original web schema reads ${managedActivities.length} managed activities and ${managedEntries.length} saved/restored records without new YAML fields.`);
