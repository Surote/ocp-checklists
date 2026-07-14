# CLAUDE.md — ocp-checklists

Guidance for AI assistants working in this repository.

## Project Overview

`ocp-checklists` is a lightweight, pure-bash diagnostic toolkit for Red Hat OpenShift Container Platform (OCP) clusters. It provides two complementary tools:

- **`ocp-checklists.sh`** — Quick compliance/health checks with color-coded PASS/FAIL/CHECK output.
- **`healthcheck.sh`** — Comprehensive diagnostic data dump for deep troubleshooting, producing a timestamped `.tar.gz` archive.

There are no package managers, build systems, or external dependencies. The only runtime requirement is the `oc` (OpenShift CLI) binary authenticated against a live OCP cluster.

**Author:** Surote Wongpaiboon  
**License:** Apache 2.0

---

## Repository Structure

```
ocp-checklists/
├── ocp-checklists.sh   # Health/compliance check script (358 lines)
├── healthcheck.sh      # Full diagnostic dump script (321 lines)
├── README.md           # Minimal placeholder
├── LICENSE             # Apache 2.0
└── CLAUDE.md           # This file
```

No test directories, CI configuration, linting configs, or build files exist.

---

## Script Details

### ocp-checklists.sh

Runs 17 health checks against a live OCP cluster and prints results to stdout. Checks are called sequentially at the bottom of the file.

**Output helpers (defined first):**

| Function | Color | Prefix | Use |
|---|---|---|---|
| `print_pass()` | Green | `PASS:` | Check succeeded |
| `print_fail()` | Red | `FAILED:` | Check failed |
| `print_check()` | Yellow | `CHECK:` | Informational, no pass/fail verdict |

Color codes are OS-aware: macOS uses `echo "\033[..."` (no `-e`), Linux uses `echo -e "\e[..."`.

**Active checks (in execution order):**

1. `check_etcd_encryption` — etcd encryption type via `apiserver cluster`
2. `check_cluster_monitoring_config` — `cluster-monitoring-config` ConfigMap presence
3. `check_pods_running` — non-Running pods in `openshift-monitoring`
4. `check_node_readiness` — NotReady nodes cluster-wide
5. `check_mcp_updated` — MachineConfigPool updated status
6. `check_kubeletconfig_dynamic_resource` — `autoSizingReserved: true` in KubeletConfig
7. `check_openshift_cni` — CNI type (informational)
8. `check_openshift_networks` — cluster/service network CIDRs (informational)
9. `check_compliance_operator_installed` — CSV in `openshift-compliance`
10. `check_csi_driver_provider` — installed CSI drivers (informational)
11. `check_oauth_htpasswd` — htpasswd identity provider in OAuth
12. `check_alertmanager_configuration` — `alertmanager-main` secret presence
13. `check_router_pods` — router pod count in `openshift-ingress`
14. `check_node_taints` — tainted nodes (informational)
15. `check_router_certificate` — custom vs. self-signed IngressController cert
16. `list_all_ingresscontrollers` — lists all IngressControllers (informational)
17. `check_image_registry_deployed` — `image-registry` deployment in `openshift-image-registry`

**Disabled checks (commented out):**

- `check_pods_not_running_with_namespace` — all non-Running pods across all namespaces
- `check_node_resource_requests` — CPU/memory allocation per node

### healthcheck.sh

Gathers a full cluster diagnostic snapshot into `/var/tmp/pg-gatherer/out/`, then archives everything as `/var/tmp/pg-gatherer/<timestamp>-pg-collect.out.tar.gz`. Runs 16 sequential steps.

**Key environment variables:**
```bash
DST=/var/tmp/pg-gatherer/out   # Output directory for individual files
COLL=/var/tmp/pg-gatherer       # Parent directory / archive destination
```

**Steps summary:**

| Step | Topic | Notable actions |
|---|---|---|
| 1 | Install config | `oc extract cm/cluster-config-v1` |
| 2 | SSH key redaction | `sed -i 's/ssh-rsa.*/<redacted>/g'` on install-config |
| 3 | Overall cluster info | nodes, versions, kubelet, machines, MCPs, per-node `oc debug` (ip, routes, sysctl, netstat, DNS, chrony) |
| 4 | Routes | haproxy backend counts per router pod |
| 5 | Networking | CNI, egress, ingress, network policies, hostsubnet, netnamespace, Service Mesh |
| 6 | Operators | ClusterOperators, CSVs, subscriptions, OperatorGroups |
| 7 | API & Autoscaling | APIServices, resource quotas, HPA, endpoints |
| 8 | Auth/Authz | RBAC, ClusterRoleBindings, OAuth, users, groups |
| 9 | Storage & Logging | StorageClasses, PVs, PVCs, snapshots, CSI, ClusterLogging, LogForwarder |
| 10 | Image Registry & Monitoring | ImageRegistry config, Prometheus, Alertmanager (live API query with bearer token) |
| 11 | Application configs | Projects, ConfigMaps, builds, deployments, DeploymentConfigs, routes, services, templates, Tuned |
| 12 | ETCD | Member list, endpoint status/health via `etcdctl` inside etcd pods |
| 13 | Certificate expiry | All `kubernetes.io/tls` secrets — STATE (OK/EXPIRED), days remaining, expiry date |
| 14 | Additional | Compliance operator (scans, settings), SCCs, ServiceMonitors, Istio (gateways, virtualservices, destinationrules), PrometheusRules, Alertmanager configs, InstallPlans, kubelet configz, RBAC custom columns |
| 15 | Virtualization | VMIs, VMs, DataVolumes, DataImportCrons, StorageProfiles, NetworkAttachmentDefinitions |
| 16 | Archive | `tar -zcf` all output files |

