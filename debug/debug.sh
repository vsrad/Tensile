#!/bin/bash

USAGE="Usage: $0 -l line -f source_file -o debug_buffer_path -w watches -t counter -p perl_args"

while getopts "l:f:o:w:t:" opt
do
    echo "-$opt $OPTARG"
    case "$opt" in
    l) line=$OPTARG ;;
    f) source_file=$OPTARG ;;
    o) debug_buffer_path=$OPTARG ;;
    w) watches=$OPTARG ;;
    t) counter=$OPTARG ;;
    p) perl_args=$OPTARG ;;
    esac
done

[[ -z "$line" || -z "$source_file" || -z "$debug_buffer_path" || -z "$watches" ]] && { echo $USAGE; exit 1; }
gcnarch=`/opt/rocm/bin/rocminfo | grep -om1 gfx9..`

rm -rf tmp/
mkdir tmp

export INTERCEPT_CONFIG=tmp/config.toml
if [[ ${source_file##*.} = "s" ]]; then
    cat <<EOF > tmp/config.toml
[logs]
agent-log = "-"
co-log = "-"
[[buffer]]
size = 1048576
dump-path = "$debug_buffer_path"
addr-env-name = "ASM_DBG_BUF_ADDR"
size-env-name = "ASM_DBG_BUF_SIZE"
[init-command]
exec = """bash -o pipefail -c '\
    perl breakpoint_assembly.pl -ba \$ASM_DBG_BUF_ADDR -bs \$ASM_DBG_BUF_SIZE \
    -l $line -w "$watches" -t ${counter:=0} -p $perl_args $source_file \
    | /opt/rocm/bin/hcc -x assembler -target amdgcn--amdhsa -mcpu=$gcnarch \
    -mno-code-object-v3 -o tmp/plugged.co -
'"""
required-return-code = 0
[[code-object-replace]]
condition = { co-load-id = 2 }
co-path = "tmp/plugged.co"
EOF
elif [[ ${source_file##*.} = "cpp" ]]; then
    cat <<EOF > tmp/config.toml
[logs]
agent-log = "-"
co-log = "-"
[[buffer]]
size = 1048576
dump-path = "$debug_buffer_path"
addr-env-name = "ASM_DBG_BUF_ADDR"
size-env-name = "ASM_DBG_BUF_SIZE"
[init-command]
exec = """bash -o pipefail -c '\
    perl breakpoint_source.pl -ba \$ASM_DBG_BUF_ADDR -bs \$ASM_DBG_BUF_SIZE \
    -l $line -w "$watches" -t ${counter:=0} -p $perl_args -o tmp/Kernels-plugged.cpp $source_file \
    ; /opt/rocm/bin/hcc `/opt/rocm/hcc/bin/hcc-config --cxxflags --ldflags --shared` \
    -I\`echo 1_BenchmarkProblems/*/00_Final/source*\` tmp/Kernels-plugged.cpp -o tmp/Kernels-plugged.so \
    ; /opt/rocm/bin/extractkernel -i tmp/Kernels-plugged.so
'"""
required-return-code = 0
[[code-object-replace]]
condition = { co-load-id = 2 }
co-path = "tmp/Kernels-plugged.so-000-$gcnarch.hsaco"
EOF
else
    >&2 echo "Unsupported source extension: ${source_file##*.}. Select a .s file for assembly debugging or .cpp file for source debugging and rerun the script."
    exit 1
fi

export HSA_TOOLS_LIB=libplugintercept.so

./0_Build/client/tensile_client --config-file 1_BenchmarkProblems/*/00_Final/source/ClientParameters.ini
echo
