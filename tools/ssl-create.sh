#!/bin/sh

#
# Copyright (C) 2015 Eaton
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#

#! \file   ssl-create.sh
#  \author Michal Hrusecky <MichalHrusecky@Eaton.com>
#  \author Jim Klimov <EvgenyKlimov@Eaton.com>
#  \brief  Initialize webserver X509 certificate
#  \details Prepares a new self-signed certificate if one is missing
#           or has expired or is not yet valid or is for another host.
#           Does not replace CA-issued certs, even if they seem invalid.

CN=""
FROM=""
TO=""
SIG="Autogenerated self-signed"

PEM_FINAL_CERT="/etc/tntnet/bios.pem"
PEM_TMP_KEY="/tmp/key.pem"
PEM_TMP_CERT="/tmp/cert.pem"

# Warn about expiration this much in advance, e.g. 45 days
WARN_EXPIRE="`expr 45 \* 24 \* 3600`"

TS_NOW="`TZ=UTC date -u +%s`"
LOCAL_HOSTNAME="`hostname -A | sort | head -1`"
BIOS_USER="admin"

if [ -s "${PEM_FINAL_CERT}" ]; then
    SSL_OUT="`openssl x509 -noout -dates -subject < "${PEM_FINAL_CERT}"`" && \
    { FROM="`echo "$SSL_OUT" | sed -n 's|notBefore=||p'`" && \
        [ -n "$FROM" ] && FROM="`TZ=UTC date -u -d "$FROM" +%s`"
      TILL="`echo "$SSL_OUT" | sed -n 's|notAfter=||p'`" && \
        [ -n "$TILL" ] && TILL="`TZ=UTC date -u -d "$TILL" +%s`" && \
        [ "$TILL" -gt "$WARN_EXPIRE" ] && TILL="`expr $TILL - $WARN_EXPIRE`"
      CN="`echo "$SSL_OUT" | sed -n 's|subject= /CN=||p'`" ; }
fi

if [ ! -r "${PEM_FINAL_CERT}" ] || [ -z "$FROM" ] || [ -z "$TILL" ] || \
   [ "$FROM" -gt "${TS_NOW}" ] || [ "$TILL" -lt "${TS_NOW}" ] || \
   [ "$CN" != "${LOCAL_HOSTNAME}" ] \
; then
    # Not to overwrite CA-issued certificate
    if [ -s "${PEM_FINAL_CERT}" ] && [ -z "`grep "$SIG" "${PEM_FINAL_CERT}" 2>/dev/null`" ]; then
        chown "${BIOS_USER}" "${PEM_FINAL_CERT}"        # Just in case
        exit 0
    fi

    # Generate self-signed cert with a new key and other data
    openssl req -x509 -newkey rsa:2048 \
        -keyout "${PEM_TMP_KEY}" -out "${PEM_TMP_CERT}" \
        -days 365 -nodes -subj "/CN=${LOCAL_HOSTNAME}" \
    || exit $?

    echo "$SIG" | \
        cat - "${PEM_TMP_KEY}" "${PEM_TMP_CERT}" > "${PEM_FINAL_CERT}" \
    || exit $?

    rm -f "${PEM_TMP_KEY}" "${PEM_TMP_CERT}"
    chown "${BIOS_USER}" "${PEM_FINAL_CERT}"
    exit $?
fi

exit 1
