#!/bin/sh
# Point apt at the Ubuntu mirror in UBUNTU_MIRROR during docker build
# Author: K. Nemoto
# Version: 1.1.0
#
# Usage (inside a RUN that has ARG UBUNTU_MIRROR in scope):
#   sh apt-mirror.sh on    save sources.list, archive.ubuntu.com -> mirror
#   sh apt-mirror.sh off   restore the saved sources.list
#
# Empty UBUNTU_MIRROR (the default): both do nothing, so apt keeps
# archive.ubuntu.com.
#
# Only archive.ubuntu.com is replaced; security.ubuntu.com stays, since
# mirrors can lag behind on security updates.
#
# An https:// mirror keeps HTTP caches on the way (some networks serve stale
# or truncated files over HTTP, which apt reports as "Hash Sum mismatch") out
# of the build. ubuntu:22.04 has no ca-certificates, so when it is missing
# that one package is installed over HTTP from the same mirror first.

set -e

list=/etc/apt/sources.list
saved=/tmp/sources.list.orig

case "$1" in
on)
    [ -n "${UBUNTU_MIRROR}" ] || exit 0
    mirror="${UBUNTU_MIRROR%/}"
    host_path="${mirror#*://}"
    case "${mirror}" in
    http://* | https://*) ;;
    *)
        echo "UBUNTU_MIRROR must start with http:// or https://: ${UBUNTU_MIRROR}" >&2
        exit 1
        ;;
    esac
    cp "${list}" "${saved}"
    sed -i "s|http://archive.ubuntu.com/ubuntu/|http://${host_path}/|g" "${list}"
    case "${mirror}" in
    https://*)
        if [ ! -e /etc/ssl/certs/ca-certificates.crt ]; then
            # Only "jammy main" (about 2 MB of index instead of about 50 MB),
            # so that as little as possible goes over HTTP
            boot=/tmp/apt-mirror-boot.list
            . /etc/os-release
            echo "deb http://${host_path}/ ${VERSION_CODENAME} main" > "${boot}"
            apt-get update -o Dir::Etc::SourceList="${boot}" -o Dir::Etc::SourceParts=-
            apt-get install -y --no-install-recommends \
              -o Dir::Etc::SourceList="${boot}" -o Dir::Etc::SourceParts=- \
              ca-certificates
            rm -f "${boot}"
        fi
        sed -i "s|http://${host_path}/|${mirror}/|g" "${list}"
        ;;
    esac
    echo "apt uses the mirror ${mirror}"
    ;;
off)
    [ -n "${UBUNTU_MIRROR}" ] || exit 0
    mv "${saved}" "${list}"
    ;;
*)
    echo "Usage: $0 on|off" >&2
    exit 2
    ;;
esac
