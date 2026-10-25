#!/usr/bin/env bash
# verify-docs.sh — fail-loud doc/code drift checker. Source of truth is ALWAYS the
# code: every check derives its expected set by scanning the tree, never from a
# hardcoded list (a hardcoded list would drift too). Exit != 0 on any mismatch so
# it can gate pre-commit / CI. Run from repo root: ./scripts/verify-docs.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
fail=0
note() { printf '  - %s\n' "$1"; fail=1; }

# 1. IPC targets: code (services/) vs docs/SERVICES.md — both directions.
real_ipc=$(grep -rl 'IpcHandler' services/ --include='*.qml' 2>/dev/null \
  | xargs grep -hoP 'target:\s*"\K[^"]+' 2>/dev/null | sort -u)
doc_ipc=$(grep -oP 'IPC target: `\K[^`]+' docs/SERVICES.md 2>/dev/null | sort -u)
echo "[IPC] services/ vs docs/SERVICES.md"
while read -r t; do [ -n "$t" ] && ! grep -qxF "$t" <<<"$doc_ipc" \
  && note "IPC '$t' exists in code but is NOT documented in docs/SERVICES.md"; done <<<"$real_ipc"
while read -r t; do [ -n "$t" ] && ! grep -qxF "$t" <<<"$real_ipc" \
  && note "IPC '$t' documented in docs/SERVICES.md but NO service exposes it"; done <<<"$doc_ipc"

# 2. docs/IPC.md ### headers must each be a real target somewhere in the tree.
#    (colorpicker etc. are standalone CLI commands documented under their own
#    heading, so only check headers that sit above the 'Standalone Commands' line.)
all_ipc=$(grep -rhoP 'target:\s*"\K[^"]+' . --include='*.qml' 2>/dev/null | sort -u)
standalone_line=$(grep -n 'Standalone Commands' docs/IPC.md | head -1 | cut -d: -f1)
: "${standalone_line:=999999}"
echo "[IPC] docs/IPC.md headers vs code"
while IFS=: read -r ln t; do
  [ -z "$t" ] && continue
  [ "$ln" -ge "$standalone_line" ] && continue   # below 'Standalone Commands' = CLI, not IPC
  grep -qxF "$t" <<<"$all_ipc" || note "docs/IPC.md documents '### $t' but no IpcHandler target '$t' exists"
done < <(grep -noP '^### \K[a-zA-Z]+' docs/IPC.md 2>/dev/null)

# 3. Backtick-quoted .qml references in docs/*.md must resolve to a real file
#    (docs cite by basename, so match the file ANYWHERE in the tree).
echo "[paths] .qml references in docs/*.md"
while read -r p; do
  [ -n "$p" ] || continue
  b=$(basename "$p")
  find . -name "$b" -not -path './.git/*' -print -quit 2>/dev/null | grep -q . \
    || note "docs reference '$p' but no file named '$b' exists"
