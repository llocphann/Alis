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
const brokenBundle="function make(p,c,s){let secret='ghp_TEST_ONLY';" +
  "function build(c,s){return c}" + "class Resolver{" + brokenSource + "}";
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
