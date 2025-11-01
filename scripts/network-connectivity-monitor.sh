#!/bin/bash

set -e

# The IP address to ping
TARGET_IP="${TARGET_IP:-$1}"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp/network-connectivity-monitor}/network-connectivity-monitor"
FAILURE_THRESHOLD=${FAILURE_THRESHOLD:-10}
SUCCESS_THRESHOLD=${SUCCESS_THRESHOLD:-3}

# Implements a circuit breaker pattern for network connectivity checks.
# State is stored in STATE_DIR/state. The state is either open, closed or failed. Faileed is a terminal state.
# The failure-count is stored in STATE_DIR/failure-count.
# The success-count is stored in STATE_DIR/success-count.
# The state should transition from closed to open after a single failure.
# The state should transition from open to closed only after SUCCESS_THRESHOLD successes
# The state should transitoin from open to failed after FAILURE_THRESHOLD failures.

function is_initialized() {
  [[ -e "$STATE_DIR/state" ]]
}

function load_state() {
  # Read the current state and counts
  state=$(cat "$STATE_DIR/state")
  failure_count=$(cat "$STATE_DIR/failure-count")
  success_count=$(cat "$STATE_DIR/success-count")
}

function save_state() {
  mkdir -p "$STATE_DIR"
  echo "$state" >"$STATE_DIR/state"
  echo "$failure_count" >"$STATE_DIR/failure-count"
  echo "$success_count" >"$STATE_DIR/success-count"
}

function check_connectivity() {
  # Test the connection
  if ping -c 1 $TARGET_IP >/dev/null 2>&1; then
    connectivity_status="up"
    echo "Network connectivity to $TARGET_IP is OK."
  else
    connectivity_status="down"
    echo "Network connectivity to $TARGET_IP is DOWN."
  fi
}

function is_up() {
  [[ $connectivity_status == "up" ]]
}

function is_down() {
  [[ $connectivity_status != "up" ]]
}

# Default values
state="closed"
failure_count=0
success_count=0

# Load any existing state
if is_initialized; then
  load_state
fi

# Check connectivity, storing state in connectivity_status
check_connectivity

# Update the state machine
case "$state" in

"closed")
  if is_down; then
    state="open"
    failure_count=$((failure_count + 1))
    success_count=0
  fi
  ;;
"open")
  if is_down; then
    failure_count=$((failure_count + 1))
    success_count=0
  else
    success_count=$((success_count + 1))
  fi

  # Check for the failure threshold
  if [[ $failure_count -ge "$FAILURE_THRESHOLD" ]]; then
    state="failed"
  fi

  # Check for the success threshold
  if [[ $success_count -ge "$SUCCESS_THRESHOLD" ]]; then
    state="closed"
    failure_count=0
    success_count=0
  fi
  ;;
*)
  state="failed"
  success_count=0
  ;;
esac

# Save the state
save_state

echo "state=$state failure=${failure_count}/${FAILURE_THRESHOLD} success=${success_count}/${SUCCESS_THRESHOLD}"

if [[ $state == "failed" ]]; then
  echo "Network connectivity has failed after $FAILURE_THRESHOLD attempts. Triggering OnFailure action."
  exit 1
fi

exit 0
