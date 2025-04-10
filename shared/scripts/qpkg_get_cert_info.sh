#!/bin/bash
###Version 1.0.0

# Exit result
readonly SUCCESS=0
readonly NOT_ENOUGH_ARGUMENT=1
readonly INVALID_OPENSSL_VERSION=2
readonly ERROR_QPKG_TYPE=3
readonly CS_VERIFY_ERROR=4
readonly CS_VERIFY_FAIL=5 #This means either the certificate is invalid or qpkg data does not match signature

##### System definitions #####
PREFIX="App Center"

##### Command definitions #####
CMD_LS="${CMD_LS:-$(command -v ls)}"
CMD_AWK="${CMD_AWK:-$(command -v awk)}"
CMD_CMP="${CMD_CMP:-$(command -v cmp)}"
CMD_CUT="${CMD_CUT:-$(command -v cut)}"
CMD_GREP="${CMD_GREP:-$(command -v grep)}"
CMD_DD="${CMD_DD:-$(command -v dd)}"
CMD_SED="${CMD_SED:-$(command -v sed)}"
CMD_MKTEMP="${CMD_MKTEMP:-$(command -v mktemp)}"
CMD_RM="${CMD_RM:-$(command -v rm)}"

CS_DIR=
CS_DIR_TMP=

readonly LEGAL_OPEN_SSL_VER="1.1"

readonly CS_READ_BS=1048576

readonly CS_PREREAD_BS=16384
readonly CS_POSTREAD_BS=16384

readonly QDK_ARCH="control.tar.gz"

readonly CS_QPKG_TAIL_DATA_LEN=100
readonly CS_DS_MAX_SIZE=20480

readonly CS_TYPE_QDK="QDK"
readonly CS_TYPE_QPKG="QPKG"

CS_QPKG_TYPE=

# Supported data types in the QDK area.
readonly QDK_AREA_SIGNATURE=1
readonly QDK_AREA_CODE_SIGNING=254
readonly QDK_AREA_EOF=255

# Length of QDK tag that is added to the front of the QDK area.
readonly QDK_AREA_TAG_LEN=3

# Length of data type value.
readonly QDK_AREA_DATA_TYPE_LEN=1

# Length of data size value.
readonly QDK_AREA_DATA_SIZE_LEN=4

# Length of tail data.
readonly TAIL_DATA_LEN=100


# CA certificate text (trqp)
readonly CA_CERT_TEXT="
-----BEGIN CERTIFICATE-----
MIIDfjCCAmYCCQDOLPu1P4u2wjANBgkqhkiG9w0BAQsFADCBgDELMAkGA1UEBhMC
VFcxDzANBgNVBAgMBlRhaXdhbjEPMA0GA1UEBwwGVGFpcGVpMQ0wCwYDVQQKDARR
TkFQMQwwCgYDVQQLDANOQVMxEDAOBgNVBAMMB1FOQVBfQ0ExIDAeBgkqhkiG9w0B
CQEWEXNlY3VyaXR5QHFuYXAuY29tMB4XDTE5MDExNzA5MzkwOVoXDTI5MDExNDA5
MzkwOVowgYAxCzAJBgNVBAYTAlRXMQ8wDQYDVQQIDAZUYWl3YW4xDzANBgNVBAcM
BlRhaXBlaTENMAsGA1UECgwEUU5BUDEMMAoGA1UECwwDTkFTMRAwDgYDVQQDDAdR
TkFQX0NBMSAwHgYJKoZIhvcNAQkBFhFzZWN1cml0eUBxbmFwLmNvbTCCASIwDQYJ
KoZIhvcNAQEBBQADggEPADCCAQoCggEBAJeEm/BWUDUHv7eSonaL17V1XMp6Yoyy
zeo91jMohhBU2tVGiewHC7LSk7I5CTe6kC04e7X+pAy1LZAI20jjEnIKhMwnJ5O4
GGbcy88qXimOSqM9qnWH5lE3e6ZPESfnQlQArDMjeEG3iWDUildKco76/q/RWxT6
BSpAFEp776qddw6lC6Y2bANXvIoE9uSn85p1iZOSTh3qX+k1OSMEKoiOEmL/gmSS
f8PeClzyzet2WpbeM15BCicpV87SDv27afsN/pD07DIbrxu9h2BkktDSejQ3tcfx
oItDToNQkyCX0wAAUBZpW2vzEjgKVomg4LCHAR/OsHn1jPP0B6EISmkCAwEAATAN
BgkqhkiG9w0BAQsFAAOCAQEAlUchw3kRdfAmEhDooQyKq84kRfTfcr0OXdaXjVuL
/QhgK7ReNr3kIUQevWtegU8nPaXcakvYK0fDul0KXqqBb0VDV6LWSuULxCfLM1th
SI+plpDo8Ocl42sJZ0+z7IXSSxBrhHAKATJDNd1av20+wIZpoCfVy0UeBwYPvM03
e8/Wynq6h2tlz8USRApVeuL1GcUiZCbP6HCleznsyXtY7Vx35adMjzL9W4MPxgCD
vEL3tZs0f0mCf28MVlV4z/L8TiHkrKmgH40ADPfFC8H9fiqHltlbxWvez+miKCj4
rMkr8vN3fXcQyQJk7fdCXXH7ZWVzmy6HmEwIq1/yZ/Sphw==
-----END CERTIFICATE-----"

