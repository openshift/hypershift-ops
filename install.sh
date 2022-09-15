#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

die() { echo "$*" >&2; exit 2; }
needs_arg() { if [ -z "$OPTARG" ]; then die "No argument for --$OPT option"; fi; }

function wait_for_crd {
  echo "waiting for customresourcedefinition ${1} to exist"
  while true; do
    if ! oc get customresourcedefinitions "$1" 2>&1 >/dev/null; then
      sleep 5
    else
      break
    fi
  done
}

# Parse arguments: https://stackoverflow.com/a/28466267
while getopts c:a:-: OPT; do
  # support long options: https://stackoverflow.com/a/28466267/519360
  if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
    OPT="${OPTARG%%=*}"       # extract long option name
    OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
    OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
  fi
  case "$OPT" in
    c | cluster )    needs_arg; CLUSTER="$OPTARG" ;;
    a | aws-creds )  needs_arg; AWS_CREDS="$OPTARG" ;;
    ??* )          die "Illegal option --$OPT" ;;  # bad long option
    ? )            exit 2 ;;  # bad short option (error reported via getopts)
  esac
done
shift $((OPTIND-1)) # remove parsed options and args from $@ list

# Set up globals
CLUSTER_DIR="${SCRIPT_DIR}/clusters/${CLUSTER}/manifests"
COMMON_DIR="${SCRIPT_DIR}/common"

# Validate inputs
$(which helm >/dev/null) || die "helm not found on PATH"
$(which oc >/dev/null) || die "oc not found on PATH"
[ -d "$CLUSTER_DIR" ] || die "cluster not found"
[ -f "$AWS_CREDS" ] || die "AWS creds file not found"

# Install the ops namespace, admin SA, and RBAC
oc apply -f "${COMMON_DIR}/hypershift-ops.yaml"

# Prepare the hypershift namespace
oc apply -f "${COMMON_DIR}/hypershift.yaml"

# Install hypershift infra resources required by the operator
oc apply -f "${CLUSTER_DIR}/hypershift-operator-infra.yaml"

echo "waiting for access key provisioning"
oc wait accesskeys "${CLUSTER}-oidc" --for=condition=Synced --timeout=30m 2>&1 >/dev/null
oc wait accesskeys "${CLUSTER}-oidc" --for=condition=Ready --timeout=30m 2>&1 >/dev/null

# Create the hypershift operator OIDC credentials secret
if ! oc get --namespace hypershift secrets oidc-s3-creds 2>&1 >/dev/null; then
  oc create secret generic oidc-s3-creds --namespace hypershift \
  --from-literal=credentials="[default]
aws_access_key_id=$(oc get accesskeys/${CLUSTER}-oidc -o go-template='{{.status.atProvider.id}}')
aws_secret_access_key=$(oc get -n hypershift secrets/oidc-s3-access-key -o go-template='{{index .data "attribute.secret" | base64decode}}')
"
else
  echo "oidc-s3-secret already exists"
fi

# Install hypershift
oc apply -f "${CLUSTER_DIR}/hypershift-operator.yaml"
