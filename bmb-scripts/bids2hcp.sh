#!/bin/bash
# bids2hcp.sh: lay out one BMB (Brain/MINDS Beyond) BIDS session as the
# RawData input of HCP Pipelines, with its hcppipe_conf.txt.
#
# Author: K. Nemoto
# Date: 3 Oct 2026
#
# One (subject, session) becomes one HCP subject, named <sub>_<ses> without
# the BIDS prefixes (sub-9036 + ses-UHISkyrafHARP001 -> 9036_UHISkyrafHARP001).
#
#   <StudyFolder>/<Subject>/RawData/
#     hcppipe_conf.txt      inputs and parameters (see below)
#     bids2hcp_map.tsv      which BIDS file went where, and what was dropped
#     Seriesinfo.csv, Studyinfo.csv
#                           as BCILDCMCONVERT (RIKEN-BCIL) writes them,
#                           rebuilt from the JSON sidecars of all series of
#                           the session (bids2seriesinfo.py)
#     T1w_MPR_1, T2w_SPC_1
#     SEField_<k>_AP, SEField_<k>_PA        k = SE field map block
#     BOLD_REST_<run>_<AP|PA>, BOLD_REST_<run>_<AP|PA>_SBRef
#     DWI_dir<N>_<AP|PA> (+ .bval, .bvec), DWI_dir<N>_<AP|PA>_SBRef
#   (all .nii.gz, each with its JSON sidecar; no NIFTI/ directory and no
#   series numbers in the names, unlike BCILDCMCONVERT's RawData)
#
# hcppipe_conf.txt is what HCPpipelines v6.0.0 Examples/Scripts/*BatchNHP.sh
# (run with SPECIES=Human) and bcil's hcppipe_qc/hcppipe_gqc source. Its file
# names are relative to RawData. Where the two read different names for the
# same thing (dMRI, structural SE field maps), both are written.
#
# Supported: HARP and CRHD sessions (T1w + T2w + spin-echo field maps).
# SRPB-type sessions (no T2w, GRE field map) are refused.
#
# Rules (see LOG.md for the reasons):
#   - T1w/T2w: if the session has prescan-normalized (NORM) and unnormalized
#     reconstructions of the same scan (CRHD), only NORM is used
#   - SE field maps: PHASE images (CRHD) are ignored. Magnitude AP and PA
#     images adjacent in SeriesNumber form a block; a lone one is incomplete
#   - BOLD: gets the SE block acquired last before it. If that block is
#     incomplete, the BOLD run is dropped (no borrowing from another block)
#   - DWI: the i-th AP and the i-th PA series (in SeriesNumber order) form a
#     pair. A series whose volume count is < 2 or does not match its
#     bval/bvec is dropped and becomes EMPTY in the Pos/Neg lists
#   - Gradient nonlinearity coefficients: none

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") -s <sub-ID> -e <ses-ID> -b <BIDS root> -o <StudyFolder> [-n] [-l] [-f]

  -s  subject, e.g. sub-9036 (the "sub-" prefix is optional)
  -e  session, e.g. ses-UHISkyrafHARP001 (the "ses-" prefix is optional)
  -b  BIDS root directory (contains sub-*/)
  -o  HCP StudyFolder; <StudyFolder>/<sub>_<ses>/RawData is created
  -n  dry run: print the mapping and hcppipe_conf.txt, write nothing
  -l  symlink the BIDS files instead of copying them
  -f  remove an existing <StudyFolder>/<sub>_<ses>/RawData first

Example:
  $(basename "$0") -s sub-9036 -e ses-UHISkyrafHARP001 -b ~/data/bids -o ~/data/hcp
EOF
  exit 1
}

die()  { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }

sub="" ses="" bids="" study="" dryrun=0 link=0 force=0
while getopts "s:e:b:o:nlfh" opt; do
  case $opt in
    s) sub=${OPTARG#sub-} ;;
    e) ses=${OPTARG#ses-} ;;
    b) bids=$OPTARG ;;
    o) study=$OPTARG ;;
    n) dryrun=1 ;;
    l) link=1 ;;
    f) force=1 ;;
    *) usage ;;
  esac
done
[[ -n $sub && -n $ses && -n $bids && -n $study ]] || usage

for cmd in jq fslval; do
  command -v "$cmd" > /dev/null || die "$cmd not found"
done

