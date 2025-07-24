#!/bin/bash

# 增量编译版本 - 基于原始build.sh优化
# 主要改进：
# 1. 智能跳过清理步骤
# 2. 增量模块编译
# 3. 更好的缓存管理
# 4. 文件变化检测

# Copyright (C) 2019 The Android Open Source Project
# (原始版权信息保持不变)

set -e

# 新增：增量编译控制变量
INCREMENTAL_BUILD=${INCREMENTAL_BUILD:-1}  # 默认启用增量编译
FORCE_CLEAN=${FORCE_CLEAN:-0}              # 强制清理
CHECK_DEPS=${CHECK_DEPS:-1}                # 检查依赖变化
VERBOSE_INCREMENTAL=${VERBOSE_INCREMENTAL:-0}  # 增量编译详细输出

# 新增：增量编译日志函数
function log_incremental() {
    if [ "${VERBOSE_INCREMENTAL}" -eq 1 ]; then
        echo "[INCREMENTAL] $1"
    fi
}

# 新增：检查文件是否需要重新编译
function check_file_changed() {
    local source_file="$1"
    local target_file="$2"
    
    if [ ! -f "${target_file}" ]; then
        log_incremental "Target ${target_file} doesn't exist, need rebuild"
        return 0  # 需要重建
    fi
    
    if [ "${source_file}" -nt "${target_file}" ]; then
        log_incremental "Source ${source_file} newer than ${target_file}"
        return 0  # 需要重建
    fi
    
    return 1  # 不需要重建
}

