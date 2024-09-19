
# ipsecFactory

Script for automatic configuration and deployment of an IPsec IKEv2 VPN with certificate authentication including certificate generation.

Based on [OpenWrt documentation](https://openwrt.org/docs/guide-user/services/vpn/strongswan/roadwarrior).


## Features

- Automates deployment and provisiong of IPsec IKEv2 VPN with certificate authentication on OpenWrt router.
- Support multiple client - including iOS - and both pubkey and EAP-TLS authentication scheme.
- Uses local DHCP server for client IP configuration
- Can generate more client certificate after first server installation.
- Tested on OpenWrt 19.07 SNAPSHOT.


## Options

- server: Required. FQDN for server. Example: --server server.domain.tld
- clients: Required. Common Name for clients' certificate. If multiple client certificates have to be issued encase in quotes. Example: --clients 'client1 client2'
- dhcp: Required. IP of local DHCP server for address allocation. Accept also network broadcast address (192.168.1.255) or broadcast address (255.255.255.255)
- capassword: Required. Password for CA keys bundle
- clientpassword: Required. Password for client certificate bundle. This password will only be required to install certificate and key, not for IPsec authentication.
- country: Country for certificate issueing. Defaults to 'US'
- caname: Certificate Authority name for certificate issueing. Defaults to 'OpenWrtCA'
- orgname: Organization name for certificate issueing. Defaults to 'OpenWrt'
- san: Shared SAN required by iOS clients. Defaults to 'vpnClients'
- scope: Define networks reachable via VPN tunnel. If not specified defaults to 0.0.0.0/0, which correspond to a full tunnel VPN. Example: --scope 192.168.1.0/24 means that only 192.168.1.0/24 destined packet will be routed via VPN
- certonly: Skip server configuration and generate only clients certificate. Require ca.p12 file generated during initial configuration inside script directory.


## Usage

- First installation: install packages, configure server, generate CA and server certificates and one client certificate.

```bash
.\ipsecFactory.sh --server vpn.yourdomain.com --client yourClient \
 --dhcp 192.168.1.1 --capassword yourCAPassword --clientpassword yourClientPassword \
 --country CH --caname yourCA --orgname yourOrganization
```

- Client certificate generate other client certificates using previously created CA. Require CA keys bundle inside script directory.

```bash
.\ipsecFactory.sh --certonly --client 'aClient anotherClient oneMoreClient' \
 --capassword yourCAPassword --clientpassword yourClientPassword
```