done < <(
  for doc in docs/*.md; do
    # Research snapshots cite other repositories, deleted historical components
    # and proposed source paths. Keep their evidence literal; active manuals
    # still require every quoted QML path to resolve in the current tree.
    head -n 5 "$doc" | grep -q '^<!-- hadalis-doc-kind: research -->$' && continue
    grep -hoP '`\K[a-zA-Z0-9_./-]+\.qml(?=`)' "$doc" 2>/dev/null
  done | sort -u
)

# 4. Relative Markdown links in README/docs must resolve to repository content.
#    GitHub Wiki exports docs/index.md as Home.md and conventionally links pages
#    without the .md suffix, so validate those intentional forms against their
#    repository source files instead of treating them as missing literal paths.
echo "[links] relative Markdown targets"
if command -v python3 >/dev/null 2>&1; then
  if ! python3 - <<'PY'
from pathlib import Path
import re
import sys
from urllib.parse import unquote

root = Path.cwd().resolve()
docs_root = (root / "docs").resolve()
documents = [Path("README.md"), *sorted(Path("docs").glob("*.md"))]
link_re = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
scheme_re = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")
errors = []


def inside_repo(path: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def candidates_for(document: Path, path_text: str) -> list[Path]:
    literal = (document.parent / path_text).resolve()
    candidates = [literal]

    # GitHub Wiki page links omit .md, while repository sources keep it.
    relative_path = Path(path_text)
    if not relative_path.suffix:
        candidates.append(literal.with_suffix(".md"))

    # scripts/wiki-sync.sh exports docs/index.md as Wiki Home.md.
    if document.parent.resolve() == docs_root and path_text == "Home":
        candidates.append((docs_root / "index.md").resolve())

    # Preserve order while avoiding duplicate checks.
    return list(dict.fromkeys(candidates))


for document in documents:
    if not document.is_file():
        continue
    text = document.read_text(encoding="utf-8")
    for match in link_re.finditer(text):
        raw = match.group(1).strip()
        if not raw or raw.startswith("#") or scheme_re.match(raw):
            continue
        if raw.startswith("<") and ">" in raw:
            destination = raw[1:raw.index(">")]
        else:
            destination = raw.split(None, 1)[0]
        path_text = unquote(destination.split("#", 1)[0])
        if not path_text:
            continue

        candidates = candidates_for(document, path_text)
        if any(not inside_repo(candidate) for candidate in candidates):
            errors.append(f"{document}: link escapes repository: {destination}")
            continue
        if not any(candidate.exists() for candidate in candidates):
            errors.append(f"{document}: missing link target: {destination}")

if errors:
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    raise SystemExit(1)
PY
  then
    note "one or more relative Markdown link targets are missing"
  fi
else
  note "python3 is required for relative Markdown link validation"
fi

# 5. (local, optional) nested AGENTS.md are gitignored — only checked if present.
#    Same basename match; these cite components by name.
if find modules services -name AGENTS.md -print -quit 2>/dev/null | grep -q .; then
  echo "[local] nested AGENTS.md .qml references"
  while read -r p; do
    [ -n "$p" ] || continue
    b=$(basename "$p")
    find . -name "$b" -not -path './.git/*' -print -quit 2>/dev/null | grep -q . \
      || note "a nested AGENTS.md references '$p' but no file named '$b' exists"
  done < <(grep -rhoP '`\K[a-zA-Z0-9_./-]+\.qml(?=`)' $(find modules services -name AGENTS.md) 2>/dev/null | sort -u)
fi

# 6. Runtime locales must expose the same keys, placeholders and markup as
#    English. The localization tool owns this contract so review batches and
#    repository verification cannot drift apart.
echo "[i18n] runtime locale structure"
if command -v python3 >/dev/null 2>&1 && [ -f translations/tools/l10n.py ]; then
  python3 translations/tools/l10n.py audit-all \
    || note "runtime locale validation failed"
else
  note "python3 and translations/tools/l10n.py are required for locale validation"
fi

# 7a. The IPC metadata parser must preserve escaped Markdown table pipes and
#     normalize documented function signatures to their QML function names.
if command -v python3 >/dev/null 2>&1 && [ -f scripts/test-ipc-registry-generator.py ]; then
  echo "[IPC] registry Markdown parser"
  python3 scripts/test-ipc-registry-generator.py \
    || note "IPC registry Markdown parser regression failed"
else
  note "python3 and scripts/test-ipc-registry-generator.py are required for IPC registry parser validation"
fi

# 7b. Generated IPC CLI registry must be in sync with docs/IPC.md + QML targets.
#     A stale scripts/lib/ipc-registry.sh breaks the `alis <target> <fn>` shorthand
#     even though the IPC itself works — the bug that hid the dashboard target.
if command -v python3 >/dev/null 2>&1 && [ -f scripts/lib/generate-ipc-registry.py ]; then
  echo "[IPC] generated CLI registry freshness"
  python3 scripts/lib/generate-ipc-registry.py --check >/dev/null 2>&1 \
    || note "scripts/lib/ipc-registry.sh is stale — run: python3 scripts/lib/generate-ipc-registry.py"
fi

# 8. Installation documentation must not claim Arch-only routing while setup
#    still contains distro-specific Fedora or Debian/Ubuntu dependency routers.
#    The router remains the source of truth; this only rejects a contradictory
#    blanket statement when those non-Arch routes actually exist in code.
router="sdata/subcmd-install/1.deps-router.sh"
install_doc="docs/INSTALL.md"
echo "[install] setup distro routing vs docs/INSTALL.md"
if [ -f "$router" ] && [ -f "$install_doc" ] \
    && grep -Eq 'source ./sdata/dist-(fedora|debian)/install-deps\.sh' "$router"; then
  if grep -Fq '**Arch Linux only.**' "$install_doc"; then
    note "docs/INSTALL.md claims Arch-only support while setup has Fedora/Debian dependency routers"
  fi
fi

# 9. If the Phase 1 Equalizer service exists, README must distinguish the
#    implemented backend contract from stabilization work and deferred UI scope.
#    This prevents roadmap text from regressing to treating all Equalizer work as
#    either fully shipped or entirely hypothetical.
equalizer_service="services/deferred/EqualizerService.qml"
readme="README.md"
echo "[roadmap] Equalizer implementation states"
if [ -f "$equalizer_service" ] && [ -f "$readme" ]; then
  grep -Fq 'property bool enabled: false' "$equalizer_service" \
    || note "EqualizerService no longer exposes the disabled-by-default Phase 1 contract"
  grep -Fq '## Equalizer implementation status' "$readme" \
    || note "README no longer has an Equalizer implementation-status section"
  for state in Implemented Stabilizing Planned; do
    grep -Fq "### $state" "$readme" \
      || note "README Equalizer roadmap no longer distinguishes $state work"
  done
  grep -Fq '`EqualizerService.qml` provides the Phase 1 backend/service contract and is disabled by default.' "$readme" \
    || note "README no longer identifies the implemented disabled-by-default Equalizer Phase 1 backend"
  grep -Fq 'planned/deferred rather than current release prerequisites' "$readme" \
    || note "README no longer keeps the future Equalizer presentation outside current release prerequisites"
fi

# 10. Release documentation must mirror the optional-package ownership gates.
release_script="scripts/release.sh"
release_doc="docs/RELEASING.md"
echo "[release] optional package gates vs docs/RELEASING.md"
if [ -f "$release_script" ] && [ -f "$release_doc" ]; then
  for contract in test-alis-intergration-install-lifecycle.py test-alis-intergration-arch-package.py; do
    if grep -Fq "\"\$script_dir/$contract\"" "$release_script"; then
      grep -Fq "python3 scripts/$contract" "$release_doc" \
        || note "docs/RELEASING.md omits the $contract release gate"
    fi
  done
  grep -Fq 'simulated command/hardware boundaries' "$release_doc" \
    || note "docs/RELEASING.md no longer explains the private optional-package release checks"
fi

[ "$fail" -eq 0 ] && echo "OK - docs and translations match code." || echo "DRIFT FOUND (see above)."
exit "$fail"