# rel_path 函数保持不变
function rel_path() {
	local to=$1
	local from=$2
	local path=
	local stem=
	local prevstem=
	[ -n "$to" ] || return 1
	[ -n "$from" ] || return 1
	to=$(readlink -e "$to")
	from=$(readlink -e "$from")
	[ -n "$to" ] || return 1
	[ -n "$from" ] || return 1
	stem=${from}/
	while [ "${to#$stem}" == "${to}" -a "${stem}" != "${prevstem}" ]; do
		prevstem=$stem
		stem=$(readlink -e "${stem}/..")
		[ "${stem%/}" == "${stem}" ] && stem=${stem}/
		path=${path}../
	done
	echo ${path}${to#$stem}
}

export ROOT_DIR=$(readlink -f $(dirname $0)/..)

# 模块签名相关（保持不变）
FILE_SIGN_BIN=scripts/sign-file
SIGN_SEC=certs/signing_key.pem
SIGN_CERT=certs/signing_key.x509
SIGN_ALGO=sha512

# 保存环境参数
CC_ARG="${CC}"

source "${ROOT_DIR}/build/_setup_env.sh"

# 新增：增量编译状态文件
INCREMENTAL_STATE_DIR="${COMMON_OUT_DIR}/.incremental"
LAST_BUILD_CONFIG="${INCREMENTAL_STATE_DIR}/last_build_config"
LAST_KERNEL_CONFIG="${INCREMENTAL_STATE_DIR}/last_kernel_config"
MODULES_TIMESTAMP="${INCREMENTAL_STATE_DIR}/modules_timestamp"

mkdir -p "${INCREMENTAL_STATE_DIR}"

export MAKE_ARGS=$*
export MAKEFLAGS="-j$(nproc) ${MAKEFLAGS}"
export MODULES_STAGING_DIR=$(readlink -m ${COMMON_OUT_DIR}/staging)
export MODULES_PRIVATE_DIR=$(readlink -m ${COMMON_OUT_DIR}/private)
export UNSTRIPPED_DIR=${DIST_DIR}/unstripped
export KERNEL_UAPI_HEADERS_DIR=$(readlink -m ${COMMON_OUT_DIR}/kernel_uapi_headers)
export INITRAMFS_STAGING_DIR=${MODULES_STAGING_DIR}/initramfs_staging

BOOT_IMAGE_HEADER_VERSION=${BOOT_IMAGE_HEADER_VERSION:-3}

cd ${ROOT_DIR}

export CLANG_TRIPLE CROSS_COMPILE CROSS_COMPILE_COMPAT CROSS_COMPILE_ARM32 ARCH SUBARCH MAKE_GOALS

# 恢复CC参数
[ -n "${CC_ARG}" ] && CC="${CC_ARG}"
[ "${CC}" == "gcc" ] && unset CC && unset CC_ARG

# 工具参数设置（保持不变）
TOOL_ARGS=()
if [ -n "${CC}" ]; then
  TOOL_ARGS+=("CC=${CC}" "HOSTCC=${CC}")
fi
if [ -n "${LD}" ]; then
  TOOL_ARGS+=("LD=${LD}")
fi
if [ -n "${NM}" ]; then
  TOOL_ARGS+=("NM=${NM}")
fi
if [ -n "${OBJCOPY}" ]; then
  TOOL_ARGS+=("OBJCOPY=${OBJCOPY}")
fi

CC_LD_ARG="${TOOL_ARGS[@]}"

mkdir -p ${OUT_DIR} ${DIST_DIR}

# 新增：检查是否需要完全重新编译
NEED_FULL_REBUILD=0

if [ "${FORCE_CLEAN}" -eq 1 ]; then
    log_incremental "Force clean requested"
    NEED_FULL_REBUILD=1
elif [ "${INCREMENTAL_BUILD}" -eq 0 ]; then
    log_incremental "Incremental build disabled"
    NEED_FULL_REBUILD=1
elif [ ! -f "${LAST_BUILD_CONFIG}" ]; then
    log_incremental "No previous build config found"
    NEED_FULL_REBUILD=1
else
    # 检查构建配置是否改变
    CURRENT_BUILD_CONFIG="${BUILD_CONFIG:-build.config}"
    if [ -f "${ROOT_DIR}/${CURRENT_BUILD_CONFIG}" ]; then
        if ! diff -q "${ROOT_DIR}/${CURRENT_BUILD_CONFIG}" "${LAST_BUILD_CONFIG}" >/dev/null 2>&1; then
            log_incremental "Build config changed"
            NEED_FULL_REBUILD=1
        fi
    fi
    
    # 检查内核配置是否改变
    if [ -f "${OUT_DIR}/.config" ] && [ -f "${LAST_KERNEL_CONFIG}" ]; then
        if ! diff -q "${OUT_DIR}/.config" "${LAST_KERNEL_CONFIG}" >/dev/null 2>&1; then
            log_incremental "Kernel config changed"
            NEED_FULL_REBUILD=1
        fi
    fi
fi

echo "========================================================"
if [ "${NEED_FULL_REBUILD}" -eq 1 ]; then
    echo " Setting up for FULL build"
    SKIP_MRPROPER=""
    SKIP_DEFCONFIG=""
else
    echo " Setting up for INCREMENTAL build"
    SKIP_MRPROPER="1"
    SKIP_DEFCONFIG="1"
    log_incremental "Skipping mrproper and defconfig for incremental build"
fi

# mrproper步骤 - 增量编译时跳过
if [ -z "${SKIP_MRPROPER}" ] ; then
  set -x
  (cd ${KERNEL_DIR} && make "${TOOL_ARGS[@]}" O=${OUT_DIR} ${MAKE_ARGS} mrproper)
  set +x
fi

# PRE_DEFCONFIG_CMDS（保持不变）
if [ -n "${PRE_DEFCONFIG_CMDS}" ]; then
  echo "========================================================"
  echo " Running pre-defconfig command(s):"
  set -x
  eval ${PRE_DEFCONFIG_CMDS}
  set +x
fi

# defconfig步骤 - 增量编译时可能跳过
if [ -z "${SKIP_DEFCONFIG}" ] ; then
    set -x
    (cd ${KERNEL_DIR} && make "${TOOL_ARGS[@]}" O=${OUT_DIR} ${MAKE_ARGS} ${DEFCONFIG})
    set +x

    if [ -n "${POST_DEFCONFIG_CMDS}" ]; then
      echo "========================================================"
      echo " Running pre-make command(s):"
      set -x
      eval ${POST_DEFCONFIG_CMDS}
      set +x
    fi
elif [ "${INCREMENTAL_BUILD}" -eq 1 ]; then
    log_incremental "Skipped defconfig step for incremental build"
fi

# 保存当前构建配置用于下次增量编译检查
if [ "${INCREMENTAL_BUILD}" -eq 1 ]; then
    CURRENT_BUILD_CONFIG="${BUILD_CONFIG:-build.config}"
    if [ -f "${ROOT_DIR}/${CURRENT_BUILD_CONFIG}" ]; then
        cp "${ROOT_DIR}/${CURRENT_BUILD_CONFIG}" "${LAST_BUILD_CONFIG}"
    fi
fi

# TAGS处理（保持不变）
if [ -n "${TAGS_CONFIG}" ]; then
  echo "========================================================"
  echo " Running tags command:"
  set -x
  (cd ${KERNEL_DIR} && SRCARCH=${ARCH} ./scripts/tags.sh ${TAGS_CONFIG})
  set +x
  exit 0
fi

# ABI处理（保持不变）
ABI_PROP=${DIST_DIR}/abi.prop
: > ${ABI_PROP}

if [ -n "${ABI_DEFINITION}" ]; then
  ABI_XML=${DIST_DIR}/abi.xml
  echo "KMI_DEFINITION=abi.xml" >> ${ABI_PROP}
  echo "KMI_MONITORED=1"        >> ${ABI_PROP}
  if [ -n "${KMI_ENFORCED}" ]; then
    echo "KMI_ENFORCED=1" >> ${ABI_PROP}
  fi
fi

if [ -n "${KMI_WHITELIST}" ]; then
  ABI_WL=${DIST_DIR}/abi_whitelist
  echo "KMI_WHITELIST=abi_whitelist" >> ${ABI_PROP}
fi

# ABI文件复制（条件性执行）
if [ -n "${ABI_DEFINITION}" ]; then
  if check_file_changed "${ROOT_DIR}/${KERNEL_DIR}/${ABI_DEFINITION}" "${ABI_XML}"; then
    echo "========================================================"
    echo " Copying abi definition to ${ABI_XML}"
    pushd $ROOT_DIR/$KERNEL_DIR
      cp "${ABI_DEFINITION}" ${ABI_XML}
    popd
  else
    log_incremental "ABI definition unchanged, skipping copy"
  fi
fi

# KMI处理（保持原有逻辑，但添加增量检查）
if [ -n "${KMI_WHITELIST}" ]; then
  if [ "${NEED_FULL_REBUILD}" -eq 1 ] || check_file_changed "${ROOT_DIR}/${KERNEL_DIR}/${KMI_WHITELIST}" "${ABI_WL}"; then
    echo "========================================================"
    echo " Generating abi whitelist definition to ${ABI_WL}"
    pushd $ROOT_DIR/$KERNEL_DIR
      cp "${KMI_WHITELIST}" ${ABI_WL}

      if [ -n "${ADDITIONAL_KMI_WHITELISTS}" ]; then
        for whitelist in ${ADDITIONAL_KMI_WHITELISTS}; do
            echo >> ${ABI_WL}
            cat "${whitelist}" >> ${ABI_WL}
        done
      fi

      if [ -n "${TRIM_NONLISTED_KMI}" ]; then
          cat ${ABI_WL} | \
                  ${ROOT_DIR}/build/abi/flatten_whitelist > \
                  ${OUT_DIR}/abi_whitelist.raw

          ./scripts/config --file ${OUT_DIR}/.config \
                  -d UNUSED_SYMBOLS -e TRIM_UNUSED_KSYMS \
                  --set-str UNUSED_KSYMS_WHITELIST ${OUT_DIR}/abi_whitelist.raw
          (cd ${OUT_DIR} && \
                  make O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MAKE_ARGS} olddefconfig)
          grep CONFIG_UNUSED_KSYMS_WHITELIST ${OUT_DIR}/.config > /dev/null || {
            echo "ERROR: Failed to apply TRIM_NONLISTED_KMI kernel configuration" >&2
            exit 1
          }

      elif [ -n "${KMI_WHITELIST_STRICT_MODE}" ]; then
        echo "ERROR: KMI_WHITELIST_STRICT_MODE requires TRIM_NONLISTED_KMI=1" >&2
        exit 1
      fi
    popd
  else
    log_incremental "KMI whitelist unchanged, skipping regeneration"
  fi
