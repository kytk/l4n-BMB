# syntax=docker/dockerfile:1

# Dockerfile for kytk/l4n-bmb
# Author: K. Nemoto
# Date: 8 Oct 2026
# Description: kytk/l4n-hcppipelines plus the tools for the Brain/MINDS Beyond
#              (BMB, "International Brain") dataset. Everything HCP Pipelines
#              needs (FreeSurfer, FSL, MCR, Workbench, HCPpipelines) comes from
#              the base image and is not touched here.
#
# Build:
#   docker build --progress=plain -t kytk/l4n-bmb:latest . 2>&1 | tee build.log
# With an Ubuntu mirror for apt (optional; https:// recommended):
#   docker build --progress=plain \
#     --build-arg UBUNTU_MIRROR=https://ftp.riken.jp/Linux/ubuntu \
#     -t kytk/l4n-bmb:latest . 2>&1 | tee build.log
#
# Added on top of the base:
#   - bcil (RIKEN-BCIL): HCP Pipelines QC (hcppipe_qc / hcppipe_gqc), run on
#     the base image's MATLAB Runtime R2022b (MATLAB_MODE=runtime)
#   - R (CRAN, >= 4.3) with ggplot2, qcc, and jq: needed by bcil
#   - boldlag (RIKEN-BCIL/HCPstyle-BOLDLagMappingAndCleaning, Python port)
#     in the base image's /opt/venv
#   - cuDIMOT NODDI-Watson (GPU only), built from source with CUDA 12.8 for
#     RTX 30/40/50 series, in two versions: NODDI_Watson (Dparallel 1.7e-3,
#     white matter) and NODDI_Watson_Dpar1p1 (1.1e-3, grey matter), in
#     /usr/local/cudimot
#   - bmb-scripts (this repository): bids2hcp.sh lays out a BMB BIDS session
#     as HCP Pipelines' RawData input with its hcppipe_conf.txt, and the
#     bmb_*.sh step scripts run the human pipelines from that conf
#   - the pyfix model trained on BMB HARP data, used by bmb_icafix.sh
#
# Optional Ubuntu mirror for apt during the build (build/apt/apt-mirror.sh,
# the same script as in l4n-HCPpipelines), e.g.
#   docker build --build-arg UBUNTU_MIRROR=https://ftp.riken.jp/Linux/ubuntu ...
# Empty (the default) keeps archive.ubuntu.com. https:// keeps HTTP caches on
# the way out of the build (some networks return broken files over HTTP,
# which apt reports as "Hash Sum mismatch"). The final image's sources.list
# is restored, so it ships with archive.ubuntu.com like the base image.

# The base is pinned to a dated tag, so that a rebuild of the base never
# changes BMB results silently. 261004: HCPpipelines v6.0.0, octave removed,
# Qt6 xcb libraries for wb_view.
ARG BASE_TAG=261007

# bcil-builder: clone bcil at a fixed commit and drop what the image does not
# need *before* COPY --from (deleting in a later layer does not shrink it).
# The v0.1.1 tag predates the MATLAB Runtime option and the prebuilt
# bin/compiled/ binaries, so a commit is pinned instead of the tag.
FROM ubuntu:22.04 AS bcil-builder
ARG BCIL_COMMIT=6d6eff6d13a40bbeba00a817d201e983bdad7bed
# The builder is discarded, so the mirror is left in sources.list here.
ARG UBUNTU_MIRROR=
RUN --mount=type=bind,source=build/apt/apt-mirror.sh,target=/tmp/apt-mirror.sh \
    set -ex && \
    sh /tmp/apt-mirror.sh on && \
    apt-get update && \
    apt-get install -y --no-install-recommends git ca-certificates && \
    git clone https://github.com/RIKEN-BCIL/bcil.git /usr/local/bcil && \
    cd /usr/local/bcil && \
    git checkout "$BCIL_COMMIT" && \
    # data/ is kept whole: BMB is human data only, but bcil supports macaque
    # and marmoset as well, and the image keeps that.
    rm -rf .git

# cudimot-builder: cuDIMOT NODDI-Watson built from source (build/cudimot/,
# see build_cudimot.md), against the base image's FSL so that the libraries
# the binaries link are the ones in the final image.
# - Source: SPMIC-UoN/cudimot (University of Nottingham's maintained fork,
#   also what our collaborators build). It has a fix FSL's GitLab copy lacks:
#   WatsonFunctions.h switches to the series approximation below kappa 0.4
#   (was 0.1); in between, the "exact" formula loses precision and the
#   predicted signal is off by up to 29% (kappa 0.2, Dparallel 1.1e-3).
# - The CUDA 10.2 binaries upstream distributes do not run on RTX 50 series
#   ("no kernel image is available"); CUDA 12.8 is the first to target them
#   (sm_120). CUDA (from conda-forge) is used only here: the runtime is
#   linked statically, and the host needs only the NVIDIA driver.
# - Dparallel is a compile-time constant (diffusivities.h), so the 1.1e-3
#   version is a second model, NODDI_Watson_Dpar1p1, with its own scripts
#   (Pipeline_NODDI_Watson_Dpar1p1.sh) and output (<dir>.NODDI_Watson_Dpar1p1/).
# - Watson only: Bingham adds dispersion anisotropy at the cost of two more
#   parameters, and Watson is the NODDI the literature compares to.
# - The source as built goes into /usr/local/cudimot/src (licence condition).
FROM kytk/l4n-hcppipelines:${BASE_TAG} AS cudimot-builder
ARG CUDIMOT_COMMIT=5f9e4ff1bbb8f08de1a7e25f988ed7e0b62072fd
ARG CUDIMOT_CUDA=12.8
USER root
RUN --mount=type=bind,source=build/cudimot,target=/tmp/cudimot-build \
    set -ex && \
    git clone https://github.com/SPMIC-UoN/cudimot.git /tmp/cudimot-src && \
    cd /tmp/cudimot-src && \
    git checkout "$CUDIMOT_COMMIT" && \
    CUDA_VERSION="$CUDIMOT_CUDA" \
      /tmp/cudimot-build/build.sh /tmp/cudimot-src /tmp/cudimot-build /usr/local/cudimot

