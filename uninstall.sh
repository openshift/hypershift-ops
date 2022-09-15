#!/bin/bash
set -euo pipefail

die() { echo "$*" >&2; exit 2; }

$(which helm >/dev/null) || die "helm not found on PATH"
$(which oc >/dev/null) || die "oc not found on PATH"

oc delete hostedclusters --all --all-namespaces --ignore-not-found
oc delete namespace clusters --ignore-not-found
