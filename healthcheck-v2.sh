#!/usr/bin/env bash
# healthcheck-v2.sh - read-only OpenShift cluster data collector
#
# Gathers cluster state into a tarball for offline analysis.
# Safe for production use:
#   - Every oc call is a read (get/describe/adm top/extract/exec with read-only commands).
#   - Sole mutation: a 10-minute bound service-account token used to query the
#     Alertmanager API. It self-expires and is never written to the output.
#   - One debug pod per node (not per command), sequential, skippable.
#
# Usage: ./healthcheck-v2.sh [--output-dir DIR] [--skip-node-debug]

set -u

# ---------- arguments ----------
COLL="/var/tmp/pg-gatherer"
SKIP_NODE_DEBUG=0

usage() {
  echo "Usage: $0 [--output-dir DIR] [--skip-node-debug]"
  echo "  --output-dir DIR    base output directory (default: /var/tmp/pg-gatherer)"
  echo "  --skip-node-debug   skip the per-node debug-pod collection step"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)      COLL="$2"; shift 2 ;;
    --skip-node-debug) SKIP_NODE_DEBUG=1; shift ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

DST="$COLL/out"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
START_TIME=$SECONDS

log()  { echo "[$(date +%H:%M:%S)] $*"; }
warn() { echo "[$(date +%H:%M:%S)] WARNING: $*" >&2; }
die()  { echo "[$(date +%H:%M:%S)] ERROR: $*" >&2; exit 1; }

# Portable "date string -> epoch" (GNU date on Linux, BSD date fallback)
to_epoch() {
  date -d "$1" +%s 2>/dev/null || date -j -f "%b %e %T %Y %Z" "$1" +%s 2>/dev/null
}

# ---------- preflight ----------
log "Preflight checks"
command -v oc >/dev/null 2>&1 || die "'oc' binary not found in PATH"
command -v curl >/dev/null 2>&1 || warn "'curl' not found - alerts collection will be skipped"

oc whoami >/dev/null 2>&1 || die "not logged in to a cluster (oc whoami failed)"
if ! oc auth can-i '*' '*' >/dev/null 2>&1; then
  warn "current user is not cluster-admin; some collections may be incomplete"
fi

# Recreate output dir. Only ever remove the 'out' subdirectory we own.
if [[ -d "$DST" ]]; then
  case "$DST" in
    */out) rm -rf "$DST" ;;
    *) die "refusing to remove unexpected output path: $DST" ;;
  esac
fi
mkdir -p "$DST" || die "cannot create output directory $DST"

AVAIL_MB=$(df -Pm "$COLL" | awk 'NR==2 {print $4}')
if [[ -n "${AVAIL_MB:-}" && "$AVAIL_MB" -lt 1024 ]]; then
  warn "less than 1GB free on $COLL (${AVAIL_MB}MB) - collection may fail"
fi

# ---------- helpers ----------
# run <output-file> <command...>  : run command, capture stdout+stderr to file
run() {
  local out="$1"; shift
  "$@" >"$DST/$out" 2>&1
}

# collect <file-prefix> <oc-get-args...> : table + yaml pair
collect() {
  local prefix="$1"; shift
  run "$prefix.out" oc get "$@"
  run "$prefix.out.yaml" oc get "$@" -o yaml
}

# Capability snapshot: skip queries for CRDs that are not installed
API_RES_FILE="$DST/api-resources.out"
oc api-resources >"$API_RES_FILE" 2>&1
has_resource() { grep -qwE "$1" "$API_RES_FILE"; }

NETWORK_TYPE=$(oc get network cluster -o jsonpath='{.status.networkType}' 2>/dev/null)
log "Cluster network type: ${NETWORK_TYPE:-unknown}"

echo "starting gathering files ...this may take some time"
log "Output directory: $DST"
echo "#####################"
echo ""

# ---------- Step 1: install config ----------
log "Step 1/16 -- Retrieving install config"
oc -n kube-system extract cm/cluster-config-v1 --to="$DST/" >/dev/null 2>&1

log "Step 2/16 -- Redacting sensitive data from install-config"
if [[ -f "$DST/install-config" ]]; then
  sed -E \
    -e 's#(ssh-(rsa|ed25519|dss)|ecdsa-sha2-[a-z0-9-]+)[[:space:]]+[A-Za-z0-9+/=]+#<redacted-ssh-key>#g' \
    -e 's#(pullSecret:).*#\1 <redacted>#' \
    -e 's#([Pp]assword:).*#\1 <redacted>#' \
    "$DST/install-config" >"$DST/install-config.tmp" && mv "$DST/install-config.tmp" "$DST/install-config"
