#!/bin/bash

function show_help() {
  echo "Uso: $0 [-b URL_BACKEND] [-f URL_FRONTEND]"
  echo
  echo "  -b URL_BACKEND    Informe a URL do repositório do backend em Go."
  echo "  -f URL_FRONTEND   Informe a URL do repositório do frontend em React."
  echo
  echo "Você deve informar pelo menos um dos parâmetros (-b ou -f)."
  exit 1
}

backend_repo=""
frontend_repo=""

while getopts "b:f:h" opt; do
  case ${opt} in
    b)
      backend_repo=$OPTARG
      ;;
    f)
      frontend_repo=$OPTARG
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
  mkdir -p project
  git clone "$backend_repo" project/backend
  git clone "$frontend_repo" project/frontend
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
  cat >> "$directory/docker-compose.yml" <<EOF
  golang-app:
    build:
      context: .
    container_name: golang-app
    command: ["sh", "-c", "go run db/seed.go && go run main.go"]
    ports:
      - "8080:8080"
    volumes:
      - .:/app
    depends_on:
      - mysql
EOF
  cat >> "$directory/docker-compose.yml" <<EOF
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
      - ./db/scripts/mysql-init.sql:/docker-entrypoint-initdb.d/init.sql
EOF
fi

if [[ -n "$frontend_repo" ]]; then
  cat >> "$directory/docker-compose.yml" <<EOF
  react-app:
    build:
      context: .
    container_name: react-app
    ports:
      - "3000:3000"
    volumes:
      - .:/app
      - ./node_modules:/app/node_modules
    environment:
      - CHOKIDAR_USEPOLLING=true
    command: sh -c "npm install && npm start"
    stdin_open: true
    tty: true
EOF
fi

echo "Arquivo docker-compose.yml criado com sucesso em $directory!"

echo "Iniciando containers com docker compose..."
cd "$directory" || exit

docker compose up -d --build && docker compose logs -f
