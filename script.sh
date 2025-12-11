#!/bin/bash

NAMESPACE="$1"

if [ -z "$NAMESPACE" ]; then
  echo "Usage: $0 <namespace>"
  exit 1
fi

echo "Collecting Deployments + StatefulSets in namespace: $NAMESPACE"
echo "----------------------------------------------------------------------------------------------"
echo -e "KIND\tNAME\tCONTAINER\tIMAGE\tREQUEST_CPU\tREQUEST_MEM\tLIMIT_CPU\tLIMIT_MEM"

###############################################
# Function to extract resources for a workload
###############################################
extract_resources() {
  kind=$1
  name=$2

  containers=$(oc get "$kind" "$name" -n "$NAMESPACE" -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{" "}{end}')
  
  for container in $containers; do
    image=$(oc get "$kind" "$name" -n "$NAMESPACE" -o jsonpath="{.spec.template.spec.containers[?(@.name=='$container')].image}")
    req_cpu=$(oc get "$kind" "$name" -n "$NAMESPACE" -o jsonpath="{.spec.template.spec.containers[?(@.name=='$container')].resources.requests.cpu}")
    req_mem=$(oc get "$kind" "$name" -n "$NAMESPACE" -o jsonpath="{.spec.template.spec.containers[?(@.name=='$container')].resources.requests.memory}")
    lim_cpu=$(oc get "$kind" "$name" -n "$NAMESPACE" -o jsonpath="{.spec.template.spec.containers[?(@.name=='$container')].resources.limits.cpu}")
    lim_mem=$(oc get "$kind" "$name" -n "$NAMESPACE" -o jsonpath="{.spec.template.spec.containers[?(@.name=='$container')].resources.limits.memory}")

    echo -e "$kind\t$name\t$container\t$image\t$req_cpu\t$req_mem\t$lim_cpu\t$lim_mem"
  done
}

###############################################
# Deployments
###############################################
deployments=$(oc get deploy -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

for dep in $deployments; do
  extract_resources "deploy" "$dep"
done

###############################################
# StatefulSets
###############################################
statefulsets=$(oc get statefulset -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

for sts in $statefulsets; do
  extract_resources "statefulset" "$sts"
done