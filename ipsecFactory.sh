#!/bin/sh


COUNTRYNAME="US"
CANAME="OpenWrtCA"
ORGNAME="OpenWrt"
SERVERDOMAINNAME=""
CLIENTNAMES=""
SHAREDSAN="vpnClients"
LOCALSUBNET="0.0.0.0/0"
DHCPSERVER=""
CAPASSWORD=""
CLIENTPASSWORD=""
CERTONLY=0


read -r -d '' HELP<< endHelp
Script for automatic configuration and deployment of an IPsec IKEv2 VPN with certificate authentication including certificate generation.
Options:
	--server	Required. FQDN for server. Example: --server server.domain.tld
	--clients	Required. Common Name for clients' certificate. If multiple client certificates have to be issued encase in quotes. Example: --clients 'client1 client2'
	--dhcp		Required. IP of local DHCP server for address allocation. Accept also network broadcast address (192.168.1.255) or broadcast address (255.255.255.255)
	--capassword	Required. Password for CA keys bundle
	--clientpassword	Required. Password for client certificate bundle. This password will only be required to install certificate and key, not for IPsec authentication.
	--country	Country for certificate issueing. Defaults to 'US'
	--caname	Certificate Authority name for certificate issueing. Defaults to 'OpenWrtCA'
	--orgname	Organization name for certificate issueing. Defaults to 'OpenWrt'
	--san		Shared SAN required by iOS clients. Defaults to 'vpnClients'
	--scope		Define networks reachable via VPN tunnel. If not specified defaults to 0.0.0.0/0, which correspond to a full tunnel VPN. Example: --scope 192.168.1.0/24 means that only 192.168.1.0/24 destined packet will be routed via VPN
	--certonly	Skip server configuration and generate only clients certificate. Require ca.p12 file generated during initial configuration inside script directory.

endHelp


read -r -d '' UCIFW<< endFw
config rule 'ipsec_esp'
	option src 'wan'
	option name 'IPSec ESP'
	option proto 'esp'
	option target 'ACCEPT'
 
config rule 'ipsec_ike'
	option src 'wan'
	option name 'IPSec IKE'
	option proto 'udp'
	option dest_port '500'
	option target 'ACCEPT'
 
config rule 'ipsec_nat_traversal'
	option src 'wan'
	option name 'IPSec NAT-T'
	option proto 'udp'
	option dest_port '4500'
	option target 'ACCEPT'
 
config rule 'ipsec_auth_header'
	option src 'wan'
	option name 'Auth Header'
	option proto 'ah'
	option target 'ACCEPT'

endFw


read -r -d '' USERFW<< endFw
iptables -I INPUT  -m policy --dir in --pol ipsec --proto esp -j ACCEPT
iptables -I FORWARD  -m policy --dir in --pol ipsec --proto esp -j ACCEPT
iptables -I FORWARD  -m policy --dir out --pol ipsec --proto esp -j ACCEPT
iptables -I OUTPUT   -m policy --dir out --pol ipsec --proto esp -j ACCEPT
iptables -t nat -I POSTROUTING -m policy --pol ipsec --dir out -j ACCEPT
endFw


if [[ $# = 0 ]]; then
	echo "$HELP"
	exit 0
fi


while [ True ]; do
	case $1 in
		--server)
			SERVERDOMAINNAME=$2
			shift 2
			;;
		--clients)
			CLIENTNAMES=$2
			shift 2
			;;
		--dhcp)
			DHCPSERVER=$2
			shift 2
			;;
		--capassword)
			CAPASSWORD=$2
			shift 2
			;;
		--clientpassword)
			CLIENTPASSWORD=$2
			shift 2
			;;
		--country)
			COUNTRYNAME=$2
			shift 2
			;;
		--caname)
			CANAME=$2
			shift 2
			;;
		--orgname)
			ORGNAME=$2
			shift 2
			;;
		--san)
			SHAREDSAN=$2
			shift 2
			;;
		--scope)
			LOCALSUBNET=$2
			shift 2
			;;
		--certonly)
			CERTONLY=1
			shift 1
			;;
		*)
			break
			;;
	esac
done


if [[ "$CLIENTNAMES" = "" -o "$CAPASSWORD" = "" -o "$CLIENTPASSWORD" = "" ]]; then
	
	echo Missing required argument.
	echo
	echo "$HELP"
	exit 0

fi


