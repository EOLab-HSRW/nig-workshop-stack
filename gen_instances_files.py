#!/usr/bin/env python3

import argparse
import csv
import re
import secrets
from pathlib import Path

INSTANCE_COLUMN = "USER_NAME"
REQUIRED_COLUMNS = ("USER_NAME", "USER_PASSWORD", "NODE_RED_PORT", "GRAFANA_PORT", "NODE_RED_EXTRA_PORT")
ENV_KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

PROJECT_RE = re.compile(r"[^a-z0-9_-]+")


def parse_env_file(path: Path) -> dict[str, str]:
    """
    Parse a Compose-compatible .env-style file.

    Supported syntax:
      KEY=value
      export KEY=value
      KEY='literal value'
      KEY="escaped value"
      blank lines
      comments starting with #
    """
    values: dict[str, str] = {}

    if not path.exists():
        return values

    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()

        if not line or line.startswith("#"):
            continue


        if line.startswith("export "):
            line = line[len("export "):].strip()

        if "=" not in line:
            raise ValueError(f"Invalid .env line {line_number} in {path}: {raw_line}")

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()

        if not ENV_KEY_RE.match(key):
            raise ValueError(f"Invalid env key in {path} line {line_number}: {key}")

        values[key] = unquote_env_value(value)

    return values


def unquote_env_value(value: str) -> str:
    if len(value) >= 2:
        if value[0] == value[-1] == '"':
            return bytes(value[1:-1], "utf-8").decode("unicode_escape")
        if value[0] == value[-1] == "'":
            return value[1:-1].replace("\\'", "'").replace("\\\\", "\\")

    return value



def quote_env_value(value: str) -> str:
    """
    Quote values for Docker Compose .env parsing.


    Important: bcrypt hashes contain '$'. Single quotes prevent Compose from
    treating '$2b', '$08', etc. as interpolation variables.
    """
    value = "" if value is None else str(value)

    if value == "":
        return "''"

    safe_unquoted = re.match(r"^[A-Za-z0-9_./:@%+-]+$", value) is not None

    if safe_unquoted and "$" not in value:
        return value


    escaped = (
        value.replace("\\", "\\\\")
        .replace("'", "\\'")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
    )

    return f"'{escaped}'"


def safe_filename(name: str) -> str:
    name = name.strip()

    if not name:
        raise ValueError("USER_NAME cannot be empty")

    return re.sub(r"[^A-Za-z0-9_.-]+", "_", name)


def safe_project_name(name: str) -> str:
    project = PROJECT_RE.sub("-", name.strip().lower()).strip("-_")

    if not project or not re.match(r"^[a-z0-9]", project):
        project = f"instance-{project}" if project else "instance"


    return project



def validate_port(name: str, value: str, row_number: int) -> None:
    try:
        port = int(value)
    except ValueError as exc:
        raise ValueError(f"{name} must be an integer on CSV row {row_number}: {value!r}") from exc

    if not 1 <= port <= 65535:
        raise ValueError(f"{name} must be between 1 and 65535 on CSV row {row_number}: {value}")


def load_csv_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        raise FileNotFoundError(f"CSV file not found: {path}")

    with path.open(newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)

        if not reader.fieldnames:
            raise ValueError("CSV has no headers")

        headers = [header.strip() for header in reader.fieldnames]
        missing = [column for column in REQUIRED_COLUMNS if column not in headers]

        if missing:
            raise ValueError(f"CSV is missing required column(s): {', '.join(missing)}")


        for header in headers:
            if not ENV_KEY_RE.match(header):
                raise ValueError(f"Invalid CSV header/env key: {header}")

        rows: list[dict[str, str]] = []

        seen_users: set[str] = set()
        seen_ports: dict[str, str] = {}

        for row_number, row in enumerate(reader, start=2):
            normalized_row = {

                key.strip(): (value.strip() if value is not None else "")
                for key, value in row.items()
                if key is not None
            }

            user_name = normalized_row.get(INSTANCE_COLUMN, "")

            if not user_name:
                raise ValueError(f"Missing USER_NAME on CSV row {row_number}")


            if user_name in seen_users:
                raise ValueError(f"Duplicate USER_NAME on CSV row {row_number}: {user_name}")

            seen_users.add(user_name)

            for port_column in ("NODE_RED_PORT", "GRAFANA_PORT"):
                port_value = normalized_row.get(port_column, "")

                validate_port(port_column, port_value, row_number)

                if port_value in seen_ports:
                    raise ValueError(
                        f"Duplicate host port {port_value} on CSV row {row_number}: "
                        f"{port_column} conflicts with {seen_ports[port_value]}"
                    )


                seen_ports[port_value] = f"{user_name}.{port_column}"

            rows.append(normalized_row)

    return rows


