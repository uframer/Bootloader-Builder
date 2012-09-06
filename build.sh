#!/bin/bash -e
#
# Copyright (c) 2010-2012 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

unset STABLE
unset TESTING

DIR=$PWD
TEMPDIR=$(mktemp -d)

CCACHE=ccache

ARCH=$(uname -m)
SYST=$(uname -n)

STABLE="v2012.07"
#TESTING="v2012.07"

#LATEST_GIT="a005f19eff946454985785788c344f10616d571e"
LATEST_GIT="a6f0c4faa4c65a7b7048b12c9d180d7e1aad1721"

unset GIT_OPTS
unset GIT_NOEDIT
LC_ALL=C git help pull | grep -m 1 -e "--no-edit" &>/dev/null && GIT_NOEDIT=1

if [ "${GIT_NOEDIT}" ] ; then
	echo "Detected git 1.7.10 or later, this script will pull via [git pull --no-edit]"
	GIT_OPTS+="--no-edit"
fi

mkdir -p ${DIR}/git/
mkdir -p ${DIR}/dl/
mkdir -p ${DIR}/deploy/latest/

dl_old_bootloaders () {
	if [ -f ${DIR}/deploy/latest/bootloader ] ; then
		rm -f ${DIR}/deploy/latest/bootloader || true
	fi
	cd ${DIR}/deploy/latest/
	wget http://rcn-ee.net/deb/tools/latest/bootloader
	cd -
}

set_cross_compiler () {
	if [ ! "${CC}" ] ; then
		if [ "x${ARCH}" == "xarmv7l" ] ; then
			#using native gcc
			CC=
		else
			#using Cross Compiler
			CC=arm-linux-gnueabi-
		fi
	fi

	if [ -f ${DIR}/rcn-ee.host ] ; then
		source ${DIR}/host/rcn-ee-host.sh
	fi
}

armv5_embedded_toolchain () {
	armv5_ver="gcc-arm-none-eabi-4_6-2012q2"
	armv5_date="20120614"
	ARMV5_GCC_EMBEDDED="${armv5_ver}-${armv5_date}.tar.bz2"
	if [ ! -f ${DIR}/dl/${armv5_date} ] ; then
		echo "Installing gcc-arm-embedded toolchain"
		echo "-----------------------------"
		wget -c --directory-prefix=${DIR}/dl/ https://launchpad.net/gcc-arm-embedded/4.6/4.6-2012-q2-update/+download/${ARMV5_GCC_EMBEDDED}
		touch ${DIR}/dl/${armv5_date}
		if [ -d ${DIR}/dl/${armv5_ver} ] ; then
			rm -rf ${DIR}/dl/${armv5_ver} || true
		fi
		tar xjf ${DIR}/dl/${ARMV5_GCC_EMBEDDED} -C ${DIR}/dl/
	fi

	armv5_gcc="${DIR}/dl/${armv5_ver}/bin/arm-none-eabi-"
}

git_generic () {
	echo "Starting ${project} build for: ${BOARD}"
	echo "-----------------------------"

	RELEASE_VER="-r0"

	if [ ! -f ${DIR}/git/${project}/.git/config ] ; then
		git clone git://github.com/RobertCNelson/${project}.git ${DIR}/git/${project}/
	fi

	cd ${DIR}/git/${project}/
	git pull ${GIT_OPTS} || true
	cd -

	if [ -d ${DIR}/build/${project} ] ; then
		rm -rf ${DIR}/build/${project} || true
	fi

	mkdir -p ${DIR}/build/${project}
	git clone --shared ${DIR}/git/${project} ${DIR}/build/${project}

	cd ${DIR}/build/${project}

	if [ "${GIT_SHA}" ] ; then
		echo "Checking out: ${GIT_SHA}"
		git checkout ${GIT_SHA} -b ${project}-scratch
	fi
}

git_cleanup () {
	cd ${DIR}/

	rm -rf ${DIR}/build/${project} || true

	echo "${project} build completed for: ${BOARD}"
	echo "-----------------------------"
}

