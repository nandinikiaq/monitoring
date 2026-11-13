# CPU and memory PromQL queries

Run these expressions in the Prometheus **Graph** page or in a Grafana panel that uses the Prometheus data source. Node Exporter must be running and its Prometheus target must be **UP**.

## CPU Usage Percentage

```promql
100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])))
```

Calculates the average share of CPU time that was not idle over the last five minutes, expressed as a percentage.

## Memory Usage Percentage

```promql
100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
```

Calculates the percentage of total memory that is not currently available to the system.

## Total Memory in GB

```promql
node_memory_MemTotal_bytes / 1024 / 1024 / 1024
```

Shows the host's total memory in gibibytes (bytes divided by 1024 three times).

## Used Memory in GB

```promql
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / 1024 / 1024 / 1024
```

Subtracts available memory from total memory and converts the result to gibibytes.

## Memory Available in GB

```promql
node_memory_MemAvailable_bytes / 1024 / 1024 / 1024
```

Shows the memory available to applications and the operating system in gibibytes.

## Target Status

```promql
up
```

Returns `1` for a scrape target Prometheus can reach (UP) and `0` when a scrape fails (DOWN).
