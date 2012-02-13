# Edit the path to oyour CM repo and the path you want your modules installed to.
#
# Let's install our modules to our modules directory
ARCH=arm CROSS_COMPILE=~/Android/CM7.1/prebuilt/linux-x86/toolchain/arm-2010q1/bin/arm-none-linux-gnueabi- make zImage -j4
#
echo "modules are now installed to your modules directory!"
