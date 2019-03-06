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
    if [ -z $(echo "$line" | cut -d':' -f2) ]
    then
        echo $line
    fi
done < /etc/shadow


# SUDO CONFIGURATION ###########################################################
title "$(ls -la /etc/sudoers)" "$(md5sum /etc/sudoers)"
cat /etc/sudoers

title "$(ls -lad /etc/sudoers.d/)"

if [ -n "$(ls -A /etc/sudoers.d)" ]
then
    for file in /etc/sudoers.d/*
    do
        file_permissions=$(ls -la "$file")
        file_hash=$(md5sum "$file")
        subtitle "$file_permissions" "$file_hash"
        cat "$file"
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
    subtitle "User $user"

    while read -r path
    do
        if [ "$path" == "ALL" ]
        then
            echo "ALL"
            continue
        fi

        if [ -e "$path" ]
        then
            ls -la "$path"

            # file is a symlink
            if [ -L "$path" ]
            then
                target=$(readlink "$path")
                if [ -e "$target" ]
                then
                    ls -la "$target"
                fi
            fi
        else
            echo "$path does not exist"

            # check that path starts with '/'
            if [[ ! $path =~ ^/ ]]
            then
                continue
            fi

            # find last existing path
            loop_control=0
            while [ "$path" != "/" ]
            do
                path=$(dirname $path)
                if [ -d "$path" ]
                then
                    ls -lad "$path"
                    path="/"
                fi
                loop_control=$((loop_control+1))
                if [ $loop_control -gt 5 ]
                then
                    break
                fi
            done
        fi
    done <<< $paths
done

title "Done"
exit 0
