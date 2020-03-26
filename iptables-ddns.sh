#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#	System Required: CentOS/Debian/Ubuntu
#	Description: iptables Port forwarding Management With DDNS
#	Version: 1.0.1
#	Author: Kenway
#=================================================
ver="1.0.1"
CONF_DIR="/etc/iptables-man"
CONF_FILE=$CONF_DIR/iptables.conf
#配置文件用localIP保存本地ip
local_IP=$( cat $CONF_FILE| grep localIP| sed -n 's/^localIP://p' )

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



#导入静态IP,标识符是SIP
IN_SIP(){
    local arr=(`cat $CONF_FILE|grep SIP|sed -n 's/^SIP://p'`)
    for item in ${arr[*]}
    do
        local item_arr=(`echo $item|tr -s ":" " "`) #格式 本地端口:远端IP:远端端口
        local localPort=${item_arr[0]}
        local remoteIP=${item_arr[1]}
        local remotePort=${item_arr[2]}
        #先尝试删除端口占用
        del_iptables $localPort
        #添加端口
        add_iptables $localPort $remoteIP $remotePort
    done
}
#导入DDNS，标识符是DDNS
IN_DDNS(){
    local arr=(`cat $CONF_FILE|grep DDNS|sed -n 's/^DDNS://p'`)
    for item in ${arr[*]}
    do
        local item_arr=(`echo $item|tr -s ":" " "`) #格式 本地端口:DDNS:原解析IP:远端端口
        local localPort=${item_arr[0]}
        local ddns=${item_arr[1]}
        local remoteIP=${item_arr[2]}
        local remotePort=${item_arr[3]}
        #检查该ddns的IP是否变更
        local tempIP=$(host -t a $ddns|sed -n 's/^.*ss //p'|head -1)
        #如果ddns解析出错则跳过转而进入下一个ddns
        [ -z "$tempIP" ] && echo "Err： $ddns 解析出错" && continue
        if [ "$tempIP" != "$remoteIP" ]
        then
            echo "Info:$ddns 域名IP发生变化，更新本地记录"
            sed -i "s/$ddns\:$remoteIP/$ddns\:$tempIP/g" $CONF_FILE
            remoteIP=$tempIP
        fi
        #先尝试删除端口占用
        del_iptables $localPort
        #添加端口
        add_iptables $localPort $remoteIP $remotePort
    done
}

#仅更新域名IP变化的中转路由
UP_DDNS(){
    local arr=(`cat $CONF_FILE|grep DDNS|sed -n 's/^DDNS://p'`)
    for item in ${arr[*]}
    do
        local item_arr=(`echo $item|tr -s ":" " "`)
        local localPort=${item_arr[0]}
        local ddns=${item_arr[1]}
        local remoteIP=${item_arr[2]}
        local remotePort=${item_arr[3]}
        #检查该ddns的IP是否变更
        local tempIP=$(host -t a $ddns|sed -n 's/^.*ss //p'|head -1)
        #如果ddns解析出错则跳过转而进入下一个ddns
        [ -z "$tempIP" ] && echo "Err： $ddns 解析出错" && continue
        if [ "$tempIP" != "$remoteIP" ]
        then
            echo "Info:$ddns 域名IP发生变化，更新本地记录"
            sed -i "s/$ddns\:$remoteIP/$ddns\:$tempIP/g" $CONF_FILE
            remoteIP=$tempIP
            #先尝试删除端口占用
        del_iptables $localPort
        #添加端口
        add_iptables $localPort $remoteIP $remotePort
        fi
    done
}

#用$1=ALL代表需要导入静态IP和DDNS
if [ "$1" == "ALL" ]
then
    echo "全部重新导入"
    #导入静态IP
    IN_SIP
    #导入DDNS
    IN_DDNS
else
    #检查DDNS并更新
    UP_DDNS
fi