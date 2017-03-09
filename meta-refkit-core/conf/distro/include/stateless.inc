INHERIT += "stateless"

###########################################################################

# This entry here allows everything in /etc because IoT Reference OS Kit is
# not actually stateless yet. We merely use the stateless.bbclass
# to remove files from /etc which get written on the device
# and thus must be excluded from images and, more importantly,
# swupd bundles.
STATELESS_ETC_WHITELIST += "*"

# Empty directories must be kept.
STATELESS_ETC_DIR_WHITELIST += "*"

# Required to find local patches.
FILESEXTRAPATHS_prepend = "${META_REFKIT_BASE}/files/stateless/${PN}:"

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

# Do not bail out in "adduser" when /etc/passwd is missing.
STATELESS_SRC_append_pn-busybox = " \
    file://adduser-enable-use-without-etc-passwd.patch None \
"

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

# Enable logins without /etc/login.defs.
STATELESS_SRC_append_pn-shadow = " \
    https://raw.githubusercontent.com/clearlinux-pkgs/shadow/2aae81d2f493e340f454e6888c79f71c0414726c/0001-Do-not-bail-out-on-missing-login.defs.patch \
    7bf3f3df680fe1515deca2e7bc1715759616f101156650c95172366a79817662 \
    https://raw.githubusercontent.com/clearlinux-pkgs/shadow/2aae81d2f493e340f454e6888c79f71c0414726c/stateless-login.patch \
    3bb9bc5936111fac2cfd9723423281c98533740c5ca564152488d9ba33021cc5 \
"

# Required for setting root password when /etc is empty, because
# otherwise PAM's "is changing the password allowed" check fails,
# leading to a "permission denied" error before the password prompt.
STATELESS_SRC_append_pn-libpam = " \
    https://raw.githubusercontent.com/clearlinux-pkgs/Linux-PAM/b71399c80514afa9411b00aef2be721338a77893/0002-Support-altfiles-locations.patch \
    53636e3e68a60cef4012735d881cffbd3e653b104e55d94d05826c48b8ec9830 \
"

# Use /usr/share/pam.d instead of /usr/lib/pam.d (for the sake of consistency?)
# and move /etc files to it. We must prevent systemd from re-creating the files
# from its own builtin copies.
STATELESS_SRC_append_pn-libpam = " \
    https://raw.githubusercontent.com/clearlinux-pkgs/Linux-PAM/b71399c80514afa9411b00aef2be721338a77893/0001-libpam-Keep-existing-pamdir-for-transition.patch \
    25761101f785878dc7817344f484f670de5723df2eccc17dad9236af446cb890 \
"
STATELESS_MV_ROOTFS += "pam.d=${datadir}/pam.d"
STATELESS_POST_POSTPROCESS += " stateless_rm_systemd_pamd_factory;"
stateless_rm_systemd_pamd_factory () {
    rm -rf ${IMAGE_ROOTFS}${datadir}/factory/etc/pam.d
    if [ -f ${IMAGE_ROOTFS}${libdir}/tmpfiles.d/etc.conf ]; then
        sed -i -e 's;^\(C */etc/pam.d *.*\);# stateless: \1;' \
            ${IMAGE_ROOTFS}${libdir}/tmpfiles.d/etc.conf
    fi
}

# Allow logins without /etc/login.defs, /etc/securetty or /etc/shells.
STATELESS_SRC_append_pn-libpam = " \
    https://raw.githubusercontent.com/clearlinux-pkgs/Linux-PAM/0681d308b660919e6a7ee71be41397dbc8516519/0003-pam_env-Only-report-non-ENOENT-errors-for-env-file.patch \
    5b6866931e70524ed29cc2b2f5abf31f732658441207d441ec00cbcb9f04833e \
    https://raw.githubusercontent.com/clearlinux-pkgs/Linux-PAM/aa0bf6295ec8faa96cad1094806a545aae03247e/0004-pam_shells-Support-a-stateless-configuration-by-defa.patch \
    35d3ca298728aab229b1b82e01ae6b7d0f7be11b0e71c7d18d92ebc8069087aa \
"
STATELESS_MV_ROOTFS += " \
    login.defs \
    securetty \
    shells \
"

