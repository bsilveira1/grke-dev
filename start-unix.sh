#!/bin/bash

function show_help() {
  echo "Uso: $0 [-b URL_BACKEND] [-f URL_FRONTEND] [-K]"
  echo
  echo "  -b URL_BACKEND    Informe a URL do repositório do backend em Go."
  echo "  -f URL_FRONTEND   Informe a URL do repositório do frontend em React."
  echo "  -K                Inclui serviços relacionados ao Kafka no docker-compose."
  echo
  echo "Você deve informar pelo menos um dos parâmetros (-b ou -f)."
  exit 1
}

backend_repo=""
frontend_repo=""
include_kafka=false

while getopts "b:f:Kh" opt; do
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

if [[ -n "$backend_repo" && -n "$frontend_repo" ]]; then
  echo "Clonando ambos os repositórios em 'project'..."
  mkdir -p project/backend project/frontend
  git clone "$backend_repo" project/backend
  git clone "$frontend_repo" project/frontend

  if [[ "$include_kafka" == true && -d "scripts" ]]; then
    echo "Movendo o diretório 'scripts' para dentro de 'project'..."
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

echo "Criando arquivo docker-compose.yml..."

sleep 3

cat > "$directory/docker-compose.yml" <<EOF
services:
EOF

if [[ -n "$backend_repo" ]]; then
  depends_on_kafka=$( [[ "$include_kafka" == true ]] && echo "      - kafka" || echo "" )
  cat >> "$directory/docker-compose.yml" <<EOF
  golang-app:
    build:
      context: $( [[ "$directory" == "project" ]] && echo "./backend" || echo "." )
    container_name: golang-app
    command: ["sh", "-c", "echo 'Esperando o banco de dados estar pronto...' && sleep 10 && go run db/seed.go && go run main.go"]
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

echo "Arquivo docker-compose.yml criado com sucesso em $directory!"

echo "Iniciando containers com docker compose..."
cd "$directory" || exit

docker compose up -d --build && docker compose logs -f
