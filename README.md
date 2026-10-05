# Agent Ratings Platform

A Rotten Tomatoes–style rating site for AI agent companies, built as a **Kubernetes platform engineering portfolio project**.

The application is intentionally simple. Roughly 90% of the effort goes into the platform underneath it: cluster provisioning, CI/CD, security, and observability, all built the way I would build them for a production team.

## Status

| Phase | Scope | Status |
|-------|-------|--------|
| 1a | LKE cluster via Terraform, remote state | ✅ Done |
| 1b | Gateway API (Envoy Gateway) + cert-manager | ⏳ Next |
| 1c | Sample app exposed over TLS | Planned |
| — | GitOps bootstrap (Argo CD or Flux) | Planned |
| 2+ | CI/CD pipeline, security hardening, observability | Planned |

## Architecture decisions

**Terraform builds the cluster and nothing else.** In-cluster components are installed with Helm (values files committed under `platform/`) and will move to GitOps. Managing in-cluster resources from the same Terraform that creates the cluster causes a chicken-and-egg problem: the Helm/Kubernetes providers need a cluster that doesn't exist yet at plan time.

**Cloud-portable module contract.** `infra/modules/lke-cluster` exposes `cluster_id`, `api_endpoints`, and `kubeconfig`. Future AKS/EKS modules will expose the same outputs, so everything downstream stays the same when the cloud changes.

**Gateway API instead of Ingress.** ingress-nginx has been retired. Gateway API separates infrastructure (GatewayClass), platform (Gateway), and application (HTTPRoute) concerns, and makes features standard that used to depend on vendor-specific annotations.

**Cluster configuration**
- Linode provider `~> 3.14`, Kubernetes 1.36, region `us-east`
- Node pool: 2–4 × `g6-standard-2`, autoscaled
- `lifecycle { ignore_changes }` on pool count so autoscaler activity doesn't appear as drift
- Non-HA control plane (cost tradeoff for a dev environment)

**Security**
- API server ACL restricted to a single /32. Variable validation rejects `0.0.0.0/0`.
- Least-privilege Linode API token: R/W on Kubernetes, Linodes, NodeBalancers, and Volumes; read-only on Events
- Secrets live only in a local env file (`chmod 600`), never in the repo. `terraform.tfvars` and `backend.hcl` are gitignored; `.example` versions are committed.
- Remote state in Linode Object Storage (S3 backend) with `use_lockfile`

## Repository layout

```
infra/
  modules/lke-cluster/   # reusable cluster module (versions, variables, main, outputs)
  envs/dev/              # dev environment root (backend, tfvars, module call)
scripts/
  pre-destroy.sh         # removes LoadBalancer Services and PVCs before destroy
```

## Prerequisites

- Terraform >= 1.10
- kubectl
- linode-cli
- A Linode API token with the scopes listed above
- A Linode Object Storage bucket and an access key **in the same region as the bucket**

## Usage

### 1. Credentials

Create `~/.config/agent-ratings.env`:

```bash
export LINODE_TOKEN='...'
export LINODE_CLI_TOKEN="$LINODE_TOKEN"
export AWS_ACCESS_KEY_ID='...'        # Linode Object Storage key (S3 backend)
export AWS_SECRET_ACCESS_KEY='...'
```

```bash
chmod 600 ~/.config/agent-ratings.env
source ~/.config/agent-ratings.env
```

Re-source the file in every open shell after editing it.

### 2. Configure the environment

```bash
cd infra/envs/dev
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
# edit both files with real values
```

### 3. Build

```bash
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

### 4. Get the kubeconfig

LKE returns the kubeconfig base64-encoded. Regenerate it after every apply:

```bash
terraform output -raw kubeconfig > ~/.kube/agent-ratings-dev.yaml
chmod 600 ~/.kube/agent-ratings-dev.yaml
export KUBECONFIG=~/.kube/agent-ratings-dev.yaml
kubectl get nodes
```

### 5. Tear down

Always run destroy from `infra/envs/dev`. From any other directory it finds no state and does nothing, without warning.

```bash
cd infra/envs/dev
../../../scripts/pre-destroy.sh
terraform destroy
terraform state list          # should be empty
```

Then check for billable resources that Terraform doesn't track:

```bash
linode-cli lke clusters-list
linode-cli nodebalancers list
linode-cli volumes list
```

## Lessons learned

Real problems hit while building this, with root causes.

| Problem | Cause | Fix |
|---------|-------|-----|
| `InvalidAccessKeyId` on `terraform init` | Linode Object Storage keys are region-scoped | Create the key in the bucket's region |
| Plan failed on example values | Placeholder k8s version and IP left in tfvars | Validation caught it at plan time; no bad infra was created |
| Destroy failed with 401 after deleting the cluster | Token could delete the cluster but lacked Events read, which it needs to confirm the deletion | Add read-only Events scope. The next refresh found the cluster gone and cleaned up state. |
| `LoadBalancer` / PVC resources survive `terraform destroy` | NodeBalancers and Volumes are created by the cluster, not Terraform | `pre-destroy.sh` plus post-destroy orphan checks |

## Known gaps

- State locking with `use_lockfile` on Linode Object Storage has not been verified yet. It depends on S3 conditional writes, and S3-compatible stores don't always implement them.
- Single environment (dev) only.
- Non-HA control plane.
