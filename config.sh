#!/bin/bash
if [ $# -ne 2 ];then
  echo 没有传入pi用户和samba服务器的密码
  exit 1
fi

pi_pw=$1
smb_pw=$2

echo 配置locale和wifi国家
raspi-config nonint do_change_locale en_US.UTF-8

if [ `raspi-config nonint get_wifi_country` == US ]; then
  echo wifi已经是US了无需设置
else
  raspi-config nonint do_wifi_country US
fi

echo 修改时区
raspi-config nonint do_change_timezone Asia/Shanghai

echo 设置pi用户密码
echo pi:$pi_pw |chpasswd

echo 准备写入temp温度查询命令
grep -q "temp" /home/pi/.bashrc
if [ $? -eq 0 ];then
  echo "temp命令之前已经被写入"
else
cat >> /home/pi/.bashrc << 'END_TEXT'
alias temp="awk '{print \$1/1000\"C\"}' /sys/class/thermal/thermal_zone0/temp"
END_TEXT
  echo "写入temp命令成功"
fi

echo 准备配置命令前缀补全
sed -i 's/^# \("\\e\[B"\)/\1/' /etc/inputrc
sed -i 's/^# \("\\e\[A"\)/\1/' /etc/inputrc

echo 自动挂载
mkdir -p /home/nas
mountpoint -q /home/nas
if [ $? -ne 0 ];then
  mount /dev/sda1 /home/nas
else
  echo /home/nas目录已经挂载
fi
chown -R pi:pi /home/nas

echo 准备写入fstab文件
grep -q "/home/nas" /etc/fstab
if [ $? -eq 0 ];then
  echo "fstab内容已经被写入"
else
cat >> /etc/fstab << 'END_TEXT'
/dev/sda1 /home/nas ext4 defaults,nofail,x-systemd.device-timeout=5,noatime 0 0
END_TEXT
  echo "写入fstab文件成功"
fi

echo 配置subconverter
if [ ! -d /root/subconverter ]; then
  echo 复制subconverter文件夹
  cp -r proxy/subconverter/subconverter /root
  chmod 777 /root/subconverter/subconverter
fi

if [ ! -f /etc/systemd/system/subconverter.service ]; then
  echo 复制subconverter的service文件
  cp proxy/subconverter/subconverter.service /etc/systemd/system
fi
systemctl enable subconverter
systemctl start subconverter

echo 开启ip转发
sed -i 's/^#\(net\.ipv4\.ip_forward=1\)/\1/' /etc/sysctl.conf
sysctl -p

echo 配置clash
if [ ! -f /usr/bin/clash ]; then
  echo 复制clash可执行文件
  cp proxy/clash/clash /usr/bin
  chmod 777 /usr/bin/clash
fi

if [ ! -d /.config/clash ]; then
  echo 复制clash配置文件
  rm -rf /.config
  cp -r proxy/clash/.config /
fi

if [ ! -f /etc/systemd/system/clash.service ]; then
  echo 复制clash的service文件
  cp proxy/clash/clash.service /etc/systemd/system
fi
systemctl enable clash
systemctl start clash

echo 配置tproxy
mkdir -p /etc/iptables
if [ ! -f /etc/iptables/rules.v4 ]; then
  echo 复制tproxy的配置文件
  cp proxy/tproxy/rules.v4 /etc/iptables
fi

if [ ! -f /etc/systemd/system/tproxy.service ]; then
  echo 复制tproxy的service文件
  cp proxy/tproxy/tproxy.service /etc/systemd/system
fi
systemctl enable tproxy
systemctl start tproxy

echo apt离线安装
mv /etc/apt/sources.list /etc/apt/sources.list.bak
cp -r apt-offline /
echo deb [trusted=yes] file:/// /apt-offline/ > /etc/apt/sources.list
apt update
apt install -y dnsutils proxychains default-jdk git libncurses-dev samba
mv /etc/apt/sources.list.bak /etc/apt/sources.list
rm -rf /apt-offline

echo 配置proxychains
type proxychains > /dev/null 2>&1
if [ $? -ne 0 ];then
  echo proxychains没有安装成功
  exit 1
fi
sed -i 's/^socks4 \t127.0.0.1 9050/socks5  127.0.0.1 7890/' /etc/proxychains.conf
sed -i 's/^#\(quiet_mode\)/\1/' /etc/proxychains.conf
curl -x localhost:7890 google.com >> /dev/null
if [ $? -eq 0 ]; then
  proxy=proxychains
fi

#echo 克隆clash-dashboard
#rm -rf /.config/clash/clash-dashboard
#$proxy git clone -b gh-pages https://github.com/Dreamacro/clash-dashboard.git /.config/clash/clash-dashboard

echo 配置awtrix
type java > /dev/null 2>&1
if [ $? -ne 0 ];then
  echo java没有安装成功
  exit 1
fi

if [ ! -d /usr/local/awtrix ]; then
  echo 复制awtrix.jar及其配置文件
  cp -r awtrix/awtrix /usr/local
fi

if [ ! -f /etc/systemd/system/awtrix.service ]; then
  echo 复制awtrix的service文件
  cp awtrix/awtrix.service /etc/systemd/system
fi
systemctl enable awtrix
systemctl start awtrix

echo 安装vim
type vim > /dev/null 2>&1
if [ $? -ne 0 ];then
  type git > /dev/null 2>&1
  if [ $? -ne 0 ];then
    echo git没有安装成功
    exit 1
  fi
  cd /home/pi
  $proxy git clone https://github.com/vim/vim.git
  cd vim
  ./configure --with-features=huge --enable-multibyte --enable-python3interp=yes --with-python-config-dir=/usr/lib/python3.7/config-3.7m-arm-linux-gnueabihf --enable-cscope --prefix=/usr/local
  make -j4
  make install
else
  echo vim已经安装
fi


echo 安装samba
type smbd > /dev/null 2>&1
if [ $? -ne 0 ];then
  echo samba没有安装成功
  exit 1
fi

grep -q "NAS" /etc/samba/smb.conf
if [ $? -ne 0 ];then
mv /etc/samba/smb.conf /etc/samba/smb.conf.bak
cat >> /etc/samba/smb.conf << 'END_TEXT'
[global]
   write cache size = 262144
   workgroup = WORKGROUP
   log file = /var/log/samba/log.%m
   max log size = 1000
   logging = file
   panic action = /usr/share/samba/panic-action %d
   server role = standalone server
   obey pam restrictions = yes
   unix password sync = yes
   passwd program = /usr/bin/passwd %u
   passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
   pam password change = yes
   map to guest = bad user
   usershare allow guests = yes

[NAS]
   comment = NAS
   browseable = yes
   read only = no
   create mask = 0777
   directory mask = 0777
   valid users = pi
   path = /home/nas
   guest ok = no
END_TEXT
  echo "写入samba配置成功"
fi
pdbedit -L | grep -q pi
if [ $? -eq 0 ];then
  echo samba的用户已经创建,删除旧用户重新创建
  smbpasswd -x pi
fi
  (echo $smb_pw;echo $smb_pw) | smbpasswd -a pi
  echo samba配置信息 用户名:pi 密码:$smb_pw