# TODO (?): avoid log entry about "Couldn't open /etc/securetty" each time
# pam_securetty is used. Written for libpam 1.2.1, does not apply to 1.3.0
# because the code was modified. Not particularly important as pam_securetty
# seems unused in OE-core.
#SRC_URI_append_pn-libpam = " \
#    https://raw.githubusercontent.com/clearlinux-pkgs/Linux-PAM/0681d308b660919e6a7ee71be41397dbc8516519/0001-pam_securetty-Do-not-report-non-fatal-documented-beh.patch \
#"

# Both connman and systemd create this via tmpfiles.d, no need to
# have it in /etc.
STATELESS_RM_ROOTFS += " \
    resolv.conf \
"
# When connman is installed, the intent probably is to use it also as
# resolver. This happens to work in practice (connman_resolvconf.conf
# sorts before etc.conf), but systemd warns about the conflict.
# Better avoid that conflict.
STATELESS_POST_POSTPROCESS += " stateless_pick_resolv_conf; "
stateless_pick_resolv_conf () {
    if ( [ -e ${IMAGE_ROOTFS}${sysconfdir}/tmpfiles.d/connman_resolvconf.conf ] ||
        [ -e ${IMAGE_ROOTFS}${libdir}/tmpfiles.d/connman_resolvconf.conf ] ) &&
       [ -f ${IMAGE_ROOTFS}${libdir}/tmpfiles.d/etc.conf ]; then
        sed -i -e 's;^\(L.* /etc/resolv.conf *.*\);# provided by connman: \1;' \
            ${IMAGE_ROOTFS}${libdir}/tmpfiles.d/etc.conf
    fi
}

# machine-id has to be present in images at least as an empty file
# because we might boot with the rootfs read/only. Otherwise
# creating it during early boot fails (see
# systemd/src/core/machine-id-setup.c).
STATELESS_ETC_WHITELIST += "machine-id"

# These files must be ignored by swupd.
STATEFUL_FILES += "/etc/machine-id"
SWUPD_FILE_BLACKLIST_append = " ${STATEFUL_FILES}"

# We can use the pre-generated hwdb.bin as OS default while still
# allowing the creation of an updated version in /etc later on.
# systemd-update-done.service will only run when there is
# something to update in /etc and there are rules in /etc, so
# we clean that up, too.
STATELESS_MV_ROOTFS += " \
    udev/hwdb.bin=${base_libdir}/udev/hwdb.bin \
    udev/hwdb.d=${base_libdir}/udev/hwdb.d \
"

# Disable creation of /etc/ld.so.cache in stateless images. The file
# gets already recreated by systemd anyway when booting. Has to be
# done by unsetting LDCONFIGDEPEND (checked by rootfs.py, which
# creates the ld.so.cache) for all IoT Reference OS Kit images, but not the
# refkit-initramfs, so we cannot set it unconditionally.
python () {
    if not oe.types.boolean(d.getVar('STATELESS_EXCLUDED')):
        d.setVar('LDCONFIGDEPEND', '')
}

# Move away ld.so.conf and let systemd's factory reset mechanism re-create
# it during boot. For this to work reliably, ldconfig.service must run
# after systemd-tmpfiles-setup.service. Normally they run in parallel.
STATELESS_MV_ROOTFS += " \
    ld.so.conf=factory:ldconfig.service \
"

# Anything related to tmpfiles.d in /etc can be considered part of the
# OS and thus be moved to /usr/lib. This includes /etc files which are
# named exactly like existing files under /usr/lib: the ones from
# /usr/lib get overwritten, which preserves the semantic that /etc has
# higher priority.
STATELESS_MV_ROOTFS += " \
    tmpfiles.d=${libdir}/tmpfiles.d \
"

# Similar for udev. There's just a slight change of semantic:
# entries in /etc override those from /run, which they no longer
# do after being moved to /usr/lib - shouldn't matter in practice.
STATELESS_MV_ROOTFS += " \
    udev/rules.d=${base_libdir}/udev/rules.d \
"