build_at91bootstrap () {
	project="at91bootstrap"
	git_generic

	make CROSS_COMPILE=${armv5_gcc} clean &> /dev/null
	make CROSS_COMPILE=${armv5_gcc} ${AT91BOOTSTRAP_CONFIG}_defconfig
	echo "Building ${project}: ${AT91BOOTSTRAP_CONFIG}${RELEASE_VER}.bin"
	make CROSS_COMPILE=${armv5_gcc} > /dev/null

	mkdir -p ${DIR}/deploy/${BOARD}/
	cp -v binaries/*.bin ${DIR}/deploy/${BOARD}/${AT91BOOTSTRAP_CONFIG}${RELEASE_VER}.bin

	git_cleanup
}

build_omap_xloader () {
	project="x-loader"
	git_generic

	make ARCH=arm distclean

	XGIT_VERSION=$(git rev-parse --short HEAD)
	XGIT_MON=$(git show HEAD | grep Date: | awk '{print $3}')
	XGIT_DAY=$(git show HEAD | grep Date: | awk '{print $4}')

	make ARCH=arm distclean &> /dev/null
	make ARCH=arm CROSS_COMPILE=${CC} ${XLOAD_CONFIG}
	echo "Building ${project}: ${BOARD}-${XGIT_MON}-${XGIT_DAY}-${XGIT_VERSION}"
	make ARCH=arm CROSS_COMPILE="${CCACHE} ${CC}" ift > /dev/null

	mkdir -p ${DIR}/deploy/${BOARD}
	cp -v MLO ${DIR}/deploy/${BOARD}/MLO-${BOARD}-${XGIT_MON}-${XGIT_DAY}-${XGIT_VERSION}

	git_cleanup
}

build_u_boot () {
	project="u-boot"
	git_generic

	make ARCH=arm CROSS_COMPILE=${CC} distclean
	UGIT_VERSION=$(git describe)

	if [ "${mno_unaligned_access}" ] ; then
		#remove r1 on next merge
		RELEASE_VER="-r1"
		git am "${DIR}/patches/v2012.10/0001-Revert-Revert-arm-armv7-add-compile-option-mno-unali.patch"
	fi

	if [ "${v2012_10}" ] ; then
		#bootz:
		git am "${DIR}/patches/v2012.10/0001-enable-bootz-support.patch"
		#uEnv.txt
		git am "${DIR}/patches/v2012.10/0002-ti-convert-to-uEnv.txt-n-fixes.patch"
		git am "${DIR}/patches/v2012.10/0002-imx-convert-to-uEnv.txt-n-fixes.patch"
	fi

	if [ "${enable_zImage_support}" ] ; then
		if [ "${v2012_04}" ] ; then
			git am "${DIR}/patches/v2012.04/0001-enable-bootz-support-for-ti-omap-targets.patch"
		fi
		if [ "${v2012_07}" ] ; then
			git am "${DIR}/patches/v2012.07/0001-enable-bootz-support-for-ti-omap-targets.patch"
			git am "${DIR}/patches/v2012.07/0001-enable-bootz-support-for-mx5x-targets.patch"
		fi
	fi

	if [ "${enable_uenv_support}" ] ; then
		if [ "${v2012_04}" ] ; then
			git am "${DIR}/patches/v2012.04/0001-panda-convert-to-uEnv.txt-bootscript.patch"
		fi
		if [ "${v2012_07}" ] ; then
			git am "${DIR}/patches/v2012.07/0001-panda-convert-to-uEnv.txt-bootscript.patch"
			git am "${DIR}/patches/v2012.07/0001-am3517_crane-convert-to-uEnv.txt-bootscript.patch"
			git am "${DIR}/patches/v2012.07/0001-am335-convert-to-uEnv.txt-bootscript.patch"
			git am "${DIR}/patches/v2012.07/0002-mx53loco-convert-to-uEnv.txt-bootscript.patch"
			git am "${DIR}/patches/v2012.07/0002-mx51evk-convert-to-uEnv.txt-bootscript.patch"
		fi
	fi

	if [ "${panda_fixes}" ] ; then
		RELEASE_VER="-r1"
		git am "${DIR}/patches/v2012.04/0003-panda-let-the-bootloader-set-the-intial-screen-resol.patch"
		RELEASE_VER="-r2"
		git am "${DIR}/patches/v2012.04/0004-panda-set-dtb_file-based-on-core.patch"
	fi

	if [ "${beagle_fixes}" ] ; then
		if [ "${v2012_07}" ] ; then
			git am "${DIR}/patches/v2012.07/0001-beagle-fix-dvi-variable-set-higher-resolution.patch"
			git am "${DIR}/patches/v2012.07/0001-beagle-ulcd-passthru-support.patch"
			RELEASE_VER="-r1"
			git am "${DIR}/patches/v2012.07/0002-beagle-add-kmsmode-for-ulcd-and-default-dtb_file.patch"
		fi
	fi

	if [ "${mx53loco_patch}" ] ; then
		if [ "${v2012_07}" ] ; then
			RELEASE_VER="-r1"
			git am "${DIR}/patches/v2012.07/0003-MX5-mx53loco-do-not-overwrite-the-console.patch"
		fi
	fi

	unset BUILDTARGET
	if [ "${mx6qsabrelite_patch}" ] ; then
		git pull ${GIT_OPTS} git://github.com/RobertCNelson/u-boot.git mx6qsabrelite_v2011.12_linaro_lt_imx6
		BUILDTARGET="u-boot.imx"
	fi

	if [ "${odroidx_patch}" ] ; then
		git am "${DIR}/patches/v2012.10/0001-Exynos-Add-minimal-support-for-ODROID-X.patch"
	fi

	if [ -f "${DIR}/stop.after.patch" ] ; then
		echo "-----------------------------"
		pwd
		echo "-----------------------------"
		echo "make ARCH=arm CROSS_COMPILE=${CC} ${UBOOT_CONFIG}"
		echo "make ARCH=arm CROSS_COMPILE="${CCACHE} ${CC}" ${BUILDTARGET}"
		echo "-----------------------------"
		exit
	fi

	make ARCH=arm CROSS_COMPILE=${CC} ${UBOOT_CONFIG}
	echo "Building ${project}: ${BOARD}-${UGIT_VERSION}${RELEASE_VER}"
	time make ARCH=arm CROSS_COMPILE="${CCACHE} ${CC}" ${BUILDTARGET} > /dev/null

	mkdir -p ${DIR}/deploy/${BOARD}

	unset UBOOT_DONE

	#Freescale targets just need u-boot.imx from u-boot
	if [ ! "${UBOOT_DONE}" ] && [ -f ${DIR}/build/${project}/u-boot.imx ] ; then
		cp -v u-boot.imx ${DIR}/deploy/${BOARD}/u-boot-${BOARD}-${UGIT_VERSION}${RELEASE_VER}.imx
		UBOOT_DONE=1
	fi

	#SPL based targets, need MLO and u-boot.img from u-boot
	if [ ! "${UBOOT_DONE}" ] && [ -f ${DIR}/build/${project}/MLO ] ; then
		cp -v MLO ${DIR}/deploy/${BOARD}/MLO-${BOARD}-${UGIT_VERSION}${RELEASE_VER}
		if [ -f ${DIR}/build/${project}/u-boot.img ] ; then 
			 cp -v u-boot.img ${DIR}/deploy/${BOARD}/u-boot-${BOARD}-${UGIT_VERSION}${RELEASE_VER}.img
		fi
		UBOOT_DONE=1
	fi

	#Just u-boot.bin
	if [ ! "${UBOOT_DONE}" ] && [ -f ${DIR}/build/${project}/u-boot.bin ] ; then
		cp -v u-boot.bin ${DIR}/deploy/${BOARD}/u-boot-${BOARD}-${UGIT_VERSION}${RELEASE_VER}.bin
		UBOOT_DONE=1
	fi

	git_cleanup
}

cleanup () {
	unset GIT_SHA
	set_cross_compiler
}

build_uboot_stable () {
	v2012_07=1
	if [ "${STABLE}" ] ; then
		GIT_SHA=${STABLE}
		build_u_boot
	fi
	unset v2012_07
}

build_uboot_testing () {
	v2012_10=1
	if [ "${TESTING}" ] ; then
		GIT_SHA=${TESTING}
		build_u_boot
	fi
	unset v2012_10
}

build_uboot_latest () {
	v2012_10=1
	if [ "${LATEST_GIT}" ] ; then
		GIT_SHA=${LATEST_GIT}
		build_u_boot
	fi
	unset v2012_10
}

at91sam9x5ek () {
	cleanup
	armv5_embedded_toolchain

	BOARD="at91sam9x5ek"
	GIT_SHA="8e099c3a47f11c03b1ebe5cbc8d7406063b55262"
	AT91BOOTSTRAP_CONFIG="at91sam9x5sduboot"
	build_at91bootstrap

	UBOOT_CONFIG="at91sam9x5ek_nandflash_config"
	CC=${armv5_gcc}

#	build_uboot_stable
#	build_uboot_testing
	build_uboot_latest
}

beagleboard () {
	cleanup

	BOARD="beagleboard"
	UBOOT_CONFIG="omap3_beagle_config"

	enable_zImage_support=1
	beagle_fixes=1
	build_uboot_stable
	unset beagle_fixes
	unset enable_zImage_support

	build_uboot_testing
	build_uboot_latest
}

beaglebone () {
	cleanup

	BOARD="beaglebone"
	UBOOT_CONFIG="am335x_evm_config"

	enable_zImage_support=1
	enable_uenv_support=1
#	build_uboot_stable
	unset enable_uenv_support
	unset enable_zImage_support

	build_uboot_testing
	build_uboot_latest
}

igep00x0 () {
	cleanup

	BOARD="igep00x0"

	XLOAD_CONFIG="igep00x0_config"
	build_omap_xloader

	UBOOT_CONFIG="igep0020_config"

	enable_zImage_support=1
	enable_uenv_support=1
	build_uboot_stable
	unset enable_uenv_support
	unset enable_zImage_support

	build_uboot_testing
	build_uboot_latest
}

am3517crane () {
	cleanup

	BOARD="am3517crane"
	UBOOT_CONFIG="am3517_crane_config"

	enable_zImage_support=1
	enable_uenv_support=1
	build_uboot_stable
	unset enable_uenv_support
	unset enable_zImage_support

	build_uboot_testing
	build_uboot_latest
}

pandaboard () {
	cleanup

	BOARD="pandaboard"
	UBOOT_CONFIG="omap4_panda_config"

	v2012_04=1
	enable_zImage_support=1
	enable_uenv_support=1
	panda_fixes=1
	GIT_SHA="v2012.04.01"
	build_u_boot
	unset panda_fixes
	unset enable_uenv_support
	unset enable_zImage_support
	unset v2012_04

	enable_zImage_support=1
	enable_uenv_support=1
	build_uboot_stable
	unset enable_uenv_support
	unset enable_zImage_support

	build_uboot_testing
	build_uboot_latest
}

mx51evk () {
	cleanup

	BOARD="mx51evk"
	UBOOT_CONFIG="mx51evk_config"

	enable_zImage_support=1
	enable_uenv_support=1
	build_uboot_stable
	unset enable_uenv_support
	unset enable_zImage_support

	mno_unaligned_access=1
	build_uboot_testing
	build_uboot_latest
	unset mno_unaligned_access
}

mx53loco () {
	cleanup

	BOARD="mx53loco"
	UBOOT_CONFIG="mx53loco_config"

	enable_zImage_support=1
	enable_uenv_support=1
	mx53loco_patch=1
	build_uboot_stable
	unset mx53loco_patch
	unset enable_uenv_support
	unset enable_zImage_support

	mno_unaligned_access=1
	build_uboot_testing
	build_uboot_latest
	unset mno_unaligned_access
}

mx6qsabrelite () {
	cleanup

	BOARD="mx6qsabrelite"
	UBOOT_CONFIG="mx6qsabrelite_config"

	mx6qsabrelite_patch=1
	GIT_SHA="v2011.12"
	build_u_boot
	unset mx6qsabrelite_patch

	enable_zImage_support=1
	enable_uenv_support=1
	build_uboot_stable
	unset enable_uenv_support
	unset enable_zImage_support

	mno_unaligned_access=1
	build_uboot_testing
	build_uboot_latest
	unset mno_unaligned_access
}

odroidx () {
	cleanup

	BOARD="odroidx"
	UBOOT_CONFIG="odroidx_config"

#	enable_zImage_support=1
#	enable_uenv_support=1
#	build_uboot_stable
#	unset enable_uenv_support
#	unset enable_zImage_support

	odroidx_patch=1
	build_uboot_testing
	build_uboot_latest
	unset odroidx_patch
}

rpi_b () {
	cleanup

	BOARD="rpi_b"
	UBOOT_CONFIG="rpi_b_config"

#	build_uboot_stable
#	build_uboot_testing
	build_uboot_latest
}

dl_old_bootloaders

at91sam9x5ek

am3517crane
beagleboard
beaglebone
igep00x0
mx51evk
mx53loco
mx6qsabrelite
odroidx
pandaboard
rpi_b

