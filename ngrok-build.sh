#!/bin/bash
_CURRENT_FILE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
_CURRENT_RUNNING_DIR="$( cd "$( dirname "." )" && pwd )"
source $_CURRENT_FILE_DIR/stella-link.sh include


# GENERATE NGROK PATCH
# FROM 1.7.1 to latest version on master
# git format-patch 1.7.1 --stdout > ngrok_patch_1.7.1_TO_20160312.patch

#DEFAULT_GOVER="1.4.2"
wget https://storage.googleapis.com/golang/go1.7.1.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.7.1.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

function usage() {
    echo "USAGE :"
    echo "----------------"
    echo " o-- List of commands"
    echo " L  prepare [--gover=<go version>] : get everything you need -- you could specify a go version which will be used for the cross-compile toolchain"
    echo " L  build -d my.domain.com : build ngrokd server and ngrok client paired together"
    echo " L  clean : delete everything for a fresh start"
}


# COMMAND LINE ARGUMENTS -----------------------------------------------------------------------------------
PARAMETERS="
ACTION=					'action' 			a					'prepare build clean'					Action.
"
OPTIONS="
DOMAIN=''				'd'			'my.domain.com'					's'			0			''		Domain name.
GOVER='$DEFAULT_GOVER'			''			''								's'			0 			'' 		Go version used to cross compile client
"

$STELLA_API argparse "$0" "$OPTIONS" "$PARAMETERS" "ngrok-build" "$(usage)" "" "$@"


function gen_cert() {

	if [ "$DOMAIN" == "" ]; then
		echo " WARN : plesae specify your root domain (my.domain.com)";
		exit 1
	fi
	
	$STELLA_API del_folder $CERT_HOME
	mkdir -p $CERT_HOME
	cd $CERT_HOME

	openssl genrsa -out rootCA.key 2048
	openssl req -x509 -new -nodes -key rootCA.key -subj "/CN=$DOMAIN" -days 5000 -out rootCA.pem
	openssl genrsa -out device.key 2048
	openssl req -new -key device.key -subj "/CN=$DOMAIN" -out device.csr
	openssl x509 -req -in device.csr -CA rootCA.pem -CAkey rootCA.key -CAcreateserial -out device.crt -days 5000

	cp -f rootCA.pem $NGROK_HOME/assets/client/tls/ngrokroot.crt
}


function check_requirements() {
	apt-get install make gcc patch git mercurial
	if [ -z $(which make) ]; then 
		echo " WARN : you have to install gnu make on your system"
		exit 1
	else
		echo "make detected"
	fi

	if [ -z $(which git) ]; then 
		echo " WARN : you have to install git on your system"
		echo " see http://git-scm.com/"
		exit 1
	else
		echo "git detected : $(git --version)"
	fi

	if [ -z $(which hg) ]; then 
		echo " WARN : you have to install mercurial on your system"
		exit 1
	else
		echo "hg detected"
	fi

	if [ -z $(which openssl) ]; then 
		echo " WARN : you have to install openssl on your system"
		echo " ubuntu : sudo apt-get install openssl"
		echo " macos : brew install openssl"
		echo " OR see https://www.openssl.org/"
		exit 1
	else
		echo "OpenSSL detected : $(openssl version)"
	fi
}

# MAIN -----------------------------------------------------------------------------------

export GOPATH=$STELLA_APP_WORK_ROOT

NGROK_HOME=$STELLA_APP_WORK_ROOT/ngrok
GONATIVE_HOME=$STELLA_APP_WORK_ROOT/gonative
RELEASE_HOME=$STELLA_APP_ROOT/release
GOTOOLCHAIN=$STELLA_APP_WORK_ROOT/gonative-toolchain
GOX_HOME=$STELLA_APP_WORK_ROOT/gox
CERT_HOME=$STELLA_APP_WORK_ROOT/cert


check_requirements

