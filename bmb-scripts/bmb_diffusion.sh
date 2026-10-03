#!/bin/bash
# bmb_diffusion.sh: DiffusionPreprocessing for one BMB subject.
# As Examples/Scripts/DiffusionPreprocessingBatch.sh. Pos = PA, Neg = AP and
# the CombineDataFlag come from hcppipe_conf.txt (bids2hcp.sh sets the flag
# to 2 when the AP and PA series do not share a gradient table, e.g. HARP).
#
# Usage: bmb_diffusion.sh <StudyFolder> <Subject> [--gpu]
#   --gpu: use eddy_cuda (default: eddy_cpu; the image has no GPU set up)

BMB_USAGE="[--gpu]"
source "$(dirname "$(readlink -f "$0")")/bmb_common.sh"
[[ -n ${DiffCombineDataFlag:-} ]] || die "no DiffCombineDataFlag in hcppipe_conf.txt (re-run bids2hcp.sh -f)"
gpu=False
[[ ${3:-} == --gpu ]] && gpu=True

run "$HCPPIPEDIR"/DiffusionPreprocessing/DiffPreprocPipeline.sh \
  --path="$StudyFolder" \
  --session="$Subject" \
  --posData="$(raw_list $DiffPosData)" \
  --negData="$(raw_list $DiffNegData)" \
  --echospacing-seconds="$DiffEchoSpacingSec" \
  --PEdir="$DiffPEdir" \
  --gdcoeffs="$GradientDistortionCoeffs" \
  --combine-data-flag="$DiffCombineDataFlag" \
  --gpu="$gpu"
