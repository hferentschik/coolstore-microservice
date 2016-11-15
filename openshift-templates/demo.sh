#! /bin/bash

# Script to seed the microservice demo from https://github.com/hferentschik/coolstore-microservice

# Create docker-machine and configure OpenShift via 'oc cluster up'
docker-machine create -d virtualbox --virtualbox-cpu-count 4 --virtualbox-memory 8192 --engine-insecure-registry 172.30.0.0/16 coolstore
eval $(docker-machine env coolstore)
oc cluster up --metrics=true

# Set environment variables used throughout the script
export OCP_PROJECT=coolstore
export OCP_MASTER=`docker-machine ip coolstore`   # hostname or IP of the OpenShift Container Platform Master
export OCP_DOMAIN="${OCP_MASTER}.xip.io"          # DNS domain that maps to your OpenShift Container Platform master
export MAVEN_MIRROR_URL="http://nexus.ci.${OCP_DOMAIN}/repository/maven-public/"

oc login -u system:admin

# Make sure we have the right templates
oc delete -n openshift -f 'https://raw.githubusercontent.com/jboss-openshift/application-templates/master/jboss-image-streams.json'
oc delete -n openshift -f 'https://raw.githubusercontent.com/openshift/openshift-ansible/master/roles/openshift_examples/files/examples/v1.3/image-streams/image-streams-rhel7.json'
oc create -n openshift -f 'https://raw.githubusercontent.com/jboss-openshift/application-templates/master/jboss-image-streams.json'
oc create -n openshift -f 'https://raw.githubusercontent.com/openshift/openshift-ansible/master/roles/openshift_examples/files/examples/v1.3/image-streams/image-streams-rhel7.json'

# Sort out some permissions and secrets
oc login https://${OCP_MASTER}:8443 -p developer -u developer

# Create a Maven mirror
oc new-project ci
oc new-app --name nexus sonatype/nexus3
oc expose svc nexus
oc deploy nexus --latest -n ci
sleep 60
oc logs -f dc/nexus

# Create the coolstore project
oc new-project ${OCP_PROJECT}
oc create -f secrets/coolstore-secrets.json
oc policy add-role-to-user view system:serviceaccount:$(oc project -q):default -n $(oc project -q)
oc policy add-role-to-user view system:serviceaccount:$(oc project -q):sso-service-account -n $(oc project -q)

# Create API gateway
oc process -f api-gateway.json | oc create -f -
sleep 60
oc logs -f bc/api-gateway

# Create catalog service
oc process -f catalog-service.json | oc create -f -
sleep 60
oc logs -f bc/catalog-service

# Create inventory service
oc process -f inventory-service.json | oc create -f -
sleep 60
oc logs -f bc/inventory-service

# Create cart service
oc process -f cart-service.json | oc create -f -
sleep 60
oc logs -f bc/cart-service

# Create UI
oc process -f ui-service.json \
    HOSTNAME_HTTP=ui-${OCP_PROJECT}.${OCP_DOMAIN} \
    API_ENDPOINT=http://api-gateway-${OCP_PROJECT}.${OCP_DOMAIN}/api | \
    oc create -f -
sleep 60
oc logs -f bc/ui

# Setup Hystrix
oc login -u system:admin
oc adm policy add-scc-to-user anyuid -z ribbon
oc create -f http://central.maven.org/maven2/io/fabric8/kubeflix/packages/kubeflix/1.0.17/kubeflix-1.0.17-kubernetes.yml
oc new-app kubeflix
oc expose service hystrix-dashboard
oc patch route hystrix-dashboard -p '{"spec": { "port": { "targetPort": 8080 } } }'
oc policy add-role-to-user admin system:serviceaccount:$(oc project -q):turbine
oc logs -f rc/hystrix-dashboard

# Create Jenkins and setup pipelines
#oc login https://${OCP_MASTER}:8443 -p developer -u developer
#oc project ci
#oc policy add-role-to-user edit system:serviceaccount:ci:default -n ci
#oc process -f jenkins.json PROD_PROJECT=${OCP_PROJECT} MAVEN_MIRROR_URL=${MAVEN_MIRROR_URL} | oc create -f -
