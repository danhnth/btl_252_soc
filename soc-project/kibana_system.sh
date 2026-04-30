echo "=== SOC Stack Setup ==="

docker exec soc-elasticsearch curl -sk -X POST \
  -u "elastic:changeme123" \
  "https://localhost:9200/_security/user/kibana_system/_password" \
  -H "Content-Type: application/json" \
  -d '{"password":"changeme123"}'


echo "=== Checking .security-7 Shard Status ==="

docker exec soc-elasticsearch curl -sk -u elastic:changeme123 \
  "https://localhost:9200/_cat/shards/.security-7?v&h=index,shard,prirep,state,unassigned.reason"
