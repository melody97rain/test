#!/bin/bash
read -p " Username :  " User
egrep "^$User" /etc/passwd >/dev/null
if [ $? -eq 0 ]; then
  read -p "         Day Extend     :  " Days

  # Dapatkan tarikh luput semasa pengguna
  Current_Expire=$(chage -l $User | grep 'Account expires' | cut -d: -f2 | xargs)

  if [[ "$Current_Expire" == "never" ]]; then
    Today=$(date +%s)
  else
    # Tukar tarikh luput kepada epoch (saat sejak 1970)
    Current_Expire=$(date -d "$Current_Expire 23:59:59" +%s)
    Now=$(date +%s)
    # Jika tarikh luput lama daripada sekarang, mula kira dari sekarang
    if [ $Current_Expire -lt $Now ]; then
      Today=$Now
    else
      Today=$Current_Expire
    fi
  fi

  Days_Detailed=$(( Days * 86400 ))
  Expire_On=$(( Today + Days_Detailed ))
  Expiration=$(date -u --date="1970-01-01 $Expire_On sec GMT" +%Y/%m/%d)
  Expiration_Display=$(date -u --date="1970-01-01 $Expire_On sec GMT" '+%d %b %Y')
  
  passwd -u $User
  usermod -e $Expiration $User

  echo -e ""
  echo -e "========================================"
  echo -e ""
  echo -e "    Username        :  $User"
  echo -e "    Days Added      :  $Days Days"
  echo -e "    Expires on      :  $Expiration_Display"
  echo -e ""
  echo -e "========================================"
else
  clear
  echo -e ""
  echo -e "======================================"
  echo -e ""
  echo -e "        Username Doesnt Exist         "
  echo -e ""
  echo -e "======================================"
fi
