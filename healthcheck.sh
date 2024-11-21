#!/bin/bash
reset
echo "starting gathering files ...this may take some time"
export DST=/var/tmp/pg-gatherer/out
export COLL=/var/tmp/pg-gatherer
time=$(date +"%Y-%m-%d_%H-%M-%S")

rm -rf $COLL
mkdir -p $DST
### sampling#####
echo "Begining commands"
echo "#####################"
echo ""

echo "Step 1/16  -- Retrieving install config"
oc -n kube-system extract cm/cluster-config-v1 --to=/$DST/
echo "Done"
echo ""

echo "Step 2/16 --Redacting SSH key information..."
sed -i 's/ssh-rsa.*/<redacted>/g' $DST/install-config

echo "Step 3/16 -- Gathering Overall Cluster Information (nodes, verion numbers, kubelet config etc)"
echo "        -- This may take a while..."
oc version  &>$DST/oc-version.out
oc cluster-info dump &>$DST/cluster-info-dump.out
oc get all -A -o wide  &>$DST/all.out
oc get imagecontentsourcepolicy -A -o yaml &>$DST/imagecontentsourcepolicy.out.yaml
oc get machine -A  &>$DST/machine.out
oc get machine -A -o yaml  &>$DST/machine.out.yaml
oc get machineautoscaler -A  &>$DST/machineautoscaler.out
oc get machineautoscaler -A -o yaml  &>$DST/machineautoscaler.out.yaml
oc get machineconfigpool -A  &>$DST/machineconfigpool.out
oc get machineconfigpool -A -o yaml  &>$DST/machineconfigpool.out.yaml
oc get machineconfigs  &>$DST/machineconfigs.out
oc get machineconfigs -o yaml  &>$DST/machineconfigs.out.yaml
oc get machineset -A  &>$DST/machineset.out
oc get machineset -A -o yaml  &>$DST/machineset.out.yaml
oc describe nodes  &>$DST/desc_nodes.out
oc get nodes --show-labels  &>$DST/nodes_labels.out
oc get nodes -o wide  &>$DST/nodes_wide.out
oc get nodes -o wide --show-labels  &>$DST/nodes_wide_labels.out
oc get nodes -o yaml  &>$DST/nodes.out.yaml
oc get imagetag -A &>$DST/imagetag.out
oc get imagetag -A -oyaml &>$DST/imagetag.out.yaml
oc adm top nodes  &>$DST/top_nodes.out
for NODE in `oc get node --no-headers|awk '{print$1}'`; do echo $NODE; oc debug node/$NODE -- chroot /host ip a; echo "=====";done  &>$DST/node_ips.out
for NODE in `oc get node --no-headers|awk '{print$1}'`; do echo $NODE; oc debug node/$NODE -- chroot /host ip route; echo "=====";done  &>$DST/node_ip_route.out
for NODE in `oc get node --no-headers|awk '{print$1}'`; do echo $NODE; oc debug node/$NODE -- chroot /host sysctl -a; echo "=====";done  &>$DST/node_sysctl.out
for NODE in `oc get node --no-headers|awk '{print$1}'`; do echo $NODE; oc debug node/$NODE -- chroot /host ip -d link ; echo "=====";done  &>$DST/node_ip_link.out
for NODE in `oc get node --no-headers|awk '{print$1}'`; do echo $NODE; oc debug node/$NODE -- chroot /host netstat -s ; echo "=====";done  &>$DST/node_netstat_s.out
for NODE in `oc get node --no-headers|awk '{print$1}'`; do echo $NODE; oc debug node/$NODE -- chroot /host cat /etc/resolv.conf; echo "=====";done  &>$DST/node_resolv.out
for NODE in `oc get node --no-headers|awk '{print$1}'`; do echo $NODE; oc debug node/$NODE -- chroot /host /usr/bin/chronyc -m sources tracking; echo "=====";done  &>$DST/node_times.out
oc get kubeletconfig -A  &>$DST/kubeletconfig.out
oc get kubeletconfig -A -o yaml   &>$DST/kubeletconfig.out.yaml
oc get config cluster -A  &>$DST/config.out
oc get config cluster -A -o yaml  &>$DST/config.out.yaml
oc get clusterversions.config.openshift.io  &>$DST/clusterversion.out
oc get clusterversions.config.openshift.io -o yaml  &>$DST/clusterversion.out.yaml
oc get featuregate -o yaml  &>$DST/featuregate.out.yaml
oc get statefulset -A -o yaml  &>$DST/statefulset.out.yaml
oc get scheduler cluster -o yaml  &>$DST/scheduler.out.yaml
oc get secrets -A  &>$DST/secrets.out
oc get customresourcedefinitions &>$DST/crd.out
oc get customresourcedefinitions -o yaml  &>$DST/crd.out.yaml


