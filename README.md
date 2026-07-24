# SafeDeployer (sd-deploy)

> A lightweight, zero-dependency orchestration engine for executing zero-downtime Blue-Green deployments on Docker daemons.

⚠️ **License Notice**: This project is published under a **Source-Available License**. You are free to view, download, and use this orchestrator for internal, personal, or educational use. Commercial redistribution, white-labeling, rebranding, or hosting this engine as a competing service is strictly prohibited. See `LICENSE` for details.

---

## 🚀 SafeDeployer Enterprise

Looking for advanced deployment features? The Enterprise version provides:
- **Canary Deployments**: Weight-based traffic splitting (e.g., 90/10 split) inside Nginx, Traefik, and Caddy.
- **Automated Rollbacks**: ACA (Automated Canary Analysis) that monitors error rates/latency and auto-reverts traffic if thresholds are breached.
- **Live UI Dashboard**: Cloud-synced state tracking and real-time deployment progress.
- **Resource Monitoring**: Continuously gathers Docker container stats (CPU, Memory, Network).

Check out [SafeDeployer ](https://safedeployer.com) for more details.

---

## How It Works

SafeDeployer automates the orchestration lifecycle of your application containers on a single Docker host:
1. **Dynamic Port Allocation**: Finds an unused random port on the host machine to bind the new environment container instance to, ensuring no port conflicts.
2. **Container Provisioning**: Pulls and provisions the new environment (the "idle" color, alternating between `blue` and `green`) with the new image tag.
3. **Zero-Downtime Traffic Switching**: Updates your reverse proxy (Nginx, Traefik, or Caddy) to route traffic to the newly spun-up container, then triggers a configuration hot-reload.
4. **Active Teardown**: Gracefully stops and removes the old environment container once the traffic switch succeeds.
5. **State Tracking**: Stores current deployment state (active color and allocated host ports) locally in a state file (defaults to `.safedeployer-state.yaml`).

---

## 📦 Installation & CI/CD Setup Guide

### 1. One-Line Quick Install
Run the standard installer script on your server or local machine:

```bash
curl -fsSL https://safedeployer.com/api/install | bash
```

### 2. How Installation Works (Root vs Non-Root Privileges)

The installer automatically detects system permissions and environment types:

* **Root Users & Passwordless Sudo (`root` or `ubuntu` VPS droplets)**:
  Installs globally to `/usr/local/bin/sd-deploy`. Instantly available system-wide for all users and shells.
* **Non-Root / Non-Interactive Shells (Unprivileged SSH users)**:
  Automatically falls back to installing in `$HOME/.local/bin/sd-deploy` with **zero `sudo` / zero password prompts**.
* **Explicit User-Space Installation**:
  Force installation to user space without root:
  ```bash
  curl -fsSL https://safedeployer.com/api/install | bash -s -- --local
  ```

### 3. Universal CI/CD Deployment Snippet (GitHub Actions / GitLab CI)

Because non-interactive SSH sessions (e.g., `appleboy/ssh-action`) do not execute interactive `.bashrc` files, include `export PATH=$PATH:$HOME/.local/bin:/usr/local/bin` at the beginning of your SSH script.

This snippet works **universally across `root` and non-root server environments**:

```yaml
      - name: Trigger Remote Zero-Downtime Deployment
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ${{ secrets.SERVER_USER }}
          key: ${{ secrets.SERVER_SSH_KEY }}
          script: |
            # 1. Auto-install SafeDeployer if missing on remote server
            if ! command -v sd-deploy &> /dev/null; then
              curl -fsSL https://safedeployer.com/api/install | bash
            fi

            # 2. Pull latest pre-built container image (if using registry)
            REPO_LOWER=$(echo "${{ github.repository }}" | tr '[:upper:]' '[:lower:]')
            docker pull ghcr.io/${REPO_LOWER}:${{ github.sha }}

            # 3. Execute Blue-Green deployment
            cd /var/www/myapp
            sd-deploy up --config docker-compose.yml --tag ${{ github.sha }}
```

---

## Reverse Proxy Architecture: Who Does What?

To make deployments zero-downtime, SafeDeployer integrates with your existing reverse proxy. 

* **What SafeDeployer Does Automatically**: It manages the dynamic backends (upstreams). It writes the dynamic configuration syntax (IPs and ports of the active container) and forces the proxy to reload. **Developers do not need to write upstream server blocks manually.**
* **What Developers Must Do**: Developers configure the public-facing settings—such as domain name mappings, SSL certificates, ports 80/443, and the volume mounts/API endpoints that link the proxy to SafeDeployer.

---

## Configuration & Usage Guides by Provider/Case

SafeDeployer supports two primary integration cases for each reverse proxy:
* **Docker Case**: The reverse proxy runs inside a Docker container. SafeDeployer writes configuration to a shared mount and calls Docker APIs to trigger container reloads.
* **Host Case**: The reverse proxy runs natively on the host system. SafeDeployer writes configuration directly to a host path and invokes host-level command execution (like `nginx -s reload`) to apply changes.

---

### 1. Nginx Integration

#### Case A: Nginx running inside Docker (Docker-to-Docker)
SafeDeployer generates the upstream configuration pointing to the internal Docker DNS name of the container and reloads the Nginx container via Docker exec.

##### Nginx Ingress Configuration (`/etc/nginx/conf.d/default.conf`):
```nginx
# Include the dynamic upstream block generated by SafeDeployer
include /etc/nginx/conf.d/upstream.conf;

server {
    listen 80;
    server_name myapp.local;

    location / {
        proxy_pass http://app_servers; # Matches upstream name in docker-compose.yml
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

##### Complete Configuration (`docker-compose.yml`):
```yaml
version: "3.8"

services:
  web:
    image: my-app:latest
    ports:
      - "3000" # SafeDeployer dynamically overrides this to an available host port at runtime

  nginx-proxy:
    image: nginx:alpine
    container_name: nginx-proxy
    ports:
      - "80:80"
    volumes:
      # Share the generated upstream.conf file with Nginx container
      - ./nginx/upstream.conf:/etc/nginx/conf.d/upstream.conf
      # Mount your static Nginx server config
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro

# SafeDeployer configuration block
x-safedeployer:
  target_service: "web"
  project_name: "my-app"
  router:
    provider: "nginx"
    is_host: false
    upstream_name: "app_servers"
    config_path: "./nginx/upstream.conf" # Path on host, shared with Nginx container
    nginx_container_name: "nginx-proxy"  # Container name of your Nginx container
```

---

#### Case B: Nginx running natively on Host OS (Host-to-Docker)
SafeDeployer writes the host port (`127.0.0.1:<allocated_host_port>`) to the upstream configuration and runs the local `nginx -s reload` command.

##### Nginx Ingress Configuration (`/etc/nginx/sites-available/default`):
```nginx
# Include the upstream block generated directly on the host machine
include /etc/nginx/conf.d/upstream.conf;

server {
    listen 80;
    server_name myapp.local;

    location / {
        proxy_pass http://app_servers;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

##### Complete Configuration (`docker-compose.yml`):
```yaml
version: "3.8"

services:
  web:
    image: my-app:latest
    ports:
      - "3000" # SafeDeployer dynamically overrides this to an available host port at runtime

# SafeDeployer configuration block
x-safedeployer:
  target_service: "web"
  project_name: "my-app"
  router:
    provider: "nginx"
    is_host: true
    upstream_name: "app_servers"
    config_path: "/etc/nginx/conf.d/upstream.conf" # Direct path on host OS
    # nginx_container_name is omitted since reload is run on the host
```

---

### 2. Traefik Integration

#### Case A: Traefik running inside Docker (Docker-to-Docker)
SafeDeployer writes dynamic YAML rules directing traffic to the internal container DNS. Traefik automatically watches this file on disk for instant reloads.

##### Traefik Static Configuration (`traefik.yml`):
```yaml
providers:
  file:
    filename: /etc/traefik/dynamic.yml
    watch: true # Enable hot reloading
```

##### SafeDeployer Configuration (`docker-compose.yml`):
```yaml
x-safedeployer:
  target_service: "web"
  project_name: "my-app"
  router:
    provider: "traefik"
    is_host: false
    upstream_name: "app-backend" # Service name in Traefik configuration
    dynamic_config_path: "./traefik/dynamic.yml" # Shared file path
```

---

#### Case B: Traefik running natively on Host OS (Host-to-Docker)
SafeDeployer writes dynamic YAML rules pointing to `http://127.0.0.1:<allocated_host_port>`.

##### Traefik Static Configuration (`traefik.yml`):
```yaml
providers:
  file:
    filename: /etc/traefik/dynamic.yml
    watch: true
```

##### SafeDeployer Configuration (`docker-compose.yml`):
```yaml
x-safedeployer:
  target_service: "web"
  project_name: "my-app"
  router:
    provider: "traefik"
    is_host: true
    upstream_name: "app-backend"
    dynamic_config_path: "/etc/traefik/dynamic.yml" # Direct host path
```

---

### 3. Caddy Integration

#### Case A: Caddy running inside Docker (Docker-to-Docker)
SafeDeployer submits an HTTP POST request to Caddy's REST API containing the container name and internal port.

##### Initial Caddy Configuration:
Ensure Caddy's API port (`2019`) is exposed and has an initial handler route defined:
```json
{
  "apps": {
    "http": {
      "servers": {
        "srv0": {
          "routes": [
            {
              "handle": [
                {
                  "handler": "reverse_proxy",
                  "upstreams": [] // SafeDeployer will populate this dynamically
                }
              ]
            }
          ]
        }
      }
    }
  }
}
```

##### SafeDeployer Configuration (`docker-compose.yml`):
```yaml
x-safedeployer:
  target_service: "web"
  project_name: "my-app"
  router:
    provider: "caddy"
    is_host: false
    admin_url: "http://localhost:2019" # Exposed API endpoint
```

---

#### Case B: Caddy running natively on Host OS (Host-to-Docker)
SafeDeployer submits an HTTP POST request to Caddy's host REST API pointing to the dial target `127.0.0.1:<allocated_host_port>`.

##### SafeDeployer Configuration (`docker-compose.yml`):
```yaml
x-safedeployer:
  target_service: "web"
  project_name: "my-app"
  router:
    provider: "caddy"
    is_host: true
    admin_url: "http://127.0.0.1:2019" # Localhost admin API port
```

---

## 💎 Enterprise Configuration Guide

If you are using the **Enterprise Binary**, you can unlock automated Canary rollouts and continuous health telemetry by adding the `analytics` and `canary` blocks to your `x-safedeployer` configuration. 

You must also export your API token before running deployments:
```bash
export SAFEDEPLOYER_API_TOKEN="sd_team_abcdef12345"
sd-deploy up --config docker-compose.yml --tag v1.2.0
```

### Complete Enterprise Compose Example:

```yaml
x-safedeployer:
  target_service: "web"
  project_name: "my-app"
  router:
    provider: "nginx"
    is_host: false
    config_path: "./nginx/upstream.conf"
    nginx_container_name: "nginx-proxy"
  
  # 🔒 Enterprise-Only Sections
  analytics:
    enabled: true
    endpoint: "https://api.safedeployer.com/v1/telemetry"
    interval_seconds: 10
  
  canary:
    enabled: true
    steps:
      - percentage: 10
        duration: "5m"
      - percentage: 50
        duration: "10m"
      - percentage: 100
    rollback_rules:
      max_error_rate_5xx: 1.0
      max_latency_ms: 500
      max_cpu_percent: 85.0
```

### Starting the Daemon Server (Process Persistence)

To unlock continuous 24/7 health monitoring and real-time dashboard updates, you should run SafeDeployer as a persistent background daemon on your host machine.

1. Start the daemon with the `--serve` flag to expose the internal IPC API. You can use **any available port** on your machine (e.g., `:7474`, `:8080`, etc.):
```bash
export SAFEDEPLOYER_API_TOKEN="sd_team_abcdef12345"
sd-deploy daemon --serve :7474
```

2. When triggering deployments via CI/CD, pass the exact same `--serve` port you chose above. SafeDeployer will automatically detect the running daemon, connect to it via IPC mode, and stream your deployment state to the dashboard without starting a conflicting process:
```bash
sd-deploy up --config docker-compose.yml --tag v1.2.0 --serve :7474
```

### Webhook Alerts

Enterprise users can receive automated real-time alerts in Slack or Discord whenever a Canary deployment triggers a rollback due to failed health metrics.

Simply export the webhook URL before your deployment:
```bash
export SAFEDEPLOYER_WEBHOOK_URL="https://hooks.slack.com/services/<SLACK_TOKEN>"
```

If the API token is missing or expired, the Enterprise binary will gracefully degrade and perform a standard 100% Blue-Green traffic switch (matching the OSS behavior) to ensure your deployments never fail due to licensing issues.

---

## CLI Usage

Run the deployment using the built binary:

```bash
sd-deploy up --config docker-compose.yml --tag v1.2.0
```

### Flags
* `--config`: Path to your target developer docker-compose file (defaults to `docker-compose.yml`).
* `--tag`: The target image tag to deploy (defaults to `latest`).
* `--state`: Path to the local state file (defaults to `.safedeployer-state.yaml`). This is useful for monorepos deploying multiple services independently.
* `--target`: Override the target service defined in `x-safedeployer` metadata (defaults to the one defined in the compose extension block if not provided).
* `--version`: Print current CLI version information and exit.


### GitHub Actions CI/CD Integration

You can easily wire up `SafeDeployer` in a GitHub Actions workflow to automate your blue-green deployments on every push or tag release.

Here is a complete workflow example that installs SafeDeployer and triggers the deployment on a target server via SSH:

```yaml
name: Deploy Application

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Deploy via SSH
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ${{ secrets.SERVER_USER }}
          key: ${{ secrets.SERVER_SSH_KEY }}
          script: |
            # 1. Update project files on the remote server
            cd /var/www/my-app
            git pull origin main
            
            # 2. Make sure SafeDeployer is installed on the remote machine
            if ! command -v sd-deploy &> /dev/null; then
              curl -fsSL https://raw.githubusercontent.com/IsaiahTek/SafeDeployer-releases/main/install.sh | bash
            fi
            
            # 3. Trigger zero-downtime blue-green deployment
            sd-deploy up --config docker-compose.yml --tag ${{ github.sha }}
```

#### Monorepo Setup (Web and API deployed independently)
For complex monorepo projects, use the `--target` and `--state` flags to orchestrate deployments separately:

```yaml
      - name: Deploy Monorepo Services via SSH
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ${{ secrets.SERVER_USER }}
          key: ${{ secrets.SERVER_SSH_KEY }}
          script: |
            cd /var/www/my-monorepo
            git pull origin main
            
            # Make sure SafeDeployer is installed
            if ! command -v sd-deploy &> /dev/null; then
              curl -fsSL https://raw.githubusercontent.com/IsaiahTek/SafeDeployer-releases/main/install.sh | bash
            fi
            
            # Deploy Web Service
            sd-deploy up --config docker-compose.yml --target web --state .web-state.yaml --tag ${{ github.sha }}
            
            # Deploy API Service
            sd-deploy up --config docker-compose.yml --target api --state .api-state.yaml --tag ${{ github.sha }}
```

---

## 🛠️ Troubleshooting

### Application Unreachable on Backend Port
If your application is unreachable when you try to hit the port defined in your backend service (e.g., `5300`), this is by design! SafeDeployer uses **dynamic port allocation** for the target backend to prevent port collisions between your active Blue and newly-spun Green environments during deployments. 

Because SafeDeployer assigns a random available host port (e.g., `39347`) to the container at runtime, you should **never** attempt to access the backend container directly. Instead, you must always route your traffic through the reverse proxy (e.g., Nginx, Traefik, or Caddy) which has a fixed, static port mapping.

### Changing the Public Port
If you want to expose your application on a custom port (e.g., `8080`) instead of port `80`, **do not** change the backend service port. You only need to change the exposed port mapping on your proxy service in your `docker-compose.yml`:

```yaml
  nginx-proxy:
    image: nginx:alpine
    ports:
      - "8080:80" # Maps host port 8080 to container port 80
```

### Nginx Returning 404 or Welcome Page
If Nginx is successfully running but returning a `404 Not Found` or the default Nginx Welcome page, ensure you have a `default.conf` server block mounted in your proxy container. SafeDeployer dynamically writes the `upstream.conf` file, but it relies on **you** to define the `server` block that catches the traffic and proxies it to that upstream:

```nginx
server {
    listen 80;
    location / {
        proxy_pass http://app_servers; # Must match your upstream_name
        proxy_set_header Host $host;
    }
}
```

---

## Installation

You can install the binary directly to your system's PATH.

### Prerequisites
* A running Docker daemon.
* `sudo` privileges (or write access to the target path) to install the binary to `/usr/local/bin`.

### Automated Installation
Run the following command in your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/IsaiahTek/SafeDeployer-releases/main/install.sh | bash
```

### Manual Installation
Alternatively, compile and install from source:

```bash
# Compile the binary
go build -o sd-deploy cmd/sd-deploy/main.go

# Make executable and move to PATH
chmod +x ./sd-deploy
sudo mv ./sd-deploy /usr/local/bin/

# Verify installation
sd-deploy --version
```
