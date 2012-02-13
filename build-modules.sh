# Edit the path to your CM repo.
#
# Let's build some modules
ARCH=arm CROSS_COMPILE=~/Android/CM7.1/prebuilt/linux-x86/toolchain/arm-2010q1/bin/arm-none-linux-gnueabi- make zImage -j4
