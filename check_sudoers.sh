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


# MACHINE BASIC INFORMATION ####################################################
title "Machine info"
hostname
uname -a
uptime


# LOCAL USERS ##################################################################
title "Local users"
subtitle "All local users"
getent passwd

subtitle "Users with passwords"
grep '\$' /etc/shadow | cut -c -40

while read -r line
do
    md5_match=$(grep ':\$1\$' $line)
    user=$(echo "$md5_match" | cut -d':' -f1)
    echo "WARNING: User $user has a MD5 hashed password"
    echo "$md5_match"
done < /etc/shadow

subtitle "Users with empty passwords"
while read -r line
do
    pass=$(echo "$line" | cut -d':' -f2)
    if [ -z "$pass" ]
    then
        echo "WARNING: Empty pass"
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
    # Current limitation: will not scan commands like "(user) /path/"
    paths_array=()
    while read line
    do
        IFS=',' read -ra commands <<< "$line"
        for com in "${commands[@]}"
        do
            # remove leading whitespaces if any
            com=$(echo "$com" | sed -e 's/^ //')

            # drop arguments if any
            com=$(echo "$com" | cut -d' ' -f1)

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
        if [ -e "$path" ]
        then
            ls -la "$path"
            file_owner=$(ls -l "$path" | cut -d' ' -f3)
            if [ "$file_owner" = "$user" ]
            then
                echo "WARNING: File rights"
            fi
        else
            echo "$path does not exist"
        fi
    done
done

title "Done"
exit 0
