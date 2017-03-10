# This moves files out of /etc. It gets applied during
# rootfs creation, so packages do not need to be modified
# (although configuring them differently may lead to
# better results).

# If set to True, a recipe gets configured with
# sysconfdir=${datadir}/defaults. If set to a path, that
# path is used instead. In both cases, /etc typically gets
# ignored and the component no longer can be configured by
# the device admin.
STATELESS_RELOCATE ??= "False"

# Set to a true boolean value 1/True for a recipe when it does not
# need to be stateless, for example with
# STATELESS_EXCLUDE_pn-core-image-sato = "1"
#
# The default is to exclude images which have
# the "read-only" image feature set, because in those /etc can
# be considered part of the read-only OS, and images
# which are built as initramfs (detected based on their
# IMAGE_FSTYPES).
STATELESS_EXCLUDED ??= "${@ '1' if \
    bb.data.inherits_class('image', d) and \
    ('read-only' in d.getVar('IMAGE_FEATURES').split() or \
     d.getVar('IMAGE_FSTYPES') == d.getVar('INITRAMFS_FSTYPES')) \
    else '0' }"

# A space-separated list of shell patterns. Anything matching a
# pattern is allowed in /etc. Changing this influences the QA check in
# do_rootfs.
STATELESS_ETC_WHITELIST ??= "${STATELESS_ETC_DIR_WHITELIST}"

# A subset of STATELESS_ETC_WHITELIST which determines which directories
# to keep in /etc although they are empty. Normally such directories
# get removed.
STATELESS_ETC_DIR_WHITELIST ??= ""

# A space-separated list of entries in /etc which need to be moved
# away. Default is to move into ${datadir}/doc/${PN}/etc. The actual
# new name can also be given with old-name=new-name, as in
# "pam.d=${datadir}/pam.d".
#
# "factory" as special target name moves the item under
# /usr/share/factory/etc and adds it to
# /usr/lib/tmpfiles.d/stateless.conf, so systemd will re-recreate
# when missing. This runs after journald has been started and local
# filesystems are mounted, so things required by those operations
# cannot use the factory mechanism.
#
# Gets applied before the normal ROOTFS_POSTPROCESS_COMMANDs.
STATELESS_MV_ROOTFS ??= ""

# A space-separated list of entries in /etc which can be removed
# entirely.
STATELESS_RM_ROOTFS ??= ""

# Semicolon-separated commands which get run after RM/MV ROOTFS
# changes and before the normal ROOTFS_POSTPROCESS_COMMAND, if
# the image is meant to be stateless.
STATELESS_PRE_POSTPROCESS ??= ""

# Semicolon-separated commands which get run after the normal
# ROOTFS_POSTPROCESS_COMMAND, if the image is meant to be stateless.
STATELESS_POST_POSTPROCESS ??= ""

# Extra packages to be installed into stateless images.
STATELESS_EXTRA_INSTALL ??= ""

# STATELESS_SRC can be used to inject source code or patches into
# SRC_URI of a recipe. It is a list of <url> <sha256sum> pairs.
# This is similar to:
# SRC_URI_pn-foo = "http://some.example.com/foo.patch;name=foo"
# SRC_URI[foo.sha256sum] = "1234"
#
# Setting the hash sum that way has the drawback of namespace
# collisions and triggering a world rebuilds for each varflag change,
# because SRC_URI is modified for all recipes (in contrast to
# normal variables, there's no syntax for setting varflags
# per recipe). STATELESS_SRC avoids that because it gets expanded
# seperately for each recipe.
STATELESS_SRC = ""

python () {
    import urllib
    import os
    import string
    src = d.getVar('STATELESS_SRC').split()
    while src:
        url = src.pop(0)
        if not src:
            bb.fatal('STATELESS_SRC must contain pairs of url + shasum')
        shasum = src.pop(0)
        name = os.path.basename(urllib.parse.urlparse(url).path)
        name = ''.join(filter(lambda x: x in string.ascii_letters, name))
        d.appendVar('SRC_URI', ' %s;name=%s' % (url, name))
        d.setVarFlag('SRC_URI', '%s.sha256sum' % name, shasum)
}

###########################################################################

# TODO: using _prepend and _append does not completely ensure the intended
# semantic, because other commands might be injected the same way
# and then ordering is not deterministic. For example, sort_passwd ends
# up running after removing /etc/passwd, which defeats the purpose.
ROOTFS_POSTPROCESS_COMMAND_prepend = "${@ '${STATELESS_PRE_POSTPROCESS}' if not oe.types.boolean('${STATELESS_EXCLUDED}') else '' }"
ROOTFS_POSTPROCESS_COMMAND_append = "${@ '${STATELESS_POST_POSTPROCESS}' if not oe.types.boolean('${STATELESS_EXCLUDED}') else '' }"

