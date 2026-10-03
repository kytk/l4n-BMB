# bmb_common.sh: sourced by the bmb_*.sh step scripts.
#
# Author: K. Nemoto
# Date: 3 Oct 2026
#
# Each step script runs one HCP Pipelines stage for one subject, with the
# standard (human) pipeline and the parameters of the upstream human batch
# scripts in Examples/Scripts. Inputs and scan parameters come from
# <StudyFolder>/<Subject>/RawData/hcppipe_conf.txt, written by bids2hcp.sh.
#
# Usage of a step script: <script> <StudyFolder> <Subject> [step options]
# BMB_DRYRUN=1 <script> ... prints the pipeline command without running it.
#
# Sets: StudyFolder, Subject, RawData, and everything in hcppipe_conf.txt.

die() { echo "ERROR: $*" >&2; exit 1; }

bmb_usage() {
  echo "Usage: $(basename "$0") <StudyFolder> <Subject> ${BMB_USAGE:-}" >&2
  exit 1
}

[[ $# -ge 2 ]] || bmb_usage
StudyFolder=$(cd "$1" && pwd) || die "no such StudyFolder: $1"
Subject=$2
RawData="$StudyFolder/$Subject/RawData"
[[ -f $RawData/hcppipe_conf.txt ]] || die "$RawData/hcppipe_conf.txt not found (run bids2hcp.sh first)"

# HCP Pipelines environment (FSL, Workbench, MCR, HCPPIPEDIR), as the
# upstream batch scripts do. Sourced before "set -u": it reads unset variables.
source "${BMB_SETUP:-$HOME/projects/HCPpipelines/Examples/Scripts/SetUpHCPPipeline.sh}"
source "$RawData/hcppipe_conf.txt"
set -euo pipefail

[[ $Tasklist != *@* ]] || die "hcppipe_conf.txt with several sessions (@) is not supported"

# raw <name>: full path of a RawData image ("EMPTY" passes through)
raw() {
  [[ $1 == EMPTY ]] && { echo EMPTY; return; }
  [[ -e $RawData/$1.nii.gz ]] || die "$RawData/$1.nii.gz not found"
  echo "$RawData/$1.nii.gz"
}
# raw_list <name> ...: the full paths joined with "@"
raw_list() {
  local n out=()
  for n in "$@"; do out+=("$(raw "$n")"); done
  local IFS=@; echo "${out[*]}"
}
# nth <k> <word list>: the k-th word (1-based)
nth() { echo "$2" | awk -v k="$1" '{ print $k }'; }

# run <command> ...: print the command (one argument per line), then run it.
# With BMB_DRYRUN=1 in the environment, only print it.
run() {
  echo "================================================================"
  printf '%s \\\n' "$1"
  local a; for a in "${@:2}"; do printf '    %s \\\n' "$a"; done
  echo "================================================================"
  [[ ${BMB_DRYRUN:-0} == 1 ]] && return
  "$@"
}
