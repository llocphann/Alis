const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const model=vm.createContext({});
vm.runInContext(fs.readFileSync('modules/dashboard/DashboardMusicModel.js','utf8').replace(/^\.pragma library\s*/,''),model);
const tracks=Object.freeze([
 Object.freeze({uri:'Jazz/Live/one.flac',folder:'Jazz/Live',title:'One',genre:'Jazz; Fusion'}),
 Object.freeze({uri:'Jazz/two.flac',folder:'Jazz',title:'Two',genre:['Jazz','Jazz']}),
 Object.freeze({uri:'Jazzical/three.flac',folder:'Jazzical',title:'Three',genre:'Classical'}),
 Object.freeze({uri:'__proto__/四.flac',folder:'__proto__',title:'四',genre:''}),
 Object.freeze({uri:'root.flac',folder:'',title:'Root',genre:'Jazz'})
]);
const json=value=>JSON.parse(JSON.stringify(value));
assert.equal(model.results(tracks,'','','').length,0,'results must start empty');
assert.deepEqual(json(model.genres(tracks)).find(x=>x.key==='Jazz'),{key:'Jazz',count:3});
assert.equal(model.results(tracks,'genre','Jazz','').length,3);
assert.equal(model.results(tracks,'genre','','').length,1);
assert.deepEqual(json(model.results(tracks,'genre',['Jazz','Fusion'],'')).map(e=>e.track.uri),
 ['Jazz/Live/one.flac','Jazz/two.flac','root.flac'],'genre union preserves order without duplicate tracks');
assert.equal(model.results(tracks,'genre',[],'').length,0,'deselected genres leave no phantom results');
assert.equal(model.results(tracks,'genre',[''],'').length,1,'unknown genre is a selectable value');
assert.deepEqual(json(model.results(tracks,'folder','',['Jazz','Jazz/Live'])).map(model.key),
 ['d:Jazz/Live','t:Jazz/two.flac','t:Jazz/Live/one.flac']);
assert.equal(model.results(tracks,'folder','',[]).length,0,'deselected folders leave no phantom results');
let sources=model.selectValues(['','Jazz','Rock'],[],-1,0,false,false);
sources=model.selectValues(['','Jazz','Rock'],sources.keys,sources.anchor,2,true,false);
assert.deepEqual(json(sources.keys),['','Rock'],'Ctrl supports unknown/root values');
sources=model.selectValues(['','Jazz','Rock'],sources.keys,sources.anchor,0,false,true);
assert.deepEqual(json(sources.keys),['','Jazz','Rock'],'Shift selects a source range');
sources=model.selectValues(['','Jazz','Rock'],sources.keys,sources.anchor,1,true,false);
assert.deepEqual(json(sources.keys),['','Rock'],'Ctrl deselects only the clicked source');
const jazz=json(model.contents(tracks,'/Jazz/'));
assert.deepEqual(jazz.map(x=>x.kind),['folder','track']);
assert.equal(jazz[0].path,'Jazz/Live');assert.equal(jazz[1].track.uri,'Jazz/two.flac');
assert.equal(model.contents(tracks,'Jazz/Live')[0].track,tracks[0],'keep track identity for playback');
assert.equal(model.contents(tracks,'Jazz').some(x=>x.name==='Three'),false,'prefix sibling must stay out');
assert.ok(model.roots(tracks).some(x=>x.path==='__proto__'),'path keys must not become object prototypes');
assert.ok(model.roots(tracks).some(x=>x.path===''),'root files remain reachable');
assert.equal(model.parent('Jazz/Live'),'Jazz');assert.equal(model.parent('Jazz'),'');
assert.deepEqual(json(model.genres([undefined,...tracks])),json(model.genres(tracks)));
assert.equal(model.trackFolder({uri:'a/b/c.flac'}),'a/b');
const entries=model.results(tracks,'genre','Jazz','');
let selection=model.select(entries,[],-1,0,false,false);
selection=model.select(entries,selection.keys,selection.anchor,1,true,false);
assert.equal(selection.keys.length,2);
assert.equal(model.selectedTracks(tracks,selection.keys).length,2);
selection=model.select(entries,selection.keys,selection.anchor,2,false,true);
assert.equal(selection.keys.length,2,'Shift selects the anchored range');
assert.equal(model.selectedTracks(tracks,['d:Jazz']).length,2,'selected folder excludes Jazzical');
assert.equal(model.selectedTracks(tracks,['d:Jazz','t:Jazz/two.flac']).length,2,'selected files and folders must not duplicate playback');
assert.equal(model.matching(tracks,'LiVe')[0],tracks[0],'search preserves playback identity');
console.log('DASHBOARD_MUSIC_MODEL_PASS empty/genre/folder/drilldown/Unicode/root-files/prefix-boundary/identity/immutable-input');

