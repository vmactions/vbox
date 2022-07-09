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
  sudo vboxmanage  startvm netbsd --type headless
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


#osname
screenText() {
  _osname="$1"
  
  if [ -z "$_osname" ]; then
    echo "Usage: screenText netbsd"
    return 1
  fi

  _png="$_osname.scr.png"
  sudo vboxmanage controlvm $_osname screenshotpng  $_png
  sudo chmod 666 $_png
  
  pytesseract $_png

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
  eval "$*"
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


#osname
key_g() {
  _osname="${1:-$VM_OS_NAME}"
  
  if [ -z "$_osname" ]; then
    echo "Usage: key_g netbsd"
    return 1
  fi
  sudo vboxmanage controlvm $_osname keyboardputscancode 22 a2
}





"$@"



