# llm-d-utils

Utilities and workflow helpers for managing LLM-D deployments in Kubernetes. Clone with submodules:

```bash
git clone --recursive https://github.com/LucasWilkinson/llm-d-utils
```

## Prerequisites

Make sure the following tools are installed and available in your `PATH`:

- [just](https://github.com/casey/just) for running the recipes in this repo
- [kubectl](https://kubernetes.io/docs/tasks/tools/) configured for the target cluster
- [helm](https://helm.sh/docs/intro/install/)
- [stern](https://github.com/stern/stern) for streaming pod logs
- [watch](https://formulae.brew.sh/formula/watch)
- Optional: [fzf](https://github.com/junegunn/fzf) for the nicer interactive pod pickers used by several recipes

## Initial Setup

1. **Configure your namespace name**
   
   Open `Justfile` and set `USER_NAME` to your username (or desired namespace prefix). The namespace is derived from this value via `NAMESPACE := USER_NAME + "-llm-d-wide-ep"`.

2. **Create a `.env` file**

   Because the Justfile loads environment variables via `set dotenv-load`, create a `.env` file in the project root containing your secrets:

   ```env
   USER_NAME=your-username
   HF_TOKEN=your-huggingface-token
   GH_TOKEN=your-github-token
   QUAY_REPO=your-quay-username
   QUAY_ROBOT=buildbot
   QUAY_PASSWORD=your-robot-account-token
   ```

   **To get quay.io credentials:**
   - Log into quay.io (via SSO)
   - Go to Account Settings → Robot Accounts
   - Create a new robot account (e.g., `buildbot`)
   - Copy the token and use it as `QUAY_PASSWORD`
   - `QUAY_REPO` should be your quay.io username (not the robot account name)
   - The full robot account name will be constructed as `QUAY_REPO+QUAY_ROBOT`

   These values are required for the secret creation step below.

3. **Point kubectl at your token file**
   
   Export the kubeconfig path you received from the platform (example path shown below):
   
   ```bash
   export KUBECONFIG=~/kubectl-token.txt
   ```

4. **Create Kubernetes secrets**

   Run:

   ```bash
   just create-secrets
   ```

   This will create (or update) the `llm-d-hf-token`, `gh-token-secret`, and `registry-auth` secrets in your namespace using the values from `.env`.

5. **(Optional) Set your kubectl namespace**
   
   To avoid specifying `-n {{NAMESPACE}}` manually, update your context with:
   
   ```bash
   just set-namespace
   ```

6. **Deploy the workload**

   Launch the deployment using Kustomize and Helm:

   ```bash
   just start
   ```

   This will:
   - Deploy model servers using `kubectl apply -k` (CoreWeave variant)
   - Install the InferencePool via Helm (with Istio gateway)
   - Deploy the Istio gateway and HTTPRoute

   To tear it back down, run `just stop`. This removes the Helm release, model server manifests, and gateway resources.

   The deployment uses manifests from `llm-d/guides/wide-ep-lws/manifests/` and values from `llm-d/guides/wide-ep-lws/inferencepool.values.yaml`.

   The benchmarking helpers (e.g. `just run-bench`) default to the deployment's model (`deepseek-ai/DeepSeek-R1-0528`). If you change the model, update the `MODEL` variable near the top of the `Justfile` so the generated remote Justfile targets the right endpoint.

## Everyday Commands

- `just describe [name=pod-name]`
  
  Describe a pod in the configured namespace. If `name` is omitted, you’ll be presented with an interactive picker listing the pod’s `NAME`, `READY`, `STATUS`, `RESTARTS`, and `AGE` columns. Requires `fzf` for the fuzzy picker, otherwise falls back to a shell `select` prompt.

- `just stern [name=pod-name] [-- <stern flags>]`
  
  Stream logs from a pod using stern. With no `name` provided, you get the same interactive picker as `just describe`. Any flags after `--` are forwarded directly to stern (e.g. `just stern -- -c vllm-worker-decode`).

- `just get-pods`
  
  Shortcut for `kubectl get pods` in the configured namespace.

- `just set-namespace`
  
  Update your current kubectl context to default to `{{NAMESPACE}}`.

- `just cp-results`
  
  Copy the most recent benchmark results from the `benchmark-interactive` pod to `results/<timestamp>` locally.

- `just start-bench`, `just interact-bench`, `just run-bench NAME`
  
  Helpers for provisioning and driving the benchmark interactive pod. See `Justfile` for the full command flow.

- `just status`
  
  Open a `watch` loop of `kubectl get pods` for the namespace so you can monitor pod status changes in real time.

### Benchmark knobs

`just run-bench` accepts optional parameters so you can tune the payload:

```bash
just run-bench name=run1 in_tokens=256 out_tokens=1024 num_prompts=8192
```

- `in_tokens` (default `128`): prompt length fed to `vllm bench`.
- `out_tokens` (default `2048`): target completion length.
- `num_prompts` (default `16384`): total requests per concurrency level.
- `concurrency_levels` (default `'8192 16384 32768'`): whitespace-separated list swept by the helper.

These values are forwarded into the remote runner as environment variables, so you can also invoke `kubectl exec … INPUT_TOKENS=… bash /app/run.sh` manually if needed.

## Building Custom vLLM Images

To build a custom vLLM image with a specific commit:

1. **Start the build pod:**
   ```bash
   just start-build-pod
   ```

2. **Build and push the image:**
   ```bash
   just build-image VLLM_COMMIT_SHA TAG

   # Example:
   just build-image 8ce5d3198d00631a76e1aa02a57947b46bc7218c mtp-enabled
   ```

   This will:
   - Clone the llm-d repository
   - Update the Dockerfile with your specified vLLM commit
   - Build the image using buildah
   - Push to `quay.io/QUAY_REPO/llm-d-cuda-dev:TAG`

3. **Update the manifests:**

   Edit `llm-d/guides/wide-ep-lws/manifests/modelserver/base/decode.yaml` and `prefill.yaml` to use your custom image:
   ```yaml
   image: quay.io/your-repo/llm-d-cuda-dev:your-tag
   ```

4. **Clean up the build pod:**
   ```bash
   just stop-build-pod
   ```

**Note:** The build takes 30-60+ minutes. Monitor progress with:
```bash
kubectl logs -f buildah-build -n your-namespace
```

## Troubleshooting

- If `just` reports missing environment variables, double-check your `.env` file and ensure you’re running commands from the repository root.
- Kubernetes errors such as `CreateContainerConfigError` usually indicate a missing or misnamed secret; re-run `just create-secrets` after updating `.env`, or inspect the pod events via `just describe name=...`.
- For log streaming issues, ensure `stern` is installed and your kubeconfig points to the correct cluster.

With the setup above you should be able to deploy, inspect, and debug the LLMD workloads quickly using the provided Just recipes.
