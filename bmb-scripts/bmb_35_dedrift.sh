#!/bin/bash
# bmb_35_dedrift.sh: DeDriftAndResample for one BMB subject: removes the group
# drift from the registration of bmb_34_msmall.sh (giving MSMAll), resamples the
# surfaces, maps and fMRI runs with it, and reapplies multi-run ICA-FIX.
# As Examples/Scripts/DeDriftAndResamplePipelineBatch.sh (HCP dedrifting
# spheres, MR FIX on all runs of Tasklist, no high-pass filter, no motion
# regression). No subset of the runs is extracted: all of them are resting
# state. The smoothing is that of bmb_31_fmrisurface.sh (2 mm).
#
# Usage: bmb_35_dedrift.sh <StudyFolder> <Subject>

source "$(dirname "$(readlink -f "$0")")/bmb_common.sh"

# As written by bmb_34_msmall.sh (not its --output-registration-name)
RegName=MSMAll_InitialReg_2_d40_WRN
Native="$StudyFolder/$Subject/MNINonLinear/Native"
for Hemisphere in L R; do
  [[ -e $Native/$Subject.$Hemisphere.sphere.$RegName.native.surf.gii ]] || die "$Native/$Subject.$Hemisphere.sphere.$RegName.native.surf.gii not found (run bmb_34_msmall.sh first)"
done
ConcatName=$(echo "$Fmriconcatlist" | tr -d ' ')
MSMAllTemplates="$HCPPIPEDIR/global/templates/MSMAll"

run "$HCPPIPEDIR"/DeDriftAndResample/DeDriftAndResamplePipeline.sh \
  --path="$StudyFolder" \
  --subject="$Subject" \
  --high-res-mesh=164 \
  --low-res-meshes=32 \
  --registration-name="$RegName" \
  --dedrift-reg-files="$MSMAllTemplates/DeDriftingGroup.L.sphere.DeDriftMSMAll.164k_fs_LR.surf.gii@$MSMAllTemplates/DeDriftingGroup.R.sphere.DeDriftMSMAll.164k_fs_LR.surf.gii" \
  --concat-reg-name=MSMAll \
  --maps=sulc@curvature@corrThickness@thickness \
  --myelin-maps=MyelinMap@SmoothedMyelinMap \
  --multirun-fix-concat-names="$ConcatName" \
  --multirun-fix-names="$(echo $Tasklist | tr ' ' @)" \
  --smoothing-fwhm=2 \
  --high-pass=0 \
  --matlab-run-mode=0 \
  --motion-regression=FALSE \
  --myelin-target-file="$MSMAllTemplates/Q1-Q6_RelatedParcellation210.MyelinMap_BC_MSMAll_2_d41_WRN_DeDrift.32k_fs_LR.dscalar.nii"