# CA certificate text (trqp3)
readonly CA_CERT3_TEXT="
-----BEGIN CERTIFICATE-----
MIIDAjCCAeoCCQCtVWmvNSMM6zANBgkqhkiG9w0BAQsFADBDMRcwFQYDVQQKDA5R
TkFQIDNyZCBwYXJ0eTEMMAoGA1UECwwDTkFTMRowGAYDVQQDDBFRTkFQIDNyZCBw
YXJ0eSBDQTAeFw0xOTAxMjgwNDE1MzhaFw0yOTAxMjUwNDE1MzhaMEMxFzAVBgNV
BAoMDlFOQVAgM3JkIHBhcnR5MQwwCgYDVQQLDANOQVMxGjAYBgNVBAMMEVFOQVAg
M3JkIHBhcnR5IENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEArad4
o7HpOYx+U6c8BoNfwzdFuEyGdG4SjLGwF6RfoIMs+SpukHWV5SuPAhw7wgQTdiKY
+ZXS6xbwp8pRGjN4pybrp06KQw/9nDziu3XmmC6BP2442/zkViyYKcib6EdFEuMM
eLZG/uEUnCh6NRPWhBuaiG3OSpXGSdRgQF0GjhgONI5BpjI7OLJaxSH9o7XhUrnn
gqazQyUKGm/Bi2RbIh8kdyaEGzkHe0OToqJB8V4Yne0jfWZ+YJq5zRCt+WJpH+ea
lkOR0p9P7CGe+gsySSVv05Hy+sy/JZHUv8kM1XcaQWjdCmkhkqoGDIO9ENnd7XNO
eUysbpSctYvfegjNYwIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQClbkqML0H9+Wy2
uu6wtgGq3vGFwQfujE8VayxWDD2GTAopwnf6FslrZiBfWYX/8iOEYlS9OyOvxTVW
FmNg1btI6O6Pw+NXpB3L0OUqVdD5/h2pgWnFRdtgZyn3sBPodrhbyjoDOl0+vXpT
vYGpZdYsMPonxuZ40mdntMgvmsJX+qZStLBQYpNlGQRNkqxYq6Rwtv5LFUIWuHjM
qZHoR5Z7EdvkFdh4B8ginJgSO2X+Kpfmj3VMsNTtV4baxGXYTIBJoCDP1HR8nbvB
ezNnh1TGnAyDvFX3fnm2YgjDF1+uQYU/jTWRcn2cpoChu3+q8Qmw4u2j2AO3Oh6i
XxNKqd6A
-----END CERTIFICATE-----"

