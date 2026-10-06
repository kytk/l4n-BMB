# bcil settings for kytk/l4n-bmb (replaces upstream bcilconf/settings.sh,
# whose paths point to RIKEN's machines). The paths are those of the base
# image kytk/l4n-hcppipelines.

export CARET7DIR=/usr/local/workbench/bin_linux64
export HCPPIPEDIR=${HOME}/projects/HCPpipelines
export FREESURFER_HOME=/usr/local/freesurfer/6.0.1
export FSLDIR=/usr/local/fsl
# DVARS (https://github.com/asoroosh/DVARS) is only an addpath for MATLAB
# mode; the compiled bcil_motiongreyplot already contains it. hcppipe_qc runs
# with "set -u", so it must be defined (empty is fine) or "-f" stops.
export DVARSDIR=${DVARSDIR:-}

# --- MATLAB execution mode for the QC plotting steps -------------------------
# The image has no MATLAB, only the MATLAB Runtime R2022b, which matches the
# prebuilt binaries in bin/compiled/ (R2022b = v9.13).
export MATLAB_MODE=${MATLAB_MODE:-runtime}
export MCRROOT=${MCRROOT:-/usr/local/MATLAB/MCR/R2022b}
