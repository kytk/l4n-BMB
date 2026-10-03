#!/bin/bash
# bmb_icafix.sh: multi-run ICA-FIX for one BMB subject: all runs of Tasklist
# concatenated as Fmriconcatlist (hcppipe_conf.txt).
# As Examples/Scripts/IcaFixProcessingBatch.sh (pyfix, no high-pass filter,
# no motion regression, threshold 10).
#
# Usage: bmb_icafix.sh <StudyFolder> <Subject>

source "$(dirname "$(readlink -f "$0")")/bmb_common.sh"

Results="$StudyFolder/$Subject/MNINonLinear/Results"
inputs=()
for fMRIName in $Tasklist; do
  [[ -e $Results/$fMRIName/$fMRIName.nii.gz ]] || die "$Results/$fMRIName/$fMRIName.nii.gz not found (run bmb_fmrivolume.sh first)"
  inputs+=("$Results/$fMRIName/$fMRIName")
done
ConcatName=$(echo "$Fmriconcatlist" | tr -d ' ')

run "$HCPPIPEDIR"/ICAFIX/hcp_fix_multi_run \
  --fmri-names="$(IFS=@; echo "${inputs[*]}")" \
  --high-pass=0 \
  --concat-fmri-name="$Results/$ConcatName/$ConcatName" \
  --motion-regression=FALSE \
  --training-file=HCP_Style_Single_Multirun_Dedrift.RData \
  --fix-threshold=10 \
  --delete-intermediates=FALSE \
  --processing-mode=HCPStyleData \
  --ica-method=MELODIC \
  --matlab-run-mode=0
