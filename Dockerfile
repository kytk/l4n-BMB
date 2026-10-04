# syntax=docker/dockerfile:1

# Dockerfile for kytk/l4n-bmb
# Author: K. Nemoto
# Date: 3 Oct 2026
# Description: kytk/l4n-hcppipelines plus the tools for the Brain/MINDS Beyond
#              (BMB, "International Brain") dataset. Everything HCP Pipelines
#              needs (FreeSurfer, FSL, MCR, Workbench, HCPpipelines) comes from
#              the base image and is not touched here.
#
# Added on top of the base:
#   - bcil (RIKEN-BCIL): HCP Pipelines QC (hcppipe_qc / hcppipe_gqc), run on
#     the base image's MATLAB Runtime R2022b (MATLAB_MODE=runtime)
#   - R (CRAN, >= 4.3) with ggplot2, qcc, and jq: needed by bcil
#   - boldlag (RIKEN-BCIL/HCPstyle-BOLDLagMappingAndCleaning, Python port)
#     in the base image's /opt/venv
#   - bmb-scripts (this repository): bids2hcp.sh lays out a BMB BIDS session
#     as HCP Pipelines' RawData input with its hcppipe_conf.txt, and the
#     bmb_*.sh step scripts run the human pipelines from that conf

# The base is pinned to a dated tag, so that a rebuild of the base never
# changes BMB results silently. 261003: HCPpipelines v6.0.0, octave removed.
ARG BASE_TAG=261003

# bcil-builder: clone bcil at a fixed commit and drop what the image does not
# need *before* COPY --from (deleting in a later layer does not shrink it).
# The v0.1.1 tag predates the MATLAB Runtime option and the prebuilt
# bin/compiled/ binaries, so a commit is pinned instead of the tag.
FROM ubuntu:22.04 AS bcil-builder
ARG BCIL_COMMIT=c4a5e529b01dcf539efe2239f21f63ee908b19bc
RUN set -ex && \
    apt-get update && \
    apt-get install -y --no-install-recommends git ca-certificates && \
    git clone https://github.com/RIKEN-BCIL/bcil.git /usr/local/bcil && \
    cd /usr/local/bcil && \
    git checkout "$BCIL_COMMIT" && \
    # data/ is kept whole: BMB is human data only, but bcil supports macaque
    # and marmoset as well, and the image keeps that.
    rm -rf .git

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
RUN set -ex && \
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
    rm -rf /var/lib/apt/lists/*

# bcil
COPY --from=bcil-builder /usr/local/bcil/ /usr/local/bcil/
# Replaces upstream's settings.sh, which hard-codes RIKEN's paths
COPY build/bcil/settings.sh /usr/local/bcil/bcilconf/settings.sh

# boldlag into the base image's /opt/venv. /opt/venv belongs to brain, so pip
# runs as brain: files installed as root would keep brain from upgrading
# them later, and a chown afterwards would duplicate the layer.
ARG BOLDLAG_VERSION=v0.2.0
USER brain
RUN set -ex && \
    /opt/venv/bin/pip install --no-cache-dir \
      "boldlag[web] @ git+https://github.com/RIKEN-BCIL/HCPstyle-BOLDLagMappingAndCleaning@${BOLDLAG_VERSION}" && \
    /opt/venv/bin/boldlag -h > /dev/null
USER root

# BMB scripts (BIDS -> HCP Pipelines input, step scripts)
COPY --chmod=755 bmb-scripts/ /usr/local/bmb-scripts/

# PATH for bcil and the BMB scripts, appended to the base image's .bash_aliases
COPY build/home/bash_aliases_bmb /tmp/bash_aliases_bmb
RUN set -ex && \
    for f in /home/brain/.bash_aliases /etc/skel/.bash_aliases /root/.bash_aliases; do \
      cat /tmp/bash_aliases_bmb >> "$f"; \
    done && \
    rm /tmp/bash_aliases_bmb

# The base image's CMD (startup.sh as root, then brain) is inherited.
