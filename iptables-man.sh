#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#	System Required: CentOS/Debian/Ubuntu
#	Description: iptables Port forwarding Management
#	Version: 1.0.0
#	Author: Kenway
#=================================================
sh_ver="1.0.0"



#以下保存一些常量
CONF_DIR="/etc/iptables-man"
CONF_FILE=$CONF_DIR/iptables.conf
SH_FILE=$CONF_DIR/iptables-ddns.sh
#字体颜色
red="\033[31m"
green="\033[32m"
plain="\033[0m"
#设置回退格
stty erase ^H


#脚本需要以root身份运行
[[ $EUID -ne 0 ]] && echo -e "[${red}Error${plain}] This script must be run as root!" && exit 1

#查看本机系统
check_sys(){
    release=`cat /etc/os-release |sed -n 's/^ID=//p'|tr -d "\""`
    version=`cat /etc/os-release |sed -n 's/^VERSION_ID=//p'| tr -d "\""`
    if [ "${release}" == "centos" ]; then
        :
	elif [ "${release}" == "ubuntu" -o "${release}" == "debian"  ]; then
        :
    else
        echo -e "$red本脚本不是您的系统!!$plain"&&exit 1
	fi
}

#获取本机ip
get_localIP(){
    local localIP=$( ip -o -4 addr list eth0 |grep -v inet6|grep inet | sed -n 's/^.*inet //p'|sed -n 's/\/.*$//gp' )
    echo -e -n "请检查您本机IP（不一定是公网IP）是否是：$red $localIP $plain?"
    read  -p '请输入y/n（默认是y）' input 
    [ "$input" == "y" -o "$input" == "Y" -o "$input" == "" ] && echo $localIP &&return 0
    read -p "请输入您本机IP： " input
    until echo $input|grep -E -q "^[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*$"
    do 
        read -p "请正确输入您本机IP： " input
    done
    echo $input
}
#设置iptables
Set_iptables(){
    cat /etc/sysctl.conf|grep -E -q "^[^#]*net.ipv4.ip_forward=1"
	[ "$?" != "0" ] &&echo -e "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
	sysctl -p
    #关闭防火墙
	if [[ ${release} == "centos" ]]; then
        systemctl stop firewalld &> /dev/null
        systemctl disable firewalld &> /dev/null
		chkconfig --level 2345 iptables on
	else
        sudo ufw disable &> /dev/null
	fi
}
#检查并安装iptables
install_iptables(){
	iptables_exist=$(iptables -V)
	if [ "${iptables_exist}" != "" ]; then
		echo -e "已经安装iptables，继续..."
	else
		echo -e "检测到未安装 iptables，开始安装..."
		if [[ ${release}  == "centos" ]]; then
			yum update
			yum install -y iptables
		else
			apt-get update
			apt-get install -y iptables
		fi
		iptables_exist=$(iptables -V)
		if [[ ${iptables_exist} = "" ]]; then
			echo -e "安装iptables失败，请检查 !" && exit 1
		else
			echo -e "iptables 安装完成 !"
		fi
	fi
	echo -e "开始配置 iptables !"
	Set_iptables
	echo -e "iptables 配置完毕 !"
}

#启用ddns
enable_ddns(){
    #向crontab添加定时执行脚本，默认2分钟执行一次
    cat /etc/crontab|grep -q $SH_FILE
    [ "$?" != "0" ]&& echo "*/2  *  *  *  * root  bash $SH_FILE &> /dev/null" > /etc/crontab
    echo -e "$green已成功开启ddns！$plain"
}

#禁用ddns
disable_ddns(){
    #从crontab删除定时执行脚本
    sed -i "/`basename $SH_FILE`/d" /etc/crontab
    echo -e "$green已成功关闭ddns！$plain"
}