# CA certificate text (trqp3_1)
readonly CA_CERT3_1_TEXT="
-----BEGIN CERTIFICATE-----
MIIC8DCCAdgCCQChgLWTbW5gCTANBgkqhkiG9w0BAQsFADA6MRQwEgYDVQQKDAtU
aGlyZCBwYXJ0eTEMMAoGA1UECwwDTkFTMRQwEgYDVQQDDAtUaGlyZCBwYXJ0eTAe
Fw0xOTA4MjgxMDE2NTZaFw0yOTA4MjUxMDE2NTZaMDoxFDASBgNVBAoMC1RoaXJk
IHBhcnR5MQwwCgYDVQQLDANOQVMxFDASBgNVBAMMC1RoaXJkIHBhcnR5MIIBIjAN
BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0AUk/sjUk/zfBGOh1eAwxH7qeNUJ
LcT4BZpeGt2QsJpT+BXVjlJ9Cg7BaIgZ8VpgA14GsHO2sQ+vfn+qmWuBaEbyaCC2
EoJEvftjpMSvAYz4k4IL2M0yGSXEgy11t8ZeDceuu/QG/u7ADHqHWmeBLAujLywZ
kVzpfkENrCfKDGTJ1MYcMmis8mgpTFJJenRcdtCENjE0CXPNz84jw3H6AxQAuoYG
eUs5eDwwuROpVtI3OyMYW9uOWX9++jrCXtpO9jAR3/i3pIeXcjrMirPsSoz5uJPm
eFWoP95f6xEvEQNQ92WpBevCPxg7JA60IhUD1JG2TYWzsfLY/l5AVceGEQIDAQAB
MA0GCSqGSIb3DQEBCwUAA4IBAQCKb5fFUBglIgiN4fwiOl16iGby69KYlqpHFpN6
UUF3A4b1JtHENRsx12NHOoscPa/zQymcJPv0B65LhOtBdi+ahowmc6Cj/UwItFzh
ZS0DM5Ir+/yhA5KT0G20O2CDSFUDGL8rmvAyyzResipPPYuhE2zziwpsUX08M3KI
mTQIwkSQf6EwPQL2hEQ+MNYkVYPjMqkmKx9ZdhYlcQEoVPvxtD7D4KonyBsQmfgf
EMFmgryoj7SHrhgaOqpMTStNDERKn/OYwmFAngOF6nL/g5iHE3wy/oVh1329+iSS
2PYETbmwZLN4FlUl6ETmqRLn6/VAl+x/IaTjSfEPu3x/aN40
-----END CERTIFICATE-----"

# CA certificate text (trqp_v2)
readonly CA_CERT_V2_TEXT="
-----BEGIN CERTIFICATE-----
MIID4zCCAsugAwIBAgIUBfjRk4cev99uzoj+6jGNdBLHL6kwDQYJKoZIhvcNAQEL
BQAwgYAxCzAJBgNVBAYTAlRXMQ8wDQYDVQQIDAZUYWl3YW4xDzANBgNVBAcMBlRh
aXBlaTENMAsGA1UECgwEUU5BUDEMMAoGA1UECwwDTkFTMRAwDgYDVQQDDAdRTkFQ
IENBMSAwHgYJKoZIhvcNAQkBFhFzZWN1cml0eUBxbmFwLmNvbTAeFw0yMTA1MTgx
MDI0NTFaFw0zMTA1MTYxMDI0NTFaMIGAMQswCQYDVQQGEwJUVzEPMA0GA1UECAwG
VGFpd2FuMQ8wDQYDVQQHDAZUYWlwZWkxDTALBgNVBAoMBFFOQVAxDDAKBgNVBAsM
A05BUzEQMA4GA1UEAwwHUU5BUCBDQTEgMB4GCSqGSIb3DQEJARYRc2VjdXJpdHlA
cW5hcC5jb20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCuvG5lNIkV
St+8OE0Acy67wM1S/mxzsHV6tmsVK0zFm+sHYihwvZMgfM5uiieusfPuYsTOo1U4
P+vqOEqSgQQJCkurV5BvHY+kyqZZWwrxWRepniQVo1MY30eSSR1IJLBL5SFgMZp1
EZIdYGkDz2EWKwpMYNvVPNgFuCqLlBq48d4pdenqtEIJlffshxaR5VO6rjwRBlq8
5Zt0kZgFtCLne1rQlef1yYv8FhDSR6ymaheHOK4/jfB2HdSTKcklC9Z1uHQVbYV9
dgGgxDdbkCM4Mwk/1kD7Tus46uMc+tI7E/S0G1dgFSuLtZ1rvZDdNZUfrF7GTGzV
ix5HBzvQiC8fAgMBAAGjUzBRMB0GA1UdDgQWBBS8wgVUAbEqNTlr+hwJ5HK+ExJ2
pDAfBgNVHSMEGDAWgBS8wgVUAbEqNTlr+hwJ5HK+ExJ2pDAPBgNVHRMBAf8EBTAD
AQH/MA0GCSqGSIb3DQEBCwUAA4IBAQAhtvRrF9UT+JSn+AElKF45/uR1VrTfgpRG
j6Ku9YkiV2RsuPv0lBIZnOMMXynRZqzAzAMIOk5uSurLu0/DZsYzbMs7/BxhrtXq
FE9EtTShZb8cpW3sl4MK/J/dFYisMHS04hJU05Xm/QzFBOE/xdyWHyrtCAHwMHub
7NQRhQt3vhpmSgrz3s+eXt/A7koQAts9GYlZAmmmgAGgkwEtz3Aa1wwnC7dFG49H
Zwo49vxCqRhVdYEwGg0itlI6L/g4a06D35CpPR8Ww41Uc32ebsUfeOUhWAXS3K0W
N4FA43LLORGEjU8fjaOEzSPL+XBRY4Hp6xmYvHTcv5/MT+LMklnK
-----END CERTIFICATE-----"

