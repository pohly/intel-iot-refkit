# The goal of this class is to enable booting with an entirely empty
# /etc. When that works, factory resets become easy (just wipe out
# /etc). System updates also become easier, because all configuration
# files are part of the read-only /usr.
#
# The goal is not to have an entirely empty /etc at runtime. There are
# too many components which still expect files there for this to be
# practical. This is covered by copying files from the read-only
# default to /etc or generate files in /etc. This can be repeated
# after a system update to also update /etc.
#
# Except for patching some components to work better without files
# in /etc, most of the necessary changes happen during rootfs
# construction, so the same distro can be used to create "normal"
# and "stateless" images.
#
# This transformation happens after all normal ROOTFS_POSTPROCESS_COMMANDs
# are run (more specifically, in ROOTFS_POSTUNINSTALL_COMMAND). That
# is necessary because several commands still need the full /etc (like
# setting an empty root password).

# 1/True/Yes when an image is meant to be stateless, 0/False/No
# otherwise.  The default is to not modified read-only images
# (detected based on the read-only image feature or the special
# IMAGE_FSTYPES used by an initramfs) and to modify everything else.
STATELESS_ACTIVE ??= "${@ '0' if 'read-only' in (d.getVar('IMAGE_FEATURES') or '').split() or d.getVar('IMAGE_FSTYPES') == d.getVar('INITRAMFS_FSTYPES') else '1' }"

# A space-separated list of shell patterns. Anything matching a
# pattern is allowed in /etc. Changing this influences the QA check in
# do_rootfs.
STATELESS_ETC_WHITELIST ??= "${STATELESS_ETC_DIR_WHITELIST}"

# A subset of STATELESS_ETC_WHITELIST which also influences do_install
# and determines which directories to keep.
STATELESS_ETC_DIR_WHITELIST ??= ""

# A space-separated list of entries in /etc which need to be moved
# away. Default is to move into ${datadir}/doc/${PN}/etc. The actual
# new name can also be given with old-name=new-name, as in
# "pam.d=${datadir}/pam.d".
#
# As a special case, old-name=factory moves
# into the factory defaults under /usr/lib/factory. A systemd tmpfiles.d
# entry will be created for that which restores the content at early
# boot.
#
# TODO: systemd services that depend on moved files?
STATELESS_MV ?= ""

# A space-separated list of entries in /etc which can be removed
# entirely.
STATELESS_RM ?= ""

# A list of semicolon-separated commands that get executed after all
# normal ROOTFS_POSTPROCESS_COMMANDs if (and only if) the current
# image is meant to be stateless.
STATELESS_POSTPROCESS_COMMAND ?= ""

# A list of <url> <sha256sum> pairs which get injected into SRC_URI
# SRC_URI[<name>.sha256sum] of a receipe. This way, a distro-level
# include file can add source code or patches into specific recipes
# via STATELESS_SRC_pn-<recipe>. This is necessary because
# _append_pn-<recipe> does not work for SRC_URI[<name>.sha256sum].
STATELESS_SRC ?= ""

###########################################################################

# Apply STATELESS_SRC.
python () {
    import os
    import urllib

    src = d.getVar('STATELESS_SRC').split()
    if len(src) % 2:
        bb.fatal('STATELESS_SRC must contain a list of <url> <sha256sum> pairs, got odd number of entries instead: %s' % src)
    while src:
        url = src.pop(0)
        hash = src.pop(0)
        path = urllib.parse.urlparse(url).path
        name = os.path.basename(path)
        url = url + ';name=%s' % name
        d.appendVar('SRC_URI', url)
        d.setVarFlag('SRC_URI', '%s.sha256sum', hash)
}

def stateless_is_whitelisted(etcentry, whitelist):
    import fnmatch
    for pattern in whitelist:
        if fnmatch.fnmatchcase(etcentry, pattern):
            return True
    return False

