# usrmerge supported changes
EXTRA_OECONF_append = "${@bb.utils.contains('DISTRO_FEATURES', 'usrmerge', ' --disable-split-usr', ' --enable-split-usr', d)}"
rootprefix = "${@bb.utils.contains('DISTRO_FEATURES', 'usrmerge', '${exec_prefix}', '${base_prefix}', d)}"
