#!/bin/bash -ex

source_dir=/tmp/cloudstack-simulator
destination_dir=/root
cloudstack_dir=$destination_dir/cloudstack

yum update -y
yum install wget -y
# Dependencies
rpm -i http://mirror.metrocast.net/fedora/epel/6/i386/epel-release-6-8.noarch.rpm || true
rpm -i http://packages.erlang-solutions.com/erlang-solutions-1.0-1.noarch.rpm || true
yum update -y
yum install \
  ant \
  ant-devel \
  erlang \
  gcc \
  java-1.6.0-openjdk \
  java-1.6.0-openjdk-devel \
  mkisofs \
  mysql \
  MySQL-python \
  mysql-server \
  nc \
  openssh-clients \
  python \
  python-devel \
  python-pip \
  tomcat6 \
  supervisor \
  git \
  which \
  -y

# RabbitMQ
rpm -i http://www.rabbitmq.com/releases/rabbitmq-server/v3.2.3/rabbitmq-server-3.2.3-1.noarch.rpm
chkconfig rabbitmq-server on
service rabbitmq-server start

# Start Dependency Services
chkconfig mysqld on
service mysqld start

# Maven
cd /usr/local
wget http://www.us.apache.org/dist/maven/maven-3/3.0.5/binaries/apache-maven-3.0.5-bin.tar.gz
tar -zxvf apache-maven-3.0.5-bin.tar.gz
export M2_HOME=/usr/local/apache-maven-3.0.5
export PATH=${M2_HOME}/bin:${PATH}

# CloudStack Build
curl -L https://github.com/dgrizzanti/cloudstack/archive/4.2-tag-patches.tar.gz | tar -xz
mv cloudstack-4.2-tag-patches $cloudstack_dir
cd $cloudstack_dir
wget https://gist.github.com/justincampbell/8599856/raw/AddingRabbitMQtoCloudStackComponentContext.patch
git apply AddingRabbitMQtoCloudStackComponentContext.patch
mvn -Pdeveloper -Dsimulator -DskipTests -Dmaven.install.skip=true install
cp $source_dir/cloudstack-simulator /etc/init.d/

# CloudStack Configuration
mvn -Pdeveloper -pl developer -Ddeploydb
mvn -Pdeveloper -pl developer -Ddeploydb-simulator
/etc/init.d/cloudstack-simulator start
pip install argparse
while ! nc -vz localhost 8096; do sleep 10; done # Wait for CloudStack to start
mvn -Pdeveloper,marvin.sync -Dendpoint=localhost -pl :cloud-marvin
mvn -Pdeveloper,marvin.setup -Dmarvin.config=setup/dev/advanced.cfg -pl :cloud-marvin integration-test || true
/etc/init.d/cloudstack-simulator stop
mysql -uroot cloud -e "update service_offering set ram_size = 32;"
mysql -uroot cloud -e "update vm_template set enable_password = 1 where name like '%CentOS%';"
mysql -uroot cloud -e "insert into hypervisor_capabilities values (100,'100','Simulator','default',50,1,6,NULL,0,1);"
mysql -uroot cloud -e "update user set api_key = 'F0Hrpezpz4D3RBrM6CBWadbhzwQMLESawX-yMzc5BCdmjMon3NtDhrwmJSB1IBl7qOrVIT4H39PTEJoDnN-4vA' where id = 2;"
mysql -uroot cloud -e "update user set secret_key = 'uWpZUVnqQB4MLrS_pjHCRaGQjX62BTk_HU8uiPhEShsY7qGsrKKFBLlkTYpKsg1MzBJ4qWL0yJ7W7beemp-_Ng' where id = 2;"

# Supervisor
cp $source_dir/supervisord.conf /etc/supervisord.conf

# Cleanup
rm -rf ~/*.tar.gz
rm -rf ~/cloudstack/.git
yum clean all
