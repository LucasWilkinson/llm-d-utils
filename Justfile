set dotenv-load
set dotenv-required
set shell := ["bash", "-c"]

USER_NAME := "lucas"
NAMESPACE := USER_NAME + "-llm-d-wide-ep"
HF_TOKEN := "$HF_TOKEN"
GH_TOKEN := "$GH_TOKEN"

MODEL := "deepseek-ai/DeepSeek-R1-0528"

KN := "kubectl -n " + NAMESPACE

EXAMPLE_DIR := "llm-d/guides/wide-ep-lws"

@print-gpus:
  kubectl get pods -A -o json | jq -r ' \
  .items \
  | map(select(.status.phase=="Running")) \
  | map({ \
  ns: .metadata.namespace, \
  pod: .metadata.name, \
  node: .spec.nodeName, \
  gpus: ([ .spec.containers[]? \
  | ( .resources.limits."nvidia.com/gpu" \
  // .resources.requests."nvidia.com/gpu" \
  // "0" ) | tonumber ] | add) \
  }) \
  | map(select(.gpus>0 and .node != null)) \
  | sort_by(.node, .ns, .pod) \
  | group_by(.node) \
  | .[] as $grp \
  | "== Node: \($grp[0].node) ==", \
  "NAMESPACE\tPOD\tGPUs", \
  ( $grp[] | "\(.ns)\t\(.pod)\t\(.gpus)" ), \
  "" \
  ' | column -t -s $'\t' \
  | awk 'NR==1{print; next} /^== /{print ""; print; next} {print}'


# Print table of nodes on Coreweave. Quiet recipe since the command is messy
@cks-nodes:
  kubectl get nodes -o=custom-columns="NAME:metadata.name,IP:status.addresses[?(@.type=='InternalIP')].address,TYPE:metadata.labels['node\.coreweave\.cloud\/type'],LINK:metadata.labels['ethernet\.coreweave\.cloud/speed'],READY:status.conditions[?(@.type=='Ready')].status,CORDON:spec.unschedulable,TAINT:spec.taints[?(@.key=='qos.coreweave.cloud/interruptable')].effect,RELIABILITY:metadata.labels['node\.coreweave\.cloud\/reliability'],LG:metadata.labels['ib\.coreweave\.cloud\/leafgroup'],VERSION:metadata.labels['node\.coreweave\.cloud\/version'],IB:metadata.labels['ib\.coreweave\.cloud\/speed'],STATE:metadata.labels['node\.coreweave\.cloud\/state'],RESERVED:metadata.labels['node\.coreweave\.cloud\/reserved']"

create-secrets:
  kubectl create secret generic llm-d-hf-token \
    --from-literal=HF_TOKEN={{HF_TOKEN}} \
    -n {{NAMESPACE}} \
    --dry-run=client -o yaml \
    | kubectl apply -n {{NAMESPACE}} -f - \
  && kubectl create secret generic gh-token-secret \
    --from-literal=GH_TOKEN={{GH_TOKEN}} \
    -n {{NAMESPACE}} \
    --dry-run=client -o yaml \
    | kubectl apply -n {{NAMESPACE}} -f -

start-bench:
  {{KN}} delete pod benchmark-interactive --ignore-not-found
  {{KN}} apply -f benchmark-interactive-pod.yaml

exec-bench:
  mkdir -p ./.tmp \
  && echo "MODEL := \"{{MODEL}}\"" > .tmp/Justfile.remote.tmp \
  && sed -e 's#__BASE_URL__#\"http://infra-wide-ep-inference-gateway-istio.{{NAMESPACE}}.svc.cluster.local\"#g' \
         -e 's#__ENDPOINT__#\"/v1/chat/completions\"#g' \
         Justfile.remote >> .tmp/Justfile.remote.tmp \
  && kubectl cp .tmp/Justfile.remote.tmp {{NAMESPACE}}/benchmark-interactive:/app/Justfile \
  && kubectl cp  ./run.sh {{NAMESPACE}}/benchmark-interactive:/app/run.sh \
  && {{KN}} exec -it benchmark-interactive -- /bin/bash

run-bench name in_tokens='128' out_tokens='2048' num_prompts='16384' concurrency_levels='8192 16384 32768':
  mkdir -p ./.tmp \
  && echo $(date +%m%d%H%M) > .tmp/TIMESTAMP \
  && echo "{{name}}" > .tmp/NAME \
  && echo "MODEL := \"{{MODEL}}\"" > .tmp/Justfile.remote \
  && sed -e 's#__BASE_URL__#\"http://infra-wide-ep-inference-gateway-istio.{{NAMESPACE}}.svc.cluster.local\"#g' \
         -e 's#__ENDPOINT__#\"/v1/chat/completions\"#g' \
         Justfile.remote >> .tmp/Justfile.remote \
  && kubectl cp .tmp/TIMESTAMP {{NAMESPACE}}/benchmark-interactive:/app/TIMESTAMP \
  && kubectl cp .tmp/NAME {{NAMESPACE}}/benchmark-interactive:/app/NAME \
  && kubectl cp .tmp/Justfile.remote {{NAMESPACE}}/benchmark-interactive:/app/Justfile \
  && kubectl cp  ./run.sh {{NAMESPACE}}/benchmark-interactive:/app/run.sh \
  && kubectl cp  {{EXAMPLE_DIR}}/ms-wide-ep/values.yaml {{NAMESPACE}}/benchmark-interactive:/app/values.yaml \
  && {{KN}} exec benchmark-interactive -- \
       env INPUT_TOKENS={{in_tokens}} \
           OUTPUT_TOKENS={{out_tokens}} \
           NUM_PROMPTS={{num_prompts}} \
           CONCURRENCY_LEVELS="{{concurrency_levels}}" \
           bash /app/run.sh

cp-results:
  kubectl cp benchmark-interactive:/app/results/$(cat ./.tmp/TIMESTAMP) \
  results/$(cat ./.tmp/TIMESTAMP)

set-namespace:
  kubectl config set-context --current --namespace={{NAMESPACE}}

get-pods:
  {{KN}} get pods

describe name='':
  scripts/describe-pod.sh {{NAMESPACE}} "{{name}}"

stern name='':
  scripts/stern-pod.sh {{NAMESPACE}} "{{name}}"

status:
  watch -n 2 {{KN}} get pods

start:
  cd {{EXAMPLE_DIR}} \
  && helmfile -n {{NAMESPACE}} apply

stop:
  cd {{EXAMPLE_DIR}} \
  && helmfile -n {{NAMESPACE}} destroy

restart:
  just stop && just start

print-results DIR STR:
  grep "{{STR}}" {{DIR}}/*.log \
  | awk -F'[/_]' '{print $3, $0}' \
  | sort -n \
  | cut -d' ' -f2-

print-throughput DIR:
  just print-results {{DIR}} "Output token throughput"

print-tpot DIR:
  just print-results {{DIR}} "Median TPOT"
