
#enable merged /usr
REFKIT_DEFAULT_DISTRO_FEATURES += "usrmerge"

export base_bindir = "${@bb.utils.contains('DISTRO_FEATURES', 'usrmerge', '${exec_prefix}/bin', '${base_prefix}/bin', d)}"
export base_sbindir = "${@bb.utils.contains('DISTRO_FEATURES', 'usrmerge', '${exec_prefix}/sbin', '${base_prefix}/sbin', d)}"
export base_libdir = "${@bb.utils.contains('DISTRO_FEATURES', 'usrmerge', '${exec_prefix}/${baselib}', '${base_prefix}/${baselib}', d)}"
export nonarch_base_libdir = "${@bb.utils.contains('DISTRO_FEATURES', 'usrmerge', '${exec_prefix}/lib', '${base_prefix}/lib', d)}"

#nativesdk
base_bindir_nativesdk = "${@bb.utils.contains('DISTRO_FEATURES', 'usrmerge', '${bindir_nativesdk}', '/bin', d)}"
base_sbindir_nativesdk = "${@bb.utils.contains('DISTRO_FEATURES', 'usrmerge', '${sbindir_nativesdk}', '/sbin', d)}"
base_libdir_nativesdk = "${@bb.utils.contains('DISTRO_FEATURES', 'usrmerge', '${libdir_nativesdk}', '/lib', d)}"

# TODO (added by Patrick Ohly): replace unconditional DISTRO_FEATURES removal with
# QA check that prevents invalid combination of usrmerge and gobject-introspection-data,
# and ensure that the default is valid in enable-refkit-config.inc.
# Even better: make it possible to combine both.
#
# Included via enable-refkit-config.inc. Once it is free of this side-effect,
# it can get included via refkit-config.inc.
DISTRO_FEATURES_remove = " gobject-introspection-data"