# By ensuring that udevd starts after tmpfiles, we can move
# its main config file into the factory defaults.
STATELESS_MV_ROOTFS += " \
    udev/udev.conf=factory:systemd-udevd.service \
"

# Move /etc/terminfo to /lib/terminfo. That's still going to be
# used before /usr/share/terminfo.
STATELESS_MV_ROOTFS += " \
    terminfo=${base_libdir}/terminfo \
"

# systemd/system.conf and systemd/journald.conf can be moved to
# /usr/share/doc if and only if they only contains the default,
# commented out values, because non-default values must already be set
# before these daemons start.
#
# For journald.conf that is problematic, because systemd_232.bb
# changes journald.conf instead of compiling systemd with different
# defaults. That could be changed. For now we ignore those
# modifications and thus accept that the first boot without
# journald.conf will not run quite as it would normally.
#
# Service settings can be moved to /usr because they are part
# of the system.
#
# All remaining systemd config files may or may not have been
# modified and thus get treated as factory defaults.
STATELESS_POST_POSTPROCESS += " stateless_mv_systemd_conf;"
stateless_mv_systemd_conf () {
    for config in system.conf journald.conf; do
        if [ -e ${IMAGE_ROOTFS}${sysconfdir}/systemd/$config ]; then
            if settings=`grep -v -e '^\[.*\]$' -e '^#' -e '^$' -e '^RuntimeMaxUse=' -e '^ForwardToSyslog=' ${IMAGE_ROOTFS}/etc/systemd/$config`; then
                bbfatal "stateless: ${IMAGE_ROOTFS}/etc/systemd/$config contains more than just comments, cannot remove:\n$settings"
            fi
            mkdir -p ${IMAGE_ROOTFS}${datadir}/doc/etc/systemd
            mv ${IMAGE_ROOTFS}${sysconfdir}/systemd/$config ${IMAGE_ROOTFS}${datadir}/doc/etc/systemd
        fi
    done
}
STATELESS_MV_ROOTFS += " \
    systemd/system=${systemd_system_unitdir} \
    xdg/systemd=factory \
    systemd=factory \
"

# Several files in /etc/ssl can become factory defaults.
# /etc/ssl/certs and /etc/ssl itself will be dealt with below.
STATELESS_MV_ROOTFS += " \
    ssl/openssl.cnf=factory \
    ssl/private=factory \
"
REFKIT_QA_IMAGE_SYMLINK_WHITELIST_append = " \
    ${sysconfdir}/ssl/openssl.cnf \
    ${sysconfdir}/ssl/private \
"

# We could just dump /etc/ssl/certs entirely into the factory
# defaults, but that sounds redundant, because the content
# is already generated from read-only system content. Instead,
# we extend systemd-tmpfiles-setup.service so that it
# also runs update-ca-certificates.
STATELESS_POST_POSTPROCESS += " stateless_rm_etc_ssl_certs;"
stateless_rm_etc_ssl_certs () {
    if [ -e ${IMAGE_ROOTFS}${sbindir}/update-ca-certificates ] &&
       [ -e ${IMAGE_ROOTFS}${systemd_system_unitdir}/systemd-tmpfiles-setup.service ]; then
        echo "ExecStartPost=/bin/sh -c '[ -e ${sysconfdir}/ssl/certs/ca-certificates.crt ] || ${sbindir}/update-ca-certificates'" >>${IMAGE_ROOTFS}${systemd_system_unitdir}/systemd-tmpfiles-setup.service
        rm -rf ${IMAGE_ROOTFS}${sysconfdir}/ssl/certs
        # If empty now, /etc/ssl can be removed, too.
        if rmdir ${IMAGE_ROOTFS}${sysconfdir}/ssl; then
            echo "d ${sysconfdir}/ssl 0755 root root - -" >>${IMAGE_ROOTFS}${libdir}/tmpfiles.d/stateless.conf
        fi
        echo "d ${sysconfdir}/ssl/certs 0755 root root - -" >>${IMAGE_ROOTFS}${libdir}/tmpfiles.d/stateless.conf
    fi
}
REFKIT_QA_IMAGE_SYMLINK_WHITELIST_append = " \
    ${sysconfdir}/ssl/certs \
"
