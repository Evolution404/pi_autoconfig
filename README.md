## 树莓派一键配置脚本

### 使用方法
1. 克隆项目到树莓派中
2. 运行项目中的`config.sh`脚本,注意要以root用户运行
3. `config.sh`需要两个参数,分别是pi用户的新密码和smb服务器的密码

```sh
git clone https://github.com/Evolution404/pi_autoconfig.git
cd pi_autoconfig
# 换成你的密码
sudo bash config.sh pi_pw smb_pw
```

### 主要功能
1. 配置locale为`en_US.UTF-8`,wifi国家为US,时区为上海
2. 修改pi用户的密码
3. 新建temp命令,可以查询当前cpu温度
4. 配置命令行命令可以根据前缀向上向下查找
5. 创建`/home/nas`目录,将硬盘挂载到此目录,并在`/etc/fstab`文件中配置自动挂载
6. clash,subconverter,iptables等透明网关配置,并开启ipv4转发
7. 配置proxychains并配置clash代理
8. 安装配置awtrix
9. 编译安装vim
10. 配置samba服务器,共享`/home/nas`目录
