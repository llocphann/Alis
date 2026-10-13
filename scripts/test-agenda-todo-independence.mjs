#!/usr/bin/env node
// Agenda and Todo must no longer create, update or delete each other.
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
const read=path=>fs.readFileSync(new URL("../"+path,import.meta.url),"utf8");
const service=read("services/Events.qml");
const todo=read("services/Todo.qml");
const internal=read("services/InternalTodoBackend.qml");
const dashboardTodo=read("modules/dashboard/DashTodo.qml");
const card=read("modules/sidebarRight/events/EventCard.qml");
const planner=read("modules/dashboard/DashboardWeeklyPlanner.qml");
const editor=read("modules/sidebarRight/events/EventsDialog.qml");
assert.doesNotMatch(service,/AgendaTodoPolicy|newLink\(|_notifyAgendaLinks|_queueTodoUnlink|setTodoLink\(|unlinkTodo\(/);
assert.doesNotMatch(todo,/_reconcileAgenda|_startExternalAgenda|_deferAgendaDeletion|ensureAgenda\(|retryAgendaLinks|agendaStatus\(|agendaError|_scheduleAgenda/);
assert.doesNotMatch(service,/todoLink\s*:\s*AgendaTodoPolicy|_queueTodoUnlink|setTodoLink\(/);
assert.doesNotMatch(todo,/onAgendaMutationFinished|agendaMutationFinished/);
assert.doesNotMatch(internal,/AgendaTodoPolicy|function ensureAgenda\\(|function unlinkAgenda\\(/);
assert.doesNotMatch(dashboardTodo,/modelData\\.agenda|text:"link"/);
// Historical task metadata is retained as inert data, never translated into a new link.
const normalizeStart=internal.indexOf("    function _normalizeList(value) {");
const normalizeEnd=internal.indexOf("    function addItem(item) {",normalizeStart);
assert.ok(normalizeStart>=0 && normalizeEnd>normalizeStart);
const normalize=new Function("return "+internal.substring(normalizeStart,normalizeEnd))();
const legacyTask={content:"Saved task",done:true,notes:"Mine",agenda:{
  version:1,key:"agenda-legacy-test-001",eventId:23}};
const historic=normalize([legacyTask]);
assert.deepEqual(JSON.parse(JSON.stringify(historic[0].agenda)),legacyTask.agenda,
  "existing Agenda metadata is preserved without any sync worker");
assert.equal(fs.existsSync(new URL("../services/AgendaTodoPolicy.js",import.meta.url)),false);
assert.doesNotMatch(card,/AgendaTodoLink/);
assert.doesNotMatch(planner,/Todo\.agendaStatus/);
assert.doesNotMatch(editor,/plannerRepeatConflictHint/);
assert.match(editor,/Events\.updateEventGroup\(root\.editingEvent\.id/);
assert.match(editor,/canonical\.repeatTemplate/);
assert.match(editor,/root\.plannerSelectedDateKeys=selectedKeys\.length/);
const O=vm.runInNewContext(read("services/EventOccurrences.js")
  +";({entry,entries,store,compatible,append})",{});
const R=vm.runInNewContext(read("services/EventRepeatPolicy.js")
  +";({allowed,templateAllowed,nextCycle})",{});
function bind(method,next,dependencies) {
 const a=service.indexOf("    function "+method+"(");
 const b=service.indexOf(next,a);
 assert.ok(a>=0&&b>a,method+" body missing");
 return new Function("root","Occurrences","RepeatPolicy",
   "return "+service.substring(a,b))(dependencies,O,R);
}
let saved=0,added=0,updated=0;
const store={ready:true,nextId:10,list:[],
  saveToFile(){saved++},eventAdded(){added++},eventUpdated(){updated++}};
const add=bind("addEvent","    // Edit the entire explicitly-selected Event ID",store);
const edit=bind("updateEventGroup","    // Reschedule one stored occurrence.",store);
const slot=(y,m,d,h=9)=>{
 const start=new Date(y,m-1,d,h),end=new Date(y,m-1,d,h+1);
 return {startDate:start.toISOString(),endDate:end.toISOString()};
};
const rows=[slot(2032,10,19),slot(2032,10,21)];
const created=add("Wake up","Tuesdays and Thursdays",rows[0].startDate,
 "general","normal",15,"weekly",rows[0].endDate,false,rows);
assert.equal(store.list.length,1);
assert.equal(store.nextId,11);
assert.equal(added,1);
assert.ok(!Object.hasOwn(created,"todoLink"),"Agenda auto-created a Todo link");
assert.equal(created.occurrences.length,2);
assert.equal(created.repeatTemplate.length,2);
const stableId=created.id;
assert.equal(edit(stableId,{
  title:"Wake up earlier",description:"edited",category:"general",
  priority:"normal",reminderMinutes:15,recurrence:"weekly",allDay:false
},rows),true);
assert.equal(store.list.length,1);
assert.equal(store.list[0].id,stableId);
assert.equal(store.list[0].occurrences.length,2);
assert.equal(store.list[0].repeatTemplate.length,2);
assert.ok(!Object.hasOwn(store.list[0],"todoLink"));
assert.equal(updated,1);
const nextRows=[slot(2032,10,19,8),slot(2032,10,21,8)];
assert.equal(edit(stableId,{
  title:"Wake up earlier",description:"edited",category:"general",
  priority:"normal",reminderMinutes:15,recurrence:"weekly",allDay:false
},nextRows),true);
assert.equal(store.list.length,1);
assert.equal(store.list[0].id,stableId);
assert.equal(store.list[0].repeatTemplate[0].startDate,nextRows[0].startDate);
assert.equal(store.list[0].repeatTemplate[1].startDate,nextRows[1].startDate);
const originalAfter=JSON.stringify(store.list);
assert.equal(edit(stableId,{
  title:"Invalid",recurrence:"daily",allDay:false
},nextRows),false);
assert.equal(JSON.stringify(store.list),originalAfter,
 "invalid group edit must not partially change the Event");
const legacy={...created,id:99,todoLink:{version:1,key:"agenda-legacy",
  state:"linked",provider:"internal"}};
store.list.push(legacy);
assert.equal(edit(99,{
 title:"Legacy Agenda remains",description:"retained",
 category:"general",priority:"normal",reminderMinutes:15,
 recurrence:"weekly",allDay:false
},rows),true);
assert.deepEqual(JSON.parse(JSON.stringify(store.list[1].todoLink)),
 {version:1,key:"agenda-legacy",state:"linked",provider:"internal"},
 "pre-existing link metadata must not be rewritten or migrated");
assert.ok(saved>=4,"successful Agenda updates must remain persisted");
console.log("AGENDA_TODO_INDEPENDENCE_PASS: independent creation, legacy preservation, full group edits");
