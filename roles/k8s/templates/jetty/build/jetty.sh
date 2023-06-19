#!/bin/bash

export JETTY_PID=$JETTY_HOME/jetty.pid
#tz
echo ${TZ} >/etc/timezone

#logs
cd /var/log/{{ item }}
[ -f gc.${HOSTNAME}.log ] || { touch gc.${HOSTNAME}.log ; }
[ -f vm.${HOSTNAME}.log ] || { touch vm.${HOSTNAME}.log ; }
[ -f ${HOSTNAME}.log ]    || { touch ${HOSTNAME}.log ; }
# ln -fs gc.${HOSTNAME}.log  gc.log
# ln -fs vm.${HOSTNAME}.log  vm.log
# ln -fs ${HOSTNAME}.log     {{ item }}.log
ln -fs /var/log/{{ item }}/gc.${HOSTNAME}.log /var/log/app/gc.log
ln -fs /var/log/{{ item }}/vm.${HOSTNAME}.log /var/log/app/vm.log
ln -fs /var/log/{{ item }}/${HOSTNAME}.log /var/log/app/{{ item }}.log
cd ${JETTY_BASE}

java_env_opts="-Djava.security.egd=file:/dev/urandom  -server
    -Duser.timezone=$TZ
    -Dfile.encoding=UTF-8
    -Djava.awt.headless=true
    -Djava.library.path=/usr/lib
    -Djava.rmi.server.hostname=$POD_IP
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
java_k8s_resource_opts="-Xmx${xmx}m -Xms${xms}m
    -XX:ActiveProcessorCount={{ k8s_jvm_active_processor_count }}"
else
java_k8s_resource_opts="-XX:+UnlockExperimentalVMOptions
    -XX:+UseCGroupMemoryLimitForHeap
    -XX:ActiveProcessorCount={{ k8s_jvm_active_processor_count }}"
fi

if [ "$AppEnv" = "qa" -o "$AppEnv" = "test" -o "$AppEnv" = "dev" ]; then
    java_debug="-Xdebug -Xnoagent -Djava.compiler=NONE -Xrunjdwp:transport=dt_socket,address=8081,server=y,suspend=n"
fi

java_memory_opts="{% if docker_build_base_image == 'jetty9' %}-XX:+PreserveFramePointer{% endif %}
    -XX:MaxTenuringThreshold=15
    -XX:-UseBiasedLocking
    -XX:AutoBoxCacheMax=20000
    -XX:+ParallelRefProcEnabled
    -XX:+SafepointTimeout
    -XX:SafepointTimeoutDelay=500
    -XX:OldPLABSize=1024
    $jvmGC"

java_log_opts=" -XX:+UnlockDiagnosticVMOptions
    -XX:LogFile=/var/log/{{ item }}/vm.${HOSTNAME}.log
    -XX:+PrintGCDetails
    {% if docker_build_base_image == 'jetty9' %}
    -Xloggc:/var/log/{{ item }}/gc.${HOSTNAME}.log
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
    -Xlog:gc:/var/log/{{ item }}/gc.${HOSTNAME}.log
    -Xlog:::time
    -Xlog:gc+heap=trace
    -Xlog:age*=debug
    -Xlog:safepoint:/var/log/{{ item }}/gc.${HOSTNAME}.log
    --add-opens java.base/java.lang=ALL-UNNAMED
    {% endif %}
    -XX:+PrintCommandLineFlags
    -XX:-DisplayVMOutput
    -XX:+LogVMOutput" 

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
