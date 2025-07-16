#!/bin/bash

# This script automates the process of gathering etcd performance metrics
# from OpenShift Hosted Control Planes (HCPs) and displays the results in a structured format.

ETCD_POD_NAME="etcd-2"
ETCD_PERF_IMAGE="quay.io/cloud-bulldozer/etcd-perf"

# Global variable to accumulate results for the final summary table
SUMMARY_DATA=""

# Function to print a formatted frame with line wrapping
print_frame() {
    local title="$1"
    local content="$2"
    local width=75
    local color_title='\033[1;36m' # Bold Cyan
    local color_content='\033[0;37m' # White
    local color_border='\033[0;34m' # Blue
    local nc='\033[0m' # No Color

    # Top border
    printf "${color_border}┌─%s─┐${nc}\n" "$(printf '─%.0s' $(seq 1 $width))"
    # Title line
    printf "${color_border}│ ${color_title}%-${width}s${color_border} │${nc}\n" "$title"
    # Middle border
    printf "${color_border}├─%s─┤${nc}\n" "$(printf '─%.0s' $(seq 1 $width))"
    # Content lines with wrapping
    while IFS= read -r line; do
        echo "$line" | fold -s -w "$width" | while IFS= read -r wrapped_line; do
            printf "${color_border}│ ${color_content}%-${width}s${color_border} │${nc}\n" "$wrapped_line"
        done
    done <<< "$content"
    # Bottom border
    printf "${color_border}└─%s─┘${nc}\n" "$(printf '─%.0s' $(seq 1 $width))"
}

echo "==================================================="
echo "=== Starting HCP etcd Performance Analysis Script ==="
echo "==================================================="
echo ""

echo "--- Fetching all HCP namespaces ---"
HCP_NAMESPACES=$(oc get hcp -A -o custom-columns=NAMESPACE:.metadata.namespace --no-headers)

if [ -z "$HCP_NAMESPACES" ]; then
    echo "No HCPs found or 'oc get hcp' command failed."
    exit 1
fi

echo "Found HCPs: $(echo "$HCP_NAMESPACES" | tr '\n' ' ')"
echo ""

# Loop through each identified HCP namespace
for hcp_name in $HCP_NAMESPACES; do
    echo "--> Processing HCP: $hcp_name..."

    # Set project and get pod info
    oc project "$hcp_name" >/dev/null
    POD_INFO=$(oc get pod "$ETCD_POD_NAME" -o custom-columns=NAME:.metadata.name,NODE_IP:.status.hostIP --no-headers 2>/dev/null)
    if [ -z "$POD_INFO" ]; then
        print_frame "ERROR: HCP '$hcp_name'" "Could not find pod '$ETCD_POD_NAME'."
        continue
    fi
    
    POD_ID=$(echo "$POD_INFO" | awk '{print $1}')
    HOST_IP=$(echo "$POD_INFO" | awk '{print $2}')
    NODE_HOSTNAME=$(oc get node -o wide --no-headers | awk -v ip="$HOST_IP" '$0 ~ ip {print $1}')
    
    # Get etcd mount point on the host
    oc project default >/dev/null
    POD_UID=$(oc get pod -n "$hcp_name" "$POD_ID" -o jsonpath='{.metadata.uid}')
    MOUNT_OUTPUT_RAW=$(oc debug node/"$NODE_HOSTNAME" -- chroot /host mount 2>/dev/null)
    ETCD_MOUNT_LINE=$(echo "$MOUNT_OUTPUT_RAW" | awk -v uid="$POD_UID" '$0 ~ "/var/lib/kubelet/pods/" uid "/volumes/" && ($0 ~ /type xfs/ || $0 ~ /type ext4/) {print; exit}')

    if [ -z "$ETCD_MOUNT_LINE" ]; then
        print_frame "ERROR: HCP '$hcp_name' on Node '$NODE_HOSTNAME'" "Could not identify a valid xfs or ext4 etcd mount point."
        continue
    fi

    ETCD_MOUNTPOINT=$(echo "$ETCD_MOUNT_LINE" | awk '{print $3}')
    FILESYSTEM_TYPE=$(echo "$ETCD_MOUNT_LINE" | grep -oP 'type \K(xfs|ext4)')

    # Get hostname and dates from the debugged node, silencing debug output
    DEBUG_NODE_CURRENT_HOSTNAME=$(oc debug node/"$NODE_HOSTNAME" -- chroot /host hostname 2>/dev/null)
    DEBUG_NODE_CURRENT_DATE=$(oc debug node/"$NODE_HOSTNAME" -- chroot /host date +"%Y-%m-%d %H:%M:%S" 2>/dev/null)
    # Create a clean timestamp for the log file name
    LOG_TIMESTAMP=$(oc debug node/"$NODE_HOSTNAME" -- chroot /host date +"%Y%m%d_%H%M%S" 2>/dev/null)


    # Run etcd-perf command, saving to a unique, timestamped log file
    LOG_FILE="${LOG_TIMESTAMP}-${hcp_name}-perf.log"
    echo "--- Saving full output to: $LOG_FILE ---"
    PODMAN_COMMAND="sudo podman run --rm --volume \"$ETCD_MOUNTPOINT:$ETCD_MOUNTPOINT:Z\" \"$ETCD_PERF_IMAGE\""
    oc debug node/"$NODE_HOSTNAME" -- chroot /host bash -c "$PODMAN_COMMAND" > "$LOG_FILE" 2>&1

    PODMAN_OUTPUT_SUMMARY=$(tail -n 5 "$LOG_FILE")

    # Prepare content for the frame using a heredoc to preserve newlines
    CARD_CONTENT=$(cat <<EOF
Hostname: $DEBUG_NODE_CURRENT_HOSTNAME
Date: $DEBUG_NODE_CURRENT_DATE
Filesystem: $FILESYSTEM_TYPE
Mount Point: $ETCD_MOUNTPOINT
---------------------------------------------------------------------------
Etcd Perf Output (Last 5 lines):
$PODMAN_OUTPUT_SUMMARY
EOF
)
    # Print the formatted card for the current HCP
    print_frame "HCP: $hcp_name" "$CARD_CONTENT"

    # Append data for the final summary. Extracts the 99th percentile fsync time.
    P99_FSYNC_TIME=$(echo "$PODMAN_OUTPUT_SUMMARY" | grep -oP '99th percentile of fsync is \K[0-9.]+' || echo "N/A")
    FSYNC_UNIT=$(echo "$PODMAN_OUTPUT_SUMMARY" | grep -oP '99th percentile of fsync is [0-9.]+ \K\w+' || echo "")
    SUMMARY_DATA+="$DEBUG_NODE_CURRENT_HOSTNAME\t$hcp_name\t$FILESYSTEM_TYPE\t${P99_FSYNC_TIME} ${FSYNC_UNIT}\n"
    
    echo "" # Add a newline for spacing
done

echo "==================================================="
echo "=== Summary of etcd Performance Analysis ==="
echo "==================================================="
echo ""

# Print the final summary table
{
    echo -e "Hostname\tHCP_Name\tFilesystem\tP99_Fsync_Time"
    echo -e "$SUMMARY_DATA"
} | column -t -s $'\t'

echo ""
echo "==================================================="
echo "=== Analysis Complete ==="
echo "==================================================="
