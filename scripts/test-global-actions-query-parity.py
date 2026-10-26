#!/usr/bin/env python3
"""Exact query scoring, action identity and read order with one tokenization."""
import json
import re
import subprocess
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "services/GlobalActions.qml").read_text()
new = re.search(r"^    function fuzzyQuery\(.*?^    }", source, re.M | re.S)[0]
new = re.sub(r"function fuzzyQuery\(query: string\): list<var>", "function fuzzyQuery(query, allActions)", new)
old = (ROOT / "scripts/fixtures/global-actions-fuzzy-reference.js").read_text().split("\n", 2)[2]
program = r'''
const vm=require('node:vm'), assert=require('node:assert/strict');
function runner(code) {
 const context={splits:0,splitWords:q=>{context.splits++;return q.split(/\s+/)}};
 vm.createContext(context);vm.runInContext(code.replace('q.split(/\\s+/)','splitWords(q)'),context);
 return context;
}
const before=runner(OLD),after=runner(NEW),queries=['',' ',null,'theme','ai chat','  WALL\tPAPER  ','é','aqua octo','fixture','no-match','ß','🦑'];
let cases=0,saved=0;
for(const size of [0,1,8,32,96])for(const sparse of [false,true])for(let epoch=0;epoch<8;epoch++) {
 let reads=[];
 const catalog=Array.from({length:size},(_,i)=>{
  const values={id:i%2?'wallpaper-'+i:'fixture-'+i,name:i%3?'AI Chat '+i:'Theme',description:i%4?'Aqua Octo':'é ß',keywords:['theme','fixture','ai','🦑']};
  if(epoch%3===0)delete values.description;
  const action={execute:()=>i};
  for(const key of ['id','name','description','keywords'])Object.defineProperty(action,key,{get(){reads.push(i+':'+key);return values[key]}});
  return action;
 });
 if(sparse)for(let i=2;i<size;i+=4)delete catalog[i];
 for(const query of queries) {
  reads=[];before.splits=0;const expected=before.fuzzyQuery(query,catalog),oldReads=reads.slice();
  reads=[];after.splits=0;const actual=after.fuzzyQuery(query,catalog);
  assert.deepEqual(reads,oldReads,'metadata read order changed');assert.equal(actual.length,expected.length);
  for(let i=0;i<actual.length;i++){
   assert.equal(i in actual,i in expected,'sparse result topology changed');
   assert.equal(actual[i],expected[i]);if(actual[i])assert.equal(actual[i].execute,expected[i].execute);
  }
  if(!query || query.trim()==='')assert.equal(actual,catalog,'empty-query catalog identity changed');
  assert.equal(before.splits,query && query.trim() ? catalog.filter(Boolean).length : 0,'baseline split instrumentation missed a call');
  assert.equal(after.splits,before.splits?1:0,'empty catalog tokenized, or repeated tokenization remains');
  saved+=before.splits-after.splits;cases++;
 }
}
console.log('GLOBAL_ACTION_QUERY_NODE_PASS',cases,'exact refs/order/read phases/empty identity; avoided',saved,'repeated splits');
'''
subprocess.run(["node", "-e", "const OLD=" + json.dumps(old) + ";const NEW=" + json.dumps(new) + ";\n" + program], check=True, cwd=ROOT)

with tempfile.TemporaryDirectory(prefix="alis-global-action-query-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import "scripts/fixtures/global-actions-fuzzy-reference.js" as Legacy
ShellRoot {
    Component.onCompleted: Quickshell.watchFiles = false
    TestCase {
        id: test; when: false; optional: true
        function check(value, message) { if (!value) throw new Error(message) }
        function runChecks() {
            try {
                tryCompare(Config, "ready", true, 4000)
                const providers = ["System","Appearance","Tools","Media","Settings","Packages","Setup","Custom"]
                const queries = [""," ","theme","AI CHAT","wall paper","fixture","tab\tline","é","aqua octo","no-match","  battery "]
                let cases = 0, largest = 0
                for (const custom of [false,true]) for (const setup of [false,true]) {
                    GlobalActions._userScriptActions = custom ? [
                        {id:"custom-fixture-a",name:"Fixture",description:"AI Chat",keywords:["fixture","é"],execute:()=>1},
                        {id:"custom-fixture-b",name:"Fixture",description:"AI Chat",keywords:["fixture","é"],execute:()=>2}] : []
                    GlobalActions._setupTargets = setup ? [{slug:"fixture",name:"Fixture setup",description:"Theme",keywords:"aqua octo"}] : []
                    for (const mode of ["all","none","custom","settings","media"]) {
                        const updates = {}
                        for (const provider of providers) updates["search.globalActions.enable"+provider] = mode==="all" || mode===provider.toLowerCase()
                        Config.setNestedValues(updates);wait(60)
                        const catalog = GlobalActions.allActions
                        largest = Math.max(largest,catalog.length)
                        for (const query of queries) {
                            const expected = Legacy.fuzzyQuery(query,catalog),actual = GlobalActions.fuzzyQuery(query)
                            check(actual.length===expected.length,"QV4 result count changed")
                            for (let i=0;i<actual.length;i++)
                                check(actual[i]===expected[i] && actual[i].execute===expected[i].execute,
                                    "QV4 action order/reference/execute closure changed at "+mode+" "+query)
                            cases++
                        }
                    }
                }
                console.info("GLOBAL_ACTION_QUERY_QV4_PASS",cases,"actual service searches; maximum catalog",largest,"provider changes, custom/setup publication, empty queries and exact closure identities")
            } catch (e) { console.error("GLOBAL_ACTION_QUERY_QV4_FAIL", e.message, e.stack) }
            Qt.quit()
        }
    }
    Timer { interval:100;running:true;onTriggered:test.runChecks() }
}
''')
    with private_wayland(folder) as env:
        if env is None:
            print("SKIP: actual service QV4 oracle requires private Niri")
            raise SystemExit(0)
        config = folder / "config/illogical-impulse/config.json"
        config.parent.mkdir()
        config.write_text((ROOT / "defaults/config.json").read_text())
        env["QT_QUICK_BACKEND"] = "software"
        result = run_qs(folder, env, 20)
        bad = ["GLOBAL_ACTION_QUERY_QV4_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "Failed to load configuration"]
        if result.returncode or "GLOBAL_ACTION_QUERY_QV4_PASS" not in result.stdout or any(s in result.stdout for s in bad):
            print(result.stdout)
            raise SystemExit(1)
        print(next(line for line in result.stdout.splitlines() if "GLOBAL_ACTION_QUERY_QV4_PASS" in line))
