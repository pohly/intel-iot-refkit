# util-linux-native tooling enables to use either lzo or lz4 compression.
# We prefer lz4 so switch to use it.
#
# Upstream-Status: Inappropriate [Downstream configuration] 

DEPENDS_remove_class-native_df-refkit-config = "lzo-native"
DEPENDS_remove_class-nativesdk_df-refkit-config = "lzo-native"
DEPENDS_append_class-native_df-refkit-config = " lz4-native"
DEPENDS_append_class-nativesdk_df-refkit-config = " lz4-native"

# A workaround for su.util-linux being broken (https://bugzilla.yoctoproject.org/show_bug.cgi?id=11126)
# We also loose runuser, but shouldn't need it.
PACKAGECONFIG_remove = "pam"
PACKAGES_remove = "util-linux-runuser"
RDEPENDS_util-linux_remove = "util-linux-runuser"
