#!/bin/bash

if [ "$EUID" -ne 0 ]
then
    echo "Needs to run as root"
    exit 1
fi


# UTILS ########################################################################
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


# LOCAL USERS ##################################################################
title "Local users"
subtitle "All local users"
getent passwd

subtitle "Users with passwords"
grep '\$' /etc/shadow | cut -c -40

subtitle "Users with empty passwords"
while read -r line
do
    pass=$(echo "$line" | cut -d':' -f2)
    if [ -z "$pass" ]
    then
        echo $line
    fi
done < /etc/shadow


# SUDO CONFIGURATION ###########################################################
title "$(ls -la /etc/sudoers)" "$(md5sum /etc/sudoers)"
grep -v '^#' /etc/sudoers | grep -v '^$'

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


# APPLIED CONFIGURATION ########################################################
title "Applied configuration"
for user in $(getent passwd | cut -d':' -f1)
do
    sudo -l -U "$user"
done


# PERMISSIONS OF TARGETED FILES ################################################
title "Permissions of targeted files"
for user in $(getent passwd | cut -d':' -f1)
do
    paths=$(sudo -l -U "$user" | grep "NOPASSWD" | cut -d':' -f2)
    if [ -z "$paths" ]
    then
        continue
    fi

    # split line contents into an array, it could be pretty pathological, i.e.:
    #     (root) path1, (root) path2
    #     path3
    paths_array=()
    for line in $paths
    do
        line=$(echo "$line" | sed -e 's/,//g')
        for elem in $line
        do
            if [[ "$elem" =~ ^/ ]]
            then
                paths_array+=("$elem")
            fi
        done
    done

    user_groups=$(groups "$user")
    subtitle "User ""$user" "Groups ""$user_groups"

    for path in "${paths_array[@]}"
    do
        if [ -e "$path" ]
        then
            ls -la "$path"

            # file is a symlink, attempt to dereference it
            if [ -L "$path" ]
            then
                target=$(readlink -f "$path")
                if [ -e "$target" ]
                then
                    ls -la "$target"
                fi
            fi
        else
            echo "$path does not exist"
        fi
    done
done

title "Done"
exit 0
