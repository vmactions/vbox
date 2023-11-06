#!/usr/bin/env bash

set -e



export PATH=$PATH:/Library/Frameworks/Python.framework/Versions/Current/bin




isLinux() {
  uname -a | grep -i "Linux" >/dev/null
}


_SUDO_VIR_=""
if isLinux; then
  _SUDO_VIR_=sudo
fi



setup() {
  if isLinux; then
    sudo apt-get update
    sudo apt-get install   -y    libvirt-daemon-system   virt-manager qemu-kvm  libosinfo-bin  axel

    sudo apt-get install  -y tesseract-ocr python3-pil tesseract-ocr-eng tesseract-ocr-script-latn  python3-pip
    pip3 install pytesseract vncdotool

  else
    brew install tesseract libvirt qemu  virt-manager axel
    brew services start libvirt
    pip3 install pytesseract
    echo "Reloading sshd services in the Host"
    sudo sh <<EOF
    echo "" >>/etc/ssh/sshd_config
    echo "StrictModes no" >>/etc/ssh/sshd_config
EOF
    sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist
    sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist

  fi
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  sudo chmod o+rx $HOME
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
   echo "Downloading: $_isolink"
   axel -n 8 -o $_iso "$_isolink"
   if echo "$_isolink" | grep 'bz2$'; then
     mv "$_iso" "$_iso.bz2"
     bzip2 -dc "$_iso.bz2" >"$_iso"
   fi
  fi
   
  sudo vboxmanage  createhd --filename $_vdi --size 100000

  sudo vboxmanage  createvm  --name  $_osname --ostype  $_ostype  --default   --basefolder $_osname --register

  sudo vboxmanage  storageattach  $_osname   --storagectl IDE --port 0  --device 1  --type hdd --medium $_vdi

  sudo vboxmanage  storageattach  $_osname   --storagectl IDE --port 0  --device 0  --type dvddrive  --medium  $_iso



  sudo vboxmanage  modifyvm $_osname --boot1 dvd --boot2 disk --boot3 none --boot4 none


  sudo vboxmanage  modifyvm $_osname   --vrde on  --vrdeport 3390

  sudo vboxmanage  modifyvm  $_osname  --natpf1 "guestssh,tcp,,$_sshport,,22"

  setCPU "$_osname" 2
}


#osname  ostype sshport
createVMFromVHD() {
  _osname="$1"
  _ostype="$2"
  _sshport="$3"
  
  if [ -z "$_osname" ]; then
    echo "Usage: createVMFromVHD  osname  ostype  sshport"
    echo "Usage: createVMFromVHD  freebsd   freebsd13.1  2222"
    return 1
  fi


  _vhd="$_osname.qcow2"

  sudo qemu-img resize $_vhd  +200G

  $_SUDO_VIR_ virt-install \
  --name $_osname \
  --memory 4096 \
  --vcpus 2 \
  --disk $_vhd,format=qcow2,bus=virtio \
  --os-variant=$_ostype \
  --network network=default,model=virtio \
  --graphics vnc,listen=0.0.0.0 \
  --noautoconsole  --import

  $_SUDO_VIR_  virsh  shutdown $_osname
  $_SUDO_VIR_  virsh  destroy $_osname

}





#ova
importVM() {
  _osname="$1"
  _ostype="$2"
  _ova="$3"
  if [ -z "$_ova" ]; then
    echo "Usage: importVM xxxx.ova"
    return 1
  fi
  $_SUDO_VIR_  virt-install \
  --name $_osname \
  --memory 4096 \
  --vcpus 2 \
  --disk $_ova,format=qcow2,bus=virtio \
  --os-variant=$_ostype \
  --network network=default,model=virtio \
  --graphics vnc,listen=0.0.0.0 \
  --noautoconsole  --import  --check all=off

  $_SUDO_VIR_  virsh  shutdown $_osname
  $_SUDO_VIR_  virsh  destroy $_osname
}

