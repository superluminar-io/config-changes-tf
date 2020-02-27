import json
import boto3
import os
import logging

sns_client = boto3.client('sns')
sns_topic_arn = os.environ['SNS_TOPIC_ARN']
logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    if 'detail' not in event:
        logger.info('cant understand event {}'.format(event))
        return False

    detail = event['detail']
    if 'newEvaluationResult' not in detail:
        logger.info('cant understand event: {}'.format(json.dumps(detail)))
        return False

    new_evaluation_result = detail['newEvaluationResult']
    if 'complianceType' not in new_evaluation_result or new_evaluation_result['complianceType'] != 'NON_COMPLIANT':
        logger.info('do not care for this event: {}'.format(json.dumps(detail)))
        return False

    sns_client.publish(
        TopicArn=sns_topic_arn,
        Message=json.dumps(detail),
    )
    logger.info('published to sns topic')