echo "Step 4/16 -- Retrieving routes..."
for PROJ in `oc get pod -A |awk '/router/ {print $1}'|sort -u`; do for POD in `oc get pod -n $PROJ --no-headers|awk '{print$1}'`; do echo -n "$PROJ : $POD :"  ;oc -n $PROJ exec $POD -- grep -c -e ^backend haproxy.config;done;done  &> $DST/routes_per_router.out

echo "Step 5/16 -- Gathering Networking Information"
oc get clusternetworks.network.openshift.io -A  &>$DST/clusternetworks.out
oc get clusternetworks.network.openshift.io -A -o yaml  &>$DST/clusternetworks.out.yaml
oc get egressnetworkpolicy -A  &>$DST/egressnetworkpolicy.out
oc get egressnetworkpolicy -A -o yaml &>$DST/egressnetworkpolicy.out.yaml
oc get ingresses.networking.k8s.io -A  &>$DST/ingresses.networking.k8s.io.out
oc get ingresses.networking.k8s.io -A -o yaml  &>$DST/ingresses.networking.k8s.io.out.yaml
oc get network  &>$DST/network.out
oc get network -o yaml  &>$DST/network.out.yaml
oc get network.operator cluster -o yaml &>$DST/network-operator.out.yaml
oc get networkpolicies -A   &>$DST/networkpolicies.out
oc get networkpolicies -A -o yaml  &>$DST/networkpolicies.out.yaml
oc get hostsubnet   &>$DST/hostsubnet.out
oc get hostsubnet -o yaml &>$DST/hostsubnet.out.yaml
oc get egressip &> $DST/egressip.out
oc get egressip -A -o yaml &>$DST/egressip.out.yaml
oc get proxy  &>$DST/proxy.out
oc get proxy -o yaml  &>$DST/proxy.out.yaml
oc get ingresscontrollers.operator.openshift.io -A  &>$DST/ingresscontrollers.operator.out
oc get ingresscontrollers.operator.openshift.io -A -o yaml  &>$DST/ingresscontrollers.operator.out.yaml
oc get ingresses.config.openshift.io -A  &>$DST/ingresses.config.out
oc get ingresses.config.openshift.io -A -o yaml  &>$DST/ingresses.config.out.yaml
oc get serviceMeshMember -A &>$DST/serviceMeshMember.out
oc get serviceMeshMember -A -o yaml  &>$DST/serviceMeshMember.out.yaml
oc get serviceMeshMemberRoll -A  &>$DST/serviceMeshMemberRoll.out
oc get serviceMeshMemberRoll -A -o yaml  &>$DST/serviceMeshMemberRoll.out.yaml
oc get serviceMeshControlPlane -A  &>$DST/serviceMeshControlPlane.out
oc get serviceMeshControlPlane -A -o yaml  &>$DST/serviceMeshControlPlane.out.yaml



