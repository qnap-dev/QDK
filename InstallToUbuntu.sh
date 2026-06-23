#!/bin/bash
########################################
#This is easy install QDK to ubuntu tool
########################################

if [ -d "/usr/share/QDK" ]; then
	echo "QDK exists."
else
	apt-get update
	apt-get install -y build-essential wget bsdmainutils curl python openssl rsync
fi

case "$1" in
	install)
		echo "Compiler QPKG encrypt"
		cd src
		make
		cp bin/qpkg_encrypt /bin
		cd ../
		echo "Install QDK"
		cp -rf ./shared /usr/share/QDK
		[ -d "/etc/config" ] || mkdir "/etc/config"
		cp ./shared/qdk.conf /etc/config
		sed -e '2d' ./shared/qdk.conf > /etc/config/qdk.conf
		sed -i '2iQDK_PATH_P=/usr/share' /etc/config/qdk.conf
		echo "PATH=$PATH:/usr/share/QDK/bin" >> ~/.bashrc
		source ~/.bashrc
	;;
	remove)
		echo "Remove QDK"
		rm -rf "/bin/qpkg_encrypt"
		rm -rf "/etc/config/qdk.conf"
		rm -rf "/usr/share/QDK"
		sed -i '/QDK/d' ~/.bashrc
		source ~/.bashrc
	;;
	*)
		echo "Usage: $0 {install|remove}"
		exit 1
esac
exit 0
