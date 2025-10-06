#!/bin/bash

# add-ssh (kemaskini untuk integrasi auto-delete expired users)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/sbin:/usr/bin:/bin:$PATH"

MYIP=$(curl -sS ipv4.icanhazip.com)
creditt=$(cat /root/provided 2>/dev/null || echo "Unknown")
box=$(cat /etc/box 2>/dev/null || echo "47")
line=$(cat /etc/line 2>/dev/null || echo "47")
back_text=$(cat /etc/back 2>/dev/null || echo "47")

clear
echo -e "  \e[$line═══════════════════════════════════════════════════════\e[m"
echo -e "  \e[$back_text             \e[30m[\e[$box CREATE USER SSH & OPENVPN\e[30m ]\e[1m             \e[m"
echo -e "  \e[$line═══════════════════════════════════════════════════════\e[m"

# Periksa useradd ada atau tidak
if ! command -v useradd >/dev/null 2>&1; then
  echo "useradd tidak dijumpai. Sila pasang pakej yang sesuai (passwd/adduser)."
  exit 1
fi

while true; do
  read -p "   Username : " Login
  if [ -z "$Login" ]; then
    echo "   Nama pengguna kosong. Sila cuba lagi."
    continue
  fi
  if id -u "$Login" >/dev/null 2>&1; then
    echo "   Username '$Login' sudah wujud. Sila masukkan username lain."
    continue
  fi
  if ! [[ "$Login" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "   Username mengandungi aksara tidak dibenarkan. Benarkan: A-Z a-z 0-9 . _ -"
    continue
  fi
  break
done

read -p "   Password : " Pass
read -p "   Expired (days): " masaaktif

# Fallback for IP/domain detection
IP=$(wget -qO- icanhazip.com 2>/dev/null || echo "")
source /var/lib/premium-script/ipvps.conf 2>/dev/null || true
if [[ -z "$IP" ]] && [[ -z "$domain" ]]; then
  domain=$(cat /usr/local/etc/xray/domain 2>/dev/null || echo "$MYIP")
else
  domain=${IP:-$domain}
fi

# gather ports/services (best-effort, keep original logic)
ssl=$(grep -w "Stunnel4" ~/log-install.txt 2>/dev/null | cut -d: -f2 | xargs)
sqd=$(grep -w "Squid" ~/log-install.txt 2>/dev/null | cut -d: -f2 | xargs)
ovpn=$(netstat -nlpt 2>/dev/null | grep -i openvpn | grep -i 0.0.0.0 | awk '{print $4}' | cut -d: -f2 | head -n1)
ovpn2=$(netstat -nlpu 2>/dev/null | grep -i openvpn | grep -i 0.0.0.0 | awk '{print $4}' | cut -d: -f2 | head -n1)
ovpn3=$(grep -w "OHP OpenVPN" ~/log-install.txt 2>/dev/null | cut -d: -f2 | sed 's/ //g')
ovpn4=$(grep -w "OpenVPN SSL" ~/log-install.txt 2>/dev/null | cut -d: -f2 | sed 's/ //g')
ohpssh=$(grep -w "OHP SSH" ~/log-install.txt 2>/dev/null | cut -d: -f2 | sed 's/ //g')
ohpdrop=$(grep -w "OHP Dropbear" ~/log-install.txt 2>/dev/null | cut -d: -f2 | sed 's/ //g')
wsdropbear=$(grep -w "Websocket SSH(HTTP)" ~/log-install.txt 2>/dev/null | cut -d: -f2 | sed 's/ //g')
wsstunnel=$(grep -w "Websocket SSL(HTTPS)" ~/log-install.txt 2>/dev/null | cut -d: -f2 | sed 's/ //g')
wsovpn=$(grep -w "Websocket OpenVPN" ~/log-install.txt 2>/dev/null | cut -d: -f2 | sed 's/ //g')

sleep 1
echo "Ping Host"
echo "Check Access..."
sleep 0.5
echo "Permission Accepted"
clear
sleep 0.5
echo "Create Acc: $Login"
sleep 0.5
echo "Setting Password: $Pass"
sleep 0.5
clear

harini=$(date -d "0 days" +"%Y-%m-%d")
useradd_expire_date=$(date -d "$masaaktif days" +"%Y-%m-%d")

# create user (no home, shell false)
# we keep -M if you don't want a home created; change if you want /home created
/usr/sbin/useradd -e "$useradd_expire_date" -s /bin/false -M "$Login"

# Ensure password is set
echo -e "$Pass\n$Pass" | passwd "$Login" &> /dev/null || { echo "Failed to set password for $Login"; }

# ---- NEW: ensure expiry is stored correctly in /etc/shadow (use chage)
if command -v chage >/dev/null 2>&1; then
  # chage -E accepts YYYY-MM-DD; it will set the shadow expiry field properly
  chage -E "$useradd_expire_date" "$Login" 2>/dev/null || echo "Warning: chage failed to set expiry for $Login"
else
  echo "Warning: chage not found; remove-expired script expects expiry field in /etc/shadow." >&2
fi

# Also write a short record to /usr/local/bin/alluser so remove script can see it (same format)
tglexp="$(date -d "$useradd_expire_date" '+%d %b %Y' 2>/dev/null || echo "$useradd_expire_date")"
mkdir -p /usr/local/bin 2>/dev/null
echo "Expired- User : $Login Expire at : $tglexp" >> /usr/local/bin/alluser

# For display, try to get chage output
exp=$(chage -l "$Login" 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}' || echo "$tglexp")

echo ""
echo -e "Informasi Account SSH & OpenVPN"
echo -e "\e[$line═════════════════════════════════\e[m"
echo -e "Username       : $Login"
echo -e "Password       : $Pass"
echo -e "\e[$line═════════════════════════════════\e[m"
echo -e "Domain         : $domain"
echo -e "IP/Host        : $MYIP"
echo -e "OpenSSH        : 22"
echo -e "Dropbear       : 442, 109"
echo -e "SSL/TLS        : $ssl"
echo -e "WS SSH(HTTP)   : $wsdropbear"
echo -e "WS SSL(HTTPS)  : $wsstunnel"
echo -e "WS OpenVPN     : $wsovpn"
echo -e "OHP Dropbear   : $ohpdrop"
echo -e "OHP OpenSSH    : $ohpssh"
echo -e "OHP OpenVPN    : $ovpn3"
echo -e "Port Squid     : $sqd"
echo -e "Badvpn(UDPGW)  : 7100-7300"
echo -e "\e[$line═════════════════════════════════\e[m"
echo -e "CONFIG OPENVPN"
echo -e "--------------"
echo -e "OpenVPN TCP : $ovpn http://$MYIP:81/client-tcp-$ovpn.ovpn"
echo -e "OpenVPN UDP : $ovpn2 http://$MYIP:81/client-udp-$ovpn2.ovpn"
echo -e "OpenVPN SSL : $ovpn4 http://$MYIP:81/client-tcp-ssl.ovpn"
echo -e "OpenVPN OHP : $ovpn3 http://$MYIP:81/client-tcp-ohp1194.ovpn"
echo -e "\e[$line═════════════════════════════════\e[m"
echo -e "PAYLOAD WEBSOCKET 1 : GET / HTTP/1.1[crlf]Host: bug.com.$domain[crlf]Upgrade: websocket[crlf][crlf]"
echo -e "\e[$line═════════════════════════════════\e[m"
echo -e "PAYLOAD WEBSOCKET 2 : GET wss://bug.com/ HTTP/1.1[crlf]Host: bug.com.$domain[crlf]Upgrade: websocket[crlf]Connection: Keep-Alive[crlf][crlf]"
echo -e ""
echo -e "----------------------"
echo -e "Created  : $harini"
echo -e "Expired  : $useradd_expire_date"
echo -e "----------------------"
echo -e "Script By $creditt"
