# Copyright (C) 2021 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""All public rules and macros to build the kernel."""

# This extension serves as a central place for users to import these public
# rules and macros. The implementations stays in sub-extensions,
# which is not expected to be loaded directly by users.

load(
    "//build/kernel/kleaf/artifact_tests:kernel_test.bzl",
    _initramfs_modules_lists_test = "initramfs_modules_lists_test",
    _kernel_module_test = "kernel_module_test",
)
load(
    "//build/kernel/kleaf/impl:abi/dependency_graph.bzl",
    _dependency_graph = "dependency_graph",
    _dependency_graph_drawer = "dependency_graph_drawer",
    _dependency_graph_extractor = "dependency_graph_extractor",
)
load("//build/kernel/kleaf/impl:abi/extracted_symbols.bzl", _extract_symbols = "extracted_symbols")
load("//build/kernel/kleaf/impl:abi/kernel_abi.bzl", _kernel_abi = "kernel_abi")
load("//build/kernel/kleaf/impl:abi/kernel_abi_dist.bzl", _kernel_abi_dist = "kernel_abi_dist", _kernel_abi_wrapped_dist = "kernel_abi_wrapped_dist")
load("//build/kernel/kleaf/impl:android_filegroup.bzl", _android_filegroup = "android_filegroup")
load("//build/kernel/kleaf/impl:checkpatch.bzl", _checkpatch = "checkpatch")
load("//build/kernel/kleaf/impl:ddk/ddk_config.bzl", _ddk_config = "ddk_config")
load("//build/kernel/kleaf/impl:ddk/ddk_headers.bzl", _ddk_headers = "ddk_headers")
load("//build/kernel/kleaf/impl:ddk/ddk_headers_archive.bzl", _ddk_headers_archive = "ddk_headers_archive")
load("//build/kernel/kleaf/impl:ddk/ddk_library.bzl", _ddk_library = "ddk_library")
load("//build/kernel/kleaf/impl:ddk/ddk_module.bzl", _ddk_module = "ddk_module")
load("//build/kernel/kleaf/impl:ddk/ddk_prebuilt_object.bzl", _ddk_prebuilt_object = "ddk_prebuilt_object")
load("//build/kernel/kleaf/impl:ddk/ddk_submodule.bzl", _ddk_submodule = "ddk_submodule")
load("//build/kernel/kleaf/impl:ddk/ddk_uapi_headers.bzl", _ddk_uapi_headers = "ddk_uapi_headers")
load("//build/kernel/kleaf/impl:gki_artifacts.bzl", _gki_artifacts = "gki_artifacts", _gki_artifacts_prebuilts = "gki_artifacts_prebuilts")
load("//build/kernel/kleaf/impl:image/dtb_image.bzl", _dtb_image = "dtb_image")
load("//build/kernel/kleaf/impl:image/dtbo.bzl", _dtbo = "dtbo")
load("//build/kernel/kleaf/impl:image/initramfs.bzl", _initramfs = "initramfs")
load("//build/kernel/kleaf/impl:image/kernel_images.bzl", _kernel_images = "kernel_images")
load("//build/kernel/kleaf/impl:image/super_image.bzl", _super_image = "super_image", _unsparsed_image = "unsparsed_image")
load("//build/kernel/kleaf/impl:image/system_dlkm_image.bzl", _system_dlkm_image = "system_dlkm_image")
load("//build/kernel/kleaf/impl:image/vendor_boot_image.bzl", _vendor_boot_image = "vendor_boot_image")
load("//build/kernel/kleaf/impl:image/vendor_dlkm_image.bzl", _vendor_dlkm_image = "vendor_dlkm_image")
load("//build/kernel/kleaf/impl:kernel_build.bzl", _kernel_build_macro = "kernel_build")
load("//build/kernel/kleaf/impl:kernel_build_config.bzl", _kernel_build_config = "kernel_build_config")
load("//build/kernel/kleaf/impl:kernel_compile_commands.bzl", _kernel_compile_commands = "kernel_compile_commands")
load("//build/kernel/kleaf/impl:kernel_dtstree.bzl", _kernel_dtstree = "kernel_dtstree")
load("//build/kernel/kleaf/impl:kernel_filegroup.bzl", _kernel_filegroup = "kernel_filegroup")
load("//build/kernel/kleaf/impl:kernel_kythe.bzl", _kernel_kythe = "kernel_kythe")
load("//build/kernel/kleaf/impl:kernel_module.bzl", _kernel_module_macro = "kernel_module")
load("//build/kernel/kleaf/impl:kernel_module_group.bzl", _kernel_module_group = "kernel_module_group")
load("//build/kernel/kleaf/impl:kernel_modules_install.bzl", _kernel_modules_install = "kernel_modules_install")
load("//build/kernel/kleaf/impl:kernel_uapi_headers_cc_library.bzl", _kernel_uapi_headers_cc_library = "kernel_uapi_headers_cc_library")
load("//build/kernel/kleaf/impl:kernel_unstripped_modules_archive.bzl", _kernel_unstripped_modules_archive = "kernel_unstripped_modules_archive")
load("//build/kernel/kleaf/impl:merge_kzip.bzl", _merge_kzip = "merge_kzip")
load("//build/kernel/kleaf/impl:merge_module_symvers.bzl", _merge_module_symvers = "merge_module_symvers")
load("//build/kernel/kleaf/impl:merged_kernel_uapi_headers.bzl", _merged_kernel_uapi_headers = "merged_kernel_uapi_headers")
load("//build/kernel/kleaf/impl:modinfo_summary.bzl", _modinfo_summary_report = "modinfo_summary_report")
load("//build/kernel/kleaf/impl/testing:kernel_unit_test.bzl", _kunit_test = "kunit_test")

