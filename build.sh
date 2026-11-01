#!/usr/bin/env bash
# GKI kernel for OnePlus 15 (infiniti) running Infinity-X 4.1 (Android 17):
#   ACK android16-6.12 at the exact commit the ROM's kernel was built from
#   + LDLDL's BakaSU / SUSFS v2.3.0 / infiniti.fragment commits
#   + Baseband-guard LSM with abl/efisp left writable (GBL/efisp boot chain)
#   + WildKernels extras (optimisation patches, NTSync, unicode fix, Droidspaces, qdiscs,
#     TTL, IP set / IPv6 NAT, tmpfs xattr/ACL).
# Output: out/Image and out/<name>-AnyKernel3.zip (flash in recovery).
# Used as-is by .github/workflows/build.yml; runs the same locally.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$ROOT/work}
OUT=${OUT:-$ROOT/out}
KERNEL_REF=${KERNEL_REF:-android16-6.12-infiniti} # github.com/LDLDL-Android/android_kernel_common
# The ROM's kernel is ACK 6b467619429a. Building on exactly that keeps every symbol CRC
# (Rust ones too) identical to what the ROM's modules expect. Empty = use KERNEL_REF as is.
KERNEL_BASE=${KERNEL_BASE-6b467619429a3e09812e862ad19b65a9910397ed}
# LDLDL's own commits on KERNEL_REF, oldest first: BakaSU hookup, SUSFS v2.3.0, infiniti.fragment.
KERNEL_PICKS=${KERNEL_PICKS:-a5cc8e8e8f5f f0dcc8d6d11a 2217b5807c39}
BAKASU_REF=${BAKASU_REF:-custom}                  # github.com/LDLDL-Android/BakaSU
BBG_REF=${BBG_REF:-main}                          # github.com/vc-teahouse/Baseband-guard (branch or tag)
PATCHES_REF=${PATCHES_REF:-c78291aeb0dca025f21e6b197e0aa4fde42e065d} # github.com/WildKernels/kernel_patches
# WildKernels fork: same AK3 core, but arm64 tools (SM8850 has no 32-bit support).
AK3_REF=${AK3_REF:-0b46673ae91aee8d60bd6ee257b4d56d3f6a0114} # github.com/WildKernels/AnyKernel3
# Droidspaces (SYSVIPC, POSIX_MQUEUE, USER_NS, PID_NS...). C symbol CRCs stay identical,
# but the Rust ones change, so the ROM's system_dlkm rust_binder.ko will not load. Harmless
# unless binder.impl=rust is on the cmdline (C binder is used otherwise). false = leave it out.
DROIDSPACES=${DROIDSPACES:-true}
JOBS=${JOBS:-$(nproc)}

mkdir -p "$WORK" "$OUT"
cd "$WORK"

echo "==> Sync ACK android16-6.12 tree, common/ = LDLDL@$KERNEL_REF, KernelSU/ = BakaSU@$BAKASU_REF"
[ -d .repo ] || repo init -u https://android.googlesource.com/kernel/manifest -b common-android16-6.12 --depth=1
mkdir -p .repo/local_manifests
cat > .repo/local_manifests/bakasu.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="github" fetch="https://github.com/" />
  <remove-project name="kernel/common" />
  <project path="common" name="LDLDL-Android/android_kernel_common" remote="github" revision="$KERNEL_REF" clone-depth="64" />
  <project path="KernelSU" name="LDLDL-Android/BakaSU" remote="github" revision="$BAKASU_REF" />
</manifest>
EOF
# Undo the edits a previous run made, so sync and the patches below start clean.
for d in common KernelSU; do
  if [ -e "$d/.git" ]; then git -C "$d" reset -q --hard; git -C "$d" clean -qfdx; fi
done
rm -rf Baseband-guard
repo sync -c -j"$JOBS" --no-tags --force-sync --fail-fast

if [ -n "$KERNEL_BASE" ]; then
  echo "==> Rebase LDLDL commits onto ROM kernel base $KERNEL_BASE"
  git -C common checkout -q --detach "$KERNEL_BASE"
  # shellcheck disable=SC2086 # KERNEL_PICKS is a list
  git -C common -c user.name=build -c user.email=build@localhost cherry-pick $KERNEL_PICKS
fi

