INHERIT += "stateless"

###########################################################################

# Temporary overrides until IoT Reference OS Kit is fully stateless.

# This entry here allows everything in /etc because IoT Reference OS Kit is
# not actually stateless yet. We merely use the stateless.bbclass
# to remove files from /etc which get written on the device
# and thus must be excluded from images and, more importantly,
# swupd bundles.
STATELESS_ETC_WHITELIST += "*"

# Empty directories must be kept.
STATELESS_ETC_DIR_WHITELIST += "*"

# The initramfs is read-only and thus doesn't need to be stateless.
STATELESS_EXCLUDED_pn-refkit-initramfs = "1"

###########################################################################

# As step towards full stateless IoT Reference OS Kit, we now
# treat some files in /etc as conceptually read-only (i.e. neither
# modified by the OS at runtime nor by an admin). Anything contained
# in the rootfs directories will get bundled and added or updated when
# running "swupd update".
#
# The implication is that we must keep certain files out of the rootfs
# which do get modified at runtime, because otherwise there are
# "swupd verify" failures.

# mtab needs to be a symlink to /proc/mounts, probably forever.
# There is no point in patching that out of binaries, nor is there
# a need to customize it, so the symlink can remain there as read-only
# system component.
STATELESS_ETC_WHITELIST += "mtab"

# Whether the netbase files (services, protocols, hosts, rpc) need to
# be relocated depends on the image. It will be done during image
# creation.
STATELESS_EXCLUDED_pn-netbase = "1"

# Enables the use of /usr/defaults/etc/nsswitch.conf as fallback
# for /etc/nsswitch.conf.
STATELESS_SRC_append_pn-glibc = " \
    https://raw.githubusercontent.com/clearlinux-pkgs/glibc/e54b638ef6b5f838e99f1f055474ef2603dfce19/nsswitch-altfiles.patch \
    82b66bc66d935aed845ae51d0ea7188dbc964ae17bda715f7114805ef5cc915d \
"

# Install nss-altfiles and activate it in /usr/defaults/etc/nsswitch.conf,
# unless the image is not stateless. We do this after other ROOTFS_POSTPROCESS_COMMAND
# because then setting a default root password makes it into the read-only
# defaults which - if done - is probably intended for debug images.
STATELESS_EXTRA_INSTALL += "nss-altfiles"
STATELESS_POST_POSTPROCESS += " stateless_activate_altfiles;"

stateless_activate_altfiles () {
    # This adds "altfiles" as fallback after "compat" or "files"
    # and moves nsswitch.conf out of /etc. This intentionally
    # fails when the image does not already have nsswitch.conf
    # (and thus presumably uses NSS), because altfiles relies on NSS.
    #
    # nsswitch.conf also gets moved to /usr and is not needed anymore
    # in /etc (see stateless_glibc_altfiles_patch), so we don't need
    # (and in fact, must not) let systemd re-create it during boot.
    install -d ${IMAGE_ROOTFS}${datadir}/defaults/etc
    sed -e 's/files/files altfiles/' -e 's/compat/compat altfiles/' \
        ${IMAGE_ROOTFS}/${sysconfdir}/nsswitch.conf \
        >${IMAGE_ROOTFS}${datadir}/defaults/etc/nsswitch.conf
    rm ${IMAGE_ROOTFS}/${sysconfdir}/nsswitch.conf
    rm -f ${IMAGE_ROOTFS}${datadir}/factory/etc/nsswitch.conf
    if [ -f ${IMAGE_ROOTFS}${libdir}/tmpfiles.d/etc.conf ]; then
        sed -i -e 's;^\(C */etc/nsswitch.conf *.*\);# stateless: \1;' \
            ${IMAGE_ROOTFS}${libdir}/tmpfiles.d/etc.conf
    fi
}

STATELESS_ALTFILES = "hosts services protocols rpc passwd group shadow gshadow"
STATELESS_MV_ROOTFS += " \
    ${@ ' '.join('%s=${datadir}/defaults/etc/%s' % (x,x) for x in '${STATELESS_ALTFILES}'.split())} \
"