# CA certificate text (trqp3_1_v2)
readonly CA_CERT3_1_V2_TEXT="
-----BEGIN CERTIFICATE-----
MIIDVTCCAj2gAwIBAgIUDSA0r5nKFXGl55Mfa/meOY/o1QwwDQYJKoZIhvcNAQEL
BQAwOjEUMBIGA1UECgwLVGhpcmQgcGFydHkxDDAKBgNVBAsMA05BUzEUMBIGA1UE
AwwLVGhpcmQgcGFydHkwHhcNMjEwNTE4MTAyNjM1WhcNMzEwNTE2MTAyNjM1WjA6
MRQwEgYDVQQKDAtUaGlyZCBwYXJ0eTEMMAoGA1UECwwDTkFTMRQwEgYDVQQDDAtU
aGlyZCBwYXJ0eTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOyoPJeY
9+qX+EEtJ8m+hoGICm6cKfasAwgMtEONLXwDr5ZN3sCHd4V6ygOs99JREbobzyD8
EldUTMe7GXDP9dWL/X3WabBX9MXpOHYyYLSoeQUxSa1vMJVjZTmCPWpSYGu1WLgW
MCdJ+DnLz8Pk123u6QgVlaAm2pPAdJ0yqMlj717YXfry5S1i1qpUCiN61v/8o689
/DR3prFxHoxpF8jZmg3g0rUi6Vh9SSW/uyb7PeVnpwsPLVCAjy5SSGQaKzBgn1UJ
6dcaiGUz9ti8rZljXW+Dspkkd5sPLKld1uzaqexjaw9YqCR4Zzr5jnyi1zXPIlzY
dtCtAdHa6awvA2cCAwEAAaNTMFEwHQYDVR0OBBYEFIOf/9nieJMEqIRSbsWKOUy0
Vc/YMB8GA1UdIwQYMBaAFIOf/9nieJMEqIRSbsWKOUy0Vc/YMA8GA1UdEwEB/wQF
MAMBAf8wDQYJKoZIhvcNAQELBQADggEBAK7WLkN6HIUVLbkbTzxeHNi0BdYqPt87
u+f4IF0qlAJ/7gq/ih+/jmGmJ354GrHhQUgNLB7RtQhlT4YgzyD/CkeRjZagNzpc
wswHS4XPS+WVkQO5ZbwDXJclFtWI+FbY7632cbvcqyDlnpWyyi44TG3BWqWxV+V+
ueITrOOjOAouqTfBI7+VWEzCDmm+/LGJlPhkrjENVinetjquPvXzAXfwvX+UWikS
fbRxpvIpayR84za/lUIAKI1lbPw3t30arA4G2ZKJKrcuyjJA5TCS+++K1EpmL2ZE
VJCQeu1twdH5ZGfIqcwVQvwPZ2taRVBB8SexXZFvqjat8mya+c7kaIQ=
-----END CERTIFICATE-----"

# Log messages are printed (to stdout) if verbose mode is greater or equal
# to specified level (default: NORMAL).
msg(){
	[ $QDK_VERBOSE -ge ${2:-$NORMAL} ] && echo "$1" || return 0
}

# Error messages are always printed (to stderr) before the application
# removes any temporary files and exit (in cleanup_all).
err_msg(){
	echo "$1" 1>&2
	cleanup_all $CS_VERIFY_ERROR
}

# Remove all temporary directories and files created by application.
cleanup_all(){
	$CMD_RM -rf $CS_DIR_TMP
	#printf "clean up %s \n" $CS_DIR_TMP
	$CMD_RM -rf $CS_DIR
	#printf "clean up %s \n" $CS_DIR
	exit $1
}

