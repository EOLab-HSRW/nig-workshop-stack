# NIG Workshop Stack

Automation scripts to deploy multiple NIG workshop instances with Docker Compose.

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
| Node-RED | `http://<IP>:17601/student1/node-red/` |
| Node-RED API | `http://<IP>:17601/student1/node-red/api` |
| Grafana | `http://<IP>:17701/` |

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
