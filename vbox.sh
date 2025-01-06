#!/usr/bin/env bash

set -e



export PATH=$PATH:/Library/Frameworks/Python.framework/Versions/Current/bin

_script="$0"
_script_home="$(dirname "$_script")"



isLinux() {
  uname -a | grep -i "Linux" >/dev/null
}


_SUDO_VIR_=""
if isLinux; then
  _SUDO_VIR_=sudo
fi



#installOCR
setup() {
  _installOCR="$1"
  if isLinux; then
    sudo apt-get update
    sudo apt-get install   -y  zstd  libvirt-daemon-system   virt-manager qemu-kvm qemu-system-arm libosinfo-bin  axel expect screen

    if [ "$_installOCR" ]; then
      sudo apt-get install  -y tesseract-ocr python3-pil tesseract-ocr-eng tesseract-ocr-script-latn python3-opencv python3-pip
      if ! pip3 install --break-system-packages  pytesseract opencv-python vncdotool; then
        #ubuntu 22.04
        pip3 install   pytesseract opencv-python vncdotool
      fi
    fi

  else
    brew install tesseract libvirt qemu  virt-manager axel
    brew services start libvirt

    virsh net-define --file /usr/local/etc/libvirt/qemu/networks/default.xml
    virsh net-autostart default
    virsh net-start default

    pip3 install pytesseract opencv-python
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


#link and localfile
download() {
  _link="$1"
  _file="$2"
  echo "Downloading $_link"
  axel -n 8 -o "$_file" -q "$_link"
  echo "Download finished"
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

  _vdi="$_osname.qcow2"
  _iso="$_osname.iso"
  if [[ "$_isolink" == *"img" ]]; then
   _iso="$_osname.img"
  fi

  if [ ! -e "$_iso" ]; then
   download "$_isolink" $_iso 
   if echo "$_isolink" | grep 'bz2$'; then
     mv "$_iso" "$_iso.bz2"
     bzip2 -dc "$_iso.bz2" >"$_iso"
   fi
  fi
  
  qemu-img create -f qcow2 -o preallocation=off $_vdi 200G

  if [ "$VM_ARCH" = "aarch64" ]; then
    if [[ "$_iso" == *"img" ]]; then
      $_SUDO_VIR_ virt-install \
      --name $_osname \
      --memory 6144 \
      --vcpus 2 \
      --arch aarch64 \
      --disk $_iso \
      --disk path=$_vdi,format=qcow2,bus=${VM_DISK:-virtio} \
      --os-variant=$_ostype \
      --network network=default,model=e1000 \
      --graphics vnc,listen=0.0.0.0 \
      --noautoconsole  --import --machine virt --noacpi --boot loader=/usr/share/AAVMF/AAVMF_CODE.fd
    else
      $_SUDO_VIR_ virt-install \
      --name $_osname \
      --memory 6144 \
      --vcpus 2 \
      --arch aarch64 \
      --disk path=$_vdi,format=qcow2,bus=${VM_DISK:-virtio} \
      --cdrom $_iso \
      --os-variant=$_ostype \
      --network network=default,model=e1000 \
      --graphics vnc,listen=0.0.0.0 \
      --noautoconsole  --import --machine virt --noacpi --boot loader=/usr/share/AAVMF/AAVMF_CODE.fd
    fi

  else
    $_SUDO_VIR_ virt-install \
    --name $_osname \
    --memory 6144 \
    --vcpus 2 \
    --arch x86_64 \
    --disk path=$_vdi,format=qcow2,bus=${VM_DISK:-virtio} \
    --cdrom $_iso \
    --os-variant=$_ostype \
    --network network=default,model=e1000 \
    --graphics vnc,listen=0.0.0.0 \
    --noautoconsole  --import
  fi

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

  if [ "$VM_ARCH" = "aarch64" ]; then
    $_SUDO_VIR_ virt-install \
    --name $_osname \
    --memory 6144 \
    --vcpus 2 \
    --arch ${VM_ARCH} \
    --disk $_vhd,format=qcow2,bus=${VM_DISK:-virtio} \
    --os-variant=$_ostype \
    --network network=default,model=e1000 \
    --graphics vnc,listen=0.0.0.0 \
    --noautoconsole  --import --machine virt --noacpi --boot loader=/usr/share/AAVMF/AAVMF_CODE.fd

  else
    $_SUDO_VIR_ virt-install \
    --name $_osname \
    --memory 6144 \
    --vcpus 2 \
    --arch x86_64 \
    --disk $_vhd,format=qcow2,bus=${VM_DISK:-virtio} \
    --os-variant=$_ostype \
    --network network=default,model=e1000 \
    --graphics vnc,listen=0.0.0.0 \
    --noautoconsole  --import

  fi

  $_SUDO_VIR_  virsh  shutdown $_osname
  $_SUDO_VIR_  virsh  destroy $_osname

}


disableSecureBoot() {
  _osname="$1"
   $_SUDO_VIR_ virsh dumpxml  "$_osname"  >"$_osname".xml
   $_SUDO_VIR_ sed -i "s/firmware='efi'//" "$_osname".xml
   $_SUDO_VIR_ sed -i "/enrolled-keys/d" "$_osname".xml
   $_SUDO_VIR_ sed -i "/feature enabled='yes' name='secure-boot'/d" "$_osname".xml
   $_SUDO_VIR_ sed -i 's/AAVMF_CODE.ms.fd/AAVMF_CODE.fd/' "$_osname".xml
   $_SUDO_VIR_ sed -i 's/AAVMF_VARS.ms.fd/AAVMF_VARS.fd/' "$_osname".xml

   $_SUDO_VIR_ virsh undefine "$_osname" --nvram
   $_SUDO_VIR_ virsh define "$_osname".xml
}



#ova
importVM() {
  _osname="$1"
  _ostype="$2"
  _ova="$3"
  _iso="$4"
  _mem="${5:-6144}"
  _cpu="${6:-2}"
  if [ -z "$_ova" ]; then
    echo "Usage: importVM xxxx.ova"
    return 1
  fi

  if [ "$VM_ARCH" = "aarch64" ]; then
    $_SUDO_VIR_ virt-install \
    --name $_osname \
    --memory 6144 \
    --vcpus 2 \
    --arch aarch64 \
    --disk $_ova,format=qcow2,bus=${VM_DISK:-virtio} \
    --os-variant=$_ostype \
    --network network=default,model=e1000 \
    --graphics vnc,listen=0.0.0.0 \
    --noautoconsole  --import --check all=off --machine virt --noacpi --boot loader=/usr/share/AAVMF/AAVMF_CODE.fd
  else
    $_SUDO_VIR_  virt-install \
    --name $_osname \
    --memory $_mem \
    --vcpus $_cpu \
    --arch ${VM_ARCH:-x86_64} \
    --disk $_ova,format=qcow2,bus=${VM_DISK:-virtio} \
    --os-variant=$_ostype \
    --network network=default,model=e1000 \
    --graphics vnc,listen=0.0.0.0 \
    --noautoconsole  --import  --check all=off
  fi


  $_SUDO_VIR_  virsh  shutdown $_osname
  $_SUDO_VIR_  virsh  destroy $_osname
  if [ "$VM_ARCH" = "aarch64" ]; then
    disableSecureBoot $_osname
  fi
}

isVMReady() {
  _osname="$1"
  [ -e "$HOME/$_osname.rebooted" ]
}

waitForVMReady() {
  _osname="$1"
  while ! isVMReady $_osname ; do
    echo "VM is booting"
    sleep 2
    $_SUDO_VIR_ virsh send-key $_osname KEY_ENTER
  done
  echo "VM is ready!"
  cat "$HOME/$_osname.rebooted"
}

#osname
startVM() {
  _osname="$1"
  
  if [ -z "$_osname" ]; then
    echo "Usage: startVM netbsd"
    return 1
  fi
  rm -f $HOME/$_osname.rebooted
  $_SUDO_VIR_  virsh  start  $_osname 
}



openConsole() {
  _osname="$1"
  CONSOLE_NAME="$_osname-$VM_RELEASE-console"
  CONSOLE_FILE="$_script_home/$_osname-$VM_RELEASE-console.log"
  screen -dmLS "$CONSOLE_NAME" -Logfile "$CONSOLE_FILE" -L $_SUDO_VIR_ virsh console "$_osname"

}

closeConsole() {
  _osname="$1"
  CONSOLE_NAME="$_osname-$VM_RELEASE-console"
  if screen -list | grep -q "$CONSOLE_NAME"; then
    screen -S "$CONSOLE_NAME" -X quit
  fi
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
    echo "Input keys: $_keys"
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

  rm -f ~/.ssh/known_hosts

}

#osname
shutdownVM() {
  _osname="$1"
  
  if [ -z "$_osname" ]; then
    echo "Usage: shutdownVM netbsd"
    return 1
  fi
  rm -f $HOME/$_osname.rebooted
  $_SUDO_VIR_  virsh  shutdown  $_osname
  sleep 2
}


#force shutdown
#osname
destroyVM() {
  _osname="$1"
  
  if [ -z "$_osname" ]; then
    echo "Usage: destroyVM netbsd"
    return 1
  fi
  rm -f $HOME/$_osname.rebooted
  $_SUDO_VIR_  virsh  destroy  $_osname
  sleep 2
}

#osname
isRunning() {
  _osname="$1"
  if $_SUDO_VIR_  virsh  list --all | grep  $_osname | grep -i running; then
    return 0
  fi
  return 1
}

detachIMG() {
  _osname="$1"

  _imgfile="$_script_home/$_osname.img"

  if [ -z "$_osname" ]; then
    echo "Usage: detachISO openbsd"
    return 1
  fi
  echo "<disk type='file' device='disk'>
  <driver name='qemu' type='raw'/>
  <source file='$_imgfile' index='2'/>
  <backingStore/>
  <target dev='vda' bus='virtio'/>
  <alias name='virtio-disk0'/>
  <address type='pci' domain='0x0000' bus='0x04' slot='0x00' function='0x0'/>
</disk>" >remove-cdrom.xml
  $_SUDO_VIR_  virsh detach-device "$_osname" --file remove-cdrom.xml --persistent

}


detachISO() {
  _osname="$1"
  
  if [ -z "$_osname" ]; then
    echo "Usage: detachISO netbsd"
    return 1
  fi
  if [ "$VM_ARCH" = "aarch64" ]; then
    echo "<disk type='file' device='cdrom'>
  <target dev='sda' bus='scsi'/>
</disk>" >remove-cdrom.xml
  else
    echo "<disk type='file' device='cdrom'>
  <target dev='hdc' bus='ide'/>
</disk>" >remove-cdrom.xml
  fi
  $_SUDO_VIR_  virsh detach-device "$_osname" --file remove-cdrom.xml --persistent

}

attachISO() {
  _osname="$1"
  _iso="$2"
  
  if [ -z "$_iso" ]; then
    echo "Usage: attachISO netbsd  netbsd.iso"
    return 1
  fi
  echo "<disk type='file' device='cdrom'>
  <driver name='qemu' type='raw'/>
  <target dev='hdc' bus='ide'/>
  <readonly/>
  <address type='drive' controller='0' bus='1' target='0' unit='0'/>
</disk>" >cdrom.xml

  $_SUDO_VIR_  virsh attach-device "$_osname" --file cdrom.xml --persistent
  $_SUDO_VIR_  virsh change-media "$_osname" hdc --insert --source "$_iso"
  $_SUDO_VIR_  virsh dumpxml "$_osname"  >dump.xml
  sed -i "/<boot dev='hd'/i <boot dev='cdrom'/>" dump.xml
  $_SUDO_VIR_  virsh define dump.xml

}

#img
_ocr() {
  _ocr_img="$1"
  if [ "$VM_OCR" == "py" ]; then
    _ocrpy "$_ocr_img"
  else
    _ocrt "$_ocr_img"
  fi
}


#img
_ocrt() {
  _ocr_img="$1"
  tesseract -l eng $_ocr_img - 2>/dev/null
}

#img
_ocrpy() {
  _ocr_img="$1"
  #pytesseract $_ocr_img
  python3 -c "
import cv2,pytesseract,numpy,sys;
img = cv2.imread(sys.argv[1]);
gray = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY);
gray, img_bin = cv2.threshold(gray,128,255,cv2.THRESH_BINARY | cv2.THRESH_OTSU);
gray = cv2.bitwise_not(img_bin);
kernel = numpy.ones((2, 1), numpy.uint8);
img = cv2.erode(gray, kernel, iterations=1);
img = cv2.dilate(img, kernel, iterations=1);
out_below = pytesseract.image_to_string(img);
print(out_below);

"  "$_ocr_img"
}


