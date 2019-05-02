#!/bin/bash

VERBOSE=0

if [ "$EUID" -ne 0 ]
then
    echo "Needs to run as root"
    exit 1
fi


# DISPLAY UTILS ################################################################
verbose()
{
    if [ "$VERBOSE" -eq 1 ]
    then
        return 1
    fi

    return 0
}

title()
{
    echo
    echo
    printf "%0.s#" {1..80}
    echo
    for string in "$@"
    do
        echo "# $string"
    done
    printf "%0.s#" {1..80}
    echo
}

subtitle()
{
    printf "%0.s-" {1..80}
    echo
    for string in "$@"
    do
        echo "| $string"
    done
    printf "%0.s-" {1..80}
    echo
}


# CHECK FILE PERMISSIONS #######################################################
# Param1: username
# Param2: group to check if user is a part of
# Return 1 if user is in group, 0 otherwise
check_if_user_in_group()
{
    user=$1
    group=$2
    user_groups_array=($(groups "$user" | cut -d':' -f2))

    for user_group in "${user_groups_array[@]}"
    do
        if [ "$group" = "$user_group" ]
        then
            return 1
        fi
    done

    return 0
}


# FORBIDDEN COMMANDS ###########################################################
# Param1: command to check
# Return: 1 if command is forbidden, 0 otherwise
check_if_command_is_forbidden()
{
    # list from https://gtfobins.github.io/
    forbidden_commands=('apt-get' 'apt' 'ash' 'awk' 'bash' 'busybox' 'cpan' 'cpulimit' 'csh' 'dash' 'easy_install' 'ed' 'emacs' 'env' 'expect' 'facter' 'find' 'flock' 'ftp' 'gdb' 'gimp' 'git' 'ionice' 'irb' 'jjs' 'journalctl' 'jrunscript' 'ksh' 'ld.so' 'less' 'logsave' 'ltrace' 'lua' 'mail' 'make' 'man' 'more' 'mysql' 'nano' 'nice' 'nmap' 'node' 'perl' 'pg' 'php' 'pic' 'pico' 'pip' 'puppet' 'python' 'rlwrap' 'rpm' 'rpmquery' 'rsync' 'ruby' 'run-mailcap' 'run-parts' 'rvim' 'scp' 'screen' 'script' 'sed' 'setarch' 'sftp' 'sh' 'smbclient' 'sqlite3' 'ssh' 'start-stop-daemon' 'stdbuf' 'strace' 'tar' 'taskset' 'tclsh' 'telnet' 'time' 'timeout' 'unshare' 'vi' 'vim' 'watch' 'wish' 'xargs' 'zip' 'zsh' 'zypper')

    user_command=$1
    user_command=$(basename "$user_command")

    for forbidden_command in "${forbidden_commands[@]}"
    do
        if [ "$user_command" = "$forbidden_command" ]
        then
            return 1
        fi
    done

    return 0
}


# MACHINE BASIC INFORMATION ####################################################
display_machine_information()
{
    title "Machine info"
    hostname=$(hostname)
    echo "$hostname"
    uname -a
    uptime

    title "Installed packages"
    if [ -f /etc/redhat-release ]
    then
        rpm -qa
    elif [ -f /etc/debian_version ]
    then
        dpkg -l --no-pager
    fi
}


# LOCAL USERS ##################################################################
display_local_users()
{
    title "Local users"
    verbose || subtitle "All local users"
    verbose || getent passwd
}

check_local_users_passwords()
{
    subtitle "Users with passwords"
    grep '\$' /etc/shadow | cut -c -40

    # check if users have MD5 passwords
    while read -r line
    do
        md5_match=$(echo "$line" | grep ':\$1\$')
        if [ -z "$md5_match" ]
        then
            continue
        fi

        user=$(echo "$md5_match" | cut -d':' -f1)
        echo "WARNING: $hostname: User $user has a MD5 hashed password: $md5_match"
    done < /etc/shadow

    # check if users have empty passwords
    while read -r line
    do
        pass=$(echo "$line" | cut -d':' -f2)
        if [ -z "$pass" ]
        then
            user=$(echo "$line" | cut -d':' -f1)
            echo "WARNING: $hostname: User $user has an empty pass: $line"
        fi
    done < /etc/shadow
}


