echo "Now starting a new dinghy-http-proxy container..."
docker run -d --restart=always \
  -v /var/run/docker.sock:/tmp/docker.sock:ro \
  -v ~/.dinghy/certs:/etc/nginx/certs \
  -p 80:80 -p 443:443 -p 19322:19322/udp \
  -e DNS_IP=127.0.0.1 -e CONTAINER_NAME=http-proxy -e DOMAIN_TLD=loc \
  --name http-proxy \
  codekitchen/dinghy-http-proxy
