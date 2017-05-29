FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

# refkit.cfg disables CONFIG_SYSLOGD so the corresponding packaging
# needs to be dropped as well.
SYSTEMD_PACKAGES_refkit-config = ""
PACKAGES_remove_refkit-config = "${PN}-syslog"
RRECOMMENDS_${PN}_remove_refkit-config = "${PN}-syslog"

SRC_URI_append_refkit-config = "\
    file://refkit.cfg \
"

# If this were to stay in refkit, RPROVIDES_${PN}_append_usrmerge
# would be better. But as the usrmerge patches are pending for
# OE-core 2.4 M1, here we use the simpler solution and make
# the change conditional on refkit-config.
RPROVIDES_${PN}_append_refkit-config = "${@bb.utils.contains('DISTRO_FEATURES', 'usrmerge', ' /bin/sh', '', d)}"