const queue = [
 {uri:'__proto__',title:'One',artist:'Nhóm Đá',folder:'First',genre:'A'},
 {uri:'__proto__',title:'Two',artist:'Other',folder:'Second',genre:'B'},
 {path:'constructor',title:'Three',folder:'Third'},
 {uri:'',title:'Four',folder:'Fourth'},
 {uri:'',title:'Five',folder:'Fifth'}
];
const queueIndex = model.createIndex(queue);
assert.equal(model.genres(queue,queueIndex),model.genres(queue,queueIndex));
assert.equal(model.contents(queue,'',queueIndex),model.contents(queue,'/',queueIndex));
for (const row of queue) {
 const result = model.search(queueIndex,row.title);
 assert.equal(result.length,1);
 assert.equal(result[0],row,'duplicate or empty URI must retain the matching queue item');
 assert.equal(model.contents(queue,row.folder,queueIndex)[0].track,row);
}
assert.equal(model.search(queueIndex,'nhom')[0],queue[0]);
assert.equal(model.search(queueIndex,'nhom da')[0],queue[0]);
assert.equal(model.search(queueIndex,'Nhó')[0],queue[0],'shorter query is recomputed');
assert.equal(model.search(queueIndex,''),queue);
const nextQueue = [{...queue[0],artist:'Replacement'}];
const nextIndex = model.createIndex(nextQueue);
assert.equal(model.search(nextIndex,'nhom').length,0);
assert.equal(model.search(nextIndex,'replacement')[0],nextQueue[0]);

// Sonora helper tests: formatDuration, totalDuration, albums, artists, sortEntries
assert.equal(model.formatDuration(0),'0:00');
assert.equal(model.formatDuration(-5),'0:00');
assert.equal(model.formatDuration(65),'1:05');
assert.equal(model.formatDuration(3661),'1:01:01');
const catalog = [
 {uri:'a/1.flac',folder:'A',title:'Zeta',artist:'Beta',album:'First',duration:120,art:'/art/1.png'},
 {uri:'a/2.flac',folder:'A',title:'Alpha',artist:'Beta',album:'First',duration:95,artUrl:'file:///art/1.png'},
 {uri:'b/3.flac',folder:'B',title:'Mid',artist:'Alpha',album:'__proto__',duration:200}
];
const catIdx = model.createIndex(catalog);
assert.equal(model.totalDuration(catalog),415);
const albumCards = model.albums(catalog,catIdx);
assert.equal(model.albums(catalog,catIdx),albumCards,'album cache must return identical array');
assert.equal(albumCards.length,2);
assert.equal(albumCards[0].name,'__proto__');
assert.equal(albumCards[1].name,'First');
assert.equal(albumCards[1].artist,'Beta');
assert.equal(albumCards[1].trackCount,2);
assert.equal(albumCards[1].totalDuration,215);
assert.equal(albumCards[1].tracks[0],catalog[0],'album tracks preserve source identity');
const artistCards = model.artists(catalog,catIdx);
assert.equal(model.artists(catalog,catIdx),artistCards,'artist cache must return identical array');
assert.equal(artistCards[0].name,'Alpha');
assert.equal(artistCards[0].albumCount,1);
assert.equal(artistCards[1].name,'Beta');
assert.equal(artistCards[1].trackCount,2);
const trackEntries = catalog.map(t=>({kind:'track',track:t,name:t.title}));
assert.deepEqual(model.sortEntries(trackEntries,'title',true).map(e=>e.track.title),['Alpha','Mid','Zeta']);
assert.deepEqual(model.sortEntries(trackEntries,'title',false).map(e=>e.track.title),['Zeta','Mid','Alpha']);
assert.deepEqual(model.sortEntries(trackEntries,'duration',true).map(e=>e.track.duration),[95,120,200]);
console.log('DASHBOARD_MUSIC_MODEL_SONORA_PASS');
