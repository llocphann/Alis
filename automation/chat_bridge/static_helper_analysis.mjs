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
  return {
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
