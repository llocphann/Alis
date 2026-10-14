/* AUTO-F01 acceptance-evidence summary, read-only and strictly fail-closed.
 * This is NOT a production transport gate and does not enable native sends.
 * The caller passes already redacted scope diagnostics. Never read Desktop
 * account metadata, auth, message bodies, project IDs or receipts here.
 */
export function assessNativeTransportEvidence(report) {
  const r = report && typeof report === "object" && !Array.isArray(report)
    ? report : {};
  const s = r.static_helper_links && typeof r.static_helper_links === "object"
    ? r.static_helper_links : {};
  const blockers = [];
  const add = x => {if (!blockers.includes(x)) blockers.push(x);};

  // Identifying only a bundle fingerprint does not prove any live project
  // or conversation binding. A malformed/missing diagnostic stays blocked.
  const fingerprintPresent = typeof r.fingerprint_prefix === "string" &&
    /^[a-f0-9]{12}$/i.test(r.fingerprint_prefix);
  if (!fingerprintPresent) add("INSTALLED_BUILD_FINGERPRINT_UNVERIFIED");

  if (r.provider_selection === "active_provider_ambiguous" ||
      (Number.isInteger(r.active_provider_map_count_capped) &&
       r.active_provider_map_count_capped > 1)) {
    add("ACTIVE_PROVIDER_MAP_AMBIGUOUS");
  } else {
    // Even one syntactically matching Map is not an authenticated context.
    add("PROVIDER_IDENTITY_NOT_PROVEN");
  }

  if (r.resolution_attempted !== false)
    add(r.resolution_attempted === true
      ? "READ_ONLY_CONTRACT_VIOLATION_RESOLVER_INVOKED"
      : "READ_ONLY_RESOLVER_STATE_UNVERIFIED");
  if (r.resolver_invocation_permitted === true)
    add("READ_ONLY_CONTRACT_VIOLATION_RESOLVER_ALLOWED");

  // Matching two minified function declarations is not proof the resolver
  // cannot mutate a shared cache, construct side-effectful objects or send.
  const helperShapeMatched = s.static_binding_match_complete === true &&
    s.helper_identity_relation === "distinct" &&
    s.resolver_source_location === "unique-in-shared";
  if (!helperShapeMatched) add("STATIC_HELPER_LINKAGE_INCOMPLETE");
  add("RESOLVER_SIDE_EFFECTS_NOT_PROVEN");

  const secondary = s.secondary_helper ?? {};
  if (secondary.map_write_syntax_present === true)
    add("SECONDARY_HELPER_WRITE_SYNTAX_PRESENT");
  if ((Array.isArray(secondary.map_write_unknown_sites)
        ? secondary.map_write_unknown_sites : []).some(x =>
       x?.receiver_initializer_kind === "new-map-token-no-args"))
    add("MAP_CONSTRUCTOR_IDENTITY_UNVERIFIED");

  // Scope discovery supplies NONE of these acceptance proofs. Do not trust
  // user-provided flags named project_verified, receipts_valid, supported,
  // submission_authorized, etc. There is no live attestation here.
  add("NATIVE_TRANSPORT_CAPABILITY_UNVERIFIED");
  add("EXACT_PROJECT_MEMBERSHIP_UNVERIFIED");
  add("EXACT_CONVERSATION_IDENTITY_UNVERIFIED");
  add("DURABLE_DISPATCH_RECEIPT_UNVERIFIED");

  return {
    purpose: "native-transport-acceptance-evidence",
    evidence_class: "read-only-static-and-scope-diagnostics",
    status: "blocked",
    supported: false,
    submission_authorized: false,
    live_transport_verified: false,
    project_conversation_verified: false,
    receipts_verified: false,
    fingerprint_syntax_present: fingerprintPresent,
    static_helper_shape_matched: helperShapeMatched,
    blocker_codes: blockers
  };
}