echo "Step 6/16 -- Gathering Operator Information"
oc describe clusteroperators  &>$DST/co-describe.out
oc get clusteroperators  &>$DST/clusteroperators.out
oc get clusteroperators -o yaml   &>$DST/clusteroperators.out.yaml
oc get clusterresourceoverride cluster -n clusterresourceoverride-operator -o yaml  &>$DST/clusterresourceoverride.out
oc get clusterserviceversions.operators.coreos.com -A  &>$DST/clusterserviceversions.out
oc get clusterserviceversions.operators.coreos.com -A -o yaml  &>$DST/clusterserviceversions.out.yaml
oc get subscriptions -A  &>$DST/subscriptions.out
oc get subscriptions -A -o yaml  &>$DST/subscriptions.out.yaml
oc get operatorgroups.operators.coreos.com -A  &>$DST/operatorgroups.out
oc get operatorsources.operators.coreos.com  -A  &>$DST/operatorgroups.out.yaml


echo "Step 7/16 -- Gathering Cluster Resource infomration, API & Autoscaling info"
oc get apiservices.apiregistration.k8s.io  &>$DST/apiservices.out
oc get authentications.config.openshift.io -o yaml &>$DST/authentications.out.yaml
oc get clusterresourcequotas.quota.openshift.io -A  &>$DST/clusterresourcequotas.out
oc get clusterresourcequotas.quota.openshift.io -A -o yaml  &>$DST/clusterresourcequotas.out.yaml
oc get appliedclusterresourcequotas.quota.openshift.io -A &>$DST/appliedclusterresourcequotas.out
oc get clusterautoscalers.autoscaling.openshift.io -A  &>$DST/clusterautoscalers.out
oc get clusterautoscalers.autoscaling.openshift.io -A -o yaml  &>$DST/clusterautoscalers.out.yaml
oc get horizontalpodautoscalers -A  &>$DST/hpa.out
oc get horizontalpodautoscalers -A -o yaml  &>$DST/hpa.out.yaml
oc get endpoints -A -o wide  &>$DST/ep.out
oc get endpoints -A -o yaml  &>$DST/ep.out.yaml


echo "Step 8/16 -- Gathering Authentication and Authorization information"
oc get authentications.config.openshift.io -o yaml &>$DST/authentications.out.yaml
oc get rolebinding -A &>$DST/rolebinding.out
oc get rolebinding -A -o yaml &>$DST/rolebinding.out.yaml
oc get clusterrolebindings.authorization.openshift.io -A  &>$DST/clusterrolebindings.out
oc get clusterrolebindings.authorization.openshift.io -A -o yaml  &>$DST/clusterrolebindings.out.yaml
oc get clusterrolebindings.rbac.authorization.k8s.io -A  &>$DST/clusterrolebindings.rbac.out
oc get clusterrolebindings.rbac.authorization.k8s.io -A -o yaml  &>$DST/clusterrolebindings.rbac.out.yaml
oc get clusterroles.authorization.openshift.io -A  &>$DST/clusterroles.out
oc get clusterroles.authorization.openshift.io -A -o yaml  &>$DST/clusterroles.out.yaml
oc get clusterroles.rbac.authorization.k8s.io -A  &>$DST/clusterroles.rbac.out
oc get clusterroles.rbac.authorization.k8s.io -A -o yaml  &>$DST/clusterroles.rbac.yaml
oc get oauth -o yaml   &>$DST/oauth.out
oc get users  &>$DST/users.out
oc get users -o yaml  &>$DST/users.out.yaml
oc get group  &>$DST/group.out
oc get group -o yaml  &>$DST/group.out.yaml


