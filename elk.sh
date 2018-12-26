#!/bin/bash
#

set -x

exec > >(sudo tee install.log)
exec 2>&1

apt-get purge oracle-java8-installer -y

sudo apt-get update -y && sudo apt-get upgrade  -y
sudo add-apt-repository ppa:webupd8team/java  -y
sudo apt-get update -y
echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | debconf-set-selections
echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 seen true" | debconf-set-selections

sudo apt-get install oracle-java8-installer -y

#sudo update-alternatives --config java

echo 'JAVA_HOME="/usr/lib/jvm/java-8-oracle"' >>/etc/environment
source /etc/environment

wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-6.5.4.deb
sudo dpkg -i elasticsearch-6.5.4.deb

sed -i -e 's/#network.host: 192.168.0.1/network.host: localhost/g' /etc/elasticsearch/elasticsearch.yml
sed -i -e 's/#MAX_LOCKED_MEMORY=unlimited/MAX_LOCKED_MEMORY=unlimited/g' /etc/default/elasticsearch

sudo systemctl enable elasticsearch
sudo systemctl start elasticsearch
sudo systemctl status elasticsearch

#curl -X GET "localhost:9200"

wget https://artifacts.elastic.co/downloads/kibana/kibana-6.5.4-amd64.deb
sudo dpkg -i kibana-6.5.4-amd64.deb

sed -i -e 's/#server.host: "localhost"/server.host: "0.0.0.0"/g' /etc/kibana/kibana.yml

sudo systemctl daemon-reload
sudo systemctl enable kibana.service
sudo systemctl start kibana.service
#sudo systemctl status kibana.service
#http://10.145.89.96:5601/
#http://10.145.89.96:5601/status
wget https://artifacts.elastic.co/downloads/logstash/logstash-6.5.4.deb
dpkg -i logstash-6.5.4.deb

cat << EOF > /etc/logstash/conf.d/02-beats-input.conf
input {
  beats {
    port => 5044
  }
}
EOF

cat << EOF > /etc/logstash/conf.d/10-syslog-filter.conf
filter {
  if [fileset][module] == "system" {
    if [fileset][name] == "auth" {
      grok {
        match => { "message" => ["%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} sshd(?:\[%{POSINT:[system][auth][pid]}\])?: %{DATA:[system][auth][ssh][event]} %{DATA:[system][auth][ssh][method]} for (invalid user )?%{DATA:[system][auth][user]} from %{IPORHOST:[system][auth][ssh][ip]} port %{NUMBER:[system][auth][ssh][port]} ssh2(: %{GREEDYDATA:[system][auth][ssh][signature]})?",
                  "%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} sshd(?:\[%{POSINT:[system][auth][pid]}\])?: %{DATA:[system][auth][ssh][event]} user %{DATA:[system][auth][user]} from %{IPORHOST:[system][auth][ssh][ip]}",
                  "%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} sshd(?:\[%{POSINT:[system][auth][pid]}\])?: Did not receive identification string from %{IPORHOST:[system][auth][ssh][dropped_ip]}",
                  "%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} sudo(?:\[%{POSINT:[system][auth][pid]}\])?: \s*%{DATA:[system][auth][user]} :( %{DATA:[system][auth][sudo][error]} ;)? TTY=%{DATA:[system][auth][sudo][tty]} ; PWD=%{DATA:[system][auth][sudo][pwd]} ; USER=%{DATA:[system][auth][sudo][user]} ; COMMAND=%{GREEDYDATA:[system][auth][sudo][command]}",
                  "%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} groupadd(?:\[%{POSINT:[system][auth][pid]}\])?: new group: name=%{DATA:system.auth.groupadd.name}, GID=%{NUMBER:system.auth.groupadd.gid}",
                  "%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} useradd(?:\[%{POSINT:[system][auth][pid]}\])?: new user: name=%{DATA:[system][auth][user][add][name]}, UID=%{NUMBER:[system][auth][user][add][uid]}, GID=%{NUMBER:[system][auth][user][add][gid]}, home=%{DATA:[system][auth][user][add][home]}, shell=%{DATA:[system][auth][user][add][shell]}$",
                  "%{SYSLOGTIMESTAMP:[system][auth][timestamp]} %{SYSLOGHOST:[system][auth][hostname]} %{DATA:[system][auth][program]}(?:\[%{POSINT:[system][auth][pid]}\])?: %{GREEDYMULTILINE:[system][auth][message]}"] }
        pattern_definitions => {
          "GREEDYMULTILINE"=> "(.|\n)*"
        }
        remove_field => "message"
      }
      date {
        match => [ "[system][auth][timestamp]", "MMM  d HH:mm:ss", "MMM dd HH:mm:ss" ]
      }
      geoip {
        source => "[system][auth][ssh][ip]"
        target => "[system][auth][ssh][geoip]"
      }
    }
    else if [fileset][name] == "syslog" {
      grok {
        match => { "message" => ["%{SYSLOGTIMESTAMP:[system][syslog][timestamp]} %{SYSLOGHOST:[system][syslog][hostname]} %{DATA:[system][syslog][program]}(?:\[%{POSINT:[system][syslog][pid]}\])?: %{GREEDYMULTILINE:[system][syslog][message]}"] }
        pattern_definitions => { "GREEDYMULTILINE" => "(.|\n)*" }
        remove_field => "message"
      }
      date {
        match => [ "[system][syslog][timestamp]", "MMM  d HH:mm:ss", "MMM dd HH:mm:ss" ]
      }
    }
  }
}
EOF

cat << EOF > /etc/logstash/conf.d/30-elasticsearch-output.conf
output {
  elasticsearch {
    hosts => ["localhost:9200"]
    manage_template => false
    index => "%{[@metadata][beat]}-%{[@metadata][version]}-%{+YYYY.MM.dd}"
  }
}
EOF

sudo -u logstash /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t

sudo systemctl enable logstash
sudo systemctl start logstash
sudo systemctl status logstash

wget https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-6.5.4-amd64.deb
dpkg -i filebeat-6.5.4-amd64.deb

#nano /etc/filebeat/filebeat.yml

sed -e '/hosts\:\s\[\"localhost\:9200\"\]/s/^#*/  #/' -i /etc/filebeat/filebeat.yml
sed -e '/output\.elasticsearch\:/s/^#*/#/' -i /etc/filebeat/filebeat.yml
sed -e '/#output.logstash:/s/^#//' -i /etc/filebeat/filebeat.yml
sed -e '/#hosts\:\s\[\"localhost\:5044\"\]/s/^\s*#/  /' -i /etc/filebeat/filebeat.yml

sudo filebeat modules enable system

sudo filebeat modules list

sudo filebeat setup --template -E output.logstash.enabled=false -E 'output.elasticsearch.hosts=["localhost:9200"]'
sudo filebeat setup -e -E output.logstash.enabled=false -E output.elasticsearch.hosts=['localhost:9200'] -E setup.kibana.host=localhost:5601

sudo systemctl enable filebeat
sudo systemctl start filebeat
sudo systemctl status filebeat

#curl -XGET 'http://localhost:9200/filebeat-*/_search?pretty'

#http://10.145.89.96:5601/app/kibana#/home/tutorial_directory?_g=()


