#!/usr/bin/env bash

set -e





setup() {
  brew install tesseract
  pip3 install pytesseract

}





#isolink  osname  ostype sshport
createVM() {
  _isolink="$1"
  _osname="$2"
  _ostype="$3"
  _sshport="$4"
  
  if [ -z "$_osname" ]; then
    echo "Usage: createVM  isolink  osname  ostype  sshport"
    echo "Usage: createVM  'https://xxxxx.com/xxx.iso'   netbsd   NetBSD_64  2225"
    return 1
  fi

  _vdi="$_osname.vdi"
  _iso="$_osname.iso"

  if [ ! -e "$_iso" ]; then
   wget -O $_iso "$_isolink"
  fi
   
  sudo vboxmanage  createhd --filename $_vdi --size 100000

  sudo vboxmanage  createvm  --name  $_osname --ostype  $_ostype  --default   --basefolder $_osname --register

  sudo vboxmanage  storageattach  $_osname   --storagectl IDE --port 0  --device 1  --type hdd --medium $_vdi

  sudo vboxmanage  storageattach  $_osname   --storagectl IDE --port 0  --device 0  --type dvddrive  --medium  $_iso



  sudo vboxmanage  modifyvm $_osname --boot1 dvd --boot2 disk --boot3 none --boot4 none


  sudo vboxmanage  modifyvm $_osname   --vrde on  --vrdeport 3390

  sudo vboxmanage  modifyvm  $_osname  --natpf1 "guestssh,tcp,,$_sshport,,22"

}


#osname
startVM() {
  _osname="$1"
  
  if [ -z "$_osname" ]; then
    echo "Usage: startVM netbsd"
    return 1
  fi
  sudo vboxmanage  startvm $_osname --type headless
}


#osname  optsfile
processOpts() {
  _osname="$1"
  _optsfile="$2"

  if [ -z "$_optsfile" ]; then
    echo "Usage: processOpts netbsd netbsd.9.2.opts.txt"
    return 1
  fi

  while read -r line; do
  if [ -z "$(echo "$line" | tr -d '# ' )" ]; then
    continue
  fi
  if echo "$line" | grep "^#" >/dev/null ; then
    continue
  fi
  echo $line
  _text="$(echo "$line" | cut -d '|' -f 1   | xargs)"
  _keys="$(echo "$line" | cut -d '|' -f 2- )"
  echo "Text: $_text"
  echo "Keys: $_keys"
  waitForText "$_osname" "$_text"
  input "$_osname" "$_keys"

  sleep 1
done <"$_optsfile"


}


#osname
clearVM() {
  _osname="$1"
  
  if [ -z "$_osname" ]; then
    echo "Usage: clearVM netbsd"
    return 1
  fi

  sudo vboxmanage  controlvm $_osname poweroff

  sudo vboxmanage unregistervm $_osname --delete

  sudo rm -fr ~/"VirtualBox VMs/$_osname"

  rm ~/.ssh/known_hosts

}

#osname
shutdownVM() {
  _osname="$1"
  
  if [ -z "$_osname" ]; then
    echo "Usage: shutdownVM netbsd"
    return 1
  fi

  sudo vboxmanage  controlvm $_osname poweroff soft
  sleep 2
}



detachISO() {
  _osname="$1"
  
  if [ -z "$_osname" ]; then
    echo "Usage: detachISO netbsd"
    return 1
  fi
  
  sudo vboxmanage storageattach  $_osname  --storagectl IDE --port 0  --device 0  --type dvddrive  --medium none

}


#osname [img]
screenText() {
  _osname="$1"
  _img="$2"
  
  if [ -z "$_osname" ]; then
    echo "Usage: screenText netbsd"
    return 1
  fi

  _png="${_img:-$_osname.png}"
  while ! sudo vboxmanage controlvm $_osname screenshotpng  $_png  >/dev/null 2>&1; do
    #echo "screenText error, lets just wait"
    sleep 3
  done
  sudo chmod 666 $_png
  
  if [ -z "$_img" ]; then
    pytesseract $_png
  else
    pytesseract $_png >screen.txt

    echo '<!DOCTYPE html>
<html>
<head>
<title>VMActions.org</title>
<meta http-equiv="refresh" content="1">
</head>
<body onclick="stop()">

<img src="screen.png" alt="Screen">

<br>
<pre>
' >index.html
    cat screen.txt >>index.html
    echo '</pre></body></html>' >>index.html

  fi


}


#osname text  [timeout secs]
waitForText() {
  _osname="$1"
  _text="$2"
  _sec="$3"

  if [ -z "$_text" ]; then
    echo "Usage: waitForText netbsd text"
    return 1
  fi
  echo "Waiting for text: $_text"
  _t=0
  while [ -z "$_sec" ] || [ $_t -lt $_sec ]; do
    sleep 1
    _screenText="$(screenText $_osname)"
    echo "$_screenText"
    if echo "$_screenText" | grep -- "$_text" >/dev/null; then
      echo "OK, found."
      break;
    fi
    _t=$((_t + 1))
  done

}