#osname
startVM() {
  _osname="$1"
  
  if [ -z "$_osname" ]; then
    echo "Usage: startVM netbsd"
    return 1
  fi
  $_SUDO_VIR_  virsh  start  $_osname 
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
  echo "====> $line"
  _text="$(echo "$line" | cut -d '|' -f 1   | xargs)"
  _keys="$(echo "$line" | cut -d '|' -f 2 )"
  _timeout="$(echo "$line" | cut -d '|' -f 3 )"
  echo "========> Text:    $_text"
  echo "========> Keys:    $_keys"
  echo "========> Timeout: $_keys"
  if waitForText "$_osname" "$_text" "$_timeout"; then
    input "$_osname" "$_keys"
  else
    echo "Timeout for waiting for text: $_text"
  fi

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
  if $_SUDO_VIR_  virsh list | grep $_osname; then
    $_SUDO_VIR_  virsh  shutdown $_osname
    $_SUDO_VIR_  virsh  destroy $_osname
    $_SUDO_VIR_  virsh  undefine $_osname  --remove-all-storage
  fi

  rm ~/.ssh/known_hosts

}

#osname
shutdownVM() {
  _osname="$1"
  
  if [ -z "$_osname" ]; then
    echo "Usage: shutdownVM netbsd"
    return 1
  fi

  $_SUDO_VIR_  virsh  shutdown  $_osname
  sleep 2
}



detachISO() {
  _osname="$1"
  
  if [ -z "$_osname" ]; then
    echo "Usage: detachISO netbsd"
    return 1
  fi
  
  echo "detachISO  not implemented"

}

attachISO() {
  _osname="$1"
  _iso="$2"
  
  if [ -z "$_iso" ]; then
    echo "Usage: attachISO netbsd  netbsd.iso"
    return 1
  fi

  echo "attachISO  not implemented"

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
  while ! vncdotool capture  temp.$_png  >/dev/null 2>&1; do
    #echo "screenText error, lets just wait"
    sleep 3
  done
  rm -rf $_png
  sudo chmod 666 temp.$_png
  mv temp.$_png  $_png

  if [ -z "$_img" ]; then
    pytesseract $_png
  else
    pytesseract $_png >screen.txt

    echo "<!DOCTYPE html>
<html>
<head>
<title>$_osname</title>
<meta http-equiv='refresh' content='1'>
</head>
<body onclick='stop()' style='background-color:grey;'>

<img src='screen.png' alt='Screen'>

<br>
<pre>
" >index.html
    cat screen.txt >>index.html
    echo '</pre></body></html>' >>index.html

  fi


}


#osname text  [timeout secs] [hook]
waitForText() {
  _osname="$1"
  _text="$2"
  _sec="$3"
  _hook="$4"

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
      echo "====> OK, found: $_text"
      return 0
    fi
    _t=$((_t + 1))
    $_hook
  done
  return 1 #timeout
}


startWeb() {
  _osname="$1"

  if [ -z "$_osname" ]; then
    echo "Usage: startWeb netbsd"
    return 1
  fi

  python3 -m http.server >/dev/null 2>&1 &
  if ! [ -e "index.html" ]; then
    echo "<!DOCTYPE html>
<html>
<head>
<title>$_osname</title>
<meta http-equiv='refresh' content='1'>
</head>
<body style='background-color:grey;'>

<h1>Please just wait....<h1>

</body>
</html>" >index.html
  fi

  (while true; do screenText "$_osname" "screen.png"; done)&

}


exportOVA() {
  _osname="$1"
  _ova="$2"
  if [ -z "$_ova" ]; then
    echo "Usage: exportOVA netbsd netbsd.9.2.qcow2"
    return 1
  fi

  _sor="$($_SUDO_VIR_  virsh domblklist $_osname | grep -E -o '/.*qcow2')"

  sudo cp  $_sor "$_ova"

  sudo xz -z "$_ova" -k -T 0

  sudo chmod +r "$_ova.xz"
}


