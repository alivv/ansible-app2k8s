#!/usr/bin/env bash

# make adapter-serving-certs for prometheus-adapter

# Detect if we are on mac or should use GNU base64 options
case `uname` in
        Darwin)
            b64_opts='-b=0'
            ;; 
        *)
            b64_opts='--wrap=0'
esac

which cfssl || { wget -O /usr/local/bin/cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 && chmod +x /usr/local/bin/cfssl ;exit ; }

cd /tmp

export PURPOSE=metrics
openssl req -x509 -sha256 -new -nodes -days 36500 -newkey rsa:2048 -keyout ${PURPOSE}-ca.key -out ${PURPOSE}-ca.crt -subj "/CN=ca"
echo '{"signing":{"default":{"expiry":"87600h","usages":["signing","key encipherment","'${PURPOSE}'"]}}}' > "${PURPOSE}-ca-config.json"

export SERVICE_NAME=custom-metrics-apiserver
export ALT_NAMES='"custom-metrics-apiserver.custom-metrics","custom-metrics-apiserver.custom-metrics.svc"'
echo '{"CN":"'${SERVICE_NAME}'","hosts":['${ALT_NAMES}'],"key":{"algo":"rsa","size":2048}}' | cfssl gencert -ca=metrics-ca.crt -ca-key=metrics-ca.key -config=metrics-ca-config.json - | cfssljson -bare apiserver

cat <<-EOF > cm-adapter-serving-certs.yaml
apiVersion: v1
kind: Secret
metadata:
  name: cm-adapter-serving-certs
  namespace: custom-metrics
data:
  serving.crt: $(cat apiserver.pem | base64 ${b64_opts})
  serving.key: $(cat apiserver-key.pem | base64 ${b64_opts})
EOF

echo 
echo 
openssl x509 -in apiserver.pem -noout -text |grep Not
echo 

cat cm-adapter-serving-certs.yaml

#https://github.com/prometheus-operator/kube-prometheus/blob/62fff622e9900fade8aecbd02bc9c557b736ef85/experimental/custom-metrics-api/gencerts.sh