CORE_IMAGE_EXTRA_INSTALL .= "${@ ' ${STATELESS_EXTRA_INSTALL}' if not oe.types.boolean('${STATELESS_EXCLUDED}') else '' }"

def stateless_is_whitelisted(etcentry, whitelist):
    import fnmatch
    for pattern in whitelist:
        if fnmatch.fnmatchcase(etcentry, pattern):
            return True
    return False

def stateless_mangle(d, root, docdir, stateless_mv, stateless_rm, dirwhitelist, is_package):
    import os
    import stat
    import errno
    import shutil

    tmpfilesdir = '%s%s/tmpfiles.d' % (root, d.getVar('libdir'))

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
    # tmpfiles.d=libdir/tmpfiles.d. "factory" as target adds
    # the file to those restored by systemd if missing.
    for entry in stateless_mv:
        paths = entry.split('=', 1)
        etcentry = paths[0]
        old = os.path.join(root, 'etc', etcentry)
        if os.path.exists(old) or os.path.islink(old):
            factory = False
            tmpfiles_before = []
            if len(paths) > 1:
                if paths[1] == 'factory' or paths[1].startswith('factory:'):
                    new = root + '/usr/share/factory/etc/' + paths[0]
                    factory = True
                    parts = paths[1].split(':', 1)
                    if len(parts) > 1:
                        tmpfiles_before = parts[1].split(',')
                    (paths[1].split(':', 1)[1:] or [''])[0].split(',')
                else:
                    new = root + paths[1]
            else:
                new = os.path.join(docdir, entry)
            destdir = os.path.dirname(new)
            bb.utils.mkdirhier(destdir)
            # Also handles moving of directories where the target already exists, by
            # moving the content. Symlinks are made relative to the target
            # directory.
            oldtop = old
            moved = []
            def move(old, new):
                bb.note('stateless: moving %s to %s' % (old, new))
                moved.append('/' + os.path.relpath(old, root))
                if os.path.islink(old):
                    link = os.readlink(old)
                    if link.startswith('/'):
                        target = root + link
                    else:
                        target = os.path.join(os.path.dirname(old), link)
                    target = os.path.normpath(target)
                    if not factory and os.path.relpath(target, oldtop).startswith('../'):
                        # Target outside of the root of what we are moving,
                        # so the target must remain the same despite moving
                        # the symlink itself.
                        link = os.path.relpath(target, os.path.dirname(new))
                    else:
                        # Target also getting moved or the symlink will be restored
                        # at its current place, so keep link relative
                        # to where it is now.
                        link = os.path.relpath(target, os.path.dirname(old))
                    if os.path.lexists(new):
                        os.unlink(new)
                    os.symlink(link, new)
                    os.unlink(old)
                elif os.path.isdir(old):
                    if os.path.exists(new):
                        if not os.path.isdir(new):
                            bb.fatal('stateless: moving directory %s to non-directory %s not supported' % (old, new))
                    else:
                        # TODO (?): also copy xattrs
                        os.mkdir(new)
                        shutil.copystat(old, new)
                        stat = os.stat(old)
                        os.chown(new, stat.st_uid, stat.st_gid)
                    for entry in os.listdir(old):
                        move(os.path.join(old, entry), os.path.join(new, entry))
                    os.rmdir(old)
                else:
                    os.rename(old, new)
            move(old, new)
            if factory:
                # Add new tmpfiles.d entry for the top-level directory.
                with open(os.path.join(tmpfilesdir, 'stateless.conf'), 'a+') as f:
                    f.write('C /etc/%s - - - -\n' % etcentry)
                # We might have moved an entry for which systemd (or something else)
                # already had a tmpfiles.d entry. We need to remove that other entry
                # to ensure that ours is used instead.
                for file in os.listdir(tmpfilesdir):
                    if file.endswith('.conf') and file != 'stateless.conf':
                        with open(os.path.join(tmpfilesdir, file), 'r+') as f:
                            lines = []
                            for line in f.readlines():
                                parts = line.split()
                                if len(parts) >= 2 and parts[1] in moved:
                                    line = '# replaced by stateless.conf entry: ' + line
                                lines.append(line)
                            f.seek(0)
                            f.write(''.join(lines))
                # Ensure that the listed service(s) start after tmpfiles.d setup.
                if tmpfiles_before:
                    service_d_dir = '%s%s/systemd-tmpfiles-setup.service.d' % (root, d.getVar('systemd_system_unitdir'))
                    bb.utils.mkdirhier(service_d_dir)
                    conf_file = os.path.join(service_d_dir, 'stateless.conf')
                    with open(conf_file, 'a') as f:
                        if f.tell() == 0:
                            f.write('[Unit]\n')
                        f.write('Before=%s\n' % ' '.join(tmpfiles_before))

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
        path_stat = os.stat(path)
        try:
            os.rmdir(path)
            # We may have moved some content into the tmpfiles.d factory,
            # and that then depends on re-creating these directories.
            etcentry = os.path.relpath(path, etcdir)
            if etcentry != '.':
                with open(os.path.join(tmpfilesdir, 'stateless.conf'), 'a') as f:
                    f.write('D /etc/%s 0%o %d %d - -\n' %
                            (etcentry,
                             stat.S_IMODE(path_stat.st_mode),
                             path_stat.st_uid,
                             path_stat.st_gid))
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

