#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

# The IP address to ping
TARGET_IP="${TARGET_IP:-8.8.8.8}"
# Failure threshold before triggering the OnFailure action
FAILURE_THRESHOLD=${FAILURE_THRESHOLD:-10}
# Success threshold before transitioning back to healthy (closed circuit) state
SUCCESS_THRESHOLD=${SUCCESS_THRESHOLD:-3}

# Directory where state will be stored between invocations
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/network-connectivity-monitor"

# Implements a circuit breaker pattern for network connectivity checks.
# State is stored in STATE_DIR/state. The state is either open, closed or failed. Faileed is a terminal state.
# The failure-count is stored in STATE_DIR/failure-count.
# The success-count is stored in STATE_DIR/success-count.
# The state should transition from closed to open after a single failure.
# The state should transition from open to closed only after SUCCESS_THRESHOLD successes
# The state should transitoin from open to failed after FAILURE_THRESHOLD failures.
#
# The script tests for connectivity and triggers an action (on_down or on_up) to update the state machine.

#####################
# State functions
#####################

# Check if the state has been initialized
function is_initialized() {
  [[ -e "$STATE_DIR/state" ]]
}

# Load the state from disk
function load_state() {
  # Default state
  state=closed
  failure_count=0
  success_count=0

  if is_initialized; then
    # Read the current state and counts
    state=$(cat "$STATE_DIR/state")
    failure_count=$(cat "$STATE_DIR/failure-count")
    success_count=$(cat "$STATE_DIR/success-count")
  fi
}

# Save the state to disk
function save_state() {
  mkdir -p "$STATE_DIR"
  echo "$state" >"$STATE_DIR/state"
  echo "$failure_count" >"$STATE_DIR/failure-count"
  echo "$success_count" >"$STATE_DIR/success-count"
}

# Resets the state as if this is a fresh boot
function reset_state() {
  rm -rf "$STATE_DIR"
}

# Checks connectivity, dispatches events, and updates the state
function dispatch_events() {
  # Load the state
  load_state

  # Check connectivity and dispatch an up/down event to update the state machine
  if check_connectivity; then
    on_up
  else
    on_down
  fi

  # Save the state
  echo "state=$state failure=${failure_count}/${FAILURE_THRESHOLD} success=${success_count}/${SUCCESS_THRESHOLD}"
  save_state
}

#####################
# Side effects
#####################

function check_connectivity() {
  # Test the connection
  if ping -c 1 $TARGET_IP >/dev/null 2>&1; then
    echo "Network connectivity to $TARGET_IP is OK."
    return 0
  else
    echo "Network connectivity to $TARGET_IP is DOWN."
    return 1
  fi
}

#####################
# Events
#####################

function on_down() {
  case "$state" in
  closed)
    state=open
    failure_count=$((failure_count + 1))
    success_count=0
    ;;
  open)
    failure_count=$((failure_count + 1))
    success_count=0

    # Check for the failure threshold
    if [[ $failure_count -ge "$FAILURE_THRESHOLD" ]]; then
      state=failed
    fi
    ;;
  esac
}

function on_up() {
  case "$state" in
  open)
    success_count=$((success_count + 1))

    # Check for the success threshold
    if [[ $success_count -ge "$SUCCESS_THRESHOLD" ]]; then
      state=closed
      failure_count=0
      success_count=0
    fi
    ;;
  esac
}

#####################
# Control loop
#####################

command="${1:-}"
if [[ "$command" == "reset" ]]; then
  reset_state
  echo "State has been reset."
  exit 0
fi

# Check connectivity and update the state machine
dispatch_events

# Check for the terminal failed state, exit with a non-zero code to trigger OnFailure action
if [[ $state == "failed" ]]; then
  echo "Network connectivity has failed after $FAILURE_THRESHOLD attempts. Triggering OnFailure action." >&2
  exit 1
fi

exit 0