startCF() {
  _http_port="$1"

  if [ -z "$_http_port" ]; then
    _http_port=8000
    echo "Using default port 8000"
  fi



  NGROK_MAC="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64.tgz"
  NGROK_Linux="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
  NGROK_Win="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
    
    


  link="$NGROK_Win"

  cloudflared="./cloudflared"

  log="./cf.log"

  protocol=http
  port=$_http_port

  if uname -a | grep -i "darwin"; then
    if [ ! -e "$cloudflared" ]; then
      link="$NGROK_MAC"
      echo "Using link: $link"
      wget -O cloudflared.tgz "$link"
      tar xzf cloudflared.tgz
      chmod +x cloudflared
    fi
  elif uname -a | grep -i "linux"; then
    if [ ! -e "$cloudflared" ]; then
      link="$NGROK_Linux"
      wget -O cloudflared "$link"
      chmod +x cloudflared
    fi
  else
    link="$NGROK_Win"
    echo "not implementd for Windows yet"
    exit 1
    cloudflared="$cloudflared.exe"
  fi



  if ! ${cloudflared} update; then 
    echo ok;
  fi


  ${cloudflared} tunnel --url ${protocol}://localhost:${port} >${log} 2>&1 &


  while ! grep "registered connIndex=" ${log}; do
    echo "waiting for the tunnel"
    sleep 2
  done


  domain="$(cat "${log}" | grep https:// | grep trycloudflare.com | head -1 | cut -d '|' -f 2 | tr -d ' ' | cut -d '/' -f 3)"

  echo "================================="
  echo ""
  echo ""
  echo "Please visit:  https://$domain"
  echo ""
  echo ""
  echo "================================="

}


startWeb() {
  _osname="$1"

  if [ -z "$_osname" ]; then
    echo "Usage: startWeb netbsd"
    return 1
  fi

  python3 -m http.server >/dev/null 2>&1 &
  if ! [ -e "index.html" ]; then
    echo '<!DOCTYPE html>
<html>
<head>
<title>VMActions.org</title>
<meta http-equiv="refresh" content="1">
</head>
<body>

<h1>Please just wait....<h1>

</body>
</html>' >index.html
  fi

  (while true; do screenText "$_osname" "screen.png"; done)&

}


exportOVA() {
  _osname="$1"
  _ova="$2"
  if [ -z "$_ova" ]; then
    echo "Usage: exportOVA netbsd netbsd.9.2.ova"
    return 1
  fi

  sudo vboxmanage export $_osname --output "$_ova"

  sudo chmod +r "$_ova"
}


#osname port 
addSSHHost() {
  _osname="$1"
  _port="$2"
  if [ -z "$_port" ]; then
    echo "Usage: addSSHHost netbsd 2225"
    return 1
  fi
  if [ ! -e ~/.ssh/id_rsa ] ; then 
    ssh-keygen -f  ~/.ssh/id_rsa -q -N "" 
  fi

  echo "
Host $_osname
  User root
  Port $_port
  HostName localhost

StrictHostKeyChecking=accept-new


  " >>~/.ssh/config


}


inputFile() {
  _osname="$1"
  _file="$2"

  if [ -z "$_file" ]; then
    echo "Usage: inputFile netbsd file.txt"
    return 1
  fi

  sudo vboxmanage controlvm $_osname keyboardputfile  "$_file"

}


#keys splitted by ;
#eg:  enter
#eg:  down; enter
#eg:  down; up; tab; enter

input() {
  _osname="$1"
  
  if [ -z "$_osname" ]; then
    echo "Usage: input netbsd enter"
    return 1
  fi
  shift
  (
  export VM_OS_NAME=$_osname
  eval "$*"
  )
}


string() {
  _osname="$VM_OS_NAME"
  if [ -z "$_osname" ]; then
    _osname=$1
    shift
  fi
  if [ -z "$_osname" ]; then
    echo "Usage: string netbsd"
    return 1
  fi
  
  sudo vboxmanage controlvm $_osname  keyboardputstring  "$1"
}


#https://www.win.tue.nl/~aeb/linux/kbd/scancodes-1.html

#press down  up :   scancode   (0x80|scancode)
#example:
#  enter scancode=0x1c
#  enter  down = 0x1c
#  enter  up   = 0x9c



#osname
enter() {
  _osname="${1:-$VM_OS_NAME}"
  
  if [ -z "$_osname" ]; then
    echo "Usage: enter netbsd"
    return 1
  fi
  sudo vboxmanage controlvm $_osname keyboardputscancode 1c 9c
}


#osname
tab() {
  _osname="${1:-$VM_OS_NAME}"
  
  if [ -z "$_osname" ]; then
    echo "Usage: tab netbsd"
    return 1
  fi
  sudo vboxmanage controlvm $_osname keyboardputscancode 0f 8f
}

#osname
f2() {
  _osname="${1:-$VM_OS_NAME}"
  
  if [ -z "$_osname" ]; then
    echo "Usage: f2 netbsd"
    return 1
  fi
  sudo vboxmanage controlvm $_osname keyboardputscancode 3c bc
}


#osname
down() {
  _osname="${1:-$VM_OS_NAME}"
  
  if [ -z "$_osname" ]; then
    echo "Usage: down netbsd"
    return 1
  fi
  sudo vboxmanage controlvm $_osname keyboardputscancode 50 d0
}







"$@"