bids=$(cd "$bids" && pwd)
sesdir="$bids/sub-$sub/ses-$ses"
[[ -d $sesdir ]] || die "no such session: $sesdir"

Subject="${sub}_${ses}"
outdir="$study/$Subject/RawData"

# --- helpers -----------------------------------------------------------------

# jval <nii.gz> <key>: a field of the JSON sidecar ("null" if absent)
jval() { jq -r --arg k "$2" '.[$k] // "null" | tostring' "${1%.nii.gz}.json"; }
# jnum <nii.gz> <key>: a numeric field in plain decimal notation. jq 1.6
# (the image's) prints 0.0000071 as 7.1e-06, which bc cannot read.
jnum() {
  local v; v=$(jval "$1" "$2")
  [[ $v != null ]] || die "$(basename "$1"): no $2 in the JSON sidecar"
  LC_ALL=C awk -v v="$v" 'BEGIN { s = sprintf("%.12f", v); sub(/0+$/, "", s); sub(/\.$/, "", s); print s }'
}
series() { jval "$1" SeriesNumber; }
has_imagetype() { jq -e --arg t "$2" '.ImageType | index($t) != null' "${1%.nii.gz}.json" > /dev/null; }
nvols() { fslval "$1" dim4 | tr -d ' '; }
# BIDS PhaseEncodingDirection -> HCP direction label
pe_label() {
  case $(jval "$1" PhaseEncodingDirection) in
    j-) echo AP ;; j) echo PA ;; i-) echo RL ;; i) echo LR ;; *) echo "?" ;;
  esac
}
# HCP direction label -> UnwarpDir, as in the upstream batch scripts
unwarp_dir() {
  case $1 in PA) echo y ;; AP) echo y- ;; RL) echo x ;; LR) echo x- ;; esac
}

# Planned copies: "<BIDS file>|<name in RawData, no extension>|<note>"
plan=()
dropped=()  # "<BIDS file>|<reason>"
add()  { plan+=("$1|$2|${3:-}"); }
drop() { dropped+=("$1|$2"); warn "dropped $(basename "$1"): $2"; }
skip() { dropped+=("$1|$2"); }  # as drop, for the expected cases, no warning

# --- structural --------------------------------------------------------------

# pick_struct <suffix>: sets $picked to the one image to use, NORM preferred
# (not $(...): drop must run in this shell to be recorded)
pick_struct() {
  local all=() norm=() f
  for f in "$sesdir"/anat/*_"$1".nii.gz; do
    [[ -e $f ]] || continue
    all+=("$f")
    has_imagetype "$f" NORM && norm+=("$f")
  done
  local cand=("${all[@]}")
  (( ${#norm[@]} > 0 )) && cand=("${norm[@]}")
  if (( ${#cand[@]} == 0 )); then
    die "no $1 in $sesdir/anat (SRPB-type sessions are not supported)"
  elif (( ${#cand[@]} > 1 )); then
    die "more than one $1 candidate: ${cand[*]##*/}"
  fi
  for f in "${all[@]}"; do
    [[ $f == "${cand[0]}" ]] || drop "$f" "not NORM; NORM reconstruction of the same scan is used"
  done
  picked=${cand[0]}
}

pick_struct T1w; T1w=$picked
pick_struct T2w; T2w=$picked

# The structural images are stored LR/PA/IS (checked 2026-10-03). Their
# readout is then along z, as in the upstream PreFreeSurferPipelineBatch.sh
# (StrucUnwarpDir=z). The PhaseEncodingDirection of the anat JSONs is not used:
# it is missing for T1w and refers to the scanner's voxel order for T2w.
for f in "$T1w" "$T2w"; do
  [[ $(fslval "$f" sform_zorient | tr -d ' ') == Inferior-to-Superior ]] ||
    die "$(basename "$f"): unexpected orientation; check UnwarpDir by hand"
done

# --- spin-echo field maps -----------------------------------------------------