# Re-exports. This is the list of public rules and macros.
android_filegroup = _android_filegroup
checkpatch = _checkpatch
ddk_config = _ddk_config
ddk_headers = _ddk_headers
ddk_headers_archive = _ddk_headers_archive
ddk_library = _ddk_library
ddk_module = _ddk_module
ddk_prebuilt_object = _ddk_prebuilt_object
ddk_submodule = _ddk_submodule
ddk_uapi_headers = _ddk_uapi_headers
dependency_graph = _dependency_graph
dependency_graph_drawer = _dependency_graph_drawer
dependency_graph_extractor = _dependency_graph_extractor
dtb_image = _dtb_image
dtbo = _dtbo
extract_symbols = _extract_symbols
gki_artifacts = _gki_artifacts
gki_artifacts_prebuilts = _gki_artifacts_prebuilts
initramfs = _initramfs
initramfs_modules_lists_test = _initramfs_modules_lists_test
kernel_abi = _kernel_abi
kernel_abi_dist = _kernel_abi_dist
kernel_abi_wrapped_dist = _kernel_abi_wrapped_dist
kernel_build = _kernel_build_macro
kernel_build_config = _kernel_build_config
kernel_compile_commands = _kernel_compile_commands
kernel_dtstree = _kernel_dtstree
kernel_filegroup = _kernel_filegroup
kernel_images = _kernel_images
kernel_kythe = _kernel_kythe
kernel_module = _kernel_module_macro
kernel_module_group = _kernel_module_group
kernel_modules_install = _kernel_modules_install
kernel_uapi_headers_cc_library = _kernel_uapi_headers_cc_library
kernel_unstripped_modules_archive = _kernel_unstripped_modules_archive
merge_kzip = _merge_kzip
merge_module_symvers = _merge_module_symvers
merged_kernel_uapi_headers = _merged_kernel_uapi_headers
modinfo_summary_report = _modinfo_summary_report
super_image = _super_image
system_dlkm_image = _system_dlkm_image
unsparsed_image = _unsparsed_image
vendor_boot_image = _vendor_boot_image
vendor_dlkm_image = _vendor_dlkm_image

# Tests
kernel_module_test = _kernel_module_test
kunit_test = _kunit_test
