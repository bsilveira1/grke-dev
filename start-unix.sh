#!/bin/bash

function show_help() {
  echo "Uso: $0 [-b URL_BACKEND] [-f URL_FRONTEND] [-K] [-E]"
  echo
  echo "  -b URL_BACKEND    Informe a URL do repositório do backend em Go."
  echo "  -f URL_FRONTEND   Informe a URL do repositório do frontend em React."
  echo "  -K                Inclui serviços relacionados ao Kafka no docker-compose."
  echo "  -E                Inclui a stack do Elasticsearch, Kibana e Filebeat no docker-compose."
  echo
  echo "Você deve informar pelo menos um dos parâmetros (-b ou -f)."
  exit 1
}

function ensure_permissions() {
  if [[ -d "scripts" ]]; then
    echo "Configurando permissões para os arquivos no diretório 'scripts'..."
    chmod -R u+rwx scripts
    echo "Permissões configuradas com sucesso."
  else
    echo "Aviso: O diretório 'scripts' não foi encontrado. Certifique-se de que ele está no local correto."
  fi
}

backend_repo=""
frontend_repo=""
include_kafka=false
include_elastic=false

while getopts "b:f:KEh" opt; do
  case ${opt} in
    b)
      backend_repo=$OPTARG
      ;;
    f)
      frontend_repo=$OPTARG
      ;;
    K)
      include_kafka=true
      ;;
    E)
      include_elastic=true
      ;;
    h)
      show_help
      ;;
    *)
      show_help
      ;;
  esac
done

if [[ -z "$backend_repo" && -z "$frontend_repo" ]]; then
  echo "Erro: Informe pelo menos um dos parâmetros (-b ou -f)." >&2
  show_help
fi

ensure_permissions

if [[ -n "$backend_repo" && -n "$frontend_repo" ]]; then
  echo "Clonando ambos os repositórios em 'project'..."
  mkdir -p project/backend project/frontend
  git clone "$backend_repo" project/backend
  git clone "$frontend_repo" project/frontend

  if [[ -d "scripts" ]]; then
    echo "Movendo o diretório 'scripts' para dentro de 'project'..."
    mv scripts project/
  fi

  echo "Processo concluído com sucesso!"
  directory="project"
elif [[ -n "$backend_repo" ]]; then
  echo "Clonando o repositório backend em 'backend'..."
  git clone "$backend_repo" backend
  directory="backend"
elif [[ -n "$frontend_repo" ]]; then
  echo "Clonando o repositório frontend em 'frontend'..."
  git clone "$frontend_repo" frontend
  directory="frontend"
fi

if [[ "$include_elastic" == true ]]; then
  filebeat_source_path="./scripts/filebeat.yml"
  filebeat_target_path="$directory/scripts/filebeat.yml"
  if [[ -f "$filebeat_source_path" ]]; then
    mkdir -p "$(dirname "$filebeat_target_path")"
    cp "$filebeat_source_path" "$filebeat_target_path"
    echo "Arquivo filebeat.yml copiado para $filebeat_target_path."
  else
    echo "Erro: O arquivo 'filebeat.yml' não foi encontrado em './scripts'." >&2
    exit 1
  fi
fi

echo "Criando arquivo docker-compose.yml..."
sleep 3

cat > "$directory/docker-compose.yml" <<EOF
services:
EOF

depends_on_elasticsearch=""
if [[ -n "$backend_repo" && -n "$frontend_repo" ]]; then
  depends_on_elasticsearch="      - golang-app
      - react-app"
elif [[ -n "$backend_repo" ]]; then
  depends_on_elasticsearch="      - golang-app"
elif [[ -n "$frontend_repo" ]]; then
  depends_on_elasticsearch="      - react-app"
fi

if [[ -n "$backend_repo" ]]; then
  depends_on_kafka=$( [[ "$include_kafka" == true ]] && echo "      - kafka" || echo "" )
  cat >> "$directory/docker-compose.yml" <<EOF
  golang-app:
    build:
      context: $( [[ "$directory" == "project" ]] && echo "./backend" || echo "." )
    container_name: golang-app
    command: ["sh", "-c", "echo 'Esperando o banco de dados estar pronto...' && sleep 20 && go run db/seed.go && go run main.go"]
    ports:
      - "8080:8080"
    volumes:
      - $( [[ "$directory" == "project" ]] && echo "./backend" || echo "." ):/app
    depends_on:
      - mysql
