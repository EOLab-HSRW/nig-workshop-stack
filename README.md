# NIG Workshop Stack

Automation scripts to deploy multiple NIG workshop instances with Docker Compose.

> [!WARNING]
> **Workshop / Local Use Only**
>
> This stack is intended for experimental local workshop deployments only.
> It is provided **AS-IS** and by no means should be used in production environments without a full security review, hardening, and operational validation.

Each user gets a separate stack with:

- [Node-RED](https://nodered.org/)
- [InfluxDB](https://www.influxdata.com/)
- [Grafana](https://grafana.com/)

## Requirements

- Docker
- Docker Compose
- Python 3

## Setup

Clone the repository:

```bash
git clone https://github.com/EOLab-HSRW/nig-workshop-stack.git
cd nig-workshop-stack
```


Edit `inventory.csv` and add one row per workshop user:

```csv
USER_NAME,USER_PASSWORD,NODE_RED_PORT,NODE_RED_EXTRA_PORT,GRAFANA_PORT
student1,dump_password,17601,1881,17701
student2,dump_password,17602,1882,17702
```

**Make sure every port is unique**.


Edit `globals.env` only if you need to change Docker images or shared defaults.

## Commands


Deploy all users:

```bash
./deploy.sh up
```

Deploy one user:

```bash
./deploy.sh up student1
```

Stop all users:

```bash
./deploy.sh down
```

Stop one user:

```bash
./deploy.sh down student1
```

Generate instance `.env` files only:


```bash
./deploy.sh generate
```


## Access

Using the example `inventory.csv`:

| Service | URL |
|---|---|
| Node-RED | `http://<IP>:<NODE_RED_PORT>/<USER_NAME>/node-red/` |
| Node-RED API | `http://<IP>:<NODE_RED_PORT>/<USER_NAME>/node-red/api` |
| Node-RED extra exposed port | `http://<IP>:<NODE_RED_EXTRA_PORT>` |
| Grafana | `http://<IP>:<GRAFANA_PORT>/<USER_NAME>/grafana` |

Login with the values from `inventory.csv`:

```text
username: USER_NAME
password: USER_PASSWORD
```

## Notes

- Generated instance files are stored in `instances/`.
- The current `inventory.csv` is just a place holder and we roll-up new info per workshop-basis.
- Do not commit `instances/`.
- Use `./deploy.sh up` instead of running `docker compose` directly, because the script generates the Node-RED password hash.

## Acknowledgement

This repo mirrors the stack and workflow by [Jan](https://github.com/orgs/EOLab-HSRW/people/SirSundays) in [Aufbau & Installation - EOLab Wiki](https://wiki.eolab.de/doku.php?id=user:jan001:nigdocu:aufbau).
