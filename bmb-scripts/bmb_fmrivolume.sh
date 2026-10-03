#!/bin/bash
# bmb_fmrivolume.sh: fMRIVolume for the runs of one BMB subject.
# As Examples/Scripts/GenericfMRIVolumeProcessingPipelineBatch.sh (TOPUP,
# SEBASED bias correction, 2 mm). Per run, the BOLD, SBRef, SE field map pair,
# echo spacing and phase encoding direction come from hcppipe_conf.txt.
#
# Usage: bmb_fmrivolume.sh <StudyFolder> <Subject> [fMRIName]
#   fMRIName: process only this run (e.g. BOLD_REST_1_AP); default all runs

BMB_USAGE="[fMRIName]"
source "$(dirname "$(readlink -f "$0")")/bmb_common.sh"
only=${3:-}

k=0 done=0
for fMRIName in $Tasklist; do
  k=$((k + 1))
  [[ -z $only || $only == "$fMRIName" ]] || continue
  run "$HCPPIPEDIR"/fMRIVolume/GenericfMRIVolumeProcessingPipeline.sh \
    --studyfolder="$StudyFolder" \
    --session="$Subject" \
    --fmriname="$fMRIName" \
    --fmritcs="$(raw "$fMRIName")" \
    --fmriscout="$(raw "$(nth $k "$Taskreflist")")" \
    --SEPhaseNeg="$(raw "$(nth $k "$TopupNegative")")" \
    --SEPhasePos="$(raw "$(nth $k "$TopupPositive")")" \
    --fmapmag=NONE \
    --fmapphase=NONE \
    --fmapcombined=NONE \
    --echospacing="$DwellTime" \
    --echodiff=NONE \
    --unwarpdir="$(nth $k "$PhaseEncodinglist")" \
    --fmrires=2 \
    --dcmethod=TOPUP \
    --gdcoeffs="$GradientDistortionCoeffs" \
    --topupconfig="$HCPPIPEDIR_Config/b02b0.cnf" \
    --biascorrection=SEBASED \
    --mctype=MCFLIRT \
    --matlab-run-mode=0
  done=$((done + 1))
done
(( done > 0 )) || die "no run named $only in Tasklist: $Tasklist"
