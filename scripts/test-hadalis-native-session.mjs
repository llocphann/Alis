import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {spawnSync} from "node:child_process";
import {fileURLToPath} from "node:url";
import {projectTurn, reconcileSubmissionCandidates, installedContract, inspectInstalledScopeContract} from "../automation/chat_bridge/native_adapter.mjs";
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
// AUTO-F01 production receipt hardening: corrupt/ambiguous branches never
// complete a managed turn. A node key is not a user-authored message identity.
const source=()=>({conversation_id:"chat-A",current_node:"final",mapping:{
  root:{id:"root",parent:null,message:message("actual-user","user",
    "finished_successfully",true,"PRIVATE_USER_BODY")},
  final:{id:"final",parent:"root",message:message("response-1","assistant",
    "finished_successfully",true,"HADALIS_LOOP:DONE")}
}});
const expected={conversation_id:"chat-A",user_message_id:"actual-user"};
assert.equal(projectTurn(source(),expected).response.message_id,"response-1");
assert.equal(projectTurn(source(),{...expected,user_message_id:"root"}).submitted,false,
  "node IDs must never attest authored user messages");
const spoof=source();
spoof.mapping.root.id="spoof-user";
spoof.mapping.root.message.author.role="assistant";
assert.equal(projectTurn(spoof,{...expected,user_message_id:"spoof-user"}).submitted,false,
  "an assistant cannot impersonate the submitted user");
assert.throws(()=>projectTurn({...source(),conversation_id:undefined},expected),/identity/);
assert.throws(()=>projectTurn(source(),{...expected,conversation_id:null}),/identity/);
assert.throws(()=>projectTurn(source(),{...expected,user_message_id:null}),/identity/);
const orphan=source();orphan.mapping.root.parent="missing";
assert.throws(()=>projectTurn(orphan,expected),/incomplete|cyclic/);
const cycle=source();cycle.mapping.root.parent="final";
assert.throws(()=>projectTurn(cycle,expected),/incomplete|cyclic/);
const missingCurrent=source();missingCurrent.current_node="ghost";
assert.throws(()=>projectTurn(missingCurrent,expected),/incomplete|cyclic/);
const brokenParent=source();brokenParent.mapping.root.parent=undefined;
assert.throws(()=>projectTurn(brokenParent,expected),/invalid parent/);
const noMapping=source();delete noMapping.mapping;
assert.throws(()=>projectTurn(noMapping,expected),/unavailable/);
const missingNode=source();missingNode.mapping.final=null;
assert.throws(()=>projectTurn(missingNode,expected),/invalid node/);
const duplicateUser=source();
duplicateUser.mapping.extra={id:"extra",parent:"root",message:
  message("actual-user","user","finished_successfully",true,"dupe")};
duplicateUser.mapping.final.parent="extra";
assert.throws(()=>projectTurn(duplicateUser,expected),/duplicate user/);
const doubleFinal=source();
doubleFinal.mapping.final2={id:"final2",parent:"final",message:
  message("response-2","assistant","finished_successfully",true,"extra final")};
doubleFinal.current_node="final2";
assert.throws(()=>projectTurn(doubleFinal,expected),/ambiguous terminal/);
const untrustedBranch=source();
untrustedBranch.mapping.forged={id:"forged",parent:null,message:
  message("actual-user","user","finished_successfully",true,"off branch")};
untrustedBranch.mapping.root.message.id="different-user";
assert.equal(projectTurn(untrustedBranch,expected).submitted,false);
const finalFromNextUser=source();
finalFromNextUser.mapping.followup={id:"followup",parent:"root",message:
  message("user-2","user","finished_successfully",true,"follow-up")};
finalFromNextUser.mapping.final.parent="followup";
assert.equal(projectTurn(finalFromNextUser,expected).completed,false);
assert.equal(projectTurn(finalFromNextUser,expected).superseded,true);
assert.equal(projectTurn(finalFromNextUser,
  {...expected,user_message_id:"user-2"}).response.message_id,"response-1");

// Reconciliation scans bounded server snapshots; a node ID, off-branch
// user, duplicate candidate or in-memory hint is never sufficient.
const reconMessage="33333333-3333-4333-8333-333333333333";
const chatA="11111111-1111-4111-8111-111111111111";
const chatB="22222222-2222-4222-8222-222222222222";
const recon={user_message_id:reconMessage};
const candidate=(chat,id=reconMessage)=>({
  conversation_id:chat,current_node:"a",mapping:{
    u:{id:"u",parent:null,message:
      message(id,"user","finished_successfully",true,"PRIVATE")},
    a:{id:"a",parent:"u",message:
      message("assistant","assistant","finished_successfully",true,"DONE")}
  }
});
assert.deepEqual(reconcileSubmissionCandidates(recon,[candidate(chatA)]),
  {conversation_id:chatA});
assert.deepEqual(reconcileSubmissionCandidates(recon,[candidate(chatA,"other")]),
  {conversation_id:null});
assert.deepEqual(reconcileSubmissionCandidates(recon,[
  candidate(chatA,"other"),candidate(chatB)]),{conversation_id:chatB});
assert.throws(()=>reconcileSubmissionCandidates(recon,[
  candidate(chatA),candidate(chatB)]),/ambiguous user message/);
assert.throws(()=>reconcileSubmissionCandidates(recon,[
  candidate(chatA),candidate(chatA)]),/ambiguous candidate/);
assert.throws(()=>reconcileSubmissionCandidates(
  {user_message_id:"invalid"},[candidate(chatA)]),/invalid pending/);
assert.throws(()=>reconcileSubmissionCandidates(
  recon,Array(13).fill(candidate(chatA))),/bounded/);
const candidateSpoof=candidate(chatA,"actual");
candidateSpoof.mapping.u.id=reconMessage;
assert.equal(reconcileSubmissionCandidates(recon,[candidateSpoof]).conversation_id,
  null,"node-key forgery cannot prove user submit");
const candidateOffBranch=candidate(chatA,"other");
candidateOffBranch.mapping.orphan={id:"orphan",parent:null,
  message:message(reconMessage,"user","finished_successfully",true,"PRIVATE")};
assert.equal(reconcileSubmissionCandidates(recon,[candidateOffBranch]).conversation_id,
  null,"off-branch user is not the submitted turn");
const candidateBroken=candidate(chatA);
candidateBroken.mapping.u.parent="missing";
assert.throws(()=>reconcileSubmissionCandidates(recon,[candidateBroken]),
  /incomplete|cyclic/);
const candidateWrongRole=candidate(chatA);
candidateWrongRole.mapping.u.message.author.role="assistant";
assert.equal(reconcileSubmissionCandidates(recon,[candidateWrongRole])
  .conversation_id,null);

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
    'var z=0,T=mk($,({scope:e})=>new Foo(e));const secret="ghp_PRIVATE_FIXTURE_SECRET";async startCompletionStream();export{T as safeExport}'
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
    assert.equal(report.scoped_constructor_callbacks_count, 1);
    assert.equal(report.stream_neighborhoods[0].scoped_constructor_candidates.count_in_12k, 1);
    assert.equal(report.stream_neighborhoods[0].scoped_constructor_candidates.exported_in_12k, 1);
    assert.equal(report.stream_neighborhoods[0].scoped_constructor_candidates.nearest[0].export_binding_present, true);
    // Source-only evidence must NEVER enable a managed conversation.
    assert.equal(report.supported, false);
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
