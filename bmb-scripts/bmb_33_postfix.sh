#!/bin/bash
# bmb_33_postfix.sh: PostFix for one BMB subject, on the multi-run ICA-FIX output
# of bmb_32_icafix.sh (Fmriconcatlist of hcppipe_conf.txt).
# As Examples/Scripts/PostFixBatch.sh (no high-pass filter, reusing the
# high-passed data of multi-run FIX). Writes the ICA classification scenes for
# Workbench, and Signal.txt / Noise.txt in the .ica directory.
#
# Usage: bmb_33_postfix.sh <StudyFolder> <Subject>

source "$(dirname "$(readlink -f "$0")")/bmb_common.sh"

Results="$StudyFolder/$Subject/MNINonLinear/Results"
ConcatName=$(echo "$Fmriconcatlist" | tr -d ' ')
[[ -d $Results/$ConcatName/${ConcatName}_hp0.ica ]] || die "$Results/$ConcatName/${ConcatName}_hp0.ica not found (run bmb_32_icafix.sh first)"

run "$HCPPIPEDIR"/ICAFIX/PostFix.sh \
  --study-folder="$StudyFolder" \
  --subject="$Subject" \
  --fmri-name="$ConcatName" \
  --high-pass=0 \
  --template-scene-dual-screen="$HCPPIPEDIR/ICAFIX/PostFixScenes/ICA_Classification_DualScreenTemplate.scene" \
  --template-scene-single-screen="$HCPPIPEDIR/ICAFIX/PostFixScenes/ICA_Classification_SingleScreenTemplate.scene" \
  --reuse-high-pass=YES \
  --matlab-run-mode=0