# Magnitude images sorted by SeriesNumber: "<series> <AP|PA> <file>"
mapfile -t se_list < <(
  for f in "$sesdir"/fmap/*_epi.nii.gz; do
    [[ -e $f ]] || continue
    if has_imagetype "$f" PHASE; then
      skip "$f" "PHASE image of a SE field map"
      continue
    fi
    echo "$(series "$f") $(pe_label "$f") $f"
  done | sort -n
)
(( ${#se_list[@]} > 0 )) || die "no spin-echo field maps in $sesdir/fmap"

# Walk the sorted list: AP and PA next to each other make a block; anything
# else is an incomplete block. Blocks are 1-based: block_start[k] is the
# smallest SeriesNumber, block_ap/block_pa are the files ("" if missing).
block_start=() block_ap=() block_pa=()
i=0
while (( i < ${#se_list[@]} )); do
  read -r s1 d1 f1 <<< "${se_list[i]}"
  ap="" pa=""
  [[ $d1 == AP ]] && ap=$f1
  [[ $d1 == PA ]] && pa=$f1
  [[ $d1 == AP || $d1 == PA ]] || die "$(basename "$f1"): unexpected phase encoding"
  if (( i + 1 < ${#se_list[@]} )); then
    read -r _ d2 f2 <<< "${se_list[i+1]}"
    if [[ $d2 != "$d1" ]]; then
      [[ $d2 == AP ]] && ap=$f2
      [[ $d2 == PA ]] && pa=$f2
      i=$((i + 1))
    fi
  fi
  block_start+=("$s1") block_ap+=("$ap") block_pa+=("$pa")
  i=$((i + 1))
done
nblocks=${#block_start[@]}

for (( k = 0; k < nblocks; k++ )); do
  ap=${block_ap[k]} pa=${block_pa[k]}
  if [[ -z $ap || -z $pa ]]; then
    warn "SE field map block $((k + 1)) (series ${block_start[k]}) has no $([[ -z $ap ]] && echo AP || echo PA) partner"
    continue
  fi
  for key in EffectiveEchoSpacing TotalReadoutTime; do
    [[ $(jval "$ap" $key) == "$(jval "$pa" $key)" ]] ||
      die "SE field map block $((k + 1)): $key differs between AP and PA"
  done
done
block_complete() { [[ -n ${block_ap[$1]} && -n ${block_pa[$1]} ]]; }

# Structural images get the complete block nearest to the T1w
t1_series=$(series "$T1w")
struct_block=-1 best=""
for (( k = 0; k < nblocks; k++ )); do
  block_complete $k || continue
  d=$(( block_start[k] - t1_series )); d=${d#-}
  if [[ -z $best ]] || (( d < best )); then best=$d struct_block=$k; fi
done
(( struct_block >= 0 )) || die "no complete SE field map pair for the structural images"

add "$T1w" T1w_MPR_1
add "$T2w" T2w_SPC_1
declare -A block_used=([$struct_block]=1)

# --- rfMRI -------------------------------------------------------------------

fmri_names=()
declare -A fmri_echo fmri_unwarp fmri_block
for bold in "$sesdir"/func/*_bold.nii.gz; do
  [[ -e $bold ]] || continue
  b=$(basename "$bold")
  if [[ ! $b =~ _task-rest_dir-(AP|PA)_run-0*([0-9]+)_bold\.nii\.gz$ ]]; then
    drop "$bold" "not a task-rest_dir-AP/PA run"
    continue
  fi
  dir=${BASH_REMATCH[1]} run=${BASH_REMATCH[2]}
  name="BOLD_REST_${run}_${dir}"
  sbref=${bold%_bold.nii.gz}_sbref.nii.gz
  [[ -e $sbref ]] || die "$b: no SBRef"
  [[ $(pe_label "$bold") == "$dir" ]] || die "$b: PhaseEncodingDirection does not match dir-$dir"

  # The SE block acquired last before this run
  s=$(series "$bold") k=-1
  for (( j = 0; j < nblocks; j++ )); do
    (( block_start[j] < s )) && k=$j
  done
  if (( k < 0 )); then
    drop "$bold" "no SE field map acquired before it"; drop "$sbref" "its BOLD was dropped"
    continue
  fi
  if ! block_complete $k; then
    drop "$bold" "its SE field map block $((k + 1)) has no AP/PA pair"
    drop "$sbref" "its BOLD was dropped"
    continue
  fi
  for key in EffectiveEchoSpacing TotalReadoutTime; do
    [[ $(jval "$bold" $key) == "$(jval "${block_ap[k]}" $key)" ]] ||
      die "$b: $key differs from that of SE field map block $((k + 1))"
  done

  fmri_names+=("$name")
  fmri_echo[$name]=$(jnum "$bold" EffectiveEchoSpacing)
  fmri_unwarp[$name]=$(unwarp_dir "$dir")
  fmri_block[$name]=$((k + 1))
  block_used[$k]=1
  add "$bold"  "$name" "SE block $((k + 1))"
  add "$sbref" "${name}_SBRef"
done
(( ${#fmri_names[@]} > 0 )) || die "no usable rest BOLD runs"
# 1_AP 1_PA 2_AP ... (glob order would put the AP runs first)
mapfile -t fmri_names < <(printf '%s\n' "${fmri_names[@]}" | sort -t_ -k3,3n -k4,4)

# hcppipe_conf.txt has one DwellTime for all runs of a session
fmri_dwell=${fmri_echo[${fmri_names[0]}]}
for n in "${fmri_names[@]}"; do
  [[ ${fmri_echo[$n]} == "$fmri_dwell" ]] || die "EffectiveEchoSpacing differs among the BOLD runs"
done

# SE field maps: the blocks in use, under their block number
for (( k = 0; k < nblocks; k++ )); do
  if [[ -n ${block_used[$k]:-} ]]; then
    add "${block_ap[k]}" "SEField_$((k + 1))_AP" "SE block $((k + 1))"
    add "${block_pa[k]}" "SEField_$((k + 1))_PA" "SE block $((k + 1))"
  else
    for f in "${block_ap[k]}" "${block_pa[k]}"; do
      [[ -n $f ]] && skip "$f" "SE field map block $((k + 1)) is not used"
    done
  fi
done

# --- diffusion ---------------------------------------------------------------

# AP and PA series, each sorted by SeriesNumber
dwi_list() {
  for f in "$sesdir"/dwi/*_dwi.nii.gz; do
    [[ -e $f ]] || continue
    [[ $(pe_label "$f") == "$1" ]] && echo "$(series "$f") $f"
  done | sort -n | cut -d' ' -f2-
}
mapfile -t dwi_ap < <(dwi_list AP)
mapfile -t dwi_pa < <(dwi_list PA)
(( ${#dwi_ap[@]} == ${#dwi_pa[@]} )) ||
  die "${#dwi_ap[@]} AP but ${#dwi_pa[@]} PA diffusion series; cannot pair them"

dwi_echo=""
for f in "${dwi_ap[@]}" "${dwi_pa[@]}"; do
  e=$(jnum "$f" EffectiveEchoSpacing)
  [[ -z $dwi_echo || $dwi_echo == "$e" ]] || die "EffectiveEchoSpacing differs among the diffusion series"
  dwi_echo=$e
done

# dwi_entry <file> <AP|PA>: adds the series and sets $entry to its name in
# the Pos/Neg list (EMPTY if dropped)
dwi_entry() {
  local f=$1 dir=$2 b nv nb nc
  b=$(basename "$f")
  [[ $b =~ _acq-dir([0-9]+)_ ]] || die "$b: no acq-dir<N> label"
  local name="DWI_dir${BASH_REMATCH[1]}_${dir}"
  nv=$(nvols "$f")
  nb=$(wc -w < "${f%.nii.gz}.bval")
  nc=$(head -1 "${f%.nii.gz}.bvec" | wc -w)
  if (( nv < 2 )) || [[ $nb != "$nv" || $nc != "$nv" ]]; then
    drop "$f" "$nv volumes, $nb bvals, $nc bvecs"
    entry=EMPTY
    return
  fi
  local sbref=${f%_dwi.nii.gz}_sbref.nii.gz
  [[ -e $sbref ]] && add "$sbref" "${name}_SBRef"
  add "$f" "$name"
  entry=$name
}
# dwi_table <dwi.nii.gz>: one line per volume, "b x y z"
dwi_table() {
  awk 'NR == FNR { for (i = 1; i <= NF; i++) b[i] = $i; n = NF; next }
       { for (i = 1; i <= NF; i++) v[FNR, i] = $i }
       END { for (i = 1; i <= n; i++) print b[i], v[1, i], v[2, i], v[3, i] }' \
    "${1%.nii.gz}.bval" "${1%.nii.gz}.bvec"
}
# same_table <a> <b>: true if volume by volume the b-values agree within 50
# and the directions within |cos| > 0.99 (sign does not matter)
same_table() {
  [[ $(wc -w < "${1%.nii.gz}.bval") == "$(wc -w < "${2%.nii.gz}.bval")" ]] || return 1
  paste -d' ' <(dwi_table "$1") <(dwi_table "$2") | awk '
    { db = $1 - $5; if (db < 0) db = -db
      c = $2 * $6 + $3 * $7 + $4 * $8; if (c < 0) c = -c
      if (db > 50 || ($1 > 50 && c < 0.99)) bad = 1 }
    END { exit bad }'
}

# CombineDataFlag of DiffPreprocPipeline: 1 (combine AP/PA pairs by least
# squares) only if every pair is complete and has the same gradient table;
# otherwise 2 (keep all volumes uncombined). HARP's dir68 AP / dir69 PA are
# different direction sets, so HARP gets 2.
dwi_pos=() dwi_neg=() dwi_combine=1
for (( i = 0; i < ${#dwi_ap[@]}; i++ )); do
  dwi_entry "${dwi_pa[i]}" PA; dwi_pos+=("$entry")
  dwi_entry "${dwi_ap[i]}" AP; dwi_neg+=("$entry")
  if [[ ${dwi_pos[i]} == EMPTY || ${dwi_neg[i]} == EMPTY ]] || ! same_table "${dwi_pa[i]}" "${dwi_ap[i]}"; then
    dwi_combine=2
  fi
done
# ms <seconds>: the same value in milliseconds, plain decimal
ms() { LC_ALL=C awk -v v="$1" 'BEGIN { s = sprintf("%.12f", v * 1000); sub(/0+$/, "", s); sub(/\.$/, "", s); print s }'; }
# per_run <sbref|unwarp|se_ap|se_pa>: one word per run, in Tasklist order
per_run() {
  local n out=()
  for n in "${fmri_names[@]}"; do
    case $1 in
      sbref)  out+=("${n}_SBRef") ;;
      unwarp) out+=("${fmri_unwarp[$n]}") ;;
      se_ap)  out+=("SEField_${fmri_block[$n]}_AP") ;;
      se_pa)  out+=("SEField_${fmri_block[$n]}_PA") ;;
    esac
  done
  echo "${out[*]}"
}

# --- hcppipe_conf.txt ---------------------------------------------------------

conf() {
  local sb=$((struct_block + 1))
  cat <<EOF
## hcppipe_conf.txt for ${Subject}
## Generated by bids2hcp.sh on $(date +%F) from
##   ${sesdir}
## File names are relative to \${StudyFolder}/\${Subject}/RawData.
## Read by HCPpipelines v6.0.0 Examples/Scripts/*BatchNHP.sh (SPECIES=Human)
## and by bcil hcppipe_qc / hcppipe_gqc. Scanner: $(jval "$T1w" ManufacturersModelName)

## Structural MRI
T1wInputImages="T1w_MPR_1"
T2wInputImages="T2w_SPC_1"
T1wSampleSpacing="$(jnum "$T1w" DwellTime)"			# readout dwell time [sec]
T2wSampleSpacing="$(jnum "$T2w" DwellTime)"			# readout dwell time [sec]
StrucUnwarpDir=z						# readout along z (FH) for the sagittal T1w/T2w
StrucTopupNegative="SEField_${sb}_AP"			# SE field map block nearest to the T1w
StrucTopupPositive="SEField_${sb}_PA"
StrucSEDwellTime="$(jnum "${block_ap[struct_block]}" EffectiveEchoSpacing)"			# echo spacing of the SE field map [sec]
StrucSEUnwarpDir="y"

## Gradient Nonlinearity Correction: none.
# "Gradient" is left unset on purpose: the fMRI batch looks for
# coeff_\${Gradient}.grad whenever it is not empty.
GradientDistortionCoeffs="NONE"

## Resting-state fMRI (one session, so no "@")
Tasklist="${fmri_names[*]}"
Taskreflist="$(per_run sbref)"
PhaseEncodinglist="$(per_run unwarp)"	# PA:y, AP:y-
Fmriconcatlist=BOLD_CONCAT

## TopUp for fMRI: the SE field map block of each run
TopupNegative="$(per_run se_ap)"
TopupPositive="$(per_run se_pa)"
DwellTime="${fmri_dwell}"			# echo spacing of the BOLD runs [sec]

## Diffusion MRI (Pos = PA, Neg = AP; EMPTY = a dropped series)
DiffPosData="${dwi_pos[*]}"
DiffNegData="${dwi_neg[*]}"
DiffEchoSpacingSec="${dwi_echo}"		# [sec]
DiffPEdir=2					# 1 for LR/RL, 2 for AP/PA
DiffCombineDataFlag=${dwi_combine}				# 1: AP/PA pairs share the gradient table (combined); 2: not (all volumes kept)
# the same, under the names bcil's hcppipe_qc reads
DmrilistPositive="${dwi_pos[*]}"
DmrilistNegative="${dwi_neg[*]}"
EchoSpacing="$(ms "$dwi_echo")"			# [msec]
PEdir=2
EOF
}

# Every image of the session, for Seriesinfo.csv; target_of: where the used
# ones go in RawData
images=("$sesdir"/*/*.nii.gz)
declare -A target_of
for e in "${plan[@]}"; do
  IFS='|' read -r src dst _ <<< "$e"
  target_of[$src]=$dst
