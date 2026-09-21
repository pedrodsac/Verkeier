#!/usr/bin/env bash
set -euo pipefail

# Produces the Valhalla graph bundled by the iOS app. The output is deliberately
# not committed: it is a generated OpenStreetMap derivative that is refreshed
# before a release and copied into the app bundle by Xcode.
#
# Prerequisites: Docker, shasum, and Python 3.
# Optional environment variables:
#   DATASET_VERSION       Graph version (default: current UTC date)
#   MINIMUM_APP_BUILD     CFBundleVersion required by the manifest (default: 1)
#   VALHALLA_CORE_COMMIT  Source revision recorded in the manifest (default: 3.6.3)

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_directory="$project_root/Verkéier/Resources"
archive_output="$output_directory/luxembourg-walking-tiles.tar"
manifest_output="$output_directory/luxembourg-walking-manifest.json"
dataset_version="${DATASET_VERSION:-$(date -u +%Y%m%d)}"
minimum_app_build="${MINIMUM_APP_BUILD:-1}"
valhalla_core_commit="${VALHALLA_CORE_COMMIT:-3.6.3}"
valhalla_image="ghcr.io/valhalla/valhalla:3.6.3"
work_directory="$(mktemp -d "${TMPDIR:-/tmp}/verkeier-routing.XXXXXX")"

cleanup() {
  rm -rf "$work_directory"
}
trap cleanup EXIT

command -v docker >/dev/null || { echo "Docker is required." >&2; exit 1; }
command -v shasum >/dev/null || { echo "shasum is required." >&2; exit 1; }
command -v python3 >/dev/null || { echo "Python 3 is required." >&2; exit 1; }

mkdir -p "$output_directory" "$work_directory/tiles"

# The timezone generator downloads and unpacks a source archive in its working
# directory. Keep that scratch work outside /work so it cannot remove the PBF
# or JSON config shared by the subsequent build tools.
docker run --rm -v "$work_directory:/work" -w /tmp "$valhalla_image" \
  sh -c 'valhalla_build_timezones > /work/timezones.sqlite'

# Download inside the same Docker-mounted workspace used by the graph tools.
# This avoids file-sharing cache races between the host and Colima/Docker.
docker run --rm -v "$work_directory:/work" -w /work "$valhalla_image" \
  sh -c 'curl --fail --location --retry 3 --output /work/luxembourg.osm.pbf \
    https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf'

# Keep pedestrian data enabled. No road profile is disabled so the artifact can
# be validated by the exact mobile Valhalla engine linked into the app.
docker run --rm -v "$work_directory:/work" -w /work "$valhalla_image" \
  sh -c '
    valhalla_build_config \
      --mjolnir-tile-dir /work/tiles \
      --mjolnir-tile-extract /work/tiles.tar \
      --mjolnir-timezone /work/timezones.sqlite \
      --mjolnir-admin /work/admins.sqlite \
      --mjolnir-include-pedestrian true > /work/valhalla.json
  '

docker run --rm -v "$work_directory:/work" -v "$output_directory:/output" -w /work "$valhalla_image" \
  bash -c '
    valhalla_build_admins -c /work/valhalla.json /work/luxembourg.osm.pbf
    valhalla_build_tiles -c /work/valhalla.json /work/luxembourg.osm.pbf
    valhalla_build_extract -c /work/valhalla.json
    cp /work/tiles.tar /output/luxembourg-walking-tiles.tar
  '

archive_size="$(stat -f %z "$archive_output")"
archive_sha256="$(shasum -a 256 "$archive_output" | awk '{print $1}')"

ARCHIVE_SIZE="$archive_size" ARCHIVE_SHA256="$archive_sha256" \
DATASET_VERSION="$dataset_version" MINIMUM_APP_BUILD="$minimum_app_build" \
VALHALLA_CORE_COMMIT="$valhalla_core_commit" MANIFEST_OUTPUT="$manifest_output" \
python3 - <<'PY'
import json
import os

manifest = {
    "schemaVersion": 1,
    "region": "luxembourg",
    "datasetVersion": os.environ["DATASET_VERSION"],
    "routingEngine": {
        "valhallaMobileVersion": "0.6.3",
        "valhallaCoreCommit": os.environ["VALHALLA_CORE_COMMIT"],
    },
    "artifact": {
        "url": "file:///bundled/luxembourg-walking-tiles.tar",
        "sizeBytes": int(os.environ["ARCHIVE_SIZE"]),
        "sha256": os.environ["ARCHIVE_SHA256"],
    },
    "minimumAppBuild": int(os.environ["MINIMUM_APP_BUILD"]),
    "source": "OpenStreetMap via Geofabrik; generated for the Verkéier app bundle",
    "formatVersion": 3,
}

with open(os.environ["MANIFEST_OUTPUT"], "w", encoding="utf-8") as file:
    json.dump(manifest, file, indent=2, sort_keys=True)
    file.write("\n")
PY

echo "Wrote $archive_output"
echo "Wrote $manifest_output"