echo "==> Baseband-guard@$BBG_REF"
curl -fsSL "https://raw.githubusercontent.com/vc-teahouse/Baseband-guard/$BBG_REF/setup.sh" | bash -s "$BBG_REF"
rm -rf Baseband-guard/.git # it is symlinked into common/, and a fresh .git defeats the Bazel cache
sed -i 's/^\(\s*\)"dtbo",$/\1"dtbo", "abl", "efisp",/' Baseband-guard/baseband_guard.h
grep -q '"abl", "efisp"' Baseband-guard/baseband_guard.h || { echo "BBG allowlist patch did not apply" >&2; exit 1; }
sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/selinux/selinux,baseband_guard/ } }' common/security/Kconfig
grep -q 'selinux,baseband_guard' common/security/Kconfig || { echo "LSM list patch did not apply" >&2; exit 1; }

echo "==> WildKernels extras (kernel_patches@$PATCHES_REF)"
# Same patch set WildKernels' OP15 config applies. Skipped: HMBIRD (SM8750/MT6991 only),
# LTO (breaks GENDWARFKSYMS CRCs and Rust), BBRv3 (off for OP15 there too), force_tcp_nodelay
# (only used without BBR), oplus module blacklist / midas ghost task (modules absent in this ROM).
rm -rf kernel_patches
git init -q kernel_patches
git -C kernel_patches fetch -q --depth=1 https://github.com/WildKernels/kernel_patches "$PATCHES_REF"
git -C kernel_patches checkout -q FETCH_HEAD
P=$WORK/kernel_patches/common
(
  cd common
  for p in optimized_mem_operations file_struct_8bytes_align reduce_cache_pressure mem_opt_prefetch \
           optimise_memcmp minimise_wakeup_time int_sqrt reduce_gc_thread_sleep_time \
           add_timeout_wakelocks_globally f2fs_reduce_congestion reduce_freeze_timeout; do
    patch -p1 --forward < "$P/$p.patch"
  done
  sed 's/SYM_FUNC_START_PI(clear_page)/SYM_FUNC_START_PI(__pi_clear_page)/' "$P/clear_page_16bytes_align.patch" \
    | patch -p1 -F3 --forward
  for p in add_limitation_scaling_min_freq re_write_limitation_scaling_min_freq adjust_cpu_scan_order \
           avoid_extra_s2idle_wake_attempts disable_cache_hot_buddy f2fs_enlarge_min_fsync_blocks \
           increase_ext4_default_commit_age increase_sk_mem_packets reduce_pci_pme_wakeups \
           silence_irq_cpu_logspam silence_system_logspam use_unlikely_wrap_cpufreq; do
    patch -p1 --forward < "$P/$p.patch"
  done
  # NTSync: 6.12 ships a partial driver, replaced by the full one.
  rm -f include/uapi/linux/ntsync.h drivers/misc/ntsync.c
  patch -p1 --forward < "$P/ntsync/ntsync_compat_android16-6.12.patch"
  patch -p1 --forward < "$P/ntsync/ntsync_base.patch"
  patch -p1 --forward < "$P/unicode_bypass_fix_6.1+.patch"
  if [ "$DROIDSPACES" = true ]; then
    # SYSVIPC / POSIX_MQUEUE without changing the C KMI layout, plus the IPC namespace
    # exports Rust binder needs once SYSVIPC is on.
    patch -p1 --forward < "$P/droidspaces/fix_sysvipc_kabi_a16-6.12.patch"
    grep -q 'EXPORT_SYMBOL.*put_ipc_ns' ipc/namespace.c || printf '\nEXPORT_SYMBOL_GPL(put_ipc_ns);\n' >> ipc/namespace.c
    grep -q 'EXPORT_SYMBOL.*init_ipc_ns' ipc/msgutil.c || printf '\nEXPORT_SYMBOL_GPL(init_ipc_ns);\n' >> ipc/msgutil.c
  fi
)

echo "==> Config"
# infiniti.fragment (LDLDL): KSU, KSU_SUSFS, BBR default, WireGuard.
cat common/arch/arm64/configs/infiniti.fragment - > common/arch/arm64/configs/bakasu.fragment <<'EOF'

