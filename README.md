# Prometheus and Grafana Monitoring on Ubuntu

A beginner-friendly setup for monitoring CPU and memory on one Ubuntu EC2 server with Prometheus, Node Exporter, and Grafana. The supplied scripts install the services and configure them to start automatically.

## What this project uses

- **Prometheus** collects and stores time-series metrics and provides the PromQL query language.
- **Node Exporter** exposes Linux host metrics such as CPU and memory for Prometheus to scrape.
- **Grafana** displays Prometheus metrics in dashboards and evaluates alert rules.

## Monitoring architecture

```text
Ubuntu host
  Node Exporter :9100 ──┐
                         ├──> Prometheus :9090 <── Grafana :3000
  Prometheus :9090 ──────┘                         (Prometheus data source)
```

Prometheus and Node Exporter run on the same host, so the scrape targets are `localhost:9090` and `localhost:9100`. Grafana also runs on that host and connects to Prometheus at `http://localhost:9090`.

## Prerequisites

- An Ubuntu 22.04 or 24.04 EC2 instance (x86-64 or ARM64) with internet access.
- A user with `sudo` access.
- Git installed, or the repository downloaded as a ZIP file.
- Inbound SSH access from your own IP address.

The scripts install official Prometheus and Node Exporter release archives and Grafana packages from Grafana's official APT repository. Review the scripts before running them. Prometheus and Node Exporter versions can be overridden with the environment variables documented below.

## 1. Get the project onto the server

Connect to the instance over SSH, then clone the repository:

```bash
git clone https://github.com/<YOUR-GITHUB-USERNAME>/prometheus-grafana-monitoring.git
cd prometheus-grafana-monitoring
```

Replace `<YOUR-GITHUB-USERNAME>` with the account or organization that owns the repository. If you uploaded a ZIP instead, extract it and `cd` into the extracted project directory.

Make the scripts executable:

```bash
chmod +x scripts/*.sh
```

## 2. Install and configure Prometheus

Run the installer from the repository root:

```bash
sudo ./scripts/install-prometheus.sh
```

The script creates a dedicated `prometheus` system user, installs the binaries and console files, creates `/etc/prometheus` and `/var/lib/prometheus`, installs the supplied configuration and systemd unit, validates the configuration with `promtool`, then enables and starts Prometheus.

The scrape configuration is in [`prometheus/prometheus.yml`](prometheus/prometheus.yml). It scrapes Prometheus itself and Node Exporter every 15 seconds. The systemd unit is in [`prometheus/prometheus.service`](prometheus/prometheus.service).

Check the service and configuration:

```bash
sudo systemctl status prometheus --no-pager
sudo promtool check config /etc/prometheus/prometheus.yml
curl http://localhost:9090/-/ready
```

