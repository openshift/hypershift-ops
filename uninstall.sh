#!/bin/bash
set -euo pipefail

die() { echo "$*" >&2; exit 2; }

$(which helm >/dev/null) || die "helm not found on PATH"
$(which oc >/dev/null) || die "oc not found on PATH"
$(oc crossplane --help >/dev/null) || die "missing crossplane kubectl plugin"

oc delete hostedclusters --all --all-namespaces --ignore-not-found
oc delete namespace clusters --ignore-not-found
oc delete accesskeys.iam.aws.jet.crossplane.io --all --ignore-not-found || :
oc delete bucketpolicies.s3.aws.jet.crossplane.io --all --ignore-not-found || :
oc delete users.iam.aws.jet.crossplane.io --all --ignore-not-found || :
oc delete buckets.s3.aws.jet.crossplane.io --all --ignore-not-found || :
oc delete namespace hypershift --ignore-not-found
oc delete providerconfigs.aws.jet.crossplane.io --all --ignore-not-found || :
oc delete provider.pkg crossplane-provider-jet-aws --ignore-not-found || :
helm delete crossplane --namespace crossplane-system || :
oc delete namespace crossplane-system --ignore-not-found
oc get crd -o name | grep crossplane.io | xargs oc delete
