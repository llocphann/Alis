#!/usr/bin/env node
import assert from "node:assert/strict";
import {analyzeStaticResolverHelpers} from
  "../automation/chat_bridge/static_helper_analysis.mjs";

const source = "resolve(provider,context){let a=make(provider,context,scope),b=a.cache.get(key);let c=build(context,scope);return b}";
const bundled = "function make(a,b,c){return {cache:new Map()}};" +
  "const build=(b,c)=>{};class C{" + source + "}";
const inspect = (initial,shared, resolverSource=source) =>
  analyzeStaticResolverHelpers({initial,shared,resolverSource});

let r = inspect(bundled,"");
assert.equal(r.resolver_source_location,"unique-in-initial");
assert.equal(r.resolver_signature,"two-distinct-arguments");
assert.equal(r.primary_helper.status,"unique-declaration");
assert.equal(r.primary_helper.kind,"function-declaration");
assert.equal(r.secondary_helper.status,"unique-declaration");
assert.equal(r.secondary_helper.kind,"arrow-function");
assert.equal(r.static_binding_match_complete,true);
assert.equal(r.primary_helper.body_inspection,"complete");
assert.equal(r.primary_helper.creates_objects_syntax_present,true);
assert.equal(r.primary_helper.side_effect_freedom_proven,false);
assert.equal(r.secondary_helper.body_inspection,"unsupported-binding-kind");
assert.equal(r.submission_authorized,false);
assert.equal(r.supported,false);
assert.equal(r.helper_identity_relation,"distinct");

// Desktop v8ff0... resolver assigns the fallback helper after an if's
// closing brace with no semicolon: ...return cached}let tmp=helper(context,scope).
// Missing "}" in the lexical boundary previously produced "not-found".
const afterIf = "resolve(provider,context){let a=make(provider,context,scope)," +
  "b=a.cache.get(key);if(b!==void 0){return b}" +
  "let c=build(context,scope);return c}";
const afterIfBundle = "function make(a,b,c){return {cache:new Map()}};" +
  "const build=(b,c)=>{};class C{" + afterIf + "}";
r=inspect(afterIfBundle,"",afterIf);
assert.equal(r.resolver_source_location,"unique-in-initial");
assert.equal(r.primary_helper.status,"unique-declaration");
assert.equal(r.secondary_helper.status,"unique-declaration");
assert.equal(r.secondary_helper.kind,"arrow-function");
assert.equal(r.helper_identity_relation,"distinct");
assert.equal(r.static_binding_match_complete,true);

// A declaration is still ambiguous if duplicated, including when the call
// after the block is recognized. Never pick a function just by location.
r=inspect(afterIfBundle+";function build(c,d){}","",afterIf);
assert.equal(r.secondary_helper.status,"ambiguous");
assert.equal(r.static_binding_match_complete,false);

// Never treat function bodies that merely lack direct writes as side-effect
// free. Detect lexical Map read/write syntax without calling the helpers.
const effectsSrc="resolve(p,c){let a=make(p,c,s),b=a.get(s);" +
  "let z=build(c,s);return b}";
const effectsBundle="function make(p,c,s){const map=new Map();" +
  "if(c.has(s)){map.set(s,c.get(s))}return map}" +
  "function build(c,s){let x=c;return x}" +
  "class Resolver{" + effectsSrc + "}";
r=inspect(effectsBundle,"",effectsSrc);
assert.equal(r.static_binding_match_complete,true);
assert.equal(r.primary_helper.body_inspection,"complete");
assert.equal(r.primary_helper.map_read_syntax_present,true);
assert.equal(r.primary_helper.map_write_syntax_present,true);
assert.equal(r.primary_helper.creates_objects_syntax_present,true);
assert.equal(r.primary_helper.side_effect_freedom_proven,false);
assert.equal(r.secondary_helper.body_inspection,"complete");
assert.equal(r.secondary_helper.map_write_syntax_present,false);
assert.equal(r.secondary_helper.side_effect_freedom_proven,false);