# SUDO CONFIGURATION ###########################################################
display_sudo_configuration()
{
    if [ "$VERBOSE" -eq 0 ]
    then
        return
    fi

    title "$(ls -la /etc/sudoers)" "$(md5sum /etc/sudoers)"
    grep -v '^#' /etc/sudoers | grep -v '^$'

    if [ -d /etc/sudoers.d/ ]
    then
        title "$(ls -lad /etc/sudoers.d/)"

        if [ -n "$(ls -A /etc/sudoers.d)" ]
        then
            for file in /etc/sudoers.d/*
            do
                file_permissions=$(ls -la "$file")
                file_hash=$(md5sum "$file")
                subtitle "$file_permissions" "$file_hash"
                grep -v '^#' "$file" | grep -v '^$'
            done
        else
            echo "Directory is empty"
        fi
    fi

    title "Applied configuration"
    for user in $(getent passwd | cut -d':' -f1)
    do
        sudo -l -U "$user"
    done
}


# PERMISSIONS OF TARGETED FILES ################################################
check_sudo()
{
    title "Permissions of targeted files"
    for user in $(getent passwd | cut -d':' -f1)
    do
        sudo_output=$(sudo -l -U "$user" | grep "NOPASSWD" | cut -d':' -f2)
        if [ -z "$sudo_output" ]
        then
            continue
        fi

        user_groups=$(groups "$user")
        subtitle "User ""$user" "Groups ""$user_groups"

        # Split line contents into an array, it could be pretty pathological, i.e.:
        #     (root) path1, (root) path2
        #     path3
        # Therefore it has to be read line by line, then split by commas, then the
        # command must be cleaned of leading and trailing chars around the path
        paths_array=()
        while read -r line
        do
            IFS=',' read -ra commands <<< "$line"
            for com in "${commands[@]}"
            do
                # remove leading whitespace if any
                com=$(echo "$com" | sed -e 's/^ //')

                # remove leading group if any
                com=$(echo "$com" | sed -e 's/^([a-z]*) //')

                # drop arguments if any
                com=$(echo "$com" | cut -d' ' -f1)

                if [ "$com" = "ALL" ]
                then
                    echo "WARNING: $hostname: User $user can run ALL commands"
                    continue
                fi

                if [[ "$com" =~ ^/ ]]
                then
                    paths_array+=("$com")
                else
                    echo "Not going to check $com"
                fi
            done
        done <<< "$sudo_output"

        for path in "${paths_array[@]}"
        do
            # check if path contains a wildcard
            if [[ "$path" == *"*"* ]]
            then
                echo "$path"
                echo "WARNING: $hostname: User $user can run sudo with a path wildcard: $path"
                # TODO: maybe check rights of expanded path insted of continue'ing
                continue
            fi

            # check if path exists
            if ! [ -e "$path" ]
            then
                echo "$path"
                echo "WARNING: $hostname: User $user can run a sudo command that does not exist: $path"
                continue
            fi

            ls -la "$path"

            file_info=($(stat -L -c "0%a %A %U %G" $path))
            file_perms=${file_info[0]}
            file_perms_hr=${file_info[1]}
            file_owner=${file_info[2]}
            file_group=${file_info[3]}

            # check world permissions
            if [ $((file_perms & 0002)) -ne 0 ]
            then
                echo "WARNING: $hostname: Anyone can write to sudo'ed file: $file_perms_hr $path"
            fi

            # check group permissions
            check_if_user_in_group "$user" "$file_group"
            user_in_group=$?
            if [ $((file_perms & 0020)) -ne 0 ] && [ "$user_in_group" -eq 1 ]
            then
                echo "WARNING: $hostname: Group can write to sudo'ed file: $file_perms_hr $path"
            fi

            # check owner permissions
            if [ "$file_owner" = "$user" ]
            then
                echo "WARNING: $hostname: User $user can write to sudo'ed file: $file_perms_hr $path"
            fi

            # check if command can elevate to root
            check_if_command_is_forbidden "$path"
            forbidden=$?
            if [ "$forbidden" -eq 1 ]
            then
                echo "WARNING: $hostname: User $user can run forbidden command $path"
            fi
        done
    done
}


# MAIN #########################################################################
display_machine_information

display_local_users
check_local_users_passwords

display_sudo_configuration
check_sudo

title "Done"
exit 0