#安装管理脚本
sys_install(){
    #检查并安装配置iptables 
    install_iptables
    #安装依赖
    echo -e "$green正在安装依赖bind-uitls，用于查询dns$plain"
    if [ "${release}" == "centos" ]; then
        yum install bind-utils -y &> /dev/null
	elif [ "${release}" == "ubuntu" -o "${release}" == "debian"  ]; then
        apt install -y dnsutils &> /dev/null
	fi
    #检查目录是否存在
    [ ! -d $CONF_DIR ] && mkdir $CONF_DIR
    #检查是否含有本机ip地址
    if [ -f $CONF_FILE ]
    then
        cat $CONF_FILE|grep -q localIP
        #文档里不存在localIP则直接添加
        [ "$?" != "0" ] && local localIP=$(get_localIP) && echo "localIP:$localIP">>$CONF_FILE 

        cat $CONF_FILE|sed -n '/^localIP:[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*$/p'|grep -q localIP
        if [ "$?" != "0" ];then
            local localIP=$(get_localIP)
            #文档里存在localIP但格式不正确，重新覆盖
            sed -i "s/^localIP:.*$/localIP:$localIP/g" $CONF_FILE 
        fi
    else
        local localIP=$(get_localIP)
        echo "localIP:$localIP">$CONF_FILE
    fi
    #检查本机管理脚本是否下载
    [ ! -f $SH_FILE ]&& wget --no-check-certificate https://raw.githubusercontent.com/MstKenway/iptables-man/master/iptables-ddns.sh -O $SH_FILE&& chmod +x $SH_FILE
    [ ! -f $SH_FILE ] && echo "管理脚本下载失败！"&&exit 1
    #设置开机启动脚本
     if [ "${release}" == "centos" ]; then
        sed -i "/exit/i\bash $SH_FILE ALL" /etc/rc.local
        chmod +x /etc/rc.local
	elif [ "${release}" == "ubuntu" -o "${release}" == "debian"  ]; then
        echo -e "#!/bin/bash\nbash $SH_FILE ALL" > /etc/network/if-pre-up.d/iptables
		chmod +x /etc/network/if-pre-up.d/iptables
	fi
    #询问是否开启ddns
    read -p "是否启用ddns？y/n（默认为n，不启用）" input
    [ "$input" == "y" -o "$input" == "Y" ] && enable_ddns
    echo 
    echo
    echo -e "${green}iptables端口转发脚本已成功安装！$plain"
}

#卸载管理脚本
sys_uninstall(){
    [ $installed -lt 1 ]&& echo -e "$red脚本尚未安装！请先安装！$plain"&exit 1
    echo -e "确定要删除iptables管理脚本 ? [y/N]"
	read -e -p "(默认: n):" unyn
    if [[ ${unyn} == [Yy] ]]; then
        [[ -z ${unyn} ]] && unyn="n"
        rm -rf $CONF_DIR
        disable_ddns
        if [ "${release}" == "centos" ]; then
            #设置开机启动脚本
            sed -i "/bash $SH_FILE ALL/d" /etc/rc.local
        elif [ "${release}" == "ubuntu" -o "${release}" == "debian"  ]; then
            #设置开机启动脚本
            rm -f /etc/network/if-pre-up.d/iptables
        fi
        echo -e "iptables端口转发脚本已卸载，感谢您的使用"
    fi
}
#高级设置
#ddns更新频率
#本机ip



