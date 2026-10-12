#!/usr/bin/env node
// First-launch automatic migration: pure policy, no Quickshell required.
// Native FileView persistence and installed runtime remain separate gates.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const source=fs.readFileSync(new URL('../services/EventOccurrences.js',import.meta.url),'utf8');
const m=vm.createContext({Date,Math,Number,Array,Object,String,Boolean});
vm.runInContext(source,m);
function item(id,title,day,link='pending',details={}) {
  return {id,title,description:'',category:'general',priority:'normal',
    reminderMinutes:15,allDay:false,recurrence:'none',
    dateTime:`2026-10-${day}T13:00:00.000Z`,
    startDate:`2026-10-${day}T13:00:00.000Z`,
    endDate:`2026-10-${day}T15:00:00.000Z`,
    notified:day==='12',reminderNotified:day==='12',
    createdAt:`2026-09-${day}T13:00:00.000Z`,
    todoLink:link===null?undefined:{
      version:1,key:`agenda-${String(id).padStart(10,'0')}`,
      state:link,provider:link==='linked'?'internal':''},
    ...details};
}
const originals=[
  item(7,'  Grade 10 Class  ','12'),
  item(8,'grade 10 class','14'),
  item(9,'Grade 10 Class','16')
];
const unchanged=JSON.stringify(originals);
const outcome=m.migrateLegacy(originals);
assert.equal(outcome.changed,true);
assert.equal(outcome.normalized,3);
assert.equal(outcome.merged,2);
assert.equal(outcome.events.length,1);
const canonical=outcome.events[0];
assert.equal(canonical.id,7);
assert.equal(canonical.todoLink.key,originals[0].todoLink.key);
assert.equal(canonical.occurrences.length,3);
assert.equal(canonical.occurrences[0].notified,true);
assert.equal(canonical.occurrences[0].reminderNotified,true);
assert.equal(canonical.occurrences[1].notified,false);
assert.equal(canonical.mergedLegacyIds.join(','),'8,9');
assert.equal(originals[0].createdAt,canonical.createdAt);
assert.equal(JSON.stringify(originals),unchanged,'caller snapshot is immutable');
const restarted=m.migrateLegacy(JSON.parse(JSON.stringify(outcome.events)));
assert.equal(restarted.changed,false,'migration is repeat-safe');
const linked=m.migrateLegacy([
  item(10,'Class','12','linked'),
  item(11,'Class','14','linked')]);
assert.equal(linked.events.length,2,'existing independently linked Todos survive');
assert.equal(linked.skippedLinked,1);
const detached=m.migrateLegacy([
  item(12,'Class','12','pending'),
  item(13,'Class','14','detached')]);
assert.equal(detached.events.length,2);
assert.equal(m.migrateLegacy([
  item(14,'Class','12',null,{description:'Math'}),
  item(15,'Class','14',null,{description:'English'})
]).events.length,2);
assert.equal(m.migrateLegacy([
  item(16,'Class','12',null,{recurrence:'weekly'})
]).changed,false,'recurring series are left alone');
assert.equal(m.migrateLegacy([
  item(17,'Class','12',null,{startDate:'bad',dateTime:'bad'})
]).changed,false,'invalid source time is retained for repair');
assert.equal(m.migrateLegacy([]).changed,false);
const backup={version:1,original:{events:originals,nextId:18,todoUnlinks:[]}};
const durable=JSON.parse(JSON.stringify({
    schemaVersion:2,events:outcome.events,nextId:18,
    todoUnlinks:[],occurrenceMigrationBackup:backup
}));
assert.equal(durable.occurrenceMigrationBackup.original.events.length,3);
assert.equal(durable.events[0].occurrences.length,3);
assert.equal(m.migrateLegacy(durable.events).events.map(e=>e.id).join(','),'7');
const backend=fs.readFileSync(new URL('../services/Events.qml',import.meta.url),'utf8');
assert.ok(backend.includes('const migration=previousBackup?.version===1'));
assert.ok(backend.includes('root._saveQueued=true'));
assert.ok(backend.includes('Qt.callLater(root.saveToFile)'));
assert.ok(backend.includes('data.occurrenceMigrationBackup=root.occurrenceMigrationBackup'));
console.log('PASS automatic legacy migration, restart idempotence, original backup, Todo safety and stored chronology');