$depends_on_kafka
  mysql:
    image: mysql:8.1
    container_name: mysql
    ports:
      - "3306:3306"
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: testdb
      MYSQL_USER: testuser
      MYSQL_PASSWORD: testpassword
    volumes:
      - $( [[ "$directory" == "project" ]] && echo "./backend/db/scripts/mysql-init.sql" || echo "./db/scripts/mysql-init.sql" ):/docker-entrypoint-initdb.d/init.sql
EOF
fi

if [[ -n "$frontend_repo" ]]; then
  cat >> "$directory/docker-compose.yml" <<EOF
  react-app:
    build:
      context: $( [[ "$directory" == "project" ]] && echo "./frontend" || echo "." )
    container_name: react-app
    ports:
      - "3000:3000"
    volumes:
      - $( [[ "$directory" == "project" ]] && echo "./frontend" || echo "." ):/app
      - $( [[ "$directory" == "project" ]] && echo "./frontend/node_modules" || echo "./node_modules" ):/app/node_modules
    environment:
      - CHOKIDAR_USEPOLLING=true
    command: sh -c "npm install && npm start"
    stdin_open: true
    tty: true
EOF
fi

if [[ "$include_kafka" == true ]]; then
  scripts_volume="../scripts:/scripts"

  cat >> "$directory/docker-compose.yml" <<EOF
  kafka:
    image: bitnami/kafka:latest
    container_name: kafka
    restart: on-failure
    ports:
      - 9092:9092
    environment:
      - KAFKA_CFG_BROKER_ID=1
      - KAFKA_CFG_LISTENERS=PLAINTEXT://:9092
      - KAFKA_CFG_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092
      - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
      - KAFKA_CFG_NUM_PARTITIONS=3
      - ALLOW_PLAINTEXT_LISTENER=yes
    depends_on:
      - zookeeper

  zookeeper:
    image: bitnami/zookeeper:latest
    container_name: zookeeper
    ports:
      - 2181:2181
    environment:
      - ALLOW_ANONYMOUS_LOGIN=yes

  kafka-ui:
    image: provectuslabs/kafka-ui
    container_name: kafka-ui
    depends_on:
      - kafka
      - zookeeper
    ports:
      - "8081:8080"
    restart: always
    environment:
      - KAFKA_CLUSTERS_0_NAME=teste
      - KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS=kafka:9092
      - KAFKA_CLUSTERS_0_ZOOKEEPER=zookeeper:2181

  kafka-topics-setup:
    image: bitnami/kafka:latest
    container_name: kafka-topics-setup
    depends_on:
      - kafka
    environment:
      - KAFKA_CFG_ZOOKEEPER_CONNECT=zookeeper:2181
      - KAFKA_CFG_BOOTSTRAP_SERVERS=kafka:9092
    entrypoint: ["/bin/bash", "-c", "sleep 10 && /scripts/create-topics.sh"]
    volumes:
      - $scripts_volume
EOF
fi

if [[ "$include_elastic" == true ]]; then
  cat >> "$directory/docker-compose.yml" <<EOF
  elasticsearch:
    image: elasticsearch:8.8.1
    container_name: elasticsearch
    ports: 
      - "9200:9200"
    environment:
      - ELASTIC_PASSWORD=elastic123
      - xpack.security.enabled=false
      - discovery.type=single-node
      - "ES_JAVA_OPTS=-Xmx1g -Xms1g"
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "curl -f elasticsearch:9200"
        ]
      interval: 5s
      timeout: 10s
      retries: 120
    depends_on:
$depends_on_elasticsearch

  kibana:
    image: kibana:8.8.1
    container_name: kibana
    ports:
      - "5601:5601"
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - ELASTICSEARCH_USERNAME=kibana
      - xpack.security.enabled=false
    depends_on:
      elasticsearch:
        condition: service_healthy
  
  filebeat:
    image: elastic/filebeat:8.8.1
    container_name: filebeat
    user: root
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    volumes:
      - $( [[ "$directory" == "project" ]] && echo "./scripts/filebeat.yml" || echo "./scripts/filebeat.yml" ):/usr/share/filebeat/filebeat.yml:ro
      - "/var/lib/docker/containers:/var/lib/docker/containers:ro"
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
    depends_on:
      elasticsearch:
        condition: service_healthy
EOF
fi

echo "Arquivo docker-compose.yml criado com sucesso em $directory!"

echo "Iniciando containers com docker compose..."
cd "$directory" || exit

docker compose up -d --build && docker compose logs -f
