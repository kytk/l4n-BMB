#!/bin/bash
# bmb_34_msmall.sh: MSMAll for one BMB subject, on the multi-run ICA-FIX output
# of bmb_32_icafix.sh. All runs of Tasklist are resting state, so all of them are
# used for the registration.
# As Examples/Scripts/MSMAllPipelineBatch.sh (MR FIX, no high-pass filter,
# MSMSulc as the input registration).
# The registration is written as MSMAll_InitialReg_2_d40_WRN (2 iterations,
# ICA dimension 40, method WRN: the defaults of MSMAllPipeline.sh);
# bmb_35_dedrift.sh turns it into MSMAll.
#
# Usage: bmb_34_msmall.sh <StudyFolder> <Subject>

source "$(dirname "$(readlink -f "$0")")/bmb_common.sh"

Results="$StudyFolder/$Subject/MNINonLinear/Results"
ConcatName=$(echo "$Fmriconcatlist" | tr -d ' ')
[[ -e $Results/$ConcatName/${ConcatName}_Atlas_hp0_clean.dtseries.nii ]] || die "$Results/$ConcatName/${ConcatName}_Atlas_hp0_clean.dtseries.nii not found (run bmb_32_icafix.sh first)"

# Name of the variance-normalized concatenation that MSMAllPipeline.sh makes of
# the runs to use; kept apart from the MR FIX concatenation
OutfMRIName=BOLD_REST_CONCAT
[[ $OutfMRIName != "$ConcatName" ]] || die "Fmriconcatlist ($ConcatName) must differ from the MSMAll output name $OutfMRIName"
fMRINames=$(echo $Tasklist | tr ' ' @)
MSMAllTemplates="$HCPPIPEDIR/global/templates/MSMAll"

run "$HCPPIPEDIR"/MSMAll/MSMAllPipeline.sh \
  --path="$StudyFolder" \
  --subject="$Subject" \
  --fmri-names-list= \
  --multirun-fix-names="$fMRINames" \
  --multirun-fix-concat-name="$ConcatName" \
  --multirun-fix-names-to-use="$fMRINames" \
  --output-fmri-name="$OutfMRIName" \
  --high-pass=0 \
  --fmri-proc-string=_Atlas_hp0_clean \
  --msm-all-templates="$MSMAllTemplates" \
  --myelin-target-file="$MSMAllTemplates/Q1-Q6_RelatedParcellation210.MyelinMap_BC_MSMAll_2_d41_WRN_DeDrift.32k_fs_LR.dscalar.nii" \
  --output-registration-name=MSMAll_InitialReg \
  --high-res-mesh=164 \
  --low-res-mesh=32 \
  --input-registration-name=MSMSulc \
  --matlab-run-mode=0
