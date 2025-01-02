function Show-Help {
    Write-Host "Uso: $($MyInvocation.MyCommand.Name) [-b URL_BACKEND] [-f URL_FRONTEND] [-K] [-E]"
    Write-Host
    Write-Host "  -b URL_BACKEND    Informe a URL do repositório do backend em Go."
    Write-Host "  -f URL_FRONTEND   Informe a URL do repositório do frontend em React."
    Write-Host "  -K                Inclui serviços relacionados ao Kafka no docker-compose."
    Write-Host "  -E                Inclui a stack do Elasticsearch, Kibana e Filebeat no docker-compose."
    Write-Host
    Write-Host "Você deve informar pelo menos um dos parâmetros (-b ou -f)."
    exit 1
}

function Ensure-Permissions {
    if (Test-Path -Path "scripts" -PathType Container) {
        Write-Host "Configurando permissões para os arquivos no diretório 'scripts'..."
        icacls "scripts" /grant:r "$($env:USERNAME):(OI)(CI)F" /T
        Write-Host "Permissões configuradas com sucesso."
    } else {
        Write-Host "Aviso: O diretório 'scripts' não foi encontrado. Certifique-se de que ele está no local correto."
    }
}

$backend_repo = ""
$frontend_repo = ""
$include_kafka = $false
$include_elastic = $false

param (
    [string]$b,
    [string]$f,
    [switch]$K,
    [switch]$E
)

if ($b) { $backend_repo = $b }
if ($f) { $frontend_repo = $f }
if ($K) { $include_kafka = $true }
if ($E) { $include_elastic = $true }

if (-not ($backend_repo -or $frontend_repo)) {
    Write-Host "Erro: Informe pelo menos um dos parâmetros (-b ou -f)." -ForegroundColor Red
    Show-Help
}

Ensure-Permissions

if ($backend_repo -and $frontend_repo) {
    Write-Host "Clonando ambos os repositórios em 'project'..."
    New-Item -Path "project" -ItemType Directory -Force
    New-Item -Path "project/backend" -ItemType Directory -Force
    New-Item -Path "project/frontend" -ItemType Directory -Force
    git clone $backend_repo project/backend
    git clone $frontend_repo project/frontend
    $directory = "project"
} elseif ($backend_repo) {
    Write-Host "Clonando o repositório backend em 'backend'..."
    git clone $backend_repo backend
    $directory = "backend"
} elseif ($frontend_repo) {
    Write-Host "Clonando o repositório frontend em 'frontend'..."
    git clone $frontend_repo frontend
    $directory = "frontend"
}

if ($include_elastic) {
    $filebeat_source_path = "./scripts/filebeat.yml"
    $filebeat_target_path = "$directory/scripts/filebeat.yml"
    if (Test-Path $filebeat_source_path) {
        Write-Host "Filebeat.yml encontrado, referenciando diretamente em $filebeat_target_path."
    } else {
        Write-Host "Erro: O arquivo 'filebeat.yml' não foi encontrado em './scripts'." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Criando arquivo docker-compose.yml..."
Start-Sleep -Seconds 3

$dockerComposeContent = @"
services:
EOF
"

$depends_on_elasticsearch = ""
if ($backend_repo -and $frontend_repo) {
    $depends_on_elasticsearch = @"
      - golang-app
      - react-app
EOF
} elseif ($backend_repo) {
    $depends_on_elasticsearch = @"
      - golang-app
EOF
} elseif ($frontend_repo) {
    $depends_on_elasticsearch = @"
      - react-app
EOF
}

if ($backend_repo) {
    $depends_on_kafka = if ($include_kafka) { "      - kafka" } else { "" }
    $dockerComposeContent += @"
  golang-app:
    build:
      context: $(if ($directory -eq "project") { "./backend" } else { "." })
    container_name: golang-app
    command: ["sh", "-c", "echo 'Esperando o banco de dados estar pronto...' && sleep 20 && go run db/seed.go && go run main.go"]
    ports:
      - "8080:8080"
    volumes:
      - $(if ($directory -eq "project") { "./backend" } else { "." }):/app
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
      - $(if ($directory -eq "project") { "./backend/db/scripts/mysql-init.sql" } else { "./db/scripts/mysql-init.sql" }):/docker-entrypoint-initdb.d/init.sql
EOF
}

if ($frontend_repo) {
    $dockerComposeContent += @"
  react-app:
    build:
      context: $(if ($directory -eq "project") { "./frontend" } else { "." })
    container_name: react-app
    ports:
      - "3000:3000"
    volumes:
      - $(if ($directory -eq "project") { "./frontend" } else { "." }):/app
      - $(if ($directory -eq "project") { "./frontend/node_modules" } else { "./node_modules" }):/app/node_modules
    environment:
      - CHOKIDAR_USEPOLLING=true
    command: sh -c "npm install && npm start"
    stdin_open: true
    tty: true
EOF
}

if ($include_kafka) {
    $scripts_volume = "../scripts:/scripts"

    $dockerComposeContent += @"
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
}

if ($include_elastic) {
    $dockerComposeContent += @"
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
      - ../scripts/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
      - "/var/lib/docker/containers:/var/lib/docker/containers:ro"
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
    depends_on:
      elasticsearch:
        condition: service_healthy
EOF
}

# Escrevendo o arquivo docker-compose.yml
Set-Content -Path "$directory/docker-compose.yml" -Value $dockerComposeContent

Write-Host "Arquivo docker-compose.yml criado com sucesso em $directory!"

Write-Host "Iniciando containers com docker compose..."
Set-Location -Path $directory
docker-compose up -d --build
docker-compose logs -f
