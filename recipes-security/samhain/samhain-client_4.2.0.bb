SAMHAIN_MODE="client"
INITSCRIPT_PARAMS = "defaults 15 85"

require samhain.inc

SRC_URI += "file://run-ptest"

inherit ptest

TESTDIR = "testsuit"

#Let the default Logserver be 127.0.0.1
EXTRA_OECONF += " \
        --with-logserver=${SAMHAIN_SERVER} \
        --with-port=${SAMHAIN_PORT} \
        --with-config-file=/etc/samhainrc \
        --with-data-file=/var/samhain/samhain.data \
        --with-pid-file=/var/samhain/samhain.pid \
        "

do_install_ptest_libc-glibc() {
	install -d ${D}${PTEST_PATH}/${TESTDIR}
	cd ${B}
	oe_runmake clean
	tar -c . | ( cd ${D}${PTEST_PATH}/${TESTDIR} && tar -xf - )
}

RDEPENDS_${PN} = "acl zlib attr bash"
RDEPENDS_${PN}-ptest = "flawfinder cppcheck gnupg libpcre vim imagemagick pkgconfig zlib"
