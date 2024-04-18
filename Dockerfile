FROM ubuntu

WORKDIR /

RUN apt-get update -y
RUN apt-get install mysql-client python3 python3-boto3 -y

COPY ./db_reloader.sh .
COPY ./sns_message.py .