def stateless_mangle(d, root, docdir, stateless_mv, stateless_rm, dirwhitelist, is_package):
    import os
    import errno
    import shutil

    # Remove content that is no longer needed.
    for entry in stateless_rm:
        old = os.path.join(root, 'etc', entry)
        if os.path.exists(old) or os.path.islink(old):
            bb.note('stateless: removing %s' % old)
            if os.path.isdir(old) and not os.path.islink(old):
                shutil.rmtree(old)
            else:
                os.unlink(old)

    # Move away files. Default target is docdir, but others can
    # be set by appending =<new name> to the entry, as in
    # tmpfiles.d=libdir/tmpfiles.d
    for entry in stateless_mv:
        paths = entry.split('=', 1)
        etcentry = paths[0]
        old = os.path.join(root, 'etc', etcentry)
        if os.path.exists(old) or os.path.islink(old):
            if len(paths) > 1:
                new = root + paths[1]
            else:
                new = os.path.join(docdir, entry)
            destdir = os.path.dirname(new)
            bb.utils.mkdirhier(destdir)
            # Also handles moving of directories where the target already exists, by
            # moving the content. When moving a relative symlink the target gets updated.
            def move(old, new):
                bb.note('stateless: moving %s to %s' % (old, new))
                if os.path.isdir(new):
                    for entry in os.listdir(old):
                        move(os.path.join(old, entry), os.path.join(new, entry))
                    os.rmdir(old)
                else:
                    os.rename(old, new)
            move(old, new)

    # Remove /etc if all that's left are directories.
    # Some directories are expected to exists (for example,
    # update-ca-certificates depends on /etc/ssl/certs),
    # so if a directory is white-listed, it does not get
    # removed.
    etcdir = os.path.join(root, 'etc')
    def tryrmdir(path):
        if is_package and \
           path.endswith('/etc/modprobe.d') or \
           path.endswith('/etc/modules-load.d'):
           # Expected to exist by kernel-module-split.bbclass
           # which will clean it itself.
           return
        if stateless_is_whitelisted(path[len(etcdir) + 1:], dirwhitelist):
           bb.note('stateless: keeping white-listed directory %s' % path)
           return
        bb.note('stateless: removing dir %s' % path)
        try:
            os.rmdir(path)
        except OSError as ex:
            bb.note('stateless: removing dir failed: %s' % ex)
            if ex.errno != errno.ENOTEMPTY:
                 raise
    if os.path.isdir(etcdir):
        for root, dirs, files in os.walk(etcdir, topdown=False):
            for dir in dirs:
                path = os.path.join(root, dir)
                if os.path.islink(path):
                    files.append(dir)
                else:
                    tryrmdir(path)
            for file in files:
                bb.note('stateless: /etc not empty: %s' % os.path.join(root, file))
        tryrmdir(etcdir)


ROOTFS_POSTUNINSTALL_COMMAND_append = "\
    ${@ '${STATELESS_POSTPROCESS_COMMAND} stateless_mangle_rootfs;' if oe.types.boolean(d.getVar('STATELESS_ACTIVE')) else '' } \
"

python stateless_mangle_rootfs () {
    rootfsdir = d.getVar('IMAGE_ROOTFS', True)
    docdir = rootfsdir + d.getVar('datadir', True) + '/doc/etc'
    whitelist = (d.getVar('STATELESS_ETC_WHITELIST', True) or '').split()
    stateless_mangle(d, rootfsdir, docdir,
                     (d.getVar('STATELESS_MV', True) or '').split(),
                     (d.getVar('STATELESS_RM', True) or '').split(),
                     whitelist,
                     False)
    import os
    etcdir = os.path.join(rootfsdir, 'etc')
    valid = True
    for dirpath, dirnames, filenames in os.walk(etcdir):
        for entry in filenames + [x for x in dirnames if os.path.islink(x)]:
            fullpath = os.path.join(dirpath, entry)
            etcentry = fullpath[len(etcdir) + 1:]
            if not stateless_is_whitelisted(etcentry, whitelist):
                bb.warn('stateless: rootfs should not contain %s' % fullpath)
                valid = False
    if not valid:
        bb.fatal('stateless: /etc not empty')
}
