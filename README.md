# Creating a HyperShift CI cluster

## Prerequisites

- OpenShift CLI
- [Crossplane CLI](https://crossplane.io/docs/v1.6/getting-started/install-configure.html#install-crossplane-cli)
- [Helm](https://helm.sh/)
- An OCP cluster ([ROSA instructions](https://www.rosaworkshop.io/rosa/2-deploy/#automatic-mode))

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
