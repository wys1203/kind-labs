CLUSTER_NAME ?= kind
KIND_CONFIG ?= kind-config.yaml
SANDBOX_DIR ?= labs/sandbox/base
KYVERNO_NAMESPACE ?= kyverno
KYVERNO_RELEASE ?= kyverno
KYVERNO_CHART_VERSION ?= 3.2.8
KYVERNO_VALUES ?= labs/kyverno-ha/helm/values.yaml
KEDA_NAMESPACE ?= keda
KEDA_RELEASE ?= keda
KEDA_CHART_VERSION ?= 2.12.0
NATS_KEDA_BASE_DIR ?= labs/nats-jetstream-keda/base

.PHONY: help install-kind create delete recreate status sandbox-apply sandbox-delete \
	kyverno-install kyverno-uninstall kyverno-policy-apply kyverno-policy-delete \
	kyverno-demo-apply kyverno-demo-delete kyverno-demo-status kyverno-demo-exception \
	kyverno-demo-scale \
	kyverno-storageclass-apply kyverno-storageclass-delete kyverno-preflight \
	kyverno-verify kyverno-up kyverno-down kyverno-reset kyverno-ready \
	keda-install keda-uninstall keda-ready \
	nats-keda-preflight nats-keda-apply nats-keda-bootstrap nats-keda-publish \
	nats-keda-status nats-keda-verify nats-keda-delete nats-keda-up nats-keda-down

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
		'make kyverno-reset Rebuild the full Kyverno HA lab from scratch' \
		'make keda-install Install a KEDA release compatible with Kubernetes 1.26' \
		'make nats-keda-up Install KEDA, apply the NATS JetStream lab, and bootstrap stream state' \
		'make nats-keda-publish Create a publisher job that seeds JetStream backlog' \
		'make nats-keda-status Show NATS, worker, and scaler status' \
		'make nats-keda-verify Run the NATS/KEDA lab verification script' \
		'make nats-keda-down Remove the NATS JetStream lab and KEDA'

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

keda-install:
	helm repo add kedacore https://kedacore.github.io/charts
	helm repo update
	helm upgrade --install $(KEDA_RELEASE) kedacore/keda \
		--namespace $(KEDA_NAMESPACE) \
		--create-namespace \
		--version $(KEDA_CHART_VERSION)
	$(MAKE) keda-ready

keda-ready:
	kubectl wait --for=condition=available deployment/$(KEDA_RELEASE)-operator -n $(KEDA_NAMESPACE) --timeout=180s
	@metrics_deployment=$$( \
		for name in $(KEDA_RELEASE)-operator-metrics-apiserver $(KEDA_RELEASE)-metrics-apiserver; do \
			if kubectl get deployment/$$name -n $(KEDA_NAMESPACE) >/dev/null 2>&1; then \
				echo $$name; \
				break; \
			fi; \
		done \
	); \
	if [ -z "$$metrics_deployment" ]; then \
		echo "Unable to find a KEDA metrics apiserver deployment in namespace $(KEDA_NAMESPACE)" >&2; \
		exit 1; \
	fi; \
	kubectl wait --for=condition=available deployment/$$metrics_deployment -n $(KEDA_NAMESPACE) --timeout=180s
	@webhook_deployment=$$( \
		for name in $(KEDA_RELEASE)-admission-webhooks $(KEDA_RELEASE)-operator-webhooks; do \
			if kubectl get deployment/$$name -n $(KEDA_NAMESPACE) >/dev/null 2>&1; then \
				echo $$name; \
				break; \
			fi; \
		done \
	); \
	if [ -z "$$webhook_deployment" ]; then \
		echo "Unable to find a KEDA webhook deployment in namespace $(KEDA_NAMESPACE)" >&2; \
		exit 1; \
	fi; \
	kubectl wait --for=condition=available deployment/$$webhook_deployment -n $(KEDA_NAMESPACE) --timeout=180s

keda-uninstall:
	helm uninstall $(KEDA_RELEASE) -n $(KEDA_NAMESPACE) || true
	kubectl delete namespace $(KEDA_NAMESPACE) --ignore-not-found=true

nats-keda-preflight:
	./labs/nats-jetstream-keda/tests/preflight.sh

nats-keda-apply:
	kubectl apply -k $(NATS_KEDA_BASE_DIR)
	kubectl rollout status statefulset/nats -n nats-jetstream-keda --timeout=180s
	kubectl rollout status deployment/orders-worker -n nats-jetstream-keda --timeout=180s

nats-keda-bootstrap:
	kubectl delete job nats-jetstream-bootstrap -n nats-jetstream-keda --ignore-not-found=true
	kubectl apply -f labs/nats-jetstream-keda/jobs/bootstrap.yaml
	kubectl wait --for=condition=complete job/nats-jetstream-bootstrap -n nats-jetstream-keda --timeout=180s

nats-keda-publish:
	kubectl delete job nats-orders-publisher -n nats-jetstream-keda --ignore-not-found=true
	kubectl apply -f labs/nats-jetstream-keda/jobs/publish.yaml

nats-keda-status:
	kubectl get pods -n nats-jetstream-keda -o wide
	kubectl get scaledobject,hpa -n nats-jetstream-keda
	kubectl get jobs -n nats-jetstream-keda

nats-keda-verify:
	./labs/nats-jetstream-keda/tests/verify.sh

nats-keda-delete:
	kubectl delete namespace nats-jetstream-keda --ignore-not-found=true

nats-keda-up: nats-keda-preflight keda-install nats-keda-apply nats-keda-bootstrap

nats-keda-down: nats-keda-delete keda-uninstall
