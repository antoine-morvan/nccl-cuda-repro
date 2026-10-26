#!/usr/bin/env bash
set -e -u -o pipefail
##################################################################################
## Settings
##################################################################################

NVHPC_VERSION=26.3

OPENMPI_VERSION=5.0.11
# CUDA_VERSION=13.2.2
CUDA_VERSION=13.3.1
NCCL_VERSION="2.32.3-1"
NCCL_TESTS_VERSION="2.21.1"

##################################################################################
## Logic
##################################################################################

REPRO_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
mkdir -p "${REPRO_SCRIPT_DIR}/downloads"

export CC=gcc
export CXX=g++
export FC=gfortran
CC_VERSION=$(gcc -dumpfullversion -dumpversion)

##################################################################################
## CUDA
##################################################################################
echo " -- CUDA"

case $CUDA_VERSION in
    13.3.1) driver_version="610.43.02" ;;
    13.3.0) driver_version="610.43.02" ;;
    13.2.2) driver_version="595.71.05" ;;
    13.2.1) driver_version="595.58.03" ;;
    13.2.0) driver_version="595.45.04" ;;
    13.1.1) driver_version="590.48.01" ;;
    13.1.0) driver_version="590.44.01" ;;
    13.0.3) driver_version="580.126.20" ;;
    13.0.2) driver_version="580.95.05" ;;
    12.9.1) driver_version="575.57.08" ;;
    12.6.3) driver_version="560.35.05" ;;
    11.8.0) driver_version="520.61.05" ;;
    *) echo "unsupported cuda version $CUDA_VERSION" ; exit 1 ;;
esac

case ${UNAMEM:-$(uname -m)} in
    aarch64) target_arch="linux_sbsa"   ;;
    x86_64)  target_arch="linux" ;;
    *) echo "unsupported arch '${UNAMEM:-$(uname -m)}'" ; exit 1 ;;
esac

CUDA_URL=https://developer.download.nvidia.com/compute/cuda/${CUDA_VERSION}/local_installers/cuda_${CUDA_VERSION}_${driver_version}_${target_arch}.run
CUDA_ARCHIVE=$(basename "$CUDA_URL")
CUDA_DIR=$(basename "$CUDA_URL" .run)