# Retrieve size of content (that is the size of the header, control data, data
# archive, and any optional extra data archives.)
get_content_size(){
	[ -n "$1" ] || err_msg "internal error: get_content_size called with no argument"
	local qpkg="$1"
	[ -f $qpkg ] || err_msg "$qpkg: no such file"

	local qpkg_header_file="${CS_DIR}/headerFile"
	sed -n "{/^exit 1\|^${QDK_ARCH}/q;p}" "${qpkg}" > "${qpkg_header_file}"
	if [ $? != 0 ]; then
		err_msg "failed to write header of ${qpkg} into $CS_DIR"
	fi

	local script_len=$(grep "${qpkg_header_file}" -e '^script_len=' | tr -dc '0-9')
	local content_size=${script_len}
	local offset_lines=$(grep "${qpkg_header_file}" -e '^offset=')
	while IFS= read -r line; do
		local offset=$(echo "${line}" | tr -dc '0-9')
		content_size=$((${content_size} + ${offset}))
	done <<< "${offset_lines}"
	echo "${content_size}"
}

# Retrieve data in network byte order.
network_order_32bit(){
	[ -n "$1" ] && [ -n "$2" ] || err_msg "internal error: network_order_32bit called with missing arguments"
	local off="$1"
	local qpkg="$2"
	[ -f $qpkg ] || err_msg "$qpkg: no such file"
	local word=$(/usr/bin/hexdump -s $off -n 1 -e '1/1 "%u"' $qpkg)
	word=$((word * 256))
	off=$((off + 1))
	word=$(((word + $(/usr/bin/hexdump -s $off -n 1 -e '1/1 "%u"' $qpkg)) * 256))
	off=$((off + 1))
	word=$(((word + $(/usr/bin/hexdump -s $off -n 1 -e '1/1 "%u"' $qpkg)) * 256))
	off=$((off + 1))
	word=$((word + $(/usr/bin/hexdump -s $off -n 1 -e '1/1 "%u"' $qpkg)))
	echo "$word"
}

# Retrieve location of QDK area.
get_qdk_area_pos(){
	[ -n "$1" ] || err_msg "internal error: get_qdk_area_pos called with no argument"
	local qpkg="$1"
	[ -f $qpkg ] || err_msg "$qpkg: no such file"
	local qdk_area="$(get_content_size $qpkg)"
	local qdk_string="$($CMD_DD if=$qpkg bs=$qdk_area skip=1 2>/dev/null | $CMD_DD bs=$QDK_AREA_TAG_LEN count=1 2>/dev/null)"
	if [ "$qdk_string" = "QDK" ]; then
		echo "$qdk_area"
		return 0
	fi
	return 1
}

# Retrieve location of specified data type in QDK area (if found)
get_qdk_area_data_pos(){
	[ -n "$1" ] && [ -n "$2" ] || err_msg "internal error: get_qdk_area_data_pos called with missing arguments"
	local data_type="$1"
	local qpkg="$2"
	[ -f $qpkg ] || err_msg "$qpkg: no such file"
	local qdk_area=
	qdk_area="$(get_qdk_area_pos $qpkg)" || return 1
	qdk_area="$(($qdk_area + $QDK_AREA_TAG_LEN))"

	# Traverse QDK area looking for specified data type. Stop if reaching the end
	# of the QDK area either by finding the QDK_AREA_EOF tag or by reaching the
	# tail data.
	local qdk_area_end="$(($(/bin/ls -l $qpkg | $CMD_AWK '{ print $5 }') - $TAIL_DATA_LEN))"
	local qdk_size=
	local qdk_pos=$qdk_area
	local qdk_type="$(/usr/bin/hexdump -s $qdk_area -n $QDK_AREA_DATA_TYPE_LEN -e '1/1 "%u"' $qpkg)"
	while [ $qdk_type -ne $data_type ] && [ $qdk_type -ne $QDK_AREA_EOF ] && (( $qdk_area <= $qdk_area_end ))
	do
		qdk_area="$(($qdk_area + $QDK_AREA_DATA_TYPE_LEN))"
		qdk_size="$(network_order_32bit $qdk_area $qpkg)"
		qdk_area="$(($qdk_area + $qdk_size + $QDK_AREA_DATA_SIZE_LEN))"
		qdk_pos=$qdk_area
		qdk_type="$(/usr/bin/hexdump -s $qdk_area -n $QDK_AREA_DATA_TYPE_LEN -e '1/1 "%u"' $qpkg)"
	done
	if [ $qdk_type -eq $data_type ]; then
		echo "$qdk_pos"
		return 0
	fi
	return 1
}