done

maptsv() {
  printf 'status\trawdata_file\tbids_file\tnote\n'
  local e src dst note
  for e in "${plan[@]}"; do
    IFS='|' read -r src dst note <<< "$e"
    printf 'used\t%s\t%s\t%s\n' "${target_of[$src]}" "${src#"$bids"/}" "$note"
  done
  declare -A listed=()
  for e in "${plan[@]}" "${dropped[@]}"; do listed[${e%%|*}]=1; done
  for e in "${dropped[@]}"; do
    IFS='|' read -r src note <<< "$e"
    printf 'dropped\t\t%s\t%s\n' "${src#"$bids"/}" "$note"
  done
  # Images not used by HCP Pipelines (MEGRE etc.): listed in Seriesinfo.csv only
  local f
  for f in "${images[@]}"; do
    [[ -n ${listed[$f]:-} ]] || printf 'unused\t\t%s\tnot copied\n' "${f#"$bids"/}"
  done
}

# --- write -------------------------------------------------------------------

if (( dryrun )); then
  echo "== $outdir (dry run)"
  maptsv | column -t -s $'\t'
  echo
  conf
  exit 0
fi

if [[ -e $outdir ]]; then
  (( force )) || die "$outdir exists (use -f to replace it)"
  rm -rf "${study:?}/${Subject:?}/RawData"
