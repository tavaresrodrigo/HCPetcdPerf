# HCPetcdPerf
This project provides a Bash script to automate the collection of etcd performance metrics from Hosted Control Planes (HCPs) in an OpenShift environment. It leverages `oc` for cluster interaction and `podman` to run a specialized `etcd-perf` container directly on the etcd host nodes, providing insights into filesystem performance.