echo "Step 9/16 -- Gathering Storage & Logging Information"
oc get storageclass  &>$DST/sc.out
oc get storageclass -o yaml  &>$DST/sc.out.yaml
oc get clusterlogging -A  &>$DST/clusterlogging.out
oc get clusterlogging -A -o yaml  &>$DST/clusterlogging.out.yaml
oc get pods -n openshift-logging -o yaml  &>$DST/pods_logging.out.yaml
oc get persistentvolume  &>$DST/pv.out
oc get persistentvolume -o yaml  &>$DST/pv.out.yaml
oc get persistentvolumeclaim -A  &>$DST/pvc.out
oc get persistentvolumeclaim -A -o yaml  &>$DST/pvc.out.yaml
oc get volumeSnapshot -A &>$DST/volumeSnapshot.out
oc get volumeSnapshot -A -o yaml   &>$DST/volumeSnapshot.out.yaml
oc get csinodes  -A  &>$DST/csinodes.out
oc get csinodes  -A -o yaml  &>$DST/csinodes.out.yaml
oc get csisnapshotcontrollers.operator.openshift.io -A -o yaml &>$DST/csisnapshotcontrollers.operator.out
oc get csidrivers   &>$DST/csidrivers.out
oc get csidrivers -o yaml  &>$DST/csidrivers.out.yaml
oc get clusterlogforwarder -A -o yaml   &>$DST/logforwarding.out.yaml
oc get clusterlogforwarder -A &>$DST/logforwarding.out

echo "Step 10/16 -- Gathering Image Registry & Monitoring Information"
oc get configs.imageregistry.operator.openshift.io cluster -o yaml  &>$DST/configs.imageregistry.operator.out.yaml
oc get imagepruner -o yaml &>$DST/imageprunner.out.yaml
oc -n openshift-monitoring get configmap cluster-monitoring-config -o yaml &>$DST/cluster-monitoring_cm.out.yaml
oc -n openshift-user-workload-monitoring get configmap user-workload-monitoring-config -o yaml &>$DST/user-workload-monitoring_cm.out.yaml
oc get prometheus -A &> $DST/prometheus.out
oc get prometheus -A -o yaml &> $DST/prometheus.out.yaml
ALERTMANAGER_ROUTE=`oc -n openshift-monitoring get routes | grep alertmanager |awk '{print $2}'`
curl -k -H "Authorization: Bearer $(oc -n openshift-monitoring create token prometheus-k8s)" https://$ALERTMANAGER_ROUTE/api/v1/alerts >$DST/alerts.json 2>$DST/alerts_err.json


echo "Step 11/16 -- Gathering Application Specific Configs (images streams, routes, services, configmaps etc)"
oc get projects  &>$DST/projects.out
oc get projects -o yaml   &>$DST/projects.out.yaml
oc get configmaps -A  &>$DST/configmaps.out
oc get configmaps -n openshift-config   &>$DST/configmaps.logging.out
oc get configmaps -n openshift-config -o yaml  &>$DST/configmaps.logging.out.yaml
oc get builds -A  &>$DST/builds.out
oc get deployment -A  &>$DST/deployment.out
oc get deployment -A -o yaml  &>$DST/deployment.out.yaml
oc get images -A  &>$DST/images.out
oc get imagestreams -A  &>$DST/is.out
oc get limits -A  &>$DST/limits.out
oc get limits -A -o yaml  &>$DST/limits.out.yaml
oc get poddisruptionbudget -A  &>$DST/pdb.out
oc get poddisruptionbudget -A -o yaml  &>$DST/pdb.out.yaml
oc get pod -n openshift-monitoring prometheus-k8s-0 -o yaml  &>$DST/prometheus-k8s-0.out.yaml
oc get pod -n openshift-monitoring prometheus-k8s-1 -o yaml  &>$DST/prometheus-k8s-1.out.yaml
oc get pods -A -o wide  &>$DST/pods_wide.out
oc get pods -n default -o yaml  &>$DST/pods_default.out.yaml
oc get quota -A  &>$DST/quota.out
oc get quota -A -o yaml  &>$DST/quota.out.yaml
oc get route -A  &>$DST/route.out
oc get route -A -o wide  &>$DST/route_wide.out
oc get route -A -o yaml  &>$DST/route.out.yaml
oc get service -A  &>$DST/svc.out
oc get service -A -o yaml  &>$DST/svc.out.yaml
oc get templates -A  &>$DST/templates.out
oc adm top pods -A  &>$DST/top_pods.out
oc get tuned -A  &>$DST/tuned.out
oc get tuned -A -o yaml  &>$DST/tuned.out.yaml
oc get validatingwebhookconfigurations -A  &>$DST/validatingwebhookconfigurations.out