elif [ -n "${TRIM_NONLISTED_KMI}" ]; then
  echo "ERROR: TRIM_NONLISTED_KMI requires a KMI_WHITELIST" >&2
  exit 1
elif [ -n "${KMI_WHITELIST_STRICT_MODE}" ]; then
  echo "ERROR: KMI_WHITELIST_STRICT_MODE requires a KMI_WHITELIST" >&2
  exit 1
fi

echo "========================================================"
if [ "${INCREMENTAL_BUILD}" -eq 1 ] && [ "${NEED_FULL_REBUILD}" -eq 0 ]; then
    echo " Building kernel (INCREMENTAL)"
    log_incremental "Using incremental compilation"
else
    echo " Building kernel (FULL)"
fi

set -x
(cd ${OUT_DIR} && make O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MAKE_ARGS} ${MAKE_GOALS})
set +x

# 保存内核配置用于下次增量编译检查
if [ "${INCREMENTAL_BUILD}" -eq 1 ] && [ -f "${OUT_DIR}/.config" ]; then
    cp "${OUT_DIR}/.config" "${LAST_KERNEL_CONFIG}"
fi

if [ -n "${POST_KERNEL_BUILD_CMDS}" ]; then
  echo "========================================================"
  echo " Running post-kernel-build command(s):"
  set -x
  eval ${POST_KERNEL_BUILD_CMDS}
  set +x