fi
mkdir -p "$outdir"

# The used images with their JSON sidecars, and bval/bvec for DWI
for e in "${plan[@]}"; do
  IFS='|' read -r src dst _ <<< "$e"
  for ext in .nii.gz .json .bval .bvec; do
    [[ -e ${src%.nii.gz}$ext ]] || continue
    if (( link )); then
      ln -s "${src%.nii.gz}$ext" "$outdir/$dst$ext"
    else
      cp "${src%.nii.gz}$ext" "$outdir/$dst$ext"
    fi
  done
done
conf > "$outdir/hcppipe_conf.txt"
maptsv > "$outdir/bids2hcp_map.tsv"

# Seriesinfo.csv / Studyinfo.csv from every image of the session (MEGRE and
# dropped series included, as BCILDCMCONVERT lists every series). NIFTI in
# RawData is the path of the copy in RawData (NONE for unused series)
py=${BMB_PYTHON:-/opt/venv/bin/python}
[[ -x $py ]] || py=python3
age=$(awk -F'\t' -v s="$ses" '
  NR == 1 { for (i = 1; i <= NF; i++) { if ($i == "session_id") c = i; if ($i == "age") a = i }; next }
  c && a && ($c == s || $c == "ses-" s) { print $a }' "$bids/sub-$sub/sub-${sub}_sessions.tsv" 2>/dev/null || true)
si_args=()
[[ -n $age ]] && si_args+=(--age "$age")
for f in "${!target_of[@]}"; do
  si_args+=(--rawdata "$f=$outdir/${target_of[$f]}.nii.gz")
done
"$py" "$(dirname "$(readlink -f "$0")")/bids2seriesinfo.py" "${si_args[@]}" \
  "$outdir" "${images[@]}" || die "bids2seriesinfo.py failed"

echo "Done: $outdir"
echo "  fMRI: ${fmri_names[*]}"
echo "  dropped: ${#dropped[@]} file(s); see bids2hcp_map.tsv"
echo "  Seriesinfo.csv: $(( $(wc -l < "$outdir/Seriesinfo.csv") - 1 )) series"
