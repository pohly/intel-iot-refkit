# Support for OSTree-upgradable images.
#
# This class adds support for building ostree image variants. It is an
# addeddum to refkit-image.bbclass and is supposed to be inherited by it.
#
# An ostree image variant adds to the base image bitbake-time support for
#
#     - building OSTree-enabled images
#     - populating a per-build OSTree repository with the image
#     - publishing builds to an HTTP-serviceable repository
#
# The ostree image variant adds to the base image runtime support for
#
#     - boot-time selection of the most recent rootfs tree
#     - booting an OSTree enabled image into a rootfs
#     - pulling in image upgrades using OSTree
#
###########################################################################

# Declare an image feature for OSTree-upgradeable images.
IMAGE_FEATURES[validitems] += " \
    ostree \
"

# rekit-ostree RDEPENDS on ostree, so we don't need to list that here.
FEATURE_PACKAGES_ostree = " \
    refkit-ostree \
"

#
# Define our image variants for OSTree support.
#
# - ostree variant:
#     Adds the necessary runtime bits for OSTree support. Using this
#     image on a device makes it possible to pull in updates to the
#     base distro using OSTree. Additionally, during bitbake images
#     will be exported to an OSTree repository for consumption by
#     devices running an ostree image variant.
#

# ostree variant: an image that can update itself using OSTree.
IMAGE_VARIANT[ostree] = "ostree"

BBCLASSEXTEND += "imagevariant:ostree"

###########################################################################

# These are our top layer directory, OSTree-compatible rootfs path,
# primary per-build OSTree repository and machine architecture to use
# in tagging versions in the repository. These are not meant to be
# overridden.
OSTREE_ROOTFS = "${IMAGE_ROOTFS}.ostree"
OSTREE_REPO   = "${WORKDIR}/ostree-repo"
OSTREE_ARCH   = "${@d.getVar('TARGET_ARCH_MULTILIB_ORIGINAL') \
                       if d.getVar('MPLPREFIX') else d.getVar('TARGET_ARCH')}"

# Each image is committed to its own, unique branch.
OSTREE_BRANCH ?= "${DISTRO}/${MACHINE}/${PN}"

# This is where we export our builds in archive-z2 format. This repository
# can be exposed over HTTP for clients to pull upgrades from. It can be
# shared between different distributions, architectures and images
# because each image has its own branch in the common repository.
#
# Beware that this repo is under TMPDIR by default. Just like other
# build output it should be moved to a permanent location if it
# is meant to be preserved after a successful build (for example,
# with "ostree pull-local" in a permanent repo), or the variable
# needs to point towards an external directory which exists
# across builds.
#
# This can be set to an empty string to disable publishing.
OSTREE_EXPORT ?= "${DEPLOY_DIR}/ostree-repo"

# This is where our GPG keyring is generated/located at and the default
# key ID we use to sign (commits in) the repository.
OSTREE_GPGDIR ?= "${TOPDIR}/gpg"
OSTREE_GPGID  ?= "${@d.getVar('DISTRO').replace(' ', '_') + '-signing@key'}"

# OSTree remote (HTTP URL) where updates will be published.
# Host the content of OSTREE_EXPORT there.
OSTREE_REMOTE ?= "https://update.example.org/ostree/"

