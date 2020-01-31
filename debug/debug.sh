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

rm -rf tmp/
mkdir tmp

export ASM_DBG_CONFIG=tmp/config.toml
cat <<EOF > tmp/config.toml
[agent]
log = "-"
[debug-buffer]
size = 1048576
dump-file = "$debug_buffer_path"
[code-object-dump]
log = "-"
directory = "tmp/"
[[code-object-swap]]
when-call-count = 5
load-file = "tmp/debug.co"
exec-before-load = """bash -o pipefail -c '\
  perl breakpoint.pl -ba \$ASM_DBG_BUF_ADDR -bs \$ASM_DBG_BUF_SIZE \
    -l $line -w "$watches" -s 96 -r s0 -t ${counter:=0} -p $perl_args $source_file \
  | /opt/rocm/opencl/bin/x86_64/clang -x assembler -target amdgcn--amdhsa -mcpu=gfx906 -mno-code-object-v3 \
    -Igfx9/include -o tmp/debug.co -'"""
EOF

export HSA_TOOLS_LIB=libplugintercept.so

./0_Build/client/tensile_client --config-file 1_BenchmarkProblems/*/00_Final/source/ClientParameters.ini
echo