#osname [img]
screenText() {
  _osname="$1"
  _img="$2"
  
  if [ -z "$_osname" ]; then
    echo "Usage: screenText netbsd"
    return 1
  fi


  CONSOLE_FILE="$_script_home/$_osname-$VM_RELEASE-console.log"

  if [ -z "$VM_USE_CONSOLE_BUILD" ]; then
    _png="${_img}"
    if [ -z "$_img" ]; then
      _png="$(mktemp).png"
      echo "using _png=$_png"
    fi
    while ! vncdotool capture  $_png >/dev/null 2>&1; do
     #echo "screenText error, lets just wait"
      sleep 3
    done
    sudo chmod 666 $_png
  fi

  if [ -z "$_img" ]; then
    if [ -z "$VM_USE_CONSOLE_BUILD" ]; then
      _ocr $_png
      rm -rf $_png
    else
      tail -50 "$CONSOLE_FILE"
    fi
  else
    if [ -z "$VM_USE_CONSOLE_BUILD" ]; then
      _ocr $_png >screen.txt
    else
      tail -50 "$CONSOLE_FILE" >screen.txt
    fi

    echo "<!DOCTYPE html>
<html>
<head>
<title>$_osname $VM_RELEASE</title>
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

#osname needOCR
startWeb() {
  _osname="$1"
  _needOCR="$2"

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

  if [ "$_needOCR" ]; then
    (while true; do screenText "$_osname" "screen.png"; sleep 3; done)&
  else
    (while true; do $_SUDO_VIR_  virsh "$_osname" "screen.ppm"; convert "screen.ppm" "screen.png"; sleep 3; done)&
  fi

}


exportOVA() {
  _osname="$1"
  _ova="$2"
  if [ -z "$_ova" ]; then
    echo "Usage: exportOVA netbsd netbsd.9.2.qcow2"
    return 1
  fi

  _sor="$($_SUDO_VIR_  virsh domblklist $_osname | grep -E -o '/.*qcow2')"
  echo "$_sor"
  sudo zstd -c "$_sor" | split -b 2000M -d -a 1 - "$_ova.zst."
  ls -lah
  sudo mv "$_ova.zst.0" "$_ova.zst"
  sudo chmod +r ${_ova}.zst*
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
Include config.d/*
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

  mkdir -p ~/.ssh/config.d

  mkdir -p ~/.local/bin
  echo "#!/usr/bin/env sh

ssh $_osname sh<\$1
  
">~/.local/bin/$_osname

  chmod +x ~/.local/bin/$_osname

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
  _osname="$1"
  if [ -e "$HOME/$_osname.rebooted" ]; then
    line=$(head -1 "$HOME/$_osname.rebooted")
    if [ "$line" ]; then
      printf -- "%s" "read ip from rebooted: $line" >&2
      echo "$line"
      return
    fi
  fi
  $_SUDO_VIR_  virsh net-dhcp-leases default | grep  -o -E '192.168.[0-9]*.[0-9]*' | head -1
}




# input the file as shell script to execute
inputFile() {
  _osname="$1"
  _file="$2"

  if [ -z "$_file" ]; then
    echo "Usage: inputFile netbsd file.txt"
    return 1
  fi
  if [ "$VM_USE_CONSOLE_BUILD" ]; then
    CONSOLE_NAME="$_osname-$VM_RELEASE-console"
    screen -S "$CONSOLE_NAME" -p 0 -X readbuf "$_file"
    screen -S "$CONSOLE_NAME" -p 0 -X paste .
  else
    vncdotool --force-caps  --delay=100  typefile "$_file"
  fi

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
  if [ "$VM_USE_CONSOLE_BUILD" ]; then
    CONSOLE_NAME="$_osname-$VM_RELEASE-console"
    screen -S "$CONSOLE_NAME" -p 0 -X stuff "$1"
  else
    vncdotool --force-caps type "$1"
  fi
}



#osname
space() {
  _osname="${1:-$VM_OS_NAME}"

  if [ -z "$_osname" ]; then
    echo "Usage: enter netbsd"
    return 1
  fi
  if [ "$VM_USE_CONSOLE_BUILD" ]; then
    CONSOLE_NAME="$_osname-$VM_RELEASE-console"
    screen -S "$CONSOLE_NAME" -p 0 -X stuff " "
  else
    vncdotool type ' '
  fi
}

#osname
enter() {
  _osname="${1:-$VM_OS_NAME}"
  
  if [ -z "$_osname" ]; then
    echo "Usage: enter netbsd"
    return 1
  fi
  if [ "$VM_USE_CONSOLE_BUILD" ]; then
    CONSOLE_NAME="$_osname-$VM_RELEASE-console"
    screen -S "$CONSOLE_NAME" -p 0 -X stuff "\r"
  else
    vncdotool key enter
  fi
  
}


#osname
tab() {
  _osname="${1:-$VM_OS_NAME}"
  
  if [ -z "$_osname" ]; then
    echo "Usage: tab netbsd"
    return 1
  fi
  if [ "$VM_USE_CONSOLE_BUILD" ]; then
    CONSOLE_NAME="$_osname-$VM_RELEASE-console"
    screen -S "$CONSOLE_NAME" -p 0 -X stuff $'\t'
  else
    vncdotool key tab
  fi

}

#osname
f2() {
  _osname="${1:-$VM_OS_NAME}"
  
  if [ -z "$_osname" ]; then
    echo "Usage: f2 netbsd"
    return 1
  fi
  if [ "$VM_USE_CONSOLE_BUILD" ]; then
    CONSOLE_NAME="$_osname-$VM_RELEASE-console"
    screen -S "$CONSOLE_NAME" -p 0 -X stuff $'\e[12~'
  else
    vncdotool key f2
  fi

}

#osname
f7() {
  _osname="${1:-$VM_OS_NAME}"
  
  if [ -z "$_osname" ]; then
    echo "Usage: f7 netbsd"
    return 1
  fi
  if [ "$VM_USE_CONSOLE_BUILD" ]; then
    CONSOLE_NAME="$_osname-$VM_RELEASE-console"
    screen -S "$CONSOLE_NAME" -p 0 -X stuff $'\e[18~'
  else
    vncdotool key f7
  fi
}

#osname
f8() {
  _osname="${1:-$VM_OS_NAME}"
  
  if [ -z "$_osname" ]; then
    echo "Usage: f8 netbsd"
    return 1
  fi
  if [ "$VM_USE_CONSOLE_BUILD" ]; then
    CONSOLE_NAME="$_osname-$VM_RELEASE-console"
    screen -S "$CONSOLE_NAME" -p 0 -X stuff $'\e[19~'
  else
    vncdotool key f8
  fi
}



#osname
down() {
  _osname="${1:-$VM_OS_NAME}"
  
  if [ -z "$_osname" ]; then
    echo "Usage: down netbsd"
    return 1
  fi
  if [ "$VM_USE_CONSOLE_BUILD" ]; then
    CONSOLE_NAME="$_osname-$VM_RELEASE-console"
    screen -S "$CONSOLE_NAME" -p 0 -X stuff $'\e[B'
  else
    vncdotool key down
  fi
}


#osname
up() {
  _osname="${1:-$VM_OS_NAME}"

  if [ -z "$_osname" ]; then
    echo "Usage: up netbsd"
    return 1
  fi
  if [ "$VM_USE_CONSOLE_BUILD" ]; then
    CONSOLE_NAME="$_osname-$VM_RELEASE-console"
    screen -S "$CONSOLE_NAME" -p 0 -X stuff $'\e[A'
  else
    vncdotool key up
  fi
}



#osname
ctrlD() {
  _osname="${1:-$VM_OS_NAME}"

  if [ -z "$_osname" ]; then
    echo "Usage: up netbsd"
    return 1
  fi
  if [ "$VM_USE_CONSOLE_BUILD" ]; then
    CONSOLE_NAME="$_osname-$VM_RELEASE-console"
    screen -S "$CONSOLE_NAME" -p 0 -X stuff $'\x04'
  else
    vncdotool key ctrl-d
  fi
}

"$@"



