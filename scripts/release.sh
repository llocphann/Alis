#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
github_repo="llocphann/Alis"
wiki_url="https://github.com/llocphann/Alis.wiki.git"

usage() {
  cat <<'EOF'
Usage:
  scripts/release.sh notes <version> [output-file]
  scripts/release.sh publish <version>

Commands:
  notes    Extract the matching CHANGELOG section and append release footer links.
  publish  Stage a draft GitHub release for an existing local tag v<version>, sync the Wiki, then publish it.

EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_clean_version() {
  [[ $# -ge 1 ]] || die "missing version"
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like X.Y.Z"
}

require_release_version_consistency() {
  local version="$1"
  local repo_version package_file package_version

  [[ -f "$repo_root/VERSION" ]] || die "missing VERSION file"
  repo_version="$(tr -d '[:space:]' < "$repo_root/VERSION")"
  [[ "$repo_version" == "$version" ]] \
    || die "VERSION=$repo_version does not match release version $version"

  for package_file in \
    "$repo_root/distro/arch/alis-shell/PKGBUILD" \
    "$repo_root/distro/arch/alis-meta/PKGBUILD" \
    "$repo_root/sdata/dist-arch/alis-deps/PKGBUILD"; do
    [[ -f "$package_file" ]] || die "missing release package metadata: ${package_file#$repo_root/}"
    package_version="$(grep -m1 '^pkgver=' "$package_file" | cut -d= -f2- || true)"
    [[ -n "$package_version" ]] \
      || die "missing pkgver in ${package_file#$repo_root/}"
    [[ "$package_version" == "$version" ]] \
      || die "${package_file#$repo_root/} pkgver=$package_version does not match release version $version"
  done
}

require_release_source_pin() {
  local tag="$1"
  local package_file srcinfo_file source_ref srcinfo_source
  package_file="$repo_root/distro/arch/alis-shell/PKGBUILD"
  srcinfo_file="$repo_root/distro/arch/alis-shell/.SRCINFO"

  [[ -f "$package_file" ]] || die "missing release package recipe: ${package_file#$repo_root/}"
  [[ -f "$srcinfo_file" ]] || die "missing release package metadata: ${srcinfo_file#$repo_root/}"

  source_ref="$(sed -n 's/^_source_ref="${ALIS_SOURCE_REF:-\([^}]*\)}"$/\1/p' "$package_file")"
  [[ -n "$source_ref" ]] \
    || die "could not read default _source_ref from ${package_file#$repo_root/}"
  [[ "$source_ref" == "$tag" ]] \
    || die "${package_file#$repo_root/} default _source_ref=$source_ref must equal release tag $tag"

  srcinfo_source="$(sed -n 's/^[[:space:]]*source = //p' "$srcinfo_file" | head -1)"
  [[ -n "$srcinfo_source" ]] \
    || die "missing source entry in ${srcinfo_file#$repo_root/}"
  [[ "$srcinfo_source" == *"/archive/${tag}.tar.gz" ]] \
    || die "${srcinfo_file#$repo_root/} source does not use release tag $tag"
  [[ "${srcinfo_source%%::*}" == *"-${tag}.tar.gz" ]] \
    || die "${srcinfo_file#$repo_root/} archive filename does not encode release tag $tag"
}

require_release_checkout() {
  local tag="$1"
  local tag_commit head_commit remote_tag_refs remote_tag_commit

  [[ -z "$(git -C "$repo_root" status --porcelain --untracked-files=all)" ]] \
    || die "release checkout must be clean (including untracked files)"

  tag_commit="$(git -C "$repo_root" rev-parse "$tag^{commit}")"
  head_commit="$(git -C "$repo_root" rev-parse HEAD)"
  [[ "$head_commit" == "$tag_commit" ]] \
    || die "HEAD must match $tag before publishing"

  git -C "$repo_root" fetch --quiet origin stable \
    || die "could not fetch origin/stable"
  git -C "$repo_root" merge-base --is-ancestor "$tag_commit" origin/stable \
    || die "$tag is not contained in origin/stable"

  remote_tag_refs="$(git -C "$repo_root" ls-remote --tags origin \
    "refs/tags/$tag" "refs/tags/$tag^{}")" \
    || die "could not read $tag from origin"
  [[ -n "$remote_tag_refs" ]] || die "$tag is not pushed to origin"
  remote_tag_commit="$(printf '%s\n' "$remote_tag_refs" | awk -v tag="$tag" '
    $2 == "refs/tags/" tag "^{}" { peeled = $1 }
    $2 == "refs/tags/" tag { direct = $1 }
    END { if (peeled != "") print peeled; else print direct }
  ')"
  [[ -n "$remote_tag_commit" ]] || die "could not resolve remote commit for $tag"
  [[ "$remote_tag_commit" == "$tag_commit" ]] \
    || die "$tag on origin does not match local tag commit $tag_commit"
}

require_release_host_features() {
  local wiki_enabled wiki_head git_name git_email

  command -v gh >/dev/null 2>&1 \
    || die "GitHub CLI (gh) is required for release publication"
  wiki_enabled="$(gh api "repos/$github_repo" --jq '.has_wiki' 2>/dev/null)" \
    || die "could not verify GitHub Wiki availability for $github_repo"
  [[ "$wiki_enabled" == "true" ]] \
    || die "GitHub Wiki is disabled for $github_repo; enable it before publishing so repository docs can be synchronized"

  wiki_head="$(GIT_TERMINAL_PROMPT=0 git ls-remote "$wiki_url" HEAD 2>/dev/null)" \
    || die "GitHub Wiki repository is not accessible; initialize the Wiki and verify Git credentials before publishing"
  [[ -n "$wiki_head" ]] \
    || die "GitHub Wiki repository is not initialized; create its first page before publishing"

  git_name="$(git -C "$repo_root" config user.name || true)"
  git_email="$(git -C "$repo_root" config user.email || true)"
  [[ -n "$git_name" && -n "$git_email" ]] \
    || die "git user.name and user.email must be configured before Wiki synchronization"
}

require_release_contracts() {
  local contract
  for contract in \
    "$script_dir/test-packaging-contract.sh" \
    "$script_dir/test-doctor-dependency-routing.sh" \
    "$script_dir/test-equalizer-boundary-contract.sh" \
    "$script_dir/test-equalizer-service-contract.sh" \
    "$script_dir/test-optional-audio-deps-contract.sh" \
    "$script_dir/test-reviewed-replacement-manifests.sh" \
    "$script_dir/test-config-namespace-migration.sh" \
    "$script_dir/test-runtime-orphan-cleanup.sh" \
    "$script_dir/test-hadalird-install-lifecycle.py" \
    "$script_dir/test-hadalird-arch-package.py" \
    "$script_dir/test-make-install-lifecycle.sh" \
    "$script_dir/test-uninstall-path-safety.sh" \
    "$script_dir/verify-docs.sh"; do
    [[ -f "$contract" ]] || die "missing release contract: ${contract#$repo_root/}"
    if [[ "$contract" == *.py ]]; then
      python3 "$contract" || die "release contract failed: ${contract#$repo_root/}"
    else
      bash "$contract" || die "release contract failed: ${contract#$repo_root/}"
    fi
  done

  # Nix compatibility remains useful diagnostic coverage, but the current
  # release acceptance lane is explicitly non-Nix. Keep running the contract
  # when present without allowing an unavailable or failing Nix lane to block
  # publication after the required non-Nix contracts have passed.
  contract="$script_dir/test-nix-module-contract.sh"
  if [[ ! -f "$contract" ]]; then
    printf 'warning: deferred Nix diagnostic is missing: %s\n' "${contract#$repo_root/}" >&2
  elif ! bash "$contract"; then
    printf 'warning: deferred Nix diagnostic failed and is non-blocking: %s\n' "${contract#$repo_root/}" >&2
  fi
}

extract_notes() {
  local version="$1"
  awk -v version="$version" '
    $0 ~ ("^## \\[" version "\\] - ") {
      in_section = 1
      next
    }
    in_section {
      if ($0 ~ /^## \[/) exit
      print
    }
  ' "$repo_root/CHANGELOG.md" | sed '/^$/N;/^\n$/D'
}

write_notes() {
  local version="$1"
  local outfile="$2"
  local notes
  notes="$(extract_notes "$version")"
  [[ -n "$notes" ]] || die "could not find CHANGELOG section for $version"

  cat > "$outfile" <<EOF
$notes

---

Update: https://github.com/llocphann/Alis/blob/stable/docs/SETUP.md#update
Fresh install: https://github.com/llocphann/Alis/blob/stable/docs/INSTALL.md
Full changelog: https://github.com/llocphann/Alis/blob/stable/CHANGELOG.md
EOF
}

stage_release_draft() {
  local tag="$1"
  local notes_file="$2"
  local release_state

  release_state="$(gh release view "$tag" --repo "$github_repo" --json isDraft --jq '.isDraft' 2>/dev/null || true)"
  case "$release_state" in
    true)
      # A prior attempt may have completed draft creation before Wiki sync or
      # final publication failed. Reuse the draft so rerunning publish is safe.
      gh release edit "$tag" \
        --repo "$github_repo" \
        --title "$tag" \
        --notes-file "$notes_file"
      ;;
    false)
      die "GitHub release $tag already exists and is published"
      ;;
    "")
      gh release create "$tag" \
        --repo "$github_repo" \
        --verify-tag \
        --draft \
        --title "$tag" \
        --notes-file "$notes_file"
      ;;
    *)
      die "could not determine GitHub release state for $tag: $release_state"
      ;;
  esac

  [[ "$(gh release view "$tag" --repo "$github_repo" --json isDraft --jq '.isDraft')" == "true" ]] \
    || die "release staging for $tag did not leave a draft"
}

