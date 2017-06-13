# This file defines some common test scenarios for system
# updates. Actual tests for certain update mechanisms need to inherit
# SystemUpdateTest and implement the stubs.

from oeqa.utils.commands import runCmd, bitbake, get_bb_var, get_bb_vars, runqemu
import oe.path

import base64
import pathlib
import pickle

class SystemUpdateModify(object):
    """
    A helper class which will be used to make changes to the rootfs.
    Each SystemUpdateBase instance needs one such helper instance.
    Derived helper classes have to be simple enough such that they
    can be pickled.
    """

    def modify_kernel(self, testname, is_update, rootfs):
        """
        Patch the kernel in an existing rootfs. Called during rootfs construction,
        once for the initial image (is_update=False) and once for the update.
        """
        pass

    def modify_files(self, testname, is_update, rootfs):
        """
        Simulate simple adding, removing and modifying of files under /usr/bin.
        """
        testdir = os.path.join(rootfs, 'usr', 'bin')
        if not is_update:
            pathlib.Path(os.path.join(testdir, 'modify_files_remove_me')).touch()
            pathlib.Path(os.path.join(testdir, 'modify_files_update_me')).touch()
        else:
            with open(os.path.join(testdir, 'modify_files_update_me'), 'w') as f:
                f.write('updated\n')
            pathlib.Path(os.path.join(testdir, 'modify_files_was_added')).touch()

    def verify_files(self, testname, is_update, qemu, test):
        """
        Sanity check files before and after update.
        """
        cmd = 'ls -1 /usr/bin/modify_files_*'
        status, output = qemu.run_serial(cmd)
        test.assertEqual(1, status, 'Failed to run command "%s":\n%s' % (cmd, output))
        if not is_update:
            test.assertEqual(output, '/usr/bin/modify_files_remove_me\r\n/usr/bin/modify_files_update_me')
        else:
            test.assertEqual(output, '/usr/bin/modify_files_update_me\r\n/usr/bin/modify_files_was_added')
            cmd = 'cat /usr/bin/modify_files_update_me'
            status, output = qemu.run_serial(cmd)
            test.assertEqual(1, status, 'Failed to run command "%s":\n%s' % (cmd, output))
            test.assertEqual(output, 'updated')

    def _do_modifications(self, d, testname, updates, is_update):
        """
        This code will run as part of a ROOTFS_POSTPROCESS_COMMAND.
        """
        rootfs = d.getVar('IMAGE_ROOTFS')
        for update in updates:
            bb.note('%s: running modify_%s' % (testname, update))
            getattr(self, 'modify_' + update)(testname, is_update, rootfs)

class SystemUpdateBase(object):
    """
    Base class for system update testing.
    """

    # The image that will get built, booted and updated.
    IMAGE_PN = 'core-image-minimal'

    # The .bbappend name which matches IMAGE_PN.
    # For example, OSTree might build and boot "core-image-minimal-ostree",
    # but the actual image recipe is "core-image-minimal" and thus
    # we would need "core-image-minimal.bbappend". Also allows to handle
    # cases where the bbappend file name must have a wildcard.
    IMAGE_BBAPPEND = 'core-image-minimal.bbappend'

    # Expected to be replaced by derived class.
    IMAGE_MODIFY = SystemUpdateModify()

    def boot_image(self, overrides):
        """
        Calls runqemu() such that commands can be started via run_serial().
        Derived classes need to replace with something that adds whatever
        other parameters are needed or useful.
        """
        return runqemu(self.IMAGE_PN, discard_writes=False, overrides=overrides)

    def update_image(self, qemu):
        """
        Triggers the actual update, optionally requesting a reboot by returning True.
        """
        self.fail('not implemented')

    def verify_image(self, testname, is_update, qemu, updates):
        """
        Verify content of image before and after the update.
        """
        for update in updates:
            getattr(self.IMAGE_MODIFY, 'verify_' + update)(testname, is_update, qemu, self)

    def do_update(self, testname, updates=['kernel']):
        """
        Builds the image, makes a copy of the result, rebuilds to produce
        an update with configurable changes, boots the original image, updates it,
        reboots and then checks the updated image.

        'update' is a list of modify_* function names which make the actual changes
        (adding, removing, modifying files or kernel) that are part of the tests.
        """

        def create_image_bbappend(is_update):
            """
            Creates an IMAGE_BBAPPEND which contains the pickled modification code.
            A .bbappend is used because it can contain code and is guaranteed to be
            applied also to image variants.
            """

            self.track_for_cleanup(self.IMAGE_BBAPPEND)
            with open(self.IMAGE_BBAPPEND, 'w') as f:
                f.write('''
python system_update_test_modify () {
    import base64
    import pickle

    code = %s
    do_modifications = pickle.loads(base64.b64decode(code), fix_imports=False)
    do_modifications(d, '%s', %s, %s)
}

ROOTFS_POSTPROCESS_COMMAND += "system_update_test_modify;"
''' % (base64.b64encode(pickle.dumps(self.IMAGE_MODIFY._do_modifications, fix_imports=False)),
       testname,
       updates,
       is_update))

        # Creating a .bbappend for the image will trigger a rebuild.
        self.write_config('BBFILES_append = " %s"' % os.path.abspath(self.IMAGE_BBAPPEND))
        create_image_bbappend(False)
        bitbake(self.IMAGE_PN)

        # Copying the entire deploy directory via hardlinks is relatively cheap
        # and gives us everything required to run qemu.
        self.image_dir = get_bb_var('DEPLOY_DIR_IMAGE')
        self.image_dir_original = self.image_dir + '.test'
        # self.track_for_cleanup(self.image_dir_original)
        oe.path.copyhardlinktree(self.image_dir, self.image_dir_original)

        # Now we change our .bbappend so that the updated state is generated
        # during the next rebuild.
        create_image_bbappend(True)
        bitbake(self.IMAGE_PN)

        # Change DEPLOY_DIR_IMAGE so that we use our copy of the
        # images from before the update. Further customizations for booting can
        # be done by rewriting self.image_dir_original/IMAGE_PN-MACHINE.qemuboot.conf
        # (read, close, write, not just appending as that would also change
        # the file copy under image_dir).
        overrides = { 'DEPLOY_DIR_IMAGE': self.image_dir_original }

        # Boot image, verify before and after update.
        with self.boot_image(overrides) as qemu:
            self.verify_image(testname, False, qemu, updates)
            reboot = self.update_image(qemu)
            if not reboot:
                self.verify_image(testname, True, qemu, updates)
        if reboot:
            with self.boot_image(overrides) as qemu:
                self.verify_image(testname, True, qemu, updates)

    def test_file_update(self):
        """
        Update just some additional files. No reboot required.
        """
        self.do_update('test_file_update', ['files'])

    def test_kernel_update(self):
        """
        Update just the kernel.
        """
        pass
        # self.do_update('test_kernel_update', ['kernel'])
