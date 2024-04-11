#!/bin/bash

if [[ $# -eq 0 ]] ; then
    echo "Usage: $0 <matrix name>"
    exit 0
fi

ROOT=$(pwd)
EXE=$ROOT/libsparsemat/build/examples/main
ADSP=$ROOT/adsp/adsp
DATA=$ROOT/data
MAT_NAME=$1
MAT_PATH=$DATA/$MAT_NAME/$MAT_NAME
NCOUNTERS=4

# build libsparesemat
git clone https://github.com/uml-hpc/libsparsemat.git
cd libsparsemat && mkdir -p build && cd build
cmake .. && make
tests/cpu_test

cd $ROOT

# build adsp utils
git clone https://github.com/uml-hpc/adsp.git
cd adsp && cd cpuid && make

cd $ROOT

# Download data
rm -rf $DATA && mkdir -p $DATA
$ADSP matrix_downloader --matrix $MAT_NAME --data-dir $DATA
cd $DATA && tar -xvf $MAT_NAME.tar.gz

cd $ROOT

# Convert to CRS
$ADSP mtx2crs --matrix $MAT_PATH.mtx --out $MAT_PATH.crs


# Group events by counter and run perf
EVENTS=(`sudo $ADSP perf_list`)
rm -rf out && mkdir -p out
for ((i = 0; i < ${#EVENTS[@]}; i += $NCOUNTERS))
do
    nevents=("${EVENTS[@]:i:$NCOUNTERS}")
    nevents=${nevents[*]}
    e_arg=${nevents// /,}
    sudo perf stat -x , -o out/$i.csv -e $e_arg $EXE --matrix $MAT_PATH.crs > /dev/null
    echo "Finished Iteration $i..."
done

cat out/*.csv | grep -o '^[^#]*' > results.csv
