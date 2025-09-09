import json
import boto3
import os

ecs = boto3.client('ecs')
autoscaling = boto3.client('autoscaling')

def lambda_handler(event, context):
    cluster = os.environ['ECS_CLUSTER']
    service = os.environ['ECS_SERVICE']
    asg_name = os.environ['ASG_NAME']
    
    action = event['action']
    
    if action == 'scale_up':
        desired_count = event['desired_count']
        
        # Scale up Auto Scaling Group
        autoscaling.update_auto_scaling_group(
            AutoScalingGroupName=asg_name,
            DesiredCapacity=desired_count
        )
        
        # Scale up ECS Service
        ecs.update_service(
            cluster=cluster,
            service=service,
            desiredCount=desired_count
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Scaled up to {desired_count} instances/tasks')
        }
    
    elif action == 'scale_down':
        # Scale down ECS Service to 0
        ecs.update_service(
            cluster=cluster,
            service=service,
            desiredCount=0
        )
        
        # Scale down Auto Scaling Group to 0
        autoscaling.update_auto_scaling_group(
            AutoScalingGroupName=asg_name,
            DesiredCapacity=0
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps('Scaled down to 0 instances/tasks')
        }
    
    else:
        return {
            'statusCode': 400,
            'body': json.dumps('Invalid action')
        }
