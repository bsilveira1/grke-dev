#!/bin/bash

# Lista de tópicos a serem criados
TOPICS=(
  "topic1"
  "topic2"
  "topic3"
)

PARTITIONS=3
REPLICATION_FACTOR=1

sleep 10

for TOPIC in "${TOPICS[@]}"; do
  /opt/bitnami/kafka/bin/kafka-topics.sh --create \
    --bootstrap-server kafka:9092 \
    --replication-factor $REPLICATION_FACTOR \
    --partitions $PARTITIONS \
    --topic $TOPIC

  echo "Tópico $TOPIC criado com sucesso!"
done
