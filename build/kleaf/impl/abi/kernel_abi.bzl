# Copyright (C) 2022 The Android Open Source Project
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

"""Rules to enable ABI monitoring."""

load("//build/kernel/kleaf:fail.bzl", "fail_rule")
load("//build/kernel/kleaf:update_source_file.bzl", "update_source_file")
load(":abi/abi_dump.bzl", "abi_dump")
load(":abi/abi_stgdiff.bzl", "stgdiff")
load(":abi/abi_transitions.bzl", "abi_common_attrs", "with_vmlinux_transition")
load(":abi/abi_update.bzl", "abi_update")
load(":abi/extracted_symbols.bzl", "extracted_symbols")
load(":abi/get_src_kmi_symbol_list.bzl", "get_src_kmi_symbol_list")
load(":abi/get_src_protected_exports_files.bzl", "get_src_protected_exports_list", "get_src_protected_modules_list")
load(":abi/protected_exports.bzl", "protected_exports")
load(":common_providers.bzl", "KernelBuildAbiInfo")
load(":diff.bzl", "diff")
load(":empty_binary.bzl", "empty_binary")
load(":kernel_build.bzl", "kernel_build")

visibility("//build/kernel/kleaf/...")

def _kmi_symbol_checks_impl(ctx):
    kmi_strict_mode_out = ctx.attr.kernel_build[KernelBuildAbiInfo].kmi_strict_mode_out
    kmi_strict_mode_out = depset([kmi_strict_mode_out]) if kmi_strict_mode_out else None
    return DefaultInfo(files = kmi_strict_mode_out)

kmi_symbol_checks = rule(
    doc = "Returns kmi symbol checks for a `kernel_build`.",
    implementation = _kmi_symbol_checks_impl,
    attrs = {
        "kernel_build": attr.label(providers = [KernelBuildAbiInfo]),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    } | abi_common_attrs(),
    cfg = with_vmlinux_transition,
)

