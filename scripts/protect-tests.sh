#!/usr/bin/env bash
# Fails if any spec test (present at tag spec-v1) was modified, renamed or deleted. Adding new test files is allowed.
# Only a human moves the tag. Override tag name for a deliberate new baseline: SPEC_TAG=spec-v2
set -u
TAG="${SPEC_TAG:-spec-v1}"
cd "$(git rev-parse --show-toplevel)" || exit 1
if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "SKIP protect-tests: tag $TAG not found (P0.3 creates it)"; exit 0
fi
BAD=$(git diff --name-status "$TAG" | grep -E '(Packages/[^/]+/Tests/|App/UITests/)' | awk '$1 !~ /^A/ {print}')
if [ -n "$BAD" ]; then
  echo "FAIL protect-tests: spec tests changed since $TAG. Revert these (or write BLOCKERS.md):"
  echo "$BAD"; exit 1
fi
echo "PASS protect-tests ($TAG)"
