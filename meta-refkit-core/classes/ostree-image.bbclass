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
OSTREEBASE    = "${FLATPAKBASE}"
OSTREE_ROOTFS = "${IMAGE_ROOTFS}.ostree"
OSTREE_REPO   = "${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.ostree"
OSTREE_ARCH   = "${@d.getVar('TARGET_ARCH_MULTILIB_ORIGINAL') \
                       if d.getVar('MPLPREFIX') else d.getVar('TARGET_ARCH')}"

# This is where we export our builds in archive-z2 format. This repository
# can be exposed over HTTP for clients to pull in upgrades from. By default
# it goes under the top build directory.
OSTREE_EXPORT ?= "${TOPDIR}/${IMAGE_BASENAME}.ostree"

# This is where our GPG keyring is generated/located at and the default
# key ID we use to sign (commits in) the repository.
OSTREE_GPGDIR ?= "${TOPDIR}/gpg"
OSTREE_GPGID  ?= "${@d.getVar('DISTRO').replace(' ', '_') + '-signing@key'}"

# OSTree remote (HTTP URL) where updates will be published.
OSTREE_REMOTE ?= "${@'http://updates.refkit.org/ostree/' + \
                        d.getVar('IMAGE_BASENAME').split('-ostree')[0]}"

# Check if we have an unchanged image and an already existing repo for it.
image_repo () {
    DEPLOY_DIR_IMAGE="${@d.getVar('DEPLOY_DIR_IMAGE')}"
    IMAGE_NAME="${@d.getVar('IMAGE_NAME')}"
    IMAGE_BASENAME="${@d.getVar('IMAGE_BASENAME')}"
    IMAGE_ROOTFS="${@d.getVar('IMAGE_ROOTFS')}"
    MACHINE="${@d.getVar('MACHINE')}"
    ROOTFS_VERSION="$(cat $IMAGE_ROOTFS/etc/version)"

    OSTREE_REPO="${@d.getVar('OSTREE_REPO')}"
    IMAGE_REPO="$DEPLOY_DIR_IMAGE/$IMAGE_BASENAME-$MACHINE-$VERSION.ostree"

    if [ -d $IMAGE_REPO ]; then
        echo $IMAGE_REPO
    else
        echo $OSTREE_REPO
    fi
}

# Take a pristine rootfs as input, shuffle its layout around to make it
# OSTree-compatible, commit the rootfs into a per-build bare-user OSTree
# repository, and finally produce an OSTree-enabled rootfs by cloning
# and checking out the rootfs as an OSTree deployment.
fakeroot do_ostree_prepare_rootfs () {
    DISTRO="${@d.getVar('DISTRO')}"
    MACHINE="${@d.getVar('MACHINE')}"
    TMPDIR="${@d.getVar('TMPDIR')}"
    IMAGE_ROOTFS="${@d.getVar('IMAGE_ROOTFS')}"
    IMAGE_BASENAME="${@d.getVar('IMAGE_BASENAME')}"
    OSTREE_REPO="${@d.getVar('OSTREE_REPO')}"
    OSTREE_ROOTFS="${@d.getVar('IMAGE_ROOTFS')}.ostree"
    OSTREE_EXPORT="${@d.getVar('OSTREE_EXPORT')}"
    OSTREE_ARCH="${@d.getVar('OSTREE_ARCH')}"
    OSTREE_GPGDIR="${@d.getVar('OSTREE_GPGDIR')}"
    OSTREE_GPGID="${@d.getVar('OSTREE_GPGID')}"
    OSTREE_REMOTE="${@d.getVar('OSTREE_REMOTE')}"

    echo "DISTRO=$DISTRO"
    echo "MACHINE=$MACHINE"
    echo "TMPDIR=$TMPDIR"
    echo "IMAGE_ROOTFS=$IMAGE_ROOTFS"
    echo "IMAGE_BASENAME=$IMAGE_BASENAME"
    echo "OSTREE_REPO=$OSTREE_REPO"
    echo "OSTREE_ROOTFS=$OSTREE_ROOTFS"
    echo "OSTREE_EXPORT=$OSTREE_EXPORT"
    echo "OSTREE_ARCH=$OSTREE_ARCH"
    echo "OSTREE_GPGDIR=$OSTREE_GPGDIR"
    echo "OSTREE_GPGID=$OSTREE_GPGID"
    echo "OSTREE_REMOTE=${OSTREE_REMOTE:-none}"

    # bail out if this does not look like an -ostree image variant
    if ${@bb.utils.contains('IMAGE_FEATURES','ostree', 'true','false', d)}; then
        echo "OSTree: image $IMAGE_BASENAME is an ostree variant"
    else
        echo "OSTree: image $IMAGE_BASENAME is not an ostree variant"
        return 0
    fi

    # Generate repository signing GPG keys, if we don't have them yet.
    # TODO: replace with pre-generated keys in the repo instead of depending on meta-flatpak?
    ${FLATPAKBASE}/scripts/gpg-keygen.sh \
        --home $OSTREE_GPGDIR \
        --id $OSTREE_GPGID \
        --base "${OSTREE_GPGID%%@*}"

    # Save (signing) public key for the repo.
    pubkey=${OSTREE_GPGID%%@*}.pub
    if [ ! -e ${IMGDEPLOYDIR}/$pubkey -a -e ${TOPDIR}/$pubkey ]; then
        echo "Saving OSTree repository signing key $pubkey"
        cp -v ${TOPDIR}/$pubkey ${IMGDEPLOYDIR}
    fi

    IMAGE_REPO=$(image_repo)

    if [ "$IMAGE_REPO" != "$OSTREE_REPO" ]; then
        echo "Symlinking to existing image repo $IMAGE_REPO..."
        ln -s $IMAGE_REPO $OSTREE_REPO
        return 0
    fi

    if [ -n "$OSTREE_REMOTE" ]; then
        remote="--remote $OSTREE_REMOTE"
    else
        remote=""
    fi

    ${META_REFKIT_CORE_BASE}/scripts/mk-ostree.sh -v -v \
        --distro $DISTRO \
        --arch $OSTREE_ARCH \
        --machine $MACHINE \
        --src $IMAGE_ROOTFS \
        --dst $OSTREE_ROOTFS \
        --repo $OSTREE_REPO \
        --export $OSTREE_EXPORT \
        --tmpdir $TMPDIR \
        --gpg-home $OSTREE_GPGDIR \
        --gpg-id $OSTREE_GPGID \
        $remote \
        --overwrite \
        prepare-sysroot export-repo
}