CONFIG_BBG=y
CONFIG_NTSYNC=y
CONFIG_TMPFS_XATTR=y
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_NET_SCH_FQ=y
CONFIG_NET_SCH_FQ_CODEL=y
CONFIG_NET_SCH_CAKE=y
CONFIG_NET_SCH_PIE=y
CONFIG_NET_SCH_FQ_PIE=y
CONFIG_IP_NF_TARGET_TTL=y
CONFIG_IP6_NF_TARGET_HL=y
CONFIG_IP6_NF_MATCH_HL=y
CONFIG_IP_SET=y
CONFIG_IP_SET_MAX=65534
CONFIG_IP_SET_BITMAP_IP=y
CONFIG_IP_SET_BITMAP_IPMAC=y
CONFIG_IP_SET_BITMAP_PORT=y
CONFIG_IP_SET_HASH_IP=y
CONFIG_IP_SET_HASH_IPMARK=y
CONFIG_IP_SET_HASH_IPPORT=y
CONFIG_IP_SET_HASH_IPPORTIP=y
CONFIG_IP_SET_HASH_IPPORTNET=y
CONFIG_IP_SET_HASH_IPMAC=y
CONFIG_IP_SET_HASH_MAC=y
CONFIG_IP_SET_HASH_NETPORTNET=y
CONFIG_IP_SET_HASH_NET=y
CONFIG_IP_SET_HASH_NETNET=y
CONFIG_IP_SET_HASH_NETPORT=y
CONFIG_IP_SET_HASH_NETIFACE=y
CONFIG_IP_SET_LIST_SET=y
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y
CONFIG_NETFILTER_XT_SET=y
CONFIG_IP6_NF_NAT=y
CONFIG_IP6_NF_TARGET_MASQUERADE=y
EOF
if [ "$DROIDSPACES" = true ]; then
  cat >> common/arch/arm64/configs/bakasu.fragment <<'EOF'
CONFIG_SYSVIPC=y
CONFIG_DEVTMPFS=y
CONFIG_PID_NS=y
CONFIG_POSIX_MQUEUE=y
CONFIG_IP_NF_TARGET_REJECT=y
CONFIG_IP6_NF_TARGET_REJECT=y
CONFIG_NETFILTER_XT_TARGET_LOG=y
CONFIG_NETFILTER_XT_MATCH_RECENT=y
CONFIG_USER_NS=y
CONFIG_MACVLAN=y
EOF
fi
echo 'exports_files(["arch/arm64/configs/bakasu.fragment"])' >> common/BUILD.bazel
# The ROM's system_dlkm modules are signed with the ROM build's throwaway key, so this
# kernel sees them as unsigned. Unsigned modules must not export "protected" symbols,
# and (with KMI trimming) may only import KMI-listed symbols. Drop both rules, the same
# way untrimmed make builds (WildKernels) behave.
sed -i '/protected_module_names_list = /d' common/BUILD.bazel

echo "==> Build"
# No --lto: android16-6.12 GKI is LTO-free (GENDWARFKSYMS, and so Rust binder, need !LTO),
# and symbol CRCs must be generated the same way as in the ROM's kernel.
rm -rf dist
tools/bazel run \
  --notrim --nokmi_symbol_list_strict_mode \
  --defconfig_fragment=//common:arch/arm64/configs/bakasu.fragment \
  //common:kernel_aarch64_dist -- --destdir="$WORK/dist"

echo "==> Package"
KVER=$(grep -a -m1 -oP 'Linux version \K\S+' dist/Image)
NAME="OP15-InfinityX-BakaSU-SUSFS-BBG-$KVER"
rm -rf ak3
git init -q ak3
git -C ak3 fetch -q --depth=1 https://github.com/WildKernels/AnyKernel3 "$AK3_REF"
git -C ak3 checkout -q FETCH_HEAD
rm -rf ak3/.git ak3/.github ak3/README.md ak3/modules ak3/patch ak3/ramdisk ak3/banner
cat > ak3/anykernel.sh <<EOF
### AnyKernel3 Ramdisk Mod Script
properties() { '
kernel.string=$NAME
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=infiniti
device.name2=OP60FFL1
'; }

block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

. tools/ak3-core.sh

# GKI boot v4: no ramdisk in boot, only the kernel is swapped.
split_boot
flash_boot
EOF
cp dist/Image ak3/Image
rm -f "$OUT"/*-AnyKernel3.zip "$OUT/Image" "$OUT/SHA256SUMS"
(cd ak3 && zip -qr9 "$OUT/$NAME-AnyKernel3.zip" .)
cp dist/Image "$OUT/Image"
(cd "$OUT" && sha256sum -- * > SHA256SUMS)
echo "==> Done: $OUT"
ls -l "$OUT"
