# SOC Project — Docker Deployment

This directory contains the Docker Compose stack and all service configuration files.

**For installation instructions, usage guide, and scripts reference, see the root README:**

👉 [../README.md](../README.md)

---

## Quick Start

```bash
# From this directory (soc-project/)
docker network create soc-net
cp .env.example .env   # then edit .env and change all passwords
bash setup.sh # This will start the stack and run all setup scripts for each service
```

Access Kibana at <http://localhost:5601>