fi

# ---------- Step 3: cluster overview ----------
log "Step 3/16 -- Gathering overall cluster information (nodes, versions, machines, etc.)"
run oc-version.out oc version
run events.out oc get events -A --sort-by=.lastTimestamp
run all.out oc get all -A -o wide
run status-suggest.out oc status -A --suggest
run imagecontentsourcepolicy.out.yaml oc get imagecontentsourcepolicy -o yaml
if has_resource "machine.openshift.io"; then
  collect machine machine -A
  collect machineautoscaler machineautoscaler -A
  collect machineset machineset -A
fi
has_resource machineconfigpools && collect machineconfigpool machineconfigpool
has_resource machineconfigs && collect machineconfigs machineconfigs
run desc_nodes.out oc describe nodes
run nodes_labels.out oc get nodes --show-labels
run nodes_wide.out oc get nodes -o wide
run nodes_wide_labels.out oc get nodes -o wide --show-labels
run nodes.out.yaml oc get nodes -o yaml
collect imagetag imagetag -A
run top_nodes.out oc adm top nodes
has_resource kubeletconfigs && collect kubeletconfig kubeletconfig
run tuned_profile.out.yaml oc get profile -A -o yaml
run infrastructure.out.yaml oc get infrastructure cluster -o yaml
collect clusterversion clusterversions.config.openshift.io
run featuregate.out.yaml oc get featuregate -o yaml
run statefulset.out.yaml oc get statefulset -A -o yaml
run scheduler.out.yaml oc get scheduler cluster -o yaml
run secrets.out oc get secrets -A
collect crd customresourcedefinitions

# ---------- Step 4: per-node data (one debug pod per node) ----------
if [[ "$SKIP_NODE_DEBUG" -eq 1 ]]; then
  log "Step 4/16 -- Skipping node debug collection (--skip-node-debug)"