if [[ "$CERTONLY" = 0 ]]; then

	if [[ "$SERVERDOMAINNAME" = "" -o "$DHCPSERVER" = "" ]]; then

		echo Missing required argument.
		echo
		echo "$HELP"
		exit 0

	fi

	echo "Installing strongswan packages..."
	opkg update
	opkg install strongswan-full

	echo "Current configuration will be renamed with .prev extension"
	cp -a /etc/ipsec.d /etc/ipsec.d.prev
	cp -a /etc/strongswan.d /etc/strongswan.d.prev
	cp /etc/config/firewall /etc/config/firewall.prev
	cp /etc/firewall.user /etc/firewall.user.prev
	mv /etc/ipsec.conf /etc/ipsec.conf.prev
	mv /etc/ipsec.secrets /etc/ipsec.secrets.prev

	echo "Downloading template files..."
	wget https://raw.githubusercontent.com/Qwertyadmin/ipsecFactory/master/ipsec.conf.template -O /etc/ipsec.conf
	wget https://raw.githubusercontent.com/Qwertyadmin/ipsecFactory/master/ipsec.secrets.template -O /etc/ipsec.secrets
	wget https://raw.githubusercontent.com/Qwertyadmin/ipsecFactory/master/dhcp.conf.template -O /etc/strongswan.d/charon/dhcp.conf

	echo "Compiling template..."
	sed -i "s+{SERVERDOMAINNAME}+$SERVERDOMAINNAME+g; s+{LOCALSUBNET}+$LOCALSUBNET+g; s+{COUNTRYNAME}+$COUNTRYNAME+g; s+{ORGNAME}+$ORGNAME+g; s+{CANAME}+$CANAME+g; s+{SHAREDSAN}+$SHAREDSAN+g;" /etc/ipsec.conf
	sed -i "s+{SERVERDOMAINNAME}+$SERVERDOMAINNAME+g" /etc/ipsec.secrets
	sed -i "s+{DHCPSERVER}+$DHCPSERVER+g" /etc/strongswan.d/charon/dhcp.conf

	echo "Configuring firewall..."
	echo "${UCIFW}" >> /etc/config/firewall
	echo "${USERFW}" >> /etc/firewall.user

	echo "Restarting firewall..."
	/etc/init.d/firewall restart

	echo "Building certificates for $SERVERDOMAINNAME and client(s) $CLIENTNAME (aka $SHAREDSAN)..."
	echo "generating a new cakey for $CANAME..."
	ipsec pki --gen --outform pem > caKey.pem
	echo "generating caCert for $CANAME..."
	ipsec pki --self --lifetime 3652 --in caKey.pem --dn "C=$COUNTRYNAME, O=$ORGNAME, CN=$CANAME" --ca --outform pem > caCert.pem
	openssl x509 -inform PEM -outform DER -in caCert.pem -out caCert.crt
	echo "Now building CA keys bundle..."
	openssl pkcs12 -export -inkey caKey.pem -in caCert.pem -name "$CANAME" -certfile caCert.pem -caname "$CANAME" -password "pass:$CAPASSWORD" -out ca.p12
	 
	echo "generating server certificates for $SERVERDOMAINNAME..."
	ipsec pki --gen --outform pem > serverKey_$SERVERDOMAINNAME.pem
	ipsec pki --pub --in serverKey_$SERVERDOMAINNAME.pem | ipsec pki --issue --lifetime 3652 --cacert caCert.pem --cakey caKey.pem --dn "C=$COUNTRYNAME, O=$ORGNAME, CN=$SERVERDOMAINNAME" --san="$SERVERDOMAINNAME" --flag serverAuth --flag ikeIntermediate --outform pem > serverCert_$SERVERDOMAINNAME.pem

	cp caCert.pem /etc/ipsec.d/cacerts/
	echo "Copy ca.p12 /somewhere/safe/on/your/pc (includes caCert and caKey, needed to generate more certs for more clients)"
	cp serverCert*.pem /etc/ipsec.d/certs/
	cp serverKey*.pem /etc/ipsec.d/private/
	rm serverKey*.pem

else

	if [ -f "caKey.pem" ] ; then

		echo "caKey exists, using existing caKey for signing clientCert...."

	elif [ -f "ca.p12" ] ; then

		echo "CA keys bundle exists, accessing existing protected caKey for signing clientCert...."
		openssl pkcs12 -in ca.p12 -passin "pass:$CAPASSWORD" -nodes  -nocerts -out caKey.pem

	else

		echo "ca.p12 file not found. CA keys are necessary to sign new client certificate."
		exit 1

	fi

	cp /etc/ipsec.d/cacerts/caCert.pem ./

fi

for CLIENTNAME in $CLIENTNAMES; do

  if [ -f "clientCert_$CLIENTNAME.pem" ] ; then

    echo "clientCert for [ $CLIENTNAME ] exists, not generating new clientCert."
    continue
  
  fi

  echo "Generating clientCert for $CLIENTNAME (aka $SHAREDSAN)..."
  ipsec pki --gen --outform pem > clientKey_$CLIENTNAME.pem
  ipsec pki --pub --in clientKey_$CLIENTNAME.pem | ipsec pki --issue --lifetime 3652 --cacert caCert.pem --cakey caKey.pem --dn "C=$COUNTRYNAME, O=$ORGNAME, CN=$CLIENTNAME" --san="$CLIENTNAME" --san="$SHAREDSAN" --outform pem > clientCert_$CLIENTNAME.pem
  openssl x509 -inform PEM -outform DER -in clientCert_$CLIENTNAME.pem -out clientCert_$CLIENTNAME.crt
  echo "Now building Client keys bundle for $CLIENTNAME..."
  openssl pkcs12 -export -inkey clientKey_$CLIENTNAME.pem -in clientCert_$CLIENTNAME.pem -name "$CLIENTNAME" -certfile caCert.pem -caname "$CANAME" -password "pass:$CLIENTPASSWORD" -out client_$CLIENTNAME.p12
  rm clientKey_$CLIENTNAME.pem
  openssl x509 -inform PEM -outform DER -in clientCert_$CLIENTNAME.pem -out clientCert_$CLIENTNAME.crt

done

rm caKey.pem
echo "copy client_*.p12 /somewhere/safe/on/your/clients"
echo "copy caCert.crt and clientCert_*.crt to /somewhere/safe/on/your/clients for Android clients"

echo "Restarting IPsec..."
/etc/init.d/ipsec stop
/etc/init.d/ipsec start