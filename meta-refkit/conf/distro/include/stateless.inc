INHERIT += "stateless"

# Gets re-created by systemd already.
STATELESS_RM += "mtab"

# Both systemd and connman create this via tmpfiles.d. connman happens
# to win because it connman.conf sorts before etc.conf, but that's
# a bit brittle, so we ensure that connman wins if installed.
STATELESS_RM += " \
    resolv.conf \
"
STATELESS_POSTPROCESS_COMMAND += "stateless_connman_resolv_conf;"
stateless_connman_resolv_conf () {
    if [ -f "${IMAGE_ROOTFS}/${libdir}/tmpfiles.d/connman.conf" ] &&
       [ -f "${IMAGE_ROOTFS}/${libdir}/tmpfiles.d/etc.conf" ]; then
        sed -i -e 's;^\(. /etc/resolv.conf \);# stateless: replaced by connman: \1;' \
            "${IMAGE_ROOTFS}/${libdir}/tmpfiles.d/etc.conf"
    fi
}

# machine-id can be removed if the rootfs and thus /etc get mounted read/write,
# because then systemd is able to create it during early startup.
# Beware that removing machine-id triggers systemd's FirstBootCondition,
# which may or may not be intended because normally OE-based images
# always boot without it.
#
# systemd also enables units during such a first boot according to their [Install]
# section, which at least for wpa-supplicant turned out to be broken.
#
# The default is to remove machine-id when possible. This can be overriden
# with STATELESS_ETC_WHITELIST_append = "machine-id"
STATELESS_ETC_WHITELIST += " \
    ${@ 'machine-id' if 'ro' in (d.getVar('APPEND') or '').split() else '' } \
"
STATELESS_POSTPROCESS_COMMAND += "stateless_rm_machineid; "
stateless_rm_machineid () {
    if ${@ bb.utils.contains('STATELESS_ETC_WHITELIST', 'machine-id', 'false', 'true', d) }; then
        rm -f "${IMAGE_ROOTFS}${sysconfdir}/machine-id"
    fi
}

# Depend on the installed components and thus has to be computed on
# the device. Handled by systemd during booting or updates.
STATELESS_RM_ROOTFS += " \
    udev/hwdb.bin \
"

# Disable creation of /etc/ld.so.cache in images and bundles. The file
# gets already recreated by systemd anyway when booting. Has to be
# done by unsetting LDCONFIGDEPEND (checked by rootfs.py, which
# creates the ld.so.cache).
python () {
    if oe.types.boolean(d.getVar('STATELESS_ACTIVE')):
        d.setVar('LDCONFIGDEPEND', '')
}