[ ! -f "${REPRO_SCRIPT_DIR}/downloads/${CUDA_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/downloads/${CUDA_ARCHIVE}" "${CUDA_URL}"

CUDA_PREFIX_DIR="${REPRO_SCRIPT_DIR}/${CUDA_DIR}.prefix"
CUDA_BUILD_DIR="${REPRO_SCRIPT_DIR}/${CUDA_DIR}.build"

if [ ! -x "${CUDA_PREFIX_DIR}/bin/nvcc" ]; then
    mkdir -p "${CUDA_PREFIX_DIR}" "${CUDA_BUILD_DIR}"
    bash "${REPRO_SCRIPT_DIR}/downloads/${CUDA_ARCHIVE}" --silent --override --toolkit --tmpdir="${CUDA_BUILD_DIR}" --installpath="${CUDA_PREFIX_DIR}"
fi

function load_cuda() {
    export CUDA_VERSION="${CUDA_VERSION}"
    export CUDA_HOME="${CUDA_PREFIX_DIR}"
    export CUDA_DIR="${CUDA_HOME}"
    export CUDA_ROOT="${CUDA_HOME}"
    export PATH="${CUDA_HOME}/bin:${PATH}"
    
    export CPATH="${CUDA_HOME}/include${CPATH:+:${CPATH}}"
    export LIBRARY_PATH="${CUDA_HOME}/lib64:${CUDA_HOME}/lib64/stubs${LIBRARY_PATH:+:${LIBRARY_PATH}}"
    export LD_LIBRARY_PATH="${CUDA_HOME}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    export CMAKE_PREFIX_PATH="${CUDA_HOME}${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"
    export PKG_CONFIG_PATH="${CUDA_HOME}/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
}


##################################################################################
## NCCL
##################################################################################
echo " -- NCCL"

NCCL_ARCHIVE=nccl-${NCCL_VERSION}.tar.gz
NCCL_DIR=nccl-${NCCL_VERSION}
NCCL_URL=https://github.com/NVIDIA/nccl/archive/refs/tags/v${NCCL_VERSION}.tar.gz

[ ! -f "${REPRO_SCRIPT_DIR}/downloads/${NCCL_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/downloads/${NCCL_ARCHIVE}" "${NCCL_URL}"
[ ! -d "${NCCL_DIR}" ] && (echo "-- extract nccl" ; cd "${REPRO_SCRIPT_DIR}" && tar xf "${REPRO_SCRIPT_DIR}/downloads/${NCCL_ARCHIVE}")

NCCL_SOURCE_DIR="${REPRO_SCRIPT_DIR}/${NCCL_DIR}"
NCCL_BUILD_DIR="${REPRO_SCRIPT_DIR}/${NCCL_DIR}.$(basename "${CC}")-${CC_VERSION}.cuda-${CUDA_VERSION}.build"
NCCL_PREFIX_DIR="${REPRO_SCRIPT_DIR}/${NCCL_DIR}.$(basename "${CC}")-${CC_VERSION}.cuda-${CUDA_VERSION}.prefix"

if [ ! -f "${NCCL_PREFIX_DIR}/lib/libnccl.so" ]; then
    rm -rf "${NCCL_BUILD_DIR}"
    mkdir -p "${NCCL_BUILD_DIR}"
    (
        load_cuda
        cd "${NCCL_BUILD_DIR}"
        if [ ! -f Makefile ]; then
            cmake \
                -Wno-dev \
                -G 'Unix Makefiles' \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_INSTALL_PREFIX="${NCCL_PREFIX_DIR}" \
                -DCMAKE_INSTALL_LIBDIR="lib" \
                -DBUILD_SHARED_LIBS=ON \
                "${NCCL_SOURCE_DIR}"
        fi
        make -j $(nproc)
        make install
    )
fi

function load_nccl() {
    export NCCL_VERSION="${NCCL_VERSION}"

    export NCCL_HOME="${NCCL_PREFIX_DIR}"
    export NCCL_ROOT="${NCCL_HOME}"
    export NCCL_DIR="${NCCL_HOME}"
    export ncclDIR="${NCCL_HOME}"

    export NCCL_LIB="$NCCL_HOME/lib"
    export NCCL_INC="$NCCL_HOME/include"
    export NCCL_BIN="$NCCL_HOME/bin"

    export PATH="${NCCL_HOME}/bin:${PATH}"
    export CPATH="${NCCL_HOME}/include${CPATH:+:${CPATH}}"
    export LIBRARY_PATH="${NCCL_HOME}/lib${LIBRARY_PATH:+:${LIBRARY_PATH}}"
    export LD_LIBRARY_PATH="${NCCL_HOME}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    export CMAKE_PREFIX_PATH="${NCCL_HOME}${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"
    export PKG_CONFIG_PATH="${NCCL_HOME}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"

}

##################################################################################
## Compiler
##################################################################################

OPENMPI_EXTRA_CONFIGURE_FLAGS=()
case ${1:-nvhpc} in
    gcc)
        # use system gcc
        export CC=gcc
        export CXX=g++
        export FC=gfortran
        CC_VERSION=$(gcc -dumpfullversion -dumpversion)
        ;;
    nvhpc)
        (command -v module &> /dev/null) || { echo "error: missing 'module' command" ; exit 1 ; }
        # install nvhpc
        NVHPC_LONGVERSION=20${NVHPC_VERSION%.*}_${NVHPC_VERSION/./}
        CUDA_VARIANT=multi

        NVHPC_DIR=nvhpc_${NVHPC_LONGVERSION}_Linux_$(uname -m)_cuda_${CUDA_VARIANT}
        NVHPC_ARCHIVE=${NVHPC_DIR}.tar.gz
        NVHPC_URL=https://developer.download.nvidia.com/hpc-sdk/${NVHPC_VERSION}/${NVHPC_ARCHIVE}

        [ ! -f "${REPRO_SCRIPT_DIR}/downloads/${NVHPC_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/downloads/${NVHPC_ARCHIVE}" "${NVHPC_URL}"
        [ ! -d "${NVHPC_DIR}" ] && (cd "${REPRO_SCRIPT_DIR}" && tar xf "${REPRO_SCRIPT_DIR}/downloads/${NVHPC_ARCHIVE}")

        NVHPC_PREFIX_DIR="$(readlink -f "${REPRO_SCRIPT_DIR}/${NVHPC_DIR}.prefix")"
        NVHPC_REAL_PREFIX_DIR="${NVHPC_PREFIX_DIR}/$(uname -s)_$(uname -m)/${NVHPC_VERSION}"
        [ ! -x "${NVHPC_REAL_PREFIX_DIR}/compilers/bin/nvfortran" ] && (
            export NVHPC_SILENT=true
            export NVHPC_INSTALL_TYPE=auto
            export NVHPC_INSTALL_DIR="${NVHPC_PREFIX_DIR}"
            "${NVHPC_DIR}/install"
        )
        module use "${NVHPC_PREFIX_DIR}/modulefiles"
        module load nvhpc-nompi

        # module already sets these
        # export CC=nvcc
        # export CXX=nvc++
        # export FC=nvfortran

        CC_VERSION="${NVHPC_VERSION}"
        ;;
    *) echo "ERROR: unsupported compiler '$1'" ; exit 1 ;;
esac

set -x
$CC --version
$CXX --version
$FC --version
set +x

##################################################################################
## Open MPI
##################################################################################
echo " -- Open MPI"

OPENMPI_DIR=openmpi-${OPENMPI_VERSION}
OPENMPI_ARCHIVE=${OPENMPI_DIR}.tar.bz2
OPENMPI_URL=https://download.open-mpi.org/release/open-mpi/v${OPENMPI_VERSION%.*}/${OPENMPI_ARCHIVE}

[ ! -f "${REPRO_SCRIPT_DIR}/downloads/${OPENMPI_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/downloads/${OPENMPI_ARCHIVE}" "${OPENMPI_URL}"
[ ! -d "${OPENMPI_DIR}" ] && (cd "${REPRO_SCRIPT_DIR}" && tar xf "${REPRO_SCRIPT_DIR}/downloads/${OPENMPI_ARCHIVE}")

SOURCE_DIR="${REPRO_SCRIPT_DIR}/${OPENMPI_DIR}"
BUILD_DIR="${REPRO_SCRIPT_DIR}/${OPENMPI_DIR}.$(basename "${CC}")-${CC_VERSION}.build"
OPENMPI_PREFIX="${REPRO_SCRIPT_DIR}/${OPENMPI_DIR}.$(basename "${CC}")-${CC_VERSION}.prefix"

[ ! -x "${OPENMPI_PREFIX}/bin/mpiexec" ] && (
    rm -rf "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"
    [ ! -f Makefile ] && "${SOURCE_DIR}/configure" \
        --prefix="${OPENMPI_PREFIX}" \
        --enable-shared \
        --enable-mpi-fortran \
        --enable-wrapper-rpath=yes \
        --enable-wrapper-runpath=no \
        --disable-mpi1-compatibility \
        --enable-prte-prefix-by-default \
        --with-libnl=no \
        --with-portals4=no \
        --without-rocm \
        --without-cuda \
        --with-libevent=internal \
        --with-hwloc=internal \
        --with-pmix=internal \
        --without-hcoll \
        --without-lustre \
        --without-knem \
        --without-xpmem \
        --without-gpfs \
        --without-libfabric \
        --without-ucx \
        --without-ucc \
        --with-cma
    set +e
    make -j $(nproc)
    res=$?
    if [ $res != 0 ]; then
        echo "[OPENMPI]"
        echo "[OPENMPI] ----- make -j1 -----"
        echo "[OPENMPI]"
        make -j1 V=1 VERBOSE=1
        echo "[OPENMPI]"
        echo "[OPENMPI] ----- exit $res -----"
        echo "[OPENMPI]"
        exit $res
    fi
    set -e
    make install
)

function load_openmpi() {
    export MPI_ROOT="${OPENMPI_PREFIX}"
    export MPI_HOME="${OPENMPI_PREFIX}"
    export MPI_DIR="${OPENMPI_PREFIX}"
    export OPENMPI_ROOT="${OPENMPI_PREFIX}"
    export OPENMPI_HOME="${OPENMPI_PREFIX}"
    export OPAL_PREFIX="${OPENMPI_PREFIX}"

    export PATH="${OPENMPI_PREFIX}/bin:${PATH}"
    export LIBRARY_PATH="${OPENMPI_PREFIX}/lib${LIBRARY_PATH:+:${LIBRARY_PATH}}"
    export LD_LIBRARY_PATH="${OPENMPI_PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    export CPATH="${OPENMPI_PREFIX}/include${CPATH:+:${CPATH}}"

    export MPI_BIN="${OPENMPI_PREFIX}/bin"
    export MPI_LIB="${OPENMPI_PREFIX}/lib"
    export MPI_INC="${OPENMPI_PREFIX}/include"

    export PKG_CONFIG_PATH="${OPENMPI_PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
    export CMAKE_PREFIX_PATH="${OPENMPI_PREFIX}${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"

    export MPICC=mpicc
    export MPICXX=mpicxx
    export MPIFC=mpifort

    export MPI_C_COMPILER=mpicc
    export MPI_CXX_COMPILER=mpicxx
    export MPI_Fortran_COMPILER=mpifort

    export OMPI_CC=${CC}
    export OMPI_CXX=${CXX}
    export OMPI_FC=${FC}
    export OMPI_F90=${FC}
    export OMPI_F77=${FC}
}

##################################################################################
## NCCL Tests
##################################################################################
echo " -- NCCL Tests"


NCCL_TESTS_DIR=nccl-tests-${NCCL_TESTS_VERSION}
NCCL_TESTS_ARCHIVE=${NCCL_TESTS_DIR}.tar.gz
NCCL_TESTS_URL=https://github.com/NVIDIA/nccl-tests/archive/refs/tags/v${NCCL_TESTS_VERSION}.tar.gz

[ ! -f "${REPRO_SCRIPT_DIR}/downloads/${NCCL_TESTS_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/downloads/${NCCL_TESTS_ARCHIVE}" "${NCCL_TESTS_URL}"
[ ! -d "${NCCL_TESTS_DIR}" ] && (echo "-- extract nccl" ; cd "${REPRO_SCRIPT_DIR}" && tar xf "${REPRO_SCRIPT_DIR}/downloads/${NCCL_TESTS_ARCHIVE}")

SOURCE_DIR="${REPRO_SCRIPT_DIR}/${NCCL_TESTS_DIR}"
BUILD_DIR="${REPRO_SCRIPT_DIR}/${NCCL_TESTS_DIR}.$(basename "${CC}")-${CC_VERSION}.cuda-${CUDA_VERSION}.nccl-${NCCL_VERSION}.build"
PREFIX_DIR="${REPRO_SCRIPT_DIR}/${NCCL_TESTS_DIR}.$(basename "${CC}")-${CC_VERSION}.cuda-${CUDA_VERSION}.nccl-${NCCL_VERSION}.prefix"

BIN_SUFFIX="_mpi"
if [ ! -f "${PREFIX_DIR}/bin/hypercube_perf${BIN_SUFFIX}" ]; then
    rm -rf "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"
    (
        cd "${BUILD_DIR}"
        cp -r "${SOURCE_DIR}"/* .

        load_cuda
        load_openmpi
        load_nccl

        make -j $(nproc) MPI=1 NAME_SUFFIX="${BIN_SUFFIX}" MPI_HOME="${MPI_ROOT}" CUDA_HOME="${CUDA_ROOT}" NCCL_HOME="${NCCL_ROOT}" V=1 VERBOSE=1

        mkdir -p "${PREFIX_DIR}/bin"
        cp "${BUILD_DIR}/build/"*"${BIN_SUFFIX}" "${PREFIX_DIR}/bin/"
    )
fi

##################################################################################
## Exit
##################################################################################
echo " -- Done."
exit 0
