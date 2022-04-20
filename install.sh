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
$(oc crossplane --help >/dev/null) || die "missing crossplane kubectl plugin"
[ -d "$CLUSTER_DIR" ] || die "cluster not found"
[ -f "$AWS_CREDS" ] || die "AWS creds file not found"

# Install the ops namespace, admin SA, and RBAC
oc apply -f "${COMMON_DIR}/hypershift-ops.yaml"

# Prepare the Crossplane namespace
oc apply -f "${COMMON_DIR}/crossplane-system.yaml"

# Install crossplane
if ! oc get -n crossplane-system deployments/crossplane 2>&1 >/dev/null; then
  echo "installing crossplane"
  helm install crossplane \
    --namespace crossplane-system crossplane-stable/crossplane \
    --set securityContextCrossplane.runAsUser=null \
    --set securityContextRBACManager.runAsUser=null
else
  echo "crossplane already installed"
fi

# Wait crossplane to roll out
echo "waiting for crossplane to roll out"
oc wait --namespace crossplane-system deployments/crossplane --for=condition=Available --timeout=30m 2>&1 >/dev/null
wait_for_crd "controllerconfigs.pkg.crossplane.io"

# By default, deployments managed by Crossplane will run as arbitrary UIDs like
# 2000, which is incompatible with OCP. Add a special Crossplane controller
# config which instructs Crossplane to use security context configurations
# compatible with OCP.
oc apply -f "${COMMON_DIR}/crossplane-controllerconfig.yaml"

# Install the Crossplane AWS provider (note that it references the controller
# config previously created)
if ! oc get customresourcedefinitions providerconfigs.aws.jet.crossplane.io 2>&1 >/dev/null; then
  echo "installing crossplane aws provider"
  oc crossplane install provider crossplane/provider-jet-aws:v0.4.0-preview --config=openshift-config
else
  echo "crossplane aws provider already installed"
fi

wait_for_crd "providerconfigs.aws.jet.crossplane.io"

# Configure the Crossplane AWS provider to reference the AWS creds secret
oc apply -f "${COMMON_DIR}/jet-aws-providerconfig.yaml"

# Create the AWS credentials for the Crossplane AWS provider
# TODO: Update if it already exists
if ! oc get -n crossplane-system secrets aws-creds 2>&1 >/dev/null; then
  oc create secret generic aws-creds -n crossplane-system --from-file=creds=$AWS_CREDS
else
  echo "crossplane AWS creds already exist"
fi

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
