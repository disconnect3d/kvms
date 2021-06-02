#!/bin/bash

#
# Tested on ubuntu 20.n. You need to have qemu-user-static and binfmt-support
# installed.
#

TOOLDIR=$BASE_DIR/buildtools
QEMU_USER=`which qemu-aarch64-static`
QEMU_PATCHFILE="$BASE_DIR/patches/0001-target-ranchu-add-support-for-android-ranchu-board.patch"

if [ "x$STATIC" = "x1" ]; then
echo "Static build"
SSTATIC="--enable-static"
QSTATIC="--disable-libudev --disable-xkbcommon --static"
else
echo "Full sysroot build"
SSTATIC=""
QSTATIC=""
fi

if [ "x$OPENGL" = "x1" ]; then
echo "OpenGL enabled"
OPENGL="--enable-opengl"
else
echo "OpenGL disabled"
OPENGL="--disable-opengl"
fi

if [ "x$SPICE" = "x1" ]; then
echo "Spice enabled"
SPICE="--enable-spice"
else
echo "Spice disabled"
SPICE="--disable-spice"
fi

if [ "x$SDL" = "x0" ]; then
echo "SDL disabled"
SDL="--disable-sdl --audio-drv-list="
else
echo "SDL enabled"
SDL="--enable-sdl --audio-drv-list=sdl"
fi

if [ "x$VIRGL" = "x0" ]; then
echo "VIRGL disabled"
VIRGL="--disable-virglrenderer"
else
echo "VIRGL enabled"
VIRGL="--enable-virglrenderer"
fi

set -e

#
# Note: cross-compilation is also possible, these can be passed through.
#

unset CC
unset LD
unset CXX
unset AR
unset CPP
unset CROSS_COMPILE
unset CFLAGS
unset LDFLAGS
unset ASFLAGS
unset INCLUDES
unset WARNINGS
unset DEFINES

export PATH=$TOOLDIR/bin:$TOOLDIR/usr/bin:/bin:/usr/bin
export CHROOTDIR=$BASE_DIR/oss/ubuntu

NJOBS=`nproc`
PKGLIST=`cat $BASE_DIR/scripts/package.list`

cleanup()
{
	sudo umount $BASE_DIR/oss/ubuntu/build/qemu || true
}
trap cleanup SIGHUP SIGINT SIGTERM EXIT

do_clean()
{
	sudo rm -rf $BASE_DIR/oss/ubuntu
	cd $BASE_DIR/oss/qemu; sudo git clean -xfd || true
}

do_patch()
{
	cd $BASE_DIR/oss/qemu
	OUT=$(git apply --check $QEMU_PATCHFILE 2>&1 | wc -l)
	if [ $OUT != "0" ]; then
		echo "Skipping qemu patch, already applied?"
	else
		echo "Patching qemu to support ranchu"
		git am $QEMU_PATCHFILE
	fi
}

do_sysroot()
{
	mkdir -p $BASE_DIR/oss/ubuntu/build
	cd $BASE_DIR/oss/ubuntu
	wget -c http://cdimage.debian.org/mirror/cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.1-base-arm64.tar.gz
	tar xf ubuntu-base-20.04.1-base-arm64.tar.gz
	echo "nameserver 8.8.8.8" > etc/resolv.conf
	cp $QEMU_USER usr/bin
	sudo chmod a+rwx tmp
	sudo mknod $CHROOTDIR/dev/urandom  c 1 9
	DEBIAN_FRONTEND=noninteractive sudo -E chroot $CHROOTDIR apt-get update
	DEBIAN_FRONTEND=noninteractive sudo -E chroot $CHROOTDIR apt-get -y install $PKGLIST
}

do_spice()
{
	cd $BASE_DIR/oss/ubuntu/build
	sudo rm -rf spice-0.14.3
	wget https://www.spice-space.org/download/releases/spice-server/spice-0.14.3.tar.bz2
	tar xf spice-0.14.3.tar.bz2
	sudo -E chroot $CHROOTDIR sh -c "cd /build/spice-0.14.3; ./configure --prefix=/usr $SSTATIC --disable-celt051 ; make -j$NJOBS ; make install"
}

do_qemu()
{
	mkdir -p $BASE_DIR/oss/ubuntu/build/qemu
	sudo mount --bind $BASE_DIR/oss/qemu $BASE_DIR/oss/ubuntu/build/qemu
	mkdir -p $BASE_DIR/oss/ubuntu/build/qemu/build
	cd $BASE_DIR/oss/ubuntu/build
	sed -i '/spice-server &&/i spice_libs="  -L/usr/lib/aarch64-linux-gnu -lgobject-2.0 -lgmodule-2.0 -lglib-2.0 $spice_libs -lopus -ljpeg -lm"' qemu/configure
	sudo -E chroot $CHROOTDIR sh -c "cd /build/qemu/build; ../configure --prefix=/usr --target-list=aarch64-softmmu --with-git-submodules=ignore --enable-kvm $SPICE $OPENGL $SDL $VIRGL $QSTATIC"
	sudo -E chroot $CHROOTDIR sh -c "cd /build/qemu/build; make -j$NJOBS; make install"
}

do_hybris()
{
	cd $BASE_DIR/oss/ubuntu/build
	rm -rf libhybris
	git clone https://github.com/libhybris/libhybris.git
	cd libhybris; patch -p1 < $BASE_DIR/scripts/hybris.patch
	tar xf $BASE_DIR/scripts/android-headers.tar.bz2 -C $BASE_DIR/oss/ubuntu/usr/local
	sudo -E chroot $CHROOTDIR sh -c "cd /build/libhybris/hybris; ./autogen.sh"
	sudo -E chroot $CHROOTDIR sh -c "cd /build/libhybris/hybris; ./configure --prefix=/usr --enable-arch=arm64 --enable-adreno-quirks --enable-mesa --enable-ubuntu-linker-overrides --enable-property-cache --with-android-headers=/usr/local/android/headers; make -j$NJOBS; make install"
}

do_clean
do_sysroot
do_patch
do_spice
do_qemu
[ -n "$HYBRIS" ] && do_hybris

echo "All ok!"
