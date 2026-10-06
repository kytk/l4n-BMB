#!/bin/bash
# Builds cuDIMOT NODDI-Watson (Dparallel 1.7e-3) and NODDI_Watson_Dpar1p1
# (Dparallel 1.1e-3) from SPMIC-UoN/cudimot into $PREFIX/bin, and keeps the
# source as built in $PREFIX/src. Runs as root in a stage FROM the base
# image (kytk/l4n-hcppipelines), whose FSL the binaries link against.
#   build.sh <cudimot source dir> <dir with this Makefile> <PREFIX>
# See build_cudimot.md.
set -euo pipefail

SRC=$1
MKDIR=$2
PREFIX=$3
FSLDIR=${FSLDIR:-/usr/local/fsl}
CUDA_VERSION=${CUDA_VERSION:-12.8}
export MAMBA_ROOT_PREFIX=/opt/mamba
mamba=$FSLDIR/bin/micromamba

# CUDA toolkit and a host compiler nvcc supports (FSL's own g++ is 15)
$mamba create -y -q -p /opt/cudaenv -c conda-forge \
  "cuda-version=$CUDA_VERSION" cuda-nvcc cuda-cudart-dev libcurand-dev \
  cuda-cudart-static "gxx_linux-64=14" make patchelf

# FSL headers: the base image's FSL has no include/. Install the very
# package builds the base image has (URLs and md5 from conda-meta), without
# dependencies, into a separate prefix.
pkgs="fsl-armawrap fsl-basisfield fsl-cprob fsl-meshclass fsl-miscmaths
      fsl-newimage fsl-newnifti fsl-newran fsl-utils fsl-warpfns fsl-znzlib
      libboost-headers"
{
  echo "@EXPLICIT"
  for p in $pkgs; do
    f=$(ls "$FSLDIR"/conda-meta/"$p"-[0-9]*.json)
    test "$(echo "$f" | wc -l)" -eq 1
    python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(d["url"] + "#" + d["md5"])' "$f"
  done
} > /tmp/fslhdr.txt
cat /tmp/fslhdr.txt
$mamba create -y -q -p /opt/fslhdr --file /tmp/fslhdr.txt

cd "$SRC"
cp "$MKDIR/Makefile" Makefile

# The Dparallel 1.1e-3 copy of NODDI_Watson. Only diffusivities.h differs;
# the scripts are renamed so that both models can live in one bin/.
m=NODDI_Watson_Dpar1p1
cp -a mymodels/NODDI_Watson "mymodels/$m"
sed -i 's/^#define Dparallel 0\.0017$/#define Dparallel 0.0011/' "mymodels/$m/diffusivities.h"
grep -qx '#define Dparallel 0.0011' "mymodels/$m/diffusivities.h"
mv "mymodels/$m/Pipeline_NODDI_Watson.sh" "mymodels/$m/Pipeline_$m.sh"
mv "mymodels/$m/NODDI_Watson_finish.sh" "mymodels/$m/${m}_finish.sh"
sed -i -e "s/^modelname=NODDI_Watson$/modelname=$m/" \
       -e "s/Pipeline_NODDI_Watson\.sh/Pipeline_$m.sh/" "mymodels/$m/Pipeline_$m.sh"
sed -i "s/NODDI_Watson_finish/${m}_finish/" "mymodels/$m/${m}_finish.sh"
grep -qx "modelname=$m" "mymodels/$m/Pipeline_$m.sh"

mkdir -p "$PREFIX/bin"
PATH=/opt/cudaenv/bin:$PATH make -j"$(nproc)" modelname=NODDI_Watson utils
cp objs/cart2spherical objs/getFanningOrientation objs/initialise_Psi "$PREFIX/bin/"
cp utils/Run_dtifit.sh utils/jobs_wrapper.sh utils/initialise_Bingham.sh "$PREFIX/bin/"
for m in NODDI_Watson NODDI_Watson_Dpar1p1; do
  PATH=/opt/cudaenv/bin:$PATH make -j"$(nproc)" modelname=$m model
  cp objs/$m/$m objs/$m/split_parts_$m objs/$m/merge_parts_$m \
     objs/$m/testFunctions_$m mymodels/$m/*.sh "$PREFIX/bin/"
  cp mymodels/$m/modelpriors "$PREFIX/bin/${m}_priors"
  ./generate_wrapper.sh $m
  ./generate_info.sh $m mymodels/$m
  mv cudimot_$m.sh $m.info "$PREFIX/bin/"
done

# Upstream scripts say #!/bin/sh but use bash syntax (jobs_wrapper.sh:
# ${@:6}), which dash rejects with "Bad substitution"
sed -i '1s|^#!/bin/sh$|#!/bin/bash|' "$PREFIX"/bin/*.sh
if grep -l '^#!/bin/sh$' "$PREFIX"/bin/*.sh; then exit 1; fi
chmod 755 "$PREFIX"/bin/*

# conda's g++ puts /opt/cudaenv/lib into RUNPATH, which the final image does
# not have (testFunctions_* would then pick up jammy's older libstdc++).
# FSL's lib has the libstdc++ (gcc 15) and everything else they link.
# The CUDA runtime is linked statically, so no libcudart may show up.
for f in "$PREFIX"/bin/*; do
  if [ "$(head -c 4 "$f" | tail -c 3)" = ELF ]; then
    /opt/cudaenv/bin/patchelf --set-rpath "$FSLDIR/lib" "$f"
    if ldd "$f" | grep -E 'not found|libcudart|/opt/'; then exit 1; fi
  fi
done
ls -la "$PREFIX/bin"

# The licence (FSL's, LICENSE in the source) allows redistribution without
# financial return only with all original and amended source code included:
# the source as built (this Makefile, the Dpar1p1 model) goes into the image
rm -rf objs .git
cp "$MKDIR/build.sh" .
cp -a "$SRC" "$PREFIX/src"
