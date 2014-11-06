#!/bin/bash


TOOLS_COMMIT="108317fde2ffb56d1dc7f14ac69c42f34a49342a"
UBOOT_COMMIT="d2a42ede2c446a6d2ce085489fb4dcb6be84877d"
#TOOLS_COMMIT="master"

DIR="$(pwd)"
cd "$DIR"
THREADS=$(($(cat /proc/cpuinfo | grep processor | wc -l) * 2))
if [ `getconf LONG_BIT` == "64" ]; then
	echo "[*] Maquina actual es 64-bit"
	MACHINE_BITS="64"
else
	echo "[*] Maquina actual es 32-bit"
	MACHINE_BITS="32"
fi

mkdir data/ > /dev/null 2>&1
mkdir build/ > /dev/null 2>&1

echo -n "[*] Comprobando utilidades de compilacion... "
type make > /dev/null 2>&1 || { echo >&2 "[!] Instalar \"make\""; read -p "Press [Enter] to continue..."; exit 1; }
type gcc > /dev/null 2>&1 || { echo >&2 "[!] Instalar \"gcc\""; read -p "Press [Enter] to continue..."; exit 1; }
type g++ > /dev/null 2>&1 || { echo >&2 "[!] Instalar \"g++\""; read -p "Press [Enter] to continue..."; exit 1; }

if [ "$(dpkg --get-selections | grep -w libncurses5-dev | grep -w install)" = "" ]; then
	echo "[!] Instalar \"libncurses5-dev\""
	read -p "Press [Enter] to continue..."
	exit 1
fi

export USE_PRIVATE_LIBGCC=yes

TOOLS_PATH="$DIR/data/tools-$TOOLS_COMMIT"

if [ "$MACHINE_BITS" == "64" ]; then
	export CCPREFIX="$TOOLS_PATH/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin/arm-linux-gnueabihf-"
else
	export CCPREFIX="$TOOLS_PATH/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian/bin/arm-linux-gnueabihf-"
fi

if [ ! -f "${CCPREFIX}gcc" ]; then
	echo -n "descargando cross-compile tools... "
	cd data
	wget --no-check-certificate -q -O - "https://github.com/raspberrypi/tools/archive/$TOOLS_COMMIT.tar.gz" | tar -zx
	cd ..
fi

echo "ok! "


echo "[*] Actualizando/comprobando modulo Raspbian..."
git submodule update --init --recursive

echo -n "[*] Comprobando git... "

if [ "$(git config user.email)" == "" ]; then
	echo -n "creando usuario falso... "
	git config --global user.email "raspbianrt@example.com"
	git config --global user.name "RaspbianRT"
fi

echo "ok!"

echo "[*] Limpiando datos antiguos..."
rm -rf data/linux-kernel
rm -rf data/u-boot
rm -rf build/*
mkdir data/linux-kernel

export KERNEL_SRC="$DIR/data/linux-kernel"

echo "[*] Descargando u-boot para RPi $UBOOT_COMMIT"
cd data
wget --no-check-certificate -q -O - "https://github.com/swarren/u-boot/archive/$UBOOT_COMMIT.tar.gz" | tar -zx
mv u-boot-$UBOOT_COMMIT u-boot
cd ..

if [ "$1" == "vanilla" ]; then
	echo "[*] Usando Raspbian vanilla"
	echo "[*] Copiando kernel..."
	cp -r Raspbian/* data/linux-kernel
else
	echo "[*] Usando Raspbian con parches RT"
	echo "[*] Aplicando parches..."
	./applyPatches.sh
	if [ "$?" != "0" ]; then
		echo "[!] Error al aplicar parches"
	else
		echo "[+] Parches aplicados correctamente"
	fi
	echo "[*] Copiando kernel..."
	cp -r RaspbianRT/* data/linux-kernel
fi

cd data/linux-kernel

echo "[*] Usando $THREADS hilos"
echo "[*] Limpiando kernel..."
make mrproper

echo "[*] Creando configuracion..."
cp ../../bcmrpi_defconfig arch/arm/configs/
ARCH=arm CROSS_COMPILE=${CCPREFIX} make -j $THREADS bcmrpi_defconfig
ARCH=arm CROSS_COMPILE=${CCPREFIX} make -j $THREADS oldconfig

echo "[*] Creando menuconfig..."
ARCH=arm CROSS_COMPILE=${CCPREFIX} make -j $THREADS menuconfig

echo "[*] Compilando kernel..."
ARCH=arm CROSS_COMPILE=${CCPREFIX} make -j $THREADS

echo "[*] Compilando modulos..."
ARCH=arm CROSS_COMPILE=${CCPREFIX} make -j $THREADS modules

echo "[*] Instalando modulos de kernel..."
rm -rf ../modules
mkdir ../modules
ARCH=arm CROSS_COMPILE=${CCPREFIX} INSTALL_MOD_PATH=../modules/ make -j $THREADS modules_install

echo "[*] Compilando u-boot"
cd ../u-boot
ARCH=arm CROSS_COMPILE=${CCPREFIX} chrt -i 0 make rpi_b_defconfig
ARCH=arm CROSS_COMPILE=${CCPREFIX} chrt -i 0 make -j $THREADS

cd tools

cp ../../../boot.scr boot.scr

echo "[*] Generando imagenes..."
./mkimage -A arm -O linux -T script -C none -n boot.scr -d boot.scr boot.scr.uimg

cd ../../linux-kernel

echo "[*] Copiando imagenes resultante..."
cp ../u-boot/u-boot.bin ../../build/kernel.img
cp arch/arm/boot/zImage arch/arm/boot/dts/bcm2835-rpi-b.dtb ../u-boot/tools/boot.scr.uimg ../../build/

echo "[*] Archivando modulos..."
cd ../modules
tar -czf ../../build/modules.tar.gz .

echo "[*] Listo!"

exit 0
