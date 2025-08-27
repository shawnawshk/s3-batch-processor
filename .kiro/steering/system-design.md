## The Design principals

The Core of this batch processing is the StepFunction, mainly use it to orchestrate the whole workflow.

The workflow logically include 3 phases,
1. provision the ECS infrastructure, mainly the compute (EC2 or Fargate) with ECS tasks based on the input (specify the compute type, instance type (can have default for EC2 type), number of workers, s3 bucket and data path)
2. use distributed map with Activity to dispatch the job, by iterate through the S3 bucket based on the specified object location in S3
3. tear down the ECS infrastructure. Specifically, the step should be also based on the compute type. If it's fargate, then stop the tasks; if it's EC2, should stop tasks and then drain all ec2 nodes


So for the infra setup, can keep existing two stack. One stack for the StepFunction, another is for ECS. The ECS can just provision essential components, including ECS cluster, compute provider for both Fargate and EC2. 
For EC2,if really necessary or have to, then the ASG can be created, just config the instance to 0 at the beginning. Then for the StepFunction workflow running, it should adjust the capacity accordingly. 
If it's have conflict ASG is static and need static instance specified, can consider to consolidate the ASG creation into the phase that the Workflow provision ECS infrastructure.