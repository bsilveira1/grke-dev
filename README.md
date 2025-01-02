# README.md

## Descrição

Este repositório contém uma série de scripts utilizados para facilitar a configuração e o gerenciamento de um ambiente de desenvolvimento com Docker, para a criação de containers para aplicações em Go, React, MySQL, Kafka, Elasticsearch, Kibana e Filebeat. Os scripts permitem automatizar o processo de clonagem de repositórios de backend e frontend, configuração de permissões, criação de tópicos Kafka, e configuração de serviços no Docker Compose.

## Funcionalidades

### 1. `setup.sh` para sistemas Unix ou `setup.ps1` para PowerShell
Este script é responsável por:
- Clonar repositórios de backend e frontend.
- Configurar permissões para os arquivos no diretório `scripts`.
- Criar o arquivo `docker-compose.yml` com os serviços necessários.
- Adicionar serviços como Kafka e Elasticsearch, Kibana e Filebeat, caso sejam solicitados.

### 2. `create-topics.sh`
Este script é responsável por criar tópicos no Kafka:
- Cria tópicos específicos com o número de partições e o fator de replicação definidos no script.
- A lista de tópicos é definida na variável `$TOPICS`.

## Requisitos

Para rodar os scripts, os seguintes requisitos são necessários:

1. **Docker**: O Docker deve estar instalado no sistema para permitir a criação e execução dos containers.
   - Instale o Docker a partir de [aqui](https://www.docker.com/products/docker-desktop).

2. **Docker Compose**: O Docker Compose deve estar instalado para orquestrar os containers.
   - Instale o Docker Compose a partir de [aqui](https://docs.docker.com/compose/install/).

3. **Git**: O Git deve estar instalado para clonar os repositórios de backend e frontend.
   - Instale o Git a partir de [aqui](https://git-scm.com/).

4. **Permissões**: Certifique-se de que os scripts possuem permissões adequadas para execução.
   - No caso de sistemas Unix-like, use o comando `chmod +x setup.sh` para garantir que o script seja executável.

## Como Usar

### 1. Executando o `setup.sh` (ou `setup.ps1`)

Para executar o script de configuração, use o comando apropriado conforme seu sistema operacional:

- **Linux / macOS / WSL (Windows Subsystem for Linux)**:
  
  ```bash
  ./setup.sh -b <URL_BACKEND> -f <URL_FRONTEND> [-K] [-E]

Onde:

- `-b` especifica a URL do repositório do backend (obrigatório).
- `-f` especifica a URL do repositório do frontend (obrigatório).
- `-K` inclui o Kafka nos serviços do Docker Compose.
- `-E` inclui Elasticsearch, Kibana e Filebeat nos serviços do Docker Compose.

- **Windows Powershell**:
  
  ```PowerShell
  .\setup.ps1 -b <URL_BACKEND> -f <URL_FRONTEND> [-K] [-E]

### Contribuições

Sinta-se à vontade para fazer contribuições! Se você encontrar algum erro ou tiver sugestões de melhorias, abra uma issue ou um pull request.


### Licença

Este projeto está licenciado sob a [MIT License](https://opensource.org/license/mit).