do_ostree_prepare_rootfs[depends] += " \
    binutils-native:do_populate_sysroot \
    ostree-native:do_populate_sysroot \
"

addtask do_ostree_prepare_rootfs after do_rootfs before do_image


# Take a per-build OSTree bare-user repository and export it to an
# archive-z2 repository which can then be exposed over HTTP for
# OSTree clients to pull in upgrades from.
fakeroot do_ostree_publish_rootfs () {
    DISTRO="${@d.getVar('DISTRO')}"
    OS_VERSION="${@d.getVar('OS_VERSION')}"
    MACHINE="${@d.getVar('MACHINE')}"
    TMPDIR="${@d.getVar('TMPDIR')}"
    IMAGE_ROOTFS="${@d.getVar('IMAGE_ROOTFS')}"
    IMAGE_BASENAME="${@d.getVar('IMAGE_BASENAME')}"
    OSTREE_REPO="${@d.getVar('OSTREE_REPO')}"
    OSTREE_ROOTFS="${@d.getVar('IMAGE_ROOTFS')}.ostree"
    OSTREE_EXPORT="${@d.getVar('OSTREE_EXPORT')}"
    OSTREE_ARCH="${@d.getVar('OSTREE_ARCH')}"
    OSTREE_GPGDIR="${@d.getVar('OSTREE_GPGDIR')}"
    OSTREE_GPGID="${@d.getVar('OSTREE_GPGID')}"

    echo "DISTRO=$DISTRO"
    echo "OS_VERSION=$OS_VERSION"
    echo "MACHINE=$MACHINE"
    echo "TMPDIR=$TMPDIR"
    echo "IMAGE_ROOTFS=$IMAGE_ROOTFS"
    echo "IMAGE_BASENAME=$IMAGE_BASENAME"
    echo "OSTREE_REPO=$OSTREE_REPO"
    echo "OSTREE_ROOTFS=$OSTREE_ROOTFS"
    echo "OSTREE_EXPORT=$OSTREE_EXPORT"
    echo "OSTREE_ARCH=$OSTREE_ARCH"
    echo "OSTREE_GPGDIR=$OSTREE_GPGDIR"
    echo "OSTREE_GPGID=$OSTREE_GPGID"

    # bail out if this does not look like an -ostree image variant or we're
    # not supposed to publish
    if ${@bb.utils.contains('IMAGE_FEATURES','ostree', 'false','true', d)}; then
        return 0
    fi

    if [ -z "${@d.getVar('OSTREE_EXPORT')}" ]; then
        echo "OSTree: OSTREE_EXPORT repository not set, not publishing."
        return 0
    fi

    ${META_REFKIT_CORE_BASE}/scripts/mk-ostree.sh -v -v \
        --distro $DISTRO \
        --arch $OSTREE_ARCH \
        --machine $MACHINE \
        --repo $OSTREE_REPO \
        --export $OSTREE_EXPORT \
        --gpg-home $OSTREE_GPGDIR \
        --gpg-id $OSTREE_GPGID \
        --overwrite \
        export-repo
}

addtask do_ostree_publish_rootfs after do_ostree_prepare_rootfs before do_image
