#!/usr/bin/env python3
"""Preprocess a GTFS feed into the compact JSON used by Verkéier.

Input may be either a GTFS zip file or an extracted GTFS directory. The output
keeps stop search and route metadata small enough for app-bundle use.
"""

from __future__ import annotations

import argparse
import csv
import json
import zipfile
from pathlib import Path
from tempfile import TemporaryDirectory


ROUTE_TYPE_TO_MODE = {
    "0": "tram",
    "1": "metro",
    "2": "train",
    "3": "bus",
    "4": "ferry",
    "7": "funicular",
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", help="GTFS .zip or extracted GTFS directory")
    parser.add_argument("output", help="Output compact JSON path")
    parser.add_argument("--max-stops", type=int, default=0, help="Optional cap for fixture generation")
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)

    with TemporaryDirectory() as temp_dir:
        gtfs_dir = extracted_gtfs_dir(input_path, Path(temp_dir))
        stops = read_table(gtfs_dir / "stops.txt")
        routes = read_table(gtfs_dir / "routes.txt")
        stop_times = read_table(gtfs_dir / "stop_times.txt")
        trips = read_table(gtfs_dir / "trips.txt")

        trip_route_ids = {
            row.get("trip_id", ""): row.get("route_id", "")
            for row in trips
            if row.get("trip_id") and row.get("route_id")
        }
        routes_by_id = {
            row.get("route_id", ""): compact_route(row)
            for row in routes
            if row.get("route_id")
        }

        stop_route_ids: dict[str, set[str]] = {}
        for row in stop_times:
            stop_id = row.get("stop_id")
            route_id = trip_route_ids.get(row.get("trip_id", ""))
            if stop_id and route_id:
                stop_route_ids.setdefault(stop_id, set()).add(route_id)

        compact_stops = []
        for row in stops:
            if row.get("location_type") not in ("", "0", None):
                continue
            stop_id = row.get("stop_id")
            stop_name = row.get("stop_name")
            lat = parse_float(row.get("stop_lat"))
            lon = parse_float(row.get("stop_lon"))
            if not stop_id or not stop_name or lat is None or lon is None:
                continue

            route_ids = sorted(stop_route_ids.get(stop_id, set()))
            modes = sorted({routes_by_id[route_id]["mode"] for route_id in route_ids if route_id in routes_by_id})
            compact_stops.append(
                {
                    "id": stop_id,
                    "name": stop_name,
                    "locality": row.get("zone_id") or None,
                    "latitude": lat,
                    "longitude": lon,
                    "modes": modes or ["unknown"],
                    "routeIds": route_ids,
                }
            )
            if args.max_stops and len(compact_stops) >= args.max_stops:
                break

        route_ids_used = {route_id for stop in compact_stops for route_id in stop["routeIds"]}
        compact_routes = [routes_by_id[route_id] for route_id in sorted(route_ids_used) if route_id in routes_by_id]

        output = {
            "source": "Administration des transports publics - GTFS public transport schedules and stops",
            "stops": compact_stops,
            "routes": compact_routes,
        }
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")


def extracted_gtfs_dir(input_path: Path, temp_dir: Path) -> Path:
    if input_path.is_dir():
        return input_path
    if input_path.suffix.lower() != ".zip":
        raise ValueError(f"Expected GTFS .zip or directory: {input_path}")
    with zipfile.ZipFile(input_path) as archive:
        archive.extractall(temp_dir)
    return temp_dir


def read_table(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as file:
        return list(csv.DictReader(file))


def compact_route(row: dict[str, str]) -> dict[str, str]:
    route_type = row.get("route_type", "")
    return {
        "id": row.get("route_id", ""),
        "shortName": row.get("route_short_name") or row.get("route_long_name") or row.get("route_id", ""),
        "longName": row.get("route_long_name") or "",
        "mode": ROUTE_TYPE_TO_MODE.get(route_type, "unknown"),
        "operatorName": row.get("agency_id") or "",
    }


def parse_float(value: str | None) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except ValueError:
        return None


if __name__ == "__main__":
    main()
