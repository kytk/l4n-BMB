#!/bin/bash
# bmb_icafix.sh: multi-run ICA-FIX for one BMB subject: all runs of Tasklist
# concatenated as Fmriconcatlist (hcppipe_conf.txt).
# As Examples/Scripts/IcaFixProcessingBatch.sh (pyfix, no high-pass filter,
# no motion regression, threshold 10).
# --training-file is the pyfix model trained on BMB HARP data, given as an
# absolute path: hcp_fix_multi_run (v6.0.0) prefixes a relative name with
# $(pwd)/, and passes a *.pyfix_model on to fix -c as is (no conversion).
#
# Usage: bmb_icafix.sh <StudyFolder> <Subject>

source "$(dirname "$(readlink -f "$0")")/bmb_common.sh"

FixModel=/usr/local/bmb-models/HARP.pyfix_model
[[ -f $FixModel ]] || die "$FixModel not found"

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
  --training-file="$FixModel" \
  --fix-threshold=10 \
  --delete-intermediates=FALSE \
  --processing-mode=HCPStyleData \
  --ica-method=MELODIC \
  --matlab-run-mode=0