def kernel_abi(
        name,
        kernel_build,
        define_abi_targets = None,
        kernel_modules = None,
        module_grouping = None,
        abi_definition_stg = None,
        kmi_enforced = None,
        unstripped_modules_archive = None,
        kmi_symbol_list_add_only = None,
        kernel_modules_exclude_list = None,
        enable_add_vmlinux = None,
        **kwargs):
    """Declare multiple targets to support ABI monitoring.

    This macro is meant to be used alongside [`kernel_build`](#kernel_build)
    macro.

    For example, you may have the following declaration. (For actual definition
    of `kernel_aarch64`, see
    [`define_common_kernels()`](#define_common_kernels).

    ```
    kernel_build(name = "kernel_aarch64", ...)
    kernel_abi(
        name = "kernel_aarch64_abi",
        kernel_build = ":kernel_aarch64",
        ...
    )
    ```

    The `kernel_abi` invocation above defines the following targets:
    - `kernel_aarch64_abi_dump`
      - Building this target extracts the ABI.
      - Include this target in a [`kernel_abi_dist`](#kernel_abi_dist)
        target to copy ABI dump to `--dist-dir`.
    - `kernel_aarch64_abi`
      - A filegroup that contains `kernel_aarch64_abi_dump`. It also contains other targets
        if `define_abi_targets = True`; see below.

    In addition, the following targets are defined if `define_abi_targets = True`:
    - `kernel_aarch64_abi_update_symbol_list`
      - Running this target updates `kmi_symbol_list`.
    - `kernel_aarch64_abi_update_protected_exports`
      - Running this target updates `protected_exports_list`.
    - `kernel_aarch64_abi_update`
      - Running this target updates `abi_definition`.
    - `kernel_aarch64_abi_dump`
      - Building this target extracts the ABI.
      - Include this target in a [`kernel_abi_dist`](#kernel_abi_dist)
        target to copy ABI dump to `--dist-dir`.

    To create a distribution, see
    [`kernel_abi_wrapped_dist`](#kernel_abi_wrapped_dist).

    See build/kernel/kleaf/abi.md for a conversion chart from `build_abi.sh`
    commands to Bazel commands.

    Args:
      name: Name of this target.
      kernel_build: The [`kernel_build`](#kernel_build).
      define_abi_targets: Whether the target contains other
        files to support ABI monitoring. If `None`, defaults to `True`.

        If `False`, this macro is equivalent to just calling
        ```
        kernel_build(name = name, **kwargs)
        filegroup(name = name + "_abi", data = [name, abi_dump_target])
        ```

        If `True`, implies `collect_unstripped_modules = True`. See
        [`kernel_build.collect_unstripped_modules`](#kernel_build-collect_unstripped_modules).
      kernel_modules: A list of external [`kernel_module()`](#kernel_module)s
        to extract symbols from.
      kernel_modules_exclude_list: List of base names for in-tree kernel modules to exclude from.
        i.e. This is the modules built in `kernel_build`, not the `kernel_modules` mentioned above.
      module_grouping: If unspecified or `None`, it is `True` by default.
        If `True`, then the symbol list will group symbols based
        on the kernel modules that reference the symbol. Otherwise the symbol
        list will simply be a sorted list of symbols used by all the kernel
        modules.
      abi_definition_stg: Location of the ABI definition in STG format.
      kmi_enforced: This is an indicative option to signal that KMI is enforced.
        If set to `True`, KMI checking tools respects it and
        reacts to it by failing if KMI differences are detected.
      unstripped_modules_archive: A [`kernel_unstripped_modules_archive`](#kernel_unstripped_modules_archive)
        which name is specified in `abi.prop`. DEPRECATED.
      kmi_symbol_list_add_only: If unspecified or `None`, it is `False` by
        default. If `True`,
        then any symbols in the symbol list that would have been
        removed are preserved (at the end of the file). Symbol list update will
        fail if there is no pre-existing symbol list file to read from. This
        property is intended to prevent unintentional shrinkage of a stable ABI.

        This should be set to `True` if `KMI_SYMBOL_LIST_ADD_ONLY=1`.
      enable_add_vmlinux: If unspecified or `None`, it is `True` by default.
        If `True`, enable the `kernel_build_add_vmlinux`
        [transition](https://bazel.build/extending/config#user-defined-transitions) from all targets
        instantiated by this macro (e.g. produced by abi_dump, extracted_symbols, etc).
      **kwargs: Additional attributes to the internal rule, e.g.
        [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
        See complete list
        [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    if define_abi_targets == None:
        define_abi_targets = True

    if unstripped_modules_archive != None:
        # buildifier: disable=print
        print("WARNING: unstripped_modules_archive is DEPRECATED, and" +
              " will be REMOVED in the future, consider removing it" +
              " from {}".format(name))

    private_kwargs = kwargs | {
        "visibility": ["//visibility:private"],
    }

    abi_dump(
        name = name + "_dump",
        kernel_build = kernel_build,
        kernel_modules = kernel_modules,
        enable_add_vmlinux = enable_add_vmlinux,
        **private_kwargs
    )

    if not define_abi_targets:
        _not_define_abi_targets(
            name = name,
            abi_dump_target = name + "_dump",
            **kwargs
        )
    else:
        _define_abi_targets(
            name = name,
            kernel_build = kernel_build,
            kernel_modules = kernel_modules,
            module_grouping = module_grouping,
            kmi_symbol_list_add_only = kmi_symbol_list_add_only,
            abi_definition_stg = abi_definition_stg,
            kmi_enforced = kmi_enforced,
            abi_dump_target = name + "_dump",
            kernel_modules_exclude_list = kernel_modules_exclude_list,
            enable_add_vmlinux = enable_add_vmlinux,
            **kwargs
        )

def _not_define_abi_targets(
        name,
        abi_dump_target,
        **kwargs):
    """Helper to `_define_other_targets` when `define_abi_targets = False.`

    Defines `{name}` filegroup that only contains the ABI dump, provided
    in `abi_dump_target`.

    Defines:
    * `{name}_diff_executable`
    * `{name}`
    """

    private_kwargs = kwargs | {
        "visibility": ["//visibility:private"],
    }

    native.filegroup(
        name = name,
        srcs = [abi_dump_target],
        **kwargs
    )

    # For kernel_abi_dist to use when define_abi_targets is not set.
    empty_binary(
        name = name + "_diff_executable",
        **private_kwargs
    )
    empty_binary(
        name = name + "_diff_executable_xml",
        **private_kwargs
    )

    fail_rule(
        name = name + "_update",
        message = "{} and other ABI targets are not setup.\n".format(
                      name + "_update",
                  ) +
                  "See kleaf/docs/abi.md for more information.",
    )

def _define_abi_targets(
        name,
        kernel_build,
        kernel_modules,
        module_grouping,
        kmi_symbol_list_add_only,
        abi_definition_stg,
        kmi_enforced,
        abi_dump_target,
        kernel_modules_exclude_list,
        enable_add_vmlinux,
        **kwargs):
    """Helper to `_define_other_targets` when `define_abi_targets = True.`

    Define targets to extract symbol list, extract ABI, update them, etc.

    Defines:
    * `{name}_diff_executable`
    * `{name}`
    """

    private_kwargs = kwargs | {
        "visibility": ["//visibility:private"],
    }

    default_outputs = [abi_dump_target]

    get_src_kmi_symbol_list(
        name = name + "_src_kmi_symbol_list",
        kernel_build = kernel_build,
        **private_kwargs
    )

    kmi_symbol_checks(
        name = name + "_kmi_symbol_checks",
        kernel_build = kernel_build,
        enable_add_vmlinux = enable_add_vmlinux,
        **private_kwargs
    )

    # extract_symbols ...
    extracted_symbols(
        name = name + "_extracted_symbols",
        kernel_build = kernel_build,
        kernel_modules = kernel_modules,
        module_grouping = module_grouping,
        src = name + "_src_kmi_symbol_list",
        kmi_symbol_list_add_only = kmi_symbol_list_add_only,
        kernel_modules_exclude_list = kernel_modules_exclude_list,
        enable_add_vmlinux = enable_add_vmlinux,
        **private_kwargs
    )

    # Sync with kleaf/bazel.py
    update_source_file(
        name = name + "_update_symbol_list",
        src = name + "_extracted_symbols",
        dst = name + "_src_kmi_symbol_list",
        **private_kwargs
    )

    # Protected Exports
    get_src_protected_exports_list(
        name = name + "_src_protected_exports_list",
        kernel_build = kernel_build,
        **private_kwargs
    )
    get_src_protected_modules_list(
        name = name + "_src_protected_modules_list",
        kernel_build = kernel_build,
        **private_kwargs
    )
    protected_exports(
        name = name + "_protected_exports",
        kernel_build = kernel_build,
        protected_modules_list_file = name + "_src_protected_modules_list",
        enable_add_vmlinux = enable_add_vmlinux,
        **private_kwargs
    )
    update_source_file(
        name = name + "_update_protected_exports",
        src = name + "_protected_exports",
        dst = name + "_src_protected_exports_list",
        **private_kwargs
    )

    default_outputs += _define_abi_definition_targets(
        name = name,
        abi_definition_stg = abi_definition_stg,
        kmi_enforced = kmi_enforced,
        kmi_symbol_list = name + "_src_kmi_symbol_list",
        protected_exports_list = name + "_src_protected_exports_list",
        kmi_symbol_checks = name + "_kmi_symbol_checks",
        **kwargs
    )

    native.filegroup(
        name = name,
        srcs = default_outputs,
        **kwargs
    )

def _define_abi_definition_targets(
        name,
        abi_definition_stg,
        kmi_enforced,
        kmi_symbol_list,
        protected_exports_list,
        kmi_symbol_checks,
        **kwargs):
    """Helper to `_define_abi_targets`.

    Defines targets to extract ABI, update ABI, compare ABI, etc. etc.

    Defines `{name}_diff_executable`.
    """

    private_kwargs = kwargs | {
        "visibility": ["//visibility:private"],
    }

    default_outputs = []

    if not abi_definition_stg:
        # For kernel_abi_dist to use when abi_definition is empty.
        empty_binary(
            name = name + "_diff_executable",
            **private_kwargs
        )
        default_outputs.append(name + "_diff_executable")

        fail_rule(
            name = name + "_update",
            message = "In {} `define_abi_targets` is True but `abi_definition_stg` was not provided.\n".format(
                          name,
                      ) +
                      "See kleaf/docs/abi.md for more information.",
            **kwargs
        )
    else:
        native.filegroup(
            name = name + "_out_file",
            srcs = [name + "_dump"],
            output_group = "abi_out_file",
            **private_kwargs
        )
        stgdiff(
            name = name + "_diff",
            baseline = abi_definition_stg,
            new = name + "_out_file",
            kmi_enforced = kmi_enforced,
            **kwargs
        )
        default_outputs.append(name + "_diff")

        # Use this filegroup to select the executable.
        native.filegroup(
            name = name + "_diff_executable",
            srcs = [name + "_diff"],
            output_group = "executable",
            **private_kwargs
        )

        native.filegroup(
            name = name + "_diff_git_message",
            srcs = [name + "_diff"],
            output_group = "git_message",
            **private_kwargs
        )

        diff(
            name = name + "_diff_symbol_list",
            file1 = name + "_extracted_symbols",
            file2 = kmi_symbol_list,
            failure_message = """\