// Classify Map-write RECEIVER syntax only. It cannot establish whether a
// local Map later escapes into shared state or an indirect callee mutates it.
const originSource="resolve(p,c){let a=make(p,c,s),b=build(c,s);return b}";
const originBundle="function make(p,c,s){const fresh=new Map();" +
  "fresh.set(s,p);p.delete(s);shared.clear();" +
  "const nested=unknown.p.set(s);return fresh}" +
  "function build(c,s){return c};class C{"+originSource+"}";
r=inspect(originBundle,"",originSource);
assert.equal(r.static_binding_match_complete,true);
assert.equal(r.primary_helper.body_inspection,"complete");
assert.equal(r.primary_helper.map_write_origin_status,"lexical-classification-only");
assert.deepEqual(r.primary_helper.map_write_receiver_counts,{
  fresh_local_capped:1,direct_parameter_capped:1,other_or_unknown_capped:2
});
assert.equal(r.primary_helper.map_write_syntax_present,true);
assert.deepEqual(r.primary_helper.map_write_unknown_sites,[
  {receiver_form:"bare-identifier",receiver_initializer_kind:"not-found",
   owner_origin_hint:"not-applicable"},
  {receiver_form:"member-property",receiver_initializer_kind:"property-access",
   owner_origin_hint:"external-member"}
]);
assert.equal(r.primary_helper.map_write_unknown_sites_truncated,false);
assert.equal(r.primary_helper.side_effect_freedom_proven,false);
assert.equal(r.submission_authorized,false);

// Unknown writes may be via a local alias, a caller-owned parameter member,
// or an unbound/closure symbol. None is sufficient proof of safe mutation.
const shapeSrc="resolve(p,c){let a=make(p,c,s),b=build(c,s);return b}";
const shapeBody="function make(p,c,s){const alias=retrieve(c)," +
  " holder=retrieve(p),other=new Custom();" +
  "alias.set(s,c);holder.cache.set(s,p);p.store.clear();" +
  "other.delete(s);return alias}";
const shapeBundle=shapeBody+
  "function build(c,s){return c};class C{"+shapeSrc+"}";
r=inspect(shapeBundle,"",shapeSrc);
assert.equal(r.primary_helper.body_inspection,"complete");
assert.deepEqual(r.primary_helper.map_write_unknown_sites,[
  {receiver_form:"bare-identifier",receiver_initializer_kind:"helper-call-result",
   owner_origin_hint:"not-applicable"},
  {receiver_form:"member-property",receiver_initializer_kind:"property-access",
   owner_origin_hint:"local-member"},
  {receiver_form:"member-property",receiver_initializer_kind:"property-access",
   owner_origin_hint:"parameter-member"},
  {receiver_form:"bare-identifier",receiver_initializer_kind:"new-other",
   owner_origin_hint:"not-applicable"}
]);
assert.equal(r.primary_helper.map_write_unknown_sites_truncated,false);
assert.equal(r.primary_helper.side_effect_freedom_proven,false);
assert.ok(!JSON.stringify(r).includes("retrieve"));

// Owner's actual Desktop site is a bare identifier initialized through
// a lexical alias. Prove we never call any helper, reveal original symbols,
 // or treat an alias's origin as authorization to invoke the resolver.
function aliasFixture(body) {
  const src="resolve(p,c){let a=make(p,c,s),b=build(c,s);return b}";
  const bundle="function make(p,c,s){"+body+"}" +
    "function build(c,s){return c};class Resolver{"+src+"}";
  const result=inspect(bundle,"",src);
  assert.equal(result.static_binding_match_complete,true);
  assert.equal(result.submission_authorized,false);
  assert.equal(result.supported,false);
  assert.equal(result.primary_helper.side_effect_freedom_proven,false);
  return result.primary_helper.map_write_unknown_sites[0];
}
let aliasSite=aliasFixture("let receiver=p;receiver.set(s,c);return receiver");
assert.equal(aliasSite.receiver_initializer_kind,"identifier-alias");
assert.deepEqual(aliasSite.alias_trace,{
  origin_hint:"parameter",hops_capped:1
});
aliasSite=aliasFixture("const owned=new Map();let receiver=owned;" +
  "receiver.set(s,c);return receiver");
