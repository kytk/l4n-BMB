#!/bin/bash
# bmb_fs.sh: FreeSurfer for one BMB subject.
# As Examples/Scripts/FreeSurferPipelineBatch.sh.
#
# Usage: bmb_fs.sh <StudyFolder> <Subject>

source "$(dirname "$(readlink -f "$0")")/bmb_common.sh"

run "$HCPPIPEDIR"/FreeSurfer/FreeSurferPipeline.sh \
  --session="$Subject" \
  --session-dir="$StudyFolder/$Subject/T1w" \
  --t1w-image="$StudyFolder/$Subject/T1w/T1w_acpc_dc_restore.nii.gz" \
  --t1w-brain="$StudyFolder/$Subject/T1w/T1w_acpc_dc_restore_brain.nii.gz" \
  --t2w-image="$StudyFolder/$Subject/T1w/T2w_acpc_dc_restore.nii.gz"
