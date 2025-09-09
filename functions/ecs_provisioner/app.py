import json
import os
import boto3
import time

def lambda_handler(event, context):
    max_workers = int(os.environ.get('MAX_WORKERS', '3'))
    cluster = os.environ.get('ECS_CLUSTER', '')
    task_definition = os.environ.get('TASK_DEFINITION', '')
    asg_name = os.environ.get('ASG_NAME', '')
    compute_type = os.environ.get('COMPUTE_TYPE', 'EC2')
    
    ecs = boto3.client('ecs')
    autoscaling = boto3.client('autoscaling')
    action = event.get('action', 'test')
    
    if action == 'provision':
        worker_count = int(event.get('worker_count', max_workers))
        
        if compute_type == 'EC2':
            # Scale up Auto Scaling Group first
            print(f"Scaling ASG {asg_name} to {worker_count} instances")
            autoscaling.update_auto_scaling_group(
                AutoScalingGroupName=asg_name,
                DesiredCapacity=worker_count
            )
            
            # Wait for instances to register with ECS
            print("Waiting for EC2 instances to register with ECS...")
            for i in range(12):  # Wait up to 2 minutes
                cluster_info = ecs.describe_clusters(clusters=[cluster], include=['STATISTICS'])
                registered_instances = cluster_info['clusters'][0]['registeredContainerInstancesCount']
                print(f"Registered instances: {registered_instances}/{worker_count}")
                
                if registered_instances >= worker_count:
                    break
                time.sleep(10)
            
            # Launch ECS tasks
            launched_tasks = []
            for i in range(worker_count):
                try:
                    response = ecs.run_task(
                        cluster=cluster,
                        taskDefinition=task_definition,
                        launchType='EC2',
                        placementConstraints=[
                            {
                                'type': 'distinctInstance'
                            }
                        ]
                    )
                    if response['tasks']:
                        launched_tasks.append(response['tasks'][0]['taskArn'])
                        print(f"Launched EC2 task {i+1}: {response['tasks'][0]['taskArn']}")
                except Exception as e:
                    print(f"Error launching task {i}: {e}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Provisioned {len(launched_tasks)} EC2 workers',
                'cluster': cluster,
                'tasks': launched_tasks,
                'action': action,
                'compute_type': compute_type
            })
        }
    
    elif action == 'deprovision':
        # Stop all running tasks
        tasks_response = ecs.list_tasks(cluster=cluster)
        task_arns = tasks_response.get('taskArns', [])
        
        stopped_tasks = []
        for task_arn in task_arns:
            try:
                ecs.stop_task(
                    cluster=cluster,
                    task=task_arn,
                    reason='Batch processing completed'
                )
                stopped_tasks.append(task_arn)
                print(f"Stopped task: {task_arn}")
            except Exception as e:
                print(f"Error stopping task {task_arn}: {e}")
        
        # Scale down Auto Scaling Group
        if compute_type == 'EC2' and asg_name:
            print(f"Scaling down ASG {asg_name} to 0")
            autoscaling.update_auto_scaling_group(
                AutoScalingGroupName=asg_name,
                DesiredCapacity=0
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Deprovisioned {len(stopped_tasks)} workers and scaled down ASG',
                'cluster': cluster,
                'stopped_tasks': stopped_tasks,
                'action': action,
                'compute_type': compute_type
            })
        }
    
    else:
        # Test mode
        try:
            cluster_info = ecs.describe_clusters(clusters=[cluster], include=['STATISTICS'])
            cluster_status = cluster_info['clusters'][0]['status'] if cluster_info['clusters'] else 'NOT_FOUND'
            registered_instances = cluster_info['clusters'][0]['registeredContainerInstancesCount']
            
            # Check running tasks
            tasks_response = ecs.list_tasks(cluster=cluster)
            running_tasks = len(tasks_response.get('taskArns', []))
            
            # Check ASG status
            asg_info = autoscaling.describe_auto_scaling_groups(AutoScalingGroupNames=[asg_name])
            asg_desired = asg_info['AutoScalingGroups'][0]['DesiredCapacity'] if asg_info['AutoScalingGroups'] else 0
            
        except Exception as e:
            cluster_status = f'ERROR: {str(e)}'
            registered_instances = 0
            running_tasks = 0
            asg_desired = 0
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'ECS Provisioner function working (EC2)',
                'max_workers': max_workers,
                'cluster': cluster,
                'cluster_status': cluster_status,
                'registered_instances': registered_instances,
                'running_tasks': running_tasks,
                'asg_desired_capacity': asg_desired,
                'task_definition': task_definition,
                'compute_type': compute_type,
                'event': event
            })
        }
