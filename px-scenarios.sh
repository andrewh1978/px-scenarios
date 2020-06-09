_pxd_gb=1073741824

# Install Portworx - set $px_version to force a version
function _pxd_install_px {
  k8s_version=$(kubectl version --short | awk -Fv '/Server Version: / {print $3}')
  url="https://install.portworx.com/$px_version?kbver=$k8s_version&b=true&c=px-deploy-$cluster&stork=true&st=k8s&lh=true"
  [ -e /usr/bin/oc ] && url="$url&osft=true"
  curl -so /tmp/px.yml $url
  kubectl apply -f /tmp/px.yml
}

# Install storkctl - wait for stork pods to become ready first
function _pxd_install_storkctl {
  while : ; do
    STORK_POD=$(kubectl get pods -n kube-system -l name=stork -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ "$STORK_POD" ]; then
      kubectl cp -n kube-system $STORK_POD:/storkctl/linux/storkctl /usr/bin/storkctl 2>/dev/null
      chmod +x /usr/bin/storkctl 2>/dev/null
      [ $? -eq 0 ] && break
    fi
    sleep 5
    echo waiting for stork
  done
}

# Wait for PX node count to be same as K8s node count
function _pxd_px_wait {
  while : ; do
    nodes=$(kubectl get node  | grep -i ready | awk '{print$1}' | xargs kubectl get node  -o=jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints}{"\n"}{end}' | grep -iv noschedule | wc -l 2>&1)
    n=$(kubectl exec -n kube-system -it $(kubectl get pods -n kube-system -lname=portworx --field-selector=status.phase=Running | tail -1 | cut -f 1 -d " ") -- /opt/pwx/bin/pxctl status status 2>/dev/null | grep "Yes.*Online.*Up" | wc -l)
    echo Waiting for Portworx nodes $n/$nodes
    [ $n -eq $nodes ] && break
    sleep 1
  done
}

# Execute a command in a portworx pod
function _pxd_kexec {
  kubectl exec -n kube-system -it $(kubectl get pods -n kube-system -lname=portworx --field-selector=status.phase=Running --no-headers | sort | tail -1 | cut -f 1 -d " ") -- $@ | tr '\r' '\n'
}

# Execute a pxctl command
function _pxd_pxctl {
  _pxd_kexec /opt/pwx/bin/pxctl $@
}

# Assumes 3 node cluster
# Assumes each node has single pool, all the same size
# Creates repl 3 volume the size of each pool
# Creates repl 1 volume the size of each pool
# Half fill both volumes, resulting in filling one pool
function pxd_fill_one_node {
  _pxd_install_px
  _pxd_px_wait
  size=$(_pxd_pxctl cluster provision-status -j | grep size | head -1 | sed 's/[^0-9]//g')
  size=$(($size/$_pxd_gb))
  _pxd_pxctl volume create --repl 3 --size $size volume1
  _pxd_pxctl volume create --repl 1 --size $size volume2
  dev1=$(_pxd_pxctl host attach volume1 | sed 's/.*: //')
  dev2=$(_pxd_pxctl host attach volume2 | sed 's/.*: //')
  _pxd_kexec mount $dev1 /mnt
  _pxd_kexec dd if=/dev/urandom of=/mnt/file bs=1048576 count=$((size*512))
  _pxd_kexec umount /mnt
  _pxd_kexec mount $dev2 /mnt
  _pxd_kexec dd if=/dev/urandom of=/mnt/file bs=1048576 count=$((size*512))
  _pxd_kexec umount /mnt
}