FROM kytk/l4n-hcppipelines:${BASE_TAG}

# R and jq for bcil.
# - jammy's own R is 4.1.2; bcil needs >= 4.3, so R comes from CRAN's apt repo
# - R packages are binaries from Posit Package Manager at a dated snapshot, so
#   a rebuild installs the same versions (the HTTPUserAgent line is what makes
#   PPM serve Linux binaries instead of source)
# - ggQC is not installed: it was archived on CRAN on 2025-06-13 and is gone
#   from PPM. bcil's QC (hcppipe_gqc) plots with bcil_qcplot_qcc.R (qcc);
#   only the standalone bin/bcil_qcplot.R, which no script calls, needs ggQC
# - the last two Rscript calls make the build fail here, not at QC time, if a
#   package or the PNG device is missing
ARG PPM_SNAPSHOT=2026-10-01
ARG UBUNTU_MIRROR=
RUN --mount=type=bind,source=build/apt/apt-mirror.sh,target=/tmp/apt-mirror.sh \
    set -ex && \
    sh /tmp/apt-mirror.sh on && \
    apt-get update && \
    apt-get install -y --no-install-recommends jq && \
    wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | \
      gpg --dearmor -o /etc/apt/keyrings/cran.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/cran.gpg] https://cloud.r-project.org/bin/linux/ubuntu jammy-cran40/" \
      > /etc/apt/sources.list.d/cran.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends r-base-core && \
    Rscript -e 'options(HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(), paste(getRversion(), R.version["platform"], R.version["arch"], R.version["os"]))); \
                install.packages(c("ggplot2", "qcc"), \
                  repos = "https://packagemanager.posit.co/cran/__linux__/jammy/'"$PPM_SNAPSHOT"'")' && \
    Rscript -e 'for (p in c("ggplot2", "qcc")) library(p, character.only = TRUE)' && \
    Rscript -e 'f <- tempfile(fileext = ".png"); png(f); plot(1); dev.off(); stopifnot(file.size(f) > 0)' && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    sh /tmp/apt-mirror.sh off

# bcil
COPY --from=bcil-builder /usr/local/bcil/ /usr/local/bcil/
# Replaces upstream's settings.sh, which hard-codes RIKEN's paths
COPY build/bcil/settings.sh /usr/local/bcil/bcilconf/settings.sh

# cuDIMOT (NODDI-Watson, Dparallel 1.7e-3 and 1.1e-3). ldd fails the build if
# any binary is missing a library.
COPY --from=cudimot-builder /usr/local/cudimot/ /usr/local/cudimot/
RUN set -ex && \
    for f in NODDI_Watson split_parts_NODDI_Watson merge_parts_NODDI_Watson \
             NODDI_Watson_Dpar1p1 split_parts_NODDI_Watson_Dpar1p1 \
             merge_parts_NODDI_Watson_Dpar1p1 cart2spherical; do \
      if ldd /usr/local/cudimot/bin/$f | grep 'not found'; then exit 1; fi; \
    done

# boldlag into the base image's /opt/venv. /opt/venv belongs to brain, so pip
# runs as brain: files installed as root would keep brain from upgrading
# them later, and a chown afterwards would duplicate the layer.
# numpy is pinned to the base image's version (numpy >= 2.4 does not work on
# macOS), so that boldlag's dependencies cannot upgrade it.
ARG BOLDLAG_VERSION=v0.2.0
USER brain
RUN set -ex && \
    /opt/venv/bin/pip install --no-cache-dir \
      numpy==2.3.5 \
      "boldlag[web] @ git+https://github.com/RIKEN-BCIL/HCPstyle-BOLDLagMappingAndCleaning@${BOLDLAG_VERSION}" && \
    /opt/venv/bin/python -c 'import numpy; assert numpy.__version__ == "2.3.5", numpy.__version__' && \
    /opt/venv/bin/boldlag -h > /dev/null
USER root

# BMB scripts (BIDS -> HCP Pipelines input, step scripts)
COPY --chmod=755 bmb-scripts/ /usr/local/bmb-scripts/

# pyfix model for ICA-FIX, trained on BMB HARP data (pyfix 0.8.0 /
# xgboost 2.0.3; loads and classifies with the base image's FSL pyfix 0.10.0
# / xgboost 3.4.2). The legacy FIX .RData models (HARP, SRPB) are not used.
COPY build/models/HARP.pyfix_model /usr/local/bmb-models/HARP.pyfix_model

# PATH for bcil, cuDIMOT and the BMB scripts, appended to the base image's .bash_aliases
COPY build/home/bash_aliases_bmb /tmp/bash_aliases_bmb
RUN set -ex && \
    for f in /home/brain/.bash_aliases /etc/skel/.bash_aliases /root/.bash_aliases; do \
      cat /tmp/bash_aliases_bmb >> "$f"; \
    done && \
    rm /tmp/bash_aliases_bmb

# The base image's CMD (startup.sh as root, then brain) is inherited.
