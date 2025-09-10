import json
import os
import boto3
import time

def lambda_handler(event, context):
    cluster = os.environ.get('ECS_CLUSTER', '')
    task_definition = os.environ.get('TASK_DEFINITION', '')
    asg_name = os.environ.get('ASG_NAME', '')
    compute_type = os.environ.get('COMPUTE_TYPE', 'EC2')
    
    ecs = boto3.client('ecs')
    autoscaling = boto3.client('autoscaling')
    action = event.get('action', 'test')
    
    if action == 'provision':
        worker_count = int(event.get('worker_count', 3))
        
        if compute_type == 'EC2':
            # Scale up Auto Scaling Group first
            print(f"Scaling ASG {asg_name} to {worker_count} instances")
            autoscaling.update_auto_scaling_group(
                AutoScalingGroupName=asg_name,
                DesiredCapacity=worker_count
            )
            
            # Wait for instances to register with ECS
            print("Waiting for EC2 instances to register with ECS...")
            registered_instances = 0
            for i in range(24):  # Wait up to 4 minutes for instances
                cluster_info = ecs.describe_clusters(clusters=[cluster], include=['STATISTICS'])
                registered_instances = cluster_info['clusters'][0]['registeredContainerInstancesCount']
                print(f"Registered instances: {registered_instances}/{worker_count}")
                
                if registered_instances >= worker_count:
                    break
                time.sleep(10)
            
            if registered_instances < worker_count:
                raise Exception(f"Failed to register {worker_count} instances with ECS. Only {registered_instances} registered after 4 minutes.")
            
            # Launch ECS tasks - one task per instance
            launched_tasks = []
            try:
                response = ecs.run_task(
                    cluster=cluster,
                    taskDefinition=task_definition,
                    launchType='EC2',
                    count=worker_count,
                    placementConstraints=[
                        {
                            'type': 'distinctInstance'
                        }
                    ]
                )
                launched_tasks = [task['taskArn'] for task in response['tasks']]
                print(f"Launched {len(launched_tasks)} EC2 tasks: {launched_tasks}")
            except Exception as e:
                print(f"Error launching tasks: {e}")
                # Fallback: launch tasks one by one
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
            
            if len(launched_tasks) == 0:
                raise Exception(f"Failed to launch any ECS tasks. Expected {worker_count} tasks.")
            
            # CRITICAL: Wait for ALL tasks to be RUNNING
            print(f"Waiting for ALL {len(launched_tasks)} tasks to be RUNNING...")
            running_tasks = []
            for i in range(30):  # Wait up to 5 minutes for tasks to be running
                running_tasks = []
                try:
                    for task_arn in launched_tasks:
                        task_response = ecs.describe_tasks(cluster=cluster, tasks=[task_arn])
                        if task_response['tasks']:
                            task_status = task_response['tasks'][0]['lastStatus']
                            if task_status == 'RUNNING':
                                running_tasks.append(task_arn)
                            elif task_status in ['STOPPED', 'DEACTIVATING']:
                                print(f"Task failed: {task_arn} - Status: {task_status}")
                    
                    print(f"Running tasks: {len(running_tasks)}/{worker_count} (iteration {i+1}/30)")
                    
                    # SUCCESS CONDITION: Exact number of running tasks
                    if len(running_tasks) == worker_count:
                        print(f"SUCCESS: All {worker_count} tasks are RUNNING!")
                        break
                        
                except Exception as e:
                    print(f"Error checking task status: {e}")
                
                time.sleep(10)
            
            # FAIL if we don't have the exact number of running tasks
            if len(running_tasks) != worker_count:
                raise Exception(f"PROVISIONING FAILED: Expected {worker_count} running tasks, but only {len(running_tasks)} are running after 5 minutes. Tasks: {launched_tasks}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully provisioned {len(running_tasks)} running EC2 workers',
                'cluster': cluster,
                'running_tasks': running_tasks,
                'action': action,
                'compute_type': compute_type,
                'worker_count': worker_count,
                'success': True
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
