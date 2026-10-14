/* AUTO-F01 pure static helper-link inspection.
 * No execution of Desktop functions. No original variable names, function
 * source, literal values, account state or tokens in return values.
 */
const IDENT = /^[A-Za-z_$][\w$]*$/;
const esc = s => s.replace(/[.*+?^$()|[\]{}\\]/g, "\\$&");
function matchCount(source, pattern) {
  let count = 0;
  for (const _ of source.matchAll(pattern)) {
    if (++count >= 3) break;
  }
  return count;
}
// Read *only* the textual body of a uniquely matched function declaration.
// Delimiter scanning ignores string/comment/template contents and fails closed
// on malformed or oversized bodies. Never execute an installed helper.
function inspectFunctionBody(source, declarationEnd) {
  const unknown = {
    body_inspection:"unavailable",
    body_length_band:"unknown",
    map_read_syntax_present:false,
    map_write_syntax_present:false,
    creates_objects_syntax_present:false,
    calls_other_functions_syntax_present:false,
    side_effect_freedom_proven:false
  };
  if (!Number.isSafeInteger(declarationEnd)) return unknown;
  const max = 16384;
  const limit = Math.min(source.length, declarationEnd + max);
  let state = "normal", escape = false, paren = 1, brace = 0;
  let bodyStart = -1, bodyEnd = -1;
  for (let i = declarationEnd; i < limit; i++) {
    const c = source[i], n = source[i + 1];
    if (state === "line") {
      if (c === "\n" || c === "\r") state = "normal";
      continue;
    }
    if (state === "block") {
      if (c === "*" && n === "/") {state = "normal"; i++;}
      continue;
    }
    if (state !== "normal") {
      if (escape) {escape = false; continue;}
      if (c === "\\") {escape = true; continue;}
      if ((state === "single" && c === "'") ||
          (state === "double" && c === '"') ||
          (state === "template" && c === "\`")) state = "normal";
      continue;
    }
    if (c === "/" && n === "/") {state = "line"; i++; continue;}
    if (c === "/" && n === "*") {state = "block"; i++; continue;}
    if (c === "'") {state = "single"; continue;}
    if (c === '"') {state = "double"; continue;}
    if (c === "\`") {state = "template"; continue;}
    if (bodyStart < 0) {
      if (c === "(") paren++;
      if (c === ")") paren--;
      if (paren < 0) return {...unknown,body_inspection:"invalid-parameters"};
      if (paren === 0) {
        // There must be no non-whitespace token between ')' and '{'.
        let k = i + 1;
        while (k < limit && /\s/.test(source[k])) k++;
        if (source[k] !== "{") return {
          ...unknown,body_inspection:"unsupported-declaration"
        };
        bodyStart = k;
        brace = 1;
        i = k;
      }
      continue;
    }
    if (c === "{") brace++;
    if (c === "}") {
      brace--;
      if (brace === 0) {bodyEnd = i; break;}
      if (brace < 0) return {...unknown,body_inspection:"invalid-body"};
    }
  }
  if (bodyStart < 0 || bodyEnd < 0)
    return {...unknown,body_inspection:"unclosed-or-oversize"};
  const body = source.slice(bodyStart + 1,bodyEnd);
  // A conservative syntax-only report. Absence of these tokens does NOT
  // establish a helper is free from side effects; called functions may write.
  const masked = body
    .replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g," ")
    .replace(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\`(?:[^\`\\]|\\.)*\`/g,"STRING");
  const has = pattern => pattern.test(masked);
  // Cautious lexical classification of .set/.delete/.clear receivers.
  // A fresh local Map write is NOT proof of no side effects: the local can
  // escape, helper calls can mutate external state, and minified classes
  // may implement these methods with arbitrary behavior.
  const paramsMatch = source.slice(declarationEnd, bodyStart).match(
    /^\s*((?:[$A-Za-z_][\w$]*\s*,\s*)*[$A-Za-z_][\w$]*|)\s*\)\s*$/
  );
  const params = paramsMatch
    ? new Set(paramsMatch[1] ? paramsMatch[1].split(",").map(x=>x.trim()) : [])
    : null;
  const freshLocals = new Set([...masked.matchAll(
    /\b(?:const|let|var)\s+([$A-Za-z_][\w$]*)\s*=\s*new\s+Map\s*\(/g
  )].map(m=>m[1]));
  const receiverCalls = [...masked.matchAll(
    /\b([$A-Za-z_][\w$]*)\s*\.\s*(?:set|delete|clear)\s*\(/g
  )];
  const counts = {fresh_local_capped:0,direct_parameter_capped:0,
    other_or_unknown_capped:0};
  // Further distinguish *why* a receiver stayed unknown without exporting
  // symbols, literals, runtime objects, source slices or account values.
  // The result is lexical evidence only, never permission to execute code.
  const unknownSites = [];
  const initializerKind = symbol => {
    if(!IDENT.test(symbol)) return "unresolved";
    const re = new RegExp("(?:^|[,;{])\\s*(?:(?:let|const|var)\\s+)?"+
      esc(symbol)+"\\s*=\\s*","g");
    const matches = [...masked.matchAll(re)].filter(m=>m.index < masked.length);
    if(matches.length!==1) return matches.length > 1 ? "multiple-assignments" :
      "not-found";
    const tail = masked.slice(matches[0].index + matches[0][0].length);
    if(/^new\s+Map\s*\(/.test(tail)) return "new-map";
    if(/^new\s+[$A-Za-z_][\w$]*\s*\(/.test(tail)) return "new-other";
    if(/^[$A-Za-z_][\w$]*\s*\(/.test(tail)) return "helper-call-result";
    if(/^[$A-Za-z_][\w$]*\s*(?:\?\.|\.)/.test(tail))
      return "member-result";
    if(/^[$A-Za-z_][\w$]*\b/.test(tail)) return "identifier-alias";
    return "other-expression";
  };
  // Trace only bare "name=otherName" lexical aliases that occur before the
  // write. A chain cannot certify ownership or side-effect freedom; it only
  // identifies a possible origin. Reassignments, cycles, unknown syntax and
  // excessive depth stop in an explicit non-authorizing state.
  const traceIdentifierAlias = (start, siteIndex) => {
    const seen = new Set();
    let symbol = start, hops = 0, cutoff = siteIndex;
    while (hops <= 8) {
      // Resolve the alias's source at the point it was assigned, rather
      // than incorrectly following later initializations/reassignments.
      const prefix = masked.slice(0,cutoff);
      if (seen.has(symbol))
        return {origin_hint:"cycle",hops_capped:Math.min(8,hops)};
      seen.add(symbol);
      const assignment = new RegExp(
        "(?:^|[,;{}])\\s*(?:(?:const|let|var)\\s+)?" +
        esc(symbol) + "\\s*=\\s*","g");
      const found = [...prefix.matchAll(assignment)];
      if (found.length > 1)
        return {origin_hint:"multiple-assignments",hops_capped:Math.min(8,hops)};
      if (!found.length)
        return {origin_hint:params?.has(symbol) ? "parameter" :
          "unresolved-external",hops_capped:Math.min(8,hops)};
      // Parameter symbols can be shadowed or reassigned. Do not assert a
      // parameter origin when an assignment was seen in this body.
      const rhs = prefix.slice(found[0].index + found[0][0].length);
      if (/^new\s+Map\s*\(/.test(rhs))
        return {origin_hint:"new-map-syntax",hops_capped:Math.min(8,hops)};
      if (/^new\s+[$A-Za-z_][\w$]*\s*\(/.test(rhs))
        return {origin_hint:"new-other-syntax",hops_capped:Math.min(8,hops)};
      if (/^[$A-Za-z_][\w$]*\s*\(/.test(rhs))
        return {origin_hint:"helper-call-result",hops_capped:Math.min(8,hops)};
      if (/^[$A-Za-z_][\w$]*\s*(?:\?\.|\.)/.test(rhs))
        return {origin_hint:"member-result",hops_capped:Math.min(8,hops)};
      const alias = rhs.match(/^([$A-Za-z_][\w$]*)\s*(?=[,;}\n\r]|$)/);
      if (!alias)
        return {origin_hint:"complex-or-unsupported-expression",
          hops_capped:Math.min(8,hops)};
      symbol = alias[1];
      cutoff = found[0].index;
      hops++;
    }
    return {origin_hint:"depth-limit",hops_capped:8};
  };
  for(const m of receiverCalls){
    const receiver = m[1];
    // A call like object.parameter.set(...) refers to a property, not
    // necessarily the parameter with the same spelling.
    const before = masked.slice(0,m.index).trimEnd();
    if(before.endsWith(".")) {
      counts.other_or_unknown_capped++;
      const ownerMatch = before.slice(0,-1).trimEnd().match(/([$A-Za-z_][\w$]*)$/);
      const owner = ownerMatch?.[1];
      const ownerType = owner
        ? params?.has(owner) ? "parameter-member"
          : initializerKind(owner) === "not-found" ? "external-member"
          : "local-member"
        : "unknown-member";
      unknownSites.push({receiver_form:"member-property",
        receiver_initializer_kind:"property-access",
        owner_origin_hint:ownerType});
    } else if(params?.has(receiver)) counts.direct_parameter_capped++;
    else if(freshLocals.has(receiver)) counts.fresh_local_capped++;
    else {
      counts.other_or_unknown_capped++;
      const kind = initializerKind(receiver);
      unknownSites.push({receiver_form:"bare-identifier",
        receiver_initializer_kind:kind,
        owner_origin_hint:"not-applicable",
        ...(kind === "identifier-alias"
          ? {alias_trace:traceIdentifierAlias(receiver,m.index)} : {})});
    }
  }
  for(const key of Object.keys(counts)) counts[key] = Math.min(8, counts[key]);
  const originStatus = receiverCalls.length === 0 ? "no-lexical-calls" :
    params ? "lexical-classification-only" : "unsupported-parameters";
  return {
    body_inspection:"complete",
    map_write_origin_status:originStatus,
    map_write_receiver_counts:counts,
    map_write_unknown_sites:unknownSites.slice(0,4),
    map_write_unknown_sites_truncated:unknownSites.length>4,
    body_length_band:body.length <= 256 ? "0-256" :
      body.length <= 1024 ? "257-1k" :
      body.length <= 4096 ? "1k-4k" : "4k-16k",
    map_read_syntax_present:has(/\.(?:get|has)\s*\(/),
    map_write_syntax_present:has(/\.(?:set|delete|clear)\s*\(/),
    creates_objects_syntax_present:has(/\bnew\s+[$A-Za-z_]/),
    calls_other_functions_syntax_present:has(/[$A-Za-z_][\w$]*\s*\(/),
    side_effect_freedom_proven:false
  };
}

function findBinding(initial, shared, symbol) {
  if (!IDENT.test(symbol))
    return {status:"invalid-symbol",kind:"none",asset:"none",candidate_count_capped:0};
  const e = esc(symbol);
  const forms = [
    ["function-declaration",new RegExp("\\bfunction\\s+" + e + "\\s*\\(","g")],
    ["function-expression",new RegExp("(?:^|[,;])\\s*(?:var|let|const)?\\s*" +
      e + "\\s*=\\s*(?:async\\s+)?function\\b","g")],
    ["arrow-function",new RegExp("(?:^|[,;])\\s*(?:var|let|const)?\\s*" +
      e + "\\s*=\\s*(?:async\\s*)?(?:\\([^)]{0,256}\\)|[A-Za-z_$][\\w$]*)\\s*=>","g")]
  ];
  const hits = [];
  for (const [asset, source] of [["initial",initial],["shared",shared]]) {
    for (const [kind, pattern] of forms) {
      const count = matchCount(source,pattern);
      if (count) hits.push({asset,kind,count});
    }
  }
  const total = hits.reduce((n,h) => n + h.count,0);
  const bodyEvidence = total === 1 && hits[0].kind === "function-declaration"
    ? (() => {
      const matchSource = hits[0].asset === "initial" ? initial : shared;
      const pat = new RegExp("\\bfunction\\s+" + e + "\\s*\\(", "g");
      const match = pat.exec(matchSource);
      return match ? inspectFunctionBody(matchSource, match.index +
        match[0].length) : {body_inspection:"unavailable",
          side_effect_freedom_proven:false};
    })()
    : {body_inspection: total === 1 ? "unsupported-binding-kind" :
        "binding-not-unique",side_effect_freedom_proven:false};
  return {
    ...bodyEvidence,
    status: total === 1 ? "unique-declaration" :
      total === 0 ? "unresolved-static" : "ambiguous",
    kind: total === 1 ? hits[0].kind : "none",
    asset: total === 1 ? hits[0].asset : "none",
    candidate_count_capped: Math.min(total,3)
  };
}
export function analyzeStaticResolverHelpers({initial,shared,resolverSource} = {}) {
  const result = {
    purpose:"static-only-helper-linkage",supported:false,
    submission_authorized:false,
    resolver_source_location:"unverified",source_match_count_capped:0,
    resolver_signature:"unrecognized",
    primary_helper:{status:"not-checked",kind:"none"},
    secondary_helper:{status:"not-checked",kind:"none"},
    helper_identity_relation:"unknown",
    static_binding_match_complete:false
  };
  if (typeof initial !== "string" || typeof shared !== "string" ||
      typeof resolverSource !== "string" || !resolverSource.length ||
      resolverSource.length > 8192) {
    result.resolver_source_location = "unavailable-or-out-of-bounds";
    return result;
  }
  const count = (s,fragment) => {
    const first = s.indexOf(fragment);
    if (first < 0) return 0;
    return s.indexOf(fragment,first + 1) < 0 ? 1 : 2;
  };
  const inInitial = count(initial,resolverSource);
  const inShared = count(shared,resolverSource);
  const n = inInitial + inShared;
  result.source_match_count_capped = Math.min(n,3);
  result.resolver_source_location = n !== 1
    ? n ? "ambiguous" : "not-found"
    : inInitial ? "unique-in-initial" : "unique-in-shared";
  if (n !== 1) return result;
  const header = resolverSource.match(
    /^(?:async\s+)?(?:function\s+)?[A-Za-z_$][\w$]*\s*\(\s*([A-Za-z_$][\w$]*)\s*,\s*([A-Za-z_$][\w$]*)\s*\)\s*\{/);
  if (!header || header[1] === header[2]) return result;
  result.resolver_signature = "two-distinct-arguments";
  const [a,b] = [header[1],header[2]];
  const body = resolverSource.slice(header[0].length);
  const primary = new RegExp("(?:^|[,;{])\\s*(?:let|const|var)?\\s*" +
    "[A-Za-z_$][\\w$]*\\s*=\\s*([A-Za-z_$][\\w$]*)\\s*\\(\\s*" +
    esc(a) + "\\s*,\\s*" + esc(b) + "\\s*,","g");
  // A fallback helper may be assigned immediately after a completed if block:
  // }let value=helper(context,scope). Include the closing brace as a
  // statement boundary; do not interpret a failed regex as a missing helper.
  const secondary = new RegExp("(?:^|[,;{}])\\s*(?:let|const|var)?\\s*" +
    "[A-Za-z_$][\\w$]*\\s*=\\s*([A-Za-z_$][\\w$]*)\\s*\\(\\s*" +
    esc(b) + "\\s*,","g");
  const p = [...body.matchAll(primary)].map(m=>m[1]);
  const q = [...body.matchAll(secondary)].map(m=>m[1]);
  result.primary_helper = p.length === 1 ? findBinding(initial,shared,p[0]) :
    {status:p.length ? "ambiguous-helper-call" : "not-found",
     kind:"none",candidate_count_capped:Math.min(3,p.length)};
  result.secondary_helper = q.length === 1 ? findBinding(initial,shared,q[0]) :
    {status:q.length ? "ambiguous-helper-call" : "not-found",
     kind:"none",candidate_count_capped:Math.min(3,q.length)};
  if (p.length === 1 && q.length === 1)
    result.helper_identity_relation = p[0] === q[0] ? "same" : "distinct";
  result.static_binding_match_complete =
    result.primary_helper.status === "unique-declaration" &&
    result.secondary_helper.status === "unique-declaration" &&
    result.helper_identity_relation === "distinct";
  return result;
}
