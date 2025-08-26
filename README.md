# S3 Batch Processing PoC - Step Functions Distributed Map + ECS

This PoC demonstrates how to process 15,000 S3 objects in parallel using AWS Step Functions Distributed Map with ECS Fargate, reducing processing time from 20 hours to 15-75 minutes.

## Architecture

```
S3 Bucket (150 objects for PoC) 
    ↓
Step Functions Distributed Map
    ↓ (batches objects)
Step Functions Activity (internal queue)
    ↓ (workers poll via get_activity_task())
ECS Worker Pool (2 persistent tasks)
    ↓
Process multiple objects per worker → CloudWatch Logs
```

## Key Benefits

- **Persistent Workers**: 2 ECS tasks stay alive and process multiple objects
- **Activity-based Queuing**: Step Functions Activity handles job dispatching
- **Cost Effective**: No task startup overhead, workers reuse containers
- **Built-in Error Handling**: Step Functions provides retry logic and task management
- **Scalable Pattern**: Easy to increase worker pool size
- **Regional**: Optimized for ap-east-1 (Hong Kong)

## Quick Start

### Prerequisites

- AWS CLI configured with ap-east-1 region
- Docker installed
- Appropriate AWS permissions for ECS, Step Functions, S3, ECR

### 1. Deploy the PoC

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Deploy all infrastructure and application
./scripts/deploy.sh
```

This will:
- Create ECR repository
- Build and push Docker image
- Deploy ECS cluster and task definition
- Deploy Step Functions state machine
- Create test S3 bucket

### 2. Generate Test Files

```bash
# Generate 150 test files for PoC (default)
./scripts/generate-test-files.sh

# Or specify a different number
./scripts/generate-test-files.sh -n 150
```

This creates files with the format:
- `00001.txt` containing "this is 00001.txt"
- `00002.txt` containing "this is 00002.txt"
- ... up to `00150.txt` containing "this is 00150.txt"

### 3. Test the Deployment

```bash
# Run a test execution
./scripts/test-execution.sh
```

This will:
- Start a Step Functions execution
- Monitor progress in real-time
- Show execution results
- Display processing results from S3
- Show CloudWatch logs

### 4. Clean Up

```bash
# Remove all PoC resources
./scripts/cleanup.sh
```

## Project Structure

```
├── poc-implementation-plan.md     # Implementation overview
├── README.md                      # This file
├── infrastructure/
│   ├── ecs-cluster.yaml          # ECS cluster and task definition
│   └── step-functions.yaml       # Step Functions state machine
├── application/
│   ├── Dockerfile                # Container definition
│   ├── requirements.txt          # Python dependencies
│   └── processor.py              # Simplified processing logic
└── scripts/
    ├── deploy.sh                 # Full deployment script
    ├── generate-test-files.sh    # Generate test files (00001.txt to NNNNN.txt)
    ├── test-execution.sh         # Test execution script
    └── cleanup.sh                # Resource cleanup script
```

## Customization

### Processing Logic

The Activity-based worker in `application/processor.py` does the following:

```python
def run(self):
    # 1. Continuously polls Step Functions Activity for tasks
    # 2. Receives object key from Distributed Map via Activity
    # 3. Downloads and processes the S3 object
    # 4. Logs the object key, content, and worker ID
    # 5. Sends success/failure back to Step Functions
    # 6. Immediately polls for the next task
```

**Key Features:**
- **Persistent Workers**: 2 workers stay alive throughout the entire workflow
- **Activity Polling**: Workers use `get_activity_task()` to receive work
- **Task Feedback**: Workers send results back via `send_task_success/failure()`
- **Load Balancing**: Workers automatically pick up available tasks

### Concurrency Settings

Adjust concurrency in `infrastructure/step-functions.yaml`:

```json
"MaxConcurrency": 1000,  // Increase up to 10,000
"ToleratedFailurePercentage": 5
```

### Resource Allocation

Modify ECS task resources in `infrastructure/ecs-cluster.yaml`:

```yaml
Cpu: 1024      # 1 vCPU
Memory: 2048   # 2 GB RAM
```

## Performance Expectations

| Scenario | Sequential | Activity Workers (2) | Scaled Workers (10) |
|----------|------------|---------------------|-------------------|
| 150 objects | 3.75 minutes | ~2 minutes | ~30 seconds |
| Processing time | 1.5s/object | 1.5s/object | 1.5s/object |
| Workers | 1 | 2 persistent | 10 persistent |
| Objects per worker | 150 | ~75 each | ~15 each |
| Total wall clock | 225 seconds | ~112 seconds | ~22 seconds |

**PoC Benefits:**
- **No task startup overhead**: Workers stay alive
- **Efficient load balancing**: Workers pull tasks as available
- **Easy scaling**: Just increase worker count in Step Functions definition

## Cost Optimization

1. **Use Fargate Spot**: 70% cost savings with spot instances
2. **Right-size tasks**: Match CPU/memory to processing needs
3. **Optimize concurrency**: Balance speed vs cost
4. **Monitor usage**: Use CloudWatch to track resource utilization

## Monitoring

### CloudWatch Metrics
- Step Functions execution metrics
- ECS task metrics
- Custom application metrics

### CloudWatch Logs
- Structured JSON logging from containers
- Step Functions execution logs
- ECS task logs

### Step Functions Console
- Visual workflow execution
- Map Run details
- Error tracking

## Troubleshooting

### Common Issues

1. **Task failures**: Check CloudWatch logs for container errors
2. **Permission errors**: Verify IAM roles and policies
3. **Resource limits**: Check ECS service quotas
4. **Network issues**: Verify VPC and security group configuration

### Debug Commands

```bash
# Check ECS tasks
aws ecs list-tasks --cluster s3-batch-processor-poc --region ap-east-1

# View Step Functions execution
aws stepfunctions describe-execution --execution-arn <ARN> --region ap-east-1

# Check CloudWatch logs
aws logs get-log-events --log-group-name /ecs/s3-batch-processor --log-stream-name <stream> --region ap-east-1
```

## Security Considerations

- IAM roles follow least privilege principle
- ECS tasks run in private subnets (configurable)
- S3 bucket access restricted to specific prefixes
- Container runs as non-root user
- Security groups restrict network access

## Next Steps

1. **Production Readiness**:
   - Add comprehensive error handling
   - Implement dead letter queues
   - Add monitoring and alerting
   - Set up CI/CD pipeline

2. **Optimization**:
   - Fine-tune concurrency settings
   - Optimize container image size
   - Implement result aggregation
   - Add progress tracking

3. **Scaling**:
   - Test with full 15k object dataset
   - Benchmark different instance types
   - Implement auto-scaling policies
   - Add multi-region support

## Support

For issues or questions:
1. Check CloudWatch logs for detailed error information
2. Review AWS service quotas and limits
3. Verify IAM permissions and resource configurations
4. Test with smaller datasets first