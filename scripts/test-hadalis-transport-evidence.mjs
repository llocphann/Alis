#!/usr/bin/env node
/* AUTO-F01 offline policy fixture. No renderer, CDP, resolver, API or send. */
import assert from "node:assert/strict";
import {assessNativeTransportEvidence} from
  "../automation/chat_bridge/transport_evidence.mjs";
const observed = {
  fingerprint_prefix:"8ff0fd9c4b19",
  supported:false,submission_authorized:false,
  provider_selection:"active_provider_ambiguous",
  active_provider_map_count_capped:7,
  resolution_attempted:false,
  resolver_invocation_permitted:false,
  static_helper_links:{
    resolver_source_location:"unique-in-shared",
    helper_identity_relation:"distinct",
    static_binding_match_complete:true,
    secondary_helper:{
      map_write_syntax_present:true,
      side_effect_freedom_proven:false,
      map_write_unknown_sites:[{receiver_form:"bare-identifier",
        receiver_initializer_kind:"new-map-token-no-args",
        alias_trace:{origin_hint:"new-map-token-no-args-unverified"}}]
    }
  }
};
const evidence=assessNativeTransportEvidence(observed);
assert.equal(evidence.status,"blocked");
assert.equal(evidence.supported,false);
assert.equal(evidence.submission_authorized,false);
assert.equal(evidence.live_transport_verified,false);
assert.equal(evidence.project_conversation_verified,false);
assert.equal(evidence.receipts_verified,false);
assert.equal(evidence.fingerprint_syntax_present,true);
assert.equal(evidence.static_helper_shape_matched,true);
assert.deepEqual(evidence.blocker_codes,[
  "ACTIVE_PROVIDER_MAP_AMBIGUOUS",
  "RESOLVER_SIDE_EFFECTS_NOT_PROVEN",
  "SECONDARY_HELPER_WRITE_SYNTAX_PRESENT",
  "MAP_CONSTRUCTOR_IDENTITY_UNVERIFIED",
  "NATIVE_TRANSPORT_CAPABILITY_UNVERIFIED",
  "EXACT_PROJECT_MEMBERSHIP_UNVERIFIED",
  "EXACT_CONVERSATION_IDENTITY_UNVERIFIED",
  "DURABLE_DISPATCH_RECEIPT_UNVERIFIED"
]);

// Even a mocked unique Map and syntactically distinct helpers cannot
// authorize resolver invocation, Project chat adoption or send.
const unique=assessNativeTransportEvidence({...observed,
  provider_selection:"unique_provider_resolver_not_invoked",
  active_provider_map_count_capped:1,
  static_helper_links:{...observed.static_helper_links,
    secondary_helper:{map_write_syntax_present:false,
      side_effect_freedom_proven:true,map_write_unknown_sites:[]}}
});
assert.ok(unique.blocker_codes.includes("PROVIDER_IDENTITY_NOT_PROVEN"));
assert.ok(unique.blocker_codes.includes("RESOLVER_SIDE_EFFECTS_NOT_PROVEN"));
assert.equal(unique.submission_authorized,false);

// An untrusted client cannot spoof transport readiness using a true flag.
const spoof=assessNativeTransportEvidence({...observed,
  supported:true,submission_authorized:true,
  live_transport_verified:true,project_verified:true,
  conversation_verified:true,receipt_verified:true});
assert.equal(spoof.submission_authorized,false);
assert.equal(spoof.live_transport_verified,false);
assert.ok(spoof.blocker_codes.includes("EXACT_PROJECT_MEMBERSHIP_UNVERIFIED"));

const invoked=assessNativeTransportEvidence({...observed,
  resolution_attempted:true,resolver_invocation_permitted:true});
assert.ok(invoked.blocker_codes.includes(
  "READ_ONLY_CONTRACT_VIOLATION_RESOLVER_INVOKED"));
assert.ok(invoked.blocker_codes.includes(
  "READ_ONLY_CONTRACT_VIOLATION_RESOLVER_ALLOWED"));

const absent=assessNativeTransportEvidence(null);
assert.equal(absent.status,"blocked");
assert.ok(absent.blocker_codes.includes(
  "INSTALLED_BUILD_FINGERPRINT_UNVERIFIED"));
assert.ok(absent.blocker_codes.includes(
  "READ_ONLY_RESOLVER_STATE_UNVERIFIED"));
assert.ok(absent.blocker_codes.includes("STATIC_HELPER_LINKAGE_INCOMPLETE"));

const malformed=assessNativeTransportEvidence({...observed,
  static_helper_links:{...observed.static_helper_links,
    secondary_helper:{map_write_unknown_sites:"private:ghp_TEST_TOKEN"}},
  fingerprint_prefix:"ghp_PRIVATE_TEST"});
assert.equal(malformed.fingerprint_syntax_present,false);
assert.equal(malformed.submission_authorized,false);

const output=JSON.stringify([evidence,unique,spoof,invoked,absent,malformed]);
for (const secret of ["ghp_", "PRIVATE_TEST", "private:",
  "Automatic Alis", "conversation-123", "project-456"]) {
  assert.ok(!output.includes(secret),"report leaked private data: "+secret);
}
console.log("PASS AUTO-F01: transport acceptance evidence fail closed, redacted, no runtime access");