fi

if [ -n "${KMI_WHITELIST_STRICT_MODE}" ]; then
  echo "========================================================"
  echo " Comparing the KMI and the whitelists:"
  set -x
  ${ROOT_DIR}/build/abi/compare_to_wl "${OUT_DIR}/Module.symvers" \
                                      "${OUT_DIR}/abi_whitelist.raw"
  set +x
fi

# 模块安装 - 增量优化
rm -rf ${MODULES_STAGING_DIR}
mkdir -p ${MODULES_STAGING_DIR}

if [ -z "${DO_NOT_STRIP_MODULES}" ]; then
    MODULE_STRIP_FLAG="INSTALL_MOD_STRIP=1"
fi

# 内核模块安装（改进：检查是否需要重新安装）
if [ -n "${BUILD_INITRAMFS}" -o  -n "${IN_KERNEL_MODULES}" ]; then
  NEED_MODULE_INSTALL=1
  
  if [ "${INCREMENTAL_BUILD}" -eq 1 ] && [ -f "${MODULES_TIMESTAMP}" ]; then
    # 检查是否有模块文件比时间戳新
    NEWER_MODULES=$(find ${OUT_DIR} -name "*.ko" -newer "${MODULES_TIMESTAMP}" 2>/dev/null | wc -l)
    if [ "${NEWER_MODULES}" -eq 0 ]; then
      log_incremental "No modules changed, skipping module install"
      NEED_MODULE_INSTALL=0
    else
      log_incremental "Found ${NEWER_MODULES} changed modules"
    fi
  fi
  
  if [ "${NEED_MODULE_INSTALL}" -eq 1 ]; then
    echo "========================================================"
    echo " Installing kernel modules into staging directory"
    (cd ${OUT_DIR} &&                                                           \
     make O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MODULE_STRIP_FLAG}                   \
          INSTALL_MOD_PATH=${MODULES_STAGING_DIR} ${MAKE_ARGS} modules_install)
    
    # 更新模块时间戳
    touch "${MODULES_TIMESTAMP}"
  else
    # 恢复之前的模块安装
    if [ -d "${MODULES_STAGING_DIR}.backup" ]; then
      cp -r "${MODULES_STAGING_DIR}.backup"/* "${MODULES_STAGING_DIR}/"
    fi
  fi
fi

# 外部模块编译 - 增量优化
if [[ -z "${SKIP_EXT_MODULES}" ]] && [[ -n "${EXT_MODULES}" ]]; then
  echo "========================================================"
  echo " Building external modules and installing them into staging directory"

  for EXT_MOD in ${EXT_MODULES}; do
    EXT_MOD_REL=$(rel_path ${ROOT_DIR}/${EXT_MOD} ${KERNEL_DIR})
    EXT_MOD_TIMESTAMP="${INCREMENTAL_STATE_DIR}/$(echo ${EXT_MOD} | tr '/' '_')_timestamp"
    
    NEED_EXT_MODULE_BUILD=1
    
    if [ "${INCREMENTAL_BUILD}" -eq 1 ] && [ -f "${EXT_MOD_TIMESTAMP}" ]; then
      # 检查外部模块源文件是否有变化
      NEWER_EXT_FILES=$(find ${ROOT_DIR}/${EXT_MOD} -name "*.c" -o -name "*.h" -o -name "Makefile" | \
                        xargs ls -t | head -1 | xargs stat -c %Y)
      EXT_TIMESTAMP=$(stat -c %Y "${EXT_MOD_TIMESTAMP}")
      
      if [ "${NEWER_EXT_FILES}" -le "${EXT_TIMESTAMP}" ]; then
        log_incremental "External module ${EXT_MOD} unchanged, skipping build"
        NEED_EXT_MODULE_BUILD=0
      fi
    fi
    
    if [ "${NEED_EXT_MODULE_BUILD}" -eq 1 ]; then
      mkdir -p ${OUT_DIR}/${EXT_MOD_REL}
      set -x
      make -C ${EXT_MOD} M=${EXT_MOD_REL} KERNEL_SRC=${ROOT_DIR}/${KERNEL_DIR}  \
                         O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MAKE_ARGS}
      make -C ${EXT_MOD} M=${EXT_MOD_REL} KERNEL_SRC=${ROOT_DIR}/${KERNEL_DIR}  \
                         O=${OUT_DIR} "${TOOL_ARGS[@]}" ${MODULE_STRIP_FLAG}    \
                         INSTALL_MOD_PATH=${MODULES_STAGING_DIR}                \
                         ${MAKE_ARGS} modules_install
      set +x
      
      # 更新外部模块时间戳
      touch "${EXT_MOD_TIMESTAMP}"
    fi
  done
fi

# 其余部分保持不变...（EXTRA_CMDS, 文件复制, overlays等）

if [ -n "${EXTRA_CMDS}" ]; then
  echo "========================================================"
  echo " Running extra build command(s):"
  set -x
  eval ${EXTRA_CMDS}
  set +x
fi

# Overlays处理（保持不变）
OVERLAYS_OUT=""
for ODM_DIR in ${ODM_DIRS}; do
  OVERLAY_DIR=${ROOT_DIR}/device/${ODM_DIR}/overlays
  if [ -d ${OVERLAY_DIR} ]; then
    OVERLAY_OUT_DIR=${OUT_DIR}/overlays/${ODM_DIR}
    mkdir -p ${OVERLAY_OUT_DIR}
    make -C ${OVERLAY_DIR} DTC=${OUT_DIR}/scripts/dtc/dtc                     \
                           OUT_DIR=${OVERLAY_OUT_DIR} ${MAKE_ARGS}
    OVERLAYS=$(find ${OVERLAY_OUT_DIR} -name "*.dtbo")
    OVERLAYS_OUT="$OVERLAYS_OUT $OVERLAYS"
  fi
done

# 文件复制 - 增量优化
echo "========================================================"
echo " Copying files"
for FILE in $(cd ${OUT_DIR} && ls -1 ${FILES} 2>/dev/null || true); do
  if [ -f ${OUT_DIR}/${FILE} ]; then
    if check_file_changed "${OUT_DIR}/${FILE}" "${DIST_DIR}/${FILE}"; then
      echo "  $FILE (updated)"
      cp -p ${OUT_DIR}/${FILE} ${DIST_DIR}/
    else
      log_incremental "  $FILE (unchanged)"
    fi
  else
    echo "  $FILE is not a file, skipping"
  fi
done

for FILE in ${OVERLAYS_OUT}; do
  OVERLAY_DIST_DIR=${DIST_DIR}/$(dirname ${FILE#${OUT_DIR}/overlays/})
  echo "  ${FILE#${OUT_DIR}/}"
  mkdir -p ${OVERLAY_DIST_DIR}
  cp ${FILE} ${OVERLAY_DIST_DIR}/
done

if [ -n "${DIST_CMDS}" ]; then
  echo "========================================================"
  echo " Running extra dist command(s):"
  set -x
  eval ${DIST_CMDS}
  set +x
fi

# 模块处理（保持原有逻辑）
MODULES=$(find ${MODULES_STAGING_DIR} -type f -name "*.ko" 2>/dev/null || true)
if [ -n "${MODULES}" ]; then
  if [ -n "${IN_KERNEL_MODULES}" -o -n "${EXT_MODULES}" ]; then
    echo "========================================================"
    echo " Copying modules files"
    for FILE in ${MODULES}; do
      MODULE_NAME=$(basename ${FILE})
      if check_file_changed "${FILE}" "${DIST_DIR}/${MODULE_NAME}"; then
        echo "  ${FILE#${MODULES_STAGING_DIR}/} (updated)"
        cp -p ${FILE} ${DIST_DIR}
      else
        log_incremental "  ${FILE#${MODULES_STAGING_DIR}/} (unchanged)"
      fi
    done
  fi
  
  # BUILD_INITRAMFS处理（保持原有逻辑但添加增量检查）
  if [ -n "${BUILD_INITRAMFS}" ]; then
    INITRAMFS_TIMESTAMP="${INCREMENTAL_STATE_DIR}/initramfs_timestamp"
    NEED_INITRAMFS_BUILD=1
    
    if [ "${INCREMENTAL_BUILD}" -eq 1 ] && [ -f "${INITRAMFS_TIMESTAMP}" ] && [ -f "${DIST_DIR}/initramfs.img" ]; then
      # 检查是否有模块比initramfs新
      NEWER_MODULES_COUNT=0
      for MODULE in ${MODULES}; do
        if [ "${MODULE}" -nt "${INITRAMFS_TIMESTAMP}" ]; then
          NEWER_MODULES_COUNT=$((NEWER_MODULES_COUNT + 1))
        fi
      done
      
      if [ "${NEWER_MODULES_COUNT}" -eq 0 ]; then
        log_incremental "No modules changed, skipping initramfs rebuild"
        NEED_INITRAMFS_BUILD=0
      else
        log_incremental "Found ${NEWER_MODULES_COUNT} newer modules, rebuilding initramfs"
      fi
    fi
    
    if [ "${NEED_INITRAMFS_BUILD}" -eq 1 ]; then
      echo "========================================================"
      echo " Creating initramfs"
      set -x
      rm -rf ${INITRAMFS_STAGING_DIR}
      
      # 原有initramfs构建逻辑保持不变
      mkdir -p ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/kernel/
      cp -r ${MODULES_STAGING_DIR}/lib/modules/*/kernel/* ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/kernel/
      cp ${MODULES_STAGING_DIR}/lib/modules/*/modules.order ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/modules.order
      cp ${MODULES_STAGING_DIR}/lib/modules/*/modules.builtin ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/modules.builtin

      if [ -n "${EXT_MODULES}" ]; then
        mkdir -p ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/extra/
        cp -r ${MODULES_STAGING_DIR}/lib/modules/*/extra/* ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/extra/
        (cd ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/ && \
            find extra -type f -name "*.ko" | sort >> modules.order)
      fi

      if [ -n "${DO_NOT_STRIP_MODULES}" ]; then
        find ${INITRAMFS_STAGING_DIR} -type f -name "*.ko" \
          -exec ${OBJCOPY:${CROSS_COMPILE}strip} --strip-debug {} \;
      fi

      (
        set +x
        set +e
        cd ${INITRAMFS_STAGING_DIR}
        DEPMOD_OUTPUT=$(depmod -e -F ${DIST_DIR}/System.map -b . 0.0 2>&1)
        if [[ "$?" -ne 0 ]]; then
          echo "$DEPMOD_OUTPUT"
          exit 1;
        fi
        echo "$DEPMOD_OUTPUT"
        if [[ -n $(echo $DEPMOD_OUTPUT | grep "needs unknown symbol") ]]; then
          echo "ERROR: out-of-tree kernel module(s) need unknown symbol(s)"
          exit 1
        fi
        set -e
        set -x
      )
      
      cp ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/modules.order ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/modules.load
      cp ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/modules.order ${DIST_DIR}/modules.load
      echo "${MODULES_OPTIONS}" > ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/modules.options
      mv ${INITRAMFS_STAGING_DIR}/lib/modules/0.0/* ${INITRAMFS_STAGING_DIR}/lib/modules/.
      rmdir ${INITRAMFS_STAGING_DIR}/lib/modules/0.0

      if [ "${BOOT_IMAGE_HEADER_VERSION}" -eq "3" ]; then
        mkdir -p ${INITRAMFS_STAGING_DIR}/first_stage_ramdisk
        if [ -f "${VENDOR_FSTAB}" ]; then
          cp ${VENDOR_FSTAB} ${INITRAMFS_STAGING_DIR}/first_stage_ramdisk/.
        fi
      fi

      (cd ${INITRAMFS_STAGING_DIR} && find . | cpio -H newc -o > ${MODULES_STAGING_DIR}/initramfs.cpio)
      gzip -fc ${MODULES_STAGING_DIR}/initramfs.cpio > ${MODULES_STAGING_DIR}/initramfs.cpio.gz
      mv ${MODULES_STAGING_DIR}/initramfs.cpio.gz ${DIST_DIR}/initramfs.img
      set +x
      
      # 更新initramfs时间戳
      touch "${INITRAMFS_TIMESTAMP}"
    else
      log_incremental "Skipped initramfs rebuild (unchanged)"
    fi
  fi
fi

# 其余部分保持原样（UNSTRIPPED_MODULES, headers, boot image等）

if [ -n "${UNSTRIPPED_MODULES}" ]; then
  echo "========================================================"
  echo " Copying unstripped module files for debugging purposes (not loaded on device)"
  mkdir -p ${UNSTRIPPED_DIR}
  for MODULE in ${UNSTRIPPED_MODULES}; do
    find ${MODULES_PRIVATE_DIR} -name ${MODULE} -exec cp {} ${UNSTRIPPED_DIR} \;
  done
fi

# UAPI headers处理 - 增量优化
if [ -z "${SKIP_CP_KERNEL_HDR}" ]; then
  HEADERS_TIMESTAMP="${INCREMENTAL_STATE_DIR}/headers_timestamp"
  NEED_HEADERS_INSTALL=1
  
  if [ "${INCREMENTAL_BUILD}" -eq 1 ] && [ -f "${HEADERS_TIMESTAMP}" ] && [ -f "${KERNEL_UAPI_HEADERS_TAR}" ]; then
    # 检查头文件是否有变化
    NEWER_HEADERS=$(find ${ROOT_DIR}/${KERNEL_DIR}/include -name "*.h" -newer "${HEADERS_TIMESTAMP}" 2>/dev/null | wc -l)
    if [ "${NEWER_HEADERS}" -eq 0 ]; then
      log_incremental "No header files changed, skipping headers install"
      NEED_HEADERS_INSTALL=0
    fi
  fi
  
  if [ "${NEED_HEADERS_INSTALL}" -eq 1 ]; then
    echo "========================================================"
    echo " Installing UAPI kernel headers:"
    mkdir -p "${KERNEL_UAPI_HEADERS_DIR}/usr"
    make -C ${OUT_DIR} O=${OUT_DIR} "${TOOL_ARGS[@]}"                           \
            INSTALL_HDR_PATH="${KERNEL_UAPI_HEADERS_DIR}/usr" ${MAKE_ARGS}      \
            headers_install
    find ${KERNEL_UAPI_HEADERS_DIR} \( -name ..install.cmd -o -name .install \) -exec rm '{}' +
    KERNEL_UAPI_HEADERS_TAR=${DIST_DIR}/kernel-uapi-headers.tar.gz
    echo " Copying kernel UAPI headers to ${KERNEL_UAPI_HEADERS_TAR}"
    tar -czf ${KERNEL_UAPI_HEADERS_TAR} --directory=${KERNEL_UAPI_HEADERS_DIR} usr/
    
    touch "${HEADERS_TIMESTAMP}"
  else
    log_incremental "Skipped UAPI headers install (unchanged)"
  fi
fi

# Kernel headers处理 - 增量优化
if [ -z "${SKIP_CP_KERNEL_HDR}" ] ; then
  KERNEL_HEADERS_TIMESTAMP="${INCREMENTAL_STATE_DIR}/kernel_headers_timestamp"
  KERNEL_HEADERS_TAR=${DIST_DIR}/kernel-headers.tar.gz
  NEED_KERNEL_HEADERS=1
  
  if [ "${INCREMENTAL_BUILD}" -eq 1 ] && [ -f "${KERNEL_HEADERS_TIMESTAMP}" ] && [ -f "${KERNEL_HEADERS_TAR}" ]; then
    NEWER_KERNEL_HEADERS=$(find ${ROOT_DIR}/${KERNEL_DIR} -name "*.h" -newer "${KERNEL_HEADERS_TIMESTAMP}" 2>/dev/null | wc -l)
    if [ "${NEWER_KERNEL_HEADERS}" -eq 0 ]; then
      log_incremental "No kernel header files changed, skipping kernel headers"
      NEED_KERNEL_HEADERS=0
    fi
  fi
  
  if [ "${NEED_KERNEL_HEADERS}" -eq 1 ]; then
    echo "========================================================"
    echo " Copying kernel headers to ${KERNEL_HEADERS_TAR}"
    pushd $ROOT_DIR/$KERNEL_DIR
      find arch include $OUT_DIR -name *.h -print0               \
              | tar -czf $KERNEL_HEADERS_TAR                     \
                --absolute-names                                 \
                --dereference                                    \
                --transform "s,.*$OUT_DIR,,"                     \
                --transform "s,^,kernel-headers/,"               \
                --null -T -
    popd
    
    touch "${KERNEL_HEADERS_TIMESTAMP}"
  else
    log_incremental "Skipped kernel headers (unchanged)"
  fi
fi

echo "========================================================"
echo " Files copied to ${DIST_DIR}"

# Boot image构建（保持原有逻辑）
if [ ! -z "${BUILD_BOOT_IMG}" ] ; then
    # 原有的boot image构建逻辑保持不变
    # （这里保持原脚本的boot image构建部分）
    
	MKBOOTIMG_ARGS=()
	if [ -n  "${BASE_ADDRESS}" ]; then
		MKBOOTIMG_ARGS+=("--base" "${BASE_ADDRESS}")
	fi
	if [ -n  "${PAGE_SIZE}" ]; then
		MKBOOTIMG_ARGS+=("--pagesize" "${PAGE_SIZE}")
	fi
	if [ -n "${KERNEL_CMDLINE}" ]; then
		MKBOOTIMG_ARGS+=("--cmdline" "${KERNEL_CMDLINE}")
	fi

	DTB_FILE_LIST=$(find ${DIST_DIR} -name "*.dtb")
	if [ -z "${DTB_FILE_LIST}" ]; then
		if [ -z "${SKIP_VENDOR_BOOT}" ]; then
			echo "No *.dtb files found in ${DIST_DIR}"
			exit 1
		fi
	else
		cat $DTB_FILE_LIST > ${DIST_DIR}/dtb.img
		MKBOOTIMG_ARGS+=("--dtb" "${DIST_DIR}/dtb.img")
	fi

	set -x
	MKBOOTIMG_RAMDISKS=()
	for ramdisk in ${VENDOR_RAMDISK_BINARY} \
		       "${MODULES_STAGING_DIR}/initramfs.cpio"; do
		if [ -f "${DIST_DIR}/${ramdisk}" ]; then
			MKBOOTIMG_RAMDISKS+=("${DIST_DIR}/${ramdisk}")
		else
			if [ -f "${ramdisk}" ]; then
				MKBOOTIMG_RAMDISKS+=("${ramdisk}")
			fi
		fi
	done
	for ((i=0; i<"${#MKBOOTIMG_RAMDISKS[@]}"; i++)); do
		CPIO_NAME="$(mktemp -t build.sh.ramdisk.XXXXXXXX)"
		if gzip -cd "${MKBOOTIMG_RAMDISKS[$i]}" 2>/dev/null > ${CPIO_NAME}; then
			MKBOOTIMG_RAMDISKS[$i]=${CPIO_NAME}
		else
			rm -f ${CPIO_NAME}
		fi
	done
	if [ "${#MKBOOTIMG_RAMDISKS[@]}" -gt 0 ]; then
		cat ${MKBOOTIMG_RAMDISKS[*]} | gzip - > ${DIST_DIR}/ramdisk.gz
	elif [ -z "${SKIP_VENDOR_BOOT}" ]; then
		echo "No ramdisk found. Please provide a GKI and/or a vendor ramdisk."
		exit 1
	fi
	set -x

	if [ -z "${MKBOOTIMG_PATH}" ]; then
		MKBOOTIMG_PATH="tools/mkbootimg/mkbootimg.py"
	fi
	if [ ! -f "$MKBOOTIMG_PATH" ]; then
		echo "mkbootimg.py script not found. MKBOOTIMG_PATH = $MKBOOTIMG_PATH"
		exit 1
	fi

	if [ ! -f "${DIST_DIR}/$KERNEL_BINARY" ]; then
		echo "kernel binary(KERNEL_BINARY = $KERNEL_BINARY) not present in ${DIST_DIR}"
		exit 1
	fi

	if [ "${BOOT_IMAGE_HEADER_VERSION}" -eq "3" ]; then
		if [ -f "${GKI_RAMDISK_PREBUILT_BINARY}" ]; then
			MKBOOTIMG_ARGS+=("--ramdisk" "${GKI_RAMDISK_PREBUILT_BINARY}")
		fi

		if [ -z "${SKIP_VENDOR_BOOT}" ]; then
			MKBOOTIMG_ARGS+=("--vendor_boot" "${DIST_DIR}/vendor_boot.img" \
				"--vendor_ramdisk" "${DIST_DIR}/ramdisk.gz")
			if [ -n "${KERNEL_VENDOR_CMDLINE}" ]; then
				MKBOOTIMG_ARGS+=("--vendor_cmdline" "${KERNEL_VENDOR_CMDLINE}")
			fi
		fi
	else
		MKBOOTIMG_ARGS+=("--ramdisk" "${DIST_DIR}/ramdisk.gz")
	fi

	set -x
	python "$MKBOOTIMG_PATH" --kernel "${DIST_DIR}/${KERNEL_BINARY}" \
		--header_version "${BOOT_IMAGE_HEADER_VERSION}" \
		"${MKBOOTIMG_ARGS[@]}" -o "${DIST_DIR}/boot.img"
	set +x

	echo "boot image created at ${DIST_DIR}/boot.img"
fi

# trace_printk检查（保持不变）
if readelf -a ${DIST_DIR}/vmlinux 2>&1 | grep -q trace_printk_fmt; then
  echo "========================================================"
  echo "WARN: Found trace_printk usage in vmlinux."
  echo ""
  echo "trace_printk will cause trace_printk_init_buffers executed in kernel"
  echo "start, which will increase memory and lead warning shown during boot."
  echo "We should not carry trace_printk in production kernel."
  echo ""
  if [ ! -z "${STOP_SHIP_TRACEPRINTK}" ]; then
    echo "ERROR: stop ship on trace_printk usage." 1>&2
    exit 1
  fi
fi

# 增量编译总结
if [ "${INCREMENTAL_BUILD}" -eq 1 ]; then
    echo "========================================================"
    echo "Incremental build completed!"
    echo "State files saved in: ${INCREMENTAL_STATE_DIR}"
    echo ""
    echo "To force a full rebuild, use: FORCE_CLEAN=1 ./build_incremental.sh"
    echo "To disable incremental build, use: INCREMENTAL_BUILD=0 ./build_incremental.sh"
    echo "For verbose incremental output, use: VERBOSE_INCREMENTAL=1 ./build_incremental.sh"
fi
EOF
)