# Take a pristine rootfs as input, shuffle its layout around to make it
# OSTree-compatible, commit the rootfs into a per-build bare-user OSTree
# repository, and finally produce an OSTree-enabled rootfs by cloning
# and checking out the rootfs as an OSTree deployment.
fakeroot do_ostree_prepare_rootfs () {
    # Generate repository signing GPG keys, if we don't have them yet.
    # TODO: replace with pre-generated keys in the repo instead of depending on meta-flatpak?
    base=${@ '${OSTREE_GPGID}'.split('@')[0]}
    pubkey=$base.pub
    ${FLATPAKBASE}/scripts/gpg-keygen.sh \
        --home ${OSTREE_GPGDIR} \
        --id ${OSTREE_GPGID} \
        --base $base

    # Save (signing) public key for the repo.
    if [ ! -e ${IMGDEPLOYDIR}/$pubkey -a -e ${TOPDIR}/$pubkey ]; then
        bbnote "Saving OSTree repository signing key $pubkey"
        cp -v ${TOPDIR}/$pubkey ${IMGDEPLOYDIR}
    fi

    if [ -n "${OSTREE_REMOTE}" ]; then
        remote="--remote ${OSTREE_REMOTE}"
    else
        remote=""
    fi

    ${META_REFKIT_CORE_BASE}/scripts/mk-ostree.sh -v -v \
        --distro "${DISTRO}" \
        --arch ${OSTREE_ARCH} \
        --machine ${MACHINE} \
        --branch ${OSTREE_BRANCH} \
        --src ${IMAGE_ROOTFS} \
        --dst ${OSTREE_ROOTFS} \
        --repo ${OSTREE_REPO} \
        --export ${OSTREE_EXPORT} \
        --tmpdir ${TMPDIR} \
        --gpg-home ${OSTREE_GPGDIR} \
        --gpg-id ${OSTREE_GPGID} \
        $remote \
        --overwrite \
        prepare-sysroot export-repo
}
# .pub/.sec keys get created in the current directory, so
# we have to be careful to always run from the same directory,
# regardless of the image.
do_ostree_prepare_rootfs[dirs] = "${TOPDIR}"

def get_file_list(filenames):
    filelist = []
    for filename in filenames:
        filelist.append(filename + ":" + str(os.path.exists(filename)))
    return ' '.join(filelist)

do_ostree_prepare_rootfs[file-checksums] += "${@get_file_list(( \
   '${META_REFKIT_CORE_BASE}/scripts/mk-ostree.sh', \
   '${FLATPAKBASE}/scripts/gpg-keygen.sh', \
))}"

# TODO: ostree-native depends on ca-certificates,
# and is probably affected by https://bugzilla.yoctoproject.org/show_bug.cgi?id=9883.
# At least there are warnings in log.do_ostree_prepare_rootfs:
# (ostree:42907): GLib-Net-WARNING **: couldn't load TLS file database: Failed to open file '/fast/build/refkit/intel-corei7-64/tmp-glibc/work/x86_64-linux/glib-networking-native/2.50.0-r0/recipe-sysroot-native/etc/ssl/certs/ca-certificates.crt': No such file or directory
do_ostree_prepare_rootfs[depends] += " \
    binutils-native:do_populate_sysroot \
    ostree-native:do_populate_sysroot \
"

# Take a per-build OSTree bare-user repository and export it to an
# archive-z2 repository which can then be exposed over HTTP for
# OSTree clients to pull in upgrades from.
fakeroot do_ostree_publish_rootfs () {
    if [ ! "${OSTREE_EXPORT}" ]; then
        bbnote "OSTree: OSTREE_EXPORT repository not set, not publishing."
        return 0
    fi

    ${META_REFKIT_CORE_BASE}/scripts/mk-ostree.sh -v -v \
        --distro ${DISTRO} \
        --arch ${OSTREE_ARCH} \
        --machine ${MACHINE} \
        --branch ${OSTREE_BRANCH} \
        --repo ${OSTREE_REPO} \
        --export ${OSTREE_EXPORT} \
        --gpg-home ${OSTREE_GPGDIR} \
        --gpg-id ${OSTREE_GPGID} \
        --overwrite \
        export-repo
}

python () {
    # Don't do anything when OSTree image feature is off.
    if bb.utils.contains('IMAGE_FEATURES', 'ostree', True, False, d):
        # TODO: we must do this after do_image, because do_image
        # is still allowed to make changes to the files (for example,
        # prelink_image in IMAGE_PREPROCESS_COMMAND)
        #
        # We rely on wic to produce the actual images, so we could do
        # after do_image before do_image_wic here.
        bb.build.addtask('do_ostree_prepare_rootfs', 'do_image', 'do_rootfs', d)
        # TODO: is this obsolete?
        bb.build.addtask('do_ostree_publish_rootfs', 'do_image', 'do_ostree_prepare_rootfs', d)
}
