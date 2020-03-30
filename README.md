# iptables-man
A script for forwarding by iptables[DDNS support]
基于iptables的端口转发脚本

version1.0.6

支持Centos7+/Debian/Ubuntu

支持DDNS转发和静态IP转发，且重启后不会丢失规则

目前不支持端口段转发

目前尚在测试中，有BUG欢迎发issue

1.0.5自启方式改变，建议1.0.4以前的卸载后重新安装（记得备份配置文件）

使用方式：

```
wget -N --no-check-certificate https://raw.githubusercontent.com/MstKenway/iptables-man/master/iptables-man.sh && chmod +x iptables-man.sh&&./iptables-man.sh 
```
或者
```
curl -O https://raw.githubusercontent.com/MstKenway/iptables-man/master/iptables-man.sh && chmod +x iptables-man.sh&&./iptables-man.sh 
```

配置文件路径：/etc/iptables-man/iptables.conf
配置文件格式：
```
localIP:本机IP
SIP:本地端口:远端IP:远端端口
DDNS:本地端口:DDNS:原解析IP:远端端口
```

---

对于1.0.4以前的版本请使用以下代码卸载，或重装系统
```
sed -i "/iptables-ddns/d"  /etc/rc.local
```


---

感谢iptablesUtils&iptables-pf，参考借鉴不少
