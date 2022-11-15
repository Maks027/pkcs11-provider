#!/bin/bash -e
# Copyright (C) 2022 Simo Sorce <simo@redhat.com>
# SPDX-License-Identifier: Apache-2.0

source helpers.sh

if ! command -v certutil &> /dev/null
then
    echo "NSS's certutil command is required"
    exit 77
fi

title SECTION "Set up testing system"

TMPPDIR="tmp.softokn"
if [ -d ${TMPPDIR} ]; then
    rm -fr ${TMPPDIR}
fi
mkdir ${TMPPDIR}

PINVALUE="12345678"
PINFILE="${PWD}/pinfile.txt"
echo ${PINVALUE} > ${PINFILE}

#RANDOM data
SEEDFILE="${TMPPDIR}/noisefile.bin"
dd if=/dev/urandom of=${SEEDFILE} bs=2048 count=1 >/dev/null 2>&1
RAND64FILE="${TMPPDIR}/64krandom.bin"
dd if=/dev/urandom of=${RAND64FILE} bs=2048 count=32 >/dev/null 2>&1

# Create brand new tokens and certs
TOKDIR="$TMPPDIR/tokens"
if [ -d ${TOKDIR} ]; then
    rm -fr ${TOKDIR}
fi
mkdir ${TOKDIR}

SERIAL=0

title LINE "Creating new NSS Database"
certutil -N -d ${TOKDIR} -f ${PINFILE}

title LINE "Creating new Self Sign CA"
let "SERIAL+=1"
certutil -S -s "CN=Issuer" -n selfCA -x -t "C,C,C" \
    -m ${SERIAL} -1 -2 -5 --keyUsage certSigning,crlSigning \
    --nsCertType sslCA,smimeCA,objectSigningCA \
    -f ${PINFILE} -d ${TOKDIR} -z ${SEEDFILE} >/dev/null 2>&1 <<CERTSCRIPT
y

n
CERTSCRIPT

# RSA
TSTCRT="${TMPPDIR}/testcert"
title LINE  "Creating Certificate request for 'My Test Cert'"
certutil -R -s "CN=My Test Cert, O=PKCS11 Provider" -o ${TSTCRT}.req \
            -d ${TOKDIR} -f ${PINFILE} -z ${SEEDFILE} >/dev/null 2>&1
let "SERIAL+=1"
certutil -C -m ${SERIAL} -i ${TSTCRT}.req -o ${TSTCRT}.crt -c selfCA \
            -d ${TOKDIR} -f ${PINFILE} >/dev/null 2>&1
certutil -A -n testCert -i ${TSTCRT}.crt -t "u,u,u" -d ${TOKDIR} \
            -f ${PINFILE} >/dev/null 2>&1

