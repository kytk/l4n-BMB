#!/bin/bash
# bmb_fmrisurface.sh: fMRISurface for the runs of one BMB subject.
# As Examples/Scripts/GenericfMRISurfaceProcessingPipelineBatch.sh.
#
# Usage: bmb_fmrisurface.sh <StudyFolder> <Subject> [fMRIName]
#   fMRIName: process only this run (e.g. BOLD_REST_1_AP); default all runs

BMB_USAGE="[fMRIName]"
source "$(dirname "$(readlink -f "$0")")/bmb_common.sh"
only=${3:-}

done=0
for fMRIName in $Tasklist; do
  [[ -z $only || $only == "$fMRIName" ]] || continue
  run "$HCPPIPEDIR"/fMRISurface/GenericfMRISurfaceProcessingPipeline.sh \
    --studyfolder="$StudyFolder" \
    --session="$Subject" \
    --fmriname="$fMRIName" \
    --lowresmesh=32 \
    --fmrires=2 \
    --smoothingFWHM=2 \
    --grayordinatesres=2 \
    --regname=MSMSulc
  done=$((done + 1))
done
(( done > 0 )) || die "no run named $only in Tasklist: $Tasklist"