def apply_derived_defaults(values: dict[str, str], existing_values: dict[str, str]) -> dict[str, str]:
    user_name = values["USER_NAME"]
    user_password = values["USER_PASSWORD"]
    project_name = safe_project_name(user_name)

    values.setdefault("COMPOSE_PROJECT_NAME", project_name)
    values.setdefault("TZ", "Europe/Berlin")
    values.setdefault("INFLUXDB_DB", "db")

    values.setdefault("INFLUXDB_ADMIN_USER", "admin")
    values.setdefault("INFLUXDB_ADMIN_PASSWORD", user_password)
    values.setdefault("INFLUXDB_USER", user_name)
    values.setdefault("INFLUXDB_USER_PASSWORD", user_password)

    # Keep this stable across regenerated files because Node-RED uses it to

    # encrypt credentials stored under /data.
    values["NODE_RED_CREDENTIAL_SECRET"] = existing_values.get(
        "NODE_RED_CREDENTIAL_SECRET",
        values.get("NODE_RED_CREDENTIAL_SECRET", secrets.token_urlsafe(32)),
    )

    return values



def write_env_file(path: Path, values: dict[str, str]) -> None:
    lines = [
        "# Generated file. Edit inventory.csv or globals.env, then rerun deploy.sh.",
        "# NODE_RED_PASSWORD_HASH is injected by deploy.sh using the Node-RED Docker image.",
    ]

    for key in sorted(values):
        if not ENV_KEY_RE.match(key):
            raise ValueError(f"Invalid env key: {key}")

        lines.append(f"{key}={quote_env_value(values[key])}")

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def generate_instance_envs(

    csv_path: Path,
    globals_env_path: Path,
    output_dir: Path,
    keep_empty_values: bool,

) -> None:
    global_values = parse_env_file(globals_env_path)
    rows = load_csv_rows(csv_path)

    output_dir.mkdir(parents=True, exist_ok=True)

    for row in rows:
        instance_name = row[INSTANCE_COLUMN]

        output_path = output_dir / f"{safe_filename(instance_name)}.env"
        existing_values = parse_env_file(output_path)

        env_values = dict(global_values)


        for key, value in row.items():
            if value == "" and not keep_empty_values:
                continue

            # CSV values override globals.env values.
            env_values[key] = value

        env_values = apply_derived_defaults(env_values, existing_values)
        write_env_file(output_path, env_values)

        print(f"Wrote {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate per-user Docker Compose .env files from inventory.csv and globals.env"
    )

    parser.add_argument(
        "csv_positional",
        nargs="?",
        type=Path,

        help="Optional positional CSV file. Kept for compatibility with older deploy.sh usage.",
    )

    parser.add_argument(
        "--csv",
        dest="csv_option",

        type=Path,
        help="CSV file with USER_NAME, USER_PASSWORD, NODE_RED_PORT, GRAFANA_PORT",

    )

    parser.add_argument(
        "--globals",
        type=Path,

        default=Path("globals.env"),
        help="Path to globals.env. Default: globals.env",
    )

    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("instances"),
        help="Output directory. Default: instances",
    )

    parser.add_argument(
        "--keep-empty",
        action="store_true",
        help="Write empty CSV values instead of ignoring them",
    )

    args = parser.parse_args()
    csv_path = args.csv_option or args.csv_positional or Path("inventory.csv")

    generate_instance_envs(
        csv_path=csv_path,
        globals_env_path=args.globals,
        output_dir=args.out_dir,
        keep_empty_values=args.keep_empty,
    )


if __name__ == "__main__":
    main()
