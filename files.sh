#!/bin/bash

export PATH=$PATH:$(dirname $0)/aux
source config.sh
source log.sh

usage(){
    cat << EOU
    Usage: $0 [-d] [-c conf_file] [-h|--help|help] command

    Script to handle the backup and restoration of Buscopista's site files.

    Options:
        help|-h|--help
            Show this help.

        -d
            Enable debug mode

        -c conf_file
            Use the configuration file conf_file instead of the default
            $conf_file

    Commands:
        backup [user|sys|all]
            Do a backup of the Buscopista's user, system or all files (will
            use all by default)

        restore [-l|file]
            Restore the last backup (the -l option) or the given backup tgz
            file.

        update [-r revision]
            Update the files with the ones in the svn to the HEAD revision or
            the one specified with -r.
EOU
    exit ${1:-0}
}

do_backup() {
    last_dir="$backups_dir/files/last"
    [[ -d $files_dir ]] \
    || {
        log WARN "No source dir $files_dir found."
        return 1
    }
    [[ -d $last_dir ]] \
    || {
        mkdir -p $last_dir \
        && log WARN "Last backup directory $last_dir not found, created a new one." \
        || {
            log ERROR "Failed to create the backups dir $last_dir."
            return 1
        }
    }
    log "Rsyncing from original directory $files_dir"
    rsync --progress --stats -r -t -p -l --delete $files_dir $last_dir \
    && log OK "Rsync Done." \
    || {
        log ERROR "Failed to rsync $files_dir to $last_dir. Aborting."
        return 1
    }
    name="$(basename $files_dir)"
    timestamp="$(date +%Y%m%d%H%M%S)"
    log "Creating tarfile $backups_dir/files/$name.$timestamp.tgz"
    tar cvzf $backups_dir/files/$name.$timestamp.tgz -C $last_dir/ $name  \
    && log OK "Tar done." \
    || {
        log ERROR "Error creating tarfile $backups_dir/files/$name.$timestamp.tgz."
        return 1
    }
    return 0
}

restore()
{
    dir="${1:?}"
    name="$(basename $files_dir)"
    [[ -d "$dir" ]] \
    || {
        log WARN "No backup found at $dir. Nothing to restore."
        exit 1
    }
    log "Rsyncing $dir to $files_dir"
    rsync --progress --stats -r -t -p -l --delete $dir/$name/ $files_dir \
    && log OK "Rsync Done." \
    || {
        log ERROR "Failed to rsync $files_dir to $dir. Aborting."
        return 1
    }
    file="$(ls -t $backups_dir/files/$name.*.tgz 2>/dev/null | head -n1)"
    log "Restoring old last dir from the newer tgz $file"
    [[ -f $file ]] \
    || {
        log WARN "No tar backup found, skipping the restoration of the last directory." 
        return 0
    }
    rm -Rf $dir/$name \
    && {
        tar xvzf $file -C $dir \
        && log OK "Last dir restored from $file." \
        || {
            log ERROR "Error toring tarfile $file."
            return 1
        }
    } || log WARN "Unable to delete old last dir. Skipping restoration from tgz."
}

do_restore() {
    [[ "$1" == "-l" ]] \
    || [[ "$dir" == "" ]] \
    && dir="$backups_dir/files/last" \
    || dir="$1"
    restore "$dir" \
    && return 0 \
    || return 1
}

do_update() {
    dir="${1:-${src_files_dir}}"
    ## if a svn url was specified, handle it
    [[ "${dir#svn:}" != "$dir" ]] \
    && {
        url="${dir#svn:}"
        ## download the changes to the temporary source directory
        [[ -d $tmp_src_dir/.svn ]] \
        && {
            cd $tmp_src_dir
            svn up ${svn_user:+--username $svn_user} \
                ${svn_pass:+--password $svn_pass} \
                --non-interactive .
            cd - &>/dev/null
        } || {
            svn co ${svn_user:+--username $svn_user} \
                ${svn_pass:+--password $svn_pass} \
                --non-interactive $url $tmp_src_dir \
            || {
                log ERROR "Error getting source code from $url to $tmp_src_dir."
                return 1
            }
        }
        dir=$tmp_src_dir
    }
    [[ -d "$dir" ]] \
    || {
        log WARN "No files found at $dir. Nothing to update."
        exit 1
    }
    log "Rsyncing $dir to $files_dir"
    rsync --progress --stats -r -t -p -l --exclude '.svn' --delete $dir/ $files_dir \
    && log OK "Rsync Done." \
    || {
        log ERROR "Failed to rsync $files_dir to $dir. Aborting."
        return 1
    }
}



while getopts 'hdc:' option; do
    case $option in
        h) usage 0;;
        d) set -x;;
        c) conf_file="$OPTARG";;
        *) usage 1;;
    esac
done
shift $(($OPTIND - 1))
OPTIND=1

conf::load ${conf_file:?No conf_file specified} \
|| { log ERROR "Error parsing config file"; exit 1; }
conf::require files_dir src_files_dir backups_dir tmp_src_dir \
|| {
    log ERROR "Some required parameters are missing in the config file."
    exit 1
}

log "
Loaded config:
    Dirs:
        files_dir: ${files_dir}
        src_files_dir: ${src_files_dir}
        tmp_src_dir: ${tmp_src_dir}
        ugc_dirs: ${ugc_dirs:-None}
    Backups:
        backups_dir: ${backups_dir}
    SVN:
        svn_repo: ${svn_repo:-None}
        svn_user: ${svn_user:-None}
        svn_pass: ${svn_pass:-None}
"


case ${1} in
    backup)
        do_backup "${@:2}"
        ;;
    restore)
        do_restore "${@:2}"
        ;;
    update)
        do_update "${@:2}"
        ;;
    *)
        usage 1
        ;;
esac



