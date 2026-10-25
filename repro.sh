#!/usr/bin/env bash
set -e -u -o pipefail
##################################################################################
## Settings
##################################################################################

CUDA_VERSION=13.2.2
# CUDA_VERSION=13.3.1
NCCL_VERSION="2.32.3-1"

OPENMPI_VERSION=5.0.11

export CC=gcc
export CXX=g++
export FC=gfortran
CC_VERSION=$(gcc -dumpfullversion -dumpversion)

##################################################################################
## Logic
##################################################################################

REPRO_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
mkdir -p "${REPRO_SCRIPT_DIR}/downloads"

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
    *) log_error "unsupported cuda version $CUDA_VERSION" ; exit 1 ;;
esac

case ${UNAMEM:-$(uname -m)} in
    aarch64) target_arch="linux_sbsa"   ;;
    x86_64)  target_arch="linux" ;;
    *) log_error "unsupported arch '${UNAMEM:-$(uname -m)}'" ; exit 1 ;;
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
## Open MPI
##################################################################################
echo " -- Open MPI"

OPENMPI_DIR=openmpi-${OPENMPI_VERSION}
OPENMPI_ARCHIVE=${OPENMPI_DIR}.tar.bz2
OPENMPI_URL=https://download.open-mpi.org/release/open-mpi/v${OPENMPI_VERSION%.*}/${OPENMPI_ARCHIVE}

[ ! -f "${REPRO_SCRIPT_DIR}/downloads/${OPENMPI_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/downloads/${OPENMPI_ARCHIVE}" "${OPENMPI_URL}"
[ ! -d "${OPENMPI_DIR}" ] && (cd "${REPRO_SCRIPT_DIR}" && tar xf "${REPRO_SCRIPT_DIR}/downloads/${OPENMPI_ARCHIVE}")

SOURCE_DIR="${REPRO_SCRIPT_DIR}/${OPENMPI_DIR}"
BUILD_DIR="${REPRO_SCRIPT_DIR}/${OPENMPI_DIR}.$(basename "${CC}")-${CC_VERSION}.cuda-${CUDA_VERSION}.build"
OPENMPI_PREFIX="${REPRO_SCRIPT_DIR}/${OPENMPI_DIR}.$(basename "${CC}")-${CC_VERSION}.cuda-${CUDA_VERSION}.prefix"

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
## NCCL
##################################################################################
echo " -- NCCL"

NCCL_ARCHIVE=nccl-${NCCL_VERSION}.tar.gz
NCCL_DIR=nccl-${NCCL_VERSION}
NCCL_URL=https://github.com/NVIDIA/nccl/archive/refs/tags/v${NCCL_VERSION}.tar.gz

[ ! -f "${REPRO_SCRIPT_DIR}/downloads/${NCCL_ARCHIVE}" ] && curl -L -o "${REPRO_SCRIPT_DIR}/downloads/${NCCL_ARCHIVE}" "${NCCL_URL}"
[ ! -d "${NCCL_DIR}" ] && (echo "-- extract nccl" ; cd "${REPRO_SCRIPT_DIR}" && tar xf "${REPRO_SCRIPT_DIR}/downloads/${NCCL_ARCHIVE}")

SOURCE_DIR="${REPRO_SCRIPT_DIR}/${NCCL_DIR}"
BUILD_DIR="${REPRO_SCRIPT_DIR}/${NCCL_DIR}.$(basename "${CC}")-${CC_VERSION}.cuda-${CUDA_VERSION}.build"
PREFIX_DIR="${REPRO_SCRIPT_DIR}/${NCCL_DIR}.$(basename "${CC}")-${CC_VERSION}.cuda-${CUDA_VERSION}.prefix"

if [ ! -f "${PREFIX_DIR}/lib/libnccl.so" ]; then
    if [ ! -d "${SOURCE_DIR}" ]; then
        tar xf "${NCCL_CACHE}" -C "${REPRO_SCRIPT_DIR}"
    fi
    rm -rf "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"
    (
        load_cuda
        cd "${BUILD_DIR}"
        if [ ! -f Makefile ]; then
            cmake \
                -Wno-dev \
                -G 'Unix Makefiles' \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_INSTALL_PREFIX="${PREFIX_DIR}" \
                -DCMAKE_INSTALL_LIBDIR="lib" \
                -DBUILD_SHARED_LIBS=ON \
                "${SOURCE_DIR}"
        fi
        make -j $(nproc)
        make install
    )
fi

##################################################################################
## NCCL Tests
##################################################################################

echo TODO nccl ttests

##################################################################################
## Exit
##################################################################################
exit 0
