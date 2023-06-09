#! /usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

GRUB_THEME='myGrubTheme'
INSTALLER_LANG='French'

# Check dependencies
INSTALLER_DEPENDENCIES=(
    'mktemp'
    'sed'
    'sort'
    'sudo'
    'tar'
    'tee'
    'tr'
    'wget'
)

for i in "${INSTALLER_DEPENDENCIES[@]}"; do
    command -v $i > /dev/null 2>&1 || {
        echo >&2 "'$i' command is required, but not available. Aborting.";
        exit 1;
    }
done

cd $(mktemp -d)

# Pre-authorise sudo
sudo echo

declare -A INSTALLER_GRUB_THEMES=(
    [OverWatch]='ovWatch'
    [HellTaker]='myGrubTheme'
    [Tutel]='tutel'
    [IFUDARE]='IFUDARE'
    [Default]='default'
)

INSTALLER_GRUB_NAMES=($(echo ${!INSTALLER_GRUB_THEMES[*]} | tr ' ' '\n' | sort -n))

PS3='Please select a grub theme #: '
select l in "${INSTALLER_GRUB_NAMES[@]}"; do
    if [[ -v INSTALLER_GRUB_THEMES[$l] ]]; then
        GRUB_THEME=${INSTALLER_GRUB_THEMES[$l]}
        break
    else
        echo 'No such grub theme, try again'
    fi
done < /dev/tty

# Select language, optional
declare -A INSTALLER_LANGS=(
    [Chinese]=zh_CN
    [English]=EN
    [French]=FR
    [German]=DE
    [Italian]=IT
    [Norwegian]=NO
    [Portuguese]=PT
    [Russian]=RU
    [Rusyn]=RUE
    [Spanish]=ES
    [Turkish]=TR
    [Ukrainian]=UA
)

INSTALLER_LANG_NAMES=($(echo ${!INSTALLER_LANGS[*]} | tr ' ' '\n' | sort -n))

PS3='Please select language #: '
select l in "${INSTALLER_LANG_NAMES[@]}"; do
    if [[ -v INSTALLER_LANGS[$l] ]]; then
        INSTALLER_LANG=$l
        break
    else
        echo 'No such language, try again'
    fi
done < /dev/tty


if [[ $GRUB_THEME != 'default' ]]; then
    echo "Fetching and unpacking theme"
    wget https://github.com/rthouvenel/${GRUB_THEME}/archive/refs/heads/main.zip
    unzip main.zip
    cd ${GRUB_THEME}-main
fi

#if [[ "$INSTALLER_LANG" != "English" ]]; then
#     echo "Changing language to ${INSTALLER_LANG}"
#     sed -i -r -e '/^\s+# EN$/{n;s/^(\s*)/\1# /}' \
#               -e '/^\s+# '"${INSTALLER_LANGS[$INSTALLER_LANG]}"'$/{n;s/^(\s*)#\s*/\1/}' theme.txt
#fi

# Detect distro and set GRUB location and update method
GRUB_DIR='grub'
UPDATE_GRUB=''
BOOT_MODE='legacy'

if [[ -d /boot/efi && -d /sys/firmware/efi ]]; then
    BOOT_MODE='UEFI'
fi

echo "Boot mode: ${BOOT_MODE}"

if [[ -e /etc/os-release ]]; then

    ID=""
    ID_LIKE=""
    source /etc/os-release

    if [[ "$ID" =~ (debian|ubuntu|solus|void) || \
          "$ID_LIKE" =~ (debian|ubuntu|void) ]]; then

        UPDATE_GRUB='update-grub'

    elif [[ "$ID" =~ (arch|gentoo) || \
            "$ID_LIKE" =~ (archlinux|gentoo) ]]; then

        UPDATE_GRUB='grub-mkconfig -o /boot/grub/grub.cfg'

    elif [[ "$ID" =~ (centos|fedora|opensuse) || \
            "$ID_LIKE" =~ (fedora|rhel|suse) ]]; then

        GRUB_DIR='grub2'
        GRUB_CFG='/boot/grub2/grub.cfg'

        if [[ "$BOOT_MODE" = "UEFI" ]]; then
            GRUB_CFG="/boot/efi/EFI/${ID}/grub.cfg"
        fi

        UPDATE_GRUB="grub2-mkconfig -o ${GRUB_CFG}"

        # BLS etries have 'kernel' class, copy corresponding icon
        if [[ -d /boot/loader/entries && -e icons/${ID}.png ]]; then
            cp icons/${ID}.png icons/kernel.png
        fi
    fi
fi

if [[ $GRUB_THEME != 'default' ]]; then
    echo 'Creating GRUB themes directory'
    sudo mkdir -p /boot/${GRUB_DIR}/themes/${GRUB_THEME}

    echo 'Copying theme to GRUB themes directory'
    sudo cp -r ./theme/* /boot/${GRUB_DIR}/themes/${GRUB_THEME}
fi

echo 'Removing other themes from GRUB config'
sudo sed -i '/^GRUB_THEME=/d' /etc/default/grub

echo 'Making sure GRUB uses graphical output'
sudo sed -i 's/^\(GRUB_TERMINAL\w*=.*\)/#\1/' /etc/default/grub

echo 'Removing empty lines at the end of GRUB config' # optional
sudo sed -i -e :a -e '/^\n*$/{$d;N;};/\n$/ba' /etc/default/grub

echo 'Adding new line to GRUB config just in case' # optional
echo | sudo tee -a /etc/default/grub

if [[ $GRUB_THEME == 'default' ]]; then
    echo 'Adding theme to GRUB config'
    echo "GRUB_THEME=default" | sudo tee -a /etc/default/grub
else
    echo 'Adding theme to GRUB config'
    echo "GRUB_THEME=/boot/${GRUB_DIR}/themes/${GRUB_THEME}/theme.txt" | sudo tee -a /etc/default/grub
    echo 'Removing theme installation files'
    cd ..
    rm -rf "$PWD"
    cd
fi

echo 'Updating GRUB'
if [[ $UPDATE_GRUB ]]; then
    eval sudo "$UPDATE_GRUB"
else
    cat << '    EOF'
    --------------------------------------------------------------------------------
    Cannot detect your distro, you will need to run `grub-mkconfig` (as root) manually.

    Common ways:
    - Debian, Ubuntu, Solus and derivatives: `update-grub` or `grub-mkconfig -o /boot/grub/grub.cfg`
    - RHEL, CentOS, Fedora, SUSE and derivatives: `grub2-mkconfig -o /boot/grub2/grub.cfg`
    - Arch, Gentoo and derivatives: `grub-mkconfig -o /boot/grub/grub.cfg`
    --------------------------------------------------------------------------------
    EOF
fi
