# OpenShift HCP etcd Performance Analyzer

This project provides a Bash script to automate the collection of etcd performance metrics from Hosted Control Planes (HCPs) in an OpenShift environment. It leverages `oc` for cluster interaction and `podman` to run a specialized `etcd-perf` container directly on the etcd host nodes, providing insights into filesystem performance.

## 🚀 Features

* **Automated HCP Discovery:** Automatically identifies all HCP namespaces within your connected OpenShift cluster.

* **Per-HCP Analysis:** Iterates through each discovered HCP to collect performance data.

* **Host-Level Execution:** Runs the `etcd-perf` benchmark directly on the etcd host nodes via `oc debug` and `podman`.

* **Mount Point Identification:** Dynamically identifies the `xfs` or `ext4` mount point for etcd data on the host.

* **Detailed Logging:** Saves the full `etcd-perf` output for each HCP to a unique, timestamped log file.

* **Structured Summary:** Presents a concise summary table of key performance metrics (e.g., 99th percentile fsync time) across all analyzed HCPs.

* **User-Friendly Output:** Provides clear console output with visual cues for progress and errors.

## 📋 Prerequisites

Before running this script, ensure you have the following installed and configured:

1.  **OpenShift CLI (`oc`):**

    * Download and install `oc` from the official OpenShift documentation.

    * You must be logged into your OpenShift cluster with sufficient permissions to:

        * `get hcp` (across all namespaces)

        * `project` (switch between namespaces)

        * `get pod` (in HCP namespaces)

        * `get node`

        * `debug node` (on etcd host nodes)

        * `chroot /host` (within the debug session)

        * `mount` (within the debug session)

        * `stat` (within the debug session)

2.  **`podman`:**

    * `podman` must be installed on the OpenShift nodes where the etcd pods are running.

    * The user running the `oc debug` command must have `sudo` privileges configured on the host nodes to execute `podman`.

3.  **`quay.io/cloud-bulldozer/etcd-perf` image:**

    * This image will be pulled by `podman` on the host nodes. Ensure the nodes have network access to `quay.io`.

## 📦 Installation

1.  **Clone the repository:**

    ```bash
    git clone [https://github.com/your-username/openshift-etcd-perf-analyzer.git](https://github.com/your-username/openshift-etcd-perf-analyzer.git)
    cd openshift-etcd-perf-analyzer
    ```

2.  **Make the script executable:**

    ```bash
    chmod +x etcd-hcp-perf.sh
    ```

## 🚀 Usage

1.  **Log in to your OpenShift cluster:**

    ```bash
    oc login --token=<your_token> --server=<your_api_server>
    ```

    Ensure your `oc` context is set to the cluster containing the HCPs you wish to analyze.

2.  **Run the script:**

    ```bash
    ./etcd-hcp-perf.sh
    ```

The script will output its progress to the console. For each HCP, it will:

* Display a formatted card summarizing the host details and the last 5 lines of the `etcd-perf` output.

* Save the complete `etcd-perf` output to a log file named `YYYYMMDD_HHMMSS-hcpname-perf.log` in the directory where the script is executed.

Finally, a summary table will be printed to the console, comparing key performance metrics across all analyzed HCPs.

## 📊 Output Explanation

### Console Output

The console output provides real-time feedback on the script's progress. For each HCP, you'll see a "card" displaying:

* **Hostname:** The hostname of the OpenShift node where the etcd pod is running.

* **Date:** The date and time when the `etcd-perf` test was executed on that node.

* **Filesystem:** The type of filesystem (`xfs` or `ext4`) used for the etcd data directory.

* **Mount Point:** The absolute path to the etcd data directory on the host node.

* **Etcd Perf Output (Last 5 lines):** A snippet of the benchmark's final results.

### Log Files

For each HCP, a detailed log file (`YYYYMMDD_HHMMSS-hcpname-perf.log`) is generated. This file contains the complete standard output and standard error from the `etcd-perf` container execution. You can examine these logs for in-depth analysis of the benchmark results, including all latency percentiles, operations per second, and any errors encountered by `etcd-perf`.

### Summary Table

The final summary table consolidates key information from all HCPs:

* **Hostname:** The hostname of the node where the etcd pod resides.

* **HCP_Name:** The namespace/name of the Hosted Control Plane.

* **Filesystem:** The filesystem type of the etcd data volume.

* **P99_Fsync_Time:** The 99th percentile of fsync latency, a critical metric for etcd performance, extracted from the `etcd-perf` output. This indicates that 99% of fsync operations completed within this time.

## 🤝 Contributing

Contributions are welcome! If you have suggestions for improvements, bug reports, or new features, please open an issue or submit a pull request.
## 🔗 Reference

This project is inspired by and aims to help validate the etcd disk performance requirements outlined in the Red Hat Access Solution:

* **"How to use 'fio' to check etcd disk performance in OpenShift"**
    * **Link:** [https://access.redhat.com/solutions/4885641](https://access.redhat.com/solutions/4885641)
    * **Summary:** This solution highlights the critical need for etcd to have fast disk response times, especially for write operations to its backing storage. It emphasizes that `wal_fsync_duration_seconds` p99 duration should ideally be less than 10ms for production workloads to ensure optimal etcd performance and cluster stability. Issues with disk speed can lead to frequent etcd alerts and overall cluster instability.

