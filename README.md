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
- Optional: [fzf](https://github.com/junegunn/fzf) for the nicer interactive pod pickers used by several recipes

## Initial Setup

1. **Configure your namespace name**
   
   Open `Justfile` and set `USER_NAME` to your username (or desired namespace prefix). The namespace is derived from this value via `NAMESPACE := USER_NAME + "-llm-d-wide-ep"`.

2. **Create a `.env` file**
   
   Because the Justfile loads environment variables via `set dotenv-load`, create a `.env` file in the project root containing your secrets:
   
   ```env
   HF_TOKEN=your-huggingface-token
   GH_TOKEN=your-github-token
   ```
   
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
   
   This will create (or update) the `llm-d-hf-token` and `gh-token-secret` secrets in your namespace using the values from `.env`.

5. **(Optional) Set your kubectl namespace**
   
   To avoid specifying `-n {{NAMESPACE}}` manually, update your context with:
   
   ```bash
   just set-namespace
   ```

6. **Deploy the workload**
   
   Launch the Helm release into your namespace:
   
   ```bash
   just start
   ```
   
   To tear it back down, run `just stop` (for Helm resources) and `just stop-bench` if you launched the benchmark pod. When you’re completely finished, stop the long-running model workloads with `just stop` so the pods vacate your namespace.

   By default the deployment pulls values from `llm-d/guides/wide-ep-lws/ms-wide-ep/values.yaml`. The `decode.parallelism.data` field (default `2`) controls how many decode workers are scheduled; update it to match the number of nodes you want to dedicate:

   ```yaml
   decode:
     parallelism:
       # This must equal the number of nodes rather than the dp_size.
       data: 1  # change as needed
   ```

   The benchmarking helpers (e.g. `just run-bench`) default to the deployment’s model (`deepseek-ai/DeepSeek-R1-0528`). If you change the model in `values.yaml`, update the `MODEL` variable near the top of the `Justfile` so the generated remote Justfile targets the right endpoint.

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

- `just start-bench`, `just exec-bench`, `just run-bench NAME`
  
  Helpers for provisioning and driving the benchmark interactive pod. See `Justfile` for the full command flow.

- `just status`
  
  Open a `watch` loop of `kubectl get pods` for the namespace so you can monitor pod status changes in real time.

## Troubleshooting

- If `just` reports missing environment variables, double-check your `.env` file and ensure you’re running commands from the repository root.
- Kubernetes errors such as `CreateContainerConfigError` usually indicate a missing or misnamed secret; re-run `just create-secrets` after updating `.env`, or inspect the pod events via `just describe name=...`.
- For log streaming issues, ensure `stern` is installed and your kubeconfig points to the correct cluster.

With the setup above you should be able to deploy, inspect, and debug the LLMD workloads quickly using the provided Just recipes.