echo "Step 12/16 -- Starting ETCD Examination"
oc get etcd -o yaml   &>$DST/etcd.out.yaml
for POD in `oc get pod -n openshift-etcd |awk '/etcd-/ {print $1}'|egrep -v "quorum|guard"`
do
echo $POD etcd_status_health_$POD.out >> $DST/etcd_status_health_$POD.out
oc -n openshift-etcd exec -c etcd $POD -- /bin/bash -c "etcdctl member list -w table" >> $DST/etcd_status_health_$POD.out
echo "---" >> $DST/etcd_status_health_$POD.out
oc -n openshift-etcd exec -c etcd $POD -- /bin/bash -c "etcdctl endpoint status -w table" >> $DST/etcd_status_health_$POD.out
echo "---" >> $DST/etcd_status_health_$POD.out
oc -n openshift-etcd exec -c etcd $POD -- /bin/bash -c "etcdctl endpoint health -w table" >> $DST/etcd_status_health_$POD.out
echo "---"  >> $DST/etcd_status_health_$POD.out
done



echo "Step 13/16 -- Starting certificates verification"
format="%-8s%-8s%-60s%-26s%-60s\n"
printf "$format" STATE DAYS NAME EXPIRY NAMESPACE | tee -a $DST/certificate_expiry.out
printf "$format" ----- ---- ---- ------ --------- | tee -a $DST/certificate_expiry.out

oc get secrets -A -o go-template='{{range .items}}{{if eq .type "kubernetes.io/tls"}}{{.metadata.namespace}}{{" "}}{{.metadata.name}}{{" "}}{{index .data "tls.crt"}}{{"\n"}}{{end}}{{end}}' | while read namespace name cert
do
  certdate=`echo $cert | base64 -d | openssl x509 -noout -enddate|cut -d= -f2`
  epochcertdate=$(date -d "$certdate" +"%s")
  currentdate=$(date +%s)
  if ((epochcertdate > currentdate)); then
    datediff=$((epochcertdate-currentdate))
    state="OK"
  else
    state="EXPIRED"
    datediff=$((currentdate-epochcertdate))
  fi
  days=$((datediff/86400))
  certdate=`echo $cert | base64 -d | openssl x509 -noout -enddate| cut -d= -f2`
  printf "$format" "$state" "$days" "$name" "$certdate" "$namespace" | tee -a $DST/certificate_expiry.out
done

