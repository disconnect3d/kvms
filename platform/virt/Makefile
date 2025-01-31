PROG := $(OBJDIR)/$(PLATFORM)/hyp
LIBNAME := lib$(PLATFORM).a
QEMU := qemu-system-aarch64

KERNEL := $(KERNEL_DIR)/arch/arm64/boot/Image
VMLINUX := $(KERNEL_DIR)/vmlinux
KERNEL_OPTS := root=/dev/vda1 console=ttyAMA0 mem=4G nokaslr loglevel=8 rw
WAYOUT := $(shell exec ip route get 1.1.1.1 | grep -oP 'src \K\S+')
PORT := 10022
DRIVE := -drive file=$(IMAGE),format=qcow2,if=sd,id=ubu-sd -device virtio-blk-device,drive=ubu-sd
USB := -device qemu-xhci -device usb-kbd -device usb-tablet
NETWORK := -device e1000,netdev=net0 -netdev user,id=net0,host=192.168.7.1,net=192.168.7.0/24,restrict=off,hostname=guest,hostfwd=tcp:$(WAYOUT):$(PORT)-192.168.7.2:22
COMP_IMG ?= $(OBJDIR)/$(PLATFORM)/hyp-loader
USE_COMP_IMG ?= 0
DTB := $(OBJDIR)/$(PLATFORM)/virt.dtb
DTC := dtc

SPICESOCK := /tmp/host
VDAGENT := -device virtio-serial-pci -device virtserialport,chardev=spicechannel0,name=spice.0 -chardev spicevmc,id=spicechannel0,name=vdagent
SPICEOPTS := unix=on,addr=$(SPICESOCK),disable-ticketing=on,image-compression=off,streaming-video=all,playback-compression=off,disable-agent-file-xfer=off

ifeq ($(DEBUGMMU),1)
QEMUDEBUGOPTS := guest_errors,unimp,mmu
else
QEMUDEBUGOPTS := guest_errors,unimp
endif
QEMUDEBUGLOG := -D $(BASE_DIR)/qemudebug.log

LINK := -T ld.out -Ttext=0xC0001000
LDFLAGS := $(LDFLAGS) $(LINK)

AS_SOURCES := reset.S
C_SOURCES := host_platform.c

ifeq ($(USE_COMP_IMG),1)
HYP_IMAGE := -device loader,file=$(COMP_IMG).bin,addr=0xC0080000,force-raw=true
else
HYP_IMAGE := -device loader,file=$(PROG).bin,addr=0xC0000000,force-raw=true
endif

QEMUOPTS := --accel tcg,thread=multi -d $(QEMUDEBUGOPTS) $(QEMUDEBUGLOG) $(DEBUGOPTS) \
	    -machine virt,virtualization=on,secure=off,gic-version=3 \
	    -cpu max,sve=off,lpa2=off -smp 4 -m 4G $(NETWORK) $(USB) $(BOOTIMG) \
	    -kernel $(KERNEL) -append '$(KERNEL_OPTS)' -dtb $(DTB) $(HYP_IMAGE)

ifeq ($(QEMUDEBUG),1)
QEMUCMD := gdb $(QEMU)-debug -ex "r $(QEMUOPTS) -serial stdio -display none"
else
QEMUCMD := $(QEMU) $(QEMUOPTS) -nographic
endif

ifeq ($(GRAPHICS),1)
QEMUCMD := $(QEMUCMD) -device virtio-gpu-gl-pci,id=gpu0 -display egl-headless -spice $(SPICEOPTS) $(VDAGENT)
endif

include $(BASE_DIR)/core/common.mk

all: $(PROG).bin

$(DTB):
	@$(DTC) -I dts -O dtb virt.dts -o $@ > /dev/null 2>&1

run: $(DTB)
	@echo "------------------------------------------------------------------------------------------"
ifeq ($(GRAPHICS),1)
	@echo "Graphics available at 'spice+unix://$(SPICESOCK)'"
endif
	@echo "Host ssh login is available via $(WAYOUT):$(PORT)"
	@echo "------------------------------------------------------------------------------------------"
	@rm -f $(SPICESOCK)
	@$(QEMUCMD)

gdb:
ifeq ($(USE_COMP_IMG),1)
	#
	# QEMU loader trampoline gets set directly to the hyp-loader entrypoint. If
	# you need to debug the loader, do:
	# -ex "add-symbol-file $(COMP_IMG) 0xC0081000"
	#
	@$(CROSS_COMPILE)gdb -ex "target remote localhost:1234" -ex "set confirm off"   \
		-ex "add-symbol-file $(PROG) 0xC0001000" \
		-ex "set {int}0x40000010 = 0xd2b80104" \
		$(VMLINUX)
else
	@$(CROSS_COMPILE)gdb -ex "target remote localhost:1234" -ex "set confirm off"	\
		-ex "add-symbol-file $(PROG) 0xC0001000" $(VMLINUX)
endif

FORCE:
	