#检查系统状态
check_state(){
    check_sys
    installed=0 #0未安装
    [ ! -d $CONF_DIR ]&& echo -e "$red 尚未安装！$plain" &&return 0
    [ ! -f $SH_FILE ]&& echo -e "$red 尚未安装！$plain" &&return 0
    [ ! -f $CONF_FILE ]&& echo -e "$red 尚未安装！$plain" &&return 0
    installed=1 #1已安装，但未启用
    if [ "${release}" == "centos" ]; then
        #设置开机启动脚本
        cat /etc/rc.local|grep -q "bash $SH_FILE ALL" 
        [ "$?" != "0" ]&& echo -e "$green已安装，但$red 尚未启用，建议执行安装$plain" &&return 0
	elif [ "${release}" == "ubuntu" -o "${release}" == "debian"  ]; then
        #设置开机启动脚本
        cat /etc/network/if-pre-up.d/iptables|grep -q "bash $SH_FILE ALL" 
		[ "$?" != "0" ]&& echo -e "$green已安装，但$red 尚未启用，建议执行安装$plain" &&return 0
	fi
    cat /etc/crontab|grep -q "root  bash $SH_FILE &> /dev/null" 
    #2已安装，但未启用DDNS
	[ "$?" != "0" ]&& echo -e "$green已安装，但未启用DDNS，可在高级设置里设置启用DDNS$plain" && installed=2 &&return 0
    echo -e "$green已安装，且已启用DDNS$plain"
    installed=3 #3已安装，且已启用启用DDNS
}

