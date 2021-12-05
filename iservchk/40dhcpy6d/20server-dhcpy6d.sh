#!/bin/bash

. /usr/lib/iserv/cfg

if ! dpkg-query -Wf '${Status}' iserv-portal 2>/dev/null | grep -qE '^(install|hold) ok (unpacked|installed)$' || { [[ ${#DHCP} -gt 0 ]] && netquery6 -gulq; }
then
cat <<EOT
# See https://github.com/HenriWahl/dhcpy6d/issues/49
Test "restart once to fix volatile.sqlite log spam"
  grep -qx 20server-dhcpy6d_restart /var/lib/iserv/config/update.log
  ---
  systemctl try-restart dhcpy6d &&
      echo 20server-dhcpy6d_restart >> /var/lib/iserv/config/update.log

Test "generate duid"
  [ -s "/var/lib/iserv/server-dhcpy6d/duid" ]
  ---
  dhcpy6d --generate-duid > /var/lib/iserv/server-dhcpy6d/duid

Check /etc/default/dhcpy6d
Check /etc/dhcpy6d.conf

Start dhcpy6d dhcpy6d

EOT
else
  cat <<EOT
Remove /etc/dhcpy6d.conf

Stop dhcpy6d dhcpy6d

EOT
fi
echo

