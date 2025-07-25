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

"""Utility functions to handle scmversion."""

load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@kernel_toolchain_info//:dict.bzl", "VARS")
load(
    ":common_providers.bzl",
    "KernelEnvInfo",
)
load(":hermetic_toolchain.bzl", "hermetic_toolchain")
load(":status.bzl", "status")

visibility("//build/kernel/kleaf/...")

def _get_status_at_path(info_file, status_name, quoted_src_path):
    # {path}:{scmversion} {path}:{scmversion} ...

    cmd = """extract_git_metadata "$({stable_status_cmd})" {quoted_src_path} {status_name}""".format(
        stable_status_cmd = status.get_status_cmd(info_file, status_name),
        quoted_src_path = quoted_src_path,
        status_name = status_name,
    )
    return cmd

def _write_localversion(ctx):
    """Sets up scmversion.

    This creates a separate action to set up scmversion to avoid direct
    dependency on stable-status.txt which contains metadata of all git
    projects in the repository, so that changes in unrelated projects does not
    trigger a rebuild.

    Args:
        ctx: [ctx](https://bazel.build/rules/lib/ctx) of `kernel_config`
    Returns:
        output localversion file
    """

    # workspace_status.py does not prepend BRANCH and KMI_GENERATION before
    # STABLE_SCMVERSION because their values aren't known at that point.
    # Emulate the logic in setlocalversion to prepend them.

    out_file = ctx.actions.declare_file(ctx.attr.name + "/localversion")
    if ctx.attr._config_is_stamp[BuildSettingInfo].value:
        inputs = [ctx.info_file]
        stable_scmversion_cmd = _get_status_at_path(ctx.info_file, "STABLE_SCMVERSIONS", '"${KERNEL_DIR}"')
    else:
        inputs = []
        stable_scmversion_cmd = "echo '-maybe-dirty'"

    transitive_inputs = [ctx.attr.env[KernelEnvInfo].inputs]
    tools = ctx.attr.env[KernelEnvInfo].tools

    cmd = ctx.attr.env[KernelEnvInfo].setup + """
        (
            # Extract the Android release version. If there is no match, then return 255
            # and clear the variable $android_release
            set +e
            if [[ "$BRANCH" == "android-mainline" ]]; then
                android_release="mainline"
            else
                android_release=$(echo "$BRANCH" | sed -e '/android[0-9]\\{{2,\\}}/!{{q255}}; s/^\\(android[0-9]\\{{2,\\}}\\)-.*/\\1/')
                if [[ $? -ne 0 ]]; then
                    echo "WARNING: Cannot extract android_release from BRANCH ${{BRANCH}}." >&2
                    android_release=
                fi
            fi
            set -e
            if [[ -n "$KMI_GENERATION" ]] && [[ $(expr $KMI_GENERATION : '^[0-9]\\+$') -eq 0 ]]; then
                echo "Invalid KMI_GENERATION $KMI_GENERATION" >&2
                exit 1
            fi
            scmversion=""
            stable_scmversion=$({stable_scmversion_cmd})
            scmversion_prefix=
            if [[ "$android_release" == "mainline" ]]; then
                scmversion_prefix="-mainline"
            elif [[ -n "$android_release" ]] && [[ -n "$KMI_GENERATION" ]]; then
                scmversion_prefix="-$android_release-$KMI_GENERATION"
            elif [[ -n "$android_release" ]] && [[ -z "$KMI_GENERATION" ]]; then
                echo "KMI_GENERATION is not set but BRANCH is ${{BRANCH}}" >&2
                exit 1
            elif [[ -z "$android_release" ]] && [[ -n "$KMI_GENERATION" ]]; then
                echo "No Android release can be extracted from BRANCH=${{BRANCH}} but KMI_GENERATION is ${{KMI_GENERATION}}" >&2
                exit 1
            fi
            scmversion="${{scmversion_prefix}}${{stable_scmversion}}"
            echo $scmversion
        ) > {out_path}
    """.format(
        stable_scmversion_cmd = stable_scmversion_cmd,
        out_path = out_file.path,
    )

    ctx.actions.run_shell(
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = [out_file],
        tools = tools,
        command = cmd,
        progress_message = "Determining scmversion %{label}",
        mnemonic = "KernelConfigScmversion",
    )
    return out_file

