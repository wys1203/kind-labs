# Repository Guidelines

## 語言與溝通規範 (Language & Communication)
- **主要語言**：所有對話、解釋、計畫說明及思考過程必須使用「繁體中文 (Traditional Chinese)」。
- **技術術語**：專業術語若無慣用中文譯名，可保留原文（例如：Hooks, Middleware, Repository Pattern），但解釋須使用繁體中文。
- **程式碼註釋**：除非另有規定，否則產出的代碼註釋應以繁體中文編寫，以確保團隊溝通順暢。


## Project Structure & Module Organization
This repository is a set of local Kubernetes lab scenarios for `kind`, not an application binary. Shared cluster settings live at the repo root in `kind-config.yaml` and the top-level [Makefile](/home/kasm-user/Personal_Data/wys1203/kind/Makefile). Lab content is grouped under `labs/`:

- `labs/kyverno-ha/`: Helm values, StorageClass, Kyverno policies, demo manifests, and shell checks
- `labs/nats-jetstream-keda/`: Kustomize base, one-shot jobs, and verification scripts
- `labs/sandbox/base/`: reusable namespace baseline resources

Keep manifests close to the lab they belong to. Put validation scripts in each lab’s `tests/` directory.

## Build, Test, and Development Commands
Use `make help` to discover the supported workflows. Common commands:

- `make create`: create the local `kind` cluster from `kind-config.yaml`
- `make sandbox-apply`: apply the sandbox baseline with `kubectl apply -k`
- `make kyverno-up`: install Kyverno, apply the policy, and deploy the demo workload
- `make kyverno-verify`: run the Kyverno verification script
- `make nats-keda-up`: install KEDA, apply the NATS JetStream lab, and bootstrap stream state
- `make nats-keda-verify`: run the NATS/KEDA verification script
- `make delete`: tear down the cluster

## Coding Style & Naming Conventions
Shell scripts use POSIX `sh` with `set -eu`, two-space indentation, and explicit error messages. Prefer small, composable scripts over dense one-liners. Kubernetes manifests use lowercase, hyphenated filenames such as `orders-worker-deployment.yaml` and `mutate-zone-spread.yaml`. Keep resource names and namespaces consistent with their directory names. Preserve the existing Kustomize and Helm file layout instead of introducing new tooling.

## Testing Guidelines
Tests are shell-based environment checks and verification scripts under `labs/*/tests/`. Name executable checks `preflight.sh` for prerequisite validation and `verify.sh` for end-to-end inspection. Run the relevant `make <lab>-verify` target after changing manifests. For infra changes, also run the matching preflight target before applying resources.

## Commit & Pull Request Guidelines
Git history currently uses short, imperative commit subjects, for example: `Add kind and Kyverno HA lab scaffolding`. Follow that pattern and keep each commit scoped to one lab or workflow change. Pull requests should include:

- a brief summary of the scenario or fix
- the `make` commands used to validate it
- linked issues, if any
- screenshots or `kubectl` output only when they clarify behavior changes
