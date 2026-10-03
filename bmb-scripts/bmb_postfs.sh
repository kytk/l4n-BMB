#!/bin/bash
# bmb_postfs.sh: PostFreeSurfer for one BMB subject.
# As Examples/Scripts/PostFreeSurferPipelineBatch.sh.
#
# Usage: bmb_postfs.sh <StudyFolder> <Subject>

source "$(dirname "$(readlink -f "$0")")/bmb_common.sh"

run "$HCPPIPEDIR"/PostFreeSurfer/PostFreeSurferPipeline.sh \
  --study-folder="$StudyFolder" \
  --session="$Subject" \
  --surfatlasdir="$HCPPIPEDIR_Templates/standard_mesh_atlases" \
  --grayordinatesdir="$HCPPIPEDIR_Templates/91282_Greyordinates" \
  --grayordinatesres=2 \
  --hiresmesh=164 \
  --lowresmesh=32 \
  --subcortgraylabels="$HCPPIPEDIR_Config/FreeSurferSubcorticalLabelTableLut.txt" \
  --freesurferlabels="$HCPPIPEDIR_Config/FreeSurferAllLut.txt" \
  --refmyelinmaps="$HCPPIPEDIR_Templates/standard_mesh_atlases/Conte69.MyelinMap_BC.164k_fs_LR.dscalar.nii" \
  --regname=MSMSulc \
  --use-ind-mean=YES
