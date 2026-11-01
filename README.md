# OnePlus 15 Infinity-X BakaSU SUSFS BBG

GKI kernel for the OnePlus 15 (infiniti) on Infinity-X 4.1 (Android 17). Built by `build.sh`, either locally or through the "Build kernel" workflow.

## Sources

- [ACK kernel manifest](https://android.googlesource.com/kernel/manifest), branch `common-android16-6.12`: Kleaf and toolchains
- [LDLDL-Android/android_kernel_common](https://github.com/LDLDL-Android/android_kernel_common), branch `android16-6.12-infiniti`, with its commits rebased onto ACK [`6b467619429a`](https://android.googlesource.com/kernel/common/+/6b467619429a3e09812e862ad19b65a9910397ed) (the commit the ROM's kernel is built from)
- [LDLDL-Android/BakaSU](https://github.com/LDLDL-Android/BakaSU), branch `custom` (fork of [Baka-SU/BakaSU](https://github.com/Baka-SU/BakaSU))
- [simonpunk/susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu), `gki-android16-6.12` (v2.3.0, ported by LDLDL)
- [vc-teahouse/Baseband-guard](https://github.com/vc-teahouse/Baseband-guard), branch `main`
- [WildKernels/kernel_patches](https://github.com/WildKernels/kernel_patches) at `c78291aeb0dc`
- [osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3) at `41f04bdb4ee3`

## Included patches

- LDLDL: `ANDROID: kernelsu: Integrate BakaSU`, `ANDROID: susfs: Add SUSFS v2.3.0 support`, `ANDROID: arm64: Add infiniti config fragment` (KernelSU, SUSFS, BBR as default, WireGuard)
- Baseband-guard LSM, with `abl` and `efisp` added to the allowlist
- WildKernels optimisation patches: `optimized_mem_operations`, `file_struct_8bytes_align`, `reduce_cache_pressure`, `mem_opt_prefetch`, `optimise_memcmp`, `minimise_wakeup_time`, `int_sqrt`, `reduce_gc_thread_sleep_time`, `add_timeout_wakelocks_globally`, `f2fs_reduce_congestion`, `reduce_freeze_timeout`, `clear_page_16bytes_align`, `add_limitation_scaling_min_freq`, `re_write_limitation_scaling_min_freq`, `adjust_cpu_scan_order`, `avoid_extra_s2idle_wake_attempts`, `disable_cache_hot_buddy`, `f2fs_enlarge_min_fsync_blocks`, `increase_ext4_default_commit_age`, `increase_sk_mem_packets`, `reduce_pci_pme_wakeups`, `silence_irq_cpu_logspam`, `silence_system_logspam`, `use_unlikely_wrap_cpufreq`
- WildKernels NTSync: `ntsync_compat_android16-6.12`, `ntsync_base`
- WildKernels `unicode_bypass_fix_6.1+`
- WildKernels Droidspaces (optional, on by default): `fix_sysvipc_kabi_a16-6.12`, plus `put_ipc_ns` / `init_ipc_ns` exports. With this on, the ROM's `rust_binder.ko` does not load; it is unused unless `binder.impl=rust` is set.
- Config only: tmpfs xattr/POSIX ACL, CAKE/PIE/FQ_PIE/FQ/FQ_CODEL qdiscs, TTL/HL targets, IP set and IPv6 NAT
- Build: module export protection removed from `common/BUILD.bazel` and KMI trimming off (`--notrim`), so the ROM's system_dlkm modules still load