else
  log "Step 4/16 -- Gathering per-node data (one debug pod per node, sequential)"
  NODE_SCRIPT='echo "##SEC ip_a";       ip a 2>&1;
               echo "##SEC ip_route";   ip route 2>&1;
               echo "##SEC ip_link";    ip -d link 2>&1;
               echo "##SEC netstat_s";  netstat -s 2>&1 || ss -s 2>&1;
               echo "##SEC sysctl";     sysctl -a 2>/dev/null;
               echo "##SEC resolv";     cat /etc/resolv.conf 2>&1;
               echo "##SEC times";      chronyc -m sources tracking 2>&1'
  NODE_TMP="$DST/.node-raw.tmp"
  for NODE in $(oc get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    log "  node: $NODE"
    oc debug "node/$NODE" -q --request-timeout=60s -- chroot /host /bin/bash -c "$NODE_SCRIPT" >"$NODE_TMP" 2>&1
    awk -v node="$NODE" -v dst="$DST" '
      BEGIN {
        map["ip_a"]      = "node_ips.out"
        map["ip_route"]  = "node_ip_route.out"
        map["ip_link"]   = "node_ip_link.out"
        map["netstat_s"] = "node_netstat_s.out"
        map["sysctl"]    = "node_sysctl.out"
        map["resolv"]    = "node_resolv.out"
        map["times"]     = "node_times.out"
      }
      /^##SEC / { f = dst "/" map[$2]; print node >> f; next }
      f { print >> f }
    ' "$NODE_TMP"
    for F in node_ips node_ip_route node_ip_link node_netstat_s node_sysctl node_resolv node_times; do
      echo "=====" >>"$DST/$F.out"
    done
  done
  rm -f "$NODE_TMP"
fi

# ---------- Step 5: routes per router ----------
log "Step 5/16 -- Retrieving route counts per router pod"
{
  for PROJ in $(oc get pod -A 2>/dev/null | awk '/router/ {print $1}' | sort -u); do
    for POD in $(oc get pod -n "$PROJ" --no-headers 2>/dev/null | awk '/router/ {print $1}'); do
      printf '%s : %s : ' "$PROJ" "$POD"
      oc -n "$PROJ" --request-timeout=30s exec "$POD" -- grep -c -e ^backend haproxy.config 2>/dev/null || echo "n/a"
    done
  done
} >"$DST/routes_per_router.out" 2>&1

# ---------- Step 6: networking ----------
log "Step 6/16 -- Gathering networking information"
if [[ "$NETWORK_TYPE" == "OpenShiftSDN" ]]; then
  collect clusternetworks clusternetworks.network.openshift.io
  collect egressnetworkpolicy egressnetworkpolicy -A
  collect hostsubnet hostsubnet
  run netnamespace.out oc get netnamespace
else
  log "  (skipping SDN-only resources: network type is ${NETWORK_TYPE:-unknown})"
fi
collect ingresses.networking.k8s.io ingresses.networking.k8s.io -A
collect network network
run network-operator.out.yaml oc get network.operator cluster -o yaml
collect networkpolicies networkpolicies -A
collect egressip egressip
collect proxy proxy
collect ingresscontrollers.operator ingresscontrollers.operator.openshift.io -A
collect ingresses.config ingresses.config.openshift.io
if has_resource servicemeshcontrolplanes; then
  collect serviceMeshMember servicemeshmembers -A
  collect serviceMeshMemberRoll servicemeshmemberrolls -A
  collect serviceMeshControlPlane servicemeshcontrolplanes -A
fi

# ---------- Step 7: operators ----------
log "Step 7/16 -- Gathering operator information"
run co-describe.out oc describe clusteroperators
collect clusteroperators clusteroperators
if has_resource clusterresourceoverrides; then
  run clusterresourceoverride.out oc get clusterresourceoverride cluster -o yaml
fi
collect clusterserviceversions clusterserviceversions.operators.coreos.com -A
collect subscriptions subscriptions.operators.coreos.com -A
run operatorgroups.out oc get operatorgroups.operators.coreos.com -A
run operatorgroups.out.yaml oc get operatorgroups.operators.coreos.com -A -o yaml
collect installplan installplan -A

# ---------- Step 8: cluster resources, API & autoscaling ----------
log "Step 8/16 -- Gathering cluster resource, API & autoscaling information"
run apiservices.out oc get apiservices.apiregistration.k8s.io
run api-versions.out oc api-versions
run api-requests-count.out oc get apirequestcount
collect clusterresourcequotas clusterresourcequotas.quota.openshift.io -A
run appliedclusterresourcequotas.out oc get appliedclusterresourcequotas.quota.openshift.io -A
has_resource clusterautoscalers && collect clusterautoscalers clusterautoscalers.autoscaling.openshift.io
collect hpa horizontalpodautoscalers -A
run ep.out oc get endpoints -A -o wide
run ep.out.yaml oc get endpoints -A -o yaml

# ---------- Step 9: authentication & authorization ----------
log "Step 9/16 -- Gathering authentication and authorization information"
run authentications.out.yaml oc get authentications.config.openshift.io -o yaml
collect rolebinding rolebinding -A
run rolebinding-custom.out oc get rolebinding -A -o custom-columns=NAME:.metadata.name,KIND:.subjects[*].kind,SUBJECTNAME:.subjects[*].name,ROLEKIND:.roleRef.kind,ROLENAME:.roleRef.name
collect clusterrolebindings.rbac clusterrolebindings.rbac.authorization.k8s.io
collect clusterroles.rbac clusterroles.rbac.authorization.k8s.io
run oauth.out.yaml oc get oauth -o yaml
collect users users
collect group group
collect scc scc

# ---------- Step 10: storage & logging ----------
log "Step 10/16 -- Gathering storage & logging information"
collect sc storageclass
collect pv persistentvolume
collect pvc persistentvolumeclaim -A
collect volumeSnapshot volumesnapshot -A
collect csinodes csinodes
run csisnapshotcontrollers.operator.out oc get csisnapshotcontrollers.operator.openshift.io -o yaml
collect csidrivers csidrivers
if has_resource clusterloggings; then
  collect clusterlogging clusterlogging -A
  run pods_logging.out.yaml oc get pods -n openshift-logging -o yaml
fi
if has_resource clusterlogforwarders; then
  collect logforwarding clusterlogforwarder -A
fi

# ---------- Step 11: image registry & monitoring ----------
log "Step 11/16 -- Gathering image registry & monitoring information"
run configs.imageregistry.operator.out.yaml oc get configs.imageregistry.operator.openshift.io cluster -o yaml
run imageprunner.out.yaml oc get imagepruner -o yaml
run image-config.out.yaml oc get image.config cluster -o yaml
run cluster-monitoring_cm.out.yaml oc -n openshift-monitoring get configmap cluster-monitoring-config -o yaml
run user-workload-monitoring_cm.out.yaml oc -n openshift-user-workload-monitoring get configmap user-workload-monitoring-config -o yaml
collect prometheus prometheus -A
collect prometheusrule prometheusrule -A
collect alertmanager-config alertmanagerconfig -A
collect servicemonitor servicemonitor -A

# Active alerts via Alertmanager API.
# Only mutating call in this script: a 10-minute bound SA token (self-expiring).
# The token is passed via a header file so it never appears in the process list
# or in the captured error output.
if command -v curl >/dev/null 2>&1; then
  ALERTMANAGER_ROUTE=$(oc -n openshift-monitoring get route alertmanager-main -o jsonpath='{.spec.host}' 2>/dev/null)
  if [[ -n "$ALERTMANAGER_ROUTE" ]]; then
    HDR_FILE=$(mktemp)
    chmod 600 "$HDR_FILE"
    if oc -n openshift-monitoring create token prometheus-k8s --duration=10m 2>"$DST/alerts_err.out" \
        | awk '{print "Authorization: Bearer " $0}' >"$HDR_FILE" && [[ -s "$HDR_FILE" ]]; then
      curl -ksS -H @"$HDR_FILE" "https://$ALERTMANAGER_ROUTE/api/v2/alerts" \
        -o "$DST/alerts.json" 2>>"$DST/alerts_err.out"
    fi
    rm -f "$HDR_FILE"
  else
    log "  (no alertmanager-main route found; skipping alerts collection)"
  fi
fi

# ---------- Step 12: application configs ----------
log "Step 12/16 -- Gathering application configs (projects, workloads, routes, services, etc.)"
collect projects projects
run configmaps.out oc get configmaps -A
collect configmaps.openshift-config configmaps -n openshift-config
run builds.out oc get builds -A
collect deployment deployment -A
# deploymentconfig is deprecated but still collected where present
if has_resource deploymentconfigs; then
  collect deploymentconfig deploymentconfig -A
fi
run images.out oc get images
run is.out oc get imagestreams -A
collect limits limits -A
collect pdb poddisruptionbudget -A
run prometheus-k8s-0.out.yaml oc get pod -n openshift-monitoring prometheus-k8s-0 -o yaml
run prometheus-k8s-1.out.yaml oc get pod -n openshift-monitoring prometheus-k8s-1 -o yaml
run pods_wide.out oc get pods -A -o wide
run pods_default.out.yaml oc get pods -n default -o yaml
collect quota quota -A
run route.out oc get route -A
run route_wide.out oc get route -A -o wide
run route.out.yaml oc get route -A -o yaml
collect svc service -A
run templates.out oc get templates -A
run top_pods.out oc adm top pods -A
collect tuned tuned -A
run validatingwebhookconfigurations.out oc get validatingwebhookconfigurations

# ---------- Step 13: etcd ----------
log "Step 13/16 -- Examining etcd (read-only etcdctl queries)"
run etcd.out.yaml oc get etcd -o yaml
ETCD_PODS=$(oc get pod -n openshift-etcd 2>/dev/null | awk '/^etcd-/ {print $1}' | grep -Ev "quorum|guard")
if [[ -z "$ETCD_PODS" ]]; then
  log "  (no etcd pods found; skipping etcdctl queries)"
fi
for POD in $ETCD_PODS; do
  OUT="etcd_status_health_$POD.out"
  echo "$POD" >"$DST/$OUT"
  for CMD in "etcdctl member list -w table" "etcdctl endpoint status -w table" "etcdctl endpoint health -w table"; do
    oc -n openshift-etcd --request-timeout=30s exec -c etcd "$POD" -- /bin/bash -c "$CMD" >>"$DST/$OUT" 2>&1
    echo "---" >>"$DST/$OUT"
  done
done

# ---------- Step 14: certificate expiry ----------
log "Step 14/16 -- Checking TLS certificate expiry"
FORMAT="%-8s%-8s%-60s%-26s%-60s\n"
printf "$FORMAT" STATE DAYS NAME EXPIRY NAMESPACE | tee "$DST/certificate_expiry.out"
printf "$FORMAT" ----- ---- ---- ------ --------- | tee -a "$DST/certificate_expiry.out"
oc get secrets -A -o go-template='{{range .items}}{{if eq .type "kubernetes.io/tls"}}{{.metadata.namespace}}{{" "}}{{.metadata.name}}{{" "}}{{index .data "tls.crt"}}{{"\n"}}{{end}}{{end}}' 2>/dev/null \
| while read -r NAMESPACE NAME CERT; do
    CERTDATE=$(echo "$CERT" | base64 -d 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    [[ -z "$CERTDATE" ]] && continue
    EPOCHCERT=$(to_epoch "$CERTDATE")
    [[ -z "$EPOCHCERT" ]] && continue
    NOW=$(date +%s)
    if ((EPOCHCERT > NOW)); then
      STATE="OK"; DAYS=$(((EPOCHCERT - NOW) / 86400))
    else
      STATE="EXPIRED"; DAYS=$(((NOW - EPOCHCERT) / 86400))
    fi
    printf "$FORMAT" "$STATE" "$DAYS" "$NAME" "$CERTDATE" "$NAMESPACE" | tee -a "$DST/certificate_expiry.out"
  done

# ---------- Step 15: additional (compliance, nmstate, mesh, kubelet) ----------
log "Step 15/16 -- Gathering additional information"
if has_resource nodenetworkconfigurationpolicies; then
  collect nncp nncp -A
fi
if has_resource nodenetworkstates; then
  collect nns nns -A
fi
if has_resource compliancescans; then
  run ccr.out oc get compliancecheckresults -A
  run rems.out oc get complianceremediations -A
  collect compliance-scan compliancescans -A
  collect compliance-scansetting scansettings -A
  collect compliance-scansettingbinding scansettingbindings -A
fi
if has_resource virtualservices; then
  collect gateway gateway -A
  collect virtualservice virtualservice -A
  collect destinationrule destinationrule -A
fi
for NODE_NAME in $(oc get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  oc get --raw "/api/v1/nodes/$NODE_NAME/proxy/configz"
  echo ""
done >"$DST/node-kubeletconfig.out.json" 2>&1

# ---------- Step 16: virtualization ----------
if has_resource virtualmachineinstances; then
  log "Step 16/16 -- Gathering virtualization information"
  collect vmi vmi -A
  collect vmim vmim -A
  collect vm vm -A
  collect dv dv -A
  collect dataimportcron dataimportcron -A
  collect storageprofile storageprofile -A
  collect nad net-attach-def -A
else
  log "Step 16/16 -- Virtualization not installed; skipping"
fi

# ---------- redact pass ----------
log "Redacting known credential material before packaging"
# machineconfigs embed node file contents; blank the payload of registry
# credential files (pull secret / kubelet config.json)
if [[ -f "$DST/machineconfigs.out.yaml" ]]; then
  awk '
    { lines[NR] = $0 }
    /source: data:/ { src[NR] = 1 }
    /path:.*(config\.json|pull-secret)/ {
      for (i = NR; i > NR - 10 && i > 0; i--)
        if (src[i]) { sub(/data:.*/, "data:,<redacted>", lines[i]); break }
    }
    END { for (i = 1; i <= NR; i++) print lines[i] }
  ' "$DST/machineconfigs.out.yaml" >"$DST/machineconfigs.out.yaml.tmp" \
    && mv "$DST/machineconfigs.out.yaml.tmp" "$DST/machineconfigs.out.yaml"
fi

# Sanity sweep: report (do not fail) any file that still looks like it holds secrets
SWEEP_HITS=$(grep -rlIE 'BEGIN [A-Z ]*PRIVATE KEY' "$DST" 2>/dev/null)
if [[ -n "$SWEEP_HITS" ]]; then
  warn "possible private key material found in output - review before sharing:"
  echo "$SWEEP_HITS" >&2
fi

# ---------- package & summary ----------
TARBALL="$COLL/$TIMESTAMP-pg-collect.tar.gz"
log "Packaging results --> $TARBALL"
tar -C "$COLL" -zcf "$TARBALL" out

ELAPSED=$((SECONDS - START_TIME))
FILE_COUNT=$(find "$DST" -type f | wc -l | tr -d ' ')
EMPTY_FILES=$(find "$DST" -type f -size 0 | sort)
ERROR_FILES=$(grep -rlIE "Error from server|error: the server|doesn't have a resource type" "$DST" 2>/dev/null | sort)

echo ""
echo "#####################"
echo "Collection complete at $(date)"
echo "  elapsed:   ${ELAPSED}s"
echo "  files:     $FILE_COUNT in $DST"
echo "  tarball:   $TARBALL"
if [[ -n "$EMPTY_FILES" ]]; then
  echo "  empty files (no data returned):"
  echo "$EMPTY_FILES" | sed 's/^/    /'
fi
if [[ -n "$ERROR_FILES" ]]; then
  echo "  files containing API errors (check permissions / availability):"
  echo "$ERROR_FILES" | sed 's/^/    /'
fi
echo "#####################"
