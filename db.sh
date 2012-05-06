#!/bin/bash

export PATH=$PATH:$(dirname $0)/aux

source config.sh
source log.sh

## Table where the applied deltas info will be stored
create_deltas_table="CREATE TABLE $deltas_table 
        (id CHAR(20),
         comment VARCHAR(256),
         md5sum CHAR(32));"



usage() {
    cat << EOU
    Usage: $0 [-h] [-d] [-c conf_file] command

    Script to handle the backup and restoration of MySQL's database.

    Options:
        -h
            Show this help.
                                                                            
        -d                                                                      
            Enable debug mode                                                   
                                                                                
        -c conf_file                                                            
            Use the configuration file conf_file instead of the default         
            $conf_file                                                          

    Commands:
        backup [user|sys|all]
            Do a backup of the user generated, system or all tables (will use
            all by default)

        restore [-d] [-l [user|sys|all]|file]
            Restore the last backup (the -l option) or the given backup sql
            file. If -l specified the last 'all' backup will be used unless
            user or system specified.
            The -d flag drops the database before restoring it.
            
        update [delta1 [...]]
            Applies the given delta scripts and registers them in the
            database. A delta file must be a SQL script with the name
            'IDNUMBER-Comment.sql' where IDNUMBER is  a number identifying
            the delta.

EOU
    exit ${1:-1}
}

## Helper funtion that checks if one element is in a list
is_in() {
    local what="$1"
    local where=(${@:2})
    for elem in ${where[@]}; do
        [[ "$what" == "$elem" ]] && return 0
    done
    return 1
}

get_all_tables() {
    local host="${1:-$dbhost}"
    local user="${2:-$dbuser}"
    local pass="${3:-$dbpass}"
    local db="${4:-$database}"
    mysql ${user:+-u$user} ${pass:+-p$pass} ${host:+-h $host} \
        -N -e "show tables;" $db
}

get_system_tables() {
    local tables=($(get_all_tables))
    for table in ${tables[@]}; do
        if ! is_in $table ${user_tables}; then
            echo $table
        fi
    done
}

get_last_backup() {
    type="${1:?Missing backup type, sys or user}"
    local lastbackup="$(ls -t $backups_dir/db/*$type*dbbackup.sql.* | head -n1)"
    [[ -f "$lastbackup" ]] \
        && echo $lastbackup \
        || return 1
}

get_applied_deltas() {
    local host="${1:-$dbhost}"
    local user="${2:-$dbuser}"
    local pass="${3:-$dbpass}"
    local db="${4:-$database}"
    mysql ${user:+-u$user} ${pass:+-p$pass} ${host:+-h $host} \
        -N -e "select id from $deltas_table;" $db
}

init_deltas_table() {
    local host="${1:-$dbhost}"
    local user="${2:-$dbuser}"
    local pass="${3:-$dbpass}"
    local db="${4:-$database}"
    tables=($(get_all_tables $host $user $pass $db))
    if ! is_in $deltas_table ${tables[@]}; then
        mysql ${user:+-u$user} ${pass:+-p$pass} ${host:+-h $host} \
            -N -e "$create_deltas_table" $db \
        && log "Delta table $deltas_table initialized on database $db." \
        || { log::ERROR "Failed to initialise deltas table $deltas_table on database $db.";
            return 1; }
    fi
    return 0
}

apply_delta() {
    local delta="${1:?No delta file supplied}"
    local host="${2:-$dbhost}"
    local user="${3:-$dbuser}"
    local pass="${4:-$dbpass}"
    local db="${5:-$database}"
    local mysql="mysql ${user:+-u$user} ${pass:+-p$pass} ${host:+-h $host}"
    $mysql $db < $delta \
        || return 1
    local id="${delta%%-*}"
    local comment="${delta#*-}"
    local md5="$(md5sum $delta | head -c 32)"
    $mysql -e "insert into $deltas_table values ('$id', '${comment%.sql}', '$md5');" $db \
        || return 1
}

get_delta_md5() {
    id="${1:?No id supplied.}"
    local host="${2:-$dbhost}"
    local user="${3:-$dbuser}"
    local pass="${4:-$dbpass}"
    local db="${5:-$database}"
    local mysql="mysql ${user:+-u$user} ${pass:+-p$pass} ${host:+-h $host}"
    $mysql -N -e "Select md5sum from $deltas_table where id='$id';" $db
}

do_backup() {
    local mysqldump="mysqldump ${dbuser:+-u$dbuser} ${dbpass:+-p$dbpass} ${dbhost:+-h $dbhost}"
    local db="$database"
    case ${1:-all} in
        all) do_backup sys && do_backup user && return 0;;
        sys*) local tables=($(get_system_tables)); local append='sys_' ;;
        user) local tables=(${user_tables}); local append='user_' ;;
        *) log::WARN "How did you get here??"; usage; exit ;;
    esac
    [[ -d $backups_dir/db ]] \
        || mkdir -p $backups_dir/db \
        || { log::ERROR "Error creating the backup dir $backups_dir/db."; exit 1;}
    local timestamp="$( date +%Y%m%d%H%M%S)"
    local outfile="$backups_dir/db/${append}dbbackup.sql.$timestamp"
    log "Creating backup at $outfile..."
    $mysqldump $db ${tables[@]}  > "$outfile" \
        && log::OK "OK" \
        || { log::ERROR " ERROR"; return 1;}
}

