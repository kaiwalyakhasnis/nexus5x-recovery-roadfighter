# Sourced by the qemu/*.sh scripts. Override any of these in the environment.
LINEAGE=${LINEAGE:-$HOME/Desktop/android/lineage}          # LineageOS 15.1 tree (lineage_bullhead)
WORK=${WORK:-$HOME/bullhead-qemu}                           # where setup.sh puts the QEMU kernel etc.
KERNEL_SRC=${KERNEL_SRC:-$LINEAGE/kernel/lge/bullhead}     # only read (git archive HEAD)
CROSS_COMPILE=${CROSS_COMPILE:-$LINEAGE/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-}
OUT=${OUT:-$LINEAGE/out/target/product/bullhead}
QEMU_MACHINE="virt,gic-version=2,virtualization=on"         # virtualization=on: see docs/04-qemu-setup.md
QMP_SOCK=${QMP_SOCK:-$WORK/qmp.sock}                         # QEMU control socket (unix paths max ~107 chars)
