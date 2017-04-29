
FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI_append_class-target = " \
	file://0001-ovmf-RefkitTestCA-TEST-UEFI-SecureBoot.patch \
"
do_install_append_class-target() {
    rm -rf ${D}/efi/boot
}