#清空端口转发
clear_all_port(){
    check_iptables
	echo -e "确定要清空 iptables 所有端口转发规则 ? [y/N]"
	read -e -p "(默认: n):" unyn
	[[ -z ${unyn} ]] && unyn="n"
	if [[ ${unyn} == [Yy] ]]; then
        iptables -t nat -F PREROUTING
        iptables -t nat -F POSTROUTING
		echo && echo -e "${Info} iptables 已清空 所有端口转发规则 !" && echo
	else
		echo && echo "清空已取消..." && echo
	fi
}
#列出所有端口转发
list_all_port(){
    echo -e "以下为本机所有转发端口"
    echo "###########################################################"
    iptables -L PREROUTING -n -t nat --line-number
    iptables -L POSTROUTING -n -t nat --line-number
    echo "###########################################################"
}
#删除本机端口为localPort的转发路由
del_iptables(){
    [ $# -ne 1 ]&&exit 1
    local localPort=$1
    #删除旧的中转规则
    local arr1=(`iptables -L PREROUTING -n -t nat --line-number |grep DNAT|grep "dpt:$localPort"|sort -r|awk '{print $1":"$3":"$9}'`)
    for cell in ${arr1[@]}  # cell= 1:tcp:to:8.8.8.8:543
    do
        local arr2=(`echo $cell|tr -s ":" " "`)  #arr2=(1 tcp to 8.8.8.8 543)
        local index=${arr2[0]}
        local proto=${arr2[1]}
        local targetIP=${arr2[3]}
        local targetPort=${arr2[4]}
        # echo 清除本机$localPort端口到$targetIP:$targetPort的${proto}的PREROUTING转发规则[$index]
        iptables -t nat  -D PREROUTING $index
        # echo ==清除对应的POSTROUTING规则
        toRmIndexs=(`iptables -L POSTROUTING -n -t nat --line-number|grep SNAT|grep $targetIP|grep dpt:$targetPort|grep $proto|awk  '{print $1}'|sort -r|tr "\n" " "`)
        for cell1 in ${toRmIndexs[@]}
        do
            iptables -t nat  -D POSTROUTING $cell1
        done
    done
}
#增加本机以localPort、remoteIP、remotePort为参数的中转路由
add_iptables(){
     [ $# -ne 3 ]&&exit 1
     local localPort=$1
     local remoteIP=$2
     local remotePort=$3
    ## 建立新的中转规则
    iptables -t nat -A PREROUTING -p tcp --dport $localPort -j DNAT --to-destination $remoteIP:$remotePort
    iptables -t nat -A PREROUTING -p udp --dport $localPort -j DNAT --to-destination $remoteIP:$remotePort
    iptables -t nat -A POSTROUTING -p tcp -d $remoteIP --dport $remotePort -j SNAT --to-source $local_IP
    iptables -t nat -A POSTROUTING -p udp -d $remoteIP --dport $remotePort -j SNAT --to-source $local_IP
}
#添加静态IP端口转发
add_SIP(){
    [ $installed -le 1 ]&&echo -e "$red脚本尚未安装或安装不完整！请重新安装后添加端口转发$plain"&&exit 1
    #设置远程端口
    read -e -p "请输入 iptables 欲转发至的 $red远程端口$plain [1-65535] (被转发服务器):" remotePort
	[[ -z "${remotePort}" ]] && echo "取消..." && exit 1
	echo && echo -e "	欲转发端口 : ${red}${remotePort}${plain}" && echo
    #设置远程IP
    read -e -p "请输入 iptables 欲转发至的 $red远程IP$plain (被转发服务器):" remoteIP
    [[ -z "${remoteIP}" ]] && echo "取消..." && exit 1
    echo && echo -e "	欲转发服务器IP : ${red}${remoteIP}${plain}" && echo
    #设置本地端口
    echo -e "请输入 iptables $red本地监听端口$plain [1-65535] "
	read -e -p "(默认端口: ${remotePort}):" localPort
	[[ -z "${localPort}" ]] && local_port="${remotePort}"
	echo && echo -e "	本地监听端口 : ${red}${localPort}${plain}" && echo
    #检查本地配置中端口是否已占用
    result=`cat $CONF_FILE|grep -E -q "^SIP:$localPort"`
    [ -n $result ]&&echo -e "$red该本地端口已被静态IP转发占用，请重新设置！$plain"&&exit 1
    result=`cat $CONF_FILE|grep -E -q "^DDNS:$localPort"`
    [ -n $result ]&&echo -e "$red该本地端口已被DDNS转发占用，请重新设置！$plain"&&exit 1
    #获取本地IP
    local_IP=$(cat $CONF_FILE|sed -n "s/^localIP://p")
    [ -z $local_IP ]&& echo -e "$red本地IP出错！请重新设置本地IP！$plain"
    add_iptables $localPort $remoteIP $remotePort
    echo -e "SIP:$localPort:$remoteIP:$remotePort">>$CONF_FILE
    echo -e "$green端口转发设置已成功！$plain"
    echo -e "本地IP：${green}${local_IP}${plain}"
    echo -e "本地端口：${green}${localPort}${plain}"
    echo
    echo -e "远端IP：${green}${remoteIP}${plain}"
    echo -e "远端端口：${green}${remotePort}${plain}"
    echo
}
#添加DDNS端口转发
add_DDNS(){
    [ $installed -le 2 ]&&echo -e "$red脚本尚未安装或安装不完整！请重新安装并开启DDNS后添加端口转发$plain"&&exit 1
    #设置远程端口
    read -e -p "请输入 iptables 欲转发至的 $red远程端口$plain [1-65535] (被转发服务器):" remotePort
	[[ -z "${remotePort}" ]] && echo "取消..." && exit 1
	echo && echo -e "	欲转发端口 : ${red}${remotePort}${plain}" && echo
    #设置DDNS
    read -e -p "请输入 iptables 欲转发至的 ${red}DDNS${plain} (被转发服务器):" DDNS
    [[ -z "${DDNS}" ]] && echo "取消..." && exit 1
    echo && echo -e "	欲转发的DDNS : ${red}${DDNS}${plain}" && echo
    #检测DDNS是否有效
    remoteIP=`$(host -t a $ddns|sed -n 's/^.*ss //p'|head -1)`
    [ -z "$remoteIP" ] && echo "Err： $ddns 解析失败！请检查DDNS以及解析工具HOST" && exit 1
    #设置本地端口
    echo -e "请输入 iptables $red本地监听端口$plain [1-65535] "
	read -e -p "(默认端口: ${remotePort}):" localPort
	[[ -z "${localPort}" ]] && local_port="${remotePort}"
	echo && echo -e "	本地监听端口 : ${red}${localPort}${plain}" && echo
    #检查本地配置中端口是否已占用
    result=`cat $CONF_FILE|grep -E -q "^SIP:$localPort"`
    [ -n $result ]&&echo -e "$red该本地端口已被静态IP转发占用，请重新设置！$plain"&&exit 1
    result=`cat $CONF_FILE|grep -E -q "^DDNS:$localPort"`
    [ -n $result ]&&echo -e "$red该本地端口已被DDNS转发占用，请重新设置！$plain"&&exit 1
    #获取本地IP
    local_IP=$(cat $CONF_FILE|sed -n "s/^localIP://p")
    [ -z $local_IP ]&& echo -e "$red本地IP出错！请重新设置本地IP！$plain"
    add_iptables $localPort $remoteIP $remotePort
    echo -e "SIP:$localPort:$DDNS:$remotePort">>$CONF_FILE
    echo -e "$green端口转发设置已成功！$plain"
    echo -e "本地IP：${green}${local_IP}${plain}"
    echo -e "本地端口：${green}${localPort}${plain}"
    echo
    echo -e "DDNS：${green}${DDNS}${plain}"
    echo -e "远端端口：${green}${remotePort}${plain}"
    echo
}

del_port(){
    [ $installed -le 1 ]&&echo -e "$red脚本尚未安装或安装不完整！请重新安装。$plain"&&exit 1
    while true;
    do
        #列出所有端口转发规则
        cat $CONF_FILE|grep -v "localIP"|sort -n -t:
        read -p "请输入您想删除的端口：(默认为取消)" port 
        [ -z $port ]&& break
        del_port $port
        echo -e "本地端口：${red}${port}${plain}已删除完毕"
    done

}

resetting_port(){
    [ $installed -gt 2 ] && bash $SH_FILE ALL &&echo -e "$green重置规则成功$plain"
}

advanced_setting(){
echo && echo -e " iptables 端口转发一键管理脚本高级设置
————————————
 ${green}1.${plain} 启用DDNS
 ${green}2.${plain} 禁用DDNS
————————————
 ${green}3.${plain} 设置本地IP（on the way)
 ${green}4.${plain} 设置DDNS更新频率(on the way)

" && echo
read -e -p " 请输入数字 [1-4]:" num
case "$num" in
    1)
    enable_ddns
    ;;
    2)
    disable_ddns
    ;;
    # 3)
    # 
    # ;;
    # 4)
    # 
    # ;;
    *)
    echo "请输入正确数字 [1-4]"
    ;;
