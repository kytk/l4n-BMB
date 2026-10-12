#!/bin/bash
# bmb_36_fmristats.sh: fMRIStats (mTSNR, fCNR, percent BOLD) for one BMB subject,
# on the MSMAll-registered, ICA-FIX cleaned concatenation of bmb_35_dedrift.sh.
# As Examples/Scripts/fMRIstatsBatch.sh (surface and volume, with the cleanup
# effects metrics), but
#   - with spatial ICA only (--ica-mode=sICA, data "_clean"): temporal ICA is
#     not run on BMB data
#   - with Octave (--matlab-run-mode=2), not the compiled MATLAB: the compiled
#     fMRIStats of v6.0.0 lacks FSL's read_avw/save_avw ("Unrecognized function
#     or variable 'read_avw'" with --process-volume=TRUE), and fMRIStats.sh
#     looks for it in Compiled_fMRIStats/, not scripts/Compiled_fMRIStats/.
#     The image's octaverc puts FSL's etc/matlab and an endsWith for Octave 6
#     on the path; HCPCIFTIRWDIR comes from SetUpHCPPipeline.sh
# Needs the Signal.txt and melodic_mix.sdseries.nii of bmb_33_postfix.sh.
#
# Usage: bmb_36_fmristats.sh <StudyFolder> <Subject>

source "$(dirname "$(readlink -f "$0")")/bmb_common.sh"

command -v octave-cli > /dev/null || die "octave-cli not found (an l4n-bmb image older than Octave's addition?)"

# fMRIStats.sh skips a concatenation with missing inputs and exits 0
Results="$StudyFolder/$Subject/MNINonLinear/Results"
ConcatName=$(echo "$Fmriconcatlist" | tr -d ' ')
[[ -e $Results/$ConcatName/${ConcatName}_Atlas_MSMAll_hp0_clean.dtseries.nii ]] || die "$Results/$ConcatName/${ConcatName}_Atlas_MSMAll_hp0_clean.dtseries.nii not found (run bmb_35_dedrift.sh first)"
ICAFolder="$Results/$ConcatName/${ConcatName}_hp0.ica"
[[ -e $ICAFolder/Signal.txt && -e $ICAFolder/filtered_func_data.ica/melodic_mix.sdseries.nii ]] || die "no Signal.txt or filtered_func_data.ica/melodic_mix.sdseries.nii in $ICAFolder (run bmb_33_postfix.sh first)"

run "$HCPPIPEDIR/fMRIStats/fMRIStats.sh" \
  --study-folder="$StudyFolder" \
  --subject="$Subject" \
  --concat-names="$ConcatName" \
  --high-pass=0 \
  --proc-string=_clean \
  --reg-name=MSMAll \
  --process-volume=TRUE \
  --cleanup-effects=TRUE \
  --ica-mode=sICA \
  --matlab-run-mode=2
