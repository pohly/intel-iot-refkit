DESCRIPTION = "Utility for signing and verifying files for UEFI Secure Boot"
LICENSE = "GPLv3 & LGPL-2.1 & LGPL-3.0 & MIT"

# sbsigntool statically links to libccan.a which is built with modules
# passed to "create-ccan-tree" (and their dependencies). Therefore,
# we also keep track of all the ccan module licenses.
LIC_FILES_CHKSUM = "file://LICENSE.GPLv3;md5=9eef91148a9b14ec7f9df333daebc746 \
                    file://COPYING;md5=a7710ac18adec371b84a9594ed04fd20 \
                    file://lib/ccan.git/ccan/endian/LICENSE;md5=2d5025d4aa3495befef8f17206a5b0a1 \
                    file://lib/ccan.git/ccan/htable/LICENSE;md5=2d5025d4aa3495befef8f17206a5b0a1 \
                    file://lib/ccan.git/ccan/list/LICENSE;md5=2d5025d4aa3495befef8f17206a5b0a1 \
                    file://lib/ccan.git/ccan/read_write_all/LICENSE;md5=2d5025d4aa3495befef8f17206a5b0a1 \
                    file://lib/ccan.git/ccan/talloc/LICENSE;md5=2d5025d4aa3495befef8f17206a5b0a1 \
                    file://lib/ccan.git/ccan/typesafe_cb/LICENSE;md5=2d5025d4aa3495befef8f17206a5b0a1 \
                    file://lib/ccan.git/ccan/failtest/LICENSE;md5=6a6a8e020838b23406c81b19c1d46df6 \
                    file://lib/ccan.git/ccan/tlist/LICENSE;md5=6a6a8e020838b23406c81b19c1d46df6 \
                    file://lib/ccan.git/ccan/time/LICENSE;md5=838c366f69b72c5df05c96dff79b35f2 \
"

# The original upstream is git://kernel.ubuntu.com/jk/sbsigntool but it has
# not been maintained and many patches have been backported in this repo.
SRC_URI = "gitsm://git.kernel.org/pub/scm/linux/kernel/git/jejb/sbsigntools.git;protocol=git \
          "

SRCREV  = "efbb550858e7bd3f43e64228d22aea440ef6a14d"

DEPENDS = "binutils-native gnu-efi-native help2man-native openssl-native util-linux-native"

PV = "0.8-git${SRCPV}"

S = "${WORKDIR}/git"

inherit native autotools pkgconfig

do_configure_prepend() {
	cd ${S}

	if [ ! -e lib/ccan ]; then

		# Use empty SCOREDIR because 'make scores' is not run.
		# The default setting depends on (non-whitelisted) host tools.
		sed -i -e 's#^\(SCOREDIR=\).*#\1#' lib/ccan.git/Makefile

		lib/ccan.git/tools/create-ccan-tree \
		--build-type=automake lib/ccan \
		talloc read_write_all build_assert array_size endian
	fi

	# Create generatable docs from git
	(
	 echo "Authors of sbsigntool:"
	 echo
	 git log --format='%an' | sort -u | sed 's,^,\t,'
	) > AUTHORS

	# Generate simple ChangeLog
	git log --date=short --format='%ad %t %an <%ae>%n%n  * %s%n' > ChangeLog

	cd ${B}
}

def efi_arch(d):
    import re
    harch = d.getVar("HOST_ARCH")
    if re.match("i[3456789]86", harch):
        return "ia32"
    return harch

EXTRA_OEMAKE = "\
    INCLUDES+='-I${S}/lib/ccan.git/ \
              -I${STAGING_INCDIR_NATIVE}/efi \
              -I${STAGING_INCDIR_NATIVE} \
              -I${STAGING_INCDIR_NATIVE}/efi/${@efi_arch(d)}' \
    "