publish_release() {
  local version="$1"
  local tag="v$version"
  local notes_file
  require_release_version_consistency "$version"
  git -C "$repo_root" rev-parse --verify "$tag" >/dev/null 2>&1 || die "missing local tag $tag"
  require_release_checkout "$tag"
  require_release_source_pin "$tag"
  require_release_host_features
  require_release_contracts

  notes_file="$(mktemp)"
  trap 'rm -f -- "${notes_file:-}"' EXIT
  write_notes "$version" "$notes_file"

  stage_release_draft "$tag" "$notes_file"
  "$script_dir/wiki-sync.sh" publish "docs: sync wiki for $tag"
  gh release edit "$tag" --repo "$github_repo" --draft=false
  rm -f "$notes_file"
  trap - EXIT
}

main() {
  [[ $# -ge 2 ]] || {
    usage
    exit 1
  }

  local cmd="$1"
  local version="$2"
  require_clean_version "$version"

  case "$cmd" in
    notes)
      local outfile="${3:-}"
      if [[ -n "$outfile" ]]; then
        write_notes "$version" "$outfile"
      else
        local tmpfile
        tmpfile="$(mktemp)"
        write_notes "$version" "$tmpfile"
        cat "$tmpfile"
        rm -f "$tmpfile"
      fi
      ;;
    publish)
      publish_release "$version"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
