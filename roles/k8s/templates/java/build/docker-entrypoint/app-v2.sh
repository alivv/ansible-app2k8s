#!/bin/sh

APP_HOME=/opt/{{ item }}
APP_LOG=/var/log/{{ item }}

#logs
cd /var/log/{{ item }}
[ -f gc.${HOSTNAME}.log ] || { touch gc.${HOSTNAME}.log ; }
[ -f ${HOSTNAME}.log ]    || { touch ${HOSTNAME}.log ; }
# ln -fs gc.${HOSTNAME}.log  gc.log
# ln -fs ${HOSTNAME}.log     {{ item }}.log
ln -fs /var/log/{{ item }}/gc.${HOSTNAME}.log /var/log/app/gc.log
ln -fs /var/log/{{ item }}/${HOSTNAME}.log /var/log/app/{{ item }}.log
cd ${APP_HOME}

#tz
echo ${TZ} >/etc/timezone

if [ "$JVMX" = "true" ]; then
	java_k8s_resource_opts="-Xmx${xmx}m -Xms${xms}m"
else
	java_k8s_resource_opts="+UseContainerSupport"
fi

if [ "$JVMX" = "true" ]; then
	java_k8s_resource_opts="-Xmx${xmx}m -Xms${xms}m"
else
	java_k8s_resource_opts="-XX:+UnlockExperimentalVMOptions -XX:+UseCGroupMemoryLimitForHeap"
fi

JAVA_OPTS="-Duser.timezone=$TZ -server 
        ${java_k8s_resource_opts} 
		-XX:ActiveProcessorCount={{ k8s_jvm_active_processor_count }} \
		-Djava.rmi.server.hostname=$HOSTNAME
		-DserviceMate=$POD_IP 
		{% if k8s_config_profiles_active_env == true %}-Dspring.profiles.active=${AppEnv:-qa} {% endif %} 
		-Dserver.servlet.context-path={{k8s_pod_context_path}}
		-DlogDir=$APP_LOG 
		-DappHome=$APP_HOME"

java_agent_opts="-javaagent:/opt/java_agent/{{java_agent}}={{java_agent_port}}:/opt/java_agent/jmx_exporter.yml"

exec java $JAVA_OPTS "${java_agent_opts}" -jar ${APP_HOME}/{{ docker_image_name }}.jar