# Retrieve location of code signing digital signature (if found)
get_code_signing_pos(){
	[ -n "$1" ] || err_msg "internal error: get_code_signing_pos called with no argument"
	local qpkg="$1"
	[ -f $qpkg ] || err_msg "$qpkg: no such file"
	local qdk_pos=
	qdk_pos="$(get_qdk_area_data_pos $QDK_AREA_CODE_SIGNING $qpkg)" || return 1

	# The code signing digital signature is located after the data type and size data.
	echo "$(($qdk_pos + $QDK_AREA_DATA_TYPE_LEN + $QDK_AREA_DATA_SIZE_LEN))"
}

# Retrieve size of code signing digital signature (if found)
get_code_signing_len(){
	[ -n "$1" ] || err_msg "internal error: get_code_signing_len called with no argument"
	local qpkg="$1"
	[ -f $qpkg ] || err_msg "$qpkg: no such file"
	local qdk_pos=
	qdk_pos="$(get_qdk_area_data_pos $QDK_AREA_CODE_SIGNING $qpkg)" || return 1
	qdk_pos="$(($qdk_pos + $QDK_AREA_DATA_TYPE_LEN))"

	echo "$(network_order_32bit $qdk_pos $qpkg)"
}

# Verify code signing digital signature in a QPKG (new)
verify_code_signing(){
	local qpkg="$3"
	# Get ca cert
	local ca_cert_file="${CS_DIR_TMP}/file"
	local tmp_ca="${CS_DIR_TMP}/tmp"
	local verify_dgst_file="${CS_DIR_TMP}/verify"
	local ret=$CS_VERIFY_FAIL
	local ARR=("$CA_CERT_TEXT" "$CA_CERT3_TEXT" "$CA_CERT3_1_TEXT" "$CA_CERT_V2_TEXT" "$CA_CERT3_1_V2_TEXT")
	local errmsg="${CS_DIR_TMP}/errmsg"

	# Verify CA
	for ca_text in "${ARR[@]}"; do
		echo "${ca_text}" > $tmp_ca
		cat $tmp_ca | $CMD_SED '/^$/d' > $ca_cert_file
		openssl cms -verify -no_check_time -in $1 -CAfile $ca_cert_file 2>$errmsg > $verify_dgst_file
		$CMD_CMP $2 $verify_dgst_file 2>/dev/null
		local res=$?
		if [ $res -eq 0 ]; then
			msg "Code signing digital signature verification successful"
			ret=$SUCCESS
			break
		fi

		local err="$($CMD_AWK '$0 ~ /Verify error:/ {idx=match($0,/Verify error:/);print substr($0, idx)}' $errmsg)"
		if [ "$err" != "Verify error:unable to get local issuer certificate" ]; then
			msg "$err"
			break
		fi
	done

	if [ $ret -eq $CS_VERIFY_FAIL ]; then
		msg "Code signing digital signature verification failed"
	fi

	return $ret
}

print_certificate_info(){
	printf '\ncertificate_info:'
	local qpkg="$1"
	local signature_file="$2"

	local cert_info="${CS_DIR_TMP}/certInfo"
	local tmp_cert="${CS_DIR_TMP}/tmpCert"
	local tmp_signer="${CS_DIR_TMP}/tmpSigner"
	openssl cms -in $signature_file -cmsout -print >> $cert_info
	if [ $? -ne 0 ]; then
    	$CMD_ECHO "Failed to run: openssl cms -in $signature_file -cmsout -print >> $cert_info"
    fi	

	$CMD_AWK '$1 ~ /d\.certificate:/,/subject:/ {print $0}' $cert_info > $tmp_cert
	local print_cert_info="$($CMD_AWK '$1 ~ /issuer:|subject:|notBefore:|notAfter:/ {idx=match($0,/issuer:|subject:|notBefore:|notAfter:/);\
        if ($1 == "issuer:") {print ""} print substr($0, idx)}' $tmp_cert)"
	echo "$print_cert_info"

	$CMD_AWK '$1 ~ /signerInfos:/,/UTCTIME:/ {print $0}' $cert_info > $tmp_signer
	local signing_time="$($CMD_AWK '$1 ~ /UTCTIME:/ {print substr($0, 23)}' $tmp_signer)"
	printf '\n'
	echo 'signing_time:' $signing_time

	local tmp_date="${CS_DIR}/tmpDate"
	$CMD_AWK '$1 ~ /notAfter:/ {idx=match($0,/notAfter:/); if ($1 == "issuer:") {print ""} print substr($0, idx)}' $tmp_cert > $tmp_date
	$CMD_SED -i 's/notAfter: //' $tmp_date

	local now=$(date +%s)
	local expired="no"
	while read notAfter; do
		local not_after_date=$(date -d "$notAfter" +%s)
		if [ "$now" -ge "$not_after_date" ]; then
			expired="yes"
			break
		fi
	done < $tmp_date

	printf '\nexpired: %s\n' $expired
}

