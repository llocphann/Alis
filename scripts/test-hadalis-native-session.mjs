import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {spawnSync} from "node:child_process";
import {fileURLToPath} from "node:url";
import {projectTurn, installedContract, inspectInstalledScopeContract} from "../automation/chat_bridge/native_adapter.mjs";
const message = (id, role, status, end, text, recipient = "all", channel = null) =>
  ({id, author:{role}, status, end_turn:end, recipient, channel, content:{parts:[text]}});
const c = {conversation_id:"chat-A",current_node:"a",mapping:{
  u:{id:"u",parent:null,message:message("u","user","finished_successfully",true,"HADALIS_LOOP:DONE")},
  a:{id:"a",parent:"u",message:message("a","assistant","in_progress",false,"HADALIS_LOOP:DONE")}}};
const p = {conversation_id:"chat-A",user_message_id:"u"};
assert.equal(projectTurn(c,p).completed,false); // A marker while streaming is not completion.
c.mapping.a.message.status="finished_successfully";
assert.equal(projectTurn(c,p).completed,false); // Tool/computation partial is not final.
c.mapping.a.message.end_turn=true;
assert.equal(projectTurn(c,p).response.message_id,"a");
assert.equal(projectTurn(c,{...p,user_message_id:"other"}).submitted,false);
assert.throws(()=>projectTurn(c,{...p,conversation_id:"chat-B"}),/identity/);
c.mapping.a.message.recipient="functions.exec";
assert.equal(projectTurn(c,p).completed,false);
c.mapping.a.message.recipient="all";
c.mapping.a.message.status="error";
assert.equal(projectTurn(c,p).streamError,true);
assert.equal(projectTurn(c,p).terminal_failed,true);
c.mapping.a.message.end_turn=false;
assert.equal(projectTurn(c,p).terminal_failed,false);
c.mapping.b={id:"b",parent:"a",message:message("b","user","finished_successfully",true,"next")};
c.mapping.z={id:"z",parent:"b",message:message("z","assistant","finished_successfully",true,"HADALIS_LOOP:DONE")};c.current_node="z";
assert.equal(projectTurn(c,p).completed,false); // Never consume the next user's reply.
assert.equal(projectTurn(c,p).superseded,true);
assert.equal(projectTurn(c,p).successor_user_message_id,"b");
assert.equal(projectTurn(c,{...p,user_message_id:"b"}).response.message_id,"z");
// Construct an intentionally incompatible tiny ASAR-like fixture containing
// no app credentials or actual Desktop source. Unsupported contracts must be
// rejected locally before Playwright/CDP is imported or a message is sent.
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "alis-native-contract-"));
try {
  const archivePath = path.join(temp, "app.asar");
  const initial = Buffer.from("function harmlessFixture() {}");
  const shared = Buffer.from("export {}");
  const entries = {
    "app-initial-fixture.js": {size: initial.length, offset: "0"},
    "app-shared-fixture.js": {size: shared.length, offset: String(initial.length)}
  };
  const tree = {files:{webview:{files:{assets:{files:entries}}}}};
  const jsonHeader = Buffer.from(JSON.stringify(tree));
  const header = Buffer.alloc(16);
  header.writeUInt32LE(8 + jsonHeader.length, 4);
  header.writeUInt32LE(jsonHeader.length, 12);
  fs.writeFileSync(archivePath, Buffer.concat([header, jsonHeader, initial, shared]));
  const prior = process.env.HADALIS_DESKTOP_ASAR;
  process.env.HADALIS_DESKTOP_ASAR = archivePath;
  try {
    assert.throws(() => installedContract(), /unsupported Desktop stream contract: conversation-call, api-export, transport-scope, stream-method/);
    const check = inspectInstalledScopeContract();
    assert.equal(check.supported, false);
    assert.equal(check.purpose, "structure-only");
    assert.equal(check.scope_binding_count_bounded, 0);
    assert.equal(check.generalized_pattern_count, 0);
    assert.deepEqual(check.scope_shapes, []);
    assert.equal(check.stream_anchor_count_bounded, 0);
    assert.deepEqual(check.stream_neighborhoods, []);
  } finally {
    if (prior == null) delete process.env.HADALIS_DESKTOP_ASAR;
    else process.env.HADALIS_DESKTOP_ASAR = prior;
  }
  const cliPath = fileURLToPath(new URL("../automation/chat_bridge/native_cli.mjs", import.meta.url));
  const before = Date.now();
  const result = spawnSync(process.execPath, [cliPath], {
    input: '{"op":"probe"}', encoding: "utf8", timeout: 3500,
    env: {...process.env,
      HADALIS_DESKTOP_ASAR: archivePath,
      HADALIS_PLAYWRIGHT_MODULE: "file:///unavailable-playwright/module.mjs",
      HADALIS_CHATGPT_CDP_URL: "http://127.0.0.1:9"}
  });
  assert.equal(result.status, 1, String(result.error ?? ""));
  assert.equal(result.stdout, "");
  assert.match(result.stderr, /DESKTOP_CAPABILITY_UNAVAILABLE/);
  assert.ok(Date.now() - before < 3500, "contract check must fail before CDP");
  // Positive structural fixture: report a possible binding shape, but never
  // include a mock secret, constructor name, or raw module source.
  const sample = Buffer.from(
    'var z=0,T=mk($,({scope:e})=>new Foo(e));const secret="ghp_PRIVATE_FIXTURE_SECRET";async startCompletionStream('
  );
  const syntheticEntries = {
    "app-initial-fixture.js": {size: sample.length, offset: "0"},
    "app-shared-fixture.js": {size: shared.length, offset: String(sample.length)}
  };
  const syntheticTree = {files:{webview:{files:{assets:{files:syntheticEntries}}}}};
  const syntheticJson = Buffer.from(JSON.stringify(syntheticTree));
  const syntheticHeader = Buffer.alloc(16);
  syntheticHeader.writeUInt32LE(8 + syntheticJson.length, 4);
  syntheticHeader.writeUInt32LE(syntheticJson.length, 12);
  fs.writeFileSync(archivePath,
    Buffer.concat([syntheticHeader, syntheticJson, sample, shared]));
  const inspectPrior = process.env.HADALIS_DESKTOP_ASAR;
  process.env.HADALIS_DESKTOP_ASAR = archivePath;
  try {
    const report = inspectInstalledScopeContract();
    assert.equal(report.supported, false);
    assert.equal(report.scope_binding_count_bounded, 1);
    assert.equal(report.generalized_pattern_count, 1);
    assert.equal(report.stream_method_present, true);
    assert.equal(report.scope_shapes.length, 1);
    assert.equal(report.stream_anchor_count_bounded, 1);
    assert.equal(report.stream_neighborhoods.length, 1);
    assert.ok(report.stream_neighborhoods[0].method_shape.includes("async"));
    assert.ok(report.stream_neighborhoods[0].scope_bindings_within_12k >= 1);
    const json = JSON.stringify(report);
    assert.ok(!json.includes("PRIVATE_FIXTURE_SECRET"));
    assert.ok(!json.includes("ghp_"));
    assert.ok(!json.includes("Foo"));
    assert.ok(!json.includes("T=mk"));
    assert.ok(!json.includes("secret"));
    assert.ok(!json.includes("app-initial"));
  } finally {
    if (inspectPrior == null) delete process.env.HADALIS_DESKTOP_ASAR;
    else process.env.HADALIS_DESKTOP_ASAR = inspectPrior;
  }
} finally {
  fs.rmSync(temp, {recursive:true, force:true});
}
if (process.env.HADALIS_TEST_INSTALLED_DESKTOP === "1") assert.ok(installedContract().api);
console.log("PASS: conversation identity, final message receipt, no cross-turn completion, native incompatible Desktop fail-fast");