assert.deepEqual(aliasSite.alias_trace,{
  origin_hint:"new-map-syntax",hops_capped:1
});
aliasSite=aliasFixture("let external=source;let receiver=external;" +
  "receiver.set(s,c);return receiver");
assert.deepEqual(aliasSite.alias_trace,{
  origin_hint:"unresolved-external",hops_capped:2
});
// Future source initializers cannot be used to infer past alias origins.
aliasSite=aliasFixture("let receiver=future;let future=new Map();" +
  "receiver.set(s,c);return receiver");
assert.deepEqual(aliasSite.alias_trace,{
  origin_hint:"unresolved-external",hops_capped:1
});
aliasSite=aliasFixture("let receiver=receiver;" +
  "receiver.set(s,c);return receiver");
assert.deepEqual(aliasSite.alias_trace,{
  origin_hint:"cycle",hops_capped:1
});
aliasSite=aliasFixture("let source=compute(p);let receiver=source;" +
  "receiver.set(s,c);return receiver");
assert.deepEqual(aliasSite.alias_trace,{
  origin_hint:"helper-call-result",hops_capped:1
});
// Desktop's first alias attempt reached a compound expression at hop zero.
// Describe syntax without inferring that any branch returns an owned Map.
let complexSite=aliasFixture(
  "let receiver=p??new Map();receiver.set(s,c);return receiver"
);
assert.deepEqual(complexSite.alias_trace,{
  origin_hint:"complex-or-unsupported-expression",hops_capped:0,
  expression_form:"logical-or-coalescing",expression_scan_complete:true,
  contains_new_map_syntax:true,mentions_parameter_token:true,
  expression_token_shape:"id ?? new id ( )",
  expression_token_shape_complete:true
});
complexSite=aliasFixture(
  "let receiver=p?new Map():fallback;receiver.set(s,c);return receiver"
);
assert.equal(complexSite.alias_trace.expression_form,"conditional-ternary");
assert.equal(complexSite.alias_trace.contains_new_map_syntax,true);
assert.equal(complexSite.alias_trace.mentions_parameter_token,true);
complexSite=aliasFixture(
  "let receiver=(p);receiver.set(s,c);return receiver"
);
assert.equal(complexSite.alias_trace.expression_form,"parenthesized");
assert.equal(complexSite.alias_trace.expression_scan_complete,true);
complexSite=aliasFixture(
  "let receiver=p||secretOther;receiver.set(s,c);return receiver"
);
assert.equal(complexSite.alias_trace.expression_form,"logical-or-coalescing");
assert.equal(complexSite.alias_trace.contains_new_map_syntax,false);
assert.equal(complexSite.alias_trace.mentions_parameter_token,true);
// Indexed access can produce a Map-like receiver without any literal
// new Map() or named parameter appearing in the RHS expression.
complexSite=aliasFixture(
  "let receiver=registry[key];receiver.set(s,c);return receiver"
);
assert.deepEqual(complexSite.alias_trace,{
  origin_hint:"complex-or-unsupported-expression",hops_capped:0,
  expression_form:"computed-member-access",expression_scan_complete:true,
  contains_new_map_syntax:false,mentions_parameter_token:false,
  expression_token_shape:"id [ id ]",
  expression_token_shape_complete:true
});
assert.equal(complexSite.receiver_initializer_kind,"identifier-alias");
complexSite=aliasFixture(
  "let receiver=registry?.[key];receiver.set(s,c);return receiver"
);
assert.equal(complexSite.alias_trace.expression_form,"computed-member-access");
assert.equal(complexSite.alias_trace.expression_scan_complete,true);
assert.equal(complexSite.alias_trace.mentions_parameter_token,false);
assert.equal(complexSite.alias_trace.expression_token_shape,"id ?. [ id ]");
assert.equal(complexSite.alias_trace.expression_token_shape_complete,true);
// Parameter-dependent indexed expression remains syntax-only evidence.
complexSite=aliasFixture(
  "let receiver=p[key];receiver.set(s,c);return receiver"
);
assert.equal(complexSite.alias_trace.expression_form,"computed-member-access");
assert.equal(complexSite.alias_trace.mentions_parameter_token,true);
assert.equal(complexSite.alias_trace.origin_hint,
  "complex-or-unsupported-expression");
