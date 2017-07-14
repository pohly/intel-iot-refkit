FILESEXTRAPATHS_prepend := "${THISDIR}/${PN}:"

# Workaround for https://github.com/kraj/meta-clang/issues/36
SRC_URI_append = " file://use-locale.h-for-glibc.patch"
