#!/bin/bash

## Default config file for everything
conf_file='/etc/default.cfg'

## Get rid of the starting and trailing spaces
trim(){
    local word
    shopt -q -s extglob
    for word in "$@"; do
        word="${word##+([[:space:]])}"
        word="${word%%+([[:space:]])}"
        echo "$word"
    done
    shopt -q -u extglob
}

## replace 'bad' chars with underscores, to make the varname bash 
## compatible (also avoid starting it with numbers)
sanitize(){ 
    local word
    for word in "$@"; do
        word="$( trim "${word}" )"
        # if you do not make sure that extglob is disabled the patterns with
        # square brackets will not work...
        shopt -q -u extglob
        # some utf-8 chars are not valid in var names, but are included in 
        # ranges, avoid using ranges
        word="${word//[^abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]/_}"
        [[ $word =~ ^[0-9] ]] \
            && echo "Malformed $word, should not start with a digit." \
            && return 1
        echo "$word"
    done
}


## Usage: load_config conf_file
conf::load(){
    local conf_file i name value line included
    conf_file=${1:-default.cfg}
    [[ -f $conf_file ]] || { echo "Config file $conf_file not found."; return 1; }
    i=0
    while read line; do
        i=$(($i+1))
        if [[ $line =~ ^include ]]; then
            included="${line#include }"
            [[ -f $included ]] \
            && {
                conf::load $included \
                || {
                    echo "Error including file $included at line $i of file $conf_file."
                    return 1
                }
            } || {
                echo "Included file $included at line $i of $conf_file not found."
                return 1
            }
            continue
        fi
        if [[ $line =~ ^[^#].*=.+ ]]; then
            name="$( sanitize "${line%%=*}" )" \
                || { echo "syntax error on name at line $i."; return 1; }
            value="$( trim "${line#*=}" )"
            eval "$name=\"${value//\"/\\\"}\""
        fi
    done < <( cat $conf_file )
}

conf::require() {
    local missing
    missing=()
    for var in $@; do
        [[ "${!var}" == "" ]] \
        && {
            echo "Required parameter $var not found in the config file."
            missing+=("$var")
        }
    done
    [[ "${#missing[@]}" -eq 0 ]] || return 1
    return 0
}