complexSite=aliasFixture(
  "let receiver=p+other;receiver.set(s,c);return receiver"
);
assert.equal(complexSite.alias_trace.expression_form,"operator-expression");
// Never infer purity from a parameter mention or a fresh-Map token.
// Original symbols and sensitive literals are excluded from diagnostics.
complexSite=aliasFixture(
  "let ghp_FAKE_TOKEN='PRIVATE',receiver=p??new Map();" +
  "receiver.set(s,c);return receiver"
);
assert.equal(complexSite.alias_trace.expression_form,"logical-or-coalescing");
assert.ok(!JSON.stringify(complexSite).includes("PRIVATE"));
assert.ok(!JSON.stringify(complexSite).includes("ghp_FAKE_TOKEN"));

// Token shape must preserve operators/punctuation but never raw identifiers,
 // numeric literal payloads, string contents, or Unicode source text.
complexSite=aliasFixture(
  "let receiver=secretOwner[privateKey]+42;" +
  "receiver.set(s,c);return receiver"
);
assert.equal(complexSite.alias_trace.expression_token_shape,
  "id [ id ] + 0");
assert.equal(complexSite.alias_trace.expression_token_shape_complete,true);
assert.ok(!JSON.stringify(complexSite).includes("secretOwner"));
assert.ok(!JSON.stringify(complexSite).includes("privateKey"));
assert.ok(!JSON.stringify(complexSite).includes("42"));
complexSite=aliasFixture(
  "let receiver=secretOwner['PRIVATE_VALUE'];" +
  "receiver.set(s,c);return receiver"
);
assert.equal(complexSite.alias_trace.expression_token_shape,
  "id [ STRING ]");
assert.ok(!JSON.stringify(complexSite).includes("PRIVATE_VALUE"));
complexSite=aliasFixture(
  "let receiver=secretOwner[π];receiver.set(s,c);return receiver"
);
assert.equal(complexSite.alias_trace.expression_token_shape_complete,false);
assert.ok(!JSON.stringify(complexSite).includes("π"));
const secretAlias=aliasFixture("let ghp_FAKE_SECRET=p;" +
  "let receiver=ghp_FAKE_SECRET;receiver.set(s,c);return receiver");
assert.deepEqual(secretAlias.alias_trace,{
  origin_hint:"parameter",hops_capped:2
});
assert.ok(!JSON.stringify(secretAlias).includes("ghp_FAKE_SECRET"));

const noWritesBundle="function make(p,c,s){const fresh=new Map();" +
  "return fresh}function build(c,s){return c}" +
  "class C{"+originSource+"}";
r=inspect(noWritesBundle,"",originSource);
assert.equal(r.primary_helper.map_write_origin_status,"no-lexical-calls");
assert.deepEqual(r.primary_helper.map_write_receiver_counts,{
  fresh_local_capped:0,direct_parameter_capped:0,other_or_unknown_capped:0
});
assert.equal(r.primary_helper.side_effect_freedom_proven,false);

const literalWritesBundle="function make(p,c,s){let x='ghp_TEST.set(x)';" +
  "/* p.delete(s) */return c}" +
  "function build(c,s){return c};class C{"+originSource+"}";