#osname [_idfile]
addSSHHost() {
  _osname="$1"
  _idfile="$2"

  if [ ! -e ~/.ssh/id_rsa ] ; then 
    ssh-keygen -f  ~/.ssh/id_rsa -q -N "" 
  fi

  _ip="$(getVMIP $_osname)"

  echo "
StrictHostKeyChecking=accept-new
SendEnv   CI  GITHUB_* 

Host $_osname
  User root
  HostName $_ip
" >>~/.ssh/config

  if [ "$_idfile" ]; then
    echo "  IdentityFile=$_idfile
" >>~/.ssh/config
  fi


}


#pbk
addSSHAuthorizedKeys() {
  _pbk="$1"
  if [ -z "$_pbk" ]; then
    echo "Usage: addSSHAuthorizedKeys id_rsa.pub"
    return 1
  fi
  
  cat "$_pbk" >> $HOME/.ssh/authorized_keys
  
  chmod 600 $HOME/.ssh/authorized_keys

}


#osname protocol hostPort vmPort
addNAT() {
  _osname="$1"
  _proto="$2"
  _hostPort="$3"
  _vmPort="$4"
  if [ -z "$_vmPort" ]; then
    echo "Usage: addNAT osname protocol hostPort vmPort"
    return 1
  fi
  echo "addNAT  not implemented"

}


#osname  memsize
setMemory() {
  _osname="$1"
  _memsize="$2"
  if [ -z "$_memsize" ]; then
    echo "Usage: setMemory osname 2048"
    return 1
  fi
  echo "setMemory  not implemented"

}

#osname  cpuCount
setCPU() {
  _osname="$1"
  _cpuCount="$2"
  if [ -z "$_cpuCount" ]; then
    echo "Usage: setCPU osname 3"
    return 1
  fi
  echo "setCPU  not implemented"

}


#osname
getVMIP() {
  $_SUDO_VIR_  virsh net-dhcp-leases default | grep  -o -E '192.168.[0-9]*.[0-9]*'
}




# input the file as shell script to execute
inputFile() {
  _osname="$1"
  _file="$2"

  if [ -z "$_file" ]; then
    echo "Usage: inputFile netbsd file.txt"
    return 1
  fi
  vncdotool --force-caps  --delay=100  typefile "$_file"

}


#upload a local file into the remote VM
#osname  local  remote
uploadFile() {
  _osname="$1"
  _local="$2" #local file in the host machine.
  _remote="$3" #remote file in the VM
  if [ -z "$_osname" ]; then
    echo "Usage: uploadFile openbsd local remote"
    return 1
  fi
  export VM_OS_NAME=$_osname
  string  "cat - >$_remote"
  input "$_osname" "enter"
  inputFile "$_osname"  "$_local"
  ctrlD

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
  
  vncdotool  type "$1"
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
  vncdotool key enter
}


#osname
tab() {
  _osname="${1:-$VM_OS_NAME}"
  
  if [ -z "$_osname" ]; then
    echo "Usage: tab netbsd"
    return 1
  fi
  vncdotool key tab
}

#osname
f2() {
  _osname="${1:-$VM_OS_NAME}"
  
  if [ -z "$_osname" ]; then
    echo "Usage: f2 netbsd"
    return 1
  fi
  vncdotool key F2
}

#osname
f7() {
  _osname="${1:-$VM_OS_NAME}"
  
  if [ -z "$_osname" ]; then
    echo "Usage: f7 netbsd"
    return 1
  fi
  vncdotool key F7
}




#osname
down() {
  _osname="${1:-$VM_OS_NAME}"
  
  if [ -z "$_osname" ]; then
    echo "Usage: down netbsd"
    return 1
  fi
  vncdotool key Down
}


#osname
up() {
  _osname="${1:-$VM_OS_NAME}"

  if [ -z "$_osname" ]; then
    echo "Usage: up netbsd"
    return 1
  fi
  vncdotool key Up
}



#osname
ctrlD() {
  _osname="${1:-$VM_OS_NAME}"

  if [ -z "$_osname" ]; then
    echo "Usage: up netbsd"
    return 1
  fi
  vncdotool key ctrl-d
}

"$@"