Open `http://<EC2-PUBLIC-IP>:9090` in a browser to access the Prometheus UI. Do not expose port 9090 to the whole internet; see [AWS EC2 Security Group ports](#aws-ec2-security-group-ports).

## 3. Install Node Exporter

```bash
sudo ./scripts/install-node-exporter.sh
```

This creates the dedicated `node_exporter` system user, installs the binary and the systemd unit from [`node-exporter/node_exporter.service`](node-exporter/node_exporter.service), and enables and starts the service.

Verify the service and metrics endpoint:

```bash
sudo systemctl status node_exporter --no-pager
curl http://localhost:9100/metrics
```

The output should include metrics such as `node_cpu_seconds_total` and `node_memory_MemTotal_bytes`. Node Exporter's port is normally only needed by Prometheus on the same server; do not make port 9100 public.

## 4. Check Prometheus targets

The Prometheus configuration uses these targets:

| Target | Address |
|---|---|
| Prometheus | `localhost:9090` |
| Node Exporter | `localhost:9100` |

After both services have started, validate and reload Prometheus:

```bash
sudo promtool check config /etc/prometheus/prometheus.yml
sudo systemctl restart prometheus
```

Visit `http://<EC2-PUBLIC-IP>:9090/targets`. Both targets should show **UP**. You can also inspect the target API:

```bash
curl -s http://localhost:9090/api/v1/targets
```

## 5. Install Grafana

```bash
sudo ./scripts/install-grafana.sh
```

The script adds Grafana's official APT repository, installs Grafana, and enables and starts its systemd service.

Check the service:

```bash
sudo systemctl status grafana-server --no-pager
```

Open `http://<EC2-PUBLIC-IP>:3000`. Sign in with the initial credentials shown by the Grafana installation (commonly `admin` / `admin`) and set a new password when prompted.

### Add Prometheus as a data source

1. In Grafana, open **Connections → Data sources** and choose **Add data source**.
2. Select **Prometheus**.
3. Set the Prometheus server URL to **`http://localhost:9090`**. Since Grafana and Prometheus are on the same server, `localhost` is correct.
4. Choose **Save & test**. Grafana should report that the data source is working.

## 6. Create the dashboard

Create a dashboard named **Ubuntu Server Monitoring** with exactly two panels:

1. In Grafana, go to **Dashboards → New → New dashboard → Add visualization**.
2. Select the Prometheus data source and create a **CPU Usage** panel with this query:

   ```promql
   100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])))
   ```

3. Set the visualization to **Time series** or **Gauge**, the unit to **Percent (0-100)**, minimum to `0`, and maximum to `100`. Save the panel.
4. Add a **Memory Usage** panel using this query:

   ```promql
   100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
   ```

5. Use the same visualization and percent range, then save the panel and dashboard. Do not add disk panels or other monitoring panels.

An instance variable is optional for multi-host setups. To add one, open **Dashboard settings → Variables → New variable**, choose **Query** and the Prometheus data source, then use `label_values(up{job="node_exporter"}, instance)`.

## 7. CPU and memory PromQL queries

The complete query list and plain-language descriptions are in [`queries/promql-queries.md`](queries/promql-queries.md). These are the queries used by the dashboard:

**CPU Usage Percentage**

```promql
100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])))
```

**Memory Usage Percentage**

```promql
100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
```

Paste either query into the Prometheus UI's **Graph** page or a Grafana panel. Metrics may take one scrape interval to appear after Node Exporter starts.

## 8. Configure the memory alert

Create a Grafana Unified Alerting rule named **High-Memory-Usage**:

1. Go to **Alerting → Alert rules → New alert rule** and enter the rule name.
2. Select the Prometheus data source and use the Memory Usage Percentage query above.
3. Configure the condition to fire when the query value **IS ABOVE 5**. If the editor requires an expression, reduce query `A` using **Last**, then add a threshold expression **Is above 5**.
4. Set the evaluation interval to **10 seconds** and the pending period (**For**) to **0 seconds**. Save the rule.
5. Under **Alerting → Alert rules**, verify that it enters **Firing** when memory usage is above 5%. To test if it is not already firing, temporarily use a threshold below the current value and then restore the required test value.
6. After testing, change the threshold to one suitable for your workload (for example, 80%) and save it.

The 5% threshold is for testing and is unusually low for production. This project defines no CPU or disk alerts.

## 9. Verify all services

Run the included verification script:

```bash
sudo ./scripts/verify-services.sh
```

Or check each service and endpoint manually:

```bash
sudo systemctl is-active prometheus
sudo systemctl is-active node_exporter
sudo systemctl is-active grafana-server
curl http://localhost:9090/-/ready
curl http://localhost:9100/metrics
curl http://localhost:3000/api/health
```

Useful service commands:

```bash
sudo systemctl restart prometheus
sudo systemctl restart node_exporter
sudo systemctl restart grafana-server
sudo journalctl -u prometheus -n 50 --no-pager
sudo journalctl -u node_exporter -n 50 --no-pager
sudo journalctl -u grafana-server -n 50 --no-pager
```

## AWS EC2 Security Group ports

Add only the inbound rules you need:

| Port | Purpose | Recommended source |
|---|---|---|
| 22 | SSH administration | Your current public IP (`/32`) |
| 3000 | Grafana web interface | Your current public IP (`/32`) or trusted network |
| 9090 | Prometheus web interface (optional) | Your current public IP (`/32`) or trusted network |
| 9100 | Node Exporter metrics | Do not expose publicly; Prometheus scrapes it locally |

If you do not need to use the Prometheus UI remotely, do not add an inbound rule for port 9090. Grafana contacts Prometheus locally; it does not require public access to port 9090. Never use `0.0.0.0/0` for SSH or metrics ports.

## Troubleshooting

- **A service fails to start:** Check `sudo systemctl status <service> --no-pager` and `sudo journalctl -u <service> -n 50 --no-pager`.
- **Prometheus configuration is invalid:** Run `sudo promtool check config /etc/prometheus/prometheus.yml`, correct the reported YAML issue, then restart Prometheus.
- **A target is DOWN:** Check the service is active, then run `curl http://localhost:9100/metrics` for Node Exporter or `curl http://localhost:9090/-/ready` for Prometheus. Confirm the target address and port in `/etc/prometheus/prometheus.yml`.
- **Grafana cannot connect to Prometheus:** Use `http://localhost:9090` as the data source URL when both services are on this instance. Verify Prometheus is active and ready.
- **A browser cannot open Grafana or Prometheus:** Check the EC2 Security Group and any host firewall. Allow only your trusted IP to ports 3000 or 9090 as needed.
- **Metrics or panels are empty:** Wait at least one scrape interval (15 seconds), confirm both Prometheus targets are **UP**, and check that the dashboard is using the correct Prometheus data source and instance.
- **The installer reports an unsupported architecture:** The release installers support `x86_64` and `aarch64` Ubuntu systems. Check `uname -m`.

## Screenshots

Add your own screenshots after completing setup, for example:

- Prometheus Targets page showing both targets **UP**.
- Grafana **Ubuntu Server Monitoring** dashboard.
- Grafana **High-Memory-Usage** alert rule and its status.

You can store images in a `screenshots/` directory and link them here, for example: `![Dashboard](screenshots/dashboard.png)`.

## Upload this project to GitHub

From the project directory on your computer, initialize and push the repository:

```bash
git init
git add README.md prometheus node-exporter grafana queries scripts
git commit -m "Add Ubuntu Prometheus and Grafana monitoring setup"
git branch -M main
git remote add origin https://github.com/<YOUR-GITHUB-USERNAME>/prometheus-grafana-monitoring.git
git push -u origin main
```

Create an empty GitHub repository named `prometheus-grafana-monitoring` first, and replace the username placeholder. Do not commit credentials, private keys, or EC2-specific IP addresses.

## Optional release version overrides

The Prometheus and Node Exporter installers have default release versions. Set an override before running an installer if you want to use another official release:

```bash
sudo PROMETHEUS_VERSION=3.5.0 ./scripts/install-prometheus.sh
sudo NODE_EXPORTER_VERSION=1.9.1 ./scripts/install-node-exporter.sh
```