symbol list must be updated before updating ABI definition.
    To update, execute
        tools/bazel run {}
    To discover additional files to be updated, execute
        tools/bazel run -k {}""".format(
                native.package_relative_label(name + "_update_symbol_list"),
                native.package_relative_label(name + "_update"),
            ),
            **private_kwargs
        )

        diff(
            name = name + "_diff_protected_exports_list",
            file1 = name + "_protected_exports",
            file2 = protected_exports_list,
            failure_message = """\
protected exports list must be updated before updating ABI definition.
    To update, execute
        tools/bazel run {}
    To discover additional files to be updated, execute
        tools/bazel run -k {}""".format(
                native.package_relative_label(native.package_relative_label(name + "_update_protected_exports")),
                native.package_relative_label(name + "_update"),
            ),
            **private_kwargs
        )

        update_source_file(
            name = name + "_nodiff_update",
            src = name + "_out_file",
            dst = abi_definition_stg,
            deps = [
                name + "_diff_symbol_list",
                name + "_diff_protected_exports_list",
                # Ensure KMI checks are executed before updating ABI.
                kmi_symbol_checks,
            ],
            **private_kwargs
        )

        abi_update(
            name = name + "_update",
            abi_definition_stg = abi_definition_stg,
            git_message = name + "_diff_git_message",
            diff = name + "_diff_executable",
            nodiff_update = name + "_nodiff_update",
            **kwargs
        )

    return default_outputs
