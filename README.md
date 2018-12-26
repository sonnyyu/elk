# ELK

Test Elasticsearch:

curl -X GET "localhost:9200"


Test Kibana:

http://10.145.89.96:5601/
http://10.145.89.96:5601/status

Test Logstash:

sudo -u logstash /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t

Test Filebeat:

curl -XGET 'http://localhost:9200/filebeat-*/_search?pretty'

Setup Sample Data:

http://10.145.89.96:5601/app/kibana#/home/tutorial_directory?_g=()



