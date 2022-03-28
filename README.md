# Creating a HyperShift CI cluster

## Prerequisites

- OpenShift CLI
- [Crossplane CLI](https://crossplane.io/docs/v1.6/getting-started/install-configure.html#install-crossplane-cli)
- [Helm](https://helm.sh/)
- An OCP cluster ([ROSA instructions](https://www.rosaworkshop.io/rosa/2-deploy/#automatic-mode))

## Update the hypershift manifest
```shell
hypershift install render \
  --oidc-storage-provider-s3-bucket-name hypershift-ci-1-oidc \
  --oidc-storage-provider-s3-region us-east-1 \
  --oidc-storage-provider-s3-secret oidc-s3-creds \
  --hypershift-image hypershift-operator:latest > clusters/hypershift-ci-1/hypershift-operator.yaml

make kustomize
```

## Install

Copy the [hypershift-ops-crossplane AWS credentials](https://vault.ci.openshift.org/ui/vault/secrets/kv/show/selfservice/hypershift-team/ops/hypershift-ops-crossplane) from Vault to `$AWS_CREDS`.

Install HyperShift:

```shell
install.sh --cluster $CLUSTER --aws-creds $AWS_CREDS
```

After initial installation or as part of a credentials rotation, create a
kubeconfig from the admin SA token which can be injected into CI jobs:

```shell
oc serviceaccounts --namespace hypershift-ops create-kubeconfig admin > /tmp/$CLUSTER.kubeconfig
```

Store the kubeconfig in Vault [under the clusters directory](https://vault.ci.openshift.org/ui/vault/secrets/kv/list/selfservice/hypershift-team/ops/clusters/) in a secret named `$CLUSTER` with the following schema:

```json
{
  "hypershift-ops-admin.kubeconfig": "<kubeconfig contents>",
  "secretsync/target-name": "$CLUSTER",
  "secretsync/target-namespace": "test-credentials"
}
```

## Uninstall

To uninstall everything and start over, run:

```shell
uninstall.sh
```
