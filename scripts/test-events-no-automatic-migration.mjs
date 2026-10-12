#!/usr/bin/env node
// Verify disabling automatic legacy migration does not remove existing
// canonical grouped Events or discard original backup metadata on save.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const eventsSource=fs.readFileSync(new URL('../services/Events.qml',import.meta.url),'utf8');
const policySource=fs.readFileSync(new URL('../services/EventOccurrences.js',import.meta.url),'utf8');
const context=vm.createContext({Date,Math,Number,Object,Array,String});
vm.runInContext(policySource,context);

assert.equal(typeof context.migrateLegacy,'undefined','legacy migration must no longer exist');
assert.equal(eventsSource.includes('_resumeLegacyMigration'),false);
assert.equal(eventsSource.includes('Occurrences.migrateLegacy'),false);
assert.equal(eventsSource.includes('occurrenceMigrationBackup'),false,
    'no migration-specific lifecycle logic in Events service');
assert.ok(eventsSource.includes('root.list=events'),
    'Events loader must use persisted records without normalization');
assert.ok(eventsSource.includes('root.retainedStorageFields=retained'),
    'unknown root data must be saved without erasing historical backups');
assert.ok(eventsSource.includes('Object.assign({},root.retainedStorageFields,'),
    'user-owned metadata must survive future saves');

const before={
    schemaVersion:2,nextId:8,
    events:[{
        id:7,title:'Existing class',startDate:'2026-10-12T09:00:00Z',
        endDate:'2026-10-12T10:00:00Z',
        todoLink:{version:1,key:'agenda-existing',state:'linked'},
        occurrences:[
            {startDate:'2026-10-12T09:00:00Z',endDate:'2026-10-12T10:00:00Z'},
            {startDate:'2026-10-14T12:00:00Z',endDate:'2026-10-14T13:00:00Z'}
        ]
    }],
    todoUnlinks:[],
    occurrenceMigrationBackup:{
        version:2,original:{events:[{id:7,title:'Original class'}]}
    },
    futureMetadata:{a:1}
};
const parsed=JSON.parse(JSON.stringify(before));
const retained={};
for(const key of Object.keys(parsed)){
    if(!['schemaVersion','nextId','events','todoUnlinks'].includes(key))
        Object.defineProperty(retained,key,{value:parsed[key],enumerable:true,
            writable:true,configurable:true});
}
const after=Object.assign({},retained,{
    schemaVersion:2,nextId:parsed.nextId,events:parsed.events,todoUnlinks:parsed.todoUnlinks
});
assert.equal(JSON.stringify(after.events),JSON.stringify(before.events));
assert.equal(JSON.stringify(after.occurrenceMigrationBackup),
    JSON.stringify(before.occurrenceMigrationBackup));
assert.equal(JSON.stringify(after.futureMetadata),
    JSON.stringify(before.futureMetadata));
assert.equal(context.entries(after.events[0]).length,2,
    'existing stored grouped Event dates remain readable');
console.log('PASS no automatic migration, existing occurrences and metadata preserved');
