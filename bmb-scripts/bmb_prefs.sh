#!/bin/bash
# bmb_prefs.sh: PreFreeSurfer for one BMB subject (human, HCP-style data).
# Parameters follow Examples/Scripts/PreFreeSurferPipelineBatch.sh, with
# readout distortion correction by TOPUP (spin-echo field maps).
#
# Usage: bmb_prefs.sh <StudyFolder> <Subject>

source "$(dirname "$(readlink -f "$0")")/bmb_common.sh"

# Templates at the resolution of the T1w (0.7 or 0.8 mm, as provided by HCP)
read -r T1w1 _ <<< "$T1wInputImages"
StrucRes=$(fslval "$(raw "$T1w1")" pixdim1 | awk '{ printf "%.1f", $1 }')
[[ $StrucRes == 0.7 || $StrucRes == 0.8 ]] || die "T1w voxel size ${StrucRes} mm: no MNI152 template at that resolution"
T=$HCPPIPEDIR_Templates

run "$HCPPIPEDIR"/PreFreeSurfer/PreFreeSurferPipeline.sh \
  --path="$StudyFolder" \
  --session="$Subject" \
  --t1="$(raw_list $T1wInputImages)" \
  --t2="$(raw_list $T2wInputImages)" \
  --t1template="$T/MNI152_T1_${StrucRes}mm.nii.gz" \
  --t1templatebrain="$T/MNI152_T1_${StrucRes}mm_brain.nii.gz" \
  --t1template2mm="$T/MNI152_T1_2mm.nii.gz" \
  --t2template="$T/MNI152_T2_${StrucRes}mm.nii.gz" \
  --t2templatebrain="$T/MNI152_T2_${StrucRes}mm_brain.nii.gz" \
  --t2template2mm="$T/MNI152_T2_2mm.nii.gz" \
  --templatemask="$T/MNI152_T1_${StrucRes}mm_brain_mask.nii.gz" \
  --template2mmmask="$T/MNI152_T1_2mm_brain_mask_dil.nii.gz" \
  --brainsize=150 \
  --fnirtconfig="$HCPPIPEDIR_Config/T1_2_MNI152_2mm.cnf" \
  --fmapmag=NONE \
  --fmapphase=NONE \
  --fmapcombined=NONE \
  --echodiff=NONE \
  --SEPhaseNeg="$(raw "$StrucTopupNegative")" \
  --SEPhasePos="$(raw "$StrucTopupPositive")" \
  --seechospacing="$StrucSEDwellTime" \
  --seunwarpdir="$StrucSEUnwarpDir" \
  --t1samplespacing="$T1wSampleSpacing" \
  --t2samplespacing="$T2wSampleSpacing" \
  --unwarpdir="$StrucUnwarpDir" \
  --gdcoeffs="$GradientDistortionCoeffs" \
  --avgrdcmethod=TOPUP \
  --topupconfig="$HCPPIPEDIR_Config/b02b0.cnf"