python () {
    # The bitbake cache must be told explicitly that changes in the
    # directories have an effect on the recipe. Otherwise adding
    # or removing patches or whole directories does not trigger
    # re-parsing and re-building.
    import os
    patchdir = d.expand('${STATELESS_PATCHES_BASE}/${PN}')
    bb.parse.mark_dependency(d, patchdir)
    if os.path.isdir(patchdir):
        patches = os.listdir(patchdir)
        if patches:
            filespath = d.getVar('FILESPATH', True)
            d.setVar('FILESPATH', filespath + ':' + patchdir)
            srcuri = d.getVar('SRC_URI', True)
            d.setVar('SRC_URI', srcuri + ' ' + ' '.join(['file://' + x for x in sorted(patches)]))

    # Dynamically reconfigure the package to use /usr instead of /etc for
    # configuration files.
    relocate = d.getVar('STATELESS_RELOCATE', True)
    if relocate != 'False':
        defaultsdir = d.expand('${datadir}/defaults') if relocate == 'True' else relocate
        d.setVar('sysconfdir', defaultsdir)
        d.setVar('EXTRA_OECONF', d.getVar('EXTRA_OECONF', True) + " --sysconfdir=" + defaultsdir)
}

# Several post-install scripts modify /etc.
# For example:
# /etc/shells - gets extended when installing a shell package
# /etc/passwd - adduser in postinst extends it
# /etc/systemd/system - has several .wants entries
#
# We fix this directly after the write_image_manifest command
# in the ROOTFS_POSTUNINSTALL_COMMAND.
#
# However, that is very late, so changes made by a ROOTFS_POSTPROCESS_COMMAND
# (like setting an empty root password) become part of the system,
# which might not be intended in all cases.
#
# It would be better to do this directly after installing with
# ROOTFS_POSTINSTALL_COMMAND += "stateless_mangle_rootfs;"
# However, opkg then becomes unhappy and causes failures in the
# *_manifest commands which get executed later:
#
# ERROR: Cannot get the installed packages list. Command '.../opkg -f .../refkit-image-minimal/1.0-r0/opkg.conf -o .../refkit-image-minimal/1.0-r0/rootfs  --force_postinstall --prefer-arch-to-version   status' returned 0 and stderr:
# Collected errors:
#  * file_md5sum_alloc: Failed to open file .../refkit-image-minimal/1.0-r0/rootfs/etc/hosts: No such file or directory.
#
# ERROR: Function failed: write_package_manifest
#
# TODO: why does opkg complain? /etc/hosts is listed in CONFFILES of netbase,
# so it should be valid to remove it. If we can fix that and ensure that
# all /etc files are marked as CONFFILES (perhaps by adding that as
# default for all packages), then we can use ROOTFS_POSTINSTALL_COMMAND
# again.
ROOTFS_POSTUNINSTALL_COMMAND_append = "stateless_mangle_rootfs;"

python stateless_mangle_rootfs () {
    pn = d.getVar('PN', True)
    if oe.types.boolean(d.getVar('STATELESS_EXCLUDED')):
        return

    rootfsdir = d.getVar('IMAGE_ROOTFS', True)
    docdir = rootfsdir + d.getVar('datadir', True) + '/doc/etc'
    whitelist = (d.getVar('STATELESS_ETC_WHITELIST', True) or '').split()
    stateless_mangle(d, rootfsdir, docdir,
                     (d.getVar('STATELESS_MV_ROOTFS', True) or '').split(),
                     (d.getVar('STATELESS_RM_ROOTFS', True) or '').split(),
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