find_string_index(){
	local res=
	x="${1%%$2*}"
	[[ "$x" = "$1" ]] && res="-1" || res="${#x}"
	echo $res
}

qpkg_main(){
	local qpkg_size="$($CMD_LS -l "$1" | $CMD_AWK '{ print $5 }')"
	local skip_len="$((($qpkg_size - $CS_POSTREAD_BS) / $CS_POSTREAD_BS))"
	local qpkg_file="${CS_DIR}/qpkg"
	tr -d '\0' < $1 > $qpkg_file
	local cs_ds_string="$($CMD_DD if="$qpkg_file" bs=$CS_POSTREAD_BS skip=$skip_len 2>/dev/null | $CMD_GREP "QDK_offset=")"

	if [ "x$cs_ds_string" = "x" ]; then
		err_msg "does not find digital siganture section for $1"
	fi

	local cs_ds_pos=$(find_string_index "$cs_ds_string" "QDK_offset=")
	if [ "$cs_ds_pos" = "-1" ]; then
		err_msg "does not find digital siganture section for $1 2"
	fi

	cs_ds_pos=${cs_ds_string:$(($cs_ds_pos))}
	cs_ds_pos="$(echo $cs_ds_pos | $CMD_CUT -f 1 -d ' ')"

	local cs_qdk_tag_len=${#cs_ds_pos}
	cs_ds_pos="$(echo $cs_ds_pos | $CMD_CUT -f 2 -d '=')"
	local cs_ds_size=


	if [ -z $cs_ds_pos ] || [ -z $cs_qdk_tag_len ]; then
		err_msg "does not find digital siganture section for $1 3"
	else
		cs_ds_size="$(($qpkg_size - $cs_ds_pos - $cs_qdk_tag_len - $CS_QPKG_TAIL_DATA_LEN - 1))"
	fi


	local signature_file="${CS_DIR_TMP}/msg"

	if [ $cs_ds_size -le 0 ] || [ $cs_ds_size -ge $CS_DS_MAX_SIZE ]; then
		err_msg "digital signature size error for $1"
	fi

	skip_len="$(($cs_ds_pos + $cs_qdk_tag_len))"
	$CMD_DD if="$1" bs=1 skip=$skip_len count=$cs_ds_size 2>/dev/null > $signature_file

	local data_file=$(get_install_data $1 $cs_ds_pos)

	local dgst_file="${CS_DIR_TMP}/dgst"

	openssl dgst -sha1 -binary $data_file 2>/dev/null > $dgst_file
	if [ $? -ne 0 ]; then
    	$CMD_ECHO "Failed to run: openssl dgst -sha1 -binary $data_file 2>/dev/null > $dgst_file"
    fi	

	verify_code_signing ${signature_file} ${dgst_file} $1
	local ret=$?

	print_certificate_info $1 ${signature_file}

	return $ret
}

do_get_install_data(){
	local cs_qpkg_file="$1"
	local size="$2"
	local install_file="${CS_DIR}/data"
	local install_file1="${CS_DIR}/data1"
	local count="$(($size / $CS_READ_BS))"
	local rest="$(($size % $CS_READ_BS))"
	if [ $count -gt 0 ]; then
		$CMD_DD if="${cs_qpkg_file}" bs=$CS_READ_BS count=$count 2>/dev/null > $install_file
		if [ $? != 0 ]; then
			err_msg "space is not enough for $cs_qpkg_file"
		fi
	fi
	if [ $rest -gt 0 ]; then
		$CMD_DD if="${cs_qpkg_file}" bs=$CS_READ_BS skip=$count 2>/dev/null > $install_file1
		$CMD_DD if="${install_file1}" bs=$rest count=1 2>/dev/null >> $install_file
		if [ $? != 0 ]; then
			err_msg "space is not enough for $cs_qpkg_file 1"
		fi
	fi

	echo $install_file
}

get_install_data(){
	local cs_qpkg_file="$1"
	local cs_dos_pos="$2"
	local ret="$(($cs_dos_pos - 1))"
	if [ $ret -le 0 ]; then
		err_msg "install position small then zero for ${cs_qpkg_file}"
	fi
	do_get_install_data $cs_qpkg_file $ret
}

qdk_main(){
	local qpkg="$1"
	[ -f $qpkg ] || err_msg "$qpkg: no such file"

	local data_size=$(get_qdk_area_pos $qpkg) || \
		err_msg "Code signing verification failed: cannot find digital signature"
	local code_signing_pos=$(get_code_signing_pos $qpkg) || \
		err_msg "Code signing verification failed: cannot find digital signature"
	local code_signing_len=$(get_code_signing_len $qpkg) || \
		err_msg "Code signing verification failed: cannot find digital signature"

	if [ $code_signing_len -le 0 ] || [ $code_signing_len -ge $CS_DS_MAX_SIZE ]; then
		err_msg "digital signature size error for $1"
	fi

	local qpkg_data_file=$(do_get_install_data $qpkg $data_size)
	local dgst_file="${CS_DIR_TMP}/dgst"
	local signature_file="${CS_DIR_TMP}/msg"

	openssl dgst -sha1 -binary $qpkg_data_file 2>/dev/null > $dgst_file
	if [ $? -ne 0 ]; then
    	$CMD_ECHO "Failed to run: openssl dgst -sha1 -binary $qpkg_data_file 2>/dev/null > $dgst_file"
    fi
	$CMD_DD if=$qpkg bs=1 skip=$code_signing_pos count=$code_signing_len 2>/dev/null > $signature_file

	verify_code_signing ${signature_file} ${dgst_file} ${qpkg}
	local ret=$?

	print_certificate_info ${qpkg} ${signature_file}

	return $ret
}

check_file_type(){
	local ret="$($CMD_DD if="$1" bs=$CS_PREREAD_BS count=1 2>/dev/null | $CMD_GREP -c "${QDK_ARCH}")"
	if [ $ret -gt 0 ]; then
		CS_QPKG_TYPE=${CS_TYPE_QDK}
	else
		CS_QPKG_TYPE=${CS_TYPE_QPKG}
	fi
}

make_temp_dir(){
	local dir_name="$(dirname $1)"

	CS_DIR="$(${CMD_MKTEMP} -d $dir_name/tmp.XXXXXX 2>/dev/null)"
	CS_DIR_TMP="$(${CMD_MKTEMP} -d /tmp/tmp.XXXXXX 2>/dev/null)"
}

checkOpenSSLVer()
{
	local openssl_ver="$(openssl version | ${CMD_AWK} '{print $2}')"
	if [[ $openssl_ver < $LEGAL_OPEN_SSL_VER ]]; then
		echo "Please use this script on a machine with OpenSSL version 1.1 or above."
		cleanup_all $INVALID_OPENSSL_VERSION
	fi
}

usage()
{
	echo "Usage: $0 <qpkg file path>"
	cleanup_all $NOT_ENOUGH_ARGUMENT
}

[ $# -le 0 ] && usage

main(){
	printf '===== Start to verify and get digital signature info =====\n'
	local qbuild_verify_code_signing_file="$1"

	checkOpenSSLVer

	make_temp_dir $0

	check_file_type ${qbuild_verify_code_signing_file}
	printf 'qpkg type: %s\n' $CS_QPKG_TYPE

	local ret=$SUCCESS
	if [ $CS_QPKG_TYPE == $CS_TYPE_QPKG ]; then
		qpkg_main ${qbuild_verify_code_signing_file}
		ret=$?
	elif [ $CS_QPKG_TYPE == $CS_TYPE_QDK ]; then
		qdk_main ${qbuild_verify_code_signing_file}
		ret=$?
	else
		echo "error qpkg type = $CS_QPKG_TYPE"
		ret=$ERROR_QPKG_TYPE
	fi

	cleanup_all $ret
}

main "$@"