r=inspect(literalWritesBundle,"",originSource);
assert.deepEqual(r.primary_helper.map_write_receiver_counts,{
  fresh_local_capped:0,direct_parameter_capped:0,other_or_unknown_capped:0
});
assert.ok(!JSON.stringify(r).includes("ghp_TEST"));

const falseSyntaxSrc="resolve(p,c){let a=make(p,c,s),b=build(c,s);return b}";
const falseSyntaxBundle="function make(p,c,s){const x='secret .set(value) }';" +
  "/* .clear() } */ return {x}}" +
  "function build(c,s){return c}" +
  "class Resolver{" + falseSyntaxSrc + "}";
r=inspect(falseSyntaxBundle,"",falseSyntaxSrc);
assert.equal(r.primary_helper.body_inspection,"complete");
assert.equal(r.primary_helper.map_write_syntax_present,false);
assert.equal(r.primary_helper.side_effect_freedom_proven,false);

// Unbalanced candidate bodies are reported without source, values, or
// speculative effects. Declaration uniqueness alone is not semantic proof.
const brokenSource="resolve(p,c){let a=make(p,c,s),b=build(c,s);return a}";
const brokenBundle="function build(c,s){return c};class Resolver{" +
  brokenSource + "};function make(p,c,s){let secret='ghp_TEST_ONLY';";
r=inspect(brokenBundle,"",brokenSource);
assert.equal(r.primary_helper.body_inspection,"unclosed-or-oversize");
assert.equal(r.primary_helper.side_effect_freedom_proven,false);
assert.ok(!JSON.stringify(r).includes("ghp_TEST_ONLY"));

r=inspect(bundled,bundled);
assert.equal(r.resolver_source_location,"ambiguous");
assert.equal(r.static_binding_match_complete,false);
assert.equal(r.primary_helper.status,"not-checked");

r=inspect("const other=2","");
assert.equal(r.resolver_source_location,"not-found");
assert.equal(r.static_binding_match_complete,false);

r=inspect(bundled + ";function make(x){}", "");
assert.equal(r.primary_helper.status,"ambiguous");
assert.equal(r.static_binding_match_complete,false);

r=inspect(bundled.replace("const build=(b,c)=>{};",""),"");
assert.equal(r.secondary_helper.status,"unresolved-static");
assert.equal(r.static_binding_match_complete,false);

const same="resolve(x,y){let a=make(x,y,z),b=make(y,z);return a}";
r=inspect("function make(){};class C{"+same+"}","",same);
assert.equal(r.helper_identity_relation,"same");
assert.equal(r.static_binding_match_complete,false);

r=inspect(bundled,"","resolve(x,y){return y}");
assert.equal(r.resolver_source_location,"not-found");
assert.equal(r.static_binding_match_complete,false);

r=inspect(bundled,"","A".repeat(9000));
assert.equal(r.resolver_source_location,"unavailable-or-out-of-bounds");

const privateName="privateGithubToken_ghp_NOT_REAL_SECRET";
const privacySource="resolve(privateInput,ctx){let a=secretHelper(privateInput,ctx,"+
  privateName+"),b=a.store.get(secret);let v=alloc(ctx,fixture);return b}";
const privacyBundle="function secretHelper(a,b,c){return a};const alloc=(b,c)=>{};" +
  "class PrivateResolver{"+privacySource+"};const "+
  privateName+"='ghp_PRIVATE_FIXTURE_SECRET'";
r=inspect(privacyBundle,"",privacySource);
assert.equal(r.static_binding_match_complete,true);
const output=JSON.stringify(r);
for(const sensitive of ["privateGithubToken","ghp_","secretHelper",
  "PrivateResolver","privateInput","alloc","PRIVATE_FIXTURE_SECRET"]) {
  assert.ok(!output.includes(sensitive),"no raw identifier or secret: "+sensitive);
}
assert.equal(r.submission_authorized,false);
console.log("PASS AUTO-F01 static helper linking: unique, ambiguous, missing, bounded, redacted");