def _ext_mod_get_localversion_file_impl(
        subrule_ctx,
        ext_mod,
        follow_stamp_flag,
        # TODO: b/401120140 - Remove once --incompatible_auto_exec_groups is set
        hermetic_tools,
        # TODO: https://github.com/bazelbuild/bazel/issues/25695 - Remove once it is available in subrule_ctx
        info_file,
        _config_is_stamp,
        _build_utils_sh):
    """Creates a file that contains the localversion for the given external module.

    Args:
        subrule_ctx: subrule_ctx
        ext_mod: Defines the directory of the external module
        follow_stamp_flag: If true, respects --config=stamp. Otherwise returns None.
        hermetic_tools: hermetic tools
        info_file: ctx.info_file
        _config_is_stamp: --config=stamp
        _build_utils_sh: build_utils.sh
    Returns:
        If follow_stamp_flag, and --config=stamp, returns the file that contains
        the localversion. Otherwise returns None.
    """

    if not follow_stamp_flag or not _config_is_stamp[BuildSettingInfo].value:
        return None

    inputs = [info_file, _build_utils_sh]

    # This creates a separate action to set up scmversion to avoid direct
    # dependency on stable-status.txt which contains metadata of all git
    # projects in the repository, so that changes in unrelated projects does not
    # trigger a rebuild.
    localversion_file = subrule_ctx.actions.declare_file(subrule_ctx.label.name + "/localversion")
    scmversion_cmd = _get_status_at_path(info_file, "STABLE_SCMVERSIONS", shell.quote(ext_mod))
    cmd = hermetic_tools.setup + """
        . {build_utils_sh}
        ( {scmversion_cmd} ) > {localversion_file}
    """.format(
        build_utils_sh = _build_utils_sh.path,
        scmversion_cmd = scmversion_cmd,
        localversion_file = localversion_file.path,
    )
    subrule_ctx.actions.run_shell(
        inputs = depset(inputs),
        outputs = [localversion_file],
        tools = hermetic_tools.deps,
        command = cmd,
        progress_message = "Determining scmversion for module %{label}",
        mnemonic = "KernelModuleScmversion",
    )
    return localversion_file

_ext_mod_get_localversion_file = subrule(
    implementation = _ext_mod_get_localversion_file_impl,
    attrs = {
        "_config_is_stamp": attr.label(default = "//build/kernel/kleaf:config_stamp"),
        "_build_utils_sh": attr.label(
            default = "//build/kernel:build_utils",
            allow_single_file = True,
        ),
    },
)

def _ext_mod_write_localversion(ctx, ext_mod):
    """Return command and inputs to get the SCM version for an external module.

    Args:
        ctx: [ctx](https://bazel.build/rules/lib/ctx).
            Must have `hermetic_tools` in toolchain.
        ext_mod: Defines the directory of the external module
    """

    localversion_file = _ext_mod_get_localversion_file(
        ext_mod = ext_mod,
        follow_stamp_flag = True,
        hermetic_tools = hermetic_toolchain.get(ctx),
        info_file = ctx.info_file,
    )
    if not localversion_file:
        cmd = """
            rm -f ${OUT_DIR}/localversion
        """
        return struct(deps = [], cmd = cmd)

    if VARS.get("KLEAF_INTERNAL_EXT_MODULE_SEPARATE_BUILD_DIR") == "1":
        dest_dir = "${OUT_DIR}/${ext_mod_rel}"
    else:
        dest_dir = "${OUT_DIR}"

    ret_cmd = """
        mkdir -p {dest_dir}
        rsync -aL --chmod=F+w {localversion_file} {dest_dir}/localversion
    """.format(
        dest_dir = dest_dir,
        localversion_file = localversion_file.path,
    )

    return struct(deps = [localversion_file], cmd = ret_cmd)

def _set_source_date_epoch(ctx):
    """Return command and inputs to set the value of `SOURCE_DATE_EPOCH`.

    Args:
        ctx: [ctx](https://bazel.build/rules/lib/ctx)
    """
    if ctx.attr._config_is_stamp[BuildSettingInfo].value:
        # SOURCE_DATE_EPOCH needs to be set before calling _setup_env.sh to
        # avoid calling into git. However, determining the correct SOURCE_DATE_EPOCH
        # from SOURCE_DATE_EPOCHS needs KERNEL_DIR, which is set by
        # _setup_env.sh. Hence, set a separate variable
        # KLEAF_SOURCE_DATE_EPOCHS so _setup_env.sh can use it to determine
        # SOURCE_DATE_EPOCH.
        # We can't put the reading of ctx.info_file in a separate action because
        # KERNEL_DIR is not known without source _setup_env.sh. This is okay
        # because kernel_env executes relatively quickly, and only the final
        # result (SOURCE_DATE_EPOCH) is emitted in *_env.sh.
        return struct(deps = [ctx.info_file], cmd = """
              export KLEAF_SOURCE_DATE_EPOCHS=$({source_date_epoch_cmd})
        """.format(source_date_epoch_cmd = status.get_stable_status_cmd(ctx, "STABLE_SOURCE_DATE_EPOCHS")))
    else:
        return struct(deps = [], cmd = """
              export SOURCE_DATE_EPOCH=0
        """)

def _set_localversion_cmd(_ctx):
    """Return command that sets `LOCALVERSION` for `--config=stamp`, otherwise empty.

    After setting `LOCALVERSION`, `setlocalversion` script reduces code paths
    that executes `git`.
    """

    # Suppress the behavior of setlocalversion looking into .git directory to decide whether
    # to append a plus sign or not.
    return """
        export LOCALVERSION=""
    """

stamp = struct(
    write_localversion = _write_localversion,
    ext_mod_write_localversion = _ext_mod_write_localversion,
    ext_mod_get_localversion_file = _ext_mod_get_localversion_file,
    set_source_date_epoch = _set_source_date_epoch,
    set_localversion_cmd = _set_localversion_cmd,
)
