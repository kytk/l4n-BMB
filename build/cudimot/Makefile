# Builds one cuDIMOT model (make modelname=<name>) against the base image's
# FSL 6.0.7 libraries, with CUDA from a conda env. Replaces upstream's
# Makefile: it includes FSL's default.mk, but builds only up to sm_86, links
# libcudart dynamically and needs FSLDEVDIR. The structure (which objects go
# where) follows upstream's.
# See build_cudimot.md.

FSLDIR    ?= /usr/local/fsl
CUDA_HOME ?= /opt/cudaenv
# FSL headers: the base image ships FSL without include/
FSLINC    ?= /opt/fslhdr/include
OBJDIR    ?= objs/$(modelname)

# RTX 30 (sm_86), 40 (sm_89) and 50 (sm_120) series. No PTX: with separate
# compilation (-dc, -dlink) the device link keeps only SASS, so a GPU of a
# newer major architecture needs a rebuild with its sm_ added here.
GENCODE ?= -gencode arch=compute_86,code=sm_86 \
           -gencode arch=compute_89,code=sm_89 \
           -gencode arch=compute_120,code=sm_120

ifndef modelname
$(error modelname has not been set)
endif

NVCC = $(CUDA_HOME)/bin/nvcc
CXX  = $(CUDA_HOME)/bin/x86_64-conda-linux-gnu-g++

MODELPATH = mymodels/$(modelname)
TYPE := $(shell grep MyType $(MODELPATH)/modelparameters.h | cut -f 2 -d ' ')
ifeq ($(TYPE),float)
  MAX_REGISTERS = -maxrregcount 64
else
  MAX_REGISTERS = -maxrregcount 128
endif

# armawrap/ too: SPMIC's Model.h includes "newmat.h" bare
INC       = -I. -I$(MODELPATH) -isystem $(FSLINC) -isystem $(FSLINC)/armawrap
CXXFLAGS  = -std=c++17 -O3 -fPIC -pthread $(INC)
NVCCFLAGS = $(GENCODE) -ccbin $(CXX) -std=c++17 -O3 -DARMA_ALLOW_FAKE_GCC \
            -Xcompiler -pthread $(INC)
# FSL's lib comes first, so that its (newer) libstdc++ is the one linked
LDFLAGS   = -L$(FSLDIR)/lib -Wl,-rpath,$(FSLDIR)/lib -Wl,-rpath-link,$(FSLDIR)/lib
NVLDFLAGS = $(GENCODE) -ccbin $(CXX) -L$(FSLDIR)/lib \
            -Xlinker -rpath,$(FSLDIR)/lib -Xlinker -rpath-link,$(FSLDIR)/lib \
            --cudart=static --cudadevrt=static
LIBS = -lfsl-warpfns -lfsl-basisfield -lfsl-meshclass -lfsl-newimage \
       -lfsl-miscmaths -lfsl-utils -lfsl-newran -lfsl-NewNifti -lfsl-znz \
       -lfsl-cprob -lboost_filesystem -lboost_system -llapack -lblas -lz -lm

CUDAOBJS = $(addprefix $(OBJDIR)/, modelparameters.o init_gpu.o dMRI_Data.o \
             Model.o Parameters.o GridSearch.o Levenberg_Marquardt.o MCMC.o \
             BIC_AIC.o getPredictedSignal.o)
DLINK    = $(OBJDIR)/link_cudimot_gpu.o

MODEL_X  = $(OBJDIR)/$(modelname) $(OBJDIR)/split_parts_$(modelname) \
           $(OBJDIR)/merge_parts_$(modelname) $(OBJDIR)/testFunctions_$(modelname)
# Model-independent helpers, built once: make modelname=<any> utils
UTILS_X  = objs/cart2spherical objs/getFanningOrientation objs/initialise_Psi

.PHONY: model utils
model: $(MODEL_X)
utils: $(UTILS_X)

$(OBJDIR):
	mkdir -p $@

$(OBJDIR)/%.o: %.cu | $(OBJDIR)
	$(NVCC) $(NVCCFLAGS) $(MAX_REGISTERS) -dc -o $@ $<

$(OBJDIR)/modelparameters.o: $(MODELPATH)/modelparameters.cc | $(OBJDIR)
	$(NVCC) $(NVCCFLAGS) $(MAX_REGISTERS) -dc -o $@ $<

$(OBJDIR)/cudimot.o: cudimot.cc | $(OBJDIR)
	$(NVCC) $(NVCCFLAGS) $(MAX_REGISTERS) -dc -o $@ $<

$(OBJDIR)/cudimotoptions.o: cudimotoptions.cc | $(OBJDIR)
	$(CXX) $(CXXFLAGS) -c -o $@ $<

$(DLINK): $(CUDAOBJS)
	$(NVCC) $(GENCODE) -ccbin $(CXX) -dlink -o $@ $^

$(OBJDIR)/$(modelname): $(OBJDIR)/cudimot.o $(OBJDIR)/cudimotoptions.o $(CUDAOBJS)
	$(NVCC) $(NVLDFLAGS) -o $@ $^ $(LIBS)

$(OBJDIR)/split_parts_$(modelname): split_parts.cc $(OBJDIR)/cudimotoptions.o $(DLINK)
	$(CXX) $(CXXFLAGS) -isystem $(CUDA_HOME)/include -o $@ $< \
	  $(OBJDIR)/cudimotoptions.o $(DLINK) $(CUDAOBJS) $(LDFLAGS) $(LIBS) \
	  -L$(CUDA_HOME)/lib -lcudart_static -lcudadevrt -ldl -lrt

$(OBJDIR)/merge_parts_$(modelname): merge_parts.cc $(OBJDIR)/cudimotoptions.o $(DLINK)
	$(CXX) $(CXXFLAGS) -isystem $(CUDA_HOME)/include -o $@ $< \
	  $(OBJDIR)/cudimotoptions.o $(DLINK) $(CUDAOBJS) $(LDFLAGS) $(LIBS) \
	  -L$(CUDA_HOME)/lib -lcudart_static -lcudadevrt -ldl -lrt

$(OBJDIR)/testFunctions_$(modelname): testFunctions.cu $(MODELPATH)/modelparameters.cc | $(OBJDIR)
	$(NVCC) $(NVCCFLAGS) $(MAX_REGISTERS) -o $@ $(MODELPATH)/modelparameters.cc $<

objs/%: utils/%.cc
	mkdir -p objs
	$(CXX) $(CXXFLAGS) -o $@ $< $(LDFLAGS) $(LIBS)
