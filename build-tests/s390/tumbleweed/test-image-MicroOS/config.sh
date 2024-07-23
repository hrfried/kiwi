#!/bin/bash
# shellcheck disable=SC1091
test -f /.kconfig && . /.kconfig

set -euxo pipefail

declare kiwi_iname=${kiwi_iname}
declare kiwi_profiles=${kiwi_profiles}

echo "Configure image: [${kiwi_iname}]-[${kiwi_profiles}]..."

# Systemd controls the console font now
echo FONT="eurlatgr.psfu" >> /etc/vconsole.conf

#======================================
# Specify default systemd target
#--------------------------------------
baseSetRunlevel multi-user.target

# Add repos from /etc/YaST2/control.xml
if [ -x /usr/sbin/add-yast-repos ]; then
    add-yast-repos
    zypper --non-interactive rm -u live-add-yast-repos
fi

# Adjust zypp conf
sed -i 's/^multiversion =.*/multiversion =/g' /etc/zypp/zypp.conf

#=====================================
# Configure snapper
#-------------------------------------
if [ "${kiwi_btrfs_root_is_snapshot-false}" = 'true' ]; then
    echo "creating initial snapper config ..."
    cp /usr/share/snapper/config-templates/default /etc/snapper/configs/root
    baseUpdateSysConfig /etc/sysconfig/snapper SNAPPER_CONFIGS root

    # Adjust parameters
    sed -i'' 's/^TIMELINE_CREATE=.*$/TIMELINE_CREATE="no"/g' /etc/snapper/configs/root
    sed -i'' 's/^NUMBER_LIMIT=.*$/NUMBER_LIMIT="2-10"/g' /etc/snapper/configs/root
    sed -i'' 's/^NUMBER_LIMIT_IMPORTANT=.*$/NUMBER_LIMIT_IMPORTANT="4-10"/g' /etc/snapper/configs/root
fi

#=====================================
# Enable chrony if installed
#-------------------------------------
if [ -f /etc/chrony.conf ]; then
    systemctl enable chronyd
fi

#======================================
# Activate services
#--------------------------------------
baseInsertService sshd

# To make x-systemd.growfs work from inside the initrd
cat >/etc/dracut.conf.d/50-microos-growfs.conf <<"EOF"
install_items+=" /usr/lib/systemd/systemd-growfs "
EOF

# For image tests with an extra boot partition the
# kernel must not be a symlink to another area of
# the filesystem. Latest changes on SUSE changed the
# layout of the kernel which breaks every image with
# an extra boot partition
#
# All of the following is more than a hack and I
# don't like it all
#
# Complains and discussions about this please with
# the SUSE kernel team as we in kiwi can just live
# with the consequences of this change
#
pushd /

for file in /boot/* /boot/.*; do
    if [ -L "${file}" ];then
        link_target=$(readlink "${file}")
        if [[ ${link_target} =~ usr/lib/modules ]];then
            mv "${link_target}" "${file}"
        fi
    fi
done