---

## Code Conventions

### Naming

- **Functions:** `{verb}_{resource}` using snake_case — e.g., `check_etcd_encryption`, `list_all_ingresscontrollers`.
- **Local variables:** UPPERCASE within functions — e.g., `ENCRYPTION_CONFIG`, `NOT_READY_NODES`.
- **Global/export variables:** UPPERCASE — `DST`, `COLL`, `OSTYPE`.
- **Output files:** `<resource>.<format>` pattern — e.g., `nodes_wide.out`, `nodes.out.yaml`.

### Function structure in ocp-checklists.sh

Every check function follows this pattern:
```bash
# Function to <description>
check_<resource>() {
  local MY_VAR
  MY_VAR=$(oc get ...)

  if [[ condition ]]; then
    print_pass "<topic>"
  else
    print_fail "<topic>"
  fi
}
```

Informational checks (no verdict) use `print_check` and may omit the if/else.

### oc command patterns

```bash
# Boolean existence check
oc get <resource> -o yaml | grep -q "pattern"

# List parsing
oc get <resource> --no-headers | awk '{print $1}'

# JSONPath extraction
oc get <resource> -o jsonpath='{.spec.field}'

# Per-node debugging
for NODE in $(oc get node --no-headers | awk '{print $1}'); do
  oc debug node/$NODE -- chroot /host <command>
done

# Output to file (healthcheck.sh)
oc get <resource> -A -o yaml &>$DST/<resource>.out.yaml
```

### Output file naming (healthcheck.sh)

- Plain text listing: `<resource>.out`
- YAML dump: `<resource>.out.yaml`
- JSON: `<resource>.json`
- Per-pod files: `<description>_<podname>.out`

### OS portability

The `print_*` functions handle macOS vs. Linux echo differences. Any new colored output should follow the same pattern:
```bash
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "\033[0;32mPASS: $topic\033[0m"
else
  echo -e "\e[32mPASS: $topic\e[0m"
fi
```

---

## Adding a New Check to ocp-checklists.sh

1. Define a new function following the naming and structure conventions above.
2. Place the function definition in a logical location among existing functions (grouped by resource type).
3. Add a comment above the function explaining what it checks.
4. Call the function at the bottom of the file with a descriptive comment, maintaining the sequential execution order.
5. If the check is optional or experimental, comment it out with `#` and add a note explaining why.

Example skeleton:
```bash
# Function to check <what you are checking>
check_<resource>() {
  local RESULT
  RESULT=$(oc get <resource> ...)

  if [[ -n "$RESULT" ]]; then
    print_pass "<human-readable topic>"
  else
    print_fail "<human-readable topic>"
  fi
}

# ... at the bottom of the file:
# Call the function to check <resource>
check_<resource>
```

---

## Adding a New Gather Step to healthcheck.sh

1. Insert `oc get` commands in the relevant existing step, or create a new numbered step before step 16 (the archive step).
2. If creating a new step, update the step counter in all `echo "Step N/16"` labels throughout the file.
3. Always redirect output with `&>$DST/<filename>.out` (or `.out.yaml`).
4. Collect both plain and YAML formats when useful: one `oc get` without flags for the table view, one with `-o yaml` for full detail.
5. Deprecated resources (like `deploymentconfig`) should include a `# deprecated` comment but still be collected for compatibility.

---

## Disabled / Optional Code

Both scripts contain sections commented out with `#`. These are intentionally disabled, not dead code. Common reasons:
- Performance: commands that take a long time on large clusters (e.g., `check_node_resource_requests`).
- Noise: checks that produce too many false positives (e.g., `check_pods_not_running_with_namespace`).
- Optional features: Alertmanager secret decoding, thanos-ruler config (requires specific cluster configuration).

Do not remove commented-out code without understanding its intent.

---

## Testing

There is no automated test suite. All validation is manual against a live OCP cluster with `oc` authenticated. When modifying scripts:

- Test `ocp-checklists.sh` by running it and verifying PASS/FAIL/CHECK output makes sense for the cluster state.
- Test `healthcheck.sh` by running it and checking that the output archive contains the expected files and that no step errors cause missing data.
- For syntax checking without a cluster, use `bash -n <script>` to catch syntax errors.

---

## Git Workflow

- **Main branch:** `main`
- **Feature branches:** `claude/<description>` or descriptive names
- **Commit style:** `feat: <description>` (as seen in git history)
- **Remote:** configured via local proxy — use `git push -u origin <branch>` for new branches

Do not push directly to `main`. Work on feature branches and merge via pull requests.

---

## Key Gotchas

- `healthcheck.sh` begins with `reset` (clears the terminal) and `rm -rf $COLL` (deletes all prior output). Running it twice will overwrite previous results.
- The script does **not** handle `oc` authentication — the user must be logged in before running either script.
- `oc debug node/<node>` spawns a privileged debug pod per node. On large clusters, the per-node loops in step 3 of `healthcheck.sh` can take many minutes.
- Certificate expiry check (step 13) uses `openssl x509` and requires `base64` — standard on Linux/macOS.
- The Alertmanager API query (step 10) uses `oc create token` which requires token creation permissions in `openshift-monitoring`.
- `deploymentconfig` is explicitly noted as deprecated in the code but is still gathered for backwards compatibility.
