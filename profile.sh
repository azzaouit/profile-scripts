#!/bin/bash

if [[ $# -eq 0 ]] ; then
    echo "Usage: $0 <matrix name>"
    exit 0
fi

ROOT=$(pwd)
DATA=$ROOT/data
MAT_NAME=$1
MAT_PATH=$DATA/$MAT_NAME/$MAT_NAME
RUNS=5

# install deps
sudo apt update
sudo apt install -y flex bison libelf-dev libtraceevent-dev
sudo apt install -y pkg-config cmake python3-dev python3-numpy python3-scipy
sudo apt install -y cargo rustc

# build perf
git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
cd linux/tools/perf
make
sudo cp perf /usr/local/bin

cd $ROOT

# build libsparsemat
git clone https://github.com/uml-hpc/libsparsemat.git
cd libsparsemat && mkdir -p build && cd build
cmake .. && make
tests/cpu_test
EXE=$ROOT/libsparsemat/build/examples/main

cd $ROOT

# build adsp utils
git clone https://github.com/uml-hpc/adsp.git
cd adsp && cd cpuid && make
ADSP=$ROOT/adsp/adsp

cd $ROOT

# build mat error
git clone https://github.com/uml-hpc/materror.git
MAT_ERR=$ROOT/materror/materror

# build perf-rs
git clone https://github.com/uml-hpc/perf-rs.git
cd perf-rs && cargo build --release
PERF_RS=$ROOT/perf-rs/target/release/perf-rs

cd $ROOT

# Download data
rm -rf $DATA && mkdir -p $DATA
$ADSP matrix_downloader --matrix $MAT_NAME --data-dir $DATA
cd $DATA && tar -xvf $MAT_NAME.tar.gz

cd $ROOT

# Inject errors
echo "Injecting Noise..."
for ERR_RATE in `seq .01 .01 .1`
do
    for INJ_RATE in `seq .01 .01 .1`
    do
        $MAT_ERR gaussian --matrix $MAT_PATH.mtx\
            --error-rate $ERR_RATE\
            --injection-rate $INJ_RATE\
            --out ${MAT_PATH}_gauss_${ERR_RATE}_${INJ_RATE}.mtx
    done
done

# Convert to CRS and run
for FILE in $DATA/$MAT_NAME/*; do
    $ADSP mtx2crs --matrix $FILE --out $FILE.crs
    echo "Profiling $FILE"
    sudo $PERF_RS  --runs $RUNS --out $FILE.json --bin $EXE -a --matrix $FILE
done
