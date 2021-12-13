#!/bin/bash

#
# Tested on ubuntu 20.n. You need to have qemu-user-static and binfmt-support
# installed.
#

TOOLDIR=$BASE_DIR/buildtools
QEMU_USER=`which qemu-aarch64-static`

#
# Default: dynamic, opengl, spice, virgl, hybris
#

if [ -n "$STATIC" ]; then
echo "Static build"
SSTATIC="--enable-static"
QSTATIC="--disable-libudev --disable-xkbcommon --static"
SHARED_GLAPI="-Dshared-glapi=disabled -Dglx=disabled"
else
echo "Full sysroot build"
SSTATIC=""
QSTATIC=""
SHARED_GLAPI="-Dshared-glapi=enabled -Dglx=gallium-xlib"
fi

if [ -n "$OPENGL" ]; then
echo "OpenGL enabled"
OPENGL="--enable-opengl"
else
echo "OpenGL disabled"
OPENGL="--disable-opengl"
fi

if [ -n "$SPICE" ]; then
echo "Spice enabled"
SPICE="--enable-spice"
else
echo "Spice disabled"
SPICE="--disable-spice"
fi

if [ -n "$SDL" ]; then
echo "SDL enabled"
SDL="--enable-sdl --audio-drv-list=sdl"
else
echo "SDL disabled"
SDL="--disable-sdl --audio-drv-list="
fi

if [ -n "$VIRGL" ]; then
echo "VIRGL enabled"
VIRGL="--enable-virglrenderer"
else
echo "VIRGL disabled"
VIRGL="--disable-virglrenderer"
fi

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
REPO=`which repo`

set -e

cleanup()
{
	sudo umount $BASE_DIR/oss/ubuntu/build/qemu || true
	sudo umount $CHROOTDIR/proc || true
	sudo umount $CHROOTDIR/dev || true
}
trap cleanup SIGHUP SIGINT SIGTERM EXIT

do_clean()
{
	cleanup
	sudo rm -rf $BASE_DIR/oss/ubuntu
	cd $BASE_DIR/oss/qemu; sudo git clean -xfd || true
	sudo rm -rf $BASE_DIR/oss/emu
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
	if [ ! -d $BASE_DIR/oss/ubuntu/build ]; then
		mkdir -p $BASE_DIR/oss/ubuntu/build
		cd $BASE_DIR/oss/ubuntu
		wget -c http://cdimage.debian.org/mirror/cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.1-base-arm64.tar.gz
		tar xf ubuntu-base-20.04.1-base-arm64.tar.gz
		echo "nameserver 8.8.8.8" > etc/resolv.conf
		cp $QEMU_USER usr/bin
		sudo chmod a+rwx tmp
	fi
	sudo mount --bind /dev $CHROOTDIR/dev
	sudo mount -t proc none $CHROOTDIR/proc
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

do_mesa()
{
	cd $BASE_DIR/oss/ubuntu/build
	wget -c https://archive.mesa3d.org//mesa-20.2.6.tar.xz
	tar xf mesa-20.2.6.tar.xz
	cd mesa-20.2.6
	sudo -E chroot $CHROOTDIR sh -c "cd /build/mesa-20.2.6; meson build --prefix /usr/local $MESAGL -Dopengl=true -Dosmesa=gallium -Dgallium-drivers=swrast,freedreno $SHARED_GLAPI ; cd build; meson install"
}

do_qemu()
{
	mkdir -p $BASE_DIR/oss/ubuntu/build/qemu
	sudo mount --bind $BASE_DIR/oss/qemu $BASE_DIR/oss/ubuntu/build/qemu
	mkdir -p $BASE_DIR/oss/ubuntu/build/qemu/build
	cd $BASE_DIR/oss/ubuntu/build
	if [ -n "$STATIC" ]; then
		sed -i '/spice-server &&/i spice_libs=" -L/usr/lib/aarch64-linux-gnu -lgmodule-2.0 -lgobject-2.0 -lgio-2.0 -lglib-2.0 -lspice-server -lpixman-1 -lgmodule-2.0 -lgobject-2.0 -lgio-2.0 -lglib-2.0 -lpthread -lpcre -ljpeg -lm -lffi -lz -lssl -lcrypto -ldl -lopus -lm"' qemu/configure
		sudo -E chroot $CHROOTDIR sh -c "cd /build/qemu/build; ../configure --prefix=/usr --target-list=aarch64-softmmu --with-git-submodules=ignore --enable-kvm --audio-drv-list=oss $SPICE $OPENGL $SDL $VIRGL $QSTATIC"
	else
		sudo -E chroot $CHROOTDIR sh -c "cd /build/qemu/build; ../configure --prefix=/usr --target-list=aarch64-softmmu --with-git-submodules=ignore --enable-kvm --extra-cflags=\"-I/usr/local/include -L/usr/local/lib/aarch64-linux-gnu -lgbm\" $SPICE $OPENGL $SDL $VIRGL $QSTATIC"
	fi
	sudo -E chroot $CHROOTDIR sh -c "cd /build/qemu/build; make -j$NJOBS; make install"
}

do_hybris()
{
	cd $BASE_DIR/oss/ubuntu/build
	sudo rm -rf libhybris
	git clone https://github.com/libhybris/libhybris.git
	cd libhybris; patch -p1 < $BASE_DIR/scripts/hybris.patch
	tar xf $BASE_DIR/scripts/android-headers.tar.bz2 -C $BASE_DIR/oss/ubuntu/usr/local
	sudo -E chroot $CHROOTDIR sh -c "cd /build/libhybris/hybris; ./autogen.sh"
	sudo -E chroot $CHROOTDIR sh -c "cd /build/libhybris/hybris; ./configure --prefix=/usr --enable-arch=arm64 --enable-adreno-quirks --enable-mesa --enable-ubuntu-linker-overrides --enable-property-cache --with-android-headers=/usr/local/android/headers; make -j$NJOBS; make install"
}

do_android_emulator()
{
	if [ -z "$REPO"  ]; then
		curl https://storage.googleapis.com/git-repo-downloads/repo > $BASE_DIR/buildtools/usr/bin/repo
		chmod a+rwx $BASE_DIR/buildtools/usr/bin/repo
	fi
	if [ ! -d "$BASE_DIR/oss/emu/external/qemu" ]; then
		rm -rf $BASE_DIR/oss/emu
		mkdir $BASE_DIR/oss/emu
		cd $BASE_DIR/oss/emu
		repo init -u https://android.googlesource.com/platform/manifest -b emu-master-dev --depth=1
		repo sync -c --no-tags -j4
	fi
	cd $BASE_DIR/oss/emu
	cd $BASE_DIR/oss/emu/external/qemu
	[ ! -f /lib/ld-linux-aarch64.so.1 ] && sudo ln -s $CHROOTDIR/usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 /lib/ld-linux-aarch64.so.1
	export LD_LIBRARY_PATH=$CHROOTDIR/usr/lib/aarch64-linux-gnu/
	EMUCONFIG="--config release"
	[ -n "$DEBUG" ] && EMUCONFIG="--config debug"
	python android/build/python/cmake.py $EMUCONFIG --noqtwebengine --noshowprefixforinfo --target linux_aarch64
}

[ -n "$CLEAN" ] && do_clean
do_sysroot
do_spice
[ -z "$STATIC" ] && do_mesa
do_qemu
[ -n "$ANDROID_EMU" ] && do_android_emulator
[ -z "$STATIC" ] && do_hybris

echo "All ok!"