#!/bin/bash

#var
app={{ item }}
#tz
echo ${TZ} >/etc/timezone
export JETTY_PID=$JETTY_HOME/jetty.pid
if [ "$POD_IP" = "" ];then
    localip=$(grep $(hostname) /etc/hosts |head -n 1 |awk '{print $1}')
    export localip=$localip
else
    export localip=$POD_IP
fi

#logs
cd /var/log/${app}
[ -f gc.${HOSTNAME}.log ] || { touch gc.${HOSTNAME}.log ; }
[ -f vm.${HOSTNAME}.log ] || { touch vm.${HOSTNAME}.log ; }
[ -f ${HOSTNAME}.log ]    || { touch ${HOSTNAME}.log ; }
# ln -fs gc.${HOSTNAME}.log  gc.log
# ln -fs vm.${HOSTNAME}.log  vm.log
# ln -fs ${HOSTNAME}.log     ${app}.log
ln -fs /var/log/${app}/gc.${HOSTNAME}.log /var/log/app/gc.log
ln -fs /var/log/${app}/vm.${HOSTNAME}.log /var/log/app/vm.log
ln -fs /var/log/${app}/${HOSTNAME}.log /var/log/app/${app}.log
{% if docker_build_base_image == 'jetty9-17' %}
#java 17
[ -f gc.safepoint.${HOSTNAME}.log ] || { touch gc.safepoint.${HOSTNAME}.log ; }
ln -fs gc.safepoint.${HOSTNAME}.log gc.safepoint.log
ln -fs /var/log/${app}/gc.safepoint.${HOSTNAME}.log /var/log/app/gc.safepoint.log
{% endif %}

cd ${JETTY_BASE}

java_env_opts="-Djava.security.egd=file:/dev/urandom  -server
    -Duser.timezone=$TZ
    -Dfile.encoding=UTF-8
    -Djava.awt.headless=true
    -Djava.library.path=/usr/lib
    -Djava.rmi.server.hostname=$localip
    -Djava.net.preferIPv4Stack=true
    {% if k8s_config_profiles_active_env == true %}-Dspring.profiles.active=${AppEnv:-qa} {% endif %}" 

# java_jmx_opts='-Dcom.sun.management.jmxremote.port=18999
#     -Dcom.sun.management.jmxremote.rmi.port=18999
#     -Dcom.sun.management.jmxremote.ssl=false
#     -Dcom.sun.management.jmxremote.authenticate=false' 

java_jmx_opts=''

jetty_java_large_opts='{% if docker_build_base_image == 'jetty9' %}-XX:+UseConcMarkSweepGC
    -XX:+CMSClassUnloadingEnabled 
    -XX:CMSInitiatingOccupancyFraction=68
    -XX:+UseCMSInitiatingOccupancyOnly
    -XX:CMSFullGCsBeforeCompaction=0
    -XX:-DisableExplicitGC
    -XX:+ExplicitGCInvokesConcurrent
    -XX:+UseCompressedClassPointers
    -XX:+UseCompressedOops
    {% endif %}' 

jetty_java_small_opts='-XX:+UseParallelGC
  -XX:+DisableExplicitGC'

[[ $xmx -ge 3276 ]] && jvmGC="${jetty_java_large_opts}" || jvmGC="${java_jmx_opts}"

if [[ "$JVMX" = "true" ]]; then
java_k8s_resource_opts="-XX:+UseContainerSupport
    -Xmx${xmx}m -Xms${xms}m"
else
java_k8s_resource_opts="-XX:+UseContainerSupport 
{% if docker_build_base_image == 'jetty9-17' %}
    -XX:MaxRAMPercentage=80
{% endif %}
    "
fi

if [ "$AppEnv" = "qa" -o "$AppEnv" = "test" -o "$AppEnv" = "dev" ]; then
    java_debug="-Xdebug -Xnoagent -Djava.compiler=NONE -Xrunjdwp:transport=dt_socket,address=8081,server=y,suspend=n"
fi

java_memory_opts="
{% if docker_build_base_image == 'jetty9' %}
    -XX:+PreserveFramePointer
    -XX:-UseBiasedLocking
    -XX:+ParallelRefProcEnabled
    -XX:+SafepointTimeout
    -XX:SafepointTimeoutDelay=500
    -XX:OldPLABSize=1024
{% endif %}
    -XX:MaxTenuringThreshold=15
    -XX:AutoBoxCacheMax=20000
    $jvmGC"

java_log_opts=" -XX:+UnlockDiagnosticVMOptions
    -XX:+LogVMOutput
    -XX:LogFile=/var/log/${app}/vm.${HOSTNAME}.log
    -XX:+PrintCommandLineFlags
{% if docker_build_base_image == 'jetty9' %}
    -XX:-DisplayVMOutput
    -XX:+PrintGCDetails
    -Xloggc:/var/log/${app}/gc.${HOSTNAME}.log
    -XX:+PrintGCDateStamps
    -XX:+PrintGCTimeStamps
    -XX:+PrintHeapAtGC
    -XX:+PrintPromotionFailure
    -XX:+PrintTenuringDistribution
    -XX:+PrintGCApplicationStoppedTime
    -XX:NativeMemoryTracking=summary
    -XX:+PrintSafepointStatistics
    -XX:PrintSafepointStatisticsCount=1
{% elif docker_build_base_image == 'jetty9-17' %}
    -XX:-OmitStackTraceInFastThrow
    -Xlog:gc*=debug:file=/var/log/${app}/gc.${HOSTNAME}.log:time,uptime,level,tags:filecount=20,filesize=100m
    -Xlog:safepoint=debug:file=/var/log/${app}/gc.safepoint.${HOSTNAME}.log:time,uptime,level,tags:filecount=10,filesize=10M
    --add-opens java.base/java.lang=ALL-UNNAMED
{% endif %}
    " 

java_agent_opts=" -javaagent:/opt/java_agent/{{java_agent}}={{java_agent_port}}:/opt/java_agent/jmx_exporter.yml"

java_dump_opts=" -XX:+HeapDumpOnOutOfMemoryError
  -XX:HeapDumpPath=/var/log/{{ k8s_pod_name }}/ "

opts="${java_env_opts}
        ${java_jmx_opts}
        ${java_dump_opts}
        ${java_memory_opts}
        ${java_log_opts}
        ${java_k8s_resource_opts}
        ${java_agent_opts}
        ${java_debug}
        -Djetty.home=${JETTY_HOME} -Djetty.base=${JETTY_BASE}
        -jar $JETTY_HOME/start.jar
        jetty.state=$JETTY_HOME/jetty.state jetty-started.xml"

jetty_opts="$(echo ${opts})"

#start jetty
exec java  ${jetty_opts}
