#!/bin/bash

{% if health_check_info is defined and health_check_info != '' %}
{% for info in health_check_info %}
echo "#{{ info.name }}-Check"
dependency_status=$(curl -s -m 2 {{ info.url }} -H "username: {{ vault_health_check_username }}" -H "password: {{ vault_health_check_password }}" | jq )
if [ "${dependency_status}" = "" ];then
 echo 'No health check response' ;
 exit 1 ; 
fi
state=$(echo ${dependency_status} | jq -r '.status.code')
if [ "${state}" != "UP" ];then
  echo $dependency_status | jq '.' ;
  exit 2 ; 
else
  [ $1 ] && echo $dependency_status | jq '.' ;
fi
#
{% endfor %}
{% else %}
echo "no check"
{% endif %}
exit 0
