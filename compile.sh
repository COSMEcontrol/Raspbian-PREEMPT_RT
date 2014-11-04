#!/bin/bash


#TOOLS_COMMIT="9c3d7b6ac692498dd36fec2872e0b55f910baac1"
TOOLS_COMMIT="master"

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

echo "[*] Actualizando/comprobando modulo Raspbian..."
git submodule update --init --recursive

echo -n "[*] Comprobando utilidades de compilacion... "
type make > /dev/null 2>&1 || { echo >&2 "[!] Instalar \"make\""; read -p "Press [Enter] to continue..."; exit 1; }
type gcc > /dev/null 2>&1 || { echo >&2 "[!] Instalar \"gcc\""; read -p "Press [Enter] to continue..."; exit 1; }
type g++ > /dev/null 2>&1 || { echo >&2 "[!] Instalar \"g++\""; read -p "Press [Enter] to continue..."; exit 1; }

if [ "$(dpkg --get-selections | grep -w libncurses5-dev | grep -w install)" = "" ]; then
	echo "[!] Instalar \"libncurses5-dev\""
	read -p "Press [Enter] to continue..."
	exit 1
fi

#TODO: check if using older arm-bcm2708-linux-gnueabi works
if [ "$MACHINE_BITS" == "64" ]; then
	TOOLS_PATH="$DIR/data/tools-$TOOLS_COMMIT/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin"
else
	TOOLS_PATH="$DIR/data/tools-$TOOLS_COMMIT/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian/bin"
fi

if [ ! -f "$TOOLS_PATH/arm-linux-gnueabihf-gcc" ]; then
	echo -n "descargando cross-compile tools... "
	cd data
	wget --no-check-certificate -q -O - "https://github.com/raspberrypi/tools/archive/$TOOLS_COMMIT.tar.gz" | tar -zx
	cd ..
fi

export PATH="$PATH:$TOOLS_PATH"

echo "ok! "

echo -n "[*] Comprobando git... "

if [ "$(git config user.email)" == "" ]; then
	echo -n "creando usuario falso... "
	git config --global user.email "raspbianrt@example.com"
	git config --global user.name "RaspbianRT"
fi

echo "ok!"

echo "[*] Limpiando datos antiguos..."
rm -rf data/linux-kernel
rm -rf build/*

if [ "$1" == "vanilla" ]; then
	echo "[*] Usando Raspbian vanilla"
	echo "[*] Copiando kernel..."
	cp -r Raspbian data/linux-kernel
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
	cp -r RaspbianRT data/linux-kernel
fi

cd data/linux-kernel

echo "[*] Usando $THREADS hilos"
echo "[*] Limpiando kernel..."
make mrproper
sed -i 's/EXTRAVERSION =.*/EXTRAVERSION = +/' Makefile

echo "[*] Creando configuracion..."
cp ../../bcmrpi_defconfig arch/arm/configs/
make -j $THREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- bcmrpi_defconfig

echo "[*] Creando menuconfig..."
make -j $THREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- menuconfig

echo "[*] Compilando kernel..."
make -j $THREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-

echo "[*] Instalando modulos de kernel..."
rm -rf ../modules
mkdir ../modules
make -j $THREADS ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_MOD_PATH=../modules/ modules_install

echo "[*] Creando imagen..."
"$DIR/data/tools-$TOOLS_COMMIT/mkimage/imagetool-uncompressed.py" arch/arm/boot/Image

echo "[*] Copiando imagen resultante..."
cp kernel.img ../../build/kernel.img
