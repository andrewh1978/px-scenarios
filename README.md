# Prerequisites
Running Kubernetes cluster with at least 3 worker nodes
Storage attached to each worker node

# Usage
Source the file:
```
. px-scenarios.sh
```

Install Portworx and cause a pool to go offline by filling it:
```
pxd_fill_one_node
```

Or, do the same but with a particular Portworx version:
```
px_version=2.3.5 px_fill_one_node
```
