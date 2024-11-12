
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

# Function to check if the compliance operator is installed in OpenShift
check_compliance_operator_installed() {
  local COMPLIANCE_OPERATOR
  COMPLIANCE_OPERATOR=$(oc get csv -n openshift-compliance --no-headers | grep compliance-operator)

  if [[ -n "$COMPLIANCE_OPERATOR" ]]; then
    print_pass "Compliance Operator is installed"
  else
    print_fail "Compliance Operator is not installed"
  fi
}

# Function to check CSI driver provider
check_csi_driver_provider() {
  local CSI_DRIVER
  CSI_DRIVER=$(oc get csidrivers --no-headers | awk '{print $1}')

  if [[ -n "$CSI_DRIVER" ]]; then
    echo "CSI Driver Provider(s) found:"
    for driver in $CSI_DRIVER; do
      print_check "CSI Driver: $driver"
    done
  else
    print_fail "No CSI Driver Provider found"
  fi
}

# Function to check if OAuth configuration has at least htpasswd
check_oauth_htpasswd() {
  local OAUTH_PROVIDERS
  OAUTH_PROVIDERS=$(oc get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}')

  if echo "$OAUTH_PROVIDERS" | grep -q "htpasswd"; then
    print_pass "OAuth configuration includes htpasswd"
  else
    print_fail "OAuth configuration does not include htpasswd"
  fi
}

# Function to check if Alertmanager configuration exists in OpenShift
check_alertmanager_configuration() {
  local ALERTMANAGER_CONFIG
  ALERTMANAGER_CONFIG=$(oc get secret -n openshift-monitoring alertmanager-main -o jsonpath='{.data.alertmanager\.yaml}')

  if [[ -n "$ALERTMANAGER_CONFIG" ]]; then
    print_pass "Alertmanager configuration exists"
  else
    print_fail "Alertmanager configuration does not exist"
  fi
}

# Function to check if any node has CPU or memory requests exceeding 70%
check_node_resource_requests() {
  local NODES
  NODES=$(oc get nodes --no-headers -o custom-columns=NAME:.metadata.name)

  for node in $NODES; do
    local ALLOCATED_RESOURCES
    ALLOCATED_RESOURCES=$(oc describe node $node | awk '/Allocated resources/,/Events/')

    local CPU_REQUESTS
    local MEMORY_REQUESTS
    CPU_REQUESTS=$(echo "$ALLOCATED_RESOURCES" | grep "cpu" | awk '{print $2, $3}')
    MEMORY_REQUESTS=$(echo "$ALLOCATED_RESOURCES" | grep "memory" | awk '{print $2, $3}')

    print_check "$node has CPU requests at $CPU_REQUESTS"
    print_check "$node has memory requests at $MEMORY_REQUESTS"
  done
}

# Function to check the number of router pods in OpenShift
check_router_pods() {
  local ROUTER_PODS
  ROUTER_PODS=$(oc get pods -n openshift-ingress --no-headers | grep router | wc -l)

  if [[ "$ROUTER_PODS" -gt 0 ]]; then
    print_pass "Number of router pods: $ROUTER_PODS"
  else
    print_fail "No router pods found"
  fi
}

# Function to check if any node is tainted
check_node_taints() {
  local TAINTED_NODES
  TAINTED_NODES=$(oc get nodes --no-headers | awk '{print $1}' | xargs -I {} oc describe node {} | grep -B 1 "Taints: " | grep "Name:" | awk '{print $2}')

  if [[ -n "$TAINTED_NODES" ]]; then
    for node in $TAINTED_NODES; do
      print_check "Node $node is tainted"
    done
  else
    print_check "No nodes are tainted"
  fi
}

# Function to check if router uses self-signed certificates
check_router_certificate() {
  local ROUTER_CERT
  ROUTER_CERT=$(oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.spec.defaultCertificate}')

  if [[ -z "$ROUTER_CERT" ]]; then
    print_fail "Router uses self-signed certificate"
  else
    print_pass "Router is using a custom certificate"
  fi
}

# Function to list all ingresscontrollers
list_all_ingresscontrollers() {
  local INGRESSCONTROLLERS
  INGRESSCONTROLLERS=$(oc get ingresscontroller -n openshift-ingress-operator --no-headers | awk '{print $1}')

  if [[ -n "$INGRESSCONTROLLERS" ]]; then
    echo "IngressControllers found:"
    for ingress in $INGRESSCONTROLLERS; do
      print_check "IngressController: $ingress"
    done
  else
    print_fail "No IngressControllers found"
  fi
}

# Call the function to check etcd encryption
check_etcd_encryption

# Call the function to check cluster-monitoring-config
check_cluster_monitoring_config

# Call the function to check if all pods in openshift-monitoring are running
check_pods_running

# Call the function to check node readiness
check_node_readiness

# Call the function to check pods not running in the cluster
#check_pods_not_running_with_namespace

# Call the function to check if all MachineConfigPools are updated
check_mcp_updated

# Call the function to check kubeletconfig dynamic resource configuration
check_kubeletconfig_dynamic_resource

# Call the function to check OpenShift CNI
check_openshift_cni

# Call the function to check OpenShift cluster network and service network
check_openshift_networks

# Call the function to check if the compliance operator is installed
check_compliance_operator_installed

# Call the function to check CSI driver provider
check_csi_driver_provider

# Call the function to check OAuth configuration for htpasswd
check_oauth_htpasswd

# Call the function to check Alertmanager configuration
check_alertmanager_configuration

# Call the function to check node resource requests
#check_node_resource_requests

# Call the function to check the number of router pods
check_router_pods

check_node_taints

# Call the function to check router certificate
check_router_certificate

# Call the function to list all ingresscontrollers
list_all_ingresscontrollers
