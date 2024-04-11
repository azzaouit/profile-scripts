#!/bin/bash

if [[ $# -eq 0 ]] ; then
    echo "Usage: $0 <matrix name>"
    exit 0
fi

ROOT=$(pwd)
EXE=$ROOT/libsparsemat/build/examples/main
ADSP=$ROOT/adsp/adsp
MAT_ERR=$ROOT/materror/materror
DATA=$ROOT/data
MAT_NAME=$1
MAT_PATH=$DATA/$MAT_NAME/$MAT_NAME
NCOUNTERS=4

# Group events by counter and run perf
function run_once() {
    rm -rf out && mkdir -p out
    for ((i = 0; i < ${#EVENTS[@]}; i += $NCOUNTERS))
    do
        nevents=("${EVENTS[@]:i:$NCOUNTERS}")
        nevents=${nevents[*]}
        e_arg=${nevents// /,}
        sudo perf stat -x , -o out/$i.csv -e $e_arg $EXE --matrix $1 2>&1 > /dev/null
    done
    cat out/*.csv | grep -o '^[^#]*' > $1.csv
}

# build libsparsemat
git clone https://github.com/uml-hpc/libsparsemat.git
cd libsparsemat && mkdir -p build && cd build
cmake .. && make
tests/cpu_test

cd $ROOT

# build adsp utils
git clone https://github.com/uml-hpc/adsp.git
cd adsp && cd cpuid && make
EVENTS=(`sudo $ADSP perf_list`)

cd $ROOT

# build mat error
git clone https://github.com/uml-hpc/materror.git

# Download data
rm -rf $DATA && mkdir -p $DATA
$ADSP matrix_downloader --matrix $MAT_NAME --data-dir $DATA
cd $DATA && tar -xvf $MAT_NAME.tar.gz

cd $ROOT

# Inject errors
echo "Injecting Noise..."
$MAT_ERR gaussian --matrix $MAT_PATH.mtx --error-rate 0.01 --injection-rate 0.01 --out ${MAT_PATH}_gauss_0p01_0p01.mtx
$MAT_ERR gaussian --matrix $MAT_PATH.mtx --error-rate 0.01 --injection-rate 0.05 --out ${MAT_PATH}_gauss_0p01_0p05.mtx
$MAT_ERR gaussian --matrix $MAT_PATH.mtx --error-rate 0.01 --injection-rate 0.10 --out ${MAT_PATH}_gauss_0p01_0p10.mtx
$MAT_ERR gaussian --matrix $MAT_PATH.mtx --error-rate 0.05 --injection-rate 0.01 --out ${MAT_PATH}_gauss_0p05_0p01.mtx
$MAT_ERR gaussian --matrix $MAT_PATH.mtx --error-rate 0.05 --injection-rate 0.05 --out ${MAT_PATH}_gauss_0p05_0p05.mtx
$MAT_ERR gaussian --matrix $MAT_PATH.mtx --error-rate 0.05 --injection-rate 0.10 --out ${MAT_PATH}_gauss_0p05_0p10.mtx
$MAT_ERR gaussian --matrix $MAT_PATH.mtx --error-rate 0.10 --injection-rate 0.01 --out ${MAT_PATH}_gauss_0p10_0p01.mtx
$MAT_ERR gaussian --matrix $MAT_PATH.mtx --error-rate 0.10 --injection-rate 0.05 --out ${MAT_PATH}_gauss_0p10_0p05.mtx
$MAT_ERR gaussian --matrix $MAT_PATH.mtx --error-rate 0.10 --injection-rate 0.10 --out ${MAT_PATH}_gauss_0p10_0p10.mtx

# Convert to CRS and run
for FILE in $DATA/$MAT_NAME/*; do
    $ADSP mtx2crs --matrix $FILE --out $FILE.crs
    run_once $FILE.crs
done
