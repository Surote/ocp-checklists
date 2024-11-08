
#!/bin/bash
# Author: Surote Wongpaiboon
# License: Non-commercial use, continue.dev

# Function to print in green text
print_pass() {
  local topic=$1
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e "\033[0;32mPASS: $topic\033[0m"
  else
    echo -e "\e[32mPASS: $topic\e[0m"
  fi
}

# Function to print in red text
print_fail() {
  local topic=$1
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e "\033[0;31mFAILED: $topic\033[0m"
  else
    echo -e "\e[31mFAILED: $topic\e[0m"
  fi
}

# Function to print in yellow text
print_check() {
  local topic=$1
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e "\033[0;33mCHECK: $topic\033[0m"
  else
    echo -e "\e[33mCHECK: $topic\e[0m"
  fi
}

# Function to check etcd encryption config in Kubernetes
check_etcd_encryption() {
  local ENCRYPTION_CONFIG
  ENCRYPTION_CONFIG=$(oc get apiserver cluster -o jsonpath='{.spec.encryption.type}')

  if [[ -n "$ENCRYPTION_CONFIG" ]]; then
    # Check if encryption is enabled in the configuration
    if echo "$ENCRYPTION_CONFIG" | grep -q "ae"; then
      print_pass "etcd encryption"
    else
      print_fail "etcd encryption"
    fi
  else
    print_fail "etcd encryption"
  fi
}

# Function to check cluster-monitoring-config in OpenShift
check_cluster_monitoring_config() {
  local MONITORING_CONFIG
  MONITORING_CONFIG=$(oc get cm -n openshift-monitoring)

  if echo "$MONITORING_CONFIG" | grep -q "cluster-monitoring-config"; then
    print_pass "cluster-monitoring-config"
  else
    print_fail "cluster-monitoring-config"
  fi
}

# Function to check node readiness in OpenShift
check_node_readiness() {
  local NOT_READY_NODES
  NOT_READY_NODES=$(oc get nodes --no-headers | grep -i "notready" | awk '{print $1}')

  if [[ -n "$NOT_READY_NODES" ]]; then
    for node in $NOT_READY_NODES; do
      print_fail "Node $node is not ready"
    done
  else
    print_pass "All nodes are ready"
  fi
}

# Function to check if all pods in openshift-monitoring namespace are in Running state
check_pods_running() {
  local NON_RUNNING_PODS
  NON_RUNNING_PODS=$(oc get pod -n openshift-monitoring --no-headers | grep -v "Running" | awk '{print $1}')

  if [[ -n "$NON_RUNNING_PODS" ]]; then
    for pod in $NON_RUNNING_PODS; do
      print_fail "Pod $pod is not running"
    done
  else
    print_pass "All pods in openshift-monitoring are running"
  fi
}

# Function to check pods not running in the cluster and return a list with their namespaces
check_pods_not_running_with_namespace() {
  local NON_RUNNING_PODS
  NON_RUNNING_PODS=$(oc get pods --all-namespaces --no-headers | grep -v "Running\|Completed" | awk '{print $1, $2}')

  if [[ -n "$NON_RUNNING_PODS" ]]; then
    while IFS= read -r line; do
      local namespace=$(echo $line | awk '{print $1}')
      local pod=$(echo $line | awk '{print $2}')
      print_fail "Pod $pod in namespace $namespace is not running"
    done <<< "$NON_RUNNING_PODS"
  else
    print_pass "All pods in the cluster are running"
  fi
}

# Function to check if all MachineConfigPools are updated
check_mcp_updated() {
  local MCP_STATUS
  MCP_STATUS=$(oc get mcp --no-headers | awk '{print $1, $3}')

  if [[ -n "$MCP_STATUS" ]]; then
    while IFS= read -r line; do
      local mcp=$(echo $line | awk '{print $1}')
      local updated=$(echo $line | awk '{print $2}')
      if [[ "$updated" == "True" ]]; then
        print_pass "MCP $mcp is updated"
      else
        print_fail "MCP $mcp is not updated"
      fi
    done <<< "$MCP_STATUS"
  else
    print_fail "No MCP found"
  fi
}

# Function to check kubeletconfig for dynamic resource configuration
check_kubeletconfig_dynamic_resource() {
  local KUBELETCONFIG
  KUBELETCONFIG=$(oc get kubeletconfig -o jsonpath='{.items[*].spec.autoSizingReserved}')

  if echo "$KUBELETCONFIG" | grep -q "true"; then
    print_pass "KubeletConfig has dynamic resource configuration with autoSizingReserved: true"
  else
    print_fail "KubeletConfig does not have autoSizingReserved: true"
  fi
}

# Function to check OpenShift CNI
check_openshift_cni() {
  local CNI_TYPE
  CNI_TYPE=$(oc get network.operator cluster -o jsonpath='{.spec.defaultNetwork.type}')
  print_check "OpenShift CNI type: $CNI_TYPE"
}

# Function to check OpenShift cluster network and service network
check_openshift_networks() {
  local CLUSTER_NETWORK
  local SERVICE_NETWORK

  CLUSTER_NETWORK=$(oc get network.config/cluster -o jsonpath='{.status.clusterNetwork[*].cidr}')
  SERVICE_NETWORK=$(oc get network.config/cluster -o jsonpath='{.status.serviceNetwork[*]}')

  print_check "Cluster Network CIDR: $CLUSTER_NETWORK"
  print_check "Service Network: $SERVICE_NETWORK"
}

# Call the function to check etcd encryption
check_etcd_encryption

# Call the function to check cluster-monitoring-config
check_cluster_monitoring_config

# Call the function to check node readiness
check_node_readiness

# Call the function to check if all pods in openshift-monitoring are running
check_pods_running

# Call the function to check pods not running in the cluster
check_pods_not_running_with_namespace

# Call the function to check if all MachineConfigPools are updated
check_mcp_updated

# Call the function to check kubeletconfig dynamic resource configuration
check_kubeletconfig_dynamic_resource

# Call the function to check OpenShift CNI
check_openshift_cni

# Call the function to check OpenShift cluster network and service network
check_openshift_networks
