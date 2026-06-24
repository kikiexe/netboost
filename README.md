# netboost

Client-side network optimization toolkit for Linux. Designed for shared Wi-Fi
environments (kost, cafe, coworking) where you have no control over the router
but need the best possible connection from your device.

## What it does

| Module | Optimization | Impact |
|--------|-------------|--------|
| Wi-Fi  | Disable power save | Eliminates 200-900ms latency spikes |
| TCP    | BBR congestion control | Handles Wi-Fi "loss" without halving throughput |
| TCP    | Fast Open, no slow-start-after-idle | Faster connection setup, stable idle connections |
| TCP    | Tuned buffers and keepalive | Sized for real Wi-Fi, not datacenter links |
| DNS    | Cloudflare (1.1.1.1) resolver | Faster name resolution than ISP defaults |
| QoS    | HTB + fq_codel traffic shaping | Prioritizes interactive traffic, eliminates bufferbloat |

## Quick start

```bash
# Install (one time)
sudo bash install.sh

# Apply all optimizations
sudo netboost optimize

# Check status
netboost status

# Live monitoring
netboost monitor

# Revert everything
sudo netboost reset
```

## Commands

| Command | Requires sudo | Description |
|---------|:------------:|-------------|
| `optimize` | Yes | Apply all optimizations |
| `status` | No | Show current state of all optimizations |
| `monitor [interval]` | No | Real-time signal/latency/throughput dashboard |
| `benchmark` | No | Benchmark DNS providers |
| `reset` | Yes | Revert all optimizations to defaults |
| `help` | No | Show usage |

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `NETBOOST_QOS_RATE` | `15000` | QoS bandwidth limit in kbit/s. Set to ~80% of your actual upload speed for best results. |

## How QoS works

The tool creates 3 traffic priority classes on your Wi-Fi interface:

```
Root (HTB, 15 Mbit/s)
|
+-- Interactive (50%, prio 0): DNS, SSH, ICMP, TCP ACKs
|
+-- Normal (30%, prio 1): HTTP, HTTPS
|
+-- Bulk (20%, prio 2): Everything else
```

Each class uses `fq_codel` to prevent bufferbloat. The most impactful rule is
prioritizing TCP ACK packets: this keeps the TCP feedback loop responsive, which
indirectly improves download speeds even though `tc` only controls outgoing traffic.

## Persistence

Optimizations are **not persistent** across reboots. To auto-apply on boot,
add this to your crontab:

```bash
sudo crontab -e
# Add this line:
@reboot /home/kikiexe/Projects/netboost/netboost.sh optimize
```

## Project structure

```
netboost/
├── netboost.sh        Main CLI entry point
├── install.sh         Symlink installer
├── README.md          This file
└── lib/
    ├── colors.sh      Terminal output utilities
    ├── wifi.sh        Wi-Fi adapter optimization
    ├── tcp.sh         TCP kernel parameter tuning
    ├── dns.sh         DNS resolver configuration
    ├── qos.sh         Traffic prioritization (tc)
    └── monitor.sh     Real-time monitoring dashboard
```

## Limitations

This tool operates entirely on your device. It cannot:

- Control how the router allocates bandwidth to other devices
- Increase the total bandwidth of the Wi-Fi network
- Fix weak signal (move closer to the router for that)

What it *can* do is ensure your device uses the available bandwidth as
efficiently as possible and responds to network conditions faster than
an unoptimized system.