esac

}


echo && echo -e " iptables 端口转发一键管理脚本【支持DDNS&自启动】 ${red}[v${sh_ver}]${plain}
  -- By MstKenway --
  
————————————
 ${green}1.${plain} 安装 iptables 转发管理
 ${green}2.${plain} 卸载 iptables 转发管理
————————————
 ${green}3.${plain} 清空 iptables 端口转发
 ${green}4.${plain} 查看 iptables 端口转发
 ${green}5.${plain} 添加 iptables 静态IP转发
 ${green}6.${plain} 添加 iptables DDNS转发
 ${green}7.${plain} 删除 iptables 端口转发
————————————
 ${green}8.${plain} 重新添加端口转发规则【可能可以解决部分问题】
 ${green}9.${plain} 高级设置

${red}注意：初次使用前请请务必执行 ${green}1. 安装 iptables${red}(不仅仅是安装)${plain}" && check_state && echo
read -e -p " 请输入数字 [1-9]:" num
case "$num" in
    1)
    sys_install
    ;;
    2)
    sys_uninstall
    ;;
    3)
    clear_all_port
    ;;
    4)
    list_all_port
    ;;
    5)
    add_SIP
    ;;
    6)
    add_DDNS
    ;;
    7)
    del_port
    ;;
    8)
    resetting_port
    ;;
    9)
    advanced_setting
    ;;
    *)
    echo "请输入正确数字 [1-9]"
    ;;
esac
