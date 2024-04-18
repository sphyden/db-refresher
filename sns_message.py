#!/usr/bin/env python3

import boto3
import sys
import json

sns = boto3.client('sns')
topic_arn = "TOPIC_ARN"

def publish_message(message_body):
    message = { "version": 1.0,
                "source": "custom",
                "content": {
                    "textType": "client-markdown",
                    "title": "TEST: :beachball: TEST",
                    "description": message_body
                   }
               }
    response = sns.publish(TopicArn=topic_arn, Message=json.dumps(message))
    return response
def main():
  message_body = sys.argv[1]

  publish_message(message_body)

main()
