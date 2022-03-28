kustomize:
	oc kustomize ./clusters/hypershift-ci-1 -o clusters/hypershift-ci-1/hypershift-operator.yaml

verify-kustomize: kustomize
	git diff --exit-code