# Teach shadow about altfiles in /usr/defaults/etc and /usr/defaults/skel.
# For example, setting a password will copy an existing entry from there into /etc.
# TODO (?): Busybox adduser does not work when /etc/passwd is missing.
STATELESS_SRC_append_pn-shadow = " \
    https://raw.githubusercontent.com/clearlinux-pkgs/shadow/2aae81d2f493e340f454e6888c79f71c0414726c/0003-Do-not-fail-on-missing-files-in-etc-create-them-inst.patch \
    3df4182a48a60dc796a2472812adc1a96146c461e6951646c4baaf47e80ed943 \
    https://raw.githubusercontent.com/clearlinux-pkgs/shadow/2aae81d2f493e340f454e6888c79f71c0414726c/0004-Force-use-shadow-even-if-missing.patch \
    8e744ae7779b64d7d9668dc2e9bbf42840dd4ed668b66c6bc22bd88837914bd5 \
    https://raw.githubusercontent.com/clearlinux-pkgs/shadow/2aae81d2f493e340f454e6888c79f71c0414726c/0005-Create-dbs-with-correct-permissions.patch \
    cb669ad9e99fba3672733524d4e8671b69a86d303f02d915580fc8af586c2aef \
    https://raw.githubusercontent.com/clearlinux-pkgs/shadow/2aae81d2f493e340f454e6888c79f71c0414726c/0006-Make-usermod-read-altfiles.patch \
    618e1c6b80f03143c614c9338284cae7928b8fed0a726eed6d8b6f38fdb3d5e5 \
    https://raw.githubusercontent.com/clearlinux-pkgs/shadow/2aae81d2f493e340f454e6888c79f71c0414726c/stateless-adduser.patch \
    8fff0b1c52712050b3652d26c8a5faf2acc4cf458964c04a6ca1d28d1d928f2e \
    https://raw.githubusercontent.com/clearlinux-pkgs/shadow/6d0c85ab07e6c7dd399953f3b9fc24947f910bc8/stateless-gpasswd.patch \
    e79a3fac817240ebe3144bab67e7ab5f1247b28b59310a13aa9f2cca33d20451 \
    https://raw.githubusercontent.com/clearlinux-pkgs/shadow/2aae81d2f493e340f454e6888c79f71c0414726c/stateless-useradd.patch \
    6f47bd7c5df44a1c4dab1bd102c5a8f0f60cf40fd5c6b4c1afd6f7758f280162 \
    https://raw.githubusercontent.com/clearlinux-pkgs/shadow/d34359528e24569457b8ee8f66d6f2991a291c67/stateless-usermod.patch \
    af825f9c02834eb7ec34f3ef4c1db0dbc2aed985d02e1c3bc6e8deba5f4ebf68 \
"

# Required for setting root password when /etc is empty, because
# otherwise PAM's "is changing the password allowed" check fails,
# leading to a "permission denied" error before the password prompt.
STATELESS_SRC_append_pn-libpam = " \
    https://raw.githubusercontent.com/clearlinux-pkgs/Linux-PAM/b71399c80514afa9411b00aef2be721338a77893/0002-Support-altfiles-locations.patch \
    53636e3e68a60cef4012735d881cffbd3e653b104e55d94d05826c48b8ec9830 \
"

# OE-core puts some files into /etc which systemd then later overwrites
# unconditionally via /usr/lib/tmpfile.d/etc.conf or creates dynamically
# (machine-id). Therefore we can remove the redundant files from our rootfs
# by not packaging them in the first place.
STATELESS_RM_pn-systemd += " \
    resolv.conf \
"

# machine-id has to be present in images at least as an empty file
# because we might boot with the rootfs read/only. Otherwise
# creating it during early boot fails (see
# systemd/src/core/machine-id-setup.c).
STATELESS_ETC_WHITELIST += "machine-id"

# These files must be ignored by swupd.
STATEFUL_FILES += "/etc/machine-id"
SWUPD_FILE_BLACKLIST_append = " ${STATEFUL_FILES}"

# Depend on the installed components and thus has to be computed on
# the device. Handled by systemd during booting or updates.
STATELESS_RM_ROOTFS += " \
    udev/hwdb.bin \
"

# Disable creation of /etc/ld.so.cache in images and bundles. The file
# gets already recreated by systemd anyway when booting. Has to be
# done by unsetting LDCONFIGDEPEND (checked by rootfs.py, which
# creates the ld.so.cache) for all IoT Reference OS Kit images, but not the
# refkit-initramfs, so we cannot set it unconditionally.
python () {
    if bb.data.inherits_class('refkit-image', d):
        d.setVar('LDCONFIGDEPEND', '')
}