do_restore() {
    local db="$database"
    local mysql="mysql ${dbuser:+-u$dbuser} ${dbpass:+-p$dbpass} ${dbhost:+-h $dbhost}"
    local drop_on_partial="False"
    [[ "$1" == "-d" ]] && drop_on_partial="True" && shift
    [[ "$1" == "" ]] && log::ERROR "No backup file specified." && usage
    case $1 in
        -l)
            case $2 in
                user)
                    local file=$(get_last_backup user) \
                    || { log::ERROR "Could not find last user tables backup."; exit 1; }
                    ;;
                sys*)
                    local file=$(get_last_backup sys) \
                    || { log::ERROR "Could not find last system tables backup."; exit 1; }
                    ;;
                *)
                    get_last_backup sys > /dev/null \
                        && get_last_backup user > /dev/null \
                        || { log::ERROR "Cannot locate all the backup files...";
                            return 1;}
                    if is_in "$db" $($mysql -e "show databases;"); then
                        log "Dropping old database $db: "
                        $mysql -e "drop database $db;" \
                        && log::OK "OK" \
                        || { log::ERROR "ERROR"; return 1;}
                    fi
                    do_restore -l user \
                    && do_restore -l sys \
                    && return 0
                    ;;
            esac
            ;;
        *)
            [[ -f ${1:-/dummy/file} ]] \
                || { log::ERROR "File $1 not found."; exit 1; }
            local file=$1
            ;;
    esac
    if [[ "$drop_on_partial" == "True" ]] \
    && is_in "$db" $($mysql -e "show databases;"); then
        log "Dropping old database $db: "
        $mysql -e "drop database $db;" \
        && log::OK "OK" \
        || { log::ERROR "ERROR"; return 1;}
    fi
    $mysql -e "create database if not exists $db;" \
    || { log::ERROR "Error creating database $db."; return 1; }
    log "Restoring $file backup..."
    $mysql $db < $file \
    && log::OK "OK" \
    || log::ERROR " ERROR"
}

do_update() {
    local abort='True'
    case $1 in
        '--noabort') shift; local abort='False';;
    esac

    log "Doing a full backup... just in case"
    do_backup || { log::ERROR "Failed to do the backup... exitting"; return 1; }
        
    init_deltas_table || return 1

    for file in $@; do
        [[ -f $file ]] \
        || { log::ERROR "Delta file $file does not exist... aborting"; return 1; }
    done
    local applied_deltas=($(get_applied_deltas))
    log "Applying deltas"
    for delta in $@; do
        local comment="${delta#*-}"
        local id="${delta%%-*}"
        if is_in $id ${applied_deltas[@]}; then
            new_md5="$(md5sum $delta | head -c 32)"
            old_md5="$(get_delta_md5 $id)"
            if [[ "$new_md5" != "$old_md5" ]]; then
                log::WARN "\tDelta $delta already applied, BUT MD5 DOES NOT MATCH, PLEASE CHECK"
                log::WARN "\t\tNew md5: $new_md5"
                log::WARN "\t\tOld md5: $old_md5"
            else
                log "\tDelta $delta already applied, skipping..."
            fi
            continue
        fi
        log "\tApplying delta $delta: "
        if apply_delta $delta; then
            log::OK "\t\tOK"
        elif [[ "$abort" == "True" ]]; then
            log::ERROR " Error aplying delta $delta, aborting and restoring backup"
            do_restore -l
            return 1
        else
            log::ERROR "Error applying delta $delta, but option --noabort set, continuing..."
        fi
    done
}


## MAIN

[[ "$1" == "-h" ]] && usage 0
[[ "$1" == "-d" ]] && shift && set -x 
[[ "$1" == "-c" ]] \
&& {
    conf_file="$2"
    [[ -f "$conf_file" ]] \
    || {
        log::ERROR "Config file $conf_file not found"
        exit 1
    }
    shift 2
}

conf::load ${conf_file:?No conf_file specified} \
|| { log::ERROR "Error parsing config file"; exit 1; }
conf::require database deltas_table backups_dir \
|| { log::ERROR "Missing parametes in the config file."; exit 1; }

log "
Loaded config:
    Database connection:
        dbhost: ${dbhost:-localhost}
        database: ${database}
        dbpass: ${dbpass:-None}
        dbuser: ${dbuser:-None}
    Delta script specifics:
        deltas_table: ${deltas_table}
        user_tables: ${user_tables:-None}
    Backups:
        backups_dir: ${backups_dir}
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
        usage
        ;;
esac
