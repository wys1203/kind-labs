CLUSTER_NAME ?= kind
KIND_CONFIG ?= kind-config.yaml
SANDBOX_DIR ?= labs/sandbox/base
KYVERNO_NAMESPACE ?= kyverno
KYVERNO_RELEASE ?= kyverno
KYVERNO_CHART_VERSION ?= 3.2.8
KYVERNO_VALUES ?= labs/kyverno-ha/helm/values.yaml

.PHONY: help install-kind create delete recreate status sandbox-apply sandbox-delete \
	kyverno-install kyverno-uninstall kyverno-policy-apply kyverno-policy-delete \
	kyverno-demo-apply kyverno-demo-delete kyverno-demo-status kyverno-demo-exception \
	kyverno-demo-scale \
	kyverno-storageclass-apply kyverno-storageclass-delete kyverno-preflight \
	kyverno-verify kyverno-up kyverno-down kyverno-reset kyverno-ready

help:
	@printf '%s\n' \
		'make install-kind  Install kind binary' \
		'make create        Create the kind cluster' \
		'make delete        Delete the kind cluster' \
		'make recreate      Recreate the kind cluster' \
		'make status        Show cluster nodes' \
		'make sandbox-apply Apply the sandbox baseline' \
		'make sandbox-delete Delete the sandbox namespace' \
		'make kyverno-up Build the full Kyverno HA lab' \
		'make kyverno-demo-status Show demo pods, PVCs, and nodes' \
		'make kyverno-verify Run the end-to-end verification script' \
		'make kyverno-demo-exception Deploy the exempt demo app' \
		'make kyverno-demo-scale Deploy a 6-replica demo app' \
		'make kyverno-ready Wait for Kyverno CRDs and controllers' \
		'make kyverno-down Remove demo, policy, Kyverno, and lab StorageClass' \
		'make kyverno-reset Rebuild the full Kyverno HA lab from scratch'

install-kind:
	./scripts/install-kind.sh

create:
	kind create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG)

delete:
	kind delete cluster --name $(CLUSTER_NAME)

recreate: delete create

status:
	kubectl get nodes -o wide

sandbox-apply:
	kubectl apply -k $(SANDBOX_DIR)

sandbox-delete:
	kubectl delete namespace sandbox --ignore-not-found=true

kyverno-install:
	@status=$$(helm status $(KYVERNO_RELEASE) -n $(KYVERNO_NAMESPACE) 2>/dev/null | sed -n 's/^STATUS: //p'); \
	if [ "$$status" = "uninstalling" ] && \
		kubectl get deployment/kyverno-admission-controller -n $(KYVERNO_NAMESPACE) >/dev/null 2>&1 && \
		kubectl get crd clusterpolicies.kyverno.io >/dev/null 2>&1; then \
		echo "Kyverno resources are already running; skipping Helm install because the release is stuck in uninstalling state."; \
	else \
		helm repo add kyverno https://kyverno.github.io/kyverno/; \
		helm repo update; \
		helm upgrade --install $(KYVERNO_RELEASE) kyverno/kyverno \
			--namespace $(KYVERNO_NAMESPACE) \
			--create-namespace \
			--version $(KYVERNO_CHART_VERSION) \
			-f $(KYVERNO_VALUES); \
	fi
	$(MAKE) kyverno-ready

kyverno-ready:
	sh -c 'i=0; while [ $$i -lt 60 ]; do \
		kubectl get crd clusterpolicies.kyverno.io >/dev/null 2>&1 && exit 0; \
		i=$$((i + 1)); \
		sleep 2; \
	done; \
	echo "Timed out waiting for Kyverno CRD clusterpolicies.kyverno.io" >&2; \
	exit 1'
	kubectl wait --for=condition=available deployment/kyverno-admission-controller -n $(KYVERNO_NAMESPACE) --timeout=180s
	kubectl wait --for=condition=available deployment/kyverno-background-controller -n $(KYVERNO_NAMESPACE) --timeout=180s
	kubectl wait --for=condition=available deployment/kyverno-cleanup-controller -n $(KYVERNO_NAMESPACE) --timeout=180s
	kubectl wait --for=condition=available deployment/kyverno-reports-controller -n $(KYVERNO_NAMESPACE) --timeout=180s

kyverno-storageclass-apply:
	kubectl apply -f labs/kyverno-ha/storageclass/block-ssd.yaml

kyverno-storageclass-delete:
	kubectl delete -f labs/kyverno-ha/storageclass/block-ssd.yaml --ignore-not-found=true

kyverno-preflight:
	./labs/kyverno-ha/tests/preflight.sh

kyverno-uninstall:
	helm uninstall $(KYVERNO_RELEASE) -n $(KYVERNO_NAMESPACE) --no-hooks || true
	kubectl delete namespace $(KYVERNO_NAMESPACE) --ignore-not-found=true

kyverno-policy-apply:
	$(MAKE) kyverno-ready
	kubectl apply -f labs/kyverno-ha/policies/mutate-zone-spread.yaml

kyverno-policy-delete:
	kubectl delete -f labs/kyverno-ha/policies/mutate-zone-spread.yaml --ignore-not-found=true

kyverno-demo-apply:
	kubectl apply -f labs/kyverno-ha/demo/namespace.yaml
	kubectl apply -f labs/kyverno-ha/demo/service.yaml
	kubectl apply -f labs/kyverno-ha/demo/statefulset.yaml

kyverno-demo-exception:
	kubectl apply -f labs/kyverno-ha/demo/namespace.yaml
	kubectl apply -f labs/kyverno-ha/demo/exception-service.yaml
	kubectl apply -f labs/kyverno-ha/demo/exception-statefulset.yaml

kyverno-demo-scale:
	kubectl apply -f labs/kyverno-ha/demo/namespace.yaml
	kubectl apply -f labs/kyverno-ha/demo/scale-service.yaml
	kubectl apply -f labs/kyverno-ha/demo/scale-statefulset.yaml

kyverno-demo-delete:
	kubectl delete namespace kyverno-ha-demo --ignore-not-found=true

kyverno-demo-status:
	kubectl get pods -n kyverno-ha-demo -o wide
	kubectl get pvc -n kyverno-ha-demo
	kubectl get nodes -L topology.kubernetes.io/zone

kyverno-verify:
	./labs/kyverno-ha/tests/verify.sh

kyverno-up: kyverno-storageclass-apply kyverno-preflight kyverno-install kyverno-policy-apply kyverno-demo-apply

kyverno-down: kyverno-demo-delete kyverno-policy-delete kyverno-uninstall kyverno-storageclass-delete

kyverno-reset: kyverno-down kyverno-up
