# node-connectivity-monitor

Systemd circuit-breaker service that monitors for node connectivity and triggers a specified action when connectivity is lost.

## Usage

1. Copy the scripts to `/usr/local/bin`. Make sure PATH includes this directory.
2. Copy the systemd files to your host `/etc/systemd/system/` directory.
3. (Optional) Configure the service through systemd drop-ins.
4. Enable and start the timer.

   ```bash
   systemctl daemon-reload
   systemctl enable --now network-connectivity-monitor.timer
   ```

### Configuration

Configuration is provided through environment variables. Uses systemd drop-ins to configure the service and OnFailure action.

```ini
# /etc/systemd/system/network-connectivity-monitor.service.d/10-custom.conf
[Unit]
OnFailure=my-custom.service

[Service]
Environement="TARGET_IP=192.168.1.1"
```

| Variable          | Description                                                                                          | Default   |
| ----------------- | ---------------------------------------------------------------------------------------------------- | --------- |
| TARGET_IP         | The IP address to test connectivity.                                                                 | `8.8.8.8` |
| FAILURE_THRESHOLD | The number of non-consecutive failures before the OnFailure action is triggered.                     | `10`      |
| SUCCESS_THRESHOLD | The number of consecutive successes before reseting the failure count (closing the circuit breaker). | `3`       |

The timer runs every minute by default. You can change this by creating a drop-in file for the timer unit.

```ini
# /etc/systemd/system/network-connectivity-monitor.timer.d/10-custom.conf
[Timer]
OnUnitActiveSec=10 # Test every 10 seconds
```

### OnFailure action

> ![important]
> By default, the OnFailure action is `systemd-reboot.service`, which will clear the state of the circuit breaker. If you use an alternative action, ensure the state is cleared. The script assumes the failed state is terminal and **will not** transition back to a healthy (closed circuit) after hitting FAILURE_THRESHOLD. You must clear the state with `network-connectivity-monitor.sh reset`.