echo "Step 14/16 -- Additional"
oc api-versions  &> $DST/api-versions.out
oc get nncp -A &> $DST/nncp.out
oc get nncp -A -o yaml &> $DST/nncp.out.yaml
oc get ccr -A &> $DST/ccr.out
oc get rems -A &> $DST/rems.out
oc get scan -A &> $DST/compliance-scan.out
oc get scan -A -o yaml &> $DST/compliance-scan.out.yaml
oc get scc -A &> $DST/scc.out
oc get scc -A -o yaml &> $DST/scc.out.yaml
oc get image.config cluster -o yaml &> $DST/image-config.out.yaml
oc get scansetting -A &> $DST/compliance-scansetting.out
oc get scansetting -A -o yaml &> $DST/compliance-scansetting.out.yaml
oc get scansettingbinding -A &> $DST/compliance-scansettingbinding.out
oc get scansettingbinding -A -o yaml &> $DST/compliance-scansettingbinding.out.yaml
oc get servicemonitor -A &> $DST/servicemonitor.out
oc get servicemonitor -A -o yaml &> $DST/servicemonitor.out.yaml
oc get gateway -A &> $DST/gateway.out
oc get gateway -A -o yaml &> $DST/gateway.out.yaml
oc get virtualservice -A &> $DST/virtualservice.out
oc get virtualservice -A -o yaml &> $DST/virtualservice.out.yaml
oc get destinationrule -A &> $DST/destinationrule.out
oc get destinationrule -A -o yaml &> $DST/destinationrule.out.yaml
oc get prometheusrule -A &> $DST/prometheusrule.out
oc get prometheusrule -A -o yaml &> $DST/prometheusrule.out.yaml
oc get alertmanagerconfig -A &> $DST/alertmanager-config.out
oc get alertmanagerconfig -A -o yaml &> $DST/alertmanager-config.out.yaml
oc get installplan -A &> $DST/installplan.out
oc get installplan -A -o yaml &> $DST/installplan.out.yaml
## optional for user-workload
oc get secret thanos-ruler-alertmanagers-config -n openshift-user-workload-monitoring -o jsonpath='{.data.alertmanagers\.yaml}' | base64 -d &> $DST/thanos-ruler-alertmanager-dst.out 
##
oc get secret -n openshift-monitoring alertmanager-main -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d &> $DST/cluster-alertmanager.out
oc get secret alertmanager-main-generated -n openshift-monitoring -o jsonpath='{.data.alertmanager\.yaml\.gz}' | base64 -d | gunzip $DST/cluster-alertmanager-generated.out
## optional for user-workload
oc get secret alertmanager-user-workload-generated -n openshift-user-workload-monitoring -o jsonpath='{.data.alertmanager\.yaml\.gz}' | base64 -d | gunzip &> $DST/generated-alertmanager.out.yaml
oc get cm thanos-ruler-user-workload-rulefiles-0 -n openshift-user-workload-monitoring -o yaml  &> $DST/thanosrulefile-user-workload-monitoring.out.yaml
##
oc get apirequestcount &> $DST/api-requests-count.out.yaml
for NODE_NAME in $(oc get nodes -o jsonpath='{.items[*].metadata.name}'); do oc get --raw /api/v1/nodes/$NODE_NAME/proxy/configz ;done &> $DST/node-kubeletconfig.out.json
oc get rolebinding -A -o custom-columns=NAME:.metadata.name,KIND:.subjects[*].kind,SUBJECTNAME:.subjects[*].name,ROLEKIND:.roleRef.kind,ROLENAME:.roleRef.name &> $DST/rolebinding-custom.out

echo "Step 15/16 -- Virtualization"
oc get vmi -A  &> $DST/vmi.out
oc get vmi -A -o yaml &> $DST/vmi.out.yaml
oc get vmim -A  &> $DST/vmim.out
oc get vmim -A -o yaml &> $DST/vmim.out.yaml
oc get vm -A  &> $DST/vm.out
oc get vm -A -o yaml &> $DST/vm.out.yaml
oc get dv -A  &> $DST/dv.out
oc get dv -A -o yaml &> $DST/dv.out.yaml
oc get dataimportcron -A  &> $DST/dataimportcron.out
oc get dataimportcron -A -o yaml &> $DST/dataimportcron.out.yaml
oc get storageprofile -A  &> $DST/storageprofile.out
oc get storageprofile -A -o yaml &> $DST/storageprofile.out.yaml
oc get nns -A  &> $DST/nns.out
oc get nns -A -o yaml &> $DST/nns.out.yaml
oc get net-attach-def -A  &> $DST/nad.out
oc get net-attach-def -A -o yaml &> $DST/nad.out.yaml

echo "Step 16/16 taring up the results here -->  $COLL/$time-pg-collect.out.tar.gz"
tar -zcf $COLL/$time-pg-collect.out.tar.gz $DST/*

echo "#####################"

echo ""
echo "All commands completed at `date`"