KEYID=`certutil -K -d ${TOKDIR} -f ${PINFILE} |grep 'testCert'| cut -b 15-54`
URIKEYID=""
for (( i=0; i<${#KEYID}; i+=2 )); do
    line=`echo "${KEYID:$i:2}"`
    URIKEYID="$URIKEYID%$line"
done

BASEURIWITHPIN="pkcs11:id=${URIKEYID};pin-value=${PINVALUE}"
BASEURI="pkcs11:id=${URIKEYID}"
PUBURI="pkcs11:type=public;id=${URIKEYID}"
PRIURI="pkcs11:type=private;id=${URIKEYID}"

title LINE "RSA PKCS11 URIS"
echo "${BASEURIWITHPIN}"
echo "${BASEURI}"
echo "${PUBURI}"
echo "${PRIURI}"
echo ""

# ECC
ECCRT="${TMPPDIR}/eccert"
title LINE  "Creating Certificate request for 'My EC Cert'"
certutil -R -s "CN=My EC Cert, O=PKCS11 Provider" -k ec -q nistp256 \
            -o ${ECCRT}.req -d ${TOKDIR} -f ${PINFILE} -z ${SEEDFILE} >/dev/null 2>&1
let "SERIAL+=1"
certutil -C -m ${SERIAL} -i ${ECCRT}.req -o ${ECCRT}.crt -c selfCA \
            -d ${TOKDIR} -f ${PINFILE} >/dev/null 2>&1
certutil -A -n ecCert -i ${ECCRT}.crt -t "u,u,u" \
            -d ${TOKDIR} -f ${PINFILE} >/dev/null 2>&1

KEYID=`certutil -K -d ${TOKDIR} -f ${PINFILE} |grep 'ecCert'| cut -b 15-54`
URIKEYID=""
for (( i=0; i<${#KEYID}; i+=2 )); do
    line=`echo "${KEYID:$i:2}"`
    URIKEYID="$URIKEYID%$line"
done

ECBASEURI="pkcs11:id=${URIKEYID}"
ECPUBURI="pkcs11:type=public;id=${URIKEYID}"
ECPRIURI="pkcs11:type=private;id=${URIKEYID}"

title LINE  "Creating Certificate request for 'My Peer EC Cert'"
ECPEERCRT="${TMPPDIR}/ecpeercert"
certutil -R -s "CN=My Peer EC Cert, O=PKCS11 Provider" \
            -k ec -q nistp256 -o ${ECPEERCRT}.req \
            -d ${TOKDIR} -f ${PINFILE} -z ${SEEDFILE} >/dev/null 2>&1
let "SERIAL+=1"
certutil -C -m ${SERIAL} -i ${ECPEERCRT}.req -o ${ECPEERCRT}.crt \
            -c selfCA -d ${TOKDIR} -f ${PINFILE} >/dev/null 2>&1
certutil -A -n ecPeerCert -i ${ECPEERCRT}.crt -t "u,u,u" \
            -d ${TOKDIR} -f ${PINFILE} >/dev/null 2>&1

KEYID=`certutil -K -d ${TOKDIR} -f ${PINFILE} |grep 'ecPeerCert'| cut -b 15-54`
URIKEYID=""
for (( i=0; i<${#KEYID}; i+=2 )); do
    line=`echo "${KEYID:$i:2}"`
    URIKEYID="$URIKEYID%$line"
done

ECPEERBASEURI="pkcs11:id=${URIKEYID}"
ECPEERPUBURI="pkcs11:type=public;id=${URIKEYID}"
ECPEERPRIURI="pkcs11:type=private;id=${URIKEYID}"

title LINE "EC PKCS11 URIS"
echo "${ECBASEURI}"
echo "${ECPUBURI}"
echo "${ECPRIURI}"
echo "${ECPEERBASEURI}"
echo "${ECPEERPUBURI}"
echo "${ECPEERPRIURI}"
echo ""

title PARA "Show contents of softoken"
echo " ----------------------------------------------------------------------------------------------------"
certutil -L -d ${TOKDIR}
certutil -K -d ${TOKDIR} -f ${PINFILE}
echo " ----------------------------------------------------------------------------------------------------"

title LINE "Export tests variables to ${TMPPDIR}/testvars"
BASEDIR=$(pwd)
cat > ${TMPPDIR}/testvars <<DBGSCRIPT
export PKCS11_PROVIDER_DEBUG="file:${BASEDIR}/${TMPPDIR}/p11prov-debug.log"
export PKCS11_PROVIDER_MODULE="${SOFTOKNPATH}/libsoftokn3.so"
export OPENSSL_CONF="${BASEDIR}/openssl.cnf"

export TOKDIR="${BASEDIR}/${TOKDIR}"
export TMPPDIR="${BASEDIR}/${TMPPDIR}"
export PINVALUE="${PINVALUE}"
export PINFILE="${BASEDIR}/${PINFILE}"
export SEEDFILE="${BASEDIR}/${TMPPDIR}/noisefile.bin"
export RAND64FILE="${BASEDIR}/${TMPPDIR}/64krandom.bin"

export BASEURIWITHPIN="${BASEURIWITHPIN}"
export BASEURI="${BASEURI}"
export PUBURI="${PUBURI}"
export PRIURI="${PRIURI}"
export ECBASEURI="${ECBASEURI}"
export ECPUBURI="${ECPUBURI}"
export ECPRIURI="${ECPRIURI}"
export ECPEERBASEURI="${ECPEERBASEURI}"
export ECPEERPUBURI="${ECPEERPUBURI}"
export ECPEERPRIURI="${ECPEERPRIURI}"
DBGSCRIPT

title ENDSECTION
