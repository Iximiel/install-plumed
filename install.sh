#!/bin/bash
#! /bin/bash

set -e
set -x

suffix=""
version=""
repo=https://github.com/plumed/plumed2.git
program_name=plumed

for opt; do
    case "$opt" in
    version=*) version="${opt#version=}" ;;
    suffix=*)
        suffix="--program-suffix=${opt#suffix=}"
        program_name="plumed${opt#suffix=}"
        ;;
    repo=*) repo="${opt#repo=}" ;;
    *)
        echo "unknown option $opt"
        exit 1
        ;;
    esac
done

cd "$(mktemp -dt plumed.XXXXXX)" || {
    echo "Failed to create tempdir"
    exit 1
}

git clone $repo
cd plumed2

if [[ -n "$version" ]]; then
    echo "installing plumed $version"
else
    version=$(git tag --sort=version:refname |
        grep '^v2\.[0-9][0-9]*\.[0-9][0-9]*' |
        tail -n 1)
    echo "installing latest stable plumed $version"
fi

#cheking out to $version before compiling the dependency json for this $version
git checkout $version

# This gets all the dependency information in plumed
{
    firstline=""
    echo '{'
    for mod in src/*/Makefile; do
        dir=${mod%/*}
        modname=${dir##*/}
        typename=$dir/module.type

        if [[ ! -f $typename ]]; then
            modtype="always"
        else
            modtype=$(head "$typename")
        fi
        dep=$(grep USE "$mod" | sed -e 's/USE=//')

        IFS=" " read -r -a deparr <<<"$dep"
        echo -e "${firstline}\"$modname\" : {"
        echo "\"type\": \"$modtype\","
        echo -n '"depends" : ['
        pre=""
        for d in "${deparr[@]}"; do
            echo -n "${pre}\"$d\""
            pre=", "
        done
        echo ']'
        echo -n '}'
        firstline=",\n"
    done
    echo -e '\n}'
} >"$GITHUB_WORKSPACE/_data/extradeps$version.json"

hash=$(git rev-parse HEAD)

if [[ -f $HOME/opt/lib/$program_name/$hash ]]; then
    echo "ALREADY AVAILABLE, NO NEED TO REINSTALL"
else

    rm -fr "$HOME/opt/lib/$program_name"
    rm -fr "$HOME/opt/bin/$program_name"
    rm -fr "$HOME/opt/include/$program_name"
    rm -fr "$HOME"/opt/lib/lib$program_name.so*

    ./configure --prefix="$HOME/opt" \
        --enable-modules=all \
        --enable-boost_serialization \
        --enable-fftw $suffix \
        --enable-libtorch LDFLAGS=-Wl,-rpath,$LD_LIBRARY_PATH
    make -j 5
    make install

    touch "$HOME/opt/lib/$program_name/$hash"

fi