case $ACTION in
	clean)
		rm -Rf $STELLA_APP_WORK_ROOT
		rm -Rf $RELEASE_HOME
	;;

	prepare)
		echo "** get all requirement"
        $STELLA_API get_data_pack "DATA_LIST"

        echo "** patch ngrok (if any)"
        cp "$STELLA_APP_ROOT"/pool/patch/*.patch "$STELLA_APP_WORK_ROOT"/ngrok/
        cd "$STELLA_APP_WORK_ROOT"/ngrok
        patch -Np1 < *.patch

        echo "** install all features"
        $STELLA_API get_features

        echo "** install gox"
        export GOPATH=$GOX_HOME
        go get github.com/mitchellh/gox
        export GOPATH=$STELLA_APP_WORK_ROOT

        echo "** install gonative"
        export GOPATH=$GONATIVE_HOME
		#go get github.com/inconshreveable/gonative
		cd $STELLA_APP_WORK_ROOT
		git clone https://github.com/inconshreveable/gonative
		cd gonative
		make
		#echo "** build cross compiling native buildchain"
		#rm -Rf $GOTOOLCHAIN
		#mkdir -p $GOTOOLCHAIN
		#cd $GOTOOLCHAIN
		#$GONATIVE_HOME/gonative build --version="1.7.1" --platforms="windows_386 windows_amd64 linux_arm linux_386 linux_amd64 darwin_386 darwin_amd64"

	;;


	build)
		echo "** gen certificates"
		gen_cert


		echo "** tweak ngrok makefile for gox support"
		cd $NGROK_HOME
		cp -f Makefile Makefile-gox
		echo "">>Makefile-gox
		echo "release-client-gox: BUILDTAGS=release">>Makefile-gox
		echo "release-client-gox: client-gox">>Makefile-gox
		echo "">>Makefile-gox
		echo "client-gox: deps">>Makefile-gox
		echo "		  $GOX_HOME/bin/gox -tags '\$(BUILDTAGS)' -osarch='windows/386 windows/amd64 linux/arm linux/386 linux/amd64 darwin/386 darwin/amd64' ngrok/main/ngrok">>Makefile-gox

		echo "">>Makefile-gox
		echo "release-server-gox: BUILDTAGS=release">>Makefile-gox
		echo "release-server-gox: server-gox">>Makefile-gox
		echo "">>Makefile-gox
		echo "server-gox: deps">>Makefile-gox
		echo "		  $GOX_HOME/bin/gox -tags '\$(BUILDTAGS)' -osarch='windows/386 windows/amd64 linux/armlinux/386 linux/amd64 darwin/386 darwin/amd64' ngrok/main/ngrokd">>Makefile-gox



		cd $NGROK_HOME
		export GOPATH=$NGROK_HOME

		# echo "** build server only for current platform"
		# make release-server

		echo "** build server for all platforms"
		export GOPATH=$NGROK_HOME
		PATH=$GOTOOLCHAIN/go/bin:$PATH make -f Makefile-gox release-server-gox

		echo "** build client for all platforms"
		export GOPATH=$NGROK_HOME
		PATH=$GOTOOLCHAIN/go/bin:$PATH make -f Makefile-gox release-client-gox
		
		echo "** retrieving files"
		rm -Rf $RELEASE_HOME
		mkdir -p $RELEASE_HOME/client
		mkdir -p $RELEASE_HOME/server
		mv -f ngrokd* $RELEASE_HOME/server
		mv -f ngrok* $RELEASE_HOME/client
		cp -f $CERT_HOME/device.crt $RELEASE_HOME/server
		cp -f $CERT_HOME/device.key $RELEASE_HOME/server


		echo "** generate ngrok client configuration file"
		echo -e "server_addr: $DOMAIN:4443\ntrust_host_root_certs: false" > $RELEASE_HOME/client/ngrok-config


		echo "** You should now get your result files from $RELEASE_HOME"
		echo "client usage :"
		echo "		sudo ngrok -subdomain=test1 -config=ngrok-config 80"
		echo "server usage :"
		echo "		sudo ./ngrokd -tlsKey='device.key' -tlsCrt='device.crt' -domain='$DOMAIN' -httpAddr=':80' -httpsAddr=':443'"
		echo ""
		echo "		-httpAddr=':80' and -httpsAddr=':443' are user endpoints port. The entry of tunnels."
		echo ""
		echo "		Dont forget on server-side to add this into your /etc/hosts"
		echo "		<DOMAIN-IP> $DOMAIN test1.$DOMAIN test2.$DOMAIN"
		echo "		or add a wildcard into a DNS server :"
		echo "		<DOMAIN-IP> *.$DOMAIN"
	;;

esac
